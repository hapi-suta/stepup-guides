#!/usr/bin/env bash
# survive/04-memory-pressure/inject.sh
# Injects: work_mem set too high, memory pressure building
# Difficulty: Hard

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "INJECT: Memory Pressure"
log "Setting work_mem dangerously high and launching concurrent sort queries"

# Get current RAM estimate from shared_buffers
SB=$(psql_exec "SELECT setting FROM pg_settings WHERE name = 'shared_buffers'")
log "Current shared_buffers pages: $SB"

# Set work_mem very high - 512MB per operation
# On a 4GB instance with 200 connections, this could exhaust RAM
psql_exec "
-- Record original work_mem
CREATE TABLE IF NOT EXISTS survive_params AS
SELECT setting AS original_work_mem FROM pg_settings WHERE name = 'work_mem';
"

log "Injecting high work_mem via ALTER ROLE (simulates misconfiguration)..."

# We use ALTER ROLE to persist the setting (simulates a config error)
psql_exec "ALTER ROLE ${DB_USER} SET work_mem = '512MB';"

echo "$(date)" > "${SURVIVE_LOG_DIR}/04-inject-time.txt"

# Now launch many concurrent queries that will each allocate 512MB for sorts
log "Launching 20 concurrent sort queries (each may allocate 512MB)..."

for i in $(seq 1 20); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT pg_sleep(0.1);
SELECT s1.n, s2.n, random() AS r
FROM generate_series(1, 10000) s1(n)
CROSS JOIN generate_series(1, 10) s2(n)
ORDER BY r
LIMIT 1000;" &>/dev/null &
done

log "Memory pressure scenario launched"

echo ""
echo "=========================================="
echo "SCENARIO INJECTED: Memory Pressure"
echo "=========================================="
echo ""
echo "What is happening:"
echo "  - ALTER ROLE set work_mem = 512MB for all new connections"
echo "  - 20 concurrent queries are each allocating up to 512MB for sorts"
echo "  - Combined potential: 20 * 512MB * 3 ops = 30GB (exceeds most instances)"
echo "  - FreeableMemory is dropping; swap may be used on smaller instances"
echo ""
echo "Symptoms to observe:"
echo "  - CloudWatch FreeableMemory dropping rapidly"
echo "  - Performance Insights: IO:BufFileRead (if OOM killer kicks in, sort spills)"
echo "  - Possible OOM errors in PostgreSQL log"
echo ""
echo "Original work_mem stored in: survive_params table"
echo ""
echo "To stop the background queries: pkill -f 'psql.*generate_series'"
