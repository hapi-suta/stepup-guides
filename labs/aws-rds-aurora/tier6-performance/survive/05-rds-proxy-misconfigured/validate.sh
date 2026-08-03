#!/usr/bin/env bash
# survive/05-rds-proxy-misconfigured/validate.sh

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "VALIDATE: RDS Proxy Misconfiguration Recovery"

if [[ -z "${PROXY_NAME:-}" ]]; then
    fail "PROXY_NAME not set"
    exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

# Check 1: Proxy targets are healthy
info "Check 1: Proxy targets are AVAILABLE"
TARGET_STATE=$(aws rds describe-db-proxy-targets \
    --db-proxy-name "$PROXY_NAME" \
    --query "Targets[0].TargetHealth.State" \
    --output text --region "$REGION" 2>/dev/null || echo "UNKNOWN")

if [[ "$TARGET_STATE" == "AVAILABLE" ]]; then
    pass "Proxy target state: AVAILABLE"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Proxy target state: $TARGET_STATE (expected AVAILABLE)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 2: Can connect through proxy
info "Check 2: Connection through proxy succeeds"
if [[ -n "$PROXY_ENDPOINT" ]]; then
    PROXY_RESULT=$(psql -h "$PROXY_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "SELECT 1" 2>/dev/null || echo "FAILED")

    if [[ "$PROXY_RESULT" == "1" ]]; then
        pass "Proxy connection: successful"
        PASS_COUNT=$(( PASS_COUNT + 1 ))
    else
        fail "Proxy connection: FAILED"
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    fi
else
    warn "PROXY_ENDPOINT not set - cannot test proxy connection directly"
fi

# Check 3: The secret contains correct username
info "Check 3: Secret contains correct database username"
SECRET_ARN=$(aws rds describe-db-proxies \
    --db-proxy-name "$PROXY_NAME" \
    --query "DBProxies[0].Auth[0].SecretArn" \
    --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$SECRET_ARN" && "$SECRET_ARN" != "None" ]]; then
    SECRET_USER=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" \
        --query SecretString --output text --region "$REGION" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('username',''))" 2>/dev/null || echo "")

    if [[ "$SECRET_USER" == "$DB_USER" ]]; then
        pass "Secret username matches DB_USER ($DB_USER)"
        PASS_COUNT=$(( PASS_COUNT + 1 ))
    else
        fail "Secret username '$SECRET_USER' does not match DB_USER '$DB_USER'"
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    fi
else
    warn "Could not retrieve secret ARN from proxy - manual check required"
fi

# Check 4: Wrong secret cleaned up
info "Check 4: Wrong credential secret deleted"
WRONG_SECRET_EXISTS=$(aws secretsmanager describe-secret \
    --secret-id "proxy-wrong-credentials-${PROXY_NAME}" \
    --region "$REGION" 2>/dev/null | grep -c '"ARN"' || echo "0")

if [[ "$WRONG_SECRET_EXISTS" -eq 0 ]]; then
    pass "Wrong credential secret has been cleaned up"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    warn "Wrong credential secret still exists - clean it up: proxy-wrong-credentials-${PROXY_NAME}"
fi

section "VALIDATION SUMMARY"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    pass "SCENARIO RESOLVED - RDS Proxy is operational with correct credentials"
    exit 0
else
    fail "SCENARIO NOT FULLY RESOLVED - $FAIL_COUNT checks still failing"
    exit 1
fi
