#!/usr/bin/env bash
# SURVIVE inject: the background ingestion queue backs up and a worker "dies".
#
# What this simulates: an admin uploads a burst of documents, but the worker
# process is down (crashed, OOM-killed, deploy left it stopped). Jobs pile up
# in status='queued', and one job is stuck in 'processing' because the worker
# died mid-job (the classic "orphaned in-flight job" that never completes).
#
# What this does:
#   1. Makes sure no worker is running (kills any).
#   2. Enqueues several documents directly into ingest_jobs.
#   3. Marks one job 'processing' with an old timestamp to mimic a job the dead
#      worker had claimed but never finished.
#
# Run as ec2-user, with Project 9 in ~/project9 and the database seeded.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR"

# Load DB config from .env if present, else fall back to lab defaults.
export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_NAME="${DB_NAME:-labdb}"
export DB_USER="${DB_USER:-labuser}"
export DB_PASSWORD="${DB_PASSWORD:-labpass}"
PSQL() { PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" "$@"; }

echo "[inject] stopping any running worker..."
pkill -f "worker.py" 2>/dev/null || true
sleep 1

echo "[inject] enqueuing a burst of documents..."
PSQL -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO ingest_jobs (title, source, body, access_level) VALUES
  ('Burst Doc 1', 'burst-1.txt', 'Backups run nightly at 2am UTC and are retained for 30 days.', 1),
  ('Burst Doc 2', 'burst-2.txt', 'All production access requires multi-factor authentication.', 1),
  ('Burst Doc 3', 'burst-3.txt', 'Change requests must be approved by a second engineer.', 1),
  ('Burst Doc 4', 'burst-4.txt', 'Customer data may not leave the EU region.', 2);

-- One job the dead worker had claimed but never finished: stuck 'processing',
-- with an updated_at far in the past so a monitor would flag it as stale.
INSERT INTO ingest_jobs (title, source, body, access_level, status, updated_at)
VALUES ('Orphaned Doc', 'orphan.txt', 'This job was mid-flight when the worker died.', 1,
        'processing', now() - interval '1 hour');
SQL

QUEUED=$(PSQL -tAc "SELECT count(*) FROM ingest_jobs WHERE status='queued'")
STUCK=$(PSQL -tAc "SELECT count(*) FROM ingest_jobs WHERE status='processing'")
echo "[inject] DONE. queued=$QUEUED  stuck-in-processing=$STUCK  (worker is DOWN)"
echo "[inject] Follow runbook.md: requeue the orphan, start the worker, drain."
