# USE 06 - Memory Parameter Optimization

**Time:** 40 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 12 complete. Custom parameter group applied. `$DB_INSTANCE_ID`, `$REGION` set.

---

## Objective

Given three workload profiles, calculate the correct memory parameters for each, apply them to the parameter group, and validate that the configuration improves buffer hit ratio and eliminates sort spills.

---

## Workload Profiles

You will tune for one of these profiles (your instructor assigns it, or pick based on your database):

**Profile A - OLTP (e-commerce transaction processing)**
- 300 concurrent connections (average)
- 32GB RAM instance (db.r6g.xlarge)
- Mostly point lookups, small updates
- Occasional reporting queries from a read replica

**Profile B - Analytics (data warehouse)**
- 20 concurrent connections
- 64GB RAM instance (db.r6g.2xlarge)
- Large aggregations, sort-heavy GROUP BY queries
- Long-running queries (10-300 seconds each)

**Profile C - Mixed (OLTP + embedded reporting)**
- 100 concurrent connections
- 16GB RAM instance (db.m6g.xlarge)
- Mix of fast OLTP and medium-complexity analytical queries
- Spike to 200 connections during business hours

---

## Task 1 - Document Current State

Run this and record the values:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT name, setting, unit,
    pg_size_pretty(
        CASE unit
            WHEN '8kB' THEN setting::bigint * 8192
            WHEN 'kB'  THEN setting::bigint * 1024
            WHEN 'MB'  THEN setting::bigint * 1048576
            ELSE NULL
        END
    ) AS human_readable
FROM pg_settings
WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem',
               'effective_cache_size','max_connections','wal_buffers',
               'autovacuum_work_mem')
ORDER BY name;"
```

Record the baseline:

| Parameter | Current Value | Your Calculated Value |
|-----------|--------------|----------------------|
| shared_buffers | | |
| work_mem | | |
| maintenance_work_mem | | |
| effective_cache_size | | |
| autovacuum_work_mem | | |

---

## Task 2 - Calculate Target Values

Use the formula from Build 12 or the calculator function:

```sql
-- Run with your profile's values
SELECT * FROM calculate_memory_params(
    32,   -- total_ram_gb (adjust for your profile)
    300,  -- max_connections (adjust for your profile)
    'OLTP' -- workload_type: OLTP, ANALYTICS, or MIXED
);
```

For Profile A (OLTP, 32GB, 300 connections):

| Parameter | Calculation | Value |
|-----------|------------|-------|
| shared_buffers | 32GB * 0.25 | 8GB |
| effective_cache_size | 32GB * 0.75 | 24GB |
| maintenance_work_mem | min(256MB, 32GB * 0.01) | 256MB |
| work_mem | (32 - 8 - 4)GB / (300 * 3) | ~22MB |

For Profile B (Analytics, 64GB, 20 connections):

| Parameter | Calculation | Value |
|-----------|------------|-------|
| shared_buffers | 64GB * 0.25 | 16GB |
| effective_cache_size | 64GB * 0.75 | 48GB |
| maintenance_work_mem | min(2GB, 64GB * 0.05) | 2GB |
| work_mem | (64 - 16 - 4)GB / (20 * 3) | ~733MB |

For Profile C (Mixed, 16GB, 100-200 connections):

| Parameter | Calculation | Value |
|-----------|------------|-------|
| shared_buffers | 16GB * 0.25 | 4GB |
| effective_cache_size | 16GB * 0.75 | 12GB |
| maintenance_work_mem | min(512MB, 16GB * 0.02) | 320MB |
| work_mem | (16 - 4 - 4)GB / (200 * 3) | ~14MB |

---

## Task 3 - Apply the Configuration

Convert to the correct units:

```bash
# Profile A example - adjust values for your profile

# shared_buffers: 8GB in 8kB pages = 8 * 1024 * 1024 / 8 = 1048576
# work_mem: 22MB in kB = 22 * 1024 = 22528
# maintenance_work_mem: 256MB in kB = 256 * 1024 = 262144
# effective_cache_size: 24GB in 8kB pages = 24 * 1024 * 1024 / 8 = 3145728

aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters \
    "ParameterName=shared_buffers,ParameterValue=1048576,ApplyMethod=pending-reboot" \
    "ParameterName=work_mem,ParameterValue=22528,ApplyMethod=immediate" \
    "ParameterName=maintenance_work_mem,ParameterValue=262144,ApplyMethod=immediate" \
    "ParameterName=effective_cache_size,ParameterValue=3145728,ApplyMethod=immediate" \
    "ParameterName=autovacuum_work_mem,ParameterValue=262144,ApplyMethod=immediate" \
  --region "$REGION"
```

Apply the parameters that do not need a reboot:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"

aws rds wait db-instance-available \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

---

## Task 4 - Generate a Workload and Validate

Create a test table:

```sql
CREATE TABLE IF NOT EXISTS memory_test (
    id BIGSERIAL PRIMARY KEY,
    category TEXT NOT NULL,
    value NUMERIC(12,2) NOT NULL,
    tag TEXT NOT NULL,
    data TEXT NOT NULL DEFAULT md5(random()::TEXT)
);

INSERT INTO memory_test (category, value, tag)
SELECT
    'cat_' || (random() * 100)::INT,
    (random() * 10000)::NUMERIC(12,2),
    'tag_' || (random() * 50)::INT
FROM generate_series(1, 2000000);

ANALYZE memory_test;
```

### Validate Buffer Hit Ratio

Run the workload:

```sql
-- Run queries that should be served from cache
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        PERFORM count(*), sum(value) FROM memory_test WHERE category = 'cat_' || (random() * 100)::INT;
    END LOOP;
END $$;
```

Check the hit ratio:

```sql
SELECT
    relname,
    heap_blks_hit,
    heap_blks_read,
    round(heap_blks_hit::numeric / nullif(heap_blks_hit + heap_blks_read, 0) * 100, 2) AS hit_ratio_pct
FROM pg_statio_user_tables
WHERE relname = 'memory_test';
```

Target: > 99% for OLTP, > 95% for analytics (analytics queries scan more data).

### Validate work_mem (No Sort Spills)

Run a sort-heavy query:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT category, tag, sum(value) AS total, count(*) AS cnt
FROM memory_test
GROUP BY category, tag
ORDER BY total DESC
LIMIT 1000;
```

Look at the Sort line in the plan. You want:
```
Sort Method: quicksort  Memory: XXXkB
```

NOT:
```
Sort Method: external merge  Disk: XXXkB
```

If you still see `external merge`, increase work_mem further and re-apply.

### Check temp file usage

```sql
SELECT
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE datname = current_database();
```

After enough queries run, `temp_files` should be 0 (with adequate work_mem).

---

## Task 5 - Memory Pressure Check

Verify the changes have not created memory pressure:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 \
  --statistics Minimum \
  --region "$REGION"
```

The minimum FreeableMemory should be above 10% of total instance RAM. If it drops below that, work_mem is too high and must be reduced.

---

## Task 6 - Write the Configuration Decision Document

Document your decisions (this is what you would present to your team):

```
MEMORY CONFIGURATION DECISION
==============================
Date: [DATE]
Instance: [DB_INSTANCE_ID]
Instance Class: [CLASS]
Total RAM: [X] GB
Workload Type: [TYPE]
Peak Connections: [N]

PARAMETER CHANGES:
Parameter             | Old Value  | New Value  | Reason
----------------------+------------+------------+-------
shared_buffers        |            |            |
work_mem              |            |            |
maintenance_work_mem  |            |            |
effective_cache_size  |            |            |
autovacuum_work_mem   |            |            |

VALIDATION RESULTS:
Buffer hit ratio: ___% (target: >99% OLTP, >95% analytics)
Sort spills: ___ files (target: 0)
FreeableMemory minimum: ___MB (target: >10% of total RAM)

RISKS AND MITIGATIONS:
Risk: work_mem too high with connection spike
Mitigation: RDS Proxy limits connections; work_mem calculated at max_connections

NEXT REVIEW DATE: [DATE + 90 days]
```

---

## Cleanup

```sql
DROP TABLE IF EXISTS memory_test;
DROP FUNCTION IF EXISTS calculate_memory_params(NUMERIC, INT, TEXT);
```
