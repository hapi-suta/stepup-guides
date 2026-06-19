# Interview Prep: Monitoring Deep-Dive
# The Voleon Group - Round with Ed Byrne

---

## Interview Quick Reference

- **Interviewer:** Ed Byrne, Sr Systems Infrastructure Engineer
- **Date/Time:** Friday June 26, 5:30-6:30pm EDT
- **Duration:** 60 minutes
- **Focus:** Monitoring Skills (Prometheus, Grafana, Alertmanager, PostgreSQL observability)
- **Context:** Voleon runs PostgreSQL on Ceph RBD, containers, Ansible, Terraform, Jenkins
- **Your angle:** 10+ years, 15,000+ databases across 11 datacenters - you've built monitoring stacks from scratch and maintained them at scale

---

## 15 Likely Questions with Answers

---

### 1. How do you approach monitoring a PostgreSQL cluster? What metrics matter most?

**Answer:**

I think about monitoring in layers. The goal is never to collect everything - it's to answer specific questions fast when something breaks.

My four layers:

1. **Infrastructure** - CPU, memory, disk I/O, network. These tell you if the box is healthy.
2. **Storage** - For bare-metal that's simple disk stats. On Ceph RBD (like Voleon's stack), I also watch RBD-specific metrics like read/write latency per image and OSD performance.
3. **Database engine** - Connections, cache hit ratios, lock waits, vacuum status, replication lag.
4. **Query performance** - Slow query counts, p95/p99 latency, table bloat.

The metrics I consider non-negotiable:

- `pg_up` - is the instance even alive
- Connections used vs `max_connections`
- Replication lag in bytes and seconds
- Cache hit ratio (should stay above 95-99%)
- Transaction rate (TPS) - baseline it so anomalies are visible
- Lock wait events
- Autovacuum activity and dead tuple counts
- Disk usage and growth rate

I've managed databases across AWS, Heroku, Linode, and on-prem simultaneously. The metrics are largely the same; what changes is where storage pressure comes from and what the alert thresholds should be per environment.

---

### 2. Walk me through your Prometheus setup for database monitoring.

**Answer:**

Standard setup I've deployed multiple times:

**Exporters:**
- `postgres_exporter` from Prometheus community - this is the primary one. I pin a specific version, deploy it via Ansible, and manage credentials through environment files (never hardcoded).
- `node_exporter` on every host for OS-level metrics.
- For Ceph environments specifically, I also pull from `ceph_exporter` or use the built-in Ceph Prometheus endpoint, then join those metrics with postgres_exporter data in Grafana.

**Scrape config example structure:**
```yaml
scrape_configs:
  - job_name: 'postgres'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['pg-primary:9187', 'pg-replica:9187']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
```

**Custom queries:** postgres_exporter supports a `queries.yaml` file for metrics Prometheus doesn't expose by default - bloat queries, custom business-level counts, WAL size, etc. I maintain these in version control and deploy them through Ansible the same as any other config.

**Retention:** For a busy database fleet, I set retention at 30 days on the Prometheus server and use Thanos or Cortex for long-term storage if I need trending beyond that.

In containerized environments I use service discovery (Kubernetes SD or Docker SD) rather than static configs, so new instances register automatically.

---

### 3. How do you handle alert fatigue? What's your alerting philosophy?

**Answer:**

Alert fatigue kills teams. I've seen it - engineers start ignoring pages because 80% of them are noise, and then the one that matters gets missed.

My philosophy is: **every alert must require a human decision.** If the right response is always the same automated action, automate it and remove the alert. Only page humans when judgment is needed.

Practical rules I enforce:

1. **No alert without a runbook.** If I can't write a clear runbook for an alert, the alert isn't ready to ship.
2. **Start with high severity only.** On a new system, I'll monitor everything but only alert on P1/P2 items. I add P3/P4 alerts after I've established baselines and know the noise floor.
3. **Use `for` duration in Prometheus rules.** Don't alert the second a threshold is crossed. `for: 5m` on most alerts eliminates a huge amount of transient noise.
4. **Review alert volume monthly.** I track how many times each alert fires. If something fires more than 5 times a month without causing an incident, it needs tuning.
5. **Separate notify from page.** Not everything needs to wake someone up at 2am. Slack notification for warnings, PagerDuty for critical.

I've gone through this tuning exercise at multiple companies. Each time I inherit a monitoring stack, one of the first things I do is pull a 30-day history of alert events and identify the top-10 noisiest alerts. Those get fixed first.

---

### 4. Explain PromQL - rate vs irate, when do you use each?

**Answer:**

Both calculate per-second rate of increase for a counter, but they use different windows.

**`rate()`** calculates the average rate over the entire range provided. It's smoothed out - great for graphs and general trend analysis. If you want to see "how many transactions per second over the last 5 minutes," use rate.

```promql
rate(pg_stat_database_xact_commit_total[5m])
```

**`irate()`** calculates rate using only the last two data points in the range. It's more sensitive to sudden spikes. Use it when you need to see instantaneous peaks - for example, detecting a sudden lock storm or connection spike.

```promql
irate(pg_stat_database_xact_commit_total[5m])
```

**When I use each:**
- Dashboards: `rate()` for readability, `irate()` as a secondary line to show spikes
- Alerts: `rate()` almost always - alerting on irate causes too many false positives from transient blips
- Capacity planning and trending: `rate()` with a longer window (1h or 6h)
- Anomaly detection overlays: `irate()` to highlight deviation from the rate baseline

One gotcha: `irate()` requires at least 3 data points in the range, so if your range is too short relative to your scrape interval, you'll get gaps.

---

### 5. How would you set up monitoring for replication lag? What thresholds?

**Answer:**

Replication lag is one of the most critical metrics in any HA PostgreSQL setup. I monitor it two ways:

**Byte lag** - distance between primary WAL position and replica's replay position:
```promql
pg_replication_slots_confirmed_flush_lsn - pg_current_wal_lsn
```
Or using postgres_exporter's built-in:
```promql
pg_replication_lag
```

**Time lag** - how many seconds behind the replica is, which is more meaningful to the application:
```promql
pg_stat_replication_write_lag_seconds
pg_stat_replication_replay_lag_seconds
```

**Thresholds I use (adjust per SLA):**

| Severity | Byte Lag | Time Lag | Action |
|----------|----------|----------|--------|
| Warning  | > 50MB   | > 30s    | Slack notification |
| Critical | > 200MB  | > 5min   | Page on-call |
| Emergency| > 1GB    | > 15min  | Escalate, consider failover |

On high-write systems, byte lag can spike during bulk loads even when the replica is healthy - I add context to my alerts using the replica's `replay_lag` vs `write_lag` ratio to distinguish "catching up from a batch" vs "genuinely falling behind."

I also monitor the replication slot `pg_replication_slots_active` to detect disconnected replicas holding slots - those accumulate WAL and can fill your disk silently.

---

### 6. Describe your Grafana dashboard strategy - what panels do you put on a DBA dashboard?

**Answer:**

I design dashboards for three different audiences: on-call engineers, DBAs doing daily reviews, and leadership doing capacity reviews. One dashboard rarely serves all three.

**For the DBA operational dashboard, I always include:**

Top row (health at a glance):
- Single-stat: PostgreSQL up/down per instance
- Single-stat: Active connections vs max_connections (color-coded)
- Single-stat: Replication lag (largest lag across all replicas)
- Single-stat: Cache hit ratio

Second row (throughput):
- Time series: TPS (commits + rollbacks) over 24h
- Time series: Read vs write query ratio
- Time series: Lock waits per minute

Third row (storage):
- Time series: Disk usage with a linear forecast overlay
- Time series: WAL generation rate
- Table: Bloat per table (top 10 by wasted space)
- Time series: Autovacuum activity

Fourth row (replication detail):
- Time series: Replication lag per replica
- Table: Replication slot status

Bottom row (query performance):
- Table: Top 10 slow queries by total time (from pg_stat_statements)
- Time series: p95 and p99 query latency

**Design rules I follow:**
- Template variables for instance and database so one dashboard covers the fleet
- Link from the operational dashboard to a drill-down dashboard per instance
- Color consistency: green/yellow/red only for status indicators, not decorative
- 1-hour default time range for operational, 7-day for capacity panels

---

### 7. How do you monitor disk usage and predict when you'll run out of space?

**Answer:**

Disk full is one of those failures that is always predictable and yet still happens all the time. Good monitoring eliminates it.

**What I track:**
- Total disk used vs capacity (from node_exporter `node_filesystem_avail_bytes`)
- WAL directory size separately - WAL can fill a disk faster than data if replication slots are holding things back
- Table and index size growth rate from `pg_database_size()` and `pg_relation_size()`
- On Ceph RBD specifically, I also watch RBD image utilization vs provisioned size

**Prediction with PromQL:**

```promql
predict_linear(node_filesystem_avail_bytes{mountpoint="/var/lib/postgresql"}[6h], 86400 * 7)
```

This uses a 6-hour window to predict free space 7 days from now. If the prediction goes negative, I page. If it goes under 20% within 30 days, I get a warning so there's time to plan expansion without urgency.

**Alert structure I use:**
- Warning: Less than 20% free
- Critical: Less than 10% free OR prediction_linear shows full within 7 days
- Emergency: Less than 5% free

I also use a recording rule to pre-compute the 6h growth rate so the prediction query doesn't hammer Prometheus on every scrape.

At one company managing 500+ databases, I built a capacity report that ran nightly from these metrics and emailed the team a ranked list of "databases most likely to hit storage pressure in the next 30 days." That surfaced problems weeks before they would have hit.

---

### 8. What's your approach to on-call and incident response?

**Answer:**

On-call should be boring. If it's stressful, the monitoring and runbooks aren't good enough.

My framework:

**Before incidents:**
- Every alert has a runbook with: what the alert means, what to check first, what actions to take, when to escalate
- I test runbooks by doing tabletop exercises - talk through a scenario with the team before it happens
- Automation handles the easy stuff (restart a crashed exporter, extend a tablespace) so humans only see the hard problems

**During incidents:**
- I follow a structured triage: Is it a database problem, a storage problem, or an application problem? Many "database incidents" are actually app-level issues.
- I always check replication status first - if a primary is struggling, I need to know if replicas are still viable before I do anything drastic
- I use Grafana's annotations feature to mark when I take actions during incidents, so the timeline is clear in post-mortems

**After incidents:**
- Blameless post-mortem within 48 hours
- Every post-mortem produces at least one monitoring improvement - either a new alert or a better runbook
- I track MTTR and alert-to-resolution time per alert type to spot which alerts need better tooling

I've been the solo on-call DBA covering 15,000+ databases. The only way that's survivable is having automation handle the obvious issues and having runbooks so good that a junior engineer can handle most alerts.

---

### 9. How do you monitor containerized databases differently from bare-metal?

**Answer:**

The metrics you care about don't change, but how you collect them and what additional context you need does.

**Key differences:**

Service discovery: On bare-metal, static scrape configs work fine. In containers, I use Prometheus service discovery - Kubernetes SD, or Docker SD for Docker Compose setups. Pod labels become metric labels, which lets me filter by namespace, deployment, or any tag the platform provides.

Resource limits vs requests: In containers, I monitor not just raw memory usage but memory usage relative to the container limit. A container at 80% of its memory limit is in danger even if the host has plenty of RAM. Same for CPU throttling - `container_cpu_throttled_seconds_total` tells you if the database is getting CPU starved by its cgroup limit.

Ephemeral vs persistent storage: I watch for the distinction between the container's writable layer (ephemeral, small) and mounted persistent volumes. On Ceph RBD, the persistent volume metrics come from the RBD side, not from inside the container, so I monitor both.

Restart tracking: `kube_pod_container_status_restarts_total` tells me if a database container is crash-looping. A database that restarts 3 times in an hour is a database that needs investigation.

Log aggregation: Container logs go to stdout/stderr by default. I send them to a central log aggregator (ELK or Loki) and build log-based alerts for FATAL and PANIC level PostgreSQL messages alongside my metric alerts.

One thing I keep consistent between bare-metal and containers: I still want `pg_up` as the heartbeat. If the exporter can't reach postgres, I want to know immediately regardless of what the container orchestrator thinks.

---

### 10. Explain Alertmanager routing - how do you handle different severity levels?

**Answer:**

Alertmanager routing is a tree - alerts flow down from the root receiver to more specific routes based on label matches.

**Structure I use:**

```yaml
route:
  receiver: 'slack-general'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty-dba'
      continue: false
    - match:
        severity: warning
      receiver: 'slack-dba-alerts'
      continue: false
    - match:
        severity: info
      receiver: 'slack-general'
```

**Key concepts I use heavily:**

`group_by`: I group by `alertname + cluster` so related alerts for the same cluster fire as one notification, not 50 individual pages. During a network partition, you don't want 200 separate alerts for every replica on every cluster.

`inhibit_rules`: If the primary is down (critical), I inhibit all replica lag alerts for that cluster. Replica lag is expected when the primary is gone - paging for it is noise.

```yaml
inhibit_rules:
  - source_match:
      alertname: PostgresPrimaryDown
    target_match:
      alertname: PostgresReplicationLagHigh
    equal: ['cluster']
```

`silences`: For maintenance windows, I create silences via the API (scripted through our deployment pipeline, not manual). They expire automatically so there's no risk of forgetting to re-enable alerts.

`repeat_interval`: I set this higher for warnings (12h) and lower for critical (1h) so critical issues keep paging until they're resolved.

---

### 11. How would you detect and alert on query performance degradation?

**Answer:**

Query performance degradation is harder to alert on than resource metrics because "slow" is relative - a query that takes 5 seconds might be fine for a batch job and catastrophic for a user-facing request.

**My approach:**

Enable `pg_stat_statements` - this is non-negotiable. It gives me total_exec_time, calls, mean_exec_time, stddev_exec_time per query fingerprint.

Track the ratio, not the absolute value:
```promql
rate(pg_stat_statements_total_exec_time_seconds[5m])
  / rate(pg_stat_statements_calls_total[5m])
```

That gives mean execution time per query type. Alert when it exceeds a baseline. I compute the baseline as a recording rule over a 7-day window using `avg_over_time`.

**Lock wait monitoring:**
```promql
rate(pg_stat_activity_wait_event_type[5m]) == "Lock"
```
Spike in lock waits often predicts query slowness before it shows up in exec time.

**Slow query log approach:** I also enable `log_min_duration_statement = 1000` (1 second) in PostgreSQL and ship those logs to a log aggregator. I alert when the rate of slow query log entries exceeds a threshold. This catches long-running queries that are below the exec_time alert threshold in aggregate but still unacceptable individually.

**During incidents,** I use `pg_stat_activity` directly to see what's running:
```sql
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
```

---

### 12. What recording rules do you use and why?

**Answer:**

Recording rules pre-compute expensive queries and store the result as a new metric. They serve two purposes: dashboard performance and alert reliability.

**Rules I always create:**

Disk growth rate (used in prediction):
```yaml
- record: job:node_filesystem_used_bytes:rate6h
  expr: rate(node_filesystem_used_bytes[6h])
```

Transaction rate per database:
```yaml
- record: job:pg_xact_rate:rate5m
  expr: rate(pg_stat_database_xact_commit_total[5m]) + rate(pg_stat_database_xact_rollback_total[5m])
```

Cache hit ratio:
```yaml
- record: job:pg_cache_hit_ratio:5m
  expr: >
    rate(pg_stat_database_blks_hit_total[5m])
    / (rate(pg_stat_database_blks_hit_total[5m]) + rate(pg_stat_database_blks_read_total[5m]))
```

Rollback ratio (elevated rollback rate signals application errors):
```yaml
- record: job:pg_rollback_ratio:5m
  expr: >
    rate(pg_stat_database_xact_rollback_total[5m])
    / (rate(pg_stat_database_xact_commit_total[5m]) + rate(pg_stat_database_xact_rollback_total[5m]))
```

**Why they matter for alerts specifically:** Some Prometheus alert expressions are complex enough that they time out during high-load events - exactly when you need them most. Recording rules ensure the data is pre-computed and available instantly when an alert needs to evaluate.

I also use recording rules for the 7-day baseline of query execution time so I can do relative alerting ("this query is 3x slower than its 7-day baseline") without the alert rule itself doing a massive range query on every evaluation.

---

### 13. How do you handle monitoring during maintenance windows?

**Answer:**

The goal during a maintenance window is: suppress expected alerts so real unexpected issues still surface.

**My process:**

1. Create an Alertmanager silence via the API, scoped to specific alert names and the specific cluster/instance label. I never silence "everything" - that's how you miss a real outage during maintenance.

   ```bash
   amtool silence add \
     --alertmanager.url=http://alertmanager:9093 \
     --duration=2h \
     --comment="Planned maintenance: PostgreSQL upgrade on pg-primary-01" \
     cluster="pg-cluster-a" severity="warning"
   ```

2. Keep critical alerts active even during maintenance. If the cluster is supposed to be up by a certain point and it isn't, I want to know.

3. Use Grafana annotations to mark the start and end of the window. When I review metrics post-maintenance, I can see exactly what changed.

4. Script the silence creation through the deployment pipeline (Jenkins in Voleon's case) so the silence is created and removed automatically as part of the maintenance job - no human forgetting to re-enable alerts.

5. Send a Slack notification to the team when the silence is created and when it expires, so everyone knows what's muted and for how long.

For major version upgrades where the database will be offline and then come back, I also check that `pg_up` comes back to 1 and that replication lag returns to zero as explicit success criteria in the automation.

---

### 14. Describe a time you caught a production issue through monitoring before users noticed.

**Answer (STAR format):**

**Situation:** At a fintech company, we had a high-write PostgreSQL cluster handling payment processing. One evening around 9pm I got a warning alert - replication lag had started climbing on one of our two replicas. Not critical yet, but trending up.

**Task:** I needed to determine if this was a transient blip or a real problem developing, and decide whether to act before it became a user-facing incident.

**Action:** I pulled up Grafana and overlaid three metrics: replication lag, write I/O on the replica host, and autovacuum activity. The autovacuum activity panel showed that autovacuum had kicked off a large vacuum on a heavily-written table at the same time the lag started climbing. The replica was catching up on WAL replays but the vacuum was competing for I/O. I could see the lag was growing faster than a normal vacuum cycle would resolve.

I confirmed that the table had significant bloat by querying pg_stat_user_tables and pg_class. The autovacuum was doing a lot of work that should have been done gradually over the previous weeks - it was a sign that autovacuum was under-tuned for this table's write rate.

I adjusted `autovacuum_vacuum_cost_delay` for that specific table to throttle the vacuum, which allowed the replica to catch up without pausing the vacuum entirely. I also scheduled a manual VACUUM ANALYZE for the next maintenance window.

**Result:** Replication lag peaked at about 90 seconds and came back down to under 1 second over the following 20 minutes. No user impact. The real fix was tuning autovacuum cost parameters for the high-write tables so this wouldn't happen again. The monitoring gave us a 40-minute window to respond before the lag would have hit our critical threshold.

---

### 15. How would you monitor PostgreSQL on Ceph RBD storage? What storage-specific metrics?

**Answer:**

Ceph RBD adds a storage layer between PostgreSQL and physical disks, which means I need to monitor both the database metrics and the storage layer independently - problems can originate in either place and look similar from the database's perspective.

**Ceph-specific metrics I monitor:**

RBD image latency - this is the most important one. High RBD latency translates directly into slow PostgreSQL I/O:
```promql
ceph_rbd_write_latency_sum / ceph_rbd_write_latency_count
ceph_rbd_read_latency_sum / ceph_rbd_read_latency_count
```

OSD utilization and latency - a single overloaded OSD affects all images on it:
```promql
ceph_osd_op_w_latency_sum / ceph_osd_op_w_latency_count
```

Cluster health indicators:
- `ceph_health_status` - alert if this is not 0 (HEALTH_OK)
- OSD count in `up` vs `in` state - a degraded OSD affects I/O
- PG states - degraded or inconsistent placement groups mean reduced throughput and durability

RBD image capacity - RBD images have a fixed provisioned size. If the filesystem inside fills up, PostgreSQL crashes:
```promql
ceph_rbd_used_bytes / ceph_rbd_total_bytes
```

**Correlation approach:** I align the Ceph metrics with PostgreSQL I/O wait metrics from node_exporter (`node_disk_io_time_seconds_total`) in the same Grafana dashboard. When PostgreSQL shows elevated I/O wait, I can immediately see whether it correlates with Ceph OSD latency - which tells me if it's a storage problem or a query/vacuum problem.

**One thing specific to RBD:** Ceph can have a "slow OSD" situation where one OSD in a CRUSH map is degraded and certain images are affected more than others. I tag RBD images with the PostgreSQL cluster name in the monitoring labels so I can quickly see which database clusters are on affected images during a Ceph incident.

---

## STAR Stories (Ready to Use)

---

### Story 1: Catching Replication Lag Before Data Loss

**Situation:** Production PostgreSQL cluster at a data company, streaming replication to two replicas. One replica had been quietly accumulating lag for 3 days - nobody noticed because it wasn't hitting the alert threshold yet.

**Task:** I was doing a routine weekly review of capacity and performance dashboards when I noticed the lag trend graph. Not alarming yet, but the slope was wrong - slowly climbing instead of flat.

**Action:** I investigated and found the replica's `max_wal_senders` slot was holding WAL segments on the primary because the replica had been throttled by a long-running report query that was blocking vacuum on the replica. The replica couldn't replay WAL fast enough because it was in a state where vacuum was blocked, and bloat was growing. I killed the long-running report query on the replica (reports can retry - data loss can't be retried), let vacuum catch up, and tuned the report job to run during lower-traffic hours with a statement timeout.

**Result:** Lag resolved within 20 minutes. The WAL slot on the primary had been accumulating 8GB of WAL that would have eventually filled the primary's pg_wal directory and caused a primary outage. We were maybe 24 hours away from that happening when I caught it.

---

### Story 2: Building a Monitoring Stack from Scratch

**Situation:** Joined a mid-size company where PostgreSQL had zero observability - no exporters, no dashboards, just "check if the service is up" via a ping.

**Task:** Build monitoring for 80+ PostgreSQL instances across three environments in under two weeks before a major product launch.

**Action:** I broke it into phases. Week 1: deploy postgres_exporter and node_exporter via Ansible to all hosts, configure Prometheus scraping, build a minimal dashboard with the 10 most critical metrics, and write alert rules for the absolute non-negotiables (pg_up, connection saturation, replication lag, disk above 80%). Week 2: add pg_stat_statements, build the full DBA dashboard, tune alert thresholds based on observed baselines, write runbooks for each alert.

I used a single parameterized Ansible playbook so adding new instances was a one-line inventory change. I version-controlled all alert rules and dashboard JSON in the same repo as the playbook.

**Result:** Complete monitoring coverage in 11 days. The product launch went smoothly. Two weeks after launch, one of the new alerts - rollback ratio spike - flagged an application bug in a background job that was failing silently. It had been failing for 3 days before monitoring caught it. Without the monitoring, we wouldn't have known until a data discrepancy surfaced.

---

### Story 3: Alert Tuning to Reduce On-Call Fatigue

**Situation:** Inherited an on-call rotation where the team was getting paged an average of 15 times per week, most of which required no action. Morale was bad and engineers were starting to ignore pages.

**Task:** Get the meaningful page rate down without missing real incidents.

**Action:** I pulled 90 days of Alertmanager history and categorized every alert by: did it require action, what action, and how long did resolution take. 70% of pages required no action - they were transient threshold crossings that resolved on their own. The fix was adding `for: 5m` or `for: 10m` to every alert that didn't have it, which filtered out the transient spikes. I also added inhibition rules so that when the primary was down, replica-related alerts were suppressed - those were generating 10-15 related pages per primary incident. Finally, I moved all warning-severity alerts from PagerDuty to Slack. Warnings should inform, not wake people up.

**Result:** Weekly page volume dropped from 15 to 3. Signal quality improved - when a page did come in, engineers knew it was real. Response times improved because engineers trusted the alerts again. Over the following quarter, we had zero missed incidents.

---

## Quick Reference Cheat Sheet

---

### Key PromQL Patterns

```promql
# Replication lag in seconds
pg_replication_lag

# Connection saturation (% of max_connections used)
sum(pg_stat_activity_count) / pg_settings_max_connections * 100

# Cache hit ratio (target: > 0.95)
rate(pg_stat_database_blks_hit_total[5m])
  / (rate(pg_stat_database_blks_hit_total[5m]) + rate(pg_stat_database_blks_read_total[5m]))

# Disk space prediction - days until full
predict_linear(node_filesystem_avail_bytes{mountpoint="/var/lib/postgresql"}[6h], 86400 * 30) < 0

# Rollback ratio - high value signals application errors
rate(pg_stat_database_xact_rollback_total[5m])
  / (rate(pg_stat_database_xact_commit_total[5m]) + rate(pg_stat_database_xact_rollback_total[5m]))

# Dead tuple ratio per table (bloat indicator)
pg_stat_user_tables_n_dead_tup / pg_stat_user_tables_n_live_tup
```

---

### Alertmanager Concepts

**Routing:** Tree structure. Alerts flow from root to the first matching route. Use `continue: true` if you want multiple receivers to get the same alert.

**Grouping:** `group_by` clusters related alerts into one notification. Use `['alertname', 'cluster']` to prevent alert storms.

**Silencing:** Time-boxed suppression of specific alerts by label match. Always set an expiry. Script silences via the API in deployment pipelines.

**Inhibition:** Suppress downstream alerts when an upstream alert is firing. Example: suppress replica lag alerts when the primary is down.

**Repeat interval:** How often to re-notify if an alert is still firing. Set low for critical (1h), high for warning (12-24h).

---

### Grafana Best Practices

- Use template variables for instance and database - one dashboard covers the entire fleet
- Set a consistent color scheme: green = healthy, yellow = warning, red = critical - use it only for status indicators
- Add annotations from your deployment and maintenance pipeline so every change is visible on the timeline
- Link dashboards - top-level overview links to per-instance drill-down, which links to specific metric deep-dives

---

### PostgreSQL Metrics to Always Monitor

1. `pg_up` - instance availability
2. Active connections vs `max_connections`
3. Replication lag (bytes and seconds)
4. Cache hit ratio (blks_hit / (blks_hit + blks_read))
5. Transactions per second (commits + rollbacks)
6. Rollback ratio
7. Lock wait events
8. Autovacuum activity and dead tuple counts
9. Table and database size + growth rate
10. WAL generation rate and replication slot bloat

---

### Common Pitfalls in Monitoring

1. **No `for` duration on alert rules** - leads to constant false positives from transient spikes
2. **Alerting on replicas when the primary is down** - inhibition rules exist for this; not using them causes alert storms
3. **Monitoring the exporter but not the database** - `pg_up` being 1 only means the exporter is running; check actual query metrics
4. **Replication slot accumulation** - slots hold WAL on the primary indefinitely if a replica disconnects; always alert on unused slots
5. **Ignoring autovacuum** - a dead-tuple backlog causes table bloat, slower queries, and eventually transaction ID wraparound; vacuum metrics must be on every DBA dashboard

---

## Questions to Ask Ed

1. "What does your current Prometheus scrape topology look like for the database fleet? Are you running federated Prometheus nodes per datacenter, or centralized collection?"

2. "You're running PostgreSQL on Ceph RBD - are you monitoring the Ceph layer (OSD latency, placement group health) alongside database metrics in the same dashboards, or are those managed by a separate storage team?"

3. "How do you handle monitoring continuity during Kubernetes pod restarts or container rescheduling? If a postgres_exporter pod moves to a different node, does service discovery pick it up automatically, or is there manual work involved?"

4. "What's the current state of your runbooks - are they automated (scripts that run on-alert), documented manual steps, or something in between? And where do they live relative to your alert rule definitions?"

5. "Is the monitoring stack itself (Prometheus, Alertmanager, Grafana) managed through the same Ansible/Terraform pipeline as the rest of infrastructure, or does it have a separate lifecycle?"
