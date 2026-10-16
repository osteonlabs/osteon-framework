# BONE curation record

One record per curation run, including runs that applied nothing. The record is simultaneously the
audit trail and the metrics source. It is **not** the decay clock: the clock is the per-source
content-hash baseline at `decay.baseline`, which the event writes and the check only reads. No
modification time of any file, including this record and the generated index, carries any meaning.
Templates below are indented blocks so their headings do not register as sections of this file.

A record **MUST NOT** be edited after it is committed. A correction is a new record referencing it.

**Why one file per event rather than one appended log.** An append-only log file has no schema, no
identifiers, and nothing computable; its ordering rot is invisible and, in practice, universal (a log
declaring "newest first" ends up with entries appended at both ends). One file per event with typed
front matter makes decision latency, approval rate, refutation rate, and CDI history queryable
without anyone maintaining a second system.

---

## 1. Record file

Path: `<paths.curation>/YYYY-MM-DD-<slug>.md`, default `docs/curation/`. `docs/` already carries the
admission rule through `docs_registry`; a second top-level directory for one more class of document
would be a second convention.

The front matter below is the schema of SPEC Appendix B.5. Field names are normative: a record that
renames a field is unqueryable, and an unqueryable log costs every metric the loop produces.

    ---
    id: YYYY-MM-DD-<slug>
    date: YYYY-MM-DD
    trigger: decay-fired | decision-fired | contract-fired | state-fired | periodic | manual
    cdi_at_trigger: <float to four decimals> | null
    cdi_after: <float to four decimals> | null
    sources: []               # provenance tokens for the records, state files, or contracts that
                              #   motivated this run: adr/NNNN, adr/NNNN#amN,
                              #   state/<topic>@YYYY-MM-DD, contract/<seam>@X.Y.Z
    actions:                  # one entry per proposal, approved or not
      - verb: ADD | UPDATE | REMOVE | MERGE | SPLIT
        targets: []
        class: D1..D10 | Q1..Q16
        rationale: <the specific new data motivating it, with its locator>
        tier_resolution: T0 | T1 | T2   # REQUIRED when a fact is introduced or moved
        outcome: approved | rejected | modified
        note: <the modification text, or the reason for rejection>
    approval: per-item | user-directed | mechanical | standing-grant | none-yet
    approver: <a named human>   # null ONLY when approval is none-yet
    approval_instruction: ""  # REQUIRED when approval is user-directed. The instruction, verbatim.
    attestation:              # REQUIRED when any action touches the never-auto-apply list.
      kind: signed-commit | reviewed-merge
      identity: <the signer, or the approver distinct from the author>
      change_request: null    # REQUIRED non-null for reviewed-merge
    verification:
      citations_checked: <n>
      citations_trimmed: <n>
      citations_corrected: <n>
      lint_passed: true | false
    follow_ups: []            # owed work, each with an owner
    refuted: []               # proposals rejected, with the reason, so they are not re-proposed
    rejected: []
    deferred: []
    not_done: []              # in scope, deliberately deferred, with why
    ---

    # <one-line theme>

    ## Trigger

    What surfaced this run, with locators.

    ## Applied

    One short paragraph or bullet per applied action: what changed, the mechanism, and the source
    that motivated it.

    ## Refuted

    Each rejected proposal and the reason. This section is read by the next audit.

    ## Owed

    Follow-ups with owners, and anything deliberately not done.

---

## 2. Field rules

- **`id`** is `YYYY-MM-DD-<slug>` and matches the filename. Stable: other records cite it.
- **`trigger`** is a closed set. It is the field that makes "what fraction of decay signals lead to a
  curation" computable, so an inaccurate trigger silently corrupts the loop's own health metric.
- **`sources`** uses provenance tokens (`adr/NNNN`, `adr/NNNN#amN`, `state/<topic>@YYYY-MM-DD`,
  `contract/<seam>@X.Y.Z`), never prose. This is what makes decision latency measurable: the interval
  between a record's date and the date of the first curation record citing it.
- **`actions`** records **every** proposal, including rejected ones. A record listing only what was
  applied cannot answer how much the human changed, which is the one number that shows whether
  propose-then-ask is doing real work or is a rubber stamp.
- **`approval: user-directed`** is a valid path, not a failure, and it **MUST** carry
  `approval_instruction` quoting the instruction verbatim. The instruction has to name the specific
  target and the specific verb; a general instruction ("tidy up the ledger") **MUST NOT** stand as
  approval for anything on the never-auto-apply list. An unquoted direct instruction is
  indistinguishable from a silent mutation after the fact.
- **`approval: standing-grant`** is an approval, and it differs from the others in the SCOPE of the
  instruction rather than in whether a human decided. It is the honest name for one grant covering a
  class of items, typically a whole run, instead of one decision per item. It **MUST** carry a named
  `approver` and **MUST** carry `approval_instruction` quoting the grant verbatim, on the same
  reasoning as `user-directed`: an unquoted grant is indistinguishable from a silent mutation after
  the fact. It counts as an approval in approval rate and it may discharge.
  **MUST NOT** stand as approval for anything on the never-auto-apply list without an `attestation`
  block, which is the same constraint the `user-directed` rule above already states about a general
  instruction, and naming the value does not relax it. Recording the grant honestly is what makes
  that constraint checkable: a run that spells a blanket grant as `per-item` hides the one fact an
  auditor needs.
- **`approval: none-yet`** means the run recorded its proposals and **no approval decision has been
  taken**. It is the one value for which `approver: null` is correct rather than a defect. It is a
  legal value and it is **NOT an approval**: a `none-yet` record **MUST NOT** discharge anything,
  **MUST NOT** count in the numerator or the denominator of approval rate, and **MUST NOT** satisfy
  an attestation requirement. It exists so that a run which proposed and stopped can be logged
  truthfully instead of being spelled as an approval it never had, and so the field stays a closed
  set that an instrument can check. Being in the set and being an approval are two separate facts,
  and an instrument **MUST NOT** collapse them: a `none-yet` record stops being reported as an
  out-of-set VALUE and goes on being reported as approval OWED, because it still names no human who
  approved it. Silencing the second along with the first is the obvious implementation error and it
  converts an unapproved record into a clean one. **CONTEXT** a record that carries `none-yet` while
  its own commit applied governed artifacts is describing an apply that outran its approval; the
  value is the honest label for that state, never a licence for it.
- **`verification`** states what was actually checked after applying, in counts that another person
  could reproduce. "Applied" is not verification.
- **`refuted`** and **`not_done`** are load-bearing. A refusal that is not written down is
  re-proposed, and the approver pays for the same decision twice.
- **`cdi_at_trigger` / `cdi_after`** are floats to four decimal places, or `null`. `null` on a first
  run, on an unsealed baseline, and whenever `units_anchored` is 0. **Never `0`.** The full reading
  that each scalar is drawn from, with its granularity label, its internal and external sub-indices,
  its three denominators and its unavailable-source count, is appended to the stream at
  `decay.readings`; the record cites the reading rather than restating it. A bare fraction cannot be
  audited or compared across corpora of different sizes.

---

## 2a. Attestation: what makes an approval checkable by someone else

A record asserting that a human approved something is evidence only about the record. Two tiers close
that gap, sized for a team small enough that a distinct approver cannot always be found.

**Tier 1, always: one event, one commit.** Every applied curation event lands as **one** commit, or
one change request, containing **both** the changed governed artifacts **and** the curation record
describing them. A commit that modifies anything under `paths.ledger`, `paths.state`,
`paths.contracts`, `paths.domain`, `paths.skills`, the constitution or `MANIFEST.yaml`, and that adds
no file under `paths.curation`, is an **unattested apply**. This is decidable from
`git log --name-only` since the genesis commit, needs no forge feature, costs nothing, and catches
the failure that actually happens: knowledge edited with no record.

**Tier 2, for the never-auto-apply list: external attestation.** An applied action touching any class
on that list **MUST** additionally be attestable by exactly one of two means, recorded in
`attestation`:

| `kind` | What it means | Required fields | Verified by |
|---|---|---|---|
| `signed-commit` | the applying commit is signed by a key listed in an allowed-signers file | `identity`: the KEY and the principal it is listed under, never the commit's author line | `git verify-commit <sha>`, or `%G?` with `%GK` and `%GS` |
| `reviewed-merge` | the change landed through a change request on a protected branch, approved by someone other than the commit author | `identity`: the approver · `change_request`: its id or url | the forge's own record |

**The concession, stated rather than hidden.** A signed commit proves that the named human's key
applied the change. It does **not** prove that a second human reviewed it. In a team too small to
guarantee a distinct approver, that is the honest ceiling of this mechanism, and it is weaker than a
hash-chained audit trail. `reviewed-merge` is the stronger of the two and **SHOULD** be preferred
wherever a distinct approver exists.

**The signature does not read the author line, and the field names the key for that reason**
(measured on git 2.39 with SSH signing; re-run the three controls on your own git before relying
on them). Three commits in a scratch repository, signed with one listed key, varying only the
committer address: the listed principal verified `G`; an address in no allowed-signers file
verified `G`; the address of a DIFFERENT principal verified `G`. In all three `%GS` reported the
principal that the signing KEY is listed under. So verification answers "was this signed by a key I
allow, and whose key is it", and the address in the commit header is never checked against it. A
commit carrying any author line at all verifies.

Two consequences for `identity`. **MUST** record the key, by fingerprint, and the principal it
resolves to, rather than copying the commit's author line, because that line is the one thing the
check did not read. And an estate whose repositories carry different identities **SHOULD** give
each its own signing key, set per repository with a local `user.signingkey`, listed under that
repository's principal: then `git verify-commit` names the publishing identity of the repository
the commit is in, and that binding is a property of the key choice rather than of the signature
mechanism. Signing every repository with one key gives a valid signature that names the wrong
identity, and nothing in the mechanism reports that as a problem.

Signing is enabled once per machine; the commands are in `bone-skills/README.md` under *Enabling
commit signing* and are not restated here. An install that does not carry that README finds each
setting they use documented in `git help config`, under `gpg.format`, `user.signingKey`,
`commit.gpgSign` and `gpg.ssh.allowedSignersFile`.

---

## 3. Generated index

`<paths.curation_index>` is generated from the record front matter and **MUST NOT** be hand-edited.
Regenerate it in the same wave as any new record. Ordering is derived from the filename and the
`date` field, never from position in a file, so it cannot rot.

    # Curation log

    Generated from `<paths.curation>/`. Do not edit by hand.

    | ID | Date | Trigger | Applied | Rejected | CDI at trigger | CDI after | Approver | Attestation |
    |---|---|---|---|---|---|---|---|---|

---

## 4. What this makes computable

Each of these falls out of the front matter with no extra instrumentation. Instrument from the first
record: a metric added later has no history, and self-reported impressions of agentic tooling are
demonstrably unreliable, which is precisely why the numbers have to exist.

| Metric | Derivation |
|---|---|
| Context Decay Index history | the `cdi_after` series |
| Decision latency | a record's date, to the date of the first curation record citing it in `sources` |
| Curation rate | records per period |
| Signal follow-through | records with `trigger: decay-fired`, over decay signals fired |
| Approval rate | `outcome: approved` actions over all actions |
| Refutation rate | `outcome: rejected` actions over all actions |
| Human modification rate | `outcome: modified` actions over approved actions |
| Follow-up debt | open `follow_ups` carried across records |
| Corpus churn | distinct `actions[].targets` per period |
| Attestation coverage | records with a verifying `attestation`, over records touching a never-auto-apply class |
