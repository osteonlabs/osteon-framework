---
name: osteon-ossification-plan-implementor
description: Run an ossification plan that has passed its gate, as ONE session that cuts lanes on shared surfaces and works them as parallel sibling subtasks, then carries finished work back into the plan. Use once a plan is calcified and building is about to begin, and whenever a lane finishes, stalls or discovers work the plan does not carry. Covers lane cutting, the parallel subtask shape, what may merge, and why a merge is not a completion. NOT the gate, which is `osteon-ossification-plan-starter`.
---

# Ossification plan implementor

The plan has passed its gate. This unit turns it into work and keeps the plan honest
while that happens.

**One session owns the plan, the gates, the merges and every verdict.** Parallelism
comes from **sibling subtasks inside that session**, never from a second session.
The distributed variant's coordination cost was measured and rejected; the rules
that made the single-session mode deliver are
`osteon-single-session-ossification`'s and are not restated here.

**Three actions. VASCULARISE, ADVANCE, REFUSE.**

## The biology

Calcified cartilage is inert until vessels invade it, carrying the cells that build.
The boundary between built and unbuilt is the **ossification front**, and it
advances rather than jumping.

## VASCULARISE: cut the lanes, then spawn siblings

**MUST** cut lanes on **exclusive shared surfaces**, not on subject matter. A lane
is a set of tasks sharing no exclusive surface with another lane. Two lanes that
both touch one state file, one protected branch, one account root or one migration
chain **are one lane wearing two names**.

**MUST** place every **cannot-start** edge inside one lane, or make it a lane
boundary with an explicit handover. **MUST NOT** let a **cannot-verify** edge force
serialisation: it constrains when something can be PROVED, not when it can be built,
and conflating the two is the commonest way a plan invents its own critical path.

**MUST** schedule the external parties first and separately. They cannot be
compressed by adding people, so they set the floor for the whole programme and
everything else is planned around that floor rather than into it.

**SHOULD** start the lane that unblocks the most other lanes, which is rarely the
one that sounds most urgent.

Then, inside the session:

- **MUST** spawn one subtask per lane, as siblings, and run them concurrently.
- **MUST** give every subtask the same four blocks: the constraints in full, the
  measured facts marked do-not-re-derive, its scope line with the instruction to
  stop rather than guess, and the gates it must clear.
- **MUST** serialise anything that contends for an exhaustible machine resource
  even when the lanes are independent. Independence of surface is not independence
  of disk.
- **MUST NOT** let a subtask merge, and **MUST NOT** accept a subtask's own report
  of a fresh claim as the verdict. Refutation by a different subtask is what turns a
  report into a verdict.

## ADVANCE: carry the work back

The front advances when built work re-enters the plan. **This is where plans rot.**

- **MUST** record against the task: which change request, which merge, and the
  verdict **per assertion** of its definition of done.
- **MUST NOT** mark a task done on a merge. A merge moves code and walks no
  checklist. Completion is the planner's MINERALISE and is not restated here.
- **MUST** re-open the gate over any part of the plan that changed shape: a new
  blocking finding, a task that turned out to be two, a dependency discovered
  mid-flight. **A plan is calcified, not frozen.**
- **SHOULD** report at every lane boundary crossing rather than at lane completion,
  because a boundary is where another lane is waiting.

## REFUSE: record what was checked and was false

**MUST** record a refused verdict, not only a met one. A plan that cannot record
"this assertion was checked and was false" computes a completion rate of one by
construction, and that is the same defect as a check that cannot fail.

**MUST** treat a self-reported completion as a claim. Measured: roughly a fifth of
them do not survive a subtask whose only instruction is to refute them.

**MUST** stop the lane rather than guess when a task meets an unanswered decision,
and hand it back to `osteon-ossification-plan-starter` to be asked. A lane that
resolves an open ruling to unblock itself has made a decision nobody ratified.

## What this unit does not own

- The gate and the asking: `osteon-ossification-plan-starter`.
- The plan, its cycles, its ledger and MINERALISE: the ossification planners.
- The single-session mode's own ten rules and their measured evidence:
  `osteon-single-session-ossification`.
- Branch, commit and change-request mechanics: the distribution's version-control
  unit.
