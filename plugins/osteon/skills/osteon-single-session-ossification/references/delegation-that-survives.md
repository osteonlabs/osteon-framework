# Delegation that survives an unreliable admission path

Measured over more than a hundred subagent attempts in one session, of which about one in
six did not land; the exact readings are held privately. Everything below follows
from grouping the failures by **how far they got**, which is a question nobody
thinks to ask because from the outside every failure looks the same, as the task
not finishing.

## R1 Classify a failure before mitigating it. MUST.

Group failed attempts by tool-call count, or by transcript length as a proxy.

| | admission failure | mid-work failure |
|---|---|---|
| tool calls | **0** | more than 0 |
| runtime | short, and clustered | variable |
| what it did | nothing | some of the work |
| what helps | retrying | a smaller or different task |
| what does NOT help | anything about the inputs | retrying the same thing |

In the measured session the two populations were unmistakable once separated:
failures had a median of **zero** tool calls and about a quarter of the runtime,
against several dozen calls for successes. Nearly nine in ten were identical in
shape, a prompt in, no tool call, one refusal, dead.

**MUST NOT mitigate before classifying.** The operator in that session diagnosed the
cause twice, first as input size and then as concurrency, and twice applied a change
that could not work: several megabytes were trimmed from the agents' optional
reading list, which changes nothing for an agent that never reads a file. That trim
cost a rewrite and bought nothing.

## R2 An admission failure is an independent event, so retry immediately. SHOULD.

A refusal at admission is not evidence about the task. It is evidence about the
moment. So the correct response is the same attempt again, and the wrong responses
are making the prompt smaller, splitting the task, or waiting for a quiet period.

In the measured session every surface that was retried enough times eventually
landed, and no surface that landed needed its prompt changed to do so.

## R3 The first request is mostly not yours. SHOULD know the number.

Measured payload of one agent's first request: **the orchestrator's own prompt was
a small fraction of it.** The rest arrived automatically at agent start, a skill
listing and a standing instruction block being the bulk, near four fifths together.

Two consequences. Shrinking your prompt moves roughly one fifteenth of the number,
so it is not a lever. And concurrency is a real lever, because N simultaneous agents
present N of those, and that is a property of the fan-out rather than of any task.

## R4 Prefer many cheap attempts to few careful ones. SHOULD.

Under R2 the expected number of attempts to land one agent is fixed and small, so a
loop that retries three or four times per unit converges, while one attempt per unit
followed by a human deciding what to do converges only as fast as the human looks.

    async function resilient(make, label, attempts = 4) {
      for (let i = 1; i <= attempts; i++) {
        const r = await make(i)
        if (r) { if (i > 1) log(`${label} landed on attempt ${i}`); return r }
        log(`${label} refused on attempt ${i} of ${attempts}`)
      }
      log(`${label} exhausted ${attempts} attempts, continuing without it`)
      return null
    }

**MUST return partial results rather than failing the run.** A fan-out that returns
nothing because one unit never landed throws away every unit that did.

## R5 Persist each result the moment it exists. MUST.

A result that lives only in the orchestrator's memory is lost when the run is
stopped, resumed or edited. In the measured session each completed unit was written
to its own file as soon as it appeared, and that decision survived repeated full
run restarts: the units banked early were never derived twice.

The orchestration layer's own cache is not this. A cache keyed on the prompt is
invalidated by editing the prompt, which is exactly what a session does when it
improves the instructions after a failure.

## R6 Order units so that partial progress is the most useful partial progress.

If the run will not finish, what it did finish should be the part that unblocks the
most. Put the units others depend on first, and the independent ones last.

## What would show this wrong

A failed-agent population whose median tool-call count is materially above zero,
which would mean the failures happened during work and R2 is the wrong remedy for
them. Or a case where reducing what an agent was instructed to read measurably
lowered a zero-tool-call failure rate, which would mean admission cost does depend
on the instruction body after all.
