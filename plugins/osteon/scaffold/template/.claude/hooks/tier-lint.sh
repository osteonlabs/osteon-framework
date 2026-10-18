#!/usr/bin/env sh
# tier-lint.sh - L-07: cross-tier copy detector.
#
# THE INVARIANT THIS DEFENDS
#   "A fact lives at exactly one tier: the narrowest that fully owns it. Lower
#   tiers reference; they never copy."
#   That is the whole reason knowledge tiering exists, and until this script was
#   written it was the one rule in the methodology with no detector at all.
#   SPEC Appendix C listed L-06 and L-07 at level BONE-1, so an instance at
#   BONE-0 (every instance that exists) never checked its own central claim.
#   It failed on its first real test: a T1 skill carried a byte-identical copy
#   of a T2 command block, the T2 copy was corrected against the real repo, the
#   T1 copy was not, and the stale copy told readers to run a command that does
#   not exist and silently exits 0. Two correct copies are two things to forget;
#   the forgotten one is indistinguishable from the current one.
#
# ALGORITHM
#   Normalise every line (strip leading/trailing space, collapse internal runs,
#   lowercase, drop markdown emphasis and list bullets). Discard lines that are
#   trivially shared across any two documents: fences, headings, table rules,
#   very short lines. Build overlapping SHINGLE-line windows and hash each one.
#   A window appearing in artifacts at two different tiers is a cross-tier copy.
#   Shingling rather than whole-file diffing is what catches a copied block
#   inside two otherwise unrelated documents.
#
#   This is deliberately a HIGH-PRECISION, LOW-RECALL check. It reports runs of
#   identical prose, not paraphrase. A paraphrased duplicate is still a tier
#   violation and this will not see it; see LIMITS at the bottom. A lint that
#   cries wolf gets switched off, and a switched-off lint detects nothing.
#
# TIERS
#   T0  $BONE_T0_ROOT/<name>/**              the org methodology library (declared)
#   T1  <bone>/.claude/skills/<name>/**       this project's facts
#   T2  <repo>/<tier2_context>                repo-local convention, resolved
#                                             through MANIFEST repos[] entries
#                                             (tier2_context + local_path)
#
# EXIT   0 = no cross-tier copy found, or nothing to compare
#        1 = at least one cross-tier copy (only with --strict)
#   Advisory by default: it must never break a session.
set -u

SHINGLE=4        # consecutive normalised lines that constitute a copy
MINLEN=24        # ignore normalised lines shorter than this
STRICT=0
QUIET=0

usage() {
	cat <<'TIERLINT_EOF'
tier-lint.sh - detect cross-tier copies (SPEC L-07)

USAGE
  tier-lint.sh [--strict] [--quiet] [--shingle N] [--min-len N] [--help]

OPTIONS
  --strict      exit 1 when a cross-tier copy is found (for CI). Default is
                advisory: report and exit 0.
  --quiet       print nothing; use the exit status only. Implies --strict.
  --shingle N   consecutive normalised lines that count as a copy (default 4).
  --min-len N   ignore normalised lines shorter than N chars (default 24).

OUTPUT
  One block per finding: the two artifacts, their tiers, and the shared text.

LIMITS
  Detects VERBATIM runs only. A paraphrased duplicate is still a violation and
  this will not see it. It also cannot judge which side should own the fact:
  that is a human call, and the report deliberately does not guess.
TIERLINT_EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	--strict) STRICT=1 ;;
	--quiet) QUIET=1; STRICT=1 ;;
	--shingle) shift; SHINGLE=${1:-4} ;;
	--min-len) shift; MINLEN=${1:-24} ;;
	-h | --help) usage; exit 0 ;;
	*) printf 'tier-lint: unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
	esac
	shift
done

HOOKS=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=/dev/null
. "$HOOKS/bone-lib.sh" 2>/dev/null || {
	printf 'tier-lint: cannot load bone-lib.sh; nothing to do\n' >&2
	exit 0
}
ROOT=$(bone_root) || ROOT=$(CDPATH= cd -- "$HOOKS/../.." && pwd)
MANIFEST="$ROOT/MANIFEST.yaml"

TMP=${TMPDIR:-/tmp}/tier-lint.$$
mkdir -p "$TMP" || exit 0
trap 'rm -rf "$TMP"' EXIT INT TERM

# --- collect (tier, path) pairs -------------------------------------------------------------------
INV="$TMP/inv"
: > "$INV"

# T0: the org methodology library. Its root is declared, never guessed: BONE_T0_ROOT names the
# directory whose bone-* subfolders hold the library (the OSTEON plugin sets it to its own skills
# directory). Unset, the T0 tier is skipped and the lint says so once, so a missing library reads
# as "not checked" and never as "clean". Symlinks are a documented install, so follow them.
T0_ROOT=${BONE_T0_ROOT:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills}}
if [ -n "$T0_ROOT" ] && [ -d "$T0_ROOT" ]; then
	for d in "$T0_ROOT"/*/; do
		[ -d "$d" ] || continue
		case $(basename "${d%/}") in
		bone-*) find -L "${d%/}" -name '*.md' -type f 2>/dev/null |
			while IFS= read -r f; do printf 'T0\t%s\n' "$f" >> "$INV"; done ;;
		esac
	done
elif [ "$QUIET" = 0 ]; then
	printf 'tier-lint: T0 not checked (set BONE_T0_ROOT to the methodology library)\n' >&2
fi

# T1: this project's capability library.
if [ -d "$ROOT/.claude/skills" ]; then
	find "$ROOT/.claude/skills" -name '*.md' -type f 2>/dev/null |
		while IFS= read -r f; do printf 'T1\t%s\n' "$f" >> "$INV"; done
fi

# T2: each repo's own constitution, resolved through the manifest.
if [ -f "$MANIFEST" ]; then
	bone_alias_init "$MANIFEST" 2>/dev/null || true
	for a in $(bone_manifest_list "$MANIFEST" repos 2>/dev/null || true); do :; done
	# bone_manifest_list does not expose repos[] pairs, so read the block directly.
	awk '
		/^repos:/ { inr = 1; next }
		inr && /^[a-z_]+:/ { inr = 0 }
		inr && /^[ \t]*-[ \t]+alias:/ { al = $0; sub(/^[ \t]*-[ \t]+alias:[[:space:]]*/, "", al); sub(/[[:space:]]*#.*$/, "", al); t2 = ""; lp = "" }
		inr && /^[ \t]*tier2_context:/ { t2 = $0; sub(/^[ \t]*tier2_context:[[:space:]]*/, "", t2); sub(/[[:space:]]*#.*$/, "", t2); gsub(/"/, "", t2) }
		inr && /^[ \t]*local_path:/ {
			lp = $0; sub(/^[ \t]*local_path:[[:space:]]*/, "", lp); sub(/[[:space:]]*#.*$/, "", lp); gsub(/"/, "", lp)
			if (t2 != "" && t2 != "null" && lp != "" && lp != "null") printf "%s/%s\n", lp, t2
		}
	' "$MANIFEST" 2>/dev/null | while IFS= read -r f; do
		[ -f "$f" ] && printf 'T2\t%s\n' "$f" >> "$INV"
	done
fi

[ -s "$INV" ] || { [ "$QUIET" -eq 1 ] || printf 'tier-lint: nothing to compare\n'; exit 0; }

# --- shingle every artifact -----------------------------------------------------------------------
# normalise -> drop trivia -> SHINGLE-line windows -> "hash<TAB>tier<TAB>path<TAB>text"
SH="$TMP/shingles"
: > "$SH"
while IFS='	' read -r tier path; do
	[ -f "$path" ] || continue
	awk -v tier="$tier" -v path="$path" -v n="$SHINGLE" -v minlen="$MINLEN" '
		function norm(s) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
			gsub(/[[:space:]][[:space:]]+/, " ", s)
			gsub(/^[-*+][[:space:]]+/, "", s)
			gsub(/^[0-9]+[.)][[:space:]]+/, "", s)
			gsub(/[`*_]/, "", s)
			return tolower(s)
		}
		{
			l = norm($0)
			if (length(l) < minlen) next          # short lines are shared by chance
			if (l ~ /^#+/) next                   # headings recur legitimately
			if (l ~ /^\|?[-: |]+\|?$/) next       # table rules
			if (l ~ /^(```|~~~)/) next            # fences
			buf[++c] = l; raw[c] = $0
		}
		END {
			for (i = 1; i + n - 1 <= c; i++) {
				key = ""; txt = ""
				for (j = 0; j < n; j++) { key = key buf[i+j] "\n"; txt = txt raw[i+j] "\n" }
				gsub(/\n/, "\\n", key); gsub(/\n/, "\\n", txt)
				printf "%s\t%s\t%s\t%s\n", key, tier, path, txt
			}
		}
	' "$path" >> "$SH" 2>/dev/null
done < "$INV"

[ -s "$SH" ] || { [ "$QUIET" -eq 1 ] || printf 'tier-lint: no comparable content\n'; exit 0; }

# --- report windows appearing at two different tiers ----------------------------------------------
OUT="$TMP/out"
sort "$SH" | awk -F'\t' '
	{
		if ($1 != prevkey) { flush(); delete tiers; delete paths; np = 0; prevkey = $1; text = $4 }
		if (!($2 in tiers)) { tiers[$2] = 1; nt++ }
		k = $2 "\t" $3
		if (!(k in seenp)) { seenp[k] = 1; paths[++np] = k }
	}
	function flush(  i, t) {
		if (nt >= 2) {
			printf "CROSS-TIER COPY\n"
			for (i = 1; i <= np; i++) { split(paths[i], t, "\t"); printf "  %s  %s\n", t[1], t[2] }
			printf "  shared text:\n"
			g = text; gsub(/\\n/, "\n    | ", g)
			printf "    | %s\n\n", g
		}
		nt = 0; delete seenp
	}
	END { flush() }
' > "$OUT" 2>/dev/null

# grep -c prints its count AND exits 1 on zero matches, so a `|| echo 0`
# fallback would append a second zero and make every later [ ] test explode.
N=$(grep -c '^CROSS-TIER COPY' "$OUT" 2>/dev/null)
[ -n "$N" ] || N=0

if [ "$QUIET" -eq 1 ]; then
	[ "$N" -eq 0 ] && exit 0 || exit 1
fi

if [ "$N" -eq 0 ]; then
	printf 'tier-lint: no cross-tier copy found (L-07 clean, shingle=%s, min-len=%s)\n' "$SHINGLE" "$MINLEN"
	exit 0
fi

printf 'tier-lint: %s cross-tier cop%s found (L-07)\n\n' "$N" "$([ "$N" -eq 1 ] && echo y || echo ies)"
cat "$OUT"
cat <<'TIERLINT_NOTE'
Each finding is one fact stated at two tiers. Decide which tier OWNS it (the
narrowest that fully does), delete the other copy, and leave a reference in its
place. This lint deliberately does not guess which side should win.
TIERLINT_NOTE

[ "$STRICT" -eq 1 ] && exit 1
exit 0
