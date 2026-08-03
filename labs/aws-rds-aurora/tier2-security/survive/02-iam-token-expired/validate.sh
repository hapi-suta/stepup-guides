#!/usr/bin/env bash
# Scenario 02 - IAM Token Expired
# validate.sh: Verifies the student can generate a fresh token and connect.
#
# Usage:
#   source survive/config.sh
#   bash survive/02-iam-token-expired/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 02 - Validating: IAM Token Authentication"

check_aws_cli
check_psql
check_config_loaded
init_checks

separator

# ─── Check 1: IAM auth is enabled on the instance ──────────────────────────────
info "Check 1: IAM database authentication is enabled"

IAM_ENABLED=$(rds_iam_auth_enabled)

if [[ "$IAM_ENABLED" == "true" ]]; then
  check_pass "IAM database authentication is enabled"
else
  check_fail "IAM database authentication is disabled (got: $IAM_ENABLED)"
fi

# ─── Check 2: The PostgreSQL role exists ───────────────────────────────────────
info "Check 2: PostgreSQL role 'iam_scenario_user' exists"

ROLE_EXISTS=$(PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT rolname FROM pg_roles WHERE rolname = 'iam_scenario_user';" 2>/dev/null)

if [[ "$ROLE_EXISTS" == "iam_scenario_user" ]]; then
  check_pass "Role 'iam_scenario_user' exists in PostgreSQL"
else
  check_fail "Role 'iam_scenario_user' not found in PostgreSQL"
fi

# ─── Check 3: The role has rds_iam ─────────────────────────────────────────────
info "Check 3: Role 'iam_scenario_user' has rds_iam granted"

RDS_IAM_GRANTED=$(PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT COUNT(*) FROM pg_auth_members am
             JOIN pg_roles r ON r.oid = am.member
             JOIN pg_roles m ON m.oid = am.roleid
             WHERE r.rolname = 'iam_scenario_user'
               AND m.rolname = 'rds_iam';" 2>/dev/null)

if [[ "$RDS_IAM_GRANTED" == "1" ]]; then
  check_pass "rds_iam is granted to 'iam_scenario_user'"
else
  check_fail "rds_iam is NOT granted to 'iam_scenario_user'"
fi

# ─── Check 4: Student can generate a fresh token and connect ───────────────────
info "Check 4: Fresh IAM token can be generated and used to connect"

FRESH_TOKEN=$(aws rds generate-db-auth-token \
  --hostname "$RDS_HOST" \
  --port "$RDS_PORT" \
  --region "$AWS_REGION" \
  --username iam_scenario_user 2>/dev/null || true)

if [[ -z "$FRESH_TOKEN" ]]; then
  check_fail "Could not generate IAM auth token - check AWS CLI credentials and IAM policy"
else
  # Try to connect with the fresh token
  TOKEN_CONNECT=$(PGPASSWORD="$FRESH_TOKEN" psql \
    "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=iam_scenario_user sslmode=require" \
    --tuples-only --no-align \
    --command="SELECT 'iam_connected';" 2>&1 || true)

  if echo "$TOKEN_CONNECT" | grep -q "iam_connected"; then
    check_pass "Fresh IAM token generated and connection successful"
  else
    check_fail "Fresh IAM token generated but connection failed: ${TOKEN_CONNECT:0:120}"
  fi
fi

# ─── Check 5: Stale token is rejected (if file still exists and is > 15 min old) ─
info "Check 5: Verifying stale token handling (informational)"
STALE_TOKEN_FILE="/tmp/tier2-scenario02-stale-token.txt"
if [[ -f "$STALE_TOKEN_FILE" ]]; then
  FILE_AGE_SECONDS=$(( $(date +%s) - $(date -r "$STALE_TOKEN_FILE" +%s 2>/dev/null || echo 0) ))
  if [[ $FILE_AGE_SECONDS -gt 900 ]]; then
    STALE_RESULT=$(PGPASSWORD="$(cat $STALE_TOKEN_FILE)" psql \
      "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=iam_scenario_user sslmode=require" \
      --tuples-only --no-align \
      --command="SELECT 1;" 2>&1 || true)
    if echo "$STALE_RESULT" | grep -q "PAM authentication failed\|authentication failed"; then
      check_pass "Stale token correctly rejected (token expired after 15 minutes)"
    else
      warn "Stale token check inconclusive - connection result: ${STALE_RESULT:0:80}"
    fi
  else
    warn "Stale token file is only $FILE_AGE_SECONDS seconds old - not yet expired (needs 900s). Skipping."
  fi
else
  warn "Stale token file not found at $STALE_TOKEN_FILE - skipping stale token check."
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
print_check_summary
