#!/usr/bin/env bash
# survive/lib/common.sh
# Shared helper functions for inject, runbook validation, and validate scripts.

# Source config if not already sourced
if [[ -z "$DB_INSTANCE_ID" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
fi

# -------------------------------------------------------------------
# Connectivity check
# -------------------------------------------------------------------
check_connectivity() {
    local result
    result=$(psql_exec "SELECT 1" 2>&1)
    if [[ "$result" == "1" ]]; then
        pass "Database connectivity: OK"
        return 0
    else
        fail "Database connectivity: FAILED - $result"
        return 1
    fi
}

# -------------------------------------------------------------------
# Check a CloudWatch metric value
# -------------------------------------------------------------------
get_cloudwatch_metric() {
    local metric_name="$1"
    local namespace="${2:-AWS/RDS}"
    local stat="${3:-Average}"
    local period="${4:-300}"

    aws cloudwatch get-metric-statistics \
        --namespace "$namespace" \
        --metric-name "$metric_name" \
        --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
        --start-time "$(date -u -v-${period}S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date="${period} seconds ago" +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period "$period" \
        --statistics "$stat" \
        --query "Datapoints[0].${stat}" \
        --output text \
        --region "$REGION" 2>/dev/null
}

# -------------------------------------------------------------------
# Check active connection count
# -------------------------------------------------------------------
get_connection_count() {
    psql_exec "SELECT count(*) FROM pg_stat_activity WHERE state != 'idle'"
}

# -------------------------------------------------------------------
# Check dead tuple count for a table
# -------------------------------------------------------------------
get_dead_tuples() {
    local table_name="$1"
    psql_exec "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = '${table_name}'"
}

# -------------------------------------------------------------------
# Check XID age of a table
# -------------------------------------------------------------------
get_xid_age() {
    local table_name="${1:-}"
    if [[ -n "$table_name" ]]; then
        psql_exec "SELECT age(relfrozenxid) FROM pg_class WHERE relname = '${table_name}'"
    else
        psql_exec "SELECT max(age(datfrozenxid)) FROM pg_database"
    fi
}

# -------------------------------------------------------------------
# Check if an index exists
# -------------------------------------------------------------------
index_exists() {
    local index_name="$1"
    local result
    result=$(psql_exec "SELECT 1 FROM pg_indexes WHERE indexname = '${index_name}'")
    [[ "$result" == "1" ]]
}

# -------------------------------------------------------------------
# Kill all connections matching a pattern
# -------------------------------------------------------------------
kill_connections_like() {
    local query_pattern="$1"
    psql_exec "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
               WHERE query LIKE '${query_pattern}' AND pid != pg_backend_pid()"
}

# -------------------------------------------------------------------
# Wait for a condition with timeout
# -------------------------------------------------------------------
wait_for_condition() {
    local condition_fn="$1"
    local timeout="${2:-120}"
    local interval="${3:-5}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if $condition_fn; then
            return 0
        fi
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
        info "Waiting... ${elapsed}s / ${timeout}s"
    done
    return 1
}

# -------------------------------------------------------------------
# Print a section header
# -------------------------------------------------------------------
section() {
    echo ""
    echo "================================================================"
    echo "  $*"
    echo "================================================================"
}

# -------------------------------------------------------------------
# Timestamp
# -------------------------------------------------------------------
ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "[$(ts)] $*"
}
