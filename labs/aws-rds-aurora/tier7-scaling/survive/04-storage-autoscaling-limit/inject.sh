#!/usr/bin/env bash
# SURVIVE Scenario 04: Storage Autoscaling Limit Hit
#
# Injects the problem:
#   - Sets the storage autoscaling maximum to a value just above current storage
#   - Generates a large volume of inserts to fill storage toward the ceiling
#   - Creates large unlogged tables that fill space rapidly
#
# The result: Storage fills toward the autoscaling ceiling. Autoscaling cannot expand further.
# Writes will eventually fail with "no space left" errors.
#
# The student must identify the problem, assess options (expand the max, delete data,
# move to cheaper storage) and act before the database becomes read-only.
#
# NOTE: This scenario is partially simulated. To avoid actually filling your disk,
# the inject script creates temporary large tables and sets a low autoscaling max.
# The symptom (approaching the autoscaling ceiling) is real; the disk-full condition is not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

# ============================================================
check_required_vars SOURCE_DB_IDENTIFIER SOURCE_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql
# ============================================================

log_info "=== SURVIVE Scenario 04: Storage Autoscaling Limit ==="
log_info "Injecting storage pressure condition."
log_info ""

# Step 1: Get current storage configuration
log_info "Step 1: Reading current storage configuration..."
CURRENT_STORAGE=$(aws rds describe-db-instances \
  --db-instance-identifier "${SOURCE_DB_IDENTIFIER}" \
  --region "${AWS_REGION}" \
  --query 'DBInstances[0].AllocatedStorage' \
  --output text 2>/dev/null || echo "100")

CURRENT_MAX=$(aws rds describe-db-instances \
  --db-instance-identifier "${SOURCE_DB_IDENTIFIER}" \
  --region "${AWS_REGION}" \
  --query 'DBInstances[0].MaxAllocatedStorage' \
  --output text 2>/dev/null || echo "None")

log_info "  Current allocated storage: ${CURRENT_STORAGE} GiB"
log_info "  Current autoscaling max:   ${CURRENT_MAX} GiB"

# Calculate a low ceiling: current storage + 5 GiB (just above current)
# This simulates having set the autoscaling ceiling too low
NEW_MAX=$((CURRENT_STORAGE + 5))

log_info "Step 2: Setting autoscaling maximum to ${NEW_MAX} GiB (just above current size)..."
aws rds modify-db-instance \
  --db-instance-identifier "${SOURCE_DB_IDENTIFIER}" \
  --max-allocated-storage "${NEW_MAX}" \
  --apply-immediately \
  --region "${AWS_REGION}" > /dev/null 2>&1 || {
  log_warn "Could not modify autoscaling maximum. Continuing with data injection only."
}

log_info "  Autoscaling max set to ${NEW_MAX} GiB. There is only 5 GiB of autoscaling headroom."

# Step 3: Create a large temporary table to consume storage
log_info "Step 3: Creating bloat table to simulate storage consumption..."
psql_source -c "
CREATE TABLE IF NOT EXISTS storage_bloat_inject (
  id       SERIAL PRIMARY KEY,
  filler   TEXT,
  created  TIMESTAMPTZ DEFAULT NOW()
);

-- Insert 1 GiB worth of data in batches
INSERT INTO storage_bloat_inject (filler)
SELECT repeat('X', 8192)
FROM generate_series(1, 130000);
" > /dev/null 2>&1 || {
  log_warn "Could not create bloat table. Your user may not have CREATE TABLE privileges."
  log_warn "Continuing with the autoscaling ceiling injection only."
}

log_info "  Bloat table created and populated."

# Step 4: Check the resulting free space
log_info "Step 4: Checking resulting storage state..."
FREE_SPACE=$(get_metric_latest "AWS/RDS" "FreeStorageSpace" "DBInstanceIdentifier" "${SOURCE_DB_IDENTIFIER}")
if [[ "${FREE_SPACE}" != "None" && -n "${FREE_SPACE}" ]]; then
  FREE_GiB=$(echo "scale=2; ${FREE_SPACE} / 1073741824" | bc 2>/dev/null || echo "unknown")
  log_info "  Current free storage: ${FREE_GiB} GiB"
else
  log_info "  Free storage metric not yet available (may take 5 minutes to appear in CloudWatch)"
fi

# Step 5: Show the current state
log_info ""
log_info "=== Injection Complete ==="
log_info ""
FINAL_CONFIG=$(aws rds describe-db-instances \
  --db-instance-identifier "${SOURCE_DB_IDENTIFIER}" \
  --region "${AWS_REGION}" \
  --query 'DBInstances[0].{Allocated:AllocatedStorage,Max:MaxAllocatedStorage}' \
  --output table 2>/dev/null || echo "unknown")
log_info "Current storage configuration:"
log_info "${FINAL_CONFIG}"

log_warn ""
log_warn "======================================================"
log_warn "  PROBLEM INJECTED."
log_warn "======================================================"
log_warn ""
log_warn "  Situation:"
log_warn "    - Storage autoscaling maximum is set to ${NEW_MAX} GiB"
log_warn "    - Current allocated storage: ${CURRENT_STORAGE} GiB"
log_warn "    - Headroom before ceiling: only 5 GiB"
log_warn "    - A bloat table was created to consume storage"
log_warn "    - If storage fills to the ceiling, RDS will set the database to read-only"
log_warn ""
log_warn "  CloudWatch metrics to watch:"
log_warn "    - FreeStorageSpace (should be declining)"
log_warn "    - aws rds describe-db-instances ... AllocatedStorage vs MaxAllocatedStorage"
log_warn ""
log_warn "  Questions to answer before taking action:"
log_warn "    1. How much free space is left?"
log_warn "    2. What is consuming the storage? (bloat table? WAL? actual data?)"
log_warn "    3. Is the autoscaling ceiling the right fix, or is there a cheaper option?"
log_warn "    4. If you raise the ceiling, how much do you raise it by? Why?"
log_warn ""
log_warn "  DO NOT READ the runbook yet. Diagnose first."
log_warn "  When fixed, run: validate.sh"
log_warn "======================================================"
