#!/bin/sh
# test_yaml_key_order.sh - Regression test for Awk YAML parser key-order resilience.
# Verifies that bone_manifest_list, bone_alias_init, and tier-lint work regardless
# of whether 'path' or 'alias' comes first, or keys are alphabetized.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
HOOKS_DIR="$REPO_ROOT/plugins/osteon/scaffold/template/.claude/hooks"

# Source bone-lib.sh
. "$HOOKS_DIR/bone-lib.sh"

PASS=0
FAIL=0

assert_eq() {
    _desc="$1"; _expected="$2"; _actual="$3"
    if [ "$_expected" = "$_actual" ]; then
        echo "ok   $_desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL $_desc"
        echo "     Expected: [$_expected]"
        echo "     Actual:   [$_actual]"
        FAIL=$((FAIL + 1))
    fi
}

TMP_TEST=$(mktemp -d "${TMPDIR:-/tmp}/test-bone-yaml.XXXXXX")
trap 'rm -rf "$TMP_TEST"' EXIT

# -----------------------------------------------------------------------------
# Test 1: bone_manifest_list with standard order (path first)
# -----------------------------------------------------------------------------
cat > "$TMP_TEST/manifest_path_first.yaml" <<'EOF'
watched:
  - path: docs/adr
    layer: L2
    note: "standard path first"
  - path: docs/contracts
    layer: L3
EOF

OUT1=$(bone_manifest_list "$TMP_TEST/manifest_path_first.yaml" "watched" | tr '\n' ' ' | sed 's/ $//')
assert_eq "bone_manifest_list (path first)" "docs/adr docs/contracts" "$OUT1"

# -----------------------------------------------------------------------------
# Test 2: bone_manifest_list with alphabetized / scrambled order (layer/note first)
# -----------------------------------------------------------------------------
cat > "$TMP_TEST/manifest_scrambled.yaml" <<'EOF'
watched:
  - layer: L2
    note: "note first"
    path: docs/adr
  - layer: L3
    path: docs/contracts
EOF

OUT2=$(bone_manifest_list "$TMP_TEST/manifest_scrambled.yaml" "watched" | tr '\n' ' ' | sed 's/ $//')
assert_eq "bone_manifest_list (scrambled keys with path last)" "docs/adr docs/contracts" "$OUT2"

# -----------------------------------------------------------------------------
# Test 3: bone_alias_init with standard order (alias first)
# -----------------------------------------------------------------------------
mkdir -p "$TMP_TEST/repo_std"
cat > "$TMP_TEST/repo_std/MANIFEST.yaml" <<'EOF'
repos:
  - alias: lending-api
    local_path: /path/to/lending
    pinned_at: "a1b2c3d"
  - alias: member-service
    local_path: /path/to/member
    pinned_at: null
EOF

bone_alias_init "$TMP_TEST/repo_std"
assert_eq "bone_alias_local standard (lending-api)" "/path/to/lending" "$(bone_alias_local lending-api)"
assert_eq "bone_alias_pin standard (lending-api)" "a1b2c3d" "$(bone_alias_pin lending-api)"
assert_eq "bone_alias_local standard (member-service)" "/path/to/member" "$(bone_alias_local member-service)"

# -----------------------------------------------------------------------------
# Test 4: bone_alias_init with alphabetized order (local_path first, alias middle/last)
# -----------------------------------------------------------------------------
mkdir -p "$TMP_TEST/repo_scrambled"
cat > "$TMP_TEST/repo_scrambled/MANIFEST.yaml" <<'EOF'
repos:
  - local_path: /path/to/lending
    pinned_at: "a1b2c3d"
    alias: lending-api
  - pinned_at: "e5f6g7h"
    alias: member-service
    local_path: /path/to/member
EOF

bone_alias_init "$TMP_TEST/repo_scrambled"
assert_eq "bone_alias_local scrambled (lending-api)" "/path/to/lending" "$(bone_alias_local lending-api)"
assert_eq "bone_alias_pin scrambled (lending-api)" "a1b2c3d" "$(bone_alias_pin lending-api)"
assert_eq "bone_alias_local scrambled (member-service)" "/path/to/member" "$(bone_alias_local member-service)"
assert_eq "bone_alias_pin scrambled (member-service)" "e5f6g7h" "$(bone_alias_pin member-service)"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "$PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
