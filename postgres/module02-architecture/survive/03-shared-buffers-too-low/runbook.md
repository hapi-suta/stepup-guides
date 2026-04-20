# Scenario 03 - shared_buffers Too Low

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes (requires restart)
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Database performance severely degraded.
Cache hit ratio dropped below expected levels.
Applications reporting slow queries.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **shared_buffers** - PostgreSQL's own buffer cache in shared memory. This is where frequently accessed data pages are cached to avoid disk reads. Unlike the OS page cache, PostgreSQL manages this directly and can use it for features like buffer pinning and dirty page tracking.
- **Cache hit ratio** - The percentage of page reads served from shared_buffers vs reading from disk. A healthy OLTP system should see 95-99%+ cache hit ratio. Below 90% usually indicates shared_buffers is too small or the working set vastly exceeds available memory.
- **pg_stat_database** - System view that tracks database-wide statistics including blks_read (pages read from disk) and blks_hit (pages served from shared_buffers). The ratio blks_hit / (blks_hit + blks_read) gives you the cache hit ratio.
- **Sizing shared_buffers** - General rule: set to 25% of total system RAM for dedicated database servers. Minimum 128MB for any real workload. Maximum practical benefit is usually around 8-16GB because the OS page cache handles the rest.
- **Why restart is required** - shared_buffers allocates shared memory segments at startup. Changing it requires reallocating shared memory, which means all backends must be stopped. A reload is not sufficient - you must restart.

---

## Diagnostic Steps

### Step 1 - Check the current cache hit ratio

```sql
SELECT datname,
       blks_read,
       blks_hit,
       ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 1) AS cache_hit_pct
FROM pg_stat_database
WHERE datname = 'labdb';
```

Expected output (yours will differ):

```
 datname | blks_read | blks_hit | cache_hit_pct
---------+-----------+----------+---------------
 labdb   |     48210 |    12054 |          20.0
(1 row)
```

A cache_hit_pct of 20% or lower confirms the problem. A healthy system shows 95%+. If you see below 90%, shared_buffers is likely too small.

### Step 2 - Check current shared_buffers setting

```sql
SHOW shared_buffers;
```

Expected output:

```
 shared_buffers
----------------
 1MB
(1 row)
```

If this shows 1MB or something absurdly low, that is your problem.

### Step 3 - Check total system RAM for context

```bash
free -m
```

shared_buffers should be roughly 25% of total RAM on a dedicated database server.

### Step 4 - Use pg_buffercache to see buffer usage

```sql
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
SELECT count(*) AS total_buffers,
       count(*) FILTER (WHERE relfilenode IS NOT NULL) AS used_buffers,
       pg_size_pretty(count(*) * 8192::bigint) AS total_size
FROM pg_buffercache;
```

With 1MB of shared_buffers, you will see very few total buffers - confirming the problem.

---

## Resolution

### Step 1 - Set shared_buffers to a reasonable value

Check total RAM first, then set to about 25% of it. For a lab server with 1-2GB RAM, 128MB is a reasonable minimum.

```sql
ALTER SYSTEM SET shared_buffers = '128MB';
```

### Step 2 - Restart PostgreSQL

A reload is NOT enough for shared_buffers. You must restart.

```bash
sudo systemctl restart postgresql-16
```

### Step 3 - Verify the new setting

```sql
SHOW shared_buffers;
```

Expected output:

```
 shared_buffers
----------------
 128MB
(1 row)
```

### Step 4 - Warm up the cache and check hit ratio

Run some queries to populate the buffer cache, then check the ratio.

```sql
SELECT count(*) FROM chaos_workload;
SELECT count(*) FROM chaos_workload WHERE payload LIKE '%x%';

-- Check ratio after warmup
SELECT datname,
       ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 1) AS cache_hit_pct
FROM pg_stat_database
WHERE datname = 'labdb';
```

Expected output (yours will differ):

```
 datname | cache_hit_pct
---------+---------------
 labdb   |          87.3
(1 row)
```

The ratio should be noticeably higher than before. It may not reach 95%+ immediately - that takes sustained workload with adequate buffers.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- shared_buffers is at least 32MB
- Cache hit ratio recovers above 50% after warmup
- State file cleaned up

---

## Interview Discussion Points

1. **How do you size shared_buffers?** - Start at 25% of total system RAM for a dedicated PostgreSQL server. On shared servers, go lower (10-15%). Never set it higher than 40% of RAM because the OS page cache also needs memory. For systems with very large datasets (hundreds of GB), diminishing returns kick in around 8-16GB and the OS page cache becomes more important.

2. **What is the relationship between shared_buffers and the OS page cache?** - PostgreSQL reads data through the OS. Even when a page is not in shared_buffers, it may be in the OS page cache (avoiding actual disk I/O). This is why PostgreSQL works reasonably well even with modest shared_buffers - the OS provides a second layer of caching. However, shared_buffers is still important because PostgreSQL can manage it more intelligently (clock-sweep eviction, pin counts, dirty page tracking).

3. **Why does shared_buffers require a restart while most other settings just need a reload?** - shared_buffers determines the size of the shared memory segment allocated at postmaster startup. Changing it means the shared memory region must be resized, which requires all backends to detach from the old segment. This is a fundamental architectural constraint - you cannot resize a live shared memory segment that hundreds of processes are actively using.

4. **What tools help diagnose buffer cache issues?** - pg_buffercache extension shows exactly what is in the buffer cache (which relations, how many pages, usage count). pg_stat_database shows the overall hit ratio. pg_stat_user_tables shows per-table sequential vs index scans. EXPLAIN (ANALYZE, BUFFERS) shows buffer hits vs reads for individual queries.

5. **What is the difference between shared_buffers and effective_cache_size?** - shared_buffers is a real allocation of shared memory. effective_cache_size is just a hint to the query planner about how much total cache (shared_buffers + OS page cache) is available. It affects cost estimates for index scans vs sequential scans but does not allocate any memory. Setting it wrong does not cause crashes - just suboptimal query plans.
