---
name: bone-adr
description: Author, amend, or supersede a decision record in a BONE knowledge repository. Use when a durable or hard-to-reverse choice is being made, when someone says "we decided", "lock this in", or "write it up so we stop re-litigating", when an accepted record no longer matches what the running system does, or when a merged change silently suspends a decision. Covers numbering, the proposed/accepted/superseded lifecycle, and the amend-never-rewrite rule. NOT for seam schemas (bone-contract) or knowledge-base audits (bone-curator). Read MANIFEST.yaml first.
---

# BONE decision records

Layer 2 of a BONE knowledge repository: the append-only ledger of durable decisions. A record exists
so a choice is made once, with its rejected alternatives preserved, and is never re-derived from chat
history. Read `MANIFEST.yaml` for `paths.ledger` and `paths.state`; this skill hardcodes no paths.

> **The ledger is append-only.** A record's body is never rewritten after it is accepted. Refinements
> are appended as amendments; replacements are new records. The rejected path is the record: it is
> the only thing stopping the same option being re-proposed next quarter.

## When to use

Write a record when the choice is **durable**, **hard or expensive to reverse**, or has
**consequences outside the team making it**. Concretely, at least one of:

1. It constrains future work: other components must be built around it.
2. Reversing it costs a migration, a re-deploy of something you do not control, or a renegotiation.
3. It resolves a question that has already been asked twice.
4. It picks one of several defensible options, and the reason for rejecting the others is not obvious
   from the code.
5. It changes a boundary: a seam, a tier, a trust boundary, or an ownership line.

**Not a record, just a commit:** a choice fully visible in the diff and cheap to change; a naming or
formatting preference; an implementation detail with one obvious option; anything a contract file
already makes normative. **CONTEXT** if you cannot state the rejected option and why it lost, there
is probably no decision to record yet.

## The ledger in one screen

| Aspect | Rule |
|---|---|
| Filing | one file per decision, `NNNN-kebab-title.md`, under `paths.ledger` |
| Numbering | zero-padded, strictly incrementing, allocated at write time |
| Reserving numbers | never: a gap is permanent and has to be explained forever |
| Lifecycle | `proposed` to `accepted` to `superseded` |
| Operative state | a separate field, because accepted and running are different questions |
| Refinement | an appended `## Amendment N` section; the body is untouched |
| Replacement | a new record; the old one becomes `superseded` with `superseded_by` set |
| Provenance | other artifacts cite `[src: adr/NNNN]` or `[src: adr/NNNN#amN]` |
| Downstream | every record and amendment populates `stales` |

## Front matter

The header is **YAML front matter**, never a bullet list and never prose. A bullet list cannot be
parsed, so `status`, `operative` and `stales` would exist for human readers only and no lint, index
generator or decay check could read them. Ten fields, all required; full template and two worked
examples in `references/adr-format.md`.

```yaml
---
id: 0012                   # four digits, matching the filename
title: "Short imperative title"
status: proposed           # proposed | accepted | superseded
operative: yes             # yes | no | suspended | partial
date: 2026-08-01
deciders: [owner-a, owner-b]
supersedes: null           # or the id this record replaces
superseded_by: null        # or the id that replaced this one
amendments: []             # items: n, date, summary
stales: []                 # MUST be populated; an empty list is written explicitly
---
```

`status` and `operative` are separate on purpose and **MUST NOT** be merged.

- `status` is lifecycle: has this choice been agreed, and is it still the current choice.
- `operative` is reality: is the running system doing this today.

A record can be `accepted` and `suspended` (agreed, but a flag turned it off), or `proposed` and
`partial` (not formally accepted, but three amendments already govern live behaviour). One field
cannot express both, and the corpus that tries ends up with status strings nobody can parse.
`status` **MUST NOT** carry a parenthetical: an open question about the decision goes in the body.
`operative: suspended` or `partial` **MUST** be accompanied by a `preconditions` block listing the
checkable conditions for returning to `yes`, each with `met: true|false` and its evidence.

`stales: []` written explicitly is different from an omitted key: it says the author checked.

## Amend vs supersede

The test is whether **the choice itself** changed.

- **The choice stands and you are recording a refinement inside its scope: AMEND.** Keep
  `status: accepted`. Add an entry to `amendments`. Append an `## Amendment N` section at the end.
  **MUST NOT** edit the body, the options, or the original consequences. A reader must be able to see
  what was believed then and what is believed now.
- **The choice is replaced: SUPERSEDE.** Write a new record that states what it supersedes and why
  the old reasoning no longer holds. Set the old record's `status: superseded` and its
  `superseded_by`. **MUST NOT** delete the old record.
- **Neither, just a clarification that changes nothing normative:** a dated `## Note (YYYY-MM-DD)`
  line in the body, never in the front matter. **SHOULD** be rare; if the note changes what someone
  would do, it is an amendment.

An amendment section carries five parts, in this order: **Context** (what was discovered, with
evidence), **Decision** (numbered normative clauses), **Scope** (what is explicitly not changed),
**Tracking** (references, and what this explicitly does not close), **Stales** (the artifacts this
amendment invalidates).

## When code suspends a decision

A merged change can contradict an accepted record without anyone editing it: a kill switch, a
default-off flag, a deleted writer, a bypassed path. **That divergence is itself an architecture
decision** and it owes an amendment the **same day**. Otherwise the record reads true while the
system does the opposite, and every agent that loads the record acts on a fact that was silently
retired.

1. **MUST** amend, not supersede: the decision still stands, the code is suspended against it.
2. **MUST** state three things: what is off, what the system actually does today, and the exact
   preconditions to turn it back on.
3. **MUST** make each precondition checkable and cite something that is on the default branch. A
   precondition that points at a draft, a chat message, or an unmerged branch cannot be checked and
   is not a precondition.
4. **MUST** set `operative: suspended` or `partial` and populate `preconditions`.
5. **CONTEXT** only if the suspension is meant to be permanent does it become a superseding record.
   Never leave the old one reading plain `accepted` with `operative: yes`.

This is the class of drift that no test catches and no reviewer sees, because nothing was written.

## After locking a decision

A new, accepted, amended, or superseded record is the trigger for reconciliation. **MUST** do all
three before moving on:

1. **Name what it stales.** Every record and every amendment populates `stales` with the artifacts
   whose text the decision invalidates. A record that does not nominate its own downstream consumers
   pushes the search cost onto whoever notices the contradiction first, usually an agent acting on
   it.
2. **Run `bone-curator`.** The decision is new data. Audit, propose, ask, apply, log. Do not
   hand-edit the artifacts the record stales: that is a silent mutation of the knowledge base, and it
   skips the audit that would have found the other four places the same claim lives.
3. **Update the generated ledger index.** One row per record: number, title, status, operative, and
   the decision in one line. The index is a lookup aid and **MUST** carry the precedence rule
   explicitly: the record text always wins over the index summary.

## Critical gotchas

- **A summary of a decision is a copy of a decision.** Every place that restates what a record decided
  is a place that will disagree with it later. Other artifacts **MUST** cite `[src: adr/NNNN]` and
  state only what they need to act on, never the rationale. The rationale lives once.
- **`proposed` is not a parking space.** A record left `proposed` while the system implements it
  produces an artifact no one may cite and everyone relies on. Either accept it or mark it
  `operative: partial` with the reason it has not been accepted.
- **Numbers are allocated, never reserved.** Reserving a block for planned records creates permanent
  gaps that every future reader has to ask about. Allocate the next free number when you write.
- **An amendment that rewrites history destroys the record's only durable value.** If the original
  reasoning is embarrassing, that is exactly the reasoning worth preserving: it is what stops the
  option being re-proposed by someone who does not know it was tried.
- **A decision recorded without its rejected options is a note, not a record.** General rule: the
  cost of a decision record is paid at write time and recovered every time someone asks "why not the
  other one". Omitting the rejected options moves the whole cost to the reader.

## References

- `references/adr-format.md` - the full record template, the amendment template, the preconditions
  block, the index row format, and two worked examples using neutral placeholder domains. **Read it
  before writing your first record in a repository.** Records written from memory drift in field
  names within three records, and a ledger with three header shapes cannot be indexed or linted.

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here.

This skill owns the decision and its rationale. `bone-contract` owns the resulting interface.
`bone-curator` owns propagating the consequences. None of the three edits what another owns.
