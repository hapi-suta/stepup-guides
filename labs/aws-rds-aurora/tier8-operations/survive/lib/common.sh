#!/usr/bin/env bash
# =============================================================================
# Tier 8 SURVIVE - Common Library Functions
# Source this file in inject.sh and validate.sh for each scenario
# =============================================================================

# Colors for terminal output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${RESET} $(date '+%H:%M:%S') $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${RESET} $(date '+%H:%M:%S') $*"
}

log_error() {
  echo -e "${RED}[ERROR]${RESET} $(date '+%H:%M:%S') $*" >&2
}

log_success() {
  echo -e "${GREEN}[PASS]${RESET} $(date '+%H:%M:%S') $*"
}

log_fail() {
  echo -e "${RED}[FAIL]${RESET} $(date '+%H:%M:%S') $*"
}

log_step() {
  echo -e "${BOLD}[STEP]${RESET} $(date '+%H:%M:%S') $*"
}

# Print a scenario banner
print_banner() {
  local title="$1"
  local width=60
  echo ""
  echo "$(printf '=%.0s' $(seq 1 $width))"
  echo "  $title"
  echo "$(printf '=%.0s' $(seq 1 $width))"
  echo ""
}

# Check if required CLI tools are available
check_prerequisites() {
  local tools=("aws" "psql" "jq")
  local missing=()

  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    log_error "Install missing tools before running this scenario."
    return 1
  fi

  return 0
}

# Check AWS CLI is authenticated
check_aws_auth() {
  if ! aws sts get-caller-identity --region "${T8_REGION}" &>/dev/null; then
    log_error "AWS CLI is not authenticated or region '${T8_REGION}' is not accessible."
    log_error "Run 'aws configure' or set AWS_PROFILE."
    return 1
  fi

  local account
  account=$(aws sts get-caller-identity --query Account --output text --region "${T8_REGION}")
  log_info "Authenticated to AWS account: ${account}, region: ${T8_REGION}"
  return 0
}

# Check that an RDS instance is in 'available' state
wait_for_instance_available() {
  local instance_id="$1"
  local max_wait="${2:-300}"
  local elapsed=0

  log_info "Waiting for instance '${instance_id}' to reach 'available' state..."

  while [[ $elapsed -lt $max_wait ]]; do
    local status
    status=$(aws rds describe-db-instances \
      --db-instance-identifier "${instance_id}" \
      --query 'DBInstances[0].DBInstanceStatus' \
      --output text \
      --region "${T8_REGION}" 2>/dev/null)

    if [[ "${status}" == "available" ]]; then
      log_success "Instance '${instance_id}' is available."
      return 0
    fi

    log_info "  Status: ${status}. Waiting... (${elapsed}s elapsed)"
    sleep 15
    elapsed=$((elapsed + 15))
  done

  log_error "Timed out waiting for instance '${instance_id}' to become available after ${max_wait}s."
  return 1
}

# Run a SQL query against the RDS instance
run_sql() {
  local query="$1"
  local dbname="${2:-${T8_DB_NAME}}"

  psql \
    --host="${T8_DB_HOST}" \
    --port="${T8_DB_PORT}" \
    --username="${T8_DB_USER}" \
    --dbname="${dbname}" \
    --command="${query}" \
    --no-psqlrc \
    --tuples-only \
    --no-align 2>/dev/null
}

# Run a SQL query and return exit code only
run_sql_check() {
  local query="$1"
  local dbname="${2:-${T8_DB_NAME}}"

  psql \
    --host="${T8_DB_HOST}" \
    --port="${T8_DB_PORT}" \
    --username="${T8_DB_USER}" \
    --dbname="${dbname}" \
    --command="${query}" \
    --no-psqlrc \
    --quiet 2>/dev/null
}

# Test basic database connectivity
check_db_connectivity() {
  if run_sql_check "SELECT 1;" &>/dev/null; then
    log_success "Database connectivity: OK"
    return 0
  else
    log_fail "Database connectivity: FAILED"
    return 1
  fi
}

# Get a CloudWatch metric value (last N minutes average)
get_cloudwatch_metric() {
  local metric_name="$1"
  local dimension_value="${2:-${T8_INSTANCE_ID}}"
  local period_minutes="${3:-5}"
  local statistic="${4:-Average}"
  local dimension_name="${5:-DBInstanceIdentifier}"

  # Handle macOS vs Linux date command
  local start_time
  if date -v-1d &>/dev/null 2>&1; then
    # macOS
    start_time=$(date -u -v-${period_minutes}M '+%Y-%m-%dT%H:%M:%SZ')
  else
    # Linux
    start_time=$(date -u -d "${period_minutes} minutes ago" '+%Y-%m-%dT%H:%M:%SZ')
  fi

  local end_time
  end_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name "${metric_name}" \
    --dimensions "Name=${dimension_name},Value=${dimension_value}" \
    --start-time "${start_time}" \
    --end-time "${end_time}" \
    --period $((period_minutes * 60)) \
    --statistics "${statistic}" \
    --query 'Datapoints[0].'"${statistic}" \
    --output text \
    --region "${T8_REGION}" 2>/dev/null
}

# Get RDS instance attribute
get_instance_attr() {
  local attr="$1"
  local instance_id="${2:-${T8_INSTANCE_ID}}"

  aws rds describe-db-instances \
    --db-instance-identifier "${instance_id}" \
    --query "DBInstances[0].${attr}" \
    --output text \
    --region "${T8_REGION}" 2>/dev/null
}

# Get parameter value from a parameter group
get_parameter_value() {
  local param_name="$1"
  local pg_name="${2:-${T8_PARAMETER_GROUP}}"

  aws rds describe-db-parameters \
    --db-parameter-group-name "${pg_name}" \
    --query "Parameters[?ParameterName=='${param_name}'].ParameterValue" \
    --output text \
    --region "${T8_REGION}" 2>/dev/null
}

# Modify a parameter group setting
set_parameter_value() {
  local param_name="$1"
  local param_value="$2"
  local apply_method="${3:-immediate}"
  local pg_name="${4:-${T8_PARAMETER_GROUP}}"

  aws rds modify-db-parameter-group \
    --db-parameter-group-name "${pg_name}" \
    --parameters "ParameterName=${param_name},ParameterValue=${param_value},ApplyMethod=${apply_method}" \
    --region "${T8_REGION}" 2>/dev/null
}

# Record scenario start time
record_start() {
  T8_SCENARIO_START=$(date +%s)
  export T8_SCENARIO_START
  log_info "Scenario start time recorded: $(date '+%Y-%m-%d %H:%M:%S UTC')"
}

# Calculate and display elapsed time
elapsed_since_start() {
  if [[ -z "${T8_SCENARIO_START}" ]]; then
    echo "N/A"
    return
  fi
  local now
  now=$(date +%s)
  local elapsed=$((now - T8_SCENARIO_START))
  echo "${elapsed} seconds"
}

# Validate function helper - checks a condition and prints pass/fail
validate_check() {
  local description="$1"
  local result="$2"  # "pass" or "fail"
  local detail="${3:-}"

  if [[ "${result}" == "pass" ]]; then
    log_success "${description}"
    [[ -n "${detail}" ]] && echo "         ${detail}"
    return 0
  else
    log_fail "${description}"
    [[ -n "${detail}" ]] && echo "         ${detail}"
    return 1
  fi
}

# Print the SURVIVE scenario intro warning
print_survive_warning() {
  local scenario_name="$1"
  echo -e "${RED}${BOLD}"
  echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "  SURVIVE SCENARIO: ${scenario_name}"
  echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo -e "${RESET}"
  echo "  This script injects a real problem condition."
  echo "  Do NOT run this against a production instance"
  echo "  unless you have verified it is a designated lab environment."
  echo ""
  echo "  After injection, diagnose independently."
  echo "  Open runbook.md only after attempting diagnosis on your own."
  echo ""
  read -rp "  Type CONFIRM to proceed: " confirmation
  if [[ "${confirmation}" != "CONFIRM" ]]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
}
