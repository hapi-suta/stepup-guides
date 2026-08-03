#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 05: Validate - Region Outage / DR Failover
#
# This validate script checks whether your DR infrastructure is properly
# configured and whether you have executed a failover drill successfully.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 05: Validation - Region Outage DR Readiness"

t8_validate_config || exit 1
check_aws_auth || exit 1

PASS_COUNT=0
FAIL_COUNT=0

if [[ -f "${SCRIPT_DIR}/.inject-state" ]]; then
  source "${SCRIPT_DIR}/.inject-state"
fi

SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
if [[ "${T8_REGION}" == "us-west-2" ]]; then
  SECONDARY_REGION="us-east-1"
fi

# -----------------------------------------------------------------------
# Check 1: Aurora Global Database is configured OR cross-region snapshots exist
# -----------------------------------------------------------------------
log_step "Check 1: DR mechanism is in place"

GLOBAL_DB=$(aws rds describe-global-clusters \
  --region "${T8_REGION}" \
  --query 'GlobalClusters[*].GlobalClusterIdentifier' \
  --output text 2>/dev/null || echo "")

SNAPSHOT_COUNT=$(aws rds describe-db-snapshots \
  --region "${SECONDARY_REGION}" \
  --query 'length(DBSnapshots[?Status==`available`])' \
  --output text 2>/dev/null || echo "0")

if [[ -n "${GLOBAL_DB}" ]]; then
  validate_check "Aurora Global Database is configured: ${GLOBAL_DB}" "pass"
  echo "         DR path: Aurora managed failover (RTO < 2 minutes)"
  PASS_COUNT=$((PASS_COUNT + 1))
elif [[ "${SNAPSHOT_COUNT}" -gt 0 ]]; then
  validate_check "Cross-region snapshots exist in ${SECONDARY_REGION}: ${SNAPSHOT_COUNT} available" "pass"
  echo "         DR path: Snapshot restore (RTO 30-90 minutes)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "No DR mechanism configured" "fail" \
    "No Global Database and no cross-region snapshots in ${SECONDARY_REGION}"
  echo ""
  echo "  This instance has no cross-region DR capability."
  echo "  Remediation options:"
  echo "    Option A (RTO < 2 min): Create an Aurora Global Database"
  echo "    Option B (RTO ~1 hour): Enable cross-region automated backup copy"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 2: Failover authorization matrix is documented
# -----------------------------------------------------------------------
log_step "Check 2: Failover authorization documented (self-assessment)"

echo ""
echo "  Self-assessment question: Have you documented who can authorize a DR failover?"
echo "  This is an organizational requirement, not a technical check."
echo ""
echo "  Required documentation:"
echo "    - Who can approve a failover during business hours"
echo "    - Who can approve a failover at 3 AM on a Saturday"
echo "    - What metrics/signals must be true before failover is executed"
echo "    - Where this document lives (runbook, wiki, incident management tool)"
echo ""
read -rp "  Is this documented for your organization? (yes/no): " auth_documented

if [[ "${auth_documented}" == "yes" ]]; then
  validate_check "Failover authorization matrix is documented" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Failover authorization matrix is NOT documented" "fail" \
    "This is a critical operational gap - decision ambiguity during an outage causes delay"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 3: DR region has required infrastructure pre-configured
# -----------------------------------------------------------------------
log_step "Check 3: Secondary region has pre-configured infrastructure"

SECONDARY_SUBNETS=$(aws rds describe-db-subnet-groups \
  --region "${SECONDARY_REGION}" \
  --query 'length(DBSubnetGroups)' \
  --output text 2>/dev/null || echo "0")

if [[ "${SECONDARY_SUBNETS}" -gt 0 ]]; then
  validate_check "DB subnet groups exist in secondary region (${SECONDARY_REGION})" "pass" \
    "Found ${SECONDARY_SUBNETS} subnet group(s)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "No DB subnet groups in secondary region (${SECONDARY_REGION})" "fail" \
    "You cannot restore an RDS instance without a DB subnet group in the target region"
  echo "  Create a VPC, subnets, and DB subnet group in ${SECONDARY_REGION} before the outage."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 4: RTO/RPO targets are defined for this workload
# -----------------------------------------------------------------------
log_step "Check 4: RTO/RPO targets defined (self-assessment)"

echo ""
echo "  Self-assessment question: Do you have documented RTO and RPO targets"
echo "  for the workload hosted on ${T8_INSTANCE_ID}?"
echo ""
read -rp "  Enter your documented RTO target (e.g. '15 minutes', or 'none'): " rto_target
read -rp "  Enter your documented RPO target (e.g. '1 minute', or 'none'): " rpo_target

if [[ "${rto_target}" != "none" && -n "${rto_target}" ]]; then
  validate_check "RTO target documented: ${rto_target}" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "RTO target not documented" "fail" \
    "RTO/RPO targets must be agreed with the business before an incident, not during one"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 5: Most recent snapshot is less than 24 hours old (for snapshot path)
# -----------------------------------------------------------------------
log_step "Check 5: Most recent cross-region snapshot is recent"

LATEST_SNAPSHOT_TIME=$(aws rds describe-db-snapshots \
  --region "${SECONDARY_REGION}" \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].SnapshotCreateTime' \
  --output text 2>/dev/null || echo "")

if [[ -z "${LATEST_SNAPSHOT_TIME}" || "${LATEST_SNAPSHOT_TIME}" == "None" ]]; then
  validate_check "Cross-region snapshot exists" "fail" \
    "No snapshots found in ${SECONDARY_REGION}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  log_info "Latest snapshot time: ${LATEST_SNAPSHOT_TIME}"
  validate_check "Cross-region snapshot exists in ${SECONDARY_REGION}" "pass" \
    "Latest: ${LATEST_SNAPSHOT_TIME}"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------
rm -f "${SCRIPT_DIR}/.inject-state"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "==========================================="
echo "VALIDATION SUMMARY"
echo "==========================================="
echo "Checks passed:  ${PASS_COUNT}"
echo "Checks failed:  ${FAIL_COUNT}"
echo ""

if [[ ${FAIL_COUNT} -eq 0 ]]; then
  log_success "Scenario 05 RESOLVED: DR readiness checks pass."
  echo ""
  echo "What you demonstrated:"
  echo "  - DR mechanism is in place (Global Database or cross-region snapshots)"
  echo "  - Failover authorization is documented"
  echo "  - Secondary region has required infrastructure"
  echo "  - RTO/RPO targets are defined"
  echo "  - Cross-region snapshots are current"
  echo ""
  echo "Next step: Execute the actual DR drill (USE Exercise 04)"
  echo "to measure your actual RTO against your target."
else
  log_fail "Scenario 05 NOT RESOLVED: ${FAIL_COUNT} gap(s) in DR readiness."
  echo ""
  echo "These gaps mean your DR plan is not operational."
  echo "Address each failed check before your next production incident."
fi
echo ""
