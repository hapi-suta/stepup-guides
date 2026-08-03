#!/usr/bin/env bash
# SUTA Labs - Tier 5 SURVIVE Common Library
# Source this file after config.sh

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Logging ──────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[PASS]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
log_section() { echo -e "\n${BLUE}===== $* =====${NC}\n"; }

# ─── AWS helpers ──────────────────────────────────────────────────────────────

# Resolve DB_HOST from DB_INSTANCE if not already set
resolve_db_host() {
    if [[ -z "${DB_HOST:-}" ]]; then
        log_info "Resolving DB_HOST from instance: $DB_INSTANCE"
        DB_HOST=$(aws rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].Endpoint.Address' \
            --output text 2>/dev/null)
        if [[ -z "$DB_HOST" || "$DB_HOST" == "None" ]]; then
            log_fail "Could not resolve endpoint for $DB_INSTANCE"
            exit 1
        fi
        export DB_HOST
        log_info "DB_HOST resolved to: $DB_HOST"
    fi
}

# Get the latest restorable time as a Unix timestamp
get_latest_restorable_epoch() {
    local ts
    ts=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].LatestRestorableTime' \
        --output text)
    date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${ts%%.*}" +%s 2>/dev/null
}

# Wait for an RDS instance to reach "available"
wait_for_instance() {
    local instance_id="$1"
    log_info "Waiting for instance $instance_id to become available..."
    aws rds wait db-instance-available \
        --db-instance-identifier "$instance_id" \
        --region "$AWS_REGION"
    log_ok "Instance $instance_id is available"
}

# Run a SQL query and return its output
run_sql() {
    local query="$1"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "$DB_HOST" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -tAc "$query" 2>/dev/null
}

# Run a SQL query against a specific host
run_sql_on() {
    local host="$1"
    local query="$2"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "$host" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -tAc "$query" 2>/dev/null
}

# ─── Validation helpers ───────────────────────────────────────────────────────

check_pass() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_ok "$label: $actual"
        return 0
    else
        log_fail "$label: expected '$expected', got '$actual'"
        return 1
    fi
}

check_numeric_gte() {
    local label="$1"
    local threshold="$2"
    local actual="$3"
    if (( $(echo "$actual >= $threshold" | bc -l) )); then
        log_ok "$label: $actual (>= $threshold)"
        return 0
    else
        log_fail "$label: $actual is below threshold $threshold"
        return 1
    fi
}

check_contains() {
    local label="$1"
    local expected_substring="$2"
    local actual="$3"
    if echo "$actual" | grep -q "$expected_substring"; then
        log_ok "$label: found '$expected_substring'"
        return 0
    else
        log_fail "$label: '$expected_substring' not found in output"
        return 1
    fi
}

# ─── Timer ────────────────────────────────────────────────────────────────────
TIMER_START=0

timer_start() {
    TIMER_START=$(date +%s)
    log_info "Timer started"
}

timer_elapsed() {
    local now
    now=$(date +%s)
    echo $(( now - TIMER_START ))
}

timer_check_rto() {
    local elapsed
    elapsed=$(timer_elapsed)
    local elapsed_min=$(( elapsed / 60 ))
    if (( elapsed_min <= RTO_TARGET_MINUTES )); then
        log_ok "RTO met: ${elapsed_min}m elapsed (target: ${RTO_TARGET_MINUTES}m)"
    else
        log_warn "RTO exceeded: ${elapsed_min}m elapsed (target: ${RTO_TARGET_MINUTES}m)"
    fi
}
