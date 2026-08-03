#!/usr/bin/env bash
# Take a compressed logical backup of labdb with pg_dump.
#
# A backup you have never restored is not a backup - it is a hope. This script
# just captures; restore.sh proves it. Config comes from the environment so the
# same script works in the lab and in production.
#
# Usage:  ./backup.sh            # writes backups/labdb-<timestamp>.dump
#         BACKUP_DIR=/x ./backup.sh
set -euo pipefail

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-labdb}"
DB_USER="${DB_USER:-labuser}"
DB_PASSWORD="${DB_PASSWORD:-labpass}"
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$0")/backups}"

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/${DB_NAME}-${STAMP}.dump"

echo "[backup] dumping $DB_NAME to $OUT"
# -Fc = custom compressed format (restores with pg_restore, supports parallel).
PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_NAME" -Fc -f "$OUT"

SIZE="$(du -h "$OUT" | cut -f1)"
echo "[backup] done: $OUT ($SIZE)"
echo "[backup] REMEMBER: an untested backup is not a backup. Run restore.sh."
