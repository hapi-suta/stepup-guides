#!/usr/bin/env bash
# SURVIVE validate: the ingestion queue is drained and nothing is stuck.
#
# PASS conditions:
#   1. No jobs left in status='queued'.
#   2. No jobs stuck in status='processing'.
#   3. At least the burst documents made it into the chunks table (work done).
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_NAME="${DB_NAME:-labdb}"
export DB_USER="${DB_USER:-labuser}"
export DB_PASSWORD="${DB_PASSWORD:-labpass}"
PSQL() { PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc "$1" 2>/dev/null; }

fail() { echo "FAIL: $1"; exit 1; }

QUEUED=$(PSQL "SELECT count(*) FROM ingest_jobs WHERE status='queued'")
[ "${QUEUED:-1}" = "0" ] || fail "$QUEUED job(s) still queued - queue not drained (is the worker running?)"
echo "OK: no jobs left queued"

STUCK=$(PSQL "SELECT count(*) FROM ingest_jobs WHERE status='processing'")
[ "${STUCK:-1}" = "0" ] || fail "$STUCK job(s) stuck in 'processing' - orphaned job not recovered"
echo "OK: no jobs stuck in processing"

CHUNKS=$(PSQL "SELECT count(*) FROM chunks WHERE source LIKE 'burst-%'")
[ "${CHUNKS:-0}" -ge 1 ] || fail "burst documents were never ingested into chunks"
echo "OK: burst documents ingested ($CHUNKS chunk rows)"

echo "PASS: ingestion queue drained safely, worker healthy."
