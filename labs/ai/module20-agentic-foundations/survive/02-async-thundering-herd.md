# Survive 02: Async Thundering Herd - Connection Exhaustion

Your async health checker fires 500 concurrent connections to PostgreSQL during a monitoring sweep, exhausting max_connections. The monitoring system that's supposed to detect problems just became the problem.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'

print("""
SCENARIO: Async Thundering Herd

Timeline:
  03:00  Async DBA agent starts monitoring sweep
  03:00  Agent launches health checks for 500 databases concurrently
  03:00  Each check opens a new PostgreSQL connection
  03:00  pg-primary: max_connections = 200, suddenly 500 connections attempted
  03:01  FATAL: too many connections for role "monitor"
  03:01  Application connections start failing too
  03:01  PgBouncer queue fills up, apps get timeouts
  03:02  Cascading failure: replicas also hit max_connections
  03:03  All monitoring checks fail (the checker can't connect either)
  03:05  On-call DBA paged: "All databases unreachable"
  03:07  Root cause identified: it was our own monitoring tool

The irony: the system designed to monitor database health
caused a database health crisis.
""")

print("What happened under the hood:")
print("=" * 55)

# Show the broken async code
print("""
BROKEN CODE (the thundering herd):

  async def check_all_databases():
      # THIS IS THE BUG: 500 concurrent connections
      tasks = []
      for db in ALL_500_DATABASES:
          tasks.append(check_database(db))  # Each opens a connection

      # All 500 fire at once!
      results = await asyncio.gather(*tasks)

  async def check_database(db_config):
      # Opens a NEW connection for each check
      conn = await asyncpg.connect(
          host=db_config["host"],
          port=5432,
          user="monitor",
          password="...",
          database=db_config["name"],
      )
      result = await conn.fetchval("SELECT 1")
      await conn.close()
      return result

The problem: asyncio.gather() with 500 tasks opens 500
connections simultaneously. PostgreSQL only allows 200.
300 connections get FATAL errors, and the existing 150
application connections start competing for the remaining 50.
""")

print("Connection timeline:")
print("-" * 55)

timeline = [
    ("03:00:00.000", "Monitor starts", "0/200 connections"),
    ("03:00:00.001", "50 check tasks start", "50/200"),
    ("03:00:00.005", "150 check tasks start", "150/200 (apps have 50)"),
    ("03:00:00.010", "200 check tasks start", "200/200 MAX HIT"),
    ("03:00:00.015", "300 more tasks try", "FATAL: too many connections x300"),
    ("03:00:00.020", "App connections rejected", "Apps can't connect either"),
    ("03:00:01.000", "Replicas hit too", "Thundering herd spreads"),
    ("03:00:05.000", "Everything down", "Total connection exhaustion"),
]

for time_str, event, conns in timeline:
    print(f"  [{time_str}] {event:<35} [{conns}]")

print("""
Impact:
  - All applications lost database connectivity for 5 minutes
  - 500 monitoring checks failed (defeating the purpose)
  - Cascading failures across replicas
  - Revenue loss during the outage
  - Trust in the monitoring system destroyed

Root cause: unbounded concurrency in async code.
asyncio.gather() is too powerful without limits.
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'

print("Investigation: Why Did Async Monitoring Crash the Database?")
print("=" * 55)

print("""
Root Cause: Unbounded Concurrency

asyncio.gather(*500_tasks) runs ALL tasks concurrently.
There's no built-in limit. If each task opens a connection,
you get 500 simultaneous connections.

PostgreSQL has max_connections = 200 (typical default).
You just tried to open 2.5x the maximum.

Contributing Factors:

  1. No connection pooling
     Each check_database() call opened a NEW connection.
     Should have used a connection pool with a fixed size.

  2. No concurrency limit (semaphore)
     asyncio.gather() ran all 500 tasks at once.
     Should have limited to 10-20 concurrent tasks.

  3. No backpressure
     When connections start failing, the code kept trying.
     Should have detected failures and slowed down.

  4. Single-threaded event loop, multi-target blast
     The async code was efficient at ONE thing: opening
     connections as fast as possible. Too efficient.

DBA analogy: like running 500 pgbench clients against a
server configured for 200 connections. The benchmark tool
overwhelms the database it's testing.
""")

print("The three fixes:")
print("-" * 55)
print("""
Fix 1: Connection Pool (limit total connections)
  Use a pool of 10-20 connections, reuse them.
  Never open more than the pool size.

Fix 2: Semaphore (limit concurrent tasks)
  asyncio.Semaphore(20) - max 20 tasks run at once.
  The rest wait their turn.

Fix 3: Batching (process in groups)
  Check 20 databases, wait, check next 20.
  Controlled, predictable load.
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'

# ============================================================
# FIX: Bounded Concurrency for Async Database Monitoring
#
# Three techniques to prevent the thundering herd:
#   1. asyncio.Semaphore - limit concurrent tasks
#   2. Connection pooling - limit total connections
#   3. Batching - process in controlled groups
# ============================================================

import asyncio
import random
import time

print("FIX: Bounded Concurrency")
print("=" * 55)

# Simulated databases (50 to show the pattern, scale to 500)
DATABASES = [f"db-{i:03d}" for i in range(50)]

async def check_database_simulated(db_name, connection_tracker):
    """
    Simulate a database health check.
    Tracks concurrent connections to show the difference.
    """
    # Track concurrent connections
    connection_tracker["current"] += 1
    connection_tracker["peak"] = max(connection_tracker["peak"], connection_tracker["current"])

    # Simulate connection + query time
    await asyncio.sleep(random.uniform(0.05, 0.15))

    result = {"database": db_name, "status": "healthy", "connections": random.randint(10, 100)}

    connection_tracker["current"] -= 1
    connection_tracker["completed"] += 1
    return result


# ---- BROKEN: Unbounded gather() ----

print("\n1. BROKEN: Unbounded asyncio.gather() (thundering herd)")
print("-" * 55)

async def check_all_unbounded():
    tracker = {"current": 0, "peak": 0, "completed": 0}
    start = time.time()

    tasks = [check_database_simulated(db, tracker) for db in DATABASES]
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start
    print(f"  Databases checked: {tracker['completed']}")
    print(f"  Peak concurrent connections: {tracker['peak']}")
    print(f"  Time: {elapsed:.2f}s")
    print(f"  PROBLEM: {tracker['peak']} connections hit the database at once!")
    if tracker["peak"] > 20:
        print(f"  With 500 databases, peak would be ~500 connections!")

asyncio.run(check_all_unbounded())


# ---- FIX 1: Semaphore ----

print(f"\n2. FIX: asyncio.Semaphore (limit concurrent tasks)")
print("-" * 55)

async def check_all_with_semaphore(max_concurrent=10):
    """
    Use a semaphore to limit concurrent connections.

    asyncio.Semaphore(10) = at most 10 tasks run at once.
    The rest wait for a slot to open.

    DBA analogy: like PgBouncer's pool_size setting.
    You configure the maximum, and excess connections wait.
    """
    semaphore = asyncio.Semaphore(max_concurrent)
    tracker = {"current": 0, "peak": 0, "completed": 0}
    start = time.time()

    async def limited_check(db_name):
        async with semaphore:  # Wait for a slot
            return await check_database_simulated(db_name, tracker)

    tasks = [limited_check(db) for db in DATABASES]
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start
    print(f"  Max concurrent: {max_concurrent}")
    print(f"  Databases checked: {tracker['completed']}")
    print(f"  Peak concurrent connections: {tracker['peak']}")
    print(f"  Time: {elapsed:.2f}s")
    print(f"  SAFE: never exceeded {max_concurrent} concurrent connections")

asyncio.run(check_all_with_semaphore(max_concurrent=10))


# ---- FIX 2: Batching ----

print(f"\n3. FIX: Batch processing (controlled groups)")
print("-" * 55)

async def check_all_batched(batch_size=10):
    """
    Process databases in batches.

    Check 10 at a time, wait for all 10 to finish,
    then start the next 10.

    DBA analogy: like running pg_dump on 10 databases at a time.
    Finish the batch, start the next one. Predictable load.
    """
    tracker = {"current": 0, "peak": 0, "completed": 0}
    start = time.time()
    all_results = []

    for i in range(0, len(DATABASES), batch_size):
        batch = DATABASES[i:i + batch_size]
        tasks = [check_database_simulated(db, tracker) for db in batch]
        results = await asyncio.gather(*tasks)
        all_results.extend(results)

    elapsed = time.time() - start
    print(f"  Batch size: {batch_size}")
    print(f"  Databases checked: {tracker['completed']}")
    print(f"  Peak concurrent connections: {tracker['peak']}")
    print(f"  Time: {elapsed:.2f}s")
    print(f"  SAFE: processed in controlled batches of {batch_size}")

asyncio.run(check_all_batched(batch_size=10))


# ---- FIX 3: Connection Pool ----

print(f"\n4. FIX: Connection pool (reuse connections)")
print("-" * 55)

class SimpleConnectionPool:
    """
    Simulated connection pool.

    In production, use asyncpg.create_pool(min_size=5, max_size=20).
    The pool manages connections and never opens more than max_size.

    DBA analogy: this IS PgBouncer. A fixed number of connections
    shared among all tasks. Tasks wait for a free connection.
    """

    def __init__(self, max_size=10):
        self.max_size = max_size
        self.semaphore = asyncio.Semaphore(max_size)
        self.connections_created = 0
        self.peak_in_use = 0
        self.current_in_use = 0

    async def acquire(self):
        await self.semaphore.acquire()
        self.current_in_use += 1
        self.peak_in_use = max(self.peak_in_use, self.current_in_use)
        if self.connections_created < self.max_size:
            self.connections_created += 1
        return f"conn-{self.current_in_use}"

    def release(self):
        self.current_in_use -= 1
        self.semaphore.release()


async def check_with_pool():
    pool = SimpleConnectionPool(max_size=10)
    tracker = {"current": 0, "peak": 0, "completed": 0}
    start = time.time()

    async def pooled_check(db_name):
        conn = await pool.acquire()
        try:
            result = await check_database_simulated(db_name, tracker)
            return result
        finally:
            pool.release()

    tasks = [pooled_check(db) for db in DATABASES]
    results = await asyncio.gather(*tasks)

    elapsed = time.time() - start
    print(f"  Pool size: {pool.max_size}")
    print(f"  Connections created: {pool.connections_created}")
    print(f"  Peak connections in use: {pool.peak_in_use}")
    print(f"  Databases checked: {tracker['completed']}")
    print(f"  Time: {elapsed:.2f}s")
    print(f"  SAFE: reused {pool.max_size} connections for {len(DATABASES)} databases")

asyncio.run(check_with_pool())


# ---- Summary ----

print(f"""
Comparison:
  {'Method':<25} {'Peak Connections':<20} {'Risk'}
  {'-'*65}
  Unbounded gather()       ~50 (500 at scale)    DANGEROUS - exceeds max_connections
  Semaphore(10)            10                     SAFE - bounded concurrency
  Batch(10)                10                     SAFE - controlled groups
  Pool(10)                 10                     SAFE - connection reuse

Production recommendation:
  Use Semaphore + Pool together.
  - Pool limits total connections (like PgBouncer)
  - Semaphore limits concurrent tasks (like a job queue)

  pool = asyncpg.create_pool(min_size=5, max_size=20, ...)
  semaphore = asyncio.Semaphore(20)

  async with semaphore:
      async with pool.acquire() as conn:
          result = await conn.fetchval("SELECT 1")

Prevention checklist:
  1. NEVER use unbounded asyncio.gather() for database connections
  2. Always use a connection pool with a fixed max_size
  3. Add a semaphore to limit concurrent tasks
  4. Monitor your monitoring tool's connection usage
  5. Set max_connections on the monitoring role:
     ALTER ROLE monitor CONNECTION LIMIT 20;

DBA analogy:
  Semaphore = PgBouncer pool_size (limits concurrent connections)
  Batching = pg_dump --jobs=4 (controlled parallelism)
  Pool = PgBouncer itself (connection reuse)
  CONNECTION LIMIT = per-role max connections (database-side safety)
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Unbounded asyncio.gather() | Opens hundreds of connections at once | Use asyncio.Semaphore to cap concurrency |
| No connection pooling | Each task opens a new connection | Use asyncpg.create_pool or connection pool |
| No backpressure | Failed connections don't slow down new attempts | Detect failures and reduce concurrency |
| Monitoring overloads database | The checker becomes the problem | Limit monitoring connections with CONNECTION LIMIT |
| No testing under load | Worked fine with 10 databases, fails at 500 | Load test your monitoring tools at production scale |
