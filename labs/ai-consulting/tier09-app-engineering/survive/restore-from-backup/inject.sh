#!/usr/bin/env bash
# SURVIVE inject: data loss - prove your backup actually restores.
#
# What this simulates: a bad migration / fat-fingered DELETE wipes the knowledge
# base. This is the disaster a backup exists for. The drill: you HAVE a backup;
# now prove it works by actually restoring it. A backup you have never restored
# is a guess, not a safety net.
#
# What this does:
#   1. Ensures there is fresh data (seeds if empty), then takes a backup with
#      backup.sh - this is your "last night's backup".
#   2. Simulates the disaster: deletes ALL documents and chunks from the LIVE
#      database. The app can no longer answer anything.
#
# Run as ec2-user, with Project 9 in ~/project9.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR"

export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_NAME="${DB_NAME:-labdb}"
export DB_USER="${DB_USER:-labuser}"
export DB_PASSWORD="${DB_PASSWORD:-labpass}"
PSQL() { PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" "$@"; }

# Make sure there is data to lose. Seed if the tables are empty.
COUNT=$(PSQL -tAc "SELECT count(*) FROM chunks" 2>/dev/null || echo 0)
if [ "${COUNT:-0}" -eq 0 ]; then
  echo "[inject] tables empty - seeding first so there is data to lose"
  PSQL -f sql/seed.sql >/dev/null
fi

echo "[inject] taking a backup (this is your 'last known good')..."
bash ./backup.sh

echo "[inject] SIMULATING DISASTER: deleting all documents and chunks..."
PSQL -v ON_ERROR_STOP=1 -c "DELETE FROM chunks; DELETE FROM documents;"

REMAIN=$(PSQL -tAc "SELECT count(*) FROM chunks")
echo "[inject] DONE. Live knowledge base wiped (chunks now: $REMAIN)."
echo "[inject] The app can no longer answer. Follow runbook.md to restore."
