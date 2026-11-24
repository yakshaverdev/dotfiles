#!/usr/bin/env bash
# Test client-context switching without network or real secrets:
#   a) `dots secret run --ctx B` from a shell in context A drops A's keys
#   b) leaving a merge context restores personal values (zsh chpwd hook)
#   c) the same for the bash BASH_ENV hook
set -euo pipefail

# A BASH_ENV hook from the surrounding agent shell would rewrite context
# variables inside the children and hide what this test measures.
unset BASH_ENV
unset CLAUDECODE T3CODE_THREAD_ID CODEX_THREAD_ID CODEX_SANDBOX OPENCODE

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# jq is often a mise shim that needs the real HOME. Keep both for later.
REAL_HOME="$HOME"
JQ_BIN="$(command -v jq || true)"

export HOME="$TMPROOT/home"
CFG="$HOME/.config/dot"
CTXDIR="$CFG/ctx"
PLAIN="$TMPROOT/plain"
mkdir -p "$CTXDIR" "$PLAIN" "$TMPROOT/tmp"
export TMPDIR="$TMPROOT/tmp"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ── Fake caches ────────────────────────────────────────────────────────────
# Personal keys: PERSONAL_ONLY and SHARED_KEY.
cat > "$CFG/secrets.zsh" <<'EOF'
export PERSONAL_ONLY='personal-only'
export SHARED_KEY='personal-shared'
EOF
printf 'PERSONAL_ONLY\nSHARED_KEY\n' > "$CFG/secrets.names"

# lyre is the repo's merge context; its cache overrides SHARED_KEY.
cat > "$CTXDIR/lyre.zsh" <<'EOF'
export LYRE_KEY='lyre-only'
export SHARED_KEY='lyre-shared'
EOF
printf 'LYRE_KEY\nSHARED_KEY\n' > "$CTXDIR/lyre.names"

# skit is the repo's strict context.
cat > "$CTXDIR/skit.zsh" <<'EOF'
export SKIT_KEY='skit-only'
EOF
printf 'SKIT_KEY\n' > "$CTXDIR/skit.names"

# Fake repos whose origins map to those contexts in config/contexts.
make_repo() { # dir origin
  git init -q "$1"
  git -C "$1" remote add origin "$2"
}
LYRE_REPO="$TMPROOT/lyre-repo"
make_repo "$LYRE_REPO" 'git@github.com:yakshaverdev/lyre.git'
SKIT_REPO="$TMPROOT/skit-repo"
make_repo "$SKIT_REPO" 'git@github.com:skit-ai/app.git'

# ── (a) dots secret run leaves the inherited context behind ────────────────
run_secret() { # ctx -> stdout of `env` from the child
  env -u BASH_ENV -u DOT_CTX -u LYRE_KEY -u SHARED_KEY -u PERSONAL_ONLY \
    HOME="$HOME" TMPDIR="$TMPDIR" \
    DOT_CTX=lyre LYRE_KEY=lyre-only SHARED_KEY=lyre-shared PERSONAL_ONLY=personal-only \
    bash "$ROOT/bin/dots-secret" run --ctx "$1" -- env
}

out="$(run_secret skit)"
[[ $out == *"SKIT_KEY=skit-only"* ]] || fail "run --ctx skit: SKIT_KEY missing"
[[ $out != *"LYRE_KEY="* ]] || fail "run --ctx skit: inherited LYRE_KEY leaked"
[[ $out != *"SHARED_KEY="* ]] || fail "run --ctx skit: inherited SHARED_KEY leaked"
[[ $out != *"PERSONAL_ONLY="* ]] || fail "run --ctx skit: personal key leaked into strict context"
[[ $out == *"DOT_CTX=skit"* ]] || fail "run --ctx skit: DOT_CTX not set to skit"

# exec must remove the plaintext temp dir first (no EXIT trap on exec).
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]] || fail "run left temp files in TMPDIR"

# Target personal from a client context: cleanup, then no DOT_CTX.
out="$(run_secret personal)"
[[ $out == *"SHARED_KEY=personal-shared"* ]] || fail "run --ctx personal: personal value not restored"
[[ $out != *"LYRE_KEY="* ]] || fail "run --ctx personal: inherited LYRE_KEY leaked"
[[ $out != *"DOT_CTX="* ]] || fail "run --ctx personal: DOT_CTX still exported"
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]] || fail "run --ctx personal left temp files"

# ── (b) zsh chpwd hook: leave a merge context ──────────────────────────────
# shellcheck disable=SC2016  # the zsh script expands its own variables
zsh_out="$(
  HOME="$HOME" DOTFILES="$ROOT" PLAIN="$PLAIN" LYRE_REPO="$LYRE_REPO" \
  env -u BASH_ENV -u DOT_CTX -u LYRE_KEY -u SHARED_KEY -u PERSONAL_ONLY \
  zsh -c '
    cd "$PLAIN" || exit 1
    source "$HOME/.config/dot/secrets.zsh" || exit 1
    source "$DOTFILES/stow/common/zsh/.config/zsh/contexts.zsh"
    [[ ${SHARED_KEY:-} == personal-shared ]] || { print -u2 "personal not sourced"; exit 1; }
    cd "$LYRE_REPO" || exit 1
    [[ ${DOT_CTX:-} == lyre ]] || { print -u2 "merge context not applied: ${DOT_CTX:-unset}"; exit 1; }
    [[ $SHARED_KEY == lyre-shared ]] || { print -u2 "merge override missing"; exit 1; }
    cd "$PLAIN" || exit 1
    print -r -- "SHARED_KEY=${SHARED_KEY:-}"
    print -r -- "LYRE_KEY=${LYRE_KEY:-}"
    print -r -- "DOT_CTX=${DOT_CTX:-}"
  '
)" || fail "zsh hook: script error"
[[ $zsh_out == *"SHARED_KEY=personal-shared"* ]] || fail "zsh hook: personal value not restored on leave: $zsh_out"
[[ $zsh_out != *"LYRE_KEY=lyre-only"* ]] || fail "zsh hook: LYRE_KEY not unset: $zsh_out"
[[ $zsh_out != *"DOT_CTX=lyre"* ]] || fail "zsh hook: DOT_CTX still set"

# ── (c) bash BASH_ENV hook: leave a merge context ──────────────────────────
BASH_ENV_FILE="$ROOT/stow/common/zsh/.config/zsh/contexts.bash"
# shellcheck disable=SC2016  # the child bash expands these variables
CHILD_PROG='printf "SHARED_KEY=%s\nLYRE_KEY=%s\nDOT_CTX=%s\n" "${SHARED_KEY:-}" "${LYRE_KEY:-}" "${DOT_CTX:-}"'
bash_enter="$(
  cd "$LYRE_REPO" && HOME="$HOME" DOTFILES="$ROOT" OPENCODE=1 \
    env -u BASH_ENV -u DOT_CTX -u LYRE_KEY -u SHARED_KEY -u PERSONAL_ONLY \
      BASH_ENV="$BASH_ENV_FILE" bash -c "$CHILD_PROG"
)" || fail "bash hook: enter failed"
[[ $bash_enter == *"SHARED_KEY=lyre-shared"* ]] || fail "bash hook: merge override not applied: $bash_enter"

bash_leave="$(
  cd "$PLAIN" && HOME="$HOME" DOTFILES="$ROOT" OPENCODE=1 \
    DOT_CTX=lyre LYRE_KEY=lyre-only SHARED_KEY=lyre-shared \
    BASH_ENV="$BASH_ENV_FILE" bash -c "$CHILD_PROG"
)" || fail "bash hook: leave failed"
[[ $bash_leave == *"SHARED_KEY=personal-shared"* ]] || fail "bash hook: personal value not restored on leave: $bash_leave"
[[ $bash_leave != *"LYRE_KEY=lyre-only"* ]] || fail "bash hook: LYRE_KEY not unset: $bash_leave"
[[ $bash_leave != *"DOT_CTX=lyre"* ]] || fail "bash hook: DOT_CTX still set: $bash_leave"

# ── (d) personal value survives an inherited context in a personal dir ────
# .zshenv sources personal values, then contexts.zsh rebuilds from a clean
# state. LYRE overrides SHARED_KEY, so unsets alone would lose it.
# shellcheck disable=SC2016  # the zsh script expands its own variables
REBUILD_PROG='
  cd "$PLAIN" || exit 1
  source "$HOME/.config/dot/secrets.zsh" || exit 1
  source "$DOTFILES/stow/common/zsh/.config/zsh/contexts.zsh"
  print -r -- "SHARED_KEY=${SHARED_KEY:-}"
  print -r -- "LYRE_KEY=${LYRE_KEY:-}"
  print -r -- "DOT_CTX=${DOT_CTX:-}"
'
out="$(
  HOME="$HOME" DOTFILES="$ROOT" PLAIN="$PLAIN" \
  env -u BASH_ENV -u DOT_CTX_PIN DOT_CTX=lyre LYRE_KEY=lyre-only SHARED_KEY=lyre-shared \
  zsh -c "$REBUILD_PROG"
)" || fail "inherited rebuild: script error"
printf '%s\n' "$out" | grep -qx 'SHARED_KEY=personal-shared' ||
  fail "inherited rebuild: personal value lost: $out"
printf '%s\n' "$out" | grep -qx 'LYRE_KEY=' ||
  fail "inherited rebuild: LYRE_KEY kept: $out"
printf '%s\n' "$out" | grep -qx 'DOT_CTX=' ||
  fail "inherited rebuild: DOT_CTX kept: $out"

# ── (e) a zsh child without agent markers still applies a strict context ──
mkdir -p "$HOME/.config/zsh"
ln -sf "$ROOT/stow/common/zsh/.zshenv" "$HOME/.zshenv"
ln -sf "$ROOT/stow/common/zsh/.config/zsh/contexts.zsh" \
  "$HOME/.config/zsh/contexts.zsh"
# shellcheck disable=SC2016  # the zsh script expands its own variables
STRICT_PROG='printf "PERSONAL_ONLY=%s\nSHARED_KEY=%s\nSKIT_KEY=%s\nDOT_CTX=%s\n" \
  "${PERSONAL_ONLY:-}" "${SHARED_KEY:-}" "${SKIT_KEY:-}" "${DOT_CTX:-}"'
out="$(
  cd "$SKIT_REPO" && HOME="$HOME" DOTFILES="$ROOT" \
  env -u BASH_ENV -u DOT_CTX_PIN -u CLAUDECODE -u T3CODE_THREAD_ID \
    -u CODEX_THREAD_ID -u CODEX_SANDBOX -u OPENCODE \
    DOT_CTX=skit SKIT_KEY=skit-only SHARED_KEY=lyre-shared PERSONAL_ONLY=personal-only \
    zsh -c "$STRICT_PROG"
)" || fail "zsh child: script error"
printf '%s\n' "$out" | grep -qx 'PERSONAL_ONLY=' ||
  fail "zsh child: personal key leaked into strict context: $out"
printf '%s\n' "$out" | grep -qx 'SHARED_KEY=' ||
  fail "zsh child: personal SHARED_KEY leaked: $out"
printf '%s\n' "$out" | grep -qx 'SKIT_KEY=skit-only' ||
  fail "zsh child: SKIT_KEY missing: $out"
printf '%s\n' "$out" | grep -qx 'DOT_CTX=skit' ||
  fail "zsh child: DOT_CTX not skit: $out"

# ── (f) dots secret run --ctx pins the context for bash children ──────────
# The bash child sources BASH_ENV and must keep skit, not the personal cwd.
# shellcheck disable=SC2016  # the child bash expands these variables
PIN_PROG='printf "SKIT_KEY=%s\nDOT_CTX=%s\nSHARED_KEY=%s\n" \
  "${SKIT_KEY:-}" "${DOT_CTX:-}" "${SHARED_KEY:-}"'
out="$(
  cd "$PLAIN" && HOME="$HOME" TMPDIR="$TMPDIR" DOTFILES="$ROOT" OPENCODE=1 \
    BASH_ENV="$BASH_ENV_FILE" \
    env -u DOT_CTX -u DOT_CTX_PIN -u LYRE_KEY -u SKIT_KEY -u SHARED_KEY -u PERSONAL_ONLY \
    bash "$ROOT/bin/dots-secret" run --ctx skit -- bash -c "$PIN_PROG"
)" || fail "pinned run: script error"
printf '%s\n' "$out" | grep -qx 'SKIT_KEY=skit-only' ||
  fail "pinned run: SKIT_KEY missing: $out"
printf '%s\n' "$out" | grep -qx 'DOT_CTX=skit' ||
  fail "pinned run: pinned context dropped: $out"

# ── (g) sync keeps names that a later sync drops ──────────────────────────
# A shell can still hold a key when the next sync removes it upstream. The
# .names files must keep the old names so a context switch unsets them.
# Read by the sync functions that this test evals from bin/dots-secret.
export CONFIG_DIR="$CFG"
export SECRETS_ZSH="$CFG/secrets.zsh"
export SECRETS_ENV="$CFG/secrets.env"
export SECRETS_NAMES="$CFG/secrets.names"
export SECRETS_SYNCED="$CFG/secrets.synced"
export CLAUDE_TOKENS_ENV="$CFG/claude-tokens.env"
export CTX_DIR="$CTXDIR"
info() { :; }
warn() { :; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
valid_name() { [[ $1 =~ ^[A-Z_][A-Z0-9_]*$ ]]; }
ctx_zsh_file() { printf '%s/%s.zsh\n' "$CTX_DIR" "$1"; }
ctx_names_file() { printf '%s/%s.names\n' "$CTX_DIR" "$1"; }
eval "$(sed -n '/^merge_known_names()/,/^}/p' "$ROOT/bin/dots-secret")"
eval "$(sed -n '/^write_ctx_files()/,/^}/p' "$ROOT/bin/dots-secret")"
eval "$(sed -n '/^write_secrets_files()/,/^}/p' "$ROOT/bin/dots-secret")"
# The real jq may be a mise shim that needs the real HOME.
[ -n "$JQ_BIN" ] || fail "names union: jq is required"
mkdir -p "$TMPROOT/bin"
printf '#!/usr/bin/env bash\nHOME=%q exec %q "$@"\n' "$REAL_HOME" "$JQ_BIN" \
  > "$TMPROOT/bin/jq"
chmod +x "$TMPROOT/bin/jq"
export PATH="$TMPROOT/bin:$PATH"

printf '%s' '{"LYRE_KEY":"lyre-only","SHARED_KEY":"lyre-shared"}' > "$TMPROOT/sync1.json"
write_ctx_files lyre "$TMPROOT/sync1.json" || fail "names union: first sync failed"
printf '%s' '{"SHARED_KEY":"lyre-shared"}' > "$TMPROOT/sync2.json"
write_ctx_files lyre "$TMPROOT/sync2.json" || fail "names union: second sync failed"
grep -qxF 'LYRE_KEY' "$CTXDIR/lyre.names" ||
  fail "names union: second sync dropped LYRE_KEY"

# shellcheck disable=SC2016  # the zsh script expands its own variables
CLIENT_PROG='
  cd "$LYRE_REPO" || exit 1
  source "$HOME/.config/dot/secrets.zsh" || exit 1
  source "$DOTFILES/stow/common/zsh/.config/zsh/contexts.zsh"
  cd "$SKIT_REPO" || exit 1
  print -r -- "LYRE_KEY=${LYRE_KEY:-}"
  print -r -- "DOT_CTX=${DOT_CTX:-}"
'
out="$(
  HOME="$HOME" DOTFILES="$ROOT" LYRE_REPO="$LYRE_REPO" SKIT_REPO="$SKIT_REPO" \
  env -u BASH_ENV -u DOT_CTX -u DOT_CTX_PIN -u SHARED_KEY -u PERSONAL_ONLY \
    LYRE_KEY=lyre-only \
    zsh -c "$CLIENT_PROG"
)" || fail "names union: client switch script error"
printf '%s\n' "$out" | grep -qx 'LYRE_KEY=' ||
  fail "names union: deleted client key survived a strict switch: $out"
printf '%s\n' "$out" | grep -qx 'DOT_CTX=skit' ||
  fail "names union: context not skit: $out"

# The personal list keeps deleted names the same way.
printf '%s' '[{"key":"PERSONAL_ONLY","value":"personal-only"},{"key":"SHARED_KEY","value":"personal-shared"}]' \
  > "$TMPROOT/personal1.json"
write_secrets_files "$TMPROOT/personal1.json" || fail "names union: first personal sync failed"
printf '%s' '[{"key":"SHARED_KEY","value":"personal-shared"}]' > "$TMPROOT/personal2.json"
write_secrets_files "$TMPROOT/personal2.json" || fail "names union: second personal sync failed"
grep -qxF 'PERSONAL_ONLY' "$CFG/secrets.names" ||
  fail "names union: second sync dropped PERSONAL_ONLY"

# shellcheck disable=SC2016  # the zsh script expands its own variables
PERSONAL_PROG='
  source "$DOTFILES/stow/common/zsh/.config/zsh/contexts.zsh"
  cd "$SKIT_REPO" || exit 1
  print -r -- "PERSONAL_ONLY=${PERSONAL_ONLY:-}"
  print -r -- "DOT_CTX=${DOT_CTX:-}"
'
out="$(
  HOME="$HOME" DOTFILES="$ROOT" SKIT_REPO="$SKIT_REPO" \
  env -u BASH_ENV -u DOT_CTX -u DOT_CTX_PIN -u SHARED_KEY \
    PERSONAL_ONLY=personal-only \
    zsh -c "$PERSONAL_PROG"
)" || fail "names union: personal switch script error"
printf '%s\n' "$out" | grep -qx 'PERSONAL_ONLY=' ||
  fail "names union: deleted personal key survived a strict switch: $out"
printf '%s\n' "$out" | grep -qx 'DOT_CTX=skit' ||
  fail "names union: personal switch context not skit: $out"

printf 'ok: dots secret run and context hooks\n'
