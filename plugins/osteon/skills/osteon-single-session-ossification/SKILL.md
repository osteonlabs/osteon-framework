---
name: osteon-single-session-ossification
description: Run an ossification as ONE session with subagent osteoblasts, instead of several cooperating sessions signalling each other. Use when a large plan must be executed quickly and cheaply, with the session owning the plan, the merge and the verdict and delegating only the work. Covers the rules that made it deliver, the failure modes it removes, and the measured cost of the multi-session alternative. NOT the multi-session variant, which is `osteon-framework`'s Ossification entry.
---

# Single-session ossification

One session holds the plan, the merge and the verdict. Subagents and workflows do
the work. **No session ever talks to another session.**

This is Ossification with the parallelism moved inside a session. The biology is
unchanged: one ossification center whose osteoblasts work the whole front,
instead of several centers meeting at growth plates.

## Why this mode exists

The multi-session variant was tried and measured. Its cost is **signalling**:
leases, broadcasts after every fusion, a registry and ledger, a rebase whenever
another center lands, and an orchestrator whose whole job is granting permission.
Every one of those is tokens spent on coordination rather than on work, and the
overhead grows with the square of the number of sessions, not linearly.

The single-session mode deletes the entire canaliculi layer. There are no
leases because there is one writer. There are no broadcasts because there is one
reader. There is no registry because the session's own control flow is the
registry.

**What you give up:** wall-clock. One session is a serial merge queue. Accept it.
The measured trade was heavily favourable.

## The rules

### 1. The session merges. A subagent never merges.

Delegate the build, never the verdict. A subagent pushes a branch and reports;
the session gates it, reads the diff, and merges. This is the single most
important rule: it is what makes one session's judgement the bottleneck rather
than N sessions' agreement.

Tell every agent explicitly: **push the branch, do NOT open a pull request, do
NOT merge.**

### 2. Every agent prompt carries four blocks

Omit any of them and you get work you have to throw away.

- **Absolute constraints.** Where it may write, the commit identity, what it must
  never run, and the credential to use. Repeat them in full every time. An agent
  does not inherit the session's caution.
- **Measured facts, marked "do not re-derive".** Everything already established,
  with its measurement. Without this, ten agents re-measure the same host and two
  of them get it wrong.
- **The scope line.** What is gated on a ruling or a decision, and the instruction
  to **stop and report rather than guess** if the work seems to need it. Agents
  will otherwise resolve an open question silently because it blocks them.
- **The gates**, with the verdict rule: judge by exit code AND by reading the full
  summary line.

### 3. Adversarially verify every fresh claim

An agent that reports its own work marks it done. Hand each fresh DONE claim to a
different agent whose only instruction is to **refute** it, defaulting to refuted
when uncertain.

Measured: **about one in five DONE claims did not survive refutation**.
A plan that overstates what is finished is worse than one that is merely stale,
because nobody re-checks a struck-through line.

### 4. Serialise anything that competes for a machine resource

Concurrent heavy builds exhausted the disk and blocked every tool,
including the shell's own output file. Builds and heavy verification run one at a
time, and each deletes its build output as its last action.

Parallelise reading. Serialise building.

### 5. Measure the wire; never trust a fixture or a document

The recurring defect in client-side code is a field the wire never sends, given
a default and rendered as data. The fixtures fabricate exactly those fields, so
the tests agree with the bug.

A 401 proves a route exists. A 404 proves it does not. Never treat a 401 as
absence.

### 6. Compose conflicts; settle behaviour against the system, not by recency

When two branches touched the same lines for different reasons, keep both
intents. When they genuinely disagree about **behaviour**, decide by what the
hosts actually answer.

"Take the newer side" is not a rule. In one merge the newer side was calling an
endpoint a decision had deliberately retired.

**A clean merge can still fail to compile.** Git reported fewer
conflicts than the merge had problems: separate test modules merged into one file
with no conflict at all. The conflict count is not the size of the merge.

### 7. Stop at the ruling boundary

Where an open decision governs the work, build up to it and stop. Record the
question, name its owner, and say what it blocks.

Guessing there is worse than stopping: a guessed mapping between two identifiers
is a guess about a consequence someone else will bear.

### 8. Clean up after every merge

Remove the worktree as part of merging, not as a later sweep. Otherwise the
machine fills and the failure surfaces as an unrelated gate failure hours later.

### 9. Run the thing, do not only read its tests

Some defects are invisible to a green suite and obvious within seconds of running
the app.

### 10. Verify the verifier

Gate tooling is code and has bugs. A land script checked test output for a
failure count but not the exit code, so a build error, which prints no count,
would have passed as green. Check that your own gate fails when it should.

## Evidence

One session over two working days, against a plan of several hundred tasks
spanning more than one repository. The exact readings are held privately; the
relative measures are these.

| Measure | Reading |
|---|---|
| Change requests merged | more than a dozen, in one session |
| Plan tasks settled | roughly doubled, from about a fifth to about two fifths |
| Test suites | each grew by roughly three quarters or more |
| DONE claims overturned by refutation | about one in five |

Several of the shipped defects that were removed rendered a failure
as a success or a success as a failure.

The durable artefact was not a fix. It was a guard that fails the build when a
schema defaults a field the wire does not send, a pattern that had caused several
separate defects.

## What this mode does not solve

It does not make blocked work unblocked. **Roughly one task in ten was blocked on
a human decision or an access someone else held**, and no amount of parallelism
moves them. Identify them early and report them as a list with owners, because they are
the only part of the plan that cannot be worked.

## Delegating when the admission path is unreliable

Six rules, measured over more than a hundred subagent attempts, are in
`references/delegation-that-survives.md`. The one that subsumes the others:
**classify a failure by how far it got before mitigating it.** An attempt with zero
tool calls was refused at the door and nothing about its inputs can change that; an
attempt that failed after real work is a different fault. From outside they look
identical, which is why the wrong remedy gets applied twice before anyone measures.

## References

- The multi-session variant, its vocabulary and its roles: `osteon-framework`,
  methodology register, Ossification.
- Its counterpart for a living bone: Remodeling, same register.
