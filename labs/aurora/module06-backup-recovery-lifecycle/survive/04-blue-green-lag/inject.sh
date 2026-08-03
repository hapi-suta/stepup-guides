#!/usr/bin/env bash
# SURVIVE 04 - inject.sh
# Simulates a Blue/Green deployment where replication lag is too high for switchover.
# A long-running transaction on Blue is blocking logical replication.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 04 - Blue/Green Replication Lag - Injecting Fault"

resolve_cluster_host

# Step 1: Check for an existing Blue/Green deployment
log_info "Checking for an existing Blue/Green deployment..."

BG_COUNT=$(aws rds describe-blue-green-deployments \
    --region "$AWS_REGION" \
    --query 'length(BlueGreenDeployments[?Status==`AVAILABLE`])' \
    --output text 2>/dev/null || echo "0")

if [[ "$BG_COUNT" -eq 0 ]]; then
    log_warn "No AVAILABLE Blue/Green deployment found."
    log_warn "This scenario requires an existing Blue/Green deployment."
    log_warn ""
    log_warn "Please:"
    log_warn "  1. Create a Blue/Green deployment (see BUILD 05)"
    log_warn "  2. Wait for it to reach AVAILABLE status"
    log_warn "  3. Re-run this inject.sh script"
    exit 1
fi

BG_ID=$(aws rds describe-blue-green-deployments \
    --region "$AWS_REGION" \
    --query 'BlueGreenDeployments[?Status==`AVAILABLE`].BlueGreenDeploymentIdentifier' \
    --output text | head -1)

echo "$BG_ID" > "$SURVIVE_TMP/04_bg_id.txt"
log_info "Found Blue/Green deployment: $BG_ID"

# Step 2: Create write workload on Blue to generate lag
log_info "Creating high-write workload on Blue to generate replication lag..."

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
DROP TABLE IF EXISTS lag_generator CASCADE;
CREATE TABLE lag_generator (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
EOF

# Start a long-running open transaction that blocks replication slot cleanup
log_info "Starting a long-running open transaction (blocks replication slot)..."

LOCK_PID_FILE="$SURVIVE_TMP/04_lock_pid.txt"

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" \
    -c "BEGIN; SELECT pg_sleep(300); ROLLBACK;" &
echo $! > "$LOCK_PID_FILE"
log_info "Background transaction started (PID: $(cat $LOCK_PID_FILE))"

# Generate writes while the transaction is open
log_info "Generating 50,000 rows to create replication lag..."
PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
INSERT INTO lag_generator (data)
SELECT md5(random()::TEXT)
FROM generate_series(1, 50000);

SELECT COUNT(*) AS rows_generated FROM lag_generator;
EOF

INCIDENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$INCIDENT_TS" > "$SURVIVE_TMP/04_incident_ts.txt"

log_warn ""
log_warn "SCENARIO DESCRIPTION FOR STUDENT:"
log_warn "===================================="
log_warn "Blue/Green deployment $BG_ID is in AVAILABLE state."
log_warn "The team wants to switchover, but replication lag on Green is high."
log_warn "AWS is refusing the switchover due to lag."
log_warn ""
log_warn "Observed symptoms:"
log_warn "  - Green replication lag > 30 seconds"
log_warn "  - A background process is holding an open transaction on Blue"
log_warn ""
log_warn "Student objective:"
log_warn "  1. Diagnose the cause of high replication lag"
log_warn "  2. Resolve the blocking condition"
log_warn "  3. Confirm lag drops below 5 seconds"
log_warn "  4. Execute the switchover"
log_warn ""
log_warn "Hint: Check pg_stat_activity for idle-in-transaction sessions."
