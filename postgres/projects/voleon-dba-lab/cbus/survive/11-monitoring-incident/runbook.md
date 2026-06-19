# Runbook: Monitoring Incident (Scenario 11)

## Scenario Overview

Three simultaneous issues have been injected into the monitoring stack:

1. **Broken Prometheus scrape config on pg-ops** - The postgres_exporter target port in `prometheus.yml` was changed from `9187` to `9999`. Prometheus is trying to scrape a port that nothing is listening on, so it gets "connection refused" for all postgres_exporter targets. No PostgreSQL metrics are reaching Prometheus.

2. **node_exporter stopped on pg-primary** - The `node_exporter` service was stopped on pg-primary. Prometheus can no longer collect OS-level metrics (CPU, memory, disk) from that host. The pg-primary node_exporter target shows as DOWN.

3. **Corrupted alert rule file on pg-ops** - An invalid rule (missing the required `expr` field) was appended to `alert_rules.yml`. Prometheus rejects or partially loads the rule file. Alerts that depend on this file may not fire correctly.

These three failures simulate a realistic scenario where monitoring goes dark in multiple ways at once. Your job is to find each problem, understand why it broke, fix it, and verify the stack is healthy again.

---

## Infrastructure Reference

| Host | Public IP | Role |
|---|---|---|
| pg-ops | 34.228.32.17 | Prometheus, Alertmanager, Grafana |
| pg-primary | 100.26.54.122 | PostgreSQL 17, postgres_exporter, node_exporter |
| pg-replica | 54.144.241.128 | PostgreSQL 17, postgres_exporter, node_exporter |

Key file paths on pg-ops:
- Prometheus config file: `/opt/prometheus/prometheus.yml`
- Alert rules file: `/opt/prometheus/alert_rules.yml`
- Alertmanager config: `/opt/prometheus/alertmanager.yml`
- promtool (validation utility): `/opt/prometheus/promtool`

Key ports:
- Prometheus: 9090
- Alertmanager: 9093
- Grafana: 3000
- node_exporter: 9100
- postgres_exporter: 9187

---

## Phase 1: Detection - What Are You Seeing?

### 1.1 Check Grafana for Missing Metrics

Open a browser and go to `http://34.228.32.17:3000`. Log in with your Grafana credentials.

Look at the PostgreSQL overview dashboard. You will see:

- All PostgreSQL metric panels show "No data" or the last known value frozen in time
- OS-level panels for pg-primary (CPU, memory, disk I/O) show "No data"
- Other hosts may still have partial data if their exporters are healthy

This tells you that data is not flowing from at least one target.

### 1.2 Check Prometheus Targets Page

The Prometheus targets page shows the health of every scrape job. This is your first diagnostic stop.

SSH into pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"scrapeUrl"' | head -40
```

This command queries the Prometheus API for all scrape targets and shows their health status and URL. You are looking for any line that says `"health": "down"`.

Expected output (yours will differ):

```
            "scrapeUrl": "http://172.31.19.86:9100/metrics",
            "health": "down",
            "scrapeUrl": "http://172.31.19.86:9999/metrics",
            "health": "down",
            "scrapeUrl": "http://172.31.22.69:9999/metrics",
            "health": "down",
```

You should see:

- `172.31.19.86:9100` (pg-primary node_exporter) is DOWN
- All targets scraping port `9999` are DOWN - this is a strong signal the port is wrong in the config

### 1.3 Check the Prometheus Alerts Page

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep -E '"name"|"state"' | head -20
```

This shows all currently firing or pending alerts.

Expected output (yours will differ):

```
                "name": "NodeExporterDown",
                "state": "firing",
```

You may or may not see alerts depending on whether the alert rule file loaded at all. If the rule file is fully rejected, no alerts fire - which is itself a sign something is wrong with the rules file.

### 1.4 Check the Prometheus Rules Status

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep -E '"name"|"lastError"' | head -30
```

This shows all loaded rules and whether any have errors. A non-empty `lastError` means Prometheus had a problem evaluating or loading that rule.

Expected output (yours will differ):

```
                    "name": "ChaosInvalidRule",
                    "lastError": "could not parse expression: ...",
```

You may also see an empty `groups` array if Prometheus rejected the entire rules file.

---

## Phase 2: Diagnosis - Understanding Each Problem

### 2.1 Diagnose the Wrong Port in prometheus.yml

On **pg-ops**, as **ec2-user**:

```bash
sudo grep -n "9187\|9999" /opt/prometheus/prometheus.yml
```

`grep -n` shows line numbers alongside matching lines. You are looking for any target that uses port `9999` where it should use `9187`.

Expected output (yours will differ):

```
47:        - targets: ['172.31.19.86:9999']
51:        - targets: ['172.31.22.69:9999']
```

The correct postgres_exporter port is `9187`. Both targets show `9999` - that is the bug. postgres_exporter does not listen on port 9999, so every scrape attempt fails with "connection refused."

### 2.2 Diagnose the Stopped node_exporter on pg-primary

Open a second terminal and SSH into pg-primary.

On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl status node_exporter
```

Expected output (yours will differ):

```
   node_exporter.service - Prometheus Node Exporter
   Loaded: loaded (/etc/systemd/system/node_exporter.service; enabled; preset: disabled)
   Active: inactive (dead)
```

`inactive (dead)` means the service is stopped. `enabled` means it is set to auto-start on boot, but it was manually stopped by the chaos script.

Confirm the port is not listening:

```bash
ss -tlnp | grep 9100
```

`ss -tlnp` lists TCP listening sockets. No output here confirms nothing is on port 9100.

Expected output (yours will differ):

```
(no output)
```

### 2.3 Diagnose the Invalid Alert Rule on pg-ops

Switch back to **pg-ops**. On **pg-ops**, as **ec2-user**:

Look at the end of the alert rules file to find the injected bad rule:

```bash
sudo tail -20 /opt/prometheus/alert_rules.yml
```

`tail -20` shows the last 20 lines of the file. The broken rule will be at the bottom.

Expected output (yours will differ):

```yaml
  # CHAOS: invalid rule - missing required 'expr' field
  - alert: ChaosInvalidRule
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "This rule is intentionally broken for chaos testing"
```

There is no `expr:` line in this rule block. Every Prometheus alert rule requires an `expr` field - this is the PromQL expression that defines when the alert fires. Without it, the rule is syntactically invalid and Prometheus rejects the file.

Now confirm the error with promtool:

```bash
/opt/prometheus/promtool check rules /opt/prometheus/alert_rules.yml
```

`promtool check rules` validates a Prometheus rules file and reports any errors. Use this before every reload to catch mistakes.

Expected output (yours will differ):

```
Checking /opt/prometheus/alert_rules.yml
  FAILED:
    /opt/prometheus/alert_rules.yml: group "...", rule 0, "ChaosInvalidRule": field 'expr' must be set in rule
```

This confirms the exact rule causing the failure.

---

## Phase 3: Fix the Prometheus Scrape Config

The wrong port in `prometheus.yml` is causing Prometheus to scrape port 9999 instead of 9187. Fix this first - it affects all postgres_exporter data.

### 3.1 Open prometheus.yml for Editing

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/prometheus.yml
```

### 3.2 Find and Fix the Wrong Port

In vi, search for the wrong port number:

```
/9999
```

Press `n` to jump to each occurrence. The quickest way to do a global replacement in vi is:

```
:%s/:9999/:9187/g
```

- `:%s` means "search and replace across all lines"
- `/:9999/:9187/g` replaces every occurrence of `:9999` with `:9187`

After running this, verify the change:

```
/9187
```

Press `n` to cycle through occurrences. You should see the postgres_exporter target lines now show `:9187`.

Save and exit:

```
:wq
```

### 3.3 Validate prometheus.yml Before Reloading

Always validate before reloading. A syntax error in prometheus.yml can stop Prometheus from loading entirely.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check config /opt/prometheus/prometheus.yml
```

Expected output (yours will differ):

```
Checking /opt/prometheus/prometheus.yml
  SUCCESS: /opt/prometheus/prometheus.yml is valid prometheus config file syntax
```

If you see any errors, go back into vi and fix them before proceeding.

### 3.4 Reload Prometheus

Prometheus supports a graceful reload via the HTTP lifecycle API. No restart is needed and no data is lost.

On **pg-ops**, as **ec2-user**:

```bash
curl -s -X POST http://localhost:9090/-/reload
```

`-X POST` sends an HTTP POST request to the Prometheus lifecycle endpoint. Prometheus re-reads its config file and applies changes without dropping in-memory data or active scrape connections.

If the lifecycle API is not enabled (no output or an error), reload via systemd instead:

```bash
sudo systemctl reload prometheus
```

Wait 5 seconds, then check the targets for the postgres_exporter jobs:

```bash
sleep 5 && curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"scrapeUrl"' | grep "9187"
```

Expected output (yours will differ):

```
            "scrapeUrl": "http://172.31.19.86:9187/metrics",
            "health": "up",
            "scrapeUrl": "http://172.31.22.69:9187/metrics",
            "health": "up",
```

The postgres_exporter targets now show `"health": "up"` with the correct port `9187`.

---

## Phase 4: Fix the Alert Rules

The corrupted alert rule is preventing the rule group from loading correctly. Fix this on pg-ops.

### 4.1 Open alert_rules.yml for Editing

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/alert_rules.yml
```

### 4.2 Remove the Invalid Rule Block

You need to delete the chaos rule block that was appended to the end of the file. It looks like this:

```yaml
  # CHAOS: invalid rule - missing required 'expr' field
  - alert: ChaosInvalidRule
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "This rule is intentionally broken for chaos testing"
```

In vi, jump to the end of the file:

```
G
```

`G` (capital G) moves your cursor to the last line of the file.

Turn on line numbers so you can see exactly where the chaos block starts:

```
:set number
```

Scroll up until you find the `# CHAOS: invalid rule` comment line. Note its line number. For example, if it starts at line 85:

```
:85,$d
```

This means "delete from line 85 to the last line (`$`) of the file." The chaos block is gone.

Scroll to the bottom to confirm the file ends cleanly with valid content:

```
G
```

Save and exit:

```
:wq
```

### 4.3 Validate alert_rules.yml with promtool

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check rules /opt/prometheus/alert_rules.yml
```

Expected output (yours will differ):

```
Checking /opt/prometheus/alert_rules.yml
  SUCCESS: 12 rules found
```

The number of rules will match however many valid rules were in your file before chaos injection. Any `FAILED` output means the file still has a problem - open vi and look again.

### 4.4 Run a Combined Validation (Config + Rules Together)

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check config /opt/prometheus/prometheus.yml
```

When run against the main config file, promtool also validates all referenced rule files. A single clean output here means both files are good.

Expected output (yours will differ):

```
Checking /opt/prometheus/prometheus.yml
  SUCCESS: /opt/prometheus/prometheus.yml is valid prometheus config file syntax

Checking /opt/prometheus/alert_rules.yml
  SUCCESS: 12 rules found
```

### 4.5 Reload Prometheus to Apply Fixed Rules

On **pg-ops**, as **ec2-user**:

```bash
curl -s -X POST http://localhost:9090/-/reload
```

Or via systemd:

```bash
sudo systemctl reload prometheus
```

Wait 10 seconds, then verify the rules are loaded:

```bash
sleep 10 && curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep -c '"name"'
```

This counts the number of rule names in the API response. The count should match what promtool reported.

Expected output (yours will differ):

```
12
```

If you see `0`, the rules file was still rejected. Go back and check for syntax errors.

---

## Phase 5: Restore node_exporter on pg-primary

node_exporter provides OS-level metrics (CPU, memory, disk, network) to Prometheus. Without it, you have no host-level visibility on pg-primary.

### 5.1 Start node_exporter

SSH into pg-primary. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl start node_exporter
```

`systemctl start` brings the service up immediately. The `enabled` flag from before the chaos injection means it will also auto-start on any future reboot - you do not need to re-enable it.

### 5.2 Verify node_exporter Is Running

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl status node_exporter
```

Expected output (yours will differ):

```
   node_exporter.service - Prometheus Node Exporter
   Loaded: loaded (/etc/systemd/system/node_exporter.service; enabled; preset: disabled)
   Active: active (running) since Wed 2026-06-18 15:30:00 UTC; 3s ago
   Main PID: 23456 (node_exporter)
```

`Active: active (running)` confirms the service is up.

### 5.3 Confirm Port 9100 Is Listening

On **pg-primary**, as **ec2-user**:

```bash
ss -tlnp | grep 9100
```

Expected output (yours will differ):

```
LISTEN 0 4096 0.0.0.0:9100 0.0.0.0:* users:(("node_exporter",pid=23456,fd=3))
```

The process `node_exporter` is now listening on port 9100 and is ready to serve metrics.

### 5.4 Test the Metrics Endpoint Locally

On **pg-primary**, as **ec2-user**:

```bash
curl -s http://localhost:9100/metrics | head -5
```

`head -5` shows just the first 5 lines so you can confirm the endpoint is serving data without printing the full metrics output (which is very long).

Expected output (yours will differ):

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 3.1e-05
go_gc_duration_seconds{quantile="0.25"} 5.1e-05
go_gc_duration_seconds{quantile="0.5"} 6.6e-05
```

Prometheus will pick this up on the next scrape cycle (within 15-30 seconds by default).

---

## Phase 6: Verification - Confirm Full Recovery

Run through all checks to confirm the monitoring stack is fully healthy before declaring the incident resolved.

### 6.1 Check All Prometheus Targets Are UP

Switch back to **pg-ops**. On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"' | sort | uniq -c
```

This command groups and counts targets by health state. You want to see only `"health": "up"` in the output with a count equal to your total number of targets.

Expected output (yours will differ):

```
      8   "health": "up",
```

All targets reporting `up`. If any show `"down"`, find their `scrapeUrl` and trace the problem back to the relevant exporter or config file.

### 6.2 Check node_exporter Target Is UP for pg-primary

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A3 "9100" | grep -E '"health"|"scrapeUrl"'
```

Expected output (yours will differ):

```
            "scrapeUrl": "http://172.31.19.86:9100/metrics",
            "health": "up",
```

### 6.3 Check postgres_exporter Metrics Are Flowing

On **pg-ops**, as **ec2-user**:

```bash
curl -s "http://localhost:9090/api/v1/query?query=pg_up" | python3 -m json.tool
```

`pg_up` is a metric published by postgres_exporter. A value of `1` means it successfully connected to PostgreSQL. A value of `0` means the exporter is running but cannot reach the database.

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "pg_up",
                    "instance": "172.31.19.86:9187",
                    "job": "postgres"
                },
                "value": [1750000000, "1"]
            }
        ]
    }
}
```

Every instance should return the value `"1"`. If any instance returns `"0"`, that exporter is running but cannot connect to the PostgreSQL process.

### 6.4 Check Alert Rules Are Loaded Without Errors

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep '"lastError"' | sort | uniq -c
```

Expected output (yours will differ):

```
     12   "lastError": "",
```

Every rule should show `"lastError": ""` (empty string). A non-empty `lastError` means that rule is failing to evaluate - check the rule syntax.

### 6.5 Check Alertmanager Is Reachable from Prometheus

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/alertmanagers | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "activeAlertmanagers": [
            {
                "url": "http://localhost:9093/api/v2/alerts"
            }
        ],
        "droppedAlertmanagers": []
    }
}
```

`activeAlertmanagers` must have at least one entry. `droppedAlertmanagers` should be empty. If `activeAlertmanagers` is empty, Prometheus cannot route alerts anywhere - check the `alerting:` section in prometheus.yml and verify the Alertmanager service is running.

### 6.6 Run the Automated Validation Script

Once you believe everything is fixed, run the validation script for a definitive PASS/FAIL result.

On your **local machine**, as your local user:

```bash
bash /path/to/voleon-dba-lab/cbus/survive/11-monitoring-incident/validate.sh
```

Expected output (yours will differ):

```
===========================================
 VALIDATION: Monitoring Incident
===========================================

[1/5] Checking Prometheus targets on pg-ops (34.228.32.17)...
  [PASS] All Prometheus targets are UP
         8/8 targets reporting UP, 0 targets DOWN

[2/5] Checking alert rule validity on pg-ops (34.228.32.17)...
  [PASS] No invalid or error alert rules
         12 rule name(s) loaded with no errors detected

[3/5] Checking node_exporter status on pg-primary (100.26.54.122)...
  [PASS] node_exporter is running on pg-primary
         systemctl state: active, port 9100 listener(s): 1

[4/5] Checking postgres_exporter metrics via Prometheus on pg-ops (34.228.32.17)...
  [PASS] postgres_exporter metrics scraped (pg_up=1)
         2/2 postgres_exporter instance(s) returning pg_up=1

[5/5] Checking Alertmanager connectivity from Prometheus on pg-ops (34.228.32.17)...
  [PASS] Alertmanager is reachable from Prometheus
         Active Alertmanager found: http://localhost:9093/api/v2/alerts

===========================================
 RESULTS: 5/5 checks passed
===========================================

 ALL CHECKS PASSED - Monitoring incident resolved!
```

All 5 checks passing means the monitoring stack is fully restored.

---

## Troubleshooting: Common Failure Scenarios

### Prometheus targets still showing DOWN after fixing prometheus.yml

- Verify the reload actually applied: `curl -s http://localhost:9090/-/healthy`
- If Prometheus needs a full restart: `sudo systemctl restart prometheus`
- After a restart, wait 30 seconds for the first scrape cycle to complete
- Check Prometheus logs: `sudo journalctl -u prometheus -n 50 --no-pager`

### promtool says alert_rules.yml is valid but Prometheus still shows errors

- The file on disk may have been updated but Prometheus has not reloaded yet
- Force a reload: `curl -s -X POST http://localhost:9090/-/reload`
- Check if the lifecycle API is enabled: look for `--web.enable-lifecycle` in the prometheus systemd unit file
- If that flag is missing, you must use `sudo systemctl reload prometheus` instead of the curl command

### node_exporter starts but Prometheus target stays DOWN

- Wait one full scrape interval (default 15 seconds) for Prometheus to re-check the target
- Confirm you can reach port 9100 from pg-ops directly: `curl -s http://172.31.19.86:9100/metrics | head -3`
- If the curl from pg-ops fails but works locally on pg-primary, check the security group rules for port 9100 inbound from pg-ops

### Alertmanager shows as dropped instead of active

- Check if Alertmanager is running on pg-ops: `sudo systemctl status alertmanager`
- Check the alerting section in prometheus.yml - the URL must match where Alertmanager is listening
- Verify Alertmanager is responding: `curl -s http://localhost:9093/api/v2/status | python3 -m json.tool`

---

## Interview Talking Points

**Prometheus scrape target health vs actual service health**

A target showing DOWN in Prometheus does not necessarily mean the database or host is down. It means Prometheus cannot scrape that specific endpoint. Always check the actual service directly on the host before escalating. The most common causes are a wrong port, wrong IP, or a stopped exporter - not a real outage. Calling a P1 incident because Prometheus shows a target DOWN when the actual database is fine is an embarrassing mistake to make in front of a Voleon on-call team.

**promtool is mandatory before every reload**

Reloading Prometheus with an invalid config causes it to reject the new config and continue running the old one (or fail if restarting). Always run `promtool check config` AND `promtool check rules` before any reload in production. This takes 2 seconds and prevents outages.

**Alert rules and scrape configs fail independently**

In this scenario, the scrape config was wrong AND the alert rule file was invalid simultaneously. A broken alert rule does not affect scraping. A broken scrape target does not affect which rules are loaded. Understanding what each config file controls lets you narrow down problems faster.

**Graceful reload vs restart**

`curl -X POST http://localhost:9090/-/reload` reloads config with no downtime and preserves in-memory state. `systemctl restart prometheus` is a full restart - it works but causes a brief gap in data collection and clears the write-ahead log. Use reload whenever possible in production. Know which one requires the `--web.enable-lifecycle` flag.

**The "monitor the monitors" problem**

When your monitoring stack breaks, you lose the ability to see what else is going wrong. This is why external uptime checks (Pingdom, AWS CloudWatch, a separate Prometheus) that watch Prometheus itself are valuable. In this scenario, if node_exporter had been down for hours unnoticed, you could have missed disk pressure or CPU spikes on pg-primary during that window.

**node_exporter is cheap - keep it running**

node_exporter uses very little CPU and memory. Every server running PostgreSQL should have node_exporter running with auto-restart enabled. Add `Restart=on-failure` and `RestartSec=5` to the systemd unit file so it recovers from crashes without human intervention.
