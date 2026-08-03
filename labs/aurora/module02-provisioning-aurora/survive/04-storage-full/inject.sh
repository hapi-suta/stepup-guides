#!/usr/bin/env bash
# survive/04-storage-full/inject.sh
# Creates a massive temporary table inside Aurora to simulate unexpected storage growth.
# Also checks and disables storage auto-scaling config if present.
#
# NOTE: Aurora storage auto-scales up to 128 TiB, so this scenario focuses on
# detecting unexpected growth and cleaning it up - not on literally running out of space.
# The real danger is cost: uncontrolled growth means unexpected bills.
#
# Required environment variables:
#   CLUSTER_ID       - Aurora cluster identifier (default: devops-lab-cluster)
#   REGION           - AWS region (default: us-east-1)
#   DB_USER          - Database username (default: clusteradmin)
#   DB_NAME          - Database name (default: devopsdb)
#   PGPASSWORD       - Database password (must be set)
#
# Usage:
#   export CLUSTER_ID=devops-lab-cluster
#   export REGION=us-east-1
#   export PGPASSWORD=YourPassword
#   bash inject.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${REGION:-us-east-1}"
DB_USER="${DB_USER:-clusteradmin}"
DB_NAME="${DB_NAME:-devopsdb}"
DB_PORT="5432"

echo ""
echo "========================================"
echo "  INJECT: Storage Full (Unexpected Growth)"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1 - Get cluster endpoint
# ---------------------------------------------------------------------------
echo "[INFO]  Looking up cluster endpoint..."

CLUSTER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Endpoint" \
  --output text 2>/dev/null)

if [[ -z "$CLUSTER_EP" || "$CLUSTER_EP" == "None" ]]; then
  echo "[FAIL]  Could not find endpoint for cluster $CLUSTER_ID"
  exit 1
fi
echo "[PASS]  Cluster endpoint: $CLUSTER_EP"

# ---------------------------------------------------------------------------
# Step 2 - Check current database size
# ---------------------------------------------------------------------------
echo "[INFO]  Checking current database size..."

DB_SIZE_BEFORE=$(PGPASSWORD="${PGPASSWORD:-}" psql \
  -h "$CLUSTER_EP" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -p "$DB_PORT" \
  -t -A \
  -c "SELECT pg_size_pretty(pg_database_size(current_database()));" 2>/dev/null || echo "unknown")

echo "[INFO]  Database size before injection: $DB_SIZE_BEFORE"

# ---------------------------------------------------------------------------
# Step 3 - Check current Aurora volume usage from CloudWatch
# ---------------------------------------------------------------------------
echo "[INFO]  Checking Aurora volume usage..."

VOLUME_BYTES=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions "Name=DBClusterIdentifier,Value=$CLUSTER_ID" \
  --start-time "$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average \
  --region "$REGION" \
  --query "Datapoints[0].Average" \
  --output text 2>/dev/null || echo "unknown")

if [[ "$VOLUME_BYTES" != "unknown" && "$VOLUME_BYTES" != "None" ]]; then
  VOLUME_GB=$(python3 -c "print(f'{float(\"$VOLUME_BYTES\") / 1073741824:.2f}')" 2>/dev/null || echo "unknown")
  echo "[INFO]  Aurora volume usage: ~${VOLUME_GB} GB"
else
  echo "[INFO]  Could not read volume metrics (may take a few minutes to appear)"
fi

# ---------------------------------------------------------------------------
# Step 4 - Create the bloat table
# ---------------------------------------------------------------------------
echo "[INFO]  Creating storage_bloat table..."

PGPASSWORD="${PGPASSWORD:-}" psql \
  -h "$CLUSTER_EP" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -p "$DB_PORT" \
  -c "DROP TABLE IF EXISTS storage_bloat;" >/dev/null 2>&1 || true

PGPASSWORD="${PGPASSWORD:-}" psql \
  -h "$CLUSTER_EP" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -p "$DB_PORT" \
  -c "CREATE UNLOGGED TABLE storage_bloat (
    id BIGSERIAL,
    payload TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );" >/dev/null

echo "[PASS]  Table created"

# ---------------------------------------------------------------------------
# Step 5 - Insert data in chunks (approximately 2 GB total)
# ---------------------------------------------------------------------------
echo "[INFO]  Inserting data in chunks (this takes 2-5 minutes)..."

for chunk in 1 2 3; do
  echo "[INFO]    Inserting chunk $chunk/3..."
  PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -c "INSERT INTO storage_bloat (payload)
        SELECT repeat(md5(i::text), 8)
        FROM generate_series(1, 3000000) AS s(i);" >/dev/null
  echo "[PASS]    Chunk $chunk complete"
done

# ---------------------------------------------------------------------------
# Step 6 - Show the damage
# ---------------------------------------------------------------------------
BLOAT_SIZE=$(PGPASSWORD="${PGPASSWORD:-}" psql \
  -h "$CLUSTER_EP" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -p "$DB_PORT" \
  -t -A \
  -c "SELECT pg_size_pretty(pg_total_relation_size('storage_bloat'));" 2>/dev/null || echo "unknown")

DB_SIZE_AFTER=$(PGPASSWORD="${PGPASSWORD:-}" psql \
  -h "$CLUSTER_EP" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -p "$DB_PORT" \
  -t -A \
  -c "SELECT pg_size_pretty(pg_database_size(current_database()));" 2>/dev/null || echo "unknown")

ROW_COUNT=$(PGPASSWORD="${PGPASSWORD:-}" psql \
  -h "$CLUSTER_EP" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -p "$DB_PORT" \
  -t -A \
  -c "SELECT count(*) FROM storage_bloat;" 2>/dev/null || echo "unknown")

echo ""
echo "========================================"
echo "  INJECTION COMPLETE"
echo "========================================"
echo ""
echo "  Scenario: Storage Full (Unexpected Growth)"
echo "  An unlogged table 'storage_bloat' was created in $DB_NAME."
echo ""
echo "  Bloat table size: $BLOAT_SIZE"
echo "  Bloat table rows: $ROW_COUNT"
echo "  Database size before: $DB_SIZE_BEFORE"
echo "  Database size after:  $DB_SIZE_AFTER"
echo ""
echo "  NOTE: Aurora storage auto-scales, so the cluster will not"
echo "  literally run out of space. The danger is COST - Aurora"
echo "  charges per GB-month of storage used."
echo ""
echo "  CloudWatch metric VolumeBytesUsed will update in 5-10 minutes."
echo ""
echo "  Now open: survive/04-storage-full/runbook.md"
echo "========================================"
