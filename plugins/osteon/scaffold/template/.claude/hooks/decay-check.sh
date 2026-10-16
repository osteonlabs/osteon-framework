#!/bin/sh
# decay-check.sh - BONE SessionStart decay gate.
# BONE template version: 0.1.0
#
# ---------------------------------------------------------------------------
# ALGORITHM
#
#   1. Locate the repo root ($CLAUDE_PROJECT_DIR, else an upward walk, else PWD).
#   2. If the kill switch is set (BONE_DECAY_CHECK=off, or a .claude/hooks/
#      DISABLED file exists), exit 0 silently.
#   3. Delegate the whole measurement to `cdi.sh --kv`. There is exactly ONE
#      implementation of the decay algorithm in a BONE repo and it lives in
#      cdi.sh; this script is the presentation and the record-keeping layer.
#      If cdi.sh is missing or errors, exit 0 silently - a broken hook must
#      never be the thing that ends a session.
#   4. Decide whether to speak:
#        state=uninitialised and units_total=0 -> silent (repo not populated yet)
#        state=uninitialised and units_total>0 -> ONE first-run line (seal the baseline)
#        cdi=0 and no unabsorbed sources       -> silent (this is the healthy path)
#        otherwise                             -> the decay advisory
#   5. Append a machine-readable decay event to metrics/decay-events.jsonl on
#      EVERY run, clean ones included, deduplicated by fingerprint so that N
#      sessions in one unchanged state produce one record and not N. Recording
#      only the warnings would leave the series with no zeros and no denominator
#      for "what fraction of warnings led to a curation" - the gap that made the
#      reference implementation unmeasurable. States: clean | firstrun |
#      unabsorbed | decayed.
#   6. Always exit 0.
#
# NO NUMERAL IS EVER PRINTED FOR AN UNMEASURED BASE. In the uninitialised state
# this hook says "CDI not computable (no baseline yet)" and names the next
# action. A healthy-looking 0.0000 in front of a reader who has measured nothing
# is worse than silence, because it will be remembered as evidence.
#
# EVERY CDI IT PRINTS COMES WITH ITS COMPANIONS (B-150a). internal-CDI,
# external-CDI, |U|, |U_int|, |U_ext| and sources_unavailable appear in the same
# message and in the same event record. A bare CDI is non-conformant: 0.0000 over
# an external set of size zero and 0.0000 over an external set of size 100 are
# different claims, and only one of them is about the code.
#
# WHY THIS IS NOT AN MTIME HOOK
#   - the watched set comes from MANIFEST.yaml, not from a hardcoded array that
#     silently diverges from the curator's own input list;
#   - "changed" means the CONTENT changed, not that mtime moved. Clone, checkout,
#     touch, rsync and edit-then-revert all move mtime without changing content,
#     and every one of them fires an mtime hook for nothing;
#   - the unit is a markdown block, so the report names the paragraph that went
#     stale rather than the 10 KB file containing it;
#   - the output is a measured fraction with a named denominator and the actual
#     offending paths, not a binary basename nudge;
#   - contracts, domain docs, references/ files and files in OTHER repositories
#     are inside the watch set;
#   - every fire is recorded, so "how often does it fire" and "what fraction of
#     fires lead to a curation" become answerable.
#
# EXIT CODES
#   0  always. There is no other exit code. This is a hard requirement of a
#      SessionStart hook and is asserted by the test in the hooks README.
#
# OUTPUT CONTRACT
#   stdout: nothing at all when the knowledge base is current; otherwise a short
#   block whose last line is a concrete next action. Repo-relative paths, counts
#   and ratios only - never file content, never an environment value.
#
# DEPENDENCIES: POSIX sh + cdi.sh + bone-lib.sh. No jq, no yq, no network.
# ---------------------------------------------------------------------------

set -u
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail || true

case "${1:-}" in
    -h|--help)
        cat <<'EOF'
decay-check.sh - BONE SessionStart decay gate.

USAGE
  decay-check.sh            run the check (this is what SessionStart calls)
  decay-check.sh --help

BEHAVIOUR
  Silent when the knowledge base is current. Prints a short advisory naming the
  CDI, the changed provenance sources and the affected knowledge units when it
  is not. Always exits 0.

DISABLE
  export BONE_DECAY_CHECK=off          # per shell / per session
  touch .claude/hooks/DISABLED         # per repo, committed or not
  or remove the SessionStart entry from .claude/settings.json

RECORDS
  Appends one deduplicated event per fire to metrics/decay-events.jsonl.
EOF
        exit 0
        ;;
esac

[ "${BONE_DECAY_CHECK:-on}" = "off" ] && exit 0

BONE_SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || exit 0
export BONE_SCRIPT_DIR
[ -f "$BONE_SCRIPT_DIR/DISABLED" ] && exit 0

CDI_SH="$BONE_SCRIPT_DIR/cdi.sh"
[ -r "$CDI_SH" ] || exit 0
[ -r "$BONE_SCRIPT_DIR/bone-lib.sh" ] || exit 0

# Never let a slow or wedged measurement hold up a session start.
KV=$(sh "$CDI_SH" --kv 2>/dev/null) || exit 0
[ -n "$KV" ] || exit 0

get() { printf '%s\n' "$KV" | sed -n "s/^$1=//p" | head -n 1; }

STATE_KV=$(get state)
METHOD=$(get method)
CDI=$(get cdi)
CDI_INT=$(get internal_cdi)
CDI_EXT=$(get external_cdi)
COVERAGE=$(get coverage)
UNITS_TOTAL=$(get units_total)
UNITS_ANCHORED=$(get units_anchored)
UNITS_DECAYED=$(get units_decayed)
U_INT=$(get units_internal)
U_EXT=$(get units_external)
SRC_CHANGED=$(get sources_changed)
SRC_UNABS=$(get sources_unabsorbed)
SRC_UNAVAIL=$(get sources_unavailable)
CHANGED_TOP=$(get changed_top)
DECAYED_TOP=$(get decayed_top)
UNABS_TOP=$(get unabsorbed_top)
UNRESOLVED=$(get unresolved_tokens)

: "${UNITS_TOTAL:=0}"; : "${UNITS_DECAYED:=0}"; : "${SRC_CHANGED:=0}"; : "${SRC_UNABS:=0}"
: "${UNITS_ANCHORED:=0}"; : "${U_INT:=0}"; : "${U_EXT:=0}"; : "${SRC_UNAVAIL:=0}"
: "${CDI:=null}"; : "${CDI_INT:=null}"; : "${CDI_EXT:=null}"; : "${COVERAGE:=null}"
: "${STATE_KV:=uninitialised}"

# Resolve the project root the same way cdi.sh did, for the event log path.
ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    ROOT=$(dirname "$(dirname "$BONE_SCRIPT_DIR")")
fi

PROJECT="{{PROJECT}}"
# The T0 capability unit, named directly. There is no project-prefixed wrapper:
# a wrapper would be a second name for one procedure, and a unit that is not
# project-specific may not live in the project capability directory (B-65).
CURATOR="bone-curator"

STATE="silent"
case "$STATE_KV" in
    uninitialised)
        if [ "$UNITS_TOTAL" -gt 0 ] 2>/dev/null; then STATE="firstrun"; fi
        ;;
    *)
        # Two distinct unhealthy states, because they need different work.
        #   decayed    - a source under a unit's feet moved: RE-READ those units.
        #   unabsorbed - a source changed that NO unit cites: the suite does not
        #                know the decision exists at all. Not a lower severity,
        #                a different one, and it can never show up in the CDI
        #                ratio because it has no edge to divide by.
        if [ "$UNITS_DECAYED" -gt 0 ] 2>/dev/null; then
            STATE="decayed"
        elif [ "$SRC_UNABS" -gt 0 ] 2>/dev/null; then
            STATE="unabsorbed"
        fi
        ;;
esac

# --- record EVERY run, including the clean ones ------------------------------
# A series made only of warnings cannot show that the knowledge base was healthy
# on the days between them, and it cannot answer "what fraction of warnings led
# to a curation" without the denominator of ordinary sessions. Deduplication is
# by fingerprint, so a week of unchanged clean sessions costs one row, not seven.
record_event() {
    _ev_file="$ROOT/metrics/decay-events.jsonl"
    _ev_day=$(date -u +%Y-%m-%d 2>/dev/null) || return 0
    _ev_state="$STATE"; [ "$_ev_state" = "silent" ] && _ev_state="clean"
    _ev_fp="$_ev_day|$_ev_state|$STATE_KV|$CDI|$SRC_CHANGED|$UNITS_DECAYED|$SRC_UNABS"
    # Nothing is written for a repository with no knowledge base yet.
    [ "${UNITS_TOTAL:-0}" -gt 0 ] 2>/dev/null || return 0
    if [ -s "$_ev_file" ]; then
        _ev_prev=$(tail -n 1 "$_ev_file" 2>/dev/null | sed -n 's/.*"fingerprint":"\([^"]*\)".*/\1/p')
        [ "$_ev_prev" = "$_ev_fp" ] && return 0
    fi
    mkdir -p "$ROOT/metrics" 2>/dev/null || return 0
    # Schema 2 carries the sub-indices and every set size, because B-150a makes a
    # record stating `cdi` alone non-conformant, and because a series that keeps
    # only the headline cannot later be re-read to ask which half moved.
    printf '{"schema":"bone.decay-event/2","at":"%s","state":"%s","reading_state":"%s","method":"%s","unit_granularity":"block","cdi":%s,"internal_cdi":%s,"external_cdi":%s,"coverage":%s,"units_total":%s,"units_anchored":%s,"units_decayed":%s,"units_internal":%s,"units_external":%s,"sources_changed":%s,"sources_unabsorbed":%s,"sources_unavailable":%s,"fingerprint":"%s","curated_after":null}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_ev_state" "$STATE_KV" "$METHOD" \
        "${CDI:-null}" "${CDI_INT:-null}" "${CDI_EXT:-null}" "${COVERAGE:-null}" \
        "${UNITS_TOTAL:-0}" "${UNITS_ANCHORED:-0}" "${UNITS_DECAYED:-0}" \
        "${U_INT:-0}" "${U_EXT:-0}" \
        "${SRC_CHANGED:-0}" "${SRC_UNABS:-0}" "${SRC_UNAVAIL:-0}" "$_ev_fp" \
        >> "$_ev_file" 2>/dev/null || return 0
}
record_event

[ "$STATE" = "silent" ] && exit 0

# --- speak ------------------------------------------------------------------
# The uninitialised state prints NO NUMERAL. There is no baseline, so nothing was
# compared, and a figure here would be read as a measurement that never happened.
if [ "$STATE" = "firstrun" ]; then
    printf '%s\n' "BONE decay check: CDI not computable (no baseline yet). $UNITS_TOTAL candidate knowledge blocks found in $PROJECT's knowledge base."
    printf '%s\n' "  Next action: run the ${CURATOR} audit (propose-then-ask), then seal the clock with .claude/hooks/cdi.sh --seal"
    exit 0
fi

if [ "$STATE" = "unabsorbed" ]; then
    printf '%s\n' "BONE decay check - $SRC_UNABS changed provenance source(s) are UNABSORBED by $PROJECT's knowledge base."
    printf '%s\n' "  No knowledge block cites them, so nothing in the suite knows they exist. CDI $CDI cannot see this; that is why it is reported separately."
else
    printf '%s\n' "BONE decay check - $PROJECT knowledge base is STALE."
    printf '%s\n' "  CDI $CDI  ($UNITS_DECAYED of $UNITS_ANCHORED anchored blocks affected)  granularity=block  method=$METHOD"
fi
# B-150a: never the headline alone.
printf '%s\n' "  internal-CDI $CDI_INT over |U_int| $U_INT   external-CDI $CDI_EXT over |U_ext| $U_EXT   |U| $UNITS_ANCHORED   sources unavailable $SRC_UNAVAIL"
printf '%s\n' "  coverage $COVERAGE of $UNITS_TOTAL candidate blocks. A low CDI at low coverage is not health: what is unanchored cannot be seen to decay."
[ "$SRC_CHANGED" -gt 0 ] 2>/dev/null && \
    printf '%s\n' "  Changed provenance sources ($SRC_CHANGED): ${CHANGED_TOP:-n/a}"
[ "$UNITS_DECAYED" -gt 0 ] 2>/dev/null && \
    printf '%s\n' "  Affected knowledge blocks ($UNITS_DECAYED, file:line): ${DECAYED_TOP:-n/a}"
[ "$U_EXT" -eq 0 ] 2>/dev/null && \
    printf '%s\n' "  Note: no anchored block cites a source outside this repository, so external-CDI is null and 'the code moved and nobody updated the doc' is invisible here. Declare product paths in MANIFEST.yaml watched."
[ "$SRC_UNABS" -gt 0 ] 2>/dev/null && \
    printf '%s\n' "  Unabsorbed ($SRC_UNABS - changed and cited by NO unit, so nothing in the suite knows): ${UNABS_TOP:-n/a}"
[ "${UNRESOLVED:-0}" -gt 0 ] 2>/dev/null && \
    printf '%s\n' "  Note: $UNRESOLVED provenance token(s) do not resolve; run .claude/hooks/provenance-lint.sh"
printf '%s\n' "  Required next action: run the ${CURATOR} audit now (propose-then-ask) and surface every ADD / UPDATE / REMOVE / MERGE / SPLIT before other work."
printf '%s\n' "  After the curation is APPLIED and logged: .claude/hooks/cdi.sh --seal && .claude/hooks/cdi.sh --append"
printf '%s\n' "  Do not seal the baseline to silence this message; sealing without curating is the one action that makes the metric lie."

exit 0
