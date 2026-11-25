#!/usr/bin/env bash
# Test that ~/.zshenv makes agent `zsh -c` commands treat unmatched globs and
# `=` words like bash, and that other zsh shells keep the zsh defaults.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/empty"
ln -s "$ROOT/stow/common/zsh/.zshenv" "$TMP/home/.zshenv"

PROG='echo --include=*.py; echo ===='
printf '%s\n' "$PROG" >"$TMP/script.zsh"
BASH_LIKE=$'--include=*.py\n===='

failed=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failed=1
}

# Run zsh in the empty directory with a clean HOME and no agent markers,
# plus the given VAR=value assignments, then the given zsh arguments.
run() { # [VAR=value...] -- zsh-args...
  local vars=()
  while [[ $1 != -- ]]; do
    vars+=("$1")
    shift
  done
  shift
  (
    cd "$TMP/empty" &&
      env -u ZDOTDIR -u CLAUDECODE -u T3CODE_THREAD_ID -u CODEX_THREAD_ID \
        -u CODEX_SANDBOX -u OPENCODE -u DOT_CTX -u DOT_CTX_PIN \
        HOME="$TMP/home" DOTFILES="$ROOT" ${vars[@]+"${vars[@]}"} zsh "$@" 2>&1 </dev/null
  ) || true
}

for marker in CLAUDECODE=1 CODEX_THREAD_ID=t CODEX_SANDBOX=seatbelt OPENCODE=1 T3CODE_THREAD_ID=t; do
  out="$(run "$marker" -- -c "$PROG")"
  [[ $out == "$BASH_LIKE" ]] || fail "$marker zsh -c: expected bash-like output, got: $out"
  out="$(run "$marker" -- -lc "$PROG")"
  [[ $out == "$BASH_LIKE" ]] || fail "$marker zsh -lc: expected bash-like output, got: $out"
done

out="$(run -- -c "$PROG")"
[[ $out == *"no matches found"* ]] || fail "no marker zsh -c: expected zsh default, got: $out"

out="$(run CLAUDECODE=1 -- -i -c "$PROG")"
[[ $out == *"no matches found"* ]] || fail "interactive shell: expected zsh default, got: $out"

out="$(run CLAUDECODE=1 -- "$TMP/script.zsh")"
[[ $out == *"no matches found"* ]] || fail "zsh script: expected zsh default, got: $out"

if ((failed)); then
  exit 1
fi
printf 'zshenv agent shell tests passed\n'
