#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 02: Unencrypted Instance Found in Production
#
# What this script does:
#   Simulates a compliance violation scenario by:
#   1. Verifying whether the target instance has encryption enabled
#   2. Creating a SECOND unencrypted test instance (to avoid modifying a running
#      production instance - you cannot disable encryption on a running RDS instance)
#   3. Tagging the unencrypted instance with Environment=production to simulate
#      a violation that AWS Config would detect
#   4. Verifying that AWS Config has fired a compliance violation
#
# NOTE: This scenario creates a new db.t3.micro RDS instance (minimal cost,
# approximately $0.017/hour). Tear it down using validate.sh after the exercise.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 02: Compliance Violation - Unencrypted Instance"
print_survive_warning "Unencrypted Production Instance"

t8_validate_config || exit 1
check_prerequisites || exit 1
check_aws_auth || exit 1

record_start

VIOLATION_INSTANCE_ID="t8-survive-02-unencrypted-$(date +%Y%m%d)"

# -----------------------------------------------------------------------
# Step 1: Create an unencrypted RDS instance tagged as production
# -----------------------------------------------------------------------
log_step "Step 1: Creating unencrypted RDS instance tagged as production..."
log_warn "This creates a real RDS instance. Estimated cost: ~\$0.02/hour."
log_warn "Instance ID: ${VIOLATION_INSTANCE_ID}"

# Get the VPC subnet group from the existing instance
DB_SUBNET_GROUP=$(get_instance_attr "DBSubnetGroup.DBSubnetGroupName")
SECURITY_GROUP=$(aws rds describe-db-instances \
  --db-instance-identifier "${T8_INSTANCE_ID}" \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text \
  --region "${T8_REGION}")

log_info "Using DB subnet group: ${DB_SUBNET_GROUP}"
log_info "Using security group: ${SECURITY_GROUP}"

aws rds create-db-instance \
  --db-instance-identifier "${VIOLATION_INSTANCE_ID}" \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15 \
  --master-username surviveadmin \
  --master-user-password "T8Survive02-$(date +%Y%m%d)!" \
  --allocated-storage 20 \
  --no-multi-az \
  --no-storage-encrypted \
  --db-subnet-group-name "${DB_SUBNET_GROUP}" \
  --vpc-security-group-ids "${SECURITY_GROUP}" \
  --backup-retention-period 0 \
  --no-publicly-accessible \
  --no-deletion-protection \
  --tags \
    Key=Environment,Value=production \
    Key=Application,Value=payments-api \
    Key=Team,Value=backend \
    Key=DataClass,Value=confidential \
    Key=ManagedBy,Value=manual \
  --region "${T8_REGION}"

log_info "Instance creation initiated. This takes 5-10 minutes."
log_info "You do not need to wait - start your diagnosis now."

# -----------------------------------------------------------------------
# Step 2: Print the scenario description
# -----------------------------------------------------------------------
echo ""
log_warn "========================================================"
log_warn "INJECTION COMPLETE"
log_warn "========================================================"
echo ""
echo "What has been injected:"
echo "  - A new RDS instance has been created: ${VIOLATION_INSTANCE_ID}"
echo "  - It is tagged: Environment=production, DataClass=confidential"
echo "  - It is UNENCRYPTED (StorageEncrypted=false)"
echo "  - AWS Config will detect this as a rds-storage-encrypted violation"
echo ""
echo "Your scenario:"
echo "  An automated compliance scan has detected an unencrypted RDS instance"
echo "  tagged as a production database containing confidential data."
echo "  The HIPAA audit is in 15 days. You need to:"
echo ""
echo "    a. Confirm the violation exists and gather evidence"
echo "    b. Assess the risk (is this instance currently serving PHI?)"
echo "    c. Remediate the violation (you cannot in-place encrypt a running RDS instance)"
echo "    d. Document what happened and prevent recurrence"
echo ""
echo "Key constraint: You cannot enable encryption on a running RDS instance."
echo "  The only paths are:"
echo "    1. Snapshot -> copy snapshot with encryption -> restore from encrypted snapshot"
echo "    2. Spin up a new encrypted instance, migrate data, decommission old instance"
echo ""
echo "Note: This instance contains no real data - it was just created."
echo "  In a real scenario, you would need to migrate existing data."
echo ""
echo "IMPORTANT: Run validate.sh to clean up (delete the instance) when done."
echo ""

# Save state for validate.sh
cat > "${SCRIPT_DIR}/.inject-state" << EOF
INJECT_TIME=$(date +%s)
VIOLATION_INSTANCE_ID=${VIOLATION_INSTANCE_ID}
EOF

log_info "Inject state saved."
