# Use Exercise 02 - Memory Sizing for a 1GB RAM Server

Calculate the ideal shared_buffers, work_mem, and effective_cache_size for a 1GB RAM PostgreSQL server. Apply the values and verify them.

**Server:** NODE1 only

---

## Context

You have been handed a PostgreSQL 16 server with 1GB of RAM. It runs a small e-commerce workload (the stepup_store database). There are at most 20 concurrent connections. Your job is to calculate the right memory parameters and apply them.

---

## The Calculation

Work through each parameter on paper or in your head before you touch the server.

### Step 1 - Total RAM

Total RAM: 1024 MB

### Step 2 - OS Reserve

The OS and other processes need memory. Reserve at least 200-256MB.

OS Reserve: 256 MB

Remaining for PostgreSQL: 1024 - 256 = 768 MB

### Step 3 - shared_buffers

Rule: 25% of total RAM, or about a third of the PostgreSQL-available memory.

25% of 1024MB = 256MB

Note: going above 512MB on a 1GB server is risky - the OS page cache needs room too.

**Your answer for shared_buffers:**

```
shared_buffers = 256MB
```

### Step 4 - effective_cache_size

This is a planner hint, not an allocation. Set it to total RAM minus shared_buffers.

1024MB - 256MB = 768MB

The OS page cache plus shared_buffers together can serve about 768MB of data.

**Your answer for effective_cache_size:**

```
effective_cache_size = 768MB
```

### Step 5 - work_mem

Formula: (Available RAM - shared_buffers) / max_connections / max_sort_operations_per_query

Available RAM: 768MB
shared_buffers: 256MB
Remaining: 768 - 256 = 512MB

max_connections: 20
Typical sort operations per query: 2-4 (joins, sorts, hash builds)

512MB / 20 connections / 3 operations = 8.5MB - round down to 8MB

**Your answer for work_mem:**

```
work_mem = 8MB
```

### Step 6 - maintenance_work_mem

Set to 10% of total RAM for this small server.

10% of 1024MB = 102MB - round to 64MB (conservative for 1GB).

**Your answer for maintenance_work_mem:**

```
maintenance_work_mem = 64MB
```

---

## Apply the Settings

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Apply settings that do not require a restart first using ALTER SYSTEM.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET work_mem = '8MB';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET maintenance_work_mem = '64MB';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET effective_cache_size = '768MB';"
```

Expected output:

```
ALTER SYSTEM
```

Reload to pick up those changes.

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

Now set shared_buffers (requires restart). Edit postgresql.conf.

```
exit
```

```
sudo vi /opt/pgsql/data/postgresql.conf
```

Find the `shared_buffers` line and set it.

```
shared_buffers = 256MB
```

Save and exit (`:wq`).

Restart PostgreSQL.

```
sudo systemctl restart postgresql-16
```

---

## Verify

Switch to postgres and confirm all values.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT name, setting || unit AS value FROM pg_settings WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size') ORDER BY name;"
```

Expected output:

```
         name          |  value
-----------------------+---------
 effective_cache_size  | 768MB
 maintenance_work_mem  | 64MB
 shared_buffers        | 256MB
 work_mem              | 8MB
(4 rows)
```

Run a query that involves a sort and confirm no temp file spills.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "EXPLAIN (ANALYZE, BUFFERS) SELECT customer_id, SUM(total_amount) FROM orders GROUP BY customer_id ORDER BY SUM(total_amount) DESC;"
```

Expected output (yours will differ):

```
                                                       QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=8.50..8.63 rows=50 width=36) (actual time=0.188..0.193 rows=50 loops=1)
   Sort Key: (sum(total_amount)) DESC
   Sort Method: quicksort  Memory: 27kB
   ->  HashAggregate  (cost=7.00..7.50 rows=50 width=36) ...
 Planning Time: 0.122 ms
 Execution Time: 0.212 ms
(6 rows)
```

`Sort Method: quicksort Memory: 27kB` - the sort used in-memory. If it showed `external merge Disk:` then work_mem needs to be higher.

```
exit
```

---

## Reflection Questions

Answer these before moving on.

1. Why is `effective_cache_size` not an actual memory allocation? What would happen if you set it to 100GB on a 1GB server?

2. If you suddenly had 50 connections instead of 20, what would you change about the work_mem calculation?

3. What is the danger of setting shared_buffers to 75% of RAM on a server that is also running the application?

4. Which of the four parameters requires a restart and why?

---

## Checkpoint

- [ ] You calculated all four values before touching the server
- [ ] All four parameters are now set correctly in PostgreSQL
- [ ] The sort in the verification query used memory (not disk)
- [ ] You can answer all four reflection questions
