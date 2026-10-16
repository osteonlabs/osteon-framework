# BONE decision record format

The single source for the record template, the amendment template, the preconditions block, and the
index row. Templates below are written as **indented blocks, not fenced blocks**, so their `#`
headings do not register as sections of this file. Heading-based tooling (index generators, structure
linters) reads phantom sections out of fenced markdown templates.

All examples use neutral placeholders: `Service A`, `Service B`, the primary datastore, the derived
index, the queue. Substitute the project's own names, never the placeholders.

---

## 1. Record template

Filename: `NNNN-kebab-title.md` under `paths.ledger`. Title in the filename matches `title` and the
H1. Other artifacts cite this record as `[src: adr/NNNN]`, and a specific amendment of it as
`[src: adr/NNNN#amN]`: lowercase, four digits, lowercase `am`.

    ---
    id: NNNN
    title: "<decision title, a noun phrase naming the choice>"
    status: proposed            # proposed | accepted | superseded
    operative: no               # yes | no | suspended | partial
    date: YYYY-MM-DD
    deciders: [<name>, <name>]
    supersedes: null            # or the id this record replaces
    superseded_by: null         # or the id that replaced this one
    amendments: []              # items: n, date, summary
    preconditions: []           # REQUIRED non-empty when operative is suspended or partial
    stales: []                  # MUST be populated; write [] explicitly when there is nothing
    ---

    # ADR-NNNN: <decision title, a noun phrase naming the choice>

    ## Context

    The forces and constraints. What is true today that makes this a question. What breaks if
    nothing is decided. Include the evidence, with locators.

    ## Decision drivers

    The criteria the options are judged against, most important first. Naming the drivers before
    the options is what stops the record being a justification written after the fact.

    ## Options considered

    1. <option> - CHOSEN
       Pros: ...
       Cons: ...
    2. <option> - Rejected: <the reason it lost, against a named driver>
    3. <option> - Rejected: <the reason it lost, against a named driver>

    ## Decision

    The choice in one sentence, then why it wins on the drivers named above.

    ## Consequences

    What becomes easier. What becomes harder. What now has to be true. What follow-up work this
    creates, with owners.

    **Related:** adr/NNNN, contract/<seam>, domain/<slug>

### Field rules

The ten front-matter fields are `id`, `title`, `status`, `operative`, `date`, `deciders`,
`supersedes`, `superseded_by`, `amendments`, `stales`. All ten are required. The header is YAML and
never a bullet list: a bullet list is unparseable, so a lint could not check it, an index generator
could not read it, and the decay mechanism could not resolve a citation against it.

- **`id`** is four digits and matches the filename. Numbers are allocated at write time, never
  reserved.
- **`status`** is a closed set: `proposed | accepted | superseded`. `deprecated` is not a member: a
  decision that is no longer followed is either superseded by another record or suspended in
  `operative`. `status` carries no parenthetical and no amendment history; an unresolved question
  about the decision belongs in the body, not in the field.
- **`operative`** answers "is the running system doing this today": `yes | no | suspended | partial`.
  `no` covers accepted but not yet built. `partial` and `suspended` both require a non-empty
  `preconditions` block.
- **`deciders`** are people, named. A record with no decider has no one to ask when it is questioned.
- **`stales`** is mandatory. `stales: []`, written explicitly, is different from an omitted key: it
  says the author checked. Every amendment populates it too.
- **Options considered** always names the rejected options and the driver each one lost on. An option
  rejected without a stated reason will be re-proposed.

---

## 2. Amendment template

Appended at the end of the record. The body above is never touched. Add an entry to the front
matter's `amendments` list and, if the amendment changes what the system does today, update
`operative` and `preconditions`.

    ## Amendment N (YYYY-MM-DD) - <one-line title of what changed>

    **Context.** What was discovered that makes the base record no longer describe reality, with
    evidence and locators.

    **Decision.**
    1. <normative clause>
    2. <normative clause>

    **Scope.** What this amendment explicitly does not change. What remains the target state. The
    limits of the change.

    **Tracking.** <references>. Does NOT close <the open item this might be confused with>.

    **Stales.** <artifacts> - run bone-curator over them, and add them to the front matter's
    `stales` list.

---

## 3. Preconditions block

Required whenever `operative` is `suspended` or `partial`. Each precondition is checkable and cites
something on the default branch. It lives in the front matter, where a lint can read it:

    preconditions:
      - id: P1
        text: "<a condition someone can check today>"
        met: true
        evidence: "<locator on the default branch>"
      - id: P2
        text: "<a condition someone can check today>"
        met: false
        evidence: null

Returning `operative` to `yes` requires every row `met: true`, and an amendment recording that it
happened. The body MAY render the same rows as a table for readability, and that table is derived:
the front matter wins.

A precondition that cannot be checked from the default branch is not a precondition, it is a hope.
Re-verify the block whenever the record is read in anger, and date the re-verification.

---

## 4. Index row

The ledger index is generated, one row per record, and carries the precedence rule in its header:
**the record text always wins over this summary.**

    | ADR | Title | Status | Operative | Decision in one line |
    |---|---|---|---|---|

Every column is generated from the front matter. A hand-typed index row is a second copy of the
record's own header and will disagree with it.

---

## 5. Worked example A - a straightforward accepted record

    ---
    id: 0012
    title: "Event transport between Service A and Service B"
    status: accepted
    operative: yes
    date: 2026-03-04
    deciders: [<name>, <name>]
    supersedes: null
    superseded_by: null
    amendments: []
    stales: ["<the Service B unit>"]
    ---

    # ADR-0012: Event transport between Service A and Service B

    ## Context

    Service A produces roughly 40 state-change events per second at peak and Service B must react
    to each one. Today Service B discovers changes by polling a table Service A owns, which couples
    B to A's schema and adds up to 30 seconds of latency. Two incidents in the last quarter were
    caused by a column rename in A that B read directly.

    ## Decision drivers

    1. B must not read A's schema. The coupling has already caused two incidents.
    2. No event may be lost when B is down for a deploy.
    3. End-to-end latency under 2 seconds at peak.
    4. Operable by the current team without a new managed service to learn.

    ## Options considered

    1. Durable queue between A and B - CHOSEN
       Pros: survives B being down (driver 2); A publishes a versioned payload, so B never reads
       A's schema (driver 1); sub-second delivery at this volume (driver 3).
       Cons: a new component to run; at-least-once delivery makes B's handlers responsible for
       idempotency.
    2. Direct synchronous call from A to B - Rejected: fails driver 2. Events are lost whenever B
       is deploying, and A's write path becomes dependent on B's availability.
    3. Keep polling, with a stable read view owned by A - Rejected: fails driver 3 (polling
       interval is the latency floor) and only partly addresses driver 1, since the view still has
       to be versioned and maintained by A.

    ## Decision

    Service A publishes versioned events to a durable queue; Service B consumes them. It is the only
    option that satisfies drivers 1 through 3 together, and the operational cost is one component
    rather than the ongoing cost of a shared read surface.

    ## Consequences

    Positive: B's deploys stop losing events. A can change its schema without coordinating with B.
    Negative: B's handlers must be idempotent, since delivery is at-least-once. A dead-letter path
    and its alerting are now required work.
    Follow-up: the payload becomes a seam and needs a contract file before the code lands.

    **Stales:** the integration section of the Service B artifact (it documents polling).
    **Related:** contract/service-a-service-b

Why this record works: the drivers are named before the options, every rejection cites the driver it
failed, and the follow-up hands the interface to the contract registry rather than describing the
payload here. The record owns the choice; the contract owns the wire.

---

## 6. Worked example B - an amendment recording that code suspended the decision

Base record, abbreviated to its header and decision:

    ---
    id: 0019
    title: "Service A maintains the derived index on write"
    status: accepted
    operative: suspended
    date: 2026-04-11
    deciders: [<name>, <name>]
    supersedes: null
    superseded_by: null
    amendments:
      - n: 1
        date: 2026-06-02
        summary: "The synchronous index write is disabled by default."
    preconditions:
      - id: P1
        text: "Index write latency at p99 measured under the request budget."
        met: false
        evidence: null
      - id: P2
        text: "A failure of the index write cannot fail the primary write."
        met: true
        evidence: "<locator on the default branch>"
      - id: P3
        text: "A backfill exists for the gap accumulated while suspended."
        met: false
        evidence: null
    stales: ["<every unit asserting read-after-write consistency>"]
    ---

    # ADR-0019: Service A maintains the derived index on write

    ## Decision

    Service A writes to the primary datastore and, in the same request, updates the derived index,
    so a read immediately after a write always reflects the write.

    [Context, drivers, options and consequences unchanged - never rewritten.]

    ## Preconditions (rendered from the front matter, re-verified 2026-07-09)

    | # | Precondition | State | Evidence |
    |---|---|---|---|
    | P1 | Index write latency at p99 measured under the request budget | unmet | no measurement on the default branch |
    | P2 | A failure of the index write cannot fail the primary write | met | <locator on the default branch> |
    | P3 | A backfill exists for the gap accumulated while suspended | unmet | not written |

    Returning `operative` to `yes` requires every row met, and an amendment recording it.

    ## Amendment 1 (2026-06-02) - the synchronous index write is disabled by default

    **Context.** A change merged on 2026-05-28 put the index write behind a configuration flag that
    defaults to off, after it was found to add enough latency to breach the request budget under
    peak load. No record mentioned this, so ADR-0019 read as current for five days while the system
    did the opposite, and one artifact still told readers that a read after a write is always
    consistent.

    **Decision.**
    1. The synchronous index write is OFF by default in every environment.
    2. Until it is re-enabled, the derived index is updated by the existing periodic rebuild, so
       reads may lag writes by up to one rebuild interval. Any caller that requires read-after-write
       consistency MUST read from the primary datastore.
    3. Re-enabling requires all rows of the Preconditions block to be met, plus an amendment
       recording it.

    **Scope.** The decision is not reversed. The synchronous write remains the target state; this
    amendment records that it is suspended and what it would take to restore. It does not change how
    the primary write path works, and it does not change the contract on the seam.

    **Tracking.** <references>. Does NOT close the open question about the rebuild interval.

    **Stales.** Every artifact asserting read-after-write consistency, and the read-path guidance
    in the Service A artifact. Both are named in the front matter's `stales`; run bone-curator over
    them.

Why this amendment works: it was written the same day the divergence was noticed, it says what is off
and what the system actually does instead, the preconditions are checkable and cite the default
branch, the base record is untouched, and it names the artifacts it stales rather than leaving the
next reader to find them.

The general rule this example teaches: **a merged change that contradicts an accepted record is an
architecture decision made by omission.** Whenever a flag, a kill switch, or a deleted writer makes
the running system diverge from the ledger, the ledger owes an amendment before the day ends, because
nothing else in the toolchain will ever notice.
