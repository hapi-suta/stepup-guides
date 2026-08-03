#!/usr/bin/env bash
# survive/config.sh
# Central configuration for all Tier 6 SURVIVE scenarios.
# Source this file at the top of every inject.sh and validate.sh.

# -------------------------------------------------------------------
# STUDENT: Fill in these values before running any scenario
# -------------------------------------------------------------------

export DB_INSTANCE_ID="${DB_INSTANCE_ID:-your-rds-instance-id}"
export DB_CLUSTER_ID="${DB_CLUSTER_ID:-your-aurora-cluster-id}"
export DB_ENDPOINT="${DB_ENDPOINT:-your-endpoint.rds.amazonaws.com}"
export DB_PORT="${DB_PORT:-5432}"
export DB_NAME="${DB_NAME:-postgres}"
export DB_USER="${DB_USER:-postgres}"
export DB_PASSWORD="${DB_PASSWORD:-}"
export REGION="${REGION:-us-east-1}"
export PROXY_ENDPOINT="${PROXY_ENDPOINT:-}"

# -------------------------------------------------------------------
# Scenario metadata
# -------------------------------------------------------------------
export SURVIVE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SURVIVE_LOG_DIR="${SURVIVE_BASE_DIR}/logs"

mkdir -p "$SURVIVE_LOG_DIR"

# -------------------------------------------------------------------
# PGPASSWORD so psql does not prompt
# -------------------------------------------------------------------
export PGPASSWORD="$DB_PASSWORD"

# -------------------------------------------------------------------
# Color codes for output
# -------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "[INFO] $*"; }

# psql shortcut
psql_exec() {
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
         -t -A -c "$1" 2>/dev/null
}
