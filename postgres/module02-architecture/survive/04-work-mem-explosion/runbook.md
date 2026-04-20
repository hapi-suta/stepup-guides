# Scenario 04 - work_mem Explosion

**Severity:** CRITICAL
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: System memory critically low.
OOM killer may activate.
15 sessions consuming excessive memory.
work_mem set to 2GB - each sort operation uses up to 2GB.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **work_mem** - Memory allocated per sort or hash operation (not per connection, not per query). A single complex query with multiple sorts and hash joins can use multiple chunks of work_mem simultaneously. Default is 4MB.
- **Per-operation, not per-connection** - This is the most commonly misunderstood aspect. If work_mem is 2GB and a query has 3 sort nodes, that query alone can consume 6GB. Multiply by 15 concurrent sessions and you need 90GB - far more than most servers have.
- **OOM killer** - When Linux runs out of memory, the kernel's Out-Of-Memory killer picks a process to terminate. PostgreSQL backends are often targeted because they are large memory consumers. When one backend is OOM-killed, PostgreSQL restarts all backends to protect shared memory integrity.
- **Sort methods** - EXPLAIN ANALYZE shows "Sort Method: quicksort Memory: XXkB" when the sort fits in work_mem, or "Sort Method: external merge Disk: XXkB" when it spills to temp files. Spilling to disk is slower but safe. In-memory is faster but dangerous with excessive work_mem.
- **temp files** - When work_mem is too small, sorts and hashes spill to temporary files in the pgsql_tmp directory. This uses disk I/O but protects the system from memory exhaustion. A small amount of temp file usage is normal and healthy.

---

## Diagnostic Steps

### Step 1 - Check system memory

```bash
free -m
```

Look at the "available" column. If it is very low (under 100MB), the system is under memory pressure.

### Step 2 - Check current work_mem

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 2GB
(1 row)
```

If this shows 2GB, that is the root cause. 2GB per sort operation with multiple concurrent sessions will exhaust any reasonably-sized server.

### Step 3 - Calculate the risk

```sql
SELECT count(*) AS active_sessions,
       current_setting('work_mem') AS work_mem_per_op
FROM pg_stat_activity
WHERE state = 'active';
```

Expected output (yours will differ):

```
 active_sessions | work_mem_per_op
-----------------+-----------------
              16 | 2GB
(1 row)
```

15 sessions x 2GB work_mem = 30GB theoretical maximum per sort node. Most lab servers have 1-2GB total RAM.

### Step 4 - Identify the runaway sessions

```sql
SELECT pid, state, query, backend_start
FROM pg_stat_activity
WHERE state = 'active'
  AND query LIKE '%chaos_sort_data%'
ORDER BY backend_start;
```

---

## Resolution

### Step 1 - Terminate the runaway sort sessions immediately

This is the priority - stop the memory bleeding before fixing the config.

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE query LIKE '%chaos_sort_data%'
  AND pid != pg_backend_pid();
```

Expected output (yours will differ):

```
 pg_terminate_backend
----------------------
 t
 t
 t
...
```

Each `t` (true) means one session was successfully terminated.

### Step 2 - Also kill any pg_sleep sessions left behind

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE query LIKE '%pg_sleep%'
  AND pid != pg_backend_pid();
```

### Step 3 - Fix work_mem to a safe value

```sql
ALTER SYSTEM SET work_mem = '4MB';
SELECT pg_reload_conf();
```

4MB is the default and safe for most workloads. Adjust upward only after testing.

### Step 4 - Verify the change took effect

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 4MB
(1 row)
```

### Step 5 - Verify memory recovered

```bash
free -m
```

Expected output (yours will differ):

```
               total        used        free      shared  buff/cache   available
Mem:            1837         312         841          24         683        1374
Swap:              0           0           0
```

The "available" column should now be well above 100MB. Compare this to the near-zero value you saw in Step 1.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- work_mem is 256MB or less
- No runaway sort sessions remain
- System has reasonable free memory
- State file cleaned up

---

## Interview Discussion Points

1. **Why is work_mem per-operation and not per-connection?** - PostgreSQL allocates work_mem each time it needs to perform a sort, hash, or bitmap heap operation. A single query with a complex execution plan might have 5-10 such operations running simultaneously. This design allows PostgreSQL to limit each individual operation rather than giving a flat budget to each connection. The downside is that the total memory usage can be much higher than (connections x work_mem).

2. **How do you determine the right work_mem setting?** - Start with the default 4MB. Use EXPLAIN (ANALYZE, BUFFERS) on your most important queries. If you see "Sort Method: external merge Disk" on queries that matter, try increasing work_mem at the session level (SET work_mem = '64MB') and re-run. Check the temp file usage in pg_stat_database (temp_files, temp_bytes). A formula some DBAs use: available_RAM / max_connections / expected_sorts_per_query - but always test, never just calculate.

3. **What does EXPLAIN ANALYZE show for sorts?** - It shows the sort method (quicksort = in-memory, external merge = disk-based), the memory or disk usage, and the number of rows. Example: "Sort Method: quicksort Memory: 25kB" means it fit comfortably. "Sort Method: external merge Disk: 15232kB" means it spilled 15MB to temp files.

4. **What happens when the OOM killer hits a PostgreSQL backend?** - The postmaster detects the lost child process and initiates a "smart restart" of all remaining backends. All active transactions in all sessions are aborted. The shared memory is reinitialized. Clients see connection resets and must reconnect. If the OOM condition persists, the cycle repeats - this is why it is critical to fix work_mem rather than just restarting.

5. **When would you set work_mem higher at the session level?** - For ETL jobs, reporting queries, or batch processing that runs during off-peak hours with few concurrent sessions. Use SET work_mem = '256MB' at the session level rather than changing the global setting. This gives the batch job the memory it needs without affecting all other connections.
