#!/usr/bin/env python3
"""
check_cluster.py - Morning health check for the Voleon quantdb cluster.

Checks primary status, replication lag, connection usage, database sizes,
disk space, and PgBouncer pool status. Outputs a formatted report with
PASS/WARN/FAIL indicators for each check.

Usage:
    python3 check_cluster.py
    python3 check_cluster.py --host 172.31.19.86 --port 5432
    python3 check_cluster.py --pgbouncer-host 172.31.19.86 --pgbouncer-port 6432
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime

import psycopg2
from psycopg2.extras import RealDictCursor

# ── Defaults ────────────────────────────────────────────────────────────────
DEFAULT_HOST = "172.31.19.86"
DEFAULT_PORT = 5432
DEFAULT_DB   = "quantdb"
DEFAULT_USER = "quant_readonly"
DEFAULT_PASS = "quant_readonly_2026"

WARN_CONN_PCT  = 70   # % of max_connections that triggers WARN
FAIL_CONN_PCT  = 90
WARN_LAG_MB    = 50   # replication lag in MB
FAIL_LAG_MB    = 200
WARN_DISK_PCT  = 75
FAIL_DISK_PCT  = 90


def indicator(status: str) -> str:
    return {"PASS": "[ PASS ]", "WARN": "[ WARN ]", "FAIL": "[ FAIL ]"}.get(status, "[ INFO ]")


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"  [ FAIL ] Cannot connect to {host}:{port}/{dbname} - {exc}")
        sys.exit(1)


def check_primary(cur):
    cur.execute("SELECT pg_is_in_recovery(), version()")
    row = cur.fetchone()
    is_replica = row["pg_is_in_recovery"]
    pg_version = row["version"].split(" ")[1] if row["version"] else "unknown"
    status = "FAIL" if is_replica else "PASS"
    label  = "REPLICA (unexpected)" if is_replica else "PRIMARY"
    print(f"  {indicator(status)} Node role     : {label}  (PostgreSQL {pg_version})")
    return not is_replica


def check_replication(cur):
    cur.execute("""
        SELECT client_addr,
               state,
               pg_wal_lsn_diff(sent_lsn, replay_lsn) / 1048576.0 AS lag_mb,
               sync_state
        FROM   pg_stat_replication
    """)
    rows = cur.fetchall()
    if not rows:
        print(f"  {indicator('WARN')} Replication    : No standbys connected")
        return
    for r in rows:
        lag_mb = r["lag_mb"] or 0.0
        if lag_mb >= FAIL_LAG_MB:
            status = "FAIL"
        elif lag_mb >= WARN_LAG_MB:
            status = "WARN"
        else:
            status = "PASS"
        print(
            f"  {indicator(status)} Replication    : {r['client_addr']}  "
            f"state={r['state']}  lag={lag_mb:.1f} MB  sync={r['sync_state']}"
        )


def check_connections(cur):
    cur.execute("""
        SELECT setting::int AS max_conn FROM pg_settings WHERE name = 'max_connections'
    """)
    max_conn = cur.fetchone()["max_conn"]
    cur.execute("SELECT count(*) AS active FROM pg_stat_activity WHERE state != 'idle'")
    active = cur.fetchone()["active"]
    cur.execute("SELECT count(*) AS total FROM pg_stat_activity")
    total = cur.fetchone()["total"]
    pct = round(total / max_conn * 100, 1)
    status = "FAIL" if pct >= FAIL_CONN_PCT else ("WARN" if pct >= WARN_CONN_PCT else "PASS")
    print(
        f"  {indicator(status)} Connections    : {total}/{max_conn} total "
        f"({pct}%), {active} active"
    )


def check_db_sizes(cur):
    cur.execute("""
        SELECT datname,
               pg_size_pretty(pg_database_size(datname)) AS size,
               pg_database_size(datname) AS size_bytes
        FROM   pg_database
        WHERE  datname NOT IN ('template0','template1','postgres')
        ORDER  BY size_bytes DESC
        LIMIT  10
    """)
    rows = cur.fetchall()
    print(f"  {indicator('PASS')} Database sizes :")
    for r in rows:
        print(f"           {r['datname']:30s}  {r['size']}")


def check_disk():
    try:
        stat = os.statvfs("/")
        total  = stat.f_blocks * stat.f_frsize
        free   = stat.f_bavail * stat.f_frsize
        used   = total - free
        pct    = round(used / total * 100, 1)
        used_g = used  / 1073741824
        total_g = total / 1073741824
        status = "FAIL" if pct >= FAIL_DISK_PCT else ("WARN" if pct >= WARN_DISK_PCT else "PASS")
        print(
            f"  {indicator(status)} Disk (/)       : {used_g:.1f} GB / {total_g:.1f} GB used "
            f"({pct}%)"
        )
    except OSError as exc:
        print(f"  {indicator('WARN')} Disk check     : Could not read statvfs - {exc}")


def check_pgbouncer(host, port):
    try:
        conn = psycopg2.connect(
            host=host, port=port, dbname="pgbouncer",
            user="pgbouncer", password="", connect_timeout=3
        )
        conn.autocommit = True
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SHOW POOLS")
            rows = cur.fetchall()
        conn.close()
        print(f"  {indicator('PASS')} PgBouncer pools:")
        for r in rows:
            if r.get("database") == "pgbouncer":
                continue
            print(
                f"           db={r.get('database','?'):20s}  "
                f"cl_active={r.get('cl_active',0)}  "
                f"sv_active={r.get('sv_active',0)}  "
                f"sv_idle={r.get('sv_idle',0)}"
            )
    except Exception as exc:
        print(f"  {indicator('WARN')} PgBouncer      : Could not connect to {host}:{port} - {exc}")


def parse_args():
    p = argparse.ArgumentParser(description="Morning cluster health check for quantdb")
    p.add_argument("--host",            default=DEFAULT_HOST)
    p.add_argument("--port",            type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",          default=DEFAULT_DB)
    p.add_argument("--user",            default=DEFAULT_USER)
    p.add_argument("--password",        default=DEFAULT_PASS)
    p.add_argument("--pgbouncer-host",  default=DEFAULT_HOST)
    p.add_argument("--pgbouncer-port",  type=int, default=6432)
    return p.parse_args()


def main():
    args = parse_args()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print("=" * 60)
    print(f"  Voleon quantdb - Cluster Health Check")
    print(f"  {now}")
    print("=" * 60)

    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        check_primary(cur)
        check_replication(cur)
        check_connections(cur)
        check_db_sizes(cur)
    conn.close()

    check_disk()
    check_pgbouncer(args.pgbouncer_host, args.pgbouncer_port)

    print("=" * 60)


if __name__ == "__main__":
    main()
