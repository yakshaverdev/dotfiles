#!/usr/bin/env bash
# Test the account failover, the Claude Code callbacks and the PATH shim in
# bin/claude-ctx. A fake claude on PATH prints the account and token it gets.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX="$ROOT/bin/claude-ctx"
export CTX

TMPROOT="$(mktemp -d)"
TEST_PIDS=""
cleanup() {
  for p in $TEST_PIDS; do
    kill -TERM "$p" 2>/dev/null || true
  done
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

# jq is often a mise shim that needs the real HOME. Wrap it so the temporary
# HOME does not break it.
REAL_HOME="$HOME"
JQ_BIN="$(command -v jq || true)"

export HOME="$TMPROOT/home"
FAKEBIN="$TMPROOT/bin"
SECRETS="$HOME/.config/dot/claude-tokens.env"
STATE="$HOME/.local/state/claude-accounts"
LOG="$STATE/failover.log"
mkdir -p "$HOME/.config/dot" "$FAKEBIN"

cat > "$FAKEBIN/claude" <<'FAKE'
#!/usr/bin/env bash
printf 'CLAUDE_ACCOUNT=%s TOKEN=%s LEAK=%s\n' \
  "${CLAUDE_ACCOUNT:-}" "${CLAUDE_CODE_OAUTH_TOKEN:-}" "${CLAUDE_TOKEN_ULTRA:-}"
FAKE
chmod +x "$FAKEBIN/claude"
if [ -n "$JQ_BIN" ]; then
  {
    printf '#!/usr/bin/env bash\n'
    printf 'HOME=%q exec %q "$@"\n' "$REAL_HOME" "$JQ_BIN"
  } > "$FAKEBIN/jq"
  chmod +x "$FAKEBIN/jq"
fi
export PATH="$FAKEBIN:$PATH"

run_ctx() { bash "$CTX" "$@"; }

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

eq() { # label expected actual
  if [ "$2" != "$3" ]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    exit 1
  fi
}

alive() { # pid -> true while the process runs (a zombie counts as gone)
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in
    Z*) return 1 ;;
  esac
  return 0
}

wait_gone() { # pid seconds
  local deadline=$(( $(date +%s) + $2 ))
  while alive "$1"; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 0.1
  done
  return 0
}

reset() {
  unset CLAUDE_ACCOUNT CLAUDE_CODE_OAUTH_TOKEN CLAUDE_TOKEN_ULTRA CLAUDE_TOKEN_TEAM
  unset CLAUDE_CTX_PID CLAUDE_CTX_WRAPPER_PID CLAUDE_CTX_FORCE_WRAP CLAUDE_CTX_BIN
  unset DOTS_SHIM_DIR
  # This test may itself run inside T3 Code; never inherit its thread id.
  unset T3CODE_THREAD_ID
  rm -rf "$STATE" "$SECRETS"
  mkdir -p "$HOME/.config/dot"
}

write_secrets() {
  printf 'CLAUDE_TOKEN_ULTRA=tok-ultra\nCLAUDE_TOKEN_TEAM=tok-team\n' > "$SECRETS"
  chmod 600 "$SECRETS"
}

now=$(date +%s)

# 1. No tokens: no account, no token, plain login.
reset
eq "no tokens" "CLAUDE_ACCOUNT= TOKEN= LEAK=" "$(run_ctx)"

# 2. Both tokens in claude-tokens.env: the primary (team) wins and tokens do not leak.
reset
write_secrets
eq "claude-tokens.env -> team" "CLAUDE_ACCOUNT=team TOKEN=tok-team LEAK=" "$(run_ctx)"

# 3. Primary limited in the future: fail over to the fallback (ultra).
reset
write_secrets
mkdir -p "$STATE"
printf '%s\n' "$((now + 3600))" > "$STATE/team.limited"
eq "team limited -> ultra" "CLAUDE_ACCOUNT=ultra TOKEN=tok-ultra LEAK=" "$(run_ctx)"

# 4. Expired limit: the primary comes back.
reset
write_secrets
mkdir -p "$STATE"
printf '%s\n' "$((now - 60))" > "$STATE/team.limited"
eq "expired limit -> team" "CLAUDE_ACCOUNT=team TOKEN=tok-team LEAK=" "$(run_ctx)"

# 5. Primary rate limit at 100% with a future reset: fail over to ultra.
reset
write_secrets
mkdir -p "$STATE"
printf '{"five_hour":{"used_percentage":100,"resets_at":%s},"seven_day":{"used_percentage":10,"resets_at":%s}}\n' \
  "$((now + 3600))" "$((now + 7200))" > "$STATE/team.rate.json"
eq "team five_hour 100% -> ultra" "CLAUDE_ACCOUNT=ultra TOKEN=tok-ultra LEAK=" "$(run_ctx)"

# 6. Both limited: pick the account that resets first.
reset
write_secrets
mkdir -p "$STATE"
printf '%s\n' "$((now + 9000))" > "$STATE/team.limited"
printf '%s\n' "$((now + 3000))" > "$STATE/ultra.limited"
eq "both limited -> ultra first" "CLAUDE_ACCOUNT=ultra TOKEN=tok-ultra LEAK=" "$(run_ctx)"

# 7. A caller-set token is respected.
reset
write_secrets
export CLAUDE_CODE_OAUTH_TOKEN=caller-token
eq "caller token kept" "CLAUDE_ACCOUNT= TOKEN=caller-token LEAK=" "$(run_ctx)"
unset CLAUDE_CODE_OAUTH_TOKEN

# 8. __limit without rate.json records now + 1800.
reset
export CLAUDE_ACCOUNT=ultra
printf '{"hook_event_name":"StopFailure"}\n' | run_ctx __limit
unset CLAUDE_ACCOUNT
[ -r "$STATE/ultra.limited" ] || fail "__limit wrote no ultra.limited"
limit_end=$(cat "$STATE/ultra.limited")
if [ "$limit_end" -lt "$((now + 1780))" ] || [ "$limit_end" -gt "$((now + 1820))" ]; then
  fail "__limit wrote $limit_end, expected about $((now + 1800))"
fi

# 8b. __limit uses the window at 100%, else the earliest reset (not the weekly one).
reset
export CLAUDE_ACCOUNT=team
mkdir -p "$STATE"
printf '{"five_hour":{"used_percentage":100,"resets_at":%s},"seven_day":{"used_percentage":40,"resets_at":%s}}\n' "$((now + 300))" "$((now + 86400))" > "$STATE/team.rate.json"
run_ctx __limit </dev/null >/dev/null
eq "__limit 5h at 100%" "$((now + 300))" "$(cat "$STATE/team.limited")"
printf '{"five_hour":{"used_percentage":1,"resets_at":%s},"seven_day":{"used_percentage":0,"resets_at":%s}}\n' "$((now + 300))" "$((now + 86400))" > "$STATE/team.rate.json"
run_ctx __limit </dev/null >/dev/null
eq "__limit none at 100% -> earliest" "$((now + 300))" "$(cat "$STATE/team.limited")"
printf '{"five_hour":{"used_percentage":20,"resets_at":%s},"seven_day":{"used_percentage":100,"resets_at":%s}}\n' "$((now + 300))" "$((now + 86400))" > "$STATE/team.rate.json"
run_ctx __limit </dev/null >/dev/null
eq "__limit 7d at 100%" "$((now + 86400))" "$(cat "$STATE/team.limited")"
unset CLAUDE_ACCOUNT

# 9. __statusline stores rate_limits and prints one line.
reset
export CLAUDE_ACCOUNT=ultra
line=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":42.4,"resets_at":1},"seven_day":{"used_percentage":13,"resets_at":2}}}' | run_ctx __statusline)
unset CLAUDE_ACCOUNT
eq "__statusline output" "ultra · 5h 42% · 7d 13%" "$line"
[ -r "$STATE/ultra.rate.json" ] || fail "__statusline wrote no ultra.rate.json"
jq -e '.five_hour.used_percentage == 42.4 and .seven_day.used_percentage == 13' \
  "$STATE/ultra.rate.json" >/dev/null 2>&1 ||
  fail "__statusline stored the wrong rate_limits"

# 10. The debug log records the pick and never a token value.
reset
write_secrets
run_ctx >/dev/null
[ -r "$LOG" ] || fail "no failover.log"
grep -q 'pick=' "$LOG" || fail "log has no pick= line"
if grep -qE 'tok-(ultra|team)' "$LOG"; then
  fail "log contains a token value"
fi

if [ "$(uname -s)" != "Linux" ]; then
  printf 'skip: process, wrapper and shim tests need Linux (11-16)\n'
else
  # 11. T3 exec mode: __limit ends the claude PID it exported.
  reset
  write_secrets
  PROCDIR="$TMPROOT/proc-t3"
  mkdir -p "$PROCDIR"
  cat > "$PROCDIR/claude" <<'PROC'
#!/usr/bin/env bash
"$CTX" __limit <<<'{}'
exec sleep 30
PROC
  chmod +x "$PROCDIR/claude"
  T3CODE_THREAD_ID=test PATH="$PROCDIR:$PATH" bash "$CTX" </dev/null >/dev/null 2>&1 &
  pid=$!
  TEST_PIDS="$TEST_PIDS $pid"
  wait_gone "$pid" 4 || fail "__limit did not end claude under T3 Code"
  wait "$pid" 2>/dev/null || true
  [ -r "$STATE/team.limited" ] || fail "__limit wrote no team.limited"
  grep -q 'kill pid=' "$LOG" || fail "log has no kill decision"

  # 12. Exec mode outside T3 and without a wrapper: nothing is killed.
  reset
  write_secrets
  PROCDIR="$TMPROOT/proc-plain"
  mkdir -p "$PROCDIR"
  cat > "$PROCDIR/claude" <<'PROC'
#!/usr/bin/env bash
"$CTX" __limit <<<'{}'
exec sleep 30
PROC
  chmod +x "$PROCDIR/claude"
  PATH="$PROCDIR:$PATH" bash "$CTX" </dev/null >/dev/null 2>&1 &
  pid=$!
  TEST_PIDS="$TEST_PIDS $pid"
  sleep 2
  alive "$pid" || fail "__limit killed claude outside T3 Code and the wrapper"
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ -r "$STATE/team.limited" ] || fail "__limit wrote no team.limited (plain)"
  grep -q 'no kill: not t3/terminal' "$LOG" || fail "log has no no-kill reason"

  # 13. Wrapper mode relaunches on the other account with --resume.
  reset
  write_secrets
  export COUNTER="$TMPROOT/counter" ACCOUNT_OUT="$TMPROOT/account" ARGS_OUT="$TMPROOT/args"
  PROCDIR="$TMPROOT/proc-wrap"
  mkdir -p "$PROCDIR"
  cat > "$PROCDIR/claude" <<'PROC'
#!/usr/bin/env bash
n=0
[ -f "$COUNTER" ] && n=$(cat "$COUNTER")
n=$((n + 1))
printf '%s' "$n" > "$COUNTER"
if [ "$n" -eq 1 ]; then
  "$CTX" __limit <<<'{"session_id":"abc"}'
  exec sleep 30
fi
printf '%s\n' "${CLAUDE_ACCOUNT:-}" > "$ACCOUNT_OUT"
printf '%s\n' "$@" > "$ARGS_OUT"
exit 0
PROC
  chmod +x "$PROCDIR/claude"
  PATH="$PROCDIR:$PATH" CLAUDE_CTX_FORCE_WRAP=1 timeout 20 \
    bash "$CTX" --model x --continue hello </dev/null >/dev/null 2>&1
  status=$?
  eq "wrapper exit status" "0" "$status"
  eq "wrapper relaunch account" "ultra" "$(cat "$ACCOUNT_OUT" 2>/dev/null)"
  eq "wrapper relaunch args" \
    "$(printf '%s\n' --model x --resume abc continue)" \
    "$(cat "$ARGS_OUT" 2>/dev/null)"
  eq "wrapper relaunch count" "2" "$(cat "$COUNTER" 2>/dev/null)"
  grep -q 'relaunch #1 --resume abc on ultra' "$LOG" || fail "log has no relaunch line"
  unset COUNTER ACCOUNT_OUT ARGS_OUT

  # 14. A caller token never wraps or relaunches.
  reset
  write_secrets
  export COUNTER="$TMPROOT/counter2"
  PROCDIR="$TMPROOT/proc-caller"
  mkdir -p "$PROCDIR"
  cat > "$PROCDIR/claude" <<'PROC'
#!/usr/bin/env bash
printf 'TOKEN=%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}"
n=0
[ -f "$COUNTER" ] && n=$(cat "$COUNTER")
printf '%s' "$((n + 1))" > "$COUNTER"
"$CTX" __limit <<<'{"session_id":"abc"}'
exit 0
PROC
  chmod +x "$PROCDIR/claude"
  out=$(CLAUDE_CODE_OAUTH_TOKEN=caller-token PATH="$PROCDIR:$PATH" CLAUDE_CTX_FORCE_WRAP=1 \
    bash "$CTX" </dev/null 2>/dev/null)
  eq "wrapper caller token" "TOKEN=caller-token" "$out"
  eq "wrapper caller token runs once" "1" "$(cat "$COUNTER" 2>/dev/null)"
  unset COUNTER

  # 15. The PATH shim routes claude through claude-ctx.
  reset
  write_secrets
  SHIMA="$TMPROOT/shimA/bin/shims"
  SHIMB="$TMPROOT/shimB"
  mkdir -p "$SHIMA" "$SHIMB"
  cp "$ROOT/bin/shims/claude" "$SHIMA/claude"
  chmod +x "$SHIMA/claude"
  cp "$FAKEBIN/claude" "$SHIMB/claude"
  chmod +x "$SHIMB/claude"
  out=$(PATH="$SHIMA:$SHIMB:$PATH" DOTS_SHIM_DIR="$SHIMA" CLAUDE_CTX_BIN="$CTX" \
    "$SHIMA/claude" </dev/null)
  eq "shim routes to claude-ctx" "CLAUDE_ACCOUNT=team TOKEN=tok-team LEAK=" "$out"

  # 16. Without DOTS_SHIM_DIR the shim is not stripped: fail, do not loop.
  err=$(timeout 5 env -u DOTS_SHIM_DIR PATH="$SHIMA:$SHIMB:$PATH" CLAUDE_CTX_BIN="$CTX" \
    "$SHIMA/claude" </dev/null 2>&1 >/dev/null)
  status=$?
  eq "shim loop guard status" "127" "$status"
  case "$err" in
    *"real claude not found on PATH"*) ;;
    *) fail "shim loop guard printed: $err" ;;
  esac
fi

# 17. Relaunch args keep option values and drop only the prompt.
eval "$(sed -n '/^build_relaunch_args()/,/^}/p' "$CTX")"
relaunch() { build_relaunch_args "$@"; printf '%s|' "${RELAUNCH_ARGS[@]}"; }
eq "relaunch keeps --model value" "--model|opus|" "$(relaunch --model opus)"
eq "relaunch drops prompt" "--model|opus|" "$(relaunch --model opus "fix it")"
eq "relaunch drops resume" "--model=opus|" "$(relaunch --resume abc --model=opus hi)"
eq "relaunch stops at --" "--verbose|" "$(relaunch --verbose -- "a prompt")"

# 18. A caller with its own endpoint or key gets no subscription token,
# not even one inherited from a parent claude, and keeps ANTHROPIC_API_KEY.
reset
write_secrets
eq "caller auth: no token" "CLAUDE_ACCOUNT= TOKEN= LEAK=" \
  "$(ANTHROPIC_AUTH_TOKEN=router CLAUDE_CODE_OAUTH_TOKEN=parent CLAUDE_ACCOUNT=team run_ctx)"
grep -q 'pick=caller-auth' "$LOG" || fail "log has no caller-auth line"
KEYBIN="$TMPROOT/keybin"
mkdir -p "$KEYBIN"
cat > "$KEYBIN/claude" <<'KEY'
#!/usr/bin/env bash
printf 'KEY=%s' "${ANTHROPIC_API_KEY:-}"
KEY
chmod +x "$KEYBIN/claude"
eq "caller auth keeps api key" "KEY=k" \
  "$(PATH="$KEYBIN:$PATH" ANTHROPIC_BASE_URL=https://router.example ANTHROPIC_API_KEY=k run_ctx)"
eq "no caller auth drops api key" "KEY=" "$(PATH="$KEYBIN:$PATH" ANTHROPIC_API_KEY=k run_ctx)"

# 19. A broken npx install of Claude Code fails loudly instead of running
# another claude; other npx tools that call claude still work.
reset
write_secrets
NPXA="$TMPROOT/npm/_npx/aaa"
mkdir -p "$NPXA/node_modules/.bin" "$NPXA/node_modules/@anthropic-ai/claude-code"
err=$(PATH="$NPXA/node_modules/.bin:$PATH" run_ctx --version 2>&1 >/dev/null)
eq "broken npx status" "1" "$?"
case "$err" in
  *"remove $NPXA"*) ;;
  *) fail "broken npx printed: $err" ;;
esac
NPXB="$TMPROOT/npm/_npx/bbb"
mkdir -p "$NPXB/node_modules/.bin"
eq "other npx tool runs claude" "CLAUDE_ACCOUNT=team TOKEN=tok-team LEAK=" \
  "$(PATH="$NPXB/node_modules/.bin:$PATH" run_ctx)"

printf 'ok: all claude-ctx tests passed\n'
