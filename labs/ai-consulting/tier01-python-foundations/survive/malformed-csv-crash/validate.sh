#!/usr/bin/env bash
# SURVIVE validate: confirm the ingester now survives malformed CSV rows.
#
# PASS conditions:
#   1. Running the ingester exits successfully (does NOT crash) on the file
#      containing a malformed row.
#   2. A dead-letter file exists and contains the malformed row.
#   3. At least one GOOD row from the batch made it into the database.
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

PY=".venv/bin/python"
[ -x "$PY" ] || PY="python3.12"

# Clean any prior good-row so the DB check is meaningful this run.
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb \
  -c "DELETE FROM support_tickets WHERE body = 'Reset email never arrives';" >/dev/null 2>&1 || true
rm -f tickets.deadletter.csv

# 1. The ingester must NOT crash on the malformed file.
if ! "$PY" import_tickets.py tickets.csv > ingest.out 2>&1; then
  echo "--- ingester output ---"; cat ingest.out
  fail "ingester crashed on malformed CSV (should survive bad rows)"
fi
echo "OK: ingester ran to completion without crashing"

# 2. Dead-letter file must exist and hold the malformed row.
if [ ! -f tickets.deadletter.csv ]; then
  fail "no dead-letter file produced - bad rows are not being captured"
fi
if ! grep -q "THIS ROW IS BROKEN" tickets.deadletter.csv; then
  fail "malformed row not found in dead-letter file"
fi
echo "OK: malformed row routed to dead-letter file"

# 3. A good row must have loaded into the database.
COUNT="$(PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -tA \
  -c "SELECT count(*) FROM support_tickets WHERE body = 'Reset email never arrives';" 2>/dev/null || echo 0)"
if [ "${COUNT:-0}" -lt 1 ]; then
  fail "no good row loaded - the batch did not survive the bad row"
fi
echo "OK: good row loaded into the database despite the bad row"

echo "PASS: pipeline survives malformed CSV; good rows load, bad rows dead-lettered."
