---
name: bone-contract
description: Create, version, or change the contract for a seam between two modules in a BONE knowledge repository. Use when two components start talking, when a wire format, field, unit, auth header, or failure behaviour is about to change, when one side is being built against the other's source instead of a written contract, or when someone asks "what does this return", "who owns this field", or "why did the payload change". Covers semver, the same-wave rule, and the registry index. NOT for decision rationale (bone-adr) or knowledge-base audits (bone-curator). Read MANIFEST.yaml first.
---

# BONE contract registry

Layer 3 of a BONE knowledge repository: one versioned, normative file per module seam, indexed in a
registry, so neither side of a seam ever builds against the other side's source, a guess, or a chat
message. Read `MANIFEST.yaml` for `paths.contracts` and `paths.domain`; this skill hardcodes no paths.

> **A contract is normative, not descriptive.** It is not documentation of what the code happens to
> do. It is the specification both sides implement against, and it changes in the same wave as the
> wire, never after.

## When a seam needs a contract

A **seam** is any boundary where two independently changeable units exchange data. Write a contract
when all three hold:

1. **Two sides** that can be changed, deployed, or reviewed separately. Two modules in one repository
   count if they are released or owned independently.
2. **A wire**: an HTTP call, a queue message, a stream, a shared file or object, a callback, or a
   schema in a store one side owns and the other reads.
3. **Independent change**: one side can change without the other's code being edited in the same
   commit. If they always change together they are one unit, and the type system is the contract.

**MUST** also write one, regardless of those tests, when the seam crosses a trust, team, or
organization boundary. Those are the seams where a silent change is found in production, not review.

**Not a seam:** a function call inside one deployable unit; a private helper; a shape that exists only
inside one process. **CONTEXT** a seam that exists only because one side reads the other's private
storage is still a seam, and the most dangerous kind: no compile-time check, no error on breakage,
and it fails as a wrong answer rather than an exception.

## The registry in one screen

| Element | Rule |
|---|---|
| Index | one complete table under `paths.contracts`, one row per seam |
| Index columns | `Seam \| Contract file \| Version \| Sides \| Status`, in that order. Extra columns MAY be appended to the right, never inserted among the five |
| Contract file | one per seam; YAML front matter carrying a semver `version`, and the changelog inside the file |
| Admission | a new seam is a new row **and** file **before** the code lands |
| Authority | the contract wins over both implementations and any prose |
| Change window | the same review wave as the wire change |
| Vocabulary | field names come from `paths.domain`, the ubiquitous language |
| Decay | every contract file is a member of `watched`, the one watch-set key |
| Withdrawal | a retired seam keeps its file, marked withdrawn, with the reason |

## Golden rules

1. **MUST** keep one file per seam, semantically versioned in **YAML front matter**, with the
   changelog **inside the file**. A version living only in the index drifts from the file that
   defines it, and a version living only in a prose bullet cannot be read by a lint.
2. **MUST** ship the contract change in the **same wave** as the wire change. Never after, never "we
   will document it later". A follow-up is a promise, and the next reviewer reads the stale contract.
3. **MUST** have both sides build against the contract, not each other's source. A test asserting the
   contract's exact strings belongs on both sides. When they disagree, the contract is right and both
   implementations are suspect.
4. **MUST** treat exact strings as normative: paths, method, headers, auth scheme, field names,
   types, units, enum members, ordering, idempotency, and failure behaviour. "Returns the usual error
   shape" is not a contract.
5. **MUST** state failure semantics explicitly, including whether the consumer fails open or closed
   when the producer is unavailable. Failure behaviour is what both sides assume and neither writes
   down, and it turns one component's outage into an incident.
6. **MUST** state units and time semantics on every quantity: unit, precision, timezone, and whether a
   timestamp is event or ingest time. Units are the cheapest defect to create and the hardest to see
   in review.
7. **MUST** add the row and the file **before** the implementing code lands. A contract written
   afterwards documents an accident.
8. **MUST NOT** reference the other side's source, types, or internals. A contract that says "the
   shape defined in the producer's model" has no independent existence and cannot be versioned.
9. **MUST** take field names from the glossary under `paths.domain`. A seam that invents a synonym for
   a term the glossary owns creates a translation layer nobody maintains.
10. **MUST** state this wire's data-handling rules: what may appear, what may never, what must be
    referenced by surrogate. Every seam carries this section, even when nothing is restricted.
11. **SHOULD** keep one seam per file. A file covering three seams has one version for three change
    cadences, so every consumer sees a major bump for a change that did not affect them.
12. **MAY** point a row at a normative contract living outside `paths.contracts`. The row is still
    mandatory: the index is the complete list of seams, and completeness is what makes "what talks to
    what" answerable.

## Semver for contracts

The version describes compatibility **for the consumer**, not effort for the producer.

| Bump | When | Examples |
|---|---|---|
| MAJOR | any change that can break a conforming consumer | removing or renaming a field; narrowing a type; changing a unit; adding a required request field; removing an enum member; changing an error code's meaning; changing fail-open to fail-closed |
| MINOR | additive, backward compatible | a new optional field; a new endpoint or message type; a new enum member **only if** the contract already told consumers to tolerate unknown members |
| PATCH | no wire change at all | wording, clarification, a corrected example |

1. **MUST** bump MAJOR when in doubt. An unnecessary major costs a conversation; a missed one breaks
   a consumer that was told the version was compatible.
2. **MUST NOT** add an enum member as MINOR unless the contract states how consumers handle unknown
   members. Extensibility is granted in advance; adding to a closed enum is breaking even though
   nothing was removed.
3. **MUST** record every bump in the file's changelog with its date and reason, and update the index
   row in the same commit.
4. **SHOULD** carry a deprecation window when a MAJOR removes something: what goes, what replaces it,
   and the date the old form stops being served.
5. **CONTEXT** `0.y.z` means the seam is still being negotiated and either side may break it.
   Reaching `1.0.0` states it is load-bearing, and **SHOULD** happen before production traffic.

## The same-wave rule

The contract, both implementations, and the tests asserting it move together.

- **MUST** put the contract diff in the same review as the wire change, so a reviewer sees the
  specification beside the implementation. A reviewer who cannot see the intended shape can only
  check that the code is self-consistent.
- **MUST** treat a wire change with no contract diff as a blocking review finding. This single check
  is what makes L3 real rather than aspirational.
- **CONTEXT** when the two sides genuinely cannot ship together, the contract still ships first, at
  the new version, stating the rollout: which side leads, what the other must tolerate meanwhile, and
  when that interval ends. The interval is part of the contract.

## Critical gotchas

- **The undocumented seam is the shared store.** One side reading a table, bucket, or file another
  side owns has no compile-time check and no error on breakage; a renamed column surfaces as an empty
  result, so a user finds it. General rule: **if a change on one side can produce a wrong answer on
  the other without raising an error, that boundary needs a contract more than an API does, not
  less.**
- **Swallowed errors turn a seam failure into a silent wrong answer.** A consumer that catches
  everything and returns a default converts the producer's outage into invalid data with no signal.
  The contract names which errors the consumer distinguishes and what it does with each. General
  rule: **a seam that cannot report its own failure has no observable contract.**
- **Both sides verifying the same credential independently is itself a seam.** Two implementations of
  one verification drift, and the drift appears only when one side accepts what the other rejects.
  Name the rules once; both sides follow that.
- **The contract lives beside the wire, not beside the decision.** A ledger record says why the seam
  exists and why this shape won; the contract says exactly what crosses it. Putting the wire spec in
  the record makes every wire change an amendment to a decision that did not change.

## References

- `references/contract-template.md` - the contract file skeleton, registry index format, changelog
  table, and a worked example with neutral placeholders. **Read it before adding the first contract to
  a repository.** Contracts written from memory diverge in section names within three files, and a
  registry whose files have three shapes cannot be diffed, linted, or read quickly under incident
  pressure.

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here.

`bone-adr` records why the seam is shaped this way, this skill specifies exactly what crosses it, and
`bone-curator` propagates the consequences to every artifact describing either.
