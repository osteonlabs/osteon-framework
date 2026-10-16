---
name: bone-review
description: Review a change against the project's own bar, derived from its BONE (L1 constitution, L2 decisions and state, L3 contracts and domain, L4 unit rules) not from generic best practice. Use on any diff before merge, as the self-review before a change is declared ready, and when asked "review this", "is this safe to merge", "what will a reviewer say". Also detects when a change invalidates a decision, a contract or a unit claim and routes it to bone-curator. NOT for branch and merge mechanics (bone-git); never edits the knowledge base itself. Load the project's T1 context skill first.
---

# BONE Code Review

Review to **this project's** bar. Load the T1 context skill first, then `MANIFEST.yaml` for the gate set and the knowledge paths.

> **A review is bounded by the BONE, and is the project's highest-yield decay detector.** Every blocking finding MUST trace to a written rule in L1 to L4 or to a defect demonstrable in the diff. Because the reviewer is already reading the diff that invalidates the knowledge base, the *Knowledge impact* block is mandatory even when the code is fine.

## When to run

- Any diff before it is committed (per staged group), and again over the whole change before ready.
- Any change request from another author or agent; any change touching a declared seam, a gated change class, or a path named in an accepted decision.
- Any hotfix, however small. Small changes are where suspended decisions and unshipped contracts hide.

## Deriving the bar

Read these before the diff; each yields review items and nothing else does. Locations resolve through `paths.*`; the canonical defaults are shown.

| Source | Yields | Enters the review as |
|---|---|---|
| L1 `paths.constitution` + `MANIFEST.yaml` | non-negotiables, the gate set by `id`, owners | items 3, 9 |
| L2 `paths.ledger` (accepted, operative) | what the system MUST do, and what was rejected and why | item 4, K1 |
| L2 `paths.state` (dated, verified) | what it DOES today, including soft or suspended enforcement | item 5, K3 |
| L3 `paths.contracts` | exact wire strings, versions, failure semantics per seam | item 6, K2 |
| L3 `paths.domain` | the ubiquitous language: the sanctioned name per concept | item 7 |
| L4 units under `paths.skills` + each repo's `tier2_context` | repo conventions, golden rules, recorded gotchas | item 8, K4 |

**MUST distinguish `is` from `ought`.** State records and code answer what the system does; decisions and contracts answer what it must do. A disagreement is not a tie to break in review, it is a defect to record: see K1.

## Checklist

Each item yields a verdict, evidence, and, on failure, one line of remediation. Item IDs are stable; a new check gets `6b`, never a renumbering, so other artifacts can cite it.

1. **Scope** - one concern, revertable alone, work-unit key present exactly once. FAIL on two unrelated concerns.
2. **Correctness** - logic, edge cases, error handling, idempotency, concurrency, failure paths. FAIL on a path that can lose or double-apply work.
3. **Constitution** - every L1 non-negotiable this change class touches. FAIL on any violation: L1 has no advisory items.
4. **Decision conformance** - does it do what the governing accepted decisions say, on the drivers they name? FAIL if it re-implements a rejected option with no superseding record.
5. **State conformance** - does it assume or contradict a fact whose state record is past the project's staleness horizon? NEEDS-INFO until re-verified.
6. **Contract co-change** - if anything crossing a registered seam moves (endpoint, field, unit, auth, error shape, retry or fail-open semantics), the contract file and its `version` change in the same wave. FAIL if the wire moved and the contract did not.
   - 6b. **New seam** - a cross-module call with no registry row FAILs until the row and file exist.
7. **Domain language** - new names match `paths.domain`. FAIL on a synonym for an existing concept; a genuinely new concept is a glossary change in this wave.
8. **Repo conventions** - the layering, boundaries, error envelope and recorded gotchas of the owning repo skill. FAIL on a rule that skill states as absolute.
9. **Declared gates** - run every gate in `gates[]` whose `scope` matches, by `id`, and report each verdict verbatim rather than summarizing it away. FAIL if a matching gate was not run. `enforcement: none` means CI does not enforce it, not that nobody checks it.
10. **Tests** - changed paths, their failure paths, and any contract-covered surface. FAIL if the only assertion covers the happy write path while read paths that must filter go untested.
11. **Sensitive data** - no secret, credential, token, key or regulated value in code, fixtures, logs, messages or the body. FAIL on any occurrence: an exposed value is compromised, not removable.
12. **Operability** - can a human tell when this fails? A path that can be switched off, degrade, or partially succeed MUST signal that to an operator and MUST NOT return plain success for work it did not do. An alarm counts only when it reaches a confirmed recipient: existence and delivery are two checks and only the second is the control.

**Documented exceptions are first-class.** A violation an accepted decision records as an accepted exception MUST NOT auto-FAIL: verify the mitigations that decision names and report `PASS (documented exception, [src: adr/NNNN])`. A gate that cannot express an exception gets disabled; one that can survives.

## Knowledge impact (the decay trigger)

Answer all five, every review. **MUST NOT edit the knowledge base inline**: this skill detects and routes, `bone-curator` proposes and applies under per-item approval. Silent repair by a reviewer is the unlogged mutation the methodology forbids.

| ID | Question | If yes |
|---|---|---|
| K1 | Does the change contradict an accepted, operative decision (a kill switch, a default-OFF flag, a deleted writer, a changed default)? | **BLOCKING.** An amendment is owed in this wave, stating what is off, what the system does today, and the checkable preconditions to restore it. Route to `bone-adr`. |
| K2 | Does it move anything on a registered seam? | **BLOCKING.** Contract and version change in this wave. Route to `bone-contract`. |
| K3 | Does it falsify a state record? | **BLOCKING if that record is cited by a gate or a contract**, otherwise routed. The record is replaced by a re-verified one, never appended to. |
| K4 | Does it falsify a claim in a skill body, a `references/` file, or a description? | Routed to `bone-curator`. Non-blocking, but the proposal MUST exist before merge. Sweep descriptions too: audits read bodies, so frontmatter drifts last and longest. |
| K5 | Does it introduce a fact with no owning tier, or duplicate one that has an owner? | Routed. Assign to the narrowest tier that fully owns it; every other mention becomes a reference. A rule copied into a second artifact is a drift hazard. |

The output MUST carry this block even when empty. `K: none` is an assertion, and an assertion can be wrong; silence cannot.

## The bar is bounded

- **MUST NOT block on a rule written nowhere in the BONE.** Raise it `ADVISORY`, say plainly it is not yet project policy, and open a `bone-curator` proposal to encode it (or a `bone-adr` candidate if it is a decision). Blocking on unwritten rules makes the bar unknowable and the review unappealable.
- **MUST cite the source that makes each finding a finding**, in the grammar of SPEC §4.2: `[src: adr/NNNN]`, `[src: contract/<seam>@X.Y.Z]`, `[src: state/<topic>@YYYY-MM-DD]`, `[src: domain/<slug>#<anchor>]`, `[src: repo/<alias>:<path>]`, or the diff itself. A finding whose only source is the diff is a defect claim, not a policy claim; a finding with no source at all is advisory by construction.
- **SHOULD** note what is good, specifically. A review naming only defects trains authors to hide work.

## Output

Findings grouped `BLOCKING` then `ADVISORY`, each with `file:line`, the issue, one-line remediation, and its `[src: ...]`. Then the per-item verdicts, the gate verdicts by `id`, then the K block.

Item verdicts (closed set): `PASS` · `FAIL` · `NEEDS-INFO`. Merge verdict (closed set): `APPROVE` · `CHANGES-REQUESTED` · `BLOCK`.

Any `FAIL` blocks merge; `NEEDS-INFO` blocks until resolved, so an under-determined item cannot be silently passed. Never emit `APPROVE` with an unanswered K row.

## Metrics

One JSON line per review in `review.jsonl` under `paths.metrics`: `id`, `date`, `change_ref`, `change_classes[]`, `gates[{id,verdict}]`, `blocking`, `advisory`, `knowledge[{k,target,routed_to,status}]`, `verdict`, `reviewer`, `review_mode` (`self` or `peer`).

When a defect later reaches an environment, append to `escapes.jsonl` under `paths.metrics` the `review_id` that saw the change and the item ID that should have caught it. **Gate catch rate = caught / (caught + escaped)**, computable only because both halves are written down. An escape is a finding about the gate set, not the reviewer, and SHOULD end as a new item ID.

## Critical gotchas

- **A green suite that only asserts the write path still ships the leak.** When a change adds a flag or column meant to segregate rows, every read path that should exclude them must filter, not just the writer and the output layer. *General rule: a change that adds a distinction owes a check on every consumer, not on its producer.*
- **A review that stops at the code is half a review.** The most expensive defect is not the bug in the diff, it is the sentence the diff just made false, which ten future sessions will act on with confidence. *General rule: every merge is a knowledge event.*
- **Read the review to its end before answering any of it, and answer it per item.** A reviewer who numbers their findings needs a numbered response to check each one off; a reply that addresses the blocking comment and silently fixes item 3 has closed nothing they can verify. This costs a reviewer their second pass, which is the scarcest thing in the loop. *General rule: a partial read is indistinguishable from a careless one, and the reviewer cannot tell which it was.*
- **Never act on truncated tool output.** Long review bodies, `git log`, and file reads are routinely cut off mid-item, and the cut is easy to miss because what you did read is coherent. Before acting, confirm you reached the end: check the last item is complete, re-fetch with an explicit range, or read the file directly. *General rule: the convention you needed was usually in the part that got truncated, which is why the estate's own commit style, change-request template and half a review can all be missed in a single session while every individual step looked correct.*

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here. The project's L5
gate units are invoked by `id` from `gates[]`.

This skill **judges** the change and **detects** the knowledge it invalidates; `bone-git` moves the change; `bone-curator` is the only skill that may change the knowledge base, and only after per-item human approval.
