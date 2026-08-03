#!/usr/bin/env bash
# survive/05-rds-proxy-misconfigured/inject.sh
# Injects: RDS Proxy misconfigured - wrong secret, connections failing
# Difficulty: Expert
# NOTE: This scenario requires an existing RDS Proxy

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "INJECT: RDS Proxy Misconfigured"

if [[ -z "${PROXY_NAME:-}" ]]; then
    fail "PROXY_NAME environment variable not set"
    echo "Set: export PROXY_NAME=your-proxy-name"
    exit 1
fi

log "Proxy name: $PROXY_NAME"

# Get current secret ARN
CURRENT_SECRET=$(aws rds describe-db-proxies \
    --db-proxy-name "$PROXY_NAME" \
    --query "DBProxies[0].Auth[0].SecretArn" \
    --output text \
    --region "$REGION")

log "Current secret ARN: $CURRENT_SECRET"
echo "$CURRENT_SECRET" > "${SURVIVE_LOG_DIR}/05-original-secret.txt"

# Create a fake/wrong secret to break the proxy
WRONG_SECRET_ARN=$(aws secretsmanager create-secret \
    --name "proxy-wrong-credentials-${PROXY_NAME}" \
    --secret-string '{"username":"wronguser","password":"wrongpassword"}' \
    --region "$REGION" \
    --query ARN --output text 2>/dev/null || \
    aws secretsmanager describe-secret \
        --secret-id "proxy-wrong-credentials-${PROXY_NAME}" \
        --query ARN --output text --region "$REGION")

log "Wrong secret ARN: $WRONG_SECRET_ARN"
echo "$WRONG_SECRET_ARN" > "${SURVIVE_LOG_DIR}/05-wrong-secret.txt"

# Get the target group
TARGET_GROUP=$(aws rds describe-db-proxy-target-groups \
    --db-proxy-name "$PROXY_NAME" \
    --query "TargetGroups[0].TargetGroupName" \
    --output text --region "$REGION")

log "Injecting wrong secret into proxy auth configuration..."

# Modify the proxy to use the wrong secret
aws rds modify-db-proxy \
    --db-proxy-name "$PROXY_NAME" \
    --auth "[{\"AuthScheme\":\"SECRETS\",\"SecretArn\":\"${WRONG_SECRET_ARN}\",\"IAMAuth\":\"DISABLED\"}]" \
    --region "$REGION"

echo "$(date)" > "${SURVIVE_LOG_DIR}/05-inject-time.txt"

log "Proxy modified to use wrong credentials"
log "Waiting 30 seconds for proxy to attempt reconnection with wrong credentials..."
sleep 30

echo ""
echo "=========================================="
echo "SCENARIO INJECTED: RDS Proxy Misconfigured"
echo "=========================================="
echo ""
echo "What is happening:"
echo "  - The RDS Proxy is configured with wrong database credentials"
echo "  - The proxy cannot authenticate to the database"
echo "  - All application connections through the proxy will fail"
echo "  - The proxy endpoint is up but returns authentication errors"
echo ""
echo "Symptoms:"
echo "  - Applications get 'password authentication failed' errors"
echo "  - CloudWatch: DatabaseConnectionsSetupFailed metric increasing"
echo "  - Proxy health status may show UNAVAILABLE"
echo ""
echo "RECOVERY HINT: The original secret ARN is stored in:"
echo "  ${SURVIVE_LOG_DIR}/05-original-secret.txt"
echo ""
echo "DO NOT read that file until you have diagnosed the problem yourself."
