#!/bin/sh
# telemetry.sh - OSTEON Telemetry & Token Metering Hook.
# BONE template version: 0.1.2
#
# Emits standardized JSONL telemetry and cost attribution events to
# .osteon/telemetry/events.jsonl for Agent-as-a-Service (AaaS) observability.
#
# USAGE
#   telemetry.sh [record|summary|--help]
#
# DEPENDENCIES: POSIX sh + bone-lib.sh. Zero external tools.
# ---------------------------------------------------------------------------

set -u
(set -o pipefail) 2>/dev/null && set -o pipefail || true

BONE_SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || exit 0
export BONE_SCRIPT_DIR

# shellcheck source=bone-lib.sh
. "$BONE_SCRIPT_DIR/bone-lib.sh" 2>/dev/null || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    ROOT=$(dirname "$(dirname "$BONE_SCRIPT_DIR")")
fi

ACTION="${1:-record}"

case "$ACTION" in
    -h|--help)
        cat <<'EOF'
telemetry.sh - OSTEON Telemetry & Token Metering Hook

USAGE
  telemetry.sh [record]     Record a telemetry event for the current session state
  telemetry.sh summary      Print aggregated telemetry summary for the current tenant
  telemetry.sh --help
EOF
        exit 0
        ;;

    summary)
        LOG_FILE="$ROOT/.osteon/telemetry/events.jsonl"
        if [ ! -f "$LOG_FILE" ]; then
            echo "No telemetry events recorded yet at $LOG_FILE"
            exit 0
        fi
        echo "========================================================================"
        echo "OSTEON Telemetry & Token Metering Summary"
        echo "Repository: $ROOT"
        echo "Tenant:     $(bone_tenant_id "$ROOT")"
        echo "========================================================================"
        TOTAL_EVENTS=$(wc -l < "$LOG_FILE" | tr -d ' ')
        echo "Total Logged Sessions: $TOTAL_EVENTS"
        tail -n 5 "$LOG_FILE"
        exit 0
        ;;

    record)
        START_TIME=$(date +%s%N 2>/dev/null || date +%s)
        TENANT_ID=$(bone_tenant_id "$ROOT")
        SESSION_ID="${BONE_SESSION_ID:-sess_$(date +%s)}"
        TIMESTAMP=$(bone_now_utc)

        # Quick CDI reading (use cached or fast-path if available)
        CDI_VAL="0.0000"
        UNITS_DECAYED=0
        STATUS="clean"

        CDI_SH="$BONE_SCRIPT_DIR/cdi.sh"
        if [ -f "$CDI_SH" ]; then
            KV=$(sh "$CDI_SH" --kv 2>/dev/null || true)
            if [ -n "$KV" ]; then
                _cdi=$(printf '%s\n' "$KV" | sed -n 's/^cdi=//p' | head -n 1)
                _decayed=$(printf '%s\n' "$KV" | sed -n 's/^units_decayed=//p' | head -n 1)
                _state=$(printf '%s\n' "$KV" | sed -n 's/^state=//p' | head -n 1)
                [ -n "$_cdi" ] && [ "$_cdi" != "null" ] && CDI_VAL="$_cdi"
                [ -n "$_decayed" ] && UNITS_DECAYED="$_decayed"
                [ -n "$_state" ] && STATUS="$_state"
            fi
        fi

        # Estimate injected BONE knowledge tokens (~4 chars per token across active skills and contracts)
        TOTAL_CHARS=0
        if [ -d "$ROOT/.claude/skills" ]; then
            for f in "$ROOT/.claude/skills"/*.md; do
                [ -f "$f" ] || continue
                _sz=$(wc -c < "$f" 2>/dev/null || echo 0)
                TOTAL_CHARS=$((TOTAL_CHARS + _sz))
            done
        fi
        if [ -d "$ROOT/docs/contracts" ]; then
            for f in "$ROOT/docs/contracts"/*.md; do
                [ -f "$f" ] || continue
                _sz=$(wc -c < "$f" 2>/dev/null || echo 0)
                TOTAL_CHARS=$((TOTAL_CHARS + _sz))
            done
        fi
        ESTIMATED_TOKENS=$((TOTAL_CHARS / 4))

        END_TIME=$(date +%s%N 2>/dev/null || date +%s)
        # Calculate latency in ms (handle fallback if %N unsupported)
        if [ "$END_TIME" -gt 1000000000000000 2>/dev/null ]; then
            LATENCY_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        else
            LATENCY_MS=15
        fi

        OUT_DIR="$ROOT/.osteon/telemetry"
        mkdir -p "$OUT_DIR" 2>/dev/null || true
        OUT_FILE="$OUT_DIR/events.jsonl"

        JSON_EVENT=$(printf '{"timestamp":"%s","session_id":"%s","tenant_id":"%s","bone_tokens_injected":%d,"cdi_score":%s,"decayed_anchors_count":%d,"latency_ms":%d,"status":"%s"}' \
            "$TIMESTAMP" "$SESSION_ID" "$TENANT_ID" "$ESTIMATED_TOKENS" "$CDI_VAL" "$UNITS_DECAYED" "$LATENCY_MS" "$STATUS")

        printf '%s\n' "$JSON_EVENT" >> "$OUT_FILE"
        ;;
esac

exit 0
