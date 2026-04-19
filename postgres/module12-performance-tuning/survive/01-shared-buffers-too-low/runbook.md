# Scenario 01 - shared_buffers Too Low

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Database is extremely slow.
Every query is slower than expected.
The Pulse cache hit ratio is near 0%.
A junior DBA 'optimized' the server to save memory.
```

---

## Key Concepts for Revision

- **shared_buffers is PostgreSQL's page cache** - When PostgreSQL reads or writes data, it works with 8kB pages in shared_buffers first. If the needed page is already in shared_buffers ("cache hit"), no disk I/O is needed. If not ("cache miss"), PostgreSQL must read from disk, which is 100-1000x slower. At 128kB, shared_buffers holds only 16 pages. Every query on any non-trivial table causes disk reads.

- **The Pulse cache hit ratio metric** - The Pulse Performance panel shows `(heap_blks_hit / (heap_blks_hit + heap_blks_read)) * 100`. A healthy OLTP database should show 99%+. Values below 90% indicate a serious cache problem. Values near 0% mean almost every page access goes to disk.

- **shared_buffers requires a restart** - Unlike most PostgreSQL parameters, `shared_buffers` is allocated from shared memory at startup. Changing it in `postgresql.conf` has no effect until the server restarts. This is why the `context` column in `pg_settings` shows `postmaster` for this parameter.

- **Why 128kB is pathological** - The PostgreSQL minimum for shared_buffers is 128kB, but this is only for development and testing. A working set of even a small table (customers with 200 rows) is larger than 128kB. Every query flushes previous pages out of cache, causing constant disk I/O for all connections.

- **Recommended sizing** - Start at 25% of total RAM. On a 1GB server, 256MB is correct. On a 4GB server, 1GB is a solid baseline. Do not exceed 40% of RAM - the OS page cache and other processes need the rest.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

PostgreSQL is running (it started fine - 128kB is the minimum but not zero).

### Step 2 - Check cache hit ratio from pg_statio

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT
  relname,
  heap_blks_read,
  heap_blks_hit,
  CASE WHEN (heap_blks_read + heap_blks_hit) = 0 THEN NULL
    ELSE round(heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 1)
  END AS cache_hit_pct
FROM pg_statio_user_tables
WHERE schemaname = 'public'
ORDER BY heap_blks_read DESC;
```

Expected output (yours will differ):

```
  relname   | heap_blks_read | heap_blks_hit | cache_hit_pct
------------+----------------+---------------+---------------
 orders     |            450 |             2 |           0.4
 customers  |            200 |             1 |           0.5
 products   |            150 |             1 |           0.7
(3 rows)
```

Cache hit rate near 0% confirms the problem.

### Step 3 - Check the current shared_buffers value

```sql
SHOW shared_buffers;
```

Expected output:

```
 shared_buffers
----------------
 128kB
(1 row)
```

128kB is the smoking gun. This is far too small for any real workload.

```sql
\q
```

### Step 4 - Check postgresql.conf for the chaos injection

```bash
grep shared_buffers /opt/pgsql/data/postgresql.conf
```

Expected output:

```
shared_buffers = 128kB   # chaos injection
```

---

## Resolution

### Step 1 - Calculate the correct value

Total RAM on this server (check with `free -h`):

```bash
exit
```

```bash
free -h
```

Expected output (yours will differ):

```
               total        used        free
Mem:           1.0Gi       400Mi       600Mi
```

25% of 1GB = 256MB. Set shared_buffers to 256MB.

### Step 2 - Edit postgresql.conf

```bash
sudo -iu postgres
```

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the line with `shared_buffers = 128kB` and the chaos comment. Change it to:

```
shared_buffers = 256MB
```

Save and exit (`:wq`).

### Step 3 - Verify the edit

```bash
grep shared_buffers /opt/pgsql/data/postgresql.conf
```

Expected output:

```
shared_buffers = 256MB
```

No chaos comment should remain.

```bash
exit
```

### Step 4 - Restart PostgreSQL (required for shared_buffers)

```bash
sudo systemctl restart postgresql-16
```

### Step 5 - Verify restart succeeded

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

### Step 6 - Confirm the new value

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW shared_buffers;"
```

Expected output:

```
 shared_buffers
----------------
 256MB
(1 row)
```

### Step 7 - Warm the cache and verify hit ratio improves

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT COUNT(*) FROM orders JOIN customers c ON c.id = orders.customer_id JOIN order_items oi ON oi.order_id = orders.id;"
```

Run the cache hit query again to see improvement.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT relname, round(heap_blks_hit::numeric / nullif(heap_blks_read + heap_blks_hit,0) * 100,1) AS hit_pct FROM pg_statio_user_tables WHERE schemaname='public' ORDER BY hit_pct DESC;"
```

Expected output (yours will differ):

```
  relname   | hit_pct
------------+---------
 products   |    99.2
 customers  |    98.8
 orders     |    97.5
(3 rows)
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
- PostgreSQL accepts connections
- shared_buffers is at least 64MB
- Chaos injection comment removed from postgresql.conf
- Query against stepup_store works

---

## Interview Discussion Points

1. **Why does shared_buffers require a restart while work_mem does not?** - `shared_buffers` is allocated from the kernel's shared memory at server startup. All PostgreSQL processes attach to this fixed shared memory segment. Changing its size requires recreating the segment, which means stopping all processes and restarting. `work_mem` is per-operation private memory allocated by each backend process on demand. It does not require shared memory and can be changed with a reload or even per-session with `SET`.

2. **How would you identify this problem in a production system with no access to EXPLAIN?** - Check `pg_statio_user_tables` for `heap_blks_read` vs `heap_blks_hit`. Check `pg_stat_bgwriter` for high `buffers_alloc` relative to `buffers_checkpoint + buffers_clean` (lots of buffer allocation means lots of cache eviction). The Pulse dashboard cache hit ratio is also an instant signal.

3. **Is there such a thing as shared_buffers being too high?** - Yes. If `shared_buffers` exceeds 40-50% of RAM, the OS page cache is starved. PostgreSQL relies on the OS page cache for WAL writes, temporary file I/O, and data files outside shared_buffers. Starving the OS cache can cause erratic I/O latency across the whole system. Also, very large shared_buffers segments cause slower checkpoint operations.

4. **What happens to shared_buffers content on a PostgreSQL restart?** - It is completely discarded. Shared memory is zeroed on restart. After a restart, the server starts "cold" with an empty cache. The first queries after restart will show higher latency as pages are loaded from disk. This "cache warming" period can take minutes to hours on large databases. Some teams warm the cache deliberately using `pg_prewarm` after planned restarts.

5. **Walk through the decision between shared_buffers and effective_cache_size.** - `shared_buffers` is real memory allocation - it actually reserves RAM. `effective_cache_size` is a planner hint that does not allocate any memory. The planner uses `effective_cache_size` to estimate whether an index scan will find its pages cached (making it cheap) or have to read from disk (making it expensive). A correct `effective_cache_size` leads to better plan choices. It should be set to `shared_buffers + available OS page cache` (roughly `total_RAM - shared_buffers`).
