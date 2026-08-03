#!/usr/bin/env bash
# survive/01-security-group-lockout/inject.sh
# Removes all inbound rules from the RDS security group.
# This simulates someone accidentally wiping firewall rules.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/01-security-group-lockout/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

BACKUP_FILE="/tmp/suta-sg-backup-01.json"

echo ""
echo "========================================"
echo "  INJECT: Security Group Lockout"
echo "========================================"
echo ""

# Step 1 - Confirm the instance is available before breaking things
info "Confirming RDS instance is available..."
if ! rds_is_available "$RDS_INSTANCE_ID"; then
  fail "RDS instance $RDS_INSTANCE_ID is not available. Aborting inject."
  exit 1
fi
success "Instance $RDS_INSTANCE_ID is available"

# Step 2 - Confirm we can currently connect (pre-check)
info "Testing connectivity before injection..."
if pg_port_open "$RDS_ENDPOINT" "$DB_PORT" 5; then
  success "Port $DB_PORT is open before inject"
else
  warn "Port $DB_PORT was already closed. Proceeding anyway."
fi

# Step 3 - Backup current security group rules
info "Backing up security group rules for $RDS_SG_ID..."
save_sg_rules "$RDS_SG_ID" "$BACKUP_FILE"

# Step 4 - Remove all inbound rules
info "Removing all inbound rules from security group $RDS_SG_ID..."
revoke_all_sg_rules "$RDS_SG_ID"

# Step 5 - Verify rules are gone
RULE_COUNT=$(rds_count_sg_rules "$RDS_SG_ID")
if [[ "$RULE_COUNT" -eq 0 ]]; then
  success "All inbound rules removed. Security group $RDS_SG_ID now has 0 rules."
else
  warn "Security group still has $RULE_COUNT rules. Manual inspection needed."
fi

echo ""
echo "========================================"
echo "  INJECTION COMPLETE"
echo "========================================"
echo ""
echo "  Scenario: Security Group Lockout"
echo "  Security group $RDS_SG_ID has no inbound rules."
echo "  All connections to port $DB_PORT are now blocked."
echo ""
echo "  Backup saved to: $BACKUP_FILE"
echo "  (Do not look at this during the exercise!)"
echo ""
echo "  Now open: survive/01-security-group-lockout/runbook.md"
echo "========================================"
