#!/usr/bin/env bash
# survive/01-connection-exhaustion/inject.sh
# Injects: Max connections hit, new connections rejected
# Difficulty: Hard

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "INJECT: Connection Exhaustion"
log "Starting connection exhaustion scenario"

# Get max_connections
MAX_CONN=$(psql_exec "SHOW max_connections")
MAX_CONN=$(echo "$MAX_CONN" | tr -d ' ')
STORM_CONN=$(( MAX_CONN * 95 / 100 ))

log "max_connections: $MAX_CONN"
log "Opening $STORM_CONN connections to exhaust the pool"

# Stamp the inject time
echo "$(date)" > "${SURVIVE_LOG_DIR}/01-inject-time.txt"
echo "$MAX_CONN" > "${SURVIVE_LOG_DIR}/01-max-connections.txt"

# Open connections that will hold for 10 minutes
for i in $(seq 1 "$STORM_CONN"); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT pg_sleep(600);" &>/dev/null &
    if (( i % 50 == 0 )); then
        log "Opened $i connections..."
    fi
done

sleep 5

CURRENT_CONN=$(psql_exec "SELECT count(*) FROM pg_stat_activity" 2>/dev/null || echo "CANNOT CONNECT")
log "Current connections: $CURRENT_CONN"

if [[ "$CURRENT_CONN" == "CANNOT CONNECT" ]]; then
    warn "Database is now rejecting connections - scenario fully injected"
else
    log "Connection count: $CURRENT_CONN / $MAX_CONN"
fi

echo ""
echo "=========================================="
echo "SCENARIO INJECTED: Connection Exhaustion"
echo "=========================================="
echo ""
echo "Symptoms your student will observe:"
echo "  - New connection attempts fail with FATAL: sorry, too many clients already"
echo "  - CloudWatch DatabaseConnections alarm firing"
echo "  - All application requests failing"
echo ""
echo "The student must diagnose and resolve this in under 15 minutes."
echo ""
echo "To stop the injection early: pkill -f 'psql.*pg_sleep'"
