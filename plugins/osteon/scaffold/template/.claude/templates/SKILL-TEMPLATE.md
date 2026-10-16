---
name: {{PREFIX}}-<thing>
description: "<WHAT this does in one clause. Use when <trigger 1>, <trigger 2>, <trigger 3> - phrased the way the user phrases it, using their standing phrases verbatim. NOT for <adjacent territory> ({{PREFIX}}-<sibling>) or <other territory> ({{PREFIX}}-<sibling>). Load {{PREFIX}}-context first.>"
---

<!--
Copy to .claude/skills/{{PREFIX}}-<thing>/SKILL.md, AND copy `meta.yaml` from this directory beside
it. A capability unit is a DIRECTORY holding both; a SKILL.md with no meta.yaml is not a unit.
The directory name, the `name` field here, and `name` in meta.yaml MUST all match.
Angle-bracket fields are filled in by the author. Delete every comment before committing.

FRONTMATTER IS EXACTLY TWO KEYS: name, description. No version, no owner, no tags, no allowed-tools.
The description is the ONLY thing a cold agent sees before deciding whether to load this file, so it
is a discovery surface, not an abstract. Required shape:
    WHAT (one clause) . WHEN (at least 3 symptom or vocabulary triggers) .
    NOT-WHEN (at least one named sibling) . LOAD-ORDER (one clause).
Target 300 to 600 characters, one unwrapped line.
PROHIBITED in the description: any fact that can change. No versions, no decisions, no counts, no
resource names, no status. Curation passes sweep bodies; frontmatter rots unnoticed.

SIZE: 5 KB target, 10 KB hard cap. Extract to references/ when the file exceeds 10 KB, when a block
exceeds 3 KB, when a block is looked up rather than read, when a block changes on a different cadence
than the rest of the file, or when the block would otherwise be pasted twice.
-->

# <Human readable name>

<One to four lines: what this is and who it is for.> Load `{{PREFIX}}-context` first.

> **<The one non-negotiable framing rule, if there is one.>**

## When to use

- <trigger restated for the reader who has already loaded the file>
- <trigger>

## <The subject> in one screen

| <Part> | <Role> | <Where> |
|---|---|---|
| <...> | <...> | `<path>` |

## Golden rules

<!-- Numbered, imperative, 8 to 14 items. Every line carries a modal marker and a provenance token
     where it asserts a fact. -->

1. **MUST** <rule>. `[src: adr/00NN]`
2. **MUST NOT** <rule>, because <the failure it prevents>.
3. **SHOULD** <rule>.

## Critical gotchas

<!-- The most transferable writing pattern in the corpus: specific failure, then the mechanism, then
     the generalized rule. End each with a stack-level statement so the lesson survives being applied
     to another project on the same stack. Demote project nouns to "for example". -->

- **<Bolded lead clause naming the failure>.** <What actually happened and the mechanism that caused
  it, with evidence.> General rule: <the stack-level statement>.

## Commands

```sh
# <what this does and when to run it>
<command>
```

## Storage and lifecycle

<!-- ONLY if this skill owns a durable artifact. At most one per skill. -->

This skill owns `<path>`. This file is the instructions; that file is the state. <How it is
reconciled when the world changes.>

## References

<!-- Each pointer states what is inside AND the consequence of not reading it. A pointer that carries
     the consequence is measurably more likely to be followed than one that carries a summary. -->

- `references/<file>.md` - <what is inside>. Read it before <action>: <what goes wrong otherwise>.

<!-- THERE IS NO `## Chains with` SECTION. Peer relations are declared exactly once, in this unit's
     `meta.yaml` sidecar (`chains_with`), which is the machine-readable carrier. A prose list here
     would be a second enumeration of the same graph and is a lint failure. Where three units crowd
     one domain, a boundary sentence in the body still helps: "This unit defines X; A runs Y; B owns
     Z." That is explanation, not an enumeration. -->
