#!/bin/sh
# build.sh - regenerate the plugin's generated trees from the committed source repositories.
#
# The sources stay the single owner of every skill and of the scaffold; plugins/osteon/skills and
# plugins/osteon/scaffold are release copies, never edited by hand. Only committed content ships
# (git archive <ref>), so untracked work in a source never leaks. Everything is built in a staging
# directory and gated there; the plugin tree changes only when every gate passes.
#
# Required:  OSTEON_DENYLIST  a non-empty file OUTSIDE this repository, one extended regex per line.
# Optional:  OSTEON_SRC, OSTEON_REF, BONE_SKILLS_SRC, BONE_SKILLS_REF, BONE_TEMPLATE_SRC,
#            BONE_TEMPLATE_REF, EXCLUDE_UNITS (space separated unit names),
#            OSTEON_AUTHOR_RE (the author's name as an extended regex; allowed only in the license,
#            the citation file and the archive metadata).
# Exit: 0 PASS, 1 FAIL. Verdicts are PASS / FAIL only; anything undecidable fails closed.
set -eu
ROOT=$(cd "$(dirname "$0")" && pwd)
OSTEON_SRC=${OSTEON_SRC:-$HOME/OSTEON-LABS};             OSTEON_REF=${OSTEON_REF:-HEAD}
BONE_SKILLS_SRC=${BONE_SKILLS_SRC:-$HOME/BONE/bone-skills}; BONE_SKILLS_REF=${BONE_SKILLS_REF:-HEAD}
BONE_TEMPLATE_SRC=${BONE_TEMPLATE_SRC:-$HOME/BONE/bone-template}; BONE_TEMPLATE_REF=${BONE_TEMPLATE_REF:-HEAD}
EXCLUDE_UNITS=${EXCLUDE_UNITS:-osteon-research-unit}
PLUGIN="$ROOT/plugins/osteon"

fail() { echo "FAIL $1"; exit 1; }
pass() { echo "PASS $1"; }

# Gate 0: the denylist exists, is outside this repo, is non-empty, and every pattern compiles.
[ -n "${OSTEON_DENYLIST:-}" ] && [ -f "$OSTEON_DENYLIST" ] || fail "set OSTEON_DENYLIST to a names file outside this repo"
case "$(cd "$(dirname "$OSTEON_DENYLIST")" && pwd)/" in "$ROOT"/*) fail "the denylist must live outside this repository";; esac
grep -qvE '^[[:space:]]*$' "$OSTEON_DENYLIST" || fail "the denylist is empty, so the scan could not fail"
set +e; printf '' | grep -E -f "$OSTEON_DENYLIST" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -le 1 ] || fail "the denylist holds a pattern grep cannot compile"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/osteon-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/skills" "$STAGE/scaffold"

# Extract. Written to a file first so a failing git archive cannot hide behind tar's status.
extract() { # <repo> <ref> <path> <dest>
  git -C "$1" archive --format=tar "$2" "$3" > "$STAGE/part.tar" || fail "git archive $1 $2 $3"
  tar -x -f "$STAGE/part.tar" -C "$4" || fail "tar extract from $1"
}
extract "$OSTEON_SRC" "$OSTEON_REF" skills "$STAGE"
extract "$BONE_SKILLS_SRC" "$BONE_SKILLS_REF" skills "$STAGE"
for f in bone-init.sh PLACEHOLDERS.md template; do extract "$BONE_TEMPLATE_SRC" "$BONE_TEMPLATE_REF" "$f" "$STAGE/scaffold"; done
rm -f "$STAGE/part.tar"
for u in $EXCLUDE_UNITS; do rm -rf "$STAGE/skills/$u"; done
[ -d "$ROOT/plugin-src/skills" ] && cp -R "$ROOT/plugin-src/skills/." "$STAGE/skills/"

# Gate 1: the denylist over every file that would be published, staged and top-level alike.
TOP="README.md .claude-plugin plugins/osteon/.claude-plugin build.sh"
AUTHOR_FILES="LICENSE CITATION.cff .zenodo.json"
[ -d "$ROOT/plugin-src" ] && TOP="$TOP plugin-src"
[ -d "$PLUGIN/hooks" ] && TOP="$TOP plugins/osteon/hooks"
set +e; (cd "$ROOT" && grep -rniE -f "$OSTEON_DENYLIST" $TOP) ; t=$?; grep -rniE -f "$OSTEON_DENYLIST" "$STAGE"; s=$?; set -e
[ "$t" -le 1 ] && [ "$s" -le 1 ] || fail "the denylist scan could not read every file"
[ "$t" -eq 1 ] && [ "$s" -eq 1 ] || fail "denylist hit above; nothing may be published"
# The author is named by decision in exactly these files, and nowhere else. Strip only the
# author's name (OSTEON_AUTHOR_RE) from them before the same scan, so any other name still fails.
for f in $AUTHOR_FILES; do
  set +e; sed -E "s/${OSTEON_AUTHOR_RE:-^\$}//g" "$ROOT/$f" | grep -niE -f "$OSTEON_DENYLIST"; a=$?; set -e
  [ "$a" -eq 1 ] || fail "denylist hit in $f beyond the author's name"
done
pass "denylist clean over the staged tree and every top-level file"

# Gate 2: house style, no em dash anywhere.
EM=$(printf '\342\200\224')
if LC_ALL=C grep -rln "$EM" "$STAGE" $(for p in $TOP $AUTHOR_FILES; do printf '%s ' "$ROOT/$p"; done); then fail "em dash present in the files above"; fi
pass "no em dash"

# Gate 3: every SKILL.md frontmatter is valid YAML with exactly name and description. A skill
# authored in plugin-src (plugin-native, so it may run a shipped script) may also carry
# allowed-tools and argument-hint; a unit from a source repository may not.
NATIVE=$(ls "$ROOT/plugin-src/skills" 2>/dev/null | tr '\n' ' ')
python3 -I -B - "$STAGE/skills" "$NATIVE" <<'PY' || fail "skill frontmatter"
import sys, os, glob
try:
    import yaml
except ImportError:
    print("FAIL PyYAML is not available, so frontmatter cannot be checked"); sys.exit(1)
bad = 0
native = set(sys.argv[2].split()) if len(sys.argv) > 2 else set()
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*", "SKILL.md"))):
    t = open(f, encoding="utf-8").read()
    if not t.startswith("---\n"):
        print("FAIL no frontmatter:", f); bad = 1; continue
    try:
        fm = yaml.safe_load(t.split("---", 2)[1])
    except Exception as e:
        print("FAIL frontmatter does not parse:", f, e); bad = 1; continue
    d = os.path.basename(os.path.dirname(f))
    extra = {"allowed-tools", "argument-hint"} if d in native else set()
    if not isinstance(fm, dict) or not {"name", "description"} <= set(fm) <= {"name", "description"} | extra or fm.get("name") != d:
        print("FAIL frontmatter keys or name:", f); bad = 1
sys.exit(bad)
PY
pass "skill frontmatter parses"

# Gate 4: one version everywhere it is declared.
V1=$(python3 -I -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")
V2=$(python3 -I -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["plugins"][0]["version"])' "$ROOT/.claude-plugin/marketplace.json")
V3=$(awk '/^version:/{print $2}' "$ROOT/CITATION.cff")
[ "$V1" = "$V2" ] && [ "$V1" = "$V3" ] || fail "versions disagree: plugin.json $V1, marketplace.json $V2, CITATION.cff $V3"
pass "version $V1 everywhere"

# Swap in. Provenance stays local (.build/ is ignored): source names and commits are not published.
rm -rf "$PLUGIN/skills" "$PLUGIN/scaffold"
mv "$STAGE/skills" "$PLUGIN/skills"; mv "$STAGE/scaffold" "$PLUGIN/scaffold"
mkdir -p "$ROOT/.build"
{ echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for p in "$OSTEON_SRC:$OSTEON_REF" "$BONE_SKILLS_SRC:$BONE_SKILLS_REF" "$BONE_TEMPLATE_SRC:$BONE_TEMPLATE_REF"; do
    printf '%s %s\n' "${p%%:*}" "$(git -C "${p%%:*}" rev-parse "${p#*:}")"; done; } > "$ROOT/.build/provenance"
echo "PASS built $(ls "$PLUGIN/skills" | wc -l | tr -d ' ') skills and the scaffold"
