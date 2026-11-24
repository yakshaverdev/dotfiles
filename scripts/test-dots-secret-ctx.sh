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

printf 'ok: dots secret run and context hooks\n'
