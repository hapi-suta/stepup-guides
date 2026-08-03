# BUILD 07 - Aurora Serverless v2: Scale, Observe, Cost
## Estimated Time: 40 minutes

---

## What You Will Do

1. Create an Aurora Serverless v2 cluster
2. Set minimum and maximum ACU capacity ranges
3. Generate load and observe automatic scaling
4. Build a mixed cluster (provisioned writer + serverless readers)
5. Review cost comparison between Serverless v2 and provisioned

---

## Before You Start

You need:
- AWS CLI v2 configured
- A VPC with subnets and a DB subnet group
- psql and the PostgreSQL pgbench tool (for load testing)

> **Concept:** ACU = Aurora Capacity Unit. 1 ACU = approximately 2 GB of RAM plus proportional CPU and network. Serverless v2 scales between your configured minimum and maximum in 0.5 ACU increments.

---

## Step 1 - Create an Aurora Serverless v2 Cluster

### Console

1. Go to RDS -> Databases -> Create database
2. Choose "Standard create"
3. Engine: Aurora (PostgreSQL compatible)
4. Engine version: 16.6 (or latest)
5. Templates: Dev/Test
6. DB cluster identifier: `my-serverless-cluster`
7. Credentials: postgres / YourPassword123
8. Instance configuration:
   - Select "Serverless"
   - Minimum ACUs: 0.5
   - Maximum ACUs: 16
9. VPC and subnet group: your existing ones
10. Click "Create database"

### CLI

Create the cluster:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-serverless-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-0abc123456789 \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
  --region us-east-1
```

`--serverless-v2-scaling-configuration` - sets the ACU range. `MinCapacity=0.5` is the lowest allowed. `MaxCapacity=16` means the cluster can scale up to 16 ACUs (~32 GB RAM).

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "my-serverless-cluster",
        "Status": "creating",
        "ServerlessV2ScalingConfiguration": {
            "MinCapacity": 0.5,
            "MaxCapacity": 16.0
        },
        ...
    }
}
```

Now add a Serverless v2 instance to the cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-serverless-writer \
  --db-cluster-identifier my-serverless-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.serverless \
  --region us-east-1
```

`--db-instance-class db.serverless` - this special class enables Serverless v2 scaling for the instance. The actual capacity is controlled by the cluster's scaling configuration.

Wait 8-12 minutes for the instance to become available.

---

## Step 2 - Verify the Serverless v2 Configuration

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-serverless-cluster \
  --query 'DBClusters[0].{Status:Status,MinACU:ServerlessV2ScalingConfiguration.MinCapacity,MaxACU:ServerlessV2ScalingConfiguration.MaxCapacity}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------
|    DescribeDBClusters      |
+----------+---------+-------+
| MaxACU   | MinACU  | Status|
+----------+---------+-------+
| 16.0     | 0.5     | avail.|
+----------+---------+-------+
```

Also check the instance:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-serverless-writer \
  --query 'DBInstances[0].{Class:DBInstanceClass,Status:DBInstanceStatus}' \
  --output table \
  --region us-east-1
```

Expected output:
```
---------------------------------
|    DescribeDBInstances        |
+---------------+---------------+
| Class         | Status        |
+---------------+---------------+
| db.serverless | available     |
+---------------+---------------+
```

---

## Step 3 - Connect and Check Current ACU Usage

Get the endpoint:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-serverless-cluster \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1
```

Connect:

```bash
psql -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Check current ACU usage:

```sql
SELECT
    unit,
    unit_type,
    value,
    value_description
FROM aurora_compute_unit_usage()
ORDER BY unit_type;
```

> Note: This function is Aurora-specific. It shows the current ACU consumption.

Expected output (yours will differ):
```
 unit | unit_type | value | value_description
------+-----------+-------+-------------------
  0.5 | min       | 0.5   | Minimum ACU
  0.5 | current   | 0.5   | Current ACU usage
 16.0 | max       | 16.0  | Maximum ACU
```

At idle, the cluster runs at the minimum 0.5 ACUs.

---

## Step 4 - Check ACU Scaling in CloudWatch

Before generating load, open a CloudWatch terminal to watch the scaling metric.

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

`--metric-name ServerlessDatabaseCapacity` - the CloudWatch metric that shows current ACU capacity.

Expected output at idle (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2024-01-15T15:00:00Z",
            "Average": 0.5,
            "Unit": "None"
        }
    ]
}
```

0.5 ACUs at idle. This is the minimum.

---

## Step 5 - Generate Load and Watch Serverless v2 Scale Up

First, create a test database and set it up for pgbench:

```bash
psql -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "CREATE DATABASE pgbenchdb;"
```

Initialize pgbench with a scale factor of 100 (about 1.5 GB of data):

```bash
pgbench -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres \
        -d pgbenchdb \
        --initialize \
        --scale 100
```

`--initialize` - creates the pgbench tables and populates them.
`--scale 100` - creates 10 million rows (~1.5 GB). Higher scale = more realistic load.

This takes 3-5 minutes.

Now run the load test:

```bash
pgbench -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres \
        -d pgbenchdb \
        --client 50 \
        --jobs 4 \
        --time 120 \
        --progress 10
```

`--client 50` - simulate 50 concurrent database connections.
`--jobs 4` - use 4 threads on your client machine to generate load.
`--time 120` - run for 120 seconds.
`--progress 10` - print progress every 10 seconds.

Expected output (yours will differ):
```
pgbench (16.6)
starting vacuum...end.
progress: 10 s, 145.2 tps, lat 344.2 ms stddev 187.5
progress: 20 s, 312.8 tps, lat 159.9 ms stddev 82.3
progress: 30 s, 487.3 tps, lat 102.6 ms stddev 45.7
...
```

While the load test runs, check the ACU metric every 30 seconds:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 10 \
  --statistics Maximum \
  --region us-east-1
```

`--period 10` - 10-second granularity to see fast scaling changes.

Expected output as load increases (yours will differ):
```json
{
    "Datapoints": [
        {"Timestamp": "...", "Maximum": 0.5},
        {"Timestamp": "...", "Maximum": 2.0},
        {"Timestamp": "...", "Maximum": 4.5},
        {"Timestamp": "...", "Maximum": 6.5}
    ]
}
```

You can see Serverless v2 scaling from 0.5 to 6.5 ACUs as the load increases.

---

## Step 6 - Observe Scale-Down After Load Stops

When the pgbench run finishes, Serverless v2 scales back down. This takes a few minutes.

Keep polling the CloudWatch metric every 30 seconds:

```bash
watch -n 30 "aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 30 \
  --statistics Average \
  --region us-east-1"
```

`watch -n 30` - re-runs the command every 30 seconds.

You will see the ACU value gradually decrease back to 0.5 over 3-5 minutes.

---

## Step 7 - Modify the ACU Range

You can change the min/max ACU range without restarting the cluster.

Increase the minimum to 2 ACUs (useful for latency-sensitive workloads that cannot tolerate cold-start delay):

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier my-serverless-cluster \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=32 \
  --apply-immediately \
  --region us-east-1
```

`MinCapacity=2` - the cluster will never go below 2 ACUs now (~4 GB RAM reserved).
`MaxCapacity=32` - increased the ceiling to 32 ACUs (~64 GB RAM).

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "ServerlessV2ScalingConfiguration": {
            "MinCapacity": 2.0,
            "MaxCapacity": 32.0
        },
        ...
    }
}
```

---

## Step 8 - Create a Mixed Cluster (Provisioned Writer + Serverless Reader)

A mixed cluster is powerful for production. The writer is provisioned (predictable cost, no scaling delay). The readers are Serverless v2 (auto-scale based on read demand).

Add a serverless reader to the cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-serverless-reader \
  --db-cluster-identifier my-serverless-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.serverless \
  --availability-zone us-east-1b \
  --promotion-tier 1 \
  --region us-east-1
```

Now change the writer to a provisioned instance class. First, modify the writer:

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-serverless-writer \
  --db-instance-class db.r6g.large \
  --apply-immediately \
  --region us-east-1
```

`--db-instance-class db.r6g.large` - changes from `db.serverless` to a fixed provisioned size.

Now you have:
- Writer: `db.r6g.large` (provisioned, fixed cost, no scaling delay)
- Reader: `db.serverless` (scales 0.5-32 ACUs based on read traffic)

This is the recommended production pattern for read-heavy applications with variable read traffic.

---

## Step 9 - Cost Comparison

Understanding when Serverless v2 saves money vs costs more.

### Comparison Table (us-east-1, prices approximate)

| Option | Spec | $/hr | $/month |
|--------|------|-------|---------|
| db.t3.medium | 2 vCPU, 4 GB | $0.068 | $50 |
| db.r6g.large | 2 vCPU, 16 GB | $0.24 | $175 |
| db.r6g.xlarge | 4 vCPU, 32 GB | $0.48 | $350 |
| Serverless v2 at 0.5 ACU | ~1 GB | $0.06 | $44 |
| Serverless v2 at 2 ACU | ~4 GB | $0.24 | $175 |
| Serverless v2 at 8 ACU | ~16 GB | $0.96 | $701 |
| Serverless v2 at 16 ACU | ~32 GB | $1.92 | $1,402 |

> Note: Serverless v2 is billed per ACU-hour. Check the [AWS Pricing page](https://aws.amazon.com/rds/aurora/pricing/) for current rates. These figures change.

### When Serverless v2 Saves Money

Good fit:
- Dev/test environments that sit idle most of the day
- Workloads with large traffic spikes (e.g., business hours only)
- New applications where you do not know the right instance size yet
- Read replicas that see variable traffic

Poor fit (provisioned is cheaper):
- Steady, predictable 24/7 workloads at high ACU levels
- Workloads that are always near the maximum ACU
- Latency-sensitive applications that cannot tolerate the 30-60 second ramp-up time

### Calculate Break-Even

At 8 ACU continuous = $0.96/hr. Equivalent db.r6g.xlarge (16 GB, close to 8 ACU) = $0.48/hr.

Serverless v2 at a sustained 8 ACU costs 2x the provisioned equivalent. But if your workload averages 4 ACUs with peaks to 8, you save money.

Run this query on the cluster to see your average ACU over the past hour:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Average \
  --region us-east-1
```

Multiply the average by the per-ACU-hour price to estimate hourly cost.

---

## Key Takeaways

1. Serverless v2 uses `db.serverless` as the instance class - the ACU range is set on the cluster
2. Scaling is fast (seconds) but not instant - latency-sensitive apps should set a higher minimum
3. Minimum is 0.5 ACU - there is no true scale-to-zero in Serverless v2
4. Mixed clusters (provisioned writer + serverless readers) are the recommended production pattern
5. At steady high load, provisioned instances are cheaper than Serverless v2
6. Monitor `ServerlessDatabaseCapacity` in CloudWatch to understand actual ACU usage

---

## Clean Up

```bash
# Delete the reader
aws rds delete-db-instance \
  --db-instance-identifier my-serverless-reader \
  --skip-final-snapshot \
  --region us-east-1

# Delete the writer
aws rds delete-db-instance \
  --db-instance-identifier my-serverless-writer \
  --skip-final-snapshot \
  --region us-east-1

# Wait for instances to be gone, then delete the cluster
aws rds delete-db-cluster \
  --db-cluster-identifier my-serverless-cluster \
  --skip-final-snapshot \
  --region us-east-1
```
