#!/usr/bin/env bash
# SURVIVE inject: feed a malformed CSV that crashes a naive ingest CLI.
#
# Simulates a real data-pipeline failure: a batch of records arrives as CSV,
# one row is malformed (wrong column count / bad type), and a naive loader
# crashes on it - losing the entire batch, including the good rows.
#
# What this does:
#   1. Writes a naive CLI ingester (import_tickets.py) that does NO error
#      handling - it will crash on a bad row.
#   2. Writes a tickets.csv that contains good rows and one malformed row.
#
# Run as ec2-user. Requires Project 1 in ~/project1 with the .venv from BUILD.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR"

echo "[inject] writing a naive (no error handling) CSV ingester..."
cat > import_tickets.py <<'PY'
"""Naive CSV ingester - crashes on any bad row. FIX ME in the runbook.

Reads tickets.csv (columns: subject,body,category) and inserts each row.
It assumes every row is perfect. It is not.
"""
import csv
import os
import sys

import psycopg2

DB = dict(
    host=os.environ.get("DB_HOST", "127.0.0.1"),
    dbname=os.environ.get("DB_NAME", "labdb"),
    user=os.environ.get("DB_USER", "labuser"),
    password=os.environ.get("DB_PASSWORD", "labpass"),
)

path = sys.argv[1] if len(sys.argv) > 1 else "tickets.csv"
conn = psycopg2.connect(**DB)
inserted = 0
with conn, conn.cursor() as cur, open(path, newline="") as f:
    reader = csv.reader(f)
    next(reader)  # skip header
    for row in reader:
        subject, body, category = row  # CRASHES if row is not exactly 3 fields
        cur.execute(
            "INSERT INTO support_tickets (subject, body, category) VALUES (%s, %s, %s)",
            (subject, body, category or None),
        )
        inserted += 1
print(f"inserted {inserted} rows")
conn.close()
PY
echo "[inject] wrote import_tickets.py (intentionally fragile)"

echo "[inject] writing tickets.csv with good rows AND one malformed row..."
cat > tickets.csv <<'CSV'
subject,body,category
Cannot reset password,Reset email never arrives,auth
Double charged this month,Invoice shows two payments,billing
THIS ROW IS BROKEN,it has,too,many,commas,and,no,category
Dashboard is slow,Takes forever to load,performance
CSV
echo "[inject] wrote tickets.csv (row 3 is malformed - extra fields)"

echo "[inject] DONE."
echo "[inject] Reproduce the crash with:"
echo "[inject]   cd ~/project1 && .venv/bin/python import_tickets.py tickets.csv"
echo "[inject] Then follow runbook.md to add error handling + a dead-letter file."
