#!/usr/bin/env bash
# Scenario 01 - SSL Not Enforced
# inject.sh: Disables SSL enforcement on the RDS instance.
#
# Usage:
#   source survive/config.sh
#   bash survive/01-ssl-not-enforced/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 01 - Injecting: SSL Not Enforced"

check_aws_cli
check_config_loaded

# ─── Verify we have a custom parameter group to work with ──────────────────────
info "Checking parameter group: $PARAM_GROUP_NAME"
if ! aws rds describe-db-parameter-groups \
    --db-parameter-group-name "$PARAM_GROUP_NAME" \
    --region "$AWS_REGION" &>/dev/null; then
  error "Parameter group '$PARAM_GROUP_NAME' not found."
  error "Create it first:"
  error "  aws rds create-db-parameter-group \\"
  error "    --db-parameter-group-name $PARAM_GROUP_NAME \\"
  error "    --db-parameter-group-family postgres16 \\"
  error "    --description 'Tier 2 survive scenarios' \\"
  error "    --region $AWS_REGION"
  error ""
  error "Then assign it to your instance:"
  error "  aws rds modify-db-instance \\"
  error "    --db-instance-identifier $RDS_INSTANCE_ID \\"
  error "    --db-parameter-group-name $PARAM_GROUP_NAME \\"
  error "    --apply-immediately \\"
  error "    --region $AWS_REGION"
  exit 1
fi

# ─── Record current state ──────────────────────────────────────────────────────
CURRENT_SSL=$(rds_force_ssl_status)
info "Current rds.force_ssl value: '${CURRENT_SSL:-not set}'"

# ─── Inject: set rds.force_ssl to 0 ───────────────────────────────────────────
info "Setting rds.force_ssl = 0 in parameter group: $PARAM_GROUP_NAME"
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP_NAME" \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=0,ApplyMethod=pending-reboot" \
  --region "$AWS_REGION"

success "Parameter set. Rebooting instance to apply..."

aws rds reboot-db-instance \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --region "$AWS_REGION"

wait_for_rds_available

separator
warn "INJECTION COMPLETE"
warn ""
warn "The RDS instance no longer enforces SSL."
warn "Database connections can now be made without encryption."
warn ""
warn "Your job: Find the problem and fix it."
warn "Runbook:  survive/01-ssl-not-enforced/runbook.md"
warn "Validate: bash survive/01-ssl-not-enforced/validate.sh"
separator
