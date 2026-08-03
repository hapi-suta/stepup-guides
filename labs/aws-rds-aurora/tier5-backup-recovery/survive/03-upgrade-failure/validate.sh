#!/usr/bin/env bash
# SURVIVE 03 - validate.sh
# Verifies the upgrade rollback was successful.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 03 - Validating Upgrade Rollback"

resolve_db_host

PASS=0
FAIL=0

# ─── Check 1: DB version is 15.x (rolled back) ───────────────────────────────
VERSION=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].EngineVersion' \
    --output text 2>/dev/null)
if echo "$VERSION" | grep -q "^15\."; then
    log_ok "Engine version is PostgreSQL 15.x: $VERSION"
    (( PASS++ ))
else
    log_fail "Engine version is $VERSION - expected PostgreSQL 15.x (rollback may not have completed)"
    (( FAIL++ ))
fi

# ─── Check 2: app_users table has expected rows ───────────────────────────────
EXPECTED_USERS=$(cat "$SURVIVE_TMP/03_user_rowcount.txt" 2>/dev/null || echo "100")
ACTUAL_USERS=$(run_sql "SELECT COUNT(*) FROM app_users;" 2>/dev/null || echo "0")
if check_pass "app_users row count" "$EXPECTED_USERS" "$ACTUAL_USERS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# ─── Check 3: app_config table has expected rows ──────────────────────────────
EXPECTED_CONFIG=$(cat "$SURVIVE_TMP/03_config_count.txt" 2>/dev/null || echo "4")
ACTUAL_CONFIG=$(run_sql "SELECT COUNT(*) FROM app_config;" 2>/dev/null || echo "0")
if check_pass "app_config row count" "$EXPECTED_CONFIG" "$ACTUAL_CONFIG"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# ─── Check 4: uuid-ossp extension works ──────────────────────────────────────
UUID_RESULT=$(run_sql "SELECT uuid_generate_v4();" 2>/dev/null || echo "FAILED")
if [[ "$UUID_RESULT" != "FAILED" && -n "$UUID_RESULT" ]]; then
    log_ok "uuid_generate_v4() works: $UUID_RESULT"
    (( PASS++ ))
else
    log_fail "uuid_generate_v4() is not working - extension may not be installed"
    (( FAIL++ ))
fi

# ─── Check 5: Backup retention is enabled ─────────────────────────────────────
RETENTION=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].BackupRetentionPeriod' \
    --output text)
if [[ "$RETENTION" -gt 0 ]]; then
    log_ok "Backup retention is enabled: $RETENTION days"
    (( PASS++ ))
else
    log_fail "Backup retention is 0 - backups must be re-enabled after rollback"
    (( FAIL++ ))
fi

# ─── Check 6: No orphaned instances ──────────────────────────────────────────
ORPHANS=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier,'survive03') && DBInstanceStatus=='available'].DBInstanceIdentifier" \
    --output text 2>/dev/null || echo "")
if [[ -z "$ORPHANS" ]]; then
    log_ok "No orphaned survive03 instances running"
    (( PASS++ ))
else
    log_warn "Orphaned instances still running: $ORPHANS (delete when confirmed stable)"
fi

# ─── Final Score ──────────────────────────────────────────────────────────────
echo ""
log_section "RESULTS"
log_info "Checks passed: $PASS"
log_info "Checks failed: $FAIL"

if (( FAIL == 0 )); then
    log_ok "SURVIVE 03 COMPLETE - All checks passed."
else
    log_fail "SURVIVE 03 INCOMPLETE - $FAIL check(s) failed."
    exit 1
fi
