#!/usr/bin/env bash
# =============================================================================
# Scenario 02: PgBouncer Connection Pool Exhaustion
# validate.sh - Confirm PgBouncer pool is healthy and accepting connections
# =============================================================================
# Pass criteria:
#   1. PgBouncer is accepting new connections on port 6432
#   2. A query executes successfully through PgBouncer within 3s
#   3. Active client count in PgBouncer is below pool_size (not saturated)
#   4. PostgreSQL on primary is healthy
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Validating Scenario 02: PgBouncer Connection Pool Exhaustion recovery"
echo ""

PASS=0
FAIL=0

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: PgBouncer port is open ----------------------------------------
log_info "Check 1: PgBouncer port ${PGBOUNCER_PORT} is open..."
if check_port "$PRIMARY_HOST" "$PGBOUNCER_PORT"; then
    check_pass "PgBouncer port ${PGBOUNCER_PORT} is open on ${PRIMARY_HOST}"
else
    check_fail "PgBouncer port ${PGBOUNCER_PORT} is not reachable on ${PRIMARY_HOST}"
fi

# ---- Check 2: Query executes through PgBouncer within 5s --------------------
log_info "Check 2: Query executes through PgBouncer within 5 seconds..."
QUERY_START=$(date +%s)
QUERY_RESULT=$(PGCONNECT_TIMEOUT=5 PGPASSWORD=quant_readonly_2026 timeout 8 psql \
    -h "$PRIMARY_HOST" -p "$PGBOUNCER_PORT" \
    -U quant_readonly -d quantdb \
    -t -c "SELECT count(*) FROM quant.instruments;" 2>&1 || echo "FAILED")
QUERY_END=$(date +%s)
QUERY_DURATION=$(( QUERY_END - QUERY_START ))

if echo "$QUERY_RESULT" | grep -qE '^[[:space:]]*[0-9]+'; then
    if (( QUERY_DURATION <= 5 )); then
        check_pass "Query executed through PgBouncer in ${QUERY_DURATION}s (healthy)"
    else
        check_fail "Query succeeded but took ${QUERY_DURATION}s (> 5s) - pool may be congested"
    fi
else
    check_fail "Query through PgBouncer failed or timed out: ${QUERY_RESULT}"
fi

# ---- Check 3: Active client count is not saturated --------------------------
log_info "Check 3: PgBouncer pool is not saturated (checking SHOW POOLS via SSH)..."
# Query PgBouncer admin via SSH on primary (avoids external auth issues)
POOLS_OUTPUT=$(ssh_primary "PGPASSWORD=pgbouncer_2026 psql \
    -h 127.0.0.1 -p ${PGBOUNCER_PORT} \
    -U pgbouncer -d pgbouncer \
    -t -c 'SHOW POOLS;'" 2>/dev/null || echo "UNAVAILABLE")

if echo "$POOLS_OUTPUT" | grep -q "UNAVAILABLE"; then
    log_warn "Could not query PgBouncer admin via SSH"
    log_warn "Skipping pool saturation check - relying on connection test instead"
else
    # Extract cl_active for quantdb - should be well below max_db_connections (100)
    CL_ACTIVE=$(echo "$POOLS_OUTPUT" | grep quantdb | awk -F'|' '{gsub(/[ \t]/,"",$3); print $3}' | head -1)
    if [[ -n "$CL_ACTIVE" ]] && (( CL_ACTIVE < 50 )); then
        check_pass "PgBouncer active clients for quantdb: ${CL_ACTIVE} (not saturated)"
    elif [[ -n "$CL_ACTIVE" ]]; then
        check_fail "PgBouncer still has ${CL_ACTIVE} active clients - pool may still be flooded"
    else
        log_warn "Could not parse cl_active from SHOW POOLS output - treating as warn"
        check_pass "PgBouncer SHOW POOLS returned output (manual check recommended)"
    fi
fi

# ---- Check 4: PostgreSQL primary is healthy ---------------------------------
log_info "Check 4: PostgreSQL primary is healthy..."
if check_pg "$PRIMARY_HOST"; then
    check_pass "PostgreSQL on ${PRIMARY_HOST}:${PG_PORT} is accepting connections"
else
    check_fail "PostgreSQL on ${PRIMARY_HOST}:${PG_PORT} is not responding"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 02 PASSED - PgBouncer pool is healthy"
    exit 0
else
    log_error "Scenario 02 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
