#!/usr/bin/env bash
# survive/02-autovacuum-blocked/inject.sh
# Injects: Long-running transaction blocking autovacuum, table bloating
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
echo "INJECT: Autovacuum Blocked"
echo "============================================"
echo ""

# Clean up previous injection
pkill -f "psql.*autovacuum_blocker" 2>/dev/null || true
sleep 2

# Create the target table
echo "Creating bloat_target table with 500K rows..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
DROP TABLE IF EXISTS bloat_target;
CREATE TABLE bloat_target (
    id BIGSERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    updated_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO bloat_target (data, status)
SELECT md5(random()::TEXT), 'active'
FROM generate_series(1, 500000);
ANALYZE bloat_target;
SQL

echo "Table created with 500K rows"

# Record baseline
BASELINE_DEAD=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bloat_target';" | tr -d ' ')
echo "$BASELINE_DEAD" > "${LOG_DIR}/baseline-dead.txt"
echo "Baseline dead tuples: $BASELINE_DEAD"

# Start a long-running transaction that blocks autovacuum
echo "Starting long-running transaction (holds for 20 minutes)..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=0 \
    -c "SET application_name = 'autovacuum_blocker'; BEGIN; SELECT count(*) FROM bloat_target; SELECT pg_sleep(1200);" &>/dev/null &
BLOCKER_PID=$!
echo "$BLOCKER_PID" > "${LOG_DIR}/blocker-pid.txt"

sleep 3

# Generate lots of dead tuples
echo "Generating dead tuples..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
UPDATE bloat_target SET status = 'updated', updated_at = now() WHERE id % 2 = 0;
UPDATE bloat_target SET status = 'active', updated_at = now() WHERE id % 2 = 0;
UPDATE bloat_target SET data = md5(random()::TEXT) WHERE id % 3 = 0;
DELETE FROM bloat_target WHERE id % 10 = 0;
SQL

CURRENT_DEAD=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bloat_target';" 2>/dev/null | tr -d ' ')

echo ""
echo "============================================"
echo "SCENARIO INJECTED: Autovacuum Blocked"
echo "============================================"
echo ""
echo "Dead tuples after updates: $CURRENT_DEAD"
echo ""
echo "What is happening:"
echo "  - A long-running transaction holds an old snapshot"
echo "  - Autovacuum cannot remove dead tuples older than that snapshot"
echo "  - The bloat_target table is accumulating dead tuples"
echo ""
echo "Symptoms to observe:"
echo "  - pg_stat_user_tables shows rising n_dead_tup for bloat_target"
echo "  - pg_stat_activity shows a very old transaction"
echo "  - Autovacuum runs but cannot clean old rows"
echo ""
echo "To stop early: kill $BLOCKER_PID"
