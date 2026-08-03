#!/usr/bin/env bash
# Tier 3 SURVIVE - Shared Environment Configuration
# Source this file in every inject.sh and validate.sh

# =====================================================================
# STUDENT: Fill in your values below before running any scenario
# =====================================================================

# Your RDS instance identifier (not the endpoint - the name you gave it)
export RDS_INSTANCE_ID="${RDS_INSTANCE_ID:-my-postgres-instance}"

# Your RDS endpoint (hostname only, no port)
export RDS_ENDPOINT="${RDS_ENDPOINT:-}"

# Your RDS master username
export RDS_USERNAME="${RDS_USERNAME:-postgres}"

# Your RDS database name
export RDS_DBNAME="${RDS_DBNAME:-postgres}"

# Your custom parameter group name (from BUILD 01)
export PARAMETER_GROUP="${PARAMETER_GROUP:-tier3-custom-pg16}"

# Your AWS region
export AWS_REGION="${AWS_REGION:-us-east-1}"

# Port (almost always 5432)
export RDS_PORT="${RDS_PORT:-5432}"

# =====================================================================
# DO NOT EDIT BELOW THIS LINE
# =====================================================================

# Validate required variables are set
check_required_vars() {
  local missing=()
  for var in RDS_INSTANCE_ID RDS_ENDPOINT RDS_USERNAME RDS_DBNAME PARAMETER_GROUP AWS_REGION; do
    if [[ -z "${!var}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: The following required variables are not set in config.sh:"
    for v in "${missing[@]}"; do
      echo "  - $v"
    done
    echo "Edit /path/to/survive/config.sh and set all required variables."
    exit 1
  fi
}

# Source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
