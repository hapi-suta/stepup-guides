#!/usr/bin/env bash
# =============================================================================
# Scenario 07: Slow Query Blocks Partition Maintenance
# inject.sh - Start a long-running query holding AccessShareLock on a partition
# =============================================================================
# What breaks: A long-running SELECT holds AccessShareLock on a market_data
#              partition. Any attempt to detach, drop, or VACUUM FULL that
#              partition gets blocked. pg_partman or maintenance jobs hang.
# Your job:    Identify the blocking query, investigate safely, and kill it.
#              Then verify partition maintenance can proceed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

LOCK_HOLD_SECONDS=300   # Hold lock for 5 minutes - enough time to practice

log_info "Scenario 07: Slow Query Blocks Partition Maintenance"
log_info "Target: quant.market_data partition on ${PRIMARY_HOST}"
echo ""

# Confirm connectivity
log_info "Checking SSH and PostgreSQL connectivity..."
if ! check_ssh "$PRIMARY_HOST"; then
    log_error "Cannot SSH into primary (${PRIMARY_HOST})"
    exit 1
fi
if ! check_pg "$PRIMARY_HOST"; then
    log_error "PostgreSQL is not responding on ${PRIMARY_HOST}"
    exit 1
fi
log_success "Primary is reachable"

# Find the oldest market_data partition (safest to lock without breaking things)
log_info "Finding oldest market_data partition to lock..."
OLDEST_PARTITION=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT child.relname \
    FROM pg_inherits \
    JOIN pg_class parent ON pg_inherits.inhparent = parent.oid \
    JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid \
    JOIN pg_namespace n  ON n.oid = parent.relnamespace \
    WHERE n.nspname = 'quant' AND parent.relname = 'market_data' \
    ORDER BY child.relname ASC \
    LIMIT 1;\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "")

if [[ -z "$OLDEST_PARTITION" ]]; then
    log_warn "market_data partitions not found. Falling back to locking quant.market_data directly."
    TARGET_TABLE="quant.market_data"
else
    TARGET_TABLE="quant.${OLDEST_PARTITION}"
    log_info "Will lock partition: ${TARGET_TABLE}"
fi

echo ""
log_warn "Starting a long-running query that holds AccessShareLock on ${TARGET_TABLE}..."
log_warn "Lock will hold for ${LOCK_HOLD_SECONDS}s unless manually killed."
echo ""

# Launch the blocking query in the background on the primary.
# pg_sleep inside a transaction is the cleanest way to hold a lock.
ssh_primary "nohup sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
    -c \"BEGIN; \
    LOCK TABLE ${TARGET_TABLE} IN ACCESS SHARE MODE; \
    SELECT pg_sleep(${LOCK_HOLD_SECONDS}); \
    COMMIT;\" > /tmp/chaos07_blocker.log 2>&1 &
echo \$! > /tmp/chaos07_blocker.pid
echo 'Blocker started with PID:' \$(cat /tmp/chaos07_blocker.pid)"

sleep 3

# Verify the lock is active
LOCK_COUNT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM pg_locks l \
    JOIN pg_class c ON c.oid = l.relation \
    JOIN pg_namespace n ON n.oid = c.relnamespace \
    WHERE n.nspname = 'quant' \
    AND c.relname LIKE '%market_data%' \
    AND l.mode = 'AccessShareLock' \
    AND l.granted = true;\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "0")

echo ""
if [[ "$LOCK_COUNT" =~ ^[0-9]+$ ]] && (( LOCK_COUNT >= 1 )); then
    log_success "AccessShareLock is active on ${TARGET_TABLE} (${LOCK_COUNT} lock entry/entries)"
else
    log_warn "Lock may not be visible yet. It will appear in pg_locks momentarily."
fi

echo ""
echo "  A long-running transaction is holding AccessShareLock on ${TARGET_TABLE}."
echo "  Any attempt to VACUUM FULL, DETACH, or DROP that partition will be blocked."
echo ""
echo "  Your tasks:"
echo "    1. Identify the blocking query:"
echo "       SELECT pid, state, wait_event_type, wait_event, query_start,"
echo "              left(query, 80) AS query"
echo "       FROM pg_stat_activity"
echo "       WHERE state != 'idle'"
echo "       ORDER BY query_start;"
echo ""
echo "    2. Find what it is blocking:"
echo "       SELECT blocking_locks.pid, blocked_locks.pid AS blocked_pid,"
echo "              blocked_activity.query AS blocked_query"
echo "       FROM pg_catalog.pg_locks blocked_locks"
echo "       JOIN pg_catalog.pg_locks blocking_locks"
echo "         ON blocking_locks.locktype = blocked_locks.locktype"
echo "       JOIN pg_catalog.pg_stat_activity blocked_activity"
echo "         ON blocked_activity.pid = blocked_locks.pid"
echo "       WHERE NOT blocked_locks.granted;"
echo ""
echo "    3. To simulate a blocked maintenance job, open another session and run:"
echo "       ALTER TABLE ${TARGET_TABLE} SET (autovacuum_enabled = false);"
echo "       (This requires an AccessExclusiveLock and will block)"
echo ""
echo "    4. Kill the blocker: SELECT pg_terminate_backend(<pid>);"
echo ""
echo "    5. Verify the maintenance job can now proceed"
echo ""
echo "  Lock will auto-release after ${LOCK_HOLD_SECONDS}s if not killed manually."
echo ""
echo "  When done: ./chaos.sh validate 07-slow-query-blocks-partitions"
