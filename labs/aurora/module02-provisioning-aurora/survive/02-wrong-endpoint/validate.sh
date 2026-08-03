#!/usr/bin/env bash
# survive/02-wrong-endpoint/validate.sh
# Verifies the config file has the correct writer endpoint
# and write operations succeed.
#
# Required environment variables:
#   CLUSTER_ID       - Aurora cluster identifier (default: devops-lab-cluster)
#   REGION           - AWS region (default: us-east-1)
#   DB_USER          - Database username (default: clusteradmin)
#   DB_NAME          - Database name (default: devopsdb)
#   PGPASSWORD       - Database password (must be set)
#
# Usage:
#   export CLUSTER_ID=devops-lab-cluster
#   export REGION=us-east-1
#   export PGPASSWORD=YourPassword
#   bash validate.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${REGION:-us-east-1}"
DB_USER="${DB_USER:-clusteradmin}"
DB_NAME="${DB_NAME:-devopsdb}"
DB_PORT="5432"
APP_CONFIG="/tmp/devops-app-config.env"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "[PASS]  $1"
  (( PASS_COUNT++ )) || true
}

fail() {
  echo "[FAIL]  $1"
  if [[ -n "${2:-}" ]]; then
    echo "        Hint: $2"
  fi
  (( FAIL_COUNT++ )) || true
}

echo ""
echo "========================================"
echo "  VALIDATE: Wrong Endpoint"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Get the actual writer endpoint from AWS
# ---------------------------------------------------------------------------
WRITER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Endpoint" \
  --output text 2>/dev/null || echo "")

READER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].ReaderEndpoint" \
  --output text 2>/dev/null || echo "")

# ---------------------------------------------------------------------------
# Check 1 - Config file exists
# ---------------------------------------------------------------------------
echo "[INFO]  Check 1: Application config file exists"

if [[ -f "$APP_CONFIG" ]]; then
  pass "Config file $APP_CONFIG exists"
else
  fail "Config file $APP_CONFIG not found" \
    "Run inject.sh first if this is your first time with this scenario"
  echo ""
  echo "================================"
  echo "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
  echo "================================"
  exit 1
fi

# ---------------------------------------------------------------------------
# Check 2 - Config has a DB_HOST value
# ---------------------------------------------------------------------------
echo "[INFO]  Check 2: Config file has DB_HOST"

CONFIG_HOST=$(grep "^DB_HOST=" "$APP_CONFIG" | cut -d= -f2)

if [[ -n "$CONFIG_HOST" ]]; then
  pass "DB_HOST is set in config: $CONFIG_HOST"
else
  fail "DB_HOST is missing from config" \
    "Edit $APP_CONFIG and add: DB_HOST=<writer-endpoint>"
fi

# ---------------------------------------------------------------------------
# Check 3 - Config endpoint is the writer (not the reader)
# ---------------------------------------------------------------------------
echo "[INFO]  Check 3: Config endpoint is the writer endpoint (not reader)"

if [[ "$CONFIG_HOST" == "$WRITER_EP" ]]; then
  pass "Config endpoint matches the Aurora writer endpoint"
elif [[ "$CONFIG_HOST" == "$READER_EP" ]]; then
  fail "Config endpoint is the READER endpoint (still wrong)" \
    "Replace with writer: $WRITER_EP"
else
  fail "Config endpoint does not match either cluster endpoint" \
    "Writer: $WRITER_EP | Reader: $READER_EP | Config: $CONFIG_HOST"
fi

# ---------------------------------------------------------------------------
# Check 4 - Config endpoint does NOT contain 'cluster-ro'
# ---------------------------------------------------------------------------
echo "[INFO]  Check 4: Endpoint does not contain 'cluster-ro'"

if [[ "$CONFIG_HOST" != *"cluster-ro"* ]]; then
  pass "Endpoint does not contain 'cluster-ro' (good - it is not a reader)"
else
  fail "Endpoint contains 'cluster-ro' - this is a reader endpoint" \
    "The writer endpoint should contain 'cluster-' without '-ro'"
fi

# ---------------------------------------------------------------------------
# Check 5 - DNS resolves for the configured host
# ---------------------------------------------------------------------------
echo "[INFO]  Check 5: Configured host resolves in DNS"

if [[ -n "$CONFIG_HOST" ]]; then
  RESOLVED_IP=$(dig +short "$CONFIG_HOST" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED_IP" ]]; then
    pass "DNS resolved $CONFIG_HOST -> $RESOLVED_IP"
  else
    fail "DNS could not resolve $CONFIG_HOST" \
      "Find the correct endpoint: aws rds describe-db-clusters --db-cluster-identifier $CLUSTER_ID --query \"DBClusters[0].Endpoint\" --output text"
  fi
fi

# ---------------------------------------------------------------------------
# Check 6 - Connected instance is the writer
# ---------------------------------------------------------------------------
echo "[INFO]  Check 6: Connected instance is the writer (pg_is_in_recovery = false)"

if [[ -n "$CONFIG_HOST" ]]; then
  IS_RECOVERY=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CONFIG_HOST" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT pg_is_in_recovery()" 2>/dev/null || echo "error")

  if [[ "$IS_RECOVERY" == "f" ]]; then
    pass "Connected to writer (pg_is_in_recovery = false)"
  elif [[ "$IS_RECOVERY" == "t" ]]; then
    fail "Connected to a reader (pg_is_in_recovery = true)" \
      "The config still points to a reader endpoint"
  else
    fail "Could not check instance role" "psql connection failed"
  fi
fi

# ---------------------------------------------------------------------------
# Check 7 - Write operations succeed
# ---------------------------------------------------------------------------
echo "[INFO]  Check 7: Write operations succeed on configured endpoint"

if [[ -n "$CONFIG_HOST" ]]; then
  WRITE_TEST=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CONFIG_HOST" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "CREATE TEMP TABLE _validate_write (id INT); INSERT INTO _validate_write VALUES (1); SELECT count(*) FROM _validate_write; DROP TABLE _validate_write;" 2>/dev/null || echo "failed")

  if [[ "$WRITE_TEST" == "1" ]]; then
    pass "Write operations (INSERT) succeed on configured endpoint"
  else
    fail "Write operations failed on configured endpoint" \
      "Still connected to a reader. Update DB_HOST to the writer endpoint."
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================"
echo "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "[WARN]  Some checks failed. See details above."
  exit 1
else
  echo "[PASS]  All checks passed."
  exit 0
fi
