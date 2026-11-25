#!/usr/bin/env bash
# Test `dots draft` end to end without network access or the real codex/ssh.
#
# A temp HOME holds the state, and stubs on PATH stand in for codex and ssh.
# The skill folder is a fixture, so the brief templates and dimensions are
# known text. Every step sets FIRST_DRAFT_NOW so row order is deterministic.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAFT="$ROOT/bin/dots-draft"
REAL_PATH="$PATH"
REAL_HOME="$HOME"
REAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME-}"
REAL_XDG_STATE_HOME="${XDG_STATE_HOME-}"
REAL_XDG_DATA_HOME="${XDG_DATA_HOME-}"
REAL_XDG_CACHE_HOME="${XDG_CACHE_HOME-}"
JQ_BIN="$(command -v jq || true)"
[ -n "$JQ_BIN" ] || { printf 'FAIL: jq is required\n' >&2; exit 1; }

# pwd -P: macOS mktemp gives /var/..., while tools may report /private/var/...
TMPROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dots-draft-test.XXXXXX")" && pwd -P)"
cleanup() {
  if [ "${KEEP_TMP:-0}" = "1" ]; then
    printf 'kept: %s\n' "$TMPROOT" >&2
  else
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT

export HOME="$TMPROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
unset DOT_MACHINE

FAKEBIN="$TMPROOT/bin"
mkdir -p "$HOME" "$FAKEBIN" "$XDG_CONFIG_HOME" "$TMPROOT/tmp"
export PATH="$FAKEBIN:$REAL_PATH"

# jq is a mise shim here, so a wrapper restores the caller's HOME for it while
# the script under test runs with the temp HOME.
real_xdg_dir() { # value default-subdir
  if [ -n "$1" ] && [ -d "$1" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$REAL_HOME/$2"
  fi
}
cat > "$FAKEBIN/jq" <<WRAP
#!/usr/bin/env bash
HOME=$(printf '%q' "$REAL_HOME")
XDG_CONFIG_HOME=$(printf '%q' "$(real_xdg_dir "$REAL_XDG_CONFIG_HOME" .config)")
XDG_STATE_HOME=$(printf '%q' "$(real_xdg_dir "$REAL_XDG_STATE_HOME" .local/state)")
XDG_DATA_HOME=$(printf '%q' "$(real_xdg_dir "$REAL_XDG_DATA_HOME" .local/share)")
XDG_CACHE_HOME=$(printf '%q' "$(real_xdg_dir "$REAL_XDG_CACHE_HOME" .cache)")
export HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME
exec $(printf '%q' "$JQ_BIN") "\$@"
WRAP
chmod +x "$FAKEBIN/jq"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

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

ok() { # label command...
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || fail "$label exited $rc: $out"
  printf '%s\n' "$out"
}

fails() { # label command...
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "$label should have failed: $out"
  printf '%s\n' "$out"
}

in_dir() { # dir command...
  local d="$1"
  shift
  ( cd "$d" && "$@" )
}

now() { export FIRST_DRAFT_NOW="$1"; }

jget() { # json filter
  printf '%s' "$1" | jq -r "$2"
}

# ── Fixtures ───────────────────────────────────────────────────────────────
SKILL="$TMPROOT/skill"
mkdir -p "$SKILL/briefs" "$SKILL/schemas"
cat > "$SKILL/briefs/spec-review.md" <<'EOF'
---
brief: spec-review
version: 3
---

SPEC REVIEW BODY
EOF
cat > "$SKILL/briefs/code-review.md" <<'EOF'
---
brief: code-review
version: 3
---

CODE REVIEW BODY
EOF
printf 'DIMENSIONS BODY\n' > "$SKILL/dimensions.md"
printf 'SPEC TEMPLATE\n' > "$SKILL/spec-template.md"
cp "$ROOT/skills/first-draft/schemas/findings.schema.json" "$SKILL/schemas/"

export FIRST_DRAFT_STATE="$TMPROOT/state"
export FIRST_DRAFT_SKILL="$SKILL"
export FIRST_DRAFT_HOST=testhost
export FIRST_DRAFT_HOSTS_FILE="$TMPROOT/hosts"
export FIRST_DRAFT_CONTEXTS_FILE="$TMPROOT/contexts"
export FIRST_DRAFT_CODEX="$FAKEBIN/codex"
export FAKE_CODEX_ARGS="$TMPROOT/codex-args"
export FAKE_CODEX_STDIN="$TMPROOT/codex-stdin"
export FAKE_CODEX_EXIT=0
export FAKE_CODEX_OUTPUT=""
export FAKE_SSH_LOG="$TMPROOT/ssh-log"
export FAKE_SSH_LEDGER="$TMPROOT/peer-ledger.jsonl"
export FAKE_SSH_EXIT=0

cat > "$FAKEBIN/codex" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'codex-cli 9.9.9\n'
  exit 0
fi
printf '%s\n' "$*" >> "${FAKE_CODEX_ARGS:?}"
shift || true
positionals=0
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -C|-c|-m|--output-schema|--sandbox)
      if [ "$#" -lt 2 ]; then
        echo 'unexpected argument' >&2
        exit 2
      fi
      shift 2
      ;;
    -o)
      if [ "$#" -lt 2 ]; then
        echo 'unexpected argument' >&2
        exit 2
      fi
      out="$2"
      shift 2
      ;;
    --) shift ;;
    -) positionals=$((positionals + 1)); shift ;;
    -*) shift ;;
    *)
      positionals=$((positionals + 1))
      shift
      ;;
  esac
done
if [ "$positionals" -gt 1 ]; then
  echo 'unexpected argument' >&2
  exit 2
fi
cat > "${FAKE_CODEX_STDIN:?}"
printf 'model: fake-model\n'
if [ -n "${FAKE_CODEX_OUTPUT:-}" ] && [ -n "$out" ]; then
  cp "$FAKE_CODEX_OUTPUT" "$out"
fi
exit "${FAKE_CODEX_EXIT:-0}"
FAKE
chmod +x "$FAKEBIN/codex"

cat > "$FAKEBIN/ssh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_SSH_LOG:?}"
if [ "${FAKE_SSH_EXIT:-0}" != "0" ]; then
  exit "$FAKE_SSH_EXIT"
fi
if [ -n "${FAKE_SSH_LEDGER:-}" ] && [ -f "$FAKE_SSH_LEDGER" ]; then
  cat "$FAKE_SSH_LEDGER"
fi
exit 0
FAKE
chmod +x "$FAKEBIN/ssh"

REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
printf 'hello\n' > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm init
git -C "$REPO" remote add origin git@github.com:acme-corp/widget-service.git
BASE="$(git -C "$REPO" rev-parse HEAD)"

STATE1="$FIRST_DRAFT_STATE"

# ── 1. new ─────────────────────────────────────────────────────────────────
NOTREPO="$TMPROOT/not-a-repo"
mkdir -p "$NOTREPO"
out="$(fails "new outside a git repo" in_dir "$NOTREPO" "$DRAFT" new alpha --tier 1)"
contains "not inside a git repository" "$out" "new outside a git repo names the problem"

now 2026-11-25T12:00:00Z
ID="retry-20261125T120000"
CDIR="$STATE1/changes/$ID"
out="$(ok "new" in_dir "$REPO" "$DRAFT" new retry --tier 2)"
contains "change  $ID" "$out" "new prints the change id"
contains "folder  $CDIR" "$out" "new prints the folder"
contains "spec    $CDIR/spec.md" "$out" "new prints the spec path"
contains "SPEC TEMPLATE" "$(cat "$CDIR/spec.md")" "spec.md comes from the template"
contains '"tier":2' "$(cat "$CDIR/meta.json")" "meta.json has the tier"
[ "$(jget "$(cat "$CDIR/meta.json")" .repo)" = "$REPO" ] || fail "meta.json repo"
[ "$(jget "$(cat "$CDIR/meta.json")" .base)" = "$BASE" ] || fail "meta.json base"
if stat -f '%Lp' / >/dev/null 2>&1; then
  mode="$(stat -f '%Lp' "$STATE1")"
else
  mode="$(stat -c '%a' "$STATE1")"
fi
[ "$mode" = "700" ] || fail "state folder mode is $mode, expected 700"
[ "$(jq -s -r '[.[] | select(.type=="change")] | last | .tier' "$STATE1/ledger.jsonl")" = "2" ] \
  || fail "ledger change row has no tier"
[ "$(jq -s -r '[.[] | select(.type=="change")] | last | .base' "$STATE1/ledger.jsonl")" = "$BASE" ] \
  || fail "ledger change row has no base"

# A repo with no commits has no base, and `git rev-parse HEAD` prints "HEAD".
EMPTYREPO="$TMPROOT/empty-repo"
mkdir -p "$EMPTYREPO"
git -C "$EMPTYREPO" init -q
ok "new with no commits" in_dir "$EMPTYREPO" "$DRAFT" new empty --tier 1 >/dev/null
[ "$(jget "$(cat "$STATE1/changes/empty-20261125T120000/meta.json")" .base)" = "" ] \
  || fail "a repo with no commits must have an empty base"

# ── 2. review spec ─────────────────────────────────────────────────────────
cat > "$TMPROOT/spec-findings.json" <<'EOF'
{"summary":"Two spec problems.","findings":[
 {"severity":"P1","dimension":"lifecycle","title":"No close step","evidence":"spec.md:3","scenario":"a change never closes","fix":"add close"},
 {"severity":"P2","dimension":"inputs","title":"Empty slug allowed","evidence":"spec.md:9","scenario":"empty slug","fix":"validate"}
]}
EOF
export FAKE_CODEX_OUTPUT="$TMPROOT/spec-findings.json"
: > "$FAKE_CODEX_ARGS"
now 2026-11-25T12:01:00Z
out="$(ok "review spec" "$DRAFT" review "$ID" spec)"
contains "spec review round 1 of $ID: 2 findings (P1 1, P2 1, P3 0)" "$out" "spec round header"
contains "s1-1" "$out" "first spec finding id"
contains "s1-2" "$out" "second spec finding id"
contains "summary: Two spec problems." "$out" "review prints the summary"

round="$(jq -s '[.[] | select(.type=="round" and .kind=="spec" and .round==1)] | last' "$STATE1/ledger.jsonl")"
[ "$(jget "$round" .brief_version)" = "3" ] || fail "round brief_version"
[ "$(jget "$round" .reviewer_version)" = "codex-cli 9.9.9" ] || fail "round reviewer_version"
[ "$(jget "$round" .model)" = "fake-model" ] || fail "round model"
[ "$(jget "$round" .findings)" = "2" ] || fail "round findings count"

BRIEF="$CDIR/rounds/spec-1/brief.md"
brief="$(cat "$BRIEF")"
contains "SPEC REVIEW BODY" "$brief" "brief has the template body"
contains "SPEC TEMPLATE" "$brief" "brief has the spec text"
contains "DIMENSIONS BODY" "$brief" "brief has the dimensions"
not_contains "version: 3" "$brief" "brief drops the front matter"
not_contains "brief: spec-review" "$brief" "brief drops the front matter header"

args="$(cat "$FAKE_CODEX_ARGS")"
contains "--sandbox read-only" "$args" "codex gets read-only sandbox"
contains "--ephemeral" "$args" "codex gets --ephemeral"
contains "--skip-git-repo-check" "$args" "codex gets --skip-git-repo-check"
contains "--output-schema" "$args" "codex gets --output-schema"
contains "-C $REPO" "$args" "codex runs in the change repo"
contains "SPEC REVIEW BODY" "$(cat "$FAKE_CODEX_STDIN")" "codex reads the brief on stdin"

# ── 3. refusal before triage, then earlier rounds ──────────────────────────
out="$(fails "review spec before triage" "$DRAFT" review "$ID" spec)"
contains "round 1 has untriaged findings" "$out" "untriaged refusal names the round"

now 2026-11-25T12:02:00Z
out="$(ok "triage accept" "$DRAFT" triage "$ID" s1-1 accept spec "clarify the close step")"
contains "s1-1: accepted" "$out" "accept output"
now 2026-11-25T12:03:00Z
out="$(ok "triage reject" "$DRAFT" triage "$ID" s1-2 reject "not a real problem")"
contains "s1-2: rejected" "$out" "reject output"

now 2026-11-25T12:04:00Z
out="$(ok "review spec round 2" "$DRAFT" review "$ID" spec)"
contains "spec review round 2 of $ID" "$out" "round 2 runs after triage"
brief="$(cat "$CDIR/rounds/spec-2/brief.md")"
contains "## Earlier rounds" "$brief" "round 2 brief has the earlier rounds section"
contains "clarify the close step" "$brief" "round 2 brief has the accept reason"
contains "not a real problem" "$brief" "round 2 brief has the reject reason"

# ── 4. failed rounds leave no rows and reuse the round number ──────────────
before="$(wc -l < "$STATE1/ledger.jsonl" | tr -d ' ')"
export FAKE_CODEX_EXIT=1
now 2026-11-25T12:10:00Z
out="$(fails "codex exit 1" "$DRAFT" review "$ID" code)"
contains "codex review failed" "$out" "codex failure is reported"
[ -d "$CDIR/failed/code-1-20261125T121000" ] || fail "failed folder for codex exit 1"
[ "$(wc -l < "$STATE1/ledger.jsonl" | tr -d ' ')" = "$before" ] || fail "failed run added ledger rows"
[ ! -e "$CDIR/review.lock" ] || fail "lock left after a failed review"
export FAKE_CODEX_EXIT=0

printf 'not json\n' > "$TMPROOT/bad.json"
export FAKE_CODEX_OUTPUT="$TMPROOT/bad.json"
now 2026-11-25T12:11:00Z
out="$(fails "invalid findings JSON" "$DRAFT" review "$ID" code)"
contains "codex review failed" "$out" "invalid JSON is reported"
[ -d "$CDIR/failed/code-1-20261125T121100" ] || fail "failed folder for invalid JSON"
[ "$(wc -l < "$STATE1/ledger.jsonl" | tr -d ' ')" = "$before" ] || fail "invalid JSON run added ledger rows"
[ ! -e "$CDIR/review.lock" ] || fail "lock left after an invalid JSON review"

cat > "$TMPROOT/bad-dimension.json" <<'EOF'
{"summary":"x","findings":[{"severity":"P1","dimension":"nope","title":"t","evidence":"e","scenario":"s","fix":"f"}]}
EOF
export FAKE_CODEX_OUTPUT="$TMPROOT/bad-dimension.json"
now 2026-11-25T12:12:00Z
out="$(fails "unknown dimension" "$DRAFT" review "$ID" code)"
contains "codex review failed" "$out" "unknown dimension is reported"
[ -d "$CDIR/failed/code-1-20261125T121200" ] || fail "failed folder for unknown dimension"
[ "$(wc -l < "$STATE1/ledger.jsonl" | tr -d ' ')" = "$before" ] || fail "bad dimension run added ledger rows"
[ ! -e "$CDIR/review.lock" ] || fail "lock left after a bad dimension review"

cat > "$TMPROOT/code-findings.json" <<'EOF'
{"summary":"One code problem.","findings":[
 {"severity":"P2","dimension":"verification","title":"No test for close","evidence":"lib/retry.dart:12","scenario":"a regression slips through","fix":"add a test"}
]}
EOF
export FAKE_CODEX_OUTPUT="$TMPROOT/code-findings.json"
now 2026-11-25T12:13:00Z
out="$(ok "code review round 1" "$DRAFT" review "$ID" code)"
contains "code review round 1 of $ID: 1 findings" "$out" "good run reuses round 1"
contains "c1-1" "$out" "code finding id"
[ ! -e "$CDIR/review.lock" ] || fail "lock left after a successful review"

# ── 4b. interrupted rounds, locks and a missing codex ──────────────────────
now 2026-11-25T12:30:00Z
IID="interrupt-20261125T123000"
ICDIR="$STATE1/changes/$IID"
ok "new interrupt" in_dir "$REPO" "$DRAFT" new interrupt --tier 1 >/dev/null
mkdir -p "$ICDIR/rounds/code-1"
printf 'stale brief\n' > "$ICDIR/rounds/code-1/brief.md"
now 2026-11-25T12:31:00Z
out="$(ok "review after an interrupted round" "$DRAFT" review "$IID" code)"
contains "code review round 1 of $IID" "$out" "interrupted review records round 1"
contains "moved an interrupted round to" "$out" "interrupted round is moved"
interrupted_ok=0
for d in "$ICDIR/failed"/code-1-*-interrupted*; do
  [ -e "$d" ] && interrupted_ok=1
done
[ "$interrupted_ok" -eq 1 ] || fail "interrupted round folder name"
[ ! -e "$ICDIR/review.lock" ] || fail "lock left after the interrupted-round review"

now 2026-11-25T12:32:00Z
before="$(wc -l < "$STATE1/ledger.jsonl" | tr -d ' ')"
mkdir "$ICDIR/review.lock"
out="$(fails "review with a lock" "$DRAFT" review "$IID" spec)"
contains "a review of $IID is already running" "$out" "lock error names the change"
contains "$ICDIR/review.lock" "$out" "lock error names the lock"
[ "$(wc -l < "$STATE1/ledger.jsonl" | tr -d ' ')" = "$before" ] || fail "locked review wrote ledger rows"
[ ! -e "$ICDIR/rounds/spec-1" ] || fail "locked review made a round folder"
[ -d "$ICDIR/review.lock" ] || fail "locked review removed a foreign lock"
rmdir "$ICDIR/review.lock"

out="$(fails "missing codex" env FIRST_DRAFT_CODEX=/nonexistent "$DRAFT" review "$IID" spec)"
contains "codex not found; install it or set FIRST_DRAFT_CODEX" "$out" "missing codex is reported"
[ ! -e "$ICDIR/review.lock" ] || fail "missing codex left a lock"

# ── 5. triage validation and the severity override ────────────────────────
out="$(fails "unknown finding" "$DRAFT" triage "$ID" zzz-9 accept spec "reason")"
contains "unknown finding" "$out" "unknown finding is rejected"
out="$(fails "unknown step" "$DRAFT" triage "$ID" s1-1 accept nope "reason")"
contains "unknown step" "$out" "unknown step is rejected"
out="$(fails "unknown verdict" "$DRAFT" triage "$ID" s1-1 maybe "reason")"
contains "verdict must be accept or reject" "$out" "unknown verdict is rejected"
out="$(fails "empty reason" "$DRAFT" triage "$ID" s1-1 accept spec)"
contains "reason is required" "$out" "empty reason is rejected"

now 2026-11-25T12:20:00Z
out="$(ok "severity override" "$DRAFT" triage --severity P2 "$ID" s2-1 accept tests "override it")"
contains "s2-1: accepted" "$out" "severity override triage output"
[ "$(jq -s -r '[.[] | select(.type=="triage" and .finding=="s2-1")] | last | .severity' "$STATE1/ledger.jsonl")" = "P2" ] \
  || fail "triage severity override not stored"

# ── 6. protect and check ───────────────────────────────────────────────────
mkdir -p "$REPO/test"
printf 'first\n' > "$REPO/test/widget_test.dart"
out="$(ok "protect" "$DRAFT" protect "$ID" test/widget_test.dart)"
contains "protected 1 test file(s)" "$out" "protect output"
out="$(ok "check unchanged" "$DRAFT" check "$ID")"
contains "protected tests unchanged (1)" "$out" "check unchanged output"
printf 'second\n' > "$REPO/test/widget_test.dart"
out="$(fails "check changed" "$DRAFT" check "$ID")"
contains "changed: test/widget_test.dart" "$out" "check reports a changed file"
rm "$REPO/test/widget_test.dart"
out="$(fails "check missing" "$DRAFT" check "$ID")"
contains "missing: test/widget_test.dart" "$out" "check reports a missing file"

# ── 7. report over two changes ─────────────────────────────────────────────
export FIRST_DRAFT_STATE="$TMPROOT/state2"

now 2026-11-27T12:00:00Z
AID="alpha-20261127T120000"
ok "new alpha" in_dir "$REPO" "$DRAFT" new alpha --tier 2 >/dev/null

cat > "$TMPROOT/a1.json" <<'EOF'
{"summary":"one major risk","findings":[
 {"severity":"P1","dimension":"lifecycle","title":"No close path","evidence":"lib/retry.dart:12","scenario":"change never closes","fix":"add close"},
 {"severity":"P2","dimension":"inputs","title":"Empty slug accepted","evidence":"spec.md:4","scenario":"empty input","fix":"validate"}
]}
EOF
export FAKE_CODEX_OUTPUT="$TMPROOT/a1.json"
now 2026-11-27T12:01:00Z
out="$(ok "review alpha code 1" "$DRAFT" review "$AID" code)"
contains "code review round 1 of $AID: 2 findings" "$out" "alpha round 1"
now 2026-11-27T12:02:00Z
ok "triage alpha p1" "$DRAFT" triage "$AID" c1-1 accept implementation "add the close step" >/dev/null
now 2026-11-27T12:03:00Z
ok "triage alpha p2" "$DRAFT" triage "$AID" c1-2 reject "no input path reaches it" >/dev/null

printf '{"summary":"clean","findings":[]}\n' > "$TMPROOT/empty.json"
export FAKE_CODEX_OUTPUT="$TMPROOT/empty.json"
now 2026-11-27T12:04:00Z
out="$(ok "review alpha code 2" "$DRAFT" review "$AID" code)"
contains "code review round 2 of $AID: 0 findings" "$out" "alpha round 2"

now 2026-11-27T12:10:00Z
BID="beta-20261127T121000"
ok "new beta" in_dir "$REPO" "$DRAFT" new beta --tier 1 >/dev/null
cat > "$TMPROOT/b1.json" <<'EOF'
{"summary":"rejected risk","findings":[
 {"severity":"P1","dimension":"security","title":"Spec leaks a token","evidence":"lib/queue.dart:3","scenario":"token in spec","fix":"redact"}
]}
EOF
export FAKE_CODEX_OUTPUT="$TMPROOT/b1.json"
now 2026-11-27T12:11:00Z
out="$(ok "review beta code 1" "$DRAFT" review "$BID" code)"
contains "code review round 1 of $BID: 1 findings" "$out" "beta round 1"
now 2026-11-27T12:12:00Z
ok "triage beta p1" "$DRAFT" triage "$BID" c1-1 reject "spec already covers it" >/dev/null

report="$(ok "report json" "$DRAFT" report --json)"
[ "$(jget "$report" .changes)" = "2" ] || fail "report changes"
[ "$(jget "$report" .tier1)" = "1" ] || fail "report tier1"
[ "$(jget "$report" .tier2)" = "1" ] || fail "report tier2"
[ "$(jget "$report" .zero_p1_first)" = "1" ] || fail "report zero_p1_first"
[ "$(jget "$report" .zero_p1_rate)" = "0.5" ] || fail "report zero_p1_rate"
[ "$(jget "$report" .mean_p1_first)" = "0.5" ] || fail "report mean_p1_first"
[ "$(jget "$report" .code_rounds_mean)" = "1.5" ] || fail "report code_rounds_mean"
[ "$(jget "$report" .code_rounds_max)" = "2" ] || fail "report code_rounds_max"
[ "$(jget "$report" .untriaged)" = "0" ] || fail "report untriaged"
[ "$(jget "$report" .spec_rounds_mean)" = "null" ] || fail "report spec_rounds_mean"
[ "$(jget "$report" .by_brief_version[0].version)" = "3" ] || fail "report brief version"
[ "$(jget "$report" .by_brief_version[0].zero_p1)" = "1" ] || fail "report brief zero_p1"
[ "$(jget "$report" .by_brief_version[0].mean_p1)" = "0.5" ] || fail "report brief mean_p1"
[ "$(jget "$report" .by_dimension[0].dimension)" = "lifecycle" ] || fail "report dimension"
[ "$(jget "$report" .by_dimension[0].steps.implementation)" = "1" ] || fail "report dimension step"
[ "$(jget "$report" .hosts[0])" = "testhost" ] || fail "report hosts"
text="$(ok "report text" "$DRAFT" report)"
contains "first review with 0 accepted P1  1/2" "$text" "report text zero P1 line"

# ── 8. a severity override turns the accepted P1 into a P2 ─────────────────
now 2026-11-27T12:20:00Z
ok "override alpha p1" "$DRAFT" triage --severity P2 "$AID" c1-1 accept implementation "still a P2 only" >/dev/null
report="$(ok "report override" "$DRAFT" report --json)"
[ "$(jget "$report" .zero_p1_first)" = "2" ] || fail "severity override must zero both changes"

# ── 9. --since excludes every change ───────────────────────────────────────
report="$(ok "report since" "$DRAFT" report --json --since 2030-01-01)"
[ "$(jget "$report" .changes)" = "0" ] || fail "since must exclude all changes"
[ "$(jget "$report" .zero_p1_rate)" = "null" ] || fail "since zero rate must be null"
text="$(ok "report since text" "$DRAFT" report --since 2030-01-01)"
contains "no changes with a code review yet" "$text" "empty report text"

# ── 10. --all-hosts merges a peer ledger ───────────────────────────────────
cat > "$FIRST_DRAFT_HOSTS_FILE" <<'EOF'
# machine  ssh-target       repo-path
testhost   nobody@testhost  ~/repo
peer       peer@peerhost    ~/repo
EOF
cat > "$FAKE_SSH_LEDGER" <<'EOF'
{"v":1,"type":"change","change":"peer-change","host":"peer","at":"2026-11-27T12:30:00Z","tier":1,"repo":"/srv/peer-repo","origin":"","base":""}
{"v":1,"type":"round","change":"peer-change","host":"peer","at":"2026-11-27T12:31:00Z","kind":"code","round":1,"brief":"code-review","brief_version":"3","reviewer":"codex","reviewer_version":"","model":"","findings":0}
EOF
export FAKE_SSH_EXIT=0
: > "$FAKE_SSH_LOG"
report="$(ok "report all hosts" "$DRAFT" report --json --all-hosts)"
[ "$(jget "$report" .changes)" = "3" ] || fail "all-hosts must count the peer change"
ssh_log="$(cat "$FAKE_SSH_LOG")"
contains "peer@peerhost" "$ssh_log" "ssh runs for the peer"
not_contains "nobody@testhost" "$ssh_log" "ssh skips the local host"

export FAKE_SSH_EXIT=1
rc=0
out="$("$DRAFT" report --json --all-hosts 2>"$TMPROOT/ssh-err")" || rc=$?
[ "$rc" -eq 0 ] || fail "report must exit 0 when a peer is unreachable"
contains "could not read the ledger on peer" "$(cat "$TMPROOT/ssh-err")" "unreachable peer warning"
[ "$(jget "$out" .changes)" = "2" ] || fail "unreachable peer must be skipped"
export FAKE_SSH_EXIT=0

# ── 11. classes, learned and closed_since_learn ────────────────────────────
classes="$(ok "classes" "$DRAFT" classes)"
contains "lifecycle (1)" "$classes" "classes lists the dimension"
contains "implementation (1)" "$classes" "classes lists the step"
contains "c1-1  $AID" "$classes" "classes lists the finding"

now 2026-11-27T12:50:00Z
ok "close beta" "$DRAFT" close "$BID" merged >/dev/null
now 2026-11-27T12:51:00Z
out="$(ok "learned" "$DRAFT" learned "first pass")"
contains "learning pass recorded at 2026-11-27T12:51:00Z" "$out" "learned output"
classes="$(ok "classes after learn" "$DRAFT" classes)"
contains "(0 findings)" "$classes" "learned hides earlier accepted findings"

now 2026-11-27T12:52:00Z
ok "close alpha" "$DRAFT" close "$AID" merged >/dev/null
report="$(ok "report closed" "$DRAFT" report --json)"
[ "$(jget "$report" .closed_since_learn)" = "1" ] || fail "closed_since_learn must count only later closes"

# ── 12. scrub ──────────────────────────────────────────────────────────────
cat > "$FIRST_DRAFT_CONTEXTS_FILE" <<'EOF'
# context file
acme  proj-1  strict  *github.com[:/]acme-corp/*
EOF
printf 'uses widget-service here\n' > "$TMPROOT/scrub-bad.md"
out="$(fails "scrub repo basename" "$DRAFT" scrub "$TMPROOT/scrub-bad.md")"
contains 'names "widget-service"' "$out" "scrub names the repo basename"

printf 'see lib/retry.dart for details\n' > "$TMPROOT/scrub-evidence.md"
out="$(fails "scrub evidence path" "$DRAFT" scrub "$TMPROOT/scrub-evidence.md")"
contains 'names "lib/retry.dart"' "$out" "scrub names an evidence path"

# Only path-like evidence tokens are terms; the bare stem "deploy" is common.
jq -n -c --arg ch "$AID" \
  '{v:1,type:"finding",change:$ch,host:"testhost",at:"2026-11-27T12:55:00Z",
    kind:"code",round:9,id:"c9-1",severity:"P3",dimension:"resources",
    title:"deploy evidence",evidence:"B3, cmdrunner/deploy.py:6-9",
    scenario:"s",fix:"f"}' >> "$FIRST_DRAFT_STATE/ledger.jsonl"
printf 'deploy.py is here\n' > "$TMPROOT/scrub-deploy-ext.md"
out="$(fails "scrub evidence extension" "$DRAFT" scrub "$TMPROOT/scrub-deploy-ext.md")"
contains 'names "deploy.py"' "$out" "scrub names an evidence basename"
printf 'cmdrunner/deploy.py is here\n' > "$TMPROOT/scrub-deploy-path.md"
out="$(fails "scrub evidence token" "$DRAFT" scrub "$TMPROOT/scrub-deploy-path.md")"
contains 'names "cmdrunner/deploy.py"' "$out" "scrub names the full evidence token"
printf 'the deploy step\n' > "$TMPROOT/scrub-deploy-word.md"
out="$(ok "scrub deploy stem" "$DRAFT" scrub "$TMPROOT/scrub-deploy-word.md")"
contains "scrub: ok" "$out" "a common evidence stem does not fail the scrub"

printf 'client acme project\n' > "$TMPROOT/scrub-context.md"
out="$(fails "scrub context" "$DRAFT" scrub "$TMPROOT/scrub-context.md")"
contains 'names "acme"' "$out" "scrub names a context"

printf 'nothing to see here\n' > "$TMPROOT/scrub-clean.md"
out="$(ok "scrub clean" "$DRAFT" scrub "$TMPROOT/scrub-clean.md")"
contains "scrub: ok" "$out" "clean file passes"
out="$(ok "scrub allowed" "$DRAFT" scrub --allow widget-service "$TMPROOT/scrub-bad.md")"
contains "scrub: ok" "$out" "--allow lets a term pass"

# ── 13. list and show ──────────────────────────────────────────────────────
list="$(ok "list" "$DRAFT" list)"
contains "$AID" "$list" "list shows alpha"
contains "$BID" "$list" "list shows beta"
contains "tier 2" "$list" "list shows the tier"
contains "merged" "$list" "list shows the close outcome"
contains "code rounds 2" "$list" "list shows the code round count"

show="$(ok "show" "$DRAFT" show "$AID")"
contains "$AID" "$show" "show names the change"
contains "code round 1" "$show" "show lists the code round"
contains "c1-1" "$show" "show lists the finding"
contains "No close path" "$show" "show lists the finding title"
contains "accept implementation" "$show" "show lists the triage verdict"

# The real skill folder: every file that `review` and `new` read exists, each
# brief has a version, and the three lists of dimensions agree (the schema
# that Codex fills, the list this script validates, and dimensions.md).
REAL_SKILL="$ROOT/skills/first-draft"
for f in SKILL.md dimensions.md spec-template.md schemas/findings.schema.json \
    briefs/spec-review.md briefs/code-review.md briefs/test-writer.md \
    briefs/implementer.md; do
  [ -f "$REAL_SKILL/$f" ] || fail "skills/first-draft/$f is missing"
done
for f in spec-review code-review test-writer implementer; do
  sed -n '2,4p' "$REAL_SKILL/briefs/$f.md" | grep -q '^version: [0-9][0-9]*$' \
    || fail "briefs/$f.md has no version in its front matter"
done
schema_dims="$(jq -r '.properties.findings.items.properties.dimension.enum[]' \
  "$REAL_SKILL/schemas/findings.schema.json" | sort | tr '\n' ' ')"
script_dims="$(sed -n "s/^DIMS_JSON='\(.*\)'$/\1/p" "$DRAFT" | jq -r '.[]' \
  | sort | tr '\n' ' ')"
# shellcheck disable=SC2016 # the backticks are literal Markdown
doc_dims="$(sed -n 's/^### `\([a-z-]*\)`.*/\1/p' "$REAL_SKILL/dimensions.md" \
  | sort | tr '\n' ' ')"
[ -n "$schema_dims" ] || fail "no dimensions in the schema"
[ "$schema_dims" = "$script_dims" ] \
  || fail "schema and bin/dots-draft dimensions differ: $schema_dims / $script_dims"
[ "$schema_dims" = "$doc_dims" ] \
  || fail "schema and dimensions.md differ: $schema_dims / $doc_dims"
grep -q '^name: first-draft$' "$REAL_SKILL/SKILL.md" \
  || fail "SKILL.md name does not match its folder"

printf 'dots draft tests passed\n'
