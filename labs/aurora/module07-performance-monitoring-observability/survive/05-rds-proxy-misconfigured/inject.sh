#!/usr/bin/env bash
# survive/05-rds-proxy-misconfigured/inject.sh
# Injects: Simulates RDS Proxy connection pinning causing pool exhaustion
# Difficulty: Hard
# Idempotent: Yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "INJECT: RDS Proxy Misconfigured (Simulated)"
echo "============================================"
echo ""

pkill -f "psql.*pinned_session" 2>/dev/null || true
sleep 2

# Simulate connection pinning by creating sessions that use session-level state
# In a real RDS Proxy scenario, these would be pinned and not multiplexed
echo "Creating 30 sessions with session-level state (simulating pinning)..."

for i in $(seq 1 30); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 \
        -c "SET application_name = 'pinned_session_${i}';
            SET search_path = public;
            SET work_mem = '16MB';
            SET statement_timeout = '0';
            CREATE TEMP TABLE IF NOT EXISTS session_cache_${i} (id INT);
            SELECT pg_sleep(600);" &>/dev/null &
done

sleep 3

# Also create sessions that hold advisory locks (another pinning cause)
echo "Creating 10 sessions with advisory locks..."
for i in $(seq 1 10); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 \
        -c "SET application_name = 'pinned_session_advisory_${i}';
            SELECT pg_advisory_lock(${i});
            SELECT pg_sleep(600);" &>/dev/null &
done

sleep 3
date > "${LOG_DIR}/inject-time.txt"

TOTAL=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'pinned_session%';" | tr -d ' ')

echo ""
echo "============================================"
echo "SCENARIO INJECTED: RDS Proxy Misconfigured"
echo "============================================"
echo ""
echo "Pinned sessions created: $TOTAL"
echo ""
echo "What is happening:"
echo "  - 30 sessions use SET commands and temp tables (causes pinning)"
echo "  - 10 sessions hold advisory locks (causes pinning)"
echo "  - In a real RDS Proxy setup, all 40 sessions would be pinned"
echo "  - Pinned connections cannot be multiplexed"
echo "  - This defeats the purpose of the proxy"
echo ""
echo "Symptoms to observe:"
echo "  - pg_stat_activity shows 40+ sessions with session-level state"
echo "  - Sessions have SET commands in their history"
echo "  - Temp tables and advisory locks present"
echo "  - Connection count higher than expected"
echo ""
echo "The student must identify pinning causes and fix them."
echo ""
echo "To stop early: pkill -f 'pinned_session'"
