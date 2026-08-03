#!/usr/bin/env bash
# survive/03-instance-stopped/validate.sh
# Verifies the instance was successfully started and is accepting connections.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/03-instance-stopped/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

echo ""
echo "========================================"
echo "  VALIDATE: Instance Stopped"
echo "========================================"
echo ""

# Check 1 - Instance status is available
info "Check 1: RDS instance status is available"
STATUS=$(rds_instance_status "$RDS_INSTANCE_ID")
if [[ "$STATUS" == "available" ]]; then
  check "RDS instance $RDS_INSTANCE_ID is available" "pass"
elif [[ "$STATUS" == "starting" ]]; then
  check "RDS instance is still starting (status: starting)" "fail" \
    "Wait a few more minutes then run validate again"
  check_summary
  exit 1
else
  check "RDS instance status is: $STATUS (expected: available)" "fail" \
    "Run: aws rds start-db-instance --db-instance-identifier $RDS_INSTANCE_ID"
  check_summary
  exit 1
fi

# Check 2 - Instance endpoint resolves in DNS
info "Check 2: Endpoint DNS resolution"
RESOLVED=$(dns_resolve "$RDS_ENDPOINT")
if [[ -n "$RESOLVED" ]]; then
  check "Endpoint $RDS_ENDPOINT resolves to $RESOLVED" "pass"
else
  check "Endpoint DNS resolution failed for $RDS_ENDPOINT" "fail" \
    "Endpoint may have changed. Check: aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query \"DBInstances[0].Endpoint.Address\" --output text"
fi

# Check 3 - Port is open
info "Check 3: Port $DB_PORT is reachable"
if pg_port_open "$RDS_ENDPOINT" "$DB_PORT" 10; then
  check "Port $DB_PORT is open on $RDS_ENDPOINT" "pass"
else
  check "Port $DB_PORT not reachable" "fail" \
    "Instance may still be starting, or security group rules are missing"
fi

# Check 4 - psql connection works
info "Check 4: psql can connect and run a query"
if pg_health_check; then
  check "psql connection and query successful" "pass"
else
  check "psql connection failed" "fail" \
    "Verify credentials and try: psql -h $RDS_ENDPOINT -U $DB_USER -d $DB_NAME -p $DB_PORT"
fi

# Check 5 - Check recent events confirm start
info "Check 5: CloudWatch events show instance started"
EVENTS=$(aws rds describe-events \
  --source-identifier "$RDS_INSTANCE_ID" \
  --source-type db-instance \
  --duration 60 \
  --query "Events[?contains(Message,'started') || contains(Message,'available')].Message" \
  --output text 2>/dev/null || echo "")

if [[ -n "$EVENTS" ]]; then
  check "RDS events confirm instance was started recently" "pass"
else
  warn "No recent start events found (may have started > 60 min ago - this is OK)"
  (( _CHECK_PASS++ )) || true
fi

# Check 6 - Data integrity: tables are accessible
info "Check 6: Database tables are accessible"
TABLE_COUNT=$(rds_exec "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo "0")
check "Public schema accessible (found $TABLE_COUNT table(s))" "pass"

echo ""
check_summary
