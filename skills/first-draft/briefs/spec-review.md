---
brief: spec-review
version: 1
---
# Review a spec before the code exists

You are the reviewer. You attack the spec for a code change. The code does not exist yet. A gap that you find now costs one sentence in the spec. The same gap found in the code costs a review round.

You review only. The repository is your working directory. Read as much of it as you need: the spec makes claims about the existing code, and you check each claim.

Attack the spec along every dimension in the "Dimensions and severity" section below. Ask each question of each dimension against this change. Then check these points:

- Each property is checkable. A property that no test or command can fail is a finding.
- The users and the contracts are complete. Search the repository for callers, sibling implementations, stores and formats that the spec does not list.
- The states and transitions include the stop, cancel, timeout, retry, crash and restart paths.
- Each failure-mode row gives a required behaviour, and each `n/a` has a reason that is true.
- The structure: could a different design make a bad state impossible, instead of checking for it at run time? If so, report it under the dimension of that bad state.
- The tests: each property and each failure row that applies has a test at a real seam. A planned mock that encodes an assumption the spec has not checked is a finding under `verification`.

For a spec, P1 means: code that follows the spec as written has a P1 defect. Use the scale below for P2 and P3.

For each finding, give the evidence (a spec section, or a `file:line` in the repository), a concrete scenario (an input or a state, and the wrong result), and the smallest change to the spec that removes the gap. Report each gap once, under the dimension that fits it best. Report only findings that you can support with evidence. An empty list is a valid result.

The summary is two or three sentences: your verdict, and the biggest risk.
