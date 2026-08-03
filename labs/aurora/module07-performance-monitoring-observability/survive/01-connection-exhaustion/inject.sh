#!/usr/bin/env bash
# survive/01-connection-exhaustion/inject.sh
# Injects: Max connections reached, new connections rejected
# Difficulty: Hard
# Idempotent: Yes - kills existing injected connections before re-injecting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source environment variables
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then
    source "${SCRIPT_DIR}/../config.sh"
fi

# Require these variables
: "${DB_ENDPOINT:?Set DB_ENDPOINT}"
: "${DB_PORT:=5432}"
: "${DB_USER:?Set DB_USER}"
: "${DB_NAME:?Set DB_NAME}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "INJECT: Connection Exhaustion"
echo "============================================"
echo ""

# Clean up any previous injection
echo "Cleaning up any previous injection..."
pkill -f "psql.*pg_sleep.*connection_flood" 2>/dev/null || true
sleep 2

# Get max_connections
MAX_CONN=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SHOW max_connections;" 2>/dev/null | tr -d ' ')

if [[ -z "$MAX_CONN" ]]; then
    echo "ERROR: Cannot connect to database to get max_connections"
    exit 1
fi

STORM_CONN=$(( MAX_CONN * 90 / 100 ))

echo "max_connections: $MAX_CONN"
echo "Opening $STORM_CONN connections to exhaust the pool..."

# Record injection time
date > "${LOG_DIR}/inject-time.txt"
echo "$MAX_CONN" > "${LOG_DIR}/max-connections.txt"

# Open connections that hold for 10 minutes
for i in $(seq 1 "$STORM_CONN"); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 \
        -c "SET application_name = 'connection_flood_${i}'; SELECT pg_sleep(600);" &>/dev/null &
    if (( i % 50 == 0 )); then
        echo "  Opened $i / $STORM_CONN connections..."
    fi
done

sleep 5

# Check current connection count
CURRENT_CONN=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || echo "CANNOT_CONNECT")
CURRENT_CONN=$(echo "$CURRENT_CONN" | tr -d ' ')

echo ""
echo "============================================"
echo "SCENARIO INJECTED: Connection Exhaustion"
echo "============================================"
echo ""
echo "Current connections: $CURRENT_CONN / $MAX_CONN"
echo ""
echo "Symptoms the student will observe:"
echo "  - New connections fail with: FATAL: sorry, too many clients already"
echo "  - CloudWatch DatabaseConnections alarm firing"
echo "  - All application requests failing"
echo ""
echo "The student must diagnose and resolve this in under 15 minutes."
echo ""
echo "To stop the injection early:"
echo "  pkill -f 'connection_flood'"
