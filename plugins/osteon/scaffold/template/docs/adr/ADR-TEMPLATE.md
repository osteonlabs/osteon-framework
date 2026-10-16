---
id: NNNN
title: "<short imperative title>"
status: proposed            # proposed | accepted | superseded
operative: yes              # yes | no | partial | suspended
date: <YYYY-MM-DD>
deciders: ["<owner id from MANIFEST.yaml owners[]>"]
supersedes: null            # or the id of the record this replaces
superseded_by: null         # or the id of the record that replaces this one
amendments: []              # items: { n: 1, date: <YYYY-MM-DD>, summary: "one line" }
preconditions: []           # REQUIRED non-empty when operative is `partial` or `suspended`.
                            # items: { id: P1, text: "<checkable statement>", met: false, evidence: null }
stales: []                  # REQUIRED. The artifacts this decision makes stale, as capability
                            # unit names or provenance refs. Populate it on every record; an
                            # empty list is written `[]` and means "nothing needs re-reading".
---

# ADR-NNNN: <short imperative title>

<!--
Copy to docs/adr/NNNN-kebab-title.md. Allocate NNNN in order; never reserve a number.
The front matter above is the machine-readable record and every field is REQUIRED: `id` matches the
filename, `title` matches the H1. Angle-bracket fields are filled in by the author. Delete every
comment before committing. The conventions this template implements are normative in ADR-0000.

`status` is lifecycle. `operative` is what the system does today. They are two different questions
and one field cannot answer both: a record can be `accepted` and `suspended` at the same time.

`stales` is what makes the curation loop bidirectional: the ledger tells the curator what to re-read
instead of the curator guessing. A record that leaves it unpopulated has recorded a decision and
hidden its consequences.
-->

## Context

The forces and constraints as they stand today. What is true, what is uncertain, what is pressing.
Every non-obvious claim carries a provenance token, for example `[src: state/deploy@<YYYY-MM-DD>]`.
State what is NOT known; an unknown recorded here is cheaper than an assumption discovered later.

## Decision drivers

Numbered. These are the criteria the options are judged against, written before the options so the
judgement is not fitted to the conclusion.

1. <driver>
2. <driver>

## Options considered

1. **<option>.** <How it would work.> Pros: <...>. Cons: <...>. Rejected: <the reason, tied to a
   named driver>.
2. **<option>.** <...> CHOSEN.

<!-- Every rejected option MUST carry its reason. The rejected path is the record: without the
     reason, the option gets re-proposed and re-rejected every six months. -->

## Decision

One sentence stating the choice, followed by why it wins on the drivers by number.

## Normative rules

<!-- OPTIONAL. Include only when the decision imposes rules others must follow. Each line carries a
     modal marker (MUST / MUST NOT / SHOULD / SHOULD NOT / MAY). These lines are what gates and
     skills cite; keep them numbered and stable. -->

## Consequences

Positive: what becomes easier or safer.
Negative: what becomes harder or more expensive. Name it honestly; an ADR with no negative
consequences was not a decision, it was a preference.
Follow-ups: what this decision now obliges someone to do.

## Preconditions

<!-- REQUIRED when `operative` is `partial` or `suspended`, and it MUST mirror the `preconditions`
     list in the front matter rather than introduce new items. A checkable list, each item citing a
     document on the default branch. An unverifiable precondition is not a precondition. -->

| id | Precondition | Met | Evidence | Re-checked |
|---|---|---|---|---|
| P1 | <checkable statement> | yes / no | `<path or resource id>` | <YYYY-MM-DD> |

**Related:** <sibling records, contracts, tracking issues>.

---

## Amendment N (<YYYY-MM-DD>) - <one-line title of what changed>

<!-- Append amendments at the end, in order. Never edit the body above. Add the amendment to the
     `amendments` list in the front matter and extend `stales` with anything the amendment newly
     makes stale. Cite an amendment as `[src: adr/NNNN#amN]`. -->

**Context.** Why the record above no longer describes reality, with evidence.

**Decision.** Numbered normative clauses. Each carries a modal marker.

**Scope and constraints.** What is explicitly NOT changed. What remains the target.

**Tracking:** <issues>. Does NOT close <the open item this could be confused with>.
