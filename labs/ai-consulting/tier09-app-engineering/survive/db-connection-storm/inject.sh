#!/usr/bin/env bash
# SURVIVE inject: a database connection storm under load.
#
# What this simulates: a code change replaced the connection POOL with a naive
# "open a new connection per request, and forget to close it" pattern. Under a
# burst of traffic the app opens more and more connections until PostgreSQL
# refuses new ones ("too many clients already") and requests start failing.
#
# What this does:
#   1. Backs up db.py.
#   2. Overwrites get_conn() with a leaky, non-pooled version.
#   3. Restarts the API with a TINY PostgreSQL-side ceiling so the storm is
#      reproducible on a small box: it sets the app's effective limit low by
#      pointing every request at its own connection with no pool cap.
#   4. Fires a burst of concurrent requests to trigger the failure.
#
# Run as ec2-user, with Project 9 in ~/project9 and the .venv from BUILD.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR"

echo "[inject] backing up db.py -> db.py.orig"
cp db.py db.py.orig

echo "[inject] replacing the pool with a LEAKY per-request connection..."
# get_conn now opens a brand-new raw connection every call and NEVER returns it
# to any pool (the yielded conn is not closed). This is the leak.
cat > db.py <<'PYEOF'
"""INJECTED (db-connection-storm): leaky, non-pooled connections.

BUG: get_conn opens a fresh connection on every call and never closes it.
Under load these accumulate until PostgreSQL refuses new connections.
The original pooled implementation is in db.py.orig.
"""
from __future__ import annotations

import contextlib
import os

import psycopg2


def _dsn() -> dict:
    return {
        "host": os.environ.get("DB_HOST", "127.0.0.1"),
        "port": os.environ.get("DB_PORT", "5432"),
        "dbname": os.environ.get("DB_NAME", "labdb"),
        "user": os.environ.get("DB_USER", "labuser"),
        "password": os.environ.get("DB_PASSWORD", "labpass"),
        "connect_timeout": 5,
    }


def init_pool() -> None:
    pass  # no pool anymore


_LEAKED = []  # keep references so connections are NOT garbage-collected/closed


@contextlib.contextmanager
def get_conn():
    conn = psycopg2.connect(**_dsn())
    _LEAKED.append(conn)  # leak on purpose: never closed, never reused
    yield conn
    # BUG: no putconn, no close - the connection is held open forever.


def pool_status() -> dict:
    return {"min": 0, "max": 0, "initialized": False, "leaked": len(_LEAKED)}


def db_ping() -> bool:
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
        return True
    except Exception:
        return False


def raw_conn():
    return psycopg2.connect(**_dsn())
PYEOF

echo "[inject] restarting the API..."
pkill -f "uvicorn app:app" 2>/dev/null || true
sleep 1
set -a; . ./.env 2>/dev/null || true; set +a
nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
sleep 3

echo "[inject] firing a burst of concurrent requests to leak connections..."
for i in $(seq 1 40); do
  curl -s -o /dev/null -H "Authorization: Bearer token-admin" \
    "http://127.0.0.1:8000/ask" -H "Content-Type: application/json" \
    -d '{"query":"backup"}' &
done
wait 2>/dev/null || true
sleep 1

# Best-effort count. During a real storm the pool may have consumed all the
# connection slots, so this very query could be refused - use a short connect
# timeout and tolerate failure so inject never hangs.
OPEN=$(PGCONNECT_TIMEOUT=3 PGPASSWORD="${DB_PASSWORD:-labpass}" psql -h "${DB_HOST:-127.0.0.1}" \
  -U "${DB_USER:-labuser}" -d "${DB_NAME:-labdb}" -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database()" 2>/dev/null || echo "many")
echo "[inject] DONE. Leaked connections are piling up (open backends: $OPEN)."
echo "[inject] Follow runbook.md: restore pooling and prove recovery under load."
