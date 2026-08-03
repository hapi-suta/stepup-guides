#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 04: Transaction ID Wraparound Approaching
#
# What this script does:
#   1. Creates a test database with a table that has autovacuum disabled.
#   2. Populates it with data that generates many dead tuples (simulating
#      a high-churn table that autovacuum has not been keeping up with).
#   3. Disables autovacuum globally via the parameter group temporarily.
#   4. Simulates the monitoring alert that would fire in production.
#
# NOTE: This scenario cannot actually advance the transaction ID age counter
# to dangerous levels in a short lab environment (would require running
# 2 billion transactions). Instead, it simulates the TABLE-level conditions
# that precede wraparound and presents the diagnostic approach.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 04: Transaction ID Wraparound Emergency"
print_survive_warning "Wraparound Emergency"

t8_validate_config || exit 1
check_prerequisites || exit 1
check_aws_auth || exit 1
check_db_connectivity || {
  log_error "Cannot connect to database. Set T8_DB_HOST."
  exit 1
}

record_start

# -----------------------------------------------------------------------
# Step 1: Create a test database/table with autovacuum disabled
# -----------------------------------------------------------------------
log_step "Step 1: Creating test table with autovacuum disabled..."

run_sql "CREATE TABLE IF NOT EXISTS t8_high_churn_events (
  id serial PRIMARY KEY,
  event_type text,
  payload text,
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
) WITH (autovacuum_enabled = false);"

log_info "Table t8_high_churn_events created with autovacuum_enabled=false"

# -----------------------------------------------------------------------
# Step 2: Generate dead tuples by inserting and updating many rows
# -----------------------------------------------------------------------
log_step "Step 2: Generating dead tuples (simulating high-churn workload)..."
log_info "This takes 30-60 seconds..."

run_sql "DO \$\$
DECLARE
  i integer;
BEGIN
  -- Insert 50,000 rows
  FOR i IN 1..50000 LOOP
    INSERT INTO t8_high_churn_events (event_type, payload)
    VALUES ('order_created', md5(random()::text));
  END LOOP;

  -- Update all rows multiple times (creates dead tuples)
  FOR i IN 1..5 LOOP
    UPDATE t8_high_churn_events SET status = 'processed_' || i;
    RAISE NOTICE 'Completed update round %', i;
  END LOOP;

  -- Delete 80% of rows (creates even more dead tuples)
  DELETE FROM t8_high_churn_events WHERE id % 5 != 0;

  RAISE NOTICE 'Workload complete';
END;
\$\$;"

# -----------------------------------------------------------------------
# Step 3: Slow down autovacuum to simulate it falling behind
# -----------------------------------------------------------------------
log_step "Step 3: Configuring autovacuum to move slowly..."

if [[ -n "${T8_PARAMETER_GROUP}" ]]; then
  # Store original values
  ORIG_COST_DELAY=$(get_parameter_value "autovacuum_vacuum_cost_delay")
  ORIG_SLEEP=$(get_parameter_value "autovacuum_naptime")

  aws rds modify-db-parameter-group \
    --db-parameter-group-name "${T8_PARAMETER_GROUP}" \
    --parameters \
      ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=200,ApplyMethod=immediate \
      ParameterName=autovacuum_naptime,ParameterValue=3600,ApplyMethod=immediate \
    --region "${T8_REGION}"

  log_warn "Autovacuum heavily throttled (cost_delay=200ms, naptime=1 hour)"
else
  log_warn "T8_PARAMETER_GROUP not set - skipping autovacuum parameter changes."
fi

# -----------------------------------------------------------------------
# Step 4: Show the current state - what the monitoring alert would show
# -----------------------------------------------------------------------
log_step "Step 4: Capturing current database state..."

XID_AGE=$(run_sql "
  SELECT datname, age(datfrozenxid) AS xid_age,
         round(age(datfrozenxid) * 100.0 / 2000000000, 4) AS pct_of_limit
  FROM pg_database
  WHERE datname = current_database();" 2>/dev/null || echo "ERROR")

DEAD_TUPLE_DATA=$(run_sql "
  SELECT n_live_tup, n_dead_tup,
         round(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
         last_autovacuum
  FROM pg_stat_user_tables
  WHERE relname = 't8_high_churn_events';" 2>/dev/null || echo "ERROR")

echo ""
log_warn "========================================================"
log_warn "INJECTION COMPLETE"
log_warn "========================================================"
echo ""
echo "Current database state:"
echo "${XID_AGE}"
echo ""
echo "t8_high_churn_events table stats:"
echo "${DEAD_TUPLE_DATA}"
echo ""
echo "Your scenario:"
echo "  Your wraparound monitoring Lambda has fired:"
echo ""
echo "  CRITICAL: Wraparound Risk Detected"
echo "  Database: ${T8_DB_NAME}"
echo "  age(datfrozenxid): [HIGH VALUE]"
echo "  Table: t8_high_churn_events"
echo "    - autovacuum_enabled: false (manually disabled)"
echo "    - Dead tuple ratio: very high"
echo "    - Last autovacuum: NEVER"
echo "  Autovacuum: throttled (running very slowly)"
echo ""
echo "  Your tasks:"
echo "    a. Confirm wraparound proximity using SQL queries"
echo "    b. Identify which tables are most at risk"
echo "    c. Run manual VACUUM FREEZE on the affected table"
echo "    d. Restore autovacuum to healthy settings"
echo "    e. Re-enable autovacuum on the affected table"
echo "    f. Document what systemic change prevents this"
echo ""
echo "Key queries to run:"
echo "  -- Wraparound check:"
echo "  SELECT datname, age(datfrozenxid), 2000000000 - age(datfrozenxid) AS remaining"
echo "  FROM pg_database ORDER BY age(datfrozenxid) DESC;"
echo ""
echo "  -- Table-level freeze check:"
echo "  SELECT relname, age(relfrozenxid) FROM pg_class"
echo "  JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace"
echo "  WHERE relkind = 'r' ORDER BY age(relfrozenxid) DESC LIMIT 10;"
echo ""

# Save state
cat > "${SCRIPT_DIR}/.inject-state" << EOF
INJECT_TIME=$(date +%s)
ORIG_COST_DELAY=${ORIG_COST_DELAY:-20}
ORIG_SLEEP=${ORIG_SLEEP:-60}
EOF

log_info "Inject state saved."
