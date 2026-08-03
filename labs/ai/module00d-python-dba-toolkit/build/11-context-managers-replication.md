# BUILD 11: Context Managers - Replication Health Checker (Streaming Replication)

**What you will build:** `~/pgdba/repl_checker.py` - a script that safely connects to a primary PostgreSQL server, checks streaming replication state, reports WAL lag in bytes, and always cleans up connections even if something goes wrong.

**Python concepts covered:** `with` statement, `psycopg2` connection as context manager, multiple `with` targets, `contextlib.contextmanager`, custom context managers, proper cleanup on errors

**Time to complete:** ~50 minutes

---

## Prerequisites

- `~/pgdba/pg_utils.py` available (from BUILD 07)
- psycopg2-binary installed: `pip3 install psycopg2-binary`
- PostgreSQL running locally on port 5432

---

## Step 1: The with statement - automatic cleanup for files

You already know this from BUILD 04, but it is worth revisiting here because the same mechanism protects database connections. The `with` statement guarantees that cleanup code runs even if an error occurs - like a `BEGIN / EXCEPTION / END` block that always rolls back on error.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
# Without 'with': you must manually close the file
f = open('/etc/hostname', 'r')
content = f.read()
f.close()  # easy to forget, and never runs if an exception happens first
print('Without with:', content.strip())

# With 'with': close() is called automatically, even if an exception happens
with open('/etc/hostname', 'r') as f:
    content = f.read()
# f is already closed here - you cannot forget it
print('With with:   ', content.strip())
"
```

What this does: the `with open(...) as f:` block automatically calls `f.close()` when the block ends - whether it ended normally or with an exception. The variable `f` is not accessible after the block exits (the file is closed).

Expected output (yours will differ):

```
Without with: macbook-pro.local
With with:    macbook-pro.local
```

---

## Step 2: The problem - connection leaks

In PostgreSQL, every connection occupies a slot in `pg_stat_activity` and uses memory. If your script opens a connection and crashes before calling `conn.close()`, that connection stays open until it times out. On a busy server with `max_connections = 100`, leaked connections are a real production issue.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

# Simulate the problem: open a connection, then an error happens
try:
    conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
    cur = conn.cursor()
    cur.execute('SELECT 1/0')   # This will raise a ZeroDivisionError from PostgreSQL
    result = cur.fetchone()
    conn.close()   # Never reached if an exception happens above
except Exception as e:
    print(f'Error: {e}')
    print('conn.close() was never called - connection is still open!')
    # We need to close it manually in the except block - easy to forget
    try:
        conn.close()
        print('Manually closed the connection in the except block.')
    except:
        pass
"
```

What this does: demonstrates that if you do not use `with`, you must remember to close the connection in your exception handler. If you forget that too, the connection leaks.

Expected output (yours will differ):

```
Error: division by zero
LINE 1: SELECT 1/0
               ^

conn.close() was never called - connection is still open!
Manually closed the connection in the except block.
```

---

## Step 3: psycopg2 connection as a context manager

The `with psycopg2.connect(...) as conn:` pattern does NOT close the connection on exit - it handles transactions (commit on success, rollback on exception). You still need to close the connection. The correct pattern uses two `with` blocks.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

# psycopg2 connection: 'with conn' handles COMMIT/ROLLBACK (not close)
# psycopg2 cursor: 'with conn.cursor()' handles cursor cleanup

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')

try:
    with conn:   # transaction block - commits on success, rolls back on exception
        with conn.cursor() as cur:
            cur.execute('SELECT version()')
            row = cur.fetchone()
            print('Version:', row[0][:60])
    # cursor is closed here (automatically)
    # transaction is committed here (automatically)
finally:
    conn.close()   # always runs, even if an exception occurred
    print('Connection closed.')
"
```

What each level does:
- `with conn:` - starts a transaction; commits when the block succeeds, rolls back on any exception. Think of it as `BEGIN ... COMMIT` with an automatic `ROLLBACK` on error.
- `with conn.cursor() as cur:` - opens a cursor and closes it when the block exits
- `finally: conn.close()` - closes the physical connection regardless of success or failure

Expected output (yours will differ):

```
Version: PostgreSQL 16.3 on aarch64-apple-darwin23.4.0, compiled by Apple clang version
Connection closed.
```

---

## Step 4: Connecting to primary and standby together

When checking replication, you need connections to two servers at the same time. Python lets you open multiple connections in the same `with` block.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

# In a real setup: PRIMARY_HOST and STANDBY_HOST would be different IPs
# For this exercise, we connect to localhost twice (simulating two servers)
PRIMARY_HOST = 'localhost'
PRIMARY_PORT = 5432
STANDBY_HOST = 'localhost'   # would be a different IP in production
STANDBY_PORT = 5432

primary_conn = psycopg2.connect(host=PRIMARY_HOST, port=PRIMARY_PORT, dbname='postgres')
standby_conn = psycopg2.connect(host=STANDBY_HOST, port=STANDBY_PORT, dbname='postgres')

try:
    with primary_conn.cursor() as p_cur:
        p_cur.execute('SELECT pg_current_wal_lsn()')
        primary_lsn = p_cur.fetchone()[0]

    with standby_conn.cursor() as s_cur:
        s_cur.execute('SELECT pg_last_wal_receive_lsn()')
        standby_lsn = s_cur.fetchone()[0]

    print(f'Primary LSN:  {primary_lsn}')
    print(f'Standby LSN:  {standby_lsn}')
finally:
    primary_conn.close()
    standby_conn.close()
    print('Both connections closed.')
"
```

What this does: opens two separate connections and queries each server for its current WAL position. `pg_current_wal_lsn()` returns the primary's current write position. `pg_last_wal_receive_lsn()` returns what the standby has received so far.

Expected output (yours will differ):

```
Primary LSN:  0/1A3F8B0
Standby LSN:  0/1A3F8B0
Both connections closed.
```

Note: on a single-instance setup with no standby, both functions query the same server, so they will return the same LSN value.

---

## Step 5: Query pg_stat_replication on the primary

`pg_stat_replication` is the primary's view into its connected standbys. Each row represents one standby. It shows the WAL positions for sent, written, flushed, and replayed data - each a step further behind the primary.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
try:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT
                application_name,
                client_addr,
                state,
                sent_lsn,
                write_lsn,
                flush_lsn,
                replay_lsn,
                sync_state,
                pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
            FROM pg_stat_replication
        ''')
        standbys = cur.fetchall()

    if standbys:
        print('Connected standbys:')
        for s in standbys:
            print(f'  app={s[0]}  addr={s[1]}  state={s[2]}  sync={s[7]}  lag={s[8]} bytes')
    else:
        print('No standbys connected. (Expected on a single-instance setup.)')

    # Also show current WAL position on the primary
    with conn.cursor() as cur:
        cur.execute('SELECT pg_current_wal_lsn()')
        lsn = cur.fetchone()[0]
    print(f'Primary current LSN: {lsn}')
finally:
    conn.close()
"
```

What each column means:
- `sent_lsn` - WAL position the primary has sent to this standby
- `write_lsn` - WAL position the standby has written to its receive buffer (OS)
- `flush_lsn` - WAL position the standby has flushed to disk
- `replay_lsn` - WAL position the standby has applied to its data files
- `pg_wal_lsn_diff()` - calculates bytes between two LSN positions

Expected output (yours will differ):

```
No standbys connected. (Expected on a single-instance setup.)
Primary current LSN: 0/1A3F8B0
```

---

## Step 6: Query pg_stat_wal_receiver on the standby

`pg_stat_wal_receiver` is the standby's view of its own replication stream - it shows whether WAL is actively being received, and from which primary.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
try:
    with conn.cursor() as cur:
        cur.execute('''
            SELECT
                status,
                receive_start_lsn,
                received_lsn,
                last_msg_send_time,
                last_msg_receipt_time,
                sender_host,
                sender_port
            FROM pg_stat_wal_receiver
        ''')
        receiver_rows = cur.fetchall()

    if receiver_rows:
        r = receiver_rows[0]
        print(f'WAL receiver status:   {r[0]}')
        print(f'Started receiving at:  {r[1]}')
        print(f'Last received LSN:     {r[2]}')
        print(f'Primary host:          {r[5]}:{r[6]}')
        print(f'Last msg from primary: {r[3]}')
        print(f'Last msg received:     {r[4]}')
    else:
        print('pg_stat_wal_receiver is empty.')
        print('This is expected - this server is a primary, not a standby.')
        print('On a real standby you would see the receiver status here.')
finally:
    conn.close()
"
```

What this does: `pg_stat_wal_receiver` is only populated on a standby server. On a primary (or a standalone server), the view returns zero rows. The script handles both cases.

Expected output (yours will differ):

```
pg_stat_wal_receiver is empty.
This is expected - this server is a primary, not a standby.
On a real standby you would see the receiver status here.
```

---

## Step 7: Calculate replication lag in bytes and seconds

`pg_wal_lsn_diff()` returns the byte difference between two WAL positions. You can also estimate lag in seconds by looking at `write_lag`, `flush_lag`, and `replay_lag` columns in `pg_stat_replication` (available in PostgreSQL 10+).

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
try:
    with conn.cursor() as cur:
        # Get sent vs replay lag per standby (bytes)
        cur.execute('''
            SELECT
                application_name,
                pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)    AS send_lag_bytes,
                pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)   AS write_lag_bytes,
                pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)   AS flush_lag_bytes,
                pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)  AS replay_lag_bytes,
                EXTRACT(EPOCH FROM write_lag)   AS write_lag_sec,
                EXTRACT(EPOCH FROM flush_lag)   AS flush_lag_sec,
                EXTRACT(EPOCH FROM replay_lag)  AS replay_lag_sec
            FROM pg_stat_replication
        ''')
        rows = cur.fetchall()

    if rows:
        for r in rows:
            print(f'Standby: {r[0]}')
            print(f'  Send lag:    {r[1]:,} bytes')
            print(f'  Write lag:   {r[2]:,} bytes  ({r[5]} sec)')
            print(f'  Flush lag:   {r[3]:,} bytes  ({r[6]} sec)')
            print(f'  Replay lag:  {r[4]:,} bytes  ({r[7]} sec)')
    else:
        print('No standbys - cannot show replication lag.')
        print('(To get real lag numbers, run this on a primary with an attached standby.)')
finally:
    conn.close()
"
```

What each lag type means:
- `write_lag` - time from primary flush to standby write (network + standby disk I/O)
- `flush_lag` - time from primary flush to standby fsync (includes standby I/O completion)
- `replay_lag` - time from primary flush to standby apply (everything including WAL apply)
- `replay_lag` is the number you alert on for DR readiness

Expected output (yours will differ):

```
No standbys - cannot show replication lag.
(To get real lag numbers, run this on a primary with an attached standby.)
```

---

## Step 8: Build a custom context manager with contextlib

Sometimes you need more than just connection cleanup - you want to log when a connection opens and closes, or automatically set a session variable on connect. `contextlib.contextmanager` lets you write a generator function that behaves like a `with` block. The code before `yield` is `__enter__`, the code after is `__exit__`.

On your **Mac terminal**:

```bash
python3 -c "
from contextlib import contextmanager
import psycopg2

@contextmanager
def db_connection(host: str, port: int, dbname: str, label: str = ''):
    '''
    A custom context manager that logs connect and disconnect.
    Yields the connection, then closes it when the with block exits.
    '''
    tag = f'[{label}]' if label else ''
    print(f'{tag} Connecting to {host}:{port}/{dbname}...')
    conn = psycopg2.connect(host=host, port=port, dbname=dbname)
    try:
        yield conn        # <-- this is where the 'with' block body runs
    except Exception as e:
        print(f'{tag} Error inside with block: {e}')
        raise             # re-raise so the caller still sees the exception
    finally:
        conn.close()      # always runs, even if an exception occurred
        print(f'{tag} Connection closed.')

# Use it exactly like a built-in context manager
with db_connection('localhost', 5432, 'postgres', label='primary') as conn:
    with conn.cursor() as cur:
        cur.execute('SELECT pg_current_wal_lsn()')
        lsn = cur.fetchone()[0]
    print(f'Current LSN: {lsn}')
"
```

What each part does:
- `@contextmanager` - a decorator that turns a generator function into a context manager
- `yield conn` - pauses the function and hands `conn` to the `with` block. When the `with` block ends, execution resumes after `yield`.
- `try / finally` around the `yield` - ensures cleanup runs even if the `with` block raises an exception. This is the equivalent of `BEGIN ... EXCEPTION ... END` in PL/pgSQL.

Expected output (yours will differ):

```
[primary] Connecting to localhost:5432/postgres...
Current LSN: 0/1A3F8B0
[primary] Connection closed.
```

---

## Step 9: Handle a downed standby cleanly

A key advantage of `with` blocks is that they compose cleanly when one resource fails. If the standby is unavailable, the `with` block for the primary still cleans up correctly.

On your **Mac terminal**:

```bash
python3 -c "
from contextlib import contextmanager
import psycopg2

@contextmanager
def db_connection(host: str, port: int, dbname: str, label: str = ''):
    tag = f'[{label}]'
    print(f'{tag} Connecting to {host}:{port}/{dbname}...')
    conn = psycopg2.connect(host=host, port=port, dbname=dbname)
    try:
        yield conn
    finally:
        conn.close()
        print(f'{tag} Connection closed.')

# Simulate: primary is up, standby is down (wrong port)
primary_lsn = None
standby_available = False
standby_error = None

with db_connection('localhost', 5432, 'postgres', 'primary') as p_conn:
    with p_conn.cursor() as cur:
        cur.execute('SELECT pg_current_wal_lsn()')
        primary_lsn = cur.fetchone()[0]
    print(f'Primary LSN: {primary_lsn}')

    # Try to connect to standby (simulated as unavailable - wrong port)
    try:
        with db_connection('localhost', 9999, 'postgres', 'standby') as s_conn:
            with s_conn.cursor() as cur:
                cur.execute('SELECT pg_last_wal_receive_lsn()')
                standby_lsn = cur.fetchone()[0]
            standby_available = True
    except psycopg2.OperationalError as e:
        standby_error = str(e).strip()
        print(f'Standby connection failed: {standby_error}')

print(f'Primary LSN:       {primary_lsn}')
print(f'Standby available: {standby_available}')
print('Primary connection was still closed cleanly - no leak.')
"
```

What this demonstrates: the `with db_connection(..., 'primary')` block closes the primary connection even though the standby connection raised an exception. The `finally` clause in our custom context manager guarantees cleanup regardless of what the inner code does.

Expected output (yours will differ):

```
[primary] Connecting to localhost:5432/postgres...
Primary LSN: 0/1A3F8B0
[standby] Connecting to localhost:9999/postgres...
Standby connection failed: connection to server at "localhost" (::1), port 9999 failed
[primary] Connection closed.
Primary LSN:       0/1A3F8B0
Standby available: False
Primary connection was still closed cleanly - no leak.
```

---

## Step 10: Write repl_checker.py

Combine everything into a complete replication health checker. This is a script you would run from cron every 60 seconds on the primary server.

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/repl_checker.py
```

Press `i` to enter insert mode, then paste the following:

```python
from contextlib import contextmanager
from datetime import datetime
from typing import Optional
import psycopg2
import psycopg2.extras

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
PRIMARY_HOST = 'localhost'
PRIMARY_PORT = 5432
PRIMARY_DBNAME = 'postgres'

# Set to actual standby host/port in production
STANDBY_HOST = 'localhost'
STANDBY_PORT = 5432
STANDBY_DBNAME = 'postgres'

# Alert thresholds
LAG_WARN_BYTES = 10 * 1024 * 1024      # 10 MB
LAG_CRITICAL_BYTES = 100 * 1024 * 1024  # 100 MB
CONNECT_TIMEOUT_SEC = 5


@contextmanager
def db_connection(host: str, port: int, dbname: str, label: str = '',
                  connect_timeout: int = CONNECT_TIMEOUT_SEC):
    """
    Context manager that opens a psycopg2 connection, yields it,
    then closes it - even if an exception occurs inside the block.
    """
    tag = f'[{label}]' if label else ''
    conn: Optional[psycopg2.extensions.connection] = None
    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            dbname=dbname,
            connect_timeout=connect_timeout,
        )
        yield conn
    finally:
        if conn is not None:
            conn.close()


def check_primary_replication(conn: psycopg2.extensions.connection) -> list[dict]:
    """
    Query pg_stat_replication on the primary.
    Returns one dict per connected standby.
    """
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute('''
            SELECT
                application_name,
                client_addr::TEXT          AS client_addr,
                state,
                sync_state,
                sent_lsn::TEXT             AS sent_lsn,
                write_lsn::TEXT            AS write_lsn,
                flush_lsn::TEXT            AS flush_lsn,
                replay_lsn::TEXT           AS replay_lsn,
                pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)    AS send_lag_bytes,
                pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)  AS replay_lag_bytes,
                EXTRACT(EPOCH FROM write_lag)   AS write_lag_sec,
                EXTRACT(EPOCH FROM replay_lag)  AS replay_lag_sec
            FROM pg_stat_replication
            ORDER BY application_name
        ''')
        return [dict(row) for row in cur.fetchall()]


def check_wal_receiver(conn: psycopg2.extensions.connection) -> Optional[dict]:
    """
    Query pg_stat_wal_receiver on a standby.
    Returns None if this server has no WAL receiver (it is a primary).
    """
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute('''
            SELECT
                status,
                receive_start_lsn::TEXT  AS receive_start_lsn,
                received_lsn::TEXT       AS received_lsn,
                last_msg_send_time,
                last_msg_receipt_time,
                sender_host,
                sender_port
            FROM pg_stat_wal_receiver
        ''')
        row = cur.fetchone()
        return dict(row) if row else None


def get_current_lsn(conn: psycopg2.extensions.connection) -> str:
    """Return the current WAL LSN for this server."""
    with conn.cursor() as cur:
        cur.execute('SELECT pg_current_wal_lsn()')
        return cur.fetchone()[0]


def is_in_recovery(conn: psycopg2.extensions.connection) -> bool:
    """Return True if this server is a standby (in recovery mode)."""
    with conn.cursor() as cur:
        cur.execute('SELECT pg_is_in_recovery()')
        return cur.fetchone()[0]


def print_report() -> None:
    """Connect to primary (and optionally standby), print replication health report."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print('=' * 70)
    print(f'  Replication Health Checker - {timestamp}')
    print('=' * 70)

    # --- Primary check ---
    print(f'\n[PRIMARY]  {PRIMARY_HOST}:{PRIMARY_PORT}')
    try:
        with db_connection(PRIMARY_HOST, PRIMARY_PORT, PRIMARY_DBNAME, 'primary') as p_conn:
            in_recovery = is_in_recovery(p_conn)
            current_lsn = get_current_lsn(p_conn)

            if in_recovery:
                print('  WARNING: This server is in recovery mode - it is a standby, not a primary.')
            else:
                print(f'  Role:        PRIMARY')

            print(f'  Current LSN: {current_lsn}')

            standbys = check_primary_replication(p_conn)

            if standbys:
                print(f'  Connected standbys: {len(standbys)}')
                for s in standbys:
                    lag_bytes = s['replay_lag_bytes'] or 0
                    lag_sec = s['replay_lag_sec'] or 0.0
                    if lag_bytes >= LAG_CRITICAL_BYTES:
                        status = 'CRITICAL'
                    elif lag_bytes >= LAG_WARN_BYTES:
                        status = 'WARNING'
                    else:
                        status = 'OK'
                    print(f'\n  Standby: {s["application_name"]} ({s["client_addr"]})')
                    print(f'    State:       {s["state"]}  /  sync: {s["sync_state"]}')
                    print(f'    Sent LSN:    {s["sent_lsn"]}')
                    print(f'    Replay LSN:  {s["replay_lsn"]}')
                    print(f'    Replay lag:  {lag_bytes:,} bytes  ({lag_sec:.3f}s)  [{status}]')
            else:
                print('  No standbys connected.')
                print('  (In production, this would be a WARNING if standbys are expected.)')

    except psycopg2.OperationalError as e:
        print(f'  CRITICAL: Cannot connect to primary: {e}')
        print('=' * 70)
        return

    # --- Standby check (optional) ---
    # Skip if standby is the same host as primary (single-instance setup)
    if STANDBY_HOST != PRIMARY_HOST or STANDBY_PORT != PRIMARY_PORT:
        print(f'\n[STANDBY]  {STANDBY_HOST}:{STANDBY_PORT}')
        try:
            with db_connection(STANDBY_HOST, STANDBY_PORT, STANDBY_DBNAME, 'standby') as s_conn:
                in_recovery = is_in_recovery(s_conn)
                receiver = check_wal_receiver(s_conn)

                print(f'  Role:         {"STANDBY (in recovery)" if in_recovery else "PRIMARY (not in recovery - check config)"}')

                if receiver:
                    print(f'  WAL receiver: {receiver["status"]}')
                    print(f'  Receiving from: {receiver["sender_host"]}:{receiver["sender_port"]}')
                    print(f'  Received LSN:   {receiver["received_lsn"]}')
                    print(f'  Last msg from primary: {receiver["last_msg_send_time"]}')
                else:
                    print('  pg_stat_wal_receiver is empty.')
                    print('  (This may mean WAL receiver has not started yet.)')

        except psycopg2.OperationalError as e:
            print(f'  WARNING: Cannot connect to standby: {e}')
            print('  (Primary connection was still closed cleanly.)')
    else:
        print('\n[STANDBY]  Same as primary (single-instance setup - skipping standby check)')
        print('  In production, set STANDBY_HOST and STANDBY_PORT to your real standby.')

    print('\n' + '=' * 70)


if __name__ == '__main__':
    print_report()
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 11: Run the checker

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/repl_checker.py
```

Expected output (yours will differ):

```
======================================================================
  Replication Health Checker - 2026-06-13 14:22:05
======================================================================

[PRIMARY]  localhost:5432
  Role:        PRIMARY
  Current LSN: 0/1A3F8B0
  No standbys connected.
  (In production, this would be a WARNING if standbys are expected.)

[STANDBY]  Same as primary (single-instance setup - skipping standby check)
  In production, set STANDBY_HOST and STANDBY_PORT to your real standby.

======================================================================
```

The script reports no standbys because this is a single-instance local PostgreSQL. In a real streaming replication setup, you would set `STANDBY_HOST` to your standby server's IP, and the checker would show lag in bytes and seconds for each standby.

---

## Step 12: Test with a simulated standby failure

To confirm the `with` blocks clean up correctly when the standby is unreachable, temporarily point the checker at a bad port.

On your **Mac terminal**:

```bash
python3 -c "
import os, sys
sys.path.insert(0, os.path.expanduser('~/pgdba'))

# Temporarily override standby config to a bad port
import repl_checker
repl_checker.STANDBY_HOST = 'localhost'
repl_checker.STANDBY_PORT = 9999   # nothing listening here

repl_checker.print_report()
"
```

Expected output (yours will differ):

```
======================================================================
  Replication Health Checker - 2026-06-13 14:22:31
======================================================================

[PRIMARY]  localhost:5432
  Role:        PRIMARY
  Current LSN: 0/1A3F8B0
  No standbys connected.
  ...

[STANDBY]  localhost:9999
  WARNING: Cannot connect to standby: connection to server at "localhost" (::1), port 9999 failed
  (Primary connection was still closed cleanly.)

======================================================================
```

The primary connection closes cleanly even though the standby connection failed. This is the key guarantee that `with` + the custom context manager provides.

---

## What you built

You now have `~/pgdba/repl_checker.py` - a safe, connection-leak-free replication health checker. Here is how the Python concepts map to DBA knowledge:

| Python concept | DBA analogy |
|---|---|
| `with` statement | `BEGIN ... END` block that always rolls back on error |
| `@contextmanager` + `yield` | `CREATE OR REPLACE FUNCTION` with `EXCEPTION WHEN OTHERS` cleanup |
| `try / finally` in context manager | `BEGIN ... EXCEPTION WHEN OTHERS THEN ... END` |
| `pg_stat_replication` query | `SELECT * FROM pg_stat_replication` in psql |
| `pg_wal_lsn_diff()` | Calculating bytes of WAL lag for DR readiness |
| Standby `OperationalError` handling | Connection pooler detecting a standby failure |

Next: BUILD 12 - argparse: Upgrade Planner CLI
