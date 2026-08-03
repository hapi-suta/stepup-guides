#!/usr/bin/env bash
# SURVIVE validate: the backup restored the lost data.
#
# PASS conditions:
#   1. A backup file exists in backups/.
#   2. The restore drill (restore.sh into a separate DB) PASSES - the backup is
#      provably restorable.
#   3. The LIVE database has its documents and chunks back (recovery complete).
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_NAME="${DB_NAME:-labdb}"
export DB_USER="${DB_USER:-labuser}"
export DB_PASSWORD="${DB_PASSWORD:-labpass}"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
PSQL() { PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc "$1" 2>/dev/null; }

fail() { echo "FAIL: $1"; exit 1; }

# 1. A backup must exist.
DUMP="$(ls -t "$BACKUP_DIR"/*.dump 2>/dev/null | head -1 || true)"
[ -n "$DUMP" ] && [ -f "$DUMP" ] || fail "no backup file found in $BACKUP_DIR"
echo "OK: backup file present ($(basename "$DUMP"))"

# 2. The restore drill must pass (backup is restorable into a fresh DB).
if bash ./restore.sh "$DUMP" >/tmp/restore_drill.out 2>&1; then
  echo "OK: restore drill passed (backup restores into a fresh database)"
else
  cat /tmp/restore_drill.out
  fail "restore drill did not PASS - the backup does not restore cleanly"
fi

# 3. The LIVE database must have its data back.
DOCS=$(PSQL "SELECT count(*) FROM documents")
CHUNKS=$(PSQL "SELECT count(*) FROM chunks")
[ "${DOCS:-0}" -ge 1 ] || fail "live documents table is still empty - recovery incomplete"
[ "${CHUNKS:-0}" -ge 1 ] || fail "live chunks table is still empty - recovery incomplete"
echo "OK: live database recovered (documents=$DOCS, chunks=$CHUNKS)"

echo "PASS: backup verified and live data restored."
