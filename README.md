# OSTEON

A Claude Code plugin for the OSTEON framework.

Agentic development made code cheap. Correct context is now the expensive part. OSTEON gives
context the same discipline code already has: version control, review gates, decay detection
and provenance.

Every project gets one knowledge repository, called its **BONE**. It holds no product code. It
holds the project's constitution, its decisions, the contracts between its modules, the state of
the running system as last verified, and the project's own skills.

## What ships

- **15 skills**, listed below. Plugin skills are namespaced, so each one is invoked as
  `/osteon:<name>`, for example `/osteon:bone-adr`. Claude also loads them on its own when a
  request matches a skill's description.
- **The BONE scaffold** (`plugins/osteon/scaffold/`): the template and `bone-init.sh`, which
  `/osteon:bone-init` runs. Every BONE it creates carries its own hooks: a decay check wired to
  `SessionStart`, and provenance, tier and attestation lints with a self-test.
- **One SessionStart hook**. In a BONE it first fast-forwards the default branch from `origin`
  (see [The session-start pull](#the-session-start-pull)), then runs the decay check if the BONE
  does not carry its own. It is silent everywhere else.

## Prerequisites

- Claude Code with plugin support.
- `git`, and a POSIX shell with the usual utilities: the ones POSIX defines (among them `sed`,
  `grep`, `awk`, `find` and `ps`), plus `mktemp` and `date` with `+%s`. The scaffold and every hook
  are POSIX `sh` with no other dependency. The session-start pull is tested on macOS with git 2.31,
  2.39 and 2.50, under bash 3.2, dash and ksh93, and in Claude Code 2.1.92, 2.1.309, 2.1.317 and
  2.1.319.
- For `osteon-ossification-delivery-teaching` only: Python 3.9 or later and a Chromium-family
  browser, for its PDF and screenshot steps.

## Install

```
/plugin marketplace add osteonlabs/osteon-framework
/plugin install osteon@osteon
```

To try it without installing, from a clone of this repository:

```
claude --plugin-dir ./plugins/osteon
```

## Start a BONE

1. Run `/osteon:bone-init` with a project name, a short skill prefix and an empty target
   directory:

   ```
   /osteon:bone-init --project "City Library Lending" --prefix cll --dir ~/city-library-lending-bone
   ```

   The skill can also ask you for them. It creates the repository, makes the genesis commit and
   prints numbered next steps. Nothing is pushed; add `--remote <url>` to set `origin`.
2. Open Claude Code in the new directory. The decay check runs at session start. On a fresh
   scaffold it reports the state `uninitialised`; that reading is correct until the knowledge
   base has real content and a sealed baseline.
3. Work the printed next steps: fill `MANIFEST.yaml`, write the first state records, open a
   decision record for each live question, then run `/osteon:bone-curator` for the first
   curation pass.
4. Returning to the project later, or onboarding someone new: `/osteon:bone-onboard`.

## The session-start pull

When a session starts, resumes or is cleared in a BONE that is the top folder of its own git
repository (not on compact), the plugin's hook fetches the default branch from `origin` and
fast-forwards it if the session is on that branch, so that the session reads the knowledge as
merged. The default branch is the one `origin/HEAD` names, else `main` or `master`; if origin's
default branch changed after you cloned, `git fetch origin` and `git remote set-head origin --auto`
bring `origin/HEAD` up to date, and the session then pulls once it is on the new branch.

- It only fast-forwards. It does not pull over a changed, untracked or ignored file, over local
  commits, or while a merge, rebase, `git am`, cherry-pick, revert or bisect is in progress, and it
  never stashes, even with `merge.autoStash` set. It also leaves alone a branch that is checked
  out, or being rebased, in a second worktree (one whose folder is gone counts until
  `git worktree prune` removes it, after `git worktree unlock` if it is locked), and, on a file
  system that ignores case (macOS, Windows), a commit that holds two names differing only in case.
  On any other branch it moves nothing. The fetch writes only `origin/<branch>`, whatever
  `remote.origin.fetch` says. A file you deleted without staging the deletion comes back when the
  pull changes it, and submodules are not updated.
- The fetch waits at most 20 s, with every prompt off: git's own, askpass programs, Git Credential
  Manager, and ssh (batch mode, unless you set your own ssh command). A configured credential
  helper is still asked for a stored credential. The checkout that follows runs as in a manual
  `git pull`, with the repository's own git hooks and filters (with prompts off and in the C
  locale), and is not cut off; in a partial clone it fetches the files it needs from `origin` too.
  If git stops that checkout part-way (a filter such as git-lfs is missing or fails, or the file
  system refuses a name), the line names the files git changed on disk: `git status` shows them as
  local changes, they come from the update rather than from you and are not to be committed, and
  later session starts do not pull over them. Once they are discarded and the cause is fixed, the
  next session start pulls; while the cause remains, it stops the same way. If the session start is
  cancelled during the checkout, git can leave files half-updated, or its lock file, in place;
  later session starts name what is in the way.
- It is silent when there is nothing to pull, also when nothing has been pushed to `origin` yet.
  Otherwise one line says what was pulled, or why nothing was, also when git refuses the folder
  because another user owns it (`safe.directory`). When the default branch moves forward while a
  session starts, by another session's pull, a pull by hand or a commit, the session is told what
  changed as well, unless that checkout takes longer than the 20 s. While another git command holds
  the index, HEAD or the branch's ref, the hook waits for it within the same 20 s and then names
  the lock file, so a lock left in place delays every session start until it is removed. No line
  suggests a command that changes anything.
- Claude Code reads `CLAUDE.md` and the skill list before SessionStart hooks run. When the pull
  changes `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md` or a rules file, the line names it and
  asks the session to read the current version; files these import are not named. When it changes
  skills or commands, the hook asks Claude Code to read them again (`reloadSkills`); Claude Code
  2.1.92 ignores that, and there the new skills appear from the next session.
- A BONE's own SessionStart hooks start at the same time as this one, so they can read the copy
  from before the pull. A session that is already open is not told when a later session's start
  pulls new files under it.
- The pull can bring in hooks and settings from `origin` that Claude Code then runs in later
  sessions. Where `core.hooksPath`, a filter or an included config file points into the repository,
  code from `origin` runs during the pull itself.
- The decay check appends rows to `metrics/decay-events.jsonl` at session start. Once a teammate
  commits that file, a clone whose copy holds rows of its own is not pulled until those rows are
  out of the way.
- To turn the pull off for one checkout, set `BONE_SESSION_PULL` to `off` under `env` in that
  BONE's `.claude/settings.local.json`. It also works as an environment variable.

## The skills

Starting and operating a BONE:

| Skill | Use it to |
|---|---|
| `/osteon:bone-init` | Scaffold a new BONE for a project. |
| `/osteon:bone-onboard` | Get up to speed on a project, or return to one after a gap. |
| `/osteon:bone-adr` | Write, amend or supersede a decision record. |
| `/osteon:bone-contract` | Create or version the contract for a seam between two modules. |
| `/osteon:bone-curator` | Audit the knowledge base and change it with per-item approval. |
| `/osteon:bone-git` | Branch, commit and open change requests the project's way. |
| `/osteon:bone-review` | Review a change against the project's own bar. |
| `/osteon:bone-standup` | Keep the daily brief, debrief and continuity journal. |

The framework and the ossification method:

| Skill | Use it to |
|---|---|
| `/osteon:osteon-framework` | Trace where a rule comes from, and name a way of working. |
| `/osteon:osteon-ossification-planner-project-daily` | Plan a multi-repository project as one dated cycle per day. |
| `/osteon:osteon-ossification-plan-starter` | Decide whether a plan may start, one question at a time. |
| `/osteon:osteon-ossification-plan-implementor` | Run a gated plan as lanes in one session. |
| `/osteon:osteon-single-session-ossification` | Run a large plan as one session with subagents. |
| `/osteon:osteon-ossification-delivery-teaching` | Report what a cycle delivered to people outside it. |
| `/osteon:osteon-capture` | Record what a session learned, without writing a rule. |

## Tiers: one owner per fact

| Tier | Lives at | Owns |
|---|---|---|
| T0 org | this plugin | The methodology: how to record a decision, version a contract, run the curation loop. |
| T1 project | the project's BONE | The project's facts, decisions, contracts and procedures, in prefix-named skills. |
| T2 repository | a code repository's own `CLAUDE.md` | Conventions true inside that one repository. |

A fact lives at exactly one tier, the narrowest that fully owns it. Lower tiers reference; they
never copy. When a fact could sit at two tiers, place it by what would change it, not by topic.
The personal tier, your own preferences and memory, sits outside: a BONE never governs or cites
it.

## References to material not in this plugin

The skills were written against the full OSTEON specification and a larger set of units. Some
pointers therefore name material this plugin does not ship. None of them is needed to use a skill:
each rule is stated in full where it applies, and the pointer records where it comes from.

- **`B-<number>`, `D-<letter>.<number>`, "SPEC section" and "SPEC Appendix" references** cite
  requirements in the OSTEON specification, which is not yet published. Read them as provenance.
- **`bone-skills/README.md`** was the source repository's README. Where a skill says to install
  the T0 library from it ("Installing T0"), installing this plugin already did that. Its
  "Enabling commit signing" section is ordinary git configuration (`gpg.format`,
  `user.signingkey`, `commit.gpgsign`). Its "section 4" held the authoring rules for T0 units;
  a `src: null` entry in a `meta.yaml` that points there means only that T0 has no project
  ledger to cite.
- **`bone-curate-fast`, `bone-team`, `bone-user` and `osteon-research-unit`** are units that are
  not in this release. `bone-curate-fast` is the in-session fast curation pass; until it ships,
  route that work to `/osteon:bone-curator`. `bone-team` owns a team tier and `bone-user` the
  personal tier; neither is needed for a single project. `osteon-research-unit` maintains the
  OSTEON research papers and depends on private data.

## Paper and citation

OSTEON is described in the preprint "Superintelligent Software Engineering: Governance That
Scales with Capability", [arXiv:2610.31306](https://arxiv.org/abs/2610.31306) [cs.SE], 2026,
DOI [10.48550/arXiv.2610.31306](https://doi.org/10.48550/arXiv.2610.31306).

If you use OSTEON or build on its ideas, cite the paper. To cite this software release, use its
Zenodo DOI, [10.5281/zenodo.23436020](https://doi.org/10.5281/zenodo.23436020). `CITATION.cff`
carries both, with the paper as the preferred citation; GitHub shows it as "Cite this repository".

## License

The content is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), so any
use or adaptation must credit the author. The scripts are licensed under MIT. See `LICENSE`.

## Building this repository

`plugins/osteon/skills/` and `plugins/osteon/scaffold/` are generated by `build.sh` from the
source repositories and are never edited by hand. Skills that exist only in the plugin, such as
`bone-init`, live in `plugin-src/skills/`. Every build must pass its gates: a names denylist over
every published file, no em dash, valid skill frontmatter, and one version across `plugin.json`,
`marketplace.json` and `CITATION.cff`. The source commits of each build are recorded locally in
`.build/provenance`, which is not published.
