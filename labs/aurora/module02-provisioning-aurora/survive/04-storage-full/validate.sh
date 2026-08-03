#!/usr/bin/env bash
# survive/04-storage-full/validate.sh
# Verifies the storage bloat has been cleaned up and the cluster is healthy.
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
#   bash validate.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${REGION:-us-east-1}"
DB_USER="${DB_USER:-clusteradmin}"
DB_NAME="${DB_NAME:-devopsdb}"
DB_PORT="5432"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "[PASS]  $1"
  (( PASS_COUNT++ )) || true
}

fail() {
  echo "[FAIL]  $1"
  if [[ -n "${2:-}" ]]; then
    echo "        Hint: $2"
  fi
  (( FAIL_COUNT++ )) || true
}

warn() {
  echo "[WARN]  $1"
}

echo ""
echo "========================================"
echo "  VALIDATE: Storage Full"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Get cluster endpoint
# ---------------------------------------------------------------------------
CLUSTER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Endpoint" \
  --output text 2>/dev/null || echo "")

# ---------------------------------------------------------------------------
# Check 1 - Cluster is available
# ---------------------------------------------------------------------------
echo "[INFO]  Check 1: Aurora cluster is available"

CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Status" \
  --output text 2>/dev/null || echo "not-found")

if [[ "$CLUSTER_STATUS" == "available" ]]; then
  pass "Aurora cluster $CLUSTER_ID is available"
else
  fail "Aurora cluster status: $CLUSTER_STATUS" "Expected: available"
fi

# ---------------------------------------------------------------------------
# Check 2 - Can connect to the database
# ---------------------------------------------------------------------------
echo "[INFO]  Check 2: psql connection works"

if [[ -n "$CLUSTER_EP" ]]; then
  QUERY_RESULT=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT 'connected'" 2>/dev/null || echo "failed")

  if [[ "$QUERY_RESULT" == "connected" ]]; then
    pass "psql connection and query successful"
  else
    fail "psql connection failed"
  fi
else
  fail "No cluster endpoint found"
fi

# ---------------------------------------------------------------------------
# Check 3 - Bloat table is gone
# ---------------------------------------------------------------------------
echo "[INFO]  Check 3: Bloat table has been removed"

if [[ -n "$CLUSTER_EP" ]]; then
  BLOAT_EXISTS=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT EXISTS(SELECT 1 FROM pg_tables WHERE tablename='storage_bloat' AND schemaname='public')" 2>/dev/null || echo "error")

  if [[ "$BLOAT_EXISTS" == "f" ]]; then
    pass "Bloat table 'storage_bloat' has been dropped"
  elif [[ "$BLOAT_EXISTS" == "t" ]]; then
    fail "Bloat table 'storage_bloat' still exists" \
      "Run in psql: DROP TABLE storage_bloat;"
  else
    warn "Could not check bloat table existence (psql may have failed)"
  fi
fi

# ---------------------------------------------------------------------------
# Check 4 - Database size is reasonable
# ---------------------------------------------------------------------------
echo "[INFO]  Check 4: Database size is reasonable (under 500 MB)"

if [[ -n "$CLUSTER_EP" ]]; then
  DB_SIZE_BYTES=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT pg_database_size(current_database())" 2>/dev/null || echo "0")

  DB_SIZE_MB=$(python3 -c "print(f'{int(\"${DB_SIZE_BYTES}\") / 1048576:.1f}')" 2>/dev/null || echo "unknown")

  # 500 MB threshold - if the database is larger, bloat may still exist
  if python3 -c "exit(0 if int('${DB_SIZE_BYTES}') < 524288000 else 1)" 2>/dev/null; then
    pass "Database size: ${DB_SIZE_MB} MB (under 500 MB threshold)"
  else
    fail "Database size: ${DB_SIZE_MB} MB (exceeds 500 MB threshold)" \
      "Check for remaining large tables: SELECT tablename, pg_size_pretty(pg_total_relation_size(tablename::regclass)) FROM pg_tables WHERE schemaname='public' ORDER BY pg_total_relation_size(tablename::regclass) DESC LIMIT 5;"
  fi
fi

# ---------------------------------------------------------------------------
# Check 5 - Write operations work
# ---------------------------------------------------------------------------
echo "[INFO]  Check 5: Write operations succeed"

if [[ -n "$CLUSTER_EP" ]]; then
  WRITE_TEST=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "CREATE TEMP TABLE _validate_write_test (id INT); INSERT INTO _validate_write_test VALUES (1); SELECT count(*) FROM _validate_write_test; DROP TABLE _validate_write_test;" 2>/dev/null || echo "failed")

  if [[ "$WRITE_TEST" == "1" ]]; then
    pass "Write operations (INSERT) succeed"
  else
    fail "Write operations failed" \
      "Check if the database is in a degraded state"
  fi
fi

# ---------------------------------------------------------------------------
# Check 6 - VolumeBytesUsed metric exists (informational)
# ---------------------------------------------------------------------------
echo "[INFO]  Check 6: CloudWatch VolumeBytesUsed metric (informational)"

VOLUME_BYTES=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions "Name=DBClusterIdentifier,Value=$CLUSTER_ID" \
  --start-time "$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average \
  --region "$REGION" \
  --query "sort_by(Datapoints, &Timestamp)[-1].Average" \
  --output text 2>/dev/null || echo "None")

if [[ "$VOLUME_BYTES" != "None" && -n "$VOLUME_BYTES" ]]; then
  VOLUME_GB=$(python3 -c "print(f'{float(\"$VOLUME_BYTES\") / 1073741824:.2f}')" 2>/dev/null || echo "unknown")
  pass "VolumeBytesUsed: ${VOLUME_GB} GB (Note: may not decrease immediately after cleanup)"
else
  warn "VolumeBytesUsed metric not available yet (Aurora metrics may take a few minutes)"
  (( PASS_COUNT++ )) || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================"
echo "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "[WARN]  Some checks failed. See details above."
  exit 1
else
  echo "[PASS]  All checks passed."
  exit 0
fi
