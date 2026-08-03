#!/usr/bin/env bash
# Common functions for Tier 7 SURVIVE scenarios

set -euo pipefail

# ============================================================
# Logging
# ============================================================

LOG_FILE="${SCENARIO_LOG_DIR:-/tmp/tier7-survive-logs}/scenario.log"

log_info()  { echo "[$(date -u +%H:%M:%S)] [INFO]  $*" | tee -a "${LOG_FILE}"; }
log_warn()  { echo "[$(date -u +%H:%M:%S)] [WARN]  $*" | tee -a "${LOG_FILE}"; }
log_error() { echo "[$(date -u +%H:%M:%S)] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; }
log_pass()  { echo "[$(date -u +%H:%M:%S)] [PASS]  $*" | tee -a "${LOG_FILE}"; }
log_fail()  { echo "[$(date -u +%H:%M:%S)] [FAIL]  $*" | tee -a "${LOG_FILE}" >&2; }

# ============================================================
# Prerequisite checks
# ============================================================

check_required_vars() {
  local missing=0
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      log_error "Required variable not set: $var"
      missing=1
    fi
  done
  if [[ $missing -ne 0 ]]; then
    log_error "Set missing variables in survive/config.sh and re-run."
    exit 1
  fi
}

check_aws_cli() {
  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not found. Install it first."
    exit 1
  fi
  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS CLI is not configured or credentials are expired."
    exit 1
  fi
  log_info "AWS CLI authenticated as: $(aws sts get-caller-identity --query 'Arn' --output text)"
}

check_psql() {
  if ! command -v psql &>/dev/null; then
    log_error "psql not found. Install postgresql-client and retry."
    exit 1
  fi
}

# ============================================================
# RDS helpers
# ============================================================

rds_instance_status() {
  local identifier="$1"
  aws rds describe-db-instances \
    --db-instance-identifier "${identifier}" \
    --region "${AWS_REGION}" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND"
}

rds_cluster_status() {
  local identifier="$1"
  aws rds describe-db-clusters \
    --db-cluster-identifier "${identifier}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].Status' \
    --output text 2>/dev/null || echo "NOT_FOUND"
}

wait_for_rds_available() {
  local identifier="$1"
  local max_wait="${2:-600}"
  local elapsed=0

  log_info "Waiting for RDS instance ${identifier} to become available..."
  while [[ $(rds_instance_status "${identifier}") != "available" ]]; do
    if [[ $elapsed -ge $max_wait ]]; then
      log_error "Timed out waiting for ${identifier} after ${max_wait}s"
      return 1
    fi
    sleep 15
    elapsed=$((elapsed + 15))
    log_info "  Still waiting... (${elapsed}s elapsed)"
  done
  log_pass "Instance ${identifier} is available."
}

# ============================================================
# CloudWatch helpers
# ============================================================

get_metric_latest() {
  local namespace="$1"
  local metric="$2"
  local dimension_name="$3"
  local dimension_value="$4"
  local stat="${5:-Maximum}"

  aws cloudwatch get-metric-statistics \
    --namespace "${namespace}" \
    --metric-name "${metric}" \
    --dimensions "Name=${dimension_name},Value=${dimension_value}" \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 300 \
    --statistics "${stat}" \
    --region "${AWS_REGION}" \
    --query "Datapoints[0].${stat}" \
    --output text 2>/dev/null || echo "None"
}

get_alarm_state() {
  local alarm_name="$1"
  aws cloudwatch describe-alarms \
    --alarm-names "${alarm_name}" \
    --region "${AWS_REGION}" \
    --query 'MetricAlarms[0].StateValue' \
    --output text 2>/dev/null || echo "NOT_FOUND"
}

# ============================================================
# PostgreSQL helpers
# ============================================================

psql_source() {
  PGPASSWORD="${PGPASSWORD}" psql \
    -h "${SOURCE_DB_HOST}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -p "${DB_PORT:-5432}" \
    --no-password \
    "$@"
}

psql_target() {
  PGPASSWORD="${PGPASSWORD}" psql \
    -h "${TARGET_DB_HOST}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -p "${DB_PORT:-5432}" \
    --no-password \
    "$@"
}

check_replication_slot_lag() {
  local slot_name="$1"
  psql_source -t -A -c "
    SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
    FROM pg_replication_slots
    WHERE slot_name = '${slot_name}'
  " 2>/dev/null || echo "-1"
}

get_replication_slot_active() {
  local slot_name="$1"
  psql_source -t -A -c "
    SELECT active FROM pg_replication_slots WHERE slot_name = '${slot_name}'
  " 2>/dev/null || echo "f"
}

# ============================================================
# Validation framework
# ============================================================

PASS_COUNT=0
FAIL_COUNT=0

assert_equal() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" == "$expected" ]]; then
    log_pass "${description}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "${description} (expected='${expected}', actual='${actual}')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_empty() {
  local description="$1"
  local value="$2"

  if [[ -n "$value" && "$value" != "None" && "$value" != "NULL" ]]; then
    log_pass "${description}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "${description} (value was empty or None)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_less_than() {
  local description="$1"
  local value="$2"
  local threshold="$3"

  if [[ $(echo "${value} < ${threshold}" | bc -l) -eq 1 ]]; then
    log_pass "${description} (${value} < ${threshold})"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "${description} (${value} >= ${threshold})"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

print_validation_summary() {
  local scenario_name="$1"
  echo ""
  echo "=========================================="
  echo "  Validation Summary: ${scenario_name}"
  echo "=========================================="
  echo "  PASS: ${PASS_COUNT}"
  echo "  FAIL: ${FAIL_COUNT}"
  echo "=========================================="
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo "  RESULT: ALL CHECKS PASSED"
    echo "=========================================="
    return 0
  else
    echo "  RESULT: ${FAIL_COUNT} CHECK(S) FAILED"
    echo "  Check the runbook to resolve failures."
    echo "=========================================="
    return 1
  fi
}
