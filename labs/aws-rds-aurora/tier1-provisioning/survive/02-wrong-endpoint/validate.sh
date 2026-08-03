#!/usr/bin/env bash
# survive/02-wrong-endpoint/validate.sh
# Verifies the config file has the correct endpoint and connectivity works.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/02-wrong-endpoint/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

APP_CONFIG="/tmp/suta-app-config.env"

echo ""
echo "========================================"
echo "  VALIDATE: Wrong Endpoint"
echo "========================================"
echo ""

# Check 1 - Config file exists
info "Check 1: Application config file exists"
if [[ -f "$APP_CONFIG" ]]; then
  check "Config file $APP_CONFIG exists" "pass"
else
  check "Config file $APP_CONFIG not found" "fail" \
    "Run inject.sh first if this is your first time with this scenario"
  check_summary
  exit 1
fi

# Check 2 - Config has a DB_HOST value
info "Check 2: Config file has DB_HOST"
CONFIG_HOST=$(grep "^DB_HOST=" "$APP_CONFIG" | cut -d= -f2)
if [[ -n "$CONFIG_HOST" ]]; then
  check "DB_HOST is set in config: $CONFIG_HOST" "pass"
else
  check "DB_HOST is missing from config" "fail" \
    "Edit $APP_CONFIG and add: DB_HOST=<your-rds-endpoint>"
fi

# Check 3 - The configured host resolves in DNS
info "Check 3: Configured host resolves in DNS"
if [[ -n "$CONFIG_HOST" ]]; then
  RESOLVED_IP=$(dns_resolve "$CONFIG_HOST")
  if [[ -n "$RESOLVED_IP" ]]; then
    check "DNS resolved $CONFIG_HOST -> $RESOLVED_IP" "pass"
  else
    check "DNS could not resolve $CONFIG_HOST" "fail" \
      "The endpoint is still wrong. Find the correct endpoint: aws rds describe-db-instances --query \"DBInstances[*].Endpoint.Address\" --output text"
  fi
fi

# Check 4 - The configured host matches the actual RDS endpoint
info "Check 4: Config endpoint matches actual RDS endpoint"
ACTUAL_ENDPOINT=$(rds_get_endpoint "$RDS_INSTANCE_ID")
if [[ "$CONFIG_HOST" == "$ACTUAL_ENDPOINT" ]]; then
  check "Config endpoint matches RDS endpoint" "pass"
else
  check "Config endpoint does NOT match RDS endpoint" "fail" \
    "Config has: $CONFIG_HOST | Correct endpoint: $ACTUAL_ENDPOINT"
fi

# Check 5 - Port is reachable at configured host
info "Check 5: Port $DB_PORT reachable at configured host"
if [[ -n "$CONFIG_HOST" ]] && pg_port_open "$CONFIG_HOST" "$DB_PORT" 10; then
  check "Port $DB_PORT is open at $CONFIG_HOST" "pass"
else
  check "Port $DB_PORT not reachable at $CONFIG_HOST" "fail" \
    "Check endpoint and security group rules"
fi

# Check 6 - psql can connect using the config file values
info "Check 6: psql can connect using values from config file"
if [[ -n "$CONFIG_HOST" ]]; then
  QUERY_RESULT=$(PGPASSWORD="$DB_PASSWORD" psql \
    -h "$CONFIG_HOST" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT 'connected'" 2>/dev/null || echo "failed")

  if [[ "$QUERY_RESULT" == "connected" ]]; then
    check "psql connected successfully using config file values" "pass"
  else
    check "psql connection failed using config file values" "fail" \
      "Check credentials and endpoint"
  fi
fi

# Check 7 - RDS instance is available
info "Check 7: RDS instance status"
STATUS=$(rds_instance_status "$RDS_INSTANCE_ID")
if [[ "$STATUS" == "available" ]]; then
  check "RDS instance $RDS_INSTANCE_ID is available" "pass"
else
  check "RDS instance status: $STATUS" "fail"
fi

echo ""
check_summary
