#!/bin/bash
# =============================================================================
# Module 09: Operations at Scale and SRE - SURVIVE Common Library
# =============================================================================
# Shared functions for SURVIVE inject.sh and validate.sh scripts.
# Source this file after config.sh.
#
# Usage:
#   source "$(dirname "$0")/../config.sh"
#   source "$(dirname "$0")/../lib/common.sh"
# =============================================================================

# ---------------------------------------------------------------------------
# Logging Functions
# ---------------------------------------------------------------------------

log_info() {
    echo "[INFO]  $(date -u +%H:%M:%S) $*"
}

log_warn() {
    echo "[WARN]  $(date -u +%H:%M:%S) $*"
}

log_error() {
    echo "[ERROR] $(date -u +%H:%M:%S) $*"
}

log_success() {
    echo "[OK]    $(date -u +%H:%M:%S) $*"
}

log_fail() {
    echo "[FAIL]  $(date -u +%H:%M:%S) $*"
}

log_step() {
    echo ""
    echo "--- Step $1: $2 ---"
}

# ---------------------------------------------------------------------------
# SQL Helpers
# ---------------------------------------------------------------------------

run_sql() {
    # Run a SQL command and return the output.
    # Usage: run_sql "SELECT 1;"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${M09_DB_HOST}" \
        -p "${M09_DB_PORT}" \
        -U "${M09_DB_USER}" \
        -d "${M09_DB_NAME}" \
        -t -A -c "$1" 2>/dev/null
}

run_sql_check() {
    # Run a SQL command and check if it succeeds.
    # Returns 0 on success, 1 on failure.
    # Usage: if run_sql_check "SELECT 1;"; then echo "ok"; fi
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${M09_DB_HOST}" \
        -p "${M09_DB_PORT}" \
        -U "${M09_DB_USER}" \
        -d "${M09_DB_NAME}" \
        -t -A -c "$1" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# CloudWatch Helpers
# ---------------------------------------------------------------------------

get_cloudwatch_metric() {
    # Get a CloudWatch metric value.
    # Usage: get_cloudwatch_metric "CPUUtilization" "Average" "300"
    local metric_name="$1"
    local statistic="${2:-Average}"
    local period="${3:-300}"

    aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name "${metric_name}" \
        --dimensions Name=DBClusterIdentifier,Value="${M09_CLUSTER_ID}" \
        --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period "${period}" \
        --statistics "${statistic}" \
        --query "Datapoints[0].${statistic}" \
        --output text \
        --region "${M09_REGION}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Validation Helpers
# ---------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0

validate_check() {
    # Run a validation check. Increments PASS_COUNT or FAIL_COUNT.
    # Usage: validate_check "Description" "command to run"
    local description="$1"
    shift
    if eval "$@" > /dev/null 2>&1; then
        log_success "PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_fail "FAIL: ${description}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

print_validation_summary() {
    local total=$((PASS_COUNT + FAIL_COUNT))
    echo ""
    echo "========================================="
    echo "Validation Summary"
    echo "========================================="
    echo "Passed: ${PASS_COUNT}/${total}"
    echo "Failed: ${FAIL_COUNT}/${total}"
    echo ""
    if [ "${FAIL_COUNT}" -eq 0 ]; then
        log_success "ALL CHECKS PASSED - Scenario remediated successfully"
    else
        log_fail "${FAIL_COUNT} CHECK(S) FAILED - Review the failures above"
    fi
    echo "========================================="
}

# ---------------------------------------------------------------------------
# Safety Warning
# ---------------------------------------------------------------------------

print_survive_warning() {
    local scenario_name="$1"
    echo ""
    echo "========================================="
    echo "  SURVIVE SCENARIO: ${scenario_name}"
    echo "========================================="
    echo ""
    echo "  This script will inject a failure condition"
    echo "  into your Aurora PostgreSQL cluster."
    echo ""
    echo "  Cluster: ${M09_CLUSTER_ID}"
    echo "  Region:  ${M09_REGION}"
    echo ""
    echo "  DO NOT run this on a production database."
    echo ""
    echo "========================================="
    echo ""
    read -p "Type CONFIRM to proceed: " response
    if [ "${response}" != "CONFIRM" ]; then
        echo "Aborted."
        exit 1
    fi
    echo ""
}
