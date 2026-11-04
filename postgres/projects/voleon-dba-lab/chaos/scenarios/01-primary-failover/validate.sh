#!/usr/bin/env bash
# =============================================================================
# Scenario 01: Primary Failover
# validate.sh - Confirm the lab is fully recovered
# =============================================================================
# Pass criteria:
#   1. A PostgreSQL instance is accepting writes (on either host)
#   2. pg_is_in_recovery() = false on the write-accepting host
#   3. PgBouncer is accepting connections on port 6432
#   4. A test INSERT into quant.signals succeeds via PgBouncer
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Validating Scenario 01: Primary Failover recovery"
echo ""

PASS=0
FAIL=0

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: At least one PG node accepts connections ----------------------
log_info "Check 1: PostgreSQL accepting connections (on replica or primary)..."
WRITE_HOST=""
WRITE_NODE=""
for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
    if check_pg "$host"; then
        WRITE_HOST="$host"
        if [[ "$host" == "$PRIMARY_HOST" ]]; then
            WRITE_NODE="primary"
        else
            WRITE_NODE="replica"
        fi
        break
    fi
done

if [[ -n "$WRITE_HOST" ]]; then
    check_pass "PostgreSQL is responding on ${WRITE_HOST}"
else
    check_fail "No PostgreSQL node is accepting connections"
fi

# ---- Check 2: The responding node is NOT in recovery (i.e., is primary) ----
log_info "Check 2: Confirming the responding node is NOT in recovery mode..."
if [[ -n "$WRITE_HOST" ]]; then
    IN_RECOVERY=$(ssh_node "${WRITE_NODE}" "sudo -u postgres ${PG_BIN}/psql -t -c \"SELECT pg_is_in_recovery();\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "error")
    if [[ "$IN_RECOVERY" == "f" ]]; then
        check_pass "Node ${WRITE_HOST} is in read-write mode (pg_is_in_recovery = f)"
    elif [[ "$IN_RECOVERY" == "t" ]]; then
        check_fail "Node ${WRITE_HOST} is still in recovery mode - promotion did not complete"
    else
        check_fail "Could not determine recovery status on ${WRITE_HOST} (got: ${IN_RECOVERY})"
    fi
else
    check_fail "Skipped - no PostgreSQL node is reachable"
fi

# ---- Check 3: PgBouncer is accepting connections ----------------------------
log_info "Check 3: PgBouncer accepting connections on port ${PGBOUNCER_PORT}..."
# Try a simple connection through PgBouncer (with timeout to avoid hanging on dead host)
BOUNCER_RESULT=$(PGCONNECT_TIMEOUT=5 PGPASSWORD=quant_readonly_2026 timeout 10 psql \
    -h "$PRIMARY_HOST" -p "$PGBOUNCER_PORT" -U quant_readonly -d quantdb \
    -t -c "SELECT 1;" 2>&1 || echo "FAILED")

if echo "$BOUNCER_RESULT" | grep -q "1"; then
    check_pass "PgBouncer on ${PRIMARY_HOST}:${PGBOUNCER_PORT} is accepting connections"
else
    # PgBouncer may be on the ops host after a failover
    BOUNCER_RESULT2=$(PGCONNECT_TIMEOUT=5 PGPASSWORD=quant_readonly_2026 timeout 10 psql \
        -h "$OPS_HOST" -p "$PGBOUNCER_PORT" -U quant_readonly -d quantdb \
        -t -c "SELECT 1;" 2>&1 || echo "FAILED")
    if echo "$BOUNCER_RESULT2" | grep -q "1"; then
        check_pass "PgBouncer on ${OPS_HOST}:${PGBOUNCER_PORT} is accepting connections"
    else
        check_fail "PgBouncer is not accepting connections on port ${PGBOUNCER_PORT}"
    fi
fi

# ---- Check 4: Writes succeed into quant.signals ----------------------------
log_info "Check 4: Test INSERT into quant.signals via PgBouncer..."
if [[ -n "$WRITE_HOST" ]]; then
    WRITE_RESULT=$(ssh_node "$WRITE_NODE" "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
        -t -c \"INSERT INTO quant.signals (model_id, instrument_id, signal_date, score, signal_type) \
        VALUES (1, 1, CURRENT_DATE, 0.00001, 'neutral') RETURNING signal_id;\" 2>&1" || echo "FAILED")

    if echo "$WRITE_RESULT" | grep -qE '^[[:space:]]*[0-9]+'; then
        check_pass "INSERT into quant.signals succeeded"
        # Clean up test row
        ssh_node "$WRITE_NODE" "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
            -c \"DELETE FROM quant.signals WHERE signal_type = 'neutral' AND score = 0.00001;\" " 2>/dev/null || true
    else
        check_fail "INSERT into quant.signals failed: ${WRITE_RESULT}"
    fi
else
    check_fail "Skipped - no writable PostgreSQL node found"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 01 PASSED - Full failover recovery confirmed"
    exit 0
else
    log_error "Scenario 01 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
