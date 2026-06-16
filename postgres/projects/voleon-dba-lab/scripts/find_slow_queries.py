#!/usr/bin/env python3
"""
find_slow_queries.py - Analyze pg_stat_statements for slow and inconsistent queries.

Reports:
  - Top N queries by total execution time
  - Top N queries by mean execution time
  - Queries with high stddev (inconsistent execution)
  - Queries exceeding a user-defined ms threshold

Requires pg_stat_statements to be loaded in shared_preload_libraries.

Usage:
    python3 find_slow_queries.py
    python3 find_slow_queries.py --top 20 --threshold 500
    python3 find_slow_queries.py --mode mean --top 5
"""

import argparse
import sys

import psycopg2
from psycopg2.extras import RealDictCursor

DEFAULT_HOST      = "172.31.19.86"
DEFAULT_PORT      = 5432
DEFAULT_DB        = "quantdb"
DEFAULT_USER      = "quant_readonly"
DEFAULT_PASS      = "quant_readonly_2026"
DEFAULT_TOP       = 10
DEFAULT_THRESHOLD = 1000   # ms
QUERY_TRUNC       = 80     # characters to show from query text


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def check_extension(cur):
    cur.execute(
        "SELECT count(*) AS n FROM pg_extension WHERE extname = %s",
        ("pg_stat_statements",)
    )
    if cur.fetchone()["n"] == 0:
        print("ERROR: pg_stat_statements extension is not installed in this database.")
        sys.exit(1)


def print_table(title, rows, columns, widths):
    print(f"\n{title}")
    print("-" * sum(widths + [len(columns) * 2]))
    header = "  ".join(col.ljust(w) for col, w in zip(columns, widths))
    print(header)
    print("-" * sum(widths + [len(columns) * 2]))
    for row in rows:
        line = "  ".join(str(row.get(c, "")).ljust(w)[:w] for c, w in zip(columns, widths))
        print(line)
    print(f"  ({len(rows)} rows)")


def top_by_total(cur, top_n):
    cur.execute("""
        SELECT left(query, %s)                        AS query,
               calls,
               round(total_exec_time::numeric, 2)     AS total_ms,
               round(mean_exec_time::numeric, 2)      AS mean_ms,
               round(stddev_exec_time::numeric, 2)    AS stddev_ms,
               rows
        FROM   pg_stat_statements
        ORDER  BY total_exec_time DESC
        LIMIT  %s
    """, (QUERY_TRUNC, top_n))
    rows = cur.fetchall()
    print_table(
        f"Top {top_n} queries by TOTAL execution time",
        rows,
        ["query", "calls", "total_ms", "mean_ms", "stddev_ms", "rows"],
        [80,       8,       12,         12,         12,          10]
    )


def top_by_mean(cur, top_n):
    cur.execute("""
        SELECT left(query, %s)                        AS query,
               calls,
               round(total_exec_time::numeric, 2)     AS total_ms,
               round(mean_exec_time::numeric, 2)      AS mean_ms,
               round(stddev_exec_time::numeric, 2)    AS stddev_ms
        FROM   pg_stat_statements
        WHERE  calls >= 5
        ORDER  BY mean_exec_time DESC
        LIMIT  %s
    """, (QUERY_TRUNC, top_n))
    rows = cur.fetchall()
    print_table(
        f"Top {top_n} queries by MEAN execution time (min 5 calls)",
        rows,
        ["query", "calls", "total_ms", "mean_ms", "stddev_ms"],
        [80,       8,       12,         12,         12]
    )


def high_stddev(cur, top_n):
    cur.execute("""
        SELECT left(query, %s)                        AS query,
               calls,
               round(mean_exec_time::numeric, 2)      AS mean_ms,
               round(stddev_exec_time::numeric, 2)    AS stddev_ms,
               round(
                 (stddev_exec_time / NULLIF(mean_exec_time, 0) * 100)::numeric, 1
               )                                      AS cv_pct
        FROM   pg_stat_statements
        WHERE  calls >= 10
          AND  mean_exec_time > 0
        ORDER  BY stddev_exec_time / NULLIF(mean_exec_time, 0) DESC
        LIMIT  %s
    """, (QUERY_TRUNC, top_n))
    rows = cur.fetchall()
    print_table(
        f"Top {top_n} queries with HIGH stddev (coefficient of variation, min 10 calls)",
        rows,
        ["query", "calls", "mean_ms", "stddev_ms", "cv_pct"],
        [80,       8,       12,        12,           8]
    )


def over_threshold(cur, threshold_ms):
    cur.execute("""
        SELECT left(query, %s)                        AS query,
               calls,
               round(mean_exec_time::numeric, 2)      AS mean_ms,
               round(max_exec_time::numeric, 2)       AS max_ms,
               round(total_exec_time::numeric, 2)     AS total_ms
        FROM   pg_stat_statements
        WHERE  mean_exec_time >= %s
        ORDER  BY mean_exec_time DESC
    """, (QUERY_TRUNC, threshold_ms))
    rows = cur.fetchall()
    print_table(
        f"Queries with mean_exec_time >= {threshold_ms} ms",
        rows,
        ["query", "calls", "mean_ms", "max_ms", "total_ms"],
        [80,       8,       12,        12,        12]
    )


def parse_args():
    p = argparse.ArgumentParser(description="Slow query analysis via pg_stat_statements")
    p.add_argument("--host",      default=DEFAULT_HOST)
    p.add_argument("--port",      type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",    default=DEFAULT_DB)
    p.add_argument("--user",      default=DEFAULT_USER)
    p.add_argument("--password",  default=DEFAULT_PASS)
    p.add_argument("--top",       type=int, default=DEFAULT_TOP,
                   help="Number of rows to return per section (default 10)")
    p.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                   help="Mean time threshold in ms for the threshold section (default 1000)")
    p.add_argument("--mode",      choices=["all", "total", "mean", "stddev", "threshold"],
                   default="all", help="Which section(s) to display (default all)")
    return p.parse_args()


def main():
    args = parse_args()
    print("=" * 60)
    print("  Voleon quantdb - Slow Query Report")
    print(f"  Host: {args.host}  DB: {args.dbname}  Top-N: {args.top}")
    print("=" * 60)

    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        check_extension(cur)
        if args.mode in ("all", "total"):
            top_by_total(cur, args.top)
        if args.mode in ("all", "mean"):
            top_by_mean(cur, args.top)
        if args.mode in ("all", "stddev"):
            high_stddev(cur, args.top)
        if args.mode in ("all", "threshold"):
            over_threshold(cur, args.threshold)
    conn.close()
    print()


if __name__ == "__main__":
    main()
