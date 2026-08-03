# USE 05 - Establish a Performance Baseline

**Time:** 45 minutes
**Difficulty:** Intermediate
**Prerequisites:** Build 01, 02, 04 complete. pg_stat_statements enabled. Performance Insights enabled.

---

## Objective

Establish a performance baseline for your Aurora cluster that you can use to detect regressions. By the end you will have documented your cluster's normal operating metrics and created a baseline comparison query.

---

## Exercise Tasks

### Task 1 - Capture CloudWatch Baseline Metrics

Collect the current baseline values for key metrics over the past 24 hours:

```bash
METRICS=("CPUUtilization" "DatabaseConnections" "FreeableMemory" "CommitLatency" "BufferCacheHitRatio")

for METRIC in "${METRICS[@]}"; do
    echo "=== $METRIC ==="
    aws cloudwatch get-metric-statistics \
      --namespace "AWS/RDS" \
      --metric-name "$METRIC" \
      --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
      --start-time "$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --period 3600 \
      --statistics Average Maximum Minimum \
      --region "$REGION" \
      --query "sort_by(Datapoints, &Timestamp)[-1].{Avg:Average,Max:Maximum,Min:Minimum}" \
      --output table
    echo ""
done
```

<details>
<summary>Expected output format</summary>

```
=== CPUUtilization ===
------------------------------------
|        GetMetricStatistics       |
+-------+-------+------------------+
|  Avg  |  Max  |       Min        |
+-------+-------+------------------+
|  3.2  |  12.5 |       1.1        |
+-------+-------+------------------+

=== DatabaseConnections ===
...
```
</details>

Fill out this baseline table:

| Metric | Average | Maximum | Minimum | Notes |
|--------|---------|---------|---------|-------|
| CPUUtilization | ___% | ___% | ___% | |
| DatabaseConnections | ___ | ___ | ___ | |
| FreeableMemory | ___GB | ___GB | ___GB | |
| CommitLatency | ___ms | ___ms | ___ms | |
| BufferCacheHitRatio | ___% | ___% | ___% | |

### Task 2 - Capture pg_stat_statements Baseline

Create a baseline snapshot of your top queries:

```sql
CREATE TABLE IF NOT EXISTS perf_baseline (
    snapshot_time TIMESTAMPTZ DEFAULT now(),
    queryid BIGINT,
    query_snippet TEXT,
    calls BIGINT,
    total_exec_time DOUBLE PRECISION,
    mean_exec_time DOUBLE PRECISION,
    stddev_exec_time DOUBLE PRECISION,
    shared_blks_read BIGINT,
    shared_blks_hit BIGINT,
    temp_blks_written BIGINT
);
```

```sql
INSERT INTO perf_baseline (queryid, query_snippet, calls, total_exec_time,
    mean_exec_time, stddev_exec_time, shared_blks_read, shared_blks_hit, temp_blks_written)
SELECT
    queryid,
    left(query, 200),
    calls,
    total_exec_time,
    mean_exec_time,
    stddev_exec_time,
    shared_blks_read,
    shared_blks_hit,
    temp_blks_written
FROM pg_stat_statements
WHERE calls > 10
  AND query NOT LIKE '%pg_stat_statements%'
  AND query NOT LIKE '%perf_baseline%'
ORDER BY total_exec_time DESC
LIMIT 50;
```

Verify the snapshot:

```sql
SELECT count(*) AS queries_captured,
    min(snapshot_time) AS captured_at
FROM perf_baseline;
```

<details>
<summary>Expected output</summary>

```
 queries_captured |         captured_at
------------------+-------------------------------
               50 | 2026-06-09 14:30:00.123456+00
```
</details>

### Task 3 - Create a Regression Detection Query

This query compares current pg_stat_statements data against your baseline:

```sql
CREATE OR REPLACE FUNCTION detect_regressions(threshold_pct NUMERIC DEFAULT 50)
RETURNS TABLE(
    queryid BIGINT,
    query_snippet TEXT,
    baseline_avg_ms NUMERIC,
    current_avg_ms NUMERIC,
    change_pct NUMERIC,
    baseline_calls BIGINT,
    current_calls BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.queryid,
        b.query_snippet,
        round(b.mean_exec_time::numeric, 1),
        round(s.mean_exec_time::numeric, 1),
        round(((s.mean_exec_time - b.mean_exec_time) / nullif(b.mean_exec_time, 0)) * 100, 1),
        b.calls,
        s.calls
    FROM perf_baseline b
    JOIN pg_stat_statements s ON b.queryid = s.queryid
    WHERE s.mean_exec_time > b.mean_exec_time * (1 + threshold_pct / 100.0)
      AND s.calls > 10
    ORDER BY ((s.mean_exec_time - b.mean_exec_time) / nullif(b.mean_exec_time, 0)) DESC;
END;
$$ LANGUAGE plpgsql;
```

Test it (no regressions expected yet):

```sql
SELECT * FROM detect_regressions(50);
```

<details>
<summary>How to use this after a deployment</summary>

1. Before the deployment: take a baseline snapshot (Task 2)
2. Deploy the application changes
3. Wait for 1 hour of production traffic
4. Run: `SELECT * FROM detect_regressions(50);`
5. Any query with > 50% increase in avg_ms is a regression candidate
6. Investigate with EXPLAIN ANALYZE
</details>

### Task 4 - Capture Connection Pattern Baseline

Document your normal connection pattern:

```sql
SELECT
    date_trunc('hour', backend_start) AS hour,
    count(*) AS connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 24;
```

### Task 5 - Document Your Baseline

Fill out and save this document:

```
PERFORMANCE BASELINE - devops-lab-cluster
Captured: [DATE]
Instance class: [INSTANCE_CLASS]
Engine version: [VERSION]

CLOUDWATCH METRICS (24h average):
  CPU Utilization:        ___% (max: ___%)
  Database Connections:   ___ (max: ___)
  Freeable Memory:        ___GB (min: ___GB)
  Commit Latency:         ___ms (max: ___ms)
  Buffer Cache Hit Ratio: ___% (min: ___%)

TOP 5 QUERIES BY TOTAL TIME:
  1. [queryid] ___ms avg, ___ calls
  2. [queryid] ___ms avg, ___ calls
  3. [queryid] ___ms avg, ___ calls
  4. [queryid] ___ms avg, ___ calls
  5. [queryid] ___ms avg, ___ calls

CONNECTION PATTERN:
  Normal connections: ___
  Peak connections:   ___
  Peak time:          ___

NEXT BASELINE REFRESH: [DATE + 30 days]
```

---

## Validation

```sql
-- Verify baseline table exists and has data
SELECT count(*) AS baseline_queries FROM perf_baseline;

-- Verify regression function exists
SELECT proname FROM pg_proc WHERE proname = 'detect_regressions';
```

Both should return results. Your baseline is now established.
