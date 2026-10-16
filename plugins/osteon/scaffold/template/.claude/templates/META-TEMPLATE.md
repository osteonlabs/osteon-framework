# `meta.yaml` - the capability unit sidecar

Every capability unit is a **directory** containing an entry document (`SKILL.md`) and a sidecar
`meta.yaml`. The sidecar is REQUIRED, not optional. A directory with a `SKILL.md` and no `meta.yaml`
is not a capability unit and does not count as one.

The copyable skeleton is `meta.yaml` in this directory. Copy it next to the new `SKILL.md`, keep the
comments while you fill it in, and delete them before committing.

## Why a sidecar and not prose

The old `## Chains with` footer was human-readable only. It could not carry a labelled relation that
a tool can traverse, it could not carry `owns`, and it could not carry typed negative knowledge with
an expiry. Three requirements had no carrier at all while it was the de facto record.

**Peer relations are declared exactly once, here.** A `## Chains with` section in an entry document
is a second enumeration of the same graph and is a lint failure. The entry document may still name a
peer inside a sentence that explains a hand-off; what it may not do is re-list the edges.

## Fields

| Field | Required | Type | Meaning |
|---|---|---|---|
| `name` | yes | string | MUST equal the directory name and the `name` in `SKILL.md` front matter. |
| `tier` | yes | `T0` \| `T1` \| `T2` | Which tier owns this unit. Everything under `.claude/skills/` here is `T1`. |
| `category` | yes | enum | `foundational` \| `repo-developer` \| `gate` \| `analysis` \| `toolchain` \| `governance` |
| `gate` | yes (nullable) | string | The gate id from `MANIFEST.yaml: gates` when this unit IS a gate. `null` otherwise. |
| `owns` | yes (nullable) | path | The at-most-one durable state artifact this unit owns. `null` when it owns none. |
| `chains_with` | yes (may be `[]`) | list | Labelled peer edges: `{ unit, relation }`. |
| `negative_knowledge` | yes (may be `[]`) | list | Typed records of what MUST NOT come back. |

### `chains_with`

```yaml
chains_with:
  - unit: {{PREFIX}}-context
    relation: "load first"
  - unit: {{PREFIX}}-contract-gate
    relation: "runs before merge on any seam change"
```

`relation` states what the edge **means**. "see also" is not a relation: it carries no information a
reader could act on, and a graph of unlabelled edges cannot be traversed by anything but a human.

### `negative_knowledge`

```yaml
negative_knowledge:
  - id: NK-1
    type: do-not-reintroduce      # do-not-reintroduce | retraction | historical-note
    text: "Do not reintroduce the shared write path."
    cause: "It existed to work around a limit that no longer applies."
    src: "adr/0009"
    expires: null                 # REQUIRED non-null for type `retraction`
```

- `do-not-reintroduce` is permanent: a decision that must not be re-made. `expires` stays `null`.
- `retraction` is a claim that was once published here and is now withdrawn. It MUST carry an
  `expires` date, because a retraction is only useful while someone might still be acting on the
  retracted claim; after that it is archaeology and belongs in the ledger.
- `historical-note` explains why something looks the way it does. It constrains nothing.

Negative knowledge is the class of fact that is hardest to recover and easiest to lose: nothing in
the code says why an approach is absent. Recording it typed, rather than as a paragraph, is what lets
a curation pass find it and re-check it.

## File form

`meta.yaml` is a plain YAML mapping with **no `---` document markers**. A leading and trailing `---`
would make it two YAML documents, the second empty, and a single-document loader would reject it.
