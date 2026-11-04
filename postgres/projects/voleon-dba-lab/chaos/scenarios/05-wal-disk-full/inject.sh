#!/usr/bin/env bash
# =============================================================================
# Scenario 05: WAL Directory Disk Full
# inject.sh - Fill the WAL directory with dummy files until PostgreSQL panics
# =============================================================================
# What breaks: PostgreSQL cannot write new WAL segments. It will PANIC and
#              shut itself down to avoid data corruption. All connections fail.
# Your job:    Identify the disk full condition, clear the dummy files,
#              restart PostgreSQL, and verify WAL is flowing again.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

WAL_DIR="${PG_DATA}/pg_wal"
DUMMY_FILE_PREFIX="chaos05_dummy"
# Fill up to leave only ~50MB free - enough to trigger PG panic without
# permanently breaking the instance.
FILL_TO_FREE_MB=50

log_info "Scenario 05: WAL Directory Disk Full"
log_info "Target: ${WAL_DIR} on ${PRIMARY_HOST}"
echo ""

# Confirm connectivity
log_info "Checking SSH and PostgreSQL connectivity..."
if ! check_ssh "$PRIMARY_HOST"; then
    log_error "Cannot SSH into primary (${PRIMARY_HOST})"
    exit 1
fi
if ! check_pg "$PRIMARY_HOST"; then
    log_error "PostgreSQL is not responding on ${PRIMARY_HOST}"
    exit 1
fi
log_success "Primary is reachable"

# Check current disk usage on the pg_wal filesystem
log_info "Checking current disk usage on pg_wal filesystem..."
DISK_INFO=$(ssh_primary "sudo df -BM --output=avail ${WAL_DIR} | tail -1" 2>/dev/null | tr -d 'M ')
log_info "Available space on pg_wal filesystem: ${DISK_INFO}MB"

if [[ ! "$DISK_INFO" =~ ^[0-9]+$ ]]; then
    log_error "Could not determine available disk space on ${WAL_DIR}"
    exit 1
fi

FILL_MB=$(( DISK_INFO - FILL_TO_FREE_MB ))

if (( FILL_MB <= 0 )); then
    log_warn "Disk is already near full (${DISK_INFO}MB available). Injection may not be needed."
    FILL_MB=100
fi

log_info "Will write ${FILL_MB}MB of dummy files to ${WAL_DIR}..."
echo ""
log_warn "Writing dummy files to fill the WAL directory..."

# Write dummy files in 100MB chunks (dd bs=1M count=X)
REMAINING=$FILL_MB
CHUNK=100
FILE_NUM=1
while (( REMAINING > 0 )); do
    THIS_CHUNK=$(( REMAINING < CHUNK ? REMAINING : CHUNK ))
    FILENAME="${WAL_DIR}/${DUMMY_FILE_PREFIX}_$(printf '%03d' $FILE_NUM)"
    ssh_primary "sudo dd if=/dev/zero of=${FILENAME} bs=1M count=${THIS_CHUNK} status=none 2>/dev/null"
    (( REMAINING -= THIS_CHUNK ))
    (( FILE_NUM++ ))
    log_info "Written file ${FILE_NUM} (${THIS_CHUNK}MB) - ${REMAINING}MB remaining..."
done

echo ""
log_warn "Forcing a PostgreSQL checkpoint to trigger WAL write pressure..."
ssh_primary "sudo -u postgres ${PG_BIN}/psql -c 'CHECKPOINT;' 2>/dev/null" || true

sleep 3

# Check if PostgreSQL is still up (it may have panicked already)
if check_pg "$PRIMARY_HOST" 2>/dev/null; then
    log_info "PostgreSQL is still running. Generating WAL activity to trigger the disk-full error..."
    # Run a quick insert loop to generate WAL and hit the limit
    ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
        -c \"INSERT INTO quant.instruments (symbol, name, asset_class) \
        SELECT 'WAL_FILL_' || i, 'WAL Fill Test', 'equity' \
        FROM generate_series(1, 500) i;\" 2>/dev/null" || true
    sleep 2
fi

CURRENT_FREE=$(ssh_primary "sudo df -BM --output=avail ${WAL_DIR} | tail -1" 2>/dev/null | tr -d 'M ' || echo "unknown")
log_info "Current free space on pg_wal filesystem: ${CURRENT_FREE}MB"

echo ""
if check_pg "$PRIMARY_HOST" 2>/dev/null; then
    log_warn "PostgreSQL is still up. Disk may not be fully exhausted."
    log_warn "It will hit errors when WAL segments need recycling or archiving."
else
    log_success "PostgreSQL has shut down due to disk pressure - injection successful"
fi

echo ""
echo "  The pg_wal filesystem on ${PRIMARY_HOST} is nearly full."
echo "  Dummy files are at: ${WAL_DIR}/${DUMMY_FILE_PREFIX}_*"
echo ""
echo "  Your tasks:"
echo "    1. SSH into ${PRIMARY_HOST} and check disk: df -h ${WAL_DIR}"
echo "    2. Identify the dummy files: ls -lh ${WAL_DIR}/${DUMMY_FILE_PREFIX}*"
echo "    3. Remove the dummy files: sudo rm ${WAL_DIR}/${DUMMY_FILE_PREFIX}*"
echo "    4. Check PostgreSQL logs for the PANIC or disk-full error"
echo "    5. Start PostgreSQL if it stopped: sudo systemctl start postgresql-${PG_VERSION}"
echo "    6. Verify WAL is flowing: check pg_current_wal_lsn() and replication lag"
echo ""
echo "  IMPORTANT: Also clean up test rows from quant.instruments:"
echo "    DELETE FROM quant.instruments WHERE symbol LIKE 'WAL_FILL_%';"
echo ""
echo "  When done: ./chaos.sh validate 05-wal-disk-full"
