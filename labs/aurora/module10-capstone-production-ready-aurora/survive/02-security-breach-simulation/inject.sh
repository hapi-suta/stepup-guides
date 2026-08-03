#!/usr/bin/env bash
# SURVIVE Scenario 02: Security Breach Simulation
# Injects: Creates a rogue database user with elevated privileges and
#          simulates credential compromise by logging failed auth attempts.
# Idempotent: Safe to run multiple times. Drops and recreates the rogue user.
#
# Usage: bash inject.sh
# Requires: AWS CLI configured, psql available, DB_HOST/DB_USER/DB_PASSWORD set

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"

DB_HOST="${DB_HOST:-$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Endpoint' --output text --region "$REGION")}"
DB_USER="${DB_USER:-dbadmin}"
DB_PASSWORD="${DB_PASSWORD:?ERROR: Set DB_PASSWORD environment variable}"

echo "============================================="
echo "  SURVIVE Scenario 02: Security Breach Simulation"
echo "============================================="
echo ""
echo "  Cluster: $CLUSTER_ID"
echo "  Host:    $DB_HOST"
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Step 1: Create a rogue user with elevated privileges
echo "Creating rogue database user 'compromised_user'..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "
  DROP ROLE IF EXISTS compromised_user;
  CREATE ROLE compromised_user WITH LOGIN PASSWORD 'weak_password_123' CREATEDB;
  GRANT ALL PRIVILEGES ON SCHEMA app TO compromised_user;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app TO compromised_user;
" 2>/dev/null

echo "Rogue user created with CREATEDB and full app schema access."
echo ""

# Step 2: Simulate suspicious activity - multiple failed login attempts
echo "Simulating failed authentication attempts..."
for i in $(seq 1 10); do
  PGPASSWORD="wrong_password" psql -h "$DB_HOST" -U "hacker_attempt_$i" -d postgres -c "SELECT 1;" 2>/dev/null || true
done

echo "10 failed authentication attempts generated."
echo ""

# Step 3: Use the rogue user to access sensitive data
echo "Simulating data exfiltration..."
PGPASSWORD="weak_password_123" psql -h "$DB_HOST" -U compromised_user -d postgres -c "
  SELECT count(*) AS users_accessed FROM app.users;
" 2>/dev/null || echo "  (No data in app.users table - that's OK for this scenario)"

echo ""
echo "YOUR MISSION:"
echo "  1. Detect the security breach using CloudWatch Logs and pgaudit"
echo "  2. Identify the rogue user and their privileges"
echo "  3. Revoke all privileges and lock the account"
echo "  4. Investigate what data was accessed"
echo "  5. Rotate the master password via Secrets Manager"
echo "  6. Document the incident timeline"
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
