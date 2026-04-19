# Scenario 07 - Too Many Partitions

**Severity:** MEDIUM
**Expected Recovery Time:** 15-20 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: The metrics table has ~500 daily partitions.
Simple queries take 200-500ms just for planning.
Even queries that only touch one day spend most
of their time in the planner, not executing.
The table was partitioned by day but should have
been partitioned by month or quarter.
```

---

## Key Concepts for Revision

- **Planning time scales with partition count** - The PostgreSQL planner must evaluate each partition during query planning: checking constraints, estimating costs, and building the plan tree. With 500 partitions, even a simple `SELECT ... WHERE date = '2024-01-01'` incurs 200-500ms of planning overhead, compared to sub-millisecond planning for a non-partitioned table.

- **Daily partitions are rarely appropriate** - Daily partitions make sense only when you regularly drop entire days of data (e.g., TTL-based retention) and each day has millions of rows. For most workloads, monthly or quarterly partitions provide the pruning benefits without the planning overhead.

- **Merging partitions requires data movement** - PostgreSQL does not have a `MERGE PARTITION` command. To consolidate daily into monthly: (1) Create the new monthly partition. (2) Move data from daily partitions into the monthly partition. (3) Detach and drop the daily partitions. This requires careful planning around data availability.

- **Monitoring planning time** - Use `EXPLAIN (ANALYZE)` and look at `Planning Time`. If planning time exceeds execution time, partition overhead is likely the cause. The `pg_stat_statements` extension tracks average planning time per query pattern.

- **Partition count guidelines** - Keep under 100-200 partitions for best planner performance. If you need more granularity, consider sub-partitioning (partition by year, then sub-partition by month). PG 14+ has improved partition planning performance, but excessive partitions still cause overhead.

---

## Diagnostic Steps

### Step 1 - Count the partitions

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT count(*) AS partition_count
FROM pg_inherits
WHERE inhparent = 'chaos7_metrics'::regclass;
```

Expected output (yours will differ):

```
 partition_count
-----------------
             500
(1 row)
```

500 daily partitions. This is excessive.

### Step 2 - Measure planning time vs execution time

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos7_metrics WHERE metric_date = '2023-06-15';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos7_metrics_2023_06_15 chaos7_metrics  (cost=...)
   Filter: (metric_date = '2023-06-15'::date)
   Actual Rows: 20
   Planning Time: 250.000 ms
   Execution Time: 0.050 ms
```

Planning Time (250ms) is thousands of times higher than Execution Time (0.05ms). The planner is the bottleneck.

### Step 3 - Check the partition structure

```sql
SELECT
  inhrelid::regclass AS partition_name,
  pg_get_expr(c.relpartbound, c.oid) AS bounds
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'chaos7_metrics'::regclass
ORDER BY partition_name
LIMIT 10;
```

Expected output (yours will differ):

```
       partition_name        |                      bounds
-----------------------------+---------------------------------------------------
 chaos7_metrics_2023_01_01   | FOR VALUES FROM ('2023-01-01') TO ('2023-01-02')
 chaos7_metrics_2023_01_02   | FOR VALUES FROM ('2023-01-02') TO ('2023-01-03')
 chaos7_metrics_2023_01_03   | FOR VALUES FROM ('2023-01-03') TO ('2023-01-04')
 ...
```

Each partition covers exactly one day. This is the root of the overhead.

---

## Resolution

We will consolidate the oldest daily partitions into monthly partitions, leaving recent months as daily for current use.

### Step 1 - Create a monthly partition for January 2023

First, check which daily partitions cover January 2023:

```sql
SELECT inhrelid::regclass AS partition_name
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'chaos7_metrics'::regclass
AND pg_get_expr(c.relpartbound, c.oid) LIKE '%2023-01-%'
ORDER BY partition_name;
```

This lists the ~31 daily partitions for January.

### Step 2 - Create a temporary table for January data

```sql
CREATE TABLE chaos7_metrics_2023_jan_tmp AS
SELECT * FROM chaos7_metrics
WHERE metric_date >= '2023-01-01' AND metric_date < '2023-02-01';
```

Expected output (yours will differ):

```
SELECT 620
```

### Step 3 - Detach and drop the daily January partitions

This is the tedious part. Detach each daily partition for January:

```sql
DO $$
DECLARE
  part_name text;
BEGIN
  FOR part_name IN
    SELECT inhrelid::regclass::text
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'chaos7_metrics'::regclass
    AND pg_get_expr(c.relpartbound, c.oid) >= 'FOR VALUES FROM (''2023-01-01'')'
    AND pg_get_expr(c.relpartbound, c.oid) < 'FOR VALUES FROM (''2023-02-01'')'
    ORDER BY inhrelid::regclass::text
  LOOP
    EXECUTE format('ALTER TABLE chaos7_metrics DETACH PARTITION %I', part_name);
    EXECUTE format('DROP TABLE %I', part_name);
  END LOOP;
END $$;
```

Expected output:

```
DO
```

### Step 4 - Create the monthly partition and load data

```sql
CREATE TABLE chaos7_metrics_2023_01
    PARTITION OF chaos7_metrics
    FOR VALUES FROM ('2023-01-01') TO ('2023-02-01');

INSERT INTO chaos7_metrics_2023_01
SELECT * FROM chaos7_metrics_2023_jan_tmp;

DROP TABLE chaos7_metrics_2023_jan_tmp;
```

### Step 5 - Repeat for remaining months (abbreviated)

For a real scenario, repeat Steps 2-4 for each month. Here is a condensed approach for all months:

```sql
DO $$
DECLARE
  m integer;
  start_date date;
  end_date date;
  part_name text;
  month_part text;
  row_count integer;
BEGIN
  FOR m IN 2..12 LOOP
    start_date := ('2023-' || lpad(m::text, 2, '0') || '-01')::date;
    end_date := (start_date + interval '1 month')::date;
    month_part := 'chaos7_metrics_2023_' || lpad(m::text, 2, '0');

    -- Create temp table
    EXECUTE format('CREATE TABLE %I_tmp AS SELECT * FROM chaos7_metrics WHERE metric_date >= %L AND metric_date < %L',
                   month_part, start_date, end_date);

    -- Detach and drop daily partitions for this month
    FOR part_name IN
      SELECT inhrelid::regclass::text
      FROM pg_inherits i
      JOIN pg_class c ON c.oid = i.inhrelid
      WHERE i.inhparent = 'chaos7_metrics'::regclass
      AND pg_get_expr(c.relpartbound, c.oid) >= format('FOR VALUES FROM (''%s'')', start_date)
      AND pg_get_expr(c.relpartbound, c.oid) < format('FOR VALUES FROM (''%s'')', end_date)
    LOOP
      EXECUTE format('ALTER TABLE chaos7_metrics DETACH PARTITION %I', part_name);
      EXECUTE format('DROP TABLE %I', part_name);
    END LOOP;

    -- Create monthly partition and load data
    EXECUTE format('CREATE TABLE %I PARTITION OF chaos7_metrics FOR VALUES FROM (%L) TO (%L)',
                   month_part, start_date, end_date);
    EXECUTE format('INSERT INTO %I SELECT * FROM %I_tmp', month_part, month_part);
    EXECUTE format('DROP TABLE %I_tmp', month_part);
  END LOOP;
END $$;
```

Expected output:

```
DO
```

### Step 6 - Verify reduced partition count

```sql
SELECT count(*) AS partition_count
FROM pg_inherits
WHERE inhparent = 'chaos7_metrics'::regclass;
```

Expected output (yours will differ):

```
 partition_count
-----------------
       12 - ~140
```

The count should be significantly reduced (monthly partitions for 2023 + remaining daily partitions for 2024 months if any).

### Step 7 - Verify improved planning time

```sql
ANALYZE chaos7_metrics;

EXPLAIN (ANALYZE) SELECT * FROM chaos7_metrics WHERE metric_date = '2023-06-15';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos7_metrics_2023_06 chaos7_metrics  (cost=...)
   Filter: (metric_date = '2023-06-15'::date)
   Planning Time: 5.000 ms
   Execution Time: 0.050 ms
```

Planning time should drop from 250ms to under 10ms.

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
- Partition count is under 200
- Planning time for single-date query is under 50ms
- Data is intact (total row count matches)

---

## Interview Discussion Points

1. **What is the partition count sweet spot?** - For most OLTP workloads, keep it under 100-200. For OLAP/analytics, up to 500 can work if queries always include the partition key. Beyond 1,000, planning overhead dominates. PG 14 improved planner performance with partitions, but the overhead is still linear.

2. **How would you prevent this in the first place?** - Establish a partition strategy document before creating the table. Choose granularity based on data retention policy (daily only if you drop daily), query patterns (monthly if reports are monthly), and data volume (daily only if each day has millions of rows). Automate partition creation with pg_partman extension.

3. **What is pg_partman and when should you use it?** - pg_partman is an extension that automates partition creation and maintenance. It handles: creating future partitions ahead of time, dropping or detaching old partitions based on retention policy, and managing partition naming. It is strongly recommended for any production partitioned table to avoid manual partition management.

4. **Can sub-partitioning help?** - Yes. Instead of 365 daily partitions per year, partition by year (4 partitions for 4 years), then sub-partition each year by month (12 sub-partitions). The top-level planner only evaluates 4 partitions, then drills into the relevant year's 12 sub-partitions. Total: 48 partitions evaluated instead of 365.

5. **How do you merge partitions without downtime?** - Use `ALTER TABLE ... MERGE PARTITIONS` (PG 17+). For older versions: create a new partition, use `INSERT INTO new_partition SELECT ... FROM old_partitions`, then detach and drop old ones. During the migration, both old and new partitions serve reads. The final detach step requires a brief lock but does not block reads for long.
