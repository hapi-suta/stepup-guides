# SURVIVE 05 - Serverless v2 Scaling Stuck Runbook
## Incident: Aurora Serverless v2 at ACU Maximum - Queries Queuing

---

## What You Are Seeing

Users are reporting slow queries and timeouts. CloudWatch shows:

```
ALARM: serverless-capacity-high
Metric: ServerlessDatabaseCapacity = 2.0 (maximum configured)
Duration: 15+ minutes
```

New connections are timing out:
```
psql: error: connection to server failed: FATAL: remaining connection slots are reserved
```

---

## Step 1 - Confirm the Cluster Is Pinned at Its ACU Ceiling

Check the current capacity:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average Maximum \
  --region us-east-1
```

Expected output during the incident (yours will differ):
```json
{
    "Datapoints": [
        {"Timestamp": "15:00:00", "Average": 2.0, "Maximum": 2.0},
        {"Timestamp": "15:01:00", "Average": 2.0, "Maximum": 2.0},
        {"Timestamp": "15:02:00", "Average": 2.0, "Maximum": 2.0}
    ]
}
```

When `Average` equals `Maximum` and both equal the configured ceiling, the cluster cannot scale higher. It is stuck.

Check the configured maximum:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-serverless-cluster \
  --query 'DBClusters[0].ServerlessV2ScalingConfiguration' \
  --output table \
  --region us-east-1
```

Expected output:
```
---------------------------------------
|       DescribeDBClusters            |
+----------------+--------------------+
| MaxCapacity    | 2.0                |
| MinCapacity    | 0.5                |
+----------------+--------------------+
```

`MaxCapacity: 2.0` - the cluster can never go above 2 ACU. This is why it is stuck.

---

## Step 2 - Check How Many Connections Are Waiting

Connect if you can still get through (connection slots may be limited):

```bash
psql -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     --connect-timeout=10
```

If you can connect:

```sql
-- Check total connections
SELECT
    COUNT(*) AS total_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle,
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting
FROM pg_stat_activity;
```

Expected output during the incident:
```
 total_connections | active | idle | waiting
-------------------+--------+------+---------
                48 |     45 |    3 |      38
```

38 connections are waiting (blocked). The cluster cannot process them because it is at CPU capacity.

```sql
-- Check what the waiting connections are waiting for
SELECT
    wait_event_type,
    wait_event,
    COUNT(*) AS connection_count
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
GROUP BY wait_event_type, wait_event
ORDER BY connection_count DESC;
```

---

## Step 3 - Fix the ACU Ceiling Immediately

This is the fix. Increase the MaxCapacity to allow the cluster to scale up:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier my-serverless-cluster \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
  --apply-immediately \
  --region us-east-1
```

`--serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16` - raises the ceiling to 16 ACU.
`--apply-immediately` - changes the config without waiting for a maintenance window.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "ServerlessV2ScalingConfiguration": {
            "MinCapacity": 0.5,
            "MaxCapacity": 16.0
        },
        "Status": "modifying"
    }
}
```

The change takes effect within 1-2 minutes. The cluster will begin scaling up immediately.

---

## Step 4 - Watch the Cluster Scale Up

```bash
# Watch the ACU metric increase
watch -n 15 "aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 30 \
  --statistics Maximum \
  --region us-east-1"
```

Expected recovery output:
```
{"Maximum": 2.0}
{"Maximum": 4.5}
{"Maximum": 8.0}
{"Maximum": 10.0}
```

The cluster scales in 0.5 ACU increments. It takes 2-5 minutes to reach the new working level.

---

## Step 5 - Confirm Query Latency Is Recovering

Check the CloudWatch database latency metrics:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name SelectLatency \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

Latency should decrease as the cluster scales up and the connection queue drains.

---

## Step 6 - Set Up a Monitoring Alarm for the Future

Create an alarm that fires when the cluster is at 80% of its maximum for more than 5 minutes:

```bash
# First get the current max ACU (should now be 16)
MAX_ACU=16
THRESHOLD=$(echo "$MAX_ACU * 0.8" | bc)  # 80% = 12.8

aws cloudwatch put-metric-alarm \
  --alarm-name serverless-capacity-high \
  --alarm-description "Serverless capacity above 80% of maximum for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --statistic Maximum \
  --period 60 \
  --threshold "$THRESHOLD" \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 5 \
  --region us-east-1
```

`--evaluation-periods 5` - must exceed threshold for 5 consecutive 1-minute periods before alarming.
`--threshold 12.8` - 80% of 16 ACU. Gives you warning before hitting the ceiling.

---

## Step 7 - Post-Incident Review

```
Incident: Serverless v2 ACU Ceiling
Date: [DATE]
Duration: [N minutes] from alert to recovery
Configured MaxCapacity: 2 ACU (too low)
New MaxCapacity: 16 ACU
Peak queuing connections: [N]
Root cause: MaxCapacity was set too low for the actual workload

Action items:
  - [ ] Review how the MaxCapacity was set to 2 (was it a mistake? a cost-cutting measure?)
  - [ ] Set CloudWatch alarm at 80% of MaxCapacity
  - [ ] Add capacity planning review to quarterly schedule
  - [ ] Document expected peak ACU based on load testing
  - [ ] Consider setting MinCapacity higher to improve warm-up time
```

---

## Prevention Checklist

- [ ] Set CloudWatch alarm at 80% of MaxCapacity (not 100%)
- [ ] Load test to find actual peak ACU before going to production
- [ ] Never set MaxCapacity to match current peak - add 50% headroom
- [ ] Review ACU metrics monthly and adjust ceiling as workload grows
- [ ] Document the rationale for MinCapacity and MaxCapacity values in your runbook
