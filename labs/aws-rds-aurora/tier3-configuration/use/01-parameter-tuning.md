# USE 01 - Parameter Tuning

**Time:** 20 minutes
**Level:** Intermediate
**Prerequisite:** BUILD 01 completed

---

## Scenario

You are the DBA for [COMPANY]'s e-commerce platform. The platform has a PostgreSQL 16 instance on RDS (db.r6g.xlarge, 32 GB RAM). Your application team has reported these problems:

1. **Slow checkout queries** - queries taking 3-8 seconds on the orders table
2. **Application timeouts** - connections piling up during flash sales
3. **Memory warnings** - occasional "out of memory" errors in logs

You need to tune the parameter group to address all three problems.

---

## Workload Profile

```
Peak concurrent users:    2,000
Database size:            180 GB
Busiest tables:           orders, order_items, inventory
Peak query type:          Complex JOINs with aggregations
Read/write ratio:         70% read, 30% write
```

---

## Task 1 - Diagnose Current Settings

First, understand what is currently configured.

**Connect to the database:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d [DBNAME]
```

**Check current memory settings:**

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name IN (
  'shared_buffers',
  'work_mem',
  'maintenance_work_mem',
  'effective_cache_size',
  'max_connections'
)
ORDER BY name;
```

Write down the current values. You will compare them after tuning.

**Check connection usage:**

```sql
SELECT
  count(*) AS total_connections,
  count(*) FILTER (WHERE state = 'active') AS active,
  count(*) FILTER (WHERE state = 'idle') AS idle,
  count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction
FROM pg_stat_activity;
```

**Find slow queries using pg_stat_statements:**

```sql
SELECT
  LEFT(query, 100) AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 0) AS avg_ms,
  round(total_exec_time::numeric, 0) AS total_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 5;
```

---

## Task 2 - Calculate Target Parameter Values

Use the formulas below to calculate appropriate values for a db.r6g.xlarge (32 GB RAM).

### Memory Parameters

**shared_buffers** - PostgreSQL's own page cache
- Rule: 25% of total RAM
- Formula: `32 GB * 0.25 = 8 GB = 8192 MB`
- Parameter value: `8192MB`

**effective_cache_size** - hint to the query planner about OS + PostgreSQL cache
- Rule: 75% of total RAM
- Formula: `32 GB * 0.75 = 24 GB = 24576 MB`
- Parameter value: `24576MB`

**work_mem** - memory per sort/hash operation (can be used many times per query)
- Rule: (RAM - shared_buffers) / (max_connections * 3)
- Formula: `(32768 - 8192) / (200 * 3) = 24576 / 600 = ~41 MB`
- Round down to: `40MB` = `40960 kB`
- Parameter value: `40960`

**maintenance_work_mem** - memory for VACUUM, CREATE INDEX, etc.
- Rule: 5-10% of RAM, max 1 GB
- Formula: `32 GB * 0.05 = 1.6 GB` - cap at `1024MB`
- Parameter value: `1048576` (1 GB in kB)

### Connection Parameters

**max_connections** - maximum simultaneous connections
- For the e-commerce workload: `200` (use PgBouncer for more)
- Reducing this frees memory

### Logging Parameters

For diagnosing slow checkouts:
- `log_min_duration_statement = 2000` (log queries taking > 2 seconds)
- `log_lock_waits = on` (log when queries wait for locks)
- `log_temp_files = 0` (log any query that writes temp files to disk)

---

## Task 3 - Apply the Tuning

Apply all the parameters to your custom parameter group.

**Step 1 - Apply dynamic parameters (no reboot needed):**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --parameters \
    "ParameterName=work_mem,ParameterValue=40960,ApplyMethod=immediate" \
    "ParameterName=maintenance_work_mem,ParameterValue=1048576,ApplyMethod=immediate" \
    "ParameterName=effective_cache_size,ParameterValue=24576,ApplyMethod=immediate" \
    "ParameterName=log_min_duration_statement,ParameterValue=2000,ApplyMethod=immediate" \
    "ParameterName=log_lock_waits,ParameterValue=1,ApplyMethod=immediate" \
    "ParameterName=log_temp_files,ParameterValue=0,ApplyMethod=immediate"
```

**Step 2 - Apply static parameters (requires reboot):**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --parameters \
    "ParameterName=shared_buffers,ParameterValue=8192,ApplyMethod=pending-reboot" \
    "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot"
```

**Step 3 - Reboot to apply static params:**

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

---

## Task 4 - Verify the Changes

After the reboot, confirm all parameters took effect.

**Verify memory parameters:**

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
  'shared_buffers',
  'work_mem',
  'maintenance_work_mem',
  'effective_cache_size',
  'max_connections'
)
ORDER BY name;
```

**Check non-default parameters in the group:**

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --source user \
  --query 'Parameters[*].{Name:ParameterName,Value:ParameterValue}' \
  --output table
```

---

## Task 5 - Validate with a Workload Test

Run a few complex queries and check if they improved.

```sql
-- Simulate a slow checkout query
EXPLAIN (ANALYZE, BUFFERS)
SELECT
  o.id AS order_id,
  o.created_at,
  COUNT(oi.id) AS item_count,
  SUM(oi.quantity * oi.unit_price) AS total
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
WHERE o.created_at >= now() - interval '30 days'
GROUP BY o.id, o.created_at
ORDER BY total DESC
LIMIT 100;
```

Look for:
- `Buffers: shared hit` - reads from shared_buffers (fast)
- `Buffers: shared read` - reads from disk (slow)
- Sort operations using `work_mem` instead of temp files

---

## Discussion Questions

1. Why is `shared_buffers` set to 25% of RAM and not more? What happens if you set it too high?

2. The formula for `work_mem` divides by `max_connections * 3`. Why multiply by 3?

3. You set `log_temp_files = 0`. A query writes a 2 MB temp file. Does that appear in the log?

4. A developer says "just increase max_connections to 1000." What is the problem with this approach?

5. After tuning, `shared_buffers` shows as `8192` in pg_settings but `shared_buffers` is set to `8192MB` in the parameter group. Why does pg_settings show a different unit?

---

## Expected Outcomes

After applying these parameters:
- Complex queries should use shared_buffers more (you'll see higher `hit` ratio in EXPLAIN BUFFERS)
- Queries that were writing temp files should now do more in memory
- Slow queries (>2 sec) will appear in CloudWatch logs
- Connection overhead should drop with lower max_connections

---

## Reference - Common Parameter Formulas

| Parameter | Formula | Notes |
|---|---|---|
| `shared_buffers` | 25% of RAM | Static - needs reboot |
| `effective_cache_size` | 75% of RAM | Dynamic - planner hint only |
| `work_mem` | (RAM - shared_buffers) / (connections * 3) | Dynamic - per-sort, per-session |
| `maintenance_work_mem` | 5% of RAM, max 1 GB | Dynamic - per maintenance op |
| `max_connections` | 100-500 for most workloads | Static - use PgBouncer for more |
| `wal_buffers` | 3% of shared_buffers, max 64 MB | Static |
