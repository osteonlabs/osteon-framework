# BONE contract file format

The single source for the registry index format, the contract file skeleton, the changelog table, and
a worked example. Templates are written as **indented blocks, not fenced blocks**, so their `#`
headings do not register as sections of this file.

All examples use neutral placeholders: `Service A`, `Service B`, the queue, the object store.

---

## 1. Registry index

One file under `paths.contracts` (conventionally `README.md`), carrying the rules and one row per
seam. The index is the **complete** list of seams. A seam that is not in the index does not exist as
far as review is concerned, which is the point: completeness is what lets someone ask "what talks to
what" and get a true answer.

    # Interface contract registry

    Every communication between two independently changeable units carries a versioned contract
    here.

    ## Rules
    1. One file per seam, semver'd. The version and the changelog live inside the file.
    2. A contract changes in the same review wave as the code that changes the wire.
    3. Both sides build against the contract, not against each other's source.
    4. Exact strings are normative: endpoints, headers, field names, types, units, error
       semantics, auth, and fail-open versus fail-closed behaviour.
    5. Data-handling rules ride every contract: what may and may never appear on that wire.

    ## Index

    | Seam | Contract file | Version | Sides | Status |
    |---|---|---|---|---|
    | <A> to <B> (<what crosses>) | [<file>.md](<file>.md) | X.Y.Z | <module or file> · <module or file> | active |

**These five columns, in this order, are required.** A project MAY append further columns to the
right (a priority, an owner); it MUST NOT insert one among the five, rename one, or lead with a row
number. A row number is not data, and a renamed column breaks every generator that reads the index.

**Sides** names the two units by the file, package, or module that implements each end, not by team.
Teams change; the code location is what someone needs when the contract is wrong.

**Status** is the same closed set the contract file carries: `active`, `deprecated`, `withdrawn`. It
also admits `undocumented-today` for a seam that demonstrably exists in code and has no specification
yet: registering it as a known gap is what stops it being rediscovered as a surprise.

---

## 2. Contract file skeleton

Filename: `<side-a>-<side-b>.md`, or `<seam-purpose>.md` when the two sides are obvious. The header
is **YAML front matter**, not a bullet list: a bullet list cannot be parsed, so the version, the
sides and the fail mode would exist only for human readers and no lint could check the index row
against them. Section order is fixed so two contracts can be diffed and so a reader under pressure
knows where to look.

    ---
    seam: <side-a>-<side-b>
    version: X.Y.Z
    sides: ["<module or file implementing A>", "<module or file implementing B>"]
    status: active              # active | deprecated | withdrawn | undocumented-today
    transport: "<protocol and encoding, in one clause>"
    fail_mode: closed           # open | closed
    ---

    # Contract: <Side A> to <Side B> - <transport>

    ## Transport and auth

    Exact endpoint, method, or topic. Auth scheme and where the credential comes from, **by name
    and location, never by value**. Transport security requirement. Timeouts. Retry policy and
    whether retries are safe, which means whether the operation is idempotent and on what key.

    ## <A> to <B> messages

    Per message or request: name, trigger, and a field table.

    | Field | Type | Required | Unit / format | Notes |
    |---|---|---|---|---|

    Every quantity states its unit. Every timestamp states its format, timezone, and whether it is
    event time or ingest time. Every enum lists its members and says whether consumers must
    tolerate unknown members.

    ## <B> to <A> messages

    Same shape. Includes the success response and every error response.

    ## Failure semantics

    - What each side does when the other is unavailable, slow, or returns malformed data.
    - Fail-open or fail-closed, stated explicitly, per operation.
    - Which errors are retryable and which are terminal.
    - What happens to in-flight work at reconnect, restart, or redeploy.
    - Delivery guarantee: at-most-once, at-least-once, or exactly-once, and which side is
      responsible for deduplication and on what key.

    ## Data handling

    What may appear on this wire, what may never, what must be referenced by surrogate rather than
    carried. State this even when nothing is restricted; the empty answer is information.

    ## Compatibility

    How consumers handle unknown fields and unknown enum members. Any deprecation window currently
    running: what is removed, what replaces it, and the date after which the old form stops.

    ## Changelog

    | Version | Date | Change |
    |---|---|---|
    | X.Y.Z | YYYY-MM-DD | <what changed on the wire, and the bump reason> |

**`fail_mode` in the front matter is the seam's default**, the answer a reader needs before opening
the file. Real seams differ per operation; the `## Failure semantics` section is the normative
statement and **MUST** state every operation whose behaviour differs from the declared default.

**`version` in the front matter is the single source.** The index row is generated from it or
asserted against it, never authored independently.

---

## 3. Worked example

    ---
    seam: service-a-service-b
    version: 2.1.0
    sides: ["<publisher module in A>", "<consumer module in B>"]
    status: active
    transport: "durable queue, JSON payloads"
    fail_mode: closed
    ---

    # Contract: Service A to Service B - durable queue

    ## Transport and auth

    Queue `<queue-name>`, one topic per event type. Credentials resolved at startup from the
    secret store under the name `<secret name>`; never read from configuration files or
    environment defaults. Transport encrypted. Publish timeout 5 s, no publish retry inside the
    request path: a failed publish is written to the outbox table and retried by the outbox worker.

    ## A to B messages

    **`resource.state_changed`** - published by A after a state change is durably committed.

    | Field | Type | Required | Unit / format | Notes |
    |---|---|---|---|---|
    | `event_id` | string (UUID v4) | yes | - | deduplication key, see Failure semantics |
    | `resource_id` | string | yes | - | the identifier defined in the domain glossary |
    | `previous_state` | enum | yes | one of `pending`, `active`, `closed` | consumers MUST tolerate unknown members |
    | `new_state` | enum | yes | same set | |
    | `occurred_at` | string | yes | RFC 3339, UTC, millisecond precision | **event time**, not publish time |
    | `size_bytes` | integer | no | bytes, not kilobytes | absent means unknown, never zero |
    | `correlation_id` | string | no | - | added in 2.1.0 |

    ## B to A messages

    None. This seam is one-way. Failures are reported through the dead-letter queue below, not
    back to A.

    ## Failure semantics

    - Delivery is **at-least-once**. B MUST deduplicate on `event_id` and MUST be idempotent per
      `event_id`; A does not guarantee single delivery and never will.
    - B **fails closed** on a malformed message: it is not acknowledged, it is routed to
      `<dead-letter-queue>` after 3 delivery attempts, and it raises an alert. B MUST NOT drop a
      message it cannot parse, and MUST NOT substitute a default value for a field it cannot read.
    - When the queue is unavailable, A **fails open** on the publish and **fails closed** on the
      primary write only if the outbox write also fails. The primary write is never lost to a
      messaging failure.
    - Ordering is not guaranteed. B MUST use `occurred_at` plus `previous_state` to reject events
      that arrive out of order rather than assuming queue order.

    ## Data handling

    Identifiers only. No personal data, free-text user content, or credential material may appear
    on this wire, including inside `correlation_id`. B resolves anything further by calling A's
    read surface, server side.

    ## Compatibility

    Consumers MUST ignore unknown fields and MUST treat an unknown enum member as a terminal
    parse failure routed to the dead-letter queue, not as a default. Adding an enum member is
    therefore a MAJOR change on this seam.

    ## Changelog

    | Version | Date | Change |
    |---|---|---|
    | 2.1.0 | 2026-05-19 | Added optional `correlation_id`. Additive, no consumer action. |
    | 2.0.0 | 2026-04-02 | `size_bytes` changed from kilobytes to bytes. Breaking: a conforming consumer would have been off by 1024. |
    | 1.0.0 | 2026-03-11 | First load-bearing version. |

### What this example demonstrates

- The unit change at 2.0.0 is a MAJOR bump even though no field was added or removed. Changing a
  unit is invisible in a type system and produces a wrong answer rather than an error, which is the
  strongest possible argument for the contract existing at all.
- The enum policy is stated in advance, so the semver consequence of adding a member is already
  decided. Without that clause the two sides would disagree about whether the next addition is MINOR
  or MAJOR, and would find out in production.
- Fail-open and fail-closed are stated per operation rather than once for the seam, because they
  differ per operation on almost every real seam.
- The credential appears by name and location only. A contract is a widely read file; a value written
  into one is a value in every clone, every mirror, and the history of both.
- The outbox is named in the transport section rather than left as an implementation detail, because
  it is the only reason a publish failure does not lose the event. **A provisioned but unused
  alternative path is not a fallback:** configuration for a second route that nothing calls reads as
  resilience in review and provides none. Either the path is exercised and specified here, or it is
  deleted.
