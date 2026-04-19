# Scenario 08 - effective_cache_size Wrong

**Severity:** MEDIUM
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Query plans have changed since a config review.
The planner is choosing sequential scans over index
scans on medium-sized tables, even when indexes exist.
The planner cost estimates seem to overestimate random I/O costs.
```

---

## Key Concepts for Revision

- **effective_cache_size is a planner hint, not memory allocation** - Unlike `shared_buffers` which actually reserves memory, `effective_cache_size` does not allocate anything. It tells the planner how much memory is available for caching data pages across both PostgreSQL's shared_buffers and the OS page cache. The planner uses this to estimate the probability that a random page read will find the page already cached.

- **How it affects plan choices** - When `effective_cache_size` is low, the planner assumes most random page reads will hit disk. This makes index scans (which do random reads) look expensive relative to sequential scans (which do sequential reads). The planner then favors sequential scans even when an index scan would be faster in practice (because the OS cache likely has the pages).

- **Recommended setting** - Set `effective_cache_size` to approximately 50-75% of total RAM. On a 1GB server: `512MB - 768MB`. The reasoning: shared_buffers uses ~25% of RAM, and the OS will use most of the remaining RAM for its page cache. Together, these form the "effective" cache.

- **No restart needed** - `effective_cache_size` is a `user` context parameter. Changes take effect immediately after `SELECT pg_reload_conf()` or even per-session with `SET`. No restart required.

- **Does not affect actual caching behavior** - Setting `effective_cache_size` higher does not make PostgreSQL cache more data. It only changes the planner's cost estimates. If you set it to 100GB on a 1GB server, the planner will think every page is cached and prefer index scans - which may not match reality, causing plans that are slower than expected.

---

## Diagnostic Steps

### Step 1 - Check current effective_cache_size

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SHOW effective_cache_size;
```

Expected output:

```
 effective_cache_size
----------------------
 32MB
(1 row)
```

32MB is extremely low for any server.

### Step 2 - Check total RAM on the server

```sql
\q
```

```bash
exit
```

```bash
free -m
```

Expected output (yours will differ):

```
               total        used        free
Mem:            1006         350         200
...
```

The server has ~1GB RAM. 32MB effective_cache_size tells the planner that virtually nothing is cached, which is wrong.

### Step 3 - Check the planner cost estimates

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 1;
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..250.00 rows=5 width=...)
   Filter: (customer_id = 1)
```

The planner chooses Seq Scan because it estimates random I/O (index scan) is too expensive relative to sequential I/O. With a correct `effective_cache_size`, the planner would know most pages are likely cached and prefer an index scan.

### Step 4 - Check where the setting was changed

```sql
\q
```

```bash
grep effective_cache_size /opt/pgsql/data/postgresql.auto.conf
```

Expected output:

```
effective_cache_size = '32MB'
```

---

## Resolution

### Step 1 - Calculate the correct effective_cache_size

Use 50-75% of total RAM. For a 1GB server:

- shared_buffers = 256MB (25% of RAM)
- OS page cache = ~500MB (most of the remaining RAM)
- effective_cache_size = 256MB + 500MB = ~768MB

A conservative value of 512MB is also acceptable.

### Step 2 - Set the correct value

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM SET effective_cache_size = '512MB';
```

Expected output:

```
ALTER SYSTEM
```

### Step 3 - Reload configuration

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 4 - Verify the new value

```sql
SHOW effective_cache_size;
```

Expected output:

```
 effective_cache_size
----------------------
 512MB
(1 row)
```

### Step 5 - Check that the planner now favors index scans

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 1;
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Index Scan using idx_orders_customer_id on orders  (cost=...)
   Index Cond: (customer_id = 1)
```

The planner now uses an Index Scan because it correctly estimates that index pages are likely cached.

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- effective_cache_size is at least 128MB
- effective_cache_size does not exceed total RAM
- Setting is reasonable relative to server memory

---

## Interview Discussion Points

1. **What happens if you set effective_cache_size too high?** - The planner overestimates cache hits and always prefers index scans, even when the data is not cached. On a cold system (after restart) or for tables larger than available cache, this leads to excessive random I/O. The plans look good on paper but perform poorly because every "cached" page actually hits disk. This is less common in practice because servers usually have enough RAM.

2. **How is effective_cache_size different from shared_buffers?** - `shared_buffers` is real memory allocation - PostgreSQL reserves that RAM at startup. `effective_cache_size` is purely informational. It tells the planner about total available cache (shared_buffers + OS page cache). You can change `effective_cache_size` without any memory impact. Changing `shared_buffers` requires a restart and actually changes memory usage.

3. **Should effective_cache_size include shared_buffers?** - Yes. The effective cache is everything: shared_buffers (which PostgreSQL manages) plus the OS page cache (which the kernel manages). A random page read might find the data in either cache. The planner does not distinguish between the two - it just needs to know the total probability of a cache hit.

4. **How do you verify the actual cache hit ratio to validate your setting?** - Query `pg_statio_user_tables` for `heap_blks_hit` vs `heap_blks_read`. If the cache hit ratio is 99%+ and `effective_cache_size` is set conservatively, you could increase it. If the cache hit ratio is low (below 90%), your `effective_cache_size` might be too high relative to actual cache effectiveness.

5. **Does effective_cache_size affect anything besides query plans?** - No. It is solely a planner input. It does not change memory allocation, buffer management, or any runtime behavior. Its only effect is on the cost estimates the planner uses to compare sequential scan vs index scan vs bitmap scan. This makes it one of the safest settings to tune - a wrong value causes suboptimal plans but never causes crashes or data loss.
