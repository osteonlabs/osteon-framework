---
name: osteon-ossification-plan-starter
description: Decide whether an ossification plan may start, and get every open decision answered by asking the owner one clear question at a time rather than reporting that questions exist. Use when a plan is declared ready, when its author says it is complete, and when a plan has been running and its state is unclear. Covers the ten gate conditions, what input refuses each, and how to put a decision to a human so it can be answered in one line. NOT the plan itself, which an ossification planner owns, and NOT the run, which is `osteon-ossification-plan-implementor`.
---

# Ossification plan starter

A plan is not work. This unit is the gate between them, and it exists because that
transition has been made by assertion: somebody says the plan is ready and building
begins.

**Two obligations, and the second is the one that gets skipped.** Run the gate. Then
**ask**, interactively, until nothing is open. A gate that reports "three questions
are unanswered" and stops has converted a decision into a status line.

## The biology, because it is the argument

Cartilage does not become bone by being declared bone. The template **calcifies**
first, which is what makes it replaceable, and calcification also kills the cells
that were still shaping it: **planning stops**. A plan still being edited cannot be
started.

## CALCIFY: the ten conditions

Each is refused by a specific input. **A condition nothing can fail is not a
condition.** Run in order; the first failure stops the gate, because a plan failing
G1 will fail others for reasons that disappear when G1 is fixed.

| # | Condition | Refused when |
|---|---|---|
| **G1** | Every open question is answered, or routed **and delivered** | A question is routed to a person and the message has not been sent. **Drafted is not routed** |
| **G2** | Every dependency names a task that exists | A `depends_on` resolves to nothing, or to an id in a survey rather than in the plan |
| **G3** | Deduplicated by **meaning**, not by id | Two tasks would produce the same change under different ids |
| **G4** | No two tasks conflict | Two cannot both be right, or both edit one exclusive surface with no ordering |
| **G5** | Every definition of done clears the bar | An assertion has no input that would make it fail. The bar itself is the planner's: see `osteon-ossification-planner-project-daily` |
| **G6** | Every blocking finding has a task, or a recorded reason it has none | Evidence names a blocker and the plan is silent |
| **G7** | Every dependency edge carries its kind | An edge does not say cannot-start or cannot-verify |
| **G8** | Every exclusive shared surface is named with its mutex | Two lanes reach one state file, branch, account root or migration chain and the plan is silent |
| **G9** | Every task has an owner who is a person or a named role | An owner reads `unassigned`, `TBD` or `the team` |
| **G10** | The critical path is named, and every external party on it | The plan cannot say what it waits for, or on whom |

**MUST** record a verdict **per condition with its evidence**, never one word.
**MUST NOT** start on a partial pass.

**The checker is code and carries the same defects as the code it gates.** Run it
against an input that must fail before trusting a pass. A first draft of this gate
over-reported unfalsifiable definitions of done through an over-strict pattern and
simultaneously reported zero duplicates while dozens sat in the plan, because it
compared ids and not meaning. Both directions of error in one run. **A pass reads as
"the checker found no failure", which is not "there is none".**

## ASK: turn every open thing into an answerable question

**MUST** put every open decision to the owner as a discrete question, and **MUST
NOT** hand back a list and wait. The shape that gets answered:

- **One decision per question.** Two bundled decisions get one answer and the other
  is lost.
- **Two to four concrete options, each with its consequence**, and say which you
  recommend and why. An open-ended question returns an open-ended answer.
- **Name what is blocked** while it is open, in the question itself, so the owner
  can price their own delay.
- **Where the answer is somebody else's**, the question is not "what should we do"
  but "do we ask them, and who sends it". Routing is a decision too.
- **Batch by audience, not by subject.** Everything for one external party is one
  message, drafted for the owner to send, because a person who receives five
  messages answers the easiest.
- **Never infer an answer from silence**, and never record a recommendation as a
  ruling. An adopted-pending-the-owner item stays adopted until they say the word.

**MUST** write each answer into the project's decision register as it arrives, not
at the end. An answer that lives only in a conversation is an answer the next
session cannot find.

**Repeat until nothing is open.** The gate is not re-run per answer; it is re-run
once when the answers land, because each answer can delete tasks and change edges.

## What this unit does not own

- The plan, its cycles and the definition-of-done bar: the ossification planners.
- Cutting lanes and running the plan: `osteon-ossification-plan-implementor`.
- Recording a refused condition as evidence that compounds: `osteon-capture`.
