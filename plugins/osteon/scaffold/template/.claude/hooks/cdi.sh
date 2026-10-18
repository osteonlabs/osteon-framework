#!/bin/sh
# cdi.sh - compute the BONE Context Decay Index.
# BONE template version: 0.1.0
#
# ---------------------------------------------------------------------------
# WHAT IT MEASURES
#
#   A KNOWLEDGE UNIT IS A MARKDOWN BLOCK, not a file (B-108, D-C.1). The block
#   rules are implemented once, in `bone_scan_blocks` in bone-lib.sh: a paragraph,
#   a top-level list item, a table data row, or a fenced block with the paragraph
#   that introduces it. The files those blocks come from are declared by
#   MANIFEST.yaml `knowledge_units:`; the fallback is every *.md under
#   .claude/skills/.
#
#   WHY THE GRANULARITY IS THE WHOLE POINT. Measured per file, a real corpus
#   reported units_total equal to units_anchored, coverage 1.0000 - "every
#   file contains a token somewhere" - while the provenance linter found
#   dozens of mechanical anchoring defects inside those same files. A
#   headline that reads 1.0000 on a corpus with dozens of unanchored claims does
#   not merely lose precision; it reports the opposite of the truth, and it does
#   so in the direction that flatters the method. Per block, one changed source
#   also decays the three paragraphs that cite it rather than the whole 10 KB
#   document.
#
#   A PROVENANCE SOURCE is an artifact a claim may chain to: a decision record
#   (docs/adr/), a dated live-state record (docs/state/), a seam contract
#   (docs/contracts/), a domain document (docs/domain/), the constitution, or a
#   file in another declared repository. Sources are declared by MANIFEST.yaml
#   `watched:` - ONE list, internal and external together; the fallback is the
#   canonical BONE layout. Any source actually cited by a unit is added to the
#   watched set even if the manifest omits it, so a manifest gap degrades
#   precision, never correctness.
#
#   THE THREE COUNTS, WHICH HAVE THREE DIFFERENT DENOMINATORS (D-C.3):
#     units_total     candidate blocks: a block holding at least one declarative
#                     sentence outside any fence, not in imperative mood.
#     units_anchored  candidate blocks carrying at least one RESOLVABLE
#                     provenance token. This set is U, the CDI denominator.
#     units_decayed   anchored blocks with at least one changed source.
#
#       CDI         = units_decayed  / units_anchored     (null when U is empty)
#       coverage    = units_anchored / units_total        (null when total is 0)
#       orphan rate = (units_total - units_anchored) / units_total
#
#   CDI is reported ONLY together with coverage, with both sub-indices below, and
#   with the size of every set. An unanchored block cannot be detected as
#   decayed, so a corpus with low coverage has an optimistically low CDI.
#
#   INTERNAL AND EXTERNAL ARE REPORTED SEPARATELY (D-D.2). Partition the watched
#   set: W_int is repo-relative, W_ext is `<alias>:<path>` resolved through
#   repos[].local_path, W_unavail is the part of W_ext with no working copy here.
#
#       internal-CDI = decayed via W_int / blocks citing W_int
#       external-CDI = decayed via W_ext / blocks citing W_ext
#
#   U_int and U_ext OVERLAP; they are two views of U, not a partition of it. The
#   split exists because an index whose entire input lives inside the repository
#   it measures cannot detect "the code moved and nobody updated the doc", which
#   is the failure this whole mechanism exists to prevent. An instance with no
#   external source reports external-CDI null and may not claim BONE-2.
#
#   UNABSORBED SOURCES are changed sources that no unit cites. A newly landed
#   decision record that nothing has absorbed is the highest-value decay signal
#   in the whole mechanism and is counted separately - it can never raise CDI,
#   because by definition no unit points at it.
#
#   A UNIT NEVER DECAYS ITSELF. A block's own file is excluded from its source
#   set, so a self-citation anchors the block and creates no edge (D-C.4).
#
# ---------------------------------------------------------------------------
# HOW "CHANGED" IS DETERMINED. ONE METHOD.
#
#   content-hash    The baseline file (default metrics/curation-baseline.tsv,
#                   written by `cdi.sh --seal` at the end of a curation) holds
#                   one `<digest>\t<source-id>` row per watched source. A source
#                   is changed if its digest differs (modified), if it is absent
#                   from the baseline (new), or if a baseline row now has no file
#                   (deleted). It is immune to clone, checkout, touch, rsync and
#                   edit-then-revert, all of which move mtime without changing
#                   content.
#
#   There is no second method. An mtime fallback existed here and is DELETED, not
#   demoted (B-139, D-C.5): it was the only code path that could print a healthy
#   0.0000 on a base that had never been measured, and because a scaffold always
#   ships a CURATION.md the path was not an edge case, it was what every new BONE
#   hit on its first run.
#
#   UNINITIALISED is a state, not a number. When the baseline is unsealed, or
#   when no block is anchored, the reading carries `"cdi": null` and
#   `"state": "uninitialised"`. Nothing downstream may print a numeral for it.
#
# ---------------------------------------------------------------------------
# EXIT CODES
#   0  a reading was produced (including an uninitialised reading)
#   0  --seal succeeded
#   2  bad usage
#   Never any other code. This script is called from a SessionStart hook path;
#   it must not be able to fail a session.
#
# DEPENDENCIES: POSIX sh, awk, sed, grep, find, sort, and one digest tool.
#   yq and jq are OPTIONAL and never required.
#
# PRIVACY: stdout carries repo-relative paths, digests, counts and ratios only.
#   No file content is ever read into the output.
# ---------------------------------------------------------------------------

set -u
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail || true

BONE_SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export BONE_SCRIPT_DIR

# shellcheck source=bone-lib.sh
if [ -r "$BONE_SCRIPT_DIR/bone-lib.sh" ]; then
    . "$BONE_SCRIPT_DIR/bone-lib.sh"
else
    echo "cdi.sh: bone-lib.sh not found next to this script; cannot run." >&2
    exit 2
fi

usage() {
    cat <<'EOF'
cdi.sh - compute the BONE Context Decay Index.

USAGE
  cdi.sh [--json|--pretty|--kv|--summary] [--root DIR]
  cdi.sh --seal [--root DIR]
  cdi.sh --append [FILE]
  cdi.sh --blocks [--root DIR]
  cdi.sh --help

OUTPUT MODES
  --json      one-line JSON (default). Directly appendable to metrics/cdi.jsonl.
  --pretty    the same object, one field per line, for reading.
  --kv        key=value lines, for shell consumers (decay-check.sh uses this).
  --summary   short human report.

ACTIONS
  --seal      Re-hash every watched provenance source and rewrite the baseline
              (default metrics/curation-baseline.tsv). THIS IS THE CURATION
              CLOCK RESET: run it as the last step of an applied curation, never
              to silence a warning. Prints the post-seal reading on stdout.
  --append F  Compute a reading and append it to F (default metrics/cdi.jsonl).
              Skipped if the last line of F already carries an identical
              fingerprint (same day, same state, same cdi, same changed set).
  --blocks    List every candidate block as
              <file>:<line> <TAB> anchored|orphan <TAB> <sources>. This is the
              audit trail for units_total and units_anchored; a coverage figure
              nobody can enumerate is a figure nobody can check.

OPTIONS
  --root DIR  Repo root. Defaults to $CLAUDE_PROJECT_DIR, else an upward walk
              from this script, else $PWD.

ENVIRONMENT
  BONE_ROOT, BONE_MANIFEST, BONE_BASELINE, BONE_PROJECT, BONE_CURATOR_SKILL
EOF
}

MODE="json"
ACTION="read"
APPEND_FILE=""
ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    MODE="json" ;;
        --pretty)  MODE="pretty" ;;
        --kv)      MODE="kv" ;;
        --summary) MODE="summary" ;;
        --seal)    ACTION="seal" ;;
        --blocks)  ACTION="blocks" ;;
        --append)
            ACTION="append"
            if [ $# -gt 1 ]; then
                case "$2" in -*) : ;; *) APPEND_FILE="$2"; shift ;; esac
            fi
            ;;
        --root)
            [ $# -gt 1 ] || { echo "cdi.sh: --root needs a directory" >&2; exit 2; }
            ROOT_ARG="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "cdi.sh: unknown argument '$1' (try --help)" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$ROOT_ARG" ] && BONE_ROOT="$ROOT_ARG"
ROOT=$(bone_root)
bone_hash_init
bone_alias_init "$ROOT"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/bone-cdi.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

# ---------------------------------------------------------------------------
# 1. Enumerate CANDIDATE BLOCKS and build the provenance edge list.
#
#    Two passes over the corpus, deliberately:
#      pass A  scan every unit FILE into blocks and raw tokens (awk, one process
#              per file), recording which block each token sits in;
#      pass B  resolve each DISTINCT token exactly once.
#    Resolution touches the filesystem, so resolving per occurrence would run it
#    several hundred times for a corpus with a couple of hundred distinct tokens.
# ---------------------------------------------------------------------------
bone_units "$ROOT" > "$TMP/unitfiles.txt" 2>/dev/null
[ -f "$TMP/unitfiles.txt" ] || : > "$TMP/unitfiles.txt"

# ONE block index, built by the library, shared with provenance-lint.sh. Two
# tools computing coverage two ways over one corpus is how a corpus ends up with
# two coverage figures and no way to tell which is the metric.
bone_block_index "$ROOT" "$TMP/unitfiles.txt" "$TMP"

cut -f2 "$TMP/edges.tsv" 2>/dev/null | sed '/^$/d' | sort -u > "$TMP/cited.txt"

# ---------------------------------------------------------------------------
# 2. Watched source set = declared (manifest or fallback) UNION cited.
# ---------------------------------------------------------------------------
bone_sources "$ROOT" > "$TMP/declared.txt" 2>/dev/null
cat "$TMP/declared.txt" "$TMP/cited.txt" 2>/dev/null | sed '/^$/d' | sort -u > "$TMP/sources.txt"

# ---------------------------------------------------------------------------
# 3. Current digests for every watched source, and the W_int / W_ext / W_unavail
#    partition of decision D-D.2.
# ---------------------------------------------------------------------------
: > "$TMP/cur.tsv"
: > "$TMP/unavailable.txt"
: > "$TMP/w_int.txt"
: > "$TMP/w_ext.txt"
while IFS= read -r s; do
    [ -n "$s" ] || continue
    case "$(bone_source_kind "$s")" in
        internal)
            printf '%s\n' "$s" >> "$TMP/w_int.txt" ;;
        external)
            printf '%s\n' "$s" >> "$TMP/w_ext.txt" ;;
        *)
            printf '%s\n' "$s" >> "$TMP/unavailable.txt" ;;
    esac
    # Read the source AS THE BONE CITES IT (at repos[].pinned_at for an external
    # source), never as it happens to be checked out. See bone_source_hash.
    h=$(bone_source_hash "$ROOT" "$s")
    printf '%s\t%s\n' "$h" "$s" >> "$TMP/cur.tsv"
done < "$TMP/sources.txt"

BASELINE_PATH="$BONE_BASELINE"
BASELINE_ABS="$ROOT/$BASELINE_PATH"

# ---------------------------------------------------------------------------
# 4. --seal writes the baseline and then falls through to a normal reading.
# ---------------------------------------------------------------------------
if [ "$ACTION" = "seal" ]; then
    mkdir -p "$(dirname "$BASELINE_ABS")" 2>/dev/null || :
    {
        printf '# bone.curation-baseline/1\tsealed_at=%s\talgo=%s\tsources=%s\n' \
            "$(bone_now_utc)" "$BONE_HASH_ALGO" "$(wc -l < "$TMP/sources.txt" | tr -d ' ')"
        printf '# Machine-written by cdi.sh --seal. This is the decay clock, not a metric.\n'
        printf '# Reset it only as the final step of an APPLIED curation.\n'
        cat "$TMP/cur.tsv"
    } > "$BASELINE_ABS" 2>/dev/null || {
        echo "cdi.sh: could not write $BASELINE_PATH" >&2
        exit 2
    }
    echo "cdi.sh: baseline sealed at $BASELINE_PATH ($(grep -cv '^#' "$BASELINE_ABS" 2>/dev/null || echo 0) sources, $BONE_HASH_ALGO)" >&2
fi

# ---------------------------------------------------------------------------
# 5. Determine the changed set. ONE method: content hash against the baseline.
#    No baseline means no comparison happened, which is a STATE, not a zero.
# ---------------------------------------------------------------------------
: > "$TMP/changed.tsv"    # source-id \t new|modified|deleted
METHOD="content-hash"
BASELINE_SEALED=""
NOTE=""

if [ -r "$BASELINE_ABS" ] && grep -qv '^#' "$BASELINE_ABS" 2>/dev/null; then
    BASELINE_SEALED=$(sed -n 's/^#.*sealed_at=\([^ 	]*\).*/\1/p' "$BASELINE_ABS" | head -n 1)
    grep -v '^#' "$BASELINE_ABS" > "$TMP/base.tsv" 2>/dev/null || : > "$TMP/base.tsv"
    # An UNAVAILABLE source (an external repo that is not checked out here) is
    # excluded from the comparison on both sides. It can neither fabricate decay
    # nor hide it; it is counted separately as sources_unavailable.
    awk -F'\t' '
        NR == FNR { b[$2] = $1; next }
        {
            seen[$2] = 1
            if ($1 == "UNAVAILABLE")      next
            if (!($2 in b))               { print $2 "\tnew";      next }
            if (b[$2] == "UNAVAILABLE")   next
            if (b[$2] != $1)              { print $2 "\tmodified"; next }
        }
        END { for (p in b) if (!(p in seen) && b[p] != "UNAVAILABLE") print p "\tdeleted" }
    ' "$TMP/base.tsv" "$TMP/cur.tsv" | sort > "$TMP/changed.tsv"
else
    NOTE="no curation baseline at $BASELINE_PATH; decay is undefined until the first curation is sealed with cdi.sh --seal."
fi

cut -f1 "$TMP/changed.tsv" 2>/dev/null | sort -u > "$TMP/changed_paths.txt"

# ---------------------------------------------------------------------------
# 6. Propagate change through the edge list, internally and externally.
#
#    decayed_int(u) <=> some s in src(u) INTERSECT W_int                is changed
#    decayed_ext(u) <=> some s in src(u) INTERSECT (W_ext MINUS unavail) is changed
#
#    A block citing both an ADR and a code file is counted in both sub-indices.
#    They are two views of U, not a partition of it.
# ---------------------------------------------------------------------------
# One tagged stream rather than three file arguments: `NR == FNR` silently
# misreads an EMPTY first file as the second one, and both the unavailable set
# and the changed set are empty on a healthy day, which is the common case.
{
    awk '{ print "X\t" $0 }' "$TMP/unavailable.txt"
    awk '{ print "C\t" $0 }' "$TMP/changed_paths.txt"
    awk '{ print "E\t" $0 }' "$TMP/uedges.tsv"
} > "$TMP/tagged.tsv" 2>/dev/null || :

: > "$TMP/decayed.tsv"            # block-id \t src1,src2
: > "$TMP/decayed_units.txt"
awk -F'\t' -v uintf="$TMP/u_int.txt" -v uextf="$TMP/u_ext.txt" \
           -v dintf="$TMP/decayed_int.txt" -v dextf="$TMP/decayed_ext.txt" '
    $1 == "X" { unavail[$2] = 1; next }
    $1 == "C" { chg[$2] = 1; next }
    $1 == "E" {
        b = $2; s = $3
        isext = (index(s, ":") > 0)
        if (isext && (s in unavail)) next          # excluded from both sides
        if (isext) print b > uextf; else print b > uintf
        if (s in chg) {
            via[b] = (b in via) ? via[b] "," s : s
            if (isext) print b > dextf; else print b > dintf
        }
    }
    END { for (b in via) print b "\t" via[b] }
' "$TMP/tagged.tsv" 2>/dev/null | sort > "$TMP/decayed.tsv"

# M9 STALE-CITATION COUNT: individual (block, source) edges whose source moved.
# Distinct from units_decayed, which counts BLOCKS: one block citing four changed
# files is one decayed unit and four stale citations, and B-151 requires both.
awk -F'\t' '{ n += split($2, a, ",") } END { print n + 0 }' "$TMP/decayed.tsv" \
    > "$TMP/stale_citations.txt" 2>/dev/null || echo 0 > "$TMP/stale_citations.txt"

for f in u_int u_ext decayed_int decayed_ext; do
    [ -f "$TMP/$f.txt" ] || : > "$TMP/$f.txt"
    sort -u "$TMP/$f.txt" -o "$TMP/$f.txt" 2>/dev/null || :
done
cut -f1 "$TMP/decayed.tsv" 2>/dev/null | sort -u > "$TMP/decayed_units.txt"

# Changed sources that no unit cites: landed but unabsorbed.
if [ -s "$TMP/changed_paths.txt" ]; then
    awk 'NR == FNR { c[$0] = 1; next } { delete c[$0] } END { for (p in c) print p }' \
        "$TMP/changed_paths.txt" "$TMP/cited.txt" | sort > "$TMP/unabsorbed.txt"
else
    : > "$TMP/unabsorbed.txt"
fi

# Declared sources that resolve to a real location but are not there: a manifest
# defect worth surfacing. Sources that are merely UNAVAILABLE (no local working
# copy for that alias) are NOT reported here; they are counted separately.
: > "$TMP/missing_declared.txt"
while IFS= read -r s; do
    [ -n "$s" ] || continue
    abs=$(bone_source_abs "$ROOT" "$s")
    [ -n "$abs" ] || continue
    [ -e "$abs" ] || printf '%s\n' "$s" >> "$TMP/missing_declared.txt"
done < "$TMP/declared.txt"

count() { [ -s "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

UNIT_FILES=$(count "$TMP/unitfiles.txt")
BLOCKS_SCANNED=$(count "$TMP/blocks.tsv")
UNITS_TOTAL=$(count "$TMP/candidates.txt")
UNITS_ANCHORED=$(count "$TMP/U.txt")
UNITS_DECAYED=$(count "$TMP/decayed_units.txt")
U_INT=$(count "$TMP/u_int.txt")
U_EXT=$(count "$TMP/u_ext.txt")
D_INT=$(count "$TMP/decayed_int.txt")
D_EXT=$(count "$TMP/decayed_ext.txt")
SOURCES_TOTAL=$(count "$TMP/sources.txt")
SOURCES_DECLARED=$(count "$TMP/declared.txt")
SOURCES_INTERNAL=$(count "$TMP/w_int.txt")
SOURCES_EXTERNAL=$(count "$TMP/w_ext.txt")
SOURCES_CHANGED=$(count "$TMP/changed_paths.txt")
SOURCES_UNABSORBED=$(count "$TMP/unabsorbed.txt")
SOURCES_UNAVAILABLE=$(count "$TMP/unavailable.txt")
UNRESOLVED_CITES=$(count "$TMP/unresolved.tsv")
STALE_CITATIONS=$(cat "$TMP/stale_citations.txt" 2>/dev/null || echo 0)
IMPERATIVE_LIST=$( [ -n "$(bone_imperative_list)" ] && printf 'present' || printf 'absent' )

# THE UNINITIALISED STATE (D-C.5). There are exactly two ways for this reading to
# carry no index, and both are states rather than numbers:
#   the baseline was never sealed  -> there is no h_base(s) to compare against;
#   no candidate block is anchored -> U is empty, so the ratio has no denominator.
# Emitting 0.0000 for either is what put a fabricated healthy point at the start
# of every metric series in the implementation this replaces. It is never done
# here, and decay-check.sh is forbidden from printing a numeral in this state.
STATE="measured"
if [ -z "$BASELINE_SEALED" ]; then
    STATE="uninitialised"
elif [ "$UNITS_ANCHORED" -eq 0 ]; then
    STATE="uninitialised"
    NOTE="baseline is sealed, but no candidate block carries a resolvable provenance token, so U is empty and the index has no denominator."
fi

if [ "$STATE" = "uninitialised" ]; then
    CDI="null"; CDI_INT="null"; CDI_EXT="null"
else
    CDI=$(bone_pct "$UNITS_DECAYED" "$UNITS_ANCHORED")
    CDI_INT=$(bone_pct "$D_INT" "$U_INT")
    CDI_EXT=$(bone_pct "$D_EXT" "$U_EXT")
fi
COVERAGE=$(bone_pct "$UNITS_ANCHORED" "$UNITS_TOTAL")
ORPHAN_RATE=$(bone_pct "$((UNITS_TOTAL - UNITS_ANCHORED))" "$UNITS_TOTAL")
CHURN=$(bone_pct "$SOURCES_CHANGED" "$SOURCES_TOTAL")

GENERATED_AT=$(bone_now_utc)
DAY=$(bone_today)

# Display name: .claude/skills/<name>/SKILL.md:LINE -> <name>:LINE
disp() {
    case "$1" in
        .claude/skills/*)
            _d=${1#.claude/skills/}
            case "$_d" in
                */SKILL.md:*) printf '%s:%s' "${_d%%/SKILL.md:*}" "${_d##*:}" ;;
                *)            printf '%s' "$_d" ;;
            esac ;;
        *) printf '%s' "$1" ;;
    esac
}

# ---------------------------------------------------------------------------
# 7. Emit.
# ---------------------------------------------------------------------------
emit_json() {
    {
        printf '{'
        printf '"schema":"bone.cdi/2",'
        printf '"metric":"M1",'
        printf '"unit_granularity":"block",'
        printf '"generated_at":"%s",' "$GENERATED_AT"
        printf '"project":"%s",' "$(bone_json_escape "$BONE_PROJECT")"
        printf '"state":"%s",' "$STATE"
        printf '"method":"%s",' "$METHOD"
        printf '"hash_algo":"%s",' "$BONE_HASH_ALGO"
        printf '"imperative_list":"%s",' "$IMPERATIVE_LIST"
        printf '"baseline":{"path":"%s","sealed_at":%s},' \
            "$(bone_json_escape "$BASELINE_PATH")" \
            "$( [ -n "$BASELINE_SEALED" ] && printf '"%s"' "$BASELINE_SEALED" || printf 'null' )"
        printf '"cdi":%s,' "$CDI"
        printf '"internal_cdi":%s,' "$CDI_INT"
        printf '"external_cdi":%s,' "$CDI_EXT"
        printf '"coverage":%s,' "$COVERAGE"
        printf '"orphan_rate":%s,' "$ORPHAN_RATE"
        printf '"source_churn":%s,' "$CHURN"
        printf '"units_total":%s,' "$UNITS_TOTAL"
        printf '"units_anchored":%s,' "$UNITS_ANCHORED"
        printf '"units_decayed":%s,' "$UNITS_DECAYED"
        printf '"units_internal":%s,' "$U_INT"
        printf '"units_external":%s,' "$U_EXT"
        printf '"units_decayed_internal":%s,' "$D_INT"
        printf '"units_decayed_external":%s,' "$D_EXT"
        printf '"unit_files":%s,' "$UNIT_FILES"
        printf '"blocks_scanned":%s,' "$BLOCKS_SCANNED"
        printf '"sources_total":%s,' "$SOURCES_TOTAL"
        printf '"sources_declared":%s,' "$SOURCES_DECLARED"
        printf '"sources_internal":%s,' "$SOURCES_INTERNAL"
        printf '"sources_external":%s,' "$SOURCES_EXTERNAL"
        printf '"sources_changed":%s,' "$SOURCES_CHANGED"
        printf '"sources_unabsorbed":%s,' "$SOURCES_UNABSORBED"
        printf '"sources_unavailable":%s,' "$SOURCES_UNAVAILABLE"
        printf '"unresolved_tokens":%s,' "$UNRESOLVED_CITES"
        printf '"stale_citations":%s,' "$STALE_CITATIONS"
        printf '"changed_sources":'
        awk -F'\t' '
            function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
            { printf "%s{\"path\":\"%s\",\"change\":\"%s\"}", (NR > 1 ? "," : "["), esc($1), esc($2) }
            END { if (NR == 0) printf "["; printf "]" }
        ' "$TMP/changed.tsv"
        printf ','
        printf '"decayed_units":'
        awk -F'\t' '
            function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
            {
                printf "%s{\"unit\":\"%s\",\"via\":[", (NR > 1 ? "," : "["), esc($1)
                n = split($2, a, ",")
                for (i = 1; i <= n; i++) printf "%s\"%s\"", (i > 1 ? "," : ""), esc(a[i])
                printf "]}"
            }
            END { if (NR == 0) printf "["; printf "]" }
        ' "$TMP/decayed.tsv"
        printf ','
        printf '"unabsorbed_sources":'; bone_json_array_file "$TMP/unabsorbed.txt"
        printf ','
        printf '"missing_declared_sources":'; bone_json_array_file "$TMP/missing_declared.txt"
        printf ','
        printf '"note":%s' "$( [ -n "$NOTE" ] && printf '"%s"' "$(bone_json_escape "$NOTE")" || printf 'null' )"
        printf '}'
    }
}

emit_kv() {
    echo "state=$STATE"
    echo "method=$METHOD"
    echo "unit_granularity=block"
    echo "cdi=$CDI"
    echo "internal_cdi=$CDI_INT"
    echo "external_cdi=$CDI_EXT"
    echo "coverage=$COVERAGE"
    echo "orphan_rate=$ORPHAN_RATE"
    echo "units_total=$UNITS_TOTAL"
    echo "units_anchored=$UNITS_ANCHORED"
    echo "units_decayed=$UNITS_DECAYED"
    echo "units_internal=$U_INT"
    echo "units_external=$U_EXT"
    echo "units_decayed_internal=$D_INT"
    echo "units_decayed_external=$D_EXT"
    echo "unit_files=$UNIT_FILES"
    echo "sources_total=$SOURCES_TOTAL"
    echo "sources_external=$SOURCES_EXTERNAL"
    echo "sources_changed=$SOURCES_CHANGED"
    echo "sources_unabsorbed=$SOURCES_UNABSORBED"
    echo "sources_unavailable=$SOURCES_UNAVAILABLE"
    echo "unresolved_tokens=$UNRESOLVED_CITES"
    echo "stale_citations=$STALE_CITATIONS"
    echo "baseline_sealed_at=${BASELINE_SEALED:-}"
    echo "note=${NOTE}"
    printf 'changed_top='
    cut -f1 "$TMP/changed.tsv" 2>/dev/null | head -n 6 | tr '\n' ',' | sed 's/,$//'
    echo
    printf 'decayed_top='
    head -n 6 "$TMP/decayed_units.txt" 2>/dev/null | while IFS= read -r u; do
        [ -n "$u" ] && printf '%s,' "$(disp "$u")"
    done | sed 's/,$//'
    echo
    printf 'unabsorbed_top='
    head -n 6 "$TMP/unabsorbed.txt" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
    echo
}

emit_summary() {
    echo "BONE Context Decay Index - $BONE_PROJECT"
    echo "  generated   $GENERATED_AT"
    echo "  state       $STATE  (method $METHOD, $BONE_HASH_ALGO, granularity block)"
    echo "  CDI         $CDI   (decayed $UNITS_DECAYED / anchored $UNITS_ANCHORED)"
    echo "    internal  $CDI_INT   ($D_INT / $U_INT blocks citing an internal source)"
    echo "    external  $CDI_EXT   ($D_EXT / $U_EXT blocks citing a product-repo source)"
    echo "  coverage    $COVERAGE  (anchored $UNITS_ANCHORED / candidate blocks $UNITS_TOTAL)"
    echo "  orphan rate $ORPHAN_RATE  (candidate blocks with no resolvable token)"
    echo "  corpus      $UNIT_FILES unit files, $BLOCKS_SCANNED blocks scanned, $UNITS_TOTAL candidates"
    echo "  sources     $SOURCES_TOTAL watched ($SOURCES_EXTERNAL external), $SOURCES_CHANGED changed, $SOURCES_UNABSORBED unabsorbed, $SOURCES_UNAVAILABLE unavailable"
    [ -n "$NOTE" ] && echo "  note        $NOTE"
    if [ "$U_EXT" -eq 0 ] 2>/dev/null; then
        echo "  WARNING     no anchored block cites a source outside this repository, so"
        echo "              external-CDI is null and this instance cannot detect the failure"
        echo "              it exists to detect. Declare product paths in MANIFEST.yaml watched."
    fi
    if [ -s "$TMP/changed.tsv" ]; then
        echo "  changed sources:"
        while IFS="$(printf '\t')" read -r p k; do echo "    [$k] $p"; done < "$TMP/changed.tsv"
    fi
    if [ -s "$TMP/decayed.tsv" ]; then
        echo "  decayed blocks:"
        while IFS="$(printf '\t')" read -r u v; do echo "    $(disp "$u")  <- $v"; done < "$TMP/decayed.tsv"
    fi
    if [ -s "$TMP/unabsorbed.txt" ]; then
        echo "  unabsorbed (changed, cited by no unit):"
        sed 's/^/    /' "$TMP/unabsorbed.txt"
    fi
    if [ -s "$TMP/missing_declared.txt" ]; then
        echo "  declared but missing on disk:"
        sed 's/^/    /' "$TMP/missing_declared.txt"
    fi
    return 0
}

case "$ACTION" in
    blocks)
        # The audit trail for units_total and units_anchored. A coverage figure
        # nobody can enumerate is a figure nobody can check, and this index has
        # already been published once at a granularity its own spec did not use.
        awk -F'\t' -v uf="$TMP/U.txt" -v ef="$TMP/uedges.tsv" '
            BEGIN {
                while ((getline l < uf) > 0) anch[l] = 1
                close(uf)
                while ((getline l < ef) > 0) {
                    split(l, a, "\t")
                    via[a[1]] = (a[1] in via) ? via[a[1]] "," a[2] : a[2]
                }
                close(ef)
            }
            $2 == "1" {
                printf "%s\t%s\t%s\n", $1, (($1 in anch) ? "anchored" : "orphan"),
                       (($1 in via) ? via[$1] : "-")
            }
        ' "$TMP/blocks.tsv" | sort
        ;;
    append)
        [ -n "$APPEND_FILE" ] || APPEND_FILE="$ROOT/metrics/cdi.jsonl"
        case "$APPEND_FILE" in /*) : ;; *) APPEND_FILE="$ROOT/$APPEND_FILE" ;; esac
        mkdir -p "$(dirname "$APPEND_FILE")" 2>/dev/null || :
        LINE=$(emit_json)
        # A repeat is the WHOLE reading repeated on the same day, not five of its
        # fields: bone_reading_is_repeat says why, and selftest.sh section 6 holds
        # the case the five-field key dropped.
        PREVLINE=""
        [ -s "$APPEND_FILE" ] && PREVLINE=$(tail -n 1 "$APPEND_FILE" 2>/dev/null)
        if bone_reading_is_repeat "$PREVLINE" "$LINE" "$DAY"; then
            echo "cdi.sh: identical reading already recorded today; not appended." >&2
        else
            printf '%s\n' "$LINE" >> "$APPEND_FILE"
        fi
        printf '%s\n' "$LINE"
        ;;
    *)
        case "$MODE" in
            json)    emit_json; echo ;;
            pretty)  emit_json | awk '{ gsub(/,"/, ",\n  \""); sub(/^\{/, "{\n  "); sub(/\}$/, "\n}"); print }' ;;
            kv)      emit_kv ;;
            summary) emit_summary ;;
        esac
        ;;
esac

exit 0
