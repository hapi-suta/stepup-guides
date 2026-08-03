#!/usr/bin/env python3
"""
replication_monitor.py - Real-time replication monitoring for quantdb.

Polls pg_stat_replication every N seconds and displays:
  - client_addr, state, sent_lsn, replay_lsn, write_lag, replay_lag
  - WAL generation rate (bytes/s estimated between polls)
  - ALERT if replay_lag exceeds threshold

Press Ctrl+C to exit.

Usage:
    python3 replication_monitor.py
    python3 replication_monitor.py --interval 10 --threshold 60
    python3 replication_monitor.py --host 172.31.19.86 --interval 3
"""

import argparse
import os
import sys
import time
from datetime import datetime

import psycopg2
from psycopg2.extras import RealDictCursor

DEFAULT_HOST      = "172.31.19.86"
DEFAULT_PORT      = 5432
DEFAULT_DB        = "quantdb"
DEFAULT_USER      = "quant_readonly"
DEFAULT_PASS      = "quant_readonly_2026"
DEFAULT_INTERVAL  = 5    # seconds between polls
DEFAULT_THRESHOLD = 30   # seconds of replay_lag before ALERT


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def get_current_lsn(cur) -> int:
    cur.execute("SELECT pg_current_wal_lsn() - '0/0'::pg_lsn AS lsn_bytes")
    row = cur.fetchone()
    return int(row["lsn_bytes"]) if row else 0


def get_replication_rows(cur) -> list:
    cur.execute("""
        SELECT pid,
               client_addr::text              AS client_addr,
               application_name,
               state,
               sent_lsn::text                 AS sent_lsn,
               write_lsn::text                AS write_lsn,
               flush_lsn::text                AS flush_lsn,
               replay_lsn::text               AS replay_lsn,
               write_lag::text                AS write_lag,
               flush_lag::text                AS flush_lag,
               replay_lag::text               AS replay_lag,
               sync_state,
               EXTRACT(EPOCH FROM replay_lag) AS replay_lag_sec
        FROM   pg_stat_replication
        ORDER  BY client_addr
    """)
    return cur.fetchall()


def lag_alert(replay_lag_sec, threshold: int) -> str:
    if replay_lag_sec is None:
        return "  ---  "
    sec = float(replay_lag_sec)
    if sec >= threshold:
        return f"ALERT {sec:.0f}s"
    return f"  ok {sec:.1f}s"


def clear_screen():
    os.system("clear" if os.name != "nt" else "cls")


def print_header(host, interval, threshold, iteration, wal_rate_kbps):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print("=" * 80)
    print(f"  Voleon quantdb - Replication Monitor   [{now}]  poll #{iteration}")
    print(f"  Host: {host}  |  Interval: {interval}s  |  Lag threshold: {threshold}s")
    if wal_rate_kbps is not None:
        print(f"  WAL generation rate: {wal_rate_kbps:.1f} KB/s")
    print("=" * 80)


def print_standbys(rows, threshold):
    if not rows:
        print("  No standbys connected to this primary.\n")
        return

    col_fmt = "  {:<18}  {:<20}  {:<12}  {:<16}  {:<16}  {:<12}  {:<10}  {:<12}"
    print(col_fmt.format(
        "client_addr", "application_name", "state",
        "sent_lsn", "replay_lsn", "write_lag", "sync", "replay_alert"
    ))
    print("  " + "-" * 76)
    for r in rows:
        alert = lag_alert(r["replay_lag_sec"], threshold)
        print(col_fmt.format(
            str(r["client_addr"] or "-"),
            str(r["application_name"] or "-")[:20],
            str(r["state"] or "-"),
            str(r["sent_lsn"] or "-"),
            str(r["replay_lsn"] or "-"),
            str(r["write_lag"] or "0"),
            str(r["sync_state"] or "-"),
            alert
        ))
    print()


def parse_args():
    p = argparse.ArgumentParser(description="Real-time replication lag monitor")
    p.add_argument("--host",      default=DEFAULT_HOST)
    p.add_argument("--port",      type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",    default=DEFAULT_DB)
    p.add_argument("--user",      default=DEFAULT_USER)
    p.add_argument("--password",  default=DEFAULT_PASS)
    p.add_argument("--interval",  type=int, default=DEFAULT_INTERVAL,
                   help="Seconds between polls (default 5)")
    p.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD,
                   help="Replay lag seconds before ALERT (default 30)")
    p.add_argument("--count",     type=int, default=0,
                   help="Stop after N iterations (0 = run forever)")
    return p.parse_args()


def main():
    args = parse_args()
    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    conn.autocommit = True

    prev_lsn  = None
    prev_time = None
    iteration = 0

    print(f"Starting replication monitor - Ctrl+C to stop")
    time.sleep(0.5)

    try:
        while True:
            iteration += 1
            now_time = time.time()

            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur_lsn = get_current_lsn(cur)
                rows    = get_replication_rows(cur)

            wal_rate = None
            if prev_lsn is not None and prev_time is not None:
                elapsed = now_time - prev_time
                if elapsed > 0:
                    wal_rate = (cur_lsn - prev_lsn) / elapsed / 1024
            prev_lsn  = cur_lsn
            prev_time = now_time

            clear_screen()
            print_header(args.host, args.interval, args.threshold, iteration, wal_rate)
            print_standbys(rows, args.threshold)

            if args.count and iteration >= args.count:
                break

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print("\nMonitor stopped.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
