#!/usr/bin/env bash
# survive/04-storage-full/inject.sh
# Creates a large temporary table to fill storage and trigger low-storage alarms.
# Uses 80% of available free storage to simulate near-full conditions safely.
#
# NOTE: This inject creates data inside PostgreSQL, not at the OS level.
# On RDS, we cannot write directly to the filesystem, so we use a large table.
#
# Usage:
#   export STUDENT_ENV_FILE=~/.suta/aws-rds-tier1.env
#   bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/04-storage-full/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

source "$LAB_DIR/config.sh"
source "$LAB_DIR/lib/common.sh"

echo ""
echo "========================================"
echo "  INJECT: Storage Full"
echo "========================================"
echo ""

# Step 1 - Confirm instance is available
info "Confirming RDS instance is available..."
if ! rds_is_available "$RDS_INSTANCE_ID"; then
  fail "Instance $RDS_INSTANCE_ID is not available. Aborting."
  exit 1
fi
success "Instance is available"

# Step 2 - Check current free storage from CloudWatch
info "Checking current free storage space..."
FREE_BYTES=$(rds_free_storage_bytes "$RDS_INSTANCE_ID")
FREE_GB=$(echo "$FREE_BYTES" | python3 -c "import sys; b=float(sys.stdin.read().strip() or 0); print(f'{b/1073741824:.1f}')" 2>/dev/null || echo "unknown")
info "Free storage: approximately ${FREE_GB} GB"

# Step 3 - Check current database size via psql
info "Checking current database size..."
DB_SIZE=$(rds_exec "SELECT pg_size_pretty(pg_database_size(current_database()))")
info "Current database size: $DB_SIZE"

# Step 4 - Calculate how much data to insert (fill to ~85% of total)
# On a 20 GB gp3 instance with a fresh database, we can safely insert ~12 GB
# We use generate_series to create a large table of random-ish data
# Each row in the bloat table is approximately 250-300 bytes
# 40 million rows ~= 10-12 GB

info "Creating bloat table to fill storage..."

# Create the table and fill it in chunks to avoid a single long transaction
rds_exec "DROP TABLE IF EXISTS storage_bloat" >/dev/null 2>&1 || true

rds_exec "CREATE UNLOGGED TABLE storage_bloat (
    id BIGSERIAL,
    payload TEXT
)" >/dev/null

# Insert data in 5 chunks of 8 million rows each (approximately 2 GB per chunk)
# Stop if free storage drops below 1 GB to avoid actually filling the disk
info "Inserting data in chunks (this takes 5-10 minutes)..."
for chunk in 1 2 3 4 5; do
  # Check free space before each chunk
  FREE_NOW=$(rds_free_storage_bytes "$RDS_INSTANCE_ID" 2>/dev/null || echo "999999999999")
  FREE_NOW_GB=$(echo "$FREE_NOW" | python3 -c "import sys; b=float(sys.stdin.read().strip() or 999); print(b/1073741824)" 2>/dev/null || echo "99")

  if python3 -c "import sys; exit(0 if float('${FREE_NOW_GB}') < 1.5 else 1)" 2>/dev/null; then
    warn "Free storage below 1.5 GB. Stopping insert to protect instance."
    break
  fi

  info "  Inserting chunk $chunk/5 (current free space: ${FREE_NOW_GB} GB)..."
  rds_exec "INSERT INTO storage_bloat (payload)
            SELECT repeat(md5(i::text), 8)
            FROM generate_series(1, 8000000) AS s(i)" >/dev/null
  success "  Chunk $chunk complete"
done

# Step 5 - Show final table size
BLOAT_SIZE=$(rds_exec "SELECT pg_size_pretty(pg_total_relation_size('storage_bloat'))")
info "Bloat table size: $BLOAT_SIZE"

# Step 6 - Get updated free storage
FREE_BYTES_AFTER=$(rds_free_storage_bytes "$RDS_INSTANCE_ID" 2>/dev/null || echo "0")
FREE_GB_AFTER=$(echo "$FREE_BYTES_AFTER" | python3 -c "import sys; b=float(sys.stdin.read().strip() or 0); print(f'{b/1073741824:.1f}')" 2>/dev/null || echo "unknown")

echo ""
echo "========================================"
echo "  INJECTION COMPLETE"
echo "========================================"
echo ""
echo "  Scenario: Storage Full"
echo "  A large unlogged table 'storage_bloat' was created in $DB_NAME."
echo "  Bloat table size: $BLOAT_SIZE"
echo "  Free storage remaining: ~${FREE_GB_AFTER} GB"
echo ""
echo "  CloudWatch FreeStorageSpace alarm may take 5-10 minutes to trigger."
echo "  You can check: AWS Console > RDS > suta-rds-lab > Monitoring tab"
echo ""
echo "  Now open: survive/04-storage-full/runbook.md"
echo "========================================"
