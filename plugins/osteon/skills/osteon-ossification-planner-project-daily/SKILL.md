---
name: osteon-ossification-planner-project-daily
description: Plan a multi-repository project's work as one dated cycle per day, held in the knowledge instance, and set the bar every task's definition of done must clear. Use at the start of a working day before opening any change request, when a merged change request needs marking done, and when a previous day's cycle is still open. One of the ossification planners, for a project planned daily. NOT the gate that decides whether a plan may start, which is `osteon-ossification-plan-starter`.
---

# Ossification planner: a project, daily

One project, one date, one cycle, spanning **every** repository. The cycle lives in
the knowledge BONE, because the BONE is the only place that can see all of them.

**A merge is not a completion.** That is the whole of this unit in one sentence.
The rest is the machinery that makes it checkable.

## Why the cycle is project level and not per repository

A day's work crosses repositories, and its consequences cross them in the other
direction. A setting seeded in one repository is the post-merge action of a
change in another. A wire change in a service is what a consumer in a third
repository needs for its next release. A cycle held inside one repository can
record only its own half of that, so the halves go missing in exactly the place
where they matter: between two repositories, owned by neither.

So there is **one** cycle per date for the whole project, and it accounts for
every repository the BONE's `MANIFEST.yaml` lists under `repos[]`, plus every
client surface those repositories serve. A repository absent from the cycle is a
repository whose work that day is untracked. **"None" is an answer; a blank is
not.**

## Where it lives

Every knowledge BONE carries an `ossification/` folder. It is the project's
full-chain record of work, distinct from `docs/` in that `docs/` holds what is
true and `ossification/` holds what is being done about it.

    ossification/
      plan/<date>/          one cycle. The day's ledger
      implementation/       what was actually built, and the evidence it works

- **MUST** keep the cycle in the BONE, never in a code repository. A code
  repository's own plan documents are a different artefact with a different
  lifetime, and this unit does not touch them.
- **MUST** name the plan folder by date, so two cycles sort and no reader has to
  ask which is current.
- **MUST NOT** put delivery captures in a code repository. They belong under
  `implementation/`, or wherever the project's own rule already puts them.

## The five actions

Closed vocabulary. A sixth verb is a second vocabulary the next project will not
find.

| Verb | What it does | Refused when |
|---|---|---|
| **ACTIVATE** | Opens cycle X for the whole project | Any open question is neither answered nor routed |
| **LOG** | Records a change request's activity under the open cycle, in any repository | There is no open cycle |
| **MINERALISE** | Marks a merged change request done | Its post-merge actions are unwalked, or any one of them is not green |
| **CARRY** | Moves an unfinished item from the closing cycle to the opening one | Nothing. An item that cannot be carried is an item that cannot be closed |
| **CLOSE** | Closes cycle X-1 | Any item is neither mineralised nor carried |

## When to run it

- **Before the first change request of a day, in any repository.** ACTIVATE, or
  find out that you may not.
- **After every merge, anywhere.** MINERALISE, or record why you cannot yet.
- **Whenever a cycle from an earlier date is still open.** That is a reversal
  waiting to happen, and it gets more expensive every day it waits.

## ACTIVATE

**MUST NOT** open a cycle while any open question is neither answered nor routed.
The questions are the owner's: they either answer, or they say who it goes to.
Both are permitted outcomes and only silence is not.

- **MUST** put the open questions in the cycle itself, each with who owns it. A
  question routed onward is **carried**, not closed: routing is not answering.
- **MUST** account for every repository in `repos[]` and every client surface
  they serve. Name the ones with nothing planned as having nothing planned.
- **SHOULD** state what the day intends to do, so the close has something to
  measure the day against besides what happened to get done.

## LOG

Every change request opened that day, in any repository, is logged under the open
cycle, and **every merge updates the cycle's status**. The cycle is a ledger
written as the day runs, not a document written once at the start and once at the
end.

- **MUST** record, per change request: the repository, what it changes, its
  state, and its post-merge actions with their owner.
- **MUST** record a cross-repository dependency as an edge, both ways. The
  commonest lost item is a post-merge action that belongs to a different
  repository from the change that created it.
- **MUST NOT** log into a cycle that is not the current date's. If the date has
  turned, the answer is a reversal, not an entry in yesterday.

## MINERALISE

A merge moves code. It does not walk a post-merge checklist, seed a parameter,
run a deploy, or check that any of those went green.

- **MUST** walk every post-merge action the change request declared, and see each
  one green, before the change request is marked done in the cycle.
- **MUST** record what was walked and what it returned, not that it was walked.
- **MUST NOT** mark done a change request whose post-merge actions belong to
  somebody who has not done them. That is a **carry**, with the owner named.

## CLOSE, and the reversal

**Opening cycle X and closing cycle X-1 are one change request.** Not two, and not
two days apart. That single change request is the reversal, and it lands in the
BONE.

Closing is the careful half:

- **MUST** resolve every item in the closing cycle to exactly one of two
  outcomes: mineralised, or carried into the opening cycle. There is no third.
- **MUST** check the closing cycle's own quality before closing it, not assume
  it. A plan that overstates what it finished is worse than one that is merely
  stale, because nobody re-reads a line that is already struck through.
- **MUST** count the cavities the close found and record the number. **A close
  that finds none on its first run is evidence the check is not working**, not
  evidence the practice was unnecessary.
- **MUST NOT** let the swap become a rename. Carrying items forward without
  reading them is the failure this verb exists to prevent.

## The bar a definition of done must clear

**This unit owns the standard. `osteon-ossification-plan-starter` owns checking it.**

A definition of done is a list of **falsifiable assertions**, not a restatement of
the title. The test is not "is this checkable" but **"what input would make this
assertion fail?"** If no such input exists, the assertion is decoration.

Each assertion **MUST**:

- name the command, route, file and line, query or screen that proves it, **and the
  answer required**. "The endpoint works" is refused. "`GET /v2/x` answers 200 with
  the key set `{a,b,c}` for an anonymous caller, asserted by a named test" is not;
- state **where** it is verified, and say so plainly when it can only be checked
  after a release, because such an assertion is unwalkable until then. Prefer one
  that holds in a pre-release environment plus a named post-release check;
- name the **count** whenever it names a test gate. A gate being green is not an
  assertion; the gate being green **and its collected count matching** is. A branch
  cut from a stale base passes lint, exits zero, prints no failure, and runs a third
  of the suite;
- for an assertion carried by a test, require the **mutation**: break the code the
  test guards and confirm it goes red. One run, and it is the only evidence that
  distinguishes a test from a comment.

And one class to refuse outright: **an assertion whose quiet state and whose absent
state are the same state.** A check that reads healthy when the thing it watches
stops existing, a test that skips when its fixture is missing, a gate that passes
when a step did not run. Each of those passes while measuring nothing.

**MUST NOT** accept a task whose deliverable is another task list, and **MUST NOT**
accept a predicate that cannot be false: "stop guessing", "retry honestly", "so the
next reader is not misled" are dispositions, not assertions.

## What this unit does not own

- Branch, commit and change-request mechanics, including what a change request's
  body must contain. `bone-git` owns those, and the project's own gate owns the
  body.
- Judging a diff. `bone-review` owns that.
- Who may merge. In single-session mode that is
  `osteon-single-session-ossification`'s rule, and this unit only says that a
  merge is not yet a completion.
- The knowledge base's own records. `bone-curator` owns those. A cycle is not a
  curation record, and adding `ossification/` to a BONE that lacks it is a
  curation event that unit owns.
- Which repositories exist. `MANIFEST.yaml` `repos[]` is the one enumeration and
  this unit reads it rather than keeping a second list.
