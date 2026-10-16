# Editions

One source, three readers. `render.py --edition` applies this table; the rows marked enforced are
failed by `check.py` when broken.

| Element | client | colleague | owner |
|---|---|---|---|
| Cover, standfirst, figures, read-first notices | yes | yes | yes |
| Testing checklist and test-now cards with steps and screenshots | yes | yes | yes |
| Coming-next items | yes | yes | yes |
| Internal items | a count per area | a count per area | itemised in the index |
| Links | only addresses matching `rules.public_link_patterns` (enforced) | all | all |
| Plan task identifiers, engineering titles | never (enforced through `rules.internal_id_pattern`) | yes | yes |
| Evidence lines | never (enforced) | yes | yes |
| Plan reference and sources | no | yes | yes |
| Open work by kind, defaults in force, asks | yes | yes | yes |
| Acts awaiting the owner's go | no | no | yes |
| Risks | only entries with `client: true` | all | all |
| Item index | no | yes | yes |

`prepared_for` and `signature` MAY be a string or an object keyed by edition, so each edition names
its own reader.

## Client edition

- **MUST NOT** name the organisation hosting the work, an internal repository, a task identifier, or
  the machinery: agents, sessions, lanes, batches, tools. **MUST** list those words in
  `rules.deny_terms` and the identifier shape in `rules.internal_id_pattern`, so the check fails on
  them instead of relying on a reread.
- **MUST** write outcomes the reader can see, in the reader's words. A change request title written
  for engineers is rewritten into `title`; the original goes in `engineering_title`, which only the
  other editions show.
- **MUST NOT** apologise, assign blame or narrate how the work was done. State what changed and what
  is needed. `check.py` returns NEEDS-INFO on apology words so a person looks.
- **MUST** follow the reader's spelling convention, declared in `locale`, and sign with the name the
  reader knows.
- **SHOULD** keep the standfirst to three sentences, with every figure a token or a sourced `kpis`
  value.

## Colleague edition

- **MAY** use engineering language, identifiers and links.
- **MUST** still carry no secret, no personal filesystem path and no account name that is not the
  reader's.
- **SHOULD** keep each evidence line to the probe and its observed result, never a transcript.

## Owner edition

- **MUST** carry everything the colleague edition carries, plus `acts_needing_go` and every risk.
- **MAY** carry process notes that change what the owner decides next. Anything else belongs in the
  session journal, not in a report.
