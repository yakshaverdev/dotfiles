#!/usr/bin/env bash
# Test the version compare helper extracted from bin/dots.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOTS="$ROOT/bin/dots"

# eval, not source <(...): macOS bash 3.2 cannot source a process substitution.
eval "$(sed -n '/^# BEGIN version_ge$/,/^# END version_ge$/p' "$DOTS")"

if ! declare -F version_ge >/dev/null; then
  printf 'FAIL: version_ge not found in %s\n' "$DOTS" >&2
  exit 1
fi

failed=0

assert_ge() { # a b
  if ! version_ge "$1" "$2"; then
    printf 'FAIL: %s >= %s\n' "$1" "$2" >&2
    failed=1
  fi
}

assert_lt() { # a b
  if version_ge "$1" "$2"; then
    printf 'FAIL: %s < %s\n' "$1" "$2" >&2
    failed=1
  fi
}

assert_ge 11.10.0 11.10.0
assert_ge 11.10.0 10.9.9
assert_lt 10.9.9 11.10.0
assert_lt 11.9.9 11.10.0

if ((failed)); then
  exit 1
fi
printf 'version_ge tests passed\n'
