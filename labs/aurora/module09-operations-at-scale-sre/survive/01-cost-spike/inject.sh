#!/bin/bash
# =============================================================================
# SURVIVE Scenario 01: Cost Spike
# INJECT - Simulates a cost spike by enabling verbose logging and creating
#          unnecessary resources that generate charges.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

STATE_FILE="${M09_STATE_DIR}/01-cost-spike.state"

print_survive_warning "Cost Spike (Costs Triple)"

# ---------------------------------------------------------------------------
log_step 1 "Save current parameter values"
# ---------------------------------------------------------------------------

CURRENT_LOG_DURATION=$(aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name "${M09_CLUSTER_PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='log_min_duration_statement'].ParameterValue" \
    --output text \
    --region "${M09_REGION}" 2>/dev/null || echo "NOT_SET")

log_info "Current log_min_duration_statement: ${CURRENT_LOG_DURATION}"

# Save state for rollback (idempotent - overwrite if exists)
cat > "${STATE_FILE}" <<EOF
ORIGINAL_LOG_DURATION=${CURRENT_LOG_DURATION}
INJECT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CHAOS_SNAPSHOT_ID=${M09_CHAOS_PREFIX}-cost-spike-snapshot
EOF

log_success "State saved to ${STATE_FILE}"

# ---------------------------------------------------------------------------
log_step 2 "Enable verbose query logging (log every query)"
# ---------------------------------------------------------------------------

aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "${M09_CLUSTER_PARAM_GROUP}" \
    --parameters "ParameterName=log_min_duration_statement,ParameterValue=0,ApplyMethod=immediate" \
    --region "${M09_REGION}" > /dev/null

log_success "Set log_min_duration_statement = 0 (logs EVERY query)"
log_warn "This will generate massive CloudWatch Logs volume"

# ---------------------------------------------------------------------------
log_step 3 "Create an unnecessary manual snapshot (storage cost)"
# ---------------------------------------------------------------------------

SNAPSHOT_ID="${M09_CHAOS_PREFIX}-cost-spike-snapshot"

# Idempotent: check if snapshot already exists
if aws rds describe-db-cluster-snapshots \
    --db-cluster-snapshot-identifier "${SNAPSHOT_ID}" \
    --region "${M09_REGION}" > /dev/null 2>&1; then
    log_info "Snapshot ${SNAPSHOT_ID} already exists (idempotent)"
else
    aws rds create-db-cluster-snapshot \
        --db-cluster-identifier "${M09_CLUSTER_ID}" \
        --db-cluster-snapshot-identifier "${SNAPSHOT_ID}" \
        --region "${M09_REGION}" > /dev/null
    log_success "Created unnecessary snapshot: ${SNAPSHOT_ID}"
fi

# ---------------------------------------------------------------------------
log_step 4 "Remove CloudWatch log retention (logs stored forever)"
# ---------------------------------------------------------------------------

LOG_GROUP="/aws/rds/cluster/${M09_CLUSTER_ID}/postgresql"

# Check if log group exists
if aws logs describe-log-groups \
    --log-group-name-prefix "${LOG_GROUP}" \
    --query "logGroups[?logGroupName=='${LOG_GROUP}']" \
    --output text \
    --region "${M09_REGION}" 2>/dev/null | grep -q "${LOG_GROUP}"; then

    CURRENT_RETENTION=$(aws logs describe-log-groups \
        --log-group-name-prefix "${LOG_GROUP}" \
        --query "logGroups[?logGroupName=='${LOG_GROUP}'].retentionInDays" \
        --output text \
        --region "${M09_REGION}" 2>/dev/null || echo "NONE")

    echo "ORIGINAL_LOG_RETENTION=${CURRENT_RETENTION}" >> "${STATE_FILE}"

    aws logs delete-retention-policy \
        --log-group-name "${LOG_GROUP}" \
        --region "${M09_REGION}" 2>/dev/null || true

    log_success "Removed log retention policy (logs stored forever)"
else
    log_warn "Log group ${LOG_GROUP} not found - skipping retention change"
    echo "ORIGINAL_LOG_RETENTION=SKIP" >> "${STATE_FILE}"
fi

# ---------------------------------------------------------------------------
log_step 5 "Remove required cost allocation tags"
# ---------------------------------------------------------------------------

CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].DBClusterArn' \
    --output text \
    --region "${M09_REGION}")

aws rds remove-tags-from-resource \
    --resource-name "${CLUSTER_ARN}" \
    --tag-keys CostCenter Environment Team \
    --region "${M09_REGION}" 2>/dev/null || true

log_success "Removed cost allocation tags (CostCenter, Environment, Team)"

# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  INJECTION COMPLETE"
echo "========================================="
echo ""
echo "  Problems injected:"
echo "  1. Verbose logging enabled (log_min_duration_statement = 0)"
echo "  2. Orphaned snapshot created (${SNAPSHOT_ID})"
echo "  3. CloudWatch log retention removed (infinite storage)"
echo "  4. Cost allocation tags removed"
echo ""
echo "  Your mission:"
echo "  - Diagnose the cost spike using the runbook"
echo "  - Fix all issues"
echo "  - Run validate.sh to verify your fixes"
echo ""
echo "========================================="
