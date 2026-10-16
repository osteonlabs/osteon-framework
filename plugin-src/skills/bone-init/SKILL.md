---
name: bone-init
description: Scaffold a new BONE, the one governed knowledge repository for a project, from the scaffold this plugin ships, with its decay-check hook wired and a genesis commit. Use when starting OSTEON on a project, when someone says "set up a BONE", "start a knowledge repo" or "init OSTEON here", or when a project has no knowledge repository yet. NOT for operating an existing BONE (bone-onboard) or changing one (bone-curator). Read this file first; it runs one script.
allowed-tools: Bash(sh ${CLAUDE_PLUGIN_ROOT}/scaffold/bone-init.sh *), Bash(sh "${CLAUDE_PLUGIN_ROOT}/scaffold/bone-init.sh" *)
argument-hint: --project "Name" --prefix pfx --dir path [--remote url] [--owner id]
---

# bone-init

Creates `{PROJECT}-BONE`, a knowledge repository that holds no product code: the constitution
(`CLAUDE.md`, `MANIFEST.yaml`), decision records, seam contracts, state records, curation records,
the project's context skill, and the hooks that detect decay. The scaffold is the one at
`${CLAUDE_PLUGIN_ROOT}/scaffold/`; its `PLACEHOLDERS.md` documents every substituted value.

## Inputs

| Flag | Required | Meaning |
|---|---|---|
| `--project NAME` | yes | Human-readable project name, for example "City Library Lending". |
| `--prefix PFX` | yes | 2 to 8 characters, `[a-z][a-z0-9]*`. Every project skill is `<prefix>-<thing>`. |
| `--dir PATH` | yes | Target directory. Created if absent; refused if not empty. |
| `--owner ID` | no | Accountable owner handle, written into the manifest and bootstrap records. |
| `--group-url URL` | no | Git host namespace that owns the project's repositories. |
| `--remote URL` | no | Sets `origin` after the genesis commit. Nothing is pushed. |
| `--no-git`, `--dry-run`, `--force` | no | See `--help`. |

Arguments given to the command: `$ARGUMENTS`

## Procedure

1. **MUST** have `--project`, `--prefix` and `--dir` before running anything. Take them from the
   arguments above; ask for any that is missing, one question, and never invent a project name.
2. **SHOULD** show the exact command and run `--dry-run` first when the user has not seen the file
   list before:

       sh "${CLAUDE_PLUGIN_ROOT}/scaffold/bone-init.sh" --project "NAME" --prefix pfx --dir PATH --dry-run

3. **MUST** run the real command once the inputs are settled:

       sh "${CLAUDE_PLUGIN_ROOT}/scaffold/bone-init.sh" --project "NAME" --prefix pfx --dir PATH

   Exit 0 is success. Exit 1 is a usage or validation error, exit 2 a non-empty target, exit 3 a
   template that failed its own lint. Report a non-zero exit with the script's message and stop;
   **MUST NOT** retry with `--force` unless the user asks for it.
4. **MUST** relay the script's numbered next steps as written. It also confirms the hook runs:
   `sh .claude/hooks/decay-check.sh` inside the new repository exits 0 and, on a fresh scaffold,
   reports state `uninitialised`. That reading is correct; **MUST NOT** seal the baseline to
   silence it.

## Notes

- CONTEXT: where the script's text says to install the T0 capability library from
  `bone-skills/README.md`, installing this plugin already did that. The T0 skills are this
  plugin's skills, named `/osteon:<name>`.
- CONTEXT: the new repository's own `.claude/settings.json` wires its decay check to
  `SessionStart`. This plugin's own SessionStart hook stays silent in any BONE that carries that
  hook.
