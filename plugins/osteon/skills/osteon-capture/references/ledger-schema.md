# The capture ledger

Four append-only streams and one generated index, in `artifacts/` of the repository this unit is
installed from. The **fields are enumerated once**, in `references/fields.yaml`, with the reason
each earns its place and the reader that consumes it. This file carries the conventions and the
semantics that a field list cannot express, and **MUST NOT** repeat the list.

A field that no named reader consumes **MUST NOT** be added. An instrument whose rows nobody reads
is the estate's measured failure mode, and it is cheaper to refuse the field than to delete it after
a thousand rows carry it.

## The header line

Line 1 of every stream is a header object rather than a row. It states the stream's class, its
writer, its reader and the path of this document. Without it, a file that drifts out of its
directory becomes a second general corpus, and the class it belongs to has to be guessed. Every
reader **MUST** skip line 1; no row-shape check applies to it.

## Row conventions

- **Append only.** Never edit, never delete, never reorder. A correction is a new row.
- **`none` rather than omission.** A variable-shape log cannot be queried. A list field with
  nothing in it is written `[]`; `none` is for scalars.
- **Times are UTC, `YYYY-MM-DDTHH:MM:SSZ`.** Two clocks in one stream cannot be ordered.
- **Ids are `<prefix>-YYYY-MM-DD-<hex>`**: `obs-`, `nom-`, `vd-`, `run-`. The date in the id is a
  convenience; the ordering field is `at`.
- **`key` is kebab-case, class then subject**, for example `gate-checks-output-not-exit-code`. It is
  the only field two independent sessions have to agree on, so it **MUST** describe the failure
  class rather than the incident.

## What a row is verifiable by, stated honestly

A row carries no project, host, vendor or person, and `context_id` is a digest rather than a name.
The consequence, which this unit **MUST NOT** paper over: **a framework-tier row is verifiable only
from inside the context that wrote it.** The map from `context_id` to a real location stays at the
instance tier and never enters this ledger. Third-party verifiability is not claimed for these rows,
and a reader who is outside every context can check a nomination's internal consistency and nothing
more.

The same honesty applies to independence. `at`, `session`, `agent` and `context_id` are written by
the same actor into a plain file that nothing signs, so branch R is an honesty convention with the
strength of whatever the writer chose to type. Committing each row is the one available mechanical
backing, because a commit's date and committer are not the row author's to choose freely.

## Examples, one per stream

    {"schema":"osteon.observation/1","at":"YYYY-MM-DDTHH:MM:SSZ","id":"obs-YYYY-MM-DD-000000",
     "key":"gate-checks-output-not-exit-code","claim":"A gate script judged a suite by grepping its
     output for a failure count and never by exit code, so a compile error would have passed green.",
     "methodology":"single-session-ossification","locator":"<commit sha>","failure":"latent-proven",
     "demonstration":"<commit sha>, run against an input that exits non-zero and prints no count",
     "counterfactual":"Judge the exit code first, then read the summary line.",
     "disconfirmer":"A run of this gate on a failing input that returns non-zero and is reported FAIL.",
     "instrument":"the gate script itself","context_id":"a1b2c3d4e5f6","session":"00000000",
     "agent":"<model id>"}

    {"schema":"osteon.nomination/1","at":"...","id":"nom-...","key":"gate-checks-output-not-exit-code",
     "observations":["obs-...","obs-..."],"branch":"R","destination":"capability-unit",
     "rationale":"...","context_id":"...","session":"..."}

    {"schema":"osteon.verdict/1","at":"...","id":"vd-...","observation":"obs-...","verdict":"declined",
     "reason":"...","reopen_condition":"none","landed_in":"docs/curation/YYYY-MM-DD-<slug>.md"}

    {"schema":"osteon.run/1","at":"...","id":"run-...","methodology":"<register entry name>",
     "unit":"<unit or none>","verdict":"completed","context_id":"...","session":"...",
     "measures":[{"name":"...","value":0,"locator":"..."}],"discharges":["..."],"observations":["obs-..."]}

Rows are written on one line. They are wrapped above only so this document stays readable.

## The three rejection states, and what each admits later

They are three because they imply opposite re-nomination rules. Collapsing them either freezes true
observations forever or lets refuted ones back in.

| Verdict | What it says | Re-nomination admitted only by |
|---|---|---|
| `refuted` | the factual claim is false | a **new locator** refuting the refutation, never a re-argument of the same evidence |
| `declined` | the claim is true, the rule is not wanted at its cost | a branch R context that did not exist at decline time, so a corroborating row whose time is **after** the decline |
| `deferred` | true and wanted, blocked on something named | the named `reopen_condition` being met. This is not a rejection |

A nomination whose `key` matches a `refuted` or `declined` row is **inadmissible** unless it carries
the thing that row's status requires. This is the mechanical form of "the next audit does not
re-propose what was already refused", and it is why the index is grepped before anything else.

## The generated index

`artifacts/NOMINATIONS.md`, newest first, **hand-editing forbidden**, regenerated in the same commit
as any row that changes it. `bin/nominations-index.py --check` writes nothing and exits non-zero if
the file would change.

Columns: key, status, claim, observations, distinct contexts, newest `at`, ruling reason. `claim` is
the human column; there is no other prose in the file.

`status` is **derived, never stored**, because the streams are append-only and a stored status would
be a lie the moment it changed. Only the mechanical part of the promotion rule is computable, so the
values are: `ruled-refuted`, `ruled-declined`, `ruled-deferred`, `ruled-promoted`, `nominated`
(proposed, no ruling yet), `corroborated` (branch R satisfied mechanically, worth a human's look),
`single-context`. Branch I, and filters F, C and T, are judgement, and the generator **MUST NOT**
infer them.
