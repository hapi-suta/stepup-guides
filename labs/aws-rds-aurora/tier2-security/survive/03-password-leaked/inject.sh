#!/usr/bin/env bash
# Scenario 03 - Password Leaked
# inject.sh: Creates a simulated "leaked" password situation.
#
# What this does:
#   1. Creates an app role with a known password
#   2. Writes that password to a fake "leaked" config file
#   3. Students must rotate the password immediately
#
# Usage:
#   source survive/config.sh
#   bash survive/03-password-leaked/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 03 - Injecting: Password Leaked"

check_aws_cli
check_psql
check_config_loaded

LEAKED_USER="payment_service"
LEAKED_PASSWORD="Sup3rSecret99!"
LEAKED_FILE="/tmp/tier2-scenario03-leaked-config.env"

# ─── Create the application role ───────────────────────────────────────────────
info "Creating PostgreSQL role '$LEAKED_USER'..."

PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" \
  --command="DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$LEAKED_USER') THEN
      CREATE ROLE $LEAKED_USER WITH LOGIN PASSWORD '$LEAKED_PASSWORD';
    ELSE
      ALTER ROLE $LEAKED_USER WITH PASSWORD '$LEAKED_PASSWORD' LOGIN;
    END IF;
    GRANT CONNECT ON DATABASE postgres TO $LEAKED_USER;
  END \$\$;" 2>/dev/null

success "Role '$LEAKED_USER' created with known password."

# ─── Write the "leaked" config file ────────────────────────────────────────────
cat > "$LEAKED_FILE" << EOF
# Application environment file
# WARNING: This file was accidentally committed to the public GitHub repository
# on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# It has been publicly visible for approximately 2 hours.

DB_HOST=$RDS_HOST
DB_PORT=$RDS_PORT
DB_NAME=postgres
DB_USER=$LEAKED_USER
DB_PASSWORD=$LEAKED_PASSWORD
EOF

success "Simulated leaked config file written to: $LEAKED_FILE"

# ─── Save scenario state ───────────────────────────────────────────────────────
STATE_FILE="/tmp/tier2-scenario03-state.sh"
cat > "$STATE_FILE" << EOF
export SCENARIO03_USER="$LEAKED_USER"
export SCENARIO03_LEAKED_PASSWORD="$LEAKED_PASSWORD"
export SCENARIO03_LEAKED_FILE="$LEAKED_FILE"
export SCENARIO03_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

separator
warn "INJECTION COMPLETE - SECURITY INCIDENT SIMULATION"
warn ""
warn "Situation:"
warn "  A developer accidentally committed a .env file to a public GitHub repo."
warn "  The file contained the database password for the '$LEAKED_USER' account."
warn "  The commit was live for 2 hours before anyone noticed."
warn "  Security team has just alerted you."
warn ""
warn "Evidence:"
warn "  Leaked config file: $LEAKED_FILE"
warn "  Current password: $LEAKED_PASSWORD (treat this as compromised)"
warn ""
warn "Your job: Execute emergency password rotation immediately."
warn "  1. Rotate the password NOW"
warn "  2. Verify the old password no longer works"
warn "  3. Store the new password in Secrets Manager"
warn "  4. Update the application config"
warn ""
warn "Runbook:  survive/03-password-leaked/runbook.md"
warn "Validate: bash survive/03-password-leaked/validate.sh"
separator
