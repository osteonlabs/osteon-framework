---
id: 0000
title: "Record architecture decisions"
status: accepted
operative: yes
date: {{DATE}}
deciders: [{{OWNER}}]
supersedes: null
superseded_by: null
amendments: []
preconditions: []
stales: []
---

# ADR-0000: Record architecture decisions

## Context

{{PROJECT}} is developed with coding agents in the loop. An agent acts on whatever context it is
given, confidently, and when that context is stale the failure is silent: the work looks correct,
passes review by a reader who shares the same stale belief, and only surfaces later as rework.

Decisions made in chat, in merge request threads, or in a person's head are unavailable to an agent
and unavailable to a new contributor. A project that cannot say *why* it chose something cannot tell
an agent which of two plausible paths is the sanctioned one.

This record is the bootstrap: it establishes the ledger by being the first entry in it.

## Decision drivers

1. An agent must be able to resolve "why is it like this" without a human in the loop.
2. The record of a decision must outlive the people who made it.
3. A rejected option is as valuable as the chosen one; re-litigating settled questions is the most
   common waste in a long-running project.
4. When the running system diverges from the record, the divergence must be detectable.
5. The format must be cheap enough to actually be used. Roughly half of the repositories that adopt
   decision records write between one and five and then abandon the practice.

## Options considered

1. **No records; decisions live in merge requests and chat.** Rejected. Not addressable, not
   greppable, not loadable by an agent, and lost when a platform or a person leaves.
2. **A single DECISIONS.md file.** Rejected. It grows without bound, produces a merge conflict on
   every parallel decision, and cannot carry per-decision status or amendment history.
3. **A wiki.** Rejected. It is outside version control, so a decision cannot be reviewed in the same
   change that implements it and cannot be diffed against the code it governs.
4. **One markdown file per decision in `docs/adr/`, append-only, amended rather than rewritten.**
   CHOSEN.

## Decision

Every architecture decision for {{PROJECT}} is recorded as a numbered markdown file in `docs/adr/`,
carrying YAML front matter and using the template in `docs/adr/ADR-TEMPLATE.md`. The ledger is
append-only: a record is amended when the choice is refined and superseded when the choice is
replaced, and the body of an accepted record is never rewritten.

This wins on all five drivers: records are addressable and greppable (1, 2), rejected options are
preserved with their reasons (3), the `operative` field plus the amendment rule make divergence
visible (4), and a single markdown file per decision is the cheapest format that still supports
per-decision status (5).

## Normative rules

1. **Filing.** `docs/adr/NNNN-kebab-title.md`, zero-padded to four digits, allocated in order.
   Numbers **MUST NOT** be reserved in advance: a reserved number that is never used becomes a
   permanent gap that every future reader has to have explained.
2. **Front matter.** Every record **MUST** open with YAML front matter carrying `id`, `title`,
   `status`, `operative`, `date`, `deciders`, `supersedes`, `superseded_by`, `amendments`,
   `preconditions` and `stales`. A markdown bullet list is not front matter: it is not parseable,
   so no lint and no skill can read it.
   - `status` is lifecycle only: `proposed` | `accepted` | `superseded`.
   - `operative` is what the system does today: `yes` | `no` | `partial` | `suspended`.
     These are two different questions and one field cannot answer both. A record can be `accepted`
     and `suspended`, or `proposed` and `partial`, and both states occur in practice.
3. **Amend, do not rewrite.** A refinement inside the scope of the existing choice is an amendment:
   append an `## Amendment N` section, add the entry to `amendments`, keep `status: accepted`. **The
   body is never edited, because the rejected path is the record.**
4. **Supersede only when the choice itself is replaced.** Write a new record, set the old one to
   `status: superseded` with `superseded_by: NNNN`, and set the new one's `supersedes`.
5. **When code suspends a decision.** A merged change can contradict an accepted record without
   anyone editing the record: a kill switch, a default-OFF flag, a deleted writer. That is itself an
   architecture decision and it owes an amendment **the same day**. The amendment MUST state what is
   off, what the system actually does today, and the exact checkable preconditions to turn it back
   on, listed in `preconditions`. Each precondition MUST cite a document that is on the default
   branch, otherwise the precondition cannot be checked by anyone but its author. Set
   `operative: suspended`. Amend rather than supersede unless the suspension is permanent.
6. **Every record nominates its consumers.** `stales` **MUST** be populated on every record and on
   every amendment. This is what makes the curation loop bidirectional: the ledger tells the curator
   what to re-read instead of the curator guessing. An empty list is written `[]` and asserts that
   nothing needs re-reading.
7. **Provenance.** Any claim of fact inside a record carries a provenance token per `CLAUDE.md`. A
   record is cited as `[src: adr/NNNN]` and an amendment as `[src: adr/NNNN#amN]`.
8. **The record wins.** Where the decision index, a skill, or a summary disagrees with the record
   text, the record text is correct and the other artifact is a defect to be fixed.

## Consequences

Positive: an agent can answer "why" from the repository alone; settled questions stay settled;
divergence between the record and the running system becomes a recordable, dated event rather than a
silent inconsistency.

Negative: writing a record costs time at exactly the moment when the decision feels obvious, which is
when it is cheapest to skip and most expensive to have skipped. The ledger is only as good as the
discipline of adding to it, and adoption of this practice fails more often than it succeeds.

Follow-up: the ledger is a watched source (`MANIFEST.yaml: watched`), so every change here raises the
Context Decay Index until a curation pass reconciles the knowledge units.

**Related:** `docs/adr/ADR-TEMPLATE.md`, `docs/adr/README.md`, `CLAUDE.md`.
