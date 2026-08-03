#!/usr/bin/env bash
# Scenario 01 - SSL Not Enforced
# inject.sh: Disables SSL enforcement on the Aurora cluster.
#
# What this does:
#   1. Sets rds.force_ssl = 0 in the cluster parameter group
#   2. The cluster now accepts unencrypted connections
#   3. Students must find and fix the problem
#
# Usage:
#   export CLUSTER_ID="devops-lab-cluster"
#   export PARAM_GROUP_NAME="devops-lab-cluster-params"
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/01-ssl-not-enforced/inject.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 01 - Injecting: SSL Not Enforced"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ID PARAM_GROUP_NAME AWS_REGION; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Export it before running this script."
    exit 1
  fi
done

# ── Check that the parameter group exists ────────────────────────────────────
echo "[INFO] Checking parameter group: $PARAM_GROUP_NAME"
if ! aws rds describe-db-cluster-parameter-groups \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --region "$AWS_REGION" &>/dev/null; then
  echo "[ERROR] Parameter group '$PARAM_GROUP_NAME' not found."
  echo "        Create it first or set PARAM_GROUP_NAME to an existing group."
  exit 1
fi

# ── Record current state ────────────────────────────────────────────────────
CURRENT_SSL=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue | [0]" \
  --output text \
  --region "$AWS_REGION" 2>/dev/null || echo "not set")

echo "[INFO] Current rds.force_ssl value: '${CURRENT_SSL}'"

# ── Inject: set rds.force_ssl to 0 ──────────────────────────────────────────
echo "[INFO] Setting rds.force_ssl = 0 in parameter group: $PARAM_GROUP_NAME"
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=0,ApplyMethod=immediate" \
  --region "$AWS_REGION" > /dev/null

echo "[OK] Parameter set. Change is dynamic - no reboot needed for Aurora."

# ── Save scenario state ─────────────────────────────────────────────────────
STATE_FILE="/tmp/module04-scenario01-state.sh"
cat > "$STATE_FILE" << EOF
export SCENARIO01_PREVIOUS_SSL="$CURRENT_SSL"
export SCENARIO01_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

echo ""
echo "============================================"
echo "  INJECTION COMPLETE"
echo "============================================"
echo ""
echo "  The Aurora cluster no longer enforces SSL."
echo "  Database connections can now be made without encryption."
echo ""
echo "  Your job: Find the problem and fix it."
echo "  Runbook:  survive/01-ssl-not-enforced/runbook.md"
echo "  Validate: bash survive/01-ssl-not-enforced/validate.sh"
echo ""
echo "============================================"
