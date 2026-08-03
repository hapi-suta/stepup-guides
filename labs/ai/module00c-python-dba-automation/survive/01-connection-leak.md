# SURVIVE 01: The Connection Leak That Killed Production

**Module:** 00c - Python DBA Automation
**Type:** Chaos Scenario
**Time:** 30-45 minutes

---

## The Setup

A junior developer wrote a monitoring script that checks database health every 30 seconds. It has been running for 3 days. This morning, PostgreSQL stopped accepting new connections. Application servers are returning "FATAL: too many connections" errors. The on-call DBA (you) gets paged at 6:47 AM.

---

## Symptom

You SSH into the database server and try to connect:

```bash
psql -U postgres
```

You see:

```
FATAL:  sorry, too many clients already
```

You check from a superuser reserved connection (if you have `superuser_reserved_connections` set):

```bash
psql -U postgres -p 5432 -d postgres -c "SELECT count(*) FROM pg_stat_activity"
```

Output:

```
 count
-------
   200
```

Your `max_connections` is 200. The server is maxed out.

You check what is connected:

```bash
psql -U postgres -p 5432 -d postgres -c "
SELECT usename, application_name, count(*)
FROM pg_stat_activity
GROUP BY usename, application_name
ORDER BY count(*) DESC
LIMIT 10
"
```

Output:

```
  usename  | application_name | count
-----------+------------------+-------
 monitor   | health_check.py  |   187
 app_user  | webapp           |     8
 postgres  |                  |     3
 replicator| walreceiver      |     2
```

187 connections from `health_check.py`. That is the monitoring script.

---

## Diagnosis

Here is the broken monitoring script. Find the bug.

```python
#!/usr/bin/env python3
"""Health check monitor - runs every 30 seconds."""

import time
import psycopg2

def check_health():
    """Run a health check."""
    conn = psycopg2.connect(
        host='localhost',
        dbname='postgres',
        user='monitor',
        password='monitor123'
    )
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM pg_stat_activity")
    count = cur.fetchone()[0]
    print(f"Active connections: {count}")

    cur.execute("SELECT pg_database_size('postgres')")
    size = cur.fetchone()[0]
    print(f"Database size: {size}")

    # Check for long queries
    cur.execute("""
        SELECT pid, query
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query_start < now() - interval '5 minutes'
    """)
    long_queries = cur.fetchall()
    if long_queries:
        print(f"WARNING: {len(long_queries)} long-running queries")

    # BUG IS HERE - can you see it?

def main():
    print("Starting health monitor...")
    while True:
        try:
            check_health()
        except Exception as e:
            print(f"Error: {e}")
        time.sleep(30)

if __name__ == '__main__':
    main()
```

**The bug:** The `check_health()` function calls `psycopg2.connect()` every iteration but NEVER calls `conn.close()` or `cur.close()`. Every 30 seconds, a new connection opens. None of them close. After 3 days:

- 3 days = 72 hours = 4,320 minutes = 8,640 iterations at 30-second intervals
- Each iteration opens 1 connection
- After ~100 minutes (200 iterations), `max_connections` is hit

The connection and cursor are local variables in `check_health()`. When the function returns, the Python variable goes out of scope, but the underlying PostgreSQL connection does NOT close automatically. The garbage collector MIGHT eventually close it, but that is not guaranteed or timely. In practice, connections pile up.

There are actually THREE problems:

1. **No `conn.close()`** - the connection stays open after each check
2. **No `cur.close()`** - the cursor stays open
3. **No error handling within `check_health()`** - if the second query fails, the connection from the first query still leaks
4. **Bare `except Exception`** - catches everything including KeyboardInterrupt, hides real errors

---

## Fix

**Step 1: Immediate fix - kill the leaked connections:**

```sql
-- From a superuser reserved connection
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = 'monitor'
  AND application_name = 'health_check.py'
  AND pid != pg_backend_pid();
```

**Step 2: Stop the broken script:**

```bash
# Find the process
ps aux | grep health_check.py

# Kill it
kill <pid>
```

**Step 3: Fix the script - use `with` statements and connection reuse:**

Create the fixed version with `vi`:

```bash
vi ~/health_check_fixed.py
```

```python
#!/usr/bin/env python3
"""Health check monitor - runs every 30 seconds. FIXED version."""

import sys
import time
import logging
import signal
import psycopg2
from contextlib import closing

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger('health_check')

running = True

def signal_handler(signum, frame):
    global running
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


def check_health(conn) -> None:
    """Run a health check using an existing connection."""
    # FIX 1: Reuse the connection instead of opening a new one each time
    # FIX 2: Use 'with' for cursor - auto-closes when block exits
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM pg_stat_activity")
        count = cur.fetchone()[0]
        logger.info(f"Active connections: {count}")

        cur.execute("SELECT pg_database_size('postgres')")
        size = cur.fetchone()[0]
        logger.info(f"Database size: {size}")

        cur.execute("""
            SELECT pid, query
            FROM pg_stat_activity
            WHERE state = 'active'
              AND query_start < now() - interval '5 minutes'
        """)
        long_queries = cur.fetchall()
        if long_queries:
            logger.warning(f"{len(long_queries)} long-running queries")
    # Cursor auto-closed here


def get_connection() -> psycopg2.extensions.connection:
    """Create a new database connection."""
    conn = psycopg2.connect(
        host='localhost',
        dbname='postgres',
        user='monitor',
        password='monitor123'  # In production, use env vars
    )
    conn.autocommit = True  # Read-only monitoring, no transactions needed
    return conn


def main() -> None:
    logger.info("Starting health monitor...")

    # FIX 3: Open ONE connection and reuse it
    conn = get_connection()

    try:
        while running:
            try:
                check_health(conn)
            except psycopg2.OperationalError as e:
                # FIX 4: Handle specific error - connection lost
                logger.error(f"Connection lost: {e}")
                logger.info("Reconnecting...")
                try:
                    conn.close()
                except Exception:
                    pass
                conn = get_connection()
            except psycopg2.Error as e:
                # FIX 5: Handle database errors specifically
                logger.error(f"Database error: {e}")
                # Connection might be in a bad state, reset it
                try:
                    conn.rollback()
                except Exception:
                    conn.close()
                    conn = get_connection()

            for _ in range(30):
                if not running:
                    break
                time.sleep(1)
    finally:
        # FIX 6: Always close the connection on exit
        conn.close()
        logger.info("Stopped - connection closed")


if __name__ == '__main__':
    main()
```

**Step 4: Verify the fix works:**

Run the fixed script and monitor connection count:

```bash
# In terminal 1: run the fixed script
python3 ~/health_check_fixed.py

# In terminal 2: watch connection count
watch -n 5 'psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE usename = '\''monitor'\''"'
```

The connection count should stay at 1 (or 2 if you count the watch query).

---

## Key Takeaways

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| Connection leak | `connect()` in loop, no `close()` | Reuse one connection; use `with` for cursors |
| No cleanup on error | Exception skips close() | `try/finally` ensures close() always runs |
| Silent error swallowing | Bare `except Exception` | Catch specific errors: `psycopg2.OperationalError`, `psycopg2.Error` |
| No graceful shutdown | `while True` with no exit | Signal handler sets `running = False` |
| Hardcoded credentials | Password in source code | Use environment variables |

**The rule:** If you call `connect()`, you MUST call `close()`. The `with` statement and `closing()` wrapper guarantee this. Never rely on garbage collection to close database connections.
