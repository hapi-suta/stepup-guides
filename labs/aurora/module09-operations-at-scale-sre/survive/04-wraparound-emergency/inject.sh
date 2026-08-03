#!/bin/bash
# =============================================================================
# SURVIVE Scenario 04: Wraparound Emergency
# INJECT - Simulates an XID wraparound risk by creating tables with disabled
#          autovacuum and advancing the transaction age.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

STATE_FILE="${M09_STATE_DIR}/04-wraparound-emergency.state"

print_survive_warning "Wraparound Emergency (XID Exhaustion Risk)"

# ---------------------------------------------------------------------------
log_step 1 "Create test tables with autovacuum disabled"
# ---------------------------------------------------------------------------

cat > "${STATE_FILE}" <<EOF
INJECT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TABLES_CREATED=true
EOF

# Create tables with autovacuum disabled (simulates misconfigured tables)
run_sql "
CREATE TABLE IF NOT EXISTS m09_wraparound_test1 (
    id serial PRIMARY KEY,
    data text,
    created_at timestamptz DEFAULT now()
) WITH (autovacuum_enabled = false);

CREATE TABLE IF NOT EXISTS m09_wraparound_test2 (
    id serial PRIMARY KEY,
    payload jsonb,
    updated_at timestamptz DEFAULT now()
) WITH (autovacuum_enabled = false);

CREATE TABLE IF NOT EXISTS m09_wraparound_test3 (
    id serial PRIMARY KEY,
    description text
) WITH (autovacuum_enabled = false);
"

log_success "Created 3 tables with autovacuum DISABLED"

# ---------------------------------------------------------------------------
log_step 2 "Generate transaction churn to age the tables"
# ---------------------------------------------------------------------------

log_info "Inserting rows and updating to generate dead tuples..."

# Insert rows
run_sql "
INSERT INTO m09_wraparound_test1 (data)
SELECT 'row-' || generate_series(1, 10000);

INSERT INTO m09_wraparound_test2 (payload)
SELECT jsonb_build_object('key', generate_series(1, 10000), 'ts', now());

INSERT INTO m09_wraparound_test3 (description)
SELECT 'description-' || generate_series(1, 10000);
"

log_success "Inserted 10,000 rows per table"

# Update rows to create dead tuples (since autovacuum is disabled, they accumulate)
run_sql "
UPDATE m09_wraparound_test1 SET data = data || '-updated' WHERE id <= 5000;
UPDATE m09_wraparound_test2 SET payload = payload || '{\"updated\": true}' WHERE id <= 5000;
UPDATE m09_wraparound_test3 SET description = description || '-v2' WHERE id <= 5000;
"

log_success "Updated 5,000 rows per table (creating dead tuples)"

# Delete some rows to create more dead tuples
run_sql "
DELETE FROM m09_wraparound_test1 WHERE id > 8000;
DELETE FROM m09_wraparound_test2 WHERE id > 8000;
DELETE FROM m09_wraparound_test3 WHERE id > 8000;
"

log_success "Deleted 2,000 rows per table (more dead tuples)"

# ---------------------------------------------------------------------------
log_step 3 "Verify autovacuum is disabled and dead tuples are accumulating"
# ---------------------------------------------------------------------------

DEAD_TUPLES=$(run_sql "
SELECT
    schemaname || '.' || relname AS table_name,
    n_dead_tup,
    n_live_tup,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname LIKE 'm09_wraparound%'
ORDER BY relname;
")

log_info "Dead tuple status:"
echo "${DEAD_TUPLES}"

# ---------------------------------------------------------------------------
log_step 4 "Check current database age"
# ---------------------------------------------------------------------------

DB_AGE=$(run_sql "
SELECT
    datname,
    age(datfrozenxid) AS age,
    CASE
        WHEN age(datfrozenxid) > 1000000000 THEN 'CRITICAL'
        WHEN age(datfrozenxid) > 500000000 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM pg_database
WHERE datname = '${M09_DB_NAME}';
")

log_info "Database age: ${DB_AGE}"

TABLE_AGE=$(run_sql "
SELECT
    c.relname,
    age(c.relfrozenxid) AS age,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname LIKE 'm09_wraparound%'
  AND c.relkind = 'r'
ORDER BY age(c.relfrozenxid) DESC;
")

log_info "Table ages:"
echo "${TABLE_AGE}"

# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  INJECTION COMPLETE"
echo "========================================="
echo ""
echo "  Problems injected:"
echo "  1. Three tables created with autovacuum DISABLED"
echo "  2. Dead tuples accumulating (updates and deletes without vacuum)"
echo "  3. Transaction age growing on these tables"
echo ""
echo "  Your mission:"
echo "  - Identify tables at risk of XID wraparound"
echo "  - Check autovacuum status and dead tuple counts"
echo "  - Run VACUUM FREEZE on affected tables"
echo "  - Re-enable autovacuum on all tables"
echo "  - Run validate.sh to verify your fixes"
echo ""
echo "  Hint: In a real wraparound emergency, the database"
echo "  refuses ALL writes to prevent data corruption."
echo "  Early detection is critical."
echo ""
echo "========================================="
