#!/usr/bin/env bash
# survive/config.sh
# Loads student environment and exports AWS-specific variables
# for RDS survive scenario scripts.
#
# Usage: source /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/config.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Load the student environment file
# ---------------------------------------------------------------------------
STUDENT_ENV="${STUDENT_ENV_FILE:-${HOME}/.suta/aws-rds-tier1.env}"

if [[ ! -f "$STUDENT_ENV" ]]; then
  echo "ERROR: Student env file not found: $STUDENT_ENV"
  echo "       Set STUDENT_ENV_FILE or create $STUDENT_ENV"
  echo ""
  echo "       Required variables:"
  echo "         RDS_INSTANCE_ID       e.g. suta-rds-lab"
  echo "         AURORA_CLUSTER_ID     e.g. suta-aurora-lab"
  echo "         RDS_ENDPOINT          e.g. suta-rds-lab.abc123.us-east-1.rds.amazonaws.com"
  echo "         AURORA_CLUSTER_EP     e.g. suta-aurora-lab.cluster-abc123.us-east-1.rds.amazonaws.com"
  echo "         AURORA_READER_EP      e.g. suta-aurora-lab.cluster-ro-abc123.us-east-1.rds.amazonaws.com"
  echo "         RDS_SG_ID             e.g. sg-0abc123def456789a"
  echo "         AURORA_SG_ID          e.g. sg-0def456abc123789b"
  echo "         DB_PORT               5432"
  echo "         DB_USER               postgres"
  echo "         DB_NAME               labdb"
  echo "         DB_PASSWORD           your_password"
  echo "         AWS_REGION            e.g. us-east-1"
  exit 1
fi

# shellcheck disable=SC1090
source "$STUDENT_ENV"

# ---------------------------------------------------------------------------
# 2. Validate required variables
# ---------------------------------------------------------------------------
REQUIRED_VARS=(
  RDS_INSTANCE_ID
  RDS_ENDPOINT
  RDS_SG_ID
  DB_PORT
  DB_USER
  DB_NAME
  DB_PASSWORD
  AWS_REGION
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required variables in $STUDENT_ENV:"
  for v in "${missing[@]}"; do
    echo "  - $v"
  done
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Export all variables so child scripts can use them
# ---------------------------------------------------------------------------
export RDS_INSTANCE_ID
export AURORA_CLUSTER_ID="${AURORA_CLUSTER_ID:-}"
export RDS_ENDPOINT
export AURORA_CLUSTER_EP="${AURORA_CLUSTER_EP:-}"
export AURORA_READER_EP="${AURORA_READER_EP:-}"
export RDS_SG_ID
export AURORA_SG_ID="${AURORA_SG_ID:-}"
export DB_PORT
export DB_USER
export DB_NAME
export DB_PASSWORD
export AWS_REGION
export PGPASSWORD="$DB_PASSWORD"

# ---------------------------------------------------------------------------
# 4. Confirm AWS CLI is configured and pointing to the right region
# ---------------------------------------------------------------------------
export AWS_DEFAULT_REGION="$AWS_REGION"

CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1) || {
  echo "ERROR: AWS CLI is not configured. Run: aws configure"
  exit 1
}

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
echo "AWS Account: $ACCOUNT_ID  |  Region: $AWS_REGION"
echo "RDS Instance: $RDS_INSTANCE_ID  |  Endpoint: $RDS_ENDPOINT"
echo ""
