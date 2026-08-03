#!/usr/bin/env bash
# SURVIVE 05 - inject.sh
# Simulates a Serverless v2 cluster hitting its ACU maximum
# Queries start queuing and latency increases
# Students must diagnose and increase the ACU ceiling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 05 - Serverless v2 ACU Ceiling Hit"

# -------------------------------------------------------
# Pre-injection: set the ACU maximum to a low value
# to ensure the load test hits the ceiling quickly
# -------------------------------------------------------
log_info "Checking Serverless v2 cluster $SERVERLESS_CLUSTER_ID..."

CLUSTER_STATUS=$(get_cluster_status "$SERVERLESS_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$CLUSTER_STATUS" != "available" ]; then
    log_error "Cluster $SERVERLESS_CLUSTER_ID is not available (status: $CLUSTER_STATUS)"
    log_error "Complete BUILD 07 first."
    exit 1
fi

# Record baseline
BASELINE_ACU=$(get_serverless_capacity "$SERVERLESS_CLUSTER_ID" "$AWS_PRIMARY_REGION")
log_info "Baseline ACU: ${BASELINE_ACU:-unknown}"
record_result "05-serverless-scaling-stuck" "baseline_acu" "${BASELINE_ACU:-unknown}"
record_result "05-serverless-scaling-stuck" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Set ACU maximum to 2 to simulate a misconfigured ceiling
# (someone accidentally set the max too low)
# -------------------------------------------------------
log_warn "INJECTING FAULT: Setting Serverless v2 MaxCapacity to 2 ACU (simulating misconfigured ceiling)..."

aws rds modify-db-cluster \
    --db-cluster-identifier "$SERVERLESS_CLUSTER_ID" \
    --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=2 \
    --apply-immediately \
    --region "$AWS_PRIMARY_REGION"

record_result "05-serverless-scaling-stuck" "injected_max_acu" "2"

log_info "ACU maximum set to 2. Starting load generator..."

# -------------------------------------------------------
# Generate load that exceeds 2 ACU
# This will pin the cluster at the ceiling and cause query queuing
# -------------------------------------------------------
log_warn "Starting load test (will exceed 2 ACU ceiling)..."

cat << 'EOF' > /tmp/survive05-load.sql
-- Generate CPU and memory pressure
DO $$
DECLARE
    i INT := 0;
BEGIN
    WHILE i < 10000 LOOP
        PERFORM COUNT(*) FROM survive_lag_test
        WHERE payload LIKE '%a%'
           OR payload LIKE '%b%'
           OR payload LIKE '%c%';
        i := i + 1;
        PERFORM pg_sleep(0.01);
    END LOOP;
END$$;
EOF

# Run multiple parallel load sessions
for session in 1 2 3 4 5; do
    psql -h "$SERVERLESS_ENDPOINT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         -f /tmp/survive05-load.sql \
         > "$SURVIVE_LOG_DIR/survive05-session${session}.log" 2>&1 &
done

log_info "Load sessions started in background."
log_info "---"
log_info "What the student will see:"
log_info "  - CloudWatch ServerlessDatabaseCapacity pinned at or near 2 ACU"
log_info "  - DatabaseConnections metric high"
log_info "  - Query latency increasing (queries are queuing)"
log_info "  - Connection timeouts for new connections"
log_info "---"
log_info "The student must:"
log_info "  1. Check CloudWatch ServerlessDatabaseCapacity metric"
log_info "  2. Identify that the cluster is at its ACU ceiling"
log_info "  3. Increase MaxCapacity to allow scaling"
log_info "  4. Confirm the cluster scales up and latency recovers"
log_info "---"
log_info "HINT: The fix is one CLI command:"
log_info "  aws rds modify-db-cluster --db-cluster-identifier $SERVERLESS_CLUSTER_ID"
log_info "  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16"
log_info "  --apply-immediately --region $AWS_PRIMARY_REGION"
log_info "---"
log_info "Run validate.sh after increasing the ACU ceiling and confirming scale-up."
