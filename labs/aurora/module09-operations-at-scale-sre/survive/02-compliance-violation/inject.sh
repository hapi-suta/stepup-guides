#!/bin/bash
# =============================================================================
# SURVIVE Scenario 02: Compliance Violation
# INJECT - Creates an unencrypted Aurora instance and disables audit logging
#          to simulate compliance violations.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

STATE_FILE="${M09_STATE_DIR}/02-compliance-violation.state"

print_survive_warning "Compliance Violation (Unencrypted DB + No Audit)"

# ---------------------------------------------------------------------------
log_step 1 "Save current state"
# ---------------------------------------------------------------------------

# Check current pgaudit configuration
CURRENT_PGAUDIT_LOG=$(aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name "${M09_CLUSTER_PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='pgaudit.log'].ParameterValue" \
    --output text \
    --region "${M09_REGION}" 2>/dev/null || echo "NOT_SET")

# Check deletion protection
CURRENT_DEL_PROTECT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].DeletionProtection' \
    --output text \
    --region "${M09_REGION}" 2>/dev/null || echo "UNKNOWN")

cat > "${STATE_FILE}" <<EOF
ORIGINAL_PGAUDIT_LOG=${CURRENT_PGAUDIT_LOG}
ORIGINAL_DEL_PROTECT=${CURRENT_DEL_PROTECT}
INJECT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UNENCRYPTED_INSTANCE_ID=${M09_CHAOS_PREFIX}-unencrypted-db
EOF

log_success "State saved to ${STATE_FILE}"

# ---------------------------------------------------------------------------
log_step 2 "Disable audit logging (pgaudit.log)"
# ---------------------------------------------------------------------------

aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "${M09_CLUSTER_PARAM_GROUP}" \
    --parameters "ParameterName=pgaudit.log,ParameterValue=none,ApplyMethod=immediate" \
    --region "${M09_REGION}" > /dev/null 2>&1 || log_warn "pgaudit.log parameter not found - may not be configured yet"

log_success "Disabled pgaudit.log (set to 'none')"

# ---------------------------------------------------------------------------
log_step 3 "Disable deletion protection"
# ---------------------------------------------------------------------------

aws rds modify-db-cluster \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --no-deletion-protection \
    --apply-immediately \
    --region "${M09_REGION}" > /dev/null

log_success "Disabled deletion protection on ${M09_CLUSTER_ID}"

# ---------------------------------------------------------------------------
log_step 4 "Remove compliance-related tags"
# ---------------------------------------------------------------------------

CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].DBClusterArn' \
    --output text \
    --region "${M09_REGION}")

aws rds remove-tags-from-resource \
    --resource-name "${CLUSTER_ARN}" \
    --tag-keys DataClassification Compliance \
    --region "${M09_REGION}" 2>/dev/null || true

log_success "Removed DataClassification and Compliance tags"

# ---------------------------------------------------------------------------
log_step 5 "Disable IAM authentication"
# ---------------------------------------------------------------------------

aws rds modify-db-cluster \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --no-enable-iam-database-authentication \
    --apply-immediately \
    --region "${M09_REGION}" > /dev/null 2>&1 || log_warn "IAM auth modification failed - may already be disabled"

log_success "Disabled IAM database authentication"

# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  INJECTION COMPLETE"
echo "========================================="
echo ""
echo "  Compliance violations injected:"
echo "  1. Audit logging disabled (pgaudit.log = none)"
echo "  2. Deletion protection disabled"
echo "  3. Compliance tags removed"
echo "  4. IAM authentication disabled"
echo ""
echo "  Your mission:"
echo "  - Run a compliance audit using the runbook"
echo "  - Fix all violations"
echo "  - Run validate.sh to verify your fixes"
echo ""
echo "========================================="
