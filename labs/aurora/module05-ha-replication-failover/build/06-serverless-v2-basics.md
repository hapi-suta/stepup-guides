# BUILD 06 - Serverless v2: Create, Scale, Observe
## Estimated Time: 40 minutes

---

## What You Will Do

1. Create an Aurora Serverless v2 cluster with min/max ACU configuration
2. Connect and check current ACU usage
3. Generate load and watch automatic scaling
4. Modify the ACU range without downtime
5. Build a mixed cluster (provisioned writer + serverless reader)
6. Review cost comparison

> **Cost warning:** Serverless v2 charges per ACU-hour. At minimum 0.5 ACU, cost is ~$0.06/hr. During load testing it may scale to 4-8 ACU (~$0.48-$0.96/hr). Delete when done.

---

## Before You Start

You need:
- AWS CLI v2 configured
- A VPC with subnets and a DB subnet group
- psql and pgbench installed

---

## Step 1 - Create the Serverless v2 Cluster

**In your terminal:**

Create the cluster with Serverless v2 scaling configuration:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier devops-serverless-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-0abc123456789 \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
  --region us-east-1
```

`--serverless-v2-scaling-configuration` - sets the ACU range.
`MinCapacity=0.5` - the lowest allowed. 0.5 ACU = ~1 GB RAM.
`MaxCapacity=16` - the cluster can scale up to 16 ACUs (~32 GB RAM).

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-serverless-cluster",
        "Status": "creating",
        "ServerlessV2ScalingConfiguration": {
            "MinCapacity": 0.5,
            "MaxCapacity": 16.0
        },
        ...
    }
}
```

Now add a Serverless v2 instance:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-serverless-writer \
  --db-cluster-identifier devops-serverless-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.serverless \
  --region us-east-1
```

`--db-instance-class db.serverless` - this special class enables Serverless v2 scaling. The actual capacity is controlled by the cluster's scaling configuration.

Wait 8-12 minutes for the instance to become available.

---

## Step 2 - Verify the Configuration

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-serverless-cluster \
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

Check the instance class:

```bash
aws rds describe-db-instances \
  --db-instance-identifier devops-serverless-writer \
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

## Step 3 - Connect and Check Current ACU

**In your terminal:**

Get the endpoint:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-serverless-cluster \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1
```

Connect:

```bash
psql -h devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

Check current capacity via CloudWatch (exit psql first):

```sql
\q
```

**In your terminal:**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=devops-serverless-cluster \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

`--metric-name ServerlessDatabaseCapacity` - shows current ACU capacity.

Expected output at idle (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2026-06-09T15:00:00Z",
            "Average": 0.5,
            "Unit": "None"
        }
    ]
}
```

0.5 ACUs at idle - the minimum.

---

## Step 4 - Generate Load and Watch Scaling

**In your terminal:**

Create a test database and initialize pgbench:

```bash
psql -h devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "CREATE DATABASE pgbenchdb;"
```

```bash
pgbench -h devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres \
        -d pgbenchdb \
        --initialize \
        --scale 100
```

`--scale 100` - creates 10 million rows (~1.5 GB of data). This alone will force some scaling.

Now run the load test:

```bash
pgbench -h devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres \
        -d pgbenchdb \
        --client 50 \
        --jobs 4 \
        --time 120 \
        --progress 10
```

`--client 50` - simulate 50 concurrent database connections.
`--time 120` - run for 2 minutes.
`--progress 10` - print progress every 10 seconds.

While the load test runs, check ACU in another terminal:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=devops-serverless-cluster \
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

Serverless v2 scales from 0.5 to 6.5 ACUs as load increases. Scaling happens in seconds.

---

## Step 5 - Observe Scale-Down

After the pgbench run finishes, the cluster scales back down. Check every 30 seconds:

**In your terminal:**

```bash
watch -n 30 "aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=devops-serverless-cluster \
  --start-time \$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time \$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 30 \
  --statistics Average \
  --region us-east-1 \
  --query 'Datapoints | sort_by(@, &Timestamp) | [-1].Average' \
  --output text"
```

You will see the ACU value gradually decrease back to 0.5 over 3-5 minutes.

---

## Step 6 - Modify the ACU Range (No Downtime)

**In your terminal:**

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-serverless-cluster \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=32 \
  --apply-immediately \
  --region us-east-1
```

`MinCapacity=2` - the cluster will never go below 2 ACUs now (~4 GB RAM reserved). This eliminates cold-start latency.
`MaxCapacity=32` - increased the ceiling to 32 ACUs (~64 GB RAM).

This takes effect immediately with no downtime or restart.

Verify:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-serverless-cluster \
  --query 'DBClusters[0].ServerlessV2ScalingConfiguration' \
  --output table \
  --region us-east-1
```

Expected output:
```
-------------------------------
| ServerlessV2ScalingConfig   |
+---------------+-------------+
| MaxCapacity   | 32.0        |
| MinCapacity   | 2.0         |
+---------------+-------------+
```

---

## Step 7 - Cost Comparison Reference

| Option | Spec | Approx $/hr | Approx $/month |
|--------|------|-------------|----------------|
| db.t3.medium | 2 vCPU, 4 GB | $0.068 | $50 |
| db.r6g.large | 2 vCPU, 16 GB | $0.24 | $175 |
| db.r6g.xlarge | 4 vCPU, 32 GB | $0.48 | $350 |
| Serverless v2 at 0.5 ACU | ~1 GB | $0.06 | $44 |
| Serverless v2 at 2 ACU | ~4 GB | $0.24 | $175 |
| Serverless v2 at 8 ACU | ~16 GB | $0.96 | $701 |
| Serverless v2 at 16 ACU | ~32 GB | $1.92 | $1,402 |

At sustained high ACU, provisioned is cheaper. For variable workloads, Serverless v2 wins.

---

## Key Takeaways

1. Serverless v2 uses `db.serverless` as the instance class - ACU range is set on the cluster
2. Scaling is fast (seconds) but not instant - latency-sensitive apps should set a higher minimum
3. Minimum is 0.5 ACU - there is no true scale-to-zero
4. ACU range can be modified without downtime or restart
5. Monitor `ServerlessDatabaseCapacity` in CloudWatch to understand actual usage
6. At steady high load, provisioned instances are cheaper than Serverless v2

---

## Clean Up

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-serverless-writer \
  --skip-final-snapshot \
  --region us-east-1
```

Wait for the instance to be deleted, then:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-serverless-cluster \
  --skip-final-snapshot \
  --region us-east-1
```
