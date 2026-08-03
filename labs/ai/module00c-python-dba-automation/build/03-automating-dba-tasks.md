# BUILD 03: Automating Routine DBA Tasks

**Module:** 00c - Python DBA Automation
**Prerequisites:** BUILD 01-02 (Connecting, Health Checks)
**Time:** 75-90 minutes

You do these tasks every week: check for bloated tables, find unused indexes, audit user accounts, kill stale queries. Each one is a psql session, a query, some eyeballing, and maybe a VACUUM or DROP INDEX. This guide automates all of it into a single script with logging, timestamps, and optional email alerts.

---

## Step 1: Bloat Checker - Find Tables Needing VACUUM

**DBA Analogy:** This is the same `pg_stat_user_tables` check from BUILD 02, but now it generates actionable VACUUM commands you can copy-paste or pipe to psql.

```bash
python3 -c "
import psycopg2
from contextlib import closing

BLOAT_THRESHOLD = 20  # percent dead tuples

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT schemaname, relname, n_live_tup, n_dead_tup,
                   CASE WHEN n_live_tup + n_dead_tup > 0
                        THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
                        ELSE 0
                   END as dead_pct
            FROM pg_stat_user_tables
            WHERE n_dead_tup > 0
            ORDER BY dead_pct DESC
        ''')
        rows = cur.fetchall()

        bloated = [r for r in rows if r[4] >= BLOAT_THRESHOLD]
        if bloated:
            print(f'Found {len(bloated)} tables with >= {BLOAT_THRESHOLD}% dead tuples:')
            print()
            for schema, table, live, dead, pct in bloated:
                fqn = f'{schema}.{table}'
                print(f'-- {fqn}: {pct}% dead ({dead} dead / {live + dead} total)')
                print(f'VACUUM ANALYZE {fqn};')
                print()
        else:
            print(f'All tables below {BLOAT_THRESHOLD}% dead tuple ratio')
"
```

Expected output (yours will differ):

```
All tables below 20% dead tuple ratio
```

If bloated tables exist, output looks like:

```
Found 2 tables with >= 20% dead tuples:

-- public.orders: 35.2% dead (150000 dead / 426000 total)
VACUUM ANALYZE public.orders;

-- public.sessions: 22.1% dead (8000 dead / 36200 total)
VACUUM ANALYZE public.sessions;
```

You can redirect this output to a file and feed it to psql: `python3 bloat_check.py > vacuum_commands.sql && psql -f vacuum_commands.sql`.

---

## Step 2: Index Analyzer - Find Unused and Duplicate Indexes

Unused indexes waste disk space and slow down writes. Duplicate indexes are even worse - same overhead, zero benefit.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        # Unused indexes (0 scans since stats reset)
        cur.execute('''
            SELECT schemaname, indexrelname, relname,
                   pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
                   idx_scan
            FROM pg_stat_user_indexes
            WHERE idx_scan = 0
              AND indexrelname NOT LIKE '%%pkey%%'
              AND indexrelname NOT LIKE '%%unique%%'
            ORDER BY pg_relation_size(indexrelid) DESC
        ''')
        unused = cur.fetchall()

        if unused:
            print(f'Unused indexes ({len(unused)}):')
            for schema, idx, table, size, scans in unused:
                print(f'-- {schema}.{idx} on {table} ({size}, {scans} scans)')
                print(f'DROP INDEX CONCURRENTLY IF EXISTS {schema}.{idx};')
                print()
        else:
            print('No unused indexes found')

        # Duplicate indexes (same columns, same table)
        cur.execute('''
            SELECT pg_size_pretty(sum(pg_relation_size(idx))::bigint) as size,
                   (array_agg(idx))[1] as idx1,
                   (array_agg(idx))[2] as idx2,
                   relname,
                   columns
            FROM (
                SELECT indexrelid::regclass as idx,
                       indrelid::regclass as relname,
                       array_to_string(array_agg(attname ORDER BY attnum), ', ') as columns
                FROM pg_index
                JOIN pg_attribute ON attrelid = indrelid AND attnum = ANY(indkey)
                WHERE indrelid::regclass::text NOT LIKE 'pg_%%'
                GROUP BY indexrelid, indrelid
            ) sub
            GROUP BY relname, columns
            HAVING count(*) > 1
        ''')
        dupes = cur.fetchall()

        if dupes:
            print(f'\\nDuplicate indexes ({len(dupes)} sets):')
            for size, idx1, idx2, table, cols in dupes:
                print(f'-- {table} ({cols}): {idx1} and {idx2} ({size})')
                print(f'-- Review and drop the redundant one:')
                print(f'-- DROP INDEX CONCURRENTLY IF EXISTS {idx2};')
                print()
        else:
            print('\\nNo duplicate indexes found')
"
```

Expected output (yours will differ):

```
No unused indexes found

No duplicate indexes found
```

---

## Step 3: User Auditor - Check Roles and Security

**DBA Analogy:** The security audit you run before compliance reviews. Check for superusers, expired passwords, roles that have never logged in.

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        # Superusers
        cur.execute('''
            SELECT rolname, rolvaliduntil
            FROM pg_roles
            WHERE rolsuper = true
            ORDER BY rolname
        ''')
        supers = cur.fetchall()
        print(f'Superusers ({len(supers)}):')
        for name, expiry in supers:
            exp_str = str(expiry)[:19] if expiry else 'never expires'
            print(f'  {name} (valid until: {exp_str})')

        # Roles with no password expiry
        cur.execute('''
            SELECT rolname
            FROM pg_roles
            WHERE rolcanlogin = true
              AND rolvaliduntil IS NULL
              AND rolname NOT LIKE 'pg_%%'
            ORDER BY rolname
        ''')
        no_expiry = cur.fetchall()
        print(f'\\nRoles with no password expiry ({len(no_expiry)}):')
        for (name,) in no_expiry:
            print(f'  {name}')

        # Roles that can login but have no password set
        cur.execute('''
            SELECT rolname
            FROM pg_roles
            WHERE rolcanlogin = true
              AND rolpassword IS NULL
              AND rolname NOT LIKE 'pg_%%'
            ORDER BY rolname
        ''')
        no_password = cur.fetchall()
        print(f'\\nLogin roles with no password ({len(no_password)}):')
        for (name,) in no_password:
            print(f'  {name} -- consider: ALTER ROLE {name} PASSWORD \\'xxx\\' VALID UNTIL \\'2025-12-31\\';')
"
```

Expected output (yours will differ):

```
Superusers (1):
  postgres (valid until: never expires)

Roles with no password expiry (1):
  postgres

Login roles with no password (0):
```

---

## Step 4: Table Size Reporter - Top 20 Largest Tables

```bash
python3 -c "
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT schemaname || '.' || relname as table_name,
                   pg_size_pretty(pg_total_relation_size(relid)) as total_size,
                   pg_size_pretty(pg_relation_size(relid)) as table_size,
                   pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as index_size,
                   n_live_tup as row_count,
                   CASE WHEN n_live_tup + n_dead_tup > 0
                        THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
                        ELSE 0
                   END as bloat_pct
            FROM pg_stat_user_tables
            ORDER BY pg_total_relation_size(relid) DESC
            LIMIT 20
        ''')
        rows = cur.fetchall()

        if rows:
            print(f'{\"Table\":<40} {\"Total\":<12} {\"Data\":<12} {\"Indexes\":<12} {\"Rows\":<12} {\"Bloat%\":<8}')
            print('-' * 96)
            for table, total, data, idx, row_ct, bloat in rows:
                print(f'{table:<40} {total:<12} {data:<12} {idx:<12} {row_ct:<12} {bloat:<8}')
        else:
            print('No user tables found')
"
```

Expected output (yours will differ):

```
Table                                    Total        Data         Indexes      Rows         Bloat%
------------------------------------------------------------------------------------------------
public.large_table                       256 MB       180 MB       76 MB        1500000      2.3
public.users                             48 MB        32 MB        16 MB        250000       0.5
...
```

---

## Step 5: Stale Query Killer

**DBA Analogy:** You have done `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE ...` many times. This automates it with safety checks.

```bash
python3 -c "
import psycopg2
from contextlib import closing

MAX_RUNTIME_MINUTES = 30
DRY_RUN = True  # Set to False to actually kill queries

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    conn.autocommit = True  # pg_terminate_backend needs autocommit
    with conn.cursor() as cur:
        cur.execute('''
            SELECT pid, usename,
                   EXTRACT(EPOCH FROM age(clock_timestamp(), query_start))::int / 60 as runtime_min,
                   left(query, 80) as query_preview
            FROM pg_stat_activity
            WHERE state = 'active'
              AND query NOT LIKE '%%pg_stat_activity%%'
              AND backend_type = 'client backend'
              AND EXTRACT(EPOCH FROM age(clock_timestamp(), query_start)) > %s
            ORDER BY query_start
        ''', (MAX_RUNTIME_MINUTES * 60,))
        stale = cur.fetchall()

        if not stale:
            print(f'No queries running longer than {MAX_RUNTIME_MINUTES} minutes')
        else:
            print(f'Found {len(stale)} stale queries (> {MAX_RUNTIME_MINUTES} min):')
            for pid, user, mins, query in stale:
                print(f'  PID {pid} ({user}) - running {mins}m: {query}')
                if not DRY_RUN:
                    cur.execute('SELECT pg_terminate_backend(%s)', (pid,))
                    result = cur.fetchone()[0]
                    print(f'    -> Terminated: {result}')
                else:
                    print(f'    -> DRY RUN (set DRY_RUN=False to actually kill)')
"
```

Expected output (yours will differ):

```
No queries running longer than 30 minutes
```

**Safety note:** The `DRY_RUN = True` flag means the script only reports - it does not kill anything. You change it to `False` only when you are sure the script identifies the right queries. Always test with `DRY_RUN = True` first.

---

## Step 6: Generating Reports - Plain Text and CSV

You have two audiences for DBA reports: yourself (plain text in the terminal) and managers (CSV they can open in Excel).

```bash
python3 -c "
import csv
import sys
import psycopg2
from contextlib import closing

with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT datname,
                   pg_size_pretty(pg_database_size(datname)) as size,
                   pg_database_size(datname) as size_bytes
            FROM pg_database
            WHERE datistemplate = false
            ORDER BY size_bytes DESC
        ''')
        rows = cur.fetchall()

        # Plain text for terminal
        print('=== Database Size Report ===')
        for name, size, _ in rows:
            print(f'  {name:<25} {size}')

        # CSV for file output
        writer = csv.writer(sys.stdout)
        print()
        print('=== CSV Format ===')
        writer.writerow(['database', 'size_pretty', 'size_bytes'])
        for name, size, size_bytes in rows:
            writer.writerow([name, size, size_bytes])
"
```

Expected output (yours will differ):

```
=== Database Size Report ===
  postgres                  7761 kB

=== CSV Format ===
database,size_pretty,size_bytes
postgres,7761 kB,7946752
```

To write to a file instead of stdout, use `open()`:

```python
with open('/tmp/db_sizes.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['database', 'size_pretty', 'size_bytes'])
    for row in rows:
        writer.writerow(row)
```

---

## Step 7: Scheduling with cron

**DBA Analogy:** `pg_cron` runs SQL on a schedule inside PostgreSQL. OS-level `cron` runs scripts on a schedule outside PostgreSQL. For DBA automation scripts, OS cron is usually better because it can run even if PostgreSQL is down.

View your current crontab:

```bash
crontab -l
```

Add a scheduled health check (runs every 6 hours, logs output):

```bash
crontab -e
```

Add this line:

```
0 */6 * * * /usr/bin/env python3 /home/youruser/health_check.py >> /var/log/pg_health.log 2>&1
```

Cron format reminder:

```
# minute  hour  day  month  weekday  command
# 0       */6   *    *      *        = every 6 hours at minute 0
# 30      2     *    *      1        = Monday at 2:30 AM
# 0       0     1    *      *        = 1st of each month at midnight
```

**Important:** cron does not load your shell profile, so `PGPASSWORD` and other environment variables will not be set. Either:
1. Set them in the crontab: `PGPASSWORD=xxx` at the top of crontab
2. Use a `.pgpass` file (PostgreSQL reads this automatically)
3. Source an env file in the command: `source ~/.pg_env && python3 health_check.py`

---

## Step 8: Python Logging Module

**DBA Analogy:** Your scripts need a log file just like PostgreSQL has `postgresql.log`. Python's `logging` module gives you timestamps, severity levels, and file output - the same things `log_destination`, `log_min_messages`, and `log_line_prefix` give PostgreSQL.

```bash
python3 -c "
import logging

# Configure logging - like setting log_destination and log_min_messages
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger('dba_automation')

# These match PostgreSQL log levels you already know
logger.debug('Detailed debug info')    # Like LOG in postgres (verbose)
logger.info('Normal operation')         # Like LOG
logger.warning('Something to watch')    # Like WARNING
logger.error('Something failed')        # Like ERROR
logger.critical('System is down')       # Like FATAL/PANIC
"
```

Expected output (yours will differ):

```
2026-06-09 14:30:00 [INFO] Normal operation
2026-06-09 14:30:00 [WARNING] Something to watch
2026-06-09 14:30:00 [ERROR] Something failed
2026-06-09 14:30:00 [CRITICAL] System is down
```

Notice `DEBUG` did not print - because we set `level=logging.INFO`. Just like `log_min_messages = info` in PostgreSQL hides debug messages.

To log to both console AND a file:

```python
import logging

logger = logging.getLogger('dba_automation')
logger.setLevel(logging.INFO)

# Console handler
console = logging.StreamHandler()
console.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
logger.addHandler(console)

# File handler
file_handler = logging.FileHandler('/var/log/dba_automation.log')
file_handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
logger.addHandler(file_handler)
```

---

## Step 9: The datetime Module

You need timestamps for log entries, report headers, and comparing "when was this last vacuumed?"

```bash
python3 -c "
from datetime import datetime, timedelta

# Current timestamp
now = datetime.now()
print('Now:', now)
print('Formatted:', now.strftime('%Y-%m-%d %H:%M:%S'))

# Time math - like interval in PostgreSQL
yesterday = now - timedelta(days=1)
print('Yesterday:', yesterday.strftime('%Y-%m-%d'))

one_hour_ago = now - timedelta(hours=1)
print('1 hour ago:', one_hour_ago.strftime('%H:%M:%S'))

# Parse a timestamp string - like casting text to timestamp
ts_string = '2026-06-09 10:30:00'
parsed = datetime.strptime(ts_string, '%Y-%m-%d %H:%M:%S')
print('Parsed:', parsed)

# Difference between two timestamps - like age() in PostgreSQL
diff = now - parsed
print('Difference:', diff)
print('Total seconds:', diff.total_seconds())
"
```

Expected output (yours will differ):

```
Now: 2026-06-09 14:30:45.123456
Formatted: 2026-06-09 14:30:45
Yesterday: 2026-06-08
1 hour ago: 13:30:45
Parsed: 2026-06-09 10:30:00
Difference: 4:00:45.123456
Total seconds: 14445.123456
```

| Python                            | PostgreSQL Equivalent              |
|-----------------------------------|------------------------------------|
| `datetime.now()`                  | `clock_timestamp()`                |
| `timedelta(days=1)`              | `INTERVAL '1 day'`                |
| `now - timedelta(hours=1)`       | `clock_timestamp() - interval '1 hour'` |
| `strftime('%Y-%m-%d')`           | `to_char(ts, 'YYYY-MM-DD')`       |
| `strptime(str, fmt)`             | `to_timestamp(str, fmt)`           |

---

## Step 10: Sending Email Alerts

When your automated script finds a problem at 3 AM, you need to know about it. Python's `smtplib` sends email - no external tools needed.

```python
import smtplib
from email.mime.text import MIMEText
from datetime import datetime


def send_alert(subject: str, body: str) -> None:
    """Send an email alert via SMTP."""
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = 'dba-alerts@yourcompany.com'
    msg['To'] = 'dba-team@yourcompany.com'

    # For Gmail/SES, use TLS on port 587
    # For local postfix, use localhost on port 25
    with smtplib.SMTP('localhost', 25) as server:
        server.send_message(msg)


# Usage in your health check:
# if status == 'CRITICAL':
#     send_alert(
#         f'[CRITICAL] PostgreSQL Health Check - {datetime.now():%Y-%m-%d %H:%M}',
#         f'Connection count at 95%. Server: prod-db-01\n\nFull report:\n{report_text}'
#     )
```

For AWS SES (which you use for SUTA Labs), replace the SMTP connection:

```python
with smtplib.SMTP('email-smtp.us-east-1.amazonaws.com', 587) as server:
    server.starttls()
    server.login(os.environ['SES_USER'], os.environ['SES_PASSWORD'])
    server.send_message(msg)
```

This is a brief intro - you will use this pattern in BUILD 04 when you need the metrics collector to alert on threshold breaches.

---

## Step 11: Practical - Build automated_maintenance.py

This script combines bloat checking, unused index detection, and stale query killing into one automated tool. Create it with `vi`:

```bash
vi ~/automated_maintenance.py
```

Enter the following content:

```python
#!/usr/bin/env python3
"""Automated PostgreSQL Maintenance - bloat check, unused indexes, stale queries."""

import os
import sys
import logging
from datetime import datetime
from contextlib import closing
import psycopg2

# ── Configuration ────────────────────────────────────────
BLOAT_THRESHOLD_PCT = 20
UNUSED_INDEX_DAYS = 7
STALE_QUERY_MINUTES = 30
DRY_RUN = True  # Set False to execute VACUUM and terminate queries

# ── Logging ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('maintenance')


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
        logger.critical(f'Cannot connect to PostgreSQL: {e}')
        sys.exit(1)


def check_bloat(cur) -> list[dict]:
    """Find tables with dead tuple ratio above threshold."""
    logger.info(f'Checking for tables with > {BLOAT_THRESHOLD_PCT}% dead tuples...')

    cur.execute('''
        SELECT schemaname, relname, n_live_tup, n_dead_tup,
               CASE WHEN n_live_tup + n_dead_tup > 0
                    THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
                    ELSE 0
               END as dead_pct,
               last_autovacuum
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 100
        ORDER BY dead_pct DESC
    ''')
    rows = cur.fetchall()

    results = []
    for schema, table, live, dead, pct, last_av in rows:
        if pct >= BLOAT_THRESHOLD_PCT:
            fqn = f'{schema}.{table}'
            results.append({
                'table': fqn,
                'dead_pct': float(pct),
                'dead_tuples': dead,
                'last_autovacuum': str(last_av) if last_av else 'never',
                'command': f'VACUUM ANALYZE {fqn};'
            })
            logger.warning(f'Bloated: {fqn} - {pct}% dead ({dead} tuples)')

    if not results:
        logger.info('No bloated tables found')

    return results


def check_unused_indexes(cur) -> list[dict]:
    """Find indexes with zero scans."""
    logger.info('Checking for unused indexes...')

    cur.execute('''
        SELECT schemaname, indexrelname, relname,
               pg_size_pretty(pg_relation_size(indexrelid)) as size,
               pg_relation_size(indexrelid) as size_bytes,
               idx_scan
        FROM pg_stat_user_indexes
        WHERE idx_scan = 0
          AND indexrelname NOT LIKE '%%pkey%%'
          AND indexrelname NOT LIKE '%%unique%%'
        ORDER BY pg_relation_size(indexrelid) DESC
    ''')
    rows = cur.fetchall()

    results = []
    for schema, idx, table, size, size_bytes, scans in rows:
        fqn = f'{schema}.{idx}'
        results.append({
            'index': fqn,
            'table': f'{schema}.{table}',
            'size': size,
            'size_bytes': size_bytes,
            'command': f'DROP INDEX CONCURRENTLY IF EXISTS {fqn};'
        })
        logger.warning(f'Unused index: {fqn} on {table} ({size})')

    if not results:
        logger.info('No unused indexes found')

    return results


def check_stale_queries(cur) -> list[dict]:
    """Find queries running longer than threshold."""
    logger.info(f'Checking for queries running > {STALE_QUERY_MINUTES} minutes...')

    cur.execute('''
        SELECT pid, usename,
               EXTRACT(EPOCH FROM age(clock_timestamp(), query_start))::int as runtime_secs,
               left(query, 100) as query_preview
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query NOT LIKE '%%pg_stat_activity%%'
          AND backend_type = 'client backend'
          AND EXTRACT(EPOCH FROM age(clock_timestamp(), query_start)) > %s
        ORDER BY query_start
    ''', (STALE_QUERY_MINUTES * 60,))
    rows = cur.fetchall()

    results = []
    for pid, user, secs, query in rows:
        mins = secs // 60
        results.append({
            'pid': pid,
            'user': user,
            'runtime_minutes': mins,
            'query': query,
            'command': f'SELECT pg_terminate_backend({pid});'
        })
        logger.warning(f'Stale query: PID {pid} ({user}) running {mins}m')

    if not results:
        logger.info('No stale queries found')

    return results


def execute_maintenance(conn, bloat_results: list[dict], stale_results: list[dict]) -> None:
    """Execute VACUUM and terminate stale queries if not in dry run mode."""
    if DRY_RUN:
        logger.info('DRY RUN mode - no changes will be made')
        return

    # VACUUM bloated tables
    conn.autocommit = True
    with conn.cursor() as cur:
        for item in bloat_results:
            logger.info(f'Running: {item["command"]}')
            try:
                cur.execute(item['command'])
                logger.info(f'  VACUUM completed for {item["table"]}')
            except psycopg2.Error as e:
                logger.error(f'  VACUUM failed for {item["table"]}: {e}')

        # Terminate stale queries
        for item in stale_results:
            logger.info(f'Terminating PID {item["pid"]}...')
            try:
                cur.execute('SELECT pg_terminate_backend(%s)', (item['pid'],))
                result = cur.fetchone()[0]
                logger.info(f'  Terminated: {result}')
            except psycopg2.Error as e:
                logger.error(f'  Failed to terminate PID {item["pid"]}: {e}')


def print_report(bloat: list[dict], indexes: list[dict], stale: list[dict]) -> None:
    """Print a summary report."""
    print(f'\n{"=" * 60}')
    print(f'Maintenance Report - {datetime.now():%Y-%m-%d %H:%M:%S}')
    print(f'{"=" * 60}')

    print(f'\nBloated Tables ({len(bloat)}):')
    if bloat:
        for item in bloat:
            print(f'  {item["table"]}: {item["dead_pct"]}% dead')
            print(f'    {item["command"]}')
    else:
        print('  None found')

    print(f'\nUnused Indexes ({len(indexes)}):')
    if indexes:
        total_bytes = sum(i['size_bytes'] for i in indexes)
        for item in indexes:
            print(f'  {item["index"]} on {item["table"]} ({item["size"]})')
            print(f'    {item["command"]}')
        print(f'  Total reclaimable: {total_bytes / (1024*1024):.1f} MB')
    else:
        print('  None found')

    print(f'\nStale Queries ({len(stale)}):')
    if stale:
        for item in stale:
            print(f'  PID {item["pid"]} ({item["user"]}) - {item["runtime_minutes"]}m')
            print(f'    {item["query"][:80]}...')
    else:
        print('  None found')

    mode = 'DRY RUN' if DRY_RUN else 'EXECUTED'
    print(f'\nMode: {mode}')
    print(f'{"=" * 60}')


def main() -> None:
    """Run all maintenance checks."""
    logger.info('Starting automated maintenance...')
    start_time = datetime.now()

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            bloat_results = check_bloat(cur)
            index_results = check_unused_indexes(cur)
            stale_results = check_stale_queries(cur)

        execute_maintenance(conn, bloat_results, stale_results)
        print_report(bloat_results, index_results, stale_results)

    finally:
        conn.close()

    elapsed = (datetime.now() - start_time).total_seconds()
    logger.info(f'Maintenance completed in {elapsed:.1f}s')


if __name__ == '__main__':
    main()
```

Save and exit vi (`:wq`).

Make it executable and run:

```bash
chmod +x ~/automated_maintenance.py
python3 ~/automated_maintenance.py
```

Expected output (yours will differ):

```
2026-06-09 14:30:00 [INFO] Starting automated maintenance...
2026-06-09 14:30:00 [INFO] Checking for tables with > 20% dead tuples...
2026-06-09 14:30:00 [INFO] No bloated tables found
2026-06-09 14:30:00 [INFO] Checking for unused indexes...
2026-06-09 14:30:00 [INFO] No unused indexes found
2026-06-09 14:30:00 [INFO] Checking for queries running > 30 minutes...
2026-06-09 14:30:00 [INFO] No stale queries found
2026-06-09 14:30:00 [INFO] DRY RUN mode - no changes will be made

============================================================
Maintenance Report - 2026-06-09 14:30:00
============================================================

Bloated Tables (0):
  None found

Unused Indexes (0):
  None found

Stale Queries (0):
  None found

Mode: DRY RUN
============================================================
2026-06-09 14:30:00 [INFO] Maintenance completed in 0.3s
```

When you are ready to actually execute maintenance, change `DRY_RUN = False` at the top of the script.

---

## What You Learned

| Concept                  | DBA Analogy                                | Python Code                                |
|--------------------------|--------------------------------------------|--------------------------------------------|
| Bloat detection          | pg_stat_user_tables dead tuple check       | Query + filter + generate VACUUM commands  |
| Unused index finder      | pg_stat_user_indexes idx_scan = 0          | Query + generate DROP INDEX commands       |
| User audit               | pg_roles security review                   | Query + report on expiry/password status   |
| Stale query killer       | pg_terminate_backend()                     | Query + optional execution with DRY_RUN   |
| DRY_RUN pattern          | `\p` before `\g` in psql                   | Boolean flag that guards destructive ops   |
| CSV output               | `\copy` in psql                            | `csv.writer()`                             |
| cron scheduling          | pg_cron but at OS level                    | `crontab -e` with schedule expression      |
| logging module           | postgresql.log with severity levels        | `logging.basicConfig()` + `logger.info()`  |
| datetime module          | clock_timestamp(), interval, age()         | `datetime.now()`, `timedelta()`, `strftime`|
| Email alerts             | Monitoring system notifications            | `smtplib.SMTP()` + `MIMEText()`           |
