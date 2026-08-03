#!/usr/bin/env bash
# SURVIVE 01 - inject.sh
# Simulates an accidental DROP TABLE on a critical table.
# Run this script ONCE to set up the scenario. Then hand off to the student.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 01 - Accidental Table Drop - Injecting Fault"

resolve_cluster_host

# Step 1: Create the target table with data
log_info "Creating critical_orders table with production-like data..."

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
DROP TABLE IF EXISTS critical_orders CASCADE;

CREATE TABLE critical_orders (
    id SERIAL PRIMARY KEY,
    customer_ref TEXT NOT NULL,
    order_total NUMERIC(12,2) NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO critical_orders (customer_ref, order_total, status)
SELECT
    'CUST-' || LPAD(i::TEXT, 6, '0'),
    (random() * 10000)::NUMERIC(12,2),
    (ARRAY['pending','processing','completed','refunded'])[floor(random()*4+1)]
FROM generate_series(1, 1000) AS s(i);

SELECT COUNT(*) AS injected_rows FROM critical_orders;
EOF

# Step 2: Record the pre-drop checksum
log_info "Recording pre-drop state..."

CHECKSUM=$(run_sql "SELECT SUM(order_total)::NUMERIC(12,2) FROM critical_orders;")
ROW_COUNT=$(run_sql "SELECT COUNT(*) FROM critical_orders;")

echo "$CHECKSUM" > "$SURVIVE_TMP/01_checksum.txt"
echo "$ROW_COUNT" > "$SURVIVE_TMP/01_rowcount.txt"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SURVIVE_TMP/01_pre_drop_time.txt"

log_info "Pre-drop row count: $ROW_COUNT"
log_info "Pre-drop sum: $CHECKSUM"

# Step 3: Wait for backup data to sync
log_info "Waiting 60 seconds for backup data to sync to S3..."
sleep 60

# Step 4: Record the "good state" timestamp
GOOD_STATE_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$GOOD_STATE_TS" > "$SURVIVE_TMP/01_good_state_ts.txt"
log_info "Good state timestamp: $GOOD_STATE_TS"

# Step 5: Drop the table (the fault)
log_info "Injecting fault: DROP TABLE critical_orders..."

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" \
    -c "DROP TABLE critical_orders;"

INCIDENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$INCIDENT_TS" > "$SURVIVE_TMP/01_incident_ts.txt"

log_warn "Fault injected at: $INCIDENT_TS"
log_warn "Table critical_orders has been dropped."
log_warn ""
log_warn "Student objective: Recover the table and all 1000 rows within 30 minutes."
log_warn "The pre-drop checksum is stored in $SURVIVE_TMP/01_checksum.txt"
log_warn "(Do NOT share checksum with student until they attempt recovery.)"
