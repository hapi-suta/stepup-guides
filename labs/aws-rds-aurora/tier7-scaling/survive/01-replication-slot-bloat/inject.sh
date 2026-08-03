#!/usr/bin/env bash
# SURVIVE Scenario 01: Replication Slot Bloat
#
# Injects the problem:
#   - Disables the logical replication subscription on the target (simulates a dead consumer)
#   - Generates a large volume of writes on the source
#   - Creates a secondary orphaned replication slot with no consumer
#
# The result: WAL accumulates on the source. Disk usage grows.
# The student must identify the problem, assess severity, and remediate.
#
# Run this script, then attempt to diagnose and fix WITHOUT reading the runbook first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

# ============================================================
check_required_vars SOURCE_DB_IDENTIFIER TARGET_DB_IDENTIFIER SOURCE_DB_HOST TARGET_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql
# ============================================================

log_info "=== SURVIVE Scenario 01: Replication Slot Bloat ==="
log_info "Injecting problem condition. This will take 2-3 minutes."
log_info ""
log_info "What is being injected:"
log_info "  1. Subscription on target will be disabled (simulating dead consumer)"
log_info "  2. An orphaned replication slot will be created with no active consumer"
log_info "  3. A burst of writes will be applied to the source"
log_info "  4. WAL will begin accumulating on the source"
log_info ""

# Step 1: Record the current state before injection
log_info "Recording pre-injection baseline..."

FREE_STORAGE_BEFORE=$(get_metric_latest "AWS/RDS" "FreeStorageSpace" "DBInstanceIdentifier" "${SOURCE_DB_IDENTIFIER}")
log_info "Free storage before injection: ${FREE_STORAGE_BEFORE} bytes"

EXISTING_SLOTS=$(psql_source -t -A -c "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_type = 'logical'" 2>/dev/null || echo "0")
log_info "Existing logical replication slots: ${EXISTING_SLOTS}"

# Step 2: Disable the subscription on the target (kill the consumer)
log_info "Step 2: Disabling logical replication subscription on target..."
psql_target -c "ALTER SUBSCRIPTION tier7_sub DISABLE;" 2>/dev/null || {
  log_warn "Subscription 'tier7_sub' not found on target. Creating and immediately disabling it."
  psql_target -c "
    CREATE SUBSCRIPTION tier7_sub_inject
      CONNECTION 'host=${SOURCE_DB_HOST} port=${DB_PORT:-5432} dbname=${DB_NAME} user=${DB_USER} password=${PGPASSWORD} sslmode=require'
      PUBLICATION tier7_pub
      WITH (copy_data = false);" 2>/dev/null || true
  psql_target -c "ALTER SUBSCRIPTION tier7_sub_inject DISABLE;" 2>/dev/null || true
}

log_info "  Subscription disabled. Consumer is now dead."

# Step 3: Create an orphaned replication slot directly on the source
log_info "Step 3: Creating orphaned replication slot (no consumer)..."
psql_source -c "
  SELECT pg_create_logical_replication_slot('orphaned_slot_do_not_use', 'pgoutput');
" 2>/dev/null || log_warn "Orphaned slot may already exist - continuing."

log_info "  Orphaned slot 'orphaned_slot_do_not_use' created. It will never be consumed."

# Step 4: Generate write volume on the source to accumulate WAL
log_info "Step 4: Generating write volume on source (60 seconds of writes)..."
log_info "  This simulates normal application activity while the slot is stuck."

END_TIME=$((SECONDS + 60))
BATCH=0
while [[ $SECONDS -lt $END_TIME ]]; do
  psql_source -c "
    INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
    SELECT
      (RANDOM() * 999 + 1)::INTEGER,
      'SKU-INJECT-' || gs,
      (RANDOM() * 5 + 1)::INTEGER,
      (RANDOM() * 200 + 10)::NUMERIC(10,2),
      'pending'
    FROM generate_series(1, 500) gs;

    UPDATE orders
    SET status = 'processing'
    WHERE order_id IN (
      SELECT order_id FROM orders WHERE status = 'pending' ORDER BY RANDOM() LIMIT 100
    );
  " > /dev/null 2>&1 || true
  BATCH=$((BATCH + 1))
  log_info "  Write batch ${BATCH} complete... (${SECONDS}/${END_TIME}s)"
  sleep 5
done

# Step 5: Show final slot state
log_info ""
log_info "=== Injection Complete ==="
log_info ""
log_info "Current replication slot state:"
psql_source -c "
SELECT
  slot_name,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS consumer_lag
FROM pg_replication_slots
ORDER BY slot_name;
" 2>/dev/null || log_warn "Could not query pg_replication_slots"

log_info ""
log_warn "======================================================"
log_warn "  PROBLEM INJECTED. The clock is ticking."
log_warn "  WAL is accumulating. Your disk is filling."
log_warn "======================================================"
log_warn ""
log_warn "  Symptoms you might observe:"
log_warn "    - CloudWatch OldestReplicationSlotLag growing"
log_warn "    - FreeStorageSpace trending down"
log_warn "    - pg_replication_slots shows inactive slots"
log_warn "    - WAL directory growing (not directly visible on RDS)"
log_warn ""
log_warn "  DO NOT READ the runbook yet. Diagnose first."
log_warn ""
log_warn "  Useful starting commands:"
log_warn "    psql -c \"SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag FROM pg_replication_slots;\""
log_warn "    aws cloudwatch get-metric-statistics --metric-name OldestReplicationSlotLag ..."
log_warn ""
log_warn "  When you have fixed it, run: validate.sh"
log_warn "======================================================"
