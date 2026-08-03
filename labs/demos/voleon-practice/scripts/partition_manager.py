#!/usr/bin/env python3
"""
partition_manager.py - Partition lifecycle management for quantdb.

Manages range partitions (by month) for market_data and signals tables.
Reports current partitions, generates DDL to create future partitions,
and identifies old partitions eligible for dropping.

Usage:
    python3 partition_manager.py
    python3 partition_manager.py --create-ahead 6 --dry-run
    python3 partition_manager.py --table market_data --retention 6
    python3 partition_manager.py --execute   # run DDL without prompting
"""

import argparse
import sys
from datetime import date, datetime
from dateutil.relativedelta import relativedelta

import psycopg2
from psycopg2.extras import RealDictCursor

DEFAULT_HOST        = "172.31.19.86"
DEFAULT_PORT        = 5432
DEFAULT_DB          = "quantdb"
DEFAULT_USER        = "quant_readonly"
DEFAULT_PASS        = "quant_readonly_2026"
DEFAULT_CREATE_AHEAD = 3   # months ahead to create
DEFAULT_RETENTION    = 12  # months of partitions to retain
MANAGED_TABLES       = ["market_data", "signals"]


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def list_partitions(cur, parent_table: str) -> list:
    """Return current partition names, bounds, and sizes for a partitioned table."""
    # Find schema of parent
    cur.execute("""
        SELECT n.nspname AS schema
        FROM   pg_class c
        JOIN   pg_namespace n ON n.oid = c.relnamespace
        WHERE  c.relname = %s
          AND  c.relkind = 'p'
        LIMIT  1
    """, (parent_table,))
    row = cur.fetchone()
    if not row:
        return []
    schema = row["schema"]

    cur.execute("""
        SELECT c.relname                                         AS partition_name,
               n.nspname                                        AS schema,
               pg_get_expr(c.relpartbound, c.oid)              AS bounds,
               pg_size_pretty(pg_total_relation_size(c.oid))   AS size,
               pg_total_relation_size(c.oid)                   AS size_bytes
        FROM   pg_inherits i
        JOIN   pg_class c  ON c.oid  = i.inhrelid
        JOIN   pg_namespace n ON n.oid = c.relnamespace
        WHERE  i.inhparent = (
            SELECT oid FROM pg_class
            WHERE relname = %s AND relnamespace = (
                SELECT oid FROM pg_namespace WHERE nspname = %s
            )
        )
        ORDER  BY c.relname
    """, (parent_table, schema))
    return cur.fetchall()


def parse_month_from_name(name: str):
    """Extract YYYY_MM from partition name like market_data_2025_01."""
    parts = name.rsplit("_", 2)
    if len(parts) == 3:
        try:
            return date(int(parts[1]), int(parts[2]), 1)
        except ValueError:
            pass
    return None


def generate_create_ddl(schema: str, parent: str, target_month: date) -> str:
    part_name = f"{parent}_{target_month.strftime('%Y_%m')}"
    start = target_month.strftime("%Y-%m-01")
    end_date = target_month + relativedelta(months=1)
    end = end_date.strftime("%Y-%m-01")
    return (
        f"CREATE TABLE IF NOT EXISTS {schema}.{part_name}\n"
        f"  PARTITION OF {schema}.{parent}\n"
        f"  FOR VALUES FROM ('{start}') TO ('{end}');"
    )


def generate_drop_ddl(schema: str, part_name: str) -> str:
    return f"DROP TABLE IF EXISTS {schema}.{part_name};"


def print_partition_table(rows, title):
    print(f"\n{title}")
    fmt = "  {:<45}  {:<40}  {:<10}"
    print(fmt.format("partition", "bounds", "size"))
    print("  " + "-" * 95)
    for r in rows:
        print(fmt.format(
            f"{r['schema']}.{r['partition_name']}"[:45],
            str(r["bounds"] or "")[:40],
            r["size"]
        ))
    print(f"  Total: {len(rows)} partition(s)")


def parse_args():
    p = argparse.ArgumentParser(description="Partition lifecycle manager for quantdb")
    p.add_argument("--host",          default=DEFAULT_HOST)
    p.add_argument("--port",          type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",        default=DEFAULT_DB)
    p.add_argument("--user",          default=DEFAULT_USER)
    p.add_argument("--password",      default=DEFAULT_PASS)
    p.add_argument("--table",         default=None,
                   help="Limit to a single table (default: all managed tables)")
    p.add_argument("--create-ahead",  type=int, default=DEFAULT_CREATE_AHEAD,
                   help="Create partitions N months ahead (default 3)")
    p.add_argument("--retention",     type=int, default=DEFAULT_RETENTION,
                   help="Keep partitions for N months (default 12)")
    p.add_argument("--dry-run",       action="store_true",
                   help="Print DDL without executing (default)")
    p.add_argument("--execute",       action="store_true",
                   help="Execute the DDL statements against the database")
    return p.parse_args()


def main():
    args   = parse_args()
    tables = [args.table] if args.table else MANAGED_TABLES
    today  = date.today()
    now    = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print("=" * 65)
    print("  Voleon quantdb - Partition Manager")
    print(f"  {now}  |  create_ahead={args.create_ahead}m  retention={args.retention}m")
    mode = "EXECUTE" if args.execute else "DRY RUN"
    print(f"  Mode: {mode}")
    print("=" * 65)

    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    all_ddl: list[str] = []

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        for table in tables:
            rows = list_partitions(cur, table)
            if not rows:
                print(f"\n  [ WARN ] Table '{table}' not found or not partitioned - skipping")
                continue

            schema = rows[0]["schema"]
            print_partition_table(rows, f"Current partitions: {schema}.{table}")

            # Determine which months to create
            existing_months = set()
            for r in rows:
                m = parse_month_from_name(r["partition_name"])
                if m:
                    existing_months.add(m)

            create_ddl = []
            for i in range(args.create_ahead + 1):
                target = date(today.year, today.month, 1) + relativedelta(months=i)
                if target not in existing_months:
                    create_ddl.append(generate_create_ddl(schema, table, target))

            drop_ddl = []
            cutoff = date(today.year, today.month, 1) - relativedelta(months=args.retention)
            for r in rows:
                m = parse_month_from_name(r["partition_name"])
                if m and m < cutoff:
                    drop_ddl.append(generate_drop_ddl(schema, r["partition_name"]))

            if create_ddl:
                print(f"\n  DDL - Create {len(create_ddl)} future partition(s):")
                for stmt in create_ddl:
                    print(f"    {stmt}")
                all_ddl.extend(create_ddl)
            else:
                print(f"\n  Future partitions: all present up to +{args.create_ahead} months")

            if drop_ddl:
                print(f"\n  DDL - Drop {len(drop_ddl)} expired partition(s) (older than {args.retention}m):")
                for stmt in drop_ddl:
                    print(f"    {stmt}")
                all_ddl.extend(drop_ddl)
            else:
                print(f"  No partitions eligible for dropping (retention={args.retention}m)")

    if args.execute and all_ddl:
        print(f"\n  Executing {len(all_ddl)} DDL statement(s)...")
        try:
            with conn.cursor() as cur:
                for stmt in all_ddl:
                    cur.execute(stmt)
                    print(f"  OK: {stmt[:80]}")
            conn.commit()
            print("  All DDL committed.")
        except Exception as exc:
            conn.rollback()
            print(f"  ERROR: {exc}")
            sys.exit(1)
    elif not args.execute:
        print(f"\n  [DRY RUN] {len(all_ddl)} statement(s) generated. Use --execute to apply.")

    conn.close()
    print("=" * 65)


if __name__ == "__main__":
    main()
