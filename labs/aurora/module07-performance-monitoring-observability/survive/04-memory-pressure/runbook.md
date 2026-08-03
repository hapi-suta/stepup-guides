# Runbook: Memory Pressure

**Scenario:** Multiple sessions are consuming excessive memory through large sort/hash operations, causing FreeableMemory to drop and shared_buffers cache to be evicted.

**Time limit:** 15 minutes
**Severity:** P1 - Performance degradation affecting all users, risk of OOM

---

## Symptoms

- CloudWatch FreeableMemory dropping rapidly
- Enhanced Monitoring shows swap usage increasing
- Performance Insights shows `IO:BufFileRead` and `IO:BufFileWrite` (sort spills to disk)
- Buffer cache hit ratio dropping below 95%
- All queries running slower than normal

---

## Step 1 - Check Memory Status

```sql
SELECT
    name, setting, unit
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size');
```

Check CloudWatch for current FreeableMemory:

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "FreeableMemory" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Average --region "$REGION" \
  --query "sort_by(Datapoints, &Timestamp)[-5:].{Time:Timestamp,MemGB:Average}" --output table
```

---

## Step 2 - Find Memory-Hungry Sessions

```sql
SELECT
    pid,
    usename,
    application_name,
    now() - query_start AS query_duration,
    state,
    wait_event_type,
    wait_event,
    left(query, 100) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND pid != pg_backend_pid()
ORDER BY query_start ASC;
```

Look for sessions with `application_name` like `memory_hog_*` or sessions running large sorts/aggregations.

---

## Step 3 - Check for Temp File Usage

```sql
SELECT
    datname,
    temp_files,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE temp_bytes > 0;
```

Also check pg_stat_statements for queries using temp files:

```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    temp_blks_written,
    round(temp_blks_written::numeric * 8 / 1024 / nullif(calls, 0), 1) AS temp_mb_per_call
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

---

## Step 4 - Kill Memory-Hungry Sessions (Immediate Mitigation)

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name LIKE 'memory_hog%'
  AND pid != pg_backend_pid();
```

If not labeled, kill sessions running the longest active queries:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
  AND pid != pg_backend_pid();
```

---

## Step 5 - Verify Memory is Recovering

Wait 2-3 minutes for OS to reclaim memory, then check:

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "FreeableMemory" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Average --region "$REGION" \
  --query "Datapoints[-1].Average" --output text
```

FreeableMemory should be increasing.

---

## Step 6 - Check Cache Hit Ratio

```sql
SELECT
    sum(heap_blks_hit) AS cache_hits,
    sum(heap_blks_read) AS disk_reads,
    round(sum(heap_blks_hit)::numeric / nullif(sum(heap_blks_hit + heap_blks_read), 0) * 100, 2) AS hit_ratio
FROM pg_statio_user_tables;
```

If the hit ratio is below 95%, the cache was evicted. It will recover as normal queries warm the cache again. This may take 15-30 minutes.

---

## Step 7 - Prevent Recurrence

Set a safe global work_mem:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters "ParameterName=work_mem,ParameterValue=32768,ApplyMethod=immediate" \
  --region "$REGION"
```

`32768` = 32 MB. This is a safe default for most OLTP workloads. Applications that need more should use `SET work_mem = '256MB';` per-session, not globally.

Set statement_timeout to prevent queries from running indefinitely:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters "ParameterName=statement_timeout,ParameterValue=3600000,ApplyMethod=immediate" \
  --region "$REGION"
```

---

## Prevention

1. **Never set work_mem globally above 64MB** - it multiplies per session per sort/hash operation
2. **Use per-session work_mem** for analytical queries: `SET work_mem = '256MB';` then `RESET work_mem;`
3. **Route analytical queries to reader instances** to isolate memory impact
4. **Monitor temp_blks_written** in pg_stat_statements to catch queries that spill
5. **Consider Aurora Optimized Reads** (NVMe instances) for faster temp file I/O

---

## Post-Incident Check

```sql
-- Verify no more memory-hungry sessions
SELECT pid, application_name FROM pg_stat_activity
WHERE application_name LIKE 'memory_hog%';

-- Check current temp file usage
SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database WHERE temp_bytes > 0;

-- Verify cache hit ratio is recovering
SELECT round(sum(heap_blks_hit)::numeric / nullif(sum(heap_blks_hit + heap_blks_read), 0) * 100, 2)
FROM pg_statio_user_tables;
```
