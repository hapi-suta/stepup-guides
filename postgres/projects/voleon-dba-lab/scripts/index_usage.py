#!/usr/bin/env python3
"""
index_usage.py - Index health analysis for quantdb.

Reports:
  - Unused indexes (idx_scan = 0, size > min_size_mb)
  - Potentially duplicate indexes (same table + same columns, different names)
  - Tables with high seq_scan and low idx_scan (missing index candidates)
  - Index bloat estimation via pg_stat_user_indexes + pg_class

Output includes DROP/CREATE suggestions where applicable.

Usage:
    python3 index_usage.py
    python3 index_usage.py --schema market_data
    python3 index_usage.py --min-size 5 --seq-scan-min 1000
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
DEFAULT_MIN_MB    = 1     # minimum index size to flag as unused
DEFAULT_SEQ_MIN   = 500   # minimum seq_scan to flag as missing index


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def unused_indexes(cur, schema, min_size_mb):
    cur.execute("""
        SELECT s.schemaname,
               s.relname                                   AS table_name,
               s.indexrelname                              AS index_name,
               pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
               pg_relation_size(s.indexrelid)              AS size_bytes,
               s.idx_scan,
               i.indisunique                               AS is_unique,
               i.indisprimary                              AS is_primary
        FROM   pg_stat_user_indexes s
        JOIN   pg_index i ON i.indexrelid = s.indexrelid
        WHERE  s.idx_scan = 0
          AND  s.schemaname = COALESCE(%s, s.schemaname)
          AND  NOT i.indisunique
          AND  NOT i.indisprimary
          AND  pg_relation_size(s.indexrelid) >= %s * 1048576
        ORDER  BY pg_relation_size(s.indexrelid) DESC
    """, (schema, min_size_mb))
    rows = cur.fetchall()

    print(f"\n--- Unused Indexes (idx_scan=0, size > {min_size_mb} MB, excluding PK/unique) ---")
    if not rows:
        print("  None found.")
        return
    for r in rows:
        print(f"  {r['schemaname']}.{r['table_name']}")
        print(f"    Index : {r['index_name']}  ({r['index_size']})")
        print(f"    Suggestion: DROP INDEX CONCURRENTLY {r['schemaname']}.{r['index_name']};")
    print(f"  Total: {len(rows)} unused indexes")


def duplicate_indexes(cur, schema):
    cur.execute("""
        SELECT n.nspname                         AS schemaname,
               t.relname                         AS table_name,
               array_agg(i.relname ORDER BY i.relname) AS index_names,
               array_to_string(
                 array_agg(a.attname ORDER BY x.ordinality), ', '
               )                                AS columns
        FROM   pg_index ix
        JOIN   pg_class t  ON t.oid  = ix.indrelid
        JOIN   pg_class i  ON i.oid  = ix.indexrelid
        JOIN   pg_namespace n ON n.oid = t.relnamespace
        JOIN   LATERAL unnest(ix.indkey) WITH ORDINALITY AS x(attnum, ordinality)
               ON TRUE
        JOIN   pg_attribute a ON a.attrelid = t.oid AND a.attnum = x.attnum
        WHERE  n.nspname = COALESCE(%s, n.nspname)
          AND  n.nspname NOT IN ('pg_catalog','information_schema')
        GROUP  BY n.nspname, t.relname, ix.indkey
        HAVING count(*) > 1
        ORDER  BY n.nspname, t.relname
    """, (schema,))
    rows = cur.fetchall()

    print("\n--- Duplicate Indexes (same table + columns, different names) ---")
    if not rows:
        print("  None found.")
        return
    for r in rows:
        print(f"  {r['schemaname']}.{r['table_name']}  columns: ({r['columns']})")
        print(f"    Indexes: {', '.join(r['index_names'])}")
        print(f"    Suggestion: Keep one, DROP CONCURRENTLY the others.")
    print(f"  Total: {len(rows)} duplicate groups")


def missing_indexes(cur, schema, seq_scan_min):
    cur.execute("""
        SELECT schemaname,
               relname                           AS table_name,
               seq_scan,
               seq_tup_read,
               idx_scan,
               n_live_tup,
               pg_size_pretty(pg_total_relation_size(relid)) AS table_size
        FROM   pg_stat_user_tables
        WHERE  schemaname = COALESCE(%s, schemaname)
          AND  seq_scan   > %s
          AND  (idx_scan  < seq_scan * 0.1 OR idx_scan IS NULL)
          AND  n_live_tup > 10000
        ORDER  BY seq_scan DESC
        LIMIT  20
    """, (schema, seq_scan_min))
    rows = cur.fetchall()

    print(f"\n--- Tables with High seq_scan (>{seq_scan_min}) and Low idx_scan ---")
    if not rows:
        print("  None found.")
        return
    fmt = "  {:<35}  {:>10}  {:>10}  {:>12}  {:<10}"
    print(fmt.format("table", "seq_scan", "idx_scan", "live_rows", "size"))
    print("  " + "-" * 72)
    for r in rows:
        print(fmt.format(
            f"{r['schemaname']}.{r['table_name']}"[:35],
            r['seq_scan'],
            r['idx_scan'] or 0,
            r['n_live_tup'],
            r['table_size']
        ))
    print(f"  Total: {len(rows)} candidates")


def index_bloat(cur, schema):
    """Simple bloat estimate using pg_class relpages vs actual data pages."""
    cur.execute("""
        SELECT s.schemaname,
               s.relname                               AS table_name,
               s.indexrelname                          AS index_name,
               pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
               round(100.0 * (1 - c.reltuples / NULLIF(c.relpages * 8192.0 / 64, 0)), 1)
                                                       AS bloat_pct_est
        FROM   pg_stat_user_indexes s
        JOIN   pg_class c ON c.oid = s.indexrelid
        WHERE  s.schemaname = COALESCE(%s, s.schemaname)
          AND  c.relpages   > 100
        ORDER  BY bloat_pct_est DESC NULLS LAST
        LIMIT  15
    """, (schema,))
    rows = cur.fetchall()

    print("\n--- Index Bloat Estimate (top 15, pages > 100) ---")
    fmt = "  {:<50}  {:>12}  {:>10}"
    print(fmt.format("index", "size", "bloat_pct_est"))
    print("  " + "-" * 75)
    for r in rows:
        name = f"{r['schemaname']}.{r['index_name']}"
        print(fmt.format(name[:50], r['index_size'], str(r['bloat_pct_est']) + "%"))


def parse_args():
    p = argparse.ArgumentParser(description="Index usage analysis for quantdb")
    p.add_argument("--host",         default=DEFAULT_HOST)
    p.add_argument("--port",         type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",       default=DEFAULT_DB)
    p.add_argument("--user",         default=DEFAULT_USER)
    p.add_argument("--password",     default=DEFAULT_PASS)
    p.add_argument("--schema",       default=None,
                   help="Limit to a specific schema (default: all user schemas)")
    p.add_argument("--min-size",     type=float, default=DEFAULT_MIN_MB,
                   help="Min index size in MB to include in unused report (default 1)")
    p.add_argument("--seq-scan-min", type=int, default=DEFAULT_SEQ_MIN,
                   help="Min seq_scan count for missing index candidates (default 500)")
    return p.parse_args()


def main():
    args = parse_args()
    print("=" * 60)
    print("  Voleon quantdb - Index Usage Analysis")
    schema_label = args.schema if args.schema else "all schemas"
    print(f"  Host: {args.host}  DB: {args.dbname}  Schema: {schema_label}")
    print("=" * 60)

    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        unused_indexes(cur, args.schema, args.min_size)
        duplicate_indexes(cur, args.schema)
        missing_indexes(cur, args.schema, args.seq_scan_min)
        index_bloat(cur, args.schema)
    conn.close()
    print()


if __name__ == "__main__":
    main()
