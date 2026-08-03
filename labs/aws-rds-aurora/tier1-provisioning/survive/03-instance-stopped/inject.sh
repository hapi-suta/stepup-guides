#!/usr/bin/env bash
# survive/03-instance-stopped/inject.sh
# Stops the RDS instance to simulate an instance going down.
# This could happen due to scheduled stop, accidental stop, or cost-saving automation.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/03-instance-stopped/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

echo ""
echo "========================================"
echo "  INJECT: Instance Stopped"
echo "========================================"
echo ""

# Step 1 - Confirm instance is available
info "Confirming RDS instance is currently available..."
STATUS=$(rds_instance_status "$RDS_INSTANCE_ID")
if [[ "$STATUS" != "available" ]]; then
  fail "Instance $RDS_INSTANCE_ID is not available (status: $STATUS). Cannot inject."
  exit 1
fi
success "Instance is available. Proceeding with inject."

# Step 2 - Verify we can connect before stopping
info "Verifying connectivity before stopping instance..."
if pg_port_open "$RDS_ENDPOINT" "$DB_PORT" 5; then
  success "Port $DB_PORT is open (pre-inject check passed)"
else
  warn "Port $DB_PORT was already unreachable. Stopping anyway."
fi

# Step 3 - Stop the instance
info "Stopping RDS instance $RDS_INSTANCE_ID..."
aws rds stop-db-instance \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  > /dev/null

# Step 4 - Confirm it is stopping
sleep 5
STATUS=$(rds_instance_status "$RDS_INSTANCE_ID")
if [[ "$STATUS" == "stopping" || "$STATUS" == "stopped" ]]; then
  success "Instance is now: $STATUS"
else
  warn "Unexpected status after stop command: $STATUS"
fi

echo ""
echo "========================================"
echo "  INJECTION COMPLETE"
echo "========================================"
echo ""
echo "  Scenario: Instance Stopped"
echo "  RDS instance $RDS_INSTANCE_ID is stopping/stopped."
echo "  Current status: $STATUS"
echo ""
echo "  IMPORTANT: It takes 3-5 minutes to fully stop."
echo "  Wait until status is 'stopped' before starting the exercise."
echo ""
echo "  Check status: aws rds describe-db-instances \\"
echo "    --db-instance-identifier $RDS_INSTANCE_ID \\"
echo "    --query \"DBInstances[0].DBInstanceStatus\" \\"
echo "    --output text"
echo ""
echo "  Now open: survive/03-instance-stopped/runbook.md"
echo "========================================"
