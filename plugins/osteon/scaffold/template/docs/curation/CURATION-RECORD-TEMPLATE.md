---
# ONE curation event, ONE file: docs/curation/YYYY-MM-DD-<slug>.md, and ONE commit carrying both
# this record and the artifacts it describes. A commit that edits governed knowledge and adds no
# record here is an unattested apply.
# Every field below is REQUIRED. Empty lists are written `[]`, never omitted.
id: <YYYY-MM-DD>-<kebab-slug, unique within the date>
date: <YYYY-MM-DD>
# What caused the audit to run.
trigger: manual              # decay-fired | decision-fired | contract-fired | state-fired | periodic | manual
# The index reported by the hook when this pass started. `null` when the baseline was unsealed.
cdi_at_trigger: null
# The knowledge that changed and made the audit necessary. Provenance refs, not prose.
sources: []                  # e.g. ["adr/0012#am1", "state/environments@2026-08-01"]
# One entry per applied change. `verb` is one of ADD | UPDATE | REMOVE | MERGE | SPLIT.
# `tier_resolution` is REQUIRED whenever a fact is introduced or moved between tiers.
actions:
  - verb: UPDATE
    targets: []
    rationale: "<what changed and the specific new data that justifies it>"
    tier_resolution: T1
# How approval was obtained.
#   per-item      each proposal was approved individually
#   user-directed a direct instruction from the owner; it counts ONLY when it names the target
#                 artifact and the verb, and the instruction is quoted verbatim below
#   mechanical    a deterministic, reviewable transformation with no judgement in it
approval: per-item           # per-item | user-directed | mechanical
approver: <owner id from MANIFEST.yaml owners[]>
approval_instruction: ""     # REQUIRED non-empty when approval is user-directed. Verbatim quote.
# REQUIRED when any action touches a never-auto-apply class (the constitution, MANIFEST.yaml, an
# accepted decision record, a contract version). Omit the block only when none does.
attestation:
  kind: signed-commit        # signed-commit | reviewed-merge
  identity: "<the signer, or the approver who is not the author>"
  change_request: null       # REQUIRED non-null for reviewed-merge
# Proposals that were disproved, with the reason. Logged so they are not re-proposed next month.
refuted: []                  # items: { proposal: "...", reason: "..." }
# Proposals that were correct but declined by the approver.
rejected: []
# Proposals held over to a named later pass.
deferred: []
# What was done to verify the APPLY itself, not the finding.
verification:
  citations_checked: 0
  citations_trimmed: 0
  citations_corrected: 0
  lint_passed: false
# Work this pass created and did not do.
follow_ups: []
# Findings surfaced and deliberately left alone, each with the reason it was out of scope.
not_done: []
---

# <YYYY-MM-DD> - <theme in one line>

## What changed

One bullet per action. Each states the change, the mechanism, and the evidence, in that order.
Bold the lead clause so the entry is scannable in one pass.

- **<change>** (`target-a`, `target-b`): what changed and why, citing the source `[src: adr/00NN]`.

## What was refuted

- **<proposal>**: why it was wrong. A hard rule copied into a second file is a drift hazard, not
  reinforcement; that reasoning belongs here when it applies.

## Premise check

What the audit brief claimed, and what was actually true. An audit's own findings are claims to
verify before anything is applied.

## Governance

Approval path, approver, attestation, and any owed follow-up. State explicitly what was surfaced and
deliberately not fixed. A signed commit proves that the named human's key applied the change; it does
not prove that a second human reviewed it. Say which one this was.
