#!/usr/bin/env bash
# =============================================================================
# Scenario 05: WAL Directory Disk Full
# validate.sh - Confirm WAL directory has space and PostgreSQL is healthy
# =============================================================================
# Pass criteria:
#   1. Dummy files are removed from pg_wal directory
#   2. pg_wal filesystem has at least 500MB free
#   3. PostgreSQL is accepting connections
#   4. A write succeeds (WAL is flowing)
#   5. Replication lag is below 30 seconds
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

WAL_DIR="${PG_DATA}/pg_wal"
DUMMY_FILE_PREFIX="chaos05_dummy"
MIN_FREE_MB=500

log_info "Validating Scenario 05: WAL Directory Disk Full recovery"
echo ""

PASS=0
FAIL=0

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: SSH into primary -----------------------------------------------
log_info "Check 1: Primary is reachable via SSH..."
if check_ssh "$PRIMARY_HOST"; then
    check_pass "Primary ${PRIMARY_HOST} is reachable via SSH"
else
    check_fail "Cannot SSH into primary ${PRIMARY_HOST}"
    exit 1
fi

# ---- Check 2: Dummy files are gone -------------------------------------------
log_info "Check 2: Dummy chaos files removed from ${WAL_DIR}..."
DUMMY_COUNT=$(ssh_primary \
    "sudo find ${WAL_DIR} -name '${DUMMY_FILE_PREFIX}*' 2>/dev/null | wc -l | tr -d '[:space:]'" \
    2>/dev/null || echo "0")

if [[ "$DUMMY_COUNT" == "0" ]]; then
    check_pass "No dummy files found in ${WAL_DIR}"
else
    check_fail "${DUMMY_COUNT} dummy file(s) still in ${WAL_DIR} - remove them: sudo rm ${WAL_DIR}/${DUMMY_FILE_PREFIX}*"
fi

# ---- Check 3: pg_wal filesystem has adequate free space ----------------------
log_info "Check 3: pg_wal filesystem has at least ${MIN_FREE_MB}MB free..."
FREE_MB=$(ssh_primary "sudo df -BM --output=avail ${WAL_DIR} | tail -1" 2>/dev/null | tr -d 'M ' || echo "0")

if [[ "$FREE_MB" =~ ^[0-9]+$ ]] && (( FREE_MB >= MIN_FREE_MB )); then
    check_pass "pg_wal filesystem has ${FREE_MB}MB free (>= ${MIN_FREE_MB}MB)"
else
    check_fail "pg_wal filesystem only has ${FREE_MB}MB free (need >= ${MIN_FREE_MB}MB)"
fi

# ---- Check 4: PostgreSQL is accepting connections ----------------------------
log_info "Check 4: PostgreSQL is accepting connections on primary..."
if check_pg "$PRIMARY_HOST"; then
    check_pass "PostgreSQL is accepting connections on ${PRIMARY_HOST}:${PG_PORT}"
else
    check_fail "PostgreSQL is not responding on ${PRIMARY_HOST}:${PG_PORT}"
fi

# ---- Check 5: Writes succeed (WAL is functional) ----------------------------
log_info "Check 5: A write to quant.signals succeeds..."
WRITE_RESULT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
    -t -c \"INSERT INTO quant.signals (model_id, instrument_id, signal_date, score, signal_type) \
    VALUES (1, 1, CURRENT_DATE, 0.00001, 'neutral') RETURNING signal_id;\" 2>&1" || echo "FAILED")

if echo "$WRITE_RESULT" | grep -qE '^[[:space:]]*[0-9]+'; then
    check_pass "Write to quant.signals succeeded - WAL is functional"
    ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
        -c \"DELETE FROM quant.signals WHERE signal_type = 'neutral' AND score = 0.00001;\" " 2>/dev/null || true
else
    check_fail "Write to quant.signals failed: ${WRITE_RESULT}"
fi

# ---- Check 6: Replication lag is below 30 seconds ---------------------------
log_info "Check 6: Replication lag is below 30 seconds..."
REPLAY_LAG=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int \
    FROM pg_stat_replication LIMIT 1;\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")

if [[ "$REPLAY_LAG" =~ ^[0-9]+$ ]]; then
    if (( REPLAY_LAG < 30 )); then
        check_pass "Replication lag: ${REPLAY_LAG}s (< 30s)"
    else
        check_fail "Replication lag: ${REPLAY_LAG}s (>= 30s) - replica may still be catching up"
    fi
else
    log_warn "Could not determine replication lag (replica may not be connected)"
    REPL_COUNT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
        -c \"SELECT COUNT(*) FROM pg_stat_replication WHERE state = 'streaming';\" \
        2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "0")
    if [[ "$REPL_COUNT" =~ ^[0-9]+$ ]] && (( REPL_COUNT >= 1 )); then
        check_pass "Streaming replication is active (${REPL_COUNT} replica(s))"
    else
        check_fail "No streaming replicas detected - check if replica reconnected after disk recovery"
    fi
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 05 PASSED - WAL directory cleared and PostgreSQL healthy"
    exit 0
else
    log_error "Scenario 05 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
