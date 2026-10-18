#!/bin/sh
# bone-init.sh - scaffold a new {PROJECT}-BONE knowledge repository from bone-template.
#
# POSIX sh. No bashisms, no dependencies beyond coreutils, sed, grep and find.
# Exit codes: 0 ok . 1 usage or validation error . 2 refused (target not empty) . 3 template lint failed.

set -eu

# --- Constants ---------------------------------------------------------------------------------
BONE_VERSION="0.1.0"      # the bone-spec version this template scaffolds to
SCHEMA_VERSION="1.0"      # the MANIFEST.yaml schema version this template emits

# The closed substitution set. A {{PLACEHOLDER}} in template/ that is not listed here is a bug, and
# so is a placeholder listed here that PLACEHOLDERS.md does not document. lint_templates() enforces both.
PLACEHOLDERS="PROJECT PROJECT_SLUG PREFIX BONE_REPO GROUP_URL OWNER DATE BONE_VERSION SCHEMA_VERSION"

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE_DIR="$SELF_DIR/template"
PLACEHOLDER_DOC="$SELF_DIR/PLACEHOLDERS.md"

# --- Defaults ----------------------------------------------------------------------------------
PROJECT=""
PROJECT_SLUG=""
PREFIX=""
TARGET_DIR=""
BONE_REPO=""
GROUP_URL="TODO-set-group-url"
OWNER="TODO-set-owner"
DATE=""
FORCE=0
DRY_RUN=0
QUIET=0
LINT_ONLY=0
NO_GIT=0
REMOTE=""

# --- Helpers -----------------------------------------------------------------------------------
die() {
	printf 'bone-init: %s\n' "$1" >&2
	exit "${2:-1}"
}

say() {
	[ "$QUIET" -eq 1 ] || printf '%s\n' "$1"
}

usage() {
	# The delimiter is deliberately not a word that can appear as a section header in the body.
	# A heredoc terminated early by its own help text is invisible to `sh -n` and turns --help,
	# the first command anyone runs, into an exit 127.
	cat <<'BONE_USAGE_EOF'
bone-init.sh - scaffold a new {PROJECT}-BONE knowledge repository.

USAGE
  bone-init.sh --project NAME --prefix PFX --dir PATH [options]
  bone-init.sh --lint-templates
  bone-init.sh --help

REQUIRED
  --project NAME     Human-readable project name, e.g. "City Library Lending".
  --prefix PFX       Skill namespace prefix, 2 to 8 chars, [a-z][a-z0-9]*, e.g. cll.
                     Every T1 skill directory is named <prefix>-<thing>.
  --dir PATH         Target directory. Created if absent. Must be empty unless --force.

OPTIONAL
  --slug SLUG        Kebab-case project slug. Default: derived from --project.
  --bone-repo NAME   Knowledge repository name.  Default: <slug>-bone.
  --group-url URL    Git host namespace that owns the project's repositories.
  --owner ID         Accountable owner handle, recorded in MANIFEST.yaml and the bootstrap records.
  --date YYYY-MM-DD  Instantiation date. Default: today.
  --remote URL       Configure "origin" on the new repository after the genesis commit. Without a
                     remote the knowledge base exists on exactly one disk, and conformance check
                     0.1 fails by construction, so BONE-0 is unreachable. Nothing is pushed; the
                     push stays a deliberate human act.
  --no-git           Do NOT initialise a git repository or make the genesis commit. By default
                     the scaffold runs "git init -b main", "git add -A" and one commit, so a
                     knowledge repository is version-controlled from second one. A knowledge
                     base that is not in git has no history, no review gate and no provenance,
                     which is the exact failure this methodology exists to fix.
  --force            Write into a non-empty target. Overwrites template-derived files only;
                     nothing outside the template is ever deleted.
  --dry-run          Print what would be written; write nothing. Implies --no-git.
  --quiet            Suppress per-file output. Errors still print.
  --lint-templates   Check the template's placeholders against PLACEHOLDERS.md, validate
                     MANIFEST.yaml.tmpl against the frozen schema, smoke-test --help and
                     --version, then exit. Writes nothing.
  --version          Print the bone-spec and schema versions this template emits.
  --help             This text.

PLACEHOLDERS
  Documented in PLACEHOLDERS.md. That file and the PLACEHOLDERS list in this script are linted
  against each other and against template/ on every run, so the three cannot drift.

EXAMPLE
  ./bone-init.sh --project "City Library Lending" --prefix cll \
                 --dir ./city-library-lending-bone \
                 --group-url https://git.example.org/city-library \
                 --owner owner

AFTERWARDS
  Install the T0 capability library once per machine: see bone-skills/README.md,
  section "Installing T0". These commands are not restated anywhere else.
BONE_USAGE_EOF
}

# Escape a replacement string for use with sed and the | delimiter.
sed_escape() {
	printf '%s' "$1" | sed 's/[\&|]/\\&/g'
}

# Lowercase, collapse non-alphanumerics to single hyphens, trim leading and trailing hyphens.
slugify() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-\{1,\}//' -e 's/-\{1,\}$//'
}

matches() {
	printf '%s' "$1" | grep -qE "$2"
}

# Every {{PLACEHOLDER}} occurring in template/, in file contents and in file and directory names.
template_placeholders() {
	{
		grep -rhoE '\{\{[A-Za-z0-9_]+\}\}' "$TEMPLATE_DIR" 2>/dev/null || true
		find "$TEMPLATE_DIR" -mindepth 1 -print |
			grep -oE '\{\{[A-Za-z0-9_]+\}\}' || true
	} | sed -e 's/^{{//' -e 's/}}$//' | sort -u
}

# --- The frozen MANIFEST.yaml schema -------------------------------------------------------------
# Top-level key order is NORMATIVE: the hooks resolve a scalar by first match in the file, so moving
# a key changes which value a consumer reads. An unknown or out-of-order top-level key is a lint
# failure, and so is a missing key that a T0 skill or a hook reads.
MANIFEST_ORDER="schema_version bone_version conformance manifest project paths hooks tiers repos
environments owners roles systems_of_record forge tracker branching commits change_request rhythm
docs_registry gates watched knowledge_units decay curation metrics conventions house_style"

# Every key that the spec marks REQUIRED, plus every key a shipped T0 skill or hook reads.
MANIFEST_REQUIRED="schema_version bone_version conformance
project.id project.name project.slug project.prefix project.bone_repo project.group_url
project.created project.status
paths.constitution paths.ledger paths.state paths.contracts paths.domain paths.skills
paths.capability_entry_filename paths.capability_meta_filename paths.curation
paths.curation_index paths.metrics
hooks.dir hooks.session_start
tiers.T0.location tiers.T0.source_repo tiers.T0.install tiers.T0.version tiers.T0.owns
tiers.T1.location tiers.T1.owns tiers.T2.location tiers.T2.owns
repos environments owners roles systems_of_record
forge.kind forge.host forge.cli forge.change_request_term
tracker.system_of_record tracker.key_pattern tracker.close_keyword
branching.integration_branch branching.protected branching.branch_pattern
commits.subject_pattern commits.types commits.trailer
change_request.template
rhythm.journal_dir rhythm.timezone rhythm.tracks rhythm.cadences
docs_registry gates watched knowledge_units
decay.method decay.baseline decay.unit_granularity decay.events decay.readings
decay.never_blocks_session
curation.cdi_threshold curation.max_interval_days
metrics.dir metrics.streams
conventions.skill_prefix conventions.skill_size_bytes conventions.description_chars
conventions.changeset_verbs conventions.modal_markers conventions.gate_verdicts
conventions.adr_status conventions.adr_operative
house_style"

# Lists whose items are read by the awk parser in bone-lib.sh. That parser emits the FIRST line of
# each `- ` item and strips a leading `path: `, so a map item whose first key is not the expected one
# is silently dropped. A dropped watch item does not error: it reports a healthy zero.
MANIFEST_PATH_FIRST="watched knowledge_units docs_registry streams"

# validate_manifest <file> <label> -> 0 ok, 1 failed (messages on stderr)
# The key lists are folded onto one line first: an awk -v assignment may not contain a newline.
validate_manifest() {
	_vm_order=$(printf '%s' "$MANIFEST_ORDER" | tr '\n' ' ')
	_vm_req=$(printf '%s' "$MANIFEST_REQUIRED" | tr '\n' ' ')
	awk -v ORDER="$_vm_order" -v REQ="$_vm_req" \
		-v PATHFIRST="$MANIFEST_PATH_FIRST" -v LABEL="$2" '
	function err(m) { printf "lint: %s: %s\n", LABEL, m > "/dev/stderr"; nerr++ }
	BEGIN {
		n = split(ORDER, o, /[ \t\n]+/); for (i = 1; i <= n; i++) if (o[i] != "") canon[o[i]] = i
		n = split(REQ, r, /[ \t\n]+/); for (i = 1; i <= n; i++) if (r[i] != "") req[r[i]] = 1
		n = split(PATHFIRST, p, /[ \t\n]+/); for (i = 1; i <= n; i++) if (p[i] != "") pathfirst[p[i]] = 1
		d = 0; ntop = 0; inlist = 0; listind = -1; nerr = 0
	}
	{
		line = $0; sub(/\r$/, "", line)
		if (line ~ /^[ \t]*$/) next
		if (line ~ /^[ \t]*#/) next
		ind = 0
		while (substr(line, ind + 1, 1) == " ") ind++
		rest = substr(line, ind + 1)

		if (rest ~ /^-[ ]+[A-Za-z0-9_]+:/) {
			k = rest; sub(/^-[ ]+/, "", k); sub(/:.*$/, "", k)
			while (d > 0 && stackind[d] >= ind) d--
			owner = (d > 0) ? stackkey[d] : "(root)"
			if (owner == "repos" && k != "alias")
				err("repos[] item starts with \"" k ":\"; `alias` MUST be the first key")
			if ((owner in pathfirst) && k != "path")
				err(owner "[] item starts with \"" k ":\"; `path` MUST be the first key")
			inlist = 1; listind = ind
			next
		}

		if (rest ~ /^[A-Za-z0-9_]+:/) {
			k = rest; sub(/:.*$/, "", k)
			if (inlist && ind > listind) next
			inlist = 0
			while (d > 0 && stackind[d] >= ind) d--
			d++; stackind[d] = ind; stackkey[d] = k
			dotted = stackkey[1]
			for (i = 2; i <= d; i++) dotted = dotted "." stackkey[i]
			present[dotted] = 1
			if (ind == 0) { ntop++; top[ntop] = k }
		}
	}
	END {
		last = 0
		for (i = 1; i <= ntop; i++) {
			if (!(top[i] in canon)) { err("unknown top-level key `" top[i] "`; the top-level key set is CLOSED"); continue }
			if (canon[top[i]] <= last)
				err("top-level key `" top[i] "` is out of order; key order is normative")
			last = canon[top[i]]
		}
		for (k in req) if (!(k in present)) err("required key `" k "` is absent")
		exit (nerr > 0 ? 1 : 0)
	}
	' "$1"
}

# --help and --version are the first two commands anyone runs, and a broken heredoc delimiter is
# invisible to `sh -n`. Assert them by execution, not by reading the source.
smoke_self() {
	_self="$SELF_DIR/$(basename -- "$0")"
	[ -f "$_self" ] || _self="$0"
	_rc=0
	_out=$("$_self" --help 2>/dev/null) || _rc=$?
	if [ "$_rc" -ne 0 ]; then
		printf 'lint: --help exited %s, expected 0\n' "$_rc" >&2
		return 1
	fi
	_lines=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
	if [ "$_lines" -le 1 ]; then
		printf 'lint: --help printed %s line(s); the usage heredoc is terminating early\n' "$_lines" >&2
		return 1
	fi
	_rc=0
	"$_self" --version >/dev/null 2>&1 || _rc=$?
	if [ "$_rc" -ne 0 ]; then
		printf 'lint: --version exited %s, expected 0\n' "$_rc" >&2
		return 1
	fi
	say "lint: ok - --help exits 0 with $_lines lines, --version exits 0"
	return 0
}

# The template must not contain an unknown placeholder, and every declared placeholder must be
# documented and actually used. A placeholder the script does not substitute is the exact bug class
# this check exists to prevent.
lint_templates() {
	rc=0
	[ -d "$TEMPLATE_DIR" ] || die "template directory not found: $TEMPLATE_DIR"
	[ -f "$PLACEHOLDER_DOC" ] || die "PLACEHOLDERS.md not found: $PLACEHOLDER_DOC"

	found=$(template_placeholders)

	for t in $found; do
		case " $PLACEHOLDERS " in
		*" $t "*) ;;
		*)
			printf 'lint: {{%s}} appears in template/ but is not in the substitution set\n' "$t" >&2
			rc=1
			;;
		esac
	done

	for t in $PLACEHOLDERS; do
		printf '%s\n' "$found" | grep -qxF "$t" ||
			{
				printf 'lint: {{%s}} is in the substitution set but is unused in template/\n' "$t" >&2
				rc=1
			}
		grep -qF "{{$t}}" "$PLACEHOLDER_DOC" ||
			{
				printf 'lint: {{%s}} is not documented in PLACEHOLDERS.md\n' "$t" >&2
				rc=1
			}
	done

	MANIFEST_TMPL="$TEMPLATE_DIR/MANIFEST.yaml.tmpl"
	if [ -f "$MANIFEST_TMPL" ]; then
		validate_manifest "$MANIFEST_TMPL" "MANIFEST.yaml.tmpl" || rc=1
	else
		printf 'lint: %s not found\n' "$MANIFEST_TMPL" >&2
		rc=1
	fi

	smoke_self || rc=1

	[ "$rc" -eq 0 ] || die "template lint failed" 3
	say "lint: ok - $(printf '%s\n' "$found" | wc -l | tr -d ' ') placeholders, all known, documented and used"
	say "lint: ok - MANIFEST.yaml.tmpl matches the frozen schema"
}

# --- Argument parsing --------------------------------------------------------------------------
need() {
	[ "$1" -gt 1 ] || die "option $2 requires a value"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--project) need $# "$1" && shift && PROJECT=$1 ;;
	--project=*) PROJECT=${1#*=} ;;
	--prefix) need $# "$1" && shift && PREFIX=$1 ;;
	--prefix=*) PREFIX=${1#*=} ;;
	--dir) need $# "$1" && shift && TARGET_DIR=$1 ;;
	--dir=*) TARGET_DIR=${1#*=} ;;
	--slug) need $# "$1" && shift && PROJECT_SLUG=$1 ;;
	--slug=*) PROJECT_SLUG=${1#*=} ;;
	--bone-repo) need $# "$1" && shift && BONE_REPO=$1 ;;
	--bone-repo=*) BONE_REPO=${1#*=} ;;
	--group-url) need $# "$1" && shift && GROUP_URL=$1 ;;
	--group-url=*) GROUP_URL=${1#*=} ;;
	--owner) need $# "$1" && shift && OWNER=$1 ;;
	--owner=*) OWNER=${1#*=} ;;
	--date) need $# "$1" && shift && DATE=$1 ;;
	--date=*) DATE=${1#*=} ;;
	--remote) need $# "$1" && shift && REMOTE=$1 ;;
	--remote=*) REMOTE=${1#*=} ;;
	--no-git) NO_GIT=1 ;;
	--force) FORCE=1 ;;
	--dry-run) DRY_RUN=1 ;;
	--quiet) QUIET=1 ;;
	--lint-templates) LINT_ONLY=1 ;;
	--version)
		printf 'bone-template: bone-spec %s, manifest schema %s\n' "$BONE_VERSION" "$SCHEMA_VERSION"
		exit 0
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
	shift
done

if [ "$LINT_ONLY" -eq 1 ]; then
	lint_templates
	exit 0
fi

# --- Validation --------------------------------------------------------------------------------
[ -n "$PROJECT" ] || die "--project is required (try --help)"
[ -n "$PREFIX" ] || die "--prefix is required (try --help)"
[ -n "$TARGET_DIR" ] || die "--dir is required (try --help)"

matches "$PREFIX" '^[a-z][a-z0-9]{1,7}$' ||
	die "--prefix must be 2 to 8 characters, lowercase letters and digits, starting with a letter (got: $PREFIX)"

[ -n "$PROJECT_SLUG" ] || PROJECT_SLUG=$(slugify "$PROJECT")
[ -n "$PROJECT_SLUG" ] ||
	die "could not derive a slug from --project \"$PROJECT\"; give --slug yourself"
matches "$PROJECT_SLUG" '^[a-z0-9]+(-[a-z0-9]+)*$' ||
	die "--slug must be kebab-case, lowercase alphanumeric (got: $PROJECT_SLUG)"

[ -n "$BONE_REPO" ] || BONE_REPO="${PROJECT_SLUG}-bone"

[ -n "$DATE" ] || DATE=$(date -u +%Y-%m-%d)
matches "$DATE" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "--date must be YYYY-MM-DD (got: $DATE)"

case "$TARGET_DIR" in
"" | "/") die "refusing to scaffold into \"$TARGET_DIR\"" ;;
esac

# The template must be sound before anything is written.
lint_templates

# --- Target directory safety -------------------------------------------------------------------
if [ -e "$TARGET_DIR" ]; then
	[ -d "$TARGET_DIR" ] || die "target exists and is not a directory: $TARGET_DIR"
	if [ -n "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -print 2>/dev/null | head -n 1)" ]; then
		[ "$FORCE" -eq 1 ] ||
			die "target directory is not empty: $TARGET_DIR (use --force to write into it anyway)" 2
		printf 'bone-init: warning: --force, writing into a non-empty directory. Template-derived\n' >&2
		printf '           files are overwritten and hand edits to them are lost. Nothing else\n' >&2
		printf '           is deleted or touched.\n' >&2
	fi
fi

# --- Build the substitution script ---------------------------------------------------------------
SED_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/bone-init.sed.XXXXXX")
FILE_LIST=$(mktemp "${TMPDIR:-/tmp}/bone-init.list.XXXXXX")
trap 'rm -f "$SED_SCRIPT" "$FILE_LIST"' EXIT HUP INT TERM

add_sub() {
	printf 's|{{%s}}|%s|g\n' "$1" "$(sed_escape "$2")" >>"$SED_SCRIPT"
}

add_sub PROJECT "$PROJECT"
add_sub PROJECT_SLUG "$PROJECT_SLUG"
add_sub PREFIX "$PREFIX"
add_sub BONE_REPO "$BONE_REPO"
add_sub GROUP_URL "$GROUP_URL"
add_sub OWNER "$OWNER"
add_sub DATE "$DATE"
add_sub BONE_VERSION "$BONE_VERSION"
add_sub SCHEMA_VERSION "$SCHEMA_VERSION"

substitute_path() {
	printf '%s' "$1" | sed -f "$SED_SCRIPT"
}

# --- Scaffold ------------------------------------------------------------------------------------
say ""
say "  project   $PROJECT ($PROJECT_SLUG)"
say "  prefix    ${PREFIX}-"
say "  repo      $BONE_REPO"
say "  owner     $OWNER"
say "  date      $DATE"
say "  target    $TARGET_DIR"
[ "$DRY_RUN" -eq 0 ] || say "  mode      DRY RUN, nothing is written"
say ""

find "$TEMPLATE_DIR" -type f -print | LC_ALL=C sort >"$FILE_LIST"
[ -s "$FILE_LIST" ] || die "template directory is empty: $TEMPLATE_DIR"

[ "$DRY_RUN" -eq 1 ] || mkdir -p "$TARGET_DIR"

COUNT=0
while IFS= read -r src; do
	rel=${src#"$TEMPLATE_DIR"/}
	out_rel=$(substitute_path "$rel")
	case "$out_rel" in
	*.tmpl) out_rel=${out_rel%.tmpl} ;;
	esac
	dest="$TARGET_DIR/$out_rel"

	if [ "$DRY_RUN" -eq 0 ]; then
		mkdir -p "$(dirname "$dest")"
		sed -f "$SED_SCRIPT" "$src" >"$dest"
		case "$dest" in
		*.sh) chmod +x "$dest" ;;
		esac
	fi

	COUNT=$((COUNT + 1))
	say "  create  $out_rel"
done <"$FILE_LIST"

# Hooks arrive from the BONE distribution rather than from this template. Any that are already in
# place are made executable here so a scaffolded repository is runnable without a follow-up step.
if [ "$DRY_RUN" -eq 0 ] && [ -d "$TARGET_DIR/.claude/hooks" ]; then
	find "$TARGET_DIR/.claude/hooks" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
fi

# --- Verify --------------------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
	LEFTOVER=$(grep -rlE '\{\{[A-Za-z0-9_]+\}\}' "$TARGET_DIR" 2>/dev/null || true)
	if [ -n "$LEFTOVER" ]; then
		printf 'bone-init: unsubstituted placeholders remain in:\n%s\n' "$LEFTOVER" >&2
		die "scaffold is incomplete" 3
	fi

	# The substituted manifest is what the hooks and the T0 skills will actually parse. Validating
	# only the template would pass a scaffold whose substitution broke the shape.
	validate_manifest "$TARGET_DIR/MANIFEST.yaml" "generated MANIFEST.yaml" ||
		die "the generated MANIFEST.yaml does not match the frozen schema" 3
fi

say ""
say "  $COUNT files written to $TARGET_DIR"

# --- Version control ------------------------------------------------------------------------------
# A knowledge repository that is not in git has no history, no review gate and no provenance, which
# is the exact failure this methodology exists to fix. The scaffold is committed here rather than
# left as a post-scaffold instruction that half of adopters skip.
git_bootstrap() {
	_t="$1"
	if ! command -v git >/dev/null 2>&1; then
		printf 'bone-init: warning: git is not on PATH; the scaffold is written but not\n' >&2
		printf '           version-controlled. Initialise it yourself before doing any work.\n' >&2
		return 0
	fi
	if [ -d "$_t/.git" ]; then
		say "  git       already a git repository; history left alone"
		return 0
	fi
	if ! (cd "$_t" && git init -b main >/dev/null 2>&1); then
		# git older than 2.28 has no `init -b`.
		if ! (cd "$_t" && git init >/dev/null 2>&1 &&
			git symbolic-ref HEAD refs/heads/main >/dev/null 2>&1); then
			printf 'bone-init: warning: git init failed; the scaffold is written but not\n' >&2
			printf '           version-controlled.\n' >&2
			return 0
		fi
	fi
	if ! (cd "$_t" && git add -A >/dev/null 2>&1); then
		printf 'bone-init: warning: git add failed; nothing is staged.\n' >&2
		return 0
	fi
	_msg="genesis: scaffold $BONE_REPO from bone-template $BONE_VERSION"
	if (cd "$_t" && git commit -q -m "$_msg" >/dev/null 2>&1); then
		say "  git       initialised on main; genesis commit made"
		if [ -n "$REMOTE" ]; then
			if (cd "$_t" && git remote add origin "$REMOTE" >/dev/null 2>&1); then
				say "  remote    origin -> $REMOTE (not pushed; push is a deliberate act)"
			else
				printf 'bone-init: warning: could not add remote "%s".\n' "$REMOTE" >&2
			fi
		fi
	else
		printf 'bone-init: warning: git commit failed. Is user.name / user.email configured?\n' >&2
		printf '           Everything is staged. Finish it with:\n' >&2
		printf '             cd %s && git commit -m "%s"\n' "$_t" "$_msg" >&2
	fi
	return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
	say "  git       skipped (--dry-run)"
elif [ "$NO_GIT" -eq 1 ]; then
	say "  git       skipped (--no-git); this repository has no history yet"
else
	git_bootstrap "$TARGET_DIR"
fi

# --- Next steps ----------------------------------------------------------------------------------
cat <<NEXT

Next steps. The scaffold is structurally complete and factually empty: every layer exists and no
layer yet holds a verified fact. Work top down; each step below is blocked by the one above it.

  0. Install the T0 capability library once per machine. The commands live in exactly one place:
     bone-skills/README.md, section "Installing T0". They are not restated here or anywhere else.
     Nothing in .claude/hooks/ needs it, but every propose-then-ask procedure does.

  1. Add a remote and push. The genesis commit is already made on branch main (unless you passed
     --no-git). A knowledge repository with no remote is not shareable, exists on one disk, and
     half the workflow rules become conditional.
       git remote add origin $GROUP_URL/$BONE_REPO
       git push -u origin main

  2. MANIFEST.yaml - replace every TODO. Nothing downstream works until this is real:
       repos[]              every repository in the estate, including the ones you are not
                            touching yet. "alias" MUST stay the first key of each item. Set
                            local_path for every working copy you have: that is what lets decay
                            detection watch files this repository does not own. Set pinned_at on
                            every T2 repo: it is the commit-ish that every unpinned code reference
                            into that repo is understood to cite.
       watched[]            uncomment and adapt the external block at the bottom. Until at least
                            one "repo/<alias>:<path>" entry is declared, external-CDI is null and
                            this knowledge base cannot notice that the code moved, which is the
                            single failure it exists to detect.
       environments[]       what is deployed where, and from which branch
       owners[], roles[]    who approves curation changesets, and who owns which class of fact
       systems_of_record[]  for each class of truth, the one authoritative place.
                            A class that is genuinely undecided stays UNDECIDED with an open ADR;
                            it MUST NOT be guessed.
       forge, tracker,      the workflow parameters the T0 skills read. "cli: none" and
       branching, commits   "system_of_record: UNDECIDED" are honest answers; wrong ones are not.
       rhythm.timezone      what "today" means.
       gates[]              the gate set. Empty is honest. Inventing gates nobody runs is not.

  3. docs/state/ - write the first records. Verify each fact first hand, record the method, and date
     it. Do not populate this layer from READMEs or plan documents: those are the artifacts most
     likely to be stale, and a fact copied from one arrives with no provenance.

  4. docs/adr/ - open a record for every question that is live. An open question recorded as open is
     worth more than a decision invented to close it.

  5. docs/contracts/ - one row and one file per module seam, including the seams that exist in code
     with no contract. Mark those "status: undocumented-today" in the contract's front matter.

  6. .claude/skills/${PREFIX}-context/ - fill SKILL.md from steps 3 to 5 only, and fill in
     meta.yaml beside it. A capability unit is a directory holding both; peer relations are
     declared once, in meta.yaml under chains_with, and nowhere else.

  7. Confirm the mechanism runs: "sh .claude/hooks/decay-check.sh" MUST exit 0. It is already
     wired to SessionStart in .claude/settings.json. On a fresh scaffold it reports unabsorbed
     sources and a NULL index in state "uninitialised", and that reading is CORRECT: sources
     exist, no baseline has been sealed, and no knowledge unit cites anything yet. Steps 3 to 6
     are what makes it go quiet. Do NOT seal the baseline to silence it: a sealed baseline over
     uncurated content is the one action that makes the metric lie.

  8. metrics/ - take the pre-intervention baseline BEFORE the first curation pass. Without that
     row, every later improvement is attributable to someone paying attention again rather than to
     the method, and the confound cannot be removed afterwards.

  9. Write metrics/curation-baseline.tsv at the end of the first real curation pass. Writing the
     baseline is what resets the decay clock; skipping it leaves every session reporting the same
     index until the warning is correctly ignored.

 10. Read CLAUDE.md end to end and confirm you can live with all seven invariants. They are cheap to
     change now and expensive to change once skills cite them.

NEXT
