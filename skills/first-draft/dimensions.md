# Dimensions, severity and steps

The spec, the spec review, the code review and the ledger use these terms. Each dimension has an ID and a list of questions. A learning pass adds questions. Change the list of dimensions only with the user's approval.

## Dimensions

### `contracts` — implicit contracts

Rules that the existing code, its callers, its sibling implementations or its stores rely on, which nobody wrote down.

- What does the existing code assume about the thing that changes: order, uniqueness, null or empty, units, encoding, time zone?
- Do sibling implementations of the same interface follow a rule that the new or changed one must also follow?
- What do the stores (database, files, caches, queues) expect: schema, key format, expiry, who writes and who reads?
- Which errors and return values do callers handle, and which do they not?

### `inputs` — inputs

- Empty, one, many, very large? Zero, negative, maximum? Missing, null and empty string?
- Malformed or hostile input? Unicode, encoding, whitespace, case? Duplicates?
- Input from a source that the code does not control: a user, the network, a file, the environment?

### `lifecycle` — lifecycle and transitions

- What starts it, and what stops it? Can a stop or cancel arrive before the start completes?
- Timeout and retry: what is retried, how many times, with what delay? Is each attempt safe to repeat?
- Teardown: what is released, closed, unsubscribed or reset on success, on error and on cancel?
- Partial completion: what state remains if it stops halfway, and what does the next run see?
- Restart after a crash or a deploy: what state survives, and is it still valid?

### `concurrency` — concurrency and ordering

- Two calls at the same time, for the same key? Two processes? Two hosts?
- Events that arrive out of order, late, twice or never?
- A read-modify-write with no lock and no version check? A gap between a check and the action?
- A callback or async work that runs after its owner is gone?

### `partial-failure` — partial failure and idempotency

- Writes to two systems: what happens if the second write fails?
- Is each step idempotent? What is the idempotency key?
- What does a retry do to side effects that already happened (messages, charges, emails, files)?
- Is each error reported, logged or silently lost?

### `resources` — resources

- Does every open have a close on every path: timers, handles, connections, subscriptions, temp files, processes?
- Are memory, queues, tasks and file sizes bounded?
- Rate limits and quotas of each dependency?

### `environment` — config and environment

- A missing or wrong config value: does it fail at start, or later and silently?
- Another OS, shell, locale, time zone, clock, or file system case rule?
- Versions of the runtime, dependencies and external services? Feature flags on and off?
- Does it work in CI, in a container and on every host that runs it?

### `callers` — callers and compatibility

- Every caller, importer and consumer of a changed function, type, endpoint, event, schema, file format or CLI flag, found by a search, not from memory.
- Data written before the change, and clients that still use the old shape? Migration and rollback?
- Docs, configs, scripts and tests that encode the old behaviour?

### `security` — security

- Does the change cross a trust boundary? Who can call it, and with what authority?
- Injection: shell, SQL, path, template, header, prompt?
- Secrets: logged, stored, sent, or put in an error message?
- Is authorisation checked at the right layer, on every path, including the new one?

### `cost` — running cost

- What runs per request, per item or per loop iteration?
- N+1 calls, unbounded loops, fan-out with no limit?
- Paid API or model calls: how many for each action, and what limits them?
- Added latency for the user? Work that can be cached or batched?

### `verification` — verification

- Does each property have a test that fails without the change?
- Does a mock encode the same assumption as the code? Does the real dependency behave the same way, including its errors and delays?
- Do the tests check behaviour at a seam, or the implementation?
- Is there a case that a property-based, differential or model-based test would find?

## Severity

- **P1:** on a reachable path, the defect causes wrong results, data loss or corruption, a security hole, a crash or a hang, a broken caller, or cost that grows with no bound. It must be fixed before merge. A reachable path is one that real inputs, real timing or a real failure can take.
- **P2:** a real defect with a limited reach or a workaround, or a spec property with no test. Fix it before merge unless the user accepts it.
- **P3:** an improvement, style, or a minor cost. Optional.

For a spec, P1 means: code that follows the spec as written has a P1 defect.

## Steps

At triage, an accepted finding gets the step that should have caught it. The step names the artifact that must improve.

- `spec`: the spec was silent or wrong about it.
- `spec-review`: the spec raised the question but left it open or vague, and the spec review let it pass.
- `tests`: the spec was right, but no protected test checked it, or a test encoded the wrong assumption.
- `implementation`: the spec and the tests were right, and the code broke a property anyway.
- `code-review`: a fix from an earlier code review round added the defect.
