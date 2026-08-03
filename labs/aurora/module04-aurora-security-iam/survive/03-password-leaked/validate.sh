#!/usr/bin/env bash
# Scenario 03 - Password Leaked
# validate.sh: Verifies the leaked password has been rotated and stored securely.
#
# Usage:
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/03-password-leaked/validate.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 03 - Validating: Password Rotation"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ENDPOINT MASTER_USER MASTER_PASSWORD AWS_REGION; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Export it before running this script."
    exit 1
  fi
done

LEAKED_USER="payment_service"
LEAKED_PASSWORD="Sup3rSecret99!"
SECRET_NAME="prod/payment-service/db-credentials"

CHECKS_PASSED=0
CHECKS_FAILED=0

check_pass() {
  echo "[PASS] $1"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_fail() {
  echo "[FAIL] $1"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

echo ""

# ── Check 1: Role still exists ──────────────────────────────────────────────
echo "[CHECK 1] PostgreSQL role '$LEAKED_USER' still exists"

ROLE_EXISTS=$(PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT rolname FROM pg_roles WHERE rolname = '$LEAKED_USER';" 2>/dev/null)

if [[ "$ROLE_EXISTS" == "$LEAKED_USER" ]]; then
  check_pass "Role '$LEAKED_USER' exists"
else
  check_fail "Role '$LEAKED_USER' not found - was it dropped instead of rotated?"
fi

# ── Check 2: Old (leaked) password no longer works ──────────────────────────
echo "[CHECK 2] Old (leaked) password no longer works"

OLD_PASS_RESULT=$(PGPASSWORD="$LEAKED_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$LEAKED_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT 1;" 2>&1 || true)

if echo "$OLD_PASS_RESULT" | grep -qiE "authentication failed|password authentication"; then
  check_pass "Leaked password '$LEAKED_PASSWORD' is rejected - password has been rotated"
else
  check_fail "Leaked password is STILL accepted. The password has NOT been rotated!"
fi

# ── Check 3: New credentials exist in Secrets Manager ───────────────────────
echo "[CHECK 3] New credentials stored in Secrets Manager"

SECRET_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query 'Name' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$SECRET_EXISTS" == "$SECRET_NAME" ]]; then
  check_pass "Secret '$SECRET_NAME' exists in Secrets Manager"
else
  check_fail "Secret '$SECRET_NAME' not found in Secrets Manager"
  echo "        Create it with:"
  echo "        aws secretsmanager create-secret --name '$SECRET_NAME' --secret-string '{...}'"
fi

# ── Check 4: Credentials from Secrets Manager can connect ───────────────────
echo "[CHECK 4] Credentials from Secrets Manager connect successfully"

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
      "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$LEAKED_USER sslmode=require" \
      --tuples-only --no-align \
      --command="SELECT 'connected';" 2>&1 || true)

    if echo "$NEW_PASS_RESULT" | grep -q "connected"; then
      check_pass "Secrets Manager credentials connect successfully"
    else
      check_fail "Secrets Manager credentials failed to connect: ${NEW_PASS_RESULT:0:100}"
    fi
  fi
else
  echo "        Skipping Check 4 - secret does not exist yet"
fi

# ── Check 5: New password is different from the leaked one ──────────────────
echo "[CHECK 5] New password is different from the leaked password"

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
    echo "        Could not verify new password - skipping"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "============================================"

if [[ $CHECKS_FAILED -eq 0 ]]; then
  echo "  PASS - All checks passed. Password has been rotated and stored securely."
  echo ""
  echo "  Next steps to complete the incident response:"
  echo "    1. Remove the leaked config file: rm /tmp/module04-scenario03-leaked-config.env"
  echo "    2. Update all application servers to fetch credentials from Secrets Manager"
  echo "    3. Check PostgreSQL logs for unauthorized access during the exposure window"
  echo "    4. File an incident report"
else
  echo "  FAIL - Some checks failed. Review and fix the issues above."
fi

exit $CHECKS_FAILED
