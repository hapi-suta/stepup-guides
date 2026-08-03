#!/usr/bin/env bash
# Tier 2 Security - Survive Scenario Configuration
# Source this file before running any inject.sh or validate.sh script.
#
# Usage:
#   source config.sh
#   ./survive/01-ssl-not-enforced/inject.sh

# ─── Required: fill these in before running any scenarios ──────────────────────

# Your RDS instance identifier (not the endpoint, the name you gave it)
export RDS_INSTANCE_ID="my-postgres-db"

# Your RDS endpoint (the full .rds.amazonaws.com address)
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"

# Port (default 5432)
export RDS_PORT="5432"

# Default database to connect to
export RDS_DB="postgres"

# Master username
export RDS_MASTER_USER="postgres"

# AWS region
export AWS_REGION="us-east-1"

# Parameter group name (custom - NOT a default group, which cannot be modified)
# If you do not have one, create it:
#   aws rds create-db-parameter-group \
#     --db-parameter-group-name tier2-survive-params \
#     --db-parameter-group-family postgres16 \
#     --description "Tier 2 survive scenarios"
export PARAM_GROUP_NAME="tier2-survive-params"

# ─── Student env (overrides placeholders above if present) ─────────────────────

STUDENT_ENV="${HOME}/.suta/aws-rds-tier1.env"
if [[ -f "$STUDENT_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$STUDENT_ENV"
  # Map student env variable names to the names common.sh expects
  export RDS_MASTER_PASSWORD="${DB_PASSWORD}"
  export RDS_MASTER_USER="${DB_USER:-$RDS_MASTER_USER}"
else
  echo "WARNING: Student env file not found at $STUDENT_ENV"
  echo "         Set RDS_MASTER_PASSWORD manually or create that file."
fi

# ─── Optional: auto-populated from the above ───────────────────────────────────

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

export DB_RESOURCE_ID=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --query 'DBInstances[0].DbiResourceId' \
  --output text \
  --region "$AWS_REGION" 2>/dev/null)

# ─── Verification ──────────────────────────────────────────────────────────────

_config_ok=true

if [[ "$RDS_INSTANCE_ID" == "my-postgres-db" ]]; then
  echo "WARNING: RDS_INSTANCE_ID is still the placeholder value."
  echo "         Edit config.sh and set your real instance ID."
  _config_ok=false
fi

if [[ "$RDS_HOST" == "your-instance.abc123.us-east-1.rds.amazonaws.com" ]]; then
  echo "WARNING: RDS_HOST is still the placeholder value."
  echo "         Edit config.sh and set your real RDS endpoint."
  _config_ok=false
fi

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: Could not retrieve AWS account ID."
  echo "       Make sure your AWS CLI is configured: aws sts get-caller-identity"
  _config_ok=false
fi

if [[ "$_config_ok" == "true" ]]; then
  echo "config.sh loaded successfully."
  echo "  Instance:   $RDS_INSTANCE_ID"
  echo "  Host:       $RDS_HOST"
  echo "  Region:     $AWS_REGION"
  echo "  Account:    $AWS_ACCOUNT_ID"
  echo "  DB Res ID:  $DB_RESOURCE_ID"
fi
