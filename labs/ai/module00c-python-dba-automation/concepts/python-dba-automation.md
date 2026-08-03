# Concepts Reference: Python DBA Automation

**Module:** 00c - Python DBA Automation
**Covers:** BUILD 01-04

Use this as a quick-reference when writing DBA automation scripts. Everything here was covered in the BUILD guides - this page collects it in one place for copy-paste.

---

## psycopg2 Connection Cheat Sheet

### Basic Connection

```python
import psycopg2
from contextlib import closing

# From parameters
conn = psycopg2.connect(
    host='localhost',
    port=5432,
    dbname='postgres',
    user='postgres',
    password='secret'
)

# From connection string
conn = psycopg2.connect("host=localhost dbname=postgres user=postgres")

# From URI
conn = psycopg2.connect("postgresql://postgres:secret@localhost:5432/postgres")

# From environment variables (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD)
conn = psycopg2.connect()
```

### Connection Patterns

```python
# Pattern 1: Simple - open, use, close
conn = psycopg2.connect(...)
try:
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
finally:
    conn.close()

# Pattern 2: Auto-commit/rollback (does NOT auto-close)
with psycopg2.connect(...) as conn:
    with conn.cursor() as cur:
        cur.execute("INSERT INTO t VALUES (1)")
    # COMMIT on success, ROLLBACK on exception
conn.close()  # Must close separately

# Pattern 3: Full auto-close
with closing(psycopg2.connect(...)) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
# Connection closed automatically

# Pattern 4: Autocommit for DDL / VACUUM
conn = psycopg2.connect(...)
conn.autocommit = True
```

### Cursor Operations

```python
cur = conn.cursor()

# Execute
cur.execute("SELECT datname FROM pg_database")

# Fetch
row = cur.fetchone()          # One row (or None)
rows = cur.fetchall()         # All rows (list of tuples)
batch = cur.fetchmany(100)    # N rows at a time

# Iterate directly (memory efficient)
for row in cur:
    print(row)

# Column names
names = [desc[0] for desc in cur.description]

# Row count (after INSERT/UPDATE/DELETE)
print(cur.rowcount)
```

---

## Parameterized Query Patterns

**Rule: ALWAYS use %s placeholders. NEVER use f-strings for SQL.**

```python
# Single value (note trailing comma in tuple)
cur.execute("SELECT * FROM users WHERE id = %s", (42,))

# Multiple values
cur.execute(
    "SELECT * FROM users WHERE name = %s AND age > %s",
    ('alice', 30)
)

# IN clause
cur.execute(
    "SELECT * FROM users WHERE id IN %s",
    ((1, 2, 3),)
)

# LIKE pattern
cur.execute(
    "SELECT * FROM users WHERE name LIKE %s",
    ('%ali%',)
)

# NULL check (use IS NULL, not = %s with None)
cur.execute("SELECT * FROM users WHERE email IS NULL")

# Insert with RETURNING
cur.execute(
    "INSERT INTO users (name) VALUES (%s) RETURNING id",
    ('alice',)
)
new_id = cur.fetchone()[0]

# Bulk insert
data = [('alice', 30), ('bob', 25), ('carol', 35)]
cur.executemany(
    "INSERT INTO users (name, age) VALUES (%s, %s)",
    data
)

# COPY (fastest bulk load)
import io
buffer = io.StringIO("alice\t30\nbob\t25\n")
cur.copy_expert("COPY users (name, age) FROM STDIN", buffer)
```

---

## Common pg_stat Views

| View                        | What It Tells You                          | Key Columns                                    |
|-----------------------------|--------------------------------------------|-------------------------------------------------|
| `pg_stat_activity`          | Current sessions and queries               | pid, state, query, query_start, wait_event      |
| `pg_stat_database`          | Per-database transaction and I/O stats     | xact_commit, xact_rollback, blks_hit, blks_read |
| `pg_stat_user_tables`       | Per-table scan, tuple, and vacuum stats    | seq_scan, idx_scan, n_dead_tup, last_autovacuum |
| `pg_stat_user_indexes`      | Per-index usage stats                      | idx_scan, idx_tup_read, idx_tup_fetch           |
| `pg_stat_bgwriter`          | Checkpoint and buffer write stats          | checkpoints_timed, buffers_checkpoint, buffers_backend |
| `pg_stat_replication`       | Replication status and lag                 | state, sent_lsn, replay_lsn, client_addr        |
| `pg_stat_statements`        | Query-level performance stats (extension)  | query, calls, total_exec_time, mean_exec_time   |

### Key Derived Metrics

```sql
-- Cache hit ratio (should be > 99%)
SELECT round(100.0 * blks_hit / (blks_hit + blks_read), 2) FROM pg_stat_database;

-- Connection usage percentage
SELECT round(100.0 * count(*) / current_setting('max_connections')::int, 1) FROM pg_stat_activity;

-- Dead tuple ratio (bloat indicator)
SELECT round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1) FROM pg_stat_user_tables;

-- Sequential scan ratio (index coverage)
SELECT round(100.0 * seq_scan / (seq_scan + idx_scan), 1) FROM pg_stat_user_tables;

-- Replication lag in bytes
SELECT pg_wal_lsn_diff(sent_lsn, replay_lsn) FROM pg_stat_replication;
```

---

## Script Structure Template

Every DBA automation script follows this structure:

```python
#!/usr/bin/env python3
"""One-line description of what this script does."""

# ── Imports ──────────────────────────────────────────────
import os
import sys
import logging
from datetime import datetime
from contextlib import closing
import psycopg2

# ── Configuration ────────────────────────────────────────
THRESHOLD_WARN = 50
THRESHOLD_CRIT = 80

# ── Logging ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('script_name')

# ── Functions ────────────────────────────────────────────

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


def do_the_work(conn) -> None:
    """Main logic goes here."""
    with conn.cursor() as cur:
        cur.execute("SELECT version()")
        logger.info(f'Connected: {cur.fetchone()[0]}')


def main() -> None:
    """Entry point."""
    logger.info('Starting...')
    conn = get_connection()
    try:
        do_the_work(conn)
    finally:
        conn.close()
    logger.info('Done')


# ── Entry Point ──────────────────────────────────────────
if __name__ == '__main__':
    main()
```

---

## Common DBA Automation Patterns

| Pattern                      | When to Use                              | Key Approach                                 |
|------------------------------|------------------------------------------|----------------------------------------------|
| Health check                 | Periodic monitoring (cron every 5-60min) | Query pg_stat views, compare thresholds, exit codes |
| Bloat checker                | Weekly or before maintenance windows     | Query n_dead_tup ratio, generate VACUUM commands |
| Index auditor                | Monthly review                           | Query idx_scan=0, find duplicates, generate DROP |
| Stale query killer           | Continuous or periodic                   | Query pg_stat_activity age(), pg_terminate_backend |
| Metrics collector            | Continuous daemon                        | time.sleep loop, snapshot to CSV, signal handling |
| User/role audit              | Before compliance reviews                | Query pg_roles for superusers, expiry, permissions |
| Size reporter                | Weekly trending                          | Query pg_database_size / pg_total_relation_size |
| Backup verifier              | After every backup                       | Check backup files exist, test restore, log result |

---

## Error Handling Patterns

```python
# Specific psycopg2 errors
import psycopg2.errors

try:
    cur.execute("CREATE TABLE t (id int)")
except psycopg2.errors.DuplicateTable:
    logger.info('Table already exists')
except psycopg2.errors.InsufficientPrivilege:
    logger.error('Permission denied')
except psycopg2.OperationalError as e:
    logger.error(f'Connection error: {e}')
except psycopg2.Error as e:
    logger.error(f'Database error: {e}')

# Reconnection pattern
def safe_execute(conn, query, params=None, max_retries=3):
    for attempt in range(max_retries):
        try:
            with conn.cursor() as cur:
                cur.execute(query, params)
                return cur.fetchall()
        except psycopg2.OperationalError:
            if attempt < max_retries - 1:
                conn = get_connection()
            else:
                raise
```

---

## Environment Variables Reference

| Variable       | Purpose                    | Example                |
|----------------|----------------------------|------------------------|
| `PGHOST`       | PostgreSQL server hostname | `localhost`            |
| `PGPORT`       | PostgreSQL server port     | `5432`                 |
| `PGDATABASE`   | Default database name      | `postgres`             |
| `PGUSER`       | Database user              | `postgres`             |
| `PGPASSWORD`   | Database password          | (set, never hardcode)  |
| `PGSSLMODE`    | SSL connection mode        | `require`              |

Set them in your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD=your_password  # or use .pgpass
```

Or source from a file (never commit the file):

```bash
source ~/.pg_env
python3 my_script.py
```

---

## Quick pip Reference

```bash
pip3 install psycopg2-binary    # PostgreSQL adapter
pip3 install python-dotenv      # Load .env files (optional)
pip3 list                       # Show installed packages
pip3 freeze > requirements.txt  # Save dependencies
pip3 install -r requirements.txt # Install from file
```
