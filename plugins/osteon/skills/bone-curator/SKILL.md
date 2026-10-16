---
name: bone-curator
description: Audit a project's BONE knowledge base and evolve it through per-item human approval. Use when a session-start decay warning fires, when a decision locks or a state record is re-verified, when a skill reads stale, redundant, or missing, or when someone says "the skills are out of date", "audit the knowledge base", "is this still true", or "curate". Proposes ADD / UPDATE / REMOVE / MERGE / SPLIT and applies nothing without sign-off. NOT for writing a decision record (bone-adr) or a seam contract (bone-contract). Read MANIFEST.yaml first.
---

# BONE curator

The maintenance loop of a BONE knowledge repository: it finds where the knowledge base has drifted
from the code and decisions it describes, then proposes a changeset and asks. Load `CLAUDE.md` and
`MANIFEST.yaml` first; this skill hardcodes no project paths.

> **The curator decides nothing.** It reads, proposes, asks, applies what a human approved, and logs.
> A change applied without per-item approval is a defect, not a shortcut. A change applied without a
> curation record did not happen.

## When to run

- **Decay signal.** The `SessionStart` hook, if the project installed it from its BONE scaffold,
  reported an index above `curation.cdi_threshold` or a changed input. Run before other work in
  that session. Without the hook this trigger never fires.
- **Event fired.** A decision locked or amended, a state record re-verified, a contract version
  changed, or a listed repository changed structurally.
- **Periodic.** `curation.max_interval_days` elapsed, or end of an iteration.
- **Felt wrong.** Two artifacts say the same thing, a task keeps being re-explained, or an agent
  acted confidently on something untrue.

A run is cheap; finding nothing is a valid, logged outcome.

## The loop

Read, audit, propose, ask, apply approved only, log. **MUST NOT** reorder or skip a step: each exists
because the one before it produces claims nothing else verifies.

## Step 1 - Resolve the manifest, then read the inputs

Take the audit surface from `MANIFEST.yaml`: the `paths.*` keys, `watched` (the one watched-input
list, shared with the hook), `knowledge_units`, `decay`, `gates`, and `repos`. Every key and its
fallback default are in `references/audit-checklist.md` under Preflight.

1. **MUST** read every `SKILL.md` **and every file under its `references/`**. Reference files are
   audit targets in their own right, not background reading. Most drift hides there.
2. **MUST** treat the ledger as drift source one and the state directory as drift source two.
3. **MUST** compare content hashes against the baseline at `decay.baseline`, never modification
   times: a clone, a checkout, or an edit and revert all move mtimes without changing meaning, and
   checking out an older file freshens one that is genuinely stale.
4. **MUST NOT** keep a second list of watched inputs. If the audit needs a source `watched` omits,
   propose adding it there. `watched` is one list: an internal item is a repo-relative path, an
   external item is `repo/<alias>:<path>`, resolved through `repos[].local_path`.
5. **SHOULD** read the last three curation records first: they carry owed follow-ups, refuted
   proposals, and deliberate omissions. Re-proposing a logged refusal erodes the protocol.
6. **CONTEXT** if `MANIFEST.yaml` is absent, use the defaults and make "ADD `MANIFEST.yaml`" the
   first row of the changeset.

## Step 2 - Audit

**MUST** run the whole checklist: the drift classes `D1` to `D10`, each with its usual verb, and the
standing quality bar `Q1` to `Q16`. The class set is enumerated **once**, in
`references/audit-checklist.md`, with each class signature, check, FAIL condition and remediation;
restating it here would be a second enumeration to keep in step.

Every finding carries its class ID, an evidence locator, and a proposed verb.

- **MUST premise-check before proposing.** An audit's findings are claims, not facts. Verify each
  against its source. A proposal built on a misread commit costs more trust than the drift it chased.
- **MUST flag, not fix, what the knowledge base does not own.** A bug or missing test found while
  auditing becomes an owed follow-up with an owner, never a silent repair.

## Step 3 - Propose

One table, one row per proposal. The verb set is closed: **ADD / UPDATE / REMOVE / MERGE / SPLIT**.

| # | Verb | Target(s) | Class | Rationale tied to the specific new data | Concrete edit |
|---|---|---|---|---|---|

1. **MUST** tie each rationale to the data motivating it, with its locator. "Feels outdated" is not a
   rationale; "the record accepted on that date closes the question this paragraph hedges" is.
2. **MUST** give the concrete edit, not the intent: replacement text for UPDATE, the new name and
   full `description` for ADD, what is lost and where the survivor lives for REMOVE.
3. **MUST** group rows by target, so the approver sees one artifact's whole blast radius at once.
4. **SHOULD** order by consequence: contradictions that would make an agent act wrongly come first.
5. **MUST NOT** propose copying an owned rule into a second artifact. A hard rule stated twice is a
   drift hazard, not reinforcement. Propose a reference instead.

## Step 4 - Ask before acting

This step is the point of the skill. Present the changeset with **AskUserQuestion**, one selectable
item per proposal, each **approved, rejected, or modified independently**.

- **MUST** apply only approved items. A modified item is applied as modified and recorded as
  `modified`, with the modification text kept in the record.
- **MUST NOT** remove or rename anything without explicit approval for that specific item.
- **MUST** record rejections. A rejection is a decision about the knowledge base; logging it stops
  the next audit re-proposing it.
- **CONTEXT** a direct human instruction **is** the sign-off, but only when it names the specific
  target artifact and the specific verb. Record `approval: user-directed` and quote it verbatim under
  `approval_instruction`. A general instruction ("tidy up the ledger") **MUST NOT** stand as approval
  for anything on the never-auto-apply list. This valve is a logged path, not an exemption from
  logging.

## Step 5 - Apply approved items only

1. **MUST** edit, then repair every cross-reference to anything renamed, moved, split, or removed.
   Grep the whole knowledge base for the old name before calling the item done.
2. **MUST** sweep a correction across the whole corpus, including frontmatter `description` strings
   and every `references/` file. Body-only sweeps are why D3 keeps recurring.
3. **MUST** keep the narrowest owning tier single-source: edit the owner, make every other mention a
   reference.
4. **MUST** regenerate what is derived: the skill catalog, the ledger and contract registry indexes,
   and `paths.curation_index`.
5. **MUST** re-run the quality lint on every touched file: description form, size budget, provenance
   tokens resolve, no em-dash, no secret value, no mutable fact in a description.
6. **MUST** re-seal the baseline at `decay.baseline` with a per-source content hash. It is written by
   the curation event, never by the check, and it is committed: a clone inheriting no baseline
   reports an uninitialised index, not a healthy zero.
7. **MUST NOT** seal while another session's work is uncommitted in the working copy, and **MUST**
   re-read the index immediately before proposing rather than trusting the trigger reading. A seal
   is one clock for the corpus, not a per-session act, so it speaks for sources the sealing session
   may never have read. Two curators sharing one checkout is the case this exists for (see the
   checklist's failure modes). A red observed in a shared checkout **MUST** be reproduced against
   the committed blob before it is reported or acted on.

## Step 6 - Log, in one commit

Write **one curation record per run, even when nothing was applied**: a file under `paths.curation`
(default `docs/curation/`) named `YYYY-MM-DD-<slug>.md`, then regenerate `paths.curation_index`. The
index is derived, never hand-edited: ordering cannot rot when it is generated.

1. **MUST** land the changed artifacts and their record as **one commit or one change request**. A
   commit touching a governed path that adds no file under `paths.curation` is an unattested apply,
   detectable from `git log --name-only` alone.
2. **MUST** add an `attestation` block whenever an applied action touches the never-auto-apply list:
   a verifiable commit signature, or a merge whose approver differs from the author. The two accepted
   kinds and their field rules: `references/curation-record.md`.

## Invariants

1. **MUST** propose, then ask, then apply. No silent mutation of the knowledge base, ever.
2. **MUST** apply only approved items; a modification is recorded as modified.
3. **MUST NOT** let any artifact contradict the constitution or an accepted decision record.
4. **MUST** keep one fact at exactly one tier. Lower tiers reference; they never copy.
5. **MUST** give every normative claim a resolvable provenance token. A claim without provenance is a
   lint failure, not a style preference.
6. **MUST** produce one curation record per run, including runs that applied nothing.
7. **MUST** log rejections and refutations with their reasons.
8. **MUST NOT** write a secret value into any artifact. Reference secrets by name and location.
9. **MUST NOT** report a Context Decay Index without its granularity label, its internal and external
   sub-indices, the size of each denominator, and the unavailable-source count, in the same record. A
   zero over an empty denominator is indistinguishable from health.

## References

- `references/audit-checklist.md` - the check, FAIL condition and remediation for every drift class
  and quality-bar item, the Context Decay Index computation, and the audit failure modes this loop
  has learned. **Read it before auditing, and append to its failure-mode list whenever an audit
  misses something a later audit catches.** Auditing from memory finds the classes you remember,
  which is how D3, D9 and D10 survive audit after audit.
- `references/curation-record.md` - the record schema, the field and attestation rules, and the index
  format. **Read it before a repository's first record.** Records written from memory soon lose
  fields, and a log of mixed shapes cannot be queried, costing every metric the loop produces.

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here.

`bone-adr` writes decisions, `bone-contract` writes seam contracts, and this skill owns no decision
of its own. It is the **only** skill that may change the knowledge base, and only after per-item
human approval.
