#!/usr/bin/env bash
# SURVIVE Scenario 06: Monitoring Blind Spot - Validation
# Verifies all alarms and metric filters were restored.
#
# Usage: bash validate.sh

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local status="$2"
  if [[ "$status" == "PASS" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================="
echo "  Validating Scenario 06: Monitoring Blind Spot"
echo "============================================="
echo ""

# Check alarms
REQUIRED_ALARMS=(
  "devops-lab-aurora-cpu-high"
  "devops-lab-aurora-memory-low"
  "devops-lab-aurora-replica-lag-high"
  "devops-lab-aurora-deadlocks"
)

EXISTING_ALARMS=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[*].AlarmName' --output text --region "$REGION" 2>/dev/null)

for ALARM in "${REQUIRED_ALARMS[@]}"; do
  if echo "$EXISTING_ALARMS" | grep -q "$ALARM"; then
    check "Alarm exists: $ALARM" "PASS"
  else
    check "Alarm missing: $ALARM" "FAIL"
  fi
done

# Check metric filters
REQUIRED_FILTERS=(
  "devops-lab-deadlock-count"
  "devops-lab-auth-failures"
  "devops-lab-wraparound-warning"
)

EXISTING_FILTERS=$(aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/$CLUSTER_ID/postgresql \
  --query 'metricFilters[*].filterName' --output text --region "$REGION" 2>/dev/null)

for FILTER in "${REQUIRED_FILTERS[@]}"; do
  if echo "$EXISTING_FILTERS" | grep -q "$FILTER"; then
    check "Metric filter exists: $FILTER" "PASS"
  else
    check "Metric filter missing: $FILTER" "FAIL"
  fi
done

# Check alarm has SNS action configured
CPU_ALARM_ACTIONS=$(aws cloudwatch describe-alarms \
  --alarm-names devops-lab-aurora-cpu-high \
  --query 'MetricAlarms[0].AlarmActions' --output text --region "$REGION" 2>/dev/null || echo "")
if [[ -n "$CPU_ALARM_ACTIONS" && "$CPU_ALARM_ACTIONS" != "None" ]]; then
  check "CPU alarm has notification action" "PASS"
else
  check "CPU alarm has no notification action" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - Monitoring not fully restored"
  exit 1
else
  echo "  STATUS: PASS - All monitoring restored"
  exit 0
fi
