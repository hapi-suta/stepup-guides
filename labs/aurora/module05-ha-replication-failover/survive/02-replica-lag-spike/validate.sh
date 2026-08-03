#!/usr/bin/env bash
# SURVIVE 02 - validate.sh
# Verifies that replica lag has recovered to a healthy level

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

log_section "SURVIVE 02 - Replica Lag Spike Validation"

# -------------------------------------------------------
# Check 1: Writer endpoint is reachable
# -------------------------------------------------------
log_info "Check 1: Writer endpoint is reachable"
if test_db_connection "$AURORA_WRITER_ENDPOINT"; then
    log_success "PASS: Writer endpoint is reachable"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to writer endpoint"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Reader endpoint is reachable
# -------------------------------------------------------
log_info "Check 2: Reader endpoint is reachable"
if test_db_connection "$AURORA_READER_ENDPOINT"; then
    log_success "PASS: Reader endpoint is reachable"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to reader endpoint"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: Replica lag is under 2 seconds
# -------------------------------------------------------
log_info "Check 3: Replica lag is under 2000ms"
LAG_SQL=$(run_query "$AURORA_READER_ENDPOINT" \
    "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int;")

record_result "02-replica-lag-spike" "post_incident_lag_s" "${LAG_SQL:-unknown}"

if [ -n "$LAG_SQL" ] && [ "$LAG_SQL" -lt 2 ] 2>/dev/null; then
    log_success "PASS: Replica lag is ${LAG_SQL}s (under 2 seconds)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Replica lag is ${LAG_SQL:-unknown}s (expected under 2)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: Reader is actually a replica
# -------------------------------------------------------
log_info "Check 4: Reader endpoint serves a replica"
IS_RECOVERY=$(run_query "$AURORA_READER_ENDPOINT" "SELECT pg_is_in_recovery();")
if [ "$IS_RECOVERY" = "t" ]; then
    log_success "PASS: Reader is serving a replica (pg_is_in_recovery = t)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_warn "WARN: Reader may be serving the writer (pg_is_in_recovery = $IS_RECOVERY)"
fi

# -------------------------------------------------------
# Check 5: No active heavy write queries
# -------------------------------------------------------
log_info "Check 5: No active heavy write queries on writer"
ACTIVE_QUERIES=$(run_query "$AURORA_WRITER_ENDPOINT" \
    "SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%';")

if [ "${ACTIVE_QUERIES:-0}" -le 5 ]; then
    log_success "PASS: Active query count is normal ($ACTIVE_QUERIES)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_warn "WARN: $ACTIVE_QUERIES active queries. Write load may still be present."
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
record_result "02-replica-lag-spike" "validation_pass" "$PASS_COUNT"
record_result "02-replica-lag-spike" "validation_fail" "$FAIL_COUNT"

echo ""
echo "=================================================="
echo " SURVIVE 02 Validation Complete"
echo "=================================================="
echo " PASS: $PASS_COUNT"
echo " FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_success "All checks passed. Replica lag has recovered."
    exit 0
else
    log_error "$FAIL_COUNT check(s) failed. Review the runbook."
    exit 1
fi
