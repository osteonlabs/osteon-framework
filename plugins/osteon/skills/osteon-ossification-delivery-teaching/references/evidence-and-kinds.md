# Evidence ladder and open-work kinds

Two closed sets. `render.py` refuses a value outside them and `check.py` fails it. The labels a
reader sees are rendered from `render.py`, which holds the one copy of them.

## The evidence ladder

Ordered from strongest to weakest. An item carries exactly one state: the lowest one whose proof is
in hand.

| State | Proof it requires | Renders under |
|---|---|---|
| `seen-live` | The change itself observed on the named host by a probe anyone can repeat, signed out or with a session a person supplied. The probe and what it returned go in `evidence`. | Test now |
| `deployed` | The build that carries the change is running on the host, read from the host (a version route, a build hash, a commit), but the change sits behind a sign-in, a device or data nobody observed. | Test now, please confirm |
| `merged` | On the main line, and not shown on the host: the ancestry test shows the host's build lacks it, or the host was not read. `read_first` says which, once. | Coming next |
| `needs-build` | A client application change visible only in a build that does not exist yet. | Coming next |
| `needs-apply` | Infrastructure, or a manual data step, merged but not in effect until someone applies it. | Coming next |
| `internal` | Tests, tooling, documentation: nothing a reader can observe. | A count; itemised for the owner only |

- **MUST** grade by the lowest state whose proof is in hand. When a writer and a verifier disagree,
  the lower state stands.
- **MUST NOT** infer `deployed` from a date, a pipeline status, a merge, or a host that usually
  deploys on merge. Read the host.
- **MUST NOT** read an authentication refusal as proof the change works. A 401 or 403 proves a route
  exists and supports `deployed` at most, unless the refusal is itself the change. A 404 proves the
  route is absent on that host, never that it is private.
- **MUST** name the environment in `where`: a live site and a development host are different
  promises to a reader.
- **MUST** set `exclude: true` on an item whose probe contradicts its change request, with the
  contradiction in `evidence`, and raise it with the owner. A client edition never carries it.
- **CONTEXT** a surface that deploys on every merge makes `deployed` likely and never proven. The
  reverse also holds: one stopped pipeline leaves a whole surface at `merged` while its neighbours
  are current. State that once in `read_first`, never on every item.

## Open-work kinds

Every open plan task carries exactly one kind. The kinds sum to the open count, and `check.py`
asserts it.

| Kind | Meaning |
|---|---|
| `workable-now` | The team can finish it with nobody else |
| `needs-a-go` | The team can finish it, but one prepared step runs only on the owner's explicit approval: a deploy, a parameter, an apply |
| `account-act` | Needs the holder of an account or a credential to act |
| `person-check` | Built; needs a person to check it with a sign-in, a device or a build |
| `held-by-ruling` | Waiting on purpose, because a ruling holds it |
| `decision-owed` | A question that no ruling, recorded default or finished task answers |

- **MUST** give every `decision-owed` entry a `note` naming why no ruling, default or finished task
  covers it. A plan that passed its start gate has few or none; a large count is a triage failure,
  not a finding.
- **MUST NOT** make a kind of a tooling or pipeline outage. It is a `risks` entry with the
  substitute in use; the tasks it touches keep their real kinds.
- **MUST NOT** fold `needs-a-go` into `decision-owed`. Approving a prepared act is not a decision
  still to be made, and reporting it as one tells the reader the plan is undecided.
- **SHOULD** list the defaults in force in `defaults`, in plain words, so the reader sees what was
  decided rather than only what is missing.
- **SHOULD** state in `plan.by_area_scope` what `by_area` counts when it covers a subset, such as
  release-blocking tasks only; `check.py` otherwise requires it to sum to the plan's totals.
