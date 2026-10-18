# Placeholders

**This file is the single source of truth for the substitution set.** `bone-init.sh` lints against it
on every run: a `{{PLACEHOLDER}}` in `template/` that is not listed here fails, and a placeholder listed here that
appears nowhere in `template/` fails. The two cannot drift.

## Syntax

| Form | Meaning | Who fills it |
|---|---|---|
| `{{PLACEHOLDER}}` | substituted by `bone-init.sh` at instantiation | the script |
| `<angle brackets>` | a field a human fills in when authoring a record from a template | the author |

The two are deliberately different so that an unfilled `<field>` in a committed ADR is obvious and an
unsubstituted `{{PLACEHOLDER}}` in a scaffolded repository is a script bug rather than an authoring gap.

Substitution runs over **every file in `template/`, including its pathnames**. A directory named
`{{PREFIX}}-context` becomes `cll-context`.

## The set

| Placeholder | Source | Required | Example | Appears in |
|---|---|---|---|---|
| `{{PROJECT}}` | `--project` | yes | `City Library Lending` | `CLAUDE.md`, `MANIFEST.yaml`, `CURATION.md`, `GLOSSARY.md`, the layer READMEs, `metrics/README.md`, the hooks, `<prefix>-context/SKILL.md`, `docs/adr/0000`, the bootstrap curation record |
| `{{PROJECT_SLUG}}` | `--slug`, else derived from `--project` | yes | `city-library-lending` | `MANIFEST.yaml` (`project.id`, `project.slug`) |
| `{{PREFIX}}` | `--prefix` | yes | `cll` | `MANIFEST.yaml`, `CLAUDE.md`, the hooks, every capability path, `SKILL.md`, `meta.yaml`, the archetypes in `.claude/templates/`, the bootstrap curation record |
| `{{BONE_REPO}}` | `--bone-repo`, else `<slug>-bone` | yes | `city-library-lending-bone` | `CLAUDE.md`, `MANIFEST.yaml`, `.gitignore`, the bootstrap curation record, and the genesis commit message |
| `{{GROUP_URL}}` | `--group-url`, else `TODO-set-group-url` | no | `https://git.example.org/city-library` | `MANIFEST.yaml` |
| `{{OWNER}}` | `--owner`, else `TODO-set-owner` | no | `owner` | `MANIFEST.yaml` (`owners[]`, `docs_registry[].owner`), `CLAUDE.md`, `CURATION.md`, `docs/adr/*`, the bootstrap curation record |
| `{{DATE}}` | `--date`, else today, `YYYY-MM-DD` | no | `2026-01-15` | `CLAUDE.md`, `MANIFEST.yaml`, `CURATION.md`, `docs/adr/0000`, the bootstrap curation record's front matter **and its filename** |
| `{{BONE_VERSION}}` | constant in `bone-init.sh` | n/a | `0.1.0` | `CLAUDE.md`, `MANIFEST.yaml`, the bootstrap curation record |
| `{{SCHEMA_VERSION}}` | constant in `bone-init.sh` | n/a | `1.0` | `MANIFEST.yaml` |

## Rules

1. **Adding a placeholder is a three-step change:** add it to `PLACEHOLDERS` in `bone-init.sh`, add a
   row here, and use it in `template/`. The lint fails if any of the three is missing, which is the
   point.
2. **Placeholder names are `[A-Z0-9_]+`.** The lint scans for `{{[A-Za-z0-9_]+}}` so a lowercase or
   hyphenated placeholder is caught rather than silently ignored.
3. **A placeholder MUST NOT carry a fact that will change.** These are identity values, fixed at
   instantiation. Anything mutable belongs in `MANIFEST.yaml` or a state record, where it can be
   dated and re-verified.
4. **`{{DATE}}` is the instantiation date and never changes afterwards.** It is not "today". Nothing
   in the scaffold re-reads it.
5. **There is no `{{...}}-curator` placeholder and there never will be.** The curation procedure is
   the T0 unit `bone-curator`, named directly. A per-project wrapper would be a second name for one
   procedure, and a placeholder that expands to a unit nobody ships is how every decay advisory in
   the scaffold ends up naming a skill that does not exist.

## What `--lint-templates` checks

Beyond the three-way placeholder lint above, it also:

- validates `template/MANIFEST.yaml.tmpl` against the frozen schema: required keys present,
  top-level key set closed and in the normative order, `alias` first in every `repos[]` item, and
  `path` first in every `watched`, `knowledge_units`, `docs_registry` and `metrics.streams` item;
- asserts by execution that `--help` exits 0 and prints more than one line, and that `--version`
  exits 0. A heredoc terminated early by its own body is invisible to `sh -n`, so this is checked by
  running it, not by reading it.

The same manifest validation runs again on the **substituted** `MANIFEST.yaml` after a scaffold, so
a substitution that breaks the shape cannot ship.
