#!/usr/bin/env bash
# SURVIVE 03 - inject.sh
# Simulates a failed major version upgrade where the application is broken
# after the upgrade completed.
#
# This script simulates the POST-failure state:
#   - A pre-upgrade snapshot exists
#   - The current cluster has been "upgraded" but the application is broken
#   - Student must roll back to the pre-upgrade snapshot

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 03 - Upgrade Failure - Injecting Fault"

resolve_cluster_host

# Step 1: Create application data
log_info "Setting up application data before simulated upgrade..."

PGPASSWORD="${PGPASSWORD:-}" psql -h "$CLUSTER_HOST" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
DROP TABLE IF EXISTS app_config CASCADE;
DROP TABLE IF EXISTS app_users CASCADE;

CREATE TABLE app_users (
    id SERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT NOT NULL,
    role TEXT DEFAULT 'viewer',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO app_users (username, email, role)
SELECT
    'user_' || i,
    'user' || i || '@example.com',
    (ARRAY['viewer','editor','admin'])[floor(random()*3+1)]
FROM generate_series(1, 100) AS s(i);

INSERT INTO app_config (key, value) VALUES
    ('feature_dark_mode', 'enabled'),
    ('max_upload_size_mb', '50'),
    ('session_timeout_minutes', '30'),
    ('maintenance_mode', 'false');

SELECT 'app_users' AS tbl, COUNT(*) FROM app_users
UNION ALL SELECT 'app_config', COUNT(*) FROM app_config;
EOF

# Step 2: Take the "pre-upgrade" snapshot
log_info "Taking pre-upgrade snapshot..."

SNAPSHOT_ID="devops-lab-survive03-pre-upgrade-$(date +%Y%m%d%H%M%S)"
echo "$SNAPSHOT_ID" > "$SURVIVE_TMP/03_snapshot_id.txt"

aws rds create-db-cluster-snapshot \
    --db-cluster-identifier "$CLUSTER_ID" \
    --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
    --region "$AWS_REGION" > /dev/null

log_info "Waiting for pre-upgrade snapshot..."
aws rds wait db-cluster-snapshot-available \
    --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
    --region "$AWS_REGION"

log_ok "Pre-upgrade snapshot ready: $SNAPSHOT_ID"

# Step 3: Record checksums
ROW_COUNT=$(run_sql "SELECT COUNT(*) FROM app_users;")
CONFIG_COUNT=$(run_sql "SELECT COUNT(*) FROM app_config;")
ADMIN_COUNT=$(run_sql "SELECT COUNT(*) FROM app_users WHERE role = 'admin';")
echo "$ROW_COUNT" > "$SURVIVE_TMP/03_user_rowcount.txt"
echo "$CONFIG_COUNT" > "$SURVIVE_TMP/03_config_count.txt"
echo "$ADMIN_COUNT" > "$SURVIVE_TMP/03_admin_count.txt"

# Step 4: Simulate the post-upgrade breakage
log_warn "Simulating post-upgrade breakage..."

INCIDENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$INCIDENT_TS" > "$SURVIVE_TMP/03_incident_ts.txt"

log_warn ""
log_warn "SCENARIO DESCRIPTION FOR STUDENT:"
log_warn "===================================="
log_warn "A major version upgrade from PostgreSQL 15 to 16 was attempted."
log_warn "The upgrade completed but the application cannot function."
log_warn "Application errors: 'function uuid_generate_v4() does not exist'"
log_warn "The uuid-ossp extension was not upgraded after the major upgrade."
log_warn "Rollback decision: the team decides to roll back to pre-upgrade state."
log_warn ""
log_warn "Available resources:"
log_warn "  - Pre-upgrade snapshot: $SNAPSHOT_ID"
log_warn "  - Current (broken) cluster: $CLUSTER_ID"
log_warn ""
log_warn "Student objective: Roll back to the pre-upgrade snapshot."
log_warn "Restore from snapshot, verify data integrity, fix the root cause."
