# SURVIVE Runbook - 04: Disk Full - Metrics Loss

**Scenario:** The Prometheus data directory is nearly full, causing metric write failures
**Symptom:** Gaps in Grafana graphs, Prometheus logs show TSDB write errors, disk usage alerts
**Severity:** High - historical metrics are being lost, future metrics cannot be written

---

## Layer 1: Quick Triage

Check disk usage on the filesystem where Prometheus stores data:

```bash
df -h /var/lib/prometheus
```

Expected output when the problem exists (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G   19G  100M  99% /
```

If Use% is above 90%, that is your problem.

Check Prometheus logs for write errors:

```bash
sudo journalctl -u prometheus -n 30 --no-pager | grep -i "error\|tsdb\|disk\|no space"
```

Common error you will see:

```
level=error msg="Compaction failed" err="no space left on device"
```

or:

```
level=warn msg="Failed to write head chunk" err="write /var/lib/prometheus/.../chunks: no space left on device"
```

---

## Layer 2: Root Cause Analysis

Find what is consuming disk space in the Prometheus data directory:

```bash
sudo du -sh /var/lib/prometheus/
sudo du -sh /var/lib/prometheus/* | sort -rh | head -20
```

Look for unexpected large files:

```bash
sudo find /var/lib/prometheus -name "*.tmp" -o -name "_junk*" | xargs ls -lh 2>/dev/null
```

Check overall disk usage on the server:

```bash
df -h
du -sh /var/lib/prometheus /var/log /tmp 2>/dev/null | sort -rh
```

Check the Prometheus retention configuration:

```bash
sudo systemctl cat prometheus | grep retention
```

If `--storage.tsdb.retention.time` is not set, Prometheus defaults to 15 days. If you have a busy database, 15 days of 15-second scrapes adds up to gigabytes.

---

## Layer 3: Fix and Verify

### Step 1 - Identify and remove the junk file

In this scenario, a junk file was written to simulate disk full:

```bash
sudo ls -lh /var/lib/prometheus/_junk_fill 2>/dev/null
```

Remove it:

```bash
sudo rm -f /var/lib/prometheus/_junk_fill
```

### Step 2 - Verify disk space is recovered

```bash
df -h /var/lib/prometheus
```

Free space should have increased substantially.

### Step 3 - Restart Prometheus to clear any error state

```bash
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

### Step 4 - Configure Prometheus retention to prevent recurrence

Open the prometheus service unit:

```bash
sudo vi /etc/systemd/system/prometheus.service
```

Verify the `--storage.tsdb.retention.time` flag is set. If the disk is small (under 20GB), reduce retention:

```ini
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --storage.tsdb.retention.size=5GB \
  ...
```

The `--storage.tsdb.retention.size=5GB` flag tells Prometheus to delete old data when the TSDB exceeds 5GB, regardless of age. This is a hard cap on disk usage.

Reload systemd and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart prometheus
```

### Step 5 - Check Prometheus is writing new data

Wait 30 seconds, then query for a recent metric:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool | grep '"value"'
```

The timestamp in the value should be close to the current time.

### Step 6 - Verify Grafana shows data again

Open Grafana and set the time range to "Last 5 minutes." You should see data for the most recent period. The gap during the disk-full period will remain in the historical view - that data is permanently lost.

### Step 7 - Set up a disk space alert in Prometheus

Add this to your alerting rules:

```yaml
- alert: PrometheusDiskSpaceLow
  expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Less than 10% disk space available"
    description: "{{ $value | humanizePercentage }} disk space remaining on /."
```

Note: this requires node_exporter to be installed. For this lab without node_exporter, check disk space via a cron job instead:

```bash
sudo crontab -e
```

Add:

```
*/15 * * * * df -h / | awk 'NR==2 {gsub("%",""); if ($5 > 85) print "DISK WARN: " $5 "% used on /"}' | logger -t disk_monitor
```

---

## Prevention

- Always set `--storage.tsdb.retention.size` as a hard cap
- Alert on disk space before it is full (at 80%, not 99%)
- Monitor disk usage trends - use `rate(node_filesystem_avail_bytes[1h])` to detect filling disk early
