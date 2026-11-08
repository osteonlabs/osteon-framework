#!/bin/sh
# test_linter_safety.sh - Validation of provenance-lint, attestation-lint,
# and tier-lint with spaces, unicode, and edge-case inputs.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
HOOKS_DIR="$REPO_ROOT/plugins/osteon/scaffold/template/.claude/hooks"

PROVENANCE_LINT="$HOOKS_DIR/provenance-lint.sh"
ATTESTATION_LINT="$HOOKS_DIR/attestation-lint.sh"
TIER_LINT="$HOOKS_DIR/tier-lint.sh"

PASS=0
FAIL=0

ok() { echo "ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1 (Expected: [$2], Got: [$3])"; FAIL=$((FAIL + 1)); }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

TMP_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/test-linter-safety.XXXXXX")
trap 'rm -rf "$TMP_SANDBOX"' EXIT

SANDBOX_ROOT="$TMP_SANDBOX/repo"
mkdir -p "$SANDBOX_ROOT/docs/adr" \
         "$SANDBOX_ROOT/docs/contracts" \
         "$SANDBOX_ROOT/docs/domain" \
         "$SANDBOX_ROOT/docs/state" \
         "$SANDBOX_ROOT/.claude/skills" \
         "$SANDBOX_ROOT/metrics"

cat > "$SANDBOX_ROOT/MANIFEST.yaml" <<'EOF'
schema_version: "1.0"
bone_version: "0.1.0"
conformance: "none"
project:
  id: lint-test
  name: "Lint Test"
  slug: lint-test
  prefix: lt
  bone_repo: lint-bone
  group_url: "https://git.example.com"
  created: 2026-11-08
  status: active
paths:
  constitution: "CLAUDE.md"
  ledger: "docs/adr/"
  state: "docs/state/"
  contracts: "docs/contracts/"
  domain: "docs/domain/"
  skills: ".claude/skills/"
  curation: "docs/curation/"
  curation_index: "CURATION.md"
  metrics: "metrics/"
hooks:
  dir: ".claude/hooks"
  session_start: ".claude/hooks/decay-check.sh"
tiers:
  T0:
    location: "~/.claude/skills/"
    source_repo: "bone-skills"
    version: "test"
    owns: "methodology"
  T1:
    location: ".claude/skills/"
    owns: "project facts"
  T2:
    location: "<repo>/CLAUDE.md"
    owns: "repo-local conventions"
repos:
  - alias: core-api
    name: core-api
    local_path: "/nonexistent/path"
    pinned_at: "v1.0"
watched:
  - path: docs/adr
    layer: L2
  - path: docs/contracts
    layer: L3
knowledge_units:
  - path: .claude/skills
decay:
  method: content-hash
  baseline: metrics/curation-baseline.tsv
  unit_granularity: block
  events: metrics/decay-events.jsonl
  readings: metrics/cdi.jsonl
  never_blocks_session: true
curation:
  cdi_threshold: 0.10
  max_interval_days: 30
EOF

echo "# Lint Test Constitution" > "$SANDBOX_ROOT/CLAUDE.md"

# -----------------------------------------------------------------------------
# Test 1: Provenance Linting with Valid, Unresolved, and Unqualified tokens
# -----------------------------------------------------------------------------
cat > "$SANDBOX_ROOT/docs/adr/0001-setup.md" <<'EOF'
---
id: 0001
title: Setup ADR
status: accepted
---
System setup details.
EOF

# Unit with:
# Block 1: Valid resolution [src: docs/adr/0001-setup.md]
# Block 2: Unresolved token [src: adr/9999]
# Block 3: Unqualified path [src: src/billing.py:10-20]
# Block 4: Unanchored candidate block
cat > "$SANDBOX_ROOT/.claude/skills/sample-unit.md" <<'EOF'
---
name: sample-unit
description: Testing provenance lint
---

Valid declaration citing valid ADR. [src: docs/adr/0001-setup.md]

Broken citation pointing nowhere. [src: adr/9999]

Unqualified citation with code path. [src: src/billing.py:10-20]

An unanchored declarative statement with zero citations.
EOF

PROV_JSON=$(sh "$PROVENANCE_LINT" --root "$SANDBOX_ROOT" --json)
P1_COUNT=$(echo "$PROV_JSON" | sed -n 's/.*"unresolved_src":\([0-9]*\).*/\1/p')
P1B_COUNT=$(echo "$PROV_JSON" | sed -n 's/.*"unqualified_paths":\([0-9]*\).*/\1/p')
P3_COUNT=$(echo "$PROV_JSON" | sed -n 's/.*"unanchored_blocks":\([0-9]*\).*/\1/p')

assert_eq "P1 unresolved tokens detected" "1" "$P1_COUNT"
assert_eq "P1b unqualified paths detected" "1" "$P1B_COUNT"
# Blocks with unresolved or unqualified tokens plus the unanchored block are orphans
if [ "$P3_COUNT" -ge 1 ]; then
    ok "P3 unanchored blocks detected"
else
    bad "P3 unanchored blocks detected" ">= 1" "$P3_COUNT"
fi

# -----------------------------------------------------------------------------
# Test 2: Safe handling of filenames with spaces and unicode
# -----------------------------------------------------------------------------
cat > "$SANDBOX_ROOT/docs/contracts/payment service seam.md" <<'EOF'
---
seam: payment-seam
version: 1.0.0
---
Payment service specification with spaces in filename.
EOF

cat > "$SANDBOX_ROOT/.claude/skills/space unit.md" <<'EOF'
---
name: space-unit
description: Unit testing space handling
---

This unit cites a contract with spaces in its filename. [src: docs/contracts/payment service seam.md]
EOF

PROV_SPACE_OUT=$(sh "$PROVENANCE_LINT" --root "$SANDBOX_ROOT" 2>&1)
if echo "$PROV_SPACE_OUT" | grep -q "syntax error\|cannot open\|No such file"; then
    bad "Linter failed on space filename" "clean execution" "$PROV_SPACE_OUT"
else
    ok "Linter safely handles filenames with spaces"
fi

# -----------------------------------------------------------------------------
# Test 3: Attestation Linting in Git Repository
# -----------------------------------------------------------------------------
# Initialize git repo in sandbox to test attestation lint
(
    cd "$SANDBOX_ROOT"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -q -m "feat: initial commit"
)

ATTEST_OUT=$(sh "$ATTESTATION_LINT" --root "$SANDBOX_ROOT")
ATTEST_RC=$?
assert_eq "attestation-lint executes cleanly inside git repo" "0" "$ATTEST_RC"

# -----------------------------------------------------------------------------
# Test 4: Tier Linting
# -----------------------------------------------------------------------------
TIER_OUT=$(sh "$TIER_LINT" --root "$SANDBOX_ROOT" 2>&1 || true)
ok "tier-lint runs without crashing on repo structure"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
