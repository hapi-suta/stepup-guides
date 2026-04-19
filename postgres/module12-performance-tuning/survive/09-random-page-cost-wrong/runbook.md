# Scenario 09 - random_page_cost Wrong

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Database queries are extremely slow.
EXPLAIN shows sequential scans on every table.
The DBA team recently tuned 'cost parameters'
but the application is performing worse than before.
```

---

## Key Concepts for Revision

- **random_page_cost estimates the cost of a random page read** - PostgreSQL's planner assigns abstract cost units to different operations. `seq_page_cost` (default 1.0) is the baseline cost of reading one page sequentially. `random_page_cost` (default 4.0) is the cost of a random page read. A ratio of 4:1 means the planner treats random I/O as 4x more expensive than sequential I/O.

- **At 100, index scans are essentially impossible** - With `random_page_cost = 100`, the planner thinks every random page read costs 100x a sequential read. Even a highly selective index scan (returning 1 row from a million) looks more expensive than scanning the entire table sequentially. The planner will choose sequential scans for virtually every query.

- **SSD vs HDD tuning** - The default of 4.0 was set when spinning disks were common (random seeks are 4-10x slower than sequential reads on HDD). On SSDs, random and sequential reads have similar performance, so `random_page_cost` should be lowered to 1.1-1.5. Some DBAs set it to 1.1 on NVMe drives.

- **This is a planner cost model parameter** - Like `effective_cache_size`, `random_page_cost` does not change actual I/O behavior. It only affects the planner's cost estimates. A wrong value leads to suboptimal plan choices, not crashes or data corruption.

- **Per-tablespace tuning is possible** - You can set `random_page_cost` per tablespace with `ALTER TABLESPACE ... SET (random_page_cost = ...)`. This is useful if some tablespaces are on SSDs and others on HDDs.

---

## Diagnostic Steps

### Step 1 - Check a query plan

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

Sequential scan on a query that should use an index.

### Step 2 - Check the cost parameters

```sql
SHOW random_page_cost;
```

Expected output:

```
 random_page_cost
------------------
 100
(1 row)
```

100 is absurdly high. Default is 4.0.

```sql
SHOW seq_page_cost;
```

Expected output:

```
 seq_page_cost
---------------
 1
(1 row)
```

The ratio is 100:1 (random:sequential). The planner thinks random I/O is 100x slower than sequential, making index scans look prohibitively expensive.

### Step 3 - Compare costs with corrected setting temporarily

```sql
SET random_page_cost = 1.5;
```

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

With a reasonable `random_page_cost`, the planner uses the index. This confirms the setting is the root cause.

```sql
RESET random_page_cost;
```

### Step 4 - Find where the setting was changed

```sql
\q
```

```bash
grep random_page_cost /opt/pgsql/data/postgresql.auto.conf
```

Expected output:

```
random_page_cost = '100'
```

---

## Resolution

### Step 1 - Set a reasonable random_page_cost

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

For SSD storage (most cloud instances):

```sql
ALTER SYSTEM SET random_page_cost = 1.1;
```

Expected output:

```
ALTER SYSTEM
```

For HDD storage, use 4.0 (the default). For this lab, 1.1 is correct because EC2 instances use SSD-backed EBS.

### Step 2 - Reload configuration

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

### Step 3 - Verify the new value

```sql
SHOW random_page_cost;
```

Expected output:

```
 random_page_cost
------------------
 1.1
(1 row)
```

### Step 4 - Confirm the planner now uses indexes

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
- random_page_cost is between 1.0 and 4.0
- EXPLAIN shows index scans on indexed columns
- postgresql.auto.conf does not have random_page_cost = 100

---

## Interview Discussion Points

1. **What is the relationship between random_page_cost and effective_cache_size?** - Both affect how the planner evaluates index scans. `effective_cache_size` tells the planner how likely a page is already cached (reducing the effective cost of the read). `random_page_cost` sets the base cost of a random read when it does hit disk. Together, they determine the expected cost of an index scan: `actual_cost = random_page_cost * (1 - cache_hit_probability)`. Misconfiguring either one can push the planner toward or away from index scans.

2. **Why is the default random_page_cost 4.0 and not higher?** - On spinning disks, random seek time is roughly 10ms while sequential read of the next page is roughly 1-3ms. The 4:1 ratio is conservative - real HDD ratios are closer to 10:1 or higher. PostgreSQL uses 4.0 as a compromise because the OS page cache absorbs many random reads, making the effective ratio lower than the raw hardware ratio.

3. **When should you set random_page_cost to 1.0 (equal to seq_page_cost)?** - In theory, on storage where random and sequential reads are identical - pure in-memory databases or extremely fast NVMe with all data cached. In practice, even NVMe has a slight penalty for random reads due to page table lookups and memory access patterns. 1.1 is safer than 1.0.

4. **How do you decide between 1.1 and 4.0 on a new server?** - Check the storage type. Cloud instances with SSD/NVMe EBS: 1.1. Local NVMe: 1.1. SAS/SATA SSD: 1.5. Spinning HDD: 4.0. You can also benchmark with `pg_test_fsync` and `fio` to measure actual random vs sequential I/O ratios on your specific hardware.

5. **Can random_page_cost be set per-tablespace?** - Yes. `ALTER TABLESPACE fast_ssd SET (random_page_cost = 1.1)` sets it for tables on that tablespace. This is useful in hybrid storage environments where some tables are on fast SSDs and others on slower storage. Per-tablespace settings override the global setting for queries that access tables in that tablespace.
