# The inheritance chain

What an instance inherits from the framework, how it is produced, and the check that proves it
still inherits. Every item cites the requirement it enforces by number; none restates it. Read the
cited requirement in the specification when an item is unclear, never this file's gloss of it.

## The chain

    specification  ->  scaffold  ->  instance
    (bone-spec)        (bone-template)  ({PROJECT}-BONE)

The specification says what is required. The scaffold is the only sanctioned way to produce an
artifact that satisfies it from a standing start. An instance is one project's copy of that shape,
carrying a pin to the T0 commit it reads, so that a change to the framework can be told to have
reached it or not.

## Producing an instance

The scaffold repository's own README carries the init command, its flags and the dry run. Those
commands live in exactly one place and are not restated here. What this unit adds is the rule:
**an instance is produced by that script or it is not an instance.** A hand-built repository that
happens to have the right directories carries no scaffold version, no genesis commit and no pin,
and the inherit check below fails it on the first item.

The scaffold emits the conformance field as `none`. That is correct and required: at instantiation
no check has run, so no level is claimable.

## The inherit check

Run against one instance, in this order. Each item names the requirement it enforces and the
failure it catches, because a check whose purpose is unstated gets skipped when it is inconvenient.

1. **Stamped, not built.** The instance has a genesis commit from the scaffold and `tiers.T0` names
   the source repositories and the install mechanism. Catches: a hand-built repository with no
   lineage.
2. **Pinned.** `tiers.T0.version` is a commit-ish, or `null` only while the T0 source is not under
   version control. A placeholder string is a failure (B-203). Catches: an instance that cannot be
   told a framework change reached it.
3. **Honest about conformance.** `conformance` is `none` unless a check has run and passed
   (B-17); a claim names its level and the specification version (B-13); no MUST-level requirement
   of the claimed level is unmet (B-14); levels are cumulative (B-16). Catches: a scaffold asserting
   a level nothing established.
4. **Clean governed set.** No secret value anywhere in it (B-10); nothing untracked cited as an
   input (B-9); no normative claim whose only support lies outside the governed set (B-11).
   Catches: a rule that rests on a document the repository cannot see.
5. **House style declared and enforced.** At least one mechanically checkable style rule, with the
   file set it applies to as globs, backed by a lint (B-12, B-12a, B-12b). Catches: a canary that
   exists in prose and fires nowhere.
6. **T0 carries the registry.** The T0 source repository holds `ORG.yaml` at its root (B-201), and
   no manifest restates the rule-class vocabulary, the non-overridable set or the team registry
   (B-202). Catches: a second enumeration that drifts the first time a team is added.
7. **Every cited unit resolves.** Every capability-unit name cited in L1, in a hook or in another
   unit resolves to a directory on disk at the tier the citation implies (B-181). Catches: a
   governance loop that routes to nothing at the moment it is supposed to engage.
8. **Assumptions are marked.** A believed-but-unverified fact in a state record is marked as a
   working assumption (B-46). Catches: a guess read at the confidence of a fact.
9. **The personal tier is outside.** T4 is never in the governed set and never cited (B-8, B-192).
   Catches: a personal path becoming citable and therefore promotable by reference.
10. **The watched set is declared once.** Decay inputs appear under the single top-level `watched`
    key and under no retired name. Catches: two watch lists, one of which the check never reads.

## Verdicts

- `PASS`: every item evidenced.
- `FAIL`: any item whose requirement is MUST-level is false. The finding goes to the instance's
  curation loop as a proposal; this unit changes nothing inside the instance.
- `NEEDS-INFO`: any item's evidence is unavailable, for example a T0 source not on disk. Not a
  pass. The conformance field stays at `none` and the missing evidence is named.

## When to run it

Before any conformance claim; after every advance of the T0 pin; and whenever a specification
revision lands, because a revision can turn a passing instance into a failing one without a single
file in the instance changing.
