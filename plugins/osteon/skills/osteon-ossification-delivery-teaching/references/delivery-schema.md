# delivery.json

The one source every edition renders from. `render.py` refuses a source it cannot render;
`check.py` gives the full verdict and reports unknown top-level keys as NEEDS-INFO, so a misspelt
field is never silently ignored.

## Top level

| Field | Required | Meaning |
|---|---|---|
| `schema` | yes | `osteon.delivery/1` |
| `kind` | yes | `delivery`, `status` or `progress` |
| `title`, `subtitle` | `title` | The reader's question, answered as a heading |
| `slug` | no | Output file stem; derived from the title when absent |
| `locale` | no | Spelling and date convention, for example `en-GB` |
| `prepared_for`, `prepared_by`, `signature` | `prepared_for` | Names the reader knows; a string, or an object keyed by edition |
| `as_of` | yes | `read_at` (ISO time, required), `since` (baseline date), `plan_ref`, `sources` (what was read, with counts) |
| `editions` | yes | Which of `client`, `colleague`, `owner` to render |
| `standfirst` | yes | Two or three sentences, the thesis, figures as tokens |
| `kpis` | no | Up to four `{label, value, note, source}`; `source` is required |
| `read_first` | no | Notices a reader needs before the first item |
| `areas` | yes | `{id, name, env, url, note}`, in reading order |
| `items` | yes | See below |
| `internal_counts` | no | `{area id: count}` for internal changes counted rather than listed |
| `plan` | for `status`, `progress` | `{total, done, not_needed, open, open_by_kind: [{kind, count, note, label}], by_area: [{name, done, open}], by_area_scope}`; `label` replaces the default reader label, for example to name who approves |
| `defaults` | no | Defaults in force, in plain words |
| `asks` | no | `{ask, who, why, blocks}` |
| `acts_needing_go` | no | `{act, effect, reversible}`; owner edition only |
| `risks` | no | `{risk, effect, mitigation, client}` |
| `next` | no | The next steps, in order |
| `glossary` | no | `{term, meaning}` |
| `rules` | for a client edition | `deny_terms`, `internal_id_pattern`, `public_link_patterns`, `reviewed_secret_fingerprints` |

## An item

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique across the source; never shown in a client edition |
| `area` | yes | An `areas[].id` |
| `state` | yes | A state on the evidence ladder |
| `title` | yes | The outcome, in the reader's words |
| `engineering_title` | no | The change request's own title, for colleague and owner |
| `what_changed` | unless internal | One to three sentences |
| `why` | should, for test-now | The effect on a customer, an operator or the business |
| `where` | test-now | Environment, address and the path through the screens |
| `steps` | test-now | Numbered actions, one each, starting from an address |
| `expect` | test-now | The observable result, including the refusal path |
| `access` | test-now | The account or role needed, or `none` |
| `not_yet` | no | What the change does not do yet |
| `test_later` | no | For coming-next items: where it becomes testable |
| `evidence` | for `seen-live` | The probe and what it returned; `needs-human:` prefixes a card waiting on a person |
| `links` | no | `{label, url}` |
| `screenshots` | no | `{file, caption, url}`, with `file` relative to the output directory |
| `screen_note` | no | For a view that cannot be captured: what the reader will see |
| `task_ids` | no | Plan task identifiers this item advances |
| `exclude` | no | `true` keeps the item out of every edition; the reason goes in `evidence` |

## Tokens

Any text field outside `rules` may carry a token. `render.py` computes it from the items and the
plan, and refuses an unknown token, an unknown state or area, and any `{{` left unexpanded.

    {{count}}                           every listed item that is not excluded
    {{count state=seen-live}}           listed items in one state
    {{count state=seen-live,deployed}}  listed items in any of the named states
    {{count area=catalogue}}            listed items in one area; combines with state=
    {{internal}}                        internal items listed plus internal_counts
    {{changes}}                         every change: listed non-internal items plus {{internal}}
    {{plan.total}} {{plan.done}} {{plan.not_needed}} {{plan.open}}
    {{kind.workable-now}}               open tasks of one kind

## Outputs

`render.py SOURCE --out DIR` writes `<slug>-<edition>.md`, `.html` and `.pdf` for each edition, and
`<slug>.render.json`, which records the digest of the source and of every output. `check.py` fails
an output whose digest no longer matches, which is how an edit made to a rendered file is caught.

## The worked example

`scripts/example/delivery.json` is complete and names nothing real. From the unit's directory:

    python3 scripts/render.py scripts/example/delivery.json --out <scratch dir>
    python3 scripts/check.py scripts/example/delivery.json --out <scratch dir>

The check ends in NEEDS-INFO on the external scanner until `--scanner` is given: that verdict is
the check working. Render the example into a scratch directory, never into a delivery directory: its
files would sit beside a real report and be sent with it.
