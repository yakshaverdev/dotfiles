# Spec: <title>

<!-- Tier 1: fill the sections marked [all tiers]. Tier 2: fill every section. Use the terms in dimensions.md. Delete these comments. -->

## Change [all tiers]

What changes and why, in two to four sentences. What is out of scope.

## Properties [all tiers]

Numbered statements of behaviour. A test or a command can fail each one.

- B1:
- B2:

## States and transitions

Every state that the change adds or touches. Include the stop, cancel, timeout, retry, crash and restart paths.

| State | Event | Next state | Side effects |
|---|---|---|---|
| | | | |

## Users of what changes [all tiers]

| What changes | User (caller, sibling, store, format, doc) | Evidence (`file:line` or search) | Impact |
|---|---|---|---|
| | | | |

## Contracts relied on

| Contract | Where it is relied on (`file:line`) | How the change keeps it |
|---|---|---|
| | | |

## Failure modes

One row per dimension. Each row gives a required behaviour and a test, or `n/a` and a reason.

| Dimension | Failure | Required behaviour | Test |
|---|---|---|---|
| contracts | | | |
| inputs | | | |
| lifecycle | | | |
| concurrency | | | |
| partial-failure | | | |
| resources | | | |
| environment | | | |
| callers | | | |
| security | | | |
| cost | | | |
| verification | | | |

## Structure

How the design makes bad states impossible: one owner for each piece of state, an explicit state machine, types that reject invalid values. Name the bad states that the design removes. Where the design uses a flag or a runtime check instead, say why.

## Tests [all tiers]

Test at the highest seam that exists. Use the real boundary where a test can run it. Mock only a boundary that a test cannot run, and give the reason.

| Test | Covers (B or dimension) | Seam | Kind (example, property, differential, model) | Real or mock (reason) |
|---|---|---|---|---|
| T1 | B1 | | | |

## Open questions

Questions for the user. This section is empty before the tests are written.
