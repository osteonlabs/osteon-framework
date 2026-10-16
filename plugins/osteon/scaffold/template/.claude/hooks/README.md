# Hooks (X, the curation loop's executable half)

These scripts ship **with the methodology**, not with the project. They are copied in unchanged and
configured through `MANIFEST.yaml`. **Do not fork one to change its behaviour for this project:** a
project that needs a different watch set declares a different watch set, and a project that needs
different behaviour needs an amendment to the spec, not a local edit.

Each script carries its full specification in its own header. That header is normative and is not
restated here.

## What is here

| File | Invoked | Role |
|---|---|---|
| `bone-lib.sh` | sourced, never executed | shared definitions: repo root, manifest reading, block extraction, token grammar, hashing |
| `cdi.sh` | manually or by `decay-check.sh` | the one implementation of the Context Decay Index |
| `decay-check.sh` | `SessionStart` (see `../settings.json`) | presentation and record keeping over `cdi.sh` |
| `provenance-lint.sh` | manually, and in CI once a gate exists | reports claims that do not chain to a source |
| `attestation-lint.sh` | manually, and in CI once a gate exists | reports governed knowledge changed with no curation record (L-27, L-28) |
| `imperative-verbs.txt` | read by `bone-lib.sh` | the published approximation of imperative mood, used to decide what counts as a claim |
| `selftest.sh` | by hand, and in CI once one exists | the assertions this directory must satisfy, including the C17 regression |
| `fixtures/blocks.md` | read by `selftest.sh` | one markdown file exercising all six block rules |

`bone-init.sh` marks every `.sh` in this directory executable at instantiation.

## The unit is a block

`cdi.sh` and `provenance-lint.sh` build ONE block index, through `bone_block_index` in
`bone-lib.sh`, so the two tools cannot report different coverage for the same corpus. A knowledge
unit is a markdown block: a paragraph, a top-level list item, a table data row, or a fenced block
with the paragraph introducing it. Not a file.

That distinction is the difference between a metric and a decoration. Measured per file, a real
corpus reported `coverage 1.0000`, meaning "every file contains a token somewhere", on the same day
the linter found dozens of anchoring defects inside those same files. Per block the same corpus
reports a coverage near 0.20, which is a number an author can act on.

## Command surface

```sh
.claude/hooks/decay-check.sh              # what SessionStart runs; silent when clean
.claude/hooks/cdi.sh                      # one-line JSON reading (default)
.claude/hooks/cdi.sh --summary            # the same reading, readable
.claude/hooks/cdi.sh --pretty             # the same reading, one field per line
.claude/hooks/cdi.sh --kv                 # key=value, for shell consumers
.claude/hooks/cdi.sh --blocks             # every candidate block, anchored or orphan
.claude/hooks/cdi.sh --seal               # rewrite the baseline: the CURATION CLOCK RESET
.claude/hooks/cdi.sh --append             # append a reading to metrics/cdi.jsonl
.claude/hooks/provenance-lint.sh          # report claims with no source
.claude/hooks/provenance-lint.sh --all    # also list P3 in full and P8 at all
.claude/hooks/provenance-lint.sh --json   # counts only, appendable to metrics/
.claude/hooks/provenance-lint.sh --strict # exit 3 on mechanical findings, for CI
sh .claude/hooks/selftest.sh              # the assertions; exit 1 if any fails
.claude/hooks/attestation-lint.sh         # L-27: a governed change with no record
.claude/hooks/attestation-lint.sh --strict # exit 3 on any L-27 finding, for CI
.claude/hooks/attestation-lint.sh --json  # counts only, appendable to metrics/
```

Every script takes `--help` and `--root DIR`. `--root` is what lets one checkout measure another.

## Exit-code contract

| Script | 0 | 2 | 3 | anything else |
|---|---|---|---|---|
| `decay-check.sh` | **always** | never | never | **impossible by design** |
| `cdi.sh` | a reading was produced, including an uninitialised one; `--seal` succeeded | bad usage, or the baseline could not be written | never | never |
| `provenance-lint.sh` | a report was produced, findings or not | bad usage | `--strict` and at least one mechanical finding | never |
| `selftest.sh` | every assertion passed | never | never | 1 when an assertion failed |
| `attestation-lint.sh` | a report was produced, or the repository has no commits | bad usage, or not a git repository | `--strict` and at least one L-27 finding | never |
| `bone-lib.sh` | n/a, it is sourced | n/a | n/a | n/a |

`decay-check.sh` returning 0 unconditionally is a hard requirement, not a convenience: a
`SessionStart` hook that can fail is a hook that ends sessions, and the first time it does, the
mechanism gets deleted rather than fixed.

`attestation-lint.sh` is the executable half of propose-then-ask. Before it existed, the only
evidence that a human had approved a change to the knowledge base was a record asserting that a human
had approved it, written by the same process that made the change. It checks that a curation record
ships in the same commit as the knowledge it describes, which is the part a machine can own; it
cannot check that the record is true, and it says so in its own footer.

`provenance-lint.sh --strict` deliberately fails only on the mechanical checks (an unresolvable
token, an unqualified path, a dead external reference, a mutable fact in a description, a state
record with no verification date). The judgement-bearing checks are reported and never block, because
a merge gate wired to a 0.6-precision heuristic is a gate that gets bypassed.

## Dependencies

POSIX `sh`, `awk`, `sed`, `grep`, `find`, `sort`, `mktemp`, `date`, and one digest utility from
`shasum` / `sha256sum` / `openssl` / `git hash-object` / `cksum` (preference order; `cksum` is used
only as a last resort and is labelled `cksum-weak` in every reading it produces).

`yq` is used for manifest reading when installed and is never required: the fallback is a documented
YAML subset parser in `bone-lib.sh`. `jq` is not used at all. There is no network access, no daemon,
no state outside the repository, and nothing is installed.

## Disabling one script

| Want | Do |
|---|---|
| silence the session hook for one shell | `export BONE_DECAY_CHECK=off` |
| silence the session hook for this checkout | `touch .claude/hooks/DISABLED` |
| remove the session hook entirely | delete the `SessionStart` entry from `../settings.json` |
| stop using `provenance-lint.sh` in CI | remove the job; nothing else references it |
| stop computing the index | there is no switch: `cdi.sh` only runs when something calls it |

There is deliberately no way to disable `cdi.sh` while leaving `decay-check.sh` on. The hook is a
presentation layer over the index; a hook that cannot measure has nothing to say.

## Verifying the installation

Run these four; each takes under a second on a repository of this size.

```sh
sh -n .claude/hooks/*.sh                          # 1. syntax, every script
sh .claude/hooks/selftest.sh                      # 2. the assertions; must end "0 failed"
.claude/hooks/decay-check.sh; echo "exit=$?"      # 3. must print exit=0
.claude/hooks/cdi.sh --summary                    # 4. must name a state and a denominator
.claude/hooks/provenance-lint.sh --json           # 5. must emit one line of valid JSON
```

A useful fifth check, because it is the property the whole design turns on: `touch` a watched source
without changing a byte of it, then run `decay-check.sh` again. It must stay silent. Under the
mtime algorithm this replaces, that `touch` would have raised a decay warning.

## What they read and write

| Path | Direction | Written by |
|---|---|---|
| `MANIFEST.yaml: watched[]` | read | the curator, by hand |
| `MANIFEST.yaml: knowledge_units[]` | read | the curator, by hand |
| `MANIFEST.yaml: repos[].alias`, `repos[].local_path`, `repos[].pinned_at` | read | the curator, by hand |
| `metrics/curation-baseline.tsv` | read, and rewritten at each curation | the curator |
| `metrics/decay-events.jsonl` | append | `decay-check.sh` |
| `metrics/cdi.jsonl` | append | `cdi.sh --append` |

**Rewriting the baseline is what resets the decay clock.** A curation that edits knowledge and does
not rewrite `metrics/curation-baseline.tsv` leaves every later session reporting the same index until
the warning is correctly ignored, which disables the loop.

## Invariants these scripts hold

1. `decay-check.sh` **always exits 0**. A `SessionStart` hook that can fail is a hook that ends
   sessions.
2. **Content, not mtime.** A clone, a checkout, a `touch`, an rsync or an edit-and-revert all move
   mtime without changing content, and every one of those would be a false decay signal. There is no
   mtime code path left to fall back to; it was deleted rather than demoted.
3. **The watch set comes from the manifest**, from ONE key, `watched`, never from a list inside a
   script. Two lists is one list too many, and the second one always drifts. The one that drifts is
   the external half, which is the only half that can see the code move.
4. **A fraction with a named denominator**, reported together with coverage, with `internal-CDI`,
   with `external-CDI` and with the size of every set. "Something changed" is not an index, and a
   bare `CDI` is not a reading.
4a. **No numeral for an unmeasured base.** With no sealed baseline, or with nothing anchored, the
   reading is `cdi: null, state: "uninitialised"` and the hook says so in words.
5. **Silent when clean.** Every fire is recorded even so, because "what fraction of warnings led to a
   curation" cannot be answered from warnings alone.
6. **Zero required dependencies** beyond POSIX sh and a hashing utility already on the machine. `yq`
   and `jq` are used when present and never required.
7. **Never prints file content.** Paths, digests, counts and ratios only.

## Kill switch

`BONE_DECAY_CHECK=off`, or a `DISABLED` file in this directory, silences the hook. If you reach for
it, record why in `docs/curation/`: a mechanism that is quietly switched off and never mentioned is
the failure mode that ends knowledge practices.

## What does NOT belong in `settings.json`

Only methodology hooks. Personal tooling, notifiers, time trackers and anything referencing `$HOME`
go in `.claude/settings.local.json`, which is gitignored. A project settings file carrying a personal
integration cannot be cloned by a teammate without importing a dependency that will fail on their
machine.
