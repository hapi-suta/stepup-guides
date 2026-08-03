# SURVIVE 05 - Serverless v2 Scaling Stuck Runbook
## Incident: Aurora Serverless v2 at ACU Maximum - Queries Queuing

---

## What Is Being Tested

The Aurora Serverless v2 cluster has hit its configured MaxCapacity ceiling. The cluster cannot scale higher, so queries are queuing and latency is increasing. You must diagnose that the ACU ceiling is the bottleneck, increase it, and verify recovery.

---

## Why This Matters

Serverless v2 auto-scales, but only up to the MaxCapacity you configure. If someone sets the ceiling too low (cost cutting, misconfiguration, or forgetting to update after traffic growth), the cluster hits the wall silently. There is no automatic alert unless you create one. Users experience slow queries and timeouts while the database appears "healthy" in every other metric.

---

## Symptoms

- Users report slow queries and connection timeouts
- CloudWatch alarm fires:
```
ALARM: serverless-capacity-high
Metric: ServerlessDatabaseCapacity = 2.0 (maximum configured)
Duration: 15+ minutes
```
- New connections fail:
```
psql: error: connection to server failed: FATAL: remaining connection slots are reserved
```
- Application logs show increasing query latency
- CPU utilization is at 100% consistently

---

## Diagnostics

### Step 1 - Check Current ACU and Configured Maximum

Check the configured scaling limits:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-serverless-cluster \
  --query 'DBClusters[0].ServerlessV2ScalingConfiguration' \
  --output table \
  --region us-east-1
```

`--query` - extracts just the scaling configuration from the full response.

Expected output during the incident:
```
---------------------------------------
|       ServerlessV2ScalingConfiguration |
+----------------+--------------------+
| MaxCapacity    | 2.0                |
| MinCapacity    | 0.5                |
+----------------+--------------------+
```

`MaxCapacity: 2.0` - the cluster can never go above 2 ACU. This is your bottleneck.

### Step 2 - Confirm the Cluster Is Pinned at the Ceiling

Check the CloudWatch capacity metric:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=devops-serverless-cluster \
  --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Average Maximum \
  --region us-east-1
```

`--start-time` - looks back 30 minutes to see the capacity trend.
`--statistics Average Maximum` - shows both average and peak ACU usage.

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

### Step 3 - Check How Many Connections Are Waiting

Connect to the cluster if you can still get through:

```bash
psql -h devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     --connect-timeout=10
```

If you can connect, check connection states:

```sql
SELECT
    COUNT(*) AS total_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle,
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting
FROM pg_stat_activity;
```

Expected output during the incident (yours will differ):
```
 total_connections | active | idle | waiting
-------------------+--------+------+---------
                48 |     45 |    3 |      38
```

38 connections are waiting (blocked). The cluster cannot process them because it is at CPU capacity with only 2 ACU.

---

## Resolution

### Step 4 - Increase the ACU Ceiling

This is the fix. Increase MaxCapacity to allow the cluster to scale up:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-serverless-cluster \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
  --apply-immediately \
  --region us-east-1
```

`--serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16` - raises the ceiling from 2 to 16 ACU.
`--apply-immediately` - changes the configuration without waiting for a maintenance window.

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

### Step 5 - Watch the Cluster Scale Up

Monitor the ACU metric as the cluster scales:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=devops-serverless-cluster \
  --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Maximum \
  --query 'Datapoints | sort_by(@, &Timestamp)' \
  --region us-east-1
```

Expected recovery output (yours will differ):
```
{"Maximum": 2.0}
{"Maximum": 4.5}
{"Maximum": 8.0}
{"Maximum": 10.0}
```

The cluster scales in 0.5 ACU increments. It takes 2-5 minutes to reach the working level needed for the current load.

### Step 6 - Verify Queries Are No Longer Queuing

Connect again and check:

```bash
psql -h devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT COUNT(*) AS waiting FROM pg_stat_activity WHERE wait_event_type IS NOT NULL AND query NOT LIKE '%pg_stat_activity%';"
```

Expected output after recovery:
```
 waiting
---------
       2
```

Waiting connections should drop to near-zero as the cluster scales up.

### Step 7 - Create a CloudWatch Alarm to Prevent Future Ceiling Hits

Set an alarm that fires when the cluster is at 80% of its maximum:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-serverless-capacity-high \
  --alarm-description "Serverless v2 capacity above 80% of maximum for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=devops-serverless-cluster \
  --statistic Maximum \
  --period 60 \
  --threshold 12.8 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 5 \
  --region us-east-1
```

`--threshold 12.8` - 80% of 16 ACU. Gives you warning before hitting the ceiling.
`--evaluation-periods 5` - must exceed threshold for 5 consecutive 1-minute periods before alarming. Prevents false alarms from brief spikes.

---

## Prevention

- [ ] Set CloudWatch alarm at 80% of MaxCapacity (not 100%)
- [ ] Load test to find actual peak ACU before going to production
- [ ] Never set MaxCapacity to match current peak - add 50% headroom
- [ ] Review ACU metrics monthly and adjust ceiling as workload grows
- [ ] Document the rationale for MinCapacity and MaxCapacity values
- [ ] Consider setting MinCapacity higher to improve warm-up time for latency-sensitive workloads

---

## Interview Questions From This Scenario

1. What is the difference between MinCapacity and MaxCapacity in Serverless v2?
2. How does Serverless v2 scaling work under the hood (0.5 ACU increments)?
3. What CloudWatch metrics would you monitor for a Serverless v2 cluster?
4. When is Serverless v2 more cost-effective than provisioned instances?
5. How would you size MaxCapacity for a workload you have never run before?

---

## Terminology

| Term | Definition |
|------|-----------|
| ACU (Aurora Capacity Unit) | 1 ACU = approximately 2 GB RAM plus proportional CPU and network. The unit of scaling for Serverless v2 |
| MaxCapacity | The upper ACU limit configured for a Serverless v2 cluster. The cluster cannot scale above this value |
| MinCapacity | The lower ACU limit. The cluster never scales below this, even when idle. Minimum is 0.5 ACU |
| Query queuing | When the database cannot process queries fast enough, they wait in a queue. Users experience this as increased latency |
| Connection slots | Each database has a maximum number of concurrent connections. At low ACU, fewer connection slots are available |
| ACU ceiling | The MaxCapacity value that prevents further scaling. Also called "scaling stuck" when the cluster needs more resources |

---

## Red Flags

- MaxCapacity set to 2 ACU for a production workload - almost certainly too low. Review immediately.
- ServerlessDatabaseCapacity equals MaxCapacity for more than 5 minutes - the cluster is stuck at the ceiling. Increase MaxCapacity.
- No CloudWatch alarm on Serverless capacity - you will not know the cluster is stuck until users complain. Create an alarm at 80%.
- MaxCapacity set exactly to the current peak - no headroom for traffic growth. Add 50% buffer above peak.
- Multiple incidents of hitting the ceiling - indicates the workload has outgrown Serverless v2 or MaxCapacity is not being reviewed regularly.
- High MinCapacity with variable traffic - you are paying for idle capacity. Review if MinCapacity can be lowered during off-peak.
