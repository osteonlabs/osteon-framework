#!/bin/sh
# provenance-lint.sh - report claims that do not chain to a source.
# BONE template version: 0.1.0
#
# ---------------------------------------------------------------------------
# WHAT THIS ENFORCES
#
#   BONE mechanism 4: every claim in a knowledge unit traces to a decision
#   record, a dated live-state record, or a file in a named repository. A claim
#   without provenance is an orphan fact.
#
#   This script is REPORT-ONLY. It never writes to, moves, or reformats any file
#   it scans. Its only side effects are stdout and stderr.
#
# ---------------------------------------------------------------------------
# THE DETECTION HEURISTIC, STATED HONESTLY
#
#   Six checks, ordered by precision. The report repeats these precision claims
#   so that nobody reads a count as a count of facts.
#
#   P1  UNRESOLVED-SRC        (precision ~1.00 within its scope)
#       A `[src: ...]` token that resolves to nothing: not a decision record in
#       docs/adr/, not a path in this repo, and not `<alias>:<path>` for an
#       alias declared in MANIFEST.yaml `repos[]`. Mechanical.
#
#   P1b UNQUALIFIED-PATH      (precision ~1.00)
#       A token that looks like a file path, is not in this repository, and
#       names no repository alias: `src/loans.py:9-23`. Under the grammar this
#       is ambiguous rather than absent - more than one code repo can contain a
#       `src/` directory - so it is separated from P1 because it has its own
#       one-word remediation: add the repo alias.
#
#   P2  DEAD-EXTERNAL-REF     (precision ~1.00, only where the repo is present)
#       A code-ref whose alias IS declared, whose working copy IS on this
#       machine, and whose file is NOT there - neither in the working tree NOR at
#       the repository's effective commit-ish. This is the check that catches the
#       knowledge base drifting off the code: the cited file was renamed or
#       deleted. Skipped silently when the working copy is absent - an
#       unverifiable citation is never reported as a broken one.
#
#       THE EFFECTIVE COMMIT-ISH (B-98a, D-E.2). A code-ref may carry `@pin`; if
#       it does not, it resolves against `repos[].pinned_at`, declared ONCE per
#       repository rather than once per token. A file that is absent from the
#       working tree but present at the pin is a correct citation of a pinned
#       state, not a dangling link, so it is not reported. Pinning per token
#       would put one fact in hundreds of places; pinning per repository puts it
#       in one, and advancing the pin becomes the visible, approvable act of
#       re-verifying every code claim at once.
#
#   P3  UNANCHORED-BLOCK      (precision ~1.00, informational)
#       A CANDIDATE BLOCK - a paragraph, list item or table row holding a
#       declarative sentence, not in imperative mood - carrying no provenance
#       token of any accepted form. This is the orphan set of EVALUATION M7 and
#       its denominator is `units_total`, both at block granularity, both shared
#       with cdi.sh through `bone_block_index`. A pure procedure step is not a
#       candidate and is never counted here.
#
#   P4  DESC-MUTABLE-FACT     (precision ~0.80)
#       A frontmatter `description:` carrying a fact that can change: a version,
#       an ADR number, or decision-state language. Descriptions are always
#       loaded, are never swept by curation passes that read bodies, and so
#       drift unnoticed (a description can name one technology while its own
#       body cites the ADR that chose another). Narrow marker list, so misfires
#       are rare and worth a glance.
#
#   P5  ORPHAN-CLAIM          (precision ~0.60, the only judgement-bearing check)
#       A bullet using DECISION or LIVE-STATE language, carrying no provenance
#       token, in a section that is not source-anchored. Suppressions that hold
#       the false-positive rate down:
#         - bullets only (prose, headings, tables and code are never flagged)
#         - fenced code blocks and YAML frontmatter skipped entirely
#         - checklist items `- [ ]` skipped (procedure, not claim)
#         - lines under 40 characters skipped (labels, not claims)
#         - these headings skipped wholesale: References, Chains with, Commands,
#           Output, When to use, When to run, Template, Examples
#         - a section whose FIRST non-empty line is a standalone `[src: ...]`
#           line is section-anchored and none of its bullets are flagged. That
#           is the escape hatch for a dense section with one shared source.
#
#   P6  STATE-NO-VERIFIED-AT  (precision ~1.00)
#       A record under docs/state/ with no `verified_at:` (or `verified:`)
#       field. A state record without a verification date cannot anchor
#       anything, because provenance to an undated fact is provenance to
#       nothing. Index files (README.md) are exempt.
#
#   P7  LEGACY-SPELLING      (precision ~1.00, NON-BLOCKING by design)
#       An external token written in the bare form `<alias>:<path>` rather than
#       the normative `repo/<alias>:<path>`. It resolves either way and nothing
#       is broken, so it never fails --strict; it is reported so that a corpus
#       migrating to the normative spelling can see how far it has to go, rather
#       than absorbing the drift silently. Normalising a spelling is a curation
#       task, not a lint failure.
#
#   P8  VOLATILE-DETAIL       (precision ~0.35, counted but not listed)
#       A bullet carrying a version, a hostname, a port or an env-var name with
#       no provenance. Listed only with --all, because it is the noisiest signal
#       here and a lint that cries wolf gets turned off.
#
#       NOTE ON THE NUMBER. VOLATILE-DETAIL was P7 before LEGACY-SPELLING
#       existed. It moved to P8 rather than sharing an identifier, because two
#       checks under one id is precisely the kind of collision a governed
#       knowledge base exists to remove. The JSON field names are descriptive, not
#       positional, so no consumer depends on the digit.
#
# ---------------------------------------------------------------------------
# PLACEHOLDERS ARE NOT FINDINGS
#   `[src: <repo-alias>:<path>]` appears inside the constitution and inside the
#   hub skill, as documentation of the grammar itself. Any token containing
#   `<`, `>` or `...` is discarded before resolution. Without that rule this
#   linter reports its own specification as a defect - which is precisely how a
#   linter earns being ignored.
#
# ---------------------------------------------------------------------------
# WHAT THIS CANNOT CATCH (say it, or the lint gets trusted more than it earns)
#   - A claim that is WRONG but properly cited. Provenance is not truth.
#   - A citation to a real source that does not support the claim
#     (over-citation). Over-citation is common in practice, and only a human
#     evidence audit finds it.
#   - A claim written as flowing prose rather than a bullet. P5 is bullet-only,
#     deliberately: prose scanning is where a lint starts crying wolf.
#   - A claim in a table cell.
#   - A cited file that still exists but whose CONTENT moved under the claim.
#     That is cdi.sh's job, not this script's.
#   - A `<alias>:<path>` citation whose working copy is not on this machine.
#   - Anything outside the knowledge-unit set and docs/.
#
# ---------------------------------------------------------------------------
# SCOPE
#   Knowledge units (MANIFEST `knowledge_units`, default .claude/skills/**/*.md):
#     P1 P1b P2 P3 P4 P5 P7 P8.
#   docs/**/*.md: P1 P1b P2 P7, and P6 for docs/state/.
#   Decision records, contracts and domain documents are provenance SOURCES;
#   they are not required to cite anything, so P5 never applies to them.
#
# EXIT CODES
#   0  report produced (with or without findings) - the default, this is advisory
#   2  bad usage
#   3  --strict AND at least one P1 / P1b / P2 / P4 / P6 finding
#      (P3, P5, P7 and P8 never fail --strict: a coverage figure, a spelling
#      migration and two heuristics must not be able to block a merge)
#
# DEPENDENCIES: POSIX sh, awk, sed, grep, find. jq/yq optional, unused.
# PRIVACY: prints paths, line numbers and a 100-character excerpt of a flagged
#   line. Excerpts come from knowledge units, which by BONE rule hold no secret
#   values; --no-excerpt suppresses them entirely.
# ---------------------------------------------------------------------------

set -u
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail || true

BONE_SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export BONE_SCRIPT_DIR

if [ -r "$BONE_SCRIPT_DIR/bone-lib.sh" ]; then
    # shellcheck source=bone-lib.sh
    . "$BONE_SCRIPT_DIR/bone-lib.sh"
else
    echo "provenance-lint.sh: bone-lib.sh not found next to this script." >&2
    exit 2
fi

usage() {
    cat <<'EOF'
provenance-lint.sh - report claims that do not chain to a source. Report-only.

USAGE
  provenance-lint.sh [--root DIR] [--all] [--strict] [--json] [--no-excerpt] [--limit N]
  provenance-lint.sh --help

OPTIONS
  --root DIR     repo root (default: $CLAUDE_PROJECT_DIR, else upward walk, else PWD)
  --all          also list P3 UNANCHORED-BLOCK and P8 VOLATILE-DETAIL in full
  --strict       exit 3 if any P1 / P1b / P2 / P4 / P6 finding exists (for CI)
  --json         one-line JSON summary instead of the text report
                 (schema bone.provenance-lint/1, appendable to metrics/)
  --no-excerpt   never print line content, only path:line
  --limit N      list at most N findings per file per check (default 5, 0 = all).
                 A wall of findings is read as noise, so the tail is summarised.

EXIT
  0 report produced   2 bad usage   3 --strict with P1/P1b/P2/P4/P6 findings
EOF
}

ROOT_ARG=""; SHOW_ALL=0; STRICT=0; JSON=0; EXCERPT=1; LIMIT=5
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -gt 1 ] || { echo "provenance-lint.sh: --root needs a directory" >&2; exit 2; }
                ROOT_ARG="$2"; shift ;;
        --all) SHOW_ALL=1 ;;
        --strict) STRICT=1 ;;
        --json) JSON=1 ;;
        --no-excerpt) EXCERPT=0 ;;
        --limit) [ $# -gt 1 ] || { echo "provenance-lint.sh: --limit needs a number" >&2; exit 2; }
                 LIMIT="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "provenance-lint.sh: unknown argument '$1' (try --help)" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$ROOT_ARG" ] && BONE_ROOT="$ROOT_ARG"
ROOT=$(bone_root)
bone_alias_init "$ROOT"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/bone-lint.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
for f in p1 p1b p2 p3 p4 p5 p6 p7 p8 extu; do : > "$TMP/$f.txt"; done
: > "$TMP/alltok.txt"; : > "$TMP/restok.txt"

bone_units "$ROOT" > "$TMP/units.txt" 2>/dev/null
[ -f "$TMP/units.txt" ] || : > "$TMP/units.txt"
if [ -d "$ROOT/docs" ]; then
    find "$ROOT/docs" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r f; do
        bone_relpath "$f" "$ROOT"
    done > "$TMP/docs.txt"
else
    : > "$TMP/docs.txt"
fi

# ---------------------------------------------------------------------------
# Token checking, shared by both passes.
# Emits into p1 / p2 / extu. $1 = repo-relative file, $2 = 1 to record excerpts.
# ---------------------------------------------------------------------------
# resolves_at_pin <local-working-copy> <repo-relative-path> <commit-ish>
#   0 when the path exists in that repository at that commit. Read-only: `git
#   show` never writes and never touches the network. Returns 1 when there is no
#   pin, no git directory, or no such object, so an unpinned repository behaves
#   exactly as before this check existed.
resolves_at_pin() {
    [ -n "${3:-}" ] || return 1
    [ -d "$1/.git" ] || [ -f "$1/.git" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    git -C "$1" show "$3:$2" >/dev/null 2>&1
}

check_tokens() {
    _ct_file="$1"
    bone_extract_tokens "$ROOT/$_ct_file" > "$TMP/tok.txt" 2>/dev/null
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        _ct_res=$(bone_resolve_src "$ROOT" "$tok")
        src=${_ct_res#*	}
        # M13 PROVENANCE RESOLVABILITY is counted over DISTINCT tokens, so that a
        # token repeated forty times in one reference file does not outvote forty
        # single-use tokens elsewhere. A placeholder is grammar documentation, not
        # a citation, so it is in neither the numerator nor the denominator.
        case "${_ct_res%%	*}" in
            placeholder) : ;;
            internal|external|time)
                printf '%s\n' "$tok" >> "$TMP/alltok.txt"
                printf '%s\n' "$tok" >> "$TMP/restok.txt" ;;
            *)  printf '%s\n' "$tok" >> "$TMP/alltok.txt" ;;
        esac
        case "${_ct_res%%	*}" in
            internal|time|placeholder) continue ;;
            external)
                _ct_alias=${src%%:*}
                _ct_rest=${src#*:}
                _ct_local=$(bone_alias_local "$_ct_alias")
                # P7: the bare spelling resolves, and is still drift.
                case "$tok" in
                    repo/*) : ;;
                    *) _ct_ln=$(grep -n -F -- "$tok" "$ROOT/$_ct_file" 2>/dev/null | head -n 1 | cut -d: -f1)
                       printf '%s:%s\t%s\n' "$_ct_file" "${_ct_ln:-0}" "$tok" >> "$TMP/p7.txt" ;;
                esac
                # The effective commit-ish: the token's own @pin wins, else the
                # repository's declared pinned_at.
                _ct_pin=""
                case "$tok" in
                    *@*) _ct_pin=${tok##*@}; _ct_pin=$(printf '%s' "$_ct_pin" | sed -e 's/[^A-Za-z0-9._-].*$//') ;;
                esac
                [ -n "$_ct_pin" ] || _ct_pin=$(bone_alias_pin "$_ct_alias")
                if [ -z "$_ct_local" ] || [ ! -d "$_ct_local" ]; then
                    printf '%s\n' "$src" >> "$TMP/extu.txt"
                elif [ ! -e "${_ct_local%/}/$_ct_rest" ] \
                     && ! resolves_at_pin "${_ct_local%/}" "$_ct_rest" "$_ct_pin"; then
                    _ct_ln=$(grep -n -F -- "$tok" "$ROOT/$_ct_file" 2>/dev/null | head -n 1 | cut -d: -f1)
                    printf '%s:%s\t%s\n' "$_ct_file" "${_ct_ln:-0}" "$src" >> "$TMP/p2.txt"
                fi
                ;;
            unqualified)
                _ct_ln=$(grep -n -F -- "$tok" "$ROOT/$_ct_file" 2>/dev/null | head -n 1 | cut -d: -f1)
                printf '%s:%s\t%s\n' "$_ct_file" "${_ct_ln:-0}" "$tok" >> "$TMP/p1b.txt"
                ;;
            *)
                _ct_ln=$(grep -n -F -- "$tok" "$ROOT/$_ct_file" 2>/dev/null | head -n 1 | cut -d: -f1)
                printf '%s:%s\t%s\n' "$_ct_file" "${_ct_ln:-0}" "$tok" >> "$TMP/p1.txt"
                ;;
        esac
    done < "$TMP/tok.txt"
}

# ---------------------------------------------------------------------------
# The body scanner. One pass per file. Emits <line>\t<class>\t<text>.
# Regexes avoid interval quantifiers ({n}); BSD awk support for them is not
# dependable, so digit runs are written out.
# ---------------------------------------------------------------------------
scan_body() {
    awk '
        function has_prov(s) {
            return (s ~ /\[src:/) || (s ~ /\[verified:/) \
                || (s ~ /\(ADR-[0-9][0-9][0-9]/) \
                || (s ~ /\(verified [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)/) \
                || (s ~ /UNVERIFIED/)
        }
        function strong(s) {
            return s ~ /(decided|decision|superseded|deprecated|canonical|source of truth|forbidden|mandatory|MUST NOT|MUST|NEVER|ALWAYS|currently|as of |in production|rolled out|is enabled|is disabled|we use|we chose|standard is|default is|the default|is now |no longer)/
        }
        function weak(s) {
            return (s ~ /[vV]?[0-9]+\.[0-9]+/) \
                || (s ~ /[a-z0-9-]+\.[a-z0-9-]+\.[a-z][a-z]+/) \
                || (s ~ /:[0-9][0-9][0-9][0-9]/) \
                || (s ~ /[A-Z][A-Z0-9_][A-Z0-9_][A-Z0-9_][A-Z0-9_][A-Z0-9_]+/)
        }
        BEGIN { fm = 0; fence = 0; skipsec = 0; anchored = 0; awaiting = 0 }
        NR == 1 && $0 == "---" { fm = 1; next }
        fm == 1 {
            if ($0 == "---") { fm = 0; next }
            if ($0 ~ /^description:/) {
                if ($0 ~ /ADR-[0-9]/ || $0 ~ /[vV][0-9]+\.[0-9]+/ || $0 ~ /[0-9]+\.[0-9]+\.[0-9]+/ \
                    || $0 ~ /(decided|chosen|superseded|deprecated|currently|as of )/) {
                    print NR "\tDESC-MUTABLE-FACT\t" substr($0, 1, 160)
                }
            }
            next
        }
        /^[ \t]*```/ { fence = 1 - fence; next }
        fence == 1 { next }
        /^#+[ \t]/ {
            skipsec = ($0 ~ /^#+[ \t]*(References|Chains with|Commands|Output|When to use|When to run|Template|Examples|Example)/) ? 1 : 0
            anchored = 0; awaiting = 1
            next
        }
        {
            if (awaiting == 1) {
                if ($0 ~ /^[ \t]*$/) next
                awaiting = 0
                if ($0 ~ /^[ \t]*\[src:/) { anchored = 1; next }
            }
            if (skipsec == 1 || anchored == 1) next
            if ($0 !~ /^[ \t]*[-*][ \t]/) next
            if ($0 ~ /^[ \t]*[-*][ \t]*\[[ xX]\]/) next
            if (length($0) < 40) next
            if (has_prov($0)) next
            if (strong($0)) { print NR "\tORPHAN-CLAIM\t"    substr($0, 1, 160); next }
            if (weak($0))   { print NR "\tVOLATILE-DETAIL\t" substr($0, 1, 160); next }
        }
    ' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Pass 1: knowledge units.
# ---------------------------------------------------------------------------
# The block index is built ONCE, by the library, and is the same index cdi.sh
# reports from. Coverage here and coverage there are the same number by
# construction rather than by coincidence.
bone_block_index "$ROOT" "$TMP/units.txt" "$TMP/idx"
UNITS_TOTAL=$(  [ -s "$TMP/idx/candidates.txt" ] && wc -l < "$TMP/idx/candidates.txt" | tr -d ' ' || echo 0 )
UNITS_ANCHORED=$( [ -s "$TMP/idx/U.txt" ] && wc -l < "$TMP/idx/U.txt" | tr -d ' ' || echo 0 )
UNIT_FILES=$(   [ -s "$TMP/units.txt" ] && wc -l < "$TMP/units.txt" | tr -d ' ' || echo 0 )

# P3 is the orphan set: candidate blocks with no resolvable token.
# The empty-first-file guard is load-bearing, not defensive tidiness: `NR == FNR`
# reads an EMPTY first file as the second one, and on a fresh scaffold NOTHING is
# anchored, so without the guard the orphan set of a wholly unanchored corpus
# reports as zero. That is the same class of defect as a fabricated healthy CDI:
# the most broken possible corpus scoring perfectly.
if [ -s "$TMP/idx/U.txt" ]; then
    awk 'NR == FNR { a[$0] = 1; next } !($0 in a) { print }' \
        "$TMP/idx/U.txt" "$TMP/idx/candidates.txt" 2>/dev/null | sort > "$TMP/p3.txt"
else
    sort "$TMP/idx/candidates.txt" 2>/dev/null > "$TMP/p3.txt"
fi
[ -f "$TMP/p3.txt" ] || : > "$TMP/p3.txt"

while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    check_tokens "$unit"

    scan_body "$ROOT/$unit" | while IFS="$(printf '\t')" read -r ln cls txt; do
        case "$cls" in
            DESC-MUTABLE-FACT) printf '%s:%s\t%s\n' "$unit" "$ln" "$txt" >> "$TMP/p4.txt" ;;
            ORPHAN-CLAIM)      printf '%s:%s\t%s\n' "$unit" "$ln" "$txt" >> "$TMP/p5.txt" ;;
            VOLATILE-DETAIL)   printf '%s:%s\t%s\n' "$unit" "$ln" "$txt" >> "$TMP/p8.txt" ;;
        esac
    done
done < "$TMP/units.txt"

# ---------------------------------------------------------------------------
# Pass 2: docs/. Token checks everywhere; P6 on docs/state records only.
# ---------------------------------------------------------------------------
DOCS_TOTAL=0
while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    DOCS_TOTAL=$((DOCS_TOTAL + 1))
    check_tokens "$doc"
    case "$doc" in
        docs/state/README.md|docs/state/index.md) : ;;
        docs/state/*)
            # Accept both carriers of the date: a YAML front-matter field and
            # the bullet-list header form (`- Verified: 2026-01-15`) that the
            # decision-record style uses. The check is for a DATE OF
            # VERIFICATION, not for a particular syntax.
            if ! grep -qiE '^[[:space:]]*([-*][[:space:]]*)?(verified_at|verified)[[:space:]]*:' "$ROOT/$doc" 2>/dev/null; then
                printf '%s\tno verified_at field\n' "$doc" >> "$TMP/p6.txt"
            fi
            ;;
    esac
done < "$TMP/docs.txt"

count() { [ -s "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
P1=$(count "$TMP/p1.txt"); P1B=$(count "$TMP/p1b.txt"); P2=$(count "$TMP/p2.txt"); P3=$(count "$TMP/p3.txt")
P4=$(count "$TMP/p4.txt"); P5=$(count "$TMP/p5.txt"); P6=$(count "$TMP/p6.txt")
P7=$(count "$TMP/p7.txt"); P8=$(count "$TMP/p8.txt")
EXTU=$(sort -u "$TMP/extu.txt" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
COVERAGE=$(bone_pct "$UNITS_ANCHORED" "$UNITS_TOTAL")
ORPHAN_RATE=$(bone_pct "$P3" "$UNITS_TOTAL")
CITES_TOTAL=$(sort -u "$TMP/alltok.txt" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
CITES_RESOLVABLE=$(sort -u "$TMP/restok.txt" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
RESOLVABILITY=$(bone_pct "$CITES_RESOLVABLE" "$CITES_TOTAL")

if [ "$JSON" -eq 1 ]; then
    printf '{"schema":"bone.provenance-lint/2","generated_at":"%s","project":"%s","unit_granularity":"block","unit_files":%s,"units_total":%s,"units_anchored":%s,"provenance_coverage":%s,"orphan_rate":%s,"docs_scanned":%s,"unresolved_src":%s,"unqualified_paths":%s,"dead_external_refs":%s,"unanchored_blocks":%s,"desc_mutable_fact":%s,"orphan_claims":%s,"state_no_verified_at":%s,"legacy_spelling":%s,"volatile_details":%s,"external_unverifiable":%s,"tokens_total":%s,"tokens_resolvable":%s,"provenance_resolvability":%s}\n' \
        "$(bone_now_utc)" "$(bone_json_escape "$BONE_PROJECT")" \
        "$UNIT_FILES" "$UNITS_TOTAL" "$UNITS_ANCHORED" "$COVERAGE" "$ORPHAN_RATE" "$DOCS_TOTAL" \
        "$P1" "$P1B" "$P2" "$P3" "$P4" "$P5" "$P6" "$P7" "$P8" "$EXTU" \
        "$CITES_TOTAL" "$CITES_RESOLVABLE" "$RESOLVABILITY"
    exit_now=1
else
    # Findings are grouped by file and capped at --limit per file. Twenty
    # identical findings in one reference file are one problem, and printing all
    # twenty is how a report stops being read.
    show() {
        [ -s "$1" ] || return 0
        echo ""
        echo "$2"
        sort "$1" | awk -F'\t' -v lim="$LIMIT" -v exc="$EXCERPT" '
            function flush(k) { if (k != "" && extra > 0) printf "    ... and %d more in %s\n", extra, k }
            {
                key = $1; sub(/:[0-9]*$/, "", key)
                if (key != prev) { flush(prev); prev = key; n = 0; extra = 0 }
                n++
                if (lim > 0 && n > lim) { extra++; next }
                printf "  %s\n", $1
                if (exc == 1 && $2 != "") printf "      %s\n", substr($2, 1, 100)
            }
            END { flush(prev) }
        '
    }

    echo "BONE provenance lint - $BONE_PROJECT"
    echo "  root                  $ROOT"
    echo "  granularity           block (the unit of B-108; shared with cdi.sh)"
    echo "  knowledge units       $UNITS_TOTAL candidate blocks in $UNIT_FILES files, $UNITS_ANCHORED anchored"
    echo "                        coverage $COVERAGE, orphan rate $ORPHAN_RATE"
    echo "  docs files            $DOCS_TOTAL scanned"
    echo "  provenance tokens     $CITES_TOTAL distinct, $CITES_RESOLVABLE resolvable (M13 $RESOLVABILITY)"
    echo ""
    echo "  P1 UNRESOLVED-SRC         $P1   (precision ~1.00)"
    echo "  P1b UNQUALIFIED-PATH      $P1B   (precision ~1.00, remediation: add the repo alias)"
    echo "  P2 DEAD-EXTERNAL-REF      $P2   (precision ~1.00 where the repo is present)"
    echo "  P3 UNANCHORED-BLOCK       $P3   (precision ~1.00, informational; this is M7)"
    echo "  P4 DESC-MUTABLE-FACT      $P4   (precision ~0.80)"
    echo "  P5 ORPHAN-CLAIM           $P5   (precision ~0.60, judgement required)"
    echo "  P6 STATE-NO-VERIFIED-AT   $P6   (precision ~1.00)"
    echo "  P7 LEGACY-SPELLING        $P7   (precision ~1.00, never blocking; write repo/<alias>:)"
    if [ "$SHOW_ALL" -eq 1 ]; then
        echo "  P8 VOLATILE-DETAIL        $P8   (precision ~0.35, listed because --all)"
    else
        echo "  P8 VOLATILE-DETAIL        $P8   (precision ~0.35, not listed; pass --all)"
    fi
    echo "  -- external refs not verifiable here: $EXTU distinct (working copy absent; not a finding)"

    show "$TMP/p1.txt" "P1 UNRESOLVED-SRC - token resolves to no record, no repo path and no known alias:"
    show "$TMP/p1b.txt" "P1b UNQUALIFIED-PATH - a path with no repo alias, ambiguous across the code repos:"
    show "$TMP/p2.txt" "P2 DEAD-EXTERNAL-REF - the alias is known, the working copy is here, the file is not, and it is not there at the effective pin either:"
    if [ -s "$TMP/p3.txt" ]; then
        echo ""
        echo "P3 UNANCHORED-BLOCK - a declarative block with no provenance token (file:line):"
        if [ "$SHOW_ALL" -eq 1 ]; then
            sed 's/^/  /' "$TMP/p3.txt"
        else
            awk -F: '{ f = $0; sub(/:[0-9]*$/, "", f); n[f]++ }
                     END { for (k in n) printf "  %s   %d block(s)\n", k, n[k] }' \
                "$TMP/p3.txt" | sort
            echo "  (pass --all for every line, or cdi.sh --blocks for the full audit trail)"
        fi
    fi
    show "$TMP/p4.txt" "P4 DESC-MUTABLE-FACT - a description carries a fact that can change:"
    show "$TMP/p5.txt" "P5 ORPHAN-CLAIM - decision or live-state language with no source:"
    if [ -s "$TMP/p6.txt" ]; then
        echo ""
        echo "P6 STATE-NO-VERIFIED-AT - a state record that cannot anchor anything:"
        sed 's/^/  /' "$TMP/p6.txt"
    fi
    show "$TMP/p7.txt" "P7 LEGACY-SPELLING - bare <alias>:<path>; the normative form is repo/<alias>:<path>:"
    [ "$SHOW_ALL" -eq 1 ] && show "$TMP/p8.txt" "P8 VOLATILE-DETAIL - version / host / port / env var with no source:"

    echo ""
    echo "READ THIS BEFORE ACTING ON THE COUNTS"
    echo "  P1, P1b, P2, P3, P6, P7 are mechanical: treat them as facts."
    echo "  P4 is narrow but not exact: glance at each one."
    echo "  P5 is a heuristic at roughly 0.6 precision. Expect about 2 in 5 to be fine."
    echo "  P8 is roughly 0.35 and exists to be counted, not obeyed."
    echo "  P3 counts declarative BLOCKS, not files. A high orphan rate on a young corpus is"
    echo "  the normal starting point; it is the trend that carries information, not the level."
    echo "  This lint CANNOT detect: a cited claim that is WRONG; a citation that does not"
    echo "  support its claim (over-citation); a claim written as prose rather than a bullet;"
    echo "  a claim in a table cell; or a claim whose source changed under it (that is cdi.sh)."
    echo "  It measures anchoring, not truth."
    echo "  Nothing was modified. This script never writes to a file it scans."
fi

if [ "$STRICT" -eq 1 ]; then
    if [ "$P1" -gt 0 ] || [ "$P1B" -gt 0 ] || [ "$P2" -gt 0 ] || [ "$P4" -gt 0 ] || [ "$P6" -gt 0 ]; then exit 3; fi
fi
exit 0
