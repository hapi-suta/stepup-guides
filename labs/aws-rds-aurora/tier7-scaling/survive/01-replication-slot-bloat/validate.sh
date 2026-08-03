#!/usr/bin/env bash
# SURVIVE Scenario 01: Validation Script
# Run this after completing your remediation to verify the system is healthy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

log_info "=== SURVIVE Scenario 01: Validation ==="
log_info "Running checks to confirm remediation is complete..."
log_info ""

# Check 1: No inactive replication slots exist
log_info "Check 1: No inactive replication slots with lag..."
INACTIVE_SLOTS=$(psql_source -t -A -c "
  SELECT COUNT(*)
  FROM pg_replication_slots
  WHERE NOT active
  AND pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) > 10485760
" 2>/dev/null || echo "-1")

assert_equal \
  "No inactive replication slots retaining significant WAL" \
  "0" \
  "${INACTIVE_SLOTS}"

# Check 2: Orphaned slot is gone
log_info "Check 2: Orphaned slot 'orphaned_slot_do_not_use' does not exist..."
ORPHANED_SLOT=$(psql_source -t -A -c "
  SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = 'orphaned_slot_do_not_use'
" 2>/dev/null || echo "-1")

assert_equal \
  "Orphaned slot dropped" \
  "0" \
  "${ORPHANED_SLOT}"

# Check 3: tier7_sub subscription is enabled and streaming on target
log_info "Check 3: Subscription tier7_sub is active and streaming..."
SUB_STATUS=$(psql_target -t -A -c "
  SELECT substatus FROM pg_stat_subscription WHERE subname = 'tier7_sub'
" 2>/dev/null || echo "not_found")

assert_equal \
  "Subscription tier7_sub is in streaming state" \
  "streaming" \
  "${SUB_STATUS}"

# Check 4: Replication lag is below 100 MB
log_info "Check 4: Replication lag is below 100 MB..."
SLOT_LAG=$(psql_source -t -A -c "
  SELECT COALESCE(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn),
    0
  )
  FROM pg_replication_slots
  WHERE slot_name = 'tier7_sub'
" 2>/dev/null || echo "999999999")

assert_less_than \
  "Replication lag below 100 MB (104857600 bytes)" \
  "${SLOT_LAG}" \
  "104857600"

# Check 5: CloudWatch OldestReplicationSlotLag is not alarming
log_info "Check 5: OldestReplicationSlotLag CloudWatch metric is below 1024 MB..."
SLOT_LAG_CW=$(get_metric_latest "AWS/RDS" "OldestReplicationSlotLag" "DBInstanceIdentifier" "${SOURCE_DB_IDENTIFIER}" "Maximum")

if [[ "${SLOT_LAG_CW}" == "None" || -z "${SLOT_LAG_CW}" ]]; then
  log_warn "  Could not read OldestReplicationSlotLag from CloudWatch (metric may not have data points yet). Skipping."
else
  assert_less_than \
    "CloudWatch OldestReplicationSlotLag below 1024 MB" \
    "${SLOT_LAG_CW}" \
    "1024"
fi

# Check 6: Replication is working - new rows replicate
log_info "Check 6: Testing end-to-end replication..."
TEST_SKU="VALIDATE-01-$(date +%s)"

psql_source -c "
  INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
  VALUES (1, '${TEST_SKU}', 1, 0.01, 'pending');
" > /dev/null 2>&1

sleep 10

REPLICATED=$(psql_target -t -A -c "
  SELECT COUNT(*) FROM orders WHERE product_sku = '${TEST_SKU}'
" 2>/dev/null || echo "0")

assert_equal \
  "Test row replicated to target within 10 seconds" \
  "1" \
  "${REPLICATED}"

# Check 7: A slot lag alarm exists
log_info "Check 7: CloudWatch alarm exists for replication slot lag..."
ALARM_EXISTS=$(aws cloudwatch describe-alarms \
  --region "${AWS_REGION}" \
  --query "length(MetricAlarms[?contains(MetricName, 'ReplicationSlotLag')])" \
  --output text 2>/dev/null || echo "0")

if [[ "${ALARM_EXISTS}" -gt "0" ]]; then
  log_pass "CloudWatch alarm for OldestReplicationSlotLag exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_warn "No CloudWatch alarm found for OldestReplicationSlotLag. Recommended but not blocking."
fi

# Summary
print_validation_summary "01-replication-slot-bloat"
