# SURVIVE Runbook - 02: Prometheus Scrape Failure

**Scenario:** Prometheus cannot scrape postgres_exporter due to wrong port in prometheus.yml
**Symptom:** Grafana dashboards show "No data", Prometheus targets page shows postgres DOWN
**Severity:** High - monitoring is blind to all PostgreSQL metrics

---

## Layer 1: Quick Triage

Open the Prometheus targets page:

```
http://<your-server-ip>:9090/targets
```

Look at the `postgres` job row. The State column shows **DOWN** with an error like:

```
connection refused
```

or:

```
dial tcp 127.0.0.1:9999: connect: connection refused
```

The error message tells you what address Prometheus is trying to scrape.

Confirm postgres_exporter itself is running fine:

```bash
sudo systemctl status postgres_exporter
```

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

If the exporter is running and responding on port 9187, but Prometheus shows it as DOWN, the problem is in Prometheus's configuration - not in the exporter itself.

---

## Layer 2: Root Cause Analysis

Check what address Prometheus is configured to scrape for the postgres job:

```bash
grep -A10 "job_name.*postgres" /etc/prometheus/prometheus.yml
```

Expected output when broken (yours will differ):

```yaml
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9999']
```

The port `9999` is wrong. postgres_exporter runs on `9187`.

Verify port 9187 is actually listening:

```bash
ss -tlnp | grep 9187
```

Compare the running port to what Prometheus is trying to connect to. The mismatch is the root cause.

Also check if a backup of the original config exists:

```bash
ls -la /etc/prometheus/
```

---

## Layer 3: Fix and Verify

### Step 1 - Restore from backup if available

```bash
sudo cp /etc/prometheus/prometheus.yml.bak /etc/prometheus/prometheus.yml
```

If no backup exists, proceed to Step 2.

### Step 2 - Fix the scrape target manually

Open prometheus.yml:

```bash
sudo vi /etc/prometheus/prometheus.yml
```

Find the postgres job section. Change the wrong port to the correct one:

```yaml
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']
```

Save and close the file.

### Step 3 - Validate the config before reloading

```bash
sudo -u prometheus /usr/local/bin/promtool check config /etc/prometheus/prometheus.yml
```

Expected output (yours will differ):

```
Checking /etc/prometheus/prometheus.yml
  SUCCESS: 7 rules found
```

If promtool reports errors, fix them before proceeding.

### Step 4 - Reload Prometheus

```bash
curl -s -X POST http://localhost:9090/-/reload
```

### Step 5 - Verify the postgres target is UP

Wait 15-30 seconds (one scrape interval), then check:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -B5 '"job": "postgres"' | grep health
```

Expected output (yours will differ):

```
        "health": "up",
```

### Step 6 - Verify data in Prometheus

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_up' | python3 -m json.tool | grep '"value"'
```

Expected output (yours will differ):

```
                "value": [1709305200.123, "1"]
```

### Step 7 - Check Grafana dashboards

Open Grafana and verify the PostgreSQL dashboard shows live data again. It may take 1-2 scrape intervals (30 seconds) to populate.

---

## Prevention

- Run `promtool check config` in a CI pipeline before applying any prometheus.yml change
- Keep prometheus.yml in version control and require code review for changes
- Set up the PostgresExporterDown alert so you are notified within 1 minute of a scrape failure
