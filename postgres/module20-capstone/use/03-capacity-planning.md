# Use 03: Capacity Planning

Analyze your current workload, project growth, and write a capacity plan document. This exercise teaches the methodology production DBAs use to prevent outages before they happen.

---

## Instructions

1. Run each query on your primary server
2. Record the results
3. Calculate projections
4. Write the capacity plan at the end

---

## 1. Current Workload Analysis

### 1.1 Database sizes

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size, pg_database_size(datname) AS bytes FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY bytes DESC;"
```

Record:

| Database | Size | Bytes |
|----------|------|-------|
| | | |
| | | |

### 1.2 Table sizes with indexes

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname || '.' || relname AS table_name, pg_size_pretty(pg_total_relation_size(relid)) AS total, pg_size_pretty(pg_relation_size(relid)) AS data, pg_size_pretty(pg_indexes_size(relid)) AS indexes, n_live_tup AS rows FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC;"
```

Record the top 5 tables:

| Table | Total Size | Data | Indexes | Rows |
|-------|-----------|------|---------|------|
| | | | | |

### 1.3 Transaction rates

```bash
/usr/pgsql-16/bin/psql -c "SELECT datname, xact_commit, xact_rollback, tup_inserted, tup_updated, tup_deleted, tup_fetched FROM pg_stat_database WHERE datname = 'appdb';"
```

Run this command twice, 60 seconds apart. Calculate the per-second rates:

```bash
/usr/pgsql-16/bin/psql -c "SELECT datname, xact_commit AS commits, tup_inserted AS inserts, tup_updated AS updates, tup_deleted AS deletes FROM pg_stat_database WHERE datname = 'appdb';"
```

Wait 60 seconds, then run the same query again. Subtract the first results from the second and divide by 60 to get per-second rates.

Record:

| Metric | Per Second |
|--------|-----------|
| Commits | |
| Inserts | |
| Updates | |
| Deletes | |

### 1.4 Connection usage

```bash
/usr/pgsql-16/bin/psql -c "SELECT count(*) AS total, count(*) FILTER (WHERE state = 'active') AS active, count(*) FILTER (WHERE state = 'idle') AS idle, count(*) FILTER (WHERE state = 'idle in transaction') AS idle_txn, (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max FROM pg_stat_activity;"
```

Record:

| Metric | Count |
|--------|-------|
| Total connections | |
| Active | |
| Idle | |
| Idle in transaction | |
| Max connections | |
| Usage % | |

### 1.5 Cache performance

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT 'table cache' AS type, sum(heap_blks_hit) AS hits, sum(heap_blks_read) AS misses, round(sum(heap_blks_hit)::numeric / greatest(sum(heap_blks_hit) + sum(heap_blks_read), 1) * 100, 2) AS hit_pct FROM pg_statio_user_tables UNION ALL SELECT 'index cache', sum(idx_blks_hit), sum(idx_blks_read), round(sum(idx_blks_hit)::numeric / greatest(sum(idx_blks_hit) + sum(idx_blks_read), 1) * 100, 2) FROM pg_statio_user_indexes;"
```

Record:

| Cache Type | Hit % |
|-----------|-------|
| Table cache | |
| Index cache | |

Target: Both above 99%. Below 95% needs attention.

### 1.6 Top queries by resource consumption

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT queryid, left(query, 50) AS query, calls, round(total_exec_time::numeric / 1000, 1) AS total_sec, round(mean_exec_time::numeric, 1) AS avg_ms, rows, round(shared_blks_hit::numeric / greatest(shared_blks_hit + shared_blks_read, 1) * 100, 1) AS cache_hit_pct FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'appdb') ORDER BY total_exec_time DESC LIMIT 10;"
```

Record the top 3 queries:

| Query (first 50 chars) | Total Time (s) | Avg (ms) | Calls |
|------------------------|----------------|----------|-------|
| | | | |
| | | | |
| | | | |

### 1.7 WAL generation rate

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_current_wal_lsn() AS current_lsn;"
```

Wait 60 seconds:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_current_wal_lsn() AS current_lsn;"
```

Calculate WAL per second:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_wal_lsn_diff('0/XXXXXXX', '0/YYYYYYY') / 60 AS bytes_per_sec;"
```

Replace the LSN values with your two readings.

```bash
exit
```

Record:

| Metric | Value |
|--------|-------|
| WAL bytes/sec | |
| WAL MB/hour | |
| WAL GB/day | |

---

## 2. Growth Projections

### 2.1 Estimate row growth

Based on your insert rate from section 1.3, calculate:

| Period | Inserts | Estimated Data Growth |
|--------|---------|----------------------|
| Per day | inserts/sec x 86400 | |
| Per month | per day x 30 | |
| Per 6 months | per month x 6 | |
| Per year | per month x 12 | |

### 2.2 Estimate storage growth

Take your current database size and project forward:

| Timeframe | Current | +3 months | +6 months | +12 months |
|-----------|---------|-----------|-----------|------------|
| Data | | | | |
| WAL/day | | | | |
| Backups | | | | |
| **Total** | | | | |

### 2.3 Connection growth

| Timeframe | Current | +3 months | +6 months |
|-----------|---------|-----------|-----------|
| Peak connections | | | |
| max_connections | | | |
| Headroom % | | | |

---

## 3. Resource Recommendations

### 3.1 Storage

Based on your projections, answer:

- Current disk usage: ____%
- Projected 6-month usage: ____%
- Action needed? (Yes/No): ____
- Recommended action: ____
- When: ____

### 3.2 Memory

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

```bash
free -h
```

```bash
exit
```

- Current shared_buffers: ____
- Current total RAM: ____
- Cache hit ratio: ____%
- If hit ratio < 99%, recommend increasing shared_buffers to: ____
- If hit ratio < 95%, recommend increasing total RAM to: ____

### 3.3 CPU

Check average CPU utilization from your monitoring (Grafana/Prometheus) or:

```bash
top -bn1 | head -5
```

- Current CPU utilization (avg): ____%
- Current CPU utilization (peak): ____%
- If peak > 70%, recommend adding vCPUs or optimizing queries

### 3.4 Connections

- Current max_connections: ____
- Current peak usage: ____
- pgBouncer max_client_conn: ____
- If usage > 60% of max_connections, recommend: ____

---

## 4. Scaling Recommendations

Based on your analysis, choose the appropriate scaling actions:

### Vertical scaling (bigger server)

- Add RAM if cache hit ratio < 99%
- Add vCPUs if CPU utilization > 70%
- Add disk IOPS if wait events show I/O waits

### Horizontal scaling (more servers)

- Add read replicas if read queries > 60% of total
- Add connection pooler if connection count is high
- Partition large tables if any table > 100GB

### Application optimization

- Add missing indexes if sequential scans dominate
- Optimize top queries if a few queries consume most time
- Implement caching if the same queries repeat frequently

---

## 5. Write the Capacity Plan

Fill in this template:

```
# Capacity Plan: [DATABASE NAME]
# Date: [DATE]
# Author: [YOUR NAME]
# Review period: 6 months

## Current State
- Database size: ____
- Peak connections: ____
- Transaction rate: ____ TPS
- Cache hit ratio: ____%
- Storage used: ____% of ____

## Growth Rate
- Data growth: ____ GB/month
- Connection growth: ____/month
- Transaction growth: ____% per month

## 6-Month Projection
- Projected database size: ____
- Projected peak connections: ____
- Projected storage usage: ____%

## Recommendations
1. [Scaling action 1] - Priority: [High/Medium/Low] - ETA: [date]
2. [Scaling action 2] - Priority: [High/Medium/Low] - ETA: [date]
3. [Scaling action 3] - Priority: [High/Medium/Low] - ETA: [date]

## Budget Impact
- [Cost of recommended changes]

## Next Review
- Date: [6 months from now]
- Trigger for early review: [storage > 80%, connections > 70%, etc.]
```
