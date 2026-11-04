#!/usr/bin/env bash
# =============================================================================
# Scenario 02: PgBouncer Connection Pool Exhaustion
# inject.sh - Flood PgBouncer with connections using parallel psql processes
# =============================================================================
# What breaks: PgBouncer pool is exhausted. New connections get
#              "no more connections allowed" or queue forever. Applications
#              see connection timeouts.
# Your job:    Identify what is consuming the pool, kill or throttle the flood,
#              verify the pool drains and new connections succeed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

FLOOD_COUNT=200         # Connections to open simultaneously (must exceed pool_size)
HOLD_SECONDS=120        # How long each connection holds (gives time to practice)

log_info "Scenario 02: PgBouncer Connection Pool Exhaustion"
log_info "Flooding ${PRIMARY_HOST}:${PGBOUNCER_PORT} with ${FLOOD_COUNT} connections"
echo ""

# Confirm PgBouncer is up before flooding
log_info "Checking PgBouncer is currently reachable..."
if ! check_port "$PRIMARY_HOST" "$PGBOUNCER_PORT"; then
    log_error "PgBouncer port ${PGBOUNCER_PORT} is not open on ${PRIMARY_HOST}."
    exit 1
fi
log_success "PgBouncer is reachable - proceeding with injection"
echo ""

log_warn "Opening ${FLOOD_COUNT} idle connections that will hold for ${HOLD_SECONDS}s..."
log_warn "This will exhaust the default PgBouncer pool size."
echo ""

# Launch flood from the primary host itself - avoids needing pgbench locally
# In transaction pooling mode, pg_sleep releases the server connection between
# transactions. To truly exhaust the pool, we hold advisory locks inside
# explicit transactions so each connection keeps its server-side slot.
ssh_primary "bash -s -- ${FLOOD_COUNT} ${HOLD_SECONDS} ${PGBOUNCER_PORT} ${PG_DB}" << 'REMOTE'
FLOOD_COUNT="$1"
HOLD_SECONDS="$2"
PGBOUNCER_PORT="$3"
PG_DB="$4"
for i in $(seq 1 "$FLOOD_COUNT"); do
    PGPASSWORD=quant_app_2026 /usr/pgsql-17/bin/psql \
        -h 127.0.0.1 -p "$PGBOUNCER_PORT" \
        -U quant_app -d "$PG_DB" \
        -c "BEGIN; SELECT pg_advisory_lock($i); SELECT pg_sleep(${HOLD_SECONDS}); COMMIT;" \
        2>/dev/null &
done
echo "Launched ${FLOOD_COUNT} background connections holding advisory locks."
REMOTE

sleep 4

# Confirm pool is now saturated by trying a fresh connection
log_info "Testing if pool is saturated with a fresh connection..."
RESULT=$(PGCONNECT_TIMEOUT=5 PGPASSWORD=quant_readonly_2026 timeout 8 psql \
    -h "$PRIMARY_HOST" -p "$PGBOUNCER_PORT" \
    -U quant_readonly -d quantdb \
    -t -c "SELECT 1;" \
    2>&1 || echo "BLOCKED")

echo ""
if echo "$RESULT" | grep -qiE "no more|queue|BLOCKED|timeout|connection refused"; then
    log_success "Pool is exhausted - new connections are being blocked or queued"
else
    log_warn "Pool may not be fully exhausted yet (got: ${RESULT})"
    log_warn "Some PgBouncer configs have larger pool_size. Check 'SHOW POOLS;' in pgbouncer admin."
fi

echo ""
echo "  PgBouncer pool is now at capacity."
echo "  Applications connecting via port ${PGBOUNCER_PORT} will queue or error."
echo ""
echo "  Your tasks:"
echo "    1. Connect to PgBouncer admin (psql -p ${PGBOUNCER_PORT} -U pgbouncer pgbouncer)"
echo "    2. Run 'SHOW POOLS;' and 'SHOW CLIENTS;' to diagnose the saturation"
echo "    3. Identify the flood source and kill those connections"
echo "       Hint: 'SHOW CLIENTS;' shows who is connected"
echo "    4. Or: restart PgBouncer to clear all connections (causes brief blip)"
echo "    5. Verify normal connections succeed after recovery"
echo ""
echo "  Flood connections will auto-expire in ~${HOLD_SECONDS}s if not cleared sooner."
echo ""
echo "  When done: ./chaos.sh validate 02-pgbouncer-exhaustion"
