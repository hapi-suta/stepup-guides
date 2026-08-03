#!/usr/bin/env bash
# Scenario 04 - Overprivileged Role
# validate.sh: Verifies that report_user has exactly the right privileges.
#
# Usage:
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/04-overprivileged-role/validate.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 04 - Validating: Privilege Fix"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ENDPOINT MASTER_USER MASTER_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Export it before running this script."
    exit 1
  fi
done

ROLE="report_user"
DB="financedb"
SCHEMA="finance"
ROLE_PASS="ReportPass1!"

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

psql_financedb() {
  PGPASSWORD="$MASTER_PASSWORD" psql \
    "host=$CLUSTER_ENDPOINT port=5432 dbname=$DB user=$MASTER_USER sslmode=require" \
    --tuples-only --no-align \
    --command="$1" 2>/dev/null
}

psql_as_report_user() {
  PGPASSWORD="$ROLE_PASS" psql \
    "host=$CLUSTER_ENDPOINT port=5432 dbname=$DB user=$ROLE sslmode=require" \
    --tuples-only --no-align \
    --command="$1" 2>&1 || true
}

echo ""

# ── Check 1: Role still exists ──────────────────────────────────────────────
echo "[CHECK 1] Role '$ROLE' exists"

ROLE_EXISTS=$(psql_financedb "SELECT rolname FROM pg_roles WHERE rolname = '$ROLE';")
if [[ "$ROLE_EXISTS" == "$ROLE" ]]; then
  check_pass "Role '$ROLE' exists"
else
  check_fail "Role '$ROLE' not found"
fi

# ── Check 2: Can SELECT from accounts ───────────────────────────────────────
echo "[CHECK 2] $ROLE can SELECT from $SCHEMA.accounts"

ACCOUNTS_SELECT=$(psql_as_report_user "SELECT COUNT(*) FROM $SCHEMA.accounts;")
if echo "$ACCOUNTS_SELECT" | grep -qE '^[0-9]+$'; then
  check_pass "$ROLE can SELECT from $SCHEMA.accounts"
else
  check_fail "$ROLE cannot SELECT from $SCHEMA.accounts: ${ACCOUNTS_SELECT:0:80}"
fi

# ── Check 3: Can SELECT from transactions ───────────────────────────────────
echo "[CHECK 3] $ROLE can SELECT from $SCHEMA.transactions"

TXN_SELECT=$(psql_as_report_user "SELECT COUNT(*) FROM $SCHEMA.transactions;")
if echo "$TXN_SELECT" | grep -qE '^[0-9]+$'; then
  check_pass "$ROLE can SELECT from $SCHEMA.transactions"
else
  check_fail "$ROLE cannot SELECT from $SCHEMA.transactions: ${TXN_SELECT:0:80}"
fi

# ── Check 4: Cannot SELECT from audit_trail ─────────────────────────────────
echo "[CHECK 4] $ROLE CANNOT SELECT from $SCHEMA.audit_trail"

AUDIT_SELECT=$(psql_as_report_user "SELECT COUNT(*) FROM $SCHEMA.audit_trail;")
if echo "$AUDIT_SELECT" | grep -qi "permission denied"; then
  check_pass "$ROLE correctly denied from $SCHEMA.audit_trail"
else
  check_fail "$ROLE can still SELECT from $SCHEMA.audit_trail (should be denied)"
fi

# ── Check 5: Cannot SELECT from internal_notes ─────────────────────────────
echo "[CHECK 5] $ROLE CANNOT SELECT from $SCHEMA.internal_notes"

NOTES_SELECT=$(psql_as_report_user "SELECT COUNT(*) FROM $SCHEMA.internal_notes;")
if echo "$NOTES_SELECT" | grep -qi "permission denied"; then
  check_pass "$ROLE correctly denied from $SCHEMA.internal_notes"
else
  check_fail "$ROLE can still SELECT from $SCHEMA.internal_notes (should be denied)"
fi

# ── Check 6: Cannot DELETE from accounts ────────────────────────────────────
echo "[CHECK 6] $ROLE CANNOT DELETE from $SCHEMA.accounts"

DELETE_RESULT=$(psql_as_report_user "DELETE FROM $SCHEMA.accounts WHERE id = -999;")
if echo "$DELETE_RESULT" | grep -qi "permission denied"; then
  check_pass "$ROLE correctly denied DELETE on $SCHEMA.accounts"
else
  check_fail "$ROLE can still DELETE from $SCHEMA.accounts (should be denied)"
fi

# ── Check 7: Cannot INSERT into transactions ───────────────────────────────
echo "[CHECK 7] $ROLE CANNOT INSERT into $SCHEMA.transactions"

INSERT_RESULT=$(psql_as_report_user "INSERT INTO $SCHEMA.transactions (account_id, amount, type) VALUES (-1, 0, 'test');")
if echo "$INSERT_RESULT" | grep -qi "permission denied"; then
  check_pass "$ROLE correctly denied INSERT on $SCHEMA.transactions"
else
  check_fail "$ROLE can still INSERT into $SCHEMA.transactions (should be denied)"
fi

# ── Check 8: Cannot CREATE tables in schema ─────────────────────────────────
echo "[CHECK 8] $ROLE CANNOT CREATE tables in $SCHEMA"

CREATE_RESULT=$(psql_as_report_user "CREATE TABLE $SCHEMA.hacked_table (id INT);")
if echo "$CREATE_RESULT" | grep -qi "permission denied"; then
  check_pass "$ROLE correctly denied CREATE in schema $SCHEMA"
else
  # Clean up if it somehow succeeded
  psql_financedb "DROP TABLE IF EXISTS $SCHEMA.hacked_table;" > /dev/null 2>&1 || true
  check_fail "$ROLE was able to CREATE a table in $SCHEMA (should be denied)"
fi

# ── Check 9: Privilege count matches expectation ────────────────────────────
echo "[CHECK 9] Total table-level privilege count for $ROLE"

PRIV_COUNT=$(psql_financedb "
  SELECT COUNT(*)
  FROM information_schema.role_table_grants
  WHERE grantee = '$ROLE'
    AND table_schema = '$SCHEMA';")

# Should be exactly 2 (SELECT on accounts, SELECT on transactions)
if [[ "$PRIV_COUNT" == "2" ]]; then
  check_pass "Exactly 2 table privileges granted to $ROLE (SELECT on accounts, SELECT on transactions)"
else
  check_fail "Expected 2 privileges, found $PRIV_COUNT. Run the diagnostic query:"
  echo "        SELECT grantee, table_name, privilege_type"
  echo "        FROM information_schema.role_table_grants"
  echo "        WHERE grantee = '$ROLE';"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "============================================"

if [[ $CHECKS_FAILED -eq 0 ]]; then
  echo "  PASS - All checks passed. Role privileges are correctly configured."
else
  echo "  FAIL - Some checks failed. Review and fix the issues above."
fi

exit $CHECKS_FAILED
