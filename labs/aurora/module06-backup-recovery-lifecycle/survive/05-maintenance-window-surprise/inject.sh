#!/usr/bin/env bash
# SURVIVE 05 - inject.sh
# Simulates a surprise maintenance window during business hours.
# The student must move the window and handle pending maintenance.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 05 - Maintenance Window Surprise - Injecting Fault"

resolve_cluster_host

# Step 1: Set the maintenance window to business hours (the "mistake")
log_info "Setting maintenance window to business hours (mis-configuration)..."

aws rds modify-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --preferred-maintenance-window "mon:14:00-mon:14:30" \
    --region "$AWS_REGION" > /dev/null

log_warn "Maintenance window set to: Monday 14:00-14:30 UTC (business hours!)"

# Step 2: Record the correct window the student should restore
echo "sun:03:00-sun:03:30" > "$SURVIVE_TMP/05_correct_window.txt"

# Step 3: Record current state for validation
CURRENT_WINDOW=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION" \
    --query 'DBClusters[0].PreferredMaintenanceWindow' \
    --output text)
echo "$CURRENT_WINDOW" > "$SURVIVE_TMP/05_injected_window.txt"

log_info "Injected maintenance window: $CURRENT_WINDOW"

INCIDENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$INCIDENT_TS" > "$SURVIVE_TMP/05_incident_ts.txt"

log_warn ""
log_warn "SCENARIO DESCRIPTION FOR STUDENT:"
log_warn "===================================="
log_warn "You received this email from AWS at 10:00 AM Monday morning:"
log_warn ""
log_warn "  'AWS RDS Maintenance Notification'"
log_warn "  'Your cluster $CLUSTER_ID has a pending OS update.'"
log_warn "  'It will be applied during your maintenance window:'"
log_warn "  'Monday 14:00-14:30 UTC'"
log_warn "  'This may cause a brief outage.'"
log_warn ""
log_warn "It is now 10:15 AM Monday. You have 3 hours 45 minutes until"
log_warn "the maintenance fires during peak business hours."
log_warn ""
log_warn "Current state:"
log_warn "  - Maintenance window: mon:14:00-mon:14:30 (WRONG - business hours)"
log_warn "  - Application team is expecting normal service all day"
log_warn ""
log_warn "Student objectives:"
log_warn "  1. Move the maintenance window to a safe off-hours time"
log_warn "  2. Check for pending maintenance actions"
log_warn "  3. If there is pending maintenance, defer it to the new window"
log_warn "  4. Verify the change took effect"
log_warn "  5. Write the team notification"
