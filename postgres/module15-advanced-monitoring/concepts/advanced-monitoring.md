# Concepts: Advanced PostgreSQL Monitoring

**Read this before starting the lab.**

---

## Why pg_stat_views Are Not Enough

PostgreSQL ships with a set of system views that show you what is happening right now: `pg_stat_activity` shows current sessions, `pg_stat_bgwriter` shows checkpoint activity, `pg_stat_user_tables` shows vacuum statistics. These views are excellent. Every DBA should know them.

But they have a fundamental problem: they only show you the current moment. You can connect and run `SELECT * FROM pg_stat_activity` and see 12 connections. Is that normal? You have no idea - because you only have the present snapshot.

Production monitoring needs three things that raw system views cannot give you:

1. **Historical data** - what did the connection count look like at 3 AM last Tuesday?
2. **Trends** - is the query response time getting worse over the past two weeks?
3. **Automated alerting** - wake me up when something crosses a threshold, even if I am not watching

The monitoring stack you are about to build adds all three of these on top of PostgreSQL's excellent built-in views.

---

## The Monitoring Stack

Your stack has four layers. Each layer does one job.

```
PostgreSQL
  (produces metrics: pg_stat_activity, pg_stat_statements, etc.)
       |
postgres_exporter
  (translates SQL query results into Prometheus metric format)
       |
Prometheus
  (scrapes, stores, and evaluates time-series data; fires alerts)
       |
Grafana
  (visualizes time-series data; provides dashboards and graphs)
```

Data flows downward: PostgreSQL produces it, postgres_exporter collects it, Prometheus stores it, Grafana displays it.

When something goes wrong, you debug upward: if Grafana shows no data, check Prometheus. If Prometheus shows the target as down, check postgres_exporter. If the exporter is failing, check PostgreSQL.

---

## postgres_exporter: How It Works

postgres_exporter is a small Go program that:

1. Connects to PostgreSQL using a standard connection string (like `postgresql://user:pass@host/db`)
2. On a schedule (every 15 seconds by default), runs a set of SQL queries against PostgreSQL system views
3. Converts the query results into Prometheus's text exposition format
4. Serves those results at `http://localhost:9187/metrics`

The metric format looks like this:

```
# HELP pg_stat_activity_count Number of connections in each state
# TYPE pg_stat_activity_count gauge
pg_stat_activity_count{datname="postgres",state="active"} 2
pg_stat_activity_count{datname="postgres",state="idle"} 5
```

Each line is a metric name, a set of labels (in curly braces), and a value. Labels let you filter and group metrics in Prometheus and Grafana.

The exporter has built-in collectors for most PostgreSQL system views. You can also add custom SQL queries in a `queries.yaml` file for metrics specific to your workload.

The monitoring role needs `pg_monitor` - a built-in PostgreSQL role that grants read access to all monitoring views without superuser access. This is a security improvement over running the exporter as a superuser.

---

## Prometheus: Pull Model and Time Series

Prometheus works differently from most monitoring tools. Instead of your applications pushing data to a central server, Prometheus reaches out and pulls data from each target on a schedule. This is called the pull model.

Why does this matter? If a target stops responding, Prometheus notices immediately because the scrape fails. You do not need the target to report its own failure - Prometheus detects it.

Prometheus stores everything as time-series data. A time series is a sequence of (timestamp, value) pairs for one specific metric and label combination. For example:

```
pg_stat_activity_count{state="active"} at t=1000 = 3
pg_stat_activity_count{state="active"} at t=1015 = 5
pg_stat_activity_count{state="active"} at t=1030 = 4
```

Every 15 seconds, Prometheus appends a new sample to each time series. Over time, this builds a complete history that you can query.

PromQL (Prometheus Query Language) is how you query that history. A few essentials:

**Instant vector** - the current value of a metric:

```
pg_stat_activity_count{state="active"}
```

**Range vector** - values over a time window (used with functions):

```
pg_stat_activity_count{state="active"}[5m]
```

**rate()** - per-second rate of change for counter metrics (metrics that only increase):

```
rate(pg_stat_database_xact_commit[5m])
```

This gives you transactions per second, averaged over 5 minutes.

**sum()** - aggregate across all label combinations:

```
sum(pg_stat_activity_count{state!="idle"}) by (instance)
```

This sums all non-idle connections grouped by server instance.

---

## Grafana: Dashboards, Panels, and Variables

Grafana is the visualization layer. It does not store data - it queries Prometheus and draws the results.

A Grafana **dashboard** is a collection of **panels**. Each panel runs one or more PromQL queries and displays the results as a graph, gauge, table, or stat number.

The important concepts:

**Data sources** - Grafana needs to know how to reach Prometheus. You configure a data source with the Prometheus URL once, and all dashboards use it.

**Time range** - Grafana always queries data for a specific time range (last 1 hour, last 7 days, etc.). You can change the range with the time picker in the top right corner. This lets you go back in time to investigate incidents.

**Variables** - Grafana supports template variables that let you build one dashboard and filter it for different databases, users, or servers using a dropdown. For example, you can have a variable `$datname` that lets you select which database to display metrics for, without duplicating the entire dashboard.

**Annotations** - You can mark specific moments on graphs (like "we deployed version 2.3" or "pgbench ran for 10 minutes") to correlate events with metric changes.

---

## Alerting Philosophy: What to Alert On

Not everything should be an alert. Here is the distinction:

**Alert on conditions that require a human to act right now.** Examples: the database is unreachable, disk is about to fill up, replication lag is growing uncontrollably. These need immediate attention at any hour.

**Dashboard everything else.** Examples: query count per second, cache hit ratio trend, table growth rate. These are useful for investigations and capacity planning, but they do not need to wake anyone up at 2 AM.

A common mistake is alerting on everything that is "interesting." This leads to alert fatigue - when you get 200 alerts per day, you start ignoring all of them. When a real emergency happens, it gets lost in the noise.

The rule: if the on-call person cannot take a specific action within 5 minutes of receiving the alert, the alert should be a dashboard panel, not an alert.

---

## Common PostgreSQL Metrics to Monitor

Here are the metrics you should track in production and why each matters:

**Connection count by state**
- Metric: `pg_stat_activity_count{state="..."}`
- Why: Connection exhaustion (`max_connections` hit) causes immediate application failures with no warning. Tracking idle-in-transaction separately catches connection leaks.

**Cache hit ratio**
- Metric: `pg_stat_database_blks_hit` / (`blks_hit` + `pg_stat_database_blks_read`)
- Why: If your data fits in `shared_buffers`, most queries run entirely from memory. A sudden drop in cache hit ratio means a new query is doing sequential scans, possibly a missing index.

**Transaction rate**
- Metric: `rate(pg_stat_database_xact_commit[5m])`
- Why: Your baseline TPS tells you what normal looks like. A sudden drop could indicate application errors. A sudden spike could indicate a runaway process.

**Replication lag**
- Metric: `pg_replication_lag`
- Why: If a standby falls too far behind the primary, it cannot serve as a failover target. Most RPO requirements have a maximum acceptable lag.

**WAL generation rate**
- Metric: Derived from `pg_stat_bgwriter_buffers_checkpoint`
- Why: High WAL generation drives high disk I/O, faster WAL archive storage consumption, and higher replication bandwidth costs.

**Table and index bloat**
- Metric: `n_dead_tup` from `pg_stat_user_tables`
- Why: PostgreSQL uses MVCC (Multi-Version Concurrency Control). Deleted and updated rows leave dead tuples behind until VACUUM cleans them up. High dead tuple counts mean VACUUM is not keeping up, causing table bloat and slower sequential scans.

**Long-running queries and idle-in-transaction sessions**
- Metric: `pg_stat_activity_max_tx_duration`
- Why: Long transactions hold locks. Locks block other work. One stuck transaction can cascade into dozens of blocked sessions within minutes.

**Checkpoint write time**
- Metric: `pg_stat_bgwriter_checkpoint_write_time`
- Why: Slow checkpoints indicate I/O bottlenecks. They also mean PostgreSQL needs to write more WAL before the next checkpoint, increasing crash recovery time.

**Sequence exhaustion**
- Metric: Custom query against `pg_sequences`
- Why: Integer sequences have a maximum value. When a sequence exhausts its range, inserts fail with an error. This is easy to prevent and catastrophic to fix under pressure.

---

## Before You Start the Lab

Make sure you understand these terms before you start the build guides. You will use all of them:

- **Scrape** - Prometheus pulling metrics from a target
- **Time series** - a sequence of timestamped metric values
- **Label** - a key=value pair that identifies a dimension of a metric
- **Gauge** - a metric that can go up or down (connection count, cache hit ratio)
- **Counter** - a metric that only goes up (transaction count, bytes written)
- **rate()** - PromQL function that computes per-second rate of change for counters
- **Alert** - a PromQL condition that, when true for a duration, is marked as FIRING
- **Exporter** - a program that translates some system's data into Prometheus format
- **Dashboard** - a collection of Grafana panels that displays related metrics together

Now start with Build Guide 01.
