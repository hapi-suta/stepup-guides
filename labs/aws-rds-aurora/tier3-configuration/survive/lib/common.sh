#!/usr/bin/env bash
# Tier 3 SURVIVE - Common Shell Functions
# Sourced by config.sh, which is sourced by all inject.sh and validate.sh scripts

# =====================================================================
# Output helpers
# =====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

fail() {
  echo -e "${RED}[FAIL]${NC} $*"
}

section() {
  echo ""
  echo "========================================"
  echo "  $*"
  echo "========================================"
}

# =====================================================================
# AWS RDS helpers
# =====================================================================

# Wait for instance to be in a specific status
# Usage: wait_for_status "available" 600
wait_for_status() {
  local target_status="$1"
  local timeout_secs="${2:-300}"
  local elapsed=0
  local interval=15

  info "Waiting for instance $RDS_INSTANCE_ID to reach status: $target_status (timeout: ${timeout_secs}s)"

  while [[ $elapsed -lt $timeout_secs ]]; do
    local current_status
    current_status=$(aws rds describe-db-instances \
      --db-instance-identifier "$RDS_INSTANCE_ID" \
      --region "$AWS_REGION" \
      --query 'DBInstances[0].DBInstanceStatus' \
      --output text 2>/dev/null)

    if [[ "$current_status" == "$target_status" ]]; then
      success "Instance reached status: $target_status"
      return 0
    fi

    info "Current status: $current_status. Waiting ${interval}s..."
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  fail "Timed out waiting for status: $target_status. Current: $current_status"
  return 1
}

# Get current parameter value from the instance's parameter group
# Usage: get_param_value "shared_buffers"
get_param_value() {
  local param_name="$1"
  aws rds describe-db-parameters \
    --db-parameter-group-name "$PARAMETER_GROUP" \
    --region "$AWS_REGION" \
    --query "Parameters[?ParameterName=='$param_name'].ParameterValue" \
    --output text 2>/dev/null
}

# Get parameter apply type (static or dynamic)
# Usage: get_param_apply_type "shared_buffers"
get_param_apply_type() {
  local param_name="$1"
  aws rds describe-db-parameters \
    --db-parameter-group-name "$PARAMETER_GROUP" \
    --region "$AWS_REGION" \
    --query "Parameters[?ParameterName=='$param_name'].ApplyType" \
    --output text 2>/dev/null
}

# Get instance status
get_instance_status() {
  aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null
}

# Get parameter group apply status from the instance
get_param_group_status() {
  aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBParameterGroups[0].ParameterApplyStatus' \
    --output text 2>/dev/null
}

# Modify a parameter in the group
# Usage: set_param "work_mem" "65536" "immediate"
set_param() {
  local param_name="$1"
  local param_value="$2"
  local apply_method="${3:-pending-reboot}"

  aws rds modify-db-parameter-group \
    --db-parameter-group-name "$PARAMETER_GROUP" \
    --region "$AWS_REGION" \
    --parameters "ParameterName=$param_name,ParameterValue=$param_value,ApplyMethod=$apply_method" \
    --output text > /dev/null
}

# Reboot the instance
reboot_instance() {
  info "Rebooting instance $RDS_INSTANCE_ID..."
  aws rds reboot-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output text > /dev/null
}

# =====================================================================
# psql helpers
# =====================================================================

# Run a SQL query and return its output
# Usage: run_sql "SELECT 1"
run_sql() {
  local query="$1"
  PGPASSWORD="$PGPASSWORD" psql \
    -h "$RDS_ENDPOINT" \
    -p "$RDS_PORT" \
    -U "$RDS_USERNAME" \
    -d "$RDS_DBNAME" \
    -t \
    -c "$query" 2>/dev/null | tr -d ' '
}

# Check if psql can connect to the instance
check_connectivity() {
  local result
  result=$(run_sql "SELECT 1" 2>&1)
  if [[ "$result" == "1" ]]; then
    return 0
  else
    return 1
  fi
}

# Check if an extension is installed
# Usage: extension_installed "pg_stat_statements"
extension_installed() {
  local ext_name="$1"
  local result
  result=$(run_sql "SELECT installed_version FROM pg_available_extensions WHERE name = '$ext_name'")
  if [[ -n "$result" && "$result" != "" ]]; then
    return 0
  else
    return 1
  fi
}

# =====================================================================
# Validation helpers
# =====================================================================

# Run a check and report pass/fail
# Usage: check "Description" "command_that_returns_0_on_success"
PASS_COUNT=0
FAIL_COUNT=0

check() {
  local description="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    success "$description"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    fail "$description"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

print_summary() {
  echo ""
  section "VALIDATION SUMMARY"
  echo "  PASS: $PASS_COUNT"
  echo "  FAIL: $FAIL_COUNT"
  echo ""
  if [[ $FAIL_COUNT -eq 0 ]]; then
    success "All checks passed. Scenario resolved."
    return 0
  else
    fail "$FAIL_COUNT check(s) failed. Keep working on the resolution."
    return 1
  fi
}
