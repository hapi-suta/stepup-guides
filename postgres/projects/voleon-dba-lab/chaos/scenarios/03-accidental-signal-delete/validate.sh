#!/usr/bin/env bash
# =============================================================================
# Scenario 03: Accidental Signal Delete
# validate.sh - Confirm signal data has been restored
# =============================================================================
# Pass criteria:
#   1. quant.signals has at least 1000 rows (data was restored)
#   2. The current month partition exists and has rows
#   3. PostgreSQL is in read-write mode (not stuck in recovery)
#   4. Replication is flowing (replica is catching up)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Validating Scenario 03: Accidental Signal Delete recovery"
echo ""

PASS=0
FAIL=0
MIN_ROWS=1000

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: PostgreSQL is accepting connections ---------------------------
log_info "Check 1: PostgreSQL is responding on primary..."
if check_pg "$PRIMARY_HOST"; then
    check_pass "PostgreSQL is responding on ${PRIMARY_HOST}"
else
    check_fail "PostgreSQL is not responding on ${PRIMARY_HOST}"
    echo "  Cannot continue - no database to query."
    exit 1
fi

# ---- Check 2: Primary is in read-write mode ---------------------------------
log_info "Check 2: Primary is in read-write mode..."
IN_RECOVERY=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT pg_is_in_recovery();\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "error")

if [[ "$IN_RECOVERY" == "f" ]]; then
    check_pass "Primary is in read-write mode (not in recovery)"
else
    check_fail "Primary is in recovery mode or could not determine status (got: ${IN_RECOVERY})"
fi

# ---- Check 3: quant.signals has at least MIN_ROWS rows ----------------------
log_info "Check 3: quant.signals has at least ${MIN_ROWS} rows..."
TOTAL_ROWS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM quant.signals;\" 2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "0")

if [[ "$TOTAL_ROWS" =~ ^[0-9]+$ ]] && (( TOTAL_ROWS >= MIN_ROWS )); then
    check_pass "quant.signals has ${TOTAL_ROWS} rows (expected >= ${MIN_ROWS})"
else
    check_fail "quant.signals has only ${TOTAL_ROWS} rows (expected >= ${MIN_ROWS}). Data may not be restored."
fi

# ---- Check 4: Current month partition has rows ------------------------------
CURRENT_MONTH=$(date '+%Y_%m')
PARTITION_NAME="signals_${CURRENT_MONTH}"
log_info "Check 4: Current month partition quant.${PARTITION_NAME} has rows..."

PARTITION_EXISTS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace \
    WHERE n.nspname = 'quant' AND c.relname = '${PARTITION_NAME}';\"" 2>/dev/null | tr -d '[:space:]' || echo "0")

if [[ "$PARTITION_EXISTS" == "0" ]]; then
    log_warn "Partition quant.${PARTITION_NAME} not found - partition may use different naming"
    log_warn "Checking recent rows in quant.signals directly..."
    RECENT_ROWS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
        -c \"SELECT COUNT(*) FROM quant.signals \
        WHERE generated_at >= date_trunc('month', now());\"" 2>/dev/null | tr -d '[:space:]' || echo "0")
    if [[ "$RECENT_ROWS" =~ ^[0-9]+$ ]] && (( RECENT_ROWS > 0 )); then
        check_pass "Recent month rows found in quant.signals: ${RECENT_ROWS}"
    else
        check_fail "No rows found for the current month in quant.signals"
    fi
else
    PARTITION_ROWS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
        -c \"SELECT COUNT(*) FROM quant.${PARTITION_NAME};\"" 2>/dev/null | tr -d '[:space:]' || echo "0")
    if [[ "$PARTITION_ROWS" =~ ^[0-9]+$ ]] && (( PARTITION_ROWS > 0 )); then
        check_pass "Partition quant.${PARTITION_NAME} has ${PARTITION_ROWS} rows"
    else
        check_fail "Partition quant.${PARTITION_NAME} has 0 rows - restore may be incomplete"
    fi
fi

# ---- Check 5: Replication is flowing ----------------------------------------
log_info "Check 5: Streaming replication is active..."
REPL_STATUS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT COUNT(*) FROM pg_stat_replication WHERE state = 'streaming';\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "0")

if [[ "$REPL_STATUS" =~ ^[0-9]+$ ]] && (( REPL_STATUS >= 1 )); then
    check_pass "Streaming replication is active (${REPL_STATUS} replica(s) streaming)"
else
    log_warn "No streaming replicas found. If you did a PITR restore, replication may need to be re-established."
    check_fail "Streaming replication is not active after restore"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 03 PASSED - Signal data restored and database healthy"
    exit 0
else
    log_error "Scenario 03 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
