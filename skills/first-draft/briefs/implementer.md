---
brief: implementer
version: 1
---
<!-- Orchestrator: replace every <...>, delete this comment, and send the rest to oc-worker (default model) with a new session ID ses_<slug>_<stamp>. Use the same ID for every fix-up. Tier 1 has no protected tests: replace the "Protected tests" section with "Write a test for each row of the spec's Tests table, at the seam it names." -->

# Implement a change so that its protected tests pass

You implement a change in the repository at `<repo>`. The spec below is the contract.

## Spec

<paste the whole spec.md>

## Protected tests

These files are the acceptance tests: `<paths>`. Run them with `<command>`.

They are read-only for you. If a test looks wrong, stop and report the test, what it expects, and why you think that is wrong. The orchestrator decides. You can add new tests in other files.

## Rules

- Satisfy every property (B1, ...) on every path, including the stop, cancel, timeout and error paths in the States and transitions table.
- Keep every contract in "Contracts relied on" and every user in "Users of what changes" working.
- Follow the Structure section. <name the structural decisions, for example "one owner for the session state: the X module">
- Make the smallest change that does this, in the style of the repository.
- Run the protected tests and the project checks: `<commands>`.

## Report

- The files that you changed, and for each change the property or failure-mode row that it serves.
- A short summary of the output of the protected tests and the project checks.
- Each gap or contradiction that you found in the spec.
