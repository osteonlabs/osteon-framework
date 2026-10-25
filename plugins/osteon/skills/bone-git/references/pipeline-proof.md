# Proving the landing pipeline

The procedure that proves, on one machine, that a change lands by the route the instance records,
and that every guard enforced on this machine refuses what it exists to refuse, from every
working-copy layout sessions push from. It is run when a machine is newly set up to push, when a
guard or its wiring changes, and when someone asks to "test the flow". Every mechanic it exercises
(the guard, its wiring, a lock, the credential) belongs to the T1 integration skill; this file owns
the order, the controls and the evidence, and introduces no mechanism of its own.

Its stages are numbered P1 to P7, so they never share a number with a step of the Workflow in
`SKILL.md`. Command shapes are indented blocks with placeholders in angle brackets.

## Principles

- **MUST** read every placeholder at use time from the source its stage names, never from memory.
- **MUST** give every stage a positive control that passes on a healthy setup and, where a refusal
  is meaningful, a negative control the mechanism has to refuse. A stage that cannot fail is
  decoration: ask what it would print if the guard were entirely absent (`bone-curator`,
  `references/audit-checklist.md`, the failure mode on instruments that measure nothing).
- **MUST** take as evidence the literal lines the mechanism printed together with the exit status,
  never an exit code alone: a push with no guard at all also exits 0, and a malformed command also
  exits non-zero.
- **MUST** answer each stage, in each layout, with one verdict from `PASS` · `FAIL` · `NEEDS-INFO`,
  its evidence beside it (SPEC B-163, B-164), combined most-restrictive-wins (SPEC B-355).
- **MUST** report a stage whose subject the instance does not declare as `not applicable`, naming
  the key or record that was read. It is a status, not a verdict: it never counts as a `PASS`, and
  the stage is never invented to fill the gap.
- **MUST** stop and report a guard that fails its control, never repair or disable it inline. This
  is the procedure's own rule, after `bone-curator`'s flag, not fix: the repair is a follow-up for
  the owner of the T1 skill that wires the guard.
- **MUST NOT** pass an option that skips a hook, such as `--no-verify`, at any stage.

## Read the route before designing the stages

1. **MUST** read the operative decision that records how a change lands, under `paths.ledger`
   (`bone-onboard`, read order step 4), before any stage is designed. When no decision records it,
   the route is this skill's Workflow.
2. **MUST NOT** add a landing step the route does not have. On a route with no change request, a
   proof that opens one tests a path nobody uses and leaves an artifact on the forge for good.
3. **MUST** report each step where the recorded route departs from this skill's Workflow as a
   departure citing the decision that records it, as a documented exception cites the record that
   accepted it (`bone-review`, documented exceptions; SPEC B-166).
4. **MUST NOT** report `READY` on a route that pushes directly to a branch in `branching.protected[]`.
   Such a route departs from golden rule 3 (`SKILL.md`) as well; the proof reports both departures
   and leaves the resolution to the owner, through `bone-adr` for the decision or a change to this
   unit.
5. **MUST** stop and route to `bone-adr` when a decision contradicts the manifest or the Workflow and
   records no accepted exception (this unit's `meta.yaml`, the `bone-adr` relation).
6. **MUST** report a route that this skill's Workflow and keys cannot express (`SKILL.md`, Workflow;
   keys table, `change_request.template`) as a gap in this skill, and never close the gap itself.

## The stages and what each reads

**MUST NOT** restate a key's value here or in the report; read it at use time (`SKILL.md`, keys
table preamble). The layouts are observed live, because the manifest declares no worktree.

| Stage | Subject, read at use time | If the instance declares nothing |
|---|---|---|
| P1 Setup | `repos[]` `url`, `default_branch`, `local_path`; the publishing identity from the T1 skill or a state record under `paths.state` | `repos[]`: STOP and ask (`SKILL.md`, keys table). Identity: not applicable, unless a guard at P3 compares identities, then STOP and ask the owner of the T1 skill |
| P2 Layouts | `git worktree list --porcelain` | a bare entry first means no main checkout: prove every linked worktree and report the bare layout |
| P3 Local guards | the T1 skill or a state record: which guard, the hook it is wired to, each rule it refuses and the refs that rule applies to | not applicable, and the report says no local guard is declared |
| P4 Cross-machine | the T1 skill's mechanism, such as a lock; `owners[].id` and `roles[].route_via` for who runs it on the other machine | not applicable |
| P5 Gates | `gates[]` by `id`, `scope` matched to the route's change classes (SPEC B-159) | a finding (`SKILL.md`, keys table) |
| P6 Landing | the route; `branching.*`, `commits.*`; `change_request.template` and `forge.*` only where the route has a change request | as the keys table says |
| P7 Write-back | `paths.state` | STOP and ask |

## Before the first probe

- **MUST** take `<remote>` as the remote whose fetch and push URLs both equal `repos[].url`, read
  with `git remote get-url <remote>` and `git remote get-url --push <remote>`; a push URL or rewrite
  that sends pushes elsewhere is a `FAIL` of P1. `<trunk>` is that repository's `default_branch`.
- **MUST** fetch, then snapshot every local ref the proof could move, before any probe is built or
  worktree added:

      git fetch <remote>
      git for-each-ref refs/heads refs/remotes/<remote> > <before file>
      git worktree list --porcelain >> <before file>

- **MUST** choose each probe ref outside `branching.protected[]` and absent on the remote, the
  ref-scope rule below being the only exception, checked by exit status, since a remote that
  cannot be read also prints nothing:

      git ls-remote --exit-code <remote> refs/heads/<probe ref>; echo "exit=$?"

  `exit=2` means absent; `exit=0` means present, so another name is chosen; anything else is
  `NEEDS-INFO`.

## Layouts: prove each guard where pushes come from

- **MUST** run P3 in the main checkout and in every linked worktree `git worktree list --porcelain`
  lists, skipping entries marked `prunable`, and report any listed worktree left unproven as such.
- **SHOULD** add one linked worktree for the proof where none is listed and the T1 skill or the
  instance's practice says sessions or parallel agents use them (`SKILL.md`, golden rule 10),
  detached so it creates no branch; otherwise that layout is `not applicable`, naming what was read:

      git worktree add --detach <path> <remote>/<trunk>

- **MUST** run the read-only wiring check from inside each layout. It prints `PRESENT` or `ABSENT`,
  and `ABSENT` where a guard is declared is a `FAIL` of that layout before any probe runs:

      p=$(git rev-parse --path-format=absolute --git-path hooks/<hook>); [ -f "$p" ] && [ -x "$p" ] && echo PRESENT || echo ABSENT

  `<hook>` is the hook the T1 skill names. The absolute form names the file a push from this layout
  would run. The relative form is a path for the directory git ran in, so tested from another one,
  as through `git -C`, it names the wrong file and the check cannot fail.
- **MUST** pair it with a negative control that has to print `ABSENT`, the same line with the lookup
  pointed at a directory that does not exist, for that one command only. It proves only that the
  test can print `ABSENT`:

      p=$(git -c core.hooksPath=<a missing directory> rev-parse --path-format=absolute --git-path hooks/<hook>); [ -f "$p" ] && [ -x "$p" ] && echo PRESENT || echo ABSENT

- **MUST** check in each layout that the wiring line agrees with that layout's positive probe:
  `PRESENT` goes with the guard's own line or a trace line naming the hook, `ABSENT` with neither.
  A disagreement is a `FAIL` of the check itself.
- **MUST** record which version of the guard ran in each layout, from the guard's own output line
  where it prints one. Where it prints none and is tracked, compare the object ids of the file the
  wiring check found and of the trunk's copy, which match only when the contents do. An untracked
  guard has no trunk copy: record its id in each layout, and report layouts whose ids differ.

      git hash-object <the guard file the wiring check found>
      git rev-parse '<remote>/<trunk>:<the guard's path in the tree>'

- **CONTEXT** a per-worktree configuration override changes only the worktree it is set in, so it
  proves nothing about the others.

## Building probes

- **MUST** build each probe with `git commit-tree` on the fetched trunk's tree, so no local branch,
  `HEAD`, index or working file moves; the fetch updates only remote-tracking refs.
- **MUST** build one positive probe the guard accepts, with author and committer both the publishing
  identity, and one negative probe per refusal rule the T1 skill says the guard enforces, each
  differing from the positive probe in that rule's one thing, so one refusal cannot hide another:
  the author alone for an author rule, the committer alone for a committer rule, a second
  `-m '<trailer line>'` for a trailer rule (an escaped newline inside one `-m` adds no trailer).
- **MUST** build and push each probe in one shell invocation, as the one block below, because a
  tool shell that keeps no variables between calls leaves `sha` empty, and `:refs/heads/<probe ref>`
  is then a delete refspec that a guard skipping deletions passes with exit 0:

      tree=$(git rev-parse '<remote>/<trunk>^{tree}') &&
      parent=$(git rev-parse '<remote>/<trunk>') &&
      sha=$(GIT_AUTHOR_EMAIL='<author>' GIT_COMMITTER_EMAIL='<committer>' \
            git commit-tree "$tree" -p "$parent" -m '<subject>') &&
      : "${sha:?probe not built}" &&
      [ "$(git cat-file -t "$sha")" = commit ] &&
      echo "probe $sha -> <probe ref>" &&
      GIT_TRACE=1 git push --dry-run <remote> "${sha}:refs/heads/<probe ref>" 2>&1
      echo "exit=$?"

  The single quotes around `^{tree}` keep a shell with extended globbing from reading `^` as a
  pattern and aborting the command. The braces in `${sha}` keep a shell that reads `:r` after a
  variable name as a modifier from cutting the refspec, which turns every probe, the healthy one
  included, into an error that never reaches the guard.
- **MUST** build a probe for a content rule on a tree written under a scratch index, with synthetic
  content, never a real secret value (`SKILL.md`, golden rule 5), or report that rule unproven. The
  lines below replace the first line of the block above, in the same invocation:

      GIT_INDEX_FILE=<scratch index file> && export GIT_INDEX_FILE &&
      git read-tree '<remote>/<trunk>^{tree}' &&
      blob=$(git hash-object -w <a scratch file holding the refused content>) &&
      git update-index --add --cacheinfo "100644,${blob},<path in the tree>" &&
      tree=$(git write-tree) && unset GIT_INDEX_FILE &&

- **CONTEXT** `git commit-tree` signs only when given `-S`, whatever the configuration says. Where
  the T1 skill says the guard requires signed commits, the positive probe carries `-S`, or that rule
  is reported unproven.

## Pushing probes and reading the verdict

- **MUST** push every probe only as a dry run. A dry run gives the push hook the same input as a
  real push and does everything except send the updates.
- **CONTEXT** a dry run still contacts the remote and reads its refs, so whether it asks for the
  credential the T1 skill resolves depends on the remote.
- **MUST** read each refusal rule's ref scope from the T1 skill, and name in the report the ref each
  probe targeted. A probe ref outside `branching.protected[]` exercises only a rule that applies to
  it; for a rule scoped to a protected ref, either report the rule unproven or aim that probe's dry
  run at the protected ref, which sends no update and so is not the direct push golden rule 3
  forbids, and record it as a dry run at a protected ref. A probe pushed from an object id gives the
  hook that id where a branch name would be, so a rule keyed on the local branch name is unproven.
- **MUST** read a positive probe as `PASS` only when the output carries its `probe` line, `exit=0`,
  a line naming the probe's full id and `-> <probe ref>` (`* [new branch]` for a ref absent on the
  remote), the guard's success line or a `run_command` trace line naming the hook, and no refusal
  line; it is `FAIL` otherwise. A `- [deleted]` line, or output with no `probe` line, is a `FAIL` of
  the proof itself.
- **MUST** read a negative probe as `PASS` only on the refusal line naming its rule, a non-zero exit
  and no line naming the probe's full id and `-> <probe ref>`. Exit 0 is `FAIL` whatever was
  printed, and a refusal naming another rule is a `FAIL` of the one-rule-per-probe design. A
  non-zero exit with no refusal line is `NEEDS-INFO`: a trace line naming the hook means the guard
  ran without stating a rule, and no such line means the guard was never reached.

## What leaves the machine

- **MUST** treat everything a real push or a forge call sends as permanent. A forge may keep a closed
  change request's head ref, its author line and the history of its body after the branch is deleted
  (`SKILL.md`, gotcha *A secret removed in a later commit is still in the branch*).
- **MUST NOT** push a negative probe for real, in any layout. Where its dry run passes, the guard is
  absent or stale there, and the same push made for real reaches the remote.
- **MUST** prove P6 with the next real change that travels the recorded route, confirmed by reading
  the remote ref against the local tip (`SKILL.md`, gotcha *A push that "succeeded" locally is not a
  push*), never with a throwaway commit or change request. P6 stays `NEEDS-INFO` until then, and its
  row names the layout that change was pushed from.
- **MUST** make whatever does leave the machine harmless if kept forever: no secret value, no name
  the instance's privacy rule forbids, no foreign identity and no trailer a guard refuses.

## Steps that need the other machine

- **MUST** write a check that needs another machine, for example one machine holding a lock while
  the other's take of the same lock is refused, as an owner-side step: who runs it (`owners[].id`,
  `roles[].route_via`), the exact command as the T1 skill gives it, and the expected output line for
  the positive and the negative control alike.
- **MUST** hold that stage at `NEEDS-INFO` until the output is quoted back. The other machine is
  never simulated on this one.
- **SHOULD** run a cross-machine stage after P3 passes wherever taking or releasing its mechanism is
  itself a commit pushed to the trunk, since it is then a real push.

## Gates

- **MUST** report each gate whose `scope` matches a change class of the route, by `id`, with its
  declared `enforcement` (`bone-review`, item 9), and stop and report, never disable, a gate that
  stands in the route's way (`SKILL.md`, golden rule 11).
- **CONTEXT** a gate's mechanically checkable subset runs in the CI jobs its `enforced_by` names; a
  gate with `enforcement: none` is checked by people, per its unit.
- **MUST** report a gate's P5 row as `NEEDS-INFO` unless the instance's records hold an observed
  rejection of a non-conforming change by that gate. This is the procedure's own rule, applying the
  discipline SPEC B-305 sets for access rules: configured is not enforced.
- **MUST NOT** count a client-side guard as a gate or infer one from a gate: `gates[]` has a fixed
  field set and `enforced_by` names CI jobs (SPEC B-156).

## What a guard does not check

- **MUST** state, for each guard proven, what it does not check, read from the guard itself, so a
  `PASS` certifies no more than the guard covers.
- **CONTEXT** for example: a guard that compares emails passes a forbidden name in an author name, a
  file, a message or a path, and a guard on commit content never sees a change-request body or a
  footer a tool adds to one.
- **MUST** state, where the route admits a merge or squash made on the forge, that no client-side
  guard sees the commit the forge produces, so only a forge-side mechanism can control the trunk.
- **MUST NOT** record a rule as `ENFORCED` on this proof alone. A client-side guard runs per machine
  and can be skipped, and the specification's access-settings guide records a commit hook as
  `CONVENTION-ONLY` under SPEC B-304; SPEC B-305 asks for an observed rejection by the recorded
  mechanism. A `PASS` here is evidence about one machine, its layouts and one date.

## Cleanup

- **MUST** remove each linked worktree the proof added with `git worktree remove <path>`, and confirm
  it is gone from `git worktree list --porcelain`. Removal is refused for a worktree with modified or
  untracked files, or a locked one; the proof never passes `--force`, and reports the refusal.
  Deleting the directory asks nothing and leaves its metadata behind.
- **MUST** repeat the snapshot after cleanup and compare it with the one taken before. Any
  difference in `refs/heads`, a worktree's `HEAD` or `refs/remotes/<remote>`, and any probe ref
  chosen absent for which `git ls-remote --exit-code` no longer prints `exit=2`, is a `FAIL` of the
  proof itself.
- **MUST NOT** delete a branch, worktree, ref or file the proof did not create.
- **MUST** release whatever the proof took, such as a lock, and confirm it by the T1 mechanism's own
  check output.
- **CONTEXT** probes built with `commit-tree` are unreferenced objects; there is no branch to delete.

## Report and write-back

- **MUST** report one row per stage, layout and control, then one readiness verdict from this
  skill's closed set (`SKILL.md`, Output), most restrictive first: `NOT-READY (<stage>, <layout>)`
  on any `FAIL`; otherwise `HELD (<stage>, <layout>: <what it waits on>)` while any applicable stage
  is `NEEDS-INFO` or a departure awaits the owner, an owner-side step and the next real change
  included; `READY` only when every applicable stage is `PASS` in every layout.
- **MUST** write the result back as a dated state record under `paths.state` in the same turn
  (`bone-onboard`, a live observation is written back), naming the machine by role and each layout.

      Stage             Layout           Control   Verdict      Evidence (literal line)
      P3 Local guards   main checkout    positive  PASS         <the guard's success line>
      P3 Local guards   linked worktree  negative  FAIL         <push output with no guard line>
      P4 Cross-machine  all              none      -            not applicable: <the key or record read>
      P6 Landing        <layout pushed>  positive  NEEDS-INFO   <awaiting the next real change>
      Departures:       <each, with the decision it cites>
      Probe refs:       <each probe and the ref it targeted>
      Does not check:   <per guard, from the guard itself>
      Readiness:        NOT-READY (P3, linked worktree)

## Critical gotchas

- **A guard wired through a relative hooks path to a directory only the main checkout has runs
  nothing from a linked worktree.** Git resolves the relative path against the top level of the
  working tree the push runs in; a linked worktree reads the shared setting but has none of the main
  checkout's untracked or ignored files, so it finds no hook and runs nothing, git prints no warning
  or hint and no trace line names the hook, and a push the guard would refuse exits 0 and, made for
  real, lands. *General rule: a guard proven in one working-copy layout is unproven in every other;
  wire it by a path that resolves the same from each, and prove it from each.*
- **A guard kept in tracked files is the version checked out where it is resolved.** That is the
  pushing worktree for a relative path, or for a shim that resolves the guard from the top level,
  and the checkout an absolute path points into. Either can be older than the trunk's version and
  pass what that version refuses, while the wiring check still prints `PRESENT`. *General rule: a
  check that a guard exists is not a check of which guard ran; record the version from the run.*
- **An exit code reads the same when the guard passed and when it was absent.** In a layout that
  skips the guard, a dry run and a real push both exit 0 with no guard line. *General rule: evidence
  that a control ran is a line the control printed.*
