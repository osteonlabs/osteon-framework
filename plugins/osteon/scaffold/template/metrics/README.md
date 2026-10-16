# Metrics

Instrumentation for the {{PROJECT}} BONE instance. This directory is part of the methodology, not an
optional extra, and it is populated from day one. A knowledge practice that cannot report whether it
is working is indistinguishable from ceremony.

There is a specific reason to instrument rather than ask. In a controlled study of experienced
developers working with AI coding tools on mature repositories, participants were measurably slower
with the tools and reported afterwards that they had been faster. Self-report about agentic tooling is
unreliable in a known direction, so the numbers here are the evidence, and impressions are not.

## Rules

- **MUST NOT** contain secrets, personal contact data, customer data, issue bodies, or file contents.
  Paths, hashes, counts, dates and ids only.
- **MUST** be committed. These files are the longitudinal record; a gitignored metric is not a metric.
- **MUST** be append-only. A correction is a new row that names the row it corrects, never an edit.
- **SHOULD** be written by the tool that produces the event, not reconstructed later. A metric
  reconstructed from memory carries the bias it was meant to detect.
- Dates are `YYYY-MM-DD`; timestamps are ISO 8601 UTC.

**Every stream file is created by the first event that produces a row.** Nothing here is pre-created
as an empty file with a header line: a header in the file plus a schema in this README are two copies
of one fact, and the copy in the file is the one nobody updates. `.gitkeep` holds the directory until
the first row lands. The declared set of streams, with the metric each carries and whether it is live
or planned, is in `MANIFEST.yaml` under `metrics.streams`, which is the single enumeration.

## Metric identifiers

The identifiers are frozen in `bone-spec/EVALUATION.md` section 2 and are cited by ID here rather
than redefined. `M1` sub-quantities (`coverage`, `internal-CDI`, `external-CDI`,
`sources_unavailable`, `units_total`, `units_anchored`, `units_decayed`, unabsorbed sources) are
**named fields of M1**, not metric identifiers of their own.

| ID | Name | Stream |
|---|---|---|
| M1 | Context Decay Index | `cdi.jsonl`, `decay-events.jsonl` |
| M2 | Time to first correct action, cold session | `cold-start.csv` |
| M3 | Context tokens per completed task | `cold-start.csv` |
| M4 | Decision latency | `decisions.csv` |
| M5 | Gate catch rate | `gates.csv` |
| M6 | Rework attributable to stale context | `rework.csv` |
| M7 | Orphan rate | `provenance.jsonl` |
| M8 | Decay debt age | `decay-events.jsonl` |
| M9 | Stale-citation count | `provenance.jsonl` |
| M10 | Duplication rate | `provenance.jsonl` |
| M11 | Curation cadence and outcome | `curation.csv` |
| M12 | Invariant adherence | `provenance.jsonl` |
| M13 | Provenance resolvability | `provenance.jsonl` |

## Streams

### `decay-events.jsonl` and `cdi.jsonl` - M1, the Context Decay Index

Written by `.claude/hooks/decay-check.sh` (one deduplicated event per fire) and by
`.claude/hooks/cdi.sh --append` (one record per explicit reading). The record schemas are defined in
those scripts' headers and are not restated here.

**The unit of measurement is a markdown BLOCK, not a file.** A file-granular index counts a file as
anchored when it holds one token, and can report full coverage over a corpus with hundreds of unanchored
claims. Any index computed at another granularity is published under the distinct name `CDI-file` and
is never written to the `cdi` key.

Three denominators, never conflated:

```
units_total    = candidate blocks: a block with at least one declarative sentence,
                 not inside a fence, not in imperative mood
units_anchored = candidate blocks carrying at least one RESOLVABLE provenance token   (this is U)
units_decayed  = anchored blocks with at least one changed source

coverage    = units_anchored / units_total            , units_total    > 0 ; null otherwise
CDI         = units_decayed  / units_anchored         , units_anchored > 0 ; null otherwise
orphan rate = (units_total - units_anchored) / units_total
```

The index splits three ways and all three are reported together; none may be published alone.
`internal-CDI` is computed over the units citing sources inside this repository, `external-CDI` over
the units citing sources in another declared repository, and `CDI` over their union. A source whose
working copy is missing is counted `sources_unavailable` and excluded from **both** sides of every
index, so it can neither fabricate decay nor hide it. Four decimal places, everywhere.

**CDI is reported only together with coverage.** An unanchored block cannot be detected as decayed,
so a corpus with low coverage has an optimistically low CDI. Reading a low CDI at low coverage as
health is the single easiest way to misuse this number.

**CDI = 0 is evidence of nothing on its own.** An unread, unedited, wholly false knowledge base
scores 0. A zero is informative only when it is read together with `coverage`, `|U_ext|` and
`sources_unavailable`: it then means that what is anchored has not moved, over a set whose size the
reader can see.

**Unabsorbed sources are counted separately.** A decision record that landed and that no unit cites is
the highest-value decay signal in the mechanism, and by construction it can never raise CDI, because
no unit points at it.

CDI is a **tunable, author-defined index** and MUST be reported as such. Its value is that it moves
under a known perturbation, not that it is a natural constant. Publish the algorithm and the raw
records alongside any claim made from it.

### `provenance.jsonl` - M7, M9, M10, M12, M13

Written by `.claude/hooks/provenance-lint.sh --json`, one record per run. Carries the resolvable and
unresolvable token counts, the orphan blocks, the legacy-spelling count and the duplication findings.

### `curation.csv` - M11, curation cadence and outcome

One row per applied changeset, derived from the front matter of the record in `docs/curation/`.

```
date,record,trigger,cdi_at_trigger,actions,refuted,rejected,deferred,approval,approver,units_before,units_after
```

`actions`, `refuted`, `rejected` and `deferred` are integer counts. `trigger` is one of
`decay-fired|decision-fired|contract-fired|state-fired|periodic|manual`. `approval` is
`per-item|user-directed|mechanical`.

### `cold-start.csv` - M2 and M3

One row per cold agent session on a task with a known-correct first action. Recorded by the operator.

```
date,task_id,condition,model,tokens_to_first_action,seconds_to_first_action,first_action_correct,files_loaded,notes
```

`condition` is the experimental arm: `none` (no knowledge base), `flat` (a single ungoverned context
file), `bone`, `bone-decayed` (BONE with the state layer rolled back while the code stays current),
or `genesis` (the corpus at its first commit, before any curation event applied a change).
`first_action_correct` is `yes|no|partial`, judged against a pre-agreed correct action, and the
judgement is recorded **before** the outcome is known where that is possible.

### `gates.csv` - M5, gate catch rate

Two event types, both required. A catch rate computed from catches alone is not a rate.

```
date,gate_id,event,change_ref,item_id,verdict,notes
```

`event` is `run` (the gate executed on a change) or `escape` (a defect of that gate's class reached
the default branch). `verdict` is `PASS|FAIL|NEEDS-INFO` for a run and empty for an escape.

### `decisions.csv` - M4, decision latency

One row per ADR reaching `accepted`. Latency is the interval a project spends acting on an unsettled
question, which is the cost the ledger exists to reduce.

```
adr,question_raised,record_created,accepted,days_to_accept,amendments,curator_pass_date,days_to_propagate
```

`days_to_propagate` is the interval from `accepted` to the curation pass that reconciled the units.
It is the direct measure of how long the knowledge base was knowingly wrong.

### `rework.csv` - M6, rework attributable to stale context

One row per incident where work was redone because the context was wrong rather than the code.

```
date,change_ref,stale_source,stale_since,detected_by,hours_lost,cdi_at_time,notes
```

`stale_source` is a provenance ref identifying what was wrong. `detected_by` is
`gate|review|ci|production|agent`. This stream is the smallest and the most valuable: it is the only
one that connects the index to a cost.

## Baseline

`metrics/curation-baseline.tsv` records the SHA-256 digest of every watched source at the moment of
the last applied curation. The curator rewrites it at the end of every applied changeset; the format
is defined in `.claude/hooks/bone-lib.sh`.

Writing the baseline is what resets the decay clock. A curation that edits knowledge without
rewriting the baseline leaves every subsequent session reporting the same stale index, and the
warning is then correctly ignored, which disables the loop.

Until the baseline is sealed there is no index: the mechanism reports `cdi: null` and
`state: "uninitialised"`. There is no mtime fallback. A fabricated 0.0000 on an unmeasured base is
worse than no reading, because it opens the time series with a number that looks like health.

## Before drawing conclusions

Record the pre-intervention baseline **before** the first curation pass: run the cold-start
measurements against the estate as it stands. Without that row, every later improvement is
attributable to someone paying attention again rather than to the method, and that confound cannot be
removed after the fact.
