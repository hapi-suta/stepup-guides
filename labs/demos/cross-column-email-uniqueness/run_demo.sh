#!/bin/bash
# ============================================================
#  One-command demo runner
#  Usage: bash run_demo.sh [dbname] [user]
#  Defaults: dbname=postgres  user=postgres
# ============================================================

DB="${1:-postgres}"
USER="${2:-postgres}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "Running setup..."
psql -U "$USER" -d "$DB" -f "$DIR/setup.sql" -q

echo ""
echo "Running test suite..."
echo ""
psql -U "$USER" -d "$DB" -f "$DIR/run_tests.sql" 2>&1 | \
  grep -v "^psql:" | \
  sed 's/^ERROR:  /[BLOCKED] /g'

echo ""
echo "Done."
