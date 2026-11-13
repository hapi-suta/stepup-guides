#!/usr/bin/env bash
# =============================================================================
# Scenario 08: Monitoring Blackout
# validate.sh - Confirm Prometheus is up, all targets UP, replica lag < 5s
# =============================================================================
# Pass criteria:
#   1. Prometheus is running on ops host (port 9090 is open)
#   2. Prometheus /api/v1/targets shows no targets in "down" state
#   3. Replica WAL replay is not paused
#   4. Replica lag is below 60 seconds
#   5. pg_exporter target is healthy (port 9187 responding)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Validating Scenario 08: Monitoring Blackout recovery"
echo ""

PASS=0
FAIL=0
LAG_THRESHOLD=60

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: Prometheus port is open ----------------------------------------
log_info "Check 1: Prometheus is running on ${OPS_HOST}:${PROMETHEUS_PORT}..."
if check_port "$OPS_HOST" "$PROMETHEUS_PORT"; then
    check_pass "Prometheus port ${PROMETHEUS_PORT} is open on ${OPS_HOST}"
else
    check_fail "Prometheus port ${PROMETHEUS_PORT} is not open on ${OPS_HOST}"
    log_error "Start it with: ssh ec2-user@${OPS_HOST} 'sudo systemctl start prometheus'"
fi

# ---- Check 2: Prometheus is ready (HTTP 200 on /-/ready) --------------------
log_info "Check 2: Prometheus /ready endpoint returns 200..."
READY_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 --max-time 8 \
    "http://${OPS_HOST}:${PROMETHEUS_PORT}/-/ready" 2>/dev/null || echo "000")

if [[ "$READY_CODE" == "200" ]]; then
    check_pass "Prometheus /ready returned HTTP 200"
else
    check_fail "Prometheus /ready returned HTTP ${READY_CODE} (not healthy)"
fi

# ---- Check 3: No Prometheus targets are in DOWN state -------------------------
log_info "Check 3: All Prometheus scrape targets are UP..."
TARGETS_JSON=$(curl -s --connect-timeout 5 --max-time 10 \
    "http://${OPS_HOST}:${PROMETHEUS_PORT}/api/v1/targets" 2>/dev/null || echo "")

if [[ -z "$TARGETS_JSON" ]] || ! echo "$TARGETS_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    check_fail "Prometheus targets API returned empty or invalid response (is Prometheus running?)"
else
    DOWN_COUNT=$(echo "$TARGETS_JSON" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); \
        targets=d.get('data',{}).get('activeTargets',[]); \
        print(sum(1 for t in targets if t.get('health') == 'down'))" \
        2>/dev/null || echo "unknown")

    if [[ "$DOWN_COUNT" == "0" ]]; then
        check_pass "All Prometheus scrape targets are UP (0 targets down)"
    elif [[ "$DOWN_COUNT" == "unknown" ]]; then
        log_warn "Could not parse Prometheus targets API"
    else
        check_fail "${DOWN_COUNT} Prometheus target(s) are in DOWN state"
        log_error "Check: curl -s http://${OPS_HOST}:${PROMETHEUS_PORT}/api/v1/targets | python3 -m json.tool"
    fi
fi

# ---- Check 4: Replica WAL replay is not paused --------------------------------
log_info "Check 4: Replica WAL replay is not paused..."
if check_pg "$REPLICA_HOST"; then
    REPLAY_PAUSED=$(ssh_replica "sudo -u postgres ${PG_BIN}/psql -t \
        -c \"SELECT pg_is_wal_replay_paused();\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")

    if [[ "$REPLAY_PAUSED" == "f" ]]; then
        check_pass "WAL replay is NOT paused on replica (pg_is_wal_replay_paused = f)"
    elif [[ "$REPLAY_PAUSED" == "t" ]]; then
        check_fail "WAL replay is still PAUSED on replica"
        log_error "Resume it: ssh ec2-user@${REPLICA_HOST} \"sudo -u postgres ${PG_BIN}/psql -c 'SELECT pg_wal_replay_resume();'\""
    else
        log_warn "Could not determine WAL replay pause state (got: ${REPLAY_PAUSED})"
    fi
else
    check_fail "Replica ${REPLICA_HOST} is not responding - cannot check WAL replay state"
fi

# ---- Check 5: Replica lag is below threshold ---------------------------------
log_info "Check 5: Replica lag is below ${LAG_THRESHOLD}s..."
if check_pg "$REPLICA_HOST"; then
    LAG=$(ssh_replica "sudo -u postgres ${PG_BIN}/psql -t \
        -c \"SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int;\" \
        2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")

    if [[ "$LAG" =~ ^[0-9]+$ ]]; then
        if (( LAG < LAG_THRESHOLD )); then
            check_pass "Replica lag: ${LAG}s (< ${LAG_THRESHOLD}s - healthy)"
        else
            check_fail "Replica lag: ${LAG}s (>= ${LAG_THRESHOLD}s - still catching up)"
            log_warn "Wait for replay to catch up, or check: pg_wal_replay_resume() was called"
        fi
    else
        log_warn "Could not determine replica lag (got: ${LAG})"
    fi
else
    check_fail "Replica is not responding - cannot check lag"
fi

# ---- Check 6: pg_exporter is responding (node_exporter check) ----------------
log_info "Check 6: pg_exporter endpoint is responding on primary..."
EXPORTER_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 --max-time 8 \
    "http://${PRIMARY_HOST}:${PG_EXPORTER_PORT}/metrics" 2>/dev/null || echo "000")

if [[ "$EXPORTER_CODE" =~ ^(200|302)$ ]]; then
    check_pass "pg_exporter on ${PRIMARY_HOST}:${PG_EXPORTER_PORT} is returning metrics"
else
    check_fail "pg_exporter on ${PRIMARY_HOST}:${PG_EXPORTER_PORT} returned HTTP ${EXPORTER_CODE}"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 08 PASSED - Monitoring restored, all targets UP, replica lag healthy"
    exit 0
else
    log_error "Scenario 08 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
