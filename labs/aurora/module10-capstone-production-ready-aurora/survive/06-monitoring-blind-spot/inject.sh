#!/usr/bin/env bash
# SURVIVE Scenario 06: Monitoring Blind Spot
# Injects: Deletes critical CloudWatch alarms and log metric filters,
#          then generates events that should trigger alerts.
# Idempotent: Safe to run multiple times.
#
# Usage: bash inject.sh
# Requires: AWS CLI configured

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================="
echo "  SURVIVE Scenario 06: Monitoring Blind Spot"
echo "============================================="
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Step 1: Delete critical alarms
echo "Deleting critical CloudWatch alarms..."

ALARMS_TO_DELETE=(
  "devops-lab-aurora-cpu-high"
  "devops-lab-aurora-memory-low"
  "devops-lab-aurora-replica-lag-high"
  "devops-lab-aurora-deadlocks"
)

for ALARM in "${ALARMS_TO_DELETE[@]}"; do
  aws cloudwatch delete-alarms \
    --alarm-names "$ALARM" \
    --region "$REGION" 2>/dev/null || true
  echo "  Deleted alarm: $ALARM"
done

echo ""

# Step 2: Delete log metric filters
echo "Deleting log metric filters..."

FILTERS_TO_DELETE=(
  "devops-lab-deadlock-count"
  "devops-lab-auth-failures"
  "devops-lab-wraparound-warning"
)

for FILTER in "${FILTERS_TO_DELETE[@]}"; do
  aws logs delete-metric-filter \
    --log-group-name /aws/rds/cluster/$CLUSTER_ID/postgresql \
    --filter-name "$FILTER" \
    --region "$REGION" 2>/dev/null || true
  echo "  Deleted metric filter: $FILTER"
done

echo ""
echo "YOUR MISSION:"
echo "  1. Discover which alarms are missing (compare against Build 04)"
echo "  2. Discover which metric filters are missing"
echo "  3. Recreate ALL missing alarms with correct thresholds"
echo "  4. Recreate ALL missing metric filters"
echo "  5. Verify all monitoring is restored"
echo "  6. Document what incidents would have been missed"
echo ""
echo "DELETED ALARMS:"
for ALARM in "${ALARMS_TO_DELETE[@]}"; do
  echo "  - $ALARM"
done
echo ""
echo "DELETED METRIC FILTERS:"
for FILTER in "${FILTERS_TO_DELETE[@]}"; do
  echo "  - $FILTER"
done
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
