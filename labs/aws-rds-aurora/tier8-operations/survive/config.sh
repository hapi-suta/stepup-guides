#!/usr/bin/env bash
# =============================================================================
# Tier 8 SURVIVE Scenario Configuration
# Source this file in inject.sh and validate.sh for each scenario
# =============================================================================

# RDS instance/cluster identifiers - update these before running scenarios
export T8_INSTANCE_ID="${T8_INSTANCE_ID:-}"
export T8_CLUSTER_ID="${T8_CLUSTER_ID:-}"
export T8_REGION="${T8_REGION:-us-east-1}"
export T8_ACCOUNT_ID="${T8_ACCOUNT_ID:-}"

# Database connection settings
export T8_DB_HOST="${T8_DB_HOST:-}"
export T8_DB_PORT="${T8_DB_PORT:-5432}"
export T8_DB_USER="${T8_DB_USER:-postgres}"
export T8_DB_NAME="${T8_DB_NAME:-postgres}"
# Do not set T8_DB_PASSWORD here - use IAM auth, .pgpass, or PGPASSWORD env var

# SNS topic for alerts (optional - used by inject scenarios that simulate alerts)
export T8_SNS_TOPIC_ARN="${T8_SNS_TOPIC_ARN:-}"

# S3 bucket for storing scenario results and snapshots
export T8_RESULTS_BUCKET="${T8_RESULTS_BUCKET:-}"

# Parameter group name attached to the instance/cluster
export T8_PARAMETER_GROUP="${T8_PARAMETER_GROUP:-}"

# CloudWatch log group for the RDS instance
export T8_LOG_GROUP="${T8_LOG_GROUP:-/aws/rds/instance/${T8_INSTANCE_ID}/postgresql}"

# Timing configuration
export T8_SCENARIO_START=""  # Set by inject.sh
export T8_INJECT_TIMEOUT=300  # Max seconds to wait for injection to take effect

# Validate required config is set
t8_validate_config() {
  local required_vars=("T8_REGION" "T8_INSTANCE_ID")
  local missing=()

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Required configuration variables not set:"
    for var in "${missing[@]}"; do
      echo "  - ${var}"
    done
    echo ""
    echo "Set these environment variables before running the scenario:"
    echo "  export T8_INSTANCE_ID=your-instance-id"
    echo "  export T8_CLUSTER_ID=your-cluster-id"
    echo "  export T8_REGION=us-east-1"
    echo "  export T8_ACCOUNT_ID=123456789012"
    echo "  export T8_DB_HOST=your-rds-endpoint"
    echo "  export T8_DB_USER=postgres"
    echo "  export T8_PARAMETER_GROUP=your-parameter-group-name"
    return 1
  fi

  return 0
}
