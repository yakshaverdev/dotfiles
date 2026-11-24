#!/usr/bin/env bash
# Test `dots agents sync` without network access or real agent CLIs.
#
# Fake claude/codex/opencode/npx log their arguments; a temp HOME and git repos
# (plus a linked worktree) exercise translation, client secret resolution,
# ownership cleanup, tracked-file skips, excludes and skill links.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOTS="$ROOT/bin/dots"
AGENTS="$ROOT/bin/dots-agents"
REAL_HOME="$HOME"
# Keep the caller's XDG values so the jq shim wrapper can restore them: mise
# finds its installed tools through XDG_DATA_HOME and would recurse otherwise.
REAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME-}"
REAL_XDG_STATE_HOME="${XDG_STATE_HOME-}"
REAL_XDG_DATA_HOME="${XDG_DATA_HOME-}"
REAL_XDG_CACHE_HOME="${XDG_CACHE_HOME-}"
JQ_BIN="$(command -v jq || true)"

# pwd -P: macOS mktemp gives /var/..., but git and the sync store /private/var/...
TMPROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dots-agents-test.XXXXXX")" && pwd -P)"
cleanup() {
  if [ "${KEEP_TMP:-0}" = "1" ]; then
    printf 'kept: %s\n' "$TMPROOT" >&2
  else
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT

export HOME="$TMPROOT/home"
# Anchor every config path inside the temp HOME so a run can never touch the
# real user's config, state, data or cache, even when the caller sets these.
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export TMPDIR="$HOME/tmp"
# bin/dots-agents does not read these today, but the agent CLIs do.
unset CODEX_HOME OPENCODE_CONFIG CLAUDE_CONFIG_DIR

FAKEBIN="$TMPROOT/bin"
TEST_LOG="$TMPROOT/log"
AGENTS_CFG="$TMPROOT/agents-config"
SECRET_RUN="$TMPROOT/secret-run"
mkdir -p "$HOME" "$FAKEBIN" "$TEST_LOG" "$AGENTS_CFG" "$TMPDIR" \
  "$XDG_CONFIG_HOME/opencode" "$XDG_STATE_HOME" "$XDG_DATA_HOME" \
  "$XDG_CACHE_HOME" "$HOME/.codex"
export TEST_LOG

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

eq() { # label expected actual
  if [ "$2" != "$3" ]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    exit 1
  fi
}

contains() { # needle haystack label
  case "$2" in
    *"$1"*) ;;
    *) fail "$3: missing '$1'" ;;
  esac
}

not_contains() {
  case "$2" in
    *"$1"*) fail "$3: unexpected '$1'" ;;
  esac
}

mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true
}

# A fake jq that keeps the real HOME and XDG paths (mise shims need them).
real_xdg_dir() { # value default-subdir
  if [ -n "$1" ] && [ -d "$1" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$REAL_HOME/$2"
  fi
}
if [ -n "$JQ_BIN" ]; then
  {
    printf '#!/usr/bin/env bash\n'
    printf 'HOME=%q\n' "$REAL_HOME"
    printf 'XDG_CONFIG_HOME=%q\n' "$(real_xdg_dir "$REAL_XDG_CONFIG_HOME" .config)"
    printf 'XDG_STATE_HOME=%q\n' \
      "$(real_xdg_dir "$REAL_XDG_STATE_HOME" .local/state)"
    printf 'XDG_DATA_HOME=%q\n' "$(real_xdg_dir "$REAL_XDG_DATA_HOME" .local/share)"
    printf 'XDG_CACHE_HOME=%q\n' "$(real_xdg_dir "$REAL_XDG_CACHE_HOME" .cache)"
    printf 'exec %q "$@"\n' "$JQ_BIN"
  } > "$FAKEBIN/jq"
  chmod +x "$FAKEBIN/jq"
fi

cat > "$FAKEBIN/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG/claude.log"
exit 0
FAKE
chmod +x "$FAKEBIN/claude"

cat > "$FAKEBIN/codex" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG/codex.log"
# Exact argument list, NUL-safe: one JSON array per call.
printf '%s\0' "$@" | jq -R -s -c 'split("\u0000") | .[:-1]' >> "$TEST_LOG/codex.args"
exit 0
FAKE
chmod +x "$FAKEBIN/codex"

cat > "$FAKEBIN/opencode" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG/opencode.log"
exit 0
FAKE
chmod +x "$FAKEBIN/opencode"

cat > "$FAKEBIN/npx" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG/npx.log"
case "$*" in
  *experimental_install*)
    mkdir -p .claude/skills/locked-skill
    printf 'locked\n' > .claude/skills/locked-skill/SKILL.md
    ;;
esac
exit 0
FAKE
chmod +x "$FAKEBIN/npx"

cat > "$SECRET_RUN" <<'FAKE'
#!/usr/bin/env bash
# Same call shape as the real CLI: dots-secret run --ctx NAME -- CMD...
[[ "${1:-}" == run ]] || { echo "fake dots-secret: expected 'run', got '${1:-}'" >&2; exit 2; }
shift
ctx=""
while (($#)); do
  case "$1" in
    --ctx) ctx="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
case "$ctx" in
  shovel)
    export CLIENT_TOKEN='resolved-shovel-token'
    export EMPTY_TOKEN=''
    ;;
esac
exec "$@"
FAKE
chmod +x "$SECRET_RUN"

export PATH="$FAKEBIN:$PATH"
export DOTS_AGENTS_CONFIG_DIR="$AGENTS_CFG"
export DOTS_SECRET_RUN="$SECRET_RUN"

OUT=""
STATUS=0
run_dots() { # dir args...
  local dir="$1"
  shift
  OUT="$( cd "$dir" && bash "$AGENTS" "$@" 2>&1 )"
  STATUS=$?
}

make_repo() { # dir origin
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name Test
  git -C "$1" remote add origin "$2"
  printf 'readme\n' > "$1/README.md"
  git -C "$1" add README.md
  git -C "$1" commit -qm init
}

exclude_file() { # repo
  local f
  f="$(git -C "$1" rev-parse --git-path info/exclude)"
  case "$f" in
    /*) printf '%s\n' "$f" ;;
    *)  printf '%s/%s\n' "$1" "$f" ;;
  esac
}

exclude_count() { # repo pattern
  grep -cxF -- "$2" "$(exclude_file "$1")" 2>/dev/null || true
}

# The `dots` dispatcher must hand off to bin/dots-agents.
DISPATCH_OUT="$(bash "$DOTS" agents --help 2>&1)"
contains "usage: dots agents sync" "$DISPATCH_OUT" "dots agents dispatch"

# ── fixtures ───────────────────────────────────────────────────────────────
cat > "$AGENTS_CFG/mcp.json" <<'JSON'
{
  "mcpServers": {
    "deepwiki": {"type": "http", "url": "https://mcp.deepwiki.com/mcp"},
    "bearer": {"type": "http", "url": "https://bearer.example/mcp",
               "headers": {"Authorization": "Bearer ${GLOBAL_TOKEN}"}},
    "literalhdr": {"type": "http", "url": "https://lit.example/mcp",
                   "headers": {"X-Api-Key": "literal-value"}},
    "envhdr": {"type": "http", "url": "https://envh.example/mcp",
               "headers": {"X-Token": "${GLOBAL_TOKEN}"}},
    "stdio": {"command": "npx", "args": ["-y", "thing"],
              "env": {"TOKEN": "${TOKEN}", "LIT_VAR": "literal-env"}},
    "renamed": {"command": "renamed", "env": {"REF_VAR": "${GLOBAL_TOKEN}"}},
    "argtest": {"command": "argcmd", "args": ["", "a\nb", "c"]},
    "badmix": {"type": "http", "url": "https://bad.example/mcp",
               "headers": {"X-Bad": "pre-${GLOBAL_TOKEN}"}}
  }
}
JSON

mkdir -p "$AGENTS_CFG/shovel"
cat > "$AGENTS_CFG/shovel/mcp.json" <<'JSON'
{
  "mcpServers": {
    "client": {"type": "http", "url": "https://client.example/mcp",
               "headers": {"X-Token": "${CLIENT_TOKEN}"}},
    "clientstdio": {"command": "run", "args": ["x"],
                    "env": {"TOKEN": "${CLIENT_TOKEN}"}}
  }
}
JSON

cat > "$HOME/.codex/config.toml" <<'TOML'
# keep this comment
model = "test-model"

[mcp_servers.handmade]
command = "handmade"
TOML

cat > "$HOME/.config/opencode/opencode.json" <<'JSON'
{"$schema": "https://opencode.ai/config.json", "autoupdate": false, "keep": {"x": 1}}
JSON

# ── global level ───────────────────────────────────────────────────────────
run_dots "$HOME" sync --global-only
contains "mixes a literal" "$OUT" "global badmix failure"

grep -q 'add-json -s user deepwiki' "$TEST_LOG/claude.log" ||
  fail "claude did not add deepwiki"
grep -q 'add-json -s user bearer' "$TEST_LOG/claude.log" ||
  fail "claude did not add bearer"
# shellcheck disable=SC2016 # literal ${VAR} in the log
grep -q 'Bearer ${GLOBAL_TOKEN}' "$TEST_LOG/claude.log" ||
  fail "claude lost the ${VAR} reference"
grep -q 'remove -s user' "$TEST_LOG/claude.log" ||
  fail "claude did not remove before adding"

grep -q 'mcp add bearer --url https://bearer.example/mcp --bearer-token-env-var GLOBAL_TOKEN' \
  "$TEST_LOG/codex.log" || fail "codex did not use bearer_token_env_var"
grep -q 'mcp add deepwiki --url https://mcp.deepwiki.com/mcp' "$TEST_LOG/codex.log" ||
  fail "codex did not use the CLI for deepwiki"
not_contains "[mcp_servers.badmix" "$(cat "$HOME/.codex/config.toml")" "badmix in codex"
# shellcheck disable=SC2016 # literal ${VAR} in the message
contains 'env REF_VAR renames ${GLOBAL_TOKEN}; Codex can only pass a variable under its own name' \
  "$OUT" "codex renamed env error"
not_contains '[mcp_servers.renamed' "$(cat "$HOME/.codex/config.toml")" \
  "renamed env server in codex"
# Empty and multi-line arguments survive the codex CLI hand-off.
eq "codex arg boundaries" '["mcp","add","argtest","--","argcmd","","a\nb","c"]' \
  "$(grep -F '"add","argtest"' "$TEST_LOG/codex.args" | tail -n 1)"

CODEX_CFG="$(cat "$HOME/.codex/config.toml")"
contains '[mcp_servers.literalhdr.http_headers]' "$CODEX_CFG" "codex literal header"
contains '"X-Api-Key" = "literal-value"' "$CODEX_CFG" "codex literal header value"
contains '[mcp_servers.envhdr.env_http_headers]' "$CODEX_CFG" "codex env header"
contains '"X-Token" = "GLOBAL_TOKEN"' "$CODEX_CFG" "codex env header value"
contains '[mcp_servers.stdio]' "$CODEX_CFG" "codex stdio"
contains 'env_vars = ["TOKEN"]' "$CODEX_CFG" "codex same-name env_vars"
contains '"LIT_VAR" = "literal-env"' "$CODEX_CFG" "codex literal env"
contains '[mcp_servers.handmade]' "$CODEX_CFG" "codex keeps unmanaged server"

OC="$HOME/.config/opencode/opencode.json"
eq "opencode bearer ref" "Bearer {env:GLOBAL_TOKEN}" \
  "$(jq -r '.mcp.bearer.headers.Authorization' "$OC")"
eq "opencode literal header" "literal-value" \
  "$(jq -r '.mcp.literalhdr.headers["X-Api-Key"]' "$OC")"
eq "opencode stdio type" "local" "$(jq -r '.mcp.stdio.type' "$OC")"
eq "opencode stdio env ref" "{env:TOKEN}" \
  "$(jq -r '.mcp.stdio.environment.TOKEN' "$OC")"
eq "opencode stdio literal env" "literal-env" \
  "$(jq -r '.mcp.stdio.environment.LIT_VAR' "$OC")"
eq "opencode deepwiki" "remote" "$(jq -r '.mcp.deepwiki.type' "$OC")"
eq "opencode keeps other keys" "1" "$(jq -r '.keep.x' "$OC")"

# Remove a global server and rerun: managed stale goes, handmade stays.
jq 'del(.mcpServers.literalhdr, .mcpServers.badmix, .mcpServers.renamed)' \
  "$AGENTS_CFG/mcp.json" > "$TMPROOT/global-reduced.json"
mv "$TMPROOT/global-reduced.json" "$AGENTS_CFG/mcp.json"
run_dots "$HOME" sync --global-only
eq "global rerun status" "0" "$STATUS"
not_contains '[mcp_servers.literalhdr' "$(cat "$HOME/.codex/config.toml")" "stale codex table"
eq "stale opencode server gone" "null" \
  "$(jq -r '.mcp.literalhdr // "null"' "$OC")"
contains '[mcp_servers.handmade]' "$(cat "$HOME/.codex/config.toml")" "unmanaged codex table"
grep -q 'remove -s user literalhdr' "$TEST_LOG/claude.log" ||
  fail "claude did not remove the stale global server"

# Global idempotence.
GLOBAL_BEFORE="$(cksum "$HOME/.codex/config.toml" "$OC" \
  "$HOME/.local/state/dots/agents-sync.json")"
run_dots "$HOME" sync --global-only
eq "global third run status" "0" "$STATUS"
GLOBAL_AFTER="$(cksum "$HOME/.codex/config.toml" "$OC" \
  "$HOME/.local/state/dots/agents-sync.json")"
eq "global idempotent" "$GLOBAL_BEFORE" "$GLOBAL_AFTER"

# ── Claude re-applies only changed servers ─────────────────────────────────
claude_adds() { grep -c 'add-json -s user' "$TEST_LOG/claude.log" || true; }
STATE="$HOME/.local/state/dots/agents-sync.json"

ADD_BEFORE="$(claude_adds)"
run_dots "$HOME" sync --global-only
eq "claude unchanged status" "0" "$STATUS"
eq "claude unchanged adds nothing" "$ADD_BEFORE" "$(claude_adds)"
eq "claude hash recorded" "64" \
  "$(jq -r '.targets["claude-user"].hashes.deepwiki | length' "$STATE")"
# shellcheck disable=SC2016 # literal ${VAR} must not appear in state
not_contains 'Bearer ${GLOBAL_TOKEN}' \
  "$(jq -c '.targets["claude-user"]' "$STATE")" "state holds server JSON"

# Changing one server's URL re-adds only that server.
jq '.mcpServers.deepwiki.url = "https://mcp.deepwiki.com/v2"' "$AGENTS_CFG/mcp.json" \
  > "$TMPROOT/global-url.json"
mv "$TMPROOT/global-url.json" "$AGENTS_CFG/mcp.json"
ADD_BEFORE="$(claude_adds)"
run_dots "$HOME" sync --global-only
eq "claude changed status" "0" "$STATUS"
eq "claude changed re-adds one" "$((ADD_BEFORE + 1))" "$(claude_adds)"
contains "add-json -s user deepwiki" "$(tail -n 1 "$TEST_LOG/claude.log")" \
  "claude changed server"

# A legacy array (names only) has no hashes: it re-applies once, then settles.
jq '.targets["claude-user"] = .targets["claude-user"].names' "$STATE" \
  > "$TMPROOT/state.json"
mv "$TMPROOT/state.json" "$STATE"
ADD_BEFORE="$(claude_adds)"
run_dots "$HOME" sync --global-only
eq "legacy state status" "0" "$STATUS"
eq "legacy state re-applies once" "1" \
  "$([ "$(claude_adds)" -gt "$ADD_BEFORE" ] && printf 1 || printf 0)"
ADD_BEFORE="$(claude_adds)"
run_dots "$HOME" sync --global-only
eq "legacy state settles" "$ADD_BEFORE" "$(claude_adds)"

# ── project level ──────────────────────────────────────────────────────────
REPO="$TMPROOT/repo"
make_repo "$REPO" "git@github.com:shovelers/agents-test.git"
cat > "$REPO/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "projhttp": {"type": "http", "url": "https://proj.example/mcp",
                 "headers": {"Authorization": "Bearer ${PROJ_TOKEN}"}},
    "projstdio": {"command": "uvx", "args": ["srv"],
                  "env": {"PROJ_TOKEN": "${PROJ_TOKEN}", "LIT": "v"}}
  }
}
JSON
mkdir -p "$REPO/.agents/skills"
printf '{}' > "$REPO/skills-lock.json"

run_dots "$REPO" sync
eq "project run status" "0" "$STATUS"
contains "context: shovel" "$OUT" "project context detection"

eq "claude approval" "projhttp projstdio" \
  "$(jq -r '.enabledMcpjsonServers | sort | join(" ")' "$REPO/.claude/settings.local.json")"
grep -q 'add-json -s local client' "$TEST_LOG/claude.log" ||
  fail "claude local client server missing"
grep -q 'resolved-shovel-token' "$TEST_LOG/claude.log" ||
  fail "claude local client value was not resolved"
# shellcheck disable=SC2016 # literal ${VAR} must not appear
not_contains '${CLIENT_TOKEN}' "$(tail -n 5 "$TEST_LOG/claude.log")" \
  "claude local unresolved ref"
not_contains 'resolved-shovel-token' "$(cat "$STATE")" "state holds a resolved secret"
eq "project local hash recorded" "64" \
  "$(jq -r --arg k "claude-local:$REPO" '.targets[$k].hashes.client | length' "$STATE")"

PCODEX="$REPO/.codex/config.toml"
POPEN="$REPO/opencode.json"
contains 'bearer_token_env_var = "PROJ_TOKEN"' "$(cat "$PCODEX")" "project codex bearer"
contains '[mcp_servers.projstdio.env]' "$(cat "$PCODEX")" "project codex env table"
contains 'env_vars = ["PROJ_TOKEN"]' "$(cat "$PCODEX")" "project codex env_vars"
contains '[mcp_servers.client.http_headers]' "$(cat "$PCODEX")" "client literal header"
contains '"X-Token" = "resolved-shovel-token"' "$(cat "$PCODEX")" "client resolved value"
contains '[mcp_servers.clientstdio]' "$(cat "$PCODEX")" "client stdio"
eq "project codex mode" "600" "$(mode_of "$PCODEX")"

eq "project opencode bearer ref" "Bearer {env:PROJ_TOKEN}" \
  "$(jq -r '.mcp.projhttp.headers.Authorization' "$POPEN")"
eq "project opencode client literal" "resolved-shovel-token" \
  "$(jq -r '.mcp.client.headers["X-Token"]' "$POPEN")"
eq "project opencode client stdio" "resolved-shovel-token" \
  "$(jq -r '.mcp.clientstdio.environment.TOKEN' "$POPEN")"
eq "project opencode mode" "600" "$(mode_of "$POPEN")"

[ -L "$REPO/.claude/skills" ] || fail "no .claude/skills link"
eq "skills link target" "../.agents/skills" "$(readlink "$REPO/.claude/skills")"
eq "skills link exclude" "1" "$(exclude_count "$REPO" ".claude/skills")"
eq "skills restore ran" "1" \
  "$(grep -c 'experimental_install' "$TEST_LOG/npx.log" || true)"
grep -q -- '-a claude-code codex opencode' "$TEST_LOG/npx.log" ||
  fail "skills restore did not target all agents"
eq "restored skill exclude" "1" \
  "$(exclude_count "$REPO" ".agents/skills/locked-skill")"

for pat in .codex/config.toml opencode.json .claude/settings.local.json; do
  eq "exclude $pat once" "1" "$(exclude_count "$REPO" "$pat")"
done

# Project idempotence.
PROJECT_BEFORE="$(cksum "$REPO/.codex/config.toml" "$POPEN" \
  "$REPO/.claude/settings.local.json" "$HOME/.local/state/dots/agents-sync.json")"
LOCAL_ADDS_BEFORE="$(grep -c 'add-json -s local' "$TEST_LOG/claude.log" || true)"
run_dots "$REPO" sync
eq "project second run status" "0" "$STATUS"
eq "project second run adds nothing" "$LOCAL_ADDS_BEFORE" \
  "$(grep -c 'add-json -s local' "$TEST_LOG/claude.log" || true)"
PROJECT_AFTER="$(cksum "$REPO/.codex/config.toml" "$POPEN" \
  "$REPO/.claude/settings.local.json" "$HOME/.local/state/dots/agents-sync.json")"
eq "project idempotent" "$PROJECT_BEFORE" "$PROJECT_AFTER"
for pat in .codex/config.toml opencode.json .claude/settings.local.json .claude/skills; do
  eq "exclude $pat still once" "1" "$(exclude_count "$REPO" "$pat")"
done

# ── tracked target is skipped ──────────────────────────────────────────────
TRACKED="$TMPROOT/tracked"
make_repo "$TRACKED" "git@github.com:shovelers/tracked.git"
printf '{"tracked":true}\n' > "$TRACKED/opencode.json"
git -C "$TRACKED" add opencode.json
git -C "$TRACKED" commit -qm "tracked opencode"
run_dots "$TRACKED" sync --project-only
contains "opencode.json is tracked by git" "$OUT" "tracked skip warning"
eq "tracked file untouched" '{"tracked":true}' "$(cat "$TRACKED/opencode.json")"
eq "tracked file not excluded" "0" "$(exclude_count "$TRACKED" "opencode.json")"

# ── skill link, other direction ────────────────────────────────────────────
REVERSE="$TMPROOT/reverse"
make_repo "$REVERSE" "git@github.com:shovelers/reverse.git"
mkdir -p "$REVERSE/.claude/skills"
run_dots "$REVERSE" sync --project-only
[ -L "$REVERSE/.agents/skills" ] || fail "no .agents/skills link"
eq "reverse skills link" "../.claude/skills" "$(readlink "$REVERSE/.agents/skills")"
eq "reverse skills exclude" "1" "$(exclude_count "$REVERSE" ".agents/skills")"

BOTH="$TMPROOT/both"
make_repo "$BOTH" "git@github.com:shovelers/both.git"
mkdir -p "$BOTH/.agents/skills" "$BOTH/.claude/skills"
run_dots "$BOTH" sync --project-only
contains "both exist" "$OUT" "both skill dirs"
[ ! -L "$BOTH/.agents/skills" ] || fail "made a link when both skill dirs exist"
[ ! -L "$BOTH/.claude/skills" ] || fail "made a link when both skill dirs exist"

# A repo with no project servers and no client context gets no empty config.
PLAIN="$TMPROOT/plain"
make_repo "$PLAIN" "git@github.com:example/plain.git"
run_dots "$PLAIN" sync --project-only
eq "plain repo status" "0" "$STATUS"
[ ! -f "$PLAIN/.codex/config.toml" ] || fail "created an empty .codex/config.toml"
[ ! -f "$PLAIN/opencode.json" ] || fail "created an empty opencode.json"
[ ! -f "$PLAIN/.claude/settings.local.json" ] ||
  fail "created an empty .claude/settings.local.json"

# ── linked worktree ────────────────────────────────────────────────────────
WT="$TMPROOT/wt"
git -C "$REPO" worktree add -q "$WT" -b wt-test
# In a real repo .mcp.json is committed, so the worktree has it too.
cp "$REPO/.mcp.json" "$WT/.mcp.json"

# Nothing trusted: the sync trusts the main repo for Codex (that covers the
# worktree) and only warns for Claude. The main repo's own sync above already
# added its entry, so drop it first.
awk -v target="[projects.\"$REPO\"]" '
  $0 == target { skipping = 1; next }
  skipping && /^\[/ { skipping = 0 }
  !skipping { print }
' "$HOME/.codex/config.toml" > "$TMPROOT/codex.toml"
mv "$TMPROOT/codex.toml" "$HOME/.codex/config.toml"
run_dots "$WT" sync --project-only
eq "untrusted worktree status" "0" "$STATUS"
contains "codex: trusted" "$OUT" "worktree sync trusts the main repo"
eq "codex trust entry once" "1" \
  "$(grep -cxF "[projects.\"$REPO\"]" "$HOME/.codex/config.toml")"
run_dots "$WT" sync --project-only
eq "codex trust entry still once" "1" \
  "$(grep -cxF "[projects.\"$REPO\"]" "$HOME/.codex/config.toml")"
contains "Claude shows .mcp.json servers as pending" "$OUT" \
  "untrusted worktree claude warning"
[ -f "$WT/.codex/config.toml" ] || fail "no worktree .codex/config.toml"
[ -f "$WT/opencode.json" ] || fail "no worktree opencode.json"
eq "worktree exclude once" "1" "$(exclude_count "$REPO" ".codex/config.toml")"

# Trust the main worktree only: the linked worktree must accept it.
jq -n --arg p "$REPO" '{projects:{($p):{hasTrustDialogAccepted:true}}}' \
  > "$HOME/.claude.json"
chmod 600 "$HOME/.claude.json"
run_dots "$WT" sync --project-only
eq "main-trusted worktree status" "0" "$STATUS"
not_contains "Codex ignores .codex/config.toml" "$OUT" \
  "main-trusted worktree codex warning"
not_contains "Claude shows .mcp.json servers as pending" "$OUT" \
  "main-trusted worktree claude warning"

# An ancestor of the repo top is accepted too.
awk -v target="[projects.\"$REPO\"]" '
  $0 == target { skipping = 1; next }
  skipping && /^\[/ { skipping = 0 }
  !skipping { print }
' "$HOME/.codex/config.toml" > "$TMPROOT/codex.toml"
mv "$TMPROOT/codex.toml" "$HOME/.codex/config.toml"
jq --arg p "$REPO" 'del(.projects[$p])' "$HOME/.claude.json" \
  > "$TMPROOT/claude.json"
mv "$TMPROOT/claude.json" "$HOME/.claude.json"
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$TMPROOT" \
  >> "$HOME/.codex/config.toml"
jq --arg p "$TMPROOT" '.projects[$p] = {hasTrustDialogAccepted:true}' \
  "$HOME/.claude.json" > "$TMPROOT/claude.json"
mv "$TMPROOT/claude.json" "$HOME/.claude.json"
run_dots "$WT" sync --project-only
eq "ancestor-trusted worktree status" "0" "$STATUS"
not_contains "Codex ignores .codex/config.toml" "$OUT" \
  "ancestor-trusted worktree codex warning"
not_contains "Claude shows .mcp.json servers as pending" "$OUT" \
  "ancestor-trusted worktree claude warning"

# An entry the user wrote (here "untrusted") is respected: warn, no append.
# Drop the ancestor trust from the case above first.
awk -v target="[projects.\"$TMPROOT\"]" '
  $0 == target { skipping = 1; next }
  skipping && /^\[/ { skipping = 0 }
  !skipping { print }
' "$HOME/.codex/config.toml" > "$TMPROOT/codex.toml"
mv "$TMPROOT/codex.toml" "$HOME/.codex/config.toml"
printf '[projects."%s"]\ntrust_level = "untrusted"\n' "$REPO" \
  >> "$HOME/.codex/config.toml"
run_dots "$WT" sync --project-only
contains "Codex does not trust" "$OUT" "explicit codex entry respected"
eq "explicit codex entry not duplicated" "1" \
  "$(grep -cxF "[projects.\"$REPO\"]" "$HOME/.codex/config.toml")"

# ── empty client reference fails only that server ──────────────────────────
cat > "$AGENTS_CFG/shovel/mcp.json" <<'JSON'
{
  "mcpServers": {
    "clientempty": {"type": "http", "url": "https://empty.example/mcp",
                    "headers": {"X-Token": "${EMPTY_TOKEN}"}}
  }
}
JSON
EMPTYREPO="$TMPROOT/empty"
make_repo "$EMPTYREPO" "git@github.com:shovelers/empty.git"
run_dots "$EMPTYREPO" sync --project-only
# shellcheck disable=SC2016 # literal ${VAR} in the message
contains 'empty ${EMPTY_TOKEN}' "$OUT" "empty reference message"
if [ -f "$EMPTYREPO/opencode.json" ]; then
  eq "empty client server skipped" "null" \
    "$(jq -r '.mcp.clientempty // "null"' "$EMPTYREPO/opencode.json")"
fi

printf 'ok: all dots agents tests passed\n'
