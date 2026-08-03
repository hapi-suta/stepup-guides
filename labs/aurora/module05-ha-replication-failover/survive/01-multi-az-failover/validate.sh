#!/usr/bin/env bash
# SURVIVE 01 - validate.sh
# Verifies that the Multi-AZ failover completed successfully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

log_section "SURVIVE 01 - Multi-AZ Failover Validation"

# -------------------------------------------------------
# Check 1: Cluster status is available
# -------------------------------------------------------
log_info "Check 1: Cluster status is 'available'"
STATUS=$(get_cluster_status "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$STATUS" = "available" ]; then
    log_success "PASS: Cluster status is 'available'"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cluster status is '$STATUS' (expected 'available')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Writer has changed
# -------------------------------------------------------
log_info "Check 2: Writer instance has changed"
PRE_WRITER=$(grep "01-multi-az-failover,pre_failover_writer" "$SURVIVE_RESULTS_DIR/results.csv" 2>/dev/null | tail -1 | cut -d',' -f4)
CURRENT_WRITER=$(get_cluster_writer "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")

record_result "01-multi-az-failover" "post_failover_writer" "$CURRENT_WRITER"

if [ -n "$PRE_WRITER" ] && [ "$PRE_WRITER" != "$CURRENT_WRITER" ]; then
    log_success "PASS: Writer changed from '$PRE_WRITER' to '$CURRENT_WRITER'"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [ -z "$PRE_WRITER" ]; then
    log_warn "SKIP: No pre-failover writer recorded (inject.sh may not have run)"
else
    log_error "FAIL: Writer did not change (still $CURRENT_WRITER)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: Writer endpoint DNS updated
# -------------------------------------------------------
log_info "Check 3: Writer endpoint DNS updated"
PRE_IP=$(grep "01-multi-az-failover,pre_failover_ip" "$SURVIVE_RESULTS_DIR/results.csv" 2>/dev/null | tail -1 | cut -d',' -f4)
CURRENT_IP=$(dig +short "$AURORA_WRITER_ENDPOINT" 2>/dev/null | head -1)

record_result "01-multi-az-failover" "post_failover_ip" "$CURRENT_IP"

if [ -n "$PRE_IP" ] && [ "$PRE_IP" != "$CURRENT_IP" ]; then
    log_success "PASS: Writer endpoint IP changed from $PRE_IP to $CURRENT_IP"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [ -z "$PRE_IP" ]; then
    log_warn "SKIP: No pre-failover IP recorded"
else
    log_warn "WARN: IP may not have changed yet. DNS TTL is 5s - try again."
fi

# -------------------------------------------------------
# Check 4: Writer endpoint accepts connections
# -------------------------------------------------------
log_info "Check 4: Writer endpoint accepts connections"
if test_db_connection "$AURORA_WRITER_ENDPOINT"; then
    log_success "PASS: Writer endpoint is accepting connections"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to writer endpoint"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: Writer is in read-write mode
# -------------------------------------------------------
log_info "Check 5: Writer is in read-write mode"
IS_RECOVERY=$(run_query "$AURORA_WRITER_ENDPOINT" "SELECT pg_is_in_recovery();")
if [ "$IS_RECOVERY" = "f" ]; then
    log_success "PASS: Writer is in read-write mode"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Writer appears to be in recovery mode"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: Can write data
# -------------------------------------------------------
log_info "Check 6: Write operation succeeds"
WRITE_RESULT=$(psql -h "$AURORA_WRITER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    --connect-timeout=5 \
    -t -c "CREATE TABLE IF NOT EXISTS failover_test (id SERIAL PRIMARY KEY, message TEXT, created_at TIMESTAMPTZ DEFAULT now()); INSERT INTO failover_test (message) VALUES ('survive-01-validation') RETURNING id;" \
    2>&1 | tr -d ' \n')

if echo "$WRITE_RESULT" | grep -qE '[0-9]+'; then
    log_success "PASS: Write operation succeeded"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Write operation failed ($WRITE_RESULT)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 7: Reader endpoint still works
# -------------------------------------------------------
log_info "Check 7: Reader endpoint accepts connections"
if test_db_connection "$AURORA_READER_ENDPOINT"; then
    log_success "PASS: Reader endpoint is accessible"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Reader endpoint is not accessible"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
record_result "01-multi-az-failover" "validation_pass" "$PASS_COUNT"
record_result "01-multi-az-failover" "validation_fail" "$FAIL_COUNT"

echo ""
echo "=================================================="
echo " SURVIVE 01 Validation Complete"
echo "=================================================="
echo " Pre-failover writer:  ${PRE_WRITER:-unknown}"
echo " Post-failover writer: ${CURRENT_WRITER:-unknown}"
echo " PASS: $PASS_COUNT"
echo " FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_success "All checks passed. Failover validated."
    exit 0
else
    log_error "$FAIL_COUNT check(s) failed. Review the runbook."
    exit 1
fi
