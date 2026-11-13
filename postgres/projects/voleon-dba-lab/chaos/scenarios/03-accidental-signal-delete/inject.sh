#!/usr/bin/env bash
# =============================================================================
# Scenario 03: Accidental Signal Delete
# inject.sh - Delete all rows from the current month's signals partition
# =============================================================================
# What breaks: Trading signals for the current month are gone. The quant
#              research team is getting wrong counts. Downstream pipelines
#              that depend on recent signals are broken.
# Your job:    Identify what was deleted, restore the data from pgBackRest
#              PITR or from a backup, verify row counts match expectations.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Scenario 03: Accidental Signal Delete"
log_info "Target: quant.signals partition for current month on ${PRIMARY_HOST}"
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

# Determine the current partition name (signals is partitioned by month)
CURRENT_MONTH=$(date '+%Y_%m')
PARTITION_NAME="signals_${CURRENT_MONTH}"

log_info "Checking for partition: quant.${PARTITION_NAME}..."
PARTITION_EXISTS=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace \
    WHERE n.nspname = 'quant' AND c.relname = '${PARTITION_NAME}';\"" 2>/dev/null | tr -d '[:space:]')

if [[ "$PARTITION_EXISTS" == "0" ]]; then
    log_warn "Partition quant.${PARTITION_NAME} does not exist."
    log_warn "Falling back to deleting all rows from quant.signals (most recent 1000)."
    PARTITION_NAME="signals"
    DELETE_SQL="DELETE FROM quant.signals WHERE id IN (SELECT id FROM quant.signals ORDER BY generated_at DESC LIMIT 1000)"
else
    DELETE_SQL="DELETE FROM quant.${PARTITION_NAME}"
fi

# Record row count before deletion
ROW_COUNT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM quant.${PARTITION_NAME};\"" 2>/dev/null | tr -d '[:space:]')

log_info "Current row count in quant.${PARTITION_NAME}: ${ROW_COUNT}"
echo ""

log_warn "Executing DELETE on quant.${PARTITION_NAME}..."
log_warn "SQL: ${DELETE_SQL}"
echo ""

ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} \
    -c \"${DELETE_SQL};\""

echo ""
# Confirm deletion
AFTER_COUNT=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -d ${PG_DB} -t \
    -c \"SELECT COUNT(*) FROM quant.${PARTITION_NAME};\"" 2>/dev/null | tr -d '[:space:]')

log_success "Deletion complete. Rows before: ${ROW_COUNT}  Rows after: ${AFTER_COUNT}"

echo ""
echo "  ${ROW_COUNT} rows have been deleted from quant.${PARTITION_NAME}."
echo "  The data still exists in pgBackRest backups and WAL archives."
echo ""
echo "  Your tasks:"
echo "    1. Confirm what was deleted and when (check pg_stat_activity, logs)"
echo "    2. Identify the backup to restore from (pgbackrest info --stanza=${PGBACKREST_STANZA})"
echo "    3. Perform a PITR restore to just before the DELETE"
echo "       OR restore the table from a logical backup if available"
echo "    4. Verify row count is restored to ~${ROW_COUNT}"
echo "    5. Confirm downstream pipelines are healthy"
echo ""
echo "  pgBackRest stanza: ${PGBACKREST_STANZA}"
echo "  Repo path:         ${PGBACKREST_REPO}"
echo ""
echo "  When done: ./chaos.sh validate 03-accidental-signal-delete"
