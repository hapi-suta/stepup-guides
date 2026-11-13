#!/usr/bin/env bash
# =============================================================================
# Scenario 08: Monitoring Blackout
# inject.sh - Stop Prometheus and introduce replica lag to create blind spot
# =============================================================================
# What breaks: Prometheus stops scraping. All alerting rules fire "no data"
#              or go silent. The replica is artificially slowed, building lag,
#              but no alert fires because Prometheus is down.
# Your job:    Restore Prometheus, fix replica lag, verify all targets are UP,
#              and lag alert is firing correctly again.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Scenario 08: Monitoring Blackout"
log_info "Targets: Prometheus on ${OPS_HOST}, replica lag on ${REPLICA_HOST}"
echo ""

# Confirm connectivity to ops and replica
log_info "Checking SSH connectivity to ops and replica nodes..."
if ! check_ssh "$OPS_HOST"; then
    log_error "Cannot SSH into ops host (${OPS_HOST})"
    exit 1
fi
if ! check_ssh "$REPLICA_HOST"; then
    log_error "Cannot SSH into replica (${REPLICA_HOST})"
    exit 1
fi
log_success "Both nodes are reachable"

# Part 1: Stop Prometheus
log_info "Stopping Prometheus on ${OPS_HOST}..."
if check_port "$OPS_HOST" "$PROMETHEUS_PORT" 2>/dev/null; then
    ssh_ops "sudo systemctl stop prometheus"
    sleep 2
    if ! check_port "$OPS_HOST" "$PROMETHEUS_PORT" 2>/dev/null; then
        log_success "Prometheus stopped successfully"
    else
        log_warn "Prometheus port ${PROMETHEUS_PORT} still open - may need a moment to shut down"
    fi
else
    log_warn "Prometheus was already not running on port ${PROMETHEUS_PORT}"
fi

# Part 2: Slow down replica WAL replay to build artificial lag
# We pause WAL replay on the replica temporarily, then let WAL pile up.
log_info "Pausing WAL replay on replica to build lag..."
ssh_replica "sudo -u postgres ${PG_BIN}/psql \
    -c \"SELECT pg_wal_replay_pause();\" 2>/dev/null" || {
    log_warn "pg_wal_replay_pause() failed - may not be in hot standby mode or paused already"
}

# Generate WAL activity on the primary to build up the lag
log_info "Generating WAL activity on primary to build replica lag..."
ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
    -c \"INSERT INTO quant.instruments (symbol, name, asset_class) \
    SELECT 'CHAOS08_' || i, 'Monitoring Test', 'equity' \
    FROM generate_series(1, 200) i;
    DELETE FROM quant.instruments WHERE symbol LIKE 'CHAOS08_%';\" \
    2>/dev/null" || log_warn "Could not generate WAL activity on primary"

# Wait 15 seconds to build noticeable lag
log_info "Waiting 15s to let lag accumulate..."
sleep 15

# Check current lag
LAG=$(ssh_replica "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int;\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")
log_info "Current replica lag: ${LAG}s"

echo ""
log_success "Monitoring blackout injected:"
log_success "  - Prometheus stopped on ${OPS_HOST}"
log_success "  - Replica WAL replay paused (lag: ${LAG}s)"
echo ""
echo "  The monitoring stack is blind. Replica lag is growing."
echo "  No alerts will fire because Prometheus is down."
echo ""
echo "  Your tasks:"
echo "    1. Notice the monitoring gap (Grafana shows stale data or N/A)"
echo "    2. Restart Prometheus: sudo systemctl start prometheus"
echo "    3. Resume WAL replay on the replica:"
echo "       sudo -u postgres ${PG_BIN}/psql -c \"SELECT pg_wal_replay_resume();\""
echo "    4. Verify Prometheus targets are all UP:"
echo "       curl http://${OPS_HOST}:${PROMETHEUS_PORT}/api/v1/targets"
echo "    5. Verify replica lag drops back to normal (< 5s)"
echo "    6. Confirm lag alert rule would fire correctly"
echo ""
echo "  Key question: How long was the monitoring blind?"
echo "  Check Prometheus TSDB: was there a gap in the metrics?"
echo ""
echo "  When done: ./chaos.sh validate 08-monitoring-blackout"
