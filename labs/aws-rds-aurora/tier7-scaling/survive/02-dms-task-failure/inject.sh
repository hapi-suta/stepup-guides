#!/usr/bin/env bash
# SURVIVE Scenario 02: DMS Migration Task Failure
#
# Injects the problem:
#   - Modifies target table to have an incompatible column (simulates schema drift)
#   - Adds a NOT NULL constraint on the target that the source does not satisfy
#   - Stops the DMS task if it is running, then starts it so it fails on load
#
# The result: DMS task enters FAILED state. Data stops flowing.
# The student must diagnose the failure, fix the schema, and resume the task.
#
# Prerequisites: A DMS task must exist (created in Build 06 or USE 04).
# Set DMS_TASK_ARN in config.sh before running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

# ============================================================
check_required_vars DMS_TASK_ARN SOURCE_DB_HOST TARGET_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql
# ============================================================

log_info "=== SURVIVE Scenario 02: DMS Task Failure ==="
log_info "Injecting schema incompatibility on the target to cause DMS task failure."
log_info ""

# Step 1: Record the current DMS task status
TASK_STATUS=$(aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'ReplicationTasks[0].Status' \
  --output text 2>/dev/null || echo "unknown")

log_info "Current DMS task status: ${TASK_STATUS}"

# Step 2: Stop the task if it is running (so we can inject the schema change)
if [[ "${TASK_STATUS}" == "running" ]]; then
  log_info "Stopping DMS task to inject schema change..."
  aws dms stop-replication-task \
    --replication-task-arn "${DMS_TASK_ARN}" \
    --region "${AWS_REGION}" > /dev/null

  log_info "Waiting for task to stop..."
  sleep 30

  for attempt in {1..20}; do
    TASK_STATUS=$(aws dms describe-replication-tasks \
      --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
      --region "${AWS_REGION}" \
      --query 'ReplicationTasks[0].Status' \
      --output text 2>/dev/null || echo "unknown")
    if [[ "${TASK_STATUS}" == "stopped" ]]; then
      break
    fi
    log_info "  Task status: ${TASK_STATUS}... waiting."
    sleep 10
  done
fi

# Step 3: Inject schema incompatibility on the target
# Add a NOT NULL column to orders that DMS won't know how to populate
log_info "Injecting schema incompatibility on target database..."
psql_target -c "
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS required_approval_code VARCHAR(20) NOT NULL DEFAULT '';
  ALTER TABLE orders ALTER COLUMN required_approval_code DROP DEFAULT;
" > /dev/null 2>&1 || {
  log_warn "Could not modify target table. Trying alternative injection."
  # Alternative: remove a column that DMS expects
  psql_target -c "
    ALTER TABLE orders ADD COLUMN IF NOT EXISTS fake_required_field INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE orders ALTER COLUMN fake_required_field DROP DEFAULT;
  " > /dev/null 2>&1 || true
}

log_info "  Schema change applied. Target now has incompatibility with source."
log_info "  The target 'orders' table has a NOT NULL column with no default."
log_info "  DMS will fail when it tries to insert rows without this column."

# Step 4: Truncate some target data to force a full-load retry
log_info "Truncating sample of target data to force DMS to reload affected rows..."
psql_target -c "
  DELETE FROM orders WHERE order_id IN (
    SELECT order_id FROM orders ORDER BY RANDOM() LIMIT 500
  );
" > /dev/null 2>&1 || true

# Step 5: Restart the DMS task to trigger the failure
log_info "Restarting DMS task to trigger the schema conflict..."
aws dms start-replication-task \
  --replication-task-arn "${DMS_TASK_ARN}" \
  --start-replication-task-type reload-target \
  --region "${AWS_REGION}" > /dev/null 2>/dev/null || {
  aws dms start-replication-task \
    --replication-task-arn "${DMS_TASK_ARN}" \
    --start-replication-task-type resume-processing \
    --region "${AWS_REGION}" > /dev/null 2>/dev/null || true
}

log_info "DMS task restarted. Waiting 60 seconds for it to encounter the error..."
sleep 60

FINAL_STATUS=$(aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'ReplicationTasks[0].{Status:Status,Reason:StopReason}' \
  --output table 2>/dev/null || echo "unknown")

log_info "Final DMS task state:"
log_info "${FINAL_STATUS}"

log_warn ""
log_warn "======================================================"
log_warn "  PROBLEM INJECTED."
log_warn "======================================================"
log_warn ""
log_warn "  The DMS task has encountered a schema conflict."
log_warn "  Data migration has stopped. Check for:"
log_warn ""
log_warn "  1. DMS task status and error messages"
log_warn "     aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=${DMS_TASK_ARN} --region ${AWS_REGION}"
log_warn ""
log_warn "  2. DMS task logs in CloudWatch"
log_warn "     aws logs filter-log-events --log-group-name dms-tasks-... --filter-pattern ERROR"
log_warn ""
log_warn "  3. Schema differences between source and target"
log_warn "     Compare: SELECT column_name, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'orders'"
log_warn ""
log_warn "  DO NOT READ the runbook yet. Diagnose first."
log_warn "  When fixed, run: validate.sh"
log_warn "======================================================"
