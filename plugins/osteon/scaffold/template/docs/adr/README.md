# Decision ledger (L2)

Append-only record of every architecture decision for {{PROJECT}}. Conventions are normative in
[ADR-0000](0000-record-architecture-decisions.md); the template is
[ADR-TEMPLATE.md](ADR-TEMPLATE.md).

**The record text always wins over this index.** Read the record before asserting what a decision
says, and read it in full before changing one. This table is a navigation aid and is allowed to be
one curation pass behind; the record is not.

## Index

| ADR | Title | Status | Operative | Am. | Decision in one line |
|---|---|---|---|---|---|
| [0000](0000-record-architecture-decisions.md) | Record architecture decisions | accepted | yes | 0 | Every architecture decision is a numbered, append-only markdown record in `docs/adr/`. |

## Open questions

Questions that are live and MUST NOT be answered by assumption. An agent that needs one of these
answered stops and asks; it does not pick the plausible option.

Resolved entries stay here, struck through, with the deciding record named. Deleting them invites
the question to be re-opened by the next person who has the same idea.

| Question | Blocking | Owner | Status |
|---|---|---|---|
| Which system of record tracks delivery work | any skill that references issues or tickets | {{OWNER}} | open |

## Working practice

- **MUST NOT** write a skill, contract or state record that contradicts an accepted record.
- **MUST** add a row here in the same change that adds the record. A record with no row is invisible;
  a row with no record is a dangling reference and fails the cross-reference lint.
- **MUST** run a curator pass after a record is accepted or amended. The record's `stales` front
  matter list names the artifacts to re-read.
- Numbers are allocated in order and **MUST NOT** be reserved. A gap in this table is permanent and
  has to be explained to every future reader.
