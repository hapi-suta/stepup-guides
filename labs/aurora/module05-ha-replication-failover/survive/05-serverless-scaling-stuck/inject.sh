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
# Pre-injection: verify Serverless v2 cluster exists
# -------------------------------------------------------
log_info "Checking Serverless v2 cluster $SERVERLESS_CLUSTER_ID..."

CLUSTER_STATUS=$(get_cluster_status "$SERVERLESS_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$CLUSTER_STATUS" != "available" ]; then
    log_error "Cluster $SERVERLESS_CLUSTER_ID is not available (status: $CLUSTER_STATUS)"
    log_error "Complete BUILD 06 (Serverless v2 Basics) first."
    exit 1
fi

# -------------------------------------------------------
# Record baseline state
# -------------------------------------------------------
BASELINE_ACU=$(get_serverless_capacity "$SERVERLESS_CLUSTER_ID" "$AWS_PRIMARY_REGION")
CURRENT_MAX=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$SERVERLESS_CLUSTER_ID" \
    --query 'DBClusters[0].ServerlessV2ScalingConfiguration.MaxCapacity' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

log_info "Baseline ACU: ${BASELINE_ACU:-unknown}"
log_info "Current MaxCapacity: ${CURRENT_MAX:-unknown}"

record_result "05-serverless-scaling-stuck" "baseline_acu" "${BASELINE_ACU:-unknown}"
record_result "05-serverless-scaling-stuck" "original_max_acu" "${CURRENT_MAX:-unknown}"
record_result "05-serverless-scaling-stuck" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Injection: set ACU maximum to 2 (simulating misconfigured ceiling)
# -------------------------------------------------------
log_warn "INJECTING FAULT: Setting Serverless v2 MaxCapacity to 2 ACU..."
log_warn "This simulates someone accidentally setting the max too low."

aws rds modify-db-cluster \
    --db-cluster-identifier "$SERVERLESS_CLUSTER_ID" \
    --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=2 \
    --apply-immediately \
    --region "$AWS_PRIMARY_REGION" > /dev/null 2>&1

record_result "05-serverless-scaling-stuck" "injected_max_acu" "2"

log_info "ACU maximum set to 2. Waiting 30 seconds for the change to take effect..."
sleep 30

# -------------------------------------------------------
# Generate load that exceeds 2 ACU
# -------------------------------------------------------
log_warn "Starting load generator (will exceed 2 ACU ceiling)..."

# Create the test table if it does not exist
psql -h "$SERVERLESS_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    --connect-timeout=10 \
    -c "CREATE TABLE IF NOT EXISTS serverless_load_test (id SERIAL PRIMARY KEY, payload TEXT, batch_id INT, created_at TIMESTAMPTZ DEFAULT now());" \
    > /dev/null 2>&1

# Create a load script that generates CPU and memory pressure
cat << 'EOF' > /tmp/survive05-load.sql
DO $$
DECLARE
    i INT := 0;
BEGIN
    WHILE i < 5000 LOOP
        INSERT INTO serverless_load_test (payload, batch_id)
        VALUES (md5(random()::text) || md5(random()::text), 505);
        i := i + 1;
        IF i % 500 = 0 THEN
            PERFORM pg_sleep(0.01);
        END IF;
    END LOOP;
END$$;

-- Generate CPU pressure with full table scans
SELECT COUNT(*) FROM serverless_load_test
WHERE payload LIKE '%a%' OR payload LIKE '%b%' OR payload LIKE '%c%';
EOF

# Run multiple parallel load sessions in the background
for session in 1 2 3 4 5; do
    psql -h "$SERVERLESS_ENDPOINT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         -f /tmp/survive05-load.sql \
         > "$SURVIVE_LOG_DIR/survive05-session${session}.log" 2>&1 &
done

log_info "Load sessions started in background (5 parallel sessions)."
log_info "---"
log_info "What the student will see:"
log_info "  - CloudWatch ServerlessDatabaseCapacity pinned at or near 2 ACU"
log_info "  - DatabaseConnections metric climbing"
log_info "  - Query latency increasing (queries are queuing)"
log_info "  - Possible connection timeouts for new connections"
log_info "---"
log_info "The student must:"
log_info "  1. Check CloudWatch ServerlessDatabaseCapacity metric"
log_info "  2. Identify that the cluster is at its ACU ceiling (MaxCapacity = 2)"
log_info "  3. Increase MaxCapacity to allow scaling (e.g., to 16 ACU)"
log_info "  4. Confirm the cluster scales up and latency recovers"
log_info "  5. Create a CloudWatch alarm to prevent future ceiling hits"
log_info "---"
log_info "Run validate.sh after increasing MaxCapacity and confirming scale-up."
