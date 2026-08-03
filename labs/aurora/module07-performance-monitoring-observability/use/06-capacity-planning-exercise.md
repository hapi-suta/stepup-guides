# USE 06 - Capacity Planning Exercise

**Time:** 40 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 01, 02 complete. Performance Insights and Enhanced Monitoring enabled. At least 24 hours of metric data available.

---

## Objective

Analyze your Aurora cluster's resource consumption trends and determine when you will need to scale. By the end you will have a capacity forecast for CPU, connections, storage, and memory.

---

## Exercise Tasks

### Task 1 - Analyze CPU Trend

Get the CPU utilization trend over the past 7 days (or whatever data is available):

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "CPUUtilization" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 86400 \
  --statistics Average Maximum \
  --region "$REGION" \
  --query "sort_by(Datapoints, &Timestamp)[].{Date:Timestamp,AvgCPU:Average,MaxCPU:Maximum}" \
  --output table
```

`--period 86400`: One data point per day (86400 seconds = 24 hours).

<details>
<summary>Expected output format</summary>

```
------------------------------------------------------
|              GetMetricStatistics                   |
+-----------+---------------------------+------------+
| AvgCPU    |          Date             |  MaxCPU    |
+-----------+---------------------------+------------+
|  3.2      |  2026-06-03T00:00:00+00:00|  15.5      |
|  4.1      |  2026-06-04T00:00:00+00:00|  22.3      |
|  3.8      |  2026-06-05T00:00:00+00:00|  18.7      |
...
```
</details>

Fill out this CPU planning table:

| Day | Avg CPU | Max CPU | Trend |
|-----|---------|---------|-------|
| Day 1 | ___% | ___% | - |
| Day 2 | ___% | ___% | Up/Down/Stable |
| Day 3 | ___% | ___% | Up/Down/Stable |
| ... | | | |

**Decision point:** If your average CPU is above 60% or max CPU regularly exceeds 80%, it is time to plan an instance upgrade.

### Task 2 - Analyze Storage Growth

For Aurora, check the volume growth:

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "VolumeBytesUsed" \
  --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_ID" \
  --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 86400 \
  --statistics Average \
  --region "$REGION" \
  --query "sort_by(Datapoints, &Timestamp)[].{Date:Timestamp,SizeGB:Average}" \
  --output table
```

Note: VolumeBytesUsed is in bytes. Divide by 1073741824 (1024^3) to get GB.

<details>
<summary>Calculating days until storage limit</summary>

Aurora storage automatically scales up to 128 TB. However, storage costs money, so you want to predict growth:

```
Growth rate = (Current size - Size 7 days ago) / 7 days
Days to 1 TB = (1 TB - Current size) / Growth rate per day
Days to 10 TB = (10 TB - Current size) / Growth rate per day
```
</details>

Also check database-level sizes inside PostgreSQL:

```sql
SELECT
    datname,
    pg_size_pretty(pg_database_size(datname)) AS size,
    pg_database_size(datname) AS size_bytes
FROM pg_database
WHERE datname NOT LIKE 'template%'
ORDER BY size_bytes DESC;
```

And table-level sizes for the largest tables:

```sql
SELECT
    schemaname || '.' || relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS data_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
    n_live_tup AS estimated_rows
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 15;
```

### Task 3 - Analyze Connection Utilization

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "DatabaseConnections" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 3600 \
  --statistics Average Maximum \
  --region "$REGION" \
  --query "sort_by(Datapoints, &Timestamp)[-24:].{Hour:Timestamp,AvgConn:Average,MaxConn:Maximum}" \
  --output table
```

Get your max_connections setting:

```sql
SHOW max_connections;
```

Calculate connection utilization:

```
Peak connections / max_connections * 100 = utilization %

If utilization > 60%: consider deploying RDS Proxy or PgBouncer
If utilization > 80%: deploy a connection pooler before scaling
```

<details>
<summary>Connection planning decision tree</summary>

```
Current peak connections
    |
    +-- < 40% of max_connections
    |       No action needed. Monitor trend.
    |
    +-- 40-60% of max_connections
    |       Plan connection pooler deployment
    |
    +-- 60-80% of max_connections
    |       Deploy connection pooler NOW
    |       Set idle_session_timeout
    |
    +-- > 80% of max_connections
            Deploy connection pooler IMMEDIATELY
            Consider instance upgrade for more max_connections
```
</details>

### Task 4 - Analyze Memory Pressure

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "FreeableMemory" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 3600 \
  --statistics Average Minimum \
  --region "$REGION" \
  --query "sort_by(Datapoints, &Timestamp)[-24:].{Hour:Timestamp,AvgMem:Average,MinMem:Minimum}" \
  --output table
```

Check cache hit ratio:

```sql
SELECT
    sum(heap_blks_hit) AS cache_hits,
    sum(heap_blks_read) AS disk_reads,
    round(sum(heap_blks_hit)::numeric / nullif(sum(heap_blks_hit + heap_blks_read), 0) * 100, 2) AS hit_ratio
FROM pg_statio_user_tables;
```

<details>
<summary>Memory planning decision tree</summary>

```
Cache hit ratio
    |
    +-- > 99%: Working set fits in memory. No action needed.
    |
    +-- 95-99%: Monitor. May need larger instance if trend is downward.
    |
    +-- < 95%: Working set exceeds shared_buffers.
              Options:
              1. Upgrade instance (more RAM = larger shared_buffers)
              2. Add indexes to reduce data scanned
              3. Use Aurora Optimized Reads (NVMe tiered cache)
              4. Partition large tables
```
</details>

### Task 5 - Write the Capacity Plan

Fill out this capacity planning document:

```
CAPACITY PLAN - devops-lab-cluster
Date: [DATE]
Instance class: [CLASS]
Review frequency: Monthly

CPU:
  Current avg: ___%, Current max: ___%, Trend: Up/Down/Stable
  Upgrade trigger: Max CPU > 80% sustained
  Upgrade path: [current class] -> [next class]
  Estimated upgrade date: [DATE or "Not needed within 6 months"]

STORAGE:
  Current size: ___GB, Growth rate: ___GB/month
  Estimated 1 TB date: [DATE or "Not applicable"]
  Cost optimization: [ ] Switch to I/O-Optimized if I/O > 25% of storage cost

CONNECTIONS:
  Current peak: ___, max_connections: ___, Utilization: ___%
  Connection pooler: [ ] Deployed  [ ] Planned  [ ] Not needed
  Upgrade trigger: Peak > 60% of max

MEMORY:
  Cache hit ratio: ___%, FreeableMemory min: ___GB
  Upgrade trigger: Cache hit ratio < 95%
  Upgrade path: [current class] -> [next class]

NEXT REVIEW: [DATE + 30 days]
```

---

## Validation

Confirm you have:
- [ ] CPU trend data for the past 7 days
- [ ] Storage growth rate calculated
- [ ] Connection utilization percentage calculated
- [ ] Cache hit ratio measured
- [ ] Capacity plan document filled out
