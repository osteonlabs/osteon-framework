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
- **One SessionStart hook**. It runs the decay check only in a BONE that does not carry its own
  hook, and is silent everywhere else, including every BONE the scaffold created.

## Prerequisites

- Claude Code with plugin support.
- A POSIX shell with `git`, `sed`, `grep`, `awk` and `find`. The scaffold and every hook are
  POSIX `sh` with no other dependency.
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

## Citing and license

If you use OSTEON or build on its ideas, cite it as `CITATION.cff` states. GitHub shows this as
"Cite this repository".

The content is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), so any
use or adaptation must credit the author. The scripts are licensed under MIT. See `LICENSE`.

## Building this repository

`plugins/osteon/skills/` and `plugins/osteon/scaffold/` are generated by `build.sh` from the
source repositories and are never edited by hand. Skills that exist only in the plugin, such as
`bone-init`, live in `plugin-src/skills/`. Every build must pass its gates: a names denylist over
every published file, no em dash, valid skill frontmatter, and one version across `plugin.json`,
`marketplace.json` and `CITATION.cff`. The source commits of each build are recorded locally in
`.build/provenance`, which is not published.
