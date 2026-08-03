#!/usr/bin/env bash
# survive/03-slow-query-cascade/inject.sh
# Injects: One bad query consuming all CPU, causing cascade of slow queries
# Difficulty: Hard
# Idempotent: Yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then
    source "${SCRIPT_DIR}/../config.sh"
fi

: "${DB_ENDPOINT:?Set DB_ENDPOINT}"
: "${DB_PORT:=5432}"
: "${DB_USER:?Set DB_USER}"
: "${DB_NAME:?Set DB_NAME}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "INJECT: Slow Query Cascade"
echo "============================================"
echo ""

# Clean up previous injection
pkill -f "psql.*slow_cascade" 2>/dev/null || true
sleep 2

# Create the test table
echo "Creating large table for slow queries..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
DROP TABLE IF EXISTS cascade_test;
CREATE TABLE cascade_test (
    id BIGSERIAL PRIMARY KEY,
    user_id INT,
    category TEXT,
    payload TEXT,
    amount NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO cascade_test (user_id, category, payload, amount)
SELECT
    (random() * 100000)::INT,
    CASE (random() * 5)::INT WHEN 0 THEN 'A' WHEN 1 THEN 'B' WHEN 2 THEN 'C' WHEN 3 THEN 'D' ELSE 'E' END,
    repeat(md5(random()::TEXT), 10),
    (random() * 10000)::NUMERIC(12,2)
FROM generate_series(1, 2000000);
ANALYZE cascade_test;
SQL

echo "Table created with 2M rows (no indexes on filter columns)"
date > "${LOG_DIR}/inject-time.txt"

# Launch 10 concurrent bad queries that will saturate CPU
echo "Launching 10 concurrent CPU-saturating queries..."
for i in $(seq 1 10); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 \
        -c "SET application_name = 'slow_cascade_${i}';
            SELECT count(DISTINCT md5(payload || category || id::text)), avg(amount)
            FROM cascade_test
            WHERE category IN ('A','B','C')
            GROUP BY user_id
            HAVING count(*) > 1
            ORDER BY avg(amount) DESC;" &>/dev/null &
done

sleep 3

echo ""
echo "============================================"
echo "SCENARIO INJECTED: Slow Query Cascade"
echo "============================================"
echo ""
echo "What is happening:"
echo "  - 10 concurrent queries are doing full table scans on 2M rows"
echo "  - Each computes md5 on every row (CPU intensive)"
echo "  - No index exists for the filter conditions"
echo "  - CPU is saturated, causing all other queries to slow down"
echo ""
echo "Symptoms to observe:"
echo "  - CloudWatch CPUUtilization spike to 90%+"
echo "  - Performance Insights shows CPU as dominant wait"
echo "  - Simple queries (SELECT 1) take much longer than normal"
echo "  - DB Load exceeds vCPU count"
echo ""
echo "To stop early: pkill -f 'slow_cascade'"
