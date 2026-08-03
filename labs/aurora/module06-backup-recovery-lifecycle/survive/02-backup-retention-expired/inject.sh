#!/usr/bin/env bash
# SURVIVE 02 - inject.sh
# Simulates a situation where the needed backup is outside the retention window.
# A manual snapshot is the only recovery point available.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 02 - Backup Retention Expired - Injecting Fault"

resolve_cluster_host

# Step 1: Create data in the database
log_info "Setting up test data..."

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
DROP TABLE IF EXISTS billing_records CASCADE;

CREATE TABLE billing_records (
    id SERIAL PRIMARY KEY,
    account_id TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    billed_at TIMESTAMPTZ DEFAULT now(),
    paid BOOLEAN DEFAULT false
);

INSERT INTO billing_records (account_id, amount, paid)
SELECT
    'ACC-' || LPAD(i::TEXT, 5, '0'),
    (random() * 5000)::NUMERIC(12,2),
    (random() > 0.5)
FROM generate_series(1, 500) AS s(i);

SELECT COUNT(*) AS row_count, SUM(amount)::NUMERIC(12,2) AS total FROM billing_records;
EOF

# Step 2: Take a manual snapshot NOW (this is the only restorable point)
log_info "Taking a manual snapshot (this simulates the last known good snapshot)..."

SNAPSHOT_ID="devops-lab-survive02-last-good-$(date +%Y%m%d%H%M%S)"
echo "$SNAPSHOT_ID" > "$SURVIVE_TMP/02_snapshot_id.txt"

aws rds create-db-cluster-snapshot \
    --db-cluster-identifier "$CLUSTER_ID" \
    --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
    --region "$AWS_REGION" > /dev/null

log_info "Waiting for snapshot to become available..."
aws rds wait db-cluster-snapshot-available \
    --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
    --region "$AWS_REGION"

log_ok "Snapshot ready: $SNAPSHOT_ID"

# Step 3: Record checksum before fault
ROW_COUNT=$(run_sql "SELECT COUNT(*) FROM billing_records;")
CHECKSUM=$(run_sql "SELECT SUM(amount)::NUMERIC(12,2) FROM billing_records;")
echo "$ROW_COUNT" > "$SURVIVE_TMP/02_rowcount.txt"
echo "$CHECKSUM" > "$SURVIVE_TMP/02_checksum.txt"

# Step 4: Set backup retention to minimum (1 day for Aurora - cannot be 0)
# and simulate that the needed PITR point is outside the window
log_warn "Setting backup retention to 1 day (minimum for Aurora)..."

aws rds modify-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --backup-retention-period 1 \
    --apply-immediately \
    --region "$AWS_REGION" > /dev/null

# Step 5: Wait for modification
log_info "Waiting for modification to apply..."
aws rds wait db-cluster-available \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION"

# Step 6: Corrupt the data (simulate the incident)
log_warn "Injecting fault: truncating billing_records..."

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" \
    -c "TRUNCATE TABLE billing_records;"

INCIDENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$INCIDENT_TS" > "$SURVIVE_TMP/02_incident_ts.txt"

log_warn "Fault injected at: $INCIDENT_TS"
log_warn ""
log_warn "Situation summary:"
log_warn "  - billing_records table has been TRUNCATED (all 500 rows gone)"
log_warn "  - Backup retention is set to 1 day (minimum for Aurora)"
log_warn "  - The incident you need to recover from happened BEFORE the retention window"
log_warn "  - PITR cannot reach far enough back to recover"
log_warn "  - One manual snapshot exists: $SNAPSHOT_ID"
log_warn ""
log_warn "Student objective: Restore billing_records from the available snapshot."
log_warn "PITR alone is not sufficient. Use the manual snapshot."
