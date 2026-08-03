# Build 03 - Enhanced Monitoring

**Time:** 30 minutes
**Goal:** Enable Enhanced Monitoring, understand OS-level metrics, and use them to diagnose problems that CloudWatch Metrics cannot reveal.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. `$WRITER_INSTANCE`, `$REGION` set. Build 01 complete.

---

## Step 1 - Enable Enhanced Monitoring via Console

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click **Databases** in the left menu.
3. Click your writer instance name.
4. Click the **Modify** button (top right).
5. Scroll down to the **Monitoring** section.
6. Find **Enhanced monitoring** and set it to **Enable enhanced monitoring**.
7. Set **Monitoring Role** to **Default** (or create a new IAM role if prompted).
8. Set **Granularity** to **60 seconds**. Use 1 second only during active performance investigations - it increases CloudWatch Logs cost.
9. Scroll to the bottom and click **Continue**.
10. On the summary screen, select **Apply immediately**.
11. Click **Modify DB Instance**.

> **Concept:** Enhanced Monitoring runs a lightweight agent inside your Aurora instance's OS. It reports OS-level metrics that the hypervisor-level CloudWatch Metrics cannot see - like per-process CPU usage, memory breakdown (active vs cached vs dirty), and per-device disk I/O. The data lands in the CloudWatch Logs group `RDSOSMetrics`.

---

## Step 2 - Enable Enhanced Monitoring via CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --monitoring-interval 60 \
  --monitoring-role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/rds-monitoring-role" \
  --apply-immediately \
  --region "$REGION"
```

Each flag explained:
- `--monitoring-interval 60`: Report every 60 seconds. Valid values: 0 (off), 1, 5, 10, 15, 30, 60.
- `--monitoring-role-arn`: The IAM role that allows RDS to write to CloudWatch Logs. If you get an error about the role not existing, use the Console method instead - it creates the role automatically.
- `--apply-immediately`: Apply without waiting for the next maintenance window.

Wait for the modification to complete:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --region "$REGION"
```

Expected output (yours will differ):
```
(no output - the command exits when the instance is available)
```

---

## Step 3 - View Enhanced Monitoring in the Console

1. Go to the RDS Console and click your writer instance.
2. Click the **Monitoring** tab.
3. At the top of the monitoring graphs, click the dropdown and select **Enhanced monitoring**.
4. You will see OS-level metrics including:

**OS process list:**
- Which processes are using CPU (postgres worker, autovacuum, WAL writer, etc.)
- Memory per process
- I/O per process

**CPU breakdown:**
- User CPU (application work)
- System CPU (kernel work)
- I/O wait (waiting for disk)
- Steal (other VMs on the same host taking CPU - rare on Aurora)
- Nice (low-priority processes)

**Memory breakdown:**
- Active: Memory currently in use
- Buffers: Block device I/O buffers
- Cached: OS file system cache (this is reclaimable)
- Dirty: Modified pages not yet written to storage
- Free: Completely unused memory
- Swap: Memory swapped to disk (should be 0)

**Disk I/O per device:**
- Read operations per second
- Write operations per second
- Bytes read/written per second
- Average service time

**Network per interface:**
- Receive/transmit bytes per second
- Packets per second

---

## Step 4 - Query Enhanced Monitoring Data via CLI

Enhanced Monitoring data lives in CloudWatch Logs, not CloudWatch Metrics. The log group is `RDSOSMetrics`.

```bash
aws logs get-log-events \
  --log-group-name "RDSOSMetrics" \
  --log-stream-name "$WRITER_INSTANCE" \
  --limit 1 \
  --region "$REGION" \
  --query "events[0].message" \
  --output text
```

`--limit 1`: Get only the most recent log event.

This returns a JSON string with the full OS metrics snapshot. To make it readable, pipe it through a JSON formatter:

```bash
aws logs get-log-events \
  --log-group-name "RDSOSMetrics" \
  --log-stream-name "$WRITER_INSTANCE" \
  --limit 1 \
  --region "$REGION" \
  --query "events[0].message" \
  --output text | python3 -m json.tool | head -50
```

Expected output (yours will differ):
```json
{
    "engine": "Aurora",
    "instanceID": "devops-lab-cluster-instance-1",
    "instanceResourceID": "db-ABCDEF123456",
    "timestamp": "2026-06-09T14:30:00Z",
    "version": 1.0,
    "uptime": "5 days, 03:22:15",
    "numVCPUs": 2,
    "cpuUtilization": {
        "guest": 0.0,
        "irq": 0.0,
        "system": 1.5,
        "wait": 0.2,
        "idle": 95.8,
        "user": 2.3,
        "total": 4.0,
        "steal": 0.0,
        "nice": 0.0
    },
    "memory": {
        "active": 4523520,
        "buffers": 256000,
        "cached": 8192000,
        "dirty": 128,
        "free": 2048000,
        "total": 16384000
    },
    ...
}
```

---

## Step 5 - Extract Specific Metrics from Enhanced Monitoring

Get the CPU breakdown:

```bash
aws logs get-log-events \
  --log-group-name "RDSOSMetrics" \
  --log-stream-name "$WRITER_INSTANCE" \
  --limit 1 \
  --region "$REGION" \
  --query "events[0].message" \
  --output text | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
cpu = data['cpuUtilization']
print(f\"CPU Total: {cpu['total']:.1f}%\")
print(f\"  User:   {cpu['user']:.1f}%\")
print(f\"  System: {cpu['system']:.1f}%\")
print(f\"  Wait:   {cpu['wait']:.1f}%\")
print(f\"  Steal:  {cpu['steal']:.1f}%\")
print(f\"  Idle:   {cpu['idle']:.1f}%\")
"
```

Expected output (yours will differ):
```
CPU Total: 4.0%
  User:   2.3%
  System: 1.5%
  Wait:   0.2%
  Steal:  0.0%
  Idle:   95.8%
```

Get the memory breakdown:

```bash
aws logs get-log-events \
  --log-group-name "RDSOSMetrics" \
  --log-stream-name "$WRITER_INSTANCE" \
  --limit 1 \
  --region "$REGION" \
  --query "events[0].message" \
  --output text | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
mem = data['memory']
total = mem['total']
print(f\"Memory Total:  {total / 1024:.0f} MB\")
print(f\"  Active:      {mem['active'] / 1024:.0f} MB\")
print(f\"  Buffers:     {mem['buffers'] / 1024:.0f} MB\")
print(f\"  Cached:      {mem['cached'] / 1024:.0f} MB\")
print(f\"  Dirty:       {mem['dirty'] / 1024:.0f} MB\")
print(f\"  Free:        {mem['free'] / 1024:.0f} MB\")
print(f\"  Freeable:    {(mem['free'] + mem['cached'] + mem['buffers']) / 1024:.0f} MB (what CloudWatch reports)\")
"
```

This shows you why FreeableMemory in CloudWatch is not the same as "free RAM." FreeableMemory = Free + Cached + Buffers. The cached memory is reclaimable - the OS will release it when applications need it.

---

## Step 6 - View the OS Process List

The Enhanced Monitoring data includes a process list showing which OS processes are consuming resources:

```bash
aws logs get-log-events \
  --log-group-name "RDSOSMetrics" \
  --log-stream-name "$WRITER_INSTANCE" \
  --limit 1 \
  --region "$REGION" \
  --query "events[0].message" \
  --output text | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
procs = sorted(data.get('processList', []), key=lambda x: x.get('cpuUsedPc', 0), reverse=True)
print(f\"{'PID':<8} {'Name':<25} {'CPU%':<8} {'Mem%':<8} {'VSS(MB)':<10}\")
print('-' * 60)
for p in procs[:10]:
    print(f\"{p.get('id', '?'):<8} {p.get('name', '?')[:25]:<25} {p.get('cpuUsedPc', 0):<8.1f} {p.get('memoryUsedPc', 0):<8.1f} {p.get('vss', 0) / 1024:.0f}\")
"
```

Expected output (yours will differ):
```
PID      Name                      CPU%     Mem%     VSS(MB)
------------------------------------------------------------
1234     postgres                  2.1      15.3     4096
1235     postgres: autovacuum wo   0.8      3.2      512
1236     postgres: wal writer      0.3      0.5      256
1237     postgres: background wr   0.1      0.5      256
1238     postgres: checkpointer    0.0      0.5      256
...
```

This is invaluable during performance investigations. If CloudWatch shows 80% CPU but you do not know what is causing it, the Enhanced Monitoring process list tells you exactly which PostgreSQL backend process is responsible.

---

## Step 7 - Change Monitoring Granularity for an Investigation

During an active performance investigation, switch to 1-second granularity for detailed analysis:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --monitoring-interval 1 \
  --apply-immediately \
  --region "$REGION"
```

After your investigation is complete, switch back to 60 seconds to reduce CloudWatch Logs cost:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --monitoring-interval 60 \
  --apply-immediately \
  --region "$REGION"
```

> **Cost note:** At 1-second granularity, Enhanced Monitoring generates roughly 60x more data than at 60-second granularity. This can add $30-60/month per instance in CloudWatch Logs ingestion charges. Only use 1-second granularity during active investigations.

---

## Summary

You have:
- Enabled Enhanced Monitoring at 60-second granularity
- Viewed OS-level metrics in the RDS Console
- Extracted CPU, memory, and process data via the CLI
- Learned when to use 1-second granularity for investigations

Enhanced Monitoring is your second-level diagnostic tool. Start with CloudWatch Metrics and Performance Insights. When you need to see which process is causing the problem, turn to Enhanced Monitoring.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Enhanced Monitoring | OS-agent based monitoring inside the RDS instance |
| RDSOSMetrics | CloudWatch Logs group where Enhanced Monitoring data lands |
| Monitoring interval | How often the agent reports (1-60 seconds) |
| Active memory | RAM currently in use by running processes |
| Cached memory | OS page cache - reclaimable when applications need RAM |
| Dirty pages | Modified memory pages not yet flushed to storage |
| I/O wait | CPU time spent waiting for disk/storage I/O to complete |
| Steal | CPU time taken by other VMs on the same physical host |
