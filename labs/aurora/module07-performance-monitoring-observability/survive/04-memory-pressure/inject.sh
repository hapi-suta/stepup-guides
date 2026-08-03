#!/usr/bin/env bash
# survive/04-memory-pressure/inject.sh
# Injects: Memory pressure from multiple large sort operations exhausting work_mem
# Difficulty: Hard
# Idempotent: Yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "INJECT: Memory Pressure"
echo "============================================"
echo ""

pkill -f "psql.*memory_hog" 2>/dev/null || true
sleep 2

# Create a large table
echo "Creating large table for memory pressure..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
DROP TABLE IF EXISTS memory_test;
CREATE TABLE memory_test (
    id BIGSERIAL PRIMARY KEY,
    user_id INT,
    data TEXT,
    amount NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO memory_test (user_id, data, amount)
SELECT
    (random() * 500000)::INT,
    repeat(md5(random()::TEXT), 5),
    (random() * 10000)::NUMERIC(12,2)
FROM generate_series(1, 3000000);
ANALYZE memory_test;
SQL

echo "Table created with 3M rows"
date > "${LOG_DIR}/inject-time.txt"

# Launch multiple sessions with high work_mem doing large sorts
echo "Launching 15 concurrent memory-hungry queries..."
for i in $(seq 1 15); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 \
        -c "SET application_name = 'memory_hog_${i}';
            SET work_mem = '256MB';
            SELECT user_id, data, sum(amount) OVER (PARTITION BY user_id ORDER BY created_at)
            FROM memory_test
            ORDER BY amount DESC;" &>/dev/null &
done

sleep 5

echo ""
echo "============================================"
echo "SCENARIO INJECTED: Memory Pressure"
echo "============================================"
echo ""
echo "What is happening:"
echo "  - 15 sessions each set work_mem = 256MB"
echo "  - Each runs a window function + sort on 3M rows"
echo "  - Worst case: 15 * 256MB = 3.8GB of sort memory"
echo "  - This competes with shared_buffers for RAM"
echo ""
echo "Symptoms to observe:"
echo "  - CloudWatch FreeableMemory dropping rapidly"
echo "  - IO:BufFileRead in Performance Insights (sorts spilling)"
echo "  - Swap usage increasing in Enhanced Monitoring"
echo "  - New queries running slower due to cache eviction"
echo ""
echo "To stop early: pkill -f 'memory_hog'"
