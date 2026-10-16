#!/bin/sh
# bone-lib.sh - shared helpers for the BONE mechanism scripts.
# BONE template version: 0.1.0
#
# THIS FILE IS SOURCED, NEVER EXECUTED. It defines functions only; it starts no
# work and prints nothing. `decay-check.sh`, `cdi.sh` and `provenance-lint.sh`
# each source it and degrade to a silent no-op if it is missing.
#
# WHY A SHARED LIB. The three scripts need the same four things: where the repo
# root is, what the MANIFEST declares, how a provenance token resolves, and how
# to hash a source. BONE's own one-fact-one-tier invariant applies to code:
# those definitions are stated once here and referenced, never copied.
#
# DEPENDENCIES: POSIX sh, awk, sed, grep, find, sort, and one of
# shasum / sha256sum / openssl / git hash-object / cksum (in that preference
# order). `yq` and `jq` are OPTIONAL and are never required.
#
# PRIVACY: no function here ever prints file CONTENT. Everything that reaches
# stdout is a path, a digest, a count or a ratio. Provenance tokens are echoed,
# and by grammar a token is a path, never a value.

# ---------------------------------------------------------------------------
# 0. Configuration. A caller may override any of these BEFORE sourcing.
# ---------------------------------------------------------------------------
BONE_LIB_VERSION="0.1.0"

: "${BONE_PROJECT:={{PROJECT}}}"
: "${BONE_CURATOR_SKILL:=bone-curator}"
: "${BONE_MANIFEST:=MANIFEST.yaml}"
: "${BONE_BASELINE:=metrics/curation-baseline.tsv}"
# There is deliberately NO curation-marker variable. An mtime clock was the
# previous algorithm and it is now forbidden outright (B-139, D-C.5): clone,
# checkout, touch, rsync and edit-then-revert all move mtime without changing
# content, and keeping the knob would keep the code path that can print a
# healthy zero on a base that was never measured.

# Fallback watch sets, used only when MANIFEST.yaml is absent or silent. These
# are the canonical BONE layout paths, so the fallback stays correct for any
# conformant repo and is merely less precise than a curated manifest list.
#
# THE FALLBACK IS INTERNAL-ONLY, AND THAT IS A REPORTED WEAKNESS, NOT A DEFAULT.
# It cannot contain an external source, because no default can know a repository
# alias. An instance running on the fallback therefore measures only its own
# inside and reports external-CDI as null, which is exactly the blind spot
# B-141 exists to close. Declare `watched` in MANIFEST.yaml.
BONE_DEFAULT_SOURCES="docs/adr
docs/state
docs/contracts
docs/domain
CLAUDE.md
MANIFEST.yaml"

BONE_DEFAULT_UNITS=".claude/skills"

# ---------------------------------------------------------------------------
# 1. Repo root. Order: BONE_ROOT, CLAUDE_PROJECT_DIR (set by the agent harness),
#    an upward walk from the hooks directory, then $PWD. Never fails.
# ---------------------------------------------------------------------------
bone_root() {
    if [ -n "${BONE_ROOT:-}" ] && [ -d "${BONE_ROOT}" ]; then
        printf '%s\n' "${BONE_ROOT%/}"; return 0
    fi
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}" ]; then
        printf '%s\n' "${CLAUDE_PROJECT_DIR%/}"; return 0
    fi
    _bone_d="${BONE_SCRIPT_DIR:-$PWD}"
    while [ "$_bone_d" != "/" ] && [ -n "$_bone_d" ]; do
        if [ -f "$_bone_d/MANIFEST.yaml" ] || [ -f "$_bone_d/CLAUDE.md" ] \
           || [ -d "$_bone_d/.claude/skills" ]; then
            printf '%s\n' "$_bone_d"; return 0
        fi
        _bone_d=$(dirname "$_bone_d")
    done
    printf '%s\n' "$PWD"
}

bone_relpath() {
    case "$1" in
        "$2"/*) printf '%s\n' "${1#"$2"/}" ;;
        "$2")   printf '.\n' ;;
        *)      printf '%s\n' "$1" ;;
    esac
}

bone_now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
bone_today()   { date -u +%Y-%m-%d; }

# bone_reading_is_repeat <previous line> <new line> <today, YYYY-MM-DD>
#   True only when the new reading repeats the previous one EXACTLY, on the same
#   UTC day, apart from its own timestamp. Every field counts, denominators
#   included. The key this replaced was day, state, CDI, sources changed and
#   units decayed, and it named none of the denominators: two readings that both
#   said CDI 0 with nothing changed were "identical" however far the corpus under
#   them had moved, so a reading taken right after a reseal that grew the anchored
#   set was discarded as a repeat of the one before it. A reading that moved only
#   its coverage is a different reading, and the stream exists to show it. False
#   when there is no previous line.
bone_reading_is_repeat() {
    _brr_prev=$1; _brr_new=$2; _brr_day=$3
    [ -n "$_brr_prev" ] || return 1
    _brr_pday=$(printf '%s' "$_brr_prev" | sed -n 's/.*"generated_at":"\([0-9-]*\)T.*/\1/p')
    [ "$_brr_pday" = "$_brr_day" ] || return 1
    _brr_a=$(printf '%s' "$_brr_prev" | sed 's/"generated_at":"[^"]*",//')
    _brr_b=$(printf '%s' "$_brr_new" | sed 's/"generated_at":"[^"]*",//')
    [ "$_brr_a" = "$_brr_b" ]
}

# ---------------------------------------------------------------------------
# 2. Hashing. Content hashing is what makes the BONE decay signal correct where
#    an mtime signal is not: clone, checkout, touch, rsync and edit-then-revert
#    all move mtime without changing content, and every one of them produces a
#    false decay reading under the mtime algorithm.
# ---------------------------------------------------------------------------
bone_hash_init() {
    if command -v shasum >/dev/null 2>&1;      then BONE_HASH_ALGO=sha256;    BONE_HASH_IMPL=shasum
    elif command -v sha256sum >/dev/null 2>&1; then BONE_HASH_ALGO=sha256;    BONE_HASH_IMPL=sha256sum
    elif command -v openssl >/dev/null 2>&1;   then BONE_HASH_ALGO=sha256;    BONE_HASH_IMPL=openssl
    elif command -v git >/dev/null 2>&1;       then BONE_HASH_ALGO=git-blob;  BONE_HASH_IMPL=git
    else                                            BONE_HASH_ALGO=cksum-weak; BONE_HASH_IMPL=cksum
    fi
    export BONE_HASH_ALGO BONE_HASH_IMPL
}

# bone_hash_file <abs-path> -> digest | MISSING (path given but unreadable)
bone_hash_file() {
    [ -n "${1:-}" ] || { printf 'UNAVAILABLE\n'; return 0; }
    [ -r "$1" ] || { printf 'MISSING\n'; return 0; }
    case "${BONE_HASH_IMPL:-}" in
        shasum)    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' ;;
        sha256sum) sha256sum "$1" 2>/dev/null | awk '{print $1}' ;;
        openssl)   openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}' ;;
        git)       git hash-object "$1" 2>/dev/null ;;
        cksum)     cksum "$1" 2>/dev/null | awk '{print $1"-"$2}' ;;
        *)         printf 'NOHASHER\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# 3. MANIFEST.yaml reading.
#
#    SUPPORTED YAML SUBSET (deliberately tiny, documented, and implemented here
#    so that no BONE repo is ever forced to install yq):
#
#        <key>:                    # at any indentation
#          <subkey>:               # one level of nesting is traversed
#            - value               # a scalar item
#            - path: value         # a map item: the `path` field is taken
#            - alias: value        # a map item: handled by bone_aliases
#
#    A block ends at the first non-empty, non-list line whose indentation is at
#    or above the key's. Deeper map keys inside a list item (kind:, note:, why:)
#    are ignored, which is what makes `- path: X` + `kind: Y` parse correctly.
#    If `yq` is installed it is tried first; both paths must agree on the subset.
#
#    THREE PARSER INVARIANTS THE MANIFEST MUST HOLD (D-A.1). They are properties
#    of this parser, so they are stated here, next to it:
#      1. In every list read by tooling (`watched`, `knowledge_units`,
#         `docs_registry`, `metrics.streams`), `path` MUST be the first key of
#         each map item.
#      2. In `repos[]`, `alias` MUST be the first key of each item.
#      3. A scalar is resolved by FIRST match in the whole file, so top-level key
#         order is normative and a leaf name used as a scalar must not be reused.
#    Reordering keys does not change the YAML. It silently empties a list, and an
#    empty watch set reports a healthy zero.
# ---------------------------------------------------------------------------
bone_manifest_path() {
    [ -f "$1/$BONE_MANIFEST" ] && printf '%s\n' "$1/$BONE_MANIFEST"
    return 0
}

# bone_manifest_list <manifest-file> <key> -> one raw item per line
bone_manifest_list() {
    _bml_file="$1"; _bml_key="$2"
    [ -f "$_bml_file" ] || return 0

    if command -v yq >/dev/null 2>&1; then
        _bml_out=$(yq -r "[.. | select(type==\"!!map\") ] | .[] | select(has(\"${_bml_key##*.}\")) | .[\"${_bml_key##*.}\"] | select(type==\"!!seq\") | .[] | (.path // .)" \
                   "$_bml_file" 2>/dev/null)
        if [ -n "${_bml_out:-}" ]; then
            printf '%s\n' "$_bml_out" | sed '/^null$/d;/^$/d'
            return 0
        fi
    fi

    awk -v key="$_bml_key" '
        function indent(s,   n) { match(s, /^[ \t]*/); return RLENGTH }
        {
            line = $0
            if (line ~ /^[ \t]*#/) next
            if (!inblock) {
                if (line ~ "^[ \t]*" key ":[ \t]*(#.*)?$") { inblock = 1; keyind = indent(line) }
                next
            }
            if (line ~ /^[ \t]*$/) next
            ind = indent(line)
            if (line ~ /^[ \t]*-[ \t]+/) {
                if (ind <= keyind) { inblock = 0; next }
                v = line
                sub(/^[ \t]*-[ \t]+/, "", v)
                sub(/[ \t]+#.*$/, "", v)
                sub(/[ \t]+$/, "", v)
                if (v != "") print v
                next
            }
            if (ind <= keyind) { inblock = 0 }
        }
    ' "$_bml_file" \
    | sed -e 's/^path:[[:space:]]*//' \
          -e 's/^"\(.*\)"$/\1/' -e "s/^'\\(.*\\)'\$/\\1/" \
    | grep -v ':[[:space:]]' \
    | sed -e '/^$/d'
    return 0
}

# bone_manifest_scalar <manifest-file> <key-leaf> -> first scalar value or empty
bone_manifest_scalar() {
    _bms_file="$1"; _bms_leaf="${2##*.}"
    [ -f "$_bms_file" ] || return 0
    awk -v k="$_bms_leaf" '
        $0 ~ "^[ \t]*" k ":[ \t]*[^ \t#]" {
            sub("^[ \t]*" k ":[ \t]*", ""); sub(/[ \t]+#.*$/, ""); print; exit
        }
    ' "$_bms_file" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\\(.*\\)'\$/\\1/"
    return 0
}

# ---------------------------------------------------------------------------
# 4. Repo aliases.
#
#    The constitution's provenance grammar allows a token to name a file in
#    ANOTHER repository: `[src: repo/<alias>:<path>[:<line-range>][@<pin>]]`.
#    Aliases, their working-copy locations and their commit pins are declared
#    once, in MANIFEST.yaml `repos[]`:
#
#        repos:
#          - alias: lending-api
#            local_path: /path/to/working/copy
#            pinned_at: "a1b2c3d"
#
#    Resolving the alias to a local working copy is what lets BONE decay-watch
#    a file it does not own - the single largest blind spot in the reference
#    implementation this replaces. If the working copy is absent (another
#    machine, a fresh clone), the source is marked UNAVAILABLE and excluded from
#    the CDI numerator AND denominator. An unavailable source never fabricates
#    decay and never hides it: it is counted and reported separately.
#
#    `pinned_at` is the commit-ish that every UNPINNED code-ref into that
#    repository is understood to cite. It is declared ONCE per repository rather
#    than once per token, so advancing it is a single visible curation act
#    instead of a mass edit, and so the fact has exactly one owner.
#
#    bone_alias_init caches the table in BONE_ALIASES
#    (alias<TAB>local_path<TAB>pinned_at).
# ---------------------------------------------------------------------------
bone_alias_init() {
    _bai_man=$(bone_manifest_path "$1")
    if [ -z "$_bai_man" ]; then BONE_ALIASES=""; export BONE_ALIASES; return 0; fi
    BONE_ALIASES=$(awk '
        function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
        function val(s) {
            sub(/^[ \t]*[a-z_]*:[ \t]*/, "", s)
            sub(/[ \t]*#.*$/, "", s); sub(/[ \t]+$/, "", s)
            gsub(/^"|"$/, "", s); gsub(/^'"'"'|'"'"'$/, "", s)
            if (s == "null" || s == "~" || s == "TODO") s = ""
            return s
        }
        /^[ \t]*#/ { next }
        !inrepos { if ($0 ~ /^[ \t]*repos:[ \t]*(#.*)?$/) { inrepos = 1; rind = indent($0) } next }
        {
            if ($0 ~ /^[ \t]*$/) next
            ind = indent($0)
            if (ind <= rind && $0 !~ /^[ \t]*-/) { inrepos = 0; next }
            if ($0 ~ /^[ \t]*-[ \t]+alias:[ \t]*/) {
                if (a != "") print a "\t" p "\t" c
                a = $0; sub(/^[ \t]*-[ \t]+alias:[ \t]*/, "", a)
                sub(/[ \t]*#.*$/, "", a); sub(/[ \t]+$/, "", a)
                gsub(/^"|"$/, "", a)
                p = ""; c = ""
                next
            }
            if ($0 ~ /^[ \t]*local_path:[ \t]*/) { p = val($0) }
            if ($0 ~ /^[ \t]*pinned_at:[ \t]*/)  { c = val($0) }
        }
        END { if (a != "") print a "\t" p "\t" c }
    ' "$_bai_man")
    export BONE_ALIASES
}

# bone_alias_local <alias> -> local working-copy path, or empty
bone_alias_local() {
    [ -n "${BONE_ALIASES:-}" ] || return 0
    printf '%s\n' "$BONE_ALIASES" | awk -F'\t' -v a="$1" '$1 == a { print $2; exit }'
    return 0
}

# bone_alias_pin <alias> -> repos[].pinned_at, or empty when unpinned
bone_alias_pin() {
    [ -n "${BONE_ALIASES:-}" ] || return 0
    printf '%s\n' "$BONE_ALIASES" | awk -F'\t' -v a="$1" '$1 == a { print $3; exit }'
    return 0
}

# bone_alias_known <alias> -> 0 if declared in MANIFEST repos[]
bone_alias_known() {
    [ -n "${BONE_ALIASES:-}" ] || return 1
    printf '%s\n' "$BONE_ALIASES" | awk -F'\t' -v a="$1" 'BEGIN{r=1} $1==a{r=0} END{exit r}'
}

# ---------------------------------------------------------------------------
# 5. Source IDs.
#
#    A SOURCE ID is the stable, portable name of a provenance source:
#      internal:  a repo-relative path        docs/adr/0002-x.md
#      external:  <alias>:<path>              lending-api:CLAUDE.md
#    IDs are what appear in the baseline, in cdi.jsonl and in every message.
#    They never contain an absolute path, so a baseline sealed on one machine is
#    still meaningful on another.
#
#    THE DISCRIMINATOR IS THE COLON, and nothing else. A repo-relative path in a
#    BONE repository does not contain one; a source ID that does is external.
#    The earlier form of this test also required a slash or a dot, which silently
#    classified `catalogue-web:Makefile` as an internal path and hashed it against
#    the wrong root. The internal/external split of decision D-D.2 is computed
#    from this one predicate, so it has to be exactly right.
# ---------------------------------------------------------------------------
# bone_source_kind <source-id> -> internal | external | external-unavailable
#   external-unavailable: the alias resolves to no working copy on this machine,
#   or to a directory that is not there. Such a source is excluded from BOTH
#   sides of every index and counted as sources_unavailable.
bone_source_kind() {
    case "$1" in
        *:*)
            _bsk_local=$(bone_alias_local "${1%%:*}")
            if [ -n "$_bsk_local" ] && [ -d "$_bsk_local" ]; then
                printf 'external\n'
            else
                printf 'external-unavailable\n'
            fi
            return 0 ;;
    esac
    printf 'internal\n'
    return 0
}

# bone_hash_stdin -> sha256 of stdin, same impl selection as bone_hash_file.
bone_hash_stdin() {
    case "${BONE_HASH_IMPL:-}" in
        shasum)    shasum -a 256 2>/dev/null | awk '{print $1}' ;;
        sha256sum) sha256sum 2>/dev/null | awk '{print $1}' ;;
        openssl)   openssl dgst -sha256 2>/dev/null | awk '{print $NF}' ;;
        git)       git hash-object --stdin 2>/dev/null ;;
        cksum)     cksum 2>/dev/null | awk '{print $1"-"$2}' ;;
        *)         cat >/dev/null 2>&1; printf 'NOHASHER\n' ;;
    esac
}

# bone_source_hash <root> <source-id> -> content hash of the source AS THE BONE
# CITES IT, not as it happens to be checked out.
#
# WHY THIS EXISTS. An earlier version hashed `local_path + path` for every
# external source, i.e. the working tree. That made the decay index measure
# whatever branch a developer had checked out, and it failed in both directions:
#
#   FALSE POSITIVE - switching branches, or working on an unmerged PR, reported
#   knowledge as decayed when nothing the BONE describes had moved. A metric that
#   cries wolf is a metric people learn to silence. This was observed live: a
#   baseline sealed while a PR branch was checked out reported several decayed
#   blocks whose claims were all still true at the pinned commit.
#
#   FALSE NEGATIVE, and this is the one that matters - if the clone sits behind
#   canonical, the source can drift arbitrarily and the index stays 0.0000. That
#   is precisely the failure external-CDI exists to catch, so the metric would
#   report health while blind to the only thing it was built to see.
#
# An external source is therefore read at `repos[].pinned_at` through
# `git show <pin>:<path>`. If the pin cannot be resolved the source is reported
# UNAVAILABLE and counted, never silently substituted with the checkout: an
# honest gap in the denominator beats a confident wrong number.
bone_source_hash() {
    case "$2" in
        *:*) : ;;
        *)   bone_hash_file "$1/$2"; return 0 ;;
    esac
    _bsh_alias=${2%%:*}
    _bsh_rest=${2#*:}
    _bsh_local=$(bone_alias_local "$_bsh_alias")
    _bsh_pin=$(bone_alias_pin "$_bsh_alias")

    if [ -z "$_bsh_local" ] || [ ! -d "$_bsh_local" ]; then
        printf 'UNAVAILABLE\n'; return 0
    fi
    if [ -z "$_bsh_pin" ]; then
        # Unpinned: the manifest asserts no commit, so the working tree is the
        # only thing the BONE can mean. Legal, but weaker, and B-99 wants a pin.
        bone_hash_file "${_bsh_local%/}/$_bsh_rest"; return 0
    fi
    if ! git -C "$_bsh_local" cat-file -e "$_bsh_pin:$_bsh_rest" 2>/dev/null; then
        # Pin unfetched, or the path does not exist at that commit. Either way the
        # cited state cannot be read, which is a reportable gap, not a zero.
        printf 'UNAVAILABLE\n'; return 0
    fi
    git -C "$_bsh_local" show "$_bsh_pin:$_bsh_rest" 2>/dev/null | bone_hash_stdin
}

# bone_source_abs <root> <source-id> -> absolute path, or empty if unavailable
#
# Presence check only. For an external source this answers "is the repository
# cloned here", NOT "what does the BONE cite" - use bone_source_hash for content.
bone_source_abs() {
    case "$2" in
        *:*)
            _bsa_alias=${2%%:*}
            _bsa_rest=${2#*:}
            _bsa_local=$(bone_alias_local "$_bsa_alias")
            [ -n "$_bsa_local" ] && [ -d "$_bsa_local" ] || return 0
            printf '%s\n' "${_bsa_local%/}/$_bsa_rest"
            return 0 ;;
    esac
    printf '%s\n' "$1/$2"
}

# bone_expand <root> <entry> -> source IDs. A directory entry expands to every
# *.md beneath it; a file entry is taken as-is. Unreadable entries yield
# nothing here and are reported as missing by the caller.
#
# A CODE FILE IS NAMED INDIVIDUALLY, never reached by declaring its directory:
# directory expansion is markdown-only, because expanding a code tree would pull
# in build output and vendored dependencies and would make the watch set depend
# on what happens to be checked out. `repo/<alias>:<dir>/<file>.py` is the shape
# the watched set uses for a product source.
bone_expand() {
    _be_root="$1"; _be_entry="${2#./}"
    case "$_be_entry" in
        *:*)
            _be_alias=${_be_entry%%:*}
            _be_rest=${_be_entry#*:}
            _be_local=$(bone_alias_local "$_be_alias")
            if [ -z "$_be_local" ]; then printf '%s\n' "$_be_entry"; return 0; fi
            _be_abs="${_be_local%/}/${_be_rest%/}"
            if [ -d "$_be_abs" ]; then
                find "$_be_abs" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r _be_f; do
                    printf '%s:%s\n' "$_be_alias" "$(bone_relpath "$_be_f" "${_be_local%/}")"
                done
            else
                printf '%s\n' "$_be_entry"
            fi
            return 0 ;;
    esac
    _be_abs="$_be_root/${_be_entry%/}"
    if [ -d "$_be_abs" ]; then
        find "$_be_abs" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r _be_f; do
            bone_relpath "$_be_f" "$_be_root"
        done
    else
        printf '%s\n' "${_be_entry%/}"
    fi
}

# bone_sources <root> -> every watched source ID.
#
#   MANIFEST.yaml `watched:`   ONE list. An internal item is a repo-relative file
#                              or directory; an external item is written
#                              `repo/<alias>:<path>` and is resolved through
#                              `repos[].local_path`.
#
# ONE LIST, ONE NAME. `provenance_sources`, `external_watch_sources` and
# `decay.watch` are retired (D-A.2). B-114 requires exactly one declaration of
# what is watched: a second list is a second thing to forget to update, and the
# thing that gets forgotten is the external half, which is the only half that can
# detect "the code moved and nobody updated the doc".
#
# External entries ARE watched. A T2 conventions file, a handoff document or a
# product source file in another repository decays this knowledge base exactly
# like an internal record does. Where the working copy is absent the source is
# marked UNAVAILABLE by the caller and excluded from both sides of the ratio.
bone_sources() {
    _bs_root="$1"
    _bs_man=$(bone_manifest_path "$_bs_root")
    _bs_decl=""
    [ -n "$_bs_man" ] && _bs_decl=$(bone_manifest_list "$_bs_man" "watched")
    [ -n "$_bs_decl" ] || _bs_decl="$BONE_DEFAULT_SOURCES"
    printf '%s\n' "$_bs_decl" | while IFS= read -r _bs_e; do
        [ -n "$_bs_e" ] || continue
        _bs_e=${_bs_e#repo/}
        bone_expand "$_bs_root" "$_bs_e"
    done | sed '/^$/d' \
    | grep -v -e '-TEMPLATE\.md$' -e '/TEMPLATE\.md$' \
    | sort -u
    return 0
}

# NOTE on the TEMPLATE exclusion above: an authoring template in docs/adr/ or
# docs/contracts/ is a form, not a fact. Left in the watch set it decays every
# unit on the day someone improves the template's wording, which trains readers
# to ignore the signal. It is excluded by filename because that is the only
# marker a scaffolded template reliably carries.

# Knowledge units: the consumers whose claims can decay.
bone_units() {
    _bu_root="$1"
    _bu_man=$(bone_manifest_path "$_bu_root")
    _bu_decl=""
    [ -n "$_bu_man" ] && _bu_decl=$(bone_manifest_list "$_bu_man" "knowledge_units")
    [ -n "$_bu_decl" ] || _bu_decl="$BONE_DEFAULT_UNITS"
    printf '%s\n' "$_bu_decl" | while IFS= read -r _bu_e; do
        [ -n "$_bu_e" ] || continue
        bone_expand "$_bu_root" "$_bu_e"
    done | grep -v -e '/SKILLS-CHANGELOG\.md$' -e '/CURATION\.md$' | sort -u \
    | while IFS= read -r _bu_u; do
        # A unit that is not on disk is not a unit. Unlike a source, where a
        # declared-but-absent path is itself the finding, an absent unit would
        # only inflate the CDI denominator with nothing.
        [ -f "$_bu_root/$_bu_u" ] && printf '%s\n' "$_bu_u"
    done
    return 0
}

# ---------------------------------------------------------------------------
# 6. Provenance tokens, and the markdown BLOCK that carries them.
#
#    ACCEPTED FORMS (the constitution's grammar):
#      [src: repo/<alias>:<path>[:<line-range>][@<commit-ish>]]  a code-ref
#      [src: <alias>:<path>[:<line>]]   legacy spelling of the same thing
#      [src: <repo-relative path>]      this repo
#      [src: adr/NNNN]  [src: adr/NNNN#amN]   a decision record
#      [src: state/<f>.md@YYYY-MM-DD]   shorthand for docs/state/<f>.md
#      [src: contract/<name>@vX.Y.Z]    shorthand for docs/contracts/<name>.md
#      [src: domain/<f>.md]             shorthand for docs/domain/<f>.md
#      [verified: YYYY-MM-DD ...]       a live observation with no file to cite
#
#    ACCEPTED LEGACY FORMS, so that a pre-BONE corpus is not reported as 100%
#    orphaned: bare `(ADR-NNNN)`, `[src: ADR-NNNN]` and `(verified YYYY-MM-DD)`.
#
#    PLACEHOLDERS ARE NOT TOKENS. Anything containing <, > or "..." is grammar
#    documentation (`[src: <repo-alias>:<path>]` appears in CLAUDE.md itself and
#    in the hub skill) and is discarded before resolution. Without this rule the
#    linter reports its own specification as a defect, which is exactly how a
#    lint earns being ignored.
#
#    A `verified:` token anchors a claim in TIME but not to a FILE, so it counts
#    as an anchor for coverage and never participates in the decay graph.
#
#    THE UNIT OF MEASUREMENT IS A BLOCK, NOT A FILE. A file-level index answers
#    "does this file contain a token somewhere", which a 10 KB reference document
#    passes on one line and which reports 1.0000 over a corpus carrying dozens of
#    unanchored claims. `bone_scan_blocks` implements the block rules in one
#    place so that cdi.sh and provenance-lint.sh cannot diverge on what a unit is.
#
#    BLOCK RULES (normative; six steps, in this order):
#      1. YAML front matter (first `---` to the next `---`) is not block content.
#         Tokens inside it are still extracted, attached to block 0, which is
#         never a candidate.
#      2. A fenced block and the paragraph immediately preceding it are ONE block.
#      3. A heading line alone is never a block; it is discarded.
#      4. In a table, each data row is one block; the header row and the
#         delimiter row are discarded.
#      5. In a list, each top-level item is one block; continuation lines
#         indented under an item join it; a nested sub-item is its own block.
#      6. Otherwise a block is a maximal run of consecutive non-blank lines.
#
#    A block is a CANDIDATE when it holds at least one declarative sentence:
#    at least four words and thirty characters of prose OUTSIDE any fence, and
#    not in imperative mood. Imperative mood is approximated by the two-part rule
#    published in `imperative-verbs.txt` beside this file.
#
#    OUTPUT of bone_scan_blocks, tab-separated, one record per line:
#      B <TAB> <block-no> <TAB> <start-line> <TAB> <candidate 0|1> <TAB> <kind>
#      T <TAB> <block-no> <TAB> <raw-token>
#    Block 0 is the front matter. Kinds: front, para, list, table, fence, other.
# ---------------------------------------------------------------------------

# bone_imperative_list -> path of the published imperative-verb list, or empty.
bone_imperative_list() {
    for _bil_d in "${BONE_SCRIPT_DIR:-}" "$(dirname -- "$0" 2>/dev/null)" .; do
        [ -n "$_bil_d" ] || continue
        if [ -r "$_bil_d/imperative-verbs.txt" ]; then
            printf '%s\n' "$_bil_d/imperative-verbs.txt"; return 0
        fi
    done
    return 0
}

# bone_scan_blocks <file> -> B and T records (see the grammar above).
bone_scan_blocks() {
    [ -r "$1" ] || return 0
    awk -v verbfile="$(bone_imperative_list)" '
        # ---- imperative-mood approximation -------------------------------
        BEGIN {
            nverb = 0
            if (verbfile != "") {
                while ((getline vline < verbfile) > 0) {
                    sub(/#.*$/, "", vline); sub(/^[ \t]+/, "", vline); sub(/[ \t]+$/, "", vline)
                    if (vline != "") { verb[tolower(vline)] = 1; nverb++ }
                }
                close(verbfile)
            }
            split("must should may never always do shall", m, " ")
            for (i in m) verb[m[i]] = 1
            blockno = 0; nblk = 0
        }
        function finite(s) {
            s = " " tolower(s) " "
            return (index(s, " is ") || index(s, " are ") || index(s, " was ") \
                 || index(s, " were ") || index(s, " has ") || index(s, " have ") \
                 || index(s, " had ") || index(s, " does ") || index(s, " do ") \
                 || index(s, " did ") || index(s, " will ") || index(s, " can ") \
                 || index(s, " cannot ") || index(s, " isnt ") || index(s, " arent "))
        }
        function firstword(s,   w) {
            sub(/^[^A-Za-z]+/, "", s)
            w = s
            sub(/[^A-Za-z].*$/, "", w)
            return tolower(w)
        }
        # ---- token extraction, the ONE implementation --------------------
        function emit_tokens(s, bn,   t, tmp) {
            tmp = s
            while (match(tmp, /\[src:[^]]*\]/)) {
                t = substr(tmp, RSTART, RLENGTH); tmp = substr(tmp, RSTART + RLENGTH)
                sub(/^\[src:[ \t]*/, "", t); sub(/[ \t]*\]$/, "", t)
                emit1(t, bn)
            }
            tmp = s
            while (match(tmp, /\[verified:[^]]*\]/)) {
                t = substr(tmp, RSTART, RLENGTH); tmp = substr(tmp, RSTART + RLENGTH)
                sub(/^\[verified:[ \t]*/, "verified:", t); sub(/[ \t]*\]$/, "", t)
                sub(/[ \t\n].*$/, "", t)
                if (t != "verified:") emit1(t, bn)
            }
            tmp = s
            while (match(tmp, /\(ADR-[0-9][0-9][0-9][0-9]*[^)]*\)/)) {
                t = substr(tmp, RSTART, RLENGTH); tmp = substr(tmp, RSTART + RLENGTH)
                sub(/^\(/, "", t); sub(/\)$/, "", t); sub(/[ \t\n].*$/, "", t)
                emit1(t, bn)
            }
            tmp = s
            while (match(tmp, /\(verified [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)/)) {
                t = substr(tmp, RSTART, RLENGTH); tmp = substr(tmp, RSTART + RLENGTH)
                sub(/^\(verified /, "verified:", t); sub(/\)$/, "", t)
                emit1(t, bn)
            }
        }
        # A token may be wrapped across a line break by the authoring tool. The
        # block buffer is multi-line, so the wrap is repaired here rather than
        # dropped: a citation that a formatter split is still a citation, and a
        # record carrying a raw newline would break every downstream reader.
        function emit1(t, bn) {
            gsub(/[ \t]*\n[ \t]*/, " ", t)
            gsub(/[ \t][ \t]*/, " ", t)
            sub(/^[ \t]*/, "", t); sub(/[ \t]*$/, "", t)
            if (t != "") print "T\t" bn "\t" t
        }
        # ---- block buffer ------------------------------------------------
        function reset() { buf = ""; prose = ""; bstart = 0; bkind = ""; nlines = 0 }
        function add(line, isprose) {
            if (bstart == 0) bstart = NR
            buf = buf line "\n"; nlines++
            if (isprose) {
                p = line
                gsub(/`/, " ", p)
                sub(/^[ \t]*[-*+][ \t]+/, "", p)
                sub(/^[ \t]*[0-9][0-9]*[.)][ \t]+/, "", p)
                sub(/^[ \t]*>[ \t]*/, "", p)
                gsub(/\|/, " ", p)
                gsub(/[*_#]/, "", p)
                prose = prose " " p
            }
        }
        function candidate(   w, nw, txt) {
            txt = prose
            gsub(/[ \t][ \t]*/, " ", txt); sub(/^ /, "", txt); sub(/ $/, "", txt)
            if (length(txt) < 30) return 0
            if (txt !~ /[A-Za-z]/) return 0
            nw = split(txt, w, " ")
            if (nw < 4) return 0
            if (verb[firstword(txt)] == 1 && !finite(txt)) return 0
            return 1
        }
        function flush(   c) {
            if (buf == "") { reset(); return }
            blockno++
            c = candidate()
            print "B\t" blockno "\t" bstart "\t" c "\t" (bkind == "" ? "other" : bkind)
            emit_tokens(buf, blockno)
            reset()
        }
        # ---- table run: header and delimiter rows are discarded -----------
        function flush_table(   i, isdelim, hdr) {
            if (trows == 0) return
            hdr = 0
            for (i = 1; i <= trows; i++) {
                isdelim = (trow[i] ~ /^[ \t]*\|?[ \t]*:?-[-: \t|]*\|[-: \t|]*$/)
                if (isdelim) { hdr = i - 1; break }
            }
            for (i = 1; i <= trows; i++) {
                if (hdr > 0 && (i == hdr || i == hdr + 1)) { emit_tokens(trow[i], 0); continue }
                if (trow[i] ~ /^[ \t]*\|?[ \t]*:?-[-: \t|]*\|[-: \t|]*$/) { emit_tokens(trow[i], 0); continue }
                reset(); bkind = "table"; bstart = tline[i]; add(trow[i], 1)
                blockno++
                print "B\t" blockno "\t" bstart "\t" candidate() "\t" bkind
                emit_tokens(trow[i], blockno)
                reset()
            }
            trows = 0
        }
        BEGIN { fm = 0; fence = 0; pending = 0; trows = 0; reset() }
        NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; emit_tokens($0, 0); next }
        fm == 1 {
            emit_tokens($0, 0)
            if ($0 ~ /^---[ \t]*$/ || $0 ~ /^\.\.\.[ \t]*$/) fm = 0
            next
        }
        # inside a fence: everything is block content, nothing is prose
        fence == 1 {
            add($0, 0)
            if ($0 ~ /^[ \t]*(```|~~~)/) { fence = 0 }
            next
        }
        # a fence opening
        /^[ \t]*(```|~~~)/ {
            if (trows > 0) flush_table()
            # rule 2: a fence joins the paragraph immediately preceding it
            if (!(buf != "" && bkind == "para")) { flush(); bkind = "fence" }
            pending = 0
            add($0, 0); fence = 1; next
        }
        /^[ \t]*$/ {
            if (trows > 0) { flush_table(); next }
            if (buf != "") pending = 1
            next
        }
        {
            if (pending == 1) { flush(); pending = 0 }
        }
        # rule 3: a heading alone is never a block
        /^[ \t]*#+[ \t]/ { if (trows > 0) flush_table(); flush(); emit_tokens($0, 0); next }
        # rule 4: tables
        /^[ \t]*\|/ { if (trows == 0) flush(); trows++; trow[trows] = $0; tline[trows] = NR; next }
        {
            if (trows > 0) flush_table()
        }
        # rule 5: lists
        /^[ \t]*([-*+]|[0-9][0-9]*[.)])[ \t]/ {
            flush(); bkind = "list"; add($0, 1); next
        }
        {
            # a continuation line indented under a list item joins that item
            if (bkind == "list" && $0 ~ /^[ \t][ \t]/) { add($0, 1); next }
            if (bkind == "list") { flush() }
            if (bkind == "") bkind = "para"
            add($0, 1)
        }
        END { if (trows > 0) flush_table(); flush() }
    ' "$1" 2>/dev/null
    return 0
}

# bone_block_index <root> <unit-file-list> <outdir>
#
#   Scans every unit file into blocks, resolves each DISTINCT token exactly once,
#   and writes the whole block index to <outdir>. Both cdi.sh and
#   provenance-lint.sh call this, so the corpus has ONE block index and the two
#   tools cannot report different coverage for the same corpus. That divergence
#   is not hypothetical: the file-level linter and the file-level index once
#   reported 1.0000 coverage and dozens of anchoring defects on the same
#   files, on the same day.
#
#   Files written (all tab-separated, all safe to be empty):
#     blocks.tsv     block-id \t candidate(0|1) \t kind        block-id = file:line
#     btok.tsv       block-id \t raw-token
#     resolved.tsv   raw-token \t kind \t source-id
#     anchored.txt   block-id of every block carrying a resolvable token
#     edges.tsv      block-id \t source-id      (self-citations excluded)
#     unresolved.tsv block-id \t raw-token      (a lint finding, not an anchor)
#     candidates.txt block-id of every CANDIDATE block   -> units_total
#     U.txt          candidate AND anchored                -> units_anchored
#     uedges.tsv     edges.tsv restricted to U
#
#   Block 0 of each file holds front-matter and heading tokens: they stay visible
#   to the linter and anchor nothing, because a heading is not a claim.
bone_block_index() {
    _bbi_root="$1"; _bbi_list="$2"; _bbi_out="$3"
    mkdir -p "$_bbi_out" 2>/dev/null || return 0
    : > "$_bbi_out/scan.tsv"
    while IFS= read -r _bbi_u; do
        [ -n "$_bbi_u" ] || continue
        bone_scan_blocks "$_bbi_root/$_bbi_u" | awk -F'\t' -v u="$_bbi_u" '
            $1 == "B" { id[$2] = u ":" $3; print "B\t" id[$2] "\t" $4 "\t" $5; next }
            $1 == "T" && $2 == "0"    { print "T\t" u ":0\t" $3; next }
            $1 == "T" && id[$2] != "" { print "T\t" id[$2] "\t" $3 }
        ' >> "$_bbi_out/scan.tsv"
    done < "$_bbi_list"

    awk -F'\t' '$1 == "B" { print $2 "\t" $3 "\t" $4 }' "$_bbi_out/scan.tsv" > "$_bbi_out/blocks.tsv"
    awk -F'\t' '$1 == "T" { print $2 "\t" $3 }'         "$_bbi_out/scan.tsv" > "$_bbi_out/btok.tsv"
    cut -f2 "$_bbi_out/btok.tsv" 2>/dev/null | sed '/^$/d' | sort -u > "$_bbi_out/rawtok.txt"

    # Resolution touches the filesystem, so it runs once per DISTINCT token, not
    # once per occurrence: a mature corpus repeats each distinct token many times.
    : > "$_bbi_out/resolved.tsv"
    while IFS= read -r _bbi_t; do
        [ -n "$_bbi_t" ] || continue
        printf '%s\t%s\n' "$_bbi_t" "$(bone_resolve_src "$_bbi_root" "$_bbi_t")" >> "$_bbi_out/resolved.tsv"
    done < "$_bbi_out/rawtok.txt"

    : > "$_bbi_out/anchored.txt"; : > "$_bbi_out/edges.tsv"; : > "$_bbi_out/unresolved.tsv"
    awk -F'\t' -v anchoredf="$_bbi_out/anchored.txt" -v edgesf="$_bbi_out/edges.tsv" \
               -v unresf="$_bbi_out/unresolved.tsv" '
        NR == FNR { kind[$1] = $2; src[$1] = $3; next }
        {
            b = $1; t = $2; k = kind[t]
            if (k == "internal" || k == "external") {
                own = b; sub(/:[0-9]*$/, "", own)
                print b > anchoredf
                # D-C.4: a unit never decays itself, so its own file is not in src(u).
                if (src[t] != own) print b "\t" src[t] > edgesf
            } else if (k == "time") {
                print b > anchoredf            # anchored in time, not to a file
            } else if (k == "placeholder") {
                next                           # grammar documentation, not a claim
            } else {
                print b "\t" t > unresf
            }
        }
    ' "$_bbi_out/resolved.tsv" "$_bbi_out/btok.tsv" 2>/dev/null || :

    sort -u "$_bbi_out/edges.tsv"    -o "$_bbi_out/edges.tsv"    2>/dev/null || :
    sort -u "$_bbi_out/anchored.txt" -o "$_bbi_out/anchored.txt" 2>/dev/null || :

    awk -F'\t' '$2 == "1" { print $1 }' "$_bbi_out/blocks.tsv" 2>/dev/null | sort -u \
        > "$_bbi_out/candidates.txt"
    # `NR == FNR` reads an EMPTY first file as the second one, so both joins below
    # are guarded. On a corpus where nothing is anchored the unguarded form yields
    # an empty orphan set, which is the most broken corpus possible scoring
    # perfectly. Empty inputs are the normal state of a fresh scaffold, not an
    # edge case.
    if [ -s "$_bbi_out/candidates.txt" ] && [ -s "$_bbi_out/anchored.txt" ]; then
        awk 'NR == FNR { c[$0] = 1; next } ($0 in c) { print }' \
            "$_bbi_out/candidates.txt" "$_bbi_out/anchored.txt" 2>/dev/null | sort -u \
            > "$_bbi_out/U.txt"
    else
        : > "$_bbi_out/U.txt"
    fi
    # Edges restricted to U. A non-candidate block (a procedure step, a code
    # caption) may carry a token, but it is not a claim about the world and may
    # not enter an index whose denominator is claims.
    if [ -s "$_bbi_out/U.txt" ] && [ -s "$_bbi_out/edges.tsv" ]; then
        awk -F'\t' 'NR == FNR { u[$0] = 1; next } ($1 in u) { print }' \
            "$_bbi_out/U.txt" "$_bbi_out/edges.tsv" 2>/dev/null > "$_bbi_out/uedges.tsv"
    else
        : > "$_bbi_out/uedges.tsv"
    fi
    for _bbi_f in blocks btok resolved anchored edges unresolved candidates U uedges; do
        [ -f "$_bbi_out/$_bbi_f.tsv" ] || [ -f "$_bbi_out/$_bbi_f.txt" ] || : > "$_bbi_out/$_bbi_f.txt"
    done
    return 0
}

# bone_extract_tokens <file> -> one raw token per line, deduplicated.
# A thin projection of bone_scan_blocks so that the token grammar exists once.
bone_extract_tokens() {
    [ -r "$1" ] || return 0
    bone_scan_blocks "$1" | awk -F'\t' '$1 == "T" && $3 != "" { print $3 }' | sort -u
    # MUST return 0. Under `set -o pipefail` a scan that legitimately matches
    # nothing fails the whole pipeline, and every caller writes this output with
    # `> file`, so a non-zero status silently produced an EMPTY token file and a
    # corpus-wide coverage of zero. Found during implementation; kept as a
    # cautionary comment because it is invisible without a test.
    return 0
}

# bone_token_clean <token> -> normalised token, or empty if it is a placeholder.
bone_token_clean() {
    _btc=$1
    case "$_btc" in *'<'*|*'>'*|*'...'*) return 0 ;; esac
    _btc=${_btc%% §*}          # drop a section suffix: "docs/x.md §15"
    _btc=${_btc%%,*}           # drop anything after a comma: multi-cite in one token
    _btc=${_btc%% *}           # drop a trailing free-text tail
    _btc=${_btc%%#*}           # drop #AmN
    _btc=${_btc%%@*}           # drop @date / @version
    while :; do                # drop trailing punctuation
        case "$_btc" in
            *.|*,|*\;|*:|*\)) _btc=${_btc%?} ;;
            *) break ;;
        esac
    done
    # Drop a trailing :LINE or :LINE-LINE or :LINE,LINE locator.
    _btc=$(printf '%s' "$_btc" | sed -E 's/:[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$//')
    case "$_btc" in
        ADR-*[!0-9-]*|adr/*[!0-9-]*) return 0 ;;   # ADR-NNNN and friends
    esac
    printf '%s\n' "$_btc"
}

# bone_resolve_src <root> <token> -> one line: "<kind><TAB><source-id>"
#
#   kind = internal     resolved to a file in this repo; id is a repo-relative path
#        | external     resolved to <alias>:<path>, alias declared in MANIFEST
#        | time         a verified: marker (anchors a claim, but not to a file)
#        | placeholder  grammar documentation, not a claim; id empty
#        | unknown      resolves to nothing; id empty. This is a lint finding.
#
# The kind is RETURNED, not stashed in a variable, because every caller reads
# this function through `$(...)` and a variable set inside a command
# substitution dies with the subshell. That defect cost a debugging cycle
# during implementation and is exactly the class of bug BONE is about.
bone_resolve_src() {
    _brs_root="$1"
    _brs_tok=$(bone_token_clean "$2")
    [ -n "$_brs_tok" ] || { printf 'placeholder\t\n'; return 0; }

    case "$_brs_tok" in
        verified:*) printf 'time\t\n'; return 0 ;;
        /*|../*)    printf 'unknown\t\n'; return 0 ;;   # absolute/escaping: never provenance
        ADR-[0-9]*|adr/[0-9]*)
            _brs_n=${_brs_tok#adr/}; _brs_n=${_brs_n#ADR-}
            for _brs_c in "$_brs_root"/docs/adr/"$_brs_n"-*.md "$_brs_root"/docs/adr/"$_brs_n".md; do
                if [ -f "$_brs_c" ]; then
                    printf 'internal\t%s\n' "$(bone_relpath "$_brs_c" "$_brs_root")"; return 0
                fi
            done
            printf 'unknown\t\n'; return 0 ;;
        state/*|contract/*|contracts/*|domain/*)
            case "$_brs_tok" in
                contracts/*) _brs_p="docs/${_brs_tok}" ;;
                contract/*)  _brs_p="docs/contracts/${_brs_tok#contract/}" ;;
                *)           _brs_p="docs/${_brs_tok}" ;;
            esac
            case "$_brs_p" in *.md) : ;; *) _brs_p="$_brs_p.md" ;; esac
            if [ -f "$_brs_root/$_brs_p" ]; then
                printf 'internal\t%s\n' "$_brs_p"
            else
                printf 'unknown\t\n'
            fi
            return 0 ;;
    esac

    # `repo/<alias>:<path>` is the normative external form; a bare
    # `<alias>:<path>` is tolerated as a legacy spelling and resolves the same
    # way, so a corpus written before the prefix was fixed is not reported as
    # broken. Normalising the spelling is a curation task, not a lint failure.
    _brs_tok=${_brs_tok#repo/}
    case "$_brs_tok" in
        *:*)
            _brs_alias=${_brs_tok%%:*}
            _brs_rest=${_brs_tok#*:}
            if bone_alias_known "$_brs_alias"; then
                printf 'external\t%s:%s\n' "$_brs_alias" "$_brs_rest"
            else
                printf 'unknown\t\n'
            fi
            return 0 ;;
    esac

    if [ -e "$_brs_root/$_brs_tok" ]; then
        printf 'internal\t%s\n' "$_brs_tok"
        return 0
    fi

    # An unqualified path: it looks like a file, it is not in this repository,
    # and it names no repository alias. Under the constitution's grammar it is
    # ambiguous rather than absent - more than one code repo can contain a
    # `config/` directory - so it gets its own kind and its own remediation
    # ("add the repo alias"), instead of being buried in the unresolved pile.
    case "$_brs_tok" in
        */*|*.py|*.ts|*.tsx|*.js|*.yml|*.yaml|*.json|*.toml|*.cfg|*.md|*.sh|*.mdc)
            printf 'unqualified\t%s\n' "$_brs_tok"; return 0 ;;
    esac
    printf 'unknown\t\n'
    return 0
}

# ---------------------------------------------------------------------------
# 7. JSON emission (no jq dependency).
# ---------------------------------------------------------------------------
bone_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g'
}

bone_json_array_file() {
    if [ ! -s "$1" ]; then printf '[]'; return 0; fi
    awk '
        { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\"%s\"", (NR > 1 ? "," : "["), $0 }
        END { printf "]" }
    ' "$1"
}

# bone_pct <numerator> <denominator> -> ratio to 4dp, or the literal null
bone_pct() {
    if [ "${2:-0}" -le 0 ] 2>/dev/null; then printf 'null'; return 0; fi
    awk -v n="$1" -v d="$2" 'BEGIN { printf "%.4f", n / d }'
}
