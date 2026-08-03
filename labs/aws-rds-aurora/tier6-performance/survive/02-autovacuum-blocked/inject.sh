#!/usr/bin/env bash
# survive/02-autovacuum-blocked/inject.sh
# Injects: Autovacuum cannot run, table bloating due to long-running transaction
# Difficulty: Hard

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "INJECT: Autovacuum Blocked"
log "Creating bloat table and blocking autovacuum with a long-running transaction"

# Create the target table
psql_exec "
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
"

log "Table created with 500K rows"

# Record baseline
BASELINE_DEAD=$(psql_exec "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bloat_target'")
echo "$BASELINE_DEAD" > "${SURVIVE_LOG_DIR}/02-baseline-dead.txt"
log "Baseline dead tuples: $BASELINE_DEAD"

# Start a long-running transaction that blocks autovacuum
# This runs in background and holds for 20 minutes
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "BEGIN; SELECT count(*) FROM bloat_target; SELECT pg_sleep(1200);" &>/dev/null &
BLOCKER_PID=$!
echo "$BLOCKER_PID" > "${SURVIVE_LOG_DIR}/02-blocker-pid.txt"
log "Long-running transaction started (PID $BLOCKER_PID, holds for 20 minutes)"

sleep 3

# Now generate lots of dead tuples
psql_exec "
UPDATE bloat_target SET status = 'updated', updated_at = now() WHERE id % 2 = 0;
UPDATE bloat_target SET status = 'active', updated_at = now() WHERE id % 2 = 0;
UPDATE bloat_target SET data = md5(random()::TEXT) WHERE id % 3 = 0;
DELETE FROM bloat_target WHERE id % 10 = 0;
"

CURRENT_DEAD=$(psql_exec "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bloat_target'" || echo "?")
log "Dead tuples after updates: $CURRENT_DEAD"

echo ""
echo "=========================================="
echo "SCENARIO INJECTED: Autovacuum Blocked"
echo "=========================================="
echo ""
echo "What is happening:"
echo "  - A long-running transaction is holding an old snapshot"
echo "  - Autovacuum cannot remove dead tuples older than that snapshot"
echo "  - The bloat_target table is accumulating dead tuples"
echo "  - Over time, the table will bloat significantly"
echo ""
echo "Symptoms to observe:"
echo "  - pg_stat_user_tables shows rising n_dead_tup for bloat_target"
echo "  - pg_stat_activity shows a very old transaction"
echo "  - Autovacuum runs but cannot clean old rows"
echo ""
echo "To stop the blocker manually: kill $BLOCKER_PID"
