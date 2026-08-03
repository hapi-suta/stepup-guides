#!/usr/bin/env bash
# survive/01-security-group-lockout/validate.sh
# Verifies that connectivity to the RDS instance has been restored
# after the security group lockout scenario.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/01-security-group-lockout/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

echo ""
echo "========================================"
echo "  VALIDATE: Security Group Lockout"
echo "========================================"
echo ""

# Check 1 - Instance is available
info "Check 1: RDS instance status"
STATUS=$(rds_instance_status "$RDS_INSTANCE_ID")
if [[ "$STATUS" == "available" ]]; then
  check "RDS instance $RDS_INSTANCE_ID is available" "pass"
else
  check "RDS instance $RDS_INSTANCE_ID status: $STATUS" "fail" "Expected: available"
fi

# Check 2 - Security group has at least one rule on port 5432
info "Check 2: Security group has at least one inbound rule on port 5432"
RULE_COUNT=$(rds_count_sg_rules "$RDS_SG_ID")
if [[ "$RULE_COUNT" -gt 0 ]]; then
  check "Security group $RDS_SG_ID has $RULE_COUNT inbound rule(s) on port 5432" "pass"
else
  check "Security group $RDS_SG_ID has no inbound rules" "fail" \
    "Run: aws ec2 authorize-security-group-ingress --group-id $RDS_SG_ID --protocol tcp --port 5432 --cidr YOUR_IP/32"
fi

# Check 3 - Port 5432 is reachable
info "Check 3: Port $DB_PORT is reachable on $RDS_ENDPOINT"
if pg_port_open "$RDS_ENDPOINT" "$DB_PORT" 10; then
  check "Port $DB_PORT is open on $RDS_ENDPOINT" "pass"
else
  check "Port $DB_PORT is NOT reachable on $RDS_ENDPOINT" "fail" \
    "Security group rule may be pointing to wrong IP or not saved yet"
fi

# Check 4 - psql can connect and run a query
info "Check 4: psql can authenticate and execute a query"
if pg_health_check; then
  check "psql connection and query successful" "pass"
else
  check "psql connection failed" "fail" \
    "Verify: psql -h $RDS_ENDPOINT -U $DB_USER -d $DB_NAME -p $DB_PORT"
fi

# Check 5 - The instance is the writer (not in recovery)
info "Check 5: Confirming instance is the primary (writer)"
IS_REPLICA=$(rds_exec "SELECT pg_is_in_recovery()" 2>/dev/null || echo "error")
if [[ "$IS_REPLICA" == "f" ]]; then
  check "Instance is primary (pg_is_in_recovery = false)" "pass"
elif [[ "$IS_REPLICA" == "t" ]]; then
  check "Instance is a replica (pg_is_in_recovery = true)" "fail" \
    "Connected to a read replica. Check your RDS_ENDPOINT variable."
else
  check "Could not determine instance role" "fail" \
    "psql query failed: $IS_REPLICA"
fi

echo ""
check_summary
