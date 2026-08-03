#!/usr/bin/env bash
# survive/01-security-group-lockout/inject.sh
# Removes all inbound rules from the Aurora cluster's security group.
# This simulates someone accidentally wiping firewall rules.
#
# Required environment variables:
#   CLUSTER_ID       - Aurora cluster identifier (default: devops-lab-cluster)
#   REGION           - AWS region (default: us-east-1)
#
# Usage:
#   export CLUSTER_ID=devops-lab-cluster
#   export REGION=us-east-1
#   bash inject.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${REGION:-us-east-1}"
BACKUP_FILE="/tmp/devops-sg-backup-01.json"

echo ""
echo "========================================"
echo "  INJECT: Security Group Lockout"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1 - Get the security group ID from the Aurora cluster
# ---------------------------------------------------------------------------
echo "[INFO]  Looking up security group for cluster $CLUSTER_ID..."

SG_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId" \
  --output text 2>/dev/null)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  echo "[FAIL]  Could not find security group for cluster $CLUSTER_ID"
  exit 1
fi
echo "[PASS]  Security group: $SG_ID"

# ---------------------------------------------------------------------------
# Step 2 - Get the cluster endpoint and verify the cluster is available
# ---------------------------------------------------------------------------
echo "[INFO]  Checking cluster status..."

CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Status" \
  --output text 2>/dev/null)

if [[ "$CLUSTER_STATUS" != "available" ]]; then
  echo "[FAIL]  Cluster $CLUSTER_ID is not available (status: $CLUSTER_STATUS). Aborting."
  exit 1
fi
echo "[PASS]  Cluster is available"

CLUSTER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Endpoint" \
  --output text 2>/dev/null)

# ---------------------------------------------------------------------------
# Step 3 - Test connectivity before injection
# ---------------------------------------------------------------------------
echo "[INFO]  Testing port 5432 before injection..."
if nc -z -w 5 "$CLUSTER_EP" 5432 2>/dev/null; then
  echo "[PASS]  Port 5432 is open before inject"
else
  echo "[WARN]  Port 5432 was already closed. Proceeding anyway."
fi

# ---------------------------------------------------------------------------
# Step 4 - Backup current security group rules
# ---------------------------------------------------------------------------
echo "[INFO]  Backing up security group rules for $SG_ID..."

aws ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions" \
  --output json > "$BACKUP_FILE"

echo "[PASS]  Rules backed up to $BACKUP_FILE"

# ---------------------------------------------------------------------------
# Step 5 - Remove all inbound rules
# ---------------------------------------------------------------------------
echo "[INFO]  Removing all inbound rules from $SG_ID..."

CURRENT_RULES=$(cat "$BACKUP_FILE")

if [[ "$CURRENT_RULES" == "[]" || -z "$CURRENT_RULES" ]]; then
  echo "[WARN]  No inbound rules found. Nothing to remove."
else
  aws ec2 revoke-security-group-ingress \
    --group-id "$SG_ID" \
    --region "$REGION" \
    --ip-permissions "$CURRENT_RULES" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 6 - Verify rules are gone
# ---------------------------------------------------------------------------
REMAINING=$(aws ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions" \
  --output json 2>/dev/null)

if [[ "$REMAINING" == "[]" ]]; then
  echo "[PASS]  All inbound rules removed from $SG_ID"
else
  echo "[WARN]  Some rules may remain. Check manually."
fi

echo ""
echo "========================================"
echo "  INJECTION COMPLETE"
echo "========================================"
echo ""
echo "  Scenario: Security Group Lockout"
echo "  Security group $SG_ID has no inbound rules."
echo "  All connections to port 5432 are now blocked."
echo ""
echo "  Backup saved to: $BACKUP_FILE"
echo "  (Do not look at this during the exercise!)"
echo ""
echo "  Now open: survive/01-security-group-lockout/runbook.md"
echo "========================================"
