#!/bin/sh
# test_cdi_math.sh - Mathematical boundary & output verification for cdi.sh.
# Asserts:
#   1. Unsealed state yields state="uninitialised", cdi=null
#   2. Sealing produces a baseline file and resets curation clock
#   3. Clean state yields cdi=0.0000, units_decayed=0
#   4. Partial decay correctly calculates CDI = |U_decayed| / |U_anchored|
#   5. Total decay yields cdi=1.0000
#   6. Unavailable external repos are reported in sources_unavailable without fabricating decay
#   7. Formats (--json, --kv, --summary, --blocks) function correctly
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CDI_BIN="$REPO_ROOT/plugins/osteon/scaffold/template/.claude/hooks/cdi.sh"

PASS=0
FAIL=0

ok() { echo "ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1 (Expected: [$2], Got: [$3])"; FAIL=$((FAIL + 1)); }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

TMP_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/test-cdi-math.XXXXXX")
trap 'rm -rf "$TMP_SANDBOX"' EXIT

# Initialize a miniature BONE repo structure
SANDBOX_ROOT="$TMP_SANDBOX/repo"
mkdir -p "$SANDBOX_ROOT/docs/adr" \
         "$SANDBOX_ROOT/docs/contracts" \
         "$SANDBOX_ROOT/docs/domain" \
         "$SANDBOX_ROOT/docs/state" \
         "$SANDBOX_ROOT/.claude/skills" \
         "$SANDBOX_ROOT/metrics"

# Create minimal MANIFEST.yaml
cat > "$SANDBOX_ROOT/MANIFEST.yaml" <<'EOF'
schema_version: "1.0"
bone_version: "0.1.0"
conformance: "none"
project:
  id: test-proj
  name: "Test Project"
  slug: test-proj
  prefix: test
  bone_repo: test-bone
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
    owns: "the methodology"
  T1:
    location: ".claude/skills/"
    owns: "project facts"
  T2:
    location: "<repo>/CLAUDE.md"
    owns: "repo-local conventions"
repos:
  - alias: auth-svc
    name: auth-service
    local_path: "/nonexistent/external/path"
    pinned_at: "v1.0"
watched:
  - path: docs/adr
    layer: L2
  - path: docs/contracts
    layer: L3
  - path: repo/auth-svc:src/auth.py
    layer: code
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

# Create constitution
echo "# Test Project" > "$SANDBOX_ROOT/CLAUDE.md"

# Create watched source 1: ADR
cat > "$SANDBOX_ROOT/docs/adr/0001-storage.md" <<'EOF'
---
id: 0001
title: Use Postgres
status: accepted
---
We store all user data in PostgreSQL.
EOF

# Create watched source 2: Contract
cat > "$SANDBOX_ROOT/docs/contracts/billing.md" <<'EOF'
---
seam: billing-api
version: 1.0.0
---
Billing contract specification.
EOF

# Create a knowledge unit that cites both internal sources and the external repo
cat > "$SANDBOX_ROOT/.claude/skills/billing-guide.md" <<'EOF'
---
name: billing-guide
description: Guide to billing operations
---

The billing subsystem relies on Postgres for state. [src: docs/adr/0001-storage.md]

All invoice calls must follow the contract specification. [src: docs/contracts/billing.md]

Authentication tokens are verified by the auth service. [src: repo/auth-svc:src/auth.py]
EOF

# -----------------------------------------------------------------------------
# Test 1: Uninitialised State (no baseline exists yet)
# -----------------------------------------------------------------------------
READING_INIT=$(sh "$CDI_BIN" --root "$SANDBOX_ROOT")
STATE_INIT=$(echo "$READING_INIT" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
CDI_INIT=$(echo "$READING_INIT" | sed -n 's/.*"cdi":\([^,}]*\).*/\1/p')
assert_eq "Uninitialised state is uninitialised" "uninitialised" "$STATE_INIT"
assert_eq "Uninitialised CDI is null" "null" "$CDI_INIT"

# -----------------------------------------------------------------------------
# Test 2: Seal the Baseline
# -----------------------------------------------------------------------------
sh "$CDI_BIN" --seal --root "$SANDBOX_ROOT" >/dev/null
if [ -f "$SANDBOX_ROOT/metrics/curation-baseline.tsv" ]; then
    ok "Baseline file created by --seal"
else
    bad "Baseline file created by --seal" "file exists" "missing"
fi

# -----------------------------------------------------------------------------
# Test 3: Clean State Measurement (Post-seal, no changes)
# -----------------------------------------------------------------------------
READING_CLEAN=$(sh "$CDI_BIN" --root "$SANDBOX_ROOT")
STATE_CLEAN=$(echo "$READING_CLEAN" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
CDI_CLEAN=$(echo "$READING_CLEAN" | sed -n 's/.*"cdi":\([^,}]*\).*/\1/p')
UNITS_DECAYED_CLEAN=$(echo "$READING_CLEAN" | sed -n 's/.*"units_decayed":\([0-9]*\).*/\1/p')
SOURCES_CHANGED_CLEAN=$(echo "$READING_CLEAN" | sed -n 's/.*"sources_changed":\([0-9]*\).*/\1/p')
SOURCES_UNAVAIL=$(echo "$READING_CLEAN" | sed -n 's/.*"sources_unavailable":\([0-9]*\).*/\1/p')

assert_eq "Clean state is measured" "measured" "$STATE_CLEAN"
assert_eq "Clean CDI is 0.0000" "0.0000" "$CDI_CLEAN"
assert_eq "Clean units_decayed is 0" "0" "$UNITS_DECAYED_CLEAN"
assert_eq "Clean sources_changed is 0" "0" "$SOURCES_CHANGED_CLEAN"
assert_eq "External unavailable source is counted without fabricating decay" "1" "$SOURCES_UNAVAIL"

# -----------------------------------------------------------------------------
# Test 4: Partial Decay (Modify 1 of 2 internal watched sources)
# -----------------------------------------------------------------------------
echo "Modification: Postgres 16 required." >> "$SANDBOX_ROOT/docs/adr/0001-storage.md"

READING_PARTIAL=$(sh "$CDI_BIN" --root "$SANDBOX_ROOT")
CDI_PARTIAL=$(echo "$READING_PARTIAL" | sed -n 's/.*"cdi":\([^,}]*\).*/\1/p')
DECAYED_PARTIAL=$(echo "$READING_PARTIAL" | sed -n 's/.*"units_decayed":\([0-9]*\).*/\1/p')
ANCHORED_PARTIAL=$(echo "$READING_PARTIAL" | sed -n 's/.*"units_anchored":\([0-9]*\).*/\1/p')

assert_eq "Partial decay units_decayed is 1" "1" "$DECAYED_PARTIAL"
assert_eq "Total units_anchored is 3" "3" "$ANCHORED_PARTIAL"
# Expected CDI: 1 / 3 = 0.3333
assert_eq "Partial CDI mathematically matches 1 / 3 = 0.3333" "0.3333" "$CDI_PARTIAL"

# -----------------------------------------------------------------------------
# Test 5: Two of Three Decay
# -----------------------------------------------------------------------------
echo "Modification: Billing wire payload changed." >> "$SANDBOX_ROOT/docs/contracts/billing.md"

READING_TWO=$(sh "$CDI_BIN" --root "$SANDBOX_ROOT")
CDI_TWO=$(echo "$READING_TWO" | sed -n 's/.*"cdi":\([^,}]*\).*/\1/p')
DECAYED_TWO=$(echo "$READING_TWO" | sed -n 's/.*"units_decayed":\([0-9]*\).*/\1/p')

assert_eq "Two decayed blocks is 2" "2" "$DECAYED_TWO"
# Expected CDI: 2 / 3 = 0.6667
assert_eq "Two decayed CDI mathematically matches 2 / 3 = 0.6667" "0.6667" "$CDI_TWO"

# -----------------------------------------------------------------------------
# Test 5b: Full Decay (CDI = 1.0000 when all anchored units decay)
# -----------------------------------------------------------------------------
# Remove the external citation so units_anchored becomes 2, both of which are decayed
cat > "$SANDBOX_ROOT/.claude/skills/billing-guide.md" <<'EOF'
---
name: billing-guide
description: Guide to billing operations
---

The billing subsystem relies on Postgres for state. [src: docs/adr/0001-storage.md]

All invoice calls must follow the contract specification. [src: docs/contracts/billing.md]
EOF

READING_FULL=$(sh "$CDI_BIN" --root "$SANDBOX_ROOT")
CDI_FULL=$(echo "$READING_FULL" | sed -n 's/.*"cdi":\([^,}]*\).*/\1/p')
DECAYED_FULL=$(echo "$READING_FULL" | sed -n 's/.*"units_decayed":\([0-9]*\).*/\1/p')
ANCHORED_FULL=$(echo "$READING_FULL" | sed -n 's/.*"units_anchored":\([0-9]*\).*/\1/p')

assert_eq "Full decay units_anchored is 2" "2" "$ANCHORED_FULL"
assert_eq "Full decay units_decayed is 2" "2" "$DECAYED_FULL"
assert_eq "Full decay CDI mathematically matches 2 / 2 = 1.0000" "1.0000" "$CDI_FULL"

# -----------------------------------------------------------------------------
# Test 6: Output Formats (--kv, --summary, --blocks)
# -----------------------------------------------------------------------------
KV_OUT=$(sh "$CDI_BIN" --kv --root "$SANDBOX_ROOT")
KV_STATE=$(echo "$KV_OUT" | awk -F= '$1=="state"{print $2}')
assert_eq "--kv state output" "measured" "$KV_STATE"

SUMMARY_OUT=$(sh "$CDI_BIN" --summary --root "$SANDBOX_ROOT")
if echo "$SUMMARY_OUT" | grep -q "CDI"; then
    ok "--summary output contains CDI report"
else
    bad "--summary output contains CDI report" "contains 'CDI'" "$SUMMARY_OUT"
fi

BLOCKS_OUT=$(sh "$CDI_BIN" --blocks --root "$SANDBOX_ROOT")
if echo "$BLOCKS_OUT" | grep -q "billing-guide.md"; then
    ok "--blocks lists candidate block audit trail"
else
    bad "--blocks lists candidate block audit trail" "contains 'billing-guide.md'" "$BLOCKS_OUT"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
