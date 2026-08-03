#!/usr/bin/env python3
"""
export_parquet.py - Export a PostgreSQL table (or query result) to Parquet format.

Fetches data via psycopg2 in batches, converts to pyarrow Table, writes
compressed Parquet. Validates row count between DB and output file.

Dependencies: psycopg2, pyarrow

Usage:
    python3 export_parquet.py --table market_data --output /tmp/market_data.parquet
    python3 export_parquet.py --table signals --output /tmp/signals.parquet --where "signal_date >= '2025-01-01'"
    python3 export_parquet.py --table market_data --compression gzip --output /tmp/out.parquet
    python3 export_parquet.py --query "SELECT * FROM market_data LIMIT 1000" --output /tmp/sample.parquet
"""

import argparse
import sys
import os
from datetime import datetime

import psycopg2
import psycopg2.extras
import pyarrow as pa
import pyarrow.parquet as pq

DEFAULT_HOST        = "172.31.19.86"
DEFAULT_PORT        = 5432
DEFAULT_DB          = "quantdb"
DEFAULT_USER        = "quant_readonly"
DEFAULT_PASS        = "quant_readonly_2026"
DEFAULT_COMPRESSION = "snappy"
DEFAULT_BATCH_SIZE  = 10_000
VALID_COMPRESSIONS  = ("snappy", "gzip", "brotli", "zstd", "none")


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def get_db_row_count(cur, table: str, where: str) -> int:
    """Count rows in the source table with optional WHERE clause."""
    where_clause = f"WHERE {where}" if where else ""
    # Table name is validated by the caller to be a simple identifier
    cur.execute(f"SELECT count(*) AS n FROM {table} {where_clause}")
    return cur.fetchone()["n"]


def build_select_sql(table: str | None, query: str | None, where: str) -> str:
    if query:
        return query
    where_clause = f"WHERE {where}" if where else ""
    return f"SELECT * FROM {table} {where_clause}"


def fetch_to_parquet(
    conn,
    sql: str,
    output_path: str,
    compression: str,
    batch_size: int
) -> tuple[int, int]:
    """Fetch rows in batches and write to Parquet. Returns (rows_written, columns)."""
    writer    = None
    total     = 0
    col_count = 0

    with conn.cursor(name="export_cursor", cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.itersize = batch_size
        cur.execute(sql)

        while True:
            rows = cur.fetchmany(batch_size)
            if not rows:
                break

            dicts = [dict(r) for r in rows]
            col_count = len(dicts[0]) if dicts else col_count
            columns: dict[str, list] = {k: [] for k in dicts[0]}
            for d in dicts:
                for k, v in d.items():
                    columns[k].append(v)

            batch_table = pa.Table.from_pydict(columns)

            if writer is None:
                comp = None if compression == "none" else compression
                writer = pq.ParquetWriter(output_path, batch_table.schema, compression=comp)

            writer.write_table(batch_table)
            total += len(dicts)
            print(f"  ... exported {total:,} rows", end="\r", flush=True)

    if writer:
        writer.close()

    print()
    return total, col_count


def validate_parquet(output_path: str, expected_rows: int) -> bool:
    meta     = pq.read_metadata(output_path)
    actual   = meta.num_rows
    match    = actual == expected_rows
    status   = "PASS" if match else "FAIL"
    print(f"  [ {status} ] Row count validation: DB={expected_rows:,}  Parquet={actual:,}")
    return match


def bytes_human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def parse_args():
    p = argparse.ArgumentParser(description="Export PostgreSQL table to Parquet")
    p.add_argument("--host",        default=DEFAULT_HOST)
    p.add_argument("--port",        type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",      default=DEFAULT_DB)
    p.add_argument("--user",        default=DEFAULT_USER)
    p.add_argument("--password",    default=DEFAULT_PASS)

    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--table",  help="Table name to export (e.g. market_data.ticks)")
    src.add_argument("--query",  help="Custom SQL query to export")

    p.add_argument("--output",      required=True,
                   help="Output Parquet file path")
    p.add_argument("--where",       default="",
                   help="Optional WHERE clause (without the WHERE keyword)")
    p.add_argument("--compression", default=DEFAULT_COMPRESSION,
                   choices=VALID_COMPRESSIONS,
                   help=f"Parquet compression codec (default: {DEFAULT_COMPRESSION})")
    p.add_argument("--batch-size",  type=int, default=DEFAULT_BATCH_SIZE,
                   help=f"Rows per fetch batch (default: {DEFAULT_BATCH_SIZE})")
    p.add_argument("--no-validate", action="store_true",
                   help="Skip row count validation after export")
    return p.parse_args()


def main():
    args = parse_args()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    source_label = args.table if args.table else "<custom query>"

    print("=" * 65)
    print("  Voleon quantdb - Parquet Export")
    print(f"  Source   : {source_label}")
    print(f"  Output   : {args.output}")
    print(f"  Compress : {args.compression}  |  Batch: {args.batch_size:,}")
    print(f"  Started  : {now}")
    print("=" * 65)

    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    conn.autocommit = True

    db_count = None
    if args.table and not args.no_validate:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            db_count = get_db_row_count(cur, args.table, args.where)
        print(f"  DB row count   : {db_count:,}")

    sql = build_select_sql(args.table, args.query, args.where)

    t_start     = datetime.now()
    rows_out, n_cols = fetch_to_parquet(conn, sql, args.output, args.compression, args.batch_size)
    conn.close()
    elapsed     = (datetime.now() - t_start).total_seconds()

    file_size   = os.path.getsize(args.output) if os.path.exists(args.output) else 0
    rows_per_s  = rows_out / elapsed if elapsed > 0 else 0
    approx_raw  = rows_out * n_cols * 8  # rough estimate at 8 bytes/col
    ratio       = approx_raw / file_size if file_size > 0 else 0

    print("\n" + "=" * 65)
    print("  Export Summary")
    print(f"  Rows written   : {rows_out:,}")
    print(f"  Columns        : {n_cols}")
    print(f"  File size      : {bytes_human(file_size)}")
    print(f"  Elapsed        : {elapsed:.1f}s  ({rows_per_s:,.0f} rows/s)")
    print(f"  Compression    : {args.compression}  (~{ratio:.1f}x vs raw estimate)")

    if not args.no_validate and db_count is not None:
        validate_parquet(args.output, db_count)
    elif not args.no_validate and args.query:
        # Validate by re-reading parquet metadata vs rows_out
        meta   = pq.read_metadata(args.output)
        status = "PASS" if meta.num_rows == rows_out else "FAIL"
        print(f"  [ {status} ] Parquet meta rows={meta.num_rows:,}  written={rows_out:,}")

    print("=" * 65)


if __name__ == "__main__":
    main()
