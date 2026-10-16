---
name: bone-onboard
description: Cold-start procedure for a human or agent meeting a BONE-governed project, or returning after a gap. Gives the exact read order (L1, MANIFEST, L2 indexes, then only the relevant L4), separates what is currently true from what was once true, and ends in an orientation whose first action names the fact it depends on. Use when asked "get up to speed", "onboard me", "pick this back up", or a session starts in an unfamiliar repo. Makes time-to-first-correct-action collectable. NOT for the daily rhythm (bone-standup) or for changing anything (bone-git). Load before the project's T1 context skill.
---

# BONE Cold Start

Reach the first correct action in an unfamiliar project without reading everything and without acting on expired facts. This skill is the entry point: it MUST run before the project's T1 context skill, and it names which skills to load after.

> **Cold start is measured, not narrated.** Every run records a start timestamp and, later, the first action judged correct. That pair is the project's time-to-first-correct-action. A run that produces an orientation but no record is an incomplete run.

> **Read the least that permits a correct action.** Reading the whole knowledge base is not thoroughness; it is cost with no verification. Stop at the point where the next action's load-bearing fact is established and cited.

## When to use

- A session begins in a repository or project the operator has not worked in, or has not worked in for longer than the project's staleness horizon.
- A person or agent is handed the project, or a project is restarted after dormancy.
- Before the first change in an unfamiliar codebase, ahead of `bone-git` and any repo skill.

## Read order

Follow in order. Each step states what to extract and what would make it wrong to continue. Locations resolve through `paths.*` in the manifest; the canonical defaults are shown.

| # | Read | Extract | Stop and report if |
|---|---|---|---|
| 1 | `paths.constitution` (L1) | the non-negotiables, the always-on governance clause, what may not be decided unilaterally | it is absent: the project is not BONE-governed, say so before proceeding |
| 2 | `MANIFEST.yaml` (L1) | repos and their roles, environments, owners, systems of record, the gate set by `id`, and `watched` | a path it declares does not exist: the manifest is stale, which invalidates every later step |
| 3 | the decay signal | the Context Decay Index with its internal and external halves, its denominators, and which units are stale | the index is above `curation.cdi_threshold`: curation is owed before non-trivial work (route to `bone-curator`, do not curate here). `null` means it was never measured, which is not the same as healthy |
| 4 | L2 decision index (`paths.ledger`) | the accepted and operative decisions, and the open ones. Read the index, not every record | the index disagrees with a record: the record text wins, and the mismatch is a finding |
| 5 | L2 state index (`paths.state`) | what is verified true today, and each record's `verified_at` | a record you are about to rely on is past the staleness horizon: re-verify it before using it |
| 6 | L3 `paths.domain` | the sanctioned name for each concept, so nothing gets renamed by accident | a term in the task has no entry: it is either new or a synonym, and both are findings |
| 7 | L3 `paths.contracts` index | which seams exist and which sides implement them | only if the task touches a seam; otherwise skip and say you skipped it |
| 8 | the T1 context unit, then **only** the L4 units the task needs | the procedures for the work at hand | you are loading a fourth unit without having named why: stop and re-scope |

**MUST NOT** read repository source code as the first move. Code answers *how*, expensively; L1 to L3 answer *what and why*, cheaply, and tell you which code is worth opening.

**MUST NOT** treat a `README`, a comment, a chat transcript, or a wiki page reached from outside the BONE as evidence. They are unowned by construction and are the usual source of a confident wrong start.

## Currently true vs historically true

The most common cold-start failure is acting on a claim that was true when written. Resolve every load-bearing fact through this ladder, highest wins.

| Rank | Source | Answers |
|---|---|---|
| 1 | a live observation made this session | what is |
| 2 | a `paths.state` record within the staleness horizon | what is |
| 3 | the integration branch's code and configuration | what is |
| 4 | an accepted, operative decision record or a versioned contract | what must be |
| 5 | an L4 claim carrying a resolvable provenance token | derived, trust at one remove |
| 6 | anything else | untrusted |

- **A live observation MUST be routed the same turn to `bone-curator` as a proposed state-record replacement (verb UPDATE, class D1d), never written directly**, otherwise the next session pays for it again and the ladder has no rank-2 entry.
- **Ranks 1 to 3 and rank 4 do not compete.** State and code say what the system does; decisions and contracts say what it must do. A disagreement is not a tie to break, it is a defect: a merged change has suspended a decision, and that owes an amendment (route to `bone-adr`, and see `bone-review` K1).
- **Historical truth is still valuable.** A superseded decision records a rejected path and the reason, which is what stops the newcomer re-deriving it. Read it as history, never as instruction.
- **A decision record with status `accepted` is not automatically operative.** Check the operative flag and any stated preconditions before relying on it.

## Orientation output

Produce this before taking any action. At most one screen.

1. **What the project is**, in two lines, and which repos are in scope for the current task.
2. **What is decided**: the two or three operative decisions that constrain this task, each with `[src: adr/NNNN]`.
3. **What is undecided**: the open decisions that would change the approach if resolved. Naming these is the point; an agent that does not know what is unsettled will settle it silently.
4. **What is stale**: the index with its denominators, and the specific records past the staleness horizon that this task depends on.
5. **What gates apply** to the change classes this task implies, by `id`.
6. **Who owns what** is unanswerable here, and by which route.
7. **The single next action**, stated as: *the action*, *the load-bearing fact it depends on*, and *that fact's provenance token*.

Item 7 is the instrument. An action whose fact cannot be cited is not yet a first action; it is a guess, and it MUST be reported as one.

## Time-to-first-correct-action

**Definitions, so the number is comparable across runs and projects:**

- **t0** = the moment this skill opens the first BONE file in a session. Recorded at step 1.
- **First correct action** = the first action that (a) depends on at least one project-specific fact, (b) was cited in orientation item 7, and (c) is accepted without a context-caused correction by a named human or by a gate verdict. A typo fix, a `ls`, or a question is not an action.
- **Context-caused correction** = a correction whose cause is a wrong, missing, stale, or wrongly-tiered fact, as opposed to a reasoning or coding error. Classify with `stale-fact` · `missing-fact` · `wrong-tier` · `no-provenance` · `not-context`.
- **Cold** = the operator had no prior session in this project inside the staleness horizon. A warm run is still recorded and MUST be marked `cold: false`; mixing the two is how this metric becomes meaningless.

**MUST append one JSON line to `onboarding.jsonl` under `paths.metrics`** when the first action is judged, with: `id`, `date`, `project`, `operator` (`human` or `agent` plus model identifier), `cold`, `t0`, `t_first_action`, `elapsed_minutes`, `tokens_to_first_action` (if measurable), `files_read`, `layers_read[]`, `cdi_at_start`, `corrections_before[{class, source}]`, `judged_by`, `outcome` (`correct` · `corrected` · `abandoned`).

**MUST NOT** self-certify. `judged_by` names the human or the gate that accepted the action. An agent scoring its own first action measures its confidence, not its correctness.

**SHOULD** record a run that fails. An abandoned cold start, with the correction classes that caused it, is the highest-value row in the file: it names which fact had no owner.

## Critical gotchas

- **A confident summary is the failure mode, not the success mode.** A cold agent given a stale knowledge base produces fluent, well-cited, wrong orientation, and nothing in the output signals the difference. This is why item 4 of the orientation is mandatory and why the CDI is read before the ledger. *General rule: an artifact that cannot express its own uncertainty will express false certainty.*
- **Dormancy expires facts silently.** Nothing changes in the repository while a project sleeps, so every record still reads as current on the day the work resumes. The horizon, not the file, decides. *General rule: freshness is a function of elapsed time, never of last edit.*
- **Reading everything is a failure with good intentions.** A cold start that loads every artifact spends its budget before the first action and still misses the one stale fact that mattered. *General rule: read to a decision, not to completion.*
- **The newest record is rarely the highest number.** Amendments land on old identifiers, so an index sorted by number puts the most recent change in the middle. *General rule: sort by when it changed.*
- **A fact you verified and did not write down was not verified.** The next session repeats the check, or skips it because someone remembers the answer. *General rule: verification that leaves no record is consumption, not investment.*

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here.

This skill **establishes what is true and how it is known**; `bone-standup` establishes **where the work stopped**; `bone-review` applies the same ladder to a diff. None of them may change the knowledge base, which is `bone-curator` alone.
