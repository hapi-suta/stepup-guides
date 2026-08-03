# Build 12 - Memory Parameter Tuning

**Time:** 35 minutes
**Goal:** Calculate correct values for shared_buffers, work_mem, maintenance_work_mem, and effective_cache_size for a given workload. Apply and validate the settings. Build a tuning calculator.
**Prerequisites:** RDS PostgreSQL with a custom parameter group. psql access. `$DB_INSTANCE_ID`, `$REGION` set.

---

## Background

PostgreSQL has several memory parameters. Getting them wrong is common and expensive - too low means queries spill to disk, too high means you risk OOM or starve other processes. Unlike some databases, PostgreSQL's memory model is multiplicative: work_mem applies per sort/hash operation, and one query can have several.

The key insight: on AWS RDS, several of these parameters are already set to sensible defaults based on instance size. Your job is to understand the defaults, know when they are wrong, and calculate corrected values based on your workload.

---

## Step 1 - Check Current Memory Settings

Connect to your database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Check all memory-related parameters:

```sql
SELECT
    name,
    setting,
    unit,
    pg_size_pretty(
        CASE unit
            WHEN '8kB' THEN setting::bigint * 8192
            WHEN 'kB' THEN setting::bigint * 1024
            WHEN 'MB' THEN setting::bigint * 1024 * 1024
            ELSE NULL
        END
    ) AS human_readable
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'temp_buffers',
    'wal_buffers',
    'autovacuum_work_mem',
    'max_connections'
)
ORDER BY name;
```

Expected output (yours will differ on a db.r6g.xlarge with 32GB RAM):
```
          name           |  setting  | unit | human_readable
-------------------------+-----------+------+----------------
 autovacuum_work_mem     | -1        |      |
 effective_cache_size    | 3145728   | 8kB  | 24 GB
 maintenance_work_mem    | 65536     | kB   | 64 MB
 max_connections         | 960       | null |
 shared_buffers          | 1048576   | 8kB  | 8 GB
 temp_buffers            | 1024      | 8kB  | 8 MB
 wal_buffers             | 2048      | 8kB  | 16 MB
 work_mem                | 4096      | kB   | 4 MB
```

---

## Step 2 - Get Instance Memory Information

Find out how much RAM your instance has:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].DBInstanceClass" \
  --output text \
  --region "$REGION"
```

Look up the instance class memory in this table:

| Instance Class | vCPUs | RAM |
|---------------|-------|-----|
| db.t3.medium | 2 | 4 GB |
| db.t3.large | 2 | 8 GB |
| db.m6g.large | 2 | 8 GB |
| db.m6g.xlarge | 4 | 16 GB |
| db.r6g.large | 2 | 16 GB |
| db.r6g.xlarge | 4 | 32 GB |
| db.r6g.2xlarge | 8 | 64 GB |
| db.r6g.4xlarge | 16 | 128 GB |
| db.r6g.8xlarge | 32 | 256 GB |
| db.r6g.16xlarge | 64 | 512 GB |

Or check in psql (requires pg_stat_statements or Enhanced Monitoring for OS info):

```sql
-- Check via a parameter that scales with RAM
SELECT
    setting::bigint * 8192 AS shared_buffers_bytes,
    pg_size_pretty(setting::bigint * 8192) AS shared_buffers,
    setting::bigint * 8192 / 0.25 AS estimated_total_ram,
    pg_size_pretty(setting::bigint * 8192 / 0.25) AS estimated_ram
FROM pg_settings
WHERE name = 'shared_buffers';
```

---

## Step 3 - The Memory Tuning Calculator

This is the formula you will apply:

```
Given:
  TOTAL_RAM        = total RAM in bytes
  MAX_CONNECTIONS  = current max_connections value
  WORKLOAD_TYPE    = OLTP | ANALYTICS | MIXED

shared_buffers:
  = TOTAL_RAM * 0.25
  (25% of RAM - do not exceed 40%)

effective_cache_size:
  = TOTAL_RAM * 0.75
  (hint to planner about total cache available)

maintenance_work_mem:
  OLTP:      min(256MB, TOTAL_RAM * 0.01)
  ANALYTICS: min(2GB,   TOTAL_RAM * 0.05)
  MIXED:     min(512MB, TOTAL_RAM * 0.02)

work_mem (safe maximum, global default):
  available = TOTAL_RAM - shared_buffers - OS_overhead(~4GB)
  max_sort_ops = MAX_CONNECTIONS * 3   (estimate)
  safe_work_mem = available / max_sort_ops

  Practical values:
  OLTP:      16MB to 64MB
  ANALYTICS: 64MB to 256MB (set per-session for big queries)
  MIXED:     32MB to 128MB

wal_buffers:
  = max(16MB, shared_buffers * 0.03)
  (auto-tuned by PostgreSQL in modern versions - usually leave as -1)
```

---

## Step 4 - Calculate Values for Your Instance

Create a function to do the calculation:

```sql
CREATE OR REPLACE FUNCTION calculate_memory_params(
    total_ram_gb NUMERIC,
    max_connections_val INT,
    workload_type TEXT DEFAULT 'OLTP'
)
RETURNS TABLE(
    parameter TEXT,
    recommended_value TEXT,
    reasoning TEXT
) AS $$
DECLARE
    ram_bytes BIGINT := (total_ram_gb * 1024 * 1024 * 1024)::BIGINT;
    shared_buf BIGINT;
    maint_wm BIGINT;
    safe_wm BIGINT;
    available_ram BIGINT;
BEGIN
    shared_buf := ram_bytes / 4;
    available_ram := ram_bytes - shared_buf - (4::BIGINT * 1024 * 1024 * 1024);

    -- maintenance_work_mem
    IF workload_type = 'ANALYTICS' THEN
        maint_wm := LEAST(2::BIGINT * 1024 * 1024 * 1024, (ram_bytes * 0.05)::BIGINT);
    ELSIF workload_type = 'MIXED' THEN
        maint_wm := LEAST(512 * 1024 * 1024, (ram_bytes * 0.02)::BIGINT);
    ELSE
        maint_wm := LEAST(256 * 1024 * 1024, (ram_bytes * 0.01)::BIGINT);
    END IF;

    -- safe work_mem
    safe_wm := GREATEST(16 * 1024 * 1024, available_ram / (max_connections_val * 3));

    RETURN QUERY VALUES
        ('shared_buffers',        pg_size_pretty(shared_buf),                'Always 25% of RAM'),
        ('effective_cache_size',  pg_size_pretty(ram_bytes * 3 / 4),         '75% of RAM - hint only'),
        ('maintenance_work_mem',  pg_size_pretty(maint_wm),                  'For VACUUM, ANALYZE, CREATE INDEX'),
        ('work_mem (safe max)',   pg_size_pretty(safe_wm),                   'Per sort/hash op; multiplies by sessions'),
        ('wal_buffers',           '16MB (auto)',                              'Auto-set from shared_buffers; leave as -1'),
        ('max_connections',       max_connections_val::TEXT,                  'Current value - consider RDS Proxy for >200');
END;
$$ LANGUAGE plpgsql;
```

Run the calculator for your instance:

```sql
-- Example: 32GB RAM instance, 200 max connections, OLTP workload
SELECT * FROM calculate_memory_params(32, 200, 'OLTP');
```

Expected output (yours will differ):
```
       parameter        | recommended_value  |              reasoning
------------------------+--------------------+---------------------------------------
 shared_buffers         | 8192 MB            | Always 25% of RAM
 effective_cache_size   | 24576 MB           | 75% of RAM - hint only
 maintenance_work_mem   | 256 MB             | For VACUUM, ANALYZE, CREATE INDEX
 work_mem (safe max)    | 42 MB              | Per sort/hash op; multiplies by sessions
 wal_buffers            | 16MB (auto)        | Auto-set from shared_buffers; leave as -1
 max_connections        | 200                | Current value - consider RDS Proxy for >200
```

---

## Step 5 - Apply Memory Parameters

Apply the calculated values to your parameter group:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters \
    "ParameterName=shared_buffers,ParameterValue=2621440,ApplyMethod=pending-reboot" \
    "ParameterName=effective_cache_size,ParameterValue=6291456,ApplyMethod=immediate" \
    "ParameterName=work_mem,ParameterValue=43008,ApplyMethod=immediate" \
    "ParameterName=maintenance_work_mem,ParameterValue=262144,ApplyMethod=immediate" \
  --region "$REGION"
```

Note: Parameter values are in the unit shown in `pg_settings`. For `shared_buffers` and `effective_cache_size`, the unit is 8kB pages. For `work_mem` and `maintenance_work_mem`, the unit is kB.

Convert your values:
- `shared_buffers = 8 GB = 8 * 1024 * 1024 / 8 = 1048576 pages`
- `work_mem = 42 MB = 42 * 1024 = 43008 kB`
- `maintenance_work_mem = 256 MB = 256 * 1024 = 262144 kB`

`shared_buffers` requires a reboot. Apply it during a maintenance window.

### Console

Use this if you prefer clicking through the AWS Console instead of running the CLI command above.

1. Open the **AWS Console** and go to **RDS** (search "RDS" in the top search bar).
2. In the left sidebar, click **Parameter groups**.
3. Find your parameter group in the list (e.g., `custom-pg16-perf`) and click its name.
4. Click the **Edit parameters** button in the top-right corner. The parameter rows will become editable.
5. In the **Filter parameters** search box, type `shared_buffers`. One result will appear.
   - Change the **Value** field to your calculated page count (e.g., `1048576` for 8 GB).
   - You will see a note next to this parameter saying **Requires restart** - this is a static parameter.
6. Clear the search box, then search for `effective_cache_size`. Change its value to your calculated page count (e.g., `6291456` for 24 GB).
   - This is a **dynamic** parameter - no reboot needed. It is a planner hint only, not an allocated buffer.
7. Clear the search box, then search for `work_mem`. Change its value in kB (e.g., `43008` for 42 MB).
   - This is **dynamic** - takes effect immediately for new connections.
8. Clear the search box, then search for `maintenance_work_mem`. Change its value in kB (e.g., `262144` for 256 MB).
   - This is **dynamic** - takes effect immediately.
9. Click **Save changes** in the top-right corner. You should see a green success banner: "Parameter group updated successfully."

**After saving:**
- `effective_cache_size`, `work_mem`, and `maintenance_work_mem` take effect within a minute for new sessions - no reboot needed.
- `shared_buffers` requires a reboot to take effect. To reboot: go to **Databases**, select your instance, click **Actions** > **Reboot**. Plan this for a maintenance window.

**Unit reminder:** When typing values in the console, use the raw unit shown in `pg_settings`:
- `shared_buffers` and `effective_cache_size` - enter the number of 8kB pages (e.g., 8 GB = `1048576`)
- `work_mem` and `maintenance_work_mem` - enter kB (e.g., 256 MB = `262144`)

---

## Step 6 - Validate shared_buffers with Buffer Hit Ratio

After applying settings and running your workload for at least 30 minutes:

```sql
-- Overall hit ratio
SELECT
    sum(heap_blks_hit) AS cache_hits,
    sum(heap_blks_read) AS disk_reads,
    round(
        sum(heap_blks_hit)::numeric /
        nullif(sum(heap_blks_hit + heap_blks_read), 0) * 100,
        2
    ) AS hit_ratio
FROM pg_statio_user_tables;
```

Expected output:
```
 cache_hits | disk_reads | hit_ratio
------------+------------+-----------
  234891023 |     234891 |     99.90
```

Target: hit_ratio > 99% for OLTP. If below 95%, shared_buffers may be too small for your working set, or you need a larger instance.

Hit ratio per table:

```sql
SELECT
    relname,
    heap_blks_hit,
    heap_blks_read,
    round(
        heap_blks_hit::numeric /
        nullif(heap_blks_hit + heap_blks_read, 0) * 100,
        1
    ) AS hit_ratio
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 0
ORDER BY heap_blks_read DESC
LIMIT 10;
```

Tables with low hit ratios are your candidates for indexing or instance upsizing.

---

## Step 7 - Validate work_mem with Sort Spill Rate

Check if current work_mem is sufficient:

```sql
SELECT
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE datname = current_database();
```

If `temp_files` is growing rapidly, work_mem is insufficient for your query workload.

Check which queries are spilling:

```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    temp_blks_written,
    round(temp_blks_written::numeric / nullif(calls, 0), 0) AS spill_blks_per_call
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

For queries that consistently spill large amounts, set work_mem higher for that session type:

```sql
-- In the application connection string or session startup
SET work_mem = '256MB';

-- Or for a specific query
BEGIN;
SET LOCAL work_mem = '512MB';
SELECT /* your large sort query here */;
COMMIT;
```

`SET LOCAL`: Scopes the parameter change to the current transaction only. After COMMIT or ROLLBACK, the session reverts to the default.

---

## Step 8 - Monitor Memory Pressure via Enhanced Monitoring

If your FreeableMemory CloudWatch metric is trending down, you may be approaching memory pressure. Check the breakdown via Enhanced Monitoring.

In the RDS Console:
1. Click your instance and go to the **Monitoring** tab.
2. Switch to **Enhanced monitoring**.
3. Look at the **Memory** section:
   - **Active**: Memory in use by processes.
   - **Buffers**: Memory used by OS buffers.
   - **Cached**: Memory used by OS page cache.
   - **Dirty**: Modified pages not yet written to disk.
   - **Free**: Truly free RAM.
   - **Swap**: If this is non-zero, you have a memory pressure problem.

Any swap usage on an RDS instance is a serious warning sign. Reduce work_mem or connection count, or upsize the instance.

---

## Step 9 - Tune autovacuum_work_mem Separately

By default, `autovacuum_work_mem = -1`, which means autovacuum uses `maintenance_work_mem`. Since maintenance_work_mem also applies to manual VACUUM and CREATE INDEX operations, setting it high can consume a lot of RAM if autovacuum runs while those operations are in progress.

Separate them:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters \
    "ParameterName=autovacuum_work_mem,ParameterValue=262144,ApplyMethod=immediate" \
    "ParameterName=maintenance_work_mem,ParameterValue=524288,ApplyMethod=immediate" \
  --region "$REGION"
```

`autovacuum_work_mem=262144`: 256MB for autovacuum workers.
`maintenance_work_mem=524288`: 512MB for manual VACUUM and CREATE INDEX (called during maintenance windows).

### Console

Use this if you prefer clicking through the AWS Console instead of running the CLI command above.

1. Open the **AWS Console** and go to **RDS**.
2. In the left sidebar, click **Parameter groups**.
3. Click your parameter group name (e.g., `custom-pg16-perf`).
4. Click **Edit parameters**.
5. In the **Filter parameters** search box, type `autovacuum_work_mem`. One result will appear.
   - Change the **Value** field to `262144` (256 MB in kB).
   - This is a **dynamic** parameter - takes effect immediately for new autovacuum workers.
6. Clear the search box, then search for `maintenance_work_mem`. Change its value to `524288` (512 MB in kB).
   - This is also **dynamic**.
7. Click **Save changes**. You should see a green success banner: "Parameter group updated successfully."

**After saving:** Both parameters take effect immediately - no reboot needed. New autovacuum runs will use `autovacuum_work_mem` (256 MB) and manual VACUUM or CREATE INDEX operations will use `maintenance_work_mem` (512 MB).

---

## Step 10 - Build a Memory Configuration Audit Query

Run this monthly to spot drift from intended settings:

```sql
WITH expected AS (
    SELECT *
    FROM (VALUES
        ('shared_buffers',       '8192 MB'),
        ('work_mem',             '42 MB'),
        ('maintenance_work_mem', '256 MB'),
        ('effective_cache_size', '24576 MB'),
        ('wal_buffers',          '16 MB')
    ) AS t(param, expected_value)
)
SELECT
    e.param,
    e.expected_value,
    pg_size_pretty(
        CASE s.unit
            WHEN '8kB' THEN s.setting::bigint * 8192
            WHEN 'kB'  THEN s.setting::bigint * 1024
            WHEN 'MB'  THEN s.setting::bigint * 1024 * 1024
            ELSE NULL
        END
    ) AS actual_value,
    CASE
        WHEN e.expected_value = pg_size_pretty(
            CASE s.unit
                WHEN '8kB' THEN s.setting::bigint * 8192
                WHEN 'kB'  THEN s.setting::bigint * 1024
                WHEN 'MB'  THEN s.setting::bigint * 1024 * 1024
                ELSE NULL
            END
        ) THEN 'OK'
        ELSE 'DRIFT DETECTED'
    END AS status
FROM expected e
JOIN pg_settings s ON s.name = e.param;
```

---

## Cleanup

```sql
DROP FUNCTION IF EXISTS calculate_memory_params(NUMERIC, INT, TEXT);
```

---

## Summary

You have:
- Inventoried current memory settings and compared them to instance RAM
- Built a memory tuning calculator function based on workload type
- Applied calculated values to the parameter group
- Validated shared_buffers with buffer hit ratio
- Validated work_mem with sort spill monitoring
- Separated autovacuum_work_mem from maintenance_work_mem for independent tuning
- Built a monthly audit query to detect parameter drift

The most impactful change for most databases: increasing work_mem from 4MB to 16-64MB eliminates sort spills and makes analytical queries dramatically faster. Do this first, then monitor FreeableMemory to ensure you have not created memory pressure.

---

## Core Concepts Quick Reference

| Parameter | Unit in pg_settings | Formula |
|-----------|--------------------|---------|
| shared_buffers | 8kB pages | 25% of RAM |
| work_mem | kB | (RAM - shared_buffers - 4GB) / (max_connections * 3) |
| maintenance_work_mem | kB | 256MB-2GB depending on workload |
| effective_cache_size | 8kB pages | 75% of RAM (planner hint only) |
| wal_buffers | 8kB pages | -1 (auto-calculated from shared_buffers) |
| autovacuum_work_mem | kB | -1 uses maintenance_work_mem; set explicitly for separate control |

| Term | Meaning |
|------|---------|
| Buffer hit ratio | % of page reads served from shared_buffers (target >99% OLTP) |
| SET LOCAL | Sets parameter for current transaction only, reverts on commit/rollback |
| Swap usage | RAM pages moved to disk - indicates memory pressure, never acceptable on RDS |
| FreeableMemory | CloudWatch metric: RAM available including reclaimable cache |
