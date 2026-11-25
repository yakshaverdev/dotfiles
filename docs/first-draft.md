# First draft

`first-draft` is a skill for every agent on these machines. Its goal: the first code review of a change finds no P1. A P1 is a defect that must be fixed before merge. The skill is in [`skills/first-draft/`](../skills/first-draft/SKILL.md), and its state is kept by `dots draft`.

## Why first reviews find P1s

The author writes code against an incomplete model of the system. The gaps fall into a few classes: unwritten contracts, lifecycle transitions, ordering, partial failure, callers that nobody listed, and tests that share the author's assumptions. A review finds these late, and only by sampling. An LLM reviewer also finds something new each round, so review loops do not end.

The skill moves the work earlier. It writes a spec, attacks the spec, writes the tests from the spec, and only then writes the code. Every review uses the same 11 dimensions ([`dimensions.md`](../skills/first-draft/dimensions.md)). Every finding gets a verdict, so the next round does not raise it again.

## Who does what

| Step | Who |
|---|---|
| Choose the tier, read the code, write the spec | Claude |
| Review the spec (Tier 2) | Codex, through `dots draft review <id> spec` |
| Write the tests from the spec (Tier 2) | `oc-worker` on `opencode-go/kimi-k3.1-pro` |
| Write the code; the tests are protected | `oc-worker` on its default model |
| Review the code for correctness and cost | Codex, through `dots draft review <id> code` |
| Triage each finding: accept or reject, with a reason | Claude |
| Close the change, and offer a learning pass every 10 changes | Claude, with your approval for each edit |

Tier 0 (no behaviour change, a one-line fix, a rename, a config value) skips the skill. Tier 2 is a change that touches lifecycle, concurrency, persisted data, an external contract, security or cost. Tier 1 is every other behaviour change: it has a short spec, no spec review and no separate test writer.

Code review stops after a round with no accepted P1 or P2, or after round 3. Then Claude reports to you.

## `dots draft`

| Command | What it does |
|---|---|
| `dots draft new <slug> --tier 1\|2` | Open a change in the current repo and copy the spec template |
| `dots draft review <id> spec\|code` | Run a fresh, read-only Codex review; findings come back as JSON |
| `dots draft triage <id> <finding> accept <step> <reason>` | Accept a finding, with the step that should have caught it |
| `dots draft triage <id> <finding> reject <reason>` | Reject a finding, with a reason the next reviewer can check |
| `dots draft protect <id> <files>` / `check <id>` | Record the protected tests, then fail if one changed |
| `dots draft close <id> merged\|abandoned` | Close the change |
| `dots draft list`, `show <id>` | Show the changes and their findings |
| `dots draft report [--all-hosts]` | Show the measure |
| `dots draft classes`, `learned` | Group the accepted findings for a learning pass, and record that a pass happened |
| `dots draft scrub <files>` | Fail if a file names a client repo, path or context |

A review runs `codex exec --sandbox read-only --ephemeral --output-schema`. Claude starts it in the background and gets a notice when it ends.

## The measure

`dots draft report` shows the share of changes whose first code review has no accepted P1. The target is 100 %. It also shows the review rounds, the reviewer precision (accepted findings divided by triaged findings) and the findings without a verdict, so extra review passes cannot reach the target. Each round records the version of its brief, so a change to a brief is visible in the numbers.

## Learning

A learning pass groups the accepted findings by dimension and by the step that should have caught them. Claude proposes class-level edits to `dimensions.md`, the spec template or a brief, one at a time, and you approve each one. A lesson names a class ("the lifecycle of a third-party session is not specified"), never an incident.

## Privacy

The ledger holds client data: repo names, paths and findings. It stays in `~/.local/state/first-draft/` (mode 700) on each machine and never goes into git. Each machine keeps its own ledger, and `dots draft report --all-hosts` reads the other one over ssh. The pre-commit hook runs `dots draft scrub` on staged files under `skills/`. Set `SKIP_FIRST_DRAFT_SCRUB=1` to skip it.

## Where it runs

`dots skills sync` links `skills/first-draft` into `~/.agents/skills` (Codex and OpenCode) and `~/.claude/skills` (Claude Code). `dots doctor` checks both links. The steps are the same in terminal Claude and in T3 Code, on the laptop and on the VPS. Run a change on the machine that holds its checkout.
