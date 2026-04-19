# Scenario 06 - Partition Pruning Disabled

**Severity:** MEDIUM
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Queries on the sales table that filter by date
are scanning all 12 partitions instead of just the
relevant month. Query performance has degraded 12x.
A configuration change was made recently during a
troubleshooting session.
```

---

## Key Concepts for Revision

- **Partition pruning eliminates irrelevant partitions** - When a query includes a WHERE clause on the partition key, PostgreSQL can determine at plan time (or execution time) which partitions cannot contain matching rows and skip them entirely. This is the primary performance benefit of partitioning.

- **enable_partition_pruning controls this optimization** - When set to `off`, PostgreSQL scans all partitions regardless of the WHERE clause. The query still returns correct results, but reads 12x more data (for 12 partitions). This setting defaults to `on` and should almost never be changed.

- **EXPLAIN shows pruned partitions** - In EXPLAIN output, pruned partitions are either absent from the plan or marked with `(never executed)` in EXPLAIN ANALYZE. The `Subplans Removed` count shows how many partitions were pruned at plan time. With pruning off, all partitions appear in the plan.

- **Runtime pruning vs plan-time pruning** - Plan-time pruning happens when the WHERE clause uses literal values (`WHERE sale_date = '2024-03-15'`). Runtime pruning happens when the value comes from a parameter or subquery - PostgreSQL evaluates the partition constraint at execution time. Both require `enable_partition_pruning = on`.

- **Constraint exclusion is the older mechanism** - Before native partitioning (PG 10), PostgreSQL used CHECK constraints and `constraint_exclusion` for similar pruning. With native partitioning, `enable_partition_pruning` is the correct setting. `constraint_exclusion` is still used for inheritance-based partitioning.

---

## Diagnostic Steps

### Step 1 - Check a query plan to see the problem

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN SELECT * FROM chaos6_sales WHERE sale_date = '2024-03-15';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Append  (cost=0.00..1200.00 rows=2 width=...)
   ->  Seq Scan on chaos6_sales_2024_01  (cost=...)
         Filter: (sale_date = '2024-03-15'::date)
   ->  Seq Scan on chaos6_sales_2024_02  (cost=...)
         Filter: (sale_date = '2024-03-15'::date)
   ->  Seq Scan on chaos6_sales_2024_03  (cost=...)
         Filter: (sale_date = '2024-03-15'::date)
   ... (all 12 partitions listed)
```

All 12 partitions are scanned. Only `chaos6_sales_2024_03` should be scanned for March 15.

### Step 2 - Check the pruning setting

```sql
SHOW enable_partition_pruning;
```

Expected output:

```
 enable_partition_pruning
--------------------------
 off
(1 row)
```

Partition pruning is disabled. This is the root cause.

### Step 3 - Confirm with a temporary session-level override

```sql
SET enable_partition_pruning = on;
EXPLAIN SELECT * FROM chaos6_sales WHERE sale_date = '2024-03-15';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos6_sales_2024_03 chaos6_sales  (cost=...)
   Filter: (sale_date = '2024-03-15'::date)
```

Only one partition is scanned. This confirms the setting is the issue.

```sql
RESET enable_partition_pruning;
```

### Step 4 - Find where the setting was changed

```sql
\q
```

```bash
grep partition_pruning /opt/pgsql/data/postgresql.auto.conf
```

Expected output:

```
enable_partition_pruning = 'off'
```

---

## Resolution

### Step 1 - Re-enable partition pruning

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM RESET enable_partition_pruning;
```

Expected output:

```
ALTER SYSTEM
```

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

### Step 3 - Verify the setting is back to on

```sql
SHOW enable_partition_pruning;
```

Expected output:

```
 enable_partition_pruning
--------------------------
 on
(1 row)
```

### Step 4 - Verify partition pruning works

```sql
EXPLAIN SELECT * FROM chaos6_sales WHERE sale_date = '2024-03-15';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos6_sales_2024_03 chaos6_sales  (cost=...)
   Filter: (sale_date = '2024-03-15'::date)
```

Only the March partition is scanned.

### Step 5 - Verify with EXPLAIN ANALYZE for actual execution

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos6_sales WHERE sale_date BETWEEN '2024-06-01' AND '2024-06-30';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos6_sales_2024_06 chaos6_sales  (cost=...)
   Filter: (sale_date >= '2024-06-01' AND sale_date <= '2024-06-30')
   Rows Removed by Filter: ...
   Actual Rows: ~2000
   Planning Time: 0.200 ms
   Execution Time: 1.500 ms
```

Only the June partition is scanned. Planning time is fast because 11 partitions were pruned.

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
- enable_partition_pruning is on
- EXPLAIN for date-filtered query shows only relevant partition
- postgresql.auto.conf has no partition pruning override

---

## Interview Discussion Points

1. **What is the difference between plan-time and runtime partition pruning?** - Plan-time pruning happens when the partition key value is a constant known at planning time (`WHERE sale_date = '2024-03-15'`). Runtime pruning happens when the value is determined during execution (from a parameter, subquery, or join). Runtime pruning (PG 11+) is critical for prepared statements where the value is not known until execution.

2. **Does partition pruning work with JOINs?** - Yes, if the join condition includes the partition key. For example, `SELECT * FROM sales s JOIN regions r ON s.region = r.name WHERE s.sale_date = '2024-03-15'` will still prune partitions based on the `sale_date` filter. The pruning decision is independent of the join.

3. **When would you intentionally disable partition pruning?** - Almost never. The only scenario is debugging: to see the full plan across all partitions, or to reproduce an issue that only appears when all partitions are scanned. Always re-enable it after debugging.

4. **How many partitions can you have before pruning overhead becomes significant?** - PostgreSQL handles hundreds of partitions efficiently. Planning time increases linearly with partition count. Above 1,000 partitions, planning overhead becomes noticeable (5-50ms per query). Above 10,000 partitions, planning can dominate query time. If you have many partitions, consider sub-partitioning or consolidating old partitions.

5. **Does partition pruning work with LIKE or function calls on the partition key?** - No, if the function or operator prevents PostgreSQL from matching the expression to partition bounds. `WHERE sale_date = '2024-03-15'` works. `WHERE EXTRACT(MONTH FROM sale_date) = 3` does not - the planner cannot map this to partition ranges. `WHERE sale_date >= '2024-03-01' AND sale_date < '2024-04-01'` works because it maps directly to bounds.
