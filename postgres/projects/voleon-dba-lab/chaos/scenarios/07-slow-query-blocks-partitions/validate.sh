#!/usr/bin/env bash
# =============================================================================
# Scenario 07: Slow Query Blocks Partition Maintenance
# validate.sh - Confirm no blocking queries remain and maintenance can run
# =============================================================================
# Pass criteria:
#   1. No long-running queries older than 60s on market_data partitions
#   2. No lock waits on quant schema tables
#   3. A simulated partition ALTER can complete without blocking (within 5s)
#   4. PostgreSQL is healthy and accepting connections
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Validating Scenario 07: Slow Query Blocks Partition Maintenance recovery"
echo ""

PASS=0
FAIL=0

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: PostgreSQL is healthy -----------------------------------------
log_info "Check 1: PostgreSQL is accepting connections..."
if check_pg "$PRIMARY_HOST"; then
    check_pass "PostgreSQL is responding on ${PRIMARY_HOST}"
else
    check_fail "PostgreSQL is not responding on ${PRIMARY_HOST}"
    exit 1
fi

# ---- Check 2: No long-running queries on market_data ------------------------
log_info "Check 2: No active queries older than 60s blocking market_data..."
BLOCKING_COUNT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM pg_stat_activity sa \
    JOIN pg_locks l ON l.pid = sa.pid \
    JOIN pg_class c ON c.oid = l.relation \
    JOIN pg_namespace n ON n.oid = c.relnamespace \
    WHERE n.nspname = 'quant' \
    AND c.relname LIKE '%market_data%' \
    AND l.mode = 'AccessShareLock' \
    AND l.granted = true \
    AND sa.state = 'active' \
    AND now() - sa.query_start > interval '60 seconds';\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")

if [[ "$BLOCKING_COUNT" == "0" ]]; then
    check_pass "No long-running AccessShareLock queries on market_data"
else
    check_fail "Found ${BLOCKING_COUNT} long-running query/queries still holding locks on market_data"
    log_error "Kill them with: SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE ...;"
fi

# ---- Check 3: No lock waits in the quant schema -----------------------------
log_info "Check 3: No lock waits (blocked processes) on quant schema tables..."
LOCK_WAITS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM pg_locks l \
    JOIN pg_class c ON c.oid = l.relation \
    JOIN pg_namespace n ON n.oid = c.relnamespace \
    WHERE n.nspname = 'quant' \
    AND l.granted = false;\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")

if [[ "$LOCK_WAITS" == "0" ]]; then
    check_pass "No blocked lock waits on quant schema tables"
else
    check_fail "${LOCK_WAITS} blocked lock wait(s) on quant schema tables"
fi

# ---- Check 4: Simulated partition DDL completes without blocking -------------
log_info "Check 4: Partition DDL (ALTER TABLE) completes within 8s..."
# Find oldest partition for the test - ALTER TABLE requires AccessExclusiveLock
# which conflicts with AccessShareLock held by the blocker query
TARGET_PARTITION=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT child.relname \
    FROM pg_inherits \
    JOIN pg_class parent ON pg_inherits.inhparent = parent.oid \
    JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid \
    JOIN pg_namespace n  ON n.oid = parent.relnamespace \
    WHERE n.nspname = 'quant' AND parent.relname = 'market_data' \
    ORDER BY child.relname ASC LIMIT 1;\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "")

if [[ -n "$TARGET_PARTITION" ]]; then
    # Use ALTER TABLE which needs AccessExclusiveLock (blocked by AccessShareLock)
    MAINT_RESULT=$(timeout 8 ssh $SSH_OPTS ${SSH_USER}@${PRIMARY_HOST} "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
        -c \"SET lock_timeout = '5s'; ALTER TABLE quant.${TARGET_PARTITION} SET (fillfactor = 90);\" \
        2>&1" || echo "TIMED_OUT")

    if echo "$MAINT_RESULT" | grep -qi "ALTER TABLE\|alter table"; then
        check_pass "Partition DDL on quant.${TARGET_PARTITION} completed without blocking"
        # Revert fillfactor
        ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
            -c \"ALTER TABLE quant.${TARGET_PARTITION} RESET (fillfactor);\" " 2>/dev/null || true
    elif echo "$MAINT_RESULT" | grep -qi "TIMED_OUT\|lock timeout"; then
        check_fail "Partition DDL timed out - a lock is still blocking maintenance"
    else
        check_fail "Partition DDL failed: ${MAINT_RESULT}"
    fi
else
    log_warn "No market_data partitions found - skipping maintenance simulation"
    check_pass "Partition maintenance simulation skipped (no partitions to test)"
fi

# ---- Check 5: Chaos blocker PID file cleaned up -----------------------------
log_info "Check 5: Chaos blocker process is no longer running..."
BLOCKER_PID=$(ssh_primary "cat /tmp/chaos07_blocker.pid 2>/dev/null || echo ''" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$BLOCKER_PID" ]]; then
    check_pass "No chaos blocker PID file found (already cleaned up)"
else
    PROC_ALIVE=$(ssh_primary "kill -0 ${BLOCKER_PID} 2>/dev/null && echo 'alive' || echo 'dead'" 2>/dev/null)
    if [[ "$PROC_ALIVE" == "dead" ]]; then
        check_pass "Chaos blocker process (PID ${BLOCKER_PID}) is no longer running"
        ssh_primary "rm -f /tmp/chaos07_blocker.pid /tmp/chaos07_blocker.log" 2>/dev/null || true
    else
        check_fail "Chaos blocker process (PID ${BLOCKER_PID}) is still running - kill it and retry"
    fi
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 07 PASSED - No blocking queries, partition maintenance can run"
    exit 0
else
    log_error "Scenario 07 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
