# BUILD 04: Bulk Operations and pg_stat Monitoring

**Module:** 00c - Python DBA Automation
**Prerequisites:** BUILD 01-03 (Connecting, Health Checks, Automation)
**Time:** 60-75 minutes

As a DBA, you deal with bulk data loading and performance monitoring constantly. This guide covers reading PostgreSQL statistics views, bulk INSERT methods, transaction control, and building a metrics collector that snapshots key stats to CSV every 60 seconds.

---

## Step 1: Reading pg_stat_user_tables - Sequential vs Index Scans

**DBA Analogy:** You check the seq_scan to idx_scan ratio to decide if a table needs better indexes. Same query, now in Python where you can track it over time.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT schemaname || '.' || relname as table_name,
                   seq_scan,
                   idx_scan,
                   CASE WHEN seq_scan + idx_scan > 0
                        THEN round(100.0 * seq_scan / (seq_scan + idx_scan), 1)
                        ELSE 0
                   END as seq_pct,
                   seq_tup_read,
                   idx_tup_fetch,
                   n_live_tup
            FROM pg_stat_user_tables
            WHERE seq_scan + idx_scan > 0
            ORDER BY seq_scan DESC
            LIMIT 10
        ''')
        rows = cur.fetchall()

        if rows:
            print(f'{\"Table\":<35} {\"SeqScan\":<10} {\"IdxScan\":<10} {\"Seq%\":<8} {\"Rows\":<12}')
            print('-' * 75)
            for table, seq, idx, pct, seq_read, idx_fetch, rows_count in rows:
                flag = ' *** NEEDS INDEX' if pct > 90 and rows_count > 10000 else ''
                print(f'{table:<35} {seq:<10} {idx:<10} {pct:<8} {rows_count:<12}{flag}')
        else:
            print('No user table scan data available')
"
```

Expected output (yours will differ):

```
Table                               SeqScan    IdxScan    Seq%     Rows
---------------------------------------------------------------------------
public.orders                       1542       89023      1.7      500000
public.sessions                     8923       245        97.3     15000    *** NEEDS INDEX
```

Tables with high `seq_pct` and many rows are candidates for new indexes. You already know this - now you can track it automatically.

---

## Step 2: Reading pg_stat_bgwriter - Checkpoint Stats

**DBA Analogy:** You check `pg_stat_bgwriter` when checkpoint tuning. The ratio of `buffers_checkpoint` to `buffers_clean` to `buffers_backend` tells you if your checkpoint_completion_target and shared_buffers are tuned correctly.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        # PostgreSQL 17+ moved checkpoint columns to pg_stat_checkpointer
        cur.execute('SHOW server_version_num')
        pg_version = int(cur.fetchone()[0])

        if pg_version >= 170000:
            cur.execute('''
                SELECT c.num_timed as checkpoints_timed,
                       c.num_requested as checkpoints_req,
                       c.buffers_written as buffers_checkpoint,
                       b.buffers_clean,
                       b.buffers_alloc as buffers_backend,
                       b.stats_reset
                FROM pg_stat_checkpointer c, pg_stat_bgwriter b
            ''')
        else:
            cur.execute('''
                SELECT checkpoints_timed,
                       checkpoints_req,
                       buffers_checkpoint,
                       buffers_clean,
                       buffers_backend,
                       stats_reset
                FROM pg_stat_bgwriter
            ''')
        row = cur.fetchone()
        timed, req, buf_ckpt, buf_clean, buf_backend, reset = row

        total_ckpt = timed + req
        total_buf = buf_ckpt + buf_clean + buf_backend

        print('Checkpoint Statistics:')
        print(f'  Timed checkpoints:    {timed}')
        print(f'  Requested checkpoints: {req}')
        if total_ckpt > 0:
            req_pct = 100.0 * req / total_ckpt
            print(f'  Requested ratio:      {req_pct:.1f}% (should be < 10%)')

        print(f'\\nBuffer Write Sources:')
        if total_buf > 0:
            print(f'  Checkpoint: {buf_ckpt} ({100.0*buf_ckpt/total_buf:.1f}%)')
            print(f'  Bgwriter:   {buf_clean} ({100.0*buf_clean/total_buf:.1f}%)')
            print(f'  Backend:    {buf_backend} ({100.0*buf_backend/total_buf:.1f}%)')
            if buf_backend / total_buf > 0.2:
                print('  WARNING: High backend writes - increase shared_buffers or tune bgwriter')

        print(f'\\nStats since: {reset}')
"
```

Expected output (yours will differ):

```
Checkpoint Statistics:
  Timed checkpoints:    142
  Requested checkpoints: 3
  Requested ratio:      2.1% (should be < 10%)

Buffer Write Sources:
  Checkpoint: 89234 (72.3%)
  Bgwriter:   24567 (19.9%)
  Backend:    9654 (7.8%)

Stats since: 2026-06-01 00:00:00+00
```

**Key insight:** If `Backend` writes are above 20%, backends are writing dirty buffers themselves instead of waiting for the bgwriter or checkpointer. That means I/O spikes during queries. You tune `bgwriter_lru_maxpages` and `bgwriter_delay` to fix it.

---

## Step 3: Reading pg_stat_statements - Top Slow Queries

This requires the `pg_stat_statements` extension. If it is not loaded, the query will fail with a clear error.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        try:
            cur.execute('''
                SELECT left(query, 80) as query,
                       calls,
                       round(total_exec_time::numeric, 2) as total_ms,
                       round(mean_exec_time::numeric, 2) as mean_ms,
                       rows
                FROM pg_stat_statements
                WHERE userid != 10  -- exclude postgres bootstrap
                ORDER BY total_exec_time DESC
                LIMIT 10
            ''')
            rows = cur.fetchall()

            if rows:
                print(f'{\"Query\":<60} {\"Calls\":<10} {\"Total(ms)\":<12} {\"Mean(ms)\":<10}')
                print('-' * 92)
                for query, calls, total, mean, row_count in rows:
                    q = query.replace('\\n', ' ')[:58]
                    print(f'{q:<60} {calls:<10} {total:<12} {mean:<10}')
            else:
                print('No statements recorded yet')

        except psycopg2.errors.UndefinedTable:
            print('pg_stat_statements extension not installed.')
            print('To install: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;')
            print('And add to shared_preload_libraries in postgresql.conf')
"
```

Expected output (yours will differ):

```
pg_stat_statements extension not installed.
To install: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
And add to shared_preload_libraries in postgresql.conf
```

Note the `try/except psycopg2.errors.UndefinedTable` - this is how you handle a specific error type. Not a generic `except Exception`, but the exact error you expect. This is important for robust scripts.

---

## Step 4: Bulk INSERT with executemany()

**DBA Analogy:** When you INSERT thousands of rows, you do not run individual INSERT statements. You use COPY or multi-value INSERT. `executemany()` is the multi-value approach from Python.

First, create a test table:

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute('''
            CREATE TABLE IF NOT EXISTS test_bulk (
                id serial PRIMARY KEY,
                name text NOT NULL,
                value numeric,
                created_at timestamp DEFAULT now()
            )
        ''')
        cur.execute('TRUNCATE test_bulk')
        print('Table test_bulk ready')
"
```

Expected output (yours will differ):

```
Table test_bulk ready
```

Now bulk insert with `executemany()`:

```bash
python3 -c "
import time
import psycopg2
from contextlib import closing

# Generate 10000 rows of test data
data = [(f'item_{i}', i * 1.5) for i in range(10000)]

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn:  # auto-commit on success
        with conn.cursor() as cur:
            start = time.time()
            cur.executemany(
                'INSERT INTO test_bulk (name, value) VALUES (%s, %s)',
                data
            )
            elapsed = time.time() - start

            cur.execute('SELECT count(*) FROM test_bulk')
            count = cur.fetchone()[0]
            print(f'Inserted {count} rows in {elapsed:.2f}s')
            print(f'Rate: {count/elapsed:.0f} rows/sec')
"
```

Expected output (yours will differ):

```
Inserted 10000 rows in 1.45s
Rate: 6896 rows/sec
```

`executemany()` is convenient but not the fastest. It sends individual INSERT statements. For truly large bulk loads, use `copy_expert()`.

---

## Step 5: Bulk INSERT with copy_expert() - The Fastest Method

**DBA Analogy:** This is COPY FROM STDIN - the same command you use with `\copy` in psql or `pg_restore`. It is the fastest way to load data into PostgreSQL.

```bash
python3 -c "
import io
import time
import psycopg2
from contextlib import closing

# Generate test data as a tab-separated string (like COPY format)
rows = 10000
data = io.StringIO()
for i in range(rows):
    data.write(f'item_{i}\t{i * 1.5}\n')
data.seek(0)  # rewind to start

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn:
        with conn.cursor() as cur:
            cur.execute('TRUNCATE test_bulk')

            start = time.time()
            cur.copy_expert(
                \"\"\"COPY test_bulk (name, value) FROM STDIN WITH (FORMAT text, DELIMITER E'\\\\t')\"\"\",
                data
            )
            elapsed = time.time() - start

            cur.execute('SELECT count(*) FROM test_bulk')
            count = cur.fetchone()[0]
            print(f'COPY loaded {count} rows in {elapsed:.3f}s')
            print(f'Rate: {count/elapsed:.0f} rows/sec')
"
```

Expected output (yours will differ):

```
COPY loaded 10000 rows in 0.085s
Rate: 117647 rows/sec
```

Compare: `executemany()` got around 7,000 rows/sec. `copy_expert()` gets over 100,000 rows/sec. That is a 15x difference. For bulk loads, always use COPY.

You can also use CSV format:

```python
cur.copy_expert(
    "COPY test_bulk (name, value) FROM STDIN WITH (FORMAT csv, HEADER false)",
    csv_file_object
)
```

---

## Step 6: Transactions - Autocommit vs Manual Commit/Rollback

**DBA Analogy:** By default, psycopg2 wraps everything in a transaction - just like `BEGIN` is implicit in psql. You must `COMMIT` or `ROLLBACK` explicitly. If you want each statement to auto-commit (like `\set AUTOCOMMIT on` in psql), you set `autocommit = True`.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    # Default: autocommit is OFF - everything is in a transaction
    print('Autocommit:', conn.autocommit)

    with conn.cursor() as cur:
        # This INSERT is inside an implicit transaction
        cur.execute(\"INSERT INTO test_bulk (name, value) VALUES ('tx_test', 999)\")

        # Check - row is visible WITHIN this transaction
        cur.execute(\"SELECT count(*) FROM test_bulk WHERE name = 'tx_test'\")
        print('Before commit (inside tx):', cur.fetchone()[0])

        # ROLLBACK - undo the insert
        conn.rollback()

        cur.execute(\"SELECT count(*) FROM test_bulk WHERE name = 'tx_test'\")
        print('After rollback:', cur.fetchone()[0])

        # Now INSERT and COMMIT
        cur.execute(\"INSERT INTO test_bulk (name, value) VALUES ('tx_test', 999)\")
        conn.commit()

        cur.execute(\"SELECT count(*) FROM test_bulk WHERE name = 'tx_test'\")
        print('After commit:', cur.fetchone()[0])
"
```

Expected output (yours will differ):

```
Autocommit: False
Before commit (inside tx): 1
After rollback: 0
After commit: 1
```

**When to use autocommit:**
- For `VACUUM`, `CREATE DATABASE`, `CREATE INDEX CONCURRENTLY` - these cannot run inside a transaction
- For monitoring queries where you do not want idle-in-transaction connections

```python
conn.autocommit = True  # Each statement commits immediately
```

**When to use manual transactions (the default):**
- For any multi-statement operation that should be atomic
- For INSERT/UPDATE/DELETE that might need rollback

The `with conn:` pattern from BUILD 01 handles this cleanly - it commits on success, rolls back on exception.

---

## Step 7: Connection Pooling Concept

Every time you call `psycopg2.connect()`, Python opens a new TCP connection to PostgreSQL, the server forks a new backend process, and they do authentication. That takes 50-200ms. If your script opens and closes connections in a loop, that overhead adds up fast.

**DBA Analogy:** This is why you use PgBouncer or Pgpool-II in production. Connection pooling keeps a set of connections open and reuses them.

For Python scripts, there are two approaches:

**Simple approach - reuse one connection:**

```python
# Open once at the start, close at the end
conn = psycopg2.connect(...)
try:
    # Use conn for all operations
    do_check_1(conn)
    do_check_2(conn)
    do_check_3(conn)
finally:
    conn.close()
```

**Pool approach - for multi-threaded scripts:**

```python
from psycopg2 import pool

# Create a pool of 5-20 connections
connection_pool = pool.ThreadedConnectionPool(
    minconn=5,
    maxconn=20,
    host='localhost',
    dbname='postgres',
    user='postgres'
)

# Get a connection from the pool
conn = connection_pool.getconn()
try:
    # Use it
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
finally:
    # Return it to the pool (does NOT close it)
    connection_pool.putconn(conn)
```

For the single-threaded DBA scripts we are writing, the simple approach (one connection, reuse it) is sufficient. Connection pools matter more for web applications and multi-threaded tools.

---

## Step 8: Writing Results to CSV

**DBA Analogy:** This is like `\copy (SELECT ...) TO '/tmp/report.csv' CSV HEADER` in psql. But from Python, you can add logic, formatting, and timestamps.

```bash
python3 -c "
import csv
import psycopg2
from datetime import datetime
from contextlib import closing

output_file = '/tmp/db_metrics.csv'

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT d.datname,
                   pg_database_size(d.datname) as size_bytes,
                   sd.numbackends
            FROM pg_database d
            JOIN pg_stat_database sd ON d.oid = sd.datid
            WHERE d.datistemplate = false
        ''')
        rows = cur.fetchall()

        # Write CSV with timestamp column added
        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'database', 'size_bytes', 'connections'])
            ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            for datname, size, backends in rows:
                writer.writerow([ts, datname, size, backends])

        print(f'Wrote {len(rows)} rows to {output_file}')

# Verify
with open(output_file) as f:
    print(f.read())
"
```

Expected output (yours will differ):

```
Wrote 1 rows to /tmp/db_metrics.csv
timestamp,database,size_bytes,connections
2026-06-09 14:30:00,postgres,7946752,5
```

For appending to an existing CSV (to build time-series data):

```python
# 'a' mode appends, does not overwrite
with open(output_file, 'a', newline='') as f:
    writer = csv.writer(f)
    # Do NOT write header again - it is already there
    writer.writerow([ts, datname, size, backends])
```

---

## Step 9: Building a Metrics Collector with time.sleep

**DBA Analogy:** This is like having a cron job that runs every minute, but more precise - it runs as a continuous process that wakes up every N seconds.

```bash
python3 -c "
import time

# Simple loop that runs every 5 seconds (demo uses 3 iterations)
interval = 5
iterations = 3

for i in range(iterations):
    print(f'Snapshot {i+1} at {time.strftime(\"%H:%M:%S\")}')
    if i < iterations - 1:  # don't sleep after last iteration
        time.sleep(interval)

print('Done')
"
```

Expected output (yours will differ):

```
Snapshot 1 at 14:30:00
Snapshot 2 at 14:30:05
Snapshot 3 at 14:30:10
Done
```

The `time.sleep(N)` pauses execution for N seconds. Combined with a `while True` loop, this gives you a continuous collector. Press Ctrl+C to stop it.

---

## Step 10: Practical - Build pg_stat_collector.py

This script snapshots key PostgreSQL metrics to CSV every 60 seconds. Create it with `vi`:

```bash
vi ~/pg_stat_collector.py
```

Enter the following content:

```python
#!/usr/bin/env python3
"""PostgreSQL Metrics Collector - snapshots key stats to CSV every N seconds."""

import os
import sys
import csv
import time
import logging
import signal
from datetime import datetime
from contextlib import closing
import psycopg2

# ── Configuration ────────────────────────────────────────
INTERVAL_SECONDS = 60
OUTPUT_DIR = '/tmp/pg_metrics'
MAX_FILE_SIZE_MB = 100  # Rotate after this size

# ── Logging ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('pg_collector')

# ── Graceful shutdown ────────────────────────────────────
running = True


def signal_handler(signum: int, frame: object) -> None:
    """Handle Ctrl+C gracefully."""
    global running
    logger.info('Received shutdown signal, finishing current snapshot...')
    running = False


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


def get_connection() -> psycopg2.extensions.connection:
    """Create connection from environment variables."""
    try:
        return psycopg2.connect(
            host=os.environ.get('PGHOST', 'localhost'),
            port=os.environ.get('PGPORT', '5432'),
            dbname=os.environ.get('PGDATABASE', 'postgres'),
            user=os.environ.get('PGUSER', 'postgres'),
            password=os.environ.get('PGPASSWORD', '')
        )
    except psycopg2.OperationalError as e:
        logger.critical(f'Cannot connect: {e}')
        sys.exit(1)


def collect_connection_stats(cur) -> dict:
    """Snapshot connection statistics."""
    cur.execute('''
        SELECT count(*) as total,
               count(*) FILTER (WHERE state = 'active') as active,
               count(*) FILTER (WHERE state = 'idle') as idle,
               count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_tx,
               count(*) FILTER (WHERE wait_event_type IS NOT NULL) as waiting
        FROM pg_stat_activity
        WHERE backend_type = 'client backend'
    ''')
    total, active, idle, idle_in_tx, waiting = cur.fetchone()

    cur.execute('SHOW max_connections')
    max_conn = int(cur.fetchone()[0])

    return {
        'conn_total': total,
        'conn_active': active,
        'conn_idle': idle,
        'conn_idle_in_tx': idle_in_tx,
        'conn_waiting': waiting,
        'conn_max': max_conn,
        'conn_pct': round(100.0 * total / max_conn, 1)
    }


def collect_database_stats(cur) -> dict:
    """Snapshot database-level statistics."""
    cur.execute('''
        SELECT sum(xact_commit) as commits,
               sum(xact_rollback) as rollbacks,
               sum(tup_returned) as tup_returned,
               sum(tup_fetched) as tup_fetched,
               sum(tup_inserted) as tup_inserted,
               sum(tup_updated) as tup_updated,
               sum(tup_deleted) as tup_deleted,
               sum(blks_read) as blks_read,
               sum(blks_hit) as blks_hit
        FROM pg_stat_database
        WHERE datname NOT LIKE 'template%%'
    ''')
    row = cur.fetchone()
    commits, rollbacks, returned, fetched, inserted, updated, deleted, read, hit = row

    cache_hit = round(100.0 * float(hit) / float(hit + read), 2) if (hit + read) > 0 else 0

    return {
        'txn_commits': commits or 0,
        'txn_rollbacks': rollbacks or 0,
        'tup_returned': returned or 0,
        'tup_fetched': fetched or 0,
        'tup_inserted': inserted or 0,
        'tup_updated': updated or 0,
        'tup_deleted': deleted or 0,
        'blks_read': read or 0,
        'blks_hit': hit or 0,
        'cache_hit_pct': cache_hit
    }


def collect_bgwriter_stats(cur) -> dict:
    """Snapshot bgwriter/checkpointer statistics."""
    # PostgreSQL 17+ moved checkpoint columns to pg_stat_checkpointer
    cur.execute('SHOW server_version_num')
    pg_version = int(cur.fetchone()[0])

    if pg_version >= 170000:
        cur.execute('''
            SELECT c.num_timed as checkpoints_timed,
                   c.num_requested as checkpoints_req,
                   c.buffers_written as buffers_checkpoint,
                   b.buffers_clean,
                   b.buffers_alloc as buffers_backend
            FROM pg_stat_checkpointer c, pg_stat_bgwriter b
        ''')
    else:
        cur.execute('''
            SELECT checkpoints_timed,
                   checkpoints_req,
                   buffers_checkpoint,
                   buffers_clean,
                   buffers_backend
            FROM pg_stat_bgwriter
        ''')
    timed, req, buf_ckpt, buf_clean, buf_backend = cur.fetchone()

    return {
        'ckpt_timed': timed,
        'ckpt_requested': req,
        'buf_checkpoint': buf_ckpt,
        'buf_bgwriter': buf_clean,
        'buf_backend': buf_backend
    }


def collect_replication_stats(cur) -> dict:
    """Snapshot replication lag (if applicable)."""
    cur.execute('''
        SELECT count(*) as replica_count,
               coalesce(max(pg_wal_lsn_diff(sent_lsn, replay_lsn)), 0) as max_lag_bytes
        FROM pg_stat_replication
    ''')
    count, max_lag = cur.fetchone()

    return {
        'replica_count': count,
        'max_lag_bytes': max_lag
    }


def take_snapshot(conn) -> dict:
    """Collect all metrics in one snapshot."""
    metrics = {'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

    with conn.cursor() as cur:
        metrics.update(collect_connection_stats(cur))
        metrics.update(collect_database_stats(cur))
        metrics.update(collect_bgwriter_stats(cur))
        metrics.update(collect_replication_stats(cur))

    return metrics


def get_csv_path() -> str:
    """Get the CSV file path for today."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    date_str = datetime.now().strftime('%Y-%m-%d')
    return os.path.join(OUTPUT_DIR, f'pg_metrics_{date_str}.csv')


def write_snapshot(metrics: dict) -> None:
    """Append a snapshot to the daily CSV file."""
    csv_path = get_csv_path()
    file_exists = os.path.exists(csv_path)

    with open(csv_path, 'a', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=metrics.keys())
        if not file_exists:
            writer.writeheader()
        writer.writerow(metrics)


def main() -> None:
    """Main collection loop."""
    logger.info(f'Starting pg_stat_collector (interval: {INTERVAL_SECONDS}s)')
    logger.info(f'Output directory: {OUTPUT_DIR}')
    logger.info('Press Ctrl+C to stop')

    conn = get_connection()
    conn.autocommit = True  # Read-only queries, no transaction needed
    snapshot_count = 0

    try:
        while running:
            try:
                metrics = take_snapshot(conn)
                write_snapshot(metrics)
                snapshot_count += 1

                # Print summary to console
                logger.info(
                    f'Snapshot #{snapshot_count}: '
                    f'conns={metrics["conn_total"]}/{metrics["conn_max"]} '
                    f'cache={metrics["cache_hit_pct"]}% '
                    f'commits={metrics["txn_commits"]} '
                    f'lag={metrics["max_lag_bytes"]}B'
                )

            except psycopg2.OperationalError as e:
                logger.error(f'Connection lost: {e}')
                logger.info('Reconnecting in 10s...')
                time.sleep(10)
                try:
                    conn.close()
                except Exception:
                    pass
                conn = get_connection()
                conn.autocommit = True
                continue

            # Sleep in 1-second intervals so Ctrl+C is responsive
            for _ in range(INTERVAL_SECONDS):
                if not running:
                    break
                time.sleep(1)

    finally:
        conn.close()
        logger.info(f'Stopped after {snapshot_count} snapshots')
        logger.info(f'Data saved to {get_csv_path()}')


if __name__ == '__main__':
    main()
```

Save and exit vi (`:wq`).

Make it executable:

```bash
chmod +x ~/pg_stat_collector.py
```

Run it (press Ctrl+C after a few snapshots to stop):

```bash
python3 ~/pg_stat_collector.py
```

Expected output (yours will differ):

```
2026-06-09 14:30:00 [INFO] Starting pg_stat_collector (interval: 60s)
2026-06-09 14:30:00 [INFO] Output directory: /tmp/pg_metrics
2026-06-09 14:30:00 [INFO] Press Ctrl+C to stop
2026-06-09 14:30:00 [INFO] Snapshot #1: conns=5/100 cache=99.85% commits=14523 lag=0B
2026-06-09 14:31:00 [INFO] Snapshot #2: conns=5/100 cache=99.85% commits=14530 lag=0B
^C
2026-06-09 14:31:15 [INFO] Received shutdown signal, finishing current snapshot...
2026-06-09 14:31:15 [INFO] Stopped after 2 snapshots
2026-06-09 14:31:15 [INFO] Data saved to /tmp/pg_metrics/pg_metrics_2026-06-09.csv
```

Check the CSV:

```bash
cat /tmp/pg_metrics/pg_metrics_2026-06-09.csv
```

Expected output (yours will differ):

```
timestamp,conn_total,conn_active,conn_idle,conn_idle_in_tx,conn_waiting,conn_max,conn_pct,...
2026-06-09 14:30:00,5,1,3,0,0,100,5.0,...
2026-06-09 14:31:00,5,1,3,0,0,100,5.0,...
```

**Key design decisions:**
- `signal.signal()` handles Ctrl+C gracefully - no half-written CSV rows
- `conn.autocommit = True` because all queries are read-only - no idle-in-transaction
- Reconnection logic handles the case where PostgreSQL restarts during collection
- Daily CSV files prevent any single file from growing too large
- Sleep in 1-second intervals so shutdown is responsive (not stuck in a 60-second sleep)

For testing, you can change `INTERVAL_SECONDS = 5` to see snapshots faster.

---

## What You Learned

| Concept                      | DBA Analogy                                  | Python Code                                 |
|------------------------------|----------------------------------------------|---------------------------------------------|
| pg_stat_user_tables          | seq_scan vs idx_scan analysis                | Query + ratio calculation                   |
| pg_stat_bgwriter             | Checkpoint tuning metrics                    | Query + buffer source percentages           |
| pg_stat_statements           | Top slow queries report                      | Query with try/except for missing extension |
| executemany()                | Multi-row INSERT                             | `cur.executemany(sql, data_list)`           |
| copy_expert()                | COPY FROM STDIN (fastest bulk load)          | `cur.copy_expert(copy_sql, file_obj)`       |
| autocommit                   | `\set AUTOCOMMIT on` in psql                | `conn.autocommit = True`                    |
| Manual commit/rollback       | BEGIN / COMMIT / ROLLBACK                    | `conn.commit()` / `conn.rollback()`         |
| Connection pooling           | PgBouncer / Pgpool-II                        | `psycopg2.pool.ThreadedConnectionPool`      |
| CSV output                   | `\copy ... TO ... CSV`                       | `csv.writer()` / `csv.DictWriter()`         |
| time.sleep loop              | Continuous monitoring daemon                 | `while running: collect(); time.sleep(N)`   |
| Signal handling              | Graceful shutdown on SIGTERM                 | `signal.signal(signal.SIGINT, handler)`     |
