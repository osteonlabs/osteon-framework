#!/bin/sh
# session-start.sh - in a BONE: pull the latest knowledge, then run the decay check if the BONE
# does not carry its own.
#
# Silent in every directory that is not a BONE (a MANIFEST.yaml declaring bone_version). In a BONE
# it first runs session-pull.sh (not on compact), which fast-forwards the default branch from
# origin when git can do that safely and says in one line when it cannot (kill switch
# BONE_SESSION_PULL=off). Claude Code reads CLAUDE.md and the skill list before SessionStart hooks
# run, so after a pull that changes CLAUDE.md, CLAUDE.local.md, .claude/CLAUDE.md or an .md file
# under .claude/rules (in any case), the line names it and asks the session to read the current
# version, and after a pull that changes .claude/skills or .claude/commands, the output is one
# JSON object whose reloadSkills asks Claude Code to read them again. A BONE scaffolded by
# bone-init wires .claude/hooks/decay-check.sh to SessionStart in its own settings, and Claude
# Code starts that hook alongside this one, so that check may read the copy from before the pull.
# The decay check below runs only for a BONE that lacks that hook, after the pull, from a
# temporary copy of the scaffold's check. The kill switch BONE_DECAY_CHECK=off is honoured. A
# broken hook must never end a session: always exit 0.
P=${CLAUDE_PROJECT_DIR:-}
H="${CLAUDE_PLUGIN_ROOT:-}/scaffold/template/.claude/hooks"
[ -n "$P" ] && [ -f "$P/MANIFEST.yaml" ] || exit 0
grep -q '^bone_version:' "$P/MANIFEST.yaml" 2>/dev/null || exit 0
exec 2>/dev/null
T=$(mktemp -d "${TMPDIR:-/tmp}/osteon-session.XXXXXX" 2>/dev/null) ||
  T=$(mktemp -d /tmp/osteon-session.XXXXXX 2>/dev/null) || T=
[ -n "$T" ] && trap 'rm -rf "$T"' EXIT
# A signal ends the hook through the EXIT trap, so the temporary folder goes with it. The pull
# runs in the background so that the signal is handled at once and passed on to it as TERM:
# started with &, the pull and the git commands under it ignore INT and QUIT, as POSIX requires.
CP=
trap 'trap "" HUP INT TERM PIPE; [ -n "$CP" ] && kill -s TERM "$CP"; exit 0' HUP INT TERM PIPE
# The pull runs when a session starts, resumes or is cleared, never on compact: a compacted session
# is mid-work, and its files must not move under it. The event comes on stdin as JSON; stdin is
# read only when it is open and not a terminal, so a run by hand does not wait for input.
if [ -t 0 ] || ! ( : 3<&0 ) 2>/dev/null; then IN=; else IN=$(cat 2>/dev/null); fi
MSG=
case "$IN" in *'"source":"compact"'*|*'"source": "compact"'*) ;; *)
  if [ ! -r "${CLAUDE_PLUGIN_ROOT:-}/hooks/session-pull.sh" ]; then
    :
  elif [ -n "$T" ]; then
    sh "${CLAUDE_PLUGIN_ROOT}/hooks/session-pull.sh" "$P" "$T/pulled" </dev/null >"$T/msg" 2>/dev/null &
    CP=$!
    wait "$CP"
    CP=
    MSG=$(cat "$T/msg" 2>/dev/null)
  else
    MSG=$(sh "${CLAUDE_PLUGIN_ROOT}/hooks/session-pull.sh" "$P" </dev/null 2>/dev/null)
  fi ;;
esac
RELOAD=
if [ -n "$T" ] && [ -s "$T/pulled" ]; then
  # Names and paths are bytes, not characters: in the C locale, tr, sed and awk never stop at a
  # byte that is not valid in the user's locale.
  # The files Claude Code reads when a session starts: CLAUDE.md and its kin first, then the .md
  # files under .claude/rules, without regard to case (a disk that ignores case serves claude.md as
  # CLAUDE.md); five are named, and the count of the rest.
  { LC_ALL=C grep -i -e '^CLAUDE\.md$' -e '^CLAUDE\.local\.md$' -e '^\.claude/CLAUDE\.md$' "$T/pulled"
    LC_ALL=C grep -i -e '^\.claude/rules/.*\.md$' "$T/pulled"; } | LC_ALL=C awk '!seen[$0]++' >"$T/read"
  NREAD=$(LC_ALL=C wc -l <"$T/read" | tr -d ' ')
  F=$(head -n 5 "$T/read" | LC_ALL=C tr -d '\001-\011\013-\037\177' | LC_ALL=C sed 's/$/,/' | LC_ALL=C tr '\n' ' ')
  F=${F%, }
  [ "${NREAD:-0}" -gt 5 ] && F="$F and $((NREAD - 5)) more"
  if [ -n "$F" ]; then
    NOTE="read the current version before relying on it"
    [ "${NREAD:-0}" -gt 1 ] && NOTE="read the current versions before relying on them"
    MSG="$MSG Since this session started, $F changed: $NOTE."
  fi
  LC_ALL=C grep -q -i -e '^\.claude/skills/' -e '^\.claude/commands/' "$T/pulled" && RELOAD=1
fi
# A read-only command the line shows comes last, after the note, so that it can be copied as it is.
[ -n "$T" ] && [ -s "$T/pulled.cmd" ] && MSG="$MSG $(cat "$T/pulled.cmd")"
DC=
if [ ! -f "$P/.claude/hooks/decay-check.sh" ] && [ "${BONE_DECAY_CHECK:-}" != off ] &&
   [ -r "$H/decay-check.sh" ] && [ -n "$T" ] && mkdir "$T/decay"; then
  # The project name is the directory's basename. It travels as data in an environment variable
  # that the copied scripts expand, so no shell code is assembled from it.
  ok=1
  OSTEON_PROJECT_NAME=$(basename "$P") && export OSTEON_PROJECT_NAME &&
    printf '%s\n' 's/{{PROJECT}}/${OSTEON_PROJECT_NAME}/g' > "$T/name.sed" || ok=
  for f in decay-check.sh cdi.sh bone-lib.sh; do
    [ -n "$ok" ] && { sed -f "$T/name.sed" "$H/$f" > "$T/decay/$f" || ok=; }
  done
  [ -n "$ok" ] && DC=$(sh "$T/decay/decay-check.sh" </dev/null 2>/dev/null)
fi
[ -n "$DC" ] && MSG="${MSG:+$MSG
}$DC"
[ -n "$MSG" ] || exit 0
if [ -z "$RELOAD" ]; then
  printf '%s\n' "$MSG"
  exit 0
fi
# One JSON string: backslash and quote escaped, tabs and line breaks written as escapes, and the
# other control characters dropped.
J=$(printf '%s' "$MSG" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' |
  LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$(printf '\t')/\\\\t/g" -e "s/$(printf '\r')/\\\\r/g" |
  LC_ALL=C awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s","reloadSkills":true}}\n' "$J"
exit 0
