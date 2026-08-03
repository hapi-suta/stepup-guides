#!/usr/bin/env bash
# common.sh - Shared functions for SURVIVE scenarios
# Source this file from inject.sh and validate.sh scripts

# -------------------------------------------------------
# Colors for terminal output
# -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------------------------------
# Logging
# -------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date -u +%H:%M:%S) $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date -u +%H:%M:%S) $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date -u +%H:%M:%S) $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $(date -u +%H:%M:%S) $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# -------------------------------------------------------
# AWS RDS Helpers
# -------------------------------------------------------

# Get current status of an RDS instance
get_instance_status() {
    local instance_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws rds describe-db-instances \
        --db-instance-identifier "$instance_id" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region "$region" 2>/dev/null
}

# Get current status of an Aurora cluster
get_cluster_status() {
    local cluster_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws rds describe-db-clusters \
        --db-cluster-identifier "$cluster_id" \
        --query 'DBClusters[0].Status' \
        --output text \
        --region "$region" 2>/dev/null
}

# Get the current writer instance of an Aurora cluster
get_cluster_writer() {
    local cluster_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws rds describe-db-clusters \
        --db-cluster-identifier "$cluster_id" \
        --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
        --output text \
        --region "$region" 2>/dev/null
}

# Get replica lag in milliseconds from CloudWatch
get_replica_lag_ms() {
    local cluster_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name AuroraReplicaLag \
        --dimensions "Name=DBClusterIdentifier,Value=$cluster_id" \
        --start-time "$(date -u -v-2M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 60 \
        --statistics Maximum \
        --query 'Datapoints[0].Maximum' \
        --output text \
        --region "$region" 2>/dev/null
}

# Get current Serverless v2 ACU capacity
get_serverless_capacity() {
    local cluster_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name ServerlessDatabaseCapacity \
        --dimensions "Name=DBClusterIdentifier,Value=$cluster_id" \
        --start-time "$(date -u -v-2M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 60 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text \
        --region "$region" 2>/dev/null
}

# -------------------------------------------------------
# Database Connectivity Helpers
# -------------------------------------------------------

# Test if a PostgreSQL endpoint is reachable and accepting connections
test_db_connection() {
    local endpoint="$1"
    local user="${2:-$DB_USER}"
    local db="${3:-$DB_NAME}"
    psql -h "$endpoint" -U "$user" -d "$db" \
        -c "SELECT 1;" \
        --connect-timeout=5 \
        -q \
        > /dev/null 2>&1
    return $?
}

# Run a query and return the result
run_query() {
    local endpoint="$1"
    local query="$2"
    local user="${3:-$DB_USER}"
    local db="${4:-$DB_NAME}"
    psql -h "$endpoint" -U "$user" -d "$db" \
        -t -c "$query" \
        --connect-timeout=5 \
        2>/dev/null | tr -d ' '
}

# Check if an endpoint is read-only
is_read_only() {
    local endpoint="$1"
    local result
    result=$(run_query "$endpoint" "SELECT pg_is_in_recovery();")
    if [ "$result" = "t" ]; then
        return 0 # read-only
    else
        return 1 # read-write (writer)
    fi
}

# Measure time to reconnect after failure
measure_reconnect_time() {
    local endpoint="$1"
    local user="${2:-$DB_USER}"
    local db="${3:-$DB_NAME}"
    local max_wait=120
    local start
    local elapsed

    start=$(date +%s)
    while [ $(($(date +%s) - start)) -lt $max_wait ]; do
        if test_db_connection "$endpoint" "$user" "$db"; then
            elapsed=$(($(date +%s) - start))
            echo "$elapsed"
            return 0
        fi
        sleep 1
    done
    echo "TIMEOUT"
    return 1
}

# -------------------------------------------------------
# Validation Helpers
# -------------------------------------------------------

# Check result and print PASS/FAIL
check() {
    local description="$1"
    local result="$2"
    local expected="$3"
    if [ "$result" = "$expected" ]; then
        log_success "PASS: $description"
        return 0
    else
        log_error "FAIL: $description (expected=$expected, got=$result)"
        return 1
    fi
}

# Check that a value is numeric and under a threshold
check_threshold() {
    local description="$1"
    local value="$2"
    local threshold="$3"
    if echo "$value" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        if (( $(echo "$value < $threshold" | bc -l) )); then
            log_success "PASS: $description ($value < $threshold)"
            return 0
        else
            log_error "FAIL: $description ($value >= $threshold)"
            return 1
        fi
    else
        log_error "FAIL: $description (non-numeric value: $value)"
        return 1
    fi
}

# Wait for a cluster to reach a target status
wait_for_cluster_status() {
    local cluster_id="$1"
    local target_status="$2"
    local region="${3:-$AWS_PRIMARY_REGION}"
    local max_wait="${4:-300}"
    local start
    local status

    start=$(date +%s)
    log_info "Waiting for cluster $cluster_id to reach status: $target_status"

    while [ $(($(date +%s) - start)) -lt $max_wait ]; do
        status=$(get_cluster_status "$cluster_id" "$region")
        if [ "$status" = "$target_status" ]; then
            log_success "Cluster $cluster_id is now: $status"
            return 0
        fi
        log_info "Current status: $status - waiting..."
        sleep 10
    done

    log_error "Timeout waiting for $cluster_id to reach $target_status (last status: $status)"
    return 1
}

# -------------------------------------------------------
# Results Recording
# -------------------------------------------------------

record_result() {
    local scenario="$1"
    local metric="$2"
    local value="$3"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    mkdir -p "$SURVIVE_RESULTS_DIR"
    echo "$timestamp,$scenario,$metric,$value" >> "$SURVIVE_RESULTS_DIR/results.csv"
}

print_results_summary() {
    local scenario="$1"
    echo ""
    echo "--- Results for $scenario ---"
    if [ -f "$SURVIVE_RESULTS_DIR/results.csv" ]; then
        grep "$scenario" "$SURVIVE_RESULTS_DIR/results.csv" | \
            awk -F',' '{printf "  %-30s %s\n", $3, $4}'
    fi
    echo ""
}
