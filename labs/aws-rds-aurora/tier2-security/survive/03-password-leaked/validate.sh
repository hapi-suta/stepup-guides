#!/usr/bin/env bash
# Scenario 03 - Password Leaked
# validate.sh: Verifies the leaked password has been rotated.
#
# Usage:
#   source survive/config.sh
#   bash survive/03-password-leaked/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 03 - Validating: Password Rotation After Leak"

check_aws_cli
check_psql
check_config_loaded
init_checks

LEAKED_USER="payment_service"
LEAKED_PASSWORD="Sup3rSecret99!"
SECRET_NAME="prod/payment-service/db-credentials"

separator

# ─── Check 1: Role still exists ────────────────────────────────────────────────
info "Check 1: PostgreSQL role '$LEAKED_USER' still exists"

ROLE_EXISTS=$(PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT rolname FROM pg_roles WHERE rolname = '$LEAKED_USER';" 2>/dev/null)

if [[ "$ROLE_EXISTS" == "$LEAKED_USER" ]]; then
  check_pass "Role '$LEAKED_USER' exists"
else
  check_fail "Role '$LEAKED_USER' not found - was it dropped instead of rotated?"
fi

# ─── Check 2: Old (leaked) password no longer works ────────────────────────────
info "Check 2: Old (leaked) password no longer works"

OLD_PASS_RESULT=$(PGPASSWORD="$LEAKED_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$LEAKED_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT 1;" 2>&1 || true)

if echo "$OLD_PASS_RESULT" | grep -qiE "authentication failed|password authentication"; then
  check_pass "Leaked password '$LEAKED_PASSWORD' is rejected - password has been rotated"
else
  check_fail "Leaked password is STILL accepted. The password has NOT been rotated!"
fi

# ─── Check 3: New credentials exist in Secrets Manager ─────────────────────────
info "Check 3: New credentials stored in Secrets Manager"

SECRET_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query 'Name' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$SECRET_EXISTS" == "$SECRET_NAME" ]]; then
  check_pass "Secret '$SECRET_NAME' exists in Secrets Manager"
else
  check_fail "Secret '$SECRET_NAME' not found in Secrets Manager"
  warn "Create it with:"
  warn "  aws secretsmanager create-secret --name '$SECRET_NAME' --secret-string '{...}'"
fi

# ─── Check 4: Credentials from Secrets Manager can connect ─────────────────────
info "Check 4: Credentials from Secrets Manager connect successfully"

if [[ "$SECRET_EXISTS" == "$SECRET_NAME" ]]; then
  SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query 'SecretString' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "{}")

  NEW_PASS=$(echo "$SECRET_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('password',''))" 2>/dev/null || echo "")

  if [[ -z "$NEW_PASS" ]]; then
    check_fail "Could not parse password from secret JSON"
  else
    NEW_PASS_RESULT=$(PGPASSWORD="$NEW_PASS" psql \
      "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$LEAKED_USER sslmode=require" \
      --tuples-only --no-align \
      --command="SELECT 'connected';" 2>&1 || true)

    if echo "$NEW_PASS_RESULT" | grep -q "connected"; then
      check_pass "Secrets Manager credentials connect successfully"
    else
      check_fail "Secrets Manager credentials failed to connect: ${NEW_PASS_RESULT:0:100}"
    fi
  fi
else
  warn "Skipping Check 4 - secret does not exist yet"
fi

# ─── Check 5: New password is not the same as the leaked one ───────────────────
info "Check 5: New password is different from the leaked password"

if [[ "$SECRET_EXISTS" == "$SECRET_NAME" ]]; then
  STORED_PASS=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query 'SecretString' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('password',''))" 2>/dev/null || echo "")

  if [[ "$STORED_PASS" != "$LEAKED_PASSWORD" ]] && [[ -n "$STORED_PASS" ]]; then
    check_pass "New password is different from the leaked password"
  elif [[ "$STORED_PASS" == "$LEAKED_PASSWORD" ]]; then
    check_fail "Secrets Manager contains the SAME leaked password. Rotate to a new one!"
  else
    warn "Could not verify new password - skipping"
  fi
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
print_check_summary

if [[ $CHECKS_FAILED -eq 0 ]]; then
  echo ""
  info "Next steps to complete the incident response:"
  info "  1. Remove the leaked config file: rm /tmp/tier2-scenario03-leaked-config.env"
  info "  2. Update all application servers to fetch credentials from Secrets Manager"
  info "  3. Check PostgreSQL logs for unauthorized access during the exposure window"
  info "  4. File an incident report"
fi
