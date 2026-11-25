---
brief: test-writer
version: 1
---
<!-- Orchestrator: replace every <...>, delete this comment, and send the rest to oc-worker with the model opencode-go/kimi-k3.1-pro and a new session ID ses_<slug>tests_<stamp>. -->

# Write the tests for a change before its code exists

You write the tests for a change to the repository at `<repo>`. Another engineer writes the code later. That engineer must make your tests pass and cannot edit them, so your tests are the contract. Write them from the spec below only.

## Spec

<paste these sections of spec.md: Change, Properties, States and transitions, Failure modes, Tests>

## What to write

- Write the tests in the spec's Tests table. Each property (B1, ...) and each failure-mode row that names a test gets at least one test. Put the IDs that a test covers in its name or in a one-line comment.
- Test the behaviour at the seam that the spec names: the public interface, not the internal functions.
- Use the real boundary where a test can run it: the file system in a temp folder, a local process, an in-memory database. Mock only where the spec gives a reason. A mock must behave like the real dependency, including its errors and its delays.
- Where the spec marks a test as property-based, differential or model-based, write it that way, with the libraries that the repository already uses. <If the spec names a new test library, say which one here.>
- Follow the repository's test layout, framework and names. Put the test files in `<paths, or "the usual place for tests in this repository">`.
- Write test code only. Where the interface does not exist yet, call it as the spec names it. A compile error or a missing symbol is then the expected failure.

## Then

1. Run `<test command>`. Each new test must fail, and the cause must be the missing behaviour (a failed assertion, or the missing symbol), not a mistake in the test.
2. Report each test file, each test name with the IDs that it covers, the command, and a short summary of the failure output.
3. Report each part of the spec that is unclear or that you could not test, with the reason.
