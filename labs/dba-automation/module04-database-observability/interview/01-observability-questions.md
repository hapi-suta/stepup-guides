# Interview Questions: Database Observability

**Module 04 - Database Observability**
**5 questions covering Prometheus, metrics, alerting, SLOs, and troubleshooting**

---

## Question 1: Top 5 PostgreSQL Metrics

**Question:** What are the top 5 PostgreSQL metrics you would monitor and why?

**What they are looking for:** Prioritization ability. Can the candidate focus on what matters, or do they list every metric they have heard of?

**Strong Answer:**

My top 5, in priority order:

**1. Connection utilization (current connections / max_connections)**
Why first: If connections are exhausted, the database is completely unavailable. No new clients can connect. This is the most common cause of "database is down" pages that are not actual crashes. I set warning at 80% and critical at 90%.

**2. Replication lag (seconds or bytes behind primary)**
Why second: If lag exceeds your tolerance, replicas serve stale data. For applications routing reads to replicas, this means users see outdated information - or worse, read-after-write failures. I typically alert at 30 seconds for async replicas.

**3. Cache hit ratio (buffer cache hits / total reads)**
Why third: This is the single best indicator of whether the database has enough memory. A healthy PostgreSQL instance should have a cache hit ratio above 99% for OLTP workloads. Below 95%, the database is doing excessive disk I/O and queries slow down. This drives decisions about shared_buffers sizing and instance right-sizing.

**4. Transaction rate and rollback ratio**
Why fourth: Transactions per second is my baseline for "normal." If TPS drops suddenly, something is wrong (locks, resource contention). If rollback ratio spikes above 5%, the application is failing - usually a deployment issue or a schema change that broke queries.

**5. Dead tuple ratio and vacuum lag**
Why fifth: Dead tuples accumulate from updates and deletes. If autovacuum falls behind (table bloat exceeds 10%), tables grow, sequential scans slow down, and index performance degrades. I have seen tables grow 5x their logical size from vacuum neglect. This is a slow-burn issue that becomes critical if ignored.

**Honorable mentions:** Disk space (should be monitored at the OS level), long-running transactions (hold locks and block vacuum), and deadlock rate.

---

## Question 2: Counter vs Gauge in Prometheus

**Question:** Explain the difference between a counter and a gauge in Prometheus. Give a PostgreSQL example of each and explain how you would query them differently.

**Strong Answer:**

A **counter** is a metric that only goes up. It represents a cumulative total that resets to zero on restart. The raw value is rarely useful - you care about the rate of change.

A **gauge** is a metric that can go up or down. It represents a current value at a point in time. The raw value IS the useful number.

**PostgreSQL examples:**

Counter: `pg_stat_database_xact_commit` - the total number of committed transactions since the server started. If the value is 5,000,000, that is not meaningful on its own. What matters is "how many per second right now?"

```promql
# CORRECT: per-second commit rate over 5 minutes
rate(pg_stat_database_xact_commit[5m])

# WRONG: raw counter value (meaningless for operational decisions)
pg_stat_database_xact_commit
```

Gauge: `pg_stat_activity_count` - the current number of connections. If the value is 85, that IS meaningful - it tells me how many clients are connected right now.

```promql
# CORRECT: raw gauge value
pg_stat_activity_count{state="active"}

# ALSO USEFUL: change over time
delta(pg_stat_activity_count[1h])
```

**The critical mistake to avoid:** Using `rate()` on a gauge or reading a counter without `rate()`. If you graph a counter directly, you see a line that only goes up forever - that is not useful. If you use `rate()` on a gauge like connection count, you get the rate of change of connections, which is rarely what you want.

One subtlety: when a counter resets (server restart), `rate()` handles this automatically. It detects the reset and calculates the rate correctly across the discontinuity. This is built into Prometheus and is one reason counters are preferred over gauges for cumulative metrics.

---

## Question 3: Preventing Alert Fatigue

**Question:** How do you prevent alert fatigue in a database monitoring setup?

**Strong Answer:**

Alert fatigue is when the on-call person receives so many alerts that they stop paying attention, and then a real critical alert gets missed. I have seen teams with 50+ alerts per day that never investigate any of them. This is dangerous.

My approach has four layers:

**1. Every alert must have an actionable response**

If there is no clear action to take when an alert fires, it should not be an alert. "CPU is at 40%" is not actionable. "CPU has been above 90% for 15 minutes - investigate top queries and consider scaling" is actionable. I review every alert rule with the question: "If this wakes me up at 3 AM, what specifically will I do?"

**2. Use severity levels strictly**

Critical alerts page someone and should fire fewer than once per week. If critical alerts fire daily, either the threshold is wrong or you have a systemic problem to fix.

Warning alerts go to Slack or email and are reviewed during business hours. They should not page anyone.

Info-level "alerts" are dashboard indicators only - no notification.

**3. Use Alertmanager features to reduce noise**

- **Grouping** (`group_by: ['instance', 'alertname']`): If 50 tables all have high dead tuples, send one notification, not 50
- **Inhibition**: If the server is down, suppress all other alerts for that server. The "server down" alert is sufficient.
- **Deduplication**: Alertmanager automatically deduplicates repeated firings
- **`for` duration**: Set it to at least 5 minutes for most alerts. This filters out transient spikes that resolve on their own.

**4. Quarterly alert review**

Every quarter, I pull alert history and ask:
- Which alerts fired but were never investigated? Remove or fix them.
- Which alerts fire and self-resolve repeatedly? Increase the `for` duration or raise the threshold.
- Which real incidents were NOT caught by an alert? Add new alerts.
- Has the team's response time degraded? That is a sign of fatigue.

**A good target:** Fewer than 5 alerts per on-call shift. If you are above that, your alerting needs tuning before it needs more coverage.

---

## Question 4: SLOs for PostgreSQL

**Question:** What is an SLO and how would you define one for a PostgreSQL database?

**Strong Answer:**

An SLO - Service Level Objective - is a target for how well a service should perform, measured over a time window. It takes a measurable metric (the SLI, or Service Level Indicator) and sets a percentage target.

For a production PostgreSQL database, I would define three SLOs:

**1. Availability SLO: 99.9% over 30 days**

SLI: Percentage of health checks that return successfully.
Measurement: Prometheus `up` metric combined with a synthetic query check (run `SELECT 1` every 10 seconds).
Error budget: 43 minutes per month.

This means I can have roughly 43 minutes of total downtime per month - planned or unplanned. A typical failover takes 30-120 seconds, so I can have multiple failovers and still meet this.

**2. Latency SLO: 99% of queries complete in under 100ms, measured over 30 days**

SLI: p99 query execution time from pg_stat_statements.
Measurement: `histogram_quantile(0.99, rate(query_duration_bucket[5m]))` if using histogram metrics, or sampling from pg_stat_statements.
Error budget: 1% of queries can exceed 100ms.

This allows for some slow queries during peak load or vacuum activity without violating the SLO.

**3. Data freshness SLO: Replica lag under 10 seconds 99.5% of the time**

SLI: Replication lag in seconds.
Measurement: `pg_replication_lag` from postgres_exporter.
Error budget: Replicas can lag more than 10 seconds for up to 3.6 hours per month.

**How I use these in practice:**

I track error budget consumption weekly. If we have consumed 50% of the budget by mid-month, we slow down deployments and focus on reliability. If we are at 80%, we freeze non-essential changes. This gives engineering teams a concrete, data-driven way to balance feature velocity against reliability.

The SLO also drives infrastructure decisions. If we are consistently close to breaching the availability SLO, that justifies investment in better HA (Aurora over RDS, for example) or additional replicas.

---

## Question 5: High CPU, Low Query Activity

**Question:** Your Grafana dashboard shows high CPU but low query activity on a PostgreSQL instance. What could cause this?

**Strong Answer:**

This is a classic mismatch that has several possible explanations. I would investigate in this order:

**1. Autovacuum running aggressively**

Autovacuum uses CPU but does not show up as "query activity" in many monitoring dashboards that only count user queries. Check `pg_stat_progress_vacuum` and `pg_stat_activity` filtered by `backend_type = 'autovacuum worker'`. If a large table just received millions of updates, autovacuum could be consuming significant CPU.

**2. Checkpointing**

A checkpoint flushes dirty buffers from shared_buffers to disk. This is CPU and I/O intensive. If `checkpoint_completion_target` is too low or checkpoints are happening too frequently (check `pg_stat_bgwriter.checkpoints_req`), CPU will spike without corresponding query activity.

**3. Background processes**

WAL writer, background writer, and logical replication workers all consume CPU but are not user queries. If you have logical replication decoding large transactions, the CPU for decoding shows up as PostgreSQL process CPU.

**4. Monitoring tool misconfiguration**

Similar to the "dashboard that lied" scenario - the monitoring might be measuring query activity from the wrong server. If postgres_exporter is connected to a replica but CPU metrics come from the primary (via node_exporter or CloudWatch), you see primary CPU but replica query counts.

**5. Connection churn**

If the application is rapidly connecting and disconnecting (no connection pooling), the CPU cost of establishing and tearing down SSL/TLS connections and PostgreSQL backend processes is significant. The connections are too short-lived to show up as "active" in periodic scrapes. Check `pg_stat_database.sessions` if available (PostgreSQL 14+).

**6. Extension or trigger overhead**

If triggers fire on DML but the triggering DML is fast and counted as one query, the trigger execution could consume CPU that does not show as separate query activity. Same with row-level security policies that require complex evaluation.

**My investigation steps:**
1. Check `pg_stat_activity` for non-user processes (autovacuum, WAL, replication)
2. Check `pg_stat_bgwriter` for checkpoint frequency
3. Run `top` or check Enhanced Monitoring for which PostgreSQL processes consume CPU
4. Verify the monitoring tool is connected to the right server
5. Check for connection churn in pg_stat_database
