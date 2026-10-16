---
id: {{DATE}}-bone-instantiation
date: {{DATE}}
trigger: manual
cdi_at_trigger: null
sources: ["adr/0000"]
actions:
  - verb: ADD
    targets:
      - CLAUDE.md
      - MANIFEST.yaml
      - CURATION.md
      - docs/adr/
      - docs/state/
      - docs/contracts/
      - docs/domain/
      - docs/curation/
      - .claude/
      - metrics/
    rationale: "Instantiate the BONE five-layer skeleton for {{PROJECT}} from bone-template {{BONE_VERSION}}."
    tier_resolution: T1
approval: user-directed
approver: {{OWNER}}
approval_instruction: "Scaffold {{BONE_REPO}} from bone-template with prefix {{PREFIX}}."
refuted: []
rejected: []
deferred: []
verification:
  citations_checked: 0
  citations_trimmed: 0
  citations_corrected: 0
  lint_passed: true
follow_ups:
  - "Replace every TODO in MANIFEST.yaml (repos, forge, tracker, rhythm, systems_of_record, tiers.T0)"
  - "Declare at least one external watched source per code repository, so external-CDI is computable"
  - "Write the first docs/state/ records so the estate has dated facts"
  - "Author .claude/skills/{{PREFIX}}-context, then seal the first decay baseline"
not_done:
  - "No gate is declared: gates[] is empty because no checklist unit and no CI job exist yet."
  - "No attestation block: this record touches no artifact that existed before the scaffold."
---

# {{DATE}} - BONE instance scaffolded

## What changed

- **ADD the full L1 to L5 skeleton** (whole repository): `{{BONE_REPO}}` was created from
  `bone-template` {{BONE_VERSION}} with prefix `{{PREFIX}}-`. The repository is structurally complete
  and factually empty: every layer exists, no layer yet carries verified project facts.

## What was refuted

Nothing. This is the origin record.

## Premise check

Not applicable. No prior state existed to verify against.

## Governance

Approved directly by {{OWNER}} as the act of instantiation, quoted in `approval_instruction`. No
`attestation` block is present because no pre-existing governed artifact was modified: this event
created the repository. The suite contains one capability unit (`{{PREFIX}}-context`, a skeleton).

**The decay baseline is not yet meaningful.** Nothing has been sealed, so the index correctly reports
`cdi: null, state: "uninitialised"` rather than a healthy zero. The first real curation pass writes
`metrics/curation-baseline.tsv` once genuine facts have landed. Sealing before then is the one action
that makes the metric lie.
