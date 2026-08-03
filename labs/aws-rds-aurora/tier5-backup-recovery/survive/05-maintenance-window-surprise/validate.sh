#!/usr/bin/env bash
# SURVIVE 05 - validate.sh
# Verifies the maintenance window has been moved to off-hours.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 05 - Validating Maintenance Window Correction"

resolve_db_host

PASS=0
FAIL=0

# ─── Check 1: Maintenance window is not during business hours ─────────────────
CURRENT_WINDOW=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].PreferredMaintenanceWindow' \
    --output text)

log_info "Current maintenance window: $CURRENT_WINDOW"

# Business hours = weekday (mon-fri) between 08:00 and 20:00 UTC
# Check if window starts with a weekday
WINDOW_DAY=$(echo "$CURRENT_WINDOW" | cut -d: -f1)
WINDOW_HOUR=$(echo "$CURRENT_WINDOW" | cut -d: -f2)

BUSINESS_DAYS=("mon" "tue" "wed" "thu" "fri")
IS_BUSINESS_DAY=false
for day in "${BUSINESS_DAYS[@]}"; do
    if [[ "$WINDOW_DAY" == "$day" ]]; then
        IS_BUSINESS_DAY=true
        break
    fi
done

IS_BUSINESS_HOURS=false
if [[ "$IS_BUSINESS_DAY" == "true" ]] && \
   [[ "$WINDOW_HOUR" -ge 8 ]] && [[ "$WINDOW_HOUR" -lt 20 ]]; then
    IS_BUSINESS_HOURS=true
fi

if [[ "$IS_BUSINESS_HOURS" == "false" ]]; then
    log_ok "Maintenance window is outside business hours: $CURRENT_WINDOW"
    (( PASS++ ))
else
    log_fail "Maintenance window is still during business hours: $CURRENT_WINDOW"
    log_fail "Move it to a weekend or late-night window (e.g., sun:03:00-sun:03:30)"
    (( FAIL++ ))
fi

# ─── Check 2: Window is not the injected business-hours window ────────────────
INJECTED_WINDOW=$(cat "$SURVIVE_TMP/05_injected_window.txt" 2>/dev/null || echo "mon:14:00-mon:14:30")
if [[ "$CURRENT_WINDOW" != "$INJECTED_WINDOW" ]]; then
    log_ok "Maintenance window has been changed from the injected value"
    (( PASS++ ))
else
    log_fail "Maintenance window is still the injected value: $INJECTED_WINDOW"
    (( FAIL++ ))
fi

# ─── Check 3: Instance is available (no accidental modifications) ─────────────
PRIMARY_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)
if check_pass "Primary instance is available" "available" "$PRIMARY_STATUS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# ─── Check 4: Backup window is not overlapping maintenance window ─────────────
BACKUP_WINDOW=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].PreferredBackupWindow' \
    --output text)
log_info "Backup window: $BACKUP_WINDOW"
log_info "Maintenance window: $CURRENT_WINDOW"
# Simple check: they should not start with the same day:hour
BACKUP_START=$(echo "$BACKUP_WINDOW" | cut -d- -f1)
MAINT_HOUR_START=$(echo "$CURRENT_WINDOW" | cut -d- -f1 | cut -d: -f2,3)
if [[ "$BACKUP_START" != "$MAINT_HOUR_START" ]]; then
    log_ok "Backup and maintenance windows do not obviously overlap"
    (( PASS++ ))
else
    log_warn "Backup and maintenance windows may overlap - verify manually"
fi

# ─── Check 5: No pending maintenance for business hours ──────────────────────
PENDING=$(aws rds describe-pending-maintenance-actions \
    --region "$AWS_REGION" \
    --query "length(PendingMaintenanceActions)" \
    --output text 2>/dev/null || echo "0")
if [[ "$PENDING" -eq 0 ]]; then
    log_ok "No pending maintenance actions queued"
    (( PASS++ ))
else
    log_warn "$PENDING pending maintenance action(s) exist"
    log_warn "Verify they will not fire during business hours given the new window"
    aws rds describe-pending-maintenance-actions \
        --region "$AWS_REGION" \
        --query 'PendingMaintenanceActions[*].{Resource:ResourceIdentifier,Actions:PendingMaintenanceActionDetails[*].{Action:Action,AutoApplied:AutoAppliedAfterDate}}' \
        --output json
fi

# ─── Final Score ──────────────────────────────────────────────────────────────
echo ""
log_section "RESULTS"
log_info "Checks passed: $PASS"
log_info "Checks failed: $FAIL"

if (( FAIL == 0 )); then
    log_ok "SURVIVE 05 COMPLETE - All checks passed."
else
    log_fail "SURVIVE 05 INCOMPLETE - $FAIL check(s) failed."
    exit 1
fi
