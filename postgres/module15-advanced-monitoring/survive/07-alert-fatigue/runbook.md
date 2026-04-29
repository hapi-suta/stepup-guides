# SURVIVE Runbook - 07: Alert Fatigue

**Scenario:** Alert thresholds are set impossibly low - every alert fires constantly for normal activity
**Symptom:** Prometheus /alerts page shows many FIRING alerts; the database appears healthy
**Severity:** Medium - monitoring is noisy and unreliable; real alerts will be ignored

---

## Layer 1: Quick Triage

Open the Prometheus alerts page:

```
http://<your-server-ip>:9090/alerts
```

If you see many alerts FIRING even though:
- postgres_exporter is running
- Grafana shows normal metrics
- pgbench is running normally (not crashing)

Then the thresholds are the problem, not the database.

Check the specific threshold values in each firing alert. Click on a FIRING alert to expand it and read the description. If you see things like:

```
More than 1 non-idle connection.
```

or:

```
Any checkpoint write time is too high.
```

These descriptions reveal that the thresholds are absurdly low.

Verify the database is actually healthy by running a sanity check:

```bash
sudo -i -u postgres
psql -c "SELECT count(*) FROM pg_stat_activity;"
psql -c "SELECT now() - pg_postmaster_start_time() AS uptime;"
exit
```

If PostgreSQL returns clean results, the database is fine and the problem is in the alert rules.

---

## Layer 2: Root Cause Analysis

Check the actual threshold values in the rules file:

```bash
sudo cat /etc/prometheus/rules/postgres.yml
```

Look for alerts with thresholds like:
- `> 1` for connection count (should be `> 80`)
- `> 0.001` for query duration in seconds (should be `> 300`)
- `< 0.9999` for cache hit ratio (should be `< 0.90`)
- `>= 0` for deadlock count (fires when deadlocks = 0, which is always)

Compare to what the thresholds should be. A good reference:
- Connection count: fire at 80% of max_connections (usually 80 out of 100)
- Query duration: fire when a query runs for more than 5 minutes (300 seconds)
- Cache hit ratio: fire when below 90%
- Replication lag: fire when above 30 seconds

Check if a backup of the original rules file exists:

```bash
ls -la /etc/prometheus/rules/
```

---

## Layer 3: Fix and Verify

### Step 1 - Restore from backup

If the backup exists:

```bash
sudo cp /etc/prometheus/rules/postgres.yml.bak_scenario07 /etc/prometheus/rules/postgres.yml
```

If no backup exists, proceed to Step 2.

### Step 2 - Rewrite the rules file with correct thresholds

```bash
sudo vi /etc/prometheus/rules/postgres.yml
```

Replace the entire file with the correct rules. Key thresholds to use:

```yaml
groups:
  - name: postgres_alerts
    interval: 30s
    rules:

      - alert: PostgresExporterDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "postgres_exporter is down"
          description: "Exporter unreachable for more than 1 minute."

      - alert: PostgresHighConnectionCount
        expr: sum(pg_stat_activity_count{state!="idle"}) by (instance) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High connection count: {{ $value }}"
          description: "More than 80 non-idle connections for 5 minutes."

      - alert: PostgresLongRunningQuery
        expr: pg_stat_activity_max_tx_duration{state="active",datname!=""} > 300
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Long running query on {{ $labels.datname }}"
          description: "Query running for {{ $value | humanizeDuration }}."

      - alert: PostgresLowCacheHitRatio
        expr: >
          (
            sum(rate(pg_stat_database_blks_hit[5m])) by (instance)
            /
            (
              sum(rate(pg_stat_database_blks_hit[5m])) by (instance)
              + sum(rate(pg_stat_database_blks_read[5m])) by (instance)
            )
          ) < 0.90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low cache hit ratio: {{ $value | humanizePercentage }}"
          description: "Cache hit ratio below 90% for 10 minutes."

      - alert: PostgresIdleInTransaction
        expr: pg_stat_activity_max_tx_duration{state="idle in transaction",datname!=""} > 600
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Idle-in-transaction on {{ $labels.datname }}"
          description: "Session idle-in-transaction for {{ $value | humanizeDuration }}."

      - alert: PostgresReplicationLag
        expr: pg_replication_lag > 30
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag is high"
          description: "Replication lag is {{ $value | humanizeDuration }}."

      - alert: PostgresCheckpointWriteTimeTooHigh
        expr: >
          rate(pg_stat_bgwriter_checkpoint_write_time[5m]) /
          rate(pg_stat_bgwriter_checkpoints_timed[5m]) > 30000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Checkpoint write time too high"
          description: "Average checkpoint write time is {{ $value | humanizeDuration }}."
```

Save and close.

### Step 3 - Validate the rules file

```bash
sudo -u prometheus /usr/local/bin/promtool check rules /etc/prometheus/rules/postgres.yml
```

Expected output:

```
Checking /etc/prometheus/rules/postgres.yml
  SUCCESS: 7 rules found
```

### Step 4 - Reload Prometheus

```bash
curl -s -X POST http://localhost:9090/-/reload
```

### Step 5 - Verify the alerts page returns to normal

Open `http://<your-server-ip>:9090/alerts`. Most alerts should return to `inactive` within 1-2 minutes as the thresholds are no longer being crossed by normal activity.

The `PostgresExporterDown` alert should remain `inactive` as long as the exporter is running.

### Step 6 - Document the alert threshold decisions

For each alert, document why that specific threshold was chosen. This prevents future developers from lowering thresholds without understanding the rationale.

---

## Prevention

- Require code review for all changes to alerting rule files
- Run `promtool check rules` in CI before any rule file is applied
- Test new thresholds in a staging environment with production-like workloads
- Define SLOs (Service Level Objectives) first, then set alert thresholds based on those SLOs
- Never set `for: 0m` on high-severity alerts unless the condition is always an emergency
