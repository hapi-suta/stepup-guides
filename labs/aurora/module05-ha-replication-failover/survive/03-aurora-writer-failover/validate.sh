#!/usr/bin/env bash
# SURVIVE 03 - validate.sh
# Verifies that the Aurora writer failover completed and a new writer is active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

log_section "SURVIVE 03 - Aurora Writer Failover Validation"

# -------------------------------------------------------
# Check 1: Cluster status is available
# -------------------------------------------------------
log_info "Check 1: Cluster status is 'available'"
STATUS=$(get_cluster_status "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$STATUS" = "available" ]; then
    log_success "PASS: Cluster status is 'available'"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cluster status is '$STATUS'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Writer has changed
# -------------------------------------------------------
log_info "Check 2: Writer instance has changed"
PRE_WRITER=$(grep "03-aurora-writer-failover,pre_failover_writer" "$SURVIVE_RESULTS_DIR/results.csv" 2>/dev/null | tail -1 | cut -d',' -f4)
CURRENT_WRITER=$(get_cluster_writer "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")

record_result "03-aurora-writer-failover" "post_failover_writer" "$CURRENT_WRITER"

if [ -n "$PRE_WRITER" ] && [ "$PRE_WRITER" != "$CURRENT_WRITER" ]; then
    log_success "PASS: Writer changed from '$PRE_WRITER' to '$CURRENT_WRITER'"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [ -z "$PRE_WRITER" ]; then
    log_warn "SKIP: No pre-failover writer recorded"
else
    log_error "FAIL: Writer did not change (still $CURRENT_WRITER)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: Writer endpoint accepts connections
# -------------------------------------------------------
log_info "Check 3: Writer endpoint accepts connections"
if test_db_connection "$AURORA_WRITER_ENDPOINT"; then
    log_success "PASS: Writer endpoint is accepting connections"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to writer endpoint"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: Writer is in read-write mode
# -------------------------------------------------------
log_info "Check 4: Writer is in read-write mode"
IS_RECOVERY=$(run_query "$AURORA_WRITER_ENDPOINT" "SELECT pg_is_in_recovery();")
if [ "$IS_RECOVERY" = "f" ]; then
    log_success "PASS: Writer is in read-write mode"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Writer is in recovery mode"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: Can write data
# -------------------------------------------------------
log_info "Check 5: Write operation succeeds"
WRITE_RESULT=$(psql -h "$AURORA_WRITER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    --connect-timeout=5 \
    -t -c "CREATE TABLE IF NOT EXISTS failover_test (id SERIAL PRIMARY KEY, message TEXT, created_at TIMESTAMPTZ DEFAULT now()); INSERT INTO failover_test (message) VALUES ('survive-03-validation') RETURNING id;" \
    2>&1 | tr -d ' \n')

if echo "$WRITE_RESULT" | grep -qE '[0-9]+'; then
    log_success "PASS: Write operation succeeded"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Write operation failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: Reader endpoint works
# -------------------------------------------------------
log_info "Check 6: Reader endpoint works"
if test_db_connection "$AURORA_READER_ENDPOINT"; then
    IS_READER=$(run_query "$AURORA_READER_ENDPOINT" "SELECT pg_is_in_recovery();")
    if [ "$IS_READER" = "t" ]; then
        log_success "PASS: Reader endpoint serves a replica"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_warn "WARN: Reader endpoint serves the writer (no readers?)"
    fi
else
    log_error "FAIL: Reader endpoint not accessible"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
record_result "03-aurora-writer-failover" "validation_pass" "$PASS_COUNT"
record_result "03-aurora-writer-failover" "validation_fail" "$FAIL_COUNT"

echo ""
echo "=================================================="
echo " SURVIVE 03 Validation Complete"
echo "=================================================="
echo " Pre-failover writer:  ${PRE_WRITER:-unknown}"
echo " Post-failover writer: ${CURRENT_WRITER:-unknown}"
echo " PASS: $PASS_COUNT"
echo " FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_success "All checks passed. Writer failover validated."
    exit 0
else
    log_error "$FAIL_COUNT check(s) failed. Review the runbook."
    exit 1
fi
