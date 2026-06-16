#!/usr/bin/env python3
"""
kill_idle_sessions.py - Terminate problematic idle and idle-in-transaction sessions.

Finds and kills:
  - idle-in-transaction sessions older than --threshold seconds (default 300)
  - idle sessions older than --idle-threshold seconds (default 3600)

Dry-run mode (--dry-run) shows what would be killed without taking action.
Logs each kill to the ops.alerts table.
Certain users can be excluded via --exclude.

Usage:
    python3 kill_idle_sessions.py --dry-run
    python3 kill_idle_sessions.py --threshold 120 --idle-threshold 1800
    python3 kill_idle_sessions.py --exclude quant_readonly,repmgr
"""

import argparse
import sys
from datetime import datetime

import psycopg2
from psycopg2.extras import RealDictCursor

DEFAULT_HOST          = "172.31.19.86"
DEFAULT_PORT          = 5432
DEFAULT_DB            = "quantdb"
DEFAULT_USER          = "quant_readonly"
DEFAULT_PASS          = "quant_readonly_2026"
DEFAULT_IDLE_XAX_SEC  = 300    # idle in transaction threshold
DEFAULT_IDLE_SEC      = 3600   # plain idle threshold
ALWAYS_EXCLUDE        = {"postgres", "repmgr", "pgbouncer"}


def connect_rw(host, port, dbname, user, password):
    """Connect with autocommit off for DML."""
    try:
        conn = psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
        conn.autocommit = False
        return conn
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def ensure_ops_schema(cur):
    cur.execute("CREATE SCHEMA IF NOT EXISTS ops")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS ops.alerts (
            id          bigserial PRIMARY KEY,
            created_at  timestamptz NOT NULL DEFAULT now(),
            event_type  text        NOT NULL,
            pid         int,
            username    text,
            datname     text,
            state       text,
            duration_s  numeric,
            query_start timestamptz,
            client_addr text,
            application text,
            note        text
        )
    """)


def find_sessions(cur, idle_xact_sec, idle_sec, exclude_users):
    excluded = list(ALWAYS_EXCLUDE | set(exclude_users))
    cur.execute("""
        SELECT pid,
               usename,
               datname,
               state,
               client_addr::text                               AS client_addr,
               application_name,
               state_change,
               query_start,
               left(query, 120)                                AS query,
               EXTRACT(EPOCH FROM (now() - state_change))     AS duration_sec
        FROM   pg_stat_activity
        WHERE  pid <> pg_backend_pid()
          AND  usename NOT IN %s
          AND  (
                   (state = 'idle in transaction'
                    AND EXTRACT(EPOCH FROM (now() - state_change)) >= %s)
                OR (state = 'idle'
                    AND EXTRACT(EPOCH FROM (now() - query_start)) >= %s)
               )
        ORDER  BY duration_sec DESC
    """, (tuple(excluded), idle_xact_sec, idle_sec))
    return cur.fetchall()


def log_kill(cur, session, note):
    cur.execute("""
        INSERT INTO ops.alerts
          (event_type, pid, username, datname, state,
           duration_s, query_start, client_addr, application, note)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        "kill_idle_session",
        session["pid"],
        session["usename"],
        session["datname"],
        session["state"],
        session["duration_sec"],
        session["query_start"],
        session["client_addr"],
        session["application_name"],
        note
    ))


def terminate_session(cur, pid) -> bool:
    cur.execute("SELECT pg_terminate_backend(%s) AS killed", (pid,))
    row = cur.fetchone()
    return row["killed"] if row else False


def fmt_duration(seconds) -> str:
    sec = int(seconds or 0)
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m {sec % 60}s"
    return f"{sec // 3600}h {(sec % 3600) // 60}m"


def parse_args():
    p = argparse.ArgumentParser(description="Kill idle and idle-in-transaction sessions")
    p.add_argument("--host",           default=DEFAULT_HOST)
    p.add_argument("--port",           type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",         default=DEFAULT_DB)
    p.add_argument("--user",           default=DEFAULT_USER)
    p.add_argument("--password",       default=DEFAULT_PASS)
    p.add_argument("--threshold",      type=int, default=DEFAULT_IDLE_XAX_SEC,
                   help="Idle-in-transaction age threshold in seconds (default 300)")
    p.add_argument("--idle-threshold", type=int, default=DEFAULT_IDLE_SEC,
                   help="Plain idle age threshold in seconds (default 3600)")
    p.add_argument("--exclude",        default="",
                   help="Comma-separated list of usernames to exclude")
    p.add_argument("--dry-run",        action="store_true",
                   help="Show what would be killed without taking action")
    return p.parse_args()


def main():
    args     = parse_args()
    excludes = {u.strip() for u in args.exclude.split(",") if u.strip()}
    mode     = "DRY RUN" if args.dry_run else "LIVE"
    now      = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print("=" * 65)
    print(f"  Voleon quantdb - Kill Idle Sessions  [{mode}]")
    print(f"  {now}")
    print(f"  idle-in-transaction threshold : {args.threshold}s")
    print(f"  idle threshold                : {args.idle_threshold}s")
    print(f"  excluded users                : {ALWAYS_EXCLUDE | excludes}")
    print("=" * 65)

    conn = connect_rw(args.host, args.port, args.dbname, args.user, args.password)
    killed = 0
    skipped = 0

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if not args.dry_run:
                ensure_ops_schema(cur)

            sessions = find_sessions(cur, args.threshold, args.idle_threshold, excludes)

            if not sessions:
                print("  No sessions matching criteria found.")
                conn.commit()
                return

            print(f"\n  Found {len(sessions)} session(s) to {'review' if args.dry_run else 'terminate'}:\n")
            fmt = "  {:<6}  {:<20}  {:<15}  {:<25}  {:<12}  {:<20}"
            print(fmt.format("PID", "user", "db", "state", "duration", "client"))
            print("  " + "-" * 100)

            for s in sessions:
                dur = fmt_duration(s["duration_sec"])
                print(fmt.format(
                    s["pid"],
                    str(s["usename"] or "-")[:20],
                    str(s["datname"] or "-")[:15],
                    str(s["state"] or "-")[:25],
                    dur,
                    str(s["client_addr"] or "-")[:20]
                ))
                print(f"         query: {s['query']}")

                if not args.dry_run:
                    ok = terminate_session(cur, s["pid"])
                    note = f"duration={dur}, mode=kill_idle_sessions.py"
                    if ok:
                        log_kill(cur, s, note)
                        print(f"         -> TERMINATED")
                        killed += 1
                    else:
                        print(f"         -> SKIPPED (already gone)")
                        skipped += 1
                else:
                    print(f"         -> [DRY RUN] would terminate")

        if not args.dry_run:
            conn.commit()

    except Exception as exc:
        conn.rollback()
        print(f"\nERROR: {exc}")
        sys.exit(1)
    finally:
        conn.close()

    print()
    if args.dry_run:
        print(f"  [DRY RUN] {len(sessions)} session(s) would have been terminated.")
    else:
        print(f"  Terminated: {killed}  |  Already gone: {skipped}")
    print("=" * 65)


if __name__ == "__main__":
    main()
