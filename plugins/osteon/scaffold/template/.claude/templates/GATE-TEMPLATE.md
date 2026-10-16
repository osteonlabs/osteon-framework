---
name: {{PREFIX}}-<gate>
description: "<WHAT this gate checks in one clause. Run before merging any change that <change class 1>, <change class 2>, or <change class 3>. This is a hard gate, not advisory; any FAIL blocks the merge. NOT for <adjacent concern> ({{PREFIX}}-<sibling>). Load {{PREFIX}}-context first.>"
---

<!--
Copy to .claude/skills/{{PREFIX}}-<gate>/SKILL.md, copy `meta.yaml` from this directory beside it with
`category: gate` and `gate:` set to the gate id, AND add the gate to MANIFEST.yaml: gates in the same
change. A checklist that is not in that list is a review aid, not a gate.
Angle-bracket fields are filled in by the author. Delete every comment before committing.
-->

# <Gate name>

<One line: what class of defect this gate exists to stop reaching the default branch.>
Load `{{PREFIX}}-context` first.

> **This is a hard gate, not advisory. Any FAIL blocks the merge.**

## When to run

Run this gate on any change that:

- <change class, stated so a reader can decide in one pass>
- <change class>

Skipping it requires a documented exception (see below), never a judgement call in the moment.

## Checklist

<!-- Each item states its own FAIL condition. Item ids are stable identifiers: when scope grows, add
     a letter suffix (6, 6b, 6c). NEVER renumber, because other skills, ADRs and merge requests cite
     these ids. -->

| # | Check | FAIL when |
|---|---|---|
| 1 | <what is verified> | <the exact condition that fails it> |
| 2 | <...> | <...> |
| 3 | <...> | <...> |

## Documented exceptions

A known, accepted violation is verified, not auto-failed. An exception MUST cite the ADR that
accepted it and MUST list the mitigations that are checked instead.

| # | Exception | Accepted by | Mitigations to verify |
|---|---|---|---|
| <n> | <what is allowed> | `[src: adr/00NN]` | <what is checked instead> |

<!-- A gate that cannot express an accepted exception gets disabled the first time it is wrong.
     One that can, survives. -->

## Output

Report every item as `PASS` / `FAIL` / `NEEDS-INFO`, each with a locator (`file:line` or a resource
id) and, for every FAIL, a one-line remediation.

- **Any FAIL blocks the merge.**
- **NEEDS-INFO blocks until resolved.** It exists so an under-determined item cannot be recorded as a
  false pass, which is the failure mode of a two-verdict gate.
- A verdict without a locator is not a verdict.
- End with a one-line overall verdict.

Record the run in `metrics/gates.csv`, and record any defect of this gate's class that reached the
default branch anyway. Catch rate is only meaningful with both numbers.

## How this gate grows

Every check here **MUST** trace to a specific incident or decision. A gate list that is designed up
front and never grows is a dead gate list; a gate list that grows without evidence becomes ceremony
and is eventually ignored.

<!-- THERE IS NO `## Chains with` SECTION. Declare the peers in this unit's `meta.yaml` sidecar,
     for example `{{PREFIX}}-context` with relation "load first" and `bone-review` with relation
     "composite reviewer that delegates into this gate". -->
