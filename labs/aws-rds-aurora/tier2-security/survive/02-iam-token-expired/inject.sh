#!/usr/bin/env bash
# Scenario 02 - IAM Token Expired
# inject.sh: Creates the IAM auth setup and then simulates an expired token.
#
# What this does:
#   1. Creates a PostgreSQL role with rds_iam
#   2. Creates a stale (pre-expired) auth token and saves it
#   3. Students must generate a fresh token and connect successfully
#
# Usage:
#   source survive/config.sh
#   bash survive/02-iam-token-expired/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 02 - Injecting: IAM Token Expired"

check_aws_cli
check_psql
check_config_loaded

# ─── Verify IAM auth is enabled on the instance ────────────────────────────────
IAM_ENABLED=$(rds_iam_auth_enabled)
if [[ "$IAM_ENABLED" != "true" ]]; then
  warn "IAM database authentication is not enabled on this instance."
  info "Enabling IAM auth now..."
  aws rds modify-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --enable-iam-database-authentication \
    --apply-immediately \
    --region "$AWS_REGION"
  wait_for_rds_available
  success "IAM auth enabled."
else
  success "IAM auth is already enabled."
fi

# ─── Create the PostgreSQL iam_scenario_user role ──────────────────────────────
info "Creating PostgreSQL role 'iam_scenario_user' with rds_iam..."

PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" \
  --command="DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'iam_scenario_user') THEN
      CREATE ROLE iam_scenario_user WITH LOGIN;
    END IF;
    GRANT rds_iam TO iam_scenario_user;
  END \$\$;" 2>/dev/null

success "Role 'iam_scenario_user' exists and has rds_iam."

# ─── Generate a stale token and save it to disk ────────────────────────────────
# The token itself is valid-looking but will be expired by the time students use it.
# We generate it now and it will expire 15 minutes from this moment.

info "Generating IAM token (this token will expire in 15 minutes)..."

STALE_TOKEN=$(aws rds generate-db-auth-token \
  --hostname "$RDS_HOST" \
  --port "$RDS_PORT" \
  --region "$AWS_REGION" \
  --username iam_scenario_user)

STALE_TOKEN_FILE="/tmp/tier2-scenario02-stale-token.txt"
echo "$STALE_TOKEN" > "$STALE_TOKEN_FILE"

success "Stale token saved to $STALE_TOKEN_FILE"
info "This token will expire at approximately: $(date -v+15M 2>/dev/null || date -d '+15 minutes' 2>/dev/null || echo '[15 minutes from now]')"

# ─── Save scenario state ───────────────────────────────────────────────────────
STATE_FILE="/tmp/tier2-scenario02-state.sh"
cat > "$STATE_FILE" << EOF
# Scenario 02 state - sourced by validate.sh
export SCENARIO02_ROLE="iam_scenario_user"
export SCENARIO02_TOKEN_FILE="$STALE_TOKEN_FILE"
export SCENARIO02_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

separator
warn "INJECTION COMPLETE"
warn ""
warn "Situation:"
warn "  An application is trying to connect to RDS using IAM authentication."
warn "  The application stored the auth token at startup."
warn "  The token has expired (or will expire very soon)."
warn "  The application cannot connect."
warn ""
warn "Evidence:"
warn "  Stale token saved to: $STALE_TOKEN_FILE"
warn "  Role name: iam_scenario_user"
warn ""
warn "Your job: Diagnose why the app cannot connect and fix it."
warn "Runbook:  survive/02-iam-token-expired/runbook.md"
warn "Validate: bash survive/02-iam-token-expired/validate.sh"
warn ""
warn "Note: Wait at least 15 minutes after injection before validating,"
warn "      or the 'stale token' will not yet be expired."
separator
