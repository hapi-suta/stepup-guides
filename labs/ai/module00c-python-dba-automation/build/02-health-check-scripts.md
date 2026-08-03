# BUILD 02: Writing Database Health Check Scripts

**Module:** 00c - Python DBA Automation
**Prerequisites:** BUILD 01 (Connecting to PostgreSQL with Python)
**Time:** 60-75 minutes

You check database health every day - connection counts, long-running queries, replication lag, bloat. Right now you do it manually with psql or a monitoring tool someone else built. In this guide, you will write your own health check script in Python that checks five metrics and prints a color-coded report.

---

## Step 1: Script Structure

Every Python script you write for DBA work should follow this structure:

```python
#!/usr/bin/env python3
"""One-line description of what this script does."""

# 1. Imports
import os
import sys
import psycopg2

# 2. Configuration (constants, thresholds)
MAX_CONNECTIONS_WARN = 80
MAX_CONNECTIONS_CRIT = 150

# 3. Functions (each does one thing)
def check_connections(cur):
    """Check active connection count."""
    pass

# 4. Main block
if __name__ == '__main__':
    main()
```

**DBA Analogy:** Think of this like a well-organized SQL file. Imports are like `\i` includes. Configuration is like `SET` parameters. Functions are like stored procedures. The main block is where you call them.

The four sections always appear in this order. Every script you write in this module will follow this pattern.

---

## Step 2: The `if __name__ == '__main__':` Pattern

**DBA Analogy:** This is like a `main()` entry point in C, or like having a SQL file that defines functions but only runs them if executed directly (not when sourced by another file).

When Python runs a file directly, it sets `__name__` to `'__main__'`. When another file imports it, `__name__` is set to the module name instead.

```bash
python3 -c "
# When you run a file directly:
print('__name__ is:', __name__)
# Output: __name__ is: __main__
"
```

Expected output (yours will differ):

```
__name__ is: __main__
```

Why this matters: if you write a health check function in `health_check.py`, you might later want to import that function into another script. Without the `if __name__` guard, importing would also RUN the health check. The guard prevents that.

```python
def check_connections(cur):
    """Reusable function - safe to import."""
    cur.execute("SELECT count(*) FROM pg_stat_activity")
    return cur.fetchone()[0]

if __name__ == '__main__':
    # This only runs when you execute: python3 health_check.py
    # It does NOT run when another script does: from health_check import check_connections
    main()
```

---

## Step 3: Check Connection Count

This is the query you probably run five times a day. Now automate it.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT count(*) as total,
                   count(*) FILTER (WHERE state = 'active') as active,
                   count(*) FILTER (WHERE state = 'idle') as idle,
                   count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_tx
            FROM pg_stat_activity
            WHERE backend_type = 'client backend'
        ''')
        row = cur.fetchone()
        total, active, idle, idle_in_tx = row

        cur.execute('SHOW max_connections')
        max_conn = int(cur.fetchone()[0])

        pct = (total / max_conn) * 100
        print(f'Connections: {total}/{max_conn} ({pct:.0f}%)')
        print(f'  Active: {active}, Idle: {idle}, Idle-in-TX: {idle_in_tx}')

        if pct > 80:
            print('  STATUS: CRITICAL')
        elif pct > 50:
            print('  STATUS: WARNING')
        else:
            print('  STATUS: OK')
"
```

Expected output (yours will differ):

```
Connections: 5/100 (5%)
  Active: 1, Idle: 3, Idle-in-TX: 0
  STATUS: OK
```

---

## Step 4: Check Database Sizes

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT datname,
                   pg_database_size(datname) as size_bytes,
                   pg_size_pretty(pg_database_size(datname)) as size_pretty
            FROM pg_database
            WHERE datistemplate = false
            ORDER BY size_bytes DESC
        ''')
        rows = cur.fetchall()

        print(f'{\"Database\":<25} {\"Size\":<15}')
        print('-' * 40)
        total = 0
        for datname, size_bytes, size_pretty in rows:
            print(f'{datname:<25} {size_pretty:<15}')
            total += size_bytes
        print('-' * 40)
        print(f'{\"TOTAL\":<25} {total / (1024**3):.2f} GB')
"
```

Expected output (yours will differ):

```
Database                  Size
----------------------------------------
mydb                      12 MB
postgres                  7761 kB
----------------------------------------
TOTAL                     0.02 GB
```

---

## Step 5: Check Long-Running Queries

**DBA Analogy:** You do `SELECT pid, age(clock_timestamp(), query_start), query FROM pg_stat_activity WHERE state = 'active' ORDER BY query_start` all the time. Same query, now in Python with thresholds.

```bash
python3 -c "
import psycopg2
from contextlib import closing

LONG_QUERY_SECONDS = 300  # 5 minutes

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT pid,
                   usename,
                   EXTRACT(EPOCH FROM age(clock_timestamp(), query_start))::int as runtime_secs,
                   left(query, 80) as query_preview
            FROM pg_stat_activity
            WHERE state = 'active'
              AND query NOT LIKE '%%pg_stat_activity%%'
              AND backend_type = 'client backend'
            ORDER BY query_start
        ''')
        rows = cur.fetchall()

        long_queries = [r for r in rows if r[2] > LONG_QUERY_SECONDS]

        if long_queries:
            print(f'WARNING: {len(long_queries)} queries running > {LONG_QUERY_SECONDS}s')
            for pid, user, secs, query in long_queries:
                mins = secs // 60
                print(f'  PID {pid} ({user}) - {mins}m {secs % 60}s: {query}')
        else:
            print(f'OK: No queries running > {LONG_QUERY_SECONDS}s')
            print(f'  Active queries: {len(rows)}')
"
```

Expected output (yours will differ):

```
OK: No queries running > 300s
  Active queries: 0
```

---

## Step 6: Check Replication Lag

This check only applies if the server is a primary with standbys. If `pg_stat_replication` is empty, you are either on a standalone or a replica.

```bash
python3 -c "
import psycopg2
from contextlib import closing

LAG_WARNING_MB = 50
LAG_CRITICAL_MB = 200

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT client_addr,
                   application_name,
                   state,
                   sent_lsn,
                   replay_lsn,
                   pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes
            FROM pg_stat_replication
            ORDER BY lag_bytes DESC
        ''')
        rows = cur.fetchall()

        if not rows:
            print('INFO: No replicas connected (standalone or replica server)')
        else:
            print(f'Replication Status ({len(rows)} replicas):')
            for addr, app, state, sent, replay, lag in rows:
                lag_mb = lag / (1024 * 1024)
                if lag_mb > LAG_CRITICAL_MB:
                    status = 'CRITICAL'
                elif lag_mb > LAG_WARNING_MB:
                    status = 'WARNING'
                else:
                    status = 'OK'
                print(f'  {addr} ({app}): lag={lag_mb:.1f} MB, state={state} [{status}]')
"
```

Expected output (yours will differ):

```
INFO: No replicas connected (standalone or replica server)
```

---

## Step 7: Check Table Bloat

Dead tuples that have not been vacuumed are bloat. You check `pg_stat_user_tables` for this. A dead tuple ratio above 20% means VACUUM is not keeping up.

```bash
python3 -c "
import psycopg2
from contextlib import closing

BLOAT_WARN_PCT = 10
BLOAT_CRIT_PCT = 20

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT schemaname,
                   relname,
                   n_live_tup,
                   n_dead_tup,
                   CASE WHEN n_live_tup > 0
                        THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
                        ELSE 0
                   END as dead_pct,
                   last_autovacuum
            FROM pg_stat_user_tables
            WHERE n_live_tup + n_dead_tup > 1000
            ORDER BY dead_pct DESC
            LIMIT 10
        ''')
        rows = cur.fetchall()

        if not rows:
            print('OK: No tables with significant tuple counts')
        else:
            bloated = [r for r in rows if r[4] > BLOAT_WARN_PCT]
            if bloated:
                print(f'WARNING: {len(bloated)} tables with > {BLOAT_WARN_PCT}% dead tuples:')
                for schema, table, live, dead, pct, last_av in bloated:
                    status = 'CRITICAL' if pct > BLOAT_CRIT_PCT else 'WARNING'
                    av_str = str(last_av)[:19] if last_av else 'never'
                    print(f'  {schema}.{table}: {pct}% dead ({dead}/{live+dead}) last_av={av_str} [{status}]')
            else:
                print(f'OK: No tables above {BLOAT_WARN_PCT}% dead tuple ratio')
"
```

Expected output (yours will differ):

```
OK: No tables with significant tuple counts
```

---

## Step 8: Formatting Output with Colors

Terminal colors make health check output scannable at a glance. ANSI escape codes work in every terminal you use.

```bash
python3 -c "
# ANSI color codes - same ones that work in bash PS1 prompts
RED = '\033[91m'
YELLOW = '\033[93m'
GREEN = '\033[92m'
BOLD = '\033[1m'
RESET = '\033[0m'

def colorize(status):
    \"\"\"Return colored status string.\"\"\"
    if status == 'CRITICAL':
        return f'{RED}{BOLD}{status}{RESET}'
    elif status == 'WARNING':
        return f'{YELLOW}{status}{RESET}'
    else:
        return f'{GREEN}{status}{RESET}'

print(f'Connections: 5/100 (5%)   [{colorize(\"OK\")}]')
print(f'Replication lag: 75 MB    [{colorize(\"WARNING\")}]')
print(f'Connections: 190/200 (95%) [{colorize(\"CRITICAL\")}]')
"
```

Expected output (yours will differ - colors show in terminal):

```
Connections: 5/100 (5%)   [OK]
Replication lag: 75 MB    [WARNING]
Connections: 190/200 (95%) [CRITICAL]
```

(In your terminal, OK will be green, WARNING will be yellow, CRITICAL will be red and bold.)

---

## Step 9: Command-Line Arguments with sys.argv

**DBA Analogy:** Like passing flags to `pg_dump --host=myserver --dbname=mydb`. `sys.argv` is a list of everything after `python3`.

```bash
python3 -c "
import sys
# sys.argv[0] is the script name
# sys.argv[1:] are the arguments
# When using -c, sys.argv[0] is '-c'
print('Arguments:', sys.argv)
" --host localhost --port 5432
```

Expected output (yours will differ):

```
Arguments: ['-c', '--host', 'localhost', '--port', '5432']
```

For our health check, we will use a simple approach:

```python
import sys

# Default connection string
connstr = "dbname=postgres user=postgres"

# Override if argument passed: python3 health_check.py "host=myserver dbname=prod"
if len(sys.argv) > 1:
    connstr = sys.argv[1]
```

This keeps it simple. In BUILD 03, we will use a more robust argument parser.

---

## Step 10: Practical - Complete Health Check Script

Create the full health check script. Open the file with `vi`:

```bash
vi ~/health_check.py
```

Enter the following content:

```python
#!/usr/bin/env python3
"""PostgreSQL Health Check - checks 5 key metrics with color-coded output."""

import os
import sys
import psycopg2
from contextlib import closing

# ── Color codes ──────────────────────────────────────────
RED = '\033[91m'
YELLOW = '\033[93m'
GREEN = '\033[92m'
BOLD = '\033[1m'
RESET = '\033[0m'

# ── Thresholds ───────────────────────────────────────────
CONN_WARN_PCT = 50
CONN_CRIT_PCT = 80
LONG_QUERY_SECS = 300
LAG_WARN_MB = 50
LAG_CRIT_MB = 200
BLOAT_WARN_PCT = 10
BLOAT_CRIT_PCT = 20
DB_SIZE_WARN_GB = 50


def colorize(status: str) -> str:
    """Return colored status string."""
    if status == 'CRITICAL':
        return f'{RED}{BOLD}{status}{RESET}'
    elif status == 'WARNING':
        return f'{YELLOW}{status}{RESET}'
    return f'{GREEN}{status}{RESET}'


def header(title: str) -> None:
    """Print a section header."""
    print(f'\n{BOLD}--- {title} ---{RESET}')


def get_connection() -> psycopg2.extensions.connection:
    """Create connection from environment variables or sys.argv."""
    try:
        if len(sys.argv) > 1:
            conn = psycopg2.connect(sys.argv[1])
        else:
            conn = psycopg2.connect(
                host=os.environ.get('PGHOST', 'localhost'),
                port=os.environ.get('PGPORT', '5432'),
                dbname=os.environ.get('PGDATABASE', 'postgres'),
                user=os.environ.get('PGUSER', 'postgres'),
                password=os.environ.get('PGPASSWORD', '')
            )
        return conn
    except psycopg2.OperationalError as e:
        print(f'{RED}ERROR: Cannot connect: {e}{RESET}')
        sys.exit(1)


def check_connections(cur) -> str:
    """Check active connection count vs max_connections."""
    header('Connection Check')

    cur.execute('''
        SELECT count(*) as total,
               count(*) FILTER (WHERE state = 'active') as active,
               count(*) FILTER (WHERE state = 'idle') as idle,
               count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_tx
        FROM pg_stat_activity
        WHERE backend_type = 'client backend'
    ''')
    total, active, idle, idle_in_tx = cur.fetchone()

    cur.execute('SHOW max_connections')
    max_conn = int(cur.fetchone()[0])

    pct = (total / max_conn) * 100

    if pct > CONN_CRIT_PCT:
        status = 'CRITICAL'
    elif pct > CONN_WARN_PCT:
        status = 'WARNING'
    else:
        status = 'OK'

    print(f'  Total: {total}/{max_conn} ({pct:.0f}%)')
    print(f'  Active: {active} | Idle: {idle} | Idle-in-TX: {idle_in_tx}')
    print(f'  Status: [{colorize(status)}]')
    return status


def check_database_sizes(cur) -> str:
    """Check database sizes."""
    header('Database Sizes')

    cur.execute('''
        SELECT datname,
               pg_database_size(datname) as size_bytes,
               pg_size_pretty(pg_database_size(datname)) as size_pretty
        FROM pg_database
        WHERE datistemplate = false
        ORDER BY size_bytes DESC
    ''')
    rows = cur.fetchall()

    status = 'OK'
    for datname, size_bytes, size_pretty in rows:
        size_gb = size_bytes / (1024 ** 3)
        if size_gb > DB_SIZE_WARN_GB:
            status = 'WARNING'
        print(f'  {datname:<25} {size_pretty}')

    print(f'  Status: [{colorize(status)}]')
    return status


def check_long_queries(cur) -> str:
    """Check for queries running longer than threshold."""
    header('Long-Running Queries')

    cur.execute('''
        SELECT pid,
               usename,
               EXTRACT(EPOCH FROM age(clock_timestamp(), query_start))::int as runtime_secs,
               left(query, 60) as query_preview
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query NOT LIKE '%%pg_stat_activity%%'
          AND backend_type = 'client backend'
        ORDER BY query_start
    ''')
    rows = cur.fetchall()
    long_queries = [r for r in rows if r[2] > LONG_QUERY_SECS]

    if long_queries:
        status = 'WARNING'
        for pid, user, secs, query in long_queries:
            mins = secs // 60
            print(f'  PID {pid} ({user}) - {mins}m{secs % 60}s: {query}...')
    else:
        status = 'OK'
        print(f'  No queries running > {LONG_QUERY_SECS}s (active: {len(rows)})')

    print(f'  Status: [{colorize(status)}]')
    return status


def check_replication_lag(cur) -> str:
    """Check replication lag for connected standbys."""
    header('Replication Lag')

    cur.execute('''
        SELECT client_addr,
               application_name,
               state,
               pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes
        FROM pg_stat_replication
        ORDER BY lag_bytes DESC
    ''')
    rows = cur.fetchall()

    if not rows:
        print('  No replicas connected (standalone or replica)')
        return 'OK'

    status = 'OK'
    for addr, app, state, lag in rows:
        lag_mb = lag / (1024 * 1024)
        if lag_mb > LAG_CRIT_MB:
            status = 'CRITICAL'
        elif lag_mb > LAG_WARN_MB and status != 'CRITICAL':
            status = 'WARNING'
        print(f'  {addr} ({app}): lag={lag_mb:.1f} MB, state={state}')

    print(f'  Status: [{colorize(status)}]')
    return status


def check_table_bloat(cur) -> str:
    """Check for tables with high dead tuple ratio."""
    header('Table Bloat')

    cur.execute('''
        SELECT schemaname,
               relname,
               n_live_tup,
               n_dead_tup,
               CASE WHEN n_live_tup > 0
                    THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
                    ELSE 0
               END as dead_pct,
               last_autovacuum
        FROM pg_stat_user_tables
        WHERE n_live_tup + n_dead_tup > 1000
        ORDER BY dead_pct DESC
        LIMIT 10
    ''')
    rows = cur.fetchall()

    if not rows:
        print('  No tables with significant tuple counts')
        return 'OK'

    status = 'OK'
    bloated = [r for r in rows if r[4] > BLOAT_WARN_PCT]
    if bloated:
        status = 'WARNING'
        for schema, table, live, dead, pct, last_av in bloated:
            if pct > BLOAT_CRIT_PCT:
                status = 'CRITICAL'
            av_str = str(last_av)[:19] if last_av else 'never'
            print(f'  {schema}.{table}: {pct}% dead ({dead} tuples) last_av={av_str}')
    else:
        print(f'  All tables below {BLOAT_WARN_PCT}% dead tuple ratio')

    print(f'  Status: [{colorize(status)}]')
    return status


def main() -> None:
    """Run all health checks and print summary."""
    print(f'{BOLD}PostgreSQL Health Check{RESET}')
    print(f'{"=" * 50}')

    conn = get_connection()
    try:
        with conn:
            with conn.cursor() as cur:
                results = {
                    'Connections': check_connections(cur),
                    'Database Sizes': check_database_sizes(cur),
                    'Long Queries': check_long_queries(cur),
                    'Replication Lag': check_replication_lag(cur),
                    'Table Bloat': check_table_bloat(cur),
                }
    finally:
        conn.close()

    # Summary
    print(f'\n{BOLD}--- Summary ---{RESET}')
    for check_name, status in results.items():
        print(f'  {check_name:<25} [{colorize(status)}]')

    # Exit code: 2 if any CRITICAL, 1 if any WARNING, 0 if all OK
    if 'CRITICAL' in results.values():
        sys.exit(2)
    elif 'WARNING' in results.values():
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
```

Save and exit vi (`:wq`).

Make it executable:

```bash
chmod +x ~/health_check.py
```

Run it:

```bash
python3 ~/health_check.py
```

Expected output (yours will differ):

```
PostgreSQL Health Check
==================================================

--- Connection Check ---
  Total: 5/100 (5%)
  Active: 1 | Idle: 3 | Idle-in-TX: 0
  Status: [OK]

--- Database Sizes ---
  postgres                  7761 kB
  Status: [OK]

--- Long-Running Queries ---
  No queries running > 300s (active: 0)
  Status: [OK]

--- Replication Lag ---
  No replicas connected (standalone or replica)

--- Table Bloat ---
  No tables with significant tuple counts

--- Summary ---
  Connections               [OK]
  Database Sizes            [OK]
  Long Queries              [OK]
  Replication Lag           [OK]
  Table Bloat               [OK]
```

**Key design decisions in this script:**
- Exit codes (0/1/2) follow the Nagios convention - useful for monitoring integration
- Each check function returns a status string so we can build the summary
- The `with conn:` block auto-commits, so read-only queries commit cleanly
- Color output makes it instantly scannable when you SSH into a server

You can also pass a connection string directly:

```bash
python3 ~/health_check.py "host=prod-db-01 dbname=production user=monitor"
```

---

## What You Learned

| Concept                       | DBA Analogy                                | Python Code                                |
|-------------------------------|--------------------------------------------|--------------------------------------------|
| Script structure              | Organized SQL file with sections           | imports, config, functions, main block     |
| `if __name__ == '__main__':`  | Entry point / main()                       | Guards against import side effects         |
| pg_stat_activity queries      | Same queries you run in psql               | `cur.execute(...)` + `cur.fetchall()`      |
| Thresholds and status         | Monitoring alert levels                    | if/elif/else with constants                |
| ANSI color codes              | Terminal colors in bash PS1                | `'\033[91m'` for red, etc.                 |
| sys.argv                      | Script arguments like pg_dump flags        | `sys.argv[1]` for first argument           |
| Exit codes                    | Nagios plugin convention                   | `sys.exit(0)` OK, `1` WARN, `2` CRIT      |
| Shebang line                  | `#!/bin/bash` equivalent                   | `#!/usr/bin/env python3`                   |
