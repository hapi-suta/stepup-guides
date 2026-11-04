#!/usr/bin/env bash
# =============================================================================
# Scenario 06: Ansible Config Drift
# validate.sh - Confirm pg_hba.conf is correct and replication is working
# =============================================================================
# Pass criteria:
#   1. pg_hba.conf does NOT contain 10.99.0.0/16 (wrong CIDR is gone)
#   2. pg_hba.conf does NOT contain an unconditional TRUST for 0.0.0.0/0
#   3. pg_hba.conf DOES contain a valid replication entry (not 10.99.0.0/16)
#   4. Streaming replication is active (at least 1 replica in streaming state)
#   5. Replica lag is below 30 seconds
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

PG_HBA="${PG_DATA}/pg_hba.conf"

log_info "Validating Scenario 06: Ansible Config Drift recovery"
echo ""

PASS=0
FAIL=0

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: SSH into primary -----------------------------------------------
log_info "Check 1: Primary is reachable..."
if check_ssh "$PRIMARY_HOST"; then
    check_pass "Primary ${PRIMARY_HOST} is reachable"
else
    check_fail "Cannot SSH into primary ${PRIMARY_HOST}"
    exit 1
fi

# ---- Check 2: Wrong CIDR is removed ------------------------------------------
log_info "Check 2: Bad replication CIDR (10.99.0.0/16) is not in pg_hba.conf..."
BAD_CIDR=$(ssh_primary "sudo grep '10\.99\.0\.0/16' ${PG_HBA} 2>/dev/null | wc -l | tr -d '[:space:]'" \
    2>/dev/null || echo "unknown")

if [[ "$BAD_CIDR" == "0" ]]; then
    check_pass "Bad CIDR 10.99.0.0/16 is not in pg_hba.conf"
else
    check_fail "Bad CIDR 10.99.0.0/16 is still present in pg_hba.conf (${BAD_CIDR} line(s))"
fi

# ---- Check 3: Suspicious TRUST line is removed --------------------------------
log_info "Check 3: No unconditional TRUST entry for 0.0.0.0/0 in pg_hba.conf..."
TRUST_LINE=$(ssh_primary "sudo grep -c '0\.0\.0\.0/0.*trust' ${PG_HBA} 2>/dev/null | tr -d '[:space:]'" \
    2>/dev/null || echo "0")

if [[ "$TRUST_LINE" == "0" ]]; then
    check_pass "No unconditional TRUST entry for 0.0.0.0/0 in pg_hba.conf"
else
    check_fail "Unsafe TRUST entry for 0.0.0.0/0 is still in pg_hba.conf - security risk"
fi

# ---- Check 4: A valid replication entry exists (not 10.99.0.0/16) -----------
log_info "Check 4: A valid replication entry for replicator exists in pg_hba.conf..."
REPL_LINE=$(ssh_primary "sudo grep -E 'replication.*replicator' ${PG_HBA} 2>/dev/null | grep -v '10\.99\.0\.0' | wc -l | tr -d '[:space:]'" \
    2>/dev/null || echo "0")

if [[ "$REPL_LINE" =~ ^[0-9]+$ ]] && (( REPL_LINE >= 1 )); then
    check_pass "Valid replication entry for replicator exists in pg_hba.conf"
else
    check_fail "No valid replication entry for replicator in pg_hba.conf (only bad CIDR or missing)"
fi

# ---- Check 5: Streaming replication is active --------------------------------
log_info "Check 5: Streaming replication is active..."
REPL_COUNT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT COUNT(*) FROM pg_stat_replication WHERE state = 'streaming';\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "0")

if [[ "$REPL_COUNT" =~ ^[0-9]+$ ]] && (( REPL_COUNT >= 1 )); then
    check_pass "Streaming replication is active (${REPL_COUNT} replica(s) in streaming state)"
else
    check_fail "No replicas in streaming state - replica may not have reconnected yet"
    log_warn "Wait 30s and try again, or check: sudo -u postgres psql -c \"SELECT * FROM pg_stat_replication;\""
fi

# ---- Check 6: Replica lag is healthy -----------------------------------------
log_info "Check 6: Replica lag is below 30 seconds..."
WRITE_LAG=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT EXTRACT(EPOCH FROM write_lag)::int FROM pg_stat_replication LIMIT 1;\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "unknown")

if [[ "$WRITE_LAG" =~ ^[0-9]+$ ]]; then
    if (( WRITE_LAG < 30 )); then
        check_pass "Replication write lag: ${WRITE_LAG}s (healthy)"
    else
        check_fail "Replication write lag: ${WRITE_LAG}s (>= 30s - replica is catching up)"
    fi
else
    log_warn "Could not determine write lag (likely no replica connected)"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 06 PASSED - pg_hba.conf is correct and replication is healthy"
    exit 0
else
    log_error "Scenario 06 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
