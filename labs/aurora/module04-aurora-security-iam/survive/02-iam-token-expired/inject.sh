#!/usr/bin/env bash
# Scenario 02 - IAM Token Expired
# inject.sh: Creates the IAM auth setup and then simulates an expired token.
#
# What this does:
#   1. Ensures IAM auth is enabled on the cluster
#   2. Creates a PostgreSQL role with rds_iam
#   3. Generates a stale (pre-expired) auth token and saves it
#   4. Students must generate a fresh token and connect successfully
#
# Usage:
#   export CLUSTER_ID="devops-lab-cluster"
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/02-iam-token-expired/inject.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 02 - Injecting: IAM Token Expired"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ID CLUSTER_ENDPOINT MASTER_USER MASTER_PASSWORD AWS_REGION; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Export it before running this script."
    exit 1
  fi
done

# ── Verify IAM auth is enabled on the cluster ───────────────────────────────
IAM_ENABLED=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
  --output text \
  --region "$AWS_REGION")

if [[ "$IAM_ENABLED" != "True" ]]; then
  echo "[WARN] IAM database authentication is not enabled."
  echo "[INFO] Enabling IAM auth now..."
  aws rds modify-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --enable-iam-database-authentication \
    --apply-immediately \
    --region "$AWS_REGION" > /dev/null
  echo "[INFO] Waiting for cluster to be available..."
  sleep 30
  echo "[OK] IAM auth enabled."
else
  echo "[OK] IAM auth is already enabled."
fi

# ── Create the PostgreSQL iam_scenario_user role ─────────────────────────────
echo "[INFO] Creating PostgreSQL role 'iam_scenario_user' with rds_iam..."

PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --command="DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'iam_scenario_user') THEN
      CREATE ROLE iam_scenario_user WITH LOGIN;
    END IF;
    GRANT rds_iam TO iam_scenario_user;
  END \$\$;" 2>/dev/null

echo "[OK] Role 'iam_scenario_user' exists and has rds_iam."

# ── Generate a stale token and save it to disk ───────────────────────────────
echo "[INFO] Generating IAM token (this token will expire in 15 minutes)..."

STALE_TOKEN=$(aws rds generate-db-auth-token \
  --hostname "$CLUSTER_ENDPOINT" \
  --port 5432 \
  --region "$AWS_REGION" \
  --username iam_scenario_user)

STALE_TOKEN_FILE="/tmp/module04-scenario02-stale-token.txt"
echo "$STALE_TOKEN" > "$STALE_TOKEN_FILE"

echo "[OK] Stale token saved to $STALE_TOKEN_FILE"

# ── Save scenario state ─────────────────────────────────────────────────────
STATE_FILE="/tmp/module04-scenario02-state.sh"
cat > "$STATE_FILE" << EOF
export SCENARIO02_ROLE="iam_scenario_user"
export SCENARIO02_TOKEN_FILE="$STALE_TOKEN_FILE"
export SCENARIO02_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

echo ""
echo "============================================"
echo "  INJECTION COMPLETE"
echo "============================================"
echo ""
echo "  Situation:"
echo "    An application is trying to connect to Aurora using IAM auth."
echo "    The application stored the auth token at startup."
echo "    The token has expired (or will expire very soon)."
echo "    The application cannot connect."
echo ""
echo "  Evidence:"
echo "    Stale token saved to: $STALE_TOKEN_FILE"
echo "    Role name: iam_scenario_user"
echo ""
echo "  Your job: Diagnose why the app cannot connect and fix it."
echo "  Runbook:  survive/02-iam-token-expired/runbook.md"
echo "  Validate: bash survive/02-iam-token-expired/validate.sh"
echo ""
echo "  Note: Wait at least 15 minutes after injection before validating,"
echo "        or the stale token will not yet be expired."
echo ""
echo "============================================"
