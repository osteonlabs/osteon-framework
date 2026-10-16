# The methodology register

The one enumeration of named methodologies in OSTEON. A methodology named anywhere else is a
second vocabulary the next project will not find. Entries never name a project, a vendor or a
person; evidence cites readings and curation records, which the tier rules do not de-identify, so
an entry's author does.

## Entry schema

Every entry carries these fields, in this order, so two entries can be compared without reading
prose. A field with nothing to say is written `none`, never omitted.

    name          the framework-metaphor name
    metaphor      the biological process it is named after, in one sentence
    problem       the one-sentence problem it solves
    status        proposed | accepted | superseded
    named         when the name was fixed: its order, or a date the owner has made public
    vocabulary    a table of concept to term
    roles         who does what, by term
    bootstrap     how the methodology's actors are brought up and verified before work starts,
                  or none when it needs no bring-up. Declared because a methodology that cannot
                  start correctly cannot run correctly, and the order is load bearing
    principles    each stated with the failure it prevents
    evidence      readings and curation records, de-identified
    executes      the capability units that carry it out, or none
    owes          what acceptance still requires: units not yet written, a specification revision
    runs          one line per execution: a runs-ledger id or withheld, a public or relative date,
                  and the owes items it discharges. The only field permitted to reduce owes
    accepted      the date and the owner's sign-off, or none. Written only when owes reads none

A methodology carries no rule of its own. A principle here is an explanation of why a practice
works; anything an instance must obey is a numbered requirement in the specification.

Until `runs` existed this register had a debt column and no credit column, so an entry could satisfy
its owed condition perfectly and stay `proposed` for a structural reason rather than an evidential
one. A `runs` id resolves to a row in the capture ledger's runs stream, whose measures each carry a
locator, so a figure here can be re-derived instead of retyped. Until the ledger is released
de-identified, only its holder re-derives a withheld row.

## The unit families, and how a methodology's units are named

A methodology's name is its **framework-metaphor** name and does not change when its
units are reorganised. Its units are named **functionally**, so a reader can tell
from the name what a unit does without opening it.

Four families carry ossification:

| Family | Names like | Owns |
|---|---|---|
| **planners** | `osteon-ossification-planner-<scope>-<cadence>` | Producing the plan and setting the bar its tasks must clear. `-project-daily` exists. `-repo-onetime` and others are expected; each is a different scope or cadence, never a different opinion about the same one |
| **starter** | `osteon-ossification-plan-starter` | Deciding whether a plan may start, and getting every open decision answered. One, because the gate is the same whatever produced the plan |
| **implementor** | `osteon-ossification-plan-implementor` | Turning a calcified plan into work and carrying it back. One, because the lane rules do not vary by planner |
| **teacher** | `osteon-ossification-delivery-teaching` | Turning plan state and landed work into what a person outside the session can read, test and act on: graded by evidence, written per audience, rendered as documents. One, because the evidence ladder and the editions do not vary by planner |

**MUST NOT** let a second planner restate the starter's gate or the implementor's
lane rules. A planner that does is a family of three wearing one name, and the
duplication will drift. **MUST** state a new planner's scope and cadence in its
name, because "which planner produced this plan" is the first question a reader of
a plan has. **MUST NOT** let the teacher change a task state: it reports what the
plan and the hosts say, and a report that edits the plan is a second writer of it.

## Admitting a methodology

- **MUST** move `status` from `proposed` to `accepted` only when every **work item** in `owes` names
  a discharging entry in `runs`, **and** the owner signs off in the same commit, **and** the question
  that acceptance itself makes a condition is asked and answered in writing: does this methodology
  need a specification requirement the specification does not have. Nothing currently asks it.
- **MUST NOT** require a sign-off item in `owes` to name a run. A signature is not a run, and an
  entry whose only remaining debt is the owner's acceptance would otherwise be permanently
  un-acceptable.
- **MUST** treat promotion as discharge and **MUST NOT** count. A count would promote an entry that
  owes four units, a protocol and a schema the moment its first run landed, with its executing units
  still unwritten.
- **MUST** cite the `runs` id that produced it on every `principles` line added after a run. One
  token per line is what stops this register being a design document.

---

## Ossification

**metaphor** Endochondral ossification: a long bone forms from a full-size cartilage model, in
which several ossification centers turn their own region into bone in parallel, kept apart by
growth plates, until the plates close and the centers fuse into one bone.

**problem** Launch a huge piece of work as independent lanes executed by several cooperating agent
sessions at once, in the safest way and with the fewest tokens and the least wall-clock.

**status** proposed

**named** first, with Remodeling

**vocabulary**

| Concept | Term |
|---|---|
| The methodology | Ossification |
| The plan: atomic, deduplicated, complete before any center starts | Cartilage model |
| One independent lane with its own sessions and change-request chain | Ossification center |
| A lane boundary: a shared surface, a cross-lane dependency edge | Growth plate |
| The merge to the main line; the launch | Fusion |
| The session that builds the cartilage model, bootstraps the cells, acts as interim osteocyte, hands over and retires as the archive | Chondrocyte |
| Orchestrator: holds the registry and the ledger, grants leases, builds nothing | Osteocyte |
| Lane sessions: build only inside their center | Osteoblasts |
| Auditor: resorbs what is defective before it fuses | Osteoclast |
| Curator: improves the framework itself while the lanes run | Periosteum |
| Session-to-session messaging | Canaliculi |
| A lease or permission grant from the osteocyte | Signal |

**roles** The osteocyte holds an on-disk registry of every session, its role, its worktrees, its
state and the leases it holds, plus an append-only ledger of every request, grant, denial and
report; it grants leases at five checkpoints (start a change request, touch a shared surface, open
a change request, merge, apply a curation item) and executes merges only after a human go it
relays and never mints. Osteoblasts ask before starting a change request and before touching a
shared surface, report at every checkpoint, and are otherwise heads-down in their own worktree.
The osteoclast takes review assignments from the osteocyte, verifies the change-request actor
before recommending merge, and posts a verdict as a comment before reporting it. The periosteum
runs the curation loop on a friction log every other session appends to, and applies nothing
without per-item approval.

**bootstrap** The session that produced the cartilage model is the chondrocyte. It bootstraps
the registry, the ledger and the worktrees and acts as interim osteocyte only until a fresh
osteocyte session signals its takeover; the chondrocyte writes the new name into the registry,
acknowledges, retitles itself and retires as the archive of the planning, never worked from
again. A session holding the whole planning transcript is the wrong shape for a role that runs
for days. Cells come up one at a time by roll call, in
a fixed order: periosteum, osteoclast, then each center. The osteocyte names the next session
and its exact first prompt; the owner opens the chat and pastes the prompt, typing nothing
beforehand. The prompt configures and verifies its own session: it sets the chat title to the
cell first, then the project and the date, because a sidebar truncates titles and every session
would otherwise read the same (never a generic title either, because several ossifications will
exist side by side); it reads its own model from its environment and refuses to continue if it is not
the one the plan names; and it then stops and asks the owner, at that moment, to type the
commands a pasted message cannot carry and to confirm the app-only controls with one word. A
slash command runs only when it is the whole message, so a prompt never embeds one; it asks for
it instead. The default model for new chats is set to the centers' model for the duration, so
only the cell on a different model is ever asked to change it. Once configured, the session
onboards, reads the osteocyte's address from the registry and signals its registration; the
osteocyte writes the row with the session's real address and only then names the next. Nothing
starts until the roll call is complete: every cell registered, the osteoclast's identity check
passed, the periosteum's first audit begun. Then the osteocyte signals every center in one turn
and the ossification begins together. A session that fails to register is opened again, never
worked around.

**principles**

- Safety is the growth plate. Leases on shared surfaces, a broadcast after every fusion so the
  other centers rebase, and a human go before any fusion. Prevents two centers writing one
  migration, and a merge landing under an identity that cannot be corrected afterwards.
- Token efficiency is the cartilage model. A center builds only inside a region fixed in advance,
  and no plan is ossified until it has been deduplicated. Prevents two centers building the same
  bone, which is the commonest waste when a plan is reconciled from several sources.
- Time efficiency is the parallel centers. Wall-clock is the slowest center, not the sum.
- Messages are signals; the repositories and the osteocyte's registry and ledger are the state.
  Prevents the loss of work when a session dies, which any session, the osteocyte included, will.
- Every session works in its own worktree. Prevents a shared checkout going stale under a
  concurrent session.
- The cartilage model is read from outside every checkout. The plan lives canonically in a
  repository that is also a center's repository, and the standing rule forbids a session touching
  any checkout but its own worktree; so the osteocyte snapshots the plan read-only at a named
  commit into the ossification directory and every center reads it there. Prevents the one rule
  that keeps centers apart from being bent on the first row, which is how the conflict was found.

**evidence** One launch plan, cut into several centers with no cross-center dependency edge after
its duplicate tasks were resorbed over several verification rounds. Without those rounds, some
findings would have exposed a secret and some pairs of tasks would have done destructive work
twice. The readings stay in the private ledger.

**executes** none

**owes** The osteocyte, osteoblast, osteoclast and periosteum units, the canaliculi protocol as a
unit, and a registry and ledger schema. Acceptance requires the first ossification to run.

**runs** none

**accepted** none

---

## Single-session ossification

**metaphor** One ossification center whose osteoblasts work the whole front, rather than several
centers meeting at growth plates.

**problem** Execute a large plan quickly and cheaply when the coordination between cooperating
sessions costs more than the work it coordinates.

**status** proposed

**named** second

**vocabulary**

| Concept | Term |
|---|---|
| The methodology | Single-session ossification |
| The one session: holds the plan, gates, merges, and owns every verdict | The center |
| A subagent or workflow agent: builds inside a scope the center fixes, never merges | Osteoblast |
| An agent whose only instruction is to refute a fresh claim | Osteoclast |
| The four blocks every agent prompt carries | Constraints, measured facts, the scope line, the gates |
| Session-to-session messaging | none, and that is the point |

**roles** The center delegates the build and never the verdict. Osteoblasts push branches and
report. Osteoclasts refute. Nothing merges but the center.

**bootstrap** none

**principles**

- Delegate the build, never the verdict. Prevents N sessions needing to agree, which is the cost
  the distributed variant pays.
- Every agent prompt repeats the constraints in full. Prevents an agent inheriting none of the
  caution the center has accumulated.
- Every agent prompt carries the measured facts marked do-not-re-derive. Prevents many agents
  re-measuring the same host and some of them getting it wrong.
- Every agent prompt carries the scope line and the instruction to stop rather than guess.
  Prevents an agent silently resolving an open ruling because it blocks them.
- Refute every fresh claim with a different agent. Measured at roughly one claim in five not
  surviving. Prevents a plan that overstates what is finished, which nobody re-checks.
- Parallelise reading, serialise building. Prevents concurrent builds exhausting a machine
  resource and surfacing hours later as an unrelated gate failure.
- Settle a behavioural disagreement against what the system answers, never by which branch is
  newer. Prevents adopting a call to a deliberately retired endpoint.
- A clean merge can still fail to compile. Prevents reading the conflict count as the size of the
  merge.
- Verify the gate tooling itself. Prevents a gate that cannot fail from certifying everything.

**evidence** One session against a multi-repository plan of several hundred tasks, over two days.
The plan's settled share roughly doubled, test counts grew substantially, and refutation overturned
about a fifth of DONE claims. A remainder stayed blocked on a human decision or an external
credential and no parallelism could move it. The exact measures stay in the private ledger.

**executes** `osteon-single-session-ossification`

**owes** Acceptance requires a second run, and a measured comparison against the distributed
variant on plans of comparable size rather than against its estimate.

**runs** withheld, the first run, two days long; discharges none. Both owed items name a second
run and a comparison, so this entry's debt does not shrink. Its measures and their locators are the
ledger row's, not this file's.

**accepted** none

---

## Remodeling

**metaphor** Bone remodeling: throughout life, osteoclasts resorb defective bone and osteoblasts
lay down new bone at many sites at once, each site regulated by the osteocytes embedded in the
matrix, so the structure stays correct under load.

**problem** Keep a living instance correct after launch: find where its knowledge has drifted from
the code and decisions it describes, and repair it without ever mutating it silently.

**status** proposed

**named** first, with Ossification

**vocabulary** Shares the cell terms of Ossification. Its own terms are the curation loop's:
audit, propose, ask, apply approved, log; the closed changeset vocabulary ADD, UPDATE, REMOVE,
MERGE, SPLIT; and the decay index that triggers a run.

**roles** The curation loop is the osteoclast and osteoblast in one cycle: it resorbs a stale
block and lays down the corrected one under per-item human approval. The decay instrument is the
osteocyte: it senses drift and signals the loop.

**bootstrap** none

**principles**

- Curation is always on and never silent. Prevents a stale fact being read at the confidence of
  a current one, which nothing in a toolchain otherwise notices.
- One event, one commit: the applied changes and their record land together. Prevents an
  unattested apply.
- The index is measured at block granularity by content hash. Prevents a corpus that was never
  measured from reporting perfect health.

**evidence** The curation records and decay readings of any instance; the observation programme's
gate-escape and catch-latency streams.

**executes** The reference distribution's capability units for the curation loop, decisions,
contracts, review, the operating rhythm, cold start and version control, plus `bone-curate-fast`
for the in-session pass. These predate the name; the register records the name over the practice.

**owes** none. The one remaining condition is the methodology owner's sign-off, which the admission
rule discharges by signature rather than by a run.

**runs** none

**accepted** none

---

## Plan coupling

**metaphor** Coupling in bone remodeling: at one site, formation is linked in time and place to the
resorption that preceded it. The reversal phase hands the site from the resorbing cells to the
forming cells, and new bone is not laid down until the previous cycle at that site has finished and
the surface has been prepared. A site where formation starts uncoupled leaves a cavity that never
fills.

**problem** Keep a multi-repository project's work honest across days, from one ledger that can see
every repository at once. Nothing merged is called done until its post-merge actions are verified,
no day's work starts on an unanswered question, and no day opens until the day before it has been
closed and its unfinished items carried across.

**status** proposed

**named** third

**vocabulary**

| Concept | Term |
|---|---|
| The methodology | Plan coupling |
| The whole project's plan for one date, spanning every repository: the day's ledger | Cycle |
| The folder in the knowledge instance that holds the full chain: the cycles and what was built under them | Ossification folder |
| A repository or user-facing surface the cycle does not account for | Untracked surface |
| The precondition for opening a cycle: every open question answered or explicitly routed onward | Activation |
| The single change request that opens cycle X and closes cycle X-1 together | Reversal |
| A change request opened that day, logged under the open cycle | Formation |
| A merged change request whose post-merge actions have been walked and passed green | Mineralised |
| An item moved out of the closing cycle into the opening one, including a question routed onward | Carried |
| A cycle in which every item is mineralised or carried, and which may therefore close | Quiescent |
| A merged change request whose post-merge actions were never walked | Cavity |

Its closed action vocabulary is five verbs, each with the condition that refuses it. A sixth verb is
a second vocabulary the next repository will not find.

| Verb | What it does | Refused when |
|---|---|---|
| **ACTIVATE** | Opens cycle X in one repository | Any open question is neither answered nor routed |
| **LOG** | Records a change request's activity under the open cycle | There is no open cycle |
| **MINERALISE** | Marks a merged change request done | Its post-merge actions are unwalked, or any one of them is not green |
| **CARRY** | Moves an unfinished item from the closing cycle to the opening one | Nothing: an item that cannot be carried is an item that cannot be closed |
| **CLOSE** | Closes cycle X-1 | Any item is neither mineralised nor carried |

**roles** One role, held by whoever opens the cycle. There is no second party: the discipline is
between a repository and its own past, not between sessions. The owner is the only source of an
activation, because the questions a cycle waits on are the owner's to answer or to route.

**bootstrap** none

**principles**

- Formation is coupled to the cycle that preceded it. Opening a day's plan and closing the
  previous day's are one change request, not two. Prevents the closing plan being left open
  indefinitely because the new work was more interesting than the bookkeeping.
- A merge is not a completion. MINERALISE is a separate verb from the merge for that reason, and it
  requires the post-merge actions to have been walked and seen green. Prevents a cavity: a change
  request that is merged, believed done, and whose deployment or configuration step never happened.
- No cycle activates over an unanswered question. Prevents a day of work built on an assumption
  that the one person who could have corrected it was never asked for.
- A question routed onward is carried, never closed. Routing is not answering. Prevents a question
  disappearing at a swap because somebody else now owns it.
- One cycle spans every repository, and it lives in the knowledge instance rather than in any code
  repository. A day's work crosses repositories and its post-merge actions cross back the other
  way; a per-repository cycle records only its own half, so the cross-repository half goes missing
  in exactly the place it matters, owned by neither side. Prevents that, and prevents the separate
  failure of tracking work in per-session folders outside every checkout, where nothing can answer
  what happened on a date.
- Every repository is accounted for, including the ones with nothing planned. "None" is an answer
  and a blank is not. Prevents a surface being quietly dropped from a launch because no cycle ever
  named it.
- Closing is the careful half. The quality of the closing plan is checked at the swap, not
  assumed. Prevents a swap becoming a rename.

**evidence** none yet. An owner stated the rule after a project could not report its own history on
a date and kept finding post-merge actions late; the same owner widened its scope from
per-repository to project-wide, because a plan has to cover every surface at once.

**executes** `osteon-ossification-planner-project-daily`, gated by `osteon-ossification-plan-starter`, run by `osteon-ossification-plan-implementor` and reported by `osteon-ossification-delivery-teaching`

**owes** The `ossification/` folder's shape as a specification requirement, since a knowledge
instance that lacks the folder cannot run this at all. Acceptance also requires a first full cycle:
one reversal that opens a cycle, closes its predecessor, mineralises every merged change request
under it and carries the rest, followed by a reading of how many cavities the close found. A close that finds none on its first run is evidence
the check is not working, not evidence the practice is unnecessary.

**runs** none

**accepted** none
