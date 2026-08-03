# USE: Observability Exercises

**Module 04 - Database Observability**
**Prerequisites:** Completed BUILD 01 through BUILD 04, all services running (Prometheus, postgres_exporter, Grafana)

Each exercise builds on the previous one. Complete them in order.

---

## Exercise 1: Prometheus Setup and Verification

**Objective:** Ensure Prometheus is correctly scraping postgres_exporter and verify you can query PostgreSQL metrics.

**Tasks:**

1. Verify all services are running:
   - Prometheus at http://localhost:9090
   - postgres_exporter at http://localhost:9187/metrics
   - Grafana at http://localhost:3000

2. Go to Prometheus Targets page (http://localhost:9090/targets) and confirm:
   - `prometheus` target is UP
   - `postgresql` target is UP

3. In the Prometheus expression browser, run these queries and record the results:

   ```promql
   # How many databases exist?
   count(pg_database_size_bytes)

   # What is the total size of all databases?
   sum(pg_database_size_bytes)

   # How many active connections right now?
   sum(pg_stat_activity_count{state="active"})

   # Transaction commit rate (per second)
   sum(rate(pg_stat_database_xact_commit[5m]))
   ```

4. Generate some database activity to see metrics change:

   ```bash
   psql -U postgres -d postgres -c "
     CREATE TABLE IF NOT EXISTS load_test (id serial, data text, ts timestamptz default now());
     INSERT INTO load_test (data) SELECT md5(random()::text) FROM generate_series(1, 10000);
     SELECT count(*) FROM load_test;
   "
   ```

5. Re-run the transaction rate query and confirm it increased.

**Deliverable:** Screenshot or notes showing all 4 PromQL query results.

---

## Exercise 2: Custom Metrics

**Objective:** Add 3 custom PostgreSQL queries to postgres_exporter and verify they appear in Prometheus.

**Tasks:**

1. Edit `~/lab-prometheus/queries.yaml` and add these 3 custom metrics:

   **Metric A: Table bloat indicator**
   ```yaml
   pg_table_bloat:
     query: |
       SELECT
         schemaname,
         relname,
         n_dead_tup,
         n_live_tup,
         CASE WHEN n_live_tup > 0
           THEN round(100.0 * n_dead_tup / n_live_tup, 2)
           ELSE 0
         END AS dead_pct
       FROM pg_stat_user_tables
       WHERE n_live_tup > 100
     metrics:
       - schemaname:
           usage: "LABEL"
           description: "Schema name"
       - relname:
           usage: "LABEL"
           description: "Table name"
       - n_dead_tup:
           usage: "GAUGE"
           description: "Dead tuples"
       - n_live_tup:
           usage: "GAUGE"
           description: "Live tuples"
       - dead_pct:
           usage: "GAUGE"
           description: "Dead tuple percentage"
   ```

   **Metric B: Index usage ratio**
   Write a query that returns for each user table:
   - `schemaname` (LABEL)
   - `relname` (LABEL)
   - `idx_scan` (COUNTER) - number of index scans
   - `seq_scan` (COUNTER) - number of sequential scans
   - `idx_ratio` (GAUGE) - percentage of scans that used an index: `idx_scan / (idx_scan + seq_scan) * 100`

   **Metric C: Database age (transaction wraparound risk)**
   Write a query that returns for each database:
   - `datname` (LABEL)
   - `age` (GAUGE) - result of `age(datfrozenxid)` from `pg_database`

2. Restart postgres_exporter with the updated queries.yaml

3. Verify each metric appears:
   ```bash
   curl -s http://localhost:9187/metrics | grep pg_table_bloat
   curl -s http://localhost:9187/metrics | grep pg_index_usage   # or whatever you named it
   curl -s http://localhost:9187/metrics | grep pg_database_age   # or whatever you named it
   ```

4. Query each metric in Prometheus:
   ```promql
   pg_table_bloat_dead_pct
   # Your index usage metric
   # Your database age metric
   ```

**Deliverable:** The 3 custom metric definitions in queries.yaml and confirmation they appear in Prometheus.

---

## Exercise 3: Dashboard Builder

**Objective:** Create a Grafana dashboard with 6 panels for PostgreSQL health monitoring.

**Tasks:**

Create a new dashboard called "PostgreSQL Health - [Your Name]" with these 6 panels:

| # | Panel Title | Panel Type | PromQL Query | Notes |
|---|---|---|---|---|
| 1 | Connection Count | Time series | `sum by (state) (pg_stat_activity_count)` | Show each state as a separate line |
| 2 | Transactions Per Second | Time series | `sum(rate(pg_stat_database_xact_commit[5m]))` and `sum(rate(pg_stat_database_xact_rollback[5m]))` | Two queries, commits and rollbacks |
| 3 | Cache Hit Ratio | Gauge | Formula from concepts doc | Set thresholds: green > 95, yellow > 90, red < 90 |
| 4 | Database Sizes | Bar gauge | `pg_database_size_bytes{datname!~"template.*"}` | Unit: bytes (IEC), horizontal orientation |
| 5 | Dead Tuple Ratio | Table | `pg_table_bloat_dead_pct > 0` (your custom metric) | Sort descending |
| 6 | Checkpoint Rate | Time series | `rate(pg_stat_bgwriter_checkpoints_timed[5m])` and `rate(pg_stat_bgwriter_checkpoints_req[5m])` | Timed = normal, requested = forced |

Additional requirements:

- Add a `$database` variable (type: Query, query: `label_values(pg_database_size_bytes, datname)`)
- Set auto-refresh to 30 seconds
- Set default time range to Last 6 hours
- Export the dashboard JSON and save to `~/lab-prometheus/my-dashboard.json`

**Deliverable:** The dashboard URL and the exported JSON file.

---

## Exercise 4: Alert Configuration

**Objective:** Write Prometheus alert rules for 5 critical database conditions and verify they work.

**Tasks:**

1. Create a new alert rules file: `~/lab-prometheus/custom_alerts.yml`

2. Write alert rules for these 5 conditions:

   | Alert Name | Condition | For Duration | Severity |
   |---|---|---|---|
   | `HighConnectionUtilization` | Connections > 80% of max_connections | 5m | warning |
   | `ReplicationLagCritical` | Replication lag > 60 seconds | 2m | critical |
   | `DiskSpacePrediction` | Database will be full in 7 days (use `predict_linear`) | 1h | warning |
   | `AutovacuumNotRunning` | Any table with > 10,000 dead tuples and no autovacuum in 24 hours | 30m | warning |
   | `TooManyDeadlocks` | Deadlock rate > 0.1/second | 5m | critical |

3. Add the new rules file to prometheus.yml:
   ```yaml
   rule_files:
     - "alert_rules.yml"
     - "custom_alerts.yml"
   ```

4. Restart Prometheus and verify rules load at http://localhost:9090/rules

5. Trigger at least one alert intentionally:
   - For `HighConnectionUtilization`: open many psql sessions
   - For `AutovacuumNotRunning`: generate dead tuples with UPDATE, then check after autovacuum threshold

6. Verify the alert transitions from `inactive` to `pending` to `firing`

**Hints:**

- `predict_linear(pg_database_size_bytes[24h], 7 * 24 * 3600)` predicts the value in 7 days
- For the autovacuum check, you can use: `time() - pg_stat_user_tables_last_autovacuum > 86400`

**Deliverable:** The `custom_alerts.yml` file and a screenshot of at least one alert in `firing` state.

---

## Exercise 5: SLO Calculator

**Objective:** Define SLIs and SLOs for a PostgreSQL service, calculate the error budget, and create a recording rule to track it.

**Tasks:**

1. Define SLIs for your PostgreSQL service:

   | SLI | Measurement | "Good" Threshold |
   |---|---|---|
   | Availability | `up{job="postgresql"}` | Value = 1 |
   | Query latency | `pg_stat_statements_top_mean_exec_time` | < 100ms |
   | Error rate | Rollback ratio | < 1% |

2. Set SLO targets:

   | SLI | SLO Target | 30-Day Error Budget |
   |---|---|---|
   | Availability | 99.9% | Calculate the minutes |
   | Query latency | 99% < 100ms | Calculate the percentage |
   | Error rate | 99.9% | Calculate the percentage |

3. Write PromQL recording rules that track each SLI:

   ```yaml
   groups:
     - name: slo_recording_rules
       rules:
         - record: slo:availability:ratio
           expr: avg_over_time(up{job="postgresql"}[5m])

         - record: slo:error_rate:ratio
           expr: # Your formula here

         # Add more as needed
   ```

4. Calculate your current error budget consumption:

   ```promql
   # What percentage of your 30-day availability budget have you consumed?
   # Formula: (1 - actual_availability) / (1 - slo_target) * 100
   ```

5. Write a document (in a text file or markdown) that includes:
   - Your SLI definitions
   - Your SLO targets
   - The error budget for each SLO (in minutes or percentage)
   - The PromQL queries to track each SLI
   - A recommendation for what action to take at 50%, 80%, and 100% budget consumption

**Deliverable:** The SLO document and the recording rules YAML file.

---

## Bonus Challenge

If you finish all 5 exercises, try this:

**Build a "DBA On-Call" Dashboard** in Grafana that includes:
- An alert list panel showing all firing alerts
- A stat panel showing current error budget remaining (as a percentage)
- Time series panels for the top 3 SLIs
- A text panel with links to runbooks for each alert
- Variables for environment and instance

This is the dashboard you would pull up on your phone at 3 AM when PagerDuty wakes you up.
