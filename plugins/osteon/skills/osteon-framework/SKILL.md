---
name: osteon-framework
description: Own the OSTEON framework that every project's BONE inherits from, with its taxonomy of framework things, the inheritance chain from specification and scaffold to instance, and the register of named methodologies. Use when a new project's BONE is started, when someone asks "where does this rule come from", "is this still conformant" or "is this a tool, a skill or a methodology", or when a way of working needs a name. NOT for papers, instruments or the corpus (osteon-research-unit), nor one instance's knowledge base (bone-curator). Read the specification in the T0 source first.
---

# OSTEON framework

The unit whose subject is the framework itself. Every project's BONE is an instance of OSTEON;
this unit owns the chain by which an instance is produced from the framework and the single
enumeration of what kinds of thing the framework contains. It resolves the T0 source repositories
through `tiers.T0.source_repo` in whichever manifest it is pointed at, and hardcodes no path.

> **The framework is inherited, never copied.** A principle lives once, as a numbered requirement
> in the specification. An instance cites it; nothing restates it. A rule that appears in two
> places is two rules the moment one is edited.

## The taxonomy

The one enumeration of what a thing in OSTEON is. **MUST** classify a new artifact here before
naming it, because the class fixes where it lives and who approves it.

| Class | What it is | Where it lives |
|---|---|---|
| Framework | OSTEON: the standard, the tier model, the curation loop, the library, the programme | the T0 source repositories |
| Specification | The numbered normative requirements every instance inherits | the specification repository |
| Scaffold | What an instance is stamped from, and the only sanctioned way to make one | the scaffold repository |
| Capability unit | Executable procedural knowledge: a directory of `SKILL.md` plus `meta.yaml` | the T0 libraries; `paths.skills` at T1 |
| Methodology | A named, theorised way of working: a problem, a vocabulary, roles, principles, an evidence base, and the units that execute it | `references/methodology-register.md` |
| Instrument | A measurement that records what happened to context without changing it | the observation repository |
| Corpus | The instruments' readings, private by default | the corpus repository |
| Gate | The enforced subset of the library, enumerated once in a manifest | the instance's manifest |
| Instance | One project's BONE | `{PROJECT}-BONE` |

**CONTEXT** the question "is this a tool, a skill or a methodology" resolves as: a methodology is
the theory and the vocabulary; capability units are its executable form; instruments are what it
measures with. A methodology **MUST NOT** carry a rule of its own. A rule it needs is a numbered
requirement, proposed to the specification.

## The inheritance chain

Specification, then scaffold, then instance. An instance inherits by being stamped from the
scaffold, and proves it still inherits by holding a conformance claim it can defend.

- **MUST** create an instance with the scaffold's init script and never by hand. A hand-built
  instance carries no version of the scaffold it came from, so nothing can say what it inherits.
- **MUST** pin `tiers.T0.version` to the commit the instance reads. A placeholder is a lint failure
  by the specification's own rule, and an instance that cannot name its T0 commit cannot be told
  whether a framework change reached it.
- **MUST** run the inherit check before any conformance claim, and record `none` until it passes.
  The checklist, what each item catches and the requirement it enforces: see
  `references/inheritance-chain.md`. Skipping it produces the failure the specification names
  first: a scaffold that ships asserting a level no check has ever established.
- **MUST** record a deviation from an inherited requirement as a working assumption in the
  instance, never by editing the requirement's copy, because there is no copy to edit.
- **SHOULD** re-run the inherit check whenever the T0 pin advances: a pin advance is the act of
  re-verifying every unpinned claim, and inheritance is the first of them.

## Admitting a methodology

A methodology enters the framework through the register, not through prose in a unit.

- **MUST** give it a name grounded in the framework's own metaphor and a one-sentence statement of
  the problem it solves, so it can be told apart from a technique.
- **MUST** record its vocabulary, its roles, the evidence it rests on, and the capability units that
  execute it. A methodology with no executing unit is a paper design and is registered as such.
- **MUST** assign it a status from the closed set `proposed`, `accepted`, `superseded`. Acceptance
  is the methodology owner's sign-off, and is a specification revision when the methodology needs
  a requirement the specification does not yet have.
- **MUST NOT** name a project, a vendor or a person in the register. The evidence cites instrument
  readings and curation records, which the tier rules do not de-identify, so the entry's author does.
- The register, its entry schema and the methodologies already named: see
  `references/methodology-register.md`. Naming a methodology outside it produces a second
  vocabulary that the next project will not find.

## Verdicts

The inherit check returns one of `PASS`, `FAIL`, `NEEDS-INFO`. `NEEDS-INFO` is not a pass: an
item whose evidence is unavailable is reported as unavailable, and the conformance field stays at
`none`.

## Boundary

This unit owns the framework's own inheritance and register, and nothing inside any one instance.
`osteon-research-unit` owns the papers, the programme's heartbeat and everything that leaves the
machine; `bone-curator` owns what a project's knowledge base says; `bone-team` owns the team tier;
`bone-user` owns the personal tier and its boundary. When a finding belongs to one of them, this
unit names the owner and stops.
