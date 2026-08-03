#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 01: Unexpected Cost Spike from I/O Charges
#
# What this script does:
#   1. Simulates the conditions that produce a cost spike by enabling verbose
#      logging (which increases log volume / CloudWatch Logs costs) and by
#      creating a workload that generates high I/O on an Aurora Standard cluster.
#   2. Disables the I/O-Optimized storage flag if it was enabled (to simulate
#      the wrong storage mode being in place).
#   3. Creates an "expensive" parameter group configuration that logs every query.
#
# COST WARNING: Running this script will temporarily increase your AWS bill.
# The I/O-generating workload runs for 10 minutes. Estimated cost impact: $5-15.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 01: Cost Spike Injection"
print_survive_warning "Unexpected I/O Cost Spike"

t8_validate_config || exit 1
check_prerequisites || exit 1
check_aws_auth || exit 1

record_start

# -----------------------------------------------------------------------
# Step 1: Verify this is an Aurora cluster (not standard RDS)
# -----------------------------------------------------------------------
log_step "Step 1: Verifying Aurora cluster configuration..."

STORAGE_TYPE=$(aws rds describe-db-clusters \
  --db-cluster-identifier "${T8_CLUSTER_ID}" \
  --query 'DBClusters[0].StorageType' \
  --output text \
  --region "${T8_REGION}" 2>/dev/null || echo "UNKNOWN")

log_info "Current storage type: ${STORAGE_TYPE}"

if [[ "${STORAGE_TYPE}" == "aurora-iopt1" ]]; then
  log_warn "Cluster is on I/O-Optimized storage. Switching to Standard to enable the cost scenario..."

  aws rds modify-db-cluster \
    --db-cluster-identifier "${T8_CLUSTER_ID}" \
    --storage-type aurora \
    --apply-immediately \
    --region "${T8_REGION}"

  log_info "Storage type switched to Standard. Waiting 30 seconds for change to apply..."
  sleep 30
else
  log_info "Cluster is on Aurora Standard storage. Proceeding with injection."
fi

# -----------------------------------------------------------------------
# Step 2: Enable verbose query logging (increases CloudWatch Logs volume)
# -----------------------------------------------------------------------
log_step "Step 2: Enabling verbose logging to generate high log volume costs..."

if [[ -n "${T8_PARAMETER_GROUP}" ]]; then
  # Save original setting for restore
  ORIGINAL_LOG_DURATION=$(get_parameter_value "log_min_duration_statement")
  log_info "Original log_min_duration_statement: ${ORIGINAL_LOG_DURATION}"

  # Set to log EVERY query (0 = log all queries regardless of duration)
  aws rds modify-db-parameter-group \
    --db-parameter-group-name "${T8_PARAMETER_GROUP}" \
    --parameters ParameterName=log_min_duration_statement,ParameterValue=0,ApplyMethod=immediate \
    --region "${T8_REGION}"

  log_warn "log_min_duration_statement set to 0 - ALL queries will be logged."
  log_warn "This generates very high CloudWatch Logs volume."
else
  log_warn "T8_PARAMETER_GROUP not set - skipping parameter change."
fi

# -----------------------------------------------------------------------
# Step 3: Generate I/O workload to simulate high I/O charges on Standard storage
# -----------------------------------------------------------------------
log_step "Step 3: Generating I/O workload to simulate cost spike..."

check_db_connectivity || {
  log_warn "Cannot connect to database - skipping SQL workload generation."
  log_warn "The storage type and logging changes above are still in effect."
}

if run_sql_check "SELECT 1;" &>/dev/null; then
  log_info "Creating I/O workload table..."

  run_sql "CREATE TABLE IF NOT EXISTS t8_cost_spike_test (
    id serial PRIMARY KEY,
    payload text,
    created_at timestamptz DEFAULT now()
  );" 2>/dev/null || true

  log_info "Inserting data to generate write I/O (this takes ~60 seconds)..."

  run_sql "DO \$\$
  DECLARE
    i integer;
  BEGIN
    FOR i IN 1..100000 LOOP
      INSERT INTO t8_cost_spike_test (payload)
      VALUES (repeat(md5(random()::text), 10));
      IF i % 10000 = 0 THEN
        RAISE NOTICE 'Inserted % rows', i;
      END IF;
    END LOOP;
  END;
  \$\$;" 2>/dev/null || log_warn "Workload insert encountered an error (may be partial)."

  log_info "Running read I/O workload (sequential scans generate maximum I/O)..."
  for i in 1 2 3; do
    run_sql "SELECT count(*), avg(length(payload)) FROM t8_cost_spike_test;" 2>/dev/null || true
  done
fi

# -----------------------------------------------------------------------
# Step 4: Print scenario state for the student
# -----------------------------------------------------------------------
echo ""
log_warn "========================================================"
log_warn "INJECTION COMPLETE"
log_warn "========================================================"
echo ""
echo "What has been injected:"
echo "  1. Aurora cluster storage type: set to Standard (per-I/O billing active)"
echo "  2. log_min_duration_statement: set to 0 (all queries logged - high CloudWatch cost)"
echo "  3. I/O workload: 100,000 rows written and read (generating I/O charges)"
echo ""
echo "Your scenario:"
echo "  The finance team has sent an alert: the RDS line item in the AWS bill"
echo "  has increased by 340% compared to last month. You need to:"
echo "    a. Identify what is driving the cost increase"
echo "    b. Determine if this represents a configuration problem or legitimate growth"
echo "    c. Remediate the unnecessary costs"
echo "    d. Prevent recurrence"
echo ""
echo "Hints (do not read until you have tried independently):"
echo "  - Start with Cost Explorer: group by Usage Type"
echo "  - Check the storage configuration of each Aurora cluster"
echo "  - Check the CloudWatch Logs ingest volume for RDS log groups"
echo "  - Check parameter group settings for logging parameters"
echo ""
echo "Run validate.sh after remediation to confirm the issue is resolved."
echo ""

# Save injected state for validate.sh
cat > "${SCRIPT_DIR}/.inject-state" << EOF
INJECT_TIME=$(date +%s)
ORIGINAL_LOG_DURATION=${ORIGINAL_LOG_DURATION:-1000}
ORIGINAL_STORAGE_TYPE=${STORAGE_TYPE}
EOF

log_info "Inject state saved to .inject-state"
