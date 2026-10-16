#!/bin/sh
# selftest.sh - assertions the BONE mechanism scripts must satisfy.
# BONE template version: 0.1.0
#
# WHY THIS FILE EXISTS
#   A class of defect in this directory is invisible without a fixture. The one
#   that motivated the file: `bone_extract_tokens` ended with
#   `sed -e 's/[ \t]*$//'`, which on BSD/macOS sed is a bracket expression
#   containing space, backslash and the LETTER t. Every provenance token ending
#   in `t` was silently truncated. `requirements/base.txt` became
#   `requirements/base.tx`, the linter then reported a DEAD-EXTERNAL-REF against
#   a check whose own footer calls itself "precision ~1.00", the sealed baseline
#   recorded the truncated name as MISSING, and a build report cited the
#   fabricated defect as evidence the tooling worked. Nothing in the corpus was
#   wrong. The tool was.
#
#   Every assertion below is therefore a case where the code can be wrong in a
#   way that reads as a finding rather than as a failure.
#
# USAGE
#   sh .claude/hooks/selftest.sh          run every assertion
#   Exit 0 when all pass, 1 when any fails. Prints one line per assertion.
#
# This script is NOT a hook and is never wired into SessionStart. It is run by
# hand and by whatever CI eventually exists.

set -u

BONE_SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export BONE_SCRIPT_DIR
. "$BONE_SCRIPT_DIR/bone-lib.sh"

FIX="$BONE_SCRIPT_DIR/fixtures/blocks.md"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       got: %s\n' "$2"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2 (expected $3)"; fi; }

# ---------------------------------------------------------------------------
# 1. C17 REGRESSION. A token ending in `t` must round-trip intact.
# ---------------------------------------------------------------------------
GOT=$(bone_extract_tokens "$FIX" | grep 'requirements/base' || true)
is "C17: a token ending in t round-trips" \
   "$GOT" "repo/lending-api:requirements/base.txt"

# The same defect, one level lower: the bracket expression itself.
GOT=$(printf 'aaat\n' | sed -e 's/[[:space:]]*$//')
is "C17: sed trailing-space strip keeps a trailing t" "$GOT" "aaat"

# ---------------------------------------------------------------------------
# 2. BLOCK EXTRACTION (D-C.2). The six rules, on one fixture.
# ---------------------------------------------------------------------------
SCAN=$(bone_scan_blocks "$FIX")

GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B"' | wc -l | tr -d ' ')
is "rule 2/3/4/5/6: ten blocks extracted" "$GOT" "10"

GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $4 == "1"' | wc -l | tr -d ' ')
is "candidate blocks: eight of the ten" "$GOT" "8"

# Rule 3: the heading at line 6 starts no block.
GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $3 == "6"' | wc -l | tr -d ' ')
is "rule 3: a heading alone is never a block" "$GOT" "0"

# Rule 2: the fence joins the paragraph above it, so the block starts at the
# paragraph, and the token INSIDE the fence belongs to that one block.
GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $5 == "fence"' | wc -l | tr -d ' ')
is "rule 2: no standalone fence block" "$GOT" "0"
BN=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $3 == "12" { print $2 }')
GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' -v b="$BN" '$1 == "T" && $2 == b { print $3 }')
is "rule 2: the fenced token anchors the introducing paragraph" \
   "$GOT" "docs/state/example.md"

# Rule 4: two data rows, no header row, no delimiter row.
GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $5 == "table"' | wc -l | tr -d ' ')
is "rule 4: a table yields data rows only" "$GOT" "2"

# Rule 5: two top-level items plus one nested sub-item, and the continuation
# line does NOT become a block of its own.
GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $5 == "list"' | wc -l | tr -d ' ')
is "rule 5: three list blocks, continuation absorbed" "$GOT" "3"

# Rule 1: front-matter tokens land in block 0 and anchor nothing.
GOT=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "T" && $2 == "0" { print $3 }')
is "rule 1: front matter is block 0" "$GOT" "adr/0001"

# ---------------------------------------------------------------------------
# 3. CANDIDATE RULE. Imperative mood out, short fragments out, claims in.
# ---------------------------------------------------------------------------
CAND=$(printf '%s\n' "$SCAN" | awk -F'\t' '$1 == "B" && $4 == "1" { print $3 }' | tr '\n' ' ')
case " $CAND " in
    *" 10 "*) bad "candidate: an imperative step is excluded" "line 10 present in $CAND" ;;
    *)        ok "candidate: an imperative step is excluded" ;;
esac
case " $CAND " in
    *" 28 "*) bad "candidate: a short fragment is excluded" "line 28 in $CAND" ;;
    *)        ok "candidate: a short fragment is excluded" ;;
esac
case " $CAND " in
    *" 8 "*)  ok "candidate: a declarative sentence is included" ;;
    *)        bad "candidate: a declarative sentence is included" "line 8 missing" ;;
esac

# ---------------------------------------------------------------------------
# 4. SOURCE-ID CLASSIFICATION. The colon is the whole discriminator.
# ---------------------------------------------------------------------------
is "source kind: a repo-relative path is internal" \
   "$(bone_source_kind 'docs/adr/0001-x.md')" "internal"
is "source kind: an undeclared alias is unavailable, not internal" \
   "$(bone_source_kind 'no-such-alias:Makefile')" "external-unavailable"

# ---------------------------------------------------------------------------
# 5. HOOK CONTRACT. Every script exits 0, always.
# ---------------------------------------------------------------------------
for s in decay-check.sh cdi.sh provenance-lint.sh; do
    sh "$BONE_SCRIPT_DIR/$s" >/dev/null 2>&1
    is "$s exits 0" "$?" "0"
done
sh "$BONE_SCRIPT_DIR/decay-check.sh" --help >/dev/null 2>&1
is "decay-check.sh --help exits 0" "$?" "0"

# attestation-lint.sh exits 2 outside a git repository and 0 inside one; both are
# correct, and neither may be any other number.
sh "$BONE_SCRIPT_DIR/attestation-lint.sh" >/dev/null 2>&1
RC=$?
case "$RC" in
    0|2) ok "attestation-lint.sh exits 0 in a repo, 2 outside one (got $RC)" ;;
    *)   bad "attestation-lint.sh exits 0 or 2" "$RC" ;;
esac
sh "$BONE_SCRIPT_DIR/attestation-lint.sh" --help >/dev/null 2>&1
is "attestation-lint.sh --help exits 0" "$?" "0"

# A wedged or missing library must never end a session.
( BONE_DECAY_CHECK=off sh "$BONE_SCRIPT_DIR/decay-check.sh" >/dev/null 2>&1 )
is "decay-check.sh honours the kill switch" "$?" "0"

# ---------------------------------------------------------------------------
# 6. CDI APPEND. A repeat is the whole reading, denominators included.
# ---------------------------------------------------------------------------
# The key this replaced compared day, state, CDI, sources changed and units
# decayed only, so a reading whose coverage or anchored count had moved while CDI
# stayed at 0 was discarded as a repeat. Every case below that expects an append
# was a repeat under that key; the first case is the control that a true repeat is
# still skipped.
rd() {  # rd <generated_at> <coverage> <total> <anchored> <unavailable> <sealed_at>
    printf '{"schema":"bone.cdi/3","generated_at":"%s","state":"measured","baseline":{"sealed_at":"%s"},"cdi":0.0000,"coverage":%s,"units_total":%s,"units_anchored":%s,"units_decayed":0,"sources_changed":0,"sources_unavailable":%s}' \
        "$1" "$6" "$2" "$3" "$4" "$5"
}
rep() { if bone_reading_is_repeat "$1" "$2" "$3"; then echo repeat; else echo append; fi; }
PR=$(rd 2026-01-02T08:00:00Z 0.2000 1000 200 5 2026-01-02T07:59:00Z)
is "cdi append: the same reading later the same day is a repeat" \
   "$(rep "$PR" "$(rd 2026-01-02T20:00:00Z 0.2000 1000 200 5 2026-01-02T07:59:00Z)" 2026-01-02)" "repeat"
is "cdi append: a grown anchored set is appended" \
   "$(rep "$PR" "$(rd 2026-01-02T20:00:00Z 0.2100 1000 210 5 2026-01-02T07:59:00Z)" 2026-01-02)" "append"
is "cdi append: a grown candidate set is appended" \
   "$(rep "$PR" "$(rd 2026-01-02T20:00:00Z 0.2000 1050 210 5 2026-01-02T07:59:00Z)" 2026-01-02)" "append"
is "cdi append: a moved unavailable count is appended" \
   "$(rep "$PR" "$(rd 2026-01-02T20:00:00Z 0.2000 1000 200 4 2026-01-02T07:59:00Z)" 2026-01-02)" "append"
is "cdi append: a new seal is appended" \
   "$(rep "$PR" "$(rd 2026-01-02T20:00:00Z 0.2000 1000 200 5 2026-01-02T19:59:00Z)" 2026-01-02)" "append"
is "cdi append: the same reading the next day is appended" \
   "$(rep "$PR" "$(rd 2026-01-03T08:00:00Z 0.2000 1000 200 5 2026-01-02T07:59:00Z)" 2026-01-03)" "append"
is "cdi append: an empty stream takes the reading" \
   "$(rep "" "$(rd 2026-01-02T20:00:00Z 0.2000 1000 200 5 2026-01-02T07:59:00Z)" 2026-01-02)" "append"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
