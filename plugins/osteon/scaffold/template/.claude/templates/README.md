# Skill archetypes and the L4 authoring contract

Skeletons for authoring skills, plus the rules that are local to this project.

**Why they are here and not in `.claude/skills/`.** Everything under `.claude/skills/` is a
**knowledge unit**: an artifact that carries claims and can therefore decay. A template carries no
claims. Leaving templates in the skills directory inflates the unit count, permanently depresses
provenance coverage, and makes the Context Decay Index read as healthier than it is. Templates are
tooling, so they live beside the tooling.

| File | For |
|---|---|
| `SKILL-TEMPLATE.md` | the general and repo-developer archetype |
| `GATE-TEMPLATE.md` | a gate (L5). A gate is a skill whose body is a checklist with a blocking verdict. |
| `meta.yaml` | the copyable sidecar skeleton. Copy it beside every new `SKILL.md`. |
| `META-TEMPLATE.md` | the sidecar schema, documented once. |

Templates for the other layers live next to the layer they serve, because that is where an author
looks: `docs/adr/ADR-TEMPLATE.md`, `docs/contracts/CONTRACT-TEMPLATE.md`,
`docs/state/STATE-TEMPLATE.md`, `docs/curation/CURATION-RECORD-TEMPLATE.md`.

## Local rules for `.claude/skills/`

Every skill there is T1: project facts and project procedures. The methodology's own units
(`bone-adr`, `bone-contract`, `bone-curator`, `bone-git`, `bone-onboard`, `bone-review`,
`bone-standup`) are T0 and live in `~/.claude/skills/`; they **MUST NOT** be copied here. Install
them once per machine: see `bone-skills/README.md`, section *Installing T0*.

The full authoring contract is normative in `bone-spec`. Only what is local is stated below.

1. Every capability unit is a **directory** named `{{PREFIX}}-<thing>` holding both `SKILL.md` and a
   `meta.yaml` sidecar. The directory name, `SKILL.md`'s `name` field and `meta.yaml`'s `name` field
   **MUST** all be equal. A `SKILL.md` with no `meta.yaml` is not a unit. Peer relations are
   declared **once**, in `meta.yaml` under `chains_with`; a `## Chains with` section in an entry
   document is a second enumeration of the same graph and is a lint failure.
2. A skill that is true for more than one project does **not** get a different prefix. It moves to
   T0. A foreign prefix inside `.claude/skills/` is a tiering error, not an exemption.
3. **MUST NOT** name a skill after a host, a vendor, or a person. All three guarantee a rename.
4. A skill **MAY** own at most one durable state artifact, and **MUST** declare it in a
   `## Storage and lifecycle` section naming the exact path. The skill is the instructions; the file
   is the state.
5. Bulk content extracts to `<skill>/references/`. Reference files are knowledge units in their own
   right: they are scanned, they decay, and they are audit targets, not background reading.
6. Every claim carries a provenance token per `CLAUDE.md`. Run `.claude/hooks/provenance-lint.sh` to
   see which claims do not chain to a source.

## Gates

A gate skeleton is only a gate once its id appears in `MANIFEST.yaml: gates`. That list is the single
enumeration of the gate set; a checklist that is not in it is a review aid, however hard its wording.

## Catalog

A catalog of the suite **MUST be generated**, not hand-maintained, from the `name` and first
description clause of every skill. A hand-maintained catalog silently misses new skills, and a
catalog that omits entries by convention is not a catalog.
