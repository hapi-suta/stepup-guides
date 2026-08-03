# BUILD 08: Classes and OOP - PG Monitor

**What you will build:** `~/pgdba/pg_monitor.py` - a script with a `PGMonitor` class that models a monitored PostgreSQL instance. It tracks active connections, database sizes, replication lag, and lock counts, then generates a unified health report.

**Python concepts covered:** `class`, `__init__`, `self`, instance variables, instance methods, `__str__`, `__repr__`, class composition

**Time to complete:** ~55 minutes

---

## Prerequisites

- `~/pgdba/` directory exists
- `psycopg2-binary` installed (`pip3 install psycopg2-binary`)
- PostgreSQL running locally on port 5432

---

## Step 1: class basics - a blueprint for an object

In PostgreSQL, `CREATE TYPE` defines a composite type - a template that describes a structure. A Python **class** is the same idea: it is a blueprint that defines what data an object holds and what operations it can perform.

Every PostgreSQL instance you want to monitor is slightly different - different host, port, version. A class lets you define the template once and create as many instances as you need, each with its own values.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
class PGMonitor:
    pass   # 'pass' means the class body is empty for now

# Create two instances from the same blueprint
monitor_prod = PGMonitor()
monitor_dev  = PGMonitor()

print(type(monitor_prod))
print(monitor_prod)
print(monitor_dev)
print(monitor_prod is monitor_dev)
"
```

What each piece does:
- `class PGMonitor:` - defines a new class (blueprint)
- `pass` - placeholder that means 'nothing here yet'
- `PGMonitor()` - creates a new instance of the class (like `ROW(...)` constructing a composite value)
- The two instances are different objects even though they were created from the same class

Expected output (yours will differ):

```
<class '__main__.PGMonitor'>
<__main__.PGMonitor object at 0x102a1f3d0>
<__main__.PGMonitor object at 0x102a1f410>
False
```

---

## Step 2: __init__ - the constructor

`__init__` is a special method that runs automatically when you create a new instance. Think of it like `DEFAULT` values in a `CREATE TABLE` statement - it sets up the initial state of each object.

The double underscores on both sides (`__init__`) mark it as a **dunder method** (special method with special meaning to Python). There are many dunder methods; `__init__` is the most important.

On your **Mac terminal**:

```bash
python3 -c "
class PGMonitor:
    def __init__(self, host, port, dbname, label):
        # __init__ runs when you call PGMonitor(...)
        # It receives the arguments you pass
        print(f'Creating monitor for {label} at {host}:{port}')

# Create two instances - __init__ runs for each one
prod = PGMonitor('prod-db.internal', 5432, 'appdb', 'PROD')
dev  = PGMonitor('localhost',         5432, 'devdb', 'DEV')
"
```

Expected output (yours will differ):

```
Creating monitor for PROD at prod-db.internal:5432
Creating monitor for DEV at localhost:5432
```

---

## Step 3: self - the current instance

`self` is the first parameter of every method in a class. It refers to the specific instance that is calling the method - the same way `NEW` in a PostgreSQL trigger refers to the row being operated on.

When you call `monitor.connect()`, Python automatically passes `monitor` as `self`. You never pass it explicitly - Python handles it behind the scenes.

On your **Mac terminal**:

```bash
python3 -c "
class PGMonitor:
    def __init__(self, host, port, dbname, label):
        # 'self' here refers to the instance being created
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label

    def show_config(self):
        # 'self' here refers to whichever instance called show_config()
        print(f'[{self.label}] {self.host}:{self.port}/{self.dbname}')

prod = PGMonitor('prod-db.internal', 5432, 'appdb', 'PROD')
dev  = PGMonitor('localhost',         5432, 'devdb', 'DEV')

prod.show_config()   # self = prod
dev.show_config()    # self = dev
"
```

Expected output (yours will differ):

```
[PROD] prod-db.internal:5432/appdb
[DEV] localhost:5432/devdb
```

---

## Step 4: Instance variables - self.host, self.port, self.status

Instance variables are stored on `self`. Each instance has its own copy - changing `prod.status` does not affect `dev.status`. Think of them as the columns in a row: the row for PROD and the row for DEV each hold their own values.

On your **Mac terminal**:

```bash
python3 -c "
class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        # Status starts unknown until we connect
        self.status = 'unknown'
        self.conn   = None

prod = PGMonitor('prod-db.internal', 5432, 'appdb', 'PROD')
dev  = PGMonitor('localhost',         5432, 'devdb', 'DEV')

# Each instance has its own values - like two separate rows
prod.status = 'connected'
dev.status  = 'unreachable'

print(f'PROD status: {prod.status}')
print(f'DEV status:  {dev.status}')

# Access any instance variable directly
print(f'PROD host: {prod.host}')
print(f'DEV  host: {dev.host}')
"
```

Expected output (yours will differ):

```
PROD status: connected
DEV status:  unreachable
PROD host: prod-db.internal
DEV  host: localhost
```

---

## Step 5: Methods - functions that belong to a class

A method is a function defined inside a class body. It has access to the instance's data via `self`. In PostgreSQL terms, think of methods as stored procedures that operate on a specific row's data - they are bound to that instance.

On your **Mac terminal**:

```bash
python3 -c "
class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.status = 'unknown'

    def get_dsn(self):
        '''Return the connection string (like a libpq DSN).'''
        return f'host={self.host} port={self.port} dbname={self.dbname}'

    def mark_up(self):
        '''Mark this instance as healthy.'''
        self.status = 'up'

    def mark_down(self, reason):
        '''Mark this instance as down with a reason.'''
        self.status = f'down: {reason}'

mon = PGMonitor('localhost', 5432, 'postgres', 'LOCAL')
print(mon.get_dsn())
print(f'Status before: {mon.status}')

mon.mark_up()
print(f'Status after mark_up: {mon.status}')

mon.mark_down('connection refused')
print(f'Status after mark_down: {mon.status}')
"
```

Expected output (yours will differ):

```
host=localhost port=5432 dbname=postgres
Status before: unknown
Status after mark_up: up
Status after mark_down: down: connection refused
```

---

## Step 6: Build PGMonitor with connect(), get_connections(), get_db_sizes()

Now add real database operations. The `connect()` method establishes a psycopg2 connection and stores it on `self.conn` so all other methods can reuse it.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import os

class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.user   = os.environ.get('USER', 'postgres')
        self.status = 'unknown'
        self.conn   = None

    def connect(self):
        '''Open a connection to this PostgreSQL instance.'''
        try:
            self.conn = psycopg2.connect(
                host=self.host, port=self.port,
                dbname=self.dbname, user=self.user
            )
            self.status = 'connected'
        except psycopg2.OperationalError as e:
            self.status = f'error: {e}'
            self.conn = None

    def get_connections(self):
        '''Return active connection count by state from pg_stat_activity.'''
        if not self.conn:
            return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT state, COUNT(*)
            FROM pg_stat_activity
            WHERE pid <> pg_backend_pid()
            GROUP BY state
            ORDER BY state
        ''')
        rows = cur.fetchall()
        cur.close()
        return {state if state else 'idle': count for state, count in rows}

    def get_db_sizes(self):
        '''Return database sizes in MB as a dict.'''
        if not self.conn:
            return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT datname, pg_database_size(datname) / 1024 / 1024 AS size_mb
            FROM pg_database
            WHERE datname NOT IN ('template0', 'template1')
            ORDER BY size_mb DESC
        ''')
        rows = cur.fetchall()
        cur.close()
        return {db: size for db, size in rows}

mon = PGMonitor('localhost', 5432, 'postgres', 'LOCAL')
mon.connect()
print(f'Status: {mon.status}')

connections = mon.get_connections()
print(f'Connections: {connections}')

sizes = mon.get_db_sizes()
for db, mb in sizes.items():
    print(f'  {db}: {mb} MB')

mon.conn.close()
"
```

Expected output (yours will differ):

```
Status: connected
Connections: {'idle': 2, 'active': 1}
  appdb: 312 MB
  postgres: 8 MB
```

---

## Step 7: get_replication_lag() method

Add a method that queries `pg_stat_replication` to find streaming standbys and their lag. On a primary with no standbys, this returns an empty dict - which is fine.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import os

class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.user   = os.environ.get('USER', 'postgres')
        self.conn   = None

    def connect(self):
        try:
            self.conn = psycopg2.connect(
                host=self.host, port=self.port,
                dbname=self.dbname, user=self.user
            )
        except psycopg2.OperationalError as e:
            print(f'Connect failed: {e}')

    def get_replication_lag(self):
        '''Return replication lag in bytes per standby. Empty dict if no standbys.'''
        if not self.conn:
            return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT
                application_name,
                client_addr::TEXT,
                state,
                pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
            FROM pg_stat_replication
        ''')
        rows = cur.fetchall()
        cur.close()
        result = {}
        for app_name, client_addr, state, lag_bytes in rows:
            result[app_name] = {
                'client_addr': client_addr,
                'state':       state,
                'lag_bytes':   lag_bytes if lag_bytes else 0
            }
        return result

mon = PGMonitor('localhost', 5432, 'postgres', 'LOCAL')
mon.connect()
lag = mon.get_replication_lag()

if lag:
    for standby, info in lag.items():
        print(f'{standby} ({info[\"client_addr\"]}): lag={info[\"lag_bytes\"]} bytes, state={info[\"state\"]}')
else:
    print('No streaming standbys connected (this is a standalone or all standbys are disconnected)')

mon.conn.close()
"
```

Expected output (yours will differ):

```
No streaming standbys connected (this is a standalone or all standbys are disconnected)
```

---

## Step 8: get_lock_count() method

Add a method that counts blocked queries - the most operationally urgent metric. A non-zero blocked count means something is waiting, which may need your attention.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import os

class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.user   = os.environ.get('USER', 'postgres')
        self.conn   = None

    def connect(self):
        try:
            self.conn = psycopg2.connect(
                host=self.host, port=self.port,
                dbname=self.dbname, user=self.user
            )
        except psycopg2.OperationalError as e:
            print(f'Connect failed: {e}')

    def get_lock_count(self):
        '''Return total locks and blocked query count.'''
        if not self.conn:
            return {'total_locks': 0, 'blocked_queries': 0}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT
                COUNT(*) AS total_locks,
                COUNT(*) FILTER (WHERE NOT granted) AS blocked
            FROM pg_locks
        ''')
        total, blocked = cur.fetchone()
        cur.close()
        return {
            'total_locks':    total,
            'blocked_queries': blocked
        }

mon = PGMonitor('localhost', 5432, 'postgres', 'LOCAL')
mon.connect()
locks = mon.get_lock_count()

print(f'Total locks:     {locks[\"total_locks\"]}')
print(f'Blocked queries: {locks[\"blocked_queries\"]}')

if locks['blocked_queries'] > 0:
    print('WARNING: blocked queries detected - investigate pg_locks')
else:
    print('No blocked queries')

mon.conn.close()
"
```

Expected output (yours will differ):

```
Total locks:     14
Blocked queries: 0
No blocked queries
```

---

## Step 9: __str__ - human-readable output

`__str__` is a dunder method that Python calls when you do `print(object)` or `str(object)`. Without it, Python shows something like `<PGMonitor object at 0x...>`. With it, you control exactly what gets printed.

This is like defining a custom `CAST(monitor AS TEXT)` in PostgreSQL - you decide how the object serializes to a readable string.

On your **Mac terminal**:

```bash
python3 -c "
class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.status = 'unknown'

    def __str__(self):
        # Called by print() and str()
        return f'PGMonitor [{self.label}] {self.host}:{self.port}/{self.dbname} ({self.status})'

    def __repr__(self):
        # Called in Python shell and for debugging - shows how to recreate the object
        return f'PGMonitor(host={self.host!r}, port={self.port}, dbname={self.dbname!r}, label={self.label!r})'

prod = PGMonitor('prod-db.internal', 5432, 'appdb', 'PROD')
prod.status = 'connected'

# print() uses __str__
print(prod)

# repr() uses __repr__ - shows developer-facing info
print(repr(prod))

# In a list, Python uses __repr__
monitors = [prod, PGMonitor('localhost', 5432, 'postgres', 'LOCAL')]
print(monitors)
"
```

Expected output (yours will differ):

```
PGMonitor [PROD] prod-db.internal:5432/appdb (connected)
PGMonitor(host='prod-db.internal', port=5432, dbname='appdb', label='PROD')
[PGMonitor(host='prod-db.internal', port=5432, dbname='appdb', label='PROD'), PGMonitor(host='localhost', port=5432, dbname='postgres', label='LOCAL')]
```

---

## Step 10: Build a full health_report() method

`health_report()` calls all the other methods and formats a consolidated report - the equivalent of a DBA health check dashboard.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import os

class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.user   = os.environ.get('USER', 'postgres')
        self.status = 'unknown'
        self.conn   = None

    def __str__(self):
        return f'PGMonitor [{self.label}] {self.host}:{self.port}/{self.dbname} ({self.status})'

    def connect(self):
        try:
            self.conn = psycopg2.connect(
                host=self.host, port=self.port,
                dbname=self.dbname, user=self.user
            )
            self.status = 'connected'
        except psycopg2.OperationalError as e:
            self.status = f'error: {e}'

    def get_connections(self):
        if not self.conn: return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT state, COUNT(*) FROM pg_stat_activity
            WHERE pid <> pg_backend_pid() GROUP BY state ORDER BY state
        ''')
        rows = cur.fetchall()
        cur.close()
        return {(state if state else 'idle'): count for state, count in rows}

    def get_db_sizes(self):
        if not self.conn: return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT datname, pg_database_size(datname) / 1024 / 1024 AS size_mb
            FROM pg_database WHERE datname NOT IN ('template0','template1')
            ORDER BY size_mb DESC
        ''')
        rows = cur.fetchall()
        cur.close()
        return {db: size for db, size in rows}

    def get_lock_count(self):
        if not self.conn: return {'total_locks': 0, 'blocked_queries': 0}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT COUNT(*), COUNT(*) FILTER (WHERE NOT granted)
            FROM pg_locks
        ''')
        total, blocked = cur.fetchone()
        cur.close()
        return {'total_locks': total, 'blocked_queries': blocked}

    def get_replication_lag(self):
        if not self.conn: return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT application_name, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)
            FROM pg_stat_replication
        ''')
        rows = cur.fetchall()
        cur.close()
        return {app: lag for app, lag in rows}

    def health_report(self):
        print('=' * 60)
        print(f'  Health Report: {self}')
        print('=' * 60)

        if self.status != 'connected':
            print(f'  CANNOT CONNECT: {self.status}')
            print('=' * 60)
            return

        connections = self.get_connections()
        db_sizes    = self.get_db_sizes()
        locks       = self.get_lock_count()
        repl_lag    = self.get_replication_lag()

        print('  CONNECTIONS')
        if connections:
            for state, count in connections.items():
                print(f'    {state:<20} {count}')
        else:
            print('    none')

        print()
        print('  DATABASE SIZES')
        for db, mb in db_sizes.items():
            print(f'    {db:<25} {mb} MB')

        print()
        print('  LOCKS')
        print(f'    Total locks:     {locks[\"total_locks\"]}')
        blocked = locks['blocked_queries']
        flag = ' *** INVESTIGATE ***' if blocked > 0 else ''
        print(f'    Blocked queries: {blocked}{flag}')

        print()
        print('  REPLICATION')
        if repl_lag:
            for app, lag in repl_lag.items():
                print(f'    {app}: {lag} bytes behind')
        else:
            print('    No streaming standbys')

        print('=' * 60)

mon = PGMonitor('localhost', 5432, 'postgres', 'LOCAL')
mon.connect()
mon.health_report()
if mon.conn:
    mon.conn.close()
"
```

Expected output (yours will differ):

```
============================================================
  Health Report: PGMonitor [LOCAL] localhost:5432/postgres (connected)
============================================================
  CONNECTIONS
    idle                 2
    active               1

  DATABASE SIZES
    appdb                    312 MB
    postgres                   8 MB

  LOCKS
    Total locks:     14
    Blocked queries: 0

  REPLICATION
    No streaming standbys
============================================================
```

---

## Step 11: Create two instances - monitor_prod and monitor_dev

The power of classes is that you create one blueprint and stamp out as many instances as you need - one per environment, one per cluster.

On your **Mac terminal**:

```bash
python3 -c "
import os

# Simulate two instances - both point to localhost for this demo
# In production these would be different hostnames
class PGMonitor:
    def __init__(self, host, port, dbname, label):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.status = 'unknown'

    def __str__(self):
        return f'PGMonitor [{self.label}] {self.host}:{self.port}/{self.dbname} ({self.status})'

# Each instance is independent - different labels, same underlying class
monitor_prod = PGMonitor('prod-primary.internal', 5432, 'appdb',    'PROD')
monitor_dev  = PGMonitor('localhost',              5432, 'postgres', 'DEV')

# Iterate over a list of monitors - like a cursor loop over a list of servers
monitors = [monitor_prod, monitor_dev]
for m in monitors:
    print(m)
    print(f'  Would connect to: {m.host}:{m.port}/{m.dbname}')
"
```

Expected output (yours will differ):

```
PGMonitor [PROD] prod-primary.internal:5432/appdb (unknown)
  Would connect to: prod-primary.internal:5432/appdb
PGMonitor [DEV] localhost:5432/postgres (unknown)
  Would connect to: localhost:5432/postgres
```

---

## Step 12: Combine into pg_monitor.py

Open vi and write the complete script:

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/pg_monitor.py
```

Press `i` to enter insert mode, then type or paste the following:

```python
import psycopg2
import os

# -------------------------------------------------------
# PGMonitor class - models one monitored PostgreSQL instance
# -------------------------------------------------------
class PGMonitor:

    def __init__(self, host: str, port: int, dbname: str, label: str):
        self.host   = host
        self.port   = port
        self.dbname = dbname
        self.label  = label
        self.user   = os.environ.get('USER', 'postgres')
        self.status = 'unknown'
        self.conn:  psycopg2.extensions.connection | None = None

    def __str__(self) -> str:
        return f'PGMonitor [{self.label}] {self.host}:{self.port}/{self.dbname} ({self.status})'

    def __repr__(self) -> str:
        return f'PGMonitor(host={self.host!r}, port={self.port}, dbname={self.dbname!r}, label={self.label!r})'

    # -------------------------------------------------------
    # Connect / disconnect
    # -------------------------------------------------------
    def connect(self) -> None:
        try:
            self.conn = psycopg2.connect(
                host=self.host, port=self.port,
                dbname=self.dbname, user=self.user
            )
            self.status = 'connected'
        except psycopg2.OperationalError as e:
            self.status = f'error: {e}'
            self.conn = None

    def disconnect(self) -> None:
        if self.conn:
            self.conn.close()
            self.conn = None
            self.status = 'disconnected'

    # -------------------------------------------------------
    # Metrics
    # -------------------------------------------------------
    def get_connections(self) -> dict:
        if not self.conn:
            return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT state, COUNT(*)
            FROM pg_stat_activity
            WHERE pid <> pg_backend_pid()
            GROUP BY state
            ORDER BY state
        ''')
        rows = cur.fetchall()
        cur.close()
        return {(state if state else 'idle'): count for state, count in rows}

    def get_db_sizes(self) -> dict:
        if not self.conn:
            return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT datname, pg_database_size(datname) / 1024 / 1024 AS size_mb
            FROM pg_database
            WHERE datname NOT IN ('template0', 'template1')
            ORDER BY size_mb DESC
        ''')
        rows = cur.fetchall()
        cur.close()
        return {db: size for db, size in rows}

    def get_replication_lag(self) -> dict:
        if not self.conn:
            return {}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT
                application_name,
                client_addr::TEXT,
                state,
                pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
            FROM pg_stat_replication
        ''')
        rows = cur.fetchall()
        cur.close()
        result = {}
        for app_name, client_addr, state, lag_bytes in rows:
            result[app_name] = {
                'client_addr': client_addr,
                'state':       state,
                'lag_bytes':   lag_bytes if lag_bytes else 0
            }
        return result

    def get_lock_count(self) -> dict:
        if not self.conn:
            return {'total_locks': 0, 'blocked_queries': 0}
        cur = self.conn.cursor()
        cur.execute('''
            SELECT
                COUNT(*) AS total_locks,
                COUNT(*) FILTER (WHERE NOT granted) AS blocked
            FROM pg_locks
        ''')
        total, blocked = cur.fetchone()
        cur.close()
        return {'total_locks': total, 'blocked_queries': blocked}

    # -------------------------------------------------------
    # Health report - runs all checks
    # -------------------------------------------------------
    def health_report(self) -> None:
        print('=' * 65)
        print(f'  Health Report: {self}')
        print('=' * 65)

        if self.status != 'connected':
            print(f'  CANNOT CONNECT: {self.status}')
            print('=' * 65)
            return

        connections = self.get_connections()
        db_sizes    = self.get_db_sizes()
        locks       = self.get_lock_count()
        repl_lag    = self.get_replication_lag()

        print('  CONNECTIONS')
        if connections:
            for state, count in connections.items():
                print(f'    {state:<20} {count}')
        else:
            print('    no activity')

        print()
        print('  DATABASE SIZES')
        for db, mb in db_sizes.items():
            print(f'    {db:<30} {mb} MB')

        print()
        print('  LOCKS')
        print(f'    Total locks:     {locks["total_locks"]}')
        blocked = locks['blocked_queries']
        flag = '  *** INVESTIGATE ***' if blocked > 0 else ''
        print(f'    Blocked queries: {blocked}{flag}')

        print()
        print('  REPLICATION')
        if repl_lag:
            for app, info in repl_lag.items():
                print(f'    {app} ({info["client_addr"]}): lag={info["lag_bytes"]} bytes, state={info["state"]}')
        else:
            print('    No streaming standbys')

        print('=' * 65)


# -------------------------------------------------------
# Main - create two monitors and run health_report on each
# -------------------------------------------------------
if __name__ == '__main__':
    # In production, change these to your actual server addresses
    monitors = [
        PGMonitor('localhost', 5432, 'postgres', 'LOCAL'),
    ]

    for monitor in monitors:
        monitor.connect()
        monitor.health_report()
        monitor.disconnect()
        print()
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 13: Run the script

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/pg_monitor.py
```

Expected output (yours will differ):

```
=================================================================
  Health Report: PGMonitor [LOCAL] localhost:5432/postgres (connected)
=================================================================
  CONNECTIONS
    idle                 2
    active               1

  DATABASE SIZES
    postgres                       8 MB

  LOCKS
    Total locks:     14
    Blocked queries: 0

  REPLICATION
    No streaming standbys
=================================================================
```

To monitor multiple instances, add more entries to the `monitors` list in `pg_monitor.py`:

```python
monitors = [
    PGMonitor('localhost',             5432, 'postgres', 'LOCAL'),
    PGMonitor('prod-primary.internal', 5432, 'appdb',    'PROD'),
    PGMonitor('prod-standby.internal', 5432, 'appdb',    'PROD-STANDBY'),
]
```

---

## What you built

You now have `~/pgdba/pg_monitor.py` - a reusable monitoring class that demonstrates:

| Python concept | DBA analogy |
|---|---|
| `class PGMonitor:` | `CREATE TYPE` - a blueprint/template |
| `__init__(self, ...)` | `DEFAULT` values in `CREATE TABLE` |
| `self` | `NEW` in a trigger - refers to the current instance |
| Instance variables | Column values in a specific row |
| Methods | Stored procedures bound to a type |
| `__str__` | Custom `CAST(monitor AS TEXT)` |
| `__repr__` | Developer-facing debug representation |
| Multiple instances | Multiple rows from the same table |

Next: BUILD 09 - String Formatting: Backup Automator
