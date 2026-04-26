# Guide 03 - Memory Tuning

Understand the five memory parameters that most affect query performance, how to inspect what is in shared buffers, and how to watch Pulse update as you change settings.

**Server:** NODE1 only

---

## What You Will Learn

- What shared_buffers, work_mem, maintenance_work_mem, effective_cache_size, and temp_buffers do
- How each parameter affects query performance
- How to use pg_buffercache to see what is cached in shared_buffers
- How to change parameters and reload/restart appropriately

---

## 1. Connect to the Server

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Switch to postgres.

```
sudo -iu postgres
```

Check current memory settings.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT name, setting, unit, context FROM pg_settings WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size','temp_buffers') ORDER BY name;"
```

Expected output (yours will differ):

```
         name          | setting | unit |  context
-----------------------+---------+------+-----------
 effective_cache_size  | 524288  | 8kB  | user
 maintenance_work_mem  | 65536   | kB   | user
 shared_buffers        | 16384   | 8kB  | postmaster
 temp_buffers          | 1024    | 8kB  | user
 work_mem              | 4096    | kB   | user
(5 rows)
```

The `context` column tells you whether a restart (`postmaster`) or reload (`sighup`/`user`) is needed.

---

## 2. shared_buffers - PostgreSQL's Main Cache

`shared_buffers` is the memory PostgreSQL uses as its internal page cache. All backend processes share this pool. It is the single most important memory parameter.

Check the current value in human-readable form.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW shared_buffers;"
```

Expected output (yours will differ):

```
 shared_buffers
----------------
 128MB
(1 row)
```

> **Concept - shared_buffers Sizing**: The traditional rule is 25% of total RAM. On a dedicated 4GB server, that is 1GB. Going higher than 40% is usually counterproductive because the OS page cache also helps, and PostgreSQL relies on it for I/O outside shared_buffers. On cloud instances with limited RAM (1-2GB), 256-512MB is a good starting point.

`shared_buffers` requires a **restart** to change (context: `postmaster`). You cannot change it with a reload.

Change shared_buffers to 256MB using ALTER SYSTEM. This writes the setting to `postgresql.auto.conf`, which overrides `postgresql.conf` on the next restart.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET shared_buffers = '256MB';"
```

Expected output:

```
ALTER SYSTEM
```

Restart PostgreSQL to apply the change.

```
exit
```

```
sudo systemctl restart postgresql-16
```

Expected output (no output means success). If you see an error, wait a few seconds and try again.

Verify the new value.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW shared_buffers;"
```

Expected output:

```
 shared_buffers
----------------
 256MB
(1 row)
```

---

## 3. work_mem - Memory Per Sort or Hash Operation

`work_mem` controls how much memory each sort, hash join, or hash aggregate operation can use **before it spills to disk**. This is per-operation, not per-query - a complex query with multiple sorts uses multiple work_mem allocations.

Check the current value.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW work_mem;"
```

Expected output:

```
 work_mem
----------
 4MB
(1 row)
```

Run a query that requires a sort and check for temp file spills.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders ORDER BY total_amount DESC;"
```

Expected output (yours will differ):

```
                                                   QUERY PLAN
-----------------------------------------------------------------------------------------------------------------
 Sort  (cost=4870.41..4995.41 rows=50000 width=43) (actual time=29.281..35.712 rows=50000 loops=1)
   Sort Key: total_amount DESC
   Sort Method: external merge  Disk: 2752kB
   Buffers: shared hit=471, temp read=344 written=345
   ->  Seq Scan on orders  (cost=0.00..968.00 rows=50000 width=43) (actual time=0.003..3.440 rows=50000 loops=1)
         Buffers: shared hit=468
 Planning Time: 0.092 ms
 Execution Time: 37.950 ms
(10 rows)
```

`Sort Method: external merge Disk: 2752kB` - the sort **spilled to disk** because 50,000 rows exceeded the 4MB work_mem budget. The `temp read=344 written=345` confirms disk I/O happened. If this were `Sort Method: quicksort Memory: 30kB`, it would mean the sort fit entirely in memory.

> **Concept - work_mem Multiplication Risk**: If you set `work_mem = 256MB` and have 100 concurrent connections, each running a query with 3 sort operations, the theoretical memory use is 100 x 3 x 256MB = 76GB. This can OOM-kill the server. Set work_mem conservatively at the server level (4MB-16MB) and raise it per-session for specific heavy queries with `SET work_mem = '256MB';`.

Increase work_mem for the current session only to test.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SET work_mem = '64MB';
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 64MB
(1 row)
```

This change only affects the current session.

```
\q
```

Change the server-level work_mem via ALTER SYSTEM (does not require restart).

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET work_mem = '8MB';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Verify the new value.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW work_mem;"
```

Expected output:

```
 work_mem
----------
 8MB
(1 row)
```

---

## 4. maintenance_work_mem - Memory for Maintenance Operations

`maintenance_work_mem` controls memory for VACUUM, CREATE INDEX, ALTER TABLE ADD FOREIGN KEY, and CLUSTER. It does not affect regular queries.

Check the current value.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW maintenance_work_mem;"
```

Expected output:

```
 maintenance_work_mem
----------------------
 64MB
(1 row)
```

This is the memory budget for VACUUM's dead tuple collection and for sorting during index creation. Raising it to 256MB or more can speed up index builds on large tables significantly.

Set it higher for faster maintenance operations.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET maintenance_work_mem = '128MB';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

> **Concept - maintenance_work_mem vs work_mem**: Only one maintenance operation runs per autovacuum worker, so `maintenance_work_mem` does not multiply the way `work_mem` does. You can safely set it to 256MB-1GB on a server with plenty of RAM without worrying about memory exhaustion from concurrent maintenance tasks.

---

## 5. effective_cache_size - Telling the Planner About OS Cache

`effective_cache_size` does NOT allocate memory. It is a **hint** that tells the query planner how much memory the OS page cache plus shared_buffers can hold. The planner uses this to decide whether index scans are likely to find pages already cached.

Check the current value.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW effective_cache_size;"
```

Expected output:

```
 effective_cache_size
----------------------
 4GB
(1 row)
```

A good rule is: `effective_cache_size = total_RAM - shared_buffers`. On a 4GB server with 1GB shared_buffers, set it to 3GB. If set too low, the planner assumes data is not cached and favors sequential scans over index scans.

Set it correctly.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET effective_cache_size = '3GB';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

---

## 6. temp_buffers - Per-Session Temporary Table Cache

`temp_buffers` controls the memory available for temporary tables created within a session (`CREATE TEMP TABLE`). It is allocated per-session, only when a session actually uses temp tables.

Check the current value.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW temp_buffers;"
```

Expected output:

```
 temp_buffers
--------------
 8MB
(1 row)
```

For sessions that use large temp tables (ETL work, complex reports), raise this per-session before creating the temp table.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SET temp_buffers = '64MB';
CREATE TEMP TABLE temp_summary AS
  SELECT customer_id, SUM(total_amount) AS total
  FROM orders GROUP BY customer_id;
SELECT COUNT(*) FROM temp_summary;
```

Expected output (yours will differ):

```
 count
-------
  9920
(1 row)
```

```
\q
```

---

## 7. pg_buffercache - See What Is in Shared Buffers

The `pg_buffercache` extension shows you exactly what data pages are currently cached in shared_buffers.

Install the extension (only needed once).

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "CREATE EXTENSION IF NOT EXISTS pg_buffercache;"
```

Expected output:

```
CREATE EXTENSION
```

See which relations are consuming the most buffer space.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT relname, count(*) AS buffers, pg_size_pretty(count(*) * 8192) AS size_in_cache FROM pg_buffercache b JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid) WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public') GROUP BY relname ORDER BY buffers DESC LIMIT 10;"
```

Expected output (yours will differ):

```
        relname         | buffers | size_in_cache
------------------------+---------+---------------
 order_items            |     960 | 7680 kB
 orders                 |     472 | 3776 kB
 order_items_pkey       |     414 | 3312 kB
 orders_pkey            |     139 | 1112 kB
 customers              |     118 | 944 kB
 customers_email_key    |      85 | 680 kB
 customers_pkey         |      30 | 240 kB
 products               |       1 | 8 kB
(8 rows)
```

> **Concept - Buffer Usagecount**: Each buffer in shared_buffers has a `usagecount` (1-5) that tracks how recently it was accessed. The clock sweep eviction algorithm evicts buffers with the lowest usagecount first. Frequently accessed data accumulates high usagecounts and stays in cache. You can see usagecount in the `pg_buffercache` view.

Check the cache hit ratio from pg_stat_bgwriter.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT buffers_clean, buffers_checkpoint, buffers_alloc, (buffers_clean::float / nullif(buffers_alloc,0) * 100)::int AS approx_hit_pct FROM pg_stat_bgwriter;"
```

Expected output (yours will differ):

```
 buffers_clean | buffers_checkpoint | buffers_alloc | approx_hit_pct
---------------+--------------------+---------------+----------------
             0 |                  5 |           500 |              0
(1 row)
```

```
exit
```

---

## Checkpoint

By the end of this guide you should be able to:

- [ ] Explain what each of the five memory parameters does
- [ ] Identify which parameters require a restart vs a reload
- [ ] Change work_mem and maintenance_work_mem using ALTER SYSTEM + pg_reload_conf
- [ ] Use pg_buffercache to see what data is in shared_buffers
- [ ] Understand the difference between in-memory sorts and disk spills

---

**Proceed to:** [Guide 04 - Query Optimization](./04-query-optimization.md)
