#!/bin/sh
# session-start.sh - run the BONE decay check for a BONE that does not carry its own.
#
# A BONE scaffolded by bone-init wires .claude/hooks/decay-check.sh to SessionStart in its own
# settings, so this hook is silent there and in every directory that is not a BONE. It speaks only
# for a BONE (a MANIFEST.yaml declaring bone_version) that lacks that hook, by running the
# scaffold's decay check from a temporary copy with the project name filled in. The kill switch
# BONE_DECAY_CHECK=off is honoured. A broken hook must never end a session: always exit 0.
P=${CLAUDE_PROJECT_DIR:-}
H="${CLAUDE_PLUGIN_ROOT:-}/scaffold/template/.claude/hooks"
[ -n "$P" ] && [ -f "$P/MANIFEST.yaml" ] || exit 0
grep -q '^bone_version:' "$P/MANIFEST.yaml" 2>/dev/null || exit 0
[ -f "$P/.claude/hooks/decay-check.sh" ] && exit 0
[ "${BONE_DECAY_CHECK:-}" = off ] && exit 0
[ -r "$H/decay-check.sh" ] || exit 0
T=$(mktemp -d "${TMPDIR:-/tmp}/osteon-decay.XXXXXX") || exit 0
trap 'rm -rf "$T"' EXIT
# The project name is the directory's basename. It is written to a sed script file first, with
# sed's own special characters escaped, so no command line is assembled from it at run time.
basename "$P" | sed 's/[\&|]/\\&/g; s|^|s/{{PROJECT}}/|; s|$|/g|' > "$T/name.sed" || exit 0
for f in decay-check.sh cdi.sh bone-lib.sh; do
  sed -f "$T/name.sed" "$H/$f" > "$T/$f" || exit 0
done
sh "$T/decay-check.sh" 2>/dev/null
exit 0
