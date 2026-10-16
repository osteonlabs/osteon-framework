# BONE audit checklist

The full checkable procedure behind Step 2 of `bone-curator`. Every item has a stable ID, the exact
check, the FAIL condition, and the remediation verb.

**Item IDs are stable identifiers.** New checks take the next free number, or a letter suffix inside
an existing family (`D1`, `D1b`, `D1c`). Never renumber: other artifacts and past curation records
cite these IDs.

**Verdicts are a closed set of three:** `PASS`, `FAIL`, `NEEDS-INFO`. A check that can only pass or
fail forces false passes on under-determined items. Every `FAIL` and `NEEDS-INFO` carries an evidence
locator (`file:line`, a record identifier, or a contract version) and a one-line remediation.

`<K>` below stands for the knowledge repository root. Every location is written as its `MANIFEST.yaml`
key, never as a literal directory: a checklist that names `docs/adr/` stops working on the first
instance that moves it. `paths.*` resolves the layer directories; `watched`, `knowledge_units`,
`gates`, `repos`, `decay`, `curation` and `conventions` are top-level keys.

---

## Preflight

- **P1 Manifest resolves.** The keys `bone-curator` consumes, each with the default used when the key
  is absent:

  | Key | Default | Holds |
  |---|---|---|
  | `paths.constitution` | `CLAUDE.md` | L1 constitution |
  | `paths.ledger` | `docs/adr/` | L2 decision records |
  | `paths.state` | `docs/state/` | L2 dated live-state records |
  | `paths.contracts` | `docs/contracts/` | L3 seam contracts and registry index |
  | `paths.domain` | `docs/domain/` | L3 glossary and model |
  | `paths.skills` | `.claude/skills/` | L4 T1 capability library |
  | `paths.capability_entry_filename` | `SKILL.md` | the entry document of a capability unit |
  | `paths.capability_meta_filename` | `meta.yaml` | the required sidecar of a capability unit |
  | `paths.curation` | `docs/curation/` | one record per curation event |
  | `paths.curation_index` | `CURATION.md` | generated index over `paths.curation` |
  | `paths.metrics` | `metrics/` | the metric series |
  | `watched` | no default; absent is a finding | **the one** watched-input list, shared with the hook |
  | `knowledge_units` | every `*.md` under `paths.skills` | the consumer set the index is measured over |
  | `decay.baseline` | `metrics/curation-baseline.tsv` | per-source content hash at the last applied curation |
  | `decay.method` | `content-hash` | the only legal value; mtime is forbidden, with no fallback |
  | `decay.unit_granularity` | `block` | the only legal value |
  | `curation.cdi_threshold` · `curation.max_interval_days` | none | the decay-fired and periodic triggers |
  | `gates` | empty | the gate set, enumerated once: `id`, `name`, `unit`, `scope`, `enforced_by`, `enforcement`, `status` |
  | `repos` | empty | each repository: `alias`, `url`, `tier`, `tier2_context`, `local_path`, `pinned_at` |
  | `conventions` | none | the mechanically checkable parameters this checklist lints against |

  FAIL if a declared path is missing. NEEDS-INFO if `MANIFEST.yaml` is absent: fall back to the
  defaults and make ADD manifest the first proposal. Remediation: UPDATE the manifest, or ADD the
  missing directory with a stated owner and lifecycle.

  **The retired names.** `provenance_sources`, `external_watch_sources` and `decay.watch` are three
  former names for `watched`. FAIL on any of them: a manifest carrying two of them has split its
  watch set, and a split watch set reports health over the half it can see.
- **P2 Baseline exists and is sealed.** The file at `decay.baseline` was written by a previous
  curation event and carries a non-null `sealed_at`. FAIL if absent or unsealed: this run is the
  baseline and every index **MUST** be reported as `null` with `state: uninitialised`, never as
  `0`. Reporting an uncomputable index as zero is the single easiest way to make the metric lie.
- **P3 Prior records read.** The last three curation records have been read; their `refuted`,
  `follow_ups`, and `not_done` lists are in hand. FAIL if not read.

---

## D1 Drift - an artifact contradicts a higher authority

The authority order is: constitution and manifest, then accepted decision records, then contracts,
then dated state records, then everything else.

- **D1a** No skill, reference file, or repo-local file contradicts the constitution.
- **D1b** No artifact contradicts an accepted decision record. Cross-check every artifact claim that
  carries an `[src: adr/...]` token against the record's current text, including its amendments.
- **D1c** No artifact describes a seam differently from that seam's contract file. The contract wins.
- **D1d** No artifact asserts a live fact that a newer dated state record contradicts.
- **D1e** No `description` frontmatter asserts a decision, a version, a count, a status, or any other
  fact that can change. Descriptions are the only always-loaded surface and are never swept by body
  audits, so a mutable fact placed there rots invisibly.

FAIL on any contradiction. Remediation: UPDATE the lower-authority artifact. If the lower artifact is
right and the higher one is wrong, that is not a curation fix: stop and route it to `bone-adr` or
`bone-contract`, and record it as an owed follow-up.

## D2 Staleness - a closed question still hedged as open

- **D2a** For every decision record accepted or amended since the last curation record, grep the
  corpus for the vocabulary of the question it closed ("open decision", "TBD", "undecided", "we may",
  "either ... or", "candidate", "leaning").
- **D2b** Every hit either cites the record that closed it or is rewritten to the decided position.
- **D2c** Resolved entries in any open-questions list are struck through with the deciding record
  named, never deleted. Deletion invites re-litigation; the strike-through is the cheapest possible
  record of why nobody should re-open it.
- **D2d** Every dated state record is within the freshness window the constitution states for its
  topic. NEEDS-INFO past the window, FAIL if the code it describes has changed since its
  `verified_at` date.

Remediation: UPDATE.

## D3 Header-only retraction - the correction did not reach the body

- **D3a** For each correction, retraction, or "this was wrong" note found anywhere in the corpus,
  grep the retracted claim across the **whole file, its `references/`, its frontmatter, and every
  other artifact**.
- **D3b** FAIL on any surviving assertion of the retracted claim outside the correction note itself.
- **D3c** Corrections accumulated in a file header are themselves a finding once there are more than
  two: the file is teaching by accretion and readers pay tokens for false facts before reaching true
  ones. Remediation: UPDATE the body and move the history to the ledger, or SPLIT.

A grep-first reader lands on the body line and never sees the header. This class is the most
frequently missed and the most expensive when missed, because the surviving text reads as current.

## D4 Overlap - two artifacts own the same ground

- **D4a** Near-duplicate paragraph detection across all skills and reference files. Any normative
  sentence appearing in two artifacts is a finding.
- **D4b** Two artifacts whose `description` triggers would both fire on the same request, with no
  `NOT for` clause distinguishing them.

Remediation: MERGE, or keep both and UPDATE one to reference the other. **Never resolve an overlap by
making both copies correct.** The rule lives at its owner; every other mention is a pointer.

## D5 Too broad - one artifact carries several change cadences

- **D5a** A `SKILL.md` over the 10 KB hard budget, or over 5 KB with no `references/`.
- **D5b** A single file containing blocks that change on visibly different cadences (a stable policy
  next to a table that changes weekly).
- **D5c** A file containing data the file itself calls unreliable, or that is derivable from a live
  source. Data a skill admits it cannot keep true does not belong in the skill.
- **D5d** A block over 3 KB that is looked up rather than read end to end.

Remediation: SPLIT, or extract to `references/` with a pointer that states what is inside and the
consequence of not opening it.

## D6 Gap - something real that no artifact covers

- **D6a** A task explained from scratch more than twice in recent sessions.
- **D6b** A live seam between two modules with no contract file (hand to `bone-contract`).
- **D6c** A decision made in conversation with no record (hand to `bone-adr`).
- **D6d** A repository listed in the manifest with no T2 file (a null `repos[].tier2_context`) and
  no covering skill.
- **D6e** A gate named in `MANIFEST.yaml` with no artifact defining its checklist.

Remediation: ADD. A gap found is a proposal, not an authorization to write the artifact.

## D7 Dead weight - an artifact describing something that no longer exists

- **D7a** The subject was removed, replaced, or archived.
- **D7b** The artifact has not been loaded, cited, or changed across a stated number of curation
  cycles and nothing references it.

Remediation: REMOVE, only ever with explicit per-item approval. Before removing, confirm no artifact
depends on it and state where the still-true parts survive. Git retains the content; the knowledge
base is not an archive.

## D8 Broken cross-reference

- **D8a** Every backticked artifact name resolves to an artifact that exists.
- **D8b** Every relative path and anchor resolves.
- **D8c** Every `meta.yaml` `chains_with[]` entry names a unit that exists on disk at the tier the
  citation implies, carries a labelled `relation`, and appears at most once. FAIL on a peer name with
  no relation, and on any peer relation enumerated a second time outside `meta.yaml` (a surviving
  `## Chains with` footer is exactly this).
- **D8d** Reverse edges: for each unit, the peers it names should name it back or be a deliberate
  one-way edge. FAIL on a dangling edge, NEEDS-INFO on an unreciprocated one.
- **D8e** No normative claim depends on a target outside the repository. External pointers may carry
  supplementary depth or deliberately-private data only; a teammate cloning the repository must be
  able to act on every normative claim without them.

Remediation: UPDATE.

## D9 Tier violation

The invariant: a fact lives at exactly one tier, the narrowest tier that fully owns it. Lower tiers
reference; they never copy. The tie-breaker is **change cadence, not topic**: if it changes when a
tool is swapped or a credential rotates it belongs with the mechanics; if it changes when the process
changes it belongs with the policy. T2 here is always one code repository's own conventions, at
`repos[].tier2_context`; the labels are those `repos[].tier` and `tier_resolution` accept.

- **D9a** A fact stated at two tiers. FAIL. Remediation: UPDATE the wider tier to reference the
  narrower owner, or vice versa if the narrower one was the copy.
- **D9b** A project-specific fact sitting at T0. FAIL: T0 must work unchanged on a project nobody has
  seen. Remediation: SPLIT the project part down to T1.
- **D9c** Knowledge that two or more projects share sitting at T1. FAIL. Remediation: promote to T0.
  A shared artifact parked in a project repository under a different prefix is the same violation
  wearing a naming exemption.
- **D9d** A fact needed by two repositories sitting in one repository's T2 file (its
  `repos[].tier2_context`). FAIL: promote to T1.
- **D9e** An artifact named after a host, a vendor, a person, or a tool version. FAIL: the name
  guarantees a rename. Remediation: UPDATE the name to the capability it provides.
- **D9f** T1 artifacts all carry the project prefix declared in the manifest. No exemptions: an
  artifact that does not fit the prefix does not belong at that tier.

## D10 Orphan fact - provenance does not resolve

Every normative claim carries a resolvable provenance token. The token forms are a **closed set of
five**, matching the grammar in SPEC §4.2 exactly. Lowercase, four-digit record numbers, `#am` in
lower case: a token that "reads right" but does not match the grammar does not resolve.

| Form | Resolves to | Example |
|---|---|---|
| `[src: adr/NNNN]` | a record in `paths.ledger` | `[src: adr/0001]` |
| `[src: adr/NNNN#amN]` | a specific amendment of that record | `[src: adr/0001#am1]` |
| `[src: state/<topic>@YYYY-MM-DD]` | a dated record in `paths.state` | `[src: state/queues@2000-01-01]` |
| `[src: contract/<seam>@X.Y.Z]` | a version of a file in `paths.contracts` | `[src: contract/a-b@2.1.0]` |
| `[src: domain/<slug>#<anchor>]` | a term in `paths.domain` | `[src: domain/glossary#order]` |
| `[src: repo/<alias>:<path>[:<lines>][@<commit-ish>]]` | a file in a declared repository | `[src: repo/service-a:src/settings.ext:50-65]` |

- **D10a** Every normative line carries at least one token. FAIL if absent (orphan claim).
- **D10b** Every token resolves. FAIL if the target does not exist (dangling provenance).
- **D10c** Every token's target actually supports the claim. FAIL on over-citation: a claim citing a
  source that does not say it is worse than an uncited claim, because it looks verified.
- **D10d** No normative claim rests on a reference to a system outside the declared repositories. A
  ticket, a wiki page, or a chat link is not a provenance link. The former `ext:` form is retired:
  FAIL on any surviving `[src: ext:...]` token and route the claim to `bone-adr` or to a state
  verification instead.
- **D10e** Amendment specificity: a claim governed by an amendment cites the amendment, not the base
  record. The base record still reads true and will mislead.
- **D10f** A `code-ref` (`repo/<alias>:<path>`) resolves against the alias's `repos[].local_path`, at
  `repos[].pinned_at` when the token carries no `@commit-ish`. FAIL on an alias not in `repos[]`, on
  a path absent at the effective commit-ish, and on a `tier: T2` repository whose `pinned_at` is
  null. The pin is declared once per repository, never per token: advancing it is itself a curation
  act, because it re-asserts every unpinned code claim into that repository at once.
- **D10g** The bare alias form `[src: <alias>:<path>]`, without the `repo/` prefix, is a retired
  spelling. Report it as a non-blocking legacy-spelling finding and propose the migration; do not
  block on it mid-migration, and do not absorb it silently either.

Remediation: UPDATE to add or correct the token; or, if no source exists, the claim is not knowledge
yet. Route it to `bone-adr` or to a state verification and record it as an owed follow-up.

---

## Q - the standing quality bar

- **Q1 Frontmatter contract and sidecar.** The entry document's front matter carries exactly two
  keys, `name` and `description`, in that order; `name` equals the containing directory name,
  kebab-case, carrying the tier's declared prefix. FAIL on any third key: all machine-readable
  metadata belongs in the `meta.yaml` sidecar. FAIL on a capability unit directory with no
  `meta.yaml`, on a `meta.yaml` that does not parse, and on one missing `name`, `tier`, `category`,
  `gate`, `owns`, `chains_with` or `negative_knowledge`.
- **Q2 Description form.** `WHAT` (one clause) plus at least three `WHEN` triggers phrased as
  symptoms or as literal user vocabulary in quotes, plus at least one `NOT for X (<sibling>)` clause
  naming a real sibling, plus a load-order clause. 300 to 600 characters
  (`conventions.description_chars`), one unwrapped line. FAIL outside the range or missing a required
  part.
- **Q3 No mutable facts in a description.** See D1e.
- **Q4 Size budget.** The entry document's hard cap and target come from
  `conventions.skill_size_bytes` (default hard 12288 bytes, target 5120). Measure bytes, never lines.
  The default was raised from 10240, with its reason recorded in the distribution README. A
  PROJECT'S OWN VALUE STILL GOVERNS: a BONE declaring `skill_size_bytes` in its manifest is
  unaffected by a change to this default, so raising it here does not relax any project that set
  its own.
  Extraction is triggered by any of: file over the hard cap, a block over 3 KB, a block that is
  looked up rather than read, a block on a different change cadence from its host, a block that would
  otherwise be written twice.
- **Q5 Pointer quality.** Every `references/` entry states what is inside **and the consequence of
  not reading it**. A pointer carrying a summary is weaker than one carrying a consequence, because
  a summary invites the reader to skip the file.
- **Q6 Peer relations, declared once.** Every peer a unit depends on appears in `meta.yaml` under
  `chains_with`, with a labelled `relation`, and nowhere else. FAIL on a `## Chains with` section in
  any entry document: it is a second enumeration of the same set, and prose cannot carry a relation
  label, an `owns` path, or a negative-knowledge type. A short prose boundary paragraph stating who
  owns what is permitted and is not an enumeration.
- **Q7 Modal markers.** Every normative line carries exactly one of `MUST`, `MUST NOT`, `SHOULD`,
  `MAY`, `CONTEXT`. FAIL on an unmarked imperative: an unmarked rule is read at whatever strength the
  reader guesses.
- **Q8 Single-source templates.** A template exists once, in `references/`, as its own file. FAIL on a
  template pasted into two artifacts, and on a markdown template embedded in a fenced block using
  heading syntax, which makes phantom sections for any heading-based tooling.
- **Q9 Gotcha shape.** Negative knowledge is written as specific failure, then mechanism, then a
  generalized rule stated at stack level, with the lead clause bolded. Domain nouns appear as
  illustrations so the lesson survives being transplanted.
- **Q10 Negative-knowledge lifetime.** Every retraction, correction, or do-not-reintroduce note is
  typed in `meta.yaml` under `negative_knowledge`: `do-not-reintroduce` (permanent, and MUST state
  the `cause` that outlived its constraint), `retraction` (MUST carry a non-null `expires`),
  `historical-note` (moves to the ledger and is removed from L4). Untyped corrections are deleted;
  git holds the history.
- **Q11 State artifact ownership.** A unit owns at most one durable state artifact, declared in
  `meta.yaml` under `owns`, and no other unit declares the same path. FAIL on a live-state database
  living inside a unit's `references/`: it belongs in `paths.state`, where the ledger owns it and the
  decay hook can watch it.
- **Q12 Gate set consistency.** The gate set is enumerated once in `MANIFEST.yaml` under `gates`,
  with the fields `id`, `name`, `unit`, `scope`, `enforced_by`, `enforcement`, `status`. Every other
  mention references a gate by its `id`. FAIL on a gate named in prose that the manifest does not
  list; on a row whose `unit` does not exist on disk; on `enforced_by: []` paired with anything other
  than `enforcement: none`; and on a CI job set that does not match `enforced_by`. There is no
  `blocking` key: a gate blocks by definition, and a non-blocking check is a review dimension, not a
  gate. A gate set declared in four places by hand is not non-bypassable, it is four things to
  forget.
- **Q13 Contract co-change.** Every contract file's version and changelog are inside the file, and the
  registry index row matches. FAIL if a wire change landed without its contract change in the same
  wave.
- **Q14 House style.** No em-dash, in any file type the constitution names, not only `*.md`. A style
  rule swept over one extension leaves the violation live in the files beside it. No emoji carrying
  semantics: verdicts and statuses are words, in table cells or front matter, never in headings.
  Headings are stable identifiers.
- **Q15 No secrets.** No credential, token, key, or password value in any artifact. Secrets are
  referenced by name and storage location. FAIL on a value, including in an example.
- **Q16 Committable by construction.** No artifact is gitignored. Knowledge that cannot be committed
  cannot be shared, watched for decay, or reviewed, and is therefore not knowledge-base material.
  Author state records sensitive-free rather than excluding them.

---

## Context Decay Index

**The unit is a markdown block, never a file.** At file granularity a corpus in which every file
happens to contain one token anywhere scores a perfect coverage, while the same corpus can carry
dozens of anchoring defects. The headline number then reports the opposite of the truth, which is why
`decay.unit_granularity` has exactly one legal value.

### Block extraction (normative, so two implementations cannot diverge)

For each `.md` file in a declared `knowledge_units` path:

1. Strip YAML front matter, between the first `---` and the next `---`.
2. A fenced block and the paragraph immediately preceding it form ONE block.
3. A heading line alone is never a block. It is discarded.
4. In a table, each data row is one block. The header row and the delimiter row are discarded.
5. In a list, each top-level item is one block; continuation lines indented under an item join that
   item; a nested sub-item is its own block.
6. Otherwise a block is a maximal run of consecutive non-blank lines.

### The three sets, and their exact names

These have different denominators and **MUST NOT** be conflated:

- `units_total` = **candidate blocks**: a block containing at least one declarative sentence, not
  inside a fenced block, and not in imperative mood. Imperative mood is approximated mechanically as:
  the first word is a modal marker, or the first word is a base-form verb from the published
  imperative-verb list. The sampled false-positive rate of that approximation is reported beside it.
- `units_anchored` = candidate blocks carrying at least one **resolvable** token. This set is `U`.
- `units_decayed` = anchored blocks with at least one changed source.

```
coverage    = units_anchored / units_total       , units_total    > 0 ; null otherwise
CDI         = units_decayed  / units_anchored    , units_anchored > 0 ; null otherwise
orphan rate = (units_total - units_anchored) / units_total
```

A unit's own file is excluded from its own source set, so nothing decays itself. A path may appear in
both `watched` and `knowledge_units`; that is normal, and required for a state record that both cites
code and is cited by skills.

### Internal, external, and the whole index

Partition the watched set `W`: `W_int` are repo-relative items, `W_ext` are `repo/<alias>:<path>`
items, and `W_unavail` is the subset of `W_ext` whose `repos[].local_path` is null, absent or
unreadable. Members of `W_unavail` are excluded from the numerator **and** the denominator of every
index and are reported as `sources_unavailable`: an unavailable source can neither fabricate decay
nor hide it.

```
U_int  = { u in U : src(u) intersect W_int                != {} }
U_ext  = { u in U : src(u) intersect (W_ext minus W_unavail) != {} }

internal-CDI = decayed units in U_int / |U_int|   , |U_int| > 0 ; null otherwise
external-CDI = decayed units in U_ext / |U_ext|   , |U_ext| > 0 ; null otherwise
CDI          = decayed units in U     / |U|       , |U|     > 0 ; null otherwise
```

`U_int` and `U_ext` overlap: a unit citing both a record and a code file is in both. They are two
views of `U`, not a partition of it.

### Rules

1. **MUST** carry `unit_granularity`, `internal-CDI`, `external-CDI`, `units_total`,
   `units_anchored`, `units_decayed`, `coverage`, `|U_int|`, `|U_ext|` and `sources_unavailable` in
   the same reading as `CDI`, wherever that reading is written or displayed. A reading, a report line
   or a hook message stating `CDI` alone is non-conformant. The curation record cites the reading by
   its two scalars and does not restate the rest.
2. **MUST** report `null` with `state: uninitialised` when the baseline is unsealed or
   `units_anchored` is 0. Never `0`. There is no mtime fallback: it is the only path that can print a
   healthy zero on a base that was never measured.
3. **MUST** compute from content hashes, not modification times.
4. **MUST** report to four decimal places, and **MUST NOT** print `coverage` without its granularity
   label. An index computed at any granularity other than `block` is published under the distinct
   name `CDI-file` and is never written to the `cdi` key.
5. **MUST** flag a watched set containing no external source. An index whose entire input lives
   inside the repository it measures cannot detect "the code moved and nobody updated the doc", which
   is the failure this whole mechanism exists to prevent. At minimum the watched set carries
   `paths.ledger`, `paths.state`, `paths.contracts`, `paths.domain`, the constitution,
   `MANIFEST.yaml`, and at least one path inside every repository whose `tier2_context` is non-null.
6. **SHOULD** report alongside: **orphan rate** (above) and **dangling rate** (tokens that do not
   resolve, over all tokens). CDI measures decay of facts that are wired up; those two measure how
   much of the corpus is wired up at all. A low CDI over a corpus with a high orphan rate is a
   measurement artifact, not health.
7. **MUST** write the computed values into `cdi_at_trigger` and `cdi_after` on the curation record,
   and append a dated point to the metric stream declared under `metrics.streams`.

**CDI = 0 is evidence of nothing on its own.** An unread, unedited, wholly false knowledge base
scores 0. A zero is informative only read together with `coverage`, `|U_ext|` and
`sources_unavailable`: it then means that what is anchored has not moved, over a set whose size the
reader can see. Driving the index to zero by deleting tokens is the obvious failure mode; the orphan
rate exists to make that visible.

---

## Audit failure modes learned

Seed list. **MUST** append a dated line whenever an audit misses something a later audit catches.
This section is how the loop improves itself.

- **Body audits do not read frontmatter.** A `description` can assert a decision the body already
  corrected, and it is loaded every session.
- **A retraction reaches the file it was written in and not its siblings.** Grep-first readers land on
  the body line and never see the header.
- **A sweep that only touches skills** leaves the ledger index, the constitution, and the contract
  registry still hedging.
- **The audit's own brief can be wrong.** Verify the premise before spending an approval on it.
- **A metric whose denominator is the wrong unit reports perfect health.** Counting files where the
  definition says blocks turns "every file has a token somewhere" into "everything is anchored".
  Check what the denominator counts before believing the fraction.
- **A skill name cited in prose is not a skill that exists.** A hook, a constitution and a decision
  record all named one capability unit that was never created; the artifacts agreed with each other
  and none of them agreed with the disk. Resolve cited unit names against the filesystem.
- **An instrument can print a reassuring figure over an empty input.** Several distinct instruments
  showed it. An attestation check passed any commit that added any record, without asking whether
  the record accounted for what the commit changed. A review loop's capped run and its converged
  run reported identically apart from one line among many, so a finding count read as a total when
  it was a floor. A metric stream deduplicated per day on a key carrying the index and omitting
  every denominator, so a reading that moved only coverage was discarded as identical to one that
  had not. And a count over a parent set was corrected by its own author after it was built. Most
  share one shape: **the number survived and its qualifier did not**, and more than once the
  person misreading the number was the person who had just written the check.
  *General rule: for every figure an instrument publishes, ask what it would print if the thing it
  measures were entirely absent. If that answer is reassuring, the instrument is not measuring. And
  never let a floor and a total render as the same string: the qualifier belongs in the sentence
  carrying the number, not in a line beside it.*
- **Two curators against one working copy, and the seal is a global clock reset.** Two sessions
  ran this loop over the same checkout concurrently and both read the identical trigger index.
  Neither could see the other. The first applied its changeset and sealed; the second was still
  auditing, and its findings, its verified premises and its record all described a corpus state
  that no longer existed by the time it proposed. Worse than duplicated effort: a seal asserts that
  every decayed block was re-read, so the first session's seal silently made that assertion on
  behalf of the sources only the second session had looked at, and the second session's own seal
  would have done the same in reverse. Nothing in the loop serialises two curators, and nothing in
  a record says which other sessions were live when it was written. A neighbouring hazard: test
  runs in a shared checkout are unstable, because a file another session has mid-write makes a
  green go red and back again, so a verdict taken there is a reading of two sessions at once.
  *General rule: before Step 5, establish that you are the only curator on this working copy, and
  re-read the trigger index immediately before proposing rather than trusting the one the session
  started with. A seal is not a per-session act and must not be taken while another session's work
  is uncommitted in the tree. When a red appears in a shared checkout, prove it survives against
  the committed blob before you report it or act on it.*

---

## Reporting

Report findings as a table ordered by consequence, not by class ID:

| ID | Verdict | Target | Evidence | Finding | Remediation |
|---|---|---|---|---|---|

Close with: the counts per verdict; the index line carrying `CDI`, `internal-CDI`, `external-CDI`,
`coverage`, `units_total`, `units_anchored`, `units_decayed`, `|U_int|`, `|U_ext|`,
`sources_unavailable` and `unit_granularity: block`; the orphan and dangling rates; and a one-line
overall verdict. Then go to Step 3 and turn the `FAIL` and `NEEDS-INFO` rows into changeset
proposals. A finding is not a change until a human approves it.
