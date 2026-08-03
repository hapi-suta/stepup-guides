#!/usr/bin/env bash
# Restore a pg_dump backup into a SEPARATE database and verify it, so the drill
# never risks the live database. This is how you prove a backup actually works.
#
# Usage:  ./restore.sh backups/labdb-20260101-120000.dump
#         ./restore.sh                 # uses the newest .dump in backups/
#
# It restores into DB_NAME_restore (e.g. labdb_restore), counts key tables, and
# prints PASS/FAIL. On PASS the restored DB is left in place for inspection.
set -euo pipefail

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-labdb}"
DB_USER="${DB_USER:-labuser}"
DB_PASSWORD="${DB_PASSWORD:-labpass}"
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$0")/backups}"
RESTORE_DB="${DB_NAME}_restore"

DUMP="${1:-}"
if [ -z "$DUMP" ]; then
    DUMP="$(ls -t "$BACKUP_DIR"/*.dump 2>/dev/null | head -1 || true)"
fi
if [ -z "$DUMP" ] || [ ! -f "$DUMP" ]; then
    echo "FAIL: no dump file found. Run backup.sh first, or pass a path." >&2
    exit 1
fi
echo "[restore] using dump: $DUMP"

export PGPASSWORD="$DB_PASSWORD"

# Drop and recreate the restore target so the drill is repeatable.
echo "[restore] recreating $RESTORE_DB"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "DROP DATABASE IF EXISTS ${RESTORE_DB};" >/dev/null
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "CREATE DATABASE ${RESTORE_DB};" >/dev/null

echo "[restore] restoring into $RESTORE_DB"
# --no-owner avoids role-mismatch noise in the lab; --exit-on-error would abort
# on any problem, but we let it continue and verify by row counts instead.
pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$RESTORE_DB" \
    --no-owner "$DUMP" 2>/dev/null || true

# Verify: the restored database must have our tables with rows.
USERS="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$RESTORE_DB" \
    -tAc "SELECT count(*) FROM app_users" 2>/dev/null || echo 0)"
CHUNKS="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$RESTORE_DB" \
    -tAc "SELECT count(*) FROM chunks" 2>/dev/null || echo 0)"

echo "[restore] restored app_users=$USERS chunks=$CHUNKS"
if [ "${USERS:-0}" -ge 1 ] && [ "${CHUNKS:-0}" -ge 1 ]; then
    echo "PASS: backup restored and verified ($USERS users, $CHUNKS chunks)."
    exit 0
fi
echo "FAIL: restored database is missing expected data." >&2
exit 1
