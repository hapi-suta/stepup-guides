#!/usr/bin/env bash
# Scenario 03 - Password Leaked
# inject.sh: Creates a simulated "leaked" password situation.
#
# What this does:
#   1. Creates an app role with a known password
#   2. Writes that password to a fake "leaked" config file
#   3. Students must rotate the password and store it in Secrets Manager
#
# Usage:
#   export CLUSTER_ID="devops-lab-cluster"
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/03-password-leaked/inject.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 03 - Injecting: Password Leaked"
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
LEAKED_FILE="/tmp/module04-scenario03-leaked-config.env"

# ── Create the application role ─────────────────────────────────────────────
echo "[INFO] Creating PostgreSQL role '$LEAKED_USER'..."

PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --command="DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$LEAKED_USER') THEN
      CREATE ROLE $LEAKED_USER WITH LOGIN PASSWORD '$LEAKED_PASSWORD';
    ELSE
      ALTER ROLE $LEAKED_USER WITH PASSWORD '$LEAKED_PASSWORD' LOGIN;
    END IF;
    GRANT CONNECT ON DATABASE postgres TO $LEAKED_USER;
  END \$\$;" 2>/dev/null

echo "[OK] Role '$LEAKED_USER' created with known password."

# ── Write the "leaked" config file ──────────────────────────────────────────
cat > "$LEAKED_FILE" << EOF
# Application environment file
# WARNING: This file was accidentally committed to the public GitHub repository
# on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# It has been publicly visible for approximately 2 hours.

DB_HOST=$CLUSTER_ENDPOINT
DB_PORT=5432
DB_NAME=postgres
DB_USER=$LEAKED_USER
DB_PASSWORD=$LEAKED_PASSWORD
EOF

echo "[OK] Simulated leaked config file written to: $LEAKED_FILE"

# ── Save scenario state ─────────────────────────────────────────────────────
STATE_FILE="/tmp/module04-scenario03-state.sh"
cat > "$STATE_FILE" << EOF
export SCENARIO03_USER="$LEAKED_USER"
export SCENARIO03_LEAKED_PASSWORD="$LEAKED_PASSWORD"
export SCENARIO03_LEAKED_FILE="$LEAKED_FILE"
export SCENARIO03_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

echo ""
echo "============================================"
echo "  INJECTION COMPLETE - SECURITY INCIDENT"
echo "============================================"
echo ""
echo "  Situation:"
echo "    A developer accidentally committed a .env file to a public GitHub repo."
echo "    The file contained the database password for the '$LEAKED_USER' account."
echo "    The commit was live for 2 hours before anyone noticed."
echo "    Security team has just alerted you."
echo ""
echo "  Evidence:"
echo "    Leaked config file: $LEAKED_FILE"
echo "    Current password: $LEAKED_PASSWORD (treat this as compromised)"
echo ""
echo "  Your job: Execute emergency password rotation immediately."
echo "    1. Rotate the password NOW"
echo "    2. Verify the old password no longer works"
echo "    3. Store the new password in Secrets Manager"
echo "    4. Update the application config"
echo ""
echo "  Runbook:  survive/03-password-leaked/runbook.md"
echo "  Validate: bash survive/03-password-leaked/validate.sh"
echo ""
echo "============================================"
