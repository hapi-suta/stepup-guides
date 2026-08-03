#!/usr/bin/env bash
# survive/04-storage-full/validate.sh
# Verifies storage headroom is restored and the instance is healthy.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/04-storage-full/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

# Minimum free storage required to pass (2 GB in bytes)
MIN_FREE_BYTES=2147483648

echo ""
echo "========================================"
echo "  VALIDATE: Storage Full"
echo "========================================"
echo ""

# Check 1 - Instance is available
info "Check 1: RDS instance is available"
STATUS=$(rds_instance_status "$RDS_INSTANCE_ID")
if [[ "$STATUS" == "available" ]]; then
  check "RDS instance $RDS_INSTANCE_ID is available" "pass"
else
  check "RDS instance status: $STATUS (expected: available)" "fail"
fi

# Check 2 - Can connect to the database
info "Check 2: psql connection works"
if pg_health_check; then
  check "psql connection and query successful" "pass"
else
  check "psql connection failed" "fail" \
    "Storage may be completely full. Try: aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_ID --allocated-storage 50 --apply-immediately"
fi

# Check 3 - Bloat table is gone
info "Check 3: Bloat table has been removed"
BLOAT_EXISTS=$(rds_exec "SELECT EXISTS(SELECT 1 FROM pg_tables WHERE tablename='storage_bloat' AND schemaname='public')" 2>/dev/null || echo "error")
if [[ "$BLOAT_EXISTS" == "f" ]]; then
  check "Bloat table 'storage_bloat' has been dropped" "pass"
elif [[ "$BLOAT_EXISTS" == "t" ]]; then
  check "Bloat table 'storage_bloat' still exists" "fail" \
    "Run in psql: DROP TABLE storage_bloat;"
else
  warn "Could not check bloat table existence (psql connection may have failed)"
fi

# Check 4 - Free storage is above minimum threshold
info "Check 4: Free storage is above 2 GB"
FREE_BYTES=$(rds_free_storage_bytes "$RDS_INSTANCE_ID" 2>/dev/null || echo "0")
FREE_GB=$(echo "$FREE_BYTES" | python3 -c "import sys; b=float(sys.stdin.read().strip() or 0); print(f'{b/1073741824:.2f}')" 2>/dev/null || echo "0")

if python3 -c "import sys; exit(0 if float('${FREE_BYTES}') >= ${MIN_FREE_BYTES} else 1)" 2>/dev/null; then
  check "Free storage: ${FREE_GB} GB (above 2 GB minimum)" "pass"
else
  check "Free storage: ${FREE_GB} GB (below 2 GB minimum)" "fail" \
    "Either drop more tables or expand storage: aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_ID --allocated-storage 50 --apply-immediately"
fi

# Check 5 - Write operations work
info "Check 5: Write operations succeed (INSERT + DELETE)"
WRITE_TEST=$(rds_exec "
  CREATE TEMP TABLE _validate_write_test (id INT);
  INSERT INTO _validate_write_test VALUES (1);
  SELECT count(*) FROM _validate_write_test;
  DROP TABLE _validate_write_test;
" 2>/dev/null || echo "failed")

if [[ "$WRITE_TEST" == "1" ]]; then
  check "Write operations (INSERT) succeed" "pass"
else
  check "Write operations failed" "fail" \
    "Database may still be in read-only mode due to storage. Check FreeStorageSpace."
fi

# Check 6 - Autoscaling is enabled (informational)
info "Check 6: Storage autoscaling enabled (recommended best practice)"
MAX_STORAGE=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --query "DBInstances[0].MaxAllocatedStorage" \
  --output text 2>/dev/null || echo "None")

if [[ "$MAX_STORAGE" != "None" && "$MAX_STORAGE" != "" && "$MAX_STORAGE" != "0" ]]; then
  check "Storage autoscaling enabled (max: ${MAX_STORAGE} GB)" "pass"
else
  warn "Storage autoscaling is NOT enabled. Recommended to enable it:"
  warn "  aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_ID --max-allocated-storage 100 --apply-immediately"
  (( _CHECK_PASS++ )) || true  # Not a hard fail - just a recommendation
fi

echo ""
check_summary
