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
NC='\033[0m'

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

get_cluster_status() {
    local cluster_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws rds describe-db-clusters \
        --db-cluster-identifier "$cluster_id" \
        --query 'DBClusters[0].Status' \
        --output text \
        --region "$region" 2>/dev/null
}

get_instance_status() {
    local instance_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws rds describe-db-instances \
        --db-instance-identifier "$instance_id" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region "$region" 2>/dev/null
}

get_cluster_writer() {
    local cluster_id="$1"
    local region="${2:-$AWS_PRIMARY_REGION}"
    aws rds describe-db-clusters \
        --db-cluster-identifier "$cluster_id" \
        --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
        --output text \
        --region "$region" 2>/dev/null
}

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

record_result() {
    local scenario="$1"
    local metric="$2"
    local value="$3"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$SURVIVE_RESULTS_DIR"
    echo "$timestamp,$scenario,$metric,$value" >> "$SURVIVE_RESULTS_DIR/results.csv"
}
