#!/usr/bin/env bash
# Tier 2 Security - Shared helper functions
# Do NOT run this file directly. It is sourced by inject.sh and validate.sh.

# ─── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No colour

# ─── Output helpers ────────────────────────────────────────────────────────────

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[FAIL]${NC}  $*"; }
header()  { echo -e "\n${BOLD}=== $* ===${NC}"; }

# Print a separator line
separator() { echo "────────────────────────────────────────────────────────────"; }

# ─── Prerequisite checks ───────────────────────────────────────────────────────

require_env() {
  # require_env VAR_NAME "description"
  local var_name="$1"
  local description="${2:-$1}"
  if [[ -z "${!var_name}" ]]; then
    error "Required variable \$$var_name is not set ($description)."
    error "Run: source survive/config.sh"
    exit 1
  fi
}

check_aws_cli() {
  if ! command -v aws &>/dev/null; then
    error "AWS CLI is not installed or not in PATH."
    exit 1
  fi
}

check_psql() {
  if ! command -v psql &>/dev/null; then
    error "psql is not installed or not in PATH."
    exit 1
  fi
}

check_config_loaded() {
  require_env RDS_INSTANCE_ID "RDS instance identifier"
  require_env RDS_HOST "RDS endpoint hostname"
  require_env AWS_REGION "AWS region"
  require_env RDS_MASTER_USER "RDS master username"
}

# ─── RDS helpers ───────────────────────────────────────────────────────────────

rds_instance_status() {
  # Returns the DBInstanceStatus of the instance
  aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null
}

wait_for_rds_available() {
  info "Waiting for RDS instance to become available (this may take a few minutes)..."
  aws rds wait db-instance-available \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --region "$AWS_REGION"
  success "RDS instance is available."
}

rds_get_param() {
  # rds_get_param PARAM_GROUP_NAME PARAM_NAME
  local group="$1"
  local param="$2"
  aws rds describe-db-parameters \
    --db-parameter-group-name "$group" \
    --query "Parameters[?ParameterName=='$param'].ParameterValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null
}

rds_force_ssl_status() {
  rds_get_param "$PARAM_GROUP_NAME" "rds.force_ssl"
}

rds_iam_auth_enabled() {
  aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].IAMDatabaseAuthenticationEnabled' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null
}

# ─── psql helpers ──────────────────────────────────────────────────────────────

psql_exec() {
  # psql_exec "SQL query" [db_name] [username]
  local query="$1"
  local db="${2:-$RDS_DB}"
  local user="${3:-$RDS_MASTER_USER}"
  PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
    --host="$RDS_HOST" \
    --port="$RDS_PORT" \
    --dbname="$db" \
    --username="$user" \
    --tuples-only \
    --no-align \
    --command="$query" 2>/dev/null
}

psql_exec_ssl() {
  # psql_exec_ssl "SQL query" - same but with sslmode=verify-full
  local query="$1"
  local db="${2:-$RDS_DB}"
  local user="${3:-$RDS_MASTER_USER}"
  PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
    "host=$RDS_HOST port=$RDS_PORT dbname=$db user=$user sslmode=verify-full sslrootcert=$HOME/rds-ca-bundle.pem" \
    --tuples-only \
    --no-align \
    --command="$query" 2>/dev/null
}

ssl_connections_count() {
  # Returns count of non-SSL active client connections
  psql_exec_ssl "SELECT COUNT(*) FROM pg_stat_activity sa JOIN pg_stat_ssl ss ON sa.pid = ss.pid WHERE sa.backend_type = 'client backend' AND ss.ssl = FALSE;"
}

# ─── Validate helpers ──────────────────────────────────────────────────────────

check_pass() {
  local description="$1"
  success "$description"
  ((CHECKS_PASSED++))
}

check_fail() {
  local description="$1"
  error "$description"
  ((CHECKS_FAILED++))
}

init_checks() {
  CHECKS_PASSED=0
  CHECKS_FAILED=0
}

print_check_summary() {
  separator
  local total=$((CHECKS_PASSED + CHECKS_FAILED))
  echo -e "${BOLD}Results: $CHECKS_PASSED/$total checks passed${NC}"
  if [[ $CHECKS_FAILED -eq 0 ]]; then
    success "All checks passed. Scenario resolved."
  else
    error "$CHECKS_FAILED check(s) failed. Review the runbook and try again."
  fi
  separator
}
