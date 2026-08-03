#!/bin/bash
# =============================================================================
# SURVIVE Scenario 03: Connection Storm
# INJECT - Opens hundreds of idle database connections to simulate a
#          reconnection storm after a failover event.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

STATE_FILE="${M09_STATE_DIR}/03-connection-storm.state"

print_survive_warning "Connection Storm (Reconnect Flood)"

# ---------------------------------------------------------------------------
log_step 1 "Check current connection count"
# ---------------------------------------------------------------------------

CURRENT_CONNECTIONS=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';")
MAX_CONNECTIONS=$(run_sql "SELECT current_setting('max_connections')::int;")

log_info "Current connections: ${CURRENT_CONNECTIONS}"
log_info "Max connections: ${MAX_CONNECTIONS}"

cat > "${STATE_FILE}" <<EOF
INJECT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BASELINE_CONNECTIONS=${CURRENT_CONNECTIONS}
MAX_CONNECTIONS=${MAX_CONNECTIONS}
STORM_USER=${M09_CHAOS_PREFIX}-storm-user
EOF

log_success "State saved to ${STATE_FILE}"

# ---------------------------------------------------------------------------
log_step 2 "Create a storm user for the simulation"
# ---------------------------------------------------------------------------

STORM_USER="${M09_CHAOS_PREFIX}-storm-user"
STORM_PASSWORD="StormPass$(date +%s | tail -c 6)"

# Idempotent: drop and recreate
run_sql "DROP ROLE IF EXISTS \"${STORM_USER}\";" 2>/dev/null || true
run_sql "CREATE ROLE \"${STORM_USER}\" LOGIN PASSWORD '${STORM_PASSWORD}';"
run_sql "GRANT CONNECT ON DATABASE ${M09_DB_NAME} TO \"${STORM_USER}\";"

echo "STORM_PASSWORD=${STORM_PASSWORD}" >> "${STATE_FILE}"

log_success "Created storm user: ${STORM_USER}"

# ---------------------------------------------------------------------------
log_step 3 "Open flood of idle connections"
# ---------------------------------------------------------------------------

TARGET_CONNECTIONS=150
log_info "Opening ${TARGET_CONNECTIONS} idle connections..."

for i in $(seq 1 ${TARGET_CONNECTIONS}); do
    PGPASSWORD="${STORM_PASSWORD}" psql \
        -h "${M09_DB_HOST}" \
        -p "${M09_DB_PORT}" \
        -U "${STORM_USER}" \
        -d "${M09_DB_NAME}" \
        -c "SELECT pg_sleep(3600);" > /dev/null 2>&1 &

    # Print progress every 25 connections
    if [ $((i % 25)) -eq 0 ]; then
        log_info "Opened ${i}/${TARGET_CONNECTIONS} connections..."
    fi
done

# Wait a moment for connections to establish
sleep 5

NEW_CONNECTIONS=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';")
STORM_CONNECTIONS=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE usename = '${STORM_USER}';")

log_success "Connections after injection: ${NEW_CONNECTIONS} (storm user: ${STORM_CONNECTIONS})"

echo "STORM_CONNECTIONS=${STORM_CONNECTIONS}" >> "${STATE_FILE}"

# ---------------------------------------------------------------------------
log_step 4 "Create some idle-in-transaction sessions"
# ---------------------------------------------------------------------------

log_info "Opening 10 idle-in-transaction sessions..."

for i in $(seq 1 10); do
    PGPASSWORD="${STORM_PASSWORD}" psql \
        -h "${M09_DB_HOST}" \
        -p "${M09_DB_PORT}" \
        -U "${STORM_USER}" \
        -d "${M09_DB_NAME}" \
        -c "BEGIN; SELECT 1; SELECT pg_sleep(3600);" > /dev/null 2>&1 &
done

sleep 3

IDLE_IN_TXN=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction' AND usename = '${STORM_USER}';")
log_success "Idle-in-transaction sessions: ${IDLE_IN_TXN}"

# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  INJECTION COMPLETE"
echo "========================================="
echo ""
echo "  Problems injected:"
echo "  1. ${STORM_CONNECTIONS} idle connections from storm user"
echo "  2. ${IDLE_IN_TXN} idle-in-transaction sessions"
echo "  3. Connection utilization is elevated"
echo ""
echo "  Your mission:"
echo "  - Diagnose the connection storm using the runbook"
echo "  - Identify the source (user, client address)"
echo "  - Terminate the offending sessions"
echo "  - Clean up the storm user"
echo "  - Run validate.sh to verify your fixes"
echo ""
echo "========================================="
