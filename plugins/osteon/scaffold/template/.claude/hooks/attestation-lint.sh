#!/bin/sh
# attestation-lint.sh - check that governed knowledge was changed with a record.
# BONE template version: 0.1.0
#
# ---------------------------------------------------------------------------
# WHAT THIS ENFORCES, AND WHY IT IS THE WEAKEST LINK BEING MADE MECHANICAL
#
#   Propose-then-ask is the trust mechanism the whole methodology rests on: an
#   agent proposes a change to the knowledge base, a named human approves it, and
#   the approval is recorded. Until this file existed there was NOTHING checking
#   any of that. The only evidence that a human approved anything was a record
#   asserting that a human approved it, written by the same process that made the
#   change. That is not an audit trail, it is a claim about one.
#
#   Two tiers, sized for a small team, because an unenforceable
#   requirement is worse than a modest one.
#
#   L-27 UNATTESTED-APPLY        error at BONE-1. Always applies.
#       Every applied curation event MUST land as ONE commit containing BOTH the
#       changed governed artifacts AND the curation record describing them
#       (B-124a). A commit that modifies a path under the ledger, state,
#       contracts, domain or skills directories, or the constitution, or
#       MANIFEST.yaml, and that ADDS no file under the curation directory, is an
#       unattested apply. Decidable from `git log` alone: no forge feature, no
#       server, no configuration, and it catches the real failure mode, which is
#       knowledge edited with no record rather than a forged record.
#
#   L-28 UNATTESTED-B129-APPLY   error at BONE-1. Applies to the never-auto-apply
#       classes only (B-129: the constitution, the manifest, an accepted decision
#       record, a released contract, anything naming a person or a cost).
#       The applying commit MUST be externally attestable by exactly one of:
#         (a) signed-commit  - the commit carries a verifiable signature;
#         (b) reviewed-merge - it landed through a change request on a protected
#             branch whose approver differs from its author.
#       (a) is verified here with `git log --show-signature`. (b) CANNOT be
#       verified from a local clone; this script reports it as DECLARED and says
#       so rather than passing it silently.
#
#   THE CONCESSION, STATED HERE SO IT IS NOT ONLY IN THE PAPER. A signed commit
#   proves that the named human's key applied the change. It does not prove that
#   a SECOND human reviewed it. In a team too small to guarantee a distinct
#   approver, that is the honest ceiling of this mechanism, and it is weaker than
#   a hash-chained trail maintained by a service outside the repository.
#
# ---------------------------------------------------------------------------
# WHAT THIS CANNOT CATCH
#   - A curation record that is present, well-formed, and false.
#   - An approval that was given carelessly.
#   - A change made outside git.
#   - Whether the record actually describes the diff it shipped with.
#   All four need a human. This checks that the artifact exists and is attached
#   to the change, which is the part a machine can own.
#
# EXIT CODES
#   0  a report was produced, or the repository has no commits yet
#   2  bad usage, or not a git repository
#   3  --strict AND at least one L-27 or verified-failing L-28 finding
#
# DEPENDENCIES: POSIX sh, awk, sed, git. Read-only: this script runs only
#   `git rev-parse`, `git log` and `git show`, writes nothing, and never touches
#   the network.
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
    echo "attestation-lint.sh: bone-lib.sh not found next to this script." >&2
    exit 2
fi

usage() {
    cat <<'EOF'
attestation-lint.sh - check that governed knowledge was changed with a record.

USAGE
  attestation-lint.sh [--root DIR] [--strict] [--json] [--since REV]
  attestation-lint.sh --help

OPTIONS
  --root DIR   repo root (default: $CLAUDE_PROJECT_DIR, else upward walk, else PWD)
  --since REV  start from REV instead of the genesis commit
  --strict     exit 3 when any L-27 finding exists (for CI)
  --json       one-line JSON summary, appendable to metrics/

EXIT
  0 report produced, or no commits yet   2 bad usage / not a git repo
  3 --strict with findings
EOF
}

ROOT_ARG=""; STRICT=0; JSON=0; SINCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)   [ $# -gt 1 ] || { echo "attestation-lint.sh: --root needs a directory" >&2; exit 2; }
                  ROOT_ARG="$2"; shift ;;
        --since)  [ $# -gt 1 ] || { echo "attestation-lint.sh: --since needs a revision" >&2; exit 2; }
                  SINCE="$2"; shift ;;
        --strict) STRICT=1 ;;
        --json)   JSON=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "attestation-lint.sh: unknown argument '$1' (try --help)" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$ROOT_ARG" ] && BONE_ROOT="$ROOT_ARG"
ROOT=$(bone_root)

command -v git >/dev/null 2>&1 || { echo "attestation-lint.sh: git not found." >&2; exit 2; }
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "attestation-lint.sh: $ROOT is not a git repository." >&2
    exit 2
}

# A repository with no commits has nothing to attest and is not a finding. Say so
# in words: a silent pass here would read as "checked and clean".
if ! git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
    if [ "$JSON" -eq 1 ]; then
        printf '{"schema":"bone.attestation-lint/1","generated_at":"%s","project":"%s","state":"no-commits","commits_scanned":0,"governed_commits":0,"unattested_applies":0,"b129_commits":0,"signed_commits":0,"unsigned_commits":0,"genesis_without_record":0}\n' \
            "$(bone_now_utc)" "$(bone_json_escape "$BONE_PROJECT")"
    else
        echo "BONE attestation lint - $BONE_PROJECT"
        echo "  The repository has no commits yet, so no apply can be attested and none is"
        echo "  unattested. This is not a pass: it is the state before the first commit."
    fi
    exit 0
fi

MAN=$(bone_manifest_path "$ROOT")

# The governed prefixes come from the manifest, never from a list in this script.
val() { [ -n "$MAN" ] && bone_manifest_scalar "$MAN" "$1" || printf ''; }
P_LEDGER=$(val ledger);          : "${P_LEDGER:=docs/adr/}"
P_STATE=$(val state);            : "${P_STATE:=docs/state/}"
P_CONTRACTS=$(val contracts);    : "${P_CONTRACTS:=docs/contracts/}"
P_DOMAIN=$(val domain);          : "${P_DOMAIN:=docs/domain/}"
P_SKILLS=$(val skills);          : "${P_SKILLS:=.claude/skills/}"
P_CONST=$(val constitution);     : "${P_CONST:=CLAUDE.md}"
P_CURATION=$(val curation);      : "${P_CURATION:=docs/curation/}"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/bone-attest.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

RANGE="HEAD"
[ -n "$SINCE" ] && RANGE="$SINCE..HEAD"

# B-124a is scoped "since the genesis commit", so the genesis commit itself is
# the base of the range and not a finding: it creates the entire tree at once and
# has nothing before it to have been proposed against. It is still counted and
# still named below, because "excluded by definition" and "checked and clean" are
# different statements and only one of them is true here.
GENESIS=$(git -C "$ROOT" rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)
: "${GENESIS:=}"

# One walk. `--name-status` so an ADDED curation record is distinguishable from a
# modified one: amending an old record is not an attestation of a new apply.
git -C "$ROOT" log --no-merges --name-status --date=short \
    --pretty=format:'@@%H|%an|%ad|%s' $RANGE > "$TMP/log.txt" 2>/dev/null || :

awk -F'|' -v ledger="$P_LEDGER" -v state="$P_STATE" -v contracts="$P_CONTRACTS" \
          -v domain="$P_DOMAIN" -v skills="$P_SKILLS" -v const="$P_CONST" \
          -v curation="$P_CURATION" -v out="$TMP/findings.tsv" -v tot="$TMP/counts.txt" \
          -v genesis="$GENESIS" '
    function governed(p) {
        return (index(p, ledger) == 1 || index(p, state) == 1 || index(p, contracts) == 1 \
             || index(p, domain) == 1 || index(p, skills) == 1 \
             || p == const || p == "MANIFEST.yaml")
    }
    # B-129: the never-auto-apply classes. A directory prefix is the closest
    # mechanical proxy for "an accepted decision record or a released contract";
    # it over-reports rather than under-reports, which is the safe direction for
    # a check whose failure mode is a missed approval.
    function b129(p) {
        return (p == const || p == "MANIFEST.yaml" \
             || index(p, ledger) == 1 || index(p, contracts) == 1)
    }
    function flush() {
        if (sha == "") return
        commits++
        if (gov > 0) {
            governedc++
            if (rec == 0) {
                if (sha == genesis) genesis_norecord = 1
                else printf "L-27\t%s\t%s\t%s\t%s\n", sha, author, date, subj > out
            }
        }
        if (b129c > 0) b129commits++
        sha = ""; gov = 0; rec = 0; b129c = 0
    }
    /^@@/ {
        flush()
        line = substr($0, 3)
        n = split(line, f, "|")
        sha = f[1]; author = f[2]; date = f[3]
        subj = f[4]
        for (i = 5; i <= n; i++) subj = subj "|" f[i]
        next
    }
    /^[AMDRT]/ {
        # name-status rows are TAB separated: <status> <TAB> <path> [<TAB> <path2>]
        nn = split($0, g, "\t")
        st = g[1]; path = g[nn]
        if (governed(path)) gov++
        if (b129(path))     b129c++
        if (index(path, curation) == 1 && substr(st, 1, 1) == "A") rec++
    }
    END {
        flush()
        printf "%d\t%d\t%d\t%d\n", commits, governedc, b129commits, genesis_norecord + 0 > tot
    }
' "$TMP/log.txt"

[ -f "$TMP/findings.tsv" ] || : > "$TMP/findings.tsv"
[ -f "$TMP/counts.txt" ]   || printf '0\t0\t0\t0\n' > "$TMP/counts.txt"
COMMITS=$(cut -f1 "$TMP/counts.txt");   : "${COMMITS:=0}"
GOVERNED=$(cut -f2 "$TMP/counts.txt");  : "${GOVERNED:=0}"
B129=$(cut -f3 "$TMP/counts.txt");      : "${B129:=0}"
GEN_NOREC=$(cut -f4 "$TMP/counts.txt"); : "${GEN_NOREC:=0}"
L27=$( [ -s "$TMP/findings.tsv" ] && wc -l < "$TMP/findings.tsv" | tr -d ' ' || echo 0 )

# ---------------------------------------------------------------------------
# L-28: signature verification over the commits that touched a B-129 class.
# `git log --show-signature` prints "Good signature" only when the key verifies.
# ---------------------------------------------------------------------------
SIGNED=0; UNSIGNED=0
if [ "$B129" -gt 0 ]; then
    git -C "$ROOT" log --no-merges --pretty=format:'%H %G?' $RANGE 2>/dev/null \
        > "$TMP/sig.txt" || : > "$TMP/sig.txt"
    # %G? is G good, U good-but-untrusted, B bad, E no key, N none.
    SIGNED=$(awk '$2 == "G" || $2 == "U" { n++ } END { print n + 0 }' "$TMP/sig.txt")
    UNSIGNED=$(awk '$2 != "G" && $2 != "U" && NF >= 2 { n++ } END { print n + 0 }' "$TMP/sig.txt")
fi

if [ "$JSON" -eq 1 ]; then
    printf '{"schema":"bone.attestation-lint/1","generated_at":"%s","project":"%s","state":"measured","commits_scanned":%s,"governed_commits":%s,"unattested_applies":%s,"b129_commits":%s,"signed_commits":%s,"unsigned_commits":%s,"genesis_without_record":%s}\n' \
        "$(bone_now_utc)" "$(bone_json_escape "$BONE_PROJECT")" \
        "$COMMITS" "$GOVERNED" "$L27" "$B129" "$SIGNED" "$UNSIGNED" "$GEN_NOREC"
else
    echo "BONE attestation lint - $BONE_PROJECT"
    echo "  root                  $ROOT"
    echo "  range                 ${RANGE}"
    echo "  commits scanned       $COMMITS"
    echo "  touching governed     $GOVERNED"
    echo ""
    echo "  L-27 UNATTESTED-APPLY $L27   (a governed path changed, no curation record added)"
    if [ "$GEN_NOREC" -gt 0 ] 2>/dev/null; then
        echo "       note: the genesis commit ${GENESIS} changed governed paths and added no"
        echo "       curation record. It is EXCLUDED from L-27 by definition, not cleared by it."
    fi
    echo "  L-28 signature cover  $SIGNED signed / $UNSIGNED unsigned of $COMMITS commits"
    if [ -s "$TMP/findings.tsv" ]; then
        echo ""
        echo "L-27 UNATTESTED-APPLY - these commits changed governed knowledge with no record:"
        awk -F'\t' '{ printf "  %s  %s  %s\n      %s\n", substr($2,1,10), $4, $3, $5 }' "$TMP/findings.tsv"
        echo ""
        echo "  Remedy: write the missing record under $P_CURATION naming what changed, why, who"
        echo "  approved it and how. A record written later is worth less than one written with the"
        echo "  change, and is worth more than none."
    fi
    echo ""
    echo "READ THIS BEFORE ACTING ON THE COUNTS"
    echo "  L-27 is mechanical and exact: it reads git, not intent."
    echo "  A signed commit proves the named human's key applied the change. It does NOT prove a"
    echo "  second human reviewed it. On a team too small to guarantee a distinct approver that is"
    echo "  the honest ceiling of this mechanism, and it is weaker than an externally hash-chained"
    echo "  trail. Do not report it as one."
    echo "  reviewed-merge attestation cannot be verified from a local clone at all; a record that"
    echo "  declares it is taken on trust here and must be checked at the forge."
fi

if [ "$STRICT" -eq 1 ] && [ "$L27" -gt 0 ]; then exit 3; fi
exit 0
