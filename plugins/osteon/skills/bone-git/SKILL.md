---
name: bone-git
description: Branch, commit and change-request discipline for any BONE-governed project, parameterised by MANIFEST.yaml instead of hardcoded to one forge or tracker. Use when asked to "commit", "push", "open an MR", "open a PR", "start a branch", "land this", when a push is rejected or a branch has drifted, or when dirty work spans several concerns. NOT for judging a diff's content (bone-review), forge auth and connection mechanics (the project's T1 integration skill), or knowledge-base edits (bone-curator). Load the project's T1 context skill and MANIFEST.yaml first.
---

# BONE Git Workflow

Land work as a reviewable, revertable, traceable unit in any project that carries a BONE. Load the project's T1 context skill first, then read `MANIFEST.yaml`.

> **The forge and the tracker are parameters of this skill, not facts of it.** Every host, CLI, branch name, key format and template path below is read from `MANIFEST.yaml` at use time. A rule here that names a specific product is a defect: T0 skills MUST stay project-agnostic.

## When to use

- Any request to commit, push, branch, or open a change request in a BONE-governed repo.
- A push is rejected, a branch is behind the integration branch, or history looks wrong.
- Uncommitted work spans several concerns, or a change request is about to be declared ready.

## MANIFEST keys this skill reads

Declared once in the manifest, read at use time. This skill MUST NOT restate their values in prose; a second copy of a list is a second thing to go stale.

| Key | Decides | If absent |
|---|---|---|
| `forge.kind` · `forge.host` · `forge.cli` · `forge.change_request_term` | which CLI and API surface to use, and the noun to use in output | STOP and ask; MUST NOT infer from remotes |
| `tracker.system_of_record` · `tracker.key_pattern` · `tracker.close_keyword` | how a work unit is keyed, referenced, closed | STOP; see *Two key conventions* |
| `branching.integration_branch` · `branching.protected[]` | what may never be pushed to directly | treat every long-lived branch as protected |
| `branching.branch_pattern` · `commits.subject_pattern` · `commits.trailer` | naming and message shape | STOP and ask |
| `commits.types[]` | the closed type vocabulary, if the project uses one | no type layer; subject is the pattern alone |
| `change_request.template` | path to the single-source body template | STOP and ask |
| `gates[]` (`id`, `scope`, `enforcement`) | which gates apply to which change classes | no gates declared is itself a finding; report it |
| `repos[]` (`alias`, `url`, `default_branch`, `local_path`, `role`) | which repository, its canonical remote, its protected branch, and where the working copy is | STOP and ask |

**Commit scopes MUST NOT be enumerated in the manifest.** They change weekly and a stale enumeration is worse than none; derive the live list from the integration branch's own subjects.

## Two key conventions, one skill

A BONE project keys its work units one of two ways; the manifest declares which. **Both are equally supported and this skill MUST NOT prefer one.**

| | `tracker.system_of_record: forge` | `tracker.system_of_record: external` |
|---|---|---|
| Work-unit key | the forge's own issue identifier | the external tracker's key |
| Branch and commit subject | `branching.branch_pattern` / `commits.subject_pattern` rendered with the key | identical templates, external key |
| Trailer | usually redundant; the forge links natively | REQUIRED; the forge cannot link it |
| Closing | `close_keyword` in the body closes the issue on merge | the tracker transitions separately; the body MUST NOT claim to close it |

**MUST: exactly one system is the system of record.** Where both a forge issue and an external key exist, the manifest names which one branches and commits are keyed to; the other MAY appear once in the body as a cross-reference. Two keys in one subject is a drift hazard.

**MUST NOT infer the convention from commit history**, which is evidence of past practice including past mistakes. A `tracker.system_of_record` of `UNDECIDED` is an undecided delivery model: stop, say so, route it to `bone-adr`. Working around a missing decision silently makes one.

## Golden rules

1. **MUST** start every work unit from a freshly fetched integration ref, never a stale local copy.
2. **MUST** keep one task per branch. A branch carrying two work-unit keys cannot be reverted, reviewed, or traced to a decision. **SHOULD** keep it small enough for one reviewer in one sitting: a change request that needs a reading order is two.
3. **MUST NOT** push directly to any branch in `branching.protected[]`. An emergency is a fast change request, not a direct push.
4. **MUST NOT** force-push a branch anyone else may have fetched. Force is permitted only on a branch you created, with no change request open, that no other agent, worktree, or mirroring pipeline tracks. Shared-ness is a property of the ref's reachability, not of who you know pulled it. When in doubt it is shared.
5. **MUST NOT** commit secret values anywhere: file contents, fixtures, messages, branch names, or change-request bodies. Reference a secret by name and location only.
6. **MUST** make each commit atomic: one concern, self-contained, independently revertable. Group by concern, not by file; split hunks when one file serves two concerns.
7. **MUST** self-review each staged group through `bone-review`, and the whole change again before declaring it ready.
8. **MUST** render the change-request body from `change_request.template`, never from memory. If a section is missing from the template it is not required; if it is required it belongs in the template.
9. **MUST** ship the knowledge change in the same wave as the code that invalidates it: a contract when the wire changes, an amendment when the change contradicts an accepted decision, a state record when a verified fact moves. Not after.
10. **MUST NOT** stash to move uncommitted work when parallel agents or worktrees share the repository: the stash stack is per-repository, so a push/pop pair can capture then drop another agent's staged work. Branch off the fetched ref; the working tree rides along.
11. **MUST** stop and report, rather than resolve, whenever landing would require rewriting shared history, deleting a protected ref, or disabling a gate.

## Workflow

No step is optional. Steps 6 and 7 are skipped only for a repo whose `repos[].url` is null, and that repo MUST be marked so in the manifest rather than special-cased here. There is no `remote` key: the canonical remote is `repos[].url`.

```
0.  Fetch. Branch off origin/<integration_branch> using branching.branch_pattern.
1.  Read the full diff before touching anything.
2.  Verify never-commit paths are clean and gitignored.
3.  Group into atomic commits by concern.
4.  Per group: stage named files only -> inspect staged diff -> self-review (bone-review)
    -> secret scan -> commit per commits.subject_pattern (+ commits.trailer).
5.  Review branch history and the full outgoing diff.
6.  Push. Confirm by reading the remote ref, not the exit code.
7.  Open the change request from change_request.template. Fill or strike every section.
```

## Self-review before declaring ready

**MUST** hold before a human reviewer is requested. A human's first read is scarce and MUST NOT be spent on findings the author could have produced.

1. Every gate whose `gates[].scope` matches a change class in this diff has run, with a per-gate verdict, reported by `id`.
2. `bone-review` has run over the full diff, not only per commit, and every BLOCKING finding is resolved or deferred to a named owner.
3. The knowledge-impact block from `bone-review` is present and non-empty. "None" is an assertion the author makes, not a silence.
4. Every body claim not visible in the diff carries a provenance token in the grammar of SPEC §4.2: `[src: adr/NNNN]`, `[src: contract/<seam>@X.Y.Z]`, `[src: state/<topic>@YYYY-MM-DD]`, `[src: domain/<slug>#<anchor>]`, or `[src: repo/<alias>:<path>]`.
5. The work-unit key appears exactly once, in the form the manifest declares.
6. If the diff touches a governed knowledge path, it carries the curation record for that change in the same commit or change request. Knowledge edited with no record is an unattested apply.

## Critical gotchas

- **A push that "succeeded" locally is not a push.** Chained commands report the last command's status, so a failed push followed by a successful query reads as success. Verify by reading the remote ref and comparing it to the local tip. *General rule: confirm a remote side effect by reading remote state, not a local exit code.*
- **Branching off an unfetched local integration branch reproduces yesterday's tree.** The failure is silent: the branch is valid, the diff is clean, and the change quietly reverts whatever landed in between. *General rule: an operation whose correctness depends on a remote ref MUST refresh that ref in the same step.*
- **A secret removed in a later commit is still in the branch.** Reviewers read the tip's diff, so the removal looks complete while the value stays reachable in history and in every mirror. Treat the value as compromised and route rotation to its owner. *General rule: for exposure purposes version control is append-only; deletion is not remediation.*

## Output

Report in this order: branch created; commits made, one subject line per concern; push result with the verified remote tip; change-request identifier and URL; readiness verdict.

Readiness vocabulary (closed set): `READY` · `NOT-READY (<blocking reason>)` · `HELD (<what it waits on>)`. Never report `READY` while any gate verdict is `FAIL` or `NEEDS-INFO`.

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here.

This skill owns the **process** (branches, commit shape, the change-request wave); the T1 integration skill owns the **mechanics** (which CLI reaches the forge, how it authenticates, where the credential resolves from); `bone-review` owns the **judgment** about content. Tie-break by change cadence: if it changes when a token rotates or a tool is swapped it is mechanics, if it changes when the process changes it is here.
