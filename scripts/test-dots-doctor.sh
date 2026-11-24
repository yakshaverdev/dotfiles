#!/usr/bin/env bash
# Test the `dots doctor --local` agent readiness checks without network access.
#
# A temp HOME holds a fake ~/.agents/skills tree; the repo manifest drives the
# check. Stubs keep mise, npm and brew from running, and --local keeps doctor
# away from Infisical. Only the "Agent skills" section and the overall status
# are asserted: every other section depends on the host, not on this test.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOTS="$ROOT/bin/dots"
MANIFEST="$ROOT/packages/agent-skills"
REAL_PATH="$PATH"

# pwd -P: macOS mktemp gives /var/..., while tools may report /private/var/...
TMPROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dots-doctor-test.XXXXXX")" && pwd -P)"
cleanup() {
  if [ "${KEEP_TMP:-0}" = "1" ]; then
    printf 'kept: %s\n' "$TMPROOT" >&2
  else
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT

export HOME="$TMPROOT/home"
# Anchor every config path inside the temp HOME so the run cannot touch the
# real user's config, state, data or cache.
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export TMPDIR="$HOME/tmp"
unset CODEX_HOME OPENCODE_CONFIG CLAUDE_CONFIG_DIR

FAKEBIN="$TMPROOT/bin"
mkdir -p "$HOME" "$FAKEBIN" "$TMPDIR" \
  "$HOME/.agents/skills" "$HOME/.claude/skills" "$XDG_CONFIG_HOME"
export PATH="$FAKEBIN:$REAL_PATH"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Exit 0 with no output: `mise ls --missing` then finds nothing missing.
cat > "$FAKEBIN/mise" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
chmod +x "$FAKEBIN/mise"

# No npm version: doctor notes that the cooldown cannot be confirmed.
cat > "$FAKEBIN/npm" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
chmod +x "$FAKEBIN/npm"

# No brew: doctor reports missing packages without running a bundle check.
cat > "$FAKEBIN/brew" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
chmod +x "$FAKEBIN/brew"

# Every skill name in the manifest, one per line (bash 3.2: no mapfile).
skill_names() {
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$MANIFEST" \
    | while IFS= read -r line; do
        line="${line#* }"
        printf '%s\n' "$line" | tr ',' '\n'
      done \
    | sed -e 's/[[:space:]]//g' -e '/^$/d'
}

# Rebuild the fake skill tree, skipping $1 (empty means keep every skill).
make_skills() {
  local skip="$1" name
  rm -rf "$HOME/.agents/skills" "$HOME/.claude/skills"
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ "$name" = "$skip" ] && continue
    mkdir -p "$HOME/.agents/skills/$name"
    ln -s "../../.agents/skills/$name" "$HOME/.claude/skills/$name"
  done <<EOF
$(skill_names)
EOF
}

skills_section() { # output
  printf '%s\n' "$1" | awk '/^→ Agent skills$/{ on = 1; next } /^→ /{ on = 0 } on'
}

contains() { # needle haystack label
  case "$2" in
    *"$1"*) ;;
    *) fail "$3 (missing: $1)" ;;
  esac
}

not_contains() { # needle haystack label
  case "$2" in
    *"$1"*) fail "$3 (unexpected: $1)" ;;
  esac
}

MISSING="$(skill_names | tail -n 1)"
[ -n "$MISSING" ] || fail "no skills found in $MANIFEST"

# 1. One skill missing: the section names it and the run fails.
make_skills "$MISSING"
rc=0
out="$("$DOTS" doctor --local 2>&1)" || rc=$?
section="$(skills_section "$out")"
[ -n "$section" ] || fail "Agent skills section missing from doctor output"
contains "$MISSING" "$section" "missing skill is named in the skills section"
contains "✗" "$section" "missing skill is reported as a problem"
[ "$rc" -ne 0 ] || fail "doctor --local exited 0 with a missing skill"

# 2. Every skill present and linked: the section reports ok.
make_skills ""
out="$("$DOTS" doctor --local 2>&1 || true)"
section="$(skills_section "$out")"
[ -n "$section" ] || fail "Agent skills section missing from doctor output"
contains "✓" "$section" "skills section reports ok when every skill is present"
not_contains "✗" "$section" "skills section must not report a problem when all skills exist"

printf 'dots doctor --local tests passed\n'
