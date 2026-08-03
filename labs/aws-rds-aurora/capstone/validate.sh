#!/usr/bin/env bash
# capstone/validate.sh
# Automated scoring script for the RDS/Aurora capstone project.
# Runs 20 checks across all 7 phases, each worth 5 points (100 total).
#
# Usage:
#   export CAPSTONE_CLUSTER_ID="your-cluster-id"
#   export AWS_REGION="us-east-1"
#   bash validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------

if [[ -z "${CAPSTONE_CLUSTER_ID:-}" ]]; then
  echo "ERROR: CAPSTONE_CLUSTER_ID is not set."
  echo "Usage: export CAPSTONE_CLUSTER_ID=\"your-cluster-id\" && bash validate.sh"
  exit 1
fi

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "ERROR: AWS_REGION is not set."
  echo "Usage: export AWS_REGION=\"us-east-1\" && bash validate.sh"
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

WRITER_ID="${CAPSTONE_CLUSTER_ID}-writer-1"
READER_ID="${CAPSTONE_CLUSTER_ID}-reader-1"

echo ""
echo "================================================"
echo "  CAPSTONE VALIDATION: Production Aurora Setup"
echo "================================================"
echo ""
echo "  Cluster: $CAPSTONE_CLUSTER_ID"
echo "  Writer:  $WRITER_ID"
echo "  Reader:  $READER_ID"
echo "  Region:  $AWS_REGION"
echo ""

# ---------------------------------------------------------------------------
# Helper: get cluster JSON once
# ---------------------------------------------------------------------------

CLUSTER_JSON=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CAPSTONE_CLUSTER_ID" \
  --query "DBClusters[0]" \
  --output json 2>/dev/null || echo "{}")

if [[ "$CLUSTER_JSON" == "{}" ]]; then
  fail "Cluster $CAPSTONE_CLUSTER_ID not found. Cannot proceed."
  exit 1
fi

WRITER_JSON=$(aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_ID" \
  --query "DBInstances[0]" \
  --output json 2>/dev/null || echo "{}")

# ---------------------------------------------------------------------------
# Phase 1: Provision (15 points)
# ---------------------------------------------------------------------------

echo "--- Phase 1: Provision ---"
echo ""

# Check 1: Cluster exists and is available
CLUSTER_STATUS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Status','not-found'))")
if [[ "$CLUSTER_STATUS" == "available" ]]; then
  check "Cluster $CAPSTONE_CLUSTER_ID is available" "pass"
else
  check "Cluster status: $CLUSTER_STATUS" "fail" "Expected: available"
fi

# Check 2: Writer instance is available
WRITER_STATUS=$(echo "$WRITER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('DBInstanceStatus','not-found'))" 2>/dev/null || echo "not-found")
if [[ "$WRITER_STATUS" == "available" ]]; then
  check "Writer instance $WRITER_ID is available" "pass"
else
  check "Writer instance status: $WRITER_STATUS" "fail" "Expected: available. Instance ID must be ${WRITER_ID}"
fi

# Check 3: Engine version is PostgreSQL 16.x
ENGINE_VERSION=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('EngineVersion','unknown'))")
if [[ "$ENGINE_VERSION" == 16.* ]]; then
  check "Engine version is PostgreSQL $ENGINE_VERSION" "pass"
else
  check "Engine version: $ENGINE_VERSION" "fail" "Expected: 16.x"
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 2: Security (20 points)
# ---------------------------------------------------------------------------

echo "--- Phase 2: Security ---"
echo ""

# Check 4: Storage encryption enabled
ENCRYPTED=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StorageEncrypted',False))")
if [[ "$ENCRYPTED" == "True" ]]; then
  check "Storage encryption is enabled" "pass"
else
  check "Storage encryption is disabled" "fail" "Must be enabled at cluster creation time"
fi

# Check 5: SSL forced via parameter group
PARAM_GROUP=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('DBClusterParameterGroup',''))")
FORCE_SSL=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP" \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" \
  --output text 2>/dev/null || echo "")
if [[ "$FORCE_SSL" == "1" ]]; then
  check "SSL/TLS is enforced (rds.force_ssl = 1)" "pass"
else
  check "SSL/TLS not enforced (rds.force_ssl = ${FORCE_SSL:-unset})" "fail" "Set rds.force_ssl = 1 in parameter group"
fi

# Check 6: No public access
PUBLIC_ACCESS=$(echo "$WRITER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('PubliclyAccessible',True))" 2>/dev/null || echo "True")
if [[ "$PUBLIC_ACCESS" == "False" ]]; then
  check "Writer instance is not publicly accessible" "pass"
else
  check "Writer instance is publicly accessible" "fail" "Set PubliclyAccessible = false"
fi

# Check 7: IAM authentication enabled
IAM_AUTH=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('IAMDatabaseAuthenticationEnabled',False))")
if [[ "$IAM_AUTH" == "True" ]]; then
  check "IAM database authentication is enabled" "pass"
else
  check "IAM database authentication is disabled" "fail" "Run: aws rds modify-db-cluster --enable-iam-database-authentication"
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 3: Configuration (10 points)
# ---------------------------------------------------------------------------

echo "--- Phase 3: Configuration ---"
echo ""

# Check 8: pg_stat_statements in shared_preload_libraries
PRELOAD_LIBS=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP" \
  --query "Parameters[?ParameterName=='shared_preload_libraries'].ParameterValue" \
  --output text 2>/dev/null || echo "")
if echo "$PRELOAD_LIBS" | grep -q "pg_stat_statements"; then
  check "pg_stat_statements is in shared_preload_libraries" "pass"
else
  check "pg_stat_statements not found in shared_preload_libraries" "fail" "Current value: ${PRELOAD_LIBS:-empty}"
fi

# Check 9: Custom parameter group (not default)
if [[ "$PARAM_GROUP" != default.aurora-postgresql* ]]; then
  check "Custom parameter group attached: $PARAM_GROUP" "pass"
else
  check "Using default parameter group: $PARAM_GROUP" "fail" "Create and attach a custom parameter group"
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 4: High Availability (15 points)
# ---------------------------------------------------------------------------

echo "--- Phase 4: High Availability ---"
echo ""

# Check 10: Multi-AZ (writer and reader in different AZs)
WRITER_AZ=$(echo "$WRITER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('AvailabilityZone','unknown'))" 2>/dev/null || echo "unknown")
READER_AZ=$(aws rds describe-db-instances \
  --db-instance-identifier "$READER_ID" \
  --query "DBInstances[0].AvailabilityZone" \
  --output text 2>/dev/null || echo "not-found")
if [[ "$READER_AZ" != "not-found" && "$READER_AZ" != "$WRITER_AZ" ]]; then
  check "Multi-AZ: writer in $WRITER_AZ, reader in $READER_AZ" "pass"
elif [[ "$READER_AZ" == "$WRITER_AZ" ]]; then
  check "Writer and reader are in the same AZ ($WRITER_AZ)" "fail" "Place reader in a different AZ"
else
  check "Reader instance $READER_ID not found" "fail" "Create a reader in a different AZ than $WRITER_AZ"
fi

# Check 11: Automated backups enabled
BACKUP_RETENTION=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackupRetentionPeriod',0))")
if [[ "$BACKUP_RETENTION" -gt 0 ]]; then
  check "Automated backups enabled (retention: ${BACKUP_RETENTION} days)" "pass"
else
  check "Automated backups disabled" "fail" "Set backup retention period > 0"
fi

# Check 12: Backup retention >= 7 days
if [[ "$BACKUP_RETENTION" -ge 7 ]]; then
  check "Backup retention >= 7 days ($BACKUP_RETENTION days)" "pass"
else
  check "Backup retention too short: $BACKUP_RETENTION days" "fail" "Set to at least 7: aws rds modify-db-cluster --backup-retention-period 7"
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 5: Monitoring (15 points)
# ---------------------------------------------------------------------------

echo "--- Phase 5: Monitoring ---"
echo ""

# Check 13: Performance Insights enabled
PI_ENABLED=$(echo "$WRITER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('PerformanceInsightsEnabled',False))" 2>/dev/null || echo "False")
if [[ "$PI_ENABLED" == "True" ]]; then
  check "Performance Insights enabled on writer" "pass"
else
  check "Performance Insights not enabled on writer" "fail" "Run: aws rds modify-db-instance --enable-performance-insights"
fi

# Check 14: CloudWatch alarm exists for this cluster
ALARM_COUNT=$(aws cloudwatch describe-alarms \
  --query "MetricAlarms[?Dimensions[?Name=='DBClusterIdentifier' && Value=='${CAPSTONE_CLUSTER_ID}']] | length(@)" \
  --output text 2>/dev/null || echo "0")
if [[ "$ALARM_COUNT" -gt 0 ]]; then
  check "CloudWatch alarm(s) found for cluster ($ALARM_COUNT)" "pass"
else
  check "No CloudWatch alarms found for cluster" "fail" "Create an alarm with dimension DBClusterIdentifier=${CAPSTONE_CLUSTER_ID}"
fi

# Check 15: Enhanced Monitoring enabled
MONITORING_INTERVAL=$(echo "$WRITER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('MonitoringInterval',0))" 2>/dev/null || echo "0")
if [[ "$MONITORING_INTERVAL" -gt 0 ]]; then
  check "Enhanced Monitoring enabled (interval: ${MONITORING_INTERVAL}s)" "pass"
else
  check "Enhanced Monitoring not enabled" "fail" "Enable with --monitoring-interval 60 and --monitoring-role-arn"
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 6: Scale (10 points)
# ---------------------------------------------------------------------------

echo "--- Phase 6: Scale ---"
echo ""

# Check 16: At least 1 reader replica
MEMBER_COUNT=$(echo "$CLUSTER_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
members = data.get('DBClusterMembers', [])
readers = [m for m in members if not m.get('IsClusterWriter', False)]
print(len(readers))
")
if [[ "$MEMBER_COUNT" -ge 1 ]]; then
  check "Reader replica(s) found: $MEMBER_COUNT" "pass"
else
  check "No reader replicas found" "fail" "Create at least one reader instance"
fi

# Check 17: Reader endpoint resolves
READER_ENDPOINT=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ReaderEndpoint',''))")
if [[ -n "$READER_ENDPOINT" ]]; then
  RESOLVED=$(dig +short "$READER_ENDPOINT" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" ]]; then
    check "Reader endpoint resolves: $READER_ENDPOINT" "pass"
  else
    check "Reader endpoint DNS not resolving: $READER_ENDPOINT" "fail" "May need a few minutes after reader creation"
  fi
else
  check "No reader endpoint found on cluster" "fail"
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 7: Operations (15 points)
# ---------------------------------------------------------------------------

echo "--- Phase 7: Operations ---"
echo ""

# Check 18: pgaudit in shared_preload_libraries
if echo "$PRELOAD_LIBS" | grep -q "pgaudit"; then
  check "pgaudit is in shared_preload_libraries" "pass"
else
  check "pgaudit not found in shared_preload_libraries" "fail" "Add pgaudit to shared_preload_libraries and reboot"
fi

# Check 19: pgaudit.log is configured
PGAUDIT_LOG=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP" \
  --query "Parameters[?ParameterName=='pgaudit.log'].ParameterValue" \
  --output text 2>/dev/null || echo "")
if [[ -n "$PGAUDIT_LOG" && "$PGAUDIT_LOG" != "None" && "$PGAUDIT_LOG" != "none" ]]; then
  check "pgaudit.log configured: $PGAUDIT_LOG" "pass"
else
  check "pgaudit.log not configured" "fail" "Set pgaudit.log in your parameter group (e.g., 'ddl,role')"
fi

# Check 20: PostgreSQL logs exported to CloudWatch
LOG_EXPORTS=$(echo "$CLUSTER_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
exports = data.get('EnabledCloudwatchLogsExports', [])
print(','.join(exports) if exports else '')
")
if echo "$LOG_EXPORTS" | grep -q "postgresql"; then
  check "PostgreSQL logs exported to CloudWatch" "pass"
else
  check "PostgreSQL log export not enabled" "fail" "Run: aws rds modify-db-cluster --enable-cloudwatch-logs-exports '[\"postgresql\"]'"
fi

echo ""

# ---------------------------------------------------------------------------
# Final Score
# ---------------------------------------------------------------------------

TOTAL_POINTS=$(( _CHECK_PASS * 5 ))
echo "================================================"
echo "  CAPSTONE SCORE: ${TOTAL_POINTS}/100"
echo "  (${_CHECK_PASS} passed, ${_CHECK_FAIL} failed)"
echo "================================================"
echo ""

if [[ $TOTAL_POINTS -eq 100 ]]; then
  success "MASTER - Production-ready environment. Well done!"
elif [[ $TOTAL_POINTS -ge 80 ]]; then
  info "ADVANCED - Minor gaps to address. Review failed checks above."
elif [[ $TOTAL_POINTS -ge 60 ]]; then
  warn "INTERMEDIATE - Review failed checks and revisit the relevant BUILD guides."
else
  fail "NEEDS WORK - Revisit the BUILD guides for failed phases."
fi

echo ""
