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
REAL_HOME="$HOME"
REAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME-}"
REAL_XDG_STATE_HOME="${XDG_STATE_HOME-}"
REAL_XDG_DATA_HOME="${XDG_DATA_HOME-}"
REAL_XDG_CACHE_HOME="${XDG_CACHE_HOME-}"
JQ_BIN="$(command -v jq || true)"
YQ_BIN="$(command -v yq || true)"

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

# jq and yq are mise shims, so a wrapper restores the caller's HOME and XDG
# paths for them while the script itself runs under the temp HOME.
real_xdg_dir() { # value default-subdir
  if [ -n "$1" ] && [ -d "$1" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$REAL_HOME/$2"
  fi
}

make_wrapper() { # tool real-binary
  {
    printf '#!/usr/bin/env bash\n'
    printf 'HOME=%q\n' "$REAL_HOME"
    printf 'XDG_CONFIG_HOME=%q\n' "$(real_xdg_dir "$REAL_XDG_CONFIG_HOME" .config)"
    printf 'XDG_STATE_HOME=%q\n' \
      "$(real_xdg_dir "$REAL_XDG_STATE_HOME" .local/state)"
    printf 'XDG_DATA_HOME=%q\n' "$(real_xdg_dir "$REAL_XDG_DATA_HOME" .local/share)"
    printf 'XDG_CACHE_HOME=%q\n' "$(real_xdg_dir "$REAL_XDG_CACHE_HOME" .cache)"
    printf 'exec %q "$@"\n' "$2"
  } > "$FAKEBIN/$1"
  chmod +x "$FAKEBIN/$1"
}

[ -z "$JQ_BIN" ] || make_wrapper jq "$JQ_BIN"
[ -z "$YQ_BIN" ] || make_wrapper yq "$YQ_BIN"

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

section_of() { # output heading (the text after →)
  printf '%s\n' "$1" | awk -v h="→ $2" '
    $0 == h { on = 1; next }
    on && /^→ / { on = 0 }
    on
  '
}

# 3. tmux plugins: every configured plugin is reported, with a repair hint.
cat > "$FAKEBIN/tmux" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
chmod +x "$FAKEBIN/tmux"
cat > "$HOME/.tmux.conf" <<'CONF'
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin "tmux-plugins/tmux-resurrect"
CONF
out="$("$DOTS" doctor --local 2>&1 || true)"
section="$(section_of "$out" "tmux plugins")"
contains "tmux-sensible missing" "$section" "missing tmux plugin is named"
contains "tmux-resurrect missing" "$section" "missing double-quoted tmux plugin is named"
not_contains "tmux plugin tpm missing" "$section" "tpm is not reported as a plugin"
contains "run: dots install" "$section" "tmux repair hint"
mkdir -p "$HOME/.tmux/plugins/tpm" "$HOME/.tmux/plugins/tmux-sensible" \
  "$HOME/.tmux/plugins/tmux-resurrect"
out="$("$DOTS" doctor --local 2>&1 || true)"
section="$(section_of "$out" "tmux plugins")"
contains "✓ TPM installed" "$section" "installed TPM is reported"
not_contains "✗" "$section" "tmux section is clean when every plugin exists"

# 4. Codex trust comes from CODEX_HOME and tolerates a header comment.
D_REPO="$TMPROOT/codexhome-repo"
mkdir -p "$D_REPO"
git -C "$D_REPO" init -q
git -C "$D_REPO" config user.email test@example.com
git -C "$D_REPO" config user.name Test
printf 'readme\n' > "$D_REPO/README.md"
git -C "$D_REPO" add README.md
git -C "$D_REPO" commit -qm init
mkdir -p "$TMPROOT/codexhome"
printf '[projects."%s"]   # trusted by hand\ntrust_level = "trusted"\n' "$TMPROOT" \
  > "$TMPROOT/codexhome/config.toml"
out="$( cd "$D_REPO" && CODEX_HOME="$TMPROOT/codexhome" "$DOTS" doctor --local 2>&1 || true )"
section="$(section_of "$out" "Trust")"
contains "codex trusts" "$section" "CODEX_HOME is read for Codex trust"
not_contains "Codex trust unchecked" "$section" "CODEX_HOME config was found"

# 5. dots skills sync installs missing enabled Claude plugins.
SETTINGS="$ROOT/stow/common/claude/.claude/settings.json"
CLAUDE_LOG="$TMPROOT/claude.log"
CLAUDE_MARKETS="$TMPROOT/marketplaces"
CLAUDE_MARKET_ADD="$TMPROOT/marketplace-add.log"
export CLAUDE_LOG CLAUDE_MARKETS CLAUDE_MARKET_ADD
: > "$CLAUDE_LOG"
: > "$CLAUDE_MARKET_ADD"
jq -r '.enabledPlugins | keys[] | split("@")[1]' "$SETTINGS" | sort -u \
  | grep -v '^pstack-claude$' > "$CLAUDE_MARKETS" || true
mkdir -p "$HOME/.claude/plugins"
jq --arg skip 'pstack@pstack-claude' '
  {version: 2,
   plugins: (.enabledPlugins // {}
     | with_entries(select(.value == true and .key != $skip))
     | map_values({}))}
' "$SETTINGS" > "$HOME/.claude/plugins/installed_plugins.json"
cat > "$FAKEBIN/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
case "$1 ${2:-}" in
  "plugin marketplace")
    case "${3:-}" in
      list) cat "$CLAUDE_MARKETS" 2>/dev/null || true ;;
      add) printf '%s\n' "${4:-}" >> "$CLAUDE_MARKET_ADD" ;;
    esac
    ;;
  "plugin install")
    id="${3:-}"
    file="$HOME/.claude/plugins/installed_plugins.json"
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || printf '{"plugins":{}}\n' > "$file"
    jq --arg p "$id" '.plugins = ((.plugins // {}) + {($p): {}})' "$file" \
      > "$file.tmp" && mv "$file.tmp" "$file"
    ;;
esac
exit 0
FAKE
chmod +x "$FAKEBIN/claude"
for t in node npx codex opencode; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
rc=0
out="$("$DOTS" skills sync 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "dots skills sync failed: $out"
grep -qF 'plugin marketplace add michael-denyer/pstack-claude' "$CLAUDE_LOG" \
  || fail "skills sync did not add the missing marketplace"
grep -qF 'plugin install pstack@pstack-claude' "$CLAUDE_LOG" \
  || fail "skills sync did not install the missing Claude plugin"
eq_install_count="$(grep -c 'plugin install' "$CLAUDE_LOG" || true)"
[ "$eq_install_count" -eq 1 ] \
  || fail "skills sync installed already-present plugins ($eq_install_count calls)"

# 6. npm below 11.10.0 is upgraded by dots install's helper.
npm_gate() { # version
  (
    eval "$(sed -n '/^# BEGIN version_ge$/,/^# END version_ge$/p' "$DOTS")"
    eval "$(sed -n '/^# BEGIN npm_cooldown_upgrade$/,/^# END npm_cooldown_upgrade$/p' "$DOTS")"
    declare -F npm_needs_upgrade >/dev/null || exit 3
    npm_needs_upgrade "$1"
  )
}
npm_gate 10.9.9 || fail "npm 10.9.9 needs the upgrade"
if npm_gate 11.10.0; then fail "npm 11.10.0 must not need the upgrade"; fi

NPM_LOG="$TMPROOT/npm-upgrade.log"
: > "$NPM_LOG"
cat > "$FAKEBIN/npm" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$NPM_LOG"
[ "\${1:-}" = "--version" ] && printf '11.10.0\n'
exit 0
FAKE
chmod +x "$FAKEBIN/npm"
run_npm_helper() { # version
  (
    eval "$(sed -n '/^# BEGIN version_ge$/,/^# END version_ge$/p' "$DOTS")"
    eval "$(sed -n '/^# BEGIN npm_cooldown_upgrade$/,/^# END npm_cooldown_upgrade$/p' "$DOTS")"
    # shellcheck disable=SC2329 # called by ensure_npm_version
    info() { printf '%s\n' "$*"; }
    # shellcheck disable=SC2329 # called by ensure_npm_version
    warn() { printf 'WARN: %s\n' "$*" >&2; }
    # shellcheck disable=SC2329 # called by ensure_npm_version
    fail() { printf 'FAILED: %s\n' "$*"; }
    ensure_npm_version "$1"
  )
}
run_npm_helper 10.9.9 > "$TMPROOT/npm-old.out" 2>&1
grep -qF 'install -g npm@11' "$NPM_LOG" || fail "old npm was not upgraded"
contains "npm updated to 11.10.0" "$(cat "$TMPROOT/npm-old.out")" "npm upgrade report"
: > "$NPM_LOG"
run_npm_helper 11.10.0 > /dev/null 2>&1
[ ! -s "$NPM_LOG" ] || fail "new enough npm must not be upgraded"

printf 'dots doctor --local tests passed\n'
