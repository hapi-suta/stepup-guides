# Use Exercise 05 - Capacity Planning Report

**Module:** 15 - Advanced Monitoring
**Estimated Time:** 45 minutes
**Prerequisite:** Build Guides 02-04 complete, at least 2 hours of metric data collected

---

## Objective

Use Prometheus data and PromQL to answer the questions a capacity planning report must answer: how fast is your database growing, when will you run out of connections, when will you run out of disk, and where are the performance bottlenecks?

You will produce a written capacity planning report based on real data from your monitoring stack.

---

## Background

Capacity planning is proactive work. Instead of reacting to "the database is full," you use trends to predict when resources will be exhausted - before it happens. A good capacity planning report answers:

1. Storage: how fast is data growing, and when will we run out?
2. Connections: how close are we to max_connections at peak load?
3. Performance: is query response time trending up or down?
4. WAL: how much write activity are we generating?
5. Vacuum: are tables staying clean or accumulating bloat?

---

## Part 1 - Generate sustained workload for trend data

Log in to pg-primary.

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

Start a sustained pgbench workload for 10 minutes in the background.

```bash
sudo -u postgres /usr/pgsql-16/bin/pgbench -c 8 -T 600 -d stepup_store &
```

While that runs, proceed to the queries below.

---

## Part 2 - Transaction rate over time

Open Prometheus at `http://<your-server-ip>:9090/graph`.

**Query 1 - Commit rate (transactions per second, 5-minute average):**

```
rate(pg_stat_database_xact_commit{datname="stepup_store"}[5m])
```

Run this query. In the Graph tab, set the time range to "Last 30 minutes."

**Record in your report:**
- Current commit rate: ___ TPS
- Peak commit rate during the lab: ___ TPS
- Average commit rate: ___ TPS

---

## Part 3 - Connection utilization trend

**Query 2 - Connection utilization percentage:**

```
100 * sum(pg_stat_activity_count{job="postgres"}) / pg_settings_max_connections{job="postgres"}
```

**Record in your report:**
- Current connection utilization: ___%
- Peak utilization: ___%
- Projected time to 85% utilization at current growth: ___

---

## Part 4 - Database size growth

**Query 3 - Database size in bytes:**

```
pg_database_size_bytes{datname="stepup_store"}
```

**Query 4 - Rate of size growth (bytes per second, averaged over 1 hour):**

```
rate(pg_database_size_bytes{datname="stepup_store"}[1h])
```

This requires at least 1 hour of data to produce a meaningful result. If you have less than 1 hour, use:

```
rate(pg_database_size_bytes{datname="stepup_store"}[10m])
```

**Record in your report:**
- Current database size: ___ MB
- Growth rate: ___ bytes/second
- Projected size in 30 days: ___ MB
- Projected size in 1 year: ___ GB

To calculate 30-day projection: `current_bytes + (growth_rate * 86400 * 30)`

---

## Part 5 - Cache hit ratio trend

**Query 5 - Cache hit ratio over 5-minute windows:**

```
100 * sum(rate(pg_stat_database_blks_hit{datname="stepup_store"}[5m])) /
(
  sum(rate(pg_stat_database_blks_hit{datname="stepup_store"}[5m])) +
  sum(rate(pg_stat_database_blks_read{datname="stepup_store"}[5m]))
)
```

**Record in your report:**
- Average cache hit ratio: ___%
- Minimum cache hit ratio observed: ___%
- Is the ratio stable or degrading over time? ___

---

## Part 6 - WAL generation rate

**Query 6 - WAL bytes written per second:**

```
rate(pg_stat_bgwriter_buffers_checkpoint[5m]) * 8192
```

This converts buffer blocks to bytes (each block is 8KB).

**Record in your report:**
- Current WAL generation rate: ___ MB/second
- Projected WAL volume per day: ___ GB/day
- At this rate, how long will 100GB of WAL storage last? ___

---

## Part 7 - Checkpoint frequency

**Query 7 - Checkpoints per minute:**

```
rate(pg_stat_bgwriter_checkpoints_timed[5m]) * 60
```

**Query 8 - Checkpoint write time (ms per checkpoint):**

```
rate(pg_stat_bgwriter_checkpoint_write_time[5m]) /
rate(pg_stat_bgwriter_checkpoints_timed[5m])
```

Checkpoints that take more than 30 seconds indicate I/O bottlenecks.

**Record in your report:**
- Checkpoints per minute: ___
- Average checkpoint write time: ___ ms
- Is checkpoint_completion_target being met? (write_time should be < 90% of checkpoint_interval)

---

## Part 8 - Tuple operation rates

**Query 9 - Insert, update, delete rates:**

```
rate(pg_stat_database_tup_inserted{datname="stepup_store"}[5m])
```

```
rate(pg_stat_database_tup_updated{datname="stepup_store"}[5m])
```

```
rate(pg_stat_database_tup_deleted{datname="stepup_store"}[5m])
```

**Record in your report:**
- Insert rate: ___ rows/second
- Update rate: ___ rows/second
- Delete rate: ___ rows/second
- Write amplification (updates are expensive - what % of DML is updates?): ___%

---

## Part 9 - Check pg_stat_statements for top queries

Switch to the postgres user and run the top-queries report.

```bash
sudo -i -u postgres
```

```bash
psql -d stepup_store -c "
SELECT
  round(total_exec_time::numeric, 0) AS total_ms,
  calls,
  round(mean_exec_time::numeric, 2)  AS mean_ms,
  round(100.0 * total_exec_time / sum(total_exec_time) OVER (), 2) AS pct_of_total,
  left(query, 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;"
```

**Record in your report:**
- Top query by total time: ___
- Its share of total database time: ___%
- Is there a single query dominating execution time? ___

```bash
exit
```

---

## Part 10 - Write the capacity planning report

Using the data you collected, write a capacity planning report in the format below. This is a real deliverable you would produce for a client or your manager.

---

### Capacity Planning Report Template

**Database:** stepup_store on pg-primary
**Report Date:** [today's date]
**Report Period:** [time range of data]
**Prepared by:** [your name]

---

#### Executive Summary

[2-3 sentences. Example: "The stepup_store database is healthy and growing at a sustainable rate. At current growth, no resources are projected to be exhausted in the next 6 months. The primary optimization opportunity is query X, which accounts for Y% of total database time."]

---

#### Current Resource Utilization

| Resource | Current | Trend | Projected (30 days) | Limit | Time to Limit |
|---|---|---|---|---|---|
| Database size | ___ MB | +___ MB/day | ___ MB | ___ GB available | ___ days |
| Connections | ___% | stable/growing | ___% | 100% (max_connections) | ___ days |
| WAL generation | ___ MB/s | stable/growing | ___ GB/day | storage dependent | ___ days |

---

#### Performance Metrics

| Metric | Value | Threshold | Status |
|---|---|---|---|
| Cache hit ratio | ___% | > 99% | OK / WARNING |
| Avg commit rate | ___ TPS | - | informational |
| Checkpoint write time | ___ ms | < 30,000ms | OK / WARNING |
| Top query mean time | ___ ms | < 100ms | OK / WARNING |

---

#### Top Findings

1. [Finding 1 - e.g., cache hit ratio is below target, recommend increasing shared_buffers]
2. [Finding 2 - e.g., one query accounts for 40% of execution time, recommend adding index]
3. [Finding 3 - e.g., WAL generation is high due to frequent updates, review update patterns]

---

#### Recommendations

| Priority | Recommendation | Expected Impact | Effort |
|---|---|---|---|
| High | [recommendation] | [impact] | Low/Medium/High |
| Medium | [recommendation] | [impact] | Low/Medium/High |
| Low | [recommendation] | [impact] | Low/Medium/High |

---

#### Next Review Date

[30 days from today, or sooner if any metric approaches a warning threshold]

---

## Reflection Questions

1. Why do you use `rate()` in PromQL when measuring transaction counts or block reads instead of querying the raw counter value?
2. If cache hit ratio is 97%, is that good or bad? What additional information would you need to decide?
3. A DBA presents a report showing "no resources will be exhausted in the next 6 months." What questions should you ask to validate that conclusion?
4. Why is it useful to track the `pct_of_total` for top queries in pg_stat_statements?
5. What is the relationship between WAL generation rate and your backup storage requirements?
