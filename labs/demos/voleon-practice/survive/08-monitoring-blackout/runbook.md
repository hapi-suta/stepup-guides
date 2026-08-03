# Runbook 08: Monitoring Blackout

## Alert
> MEDIUM (discovered manually): No alert was received. This incident was found during a routine manual check.
> Prometheus has been down for approximately 6 hours on pg-ops.
> During that window, pg-replica fell 30 minutes behind primary and nobody was notified.
> Grafana dashboards show no data for the past 6 hours.

---

## Lab Environment

| Node | Public IP | Private IP | Role |
|------|-----------|------------|------|
| pg-primary | 3.90.199.62 | 172.31.19.86 | Primary |
| pg-replica | 3.91.32.84 | 172.31.22.69 | Replica |
| pg-container | 34.235.89.112 | 172.31.21.45 | Container workloads |
| pg-ops | 54.209.143.137 | 172.31.26.19 | Prometheus + Grafana |

SSH command: `ssh -i ~/.ssh/id_ed25519 ec2-user@<IP>`

Monitoring stack on pg-ops:
- Prometheus: port 9090
- Grafana: port 3000

---

## Layer 1 - Junior DBA: Assess and Contain

Monitoring is down. You are flying blind. Your job right now is to manually check every critical system and confirm the current health of the cluster - without relying on any automated tooling.

### Step 1 - SSH into pg-ops and confirm Prometheus is down

From your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

On **pg-ops**, as **ec2-user**:

```bash
systemctl status prometheus
```

Expected output (yours will differ):

```
* prometheus.service - Prometheus
     Loaded: loaded (/usr/lib/systemd/system/prometheus.service; enabled)
     Active: failed (Result: exit-code) since Mon 2024-01-15 09:00:00 UTC; 6h 12min ago
    Process: 4567 ExecStart=/usr/local/bin/prometheus ... (code=exited, status=1/FAILURE)
```

`Active: failed` confirms Prometheus is down. Note the time it went down.

### Step 2 - Check Grafana status

On **pg-ops**, as **ec2-user**:

```bash
systemctl status grafana-server
```

Expected output (yours will differ):

```
* grafana-server.service - Grafana instance
     Active: active (running) since Mon 2024-01-15 08:58:00 UTC; 6h 14min ago
```

Grafana may still be running but showing no data because Prometheus (its data source) is down.

### Step 3 - Manually check replication lag on the primary

Open a new terminal and SSH into the primary:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
SELECT client_addr, state,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_size,
       extract(epoch from (now() - reply_time)) AS lag_seconds
FROM pg_stat_replication;
```

Expected output (yours will differ):

```
  client_addr  |   state   | lag_size | lag_seconds
---------------+-----------+----------+-------------
 172.31.22.69  | streaming | 1842 MB  | 1823.4
(1 row)
```

`lag_seconds` of 1823 means the replica is about 30 minutes behind. Document this number.

### Step 4 - Manually check disk space on all nodes

You need to check disk space on every node because monitoring was not watching for it during the blackout.

On **pg-primary**, inside psql, exit first:

```bash
exit
```

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
df -h
```

Now open separate terminals and check the other nodes:

On **pg-replica** (3.91.32.84), as **ec2-user**:

```bash
df -h
```

On **pg-container** (34.235.89.112), as **ec2-user**:

```bash
df -h
```

Document any filesystem at over 80% usage. You are checking because these may have changed during the 6-hour blackout and nobody would have been alerted.

### Step 5 - Manually check connection counts on primary

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
SELECT count(*) AS total_connections,
       max_conn.setting::int AS max_connections,
       round(count(*) * 100.0 / max_conn.setting::int, 1) AS pct_used
FROM pg_stat_activity,
     (SELECT setting FROM pg_settings WHERE name = 'max_connections') max_conn
GROUP BY max_conn.setting;
```

Expected output (yours will differ):

```
 total_connections | max_connections | pct_used
-------------------+-----------------+----------
                87 |             200 |     43.5
(1 row)
```

If you are above 85%, that is a risk. Note it.

```bash
exit
```

```bash
exit
```

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

You have the manual health check results. Now restart the monitoring stack, investigate why Prometheus went down, and address the replica lag.

### Step 1 - Restart Prometheus

On **pg-ops**, as **ec2-user**:

```bash
systemctl restart prometheus
```

Wait 10 seconds, then verify it came back up:

```bash
systemctl status prometheus
```

Expected output (yours will differ):

```
* prometheus.service - Prometheus
     Active: active (running) since Mon 2024-01-15 15:15:00 UTC; 8s ago
```

### Step 2 - Verify Prometheus is scraping targets

On **pg-ops**, as **ec2-user**, use curl to check the targets endpoint:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A2 '"health"'
```

Expected output (yours will differ):

```
            "health": "up",
            "health": "up",
            "health": "up",
```

All targets should show `"health": "up"`. If any show `"health": "down"`, the exporter on that node is not responding.

### Step 3 - Find out why Prometheus went down

On **pg-ops**, as **ec2-user**:

```bash
journalctl -u prometheus --since "7 hours ago" --no-pager | tail -60
```

Expected output (yours will differ - look for the error):

```
Jan 15 09:00:01 pg-ops prometheus[4567]: level=error ts=2024-01-15T09:00:01.234Z
  caller=main.go:1013 err="opening storage failed: lock DB directory:
  open /var/lib/prometheus/data/lock: no space left on device"
Jan 15 09:00:01 pg-ops systemd[1]: prometheus.service: Main process exited, code=exited, status=1/FAILURE
```

Common causes for Prometheus going down:
- Disk full on `/var/lib/prometheus/data/` (Prometheus TSDB fills up)
- OOM kill (Prometheus uses too much memory)
- Config file syntax error after a config change
- Prometheus binary updated without testing

Check which one applies:

```bash
df -h /var/lib/prometheus/
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G   19G  500M  97% /
```

If disk is full, Prometheus TSDB was the cause.

### Step 4 - Free disk space for Prometheus if TSDB caused the outage

Check the size of Prometheus data:

```bash
sudo du -sh /var/lib/prometheus/data/
```

Expected output (yours will differ):

```
15G     /var/lib/prometheus/data/
```

Check what retention is configured:

```bash
systemctl cat prometheus | grep retention
```

If no retention flag is set, Prometheus defaults to 15 days. You can reduce it:

```bash
sudo vi /etc/systemd/system/prometheus.service
```

Find the `ExecStart` line and add `--storage.tsdb.retention.time=7d`:

```
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/data \
    --storage.tsdb.retention.time=7d \
    --web.listen-address=0.0.0.0:9090
```

Reload and restart:

```bash
systemctl daemon-reload
systemctl restart prometheus
```

Prometheus will compact old data during its next compaction cycle. Check disk space again in a few minutes.

### Step 5 - Address the replica lag

The replica is 30 minutes behind. Check if it is still catching up or if it is stuck.

Open a terminal to **pg-primary** (3.90.199.62), as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql - check lag now and again in 2 minutes:

```sql
SELECT pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_size,
       extract(epoch from (now() - reply_time)) AS lag_seconds
FROM pg_stat_replication;
```

Check again after 2 minutes:

```sql
SELECT pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_size,
       extract(epoch from (now() - reply_time)) AS lag_seconds
FROM pg_stat_replication;
```

If `lag_size` is decreasing between checks, the replica is catching up on its own. This is normal and no action is needed - just monitor until it reaches 0.

If `lag_size` is not decreasing or is growing, the replica has a problem. Check replica logs:

Open a terminal to **pg-replica** (3.91.32.84):

```bash
sudo tail -50 /var/lib/pgsql/17/data/log/postgresql-$(date +%Y-%m-%d).log
```

Look for errors. A replica that is stuck usually has a WAL receiver error or a conflict. Escalate to Layer 3 if the replica is not catching up within 15 minutes.

```bash
exit
```

```bash
exit
```

### Step 6 - Manually verify Docker container health on pg-container

Since monitoring was down, the container node was unsupervised. Check it:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

On **pg-container**, as **ec2-user**:

```bash
sudo docker ps -a
```

Expected output (yours will differ):

```
CONTAINER ID   IMAGE          COMMAND                  CREATED        STATUS                     PORTS     NAMES
a1b2c3d4e5f6   postgres:17    "docker-entrypoint.s…"   2 days ago     Up 2 days                            quantdb_dev
```

If any containers are in `Exited` status, note them. This is for the senior DBA to review.

---

## Layer 3 - Senior DBA: Root Cause and Prevent

Prometheus going down should have triggered an alert. The fact that it did not is the real failure here. Implement meta-monitoring.

### Step 1 - Understand what meta-monitoring means

The monitoring system was not being monitored. Prometheus alerts only work if Prometheus is running. If Prometheus crashes, you lose all visibility AND all alerting. The solution is a "dead man's switch" pattern:

- Prometheus should continuously send a "heartbeat" alert to an external system
- If that heartbeat stops, the external system fires an alert
- This way, Prometheus going silent automatically triggers a page

### Step 2 - Configure a Watchdog alert in Prometheus (dead man's switch)

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /etc/prometheus/rules/watchdog.yml
```

Add this content:

```yaml
groups:
  - name: watchdog
    rules:
      - alert: Watchdog
        expr: vector(1)
        for: 0m
        labels:
          severity: none
        annotations:
          summary: "Prometheus is alive - this alert should always be firing"
          description: "This is a dead man switch. If this alert stops firing, Prometheus is down."
```

This alert always evaluates to true. If your Alertmanager (or external service like PagerDuty/Opsgenie) stops receiving this alert, it means Prometheus is down and it fires an "absence" alert.

Reload Prometheus:

```bash
systemctl reload prometheus
```

Verify the Watchdog alert is firing:

```bash
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep -A3 "Watchdog"
```

Expected output (yours will differ):

```
            "alertname": "Watchdog",
            "state": "firing",
```

### Step 3 - Add a systemd watchdog to auto-restart Prometheus

If Prometheus crashes, systemd should restart it automatically without human intervention.

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /etc/systemd/system/prometheus.service
```

Add or confirm these lines exist in the `[Service]` section:

```ini
[Service]
Restart=on-failure
RestartSec=10s
StartLimitIntervalSec=60s
StartLimitBurst=5
```

This tells systemd: if Prometheus exits with a failure, wait 10 seconds and restart it. Try up to 5 times within 60 seconds.

```bash
systemctl daemon-reload
systemctl restart prometheus
```

Verify the restart policy took effect:

```bash
systemctl cat prometheus | grep Restart
```

Expected output:

```
Restart=on-failure
RestartSec=10s
```

### Step 4 - Create a cron-based fallback monitoring script

Even with systemd restart, there is a window between crash and restart where you are blind. Add an independent cron script that checks critical metrics without Prometheus:

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/scripts/fallback_health_check.sh
```

Add this content:

```bash
#!/bin/bash
set -euo pipefail

LOG="/var/log/fallback_health_check.log"
ALERT_THRESHOLD_LAG_SECONDS=300
ALERT_EMAIL="your-alert-email@example.com"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

check_replication_lag() {
  local lag_seconds
  lag_seconds=$(/usr/pgsql-17/bin/psql -U postgres -d quantdb -tAc \
    "SELECT extract(epoch from (now() - reply_time)) FROM pg_stat_replication LIMIT 1;")

  if [[ -z "$lag_seconds" ]]; then
    log "CRITICAL: No replication connections found on primary"
    return 1
  fi

  lag_int=${lag_seconds%.*}

  if [[ "$lag_int" -gt "$ALERT_THRESHOLD_LAG_SECONDS" ]]; then
    log "WARNING: Replication lag is ${lag_int}s (threshold: ${ALERT_THRESHOLD_LAG_SECONDS}s)"
    return 1
  else
    log "OK: Replication lag is ${lag_int}s"
    return 0
  fi
}

check_disk_space() {
  local pct_used
  pct_used=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  if [[ "$pct_used" -gt 85 ]]; then
    log "WARNING: Root filesystem at ${pct_used}% on $(hostname)"
    return 1
  else
    log "OK: Root filesystem at ${pct_used}%"
    return 0
  fi
}

check_postgres_running() {
  if ! systemctl is-active --quiet postgresql-17; then
    log "CRITICAL: postgresql-17 is not running on $(hostname)"
    return 1
  else
    log "OK: postgresql-17 is running"
    return 0
  fi
}

log "--- Fallback health check starting ---"
FAILURES=0

check_disk_space       || FAILURES=$((FAILURES + 1))
check_postgres_running || FAILURES=$((FAILURES + 1))
check_replication_lag  || FAILURES=$((FAILURES + 1))

if [[ "$FAILURES" -gt 0 ]]; then
  log "ALERT: $FAILURES check(s) failed - review $LOG"
fi

log "--- Check complete: $FAILURES failure(s) ---"
```

```bash
sudo chmod +x /opt/scripts/fallback_health_check.sh
```

Add to cron - run every 5 minutes:

```bash
crontab -e
```

Add:

```
*/5 * * * * /opt/scripts/fallback_health_check.sh
```

### Step 5 - Review Prometheus resource allocation to prevent recurrence

The Prometheus disk fill was the root cause. Set retention and storage limits so it cannot happen again.

On **pg-ops**, as **ec2-user**, check how much disk Prometheus TSDB is using now:

```bash
sudo du -sh /var/lib/prometheus/data/
```

Set a storage size limit in addition to a time-based limit:

```bash
sudo vi /etc/systemd/system/prometheus.service
```

Update the `ExecStart` line to include both retention settings:

```
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/data \
    --storage.tsdb.retention.time=7d \
    --storage.tsdb.retention.size=5GB \
    --web.listen-address=0.0.0.0:9090
```

`--storage.tsdb.retention.size=5GB` caps the TSDB storage. When it hits 5GB, Prometheus deletes the oldest data automatically - it cannot grow past this.

```bash
systemctl daemon-reload
systemctl restart prometheus
```

### Step 6 - Add a Prometheus self-monitoring alert rule

Add alerts for Prometheus's own disk and memory use:

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /etc/prometheus/rules/prometheus_self.yml
```

Add this content:

```yaml
groups:
  - name: prometheus_self_monitoring
    rules:
      - alert: PrometheusStorageHigh
        expr: (prometheus_tsdb_storage_blocks_bytes / (5 * 1024 * 1024 * 1024)) * 100 > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Prometheus TSDB is above 80% of storage limit on {{ $labels.instance }}"

      - alert: PrometheusScrapeFailure
        expr: up == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Prometheus cannot scrape {{ $labels.job }} on {{ $labels.instance }}"
```

Reload:

```bash
systemctl reload prometheus
```

```bash
exit
```

---

## Summary

### Root Cause

Prometheus TSDB on pg-ops consumed all available disk space on the root filesystem after 6+ hours of operation without a storage retention limit. When the disk hit 100%, Prometheus crashed writing its WAL and could not restart (it needs disk space to start). Because there was no systemd `Restart=on-failure` policy, no dead man's switch, and no fallback monitoring, the outage lasted 6 hours undetected. During that window, pg-replica fell 30 minutes behind the primary and nobody was alerted.

### Resolution

1. Confirmed Prometheus down via `systemctl status prometheus`
2. Found the root cause in `journalctl`: "lock DB directory: no space left on device"
3. Confirmed Prometheus TSDB had grown to 15GB on a 20GB volume
4. Added `--storage.tsdb.retention.time=7d` and `--storage.tsdb.retention.size=5GB` to Prometheus service
5. Restarted Prometheus successfully
6. Confirmed replica was catching up (lag decreasing) and required no manual intervention

### Prevention

- Added `Restart=on-failure` and `RestartSec=10s` to Prometheus systemd service so crashes self-recover
- Added `--storage.tsdb.retention.size=5GB` to cap TSDB growth permanently
- Implemented Watchdog alert (dead man's switch) - if Prometheus stops sending it, external system fires
- Created `/opt/scripts/fallback_health_check.sh` cron script that checks disk, replication lag, and PostgreSQL health every 5 minutes without depending on Prometheus
- Added Prometheus self-monitoring alert rules for TSDB storage growth
- Documented the meta-monitoring architecture: never rely on a single monitoring path for critical alerting
