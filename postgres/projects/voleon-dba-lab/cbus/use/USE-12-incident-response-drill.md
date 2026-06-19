# USE Exercise 12: Incident Response Workflow Drills

| | |
|---|---|
| **Time** | 100 minutes total (four exercises) |
| **Servers** | pg-primary (100.26.54.122), pg-replica (54.144.241.128), pg-ops (34.228.32.17) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |
| **Interview prep** | Ed Byrne - Senior Systems Infrastructure Engineer, The Voleon Group |

## What You'll Practice

- Running a full incident response workflow from page to post-mortem
- Using PromQL for capacity planning and predictive analysis
- Building an operational runbook from live metrics
- Correlating multiple signal sources to diagnose intermittent application issues

## Prerequisites

- Completed USE-11 (Monitoring Operations)
- Prometheus running on pg-ops:9090
- Grafana running on pg-ops:3000
- Alertmanager running on pg-ops:9093
- postgres_exporter on pg-primary (:9187) and pg-replica (:9187)
- node_exporter on all nodes (:9100)
- PostgreSQL 17 running on pg-primary, database quantdb

---

## Exercise 1: The 3 AM Alert - Full Incident Response (30 min)

**Scenario:** You get paged at 3 AM. Your phone shows: `[FIRING] ReplicationLagCritical - pg-replica - lag > 30s for 5m`. Walk through the full incident response workflow from triage to post-mortem.

---

### Step 1.1: Triage - Check Alertmanager for Alert Details

The first thing you do when paged is open Alertmanager to understand the scope of the incident. How many alerts are firing? When did it start? What labels does the alert carry?

On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

Query Alertmanager for all currently firing alerts:

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool
```

`curl` fetches the alert list from Alertmanager's REST API. `python3 -m json.tool` formats the JSON so it is readable.

Expected output (yours will differ):

```json
[
    {
        "labels": {
            "alertname": "ReplicationLagCritical",
            "instance": "172.31.22.69:9187",
            "severity": "critical"
        },
        "annotations": {
            "summary": "Replication lag on pg-replica exceeds 30 seconds",
            "description": "Current lag: 47.3s"
        },
        "startsAt": "2026-06-18T03:02:14Z",
        "status": {
            "state": "active"
        }
    }
]
```

Read the output carefully. Note the `startsAt` timestamp - that tells you when the alert first fired. Write it down:

```
Alert started: ____________________
Current time:  ____________________
Duration so far: ____________________
```

This is a critical-severity alert on the replica instance (172.31.22.69). Only one alert is firing, which is a good sign - this looks isolated to replication, not a broader outage.

---

### Step 1.2: Assess - Measure Current Lag with PromQL

Before you SSH anywhere, use Prometheus to understand the current state and trend of the lag. You want to know: how bad is it, and is it getting worse or better?

Still on **pg-ops**, as **ec2-user**:

Check the current replication lag value:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_replication_lag_seconds' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "instance": "172.31.22.69:9187"
                },
                "value": [ 1750208534, "47.3" ]
            }
        ]
    }
}
```

The value `47.3` means the replica is 47.3 seconds behind the primary. The threshold for this alert is 30 seconds, so the lag has exceeded that threshold by about 17 seconds.

Now check the WAL byte difference between primary and replica to understand how much data is queued:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_replication_pg_wal_lsn_diff' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "application_name": "pg-replica",
                    "instance": "172.31.19.86:9187",
                    "state": "streaming"
                },
                "value": [ 1750208534, "2097152" ]
            }
        ]
    }
}
```

`2097152` bytes is 2 MB of WAL that the replica has not yet applied. This is a moderate amount - it is not catastrophic (not hundreds of megabytes), which suggests the issue may be a temporary slowdown rather than a full disconnect.

Check the trend over the last 10 minutes to see if lag is growing or stable:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=deriv(pg_replication_lag_seconds[10m])' | python3 -m json.tool
```

`deriv()` returns the per-second rate of change. A positive value means lag is growing. A negative value means lag is shrinking (recovery). A value near 0 means lag is stable.

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "instance": "172.31.22.69:9187" },
                "value": [ 1750208534, "0.8" ]
            }
        ]
    }
}
```

A `deriv` of `0.8` means lag is growing at 0.8 seconds per second - it is getting worse, not recovering. This escalates the urgency. You need to diagnose and fix this quickly before the replica falls too far behind to be useful for failover.

---

### Step 1.3: Diagnose - Check pg_stat_replication on the Primary

SSH to pg-primary and query the replication system view directly.

Open a **second terminal**. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -x -c "SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag, sync_state FROM pg_stat_replication;"
```

`-x` enables expanded display, which prints each column on its own line. This makes wide rows like replication status much easier to read.

Expected output (yours will differ):

```
-[ RECORD 1 ]----+------------------------------
application_name | pg-replica
state            | streaming
sent_lsn         | 0/A1234500
write_lsn        | 0/A1200000
flush_lsn        | 0/A1100000
replay_lsn       | 0/A0F00000
write_lag        | 00:00:02.1
flush_lag        | 00:00:08.4
replay_lag       | 00:00:47.3
sync_state       | async
```

Read the output carefully:

- `state: streaming` - The replica is connected and streaming. It has not disconnected.
- `replay_lag: 00:00:47.3` - This matches what Prometheus showed. The replica is 47 seconds behind on applying WAL.
- `flush_lag` is much lower than `replay_lag` - The replica is receiving WAL fast but applying it slowly. This points to a replay bottleneck on the replica, not a network or send problem.

This is an important distinction. If `write_lag` and `flush_lag` were also high, it would suggest a network problem or a disk problem on the replica. Since only `replay_lag` is high, the bottleneck is on the replica's recovery process.

Now check if there are any long-running transactions on the primary that could be blocking replication:

```bash
psql -d quantdb -c "SELECT pid, now() - xact_start AS duration, state, wait_event_type, wait_event, left(query, 60) AS query FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY duration DESC LIMIT 5;"
```

Expected output (yours will differ):

```
 pid  |    duration     | state  | wait_event_type | wait_event |               query
------+-----------------+--------+-----------------+------------+------------------------------------
 1234 | 00:00:01.234567 | active |                 |            | SELECT ...
```

If you see a transaction that has been running for minutes with `wait_event_type` of `Lock`, that could be holding back replication. In this case, assume transactions look normal.

---

### Step 1.4: Diagnose - Check pg_stat_wal_receiver on the Replica

Now check from the replica's perspective. The replica has its own view of the replication state.

Open a **third terminal**. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.144.241.128
```

On **pg-replica**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-replica**, as **postgres**:

```bash
psql -x -c "SELECT status, receive_start_lsn, received_lsn, last_msg_send_time, last_msg_receipt_time, latest_end_lsn, latest_end_time, sender_host, conninfo FROM pg_stat_wal_receiver;"
```

Expected output (yours will differ):

```
-[ RECORD 1 ]--------+----------------------------------------
status               | streaming
receive_start_lsn    | 0/90000000
received_lsn         | 0/A1234500
last_msg_send_time   | 2026-06-18 03:07:44.123456+00
last_msg_receipt_time| 2026-06-18 03:07:44.456789+00
latest_end_lsn       | 0/A1234500
latest_end_time      | 2026-06-18 03:07:44.123456+00
sender_host          | 172.31.19.86
conninfo             | application_name=pg-replica ...
```

Key things to check:

- `status: streaming` - The WAL receiver process is running and connected to the primary.
- `last_msg_receipt_time` should be recent (within the last few seconds). If it is stale, the network connection may have dropped silently.
- The gap between `received_lsn` and the primary's `sent_lsn` tells you if data is being received.

The WAL receiver is healthy - it is receiving data. The problem is that the WAL is being received but not applied fast enough. Check what the recovery process is doing:

```bash
psql -x -c "SELECT pid, now() - xact_start AS duration, state, wait_event_type, wait_event, left(query, 60) AS query FROM pg_stat_activity WHERE backend_type = 'walreceiver' OR backend_type = 'startup';"
```

Expected output (yours will differ):

```
-[ RECORD 1 ]----+---------------------------
pid              | 5678
duration         |
state            | active
wait_event_type  | Activity
wait_event       | RecoveryApplyDelay
...
```

If you see `RecoveryApplyDelay` as the wait event, the replica is intentionally delaying replay due to a `recovery_min_apply_delay` setting. Check for that:

```bash
psql -c "SHOW recovery_min_apply_delay;"
```

Expected output (yours will differ):

```
 recovery_min_apply_delay
--------------------------
 0
(1 row)
```

If the value is `0`, there is no intentional delay. The lag is a real bottleneck.

---

### Step 1.5: Correlate - Check System Metrics Around the Alert Start Time

Go back to **pg-ops** to check system metrics. You want to know if something happened on the replica's host around 03:02 AM (when the alert fired) that could explain the slowdown.

On **pg-ops**, as **ec2-user**:

Check CPU usage on the replica around the alert start time. Use a range query to look at the last 30 minutes:

```bash
curl -s 'http://localhost:9090/api/v1/query_range?query=100-(avg+by(instance)(rate(node_cpu_seconds_total{instance="172.31.22.69:9100",mode="idle"}[5m]))*100)&start=$(date -u -d '30 minutes ago' +%s)&end=$(date -u +%s)&step=60' | python3 -m json.tool | grep -A3 '"values"'
```

Check I/O wait on the replica. High I/O wait means the disk is the bottleneck:

```bash
curl -s 'http://localhost:9090/api/v1/query_range?query=rate(node_cpu_seconds_total{instance="172.31.22.69:9100",mode="iowait"}[5m])&start=$(date -u -d '30 minutes ago' +%s)&end=$(date -u +%s)&step=60' | python3 -m json.tool | grep -A3 '"values"'
```

Expected output (yours will differ):

```json
{
    "values": [
        [ 1750207200, "0.02" ],
        [ 1750207260, "0.03" ],
        [ 1750207320, "0.41" ],
        [ 1750207380, "0.63" ],
        ...
    ]
}
```

If you see the `iowait` value jump significantly at the same time the alert fired, that is your root cause. The replica's disk became slow (possibly a noisy neighbor on EC2 or a disk throughput limit being hit), which slowed WAL replay, which caused replication lag to accumulate.

Check disk write throughput on the replica to confirm:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(node_disk_written_bytes_total{instance="172.31.22.69:9100"}[5m])' | python3 -m json.tool
```

Check network receive throughput on the replica (WAL comes in over the network):

```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(node_network_receive_bytes_total{instance="172.31.22.69:9100",device="eth0"}[5m])' | python3 -m json.tool
```

---

### Step 1.6: Remediate - Apply Common Fixes

Based on your diagnosis, the WAL receiver is connected and receiving data, but WAL replay on the replica is slow due to high I/O wait. Here are the remediation steps in order of invasiveness.

**Fix 1 (Low risk): Check if replay is paused**

Sometimes the WAL receiver gets into a slow state and a restart helps. First check if the replica is in paused recovery mode.

On **pg-replica**, as **postgres**:

```bash
psql -c "SELECT pg_is_wal_replay_paused();"
```

Expected output (yours will differ):

```
 pg_is_wal_replay_paused
--------------------------
 f
(1 row)
```

`f` means replay is not paused. If it were `t`, you would run `SELECT pg_wal_replay_resume();` to unpause it.

**Fix 2 (Low risk): Force a checkpoint on the primary**

A checkpoint flushes dirty pages to disk and can reduce the write load on the replica's recovery process by giving it a clean starting point.

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -c "CHECKPOINT;"
```

Expected output (yours will differ):

```
CHECKPOINT
```

The checkpoint completes immediately. Now monitor whether lag starts decreasing.

**Fix 3 (Moderate risk): Restart walreceiver via pg_terminate_backend**

If the WAL receiver process seems stuck, you can terminate it. PostgreSQL will immediately restart it.

First, find the walreceiver PID on the replica.

On **pg-replica**, as **postgres**:

```bash
psql -c "SELECT pid FROM pg_stat_activity WHERE backend_type = 'walreceiver';"
```

Expected output (yours will differ):

```
 pid
------
 5678
(1 row)
```

Terminate the process:

```bash
psql -c "SELECT pg_terminate_backend(5678);"
```

PostgreSQL will start a new walreceiver process within seconds. Watch the log to confirm:

```bash
exit
```

On **pg-replica**, as **ec2-user**:

```bash
sudo tail -f /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log | grep -i "walreceiver\|replication\|recovery"
```

Press `Ctrl+C` when you see the walreceiver reconnect message.

Expected output (yours will differ):

```
2026-06-18 03:09:14 UTC [5679]: LOG:  started streaming WAL from primary at 0/A1234500
2026-06-18 03:09:14 UTC [5679]: LOG:  replication connection established
```

---

### Step 1.7: Verify - Confirm Lag Is Decreasing

Go back to **pg-ops** and watch the lag metric.

On **pg-ops**, as **ec2-user**:

Poll the replication lag every 15 seconds for 2 minutes to watch it change:

```bash
for i in $(seq 1 8); do
  echo "--- Check $i at $(date +%H:%M:%S) ---"
  curl -s 'http://localhost:9090/api/v1/query?query=pg_replication_lag_seconds' | python3 -c "import sys,json; data=json.load(sys.stdin); [print(r['metric'].get('instance','?'), '->', r['value'][1]+'s') for r in data['data']['result']]"
  sleep 15
done
```

This loop runs 8 checks, 15 seconds apart. Watch the lag value decrease over time.

Expected output (yours will differ):

```
--- Check 1 at 03:09:20 ---
172.31.22.69:9187 -> 47.3s
--- Check 2 at 03:09:35 ---
172.31.22.69:9187 -> 38.1s
--- Check 3 at 03:09:50 ---
172.31.22.69:9187 -> 29.4s
--- Check 4 at 03:10:05 ---
172.31.22.69:9187 -> 18.2s
...
--- Check 8 at 03:11:05 ---
172.31.22.69:9187 -> 1.3s
```

As the lag drops below 30 seconds, Prometheus will move the alert from `firing` to `pending` and then auto-resolve it after the configured `for` duration.

Confirm the alert is no longer firing:

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool | grep -E '"state"|"alertname"'
```

Expected output (yours will differ):

```json
            "alertname": "ReplicationLagCritical",
            "state": "suppressed"
```

Or, if it has fully resolved, the alert list will be empty.

---

### Step 1.8: Document - Write the Incident Summary

Open a notes file on pg-ops to write up the incident summary.

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/incident-$(date +%Y%m%d-%H%M).md
```

Press `i` to enter insert mode and write your summary using this template:

```
## Incident Summary

Date: 2026-06-18
Duration: 03:02 AM - 03:11 AM UTC (9 minutes)
Severity: Critical
Alert: ReplicationLagCritical

Timeline
- 03:02 - Alert fires. Replica lag exceeds 30s.
- 03:03 - Triage: Alertmanager confirms single alert, no cascading failures.
- 03:04 - Assessment: PromQL shows lag at 47.3s, growing at 0.8s/s.
- 03:05 - Diagnosis: pg_stat_replication shows state=streaming, replay_lag=47s.
           WAL receiver healthy. Bottleneck is replay speed on replica.
- 03:06 - Correlation: node_exporter iowait spiked on replica at 03:02.
           Disk write throughput dropped at same time.
- 03:07 - Remediation: Forced CHECKPOINT on primary.
           Restarted walreceiver on replica via pg_terminate_backend.
- 03:09 - Recovery: Lag decreasing. 47s -> 18s -> 1s.
- 03:11 - Alert resolved. Replication caught up.

Root Cause
High I/O wait on pg-replica caused WAL replay to slow down.
WAL was being received but not applied fast enough.
Suspected cause: EC2 EBS throughput burst bucket exhausted.

Action Items
1. Add a Grafana panel for replica iowait alongside replication lag.
2. Review EBS volume type on pg-replica - consider GP3 with provisioned IOPS.
3. Add a recording rule for iowait to make alerting easier.
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

**Interview talking point:** "When I'm paged, I follow a structured workflow: triage in Alertmanager, assess with PromQL before touching any servers, diagnose with PostgreSQL system views, correlate with system metrics to find root cause, remediate in order of least to most invasive, verify with the same metrics I started with, and document with a timeline. The documentation step is not optional - it is how the team learns and prevents recurrence."

---

## Exercise 2: Capacity Planning with PromQL (25 min)

**Scenario:** Ed asks in the interview: "How would you figure out when we need to add more disk capacity?" Instead of guessing, you are going to use PromQL to answer five specific capacity questions with real data.

SSH into pg-ops if you are not already there. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

---

### Step 2.1: Average Daily WAL Generation

**Question:** How much WAL does the primary generate per day?

On **pg-ops**, as **ec2-user**:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=increase(pg_stat_replication_pg_stat_replication_pg_current_wal_lsn_bytes{instance="172.31.19.86:9187"}[24h])' | python3 -m json.tool
```

`increase()` returns the total increase of a gauge or counter over the given time range. Here it shows how many bytes the WAL directory grew in the last 24 hours. This is an approximation - WAL files are recycled, so `pg_stat_replication_pg_stat_replication_pg_current_wal_lsn_bytes` may not grow linearly.

A more accurate approach is to use the LSN position counter:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=increase(pg_stat_replication_pg_current_wal_lsn_bytes{instance="172.31.19.86:9187"}[24h])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "536870912" ]
            }
        ]
    }
}
```

`536870912` bytes is 512 MB of WAL generated per day. Convert that to a human-readable number:

```bash
python3 -c "print(f'{536870912 / 1024 / 1024:.0f} MB/day or {536870912 / 1024 / 1024 / 1024:.2f} GB/day')"
```

Expected output (yours will differ):

```
512 MB/day or 0.50 GB/day
```

**Write your result:**

```
Average WAL generation: ____ MB/day
Weekly: ____ GB
Monthly: ____ GB
```

**Recommendation:** If WAL archiving is enabled, the archive destination needs at least `daily_wal * retention_days` of free space.

---

### Step 2.2: Predict When Disk Will Hit 80%

**Question:** At the current growth rate, when will the root filesystem on pg-primary hit 80% full?

On **pg-ops**, as **ec2-user**:

First, check current disk usage percentage:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=100-(node_filesystem_avail_bytes{instance="172.31.19.86:9100",mountpoint="/"}/node_filesystem_size_bytes{instance="172.31.19.86:9100",mountpoint="/"} * 100)' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100", "mountpoint": "/" },
                "value": [ 1750208534, "34.7" ]
            }
        ]
    }
}
```

Current usage is 34.7%. Now use `predict_linear` to project the available bytes 30 days from now:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=predict_linear(node_filesystem_avail_bytes{instance="172.31.19.86:9100",mountpoint="/"}[7d],86400*30)' | python3 -m json.tool
```

`predict_linear(v, t)` extrapolates the value `t` seconds into the future based on a linear regression of the last 7 days. The result is the predicted number of available bytes 30 days from now.

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100", "mountpoint": "/" },
                "value": [ 1750208534, "8589934592" ]
            }
        ]
    }
}
```

Convert the predicted available bytes to a percentage. Get the total size first:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=node_filesystem_size_bytes{instance="172.31.19.86:9100",mountpoint="/"}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
size = float(data['data']['result'][0]['value'][1])
avail_in_30d = 8589934592
used_in_30d = size - avail_in_30d
pct_in_30d = (used_in_30d / size) * 100
print(f'Disk size: {size/1024/1024/1024:.1f} GB')
print(f'Predicted available in 30 days: {avail_in_30d/1024/1024/1024:.1f} GB')
print(f'Predicted usage in 30 days: {pct_in_30d:.1f}%')
"
```

Expected output (yours will differ):

```
Disk size: 30.0 GB
Predicted available in 30 days: 8.0 GB
Predicted usage in 30 days: 73.3%
```

**Write your result:**

```
Current disk usage: ____%
Predicted disk usage in 30 days: ____%
Will we hit 80% in 30 days? Yes / No
```

**Recommendation:** If the 30-day projection is above 75%, open a ticket to expand the volume before it becomes an incident.

---

### Step 2.3: Peak Connection Count and Timing

**Question:** What is the peak connection count over the last 24 hours, and when does it occur?

On **pg-ops**, as **ec2-user**:

Find the maximum connection count in the last 24 hours:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time(pg_stat_database_numbackends{datname="quantdb",instance="172.31.19.86:9187"}[24h])' | python3 -m json.tool
```

`max_over_time()` returns the maximum value of a metric over a time range. This tells you the highest number of connections seen in the last 24 hours.

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "87" ]
            }
        ]
    }
}
```

Now compare to `max_connections` to understand headroom:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_settings_max_connections{instance="172.31.19.86:9187"}' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "200" ]
            }
        ]
    }
}
```

Calculate headroom:

```bash
python3 -c "
peak = 87
max_conn = 200
headroom = max_conn - peak
pct_used = (peak / max_conn) * 100
print(f'Peak connections: {peak}')
print(f'max_connections: {max_conn}')
print(f'Headroom: {headroom} connections ({100-pct_used:.0f}%)')
"
```

Expected output (yours will differ):

```
Peak connections: 87
max_connections: 200
Headroom: 113 connections (56%)
```

**Write your result:**

```
Peak connections (last 24h): ____
max_connections setting: ____
Headroom: ____ connections (___%)
```

**Recommendation:** If peak connections exceed 80% of `max_connections`, consider implementing a connection pooler (PgBouncer) or increasing `max_connections` (note: this increases memory usage).

---

### Step 2.4: 95th Percentile Query Duration

**Question:** What is the 95th percentile query duration for quantdb?

On **pg-ops**, as **ec2-user**:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,rate(pg_stat_statements_seconds_bucket{datname="quantdb"}[1h]))' | python3 -m json.tool
```

`histogram_quantile(0.95, ...)` calculates the 95th percentile from a histogram metric. This means 95% of queries complete faster than this value.

Note: `pg_stat_statements` histogram metrics require a custom postgres_exporter configuration. If this query returns no data, try this alternative using the max transaction duration:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_activity_max_tx_duration{datname="quantdb",instance="172.31.19.86:9187"}' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "0.342" ]
            }
        ]
    }
}
```

A max transaction duration of 0.342 seconds means the slowest active transaction has been running for 342 milliseconds. If this value stays low (under 1 second during normal operation), query performance is acceptable.

**Write your result:**

```
P95 query duration: ____ ms
Max active transaction duration: ____ ms
Is this acceptable? Yes / No (threshold: ___ ms)
```

**Recommendation:** If P95 query duration exceeds your SLA target, investigate with `pg_stat_statements` to find the slow queries.

---

### Step 2.5: CPU Headroom

**Question:** How much CPU headroom do we have on the primary?

On **pg-ops**, as **ec2-user**:

Check current CPU usage on pg-primary:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=100-(avg+by(instance)(rate(node_cpu_seconds_total{instance="172.31.19.86:9100",mode="idle"}[5m]))*100)' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "23.4" ]
            }
        ]
    }
}
```

Current CPU usage is 23.4%. Check the peak CPU over the last 24 hours:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time((100-(avg+by(instance)(rate(node_cpu_seconds_total{instance="172.31.19.86:9100",mode="idle"}[5m]))*100))[24h:5m])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "61.2" ]
            }
        ]
    }
}
```

**Write your result:**

```
Current CPU usage: ____%
Peak CPU usage (last 24h): ____%
Headroom at peak: ____%
```

**Recommendation:** If peak CPU exceeds 70% regularly, investigate query optimization or consider vertical scaling. CPU headroom below 30% at peak is a warning sign.

---

### Capacity Planning Summary Table

Fill this in from your query results:

| Metric | Current Value | Threshold | Status |
|--------|--------------|-----------|--------|
| WAL generation | ___ MB/day | Archive disk budget | OK / Warning |
| Disk usage (30-day projection) | ___% | 80% | OK / Warning |
| Peak connections | ___ / ___ | 80% of max_connections | OK / Warning |
| P95 query duration | ___ ms | SLA target | OK / Warning |
| Peak CPU | ___% | 70% | OK / Warning |

**Interview talking point:** "For capacity planning, I use PromQL's `predict_linear()` and `max_over_time()` to answer concrete questions: when will disk fill up, how close are we to connection limits, what is the query latency trend. I build this into a monthly capacity review process so we are never surprised by resource exhaustion."

---

## Exercise 3: Building a Runbook from Metrics (20 min)

**Scenario:** The "DiskSpaceLow" alert fires on pg-primary. Your task is to build an operational runbook by using PromQL to guide each decision step - confirming the problem, identifying the cause, taking action, and verifying recovery.

SSH into pg-ops if you are not already there.

---

### Step 3.1: Confirm the Alert - Query Current Disk Usage

Do not assume the alert is accurate. Confirm it with a direct query before taking any action.

On **pg-ops**, as **ec2-user**:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=node_filesystem_avail_bytes{instance="172.31.19.86:9100"}/node_filesystem_size_bytes{instance="172.31.19.86:9100"}*100' | python3 -m json.tool
```

This returns the percentage of disk available (not used). Lower is worse.

Expected output (yours will differ):

```json
{
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "mountpoint": "/", "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "18.3" ]
            },
            {
                "metric": { "mountpoint": "/opt/pgsql", "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "12.7" ]
            }
        ]
    }
}
```

Two filesystems are reported. The `/opt/pgsql` mount is at 12.7% free (87.3% used) - that is the critical one. The data directory is nearly full.

**Write it down:**

```
Filesystem: /opt/pgsql
Available: 12.7%
Used: 87.3%
Alert threshold: 15% free (confirmed: YES, this is below threshold)
```

---

### Step 3.2: Identify the Cause - Which Filesystem, Growth Rate

Find out which filesystem is growing fastest and how fast it is growing.

On **pg-ops**, as **ec2-user**:

Check the growth rate of the `/opt/pgsql` mount over the last hour:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=-deriv(node_filesystem_avail_bytes{instance="172.31.19.86:9100",mountpoint="/opt/pgsql"}[1h])' | python3 -m json.tool
```

The negative sign on `deriv()` converts the rate of available bytes decreasing into a positive "consumption rate." The result is bytes per second being consumed.

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "mountpoint": "/opt/pgsql", "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "52428800" ]
            }
        ]
    }
}
```

`52428800` bytes per second is 50 MB/s - that is unusually high. Something is writing to `/opt/pgsql` at 50 MB/s.

Calculate how long before the disk is completely full:

```bash
python3 -c "
avail_bytes = 0.127 * 100 * 1024 * 1024 * 1024  # 12.7% of 100GB
growth_rate = 52428800  # bytes/second
seconds_left = avail_bytes / growth_rate
hours_left = seconds_left / 3600
print(f'Estimated time until full: {hours_left:.1f} hours')
"
```

Expected output (yours will differ):

```
Estimated time until full: 0.7 hours
```

Less than an hour. This is urgent.

---

### Step 3.3: Find Large Files - Correlate with PG Metrics

Use PostgreSQL metrics to identify which component is consuming the space.

On **pg-ops**, as **ec2-user**:

Check WAL directory size:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_replication_pg_stat_replication_pg_current_wal_lsn_bytes{instance="172.31.19.86:9187"}' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "3221225472" ]
            }
        ]
    }
}
```

`3221225472` bytes is 3 GB of WAL. Check if this is growing:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=deriv(pg_stat_replication_pg_stat_replication_pg_current_wal_lsn_bytes{instance="172.31.19.86:9187"}[30m])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "10485760" ]
            }
        ]
    }
}
```

WAL is growing at 10 MB/s over the last 30 minutes. That is significant.

Check dead tuple count to see if tables need vacuuming (dead tuples increase table bloat):

```bash
curl -s 'http://localhost:9090/api/v1/query?query=topk(5,pg_stat_user_tables_n_dead_tup{datname="quantdb",instance="172.31.19.86:9187"})' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "relname": "market_events", "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "5823401" ]
            },
            ...
        ]
    }
}
```

The `market_events` table has 5.8 million dead tuples. That is a lot of bloat that could be reclaimed with a VACUUM.

Now check for temporary file usage (temp files are written to disk during large sorts and hash joins):

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_database_temp_bytes{datname="quantdb",instance="172.31.19.86:9187"}' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "8589934592" ]
            }
        ]
    }
}
```

`8589934592` bytes is 8 GB of temp files written since the last server restart. High temp file usage means queries are spilling to disk because `work_mem` is too low.

Summary of findings:
- WAL directory: 3 GB and growing (10 MB/s)
- Dead tuples on `market_events`: 5.8 million (bloat)
- Temp file usage: 8 GB (queries spilling to disk)

---

### Step 3.4: Take Action

Address each cause in order of speed and impact.

**Action 1: VACUUM the bloated table**

SSH to pg-primary. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -c "VACUUM VERBOSE market_events;"
```

`VACUUM VERBOSE` reclaims space from dead tuples and prints progress so you can see what it is doing.

Expected output (yours will differ):

```
INFO:  vacuuming "public.market_events"
INFO:  scanned index "market_events_pkey" to remove 5823401 row versions
INFO:  "market_events": removed 5823401 row versions in 29117 pages
INFO:  "market_events": found 5823401 removable, 12000000 nonremovable row versions
INFO:  free space: removed 5823401 dead row versions, recovering 2.8 GB
VACUUM
```

**Action 2: Check and clean WAL archive backlog**

If WAL archiving is enabled, a failed `archive_command` causes WAL files to pile up:

```bash
psql -d quantdb -c "SELECT last_failed_wal, last_failed_time, last_archived_wal, last_archived_time FROM pg_stat_archiver;"
```

Expected output (yours will differ):

```
    last_failed_wal    |     last_failed_time      | last_archived_wal  | last_archived_time
-----------------------+---------------------------+--------------------+---------------------------
 000000010000000A001F  | 2026-06-18 02:55:12+00    | 000000010000000A001E | 2026-06-18 02:54:55+00
```

If `last_failed_wal` is recent and `last_archived_wal` is behind it, the archiver has been failing. Fix the archive destination issue, then reset the archiver:

```bash
psql -d quantdb -c "SELECT pg_switch_wal();"
```

`pg_switch_wal()` forces a WAL segment switch, which triggers the archiver to retry the pending file.

**Action 3: Check for temp files in PostgreSQL data directory**

```bash
find /opt/pgsql/data/base/pgsql_tmp -name "pgsql_tmp*" -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -10
```

If you see large temp files (over 100 MB each), they are from queries currently running or recently crashed. If the queries have finished, the files should be cleaned up by PostgreSQL automatically.

Exit the postgres shell when done:

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
exit
```

---

### Step 3.5: Verify - Disk Usage Decreasing

Go back to **pg-ops** and watch disk usage.

On **pg-ops**, as **ec2-user**:

Poll disk usage every 30 seconds:

```bash
for i in $(seq 1 6); do
  echo "--- Check $i at $(date +%H:%M:%S) ---"
  curl -s 'http://localhost:9090/api/v1/query?query=100-(node_filesystem_avail_bytes{instance="172.31.19.86:9100",mountpoint="/opt/pgsql"}/node_filesystem_size_bytes{instance="172.31.19.86:9100",mountpoint="/opt/pgsql"}*100)' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'{r[\"metric\"][\"mountpoint\"]}: {float(r[\"value\"][1]):.1f}% used') for r in d['data']['result']]"
  sleep 30
done
```

Expected output (yours will differ):

```
--- Check 1 at 03:22:00 ---
/opt/pgsql: 87.3% used
--- Check 2 at 03:22:30 ---
/opt/pgsql: 84.1% used
--- Check 3 at 03:23:00 ---
/opt/pgsql: 80.6% used
...
```

As VACUUM frees space, the used percentage should drop. If it does not drop, the dominant cause is WAL accumulation, not dead tuples.

---

### Step 3.6: Prevent - Set Up a Recording Rule for Disk Growth

A recording rule pre-computes an expensive query and stores it as a new metric. This makes dashboards faster and alerting simpler.

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/disk_recording_rules.yml
```

Press `i` to enter insert mode and type:

```yaml
groups:
  - name: disk_capacity
    interval: 5m
    rules:
      - record: node:disk_used_pct:avg5m
        expr: |
          100 - (
            node_filesystem_avail_bytes{fstype!="tmpfs"}
            / node_filesystem_size_bytes{fstype!="tmpfs"}
            * 100
          )

      - alert: DiskWillFillIn4Hours
        expr: |
          predict_linear(
            node_filesystem_avail_bytes{fstype!="tmpfs",instance=~"172.31.19.86.*|172.31.22.69.*|172.31.26.19.*"}[1h],
            4*3600
          ) < 0
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "Disk on {{ $labels.instance }} ({{ $labels.mountpoint }}) predicted full within 4 hours"
          description: "At the current growth rate, the filesystem will run out of space in less than 4 hours."
          runbook: "Check WAL directory, dead tuples, and temp files. Run VACUUM. Check archive_command."
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

Validate the rules file:

```bash
/opt/prometheus/promtool check rules /tmp/disk_recording_rules.yml
```

Expected output (yours will differ):

```
Checking /tmp/disk_recording_rules.yml
  SUCCESS: 2 rules found
```

Copy to Prometheus and reload:

```bash
sudo cp /tmp/disk_recording_rules.yml /opt/prometheus/disk_recording_rules.yml
sudo chown ec2-user:ec2-user /opt/prometheus/disk_recording_rules.yml
```

Add to Prometheus config:

```bash
sudo vi /opt/prometheus/prometheus.yml
```

Add `"disk_recording_rules.yml"` under `rule_files:`, then press `Esc` and type `:wq` to save.

```bash
sudo systemctl reload prometheus
```

**Interview talking point:** "When I fix a DiskSpaceLow incident, I always come out of it with a new predictive alert - `predict_linear(avail_bytes[1h], 4*3600) < 0` - that fires 4 hours before the disk fills up. That way I go from reacting to disk full alerts at 3 AM to getting a warning during business hours when I can act calmly."

---

## Exercise 4: Multi-Signal Correlation (25 min)

**Scenario:** Application engineers report that their app is getting intermittent connection timeouts - sometimes requests fail, sometimes they succeed. There are no obvious single-metric alerts firing. Your job is to correlate multiple signal sources to find the cause.

SSH into pg-ops if you are not already there.

---

### Step 4.1: Check PostgreSQL Connection Count Over the Last Hour

When applications time out trying to connect, the first thing to check is whether the connection count is near `max_connections`.

On **pg-ops**, as **ec2-user**:

Check the maximum connection count in the last hour:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time(pg_stat_database_numbackends{datname="quantdb",instance="172.31.19.86:9187"}[1h])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "178" ]
            }
        ]
    }
}
```

Peak connections in the last hour: 178. If `max_connections` is 200, that is 89% of capacity. When new connection attempts arrive and all 200 slots are taken, PostgreSQL rejects them with "FATAL: sorry, too many clients already" - which looks like a timeout to the application.

**Write it down:**

```
Max connections (last 1h): ____
max_connections setting: ____
% of capacity: ____%
Signal strength: High / Medium / Low
```

---

### Step 4.2: Check PostgreSQL Lock Waits

Timeouts can also come from queries waiting on locks for too long.

On **pg-ops**, as **ec2-user**:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_locks_count{datname="quantdb",instance="172.31.19.86:9187"}' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "datname": "quantdb", "mode": "accesssharelock", "instance": "172.31.19.86:9187" },
                "value": [ 1750208534, "12" ]
            }
        ]
    }
}
```

12 connections are currently waiting on locks. That is significant. Check if this is elevated compared to the past hour:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time(pg_locks_count{datname="quantdb",instance="172.31.19.86:9187"}[1h])' | python3 -m json.tool
```

If the max lock wait count is much higher than the current value, there were lock spikes earlier that correlate with the reported timeout window.

To visualize the trend, open your browser and go to `http://34.228.32.17:9090/graph`. Run this query and set the time range to "Last 1 hour":

```
pg_locks_count{datname="quantdb"}
```

Look for spikes that correlate with the time the application reported timeouts.

**Write it down:**

```
Current lock waiters: ____
Max lock waiters (last 1h): ____
Signal strength: High / Medium / Low
```

---

### Step 4.3: Check System CPU and I/O

High CPU and I/O on the primary can slow query execution, causing application requests to pile up and eventually time out.

On **pg-ops**, as **ec2-user**:

Check peak CPU usage over the last hour:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time((100-(avg+by(instance)(rate(node_cpu_seconds_total{instance="172.31.19.86:9100",mode="idle"}[5m]))*100))[1h:5m])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "94.2" ]
            }
        ]
    }
}
```

Peak CPU at 94.2% in the last hour. That is very high and a strong signal that the primary was under heavy load.

Check I/O utilization (disk busy time as a percentage):

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time(rate(node_disk_io_time_seconds_total{instance="172.31.19.86:9100"}[5m])[1h:5m])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100", "device": "xvda" },
                "value": [ 1750208534, "0.98" ]
            }
        ]
    }
}
```

`0.98` means the disk was busy 98% of the time during the peak. At near-100% I/O utilization, new I/O requests queue up, queries slow down, and connection slots fill up waiting for slow queries to finish.

**Write it down:**

```
Peak CPU (last 1h): ____%
Peak I/O utilization (last 1h): ____%
Signal strength: High / Medium / Low
```

---

### Step 4.4: Check Network Packet Drops and Retransmits

Network problems between the application servers and PostgreSQL can cause partial or delayed connections that look like timeouts.

On **pg-ops**, as **ec2-user**:

Check packet receive errors on pg-primary's network interface:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(node_network_receive_errs_total{instance="172.31.19.86:9100",device="eth0"}[5m])' | python3 -m json.tool
```

Check TCP retransmit rate:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(node_netstat_Tcp_RetransSegs{instance="172.31.19.86:9100"}[5m])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100" },
                "value": [ 1750208534, "0.03" ]
            }
        ]
    }
}
```

`0.03` retransmits per second is low - network looks healthy. This signal is negative (not the cause).

**Write it down:**

```
Network receive errors: ____/s
TCP retransmits: ____/s
Signal strength: High / Medium / Low
```

---

### Step 4.5: Check Replication Lag as a Proxy for Primary Overload

When the primary is under very high load, it sometimes cannot send WAL to the replica fast enough. A sudden spike in replication lag is a strong indicator that the primary was overloaded.

On **pg-ops**, as **ec2-user**:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=max_over_time(pg_replication_lag_seconds[1h])' | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "data": {
        "result": [
            {
                "metric": { "instance": "172.31.22.69:9187" },
                "value": [ 1750208534, "23.4" ]
            }
        ]
    }
}
```

Peak replication lag of 23.4 seconds in the last hour. Below the 30-second alert threshold, but elevated enough to suggest the primary was under load during that period.

**Write it down:**

```
Max replication lag (last 1h): ____ seconds
Correlates with CPU spike: Yes / No
Signal strength: High / Medium / Low
```

---

### Step 4.6: Check PgBouncer Stats

If your infrastructure includes PgBouncer as a connection pooler between the application and PostgreSQL, check its stats. A full pool or high wait times in PgBouncer will directly cause application connection timeouts.

On **pg-ops**, as **ec2-user**:

Check if PgBouncer metrics are available:

```bash
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep pgbouncer
```

Expected output if PgBouncer is not installed (yours will differ):

```
(empty - no pgbouncer metrics found)
```

If PgBouncer is not deployed in this lab, note it and move on. In a real Voleon environment, PgBouncer stats to check would include:

| Metric | What to Look For |
|--------|-----------------|
| `pgbouncer_pools_cl_waiting` | Clients waiting for a server connection. Should be near 0. |
| `pgbouncer_pools_sv_active` | Active server connections. Compare to pool_size. |
| `pgbouncer_stats_total_wait_time` | Total time clients waited for a connection. Spikes here mean pool exhaustion. |

**Write it down:**

```
PgBouncer deployed: Yes / No
If yes, pool waiting clients during spike: ____
Signal strength: High / Medium / Low / N/A
```

---

### Step 4.7: Build a Grafana Dashboard Row

Now build a single dashboard that shows all five signals side by side, so you can visually correlate them in future incidents.

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/correlation-dashboard.json
```

Press `i` to enter insert mode and type:

```json
{
  "dashboard": {
    "title": "Multi-Signal Correlation - Timeout Diagnosis",
    "tags": ["postgresql", "incident", "correlation"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "title": "Active Connections (quantdb)",
        "type": "timeseries",
        "gridPos": { "h": 6, "w": 8, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "pg_stat_database_numbackends{datname=\"quantdb\", instance=\"172.31.19.86:9187\"}",
            "legendFormat": "connections",
            "refId": "A"
          },
          {
            "expr": "pg_settings_max_connections{instance=\"172.31.19.86:9187\"}",
            "legendFormat": "max_connections",
            "refId": "B"
          }
        ],
        "datasource": { "type": "prometheus", "uid": "dfpkj7ljqzfnka" },
        "fieldConfig": { "defaults": { "unit": "short" } }
      },
      {
        "id": 2,
        "title": "Lock Wait Count (quantdb)",
        "type": "timeseries",
        "gridPos": { "h": 6, "w": 8, "x": 8, "y": 0 },
        "targets": [
          {
            "expr": "pg_locks_count{datname=\"quantdb\", instance=\"172.31.19.86:9187\"}",
            "legendFormat": "lock waiters",
            "refId": "A"
          }
        ],
        "datasource": { "type": "prometheus", "uid": "dfpkj7ljqzfnka" },
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 5 },
                { "color": "red", "value": 20 }
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "title": "Primary CPU Usage (%)",
        "type": "timeseries",
        "gridPos": { "h": 6, "w": 8, "x": 16, "y": 0 },
        "targets": [
          {
            "expr": "100 - (avg by(instance)(rate(node_cpu_seconds_total{instance=\"172.31.19.86:9100\", mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "cpu %",
            "refId": "A"
          }
        ],
        "datasource": { "type": "prometheus", "uid": "dfpkj7ljqzfnka" },
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 70 },
                { "color": "red", "value": 90 }
              ]
            }
          }
        }
      },
      {
        "id": 4,
        "title": "TCP Retransmits (primary)",
        "type": "timeseries",
        "gridPos": { "h": 6, "w": 8, "x": 0, "y": 6 },
        "targets": [
          {
            "expr": "rate(node_netstat_Tcp_RetransSegs{instance=\"172.31.19.86:9100\"}[5m])",
            "legendFormat": "retransmits/s",
            "refId": "A"
          }
        ],
        "datasource": { "type": "prometheus", "uid": "dfpkj7ljqzfnka" },
        "fieldConfig": { "defaults": { "unit": "short" } }
      },
      {
        "id": 5,
        "title": "Replication Lag (seconds)",
        "type": "timeseries",
        "gridPos": { "h": 6, "w": 8, "x": 8, "y": 6 },
        "targets": [
          {
            "expr": "pg_replication_lag_seconds",
            "legendFormat": "lag",
            "refId": "A"
          }
        ],
        "datasource": { "type": "prometheus", "uid": "dfpkj7ljqzfnka" },
        "fieldConfig": {
          "defaults": {
            "unit": "s",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 5 },
                { "color": "red", "value": 30 }
              ]
            }
          }
        }
      },
      {
        "id": 6,
        "title": "Disk I/O Utilization (primary)",
        "type": "timeseries",
        "gridPos": { "h": 6, "w": 8, "x": 16, "y": 6 },
        "targets": [
          {
            "expr": "rate(node_disk_io_time_seconds_total{instance=\"172.31.19.86:9100\"}[5m])",
            "legendFormat": "{{ device }} utilization",
            "refId": "A"
          }
        ],
        "datasource": { "type": "prometheus", "uid": "dfpkj7ljqzfnka" },
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "min": 0,
            "max": 1,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 0.7 },
                { "color": "red", "value": 0.9 }
              ]
            }
          }
        }
      }
    ]
  },
  "overwrite": true
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

Push the dashboard to Grafana:

```bash
curl -s -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @/tmp/correlation-dashboard.json | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "id": 3,
    "uid": "xyz789abc",
    "url": "/d/xyz789abc/multi-signal-correlation-timeout-diagnosis",
    "status": "success",
    "version": 1
}
```

Open the dashboard in your browser:

```
http://34.228.32.17:3000
```

Navigate to **Dashboards** and find **Multi-Signal Correlation - Timeout Diagnosis**. You should see six panels arranged in two rows. The top row shows connections, lock waits, and CPU. The bottom row shows network retransmits, replication lag, and disk I/O. All six signals on one screen.

---

### Step 4.8: Write the Diagnosis Summary

Based on the signals you collected, write a diagnosis summary. Fill in the blanks using your actual query results.

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/timeout-diagnosis-$(date +%Y%m%d-%H%M).md
```

Press `i` to enter insert mode and write:

```
## Timeout Incident Diagnosis

Reported symptom: Intermittent connection timeouts from application
Investigation period: Last 1 hour
Date: 2026-06-18

### Signals Checked

Signal            | Value        | Threshold                    | Status
Max connections   | 178 / 200    | 80% = 160                    | HIGH
Max lock waiters  | 12           | 5 = warning, 20 = critical   | ELEVATED
Peak CPU          | 94.2%        | 70% = warning, 90% = critical| HIGH
I/O utilization   | 98%          | 70% = warning, 90% = critical| CRITICAL
TCP retransmits   | 0.03/s       | < 1/s = normal               | NORMAL
Replication lag   | 23.4s max    | 30s = alert                  | ELEVATED

### Root Cause Assessment

The primary cause is I/O saturation on pg-primary (98% disk busy).
When disk I/O is saturated, queries that need to read or write data slow down.
Slow queries hold database connections for longer, causing the connection
count to approach max_connections (178/200 - 89% capacity).
When new connection attempts arrive and all slots are taken, PostgreSQL
rejects them, which the application reports as a timeout.

The lock wait count (12) is a secondary symptom caused by the same slow queries
holding locks for longer than normal while waiting for I/O.

Network is not a factor (retransmits are low).

### Contributing Factors

1. I/O saturation was likely caused by EBS burst balance being depleted
   on the GP2 volume. Check AWS CloudWatch for the instance.
2. High connection count is a risk factor. Recommend deploying PgBouncer
   to pool connections and reduce the peak connection footprint.
3. Replication lag spike confirms primary was under heavy load.

### Immediate Recommendations

1. Check AWS CloudWatch - EC2 instance EBS burst balance for pg-primary.
   If depleted, upgrade volume from GP2 to GP3 with provisioned IOPS.
2. Deploy PgBouncer on pg-ops or application servers to pool connections.
   Set pool_size = 20-30 for quantdb. This will reduce connection count
   from ~178 to ~30 on the PostgreSQL side.
3. Investigate what caused the I/O spike - was it a large batch job,
   autovacuum, or a query plan regression?

### Preventive Monitoring Added

- Dashboard: Multi-Signal Correlation - Timeout Diagnosis (Grafana)
- Alert: DiskWillFillIn4Hours (Prometheus) - predictive disk alert
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

**Interview talking point:** "For intermittent timeouts, I never look at just one metric. I check connections, locks, CPU, I/O, network, and replication lag all over the same time window. Usually, one metric is the root cause and the others are downstream symptoms. In this case, I/O saturation was the root cause - it slowed queries, which filled connection slots, which caused timeouts. Understanding that causal chain is what separates a real fix from a temporary workaround."

---

## Summary

You have practiced four incident response workflows that cover the full operational spectrum:

| Exercise | Skill | Time | Interview Relevance |
|---|---|---|---|
| 1. 3 AM Alert | Triage, assess, diagnose, remediate, verify, document | 30 min | "Walk me through how you handle an on-call incident" |
| 2. Capacity Planning | PromQL for predict_linear, max_over_time, deriv | 25 min | "How do you know when to add more resources?" |
| 3. Runbook from Metrics | Confirm, identify cause, act, verify, prevent | 20 min | "How do you respond to a DiskSpaceLow alert?" |
| 4. Multi-Signal Correlation | Six signals, Grafana dashboard, diagnosis summary | 25 min | "How do you debug intermittent timeouts?" |

Each exercise follows the same structure that experienced DBAs use in real incidents: measure first, diagnose before touching anything, fix in order of least invasiveness, verify with the same metrics you started with, and document so the team learns.
