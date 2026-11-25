---
name: first-draft
description: "Spec-first workflow that makes the first draft of a code change pass its first review with no P1: tier, spec, Codex spec review, independent tests, oc-worker implementation, Codex code review, triage, ledger. Use before you implement a feature or any behaviour change, when the user says 'first draft', or for a learning pass or the first-review report."
---

# First draft

The goal: the first Codex code review of a change finds no P1. The method: find the gaps before the code exists. Write a spec, attack the spec, write tests from the spec, and only then write the code.

Roles:

- **You (the orchestrator)** classify the change, write the spec, triage every finding, and read every diff.
- **Codex** reviews the spec and the code. `dots draft review` starts each review in a fresh, read-only session.
- **The test writer** is `oc-worker` with the model `opencode-go/kimi-k3.1-pro`. It writes the tests from the spec only.
- **The implementer** is `oc-worker` with its default model. It writes the code, and it may not edit the protected tests.

`dots draft` keeps the state of each change in a private ledger. If `dots` is not on `PATH`, use `~/.local/bin/dots`. `dots draft help` lists the commands. Run the whole change on the machine that holds its checkout.

[`dimensions.md`](dimensions.md) holds the 11 dimensions, the severity scale and the step names. Read it before step 3. Every spec, review and triage verdict uses its terms.

## 1. Tier

Choose the tier and tell the user the tier and the reason in one line. The user can override it.

- **Tier 0:** no behaviour change, or a one-line fix, a rename, a config value, docs or formatting. This skill does not apply. Stop here.
- **Tier 2:** the change touches state or lifecycle (start, stop, cancel, retry, timeout, teardown), concurrency or ordering, persisted data or partial failure, an external contract (API, schema, wire or file format, CLI), security, or cost that grows with load.
- **Tier 1:** any other behaviour change.

The trigger is the dimensions, not the size. If you are not sure, choose Tier 2.

In the target repo, run `dots draft new <slug> --tier <1|2>`. It prints the change ID and the path of `spec.md`.

## 2. Ground

Read the code that the change touches, and its callers. At Tier 2, run the pstack `blast-radius` skill on the planned change to find the users that a search does not show. If the change adds a module or moves ownership of state, you can also run pstack `architect`. If the requirement itself is unclear, use `grilling` with the user first.

Done when every user of what changes, and every implicit contract that the change relies on, has a `file:line` or a search result as evidence.

## 3. Spec

Fill `spec.md` from the template that `dots draft new` copied. Tier 1 fills the sections marked `[all tiers]`. Tier 2 fills every section.

Done when:

- every property is a statement that a test or a command can fail;
- every dimension has a row in the failure-mode table, with a required behaviour, or with `n/a` and a reason that is true;
- the open questions are answered by the user, or there are none.

## 4. Spec review (Tier 2)

Run `dots draft review <id> spec` with `run_in_background: true`, and wait for the completion notice. Then triage (see below) and fix the spec. Run another round after a round that has an accepted P1 or P2. Stop after a round with no accepted P1 or P2, or after round 2. Tell the user about any accepted finding that is still open.

## 5. Tests (Tier 2)

Fill [`briefs/test-writer.md`](briefs/test-writer.md) and send it to `oc-worker` with the model `opencode-go/kimi-k3.1-pro` and a new session ID `ses_<slug>tests_<stamp>`.

When it reports, run the tests yourself. Each new test must fail because the behaviour is missing, not because of a mistake in the test. If a test is wrong, send a fix-up brief with the same session ID. Then run `dots draft protect <id> <test files>`.

Done when every property and every failure row that names a test has a test, every test fails for the right reason, and the test files are protected.

## 6. Implement

Fill [`briefs/implementer.md`](briefs/implementer.md) and send it to `oc-worker` (default model) with a new session ID `ses_<slug>_<stamp>`. Use the same ID for every fix-up of this change.

When it reports:

1. Run `dots draft check <id>`. If a protected test changed, restore it with `git checkout -- <path>` and send a fix-up brief. If the implementer reports a wrong test, decide yourself: fix the test through the test writer's session, then run `dots draft protect` again.
2. Run the protected tests and the project's checks.
3. Read the whole diff against the spec, property by property.

Done when all three pass. The first code review must see a complete draft.

## 7. Code review

Run `dots draft review <id> code` with `run_in_background: true`, and wait for the notice. Round 1 is the measured review.

Triage every finding. Send the accepted P1 and P2 findings to the implementer as a fix-up brief with the same session ID. Give the evidence, the scenario and the agreed fix for each finding. Then repeat step 6 checks and run the next review round.

Stop after a round with no accepted P1 or P2, or after round 3. Then report to the user: the accepted findings that are still open, the P3 findings, and the first-review P1 count.

## Triage

Do this after every review round, for every finding:

1. Read the evidence yourself, in the spec or the code.
2. **Accept** a finding when its scenario can happen. Give the step that should have caught it (`dimensions.md` defines the steps). If the reviewer chose the wrong severity, set the right one with `--severity`, and say why in the reason.
3. **Reject** a finding when its scenario cannot happen or the finding is wrong. Give a reason that the next reviewer can check, such as the `file:line` that prevents the scenario.

```bash
dots draft triage [--severity P2] <id> <finding> accept <step> <reason>
dots draft triage <id> <finding> reject <reason>
```

Done when `dots draft show <id>` shows no untriaged finding. The next review round gets your verdicts and reasons.

## 8. Close

When the change is merged or abandoned, run `dots draft close <id> merged|abandoned`.

Then run `dots draft report`. If `closed since last learning pass` is 10 or more, offer the user a learning pass.

## Learning pass

1. Run `dots draft classes --all-hosts`. It groups the accepted findings since the last pass by dimension and by step.
2. For each class that recurs, propose one class-level edit: a new question under a dimension in `dimensions.md`, a change to `spec-template.md`, or a change to a brief. Write the class, never the incident. "The lifecycle of a third-party session is not specified" is a class. A library, function, repo, client or path name is an incident.
3. Ask the user about one edit at a time, with its context, its consequences and your recommendation.
4. Make each approved edit in the dotfiles repo (`skills/first-draft/`). Increment `version:` in each review brief whose text changes, and in both review briefs when `dimensions.md` changes.
5. Run `dots draft scrub <changed files>`. Fix every name it reports. Commit.
6. Run `dots draft learned "<one-line summary>"`.

## Privacy

The ledger and the change folders hold client data: repo names, paths, code and findings. Show that data only to the user. Only class-level text goes into the dotfiles repo, which is public.
