# Build 01: Async Python for Agents

Before building AI agents, you need async Python. Agents spend most of their time waiting - waiting for LLM API responses, waiting for database queries, waiting for health checks. Async lets you do useful work during that wait.

---

## Step 1. Why async matters for DBA work

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# WHY ASYNC MATTERS
# Checking 10 database servers: sync vs async
#
# DBA analogy: imagine you call 10 database servers on the phone.
# Sync = call one, wait for answer, hang up, call next.
# Async = conference call - ask all 10 at once.
# ============================================================

import time

print("Why Async Matters for DBA Work")
print("=" * 50)

# Simulate checking database servers synchronously
def check_server_sync(server_name, latency):
    """Check one server. Blocks for 'latency' seconds."""
    time.sleep(latency)
    return {"server": server_name, "status": "healthy", "connections": 42}

servers = [
    ("pg-primary", 0.2),
    ("pg-replica-1", 0.15),
    ("pg-replica-2", 0.18),
    ("pg-analytics", 0.25),
    ("pg-reporting", 0.12),
]

# Synchronous: check one at a time
start = time.time()
results = []
for name, latency in servers:
    result = check_server_sync(name, latency)
    results.append(result)
sync_time = time.time() - start

print(f"\nSynchronous (one at a time):")
print(f"  Servers checked: {len(results)}")
print(f"  Total time: {sync_time:.2f} seconds")
print(f"  Each server waited for the previous one to finish.")

# Show the math
total_latency = sum(lat for _, lat in servers)
print(f"\n  Individual latencies: {[lat for _, lat in servers]}")
print(f"  Sum of latencies: {total_latency:.2f}s")
print(f"  Actual time: {sync_time:.2f}s (close to the sum)")

print(f"""
With async, all 5 checks run concurrently.
Total time = slowest single check (~0.25s), not the sum (0.90s).
That's a {total_latency / max(lat for _, lat in servers):.1f}x speedup.

Now imagine 100 servers. Sync = 100 * 0.2s = 20 seconds.
Async = 0.25 seconds. That's an 80x speedup.

DBA parallel: this is why PgBouncer exists. One process handles
thousands of connections by not blocking on any single one.
""")
PYEOF
```

Expected output (yours will differ):
```
Why Async Matters for DBA Work
==================================================

Synchronous (one at a time):
  Servers checked: 5
  Total time: 0.90 seconds
  Each server waited for the previous one to finish.

  Individual latencies: [0.2, 0.15, 0.18, 0.25, 0.12]
  Sum of latencies: 0.90s
  Actual time: 0.90s (close to the sum)

With async, all 5 checks run concurrently.
Total time = slowest single check (~0.25s), not the sum (0.90s).
That's a 3.6x speedup.
...
```

---

## Step 2. async/await basics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ASYNC/AWAIT BASICS
#
# Two keywords to learn:
#   async def - declares a coroutine (a function that can pause)
#   await     - pauses here until the result is ready
#
# DBA analogy:
#   async def = "I'm a query that might need to wait for I/O"
#   await     = "I'm waiting for WAL flush / disk read / network"
#   While I wait, PostgreSQL runs other queries.
# ============================================================

import asyncio

print("Async/Await Basics")
print("=" * 50)

# A regular function - blocks until done
def check_sync():
    import time
    time.sleep(0.5)
    return "done (sync)"

# An async function (coroutine) - can pause and let others run
async def check_async(name, delay):
    """
    This is a coroutine. When it hits 'await', it pauses
    and lets other coroutines run.

    DBA analogy: like a PostgreSQL backend that releases the CPU
    while waiting for a disk read. Other backends run instead.
    """
    print(f"  [{name}] Starting check...")
    await asyncio.sleep(delay)  # Non-blocking sleep
    print(f"  [{name}] Done after {delay}s")
    return {"server": name, "status": "healthy"}

# Run a single async function
print("\n1. Running a single coroutine:")
result = asyncio.run(check_async("pg-primary", 0.3))
print(f"   Result: {result}")

# Run multiple coroutines concurrently with gather()
print("\n2. Running 3 coroutines concurrently with gather():")

async def check_all():
    """
    asyncio.gather() runs all coroutines concurrently.
    Like running 3 queries in 3 psql windows at once.
    """
    import time
    start = time.time()

    results = await asyncio.gather(
        check_async("pg-primary", 0.3),
        check_async("pg-replica-1", 0.2),
        check_async("pg-replica-2", 0.25),
    )

    elapsed = time.time() - start
    print(f"\n   All 3 completed in {elapsed:.2f}s (not 0.75s!)")
    return results

results = asyncio.run(check_all())
print(f"   Results: {results}")

print("""
Key points:
  - async def creates a coroutine (not a regular function)
  - await pauses the coroutine (lets others run)
  - asyncio.run() starts the event loop and runs a coroutine
  - asyncio.gather() runs multiple coroutines concurrently

  You CANNOT call await outside an async function.
  You CANNOT call a coroutine like a regular function
  (it returns a coroutine object, not the result).
""")
PYEOF
```

Expected output (yours will differ):
```
Async/Await Basics
==================================================

1. Running a single coroutine:
  [pg-primary] Starting check...
  [pg-primary] Done after 0.3s
   Result: {'server': 'pg-primary', 'status': 'healthy'}

2. Running 3 coroutines concurrently with gather():
  [pg-primary] Starting check...
  [pg-replica-1] Starting check...
  [pg-replica-2] Starting check...
  [pg-replica-1] Done after 0.2s
  [pg-replica-2] Done after 0.25s
  [pg-primary] Done after 0.3s

   All 3 completed in 0.30s (not 0.75s!)
...
```

---

## Step 3. Async health checker for multiple PostgreSQL servers

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ASYNC HEALTH CHECKER
# Check 5 PostgreSQL servers concurrently.
#
# We simulate the checks since you may not have 5 PG servers,
# but the async pattern is exactly what you'd use in production.
#
# DBA analogy: like running SELECT 1 against every server
# in your fleet simultaneously, instead of one at a time.
# ============================================================

import asyncio
import time
import random

print("Async PostgreSQL Health Checker")
print("=" * 50)

# Simulated server configs
SERVERS = {
    "pg-primary": {"host": "10.0.1.10", "port": 5432, "role": "primary"},
    "pg-replica-1": {"host": "10.0.1.11", "port": 5432, "role": "replica"},
    "pg-replica-2": {"host": "10.0.1.12", "port": 5432, "role": "replica"},
    "pg-analytics": {"host": "10.0.2.10", "port": 5432, "role": "primary"},
    "pg-reporting": {"host": "10.0.2.11", "port": 5432, "role": "replica"},
}

async def check_server_health(name, config):
    """
    Check a single server's health.

    In production, this would:
      1. Connect to PostgreSQL (asyncpg or psycopg3 async)
      2. Run SELECT 1 (connectivity check)
      3. Query pg_stat_activity (connection count)
      4. Check replication lag (if replica)

    We simulate with random delays and results.
    """
    # Simulate network latency (100-300ms)
    latency = random.uniform(0.1, 0.3)
    await asyncio.sleep(latency)

    # Simulate health check results
    connections = random.randint(10, 200)
    replication_lag = random.uniform(0, 5.0) if config["role"] == "replica" else 0.0

    # Determine health status
    if connections > 180:
        status = "warning"
        issue = f"High connections: {connections}/200"
    elif replication_lag > 3.0:
        status = "warning"
        issue = f"Replication lag: {replication_lag:.1f}s"
    else:
        status = "healthy"
        issue = None

    return {
        "server": name,
        "host": config["host"],
        "role": config["role"],
        "status": status,
        "connections": connections,
        "replication_lag_seconds": round(replication_lag, 2),
        "latency_ms": round(latency * 1000),
        "issue": issue,
    }

async def run_health_check():
    """Check all servers concurrently."""
    start = time.time()

    # Create a task for each server
    tasks = [
        check_server_health(name, config)
        for name, config in SERVERS.items()
    ]

    # Run all tasks concurrently
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start

    # Display results
    print(f"\nHealth Check Results ({elapsed:.2f}s for {len(results)} servers)")
    print("-" * 65)
    print(f"{'Server':<18} {'Role':<10} {'Status':<10} {'Conns':<8} {'Rep Lag':<10} {'Issue'}")
    print("-" * 65)

    warnings = []
    for r in results:
        lag_str = f"{r['replication_lag_seconds']:.2f}s" if r["role"] == "replica" else "n/a"
        issue_str = r["issue"] or ""
        status_marker = "!!" if r["status"] == "warning" else "  "
        print(f"{status_marker}{r['server']:<16} {r['role']:<10} {r['status']:<10} {r['connections']:<8} {lag_str:<10} {issue_str}")
        if r["status"] == "warning":
            warnings.append(r)

    print(f"\nSummary:")
    print(f"  Total servers: {len(results)}")
    print(f"  Healthy: {sum(1 for r in results if r['status'] == 'healthy')}")
    print(f"  Warnings: {len(warnings)}")
    print(f"  Check time: {elapsed:.2f}s (async - all concurrent)")
    print(f"  Sequential would take: ~{sum(r['latency_ms'] for r in results) / 1000:.2f}s")

    return results

# Run the health check
asyncio.run(run_health_check())

print("""
This checked 5 servers in ~0.3s instead of ~1.0s.
In production with 100+ servers, the speedup is dramatic.

Pattern: asyncio.gather(*tasks) is your best friend for
"check many things at once" scenarios.
""")
PYEOF
```

Expected output (yours will differ):
```
Async PostgreSQL Health Checker
==================================================

Health Check Results (0.28s for 5 servers)
-----------------------------------------------------------------
Server             Role       Status     Conns    Rep Lag    Issue
-----------------------------------------------------------------
  pg-primary       primary    healthy    87       n/a
  pg-replica-1     replica    healthy    45       0.82s
!!pg-replica-2     replica    warning    23       4.21s      Replication lag: 4.2s
  pg-analytics     primary    healthy    156      n/a
  pg-reporting     replica    healthy    34       1.15s

Summary:
  Total servers: 5
  Healthy: 4
  Warnings: 1
...
```

---

## Step 4. aiohttp for async HTTP calls

On your **Mac terminal**, first install aiohttp:

```bash
pip3 install aiohttp
```

Then run:

```bash
python3 << 'PYEOF'

# ============================================================
# AIOHTTP: ASYNC HTTP CLIENT
#
# When your agent calls LLM APIs or monitoring endpoints,
# it needs async HTTP. aiohttp is the standard library for this.
#
# DBA analogy: like using connection pooling (PgBouncer) for HTTP.
# One session manages many concurrent requests efficiently.
# ============================================================

import asyncio
import aiohttp
import time

print("aiohttp: Async HTTP Client")
print("=" * 50)

# We'll use httpbin.org for demonstration (public test API)
# In production, these would be your monitoring endpoints

async def fetch_url(session, url, label):
    """
    Fetch a URL using an existing session.

    'session' is reused across requests (connection pooling).
    DBA analogy: like reusing a database connection from a pool
    instead of connecting/disconnecting for every query.
    """
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as response:
            data = await response.json()
            return {"label": label, "status": response.status, "success": True}
    except Exception as e:
        return {"label": label, "error": str(e), "success": False}

async def demo_aiohttp():
    """Demonstrate async HTTP with connection pooling."""

    # aiohttp.ClientSession is like a connection pool
    # Create it once, reuse for all requests
    async with aiohttp.ClientSession() as session:
        print("\n1. Single request:")
        result = await fetch_url(
            session, "https://httpbin.org/get", "single-request"
        )
        print(f"   {result}")

        print("\n2. Multiple concurrent requests:")
        start = time.time()

        # Fetch 5 URLs concurrently
        urls = [
            ("https://httpbin.org/delay/1", "endpoint-1"),
            ("https://httpbin.org/delay/1", "endpoint-2"),
            ("https://httpbin.org/delay/1", "endpoint-3"),
            ("https://httpbin.org/delay/1", "endpoint-4"),
            ("https://httpbin.org/delay/1", "endpoint-5"),
        ]

        tasks = [fetch_url(session, url, label) for url, label in urls]
        results = await asyncio.gather(*tasks)

        elapsed = time.time() - start
        print(f"   Fetched {len(results)} URLs in {elapsed:.2f}s")
        print(f"   (Each has 1s delay, but async = ~1s total, not 5s)")
        for r in results:
            status = "OK" if r["success"] else f"FAIL: {r.get('error', '?')}"
            print(f"   {r['label']}: {status}")

    # Session is automatically closed here (async context manager)
    print("\n   Session closed automatically (async context manager)")

try:
    asyncio.run(demo_aiohttp())
except Exception as e:
    # If no internet, show the pattern anyway
    print(f"\n   (Network unavailable: {e})")
    print("   The pattern still applies - aiohttp.ClientSession()")
    print("   manages connection pooling for async HTTP.")

print("""
Key patterns:
  1. Create ONE ClientSession, reuse it (connection pooling)
  2. Use 'async with' for automatic cleanup
  3. Use asyncio.gather() for concurrent requests
  4. Set timeouts to avoid hanging forever

  async with aiohttp.ClientSession() as session:
      results = await asyncio.gather(
          fetch(session, url1),
          fetch(session, url2),
          fetch(session, url3),
      )

DBA parallel: this is like PgBouncer's connection pooling.
You don't open a new TCP connection for every query.
You reuse connections from a pool.
""")
PYEOF
```

Expected output (yours will differ):
```
aiohttp: Async HTTP Client
==================================================

1. Single request:
   {'label': 'single-request', 'status': 200, 'success': True}

2. Multiple concurrent requests:
   Fetched 5 URLs in 1.23s
   (Each has 1s delay, but async = ~1s total, not 5s)
   endpoint-1: OK
   endpoint-2: OK
...
```

---

## Step 5. Async context managers

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ASYNC CONTEXT MANAGERS
#
# Regular context managers: with open("file") as f:
# Async context managers:   async with connect() as conn:
#
# DBA analogy: like a connection that automatically returns
# to the pool when you're done, even if an error occurs.
# ============================================================

import asyncio

print("Async Context Managers")
print("=" * 50)

# ---- Example 1: Async database connection pool ----

class AsyncConnectionPool:
    """
    Simulated async connection pool.

    In production, you'd use asyncpg.create_pool() or
    psycopg3's AsyncConnectionPool. Same pattern.

    DBA analogy: this IS connection pooling. The pool
    manages connections, hands them out on request,
    and takes them back when you're done.
    """

    def __init__(self, dsn, min_size=2, max_size=10):
        self.dsn = dsn
        self.min_size = min_size
        self.max_size = max_size
        self._pool = []
        self._in_use = 0

    async def __aenter__(self):
        """Called when entering 'async with pool'."""
        print(f"  Pool: Opening pool to {self.dsn} (min={self.min_size}, max={self.max_size})")
        # Simulate creating initial connections
        await asyncio.sleep(0.1)
        self._pool = [f"conn-{i}" for i in range(self.min_size)]
        print(f"  Pool: Created {len(self._pool)} initial connections")
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Called when exiting 'async with pool' (even on error)."""
        print(f"  Pool: Closing all {len(self._pool)} connections")
        self._pool.clear()
        self._in_use = 0
        # Return False to propagate exceptions (don't swallow them)
        return False

    async def acquire(self):
        """Get a connection from the pool."""
        if self._pool:
            conn = self._pool.pop()
            self._in_use += 1
            return conn
        elif self._in_use < self.max_size:
            self._in_use += 1
            conn = f"conn-{self._in_use + self.min_size}"
            return conn
        else:
            raise Exception("Pool exhausted - max_size reached")

    async def release(self, conn):
        """Return a connection to the pool."""
        self._pool.append(conn)
        self._in_use -= 1


# ---- Example 2: Async connection context manager ----

class AsyncConnection:
    """Context manager for a single pooled connection."""

    def __init__(self, pool):
        self.pool = pool
        self.conn = None

    async def __aenter__(self):
        self.conn = await self.pool.acquire()
        return self.conn

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.conn:
            await self.pool.release(self.conn)
        return False


async def demo_context_managers():
    """Show how async context managers work."""

    print("\n1. Pool lifecycle (async with):")
    async with AsyncConnectionPool("postgresql://localhost/mydb") as pool:
        # Pool is open here

        print("\n2. Using connections from the pool:")
        async with AsyncConnection(pool) as conn:
            print(f"     Got connection: {conn}")
            # Simulate running a query
            await asyncio.sleep(0.05)
            print(f"     Ran query on {conn}")
        # Connection automatically returned to pool

        print("\n3. Multiple connections concurrently:")
        async def worker(pool, worker_id):
            async with AsyncConnection(pool) as conn:
                print(f"     Worker {worker_id} using {conn}")
                await asyncio.sleep(0.1)
                print(f"     Worker {worker_id} done with {conn}")

        await asyncio.gather(
            worker(pool, 1),
            worker(pool, 2),
            worker(pool, 3),
        )

    # Pool is closed here (all connections cleaned up)
    print("\n4. Pool closed automatically (exited 'async with')")

asyncio.run(demo_context_managers())

print("""
Key patterns:
  __aenter__  = setup (open pool, acquire connection)
  __aexit__   = cleanup (release connection, close pool)

  async with Pool() as pool:         # opens pool
      async with pool.acquire() as conn:  # gets connection
          await conn.execute(query)  # uses connection
      # connection returned to pool
  # pool closed

  The cleanup ALWAYS runs, even if an error occurs.
  DBA analogy: like BEGIN ... COMMIT/ROLLBACK.
  The transaction always ends, one way or another.
""")
PYEOF
```

Expected output (yours will differ):
```
Async Context Managers
==================================================

1. Pool lifecycle (async with):
  Pool: Opening pool to postgresql://localhost/mydb (min=2, max=10)
  Pool: Created 2 initial connections

2. Using connections from the pool:
     Got connection: conn-1
     Ran query on conn-1

3. Multiple connections concurrently:
     Worker 1 using conn-1
     Worker 2 using conn-0
     Worker 3 using conn-3
     Worker 1 done with conn-1
     Worker 2 done with conn-0
     Worker 3 done with conn-3

4. Pool closed automatically (exited 'async with')
  Pool: Closing all 2 connections
...
```

---

## Step 6. Error handling in async code

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ERROR HANDLING IN ASYNC CODE
#
# Async errors are tricky. If one task fails in gather(),
# what happens to the others? You need to handle this.
#
# DBA analogy: if one replica goes down during a fleet check,
# you still want results from the other 9 servers.
# ============================================================

import asyncio

print("Error Handling in Async Code")
print("=" * 50)

# ---- Problem: one bad task kills everything ----

async def check_server(name, should_fail=False):
    """Simulate a server check that might fail."""
    await asyncio.sleep(0.1)
    if should_fail:
        raise ConnectionError(f"Cannot connect to {name}: Connection refused")
    return {"server": name, "status": "healthy"}

print("\n1. Default gather() - one failure cancels all:")
async def demo_failure():
    try:
        results = await asyncio.gather(
            check_server("pg-primary"),
            check_server("pg-replica-1", should_fail=True),  # This fails
            check_server("pg-replica-2"),
        )
    except ConnectionError as e:
        print(f"   FAILED: {e}")
        print(f"   We lost ALL results, not just the failed one!")

asyncio.run(demo_failure())

# ---- Solution: return_exceptions=True ----

print("\n2. gather(return_exceptions=True) - get all results:")
async def demo_return_exceptions():
    results = await asyncio.gather(
        check_server("pg-primary"),
        check_server("pg-replica-1", should_fail=True),
        check_server("pg-replica-2"),
        return_exceptions=True,  # Don't raise, return exceptions as results
    )

    for r in results:
        if isinstance(r, Exception):
            print(f"   FAILED: {r}")
        else:
            print(f"   OK: {r}")

asyncio.run(demo_return_exceptions())

# ---- Better pattern: wrap each task with error handling ----

print("\n3. Best pattern - wrap each task individually:")
async def safe_check(name, should_fail=False):
    """
    Wrap a server check with error handling.
    Always returns a result dict, never raises.

    DBA analogy: like a monitoring script that logs errors
    instead of crashing. You want the overall health report,
    even if some servers are unreachable.
    """
    try:
        result = await check_server(name, should_fail)
        return {"server": name, "success": True, "data": result}
    except Exception as e:
        return {"server": name, "success": False, "error": str(e)}

async def demo_safe_check():
    results = await asyncio.gather(
        safe_check("pg-primary"),
        safe_check("pg-replica-1", should_fail=True),
        safe_check("pg-replica-2"),
    )

    healthy = [r for r in results if r["success"]]
    failed = [r for r in results if not r["success"]]

    print(f"   Healthy: {len(healthy)}, Failed: {len(failed)}")
    for r in results:
        if r["success"]:
            print(f"   OK    {r['server']}: {r['data']['status']}")
        else:
            print(f"   FAIL  {r['server']}: {r['error']}")

asyncio.run(demo_safe_check())

# ---- Timeouts ----

print("\n4. Timeouts - don't wait forever:")
async def slow_server(name, delay):
    await asyncio.sleep(delay)
    return {"server": name, "status": "healthy"}

async def demo_timeout():
    try:
        # Wait at most 1 second
        result = await asyncio.wait_for(
            slow_server("pg-stuck", 5.0),  # Would take 5 seconds
            timeout=1.0
        )
        print(f"   Result: {result}")
    except asyncio.TimeoutError:
        print(f"   TIMEOUT: pg-stuck did not respond in 1 second")
        print(f"   Marking as unreachable and moving on")

asyncio.run(demo_timeout())

print("""
Error handling rules for async DBA agents:
  1. ALWAYS use return_exceptions=True or wrap tasks individually
  2. Never let one failed server crash the whole health check
  3. Set timeouts on every external call (asyncio.wait_for)
  4. Log errors with context (which server, what error)
  5. Return partial results (4/5 servers healthy is useful info)

DBA parallel:
  - return_exceptions=True = like ON_ERROR_STOP=off in psql scripts
  - Timeouts = like statement_timeout in PostgreSQL
  - Wrapping tasks = like EXCEPTION handling in PL/pgSQL
""")
PYEOF
```

Expected output (yours will differ):
```
Error Handling in Async Code
==================================================

1. Default gather() - one failure cancels all:
   FAILED: Cannot connect to pg-replica-1: Connection refused
   We lost ALL results, not just the failed one!

2. gather(return_exceptions=True) - get all results:
   OK: {'server': 'pg-primary', 'status': 'healthy'}
   FAILED: Cannot connect to pg-replica-1: Connection refused
   OK: {'server': 'pg-replica-2', 'status': 'healthy'}

3. Best pattern - wrap each task individually:
   Healthy: 2, Failed: 1
   OK    pg-primary: healthy
   FAIL  pg-replica-1: Cannot connect to pg-replica-1: Connection refused
   OK    pg-replica-2: healthy

4. Timeouts - don't wait forever:
   TIMEOUT: pg-stuck did not respond in 1 second
   Marking as unreachable and moving on
...
```

---

## Step 7. Practical - async pg_stat_activity monitor

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ASYNC PG_STAT_ACTIVITY MONITOR
#
# Poll multiple databases concurrently, detect anomalies,
# and report findings. This is the async pattern you'll use
# in your DBA agent (BUILD 04).
#
# DBA analogy: like running a monitoring cron job that checks
# pg_stat_activity on every server in your fleet, but doing
# all checks concurrently instead of one at a time.
# ============================================================

import asyncio
import random
import time
from datetime import datetime

print("Async pg_stat_activity Monitor")
print("=" * 50)

# Simulated database fleet
DATABASES = {
    "prod-primary": {"host": "10.0.1.10", "max_conn": 200},
    "prod-replica-1": {"host": "10.0.1.11", "max_conn": 200},
    "prod-replica-2": {"host": "10.0.1.12", "max_conn": 200},
    "staging": {"host": "10.0.2.10", "max_conn": 100},
    "analytics": {"host": "10.0.3.10", "max_conn": 300},
}

# Anomaly thresholds
THRESHOLDS = {
    "connection_percent": 80,       # Alert if > 80% of max_connections used
    "long_query_seconds": 300,      # Alert if query running > 5 minutes
    "idle_in_transaction_seconds": 60,  # Alert if idle in transaction > 1 min
    "waiting_queries": 5,           # Alert if > 5 queries waiting on locks
}

async def poll_pg_stat_activity(db_name, db_config):
    """
    Simulate polling pg_stat_activity on one database.

    In production, this would run:
      SELECT pid, state, query, now() - query_start as duration,
             wait_event_type, wait_event
      FROM pg_stat_activity
      WHERE backend_type = 'client backend';
    """
    # Simulate network latency
    await asyncio.sleep(random.uniform(0.05, 0.2))

    # Simulate pg_stat_activity results
    active_connections = random.randint(5, int(db_config["max_conn"] * 0.9))
    long_queries = random.randint(0, 3)
    idle_in_tx = random.randint(0, 2)
    waiting = random.randint(0, 8)

    # Simulate some query details
    queries = []
    for i in range(min(long_queries, 3)):
        duration = random.uniform(10, 600)
        queries.append({
            "pid": random.randint(10000, 99999),
            "state": "active",
            "duration_seconds": round(duration, 1),
            "query": random.choice([
                "SELECT * FROM large_table WHERE ...",
                "UPDATE orders SET status = ... WHERE ...",
                "DELETE FROM audit_log WHERE created_at < ...",
                "CREATE INDEX CONCURRENTLY ON ...",
            ])[:60],
        })

    return {
        "database": db_name,
        "host": db_config["host"],
        "max_connections": db_config["max_conn"],
        "active_connections": active_connections,
        "connection_percent": round(active_connections / db_config["max_conn"] * 100, 1),
        "long_queries": long_queries,
        "idle_in_transaction": idle_in_tx,
        "waiting_on_locks": waiting,
        "sample_queries": queries,
    }

def detect_anomalies(result):
    """Check a poll result against thresholds."""
    anomalies = []

    if result["connection_percent"] > THRESHOLDS["connection_percent"]:
        anomalies.append({
            "type": "HIGH_CONNECTIONS",
            "severity": "warning" if result["connection_percent"] < 90 else "critical",
            "message": f"{result['connection_percent']}% of max_connections used ({result['active_connections']}/{result['max_connections']})",
        })

    for q in result["sample_queries"]:
        if q["duration_seconds"] > THRESHOLDS["long_query_seconds"]:
            anomalies.append({
                "type": "LONG_QUERY",
                "severity": "warning",
                "message": f"PID {q['pid']} running for {q['duration_seconds']}s: {q['query'][:40]}...",
            })

    if result["idle_in_transaction"] > 0:
        anomalies.append({
            "type": "IDLE_IN_TRANSACTION",
            "severity": "warning",
            "message": f"{result['idle_in_transaction']} connections idle in transaction",
        })

    if result["waiting_on_locks"] > THRESHOLDS["waiting_queries"]:
        anomalies.append({
            "type": "LOCK_CONTENTION",
            "severity": "critical",
            "message": f"{result['waiting_on_locks']} queries waiting on locks",
        })

    return anomalies

async def monitor_cycle():
    """Run one monitoring cycle across all databases."""
    start = time.time()

    # Poll all databases concurrently
    tasks = [
        poll_pg_stat_activity(name, config)
        for name, config in DATABASES.items()
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    elapsed = time.time() - start
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print(f"\n[{timestamp}] Monitoring Cycle Complete ({elapsed:.2f}s)")
    print("-" * 70)

    all_anomalies = []

    for result in results:
        if isinstance(result, Exception):
            print(f"  ERROR: {result}")
            continue

        anomalies = detect_anomalies(result)
        all_anomalies.extend(anomalies)

        status = "OK" if not anomalies else f"!! {len(anomalies)} anomaly(ies)"
        print(f"  {result['database']:<20} conns={result['active_connections']:>3}/{result['max_connections']:<3} "
              f"({result['connection_percent']:>5.1f}%)  long_q={result['long_queries']}  "
              f"idle_tx={result['idle_in_transaction']}  locks={result['waiting_on_locks']}  [{status}]")

    if all_anomalies:
        print(f"\nAnomalies Detected: {len(all_anomalies)}")
        print("-" * 70)
        for a in all_anomalies:
            severity_marker = "CRIT" if a["severity"] == "critical" else "WARN"
            print(f"  [{severity_marker}] {a['type']}: {a['message']}")

    return results, all_anomalies

async def run_monitor(cycles=3, interval=1):
    """Run the monitor for multiple cycles."""
    print(f"Starting async monitor: {len(DATABASES)} databases, {cycles} cycles, {interval}s interval")

    for i in range(cycles):
        results, anomalies = await monitor_cycle()
        if i < cycles - 1:
            await asyncio.sleep(interval)

    print(f"\nMonitor complete. Ran {cycles} cycles.")

# Run 3 monitoring cycles
asyncio.run(run_monitor(cycles=3, interval=0.5))

print("""
This is the foundation for your DBA agent (BUILD 04).
The agent will:
  1. Run this polling loop continuously
  2. Feed anomalies to an LLM for analysis
  3. Let the LLM decide what tools to call
  4. Log all decisions and actions

Key async patterns used:
  - asyncio.gather() for concurrent database polling
  - return_exceptions=True for partial failure tolerance
  - asyncio.sleep() for non-blocking intervals
  - Async functions for all I/O operations
""")
PYEOF
```

Expected output (yours will differ):
```
Starting async monitor: 5 databases, 3 cycles, 1s interval

[2026-06-15 10:30:45] Monitoring Cycle Complete (0.18s)
----------------------------------------------------------------------
  prod-primary         conns= 87/200 ( 43.5%)  long_q=1  idle_tx=0  locks=2  [OK]
  prod-replica-1       conns=156/200 ( 78.0%)  long_q=0  idle_tx=1  locks=1  [!! 1 anomaly(ies)]
  prod-replica-2       conns= 34/200 ( 17.0%)  long_q=2  idle_tx=0  locks=0  [OK]
  staging              conns= 23/100 ( 23.0%)  long_q=0  idle_tx=0  locks=0  [OK]
  analytics            conns=245/300 ( 81.7%)  long_q=1  idle_tx=2  locks=7  [!! 3 anomaly(ies)]

Anomalies Detected: 4
----------------------------------------------------------------------
  [WARN] IDLE_IN_TRANSACTION: 1 connections idle in transaction
  [WARN] HIGH_CONNECTIONS: 81.7% of max_connections used (245/300)
  [WARN] IDLE_IN_TRANSACTION: 2 connections idle in transaction
  [CRIT] LOCK_CONTENTION: 7 queries waiting on locks
...
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| `async def` | Declares a coroutine that can pause | A query that can yield CPU while waiting for I/O |
| `await` | Pauses until result is ready | Waiting for WAL flush or disk read |
| `asyncio.run()` | Starts the event loop | Starting the PostgreSQL postmaster |
| `asyncio.gather()` | Runs coroutines concurrently | Running queries in multiple psql sessions |
| `return_exceptions=True` | Returns errors as results instead of crashing | ON_ERROR_STOP=off in psql |
| `asyncio.wait_for()` | Adds a timeout | `statement_timeout` in PostgreSQL |
| `async with` | Async context manager for cleanup | Connection pooling - auto-release on exit |
| `aiohttp.ClientSession` | HTTP connection pool | PgBouncer for HTTP calls |
