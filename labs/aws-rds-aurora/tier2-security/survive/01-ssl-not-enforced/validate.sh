#!/usr/bin/env bash
# Scenario 01 - SSL Not Enforced
# validate.sh: Verifies that SSL enforcement has been restored.
#
# Usage:
#   source survive/config.sh
#   bash survive/01-ssl-not-enforced/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 01 - Validating: SSL Enforcement"

check_aws_cli
check_psql
check_config_loaded
init_checks

separator

# ─── Check 1: Parameter group has rds.force_ssl = 1 ───────────────────────────
info "Check 1: rds.force_ssl parameter value"

FORCE_SSL=$(rds_force_ssl_status)

if [[ "$FORCE_SSL" == "1" ]]; then
  check_pass "rds.force_ssl = 1 in parameter group '$PARAM_GROUP_NAME'"
else
  check_fail "rds.force_ssl = '${FORCE_SSL:-not set}' in parameter group '$PARAM_GROUP_NAME' (expected: 1)"
fi

# ─── Check 2: Instance actually rejects non-SSL connections ────────────────────
info "Check 2: RDS instance rejects non-SSL connection"

NON_SSL_RESULT=$(psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=disable" \
  --command="SELECT 1;" 2>&1 || true)

if echo "$NON_SSL_RESULT" | grep -q "SSL off\|SSL connection is required"; then
  check_pass "RDS instance rejected non-SSL connection"
else
  check_fail "RDS instance accepted a non-SSL connection (got: ${NON_SSL_RESULT:0:100})"
fi

# ─── Check 3: SSL connections still work ───────────────────────────────────────
info "Check 3: SSL connections still accepted"

SSL_RESULT=$(PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT 'ssl_ok';" 2>&1 || true)

if echo "$SSL_RESULT" | grep -q "ssl_ok"; then
  check_pass "SSL connections accepted successfully"
else
  check_fail "SSL connection also failed - check instance status"
fi

# ─── Check 4: Parameter group is assigned to the instance ──────────────────────
info "Check 4: Custom parameter group assigned to instance"

ASSIGNED_PG=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text \
  --region "$AWS_REGION")

if [[ "$ASSIGNED_PG" == "$PARAM_GROUP_NAME" ]]; then
  check_pass "Parameter group '$PARAM_GROUP_NAME' is assigned to the instance"
else
  check_fail "Instance is using parameter group '$ASSIGNED_PG', expected '$PARAM_GROUP_NAME'"
fi

# ─── Check 5: Parameter group status is in-sync ────────────────────────────────
info "Check 5: Parameter group status is in-sync (not pending reboot)"

PG_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --query 'DBInstances[0].DBParameterGroups[0].ParameterApplyStatus' \
  --output text \
  --region "$AWS_REGION")

if [[ "$PG_STATUS" == "in-sync" ]]; then
  check_pass "Parameter group status: in-sync"
else
  check_fail "Parameter group status: '$PG_STATUS' (expected: in-sync - try rebooting the instance)"
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
print_check_summary
