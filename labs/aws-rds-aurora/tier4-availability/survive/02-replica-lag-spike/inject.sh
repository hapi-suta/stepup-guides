#!/usr/bin/env bash
# SURVIVE 02 - inject.sh
# Causes replica lag to spike by generating a massive write storm on the Aurora writer
# Students must diagnose the lag, identify the cause, and respond

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 02 - Replica Lag Spike Injection"

# -------------------------------------------------------
# Pre-injection: confirm cluster is healthy
# -------------------------------------------------------
log_info "Checking Aurora cluster before injection..."

CLUSTER_STATUS=$(get_cluster_status "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$CLUSTER_STATUS" != "available" ]; then
    log_error "Cluster is not in 'available' state (got: $CLUSTER_STATUS). Aborting."
    exit 1
fi

# Check baseline lag
BASELINE_LAG=$(get_replica_lag_ms "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
log_info "Baseline replica lag: ${BASELINE_LAG}ms"
record_result "02-replica-lag-spike" "baseline_lag_ms" "${BASELINE_LAG:-unknown}"
record_result "02-replica-lag-spike" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Injection: massive bulk insert on the writer
# The load runs for 3 minutes, long enough to cause noticeable lag
# -------------------------------------------------------
log_warn "INJECTING FAULT: Starting write storm on Aurora writer..."
log_warn "This will cause replica lag to spike significantly."
log_warn "The write storm will run for approximately 3 minutes."

cat << 'EOF' > /tmp/survive02-inject.sql
-- Create the storm table if it doesn't exist
CREATE TABLE IF NOT EXISTS survive_lag_test (
    id BIGSERIAL PRIMARY KEY,
    payload TEXT,
    batch_id INT,
    created_at TIMESTAMPTZ DEFAULT now()
);
EOF

(
psql -h "$AURORA_WRITER_ENDPOINT" \
     -U "$DB_USER" \
     -d "$DB_NAME" \
     -f /tmp/survive02-inject.sql

# Generate write load in a shell loop (60 batches, 5000 rows each, 2 second pause)
for batch in $(seq 0 59); do
    psql -h "$AURORA_WRITER_ENDPOINT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         -c "INSERT INTO survive_lag_test (payload, batch_id) SELECT md5(random()::text) || md5(random()::text), $batch FROM generate_series(1, 5000);"
    sleep 2
done
) > "$SURVIVE_LOG_DIR/survive02-inject.log" 2>&1 &

INJECT_PID=$!
echo $INJECT_PID > /tmp/survive02-inject.pid

log_info "Write storm started in background (PID: $INJECT_PID)"
log_info "---"
log_info "What the student will see:"
log_info "  - CloudWatch AuroraReplicaLag metric climbing"
log_info "  - Reads from the reader endpoint returning stale data"
log_info "  - pg_last_xact_replay_timestamp() lagging further behind now()"
log_info "---"
log_info "The student must:"
log_info "  1. Detect elevated replica lag (CloudWatch or SQL query)"
log_info "  2. Identify the cause (heavy write activity)"
log_info "  3. Decide whether to redirect reads to the writer temporarily"
log_info "  4. Wait for lag to recover after the write storm ends"
log_info "---"
log_info "To stop the write storm early:"
log_info "  kill \$(cat /tmp/survive02-inject.pid)"
log_info "---"
log_info "Run validate.sh after the write storm ends and lag recovers."
