# BUILD 04 - Auto-Scaling Policies: Create, Test, Monitor
## Estimated Time: 40 minutes

---

## What You Will Do

1. Register your Aurora cluster as a scalable target
2. Create a target tracking auto-scaling policy based on CPU
3. Generate load to trigger scale-out
4. Observe Aurora adding a reader automatically
5. Watch scale-in after load stops

> **Cost warning:** Auto-scaling may create additional reader instances (db.t3.medium ~$0.07/hr each). The policy will remove them when load drops, but monitor your account.

---

## Before You Start

You need:
- The Aurora cluster from BUILD 01-03 (`devops-lab-cluster`) with at least 1 reader
- AWS CLI v2 configured
- psql and pgbench installed
- The pgbench database from a previous lab (or create one in Step 2)

---

## Step 1 - Register the Aurora Cluster as a Scalable Target

**In your terminal:**

Aurora Auto Scaling uses the Application Auto Scaling service. First, register your cluster:

```bash
aws application-autoscaling register-scalable-target \
  --service-namespace rds \
  --resource-id cluster:devops-lab-cluster \
  --scalable-dimension rds:cluster:ReadReplicaCount \
  --min-capacity 1 \
  --max-capacity 4 \
  --region us-east-1
```

`--service-namespace rds` - we are scaling an RDS resource.
`--resource-id cluster:devops-lab-cluster` - the cluster to scale. Format is `cluster:<cluster-id>`.
`--scalable-dimension rds:cluster:ReadReplicaCount` - we are scaling the number of read replicas.
`--min-capacity 1` - never go below 1 reader.
`--max-capacity 4` - never exceed 4 readers.

Expected output (yours will differ):
```json
{
    "ScalableTargets": []
}
```

Verify the registration:

```bash
aws application-autoscaling describe-scalable-targets \
  --service-namespace rds \
  --resource-ids cluster:devops-lab-cluster \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "ScalableTargets": [
        {
            "ServiceNamespace": "rds",
            "ResourceId": "cluster:devops-lab-cluster",
            "ScalableDimension": "rds:cluster:ReadReplicaCount",
            "MinCapacity": 1,
            "MaxCapacity": 4
        }
    ]
}
```

---

## Step 2 - Create a pgbench Database (If Not Already Done)

**In your terminal:**

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "CREATE DATABASE pgbenchdb;"
```

Initialize pgbench with test data:

```bash
pgbench -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres \
        -d pgbenchdb \
        --initialize \
        --scale 50
```

`--initialize` - creates the pgbench tables and populates them.
`--scale 50` - creates 5 million rows (~750 MB of data).

This takes 2-4 minutes.

---

## Step 3 - Create a Target Tracking Auto-Scaling Policy

**In your terminal:**

Create a policy that targets 40% average CPU utilization across readers:

```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace rds \
  --resource-id cluster:devops-lab-cluster \
  --scalable-dimension rds:cluster:ReadReplicaCount \
  --policy-name devops-lab-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 40.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "RDSReaderAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 300
  }' \
  --region us-east-1
```

`--policy-type TargetTrackingScaling` - Aurora adjusts replica count to keep CPU at the target.
`TargetValue: 40.0` - Aurora adds readers when average CPU exceeds 40%, removes when below.
`RDSReaderAverageCPUUtilization` - average CPU across all readers in the cluster.
`ScaleInCooldown: 300` - wait 300 seconds (5 minutes) after removing a reader before removing another.
`ScaleOutCooldown: 300` - wait 300 seconds after adding a reader before adding another.

Expected output (yours will differ):
```json
{
    "PolicyARN": "arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:...",
    "Alarms": [
        {
            "AlarmName": "TargetTracking-cluster:devops-lab-cluster-AlarmHigh-...",
            "AlarmARN": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:..."
        },
        {
            "AlarmName": "TargetTracking-cluster:devops-lab-cluster-AlarmLow-...",
            "AlarmARN": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:..."
        }
    ]
}
```

Aurora Auto Scaling automatically creates two CloudWatch alarms: one for scaling out (CPU too high) and one for scaling in (CPU too low).

---

## Step 4 - Check Current Reader Count Before Load

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`false`]|length(@)' \
  --output text \
  --region us-east-1
```

Expected output:
```
2
```

You currently have 2 readers (from BUILD 01 and BUILD 03).

---

## Step 5 - Generate Load to Trigger Scale-Out

**In your terminal:**

Run a heavy read workload against the reader endpoint:

```bash
pgbench -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres \
        -d pgbenchdb \
        --client 80 \
        --jobs 8 \
        --time 300 \
        --progress 30 \
        --select-only
```

`--client 80` - simulate 80 concurrent connections.
`--jobs 8` - use 8 threads on your machine.
`--time 300` - run for 5 minutes (300 seconds).
`--select-only` - only run SELECT queries (read-only load for readers).

This will push the reader CPU above 40%, triggering auto-scaling.

---

## Step 6 - Monitor CPU and Scaling Activity

While the load test runs, open a second terminal and monitor CPU:

**In Terminal 2:**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

Watch for CPU exceeding 40%. When it does, auto-scaling will add a reader.

Check for scaling activities:

```bash
aws application-autoscaling describe-scaling-activities \
  --service-namespace rds \
  --resource-id cluster:devops-lab-cluster \
  --region us-east-1
```

Expected output when scale-out triggers (yours will differ):
```json
{
    "ScalingActivities": [
        {
            "ActivityId": "...",
            "ResourceId": "cluster:devops-lab-cluster",
            "StatusCode": "Successful",
            "Description": "Setting desired count to 3",
            "Cause": "Target tracking alarm ... breached threshold"
        }
    ]
}
```

Check the current reader count:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

If scaling triggered, you will see a new reader being created.

---

## Step 7 - Wait for Scale-In After Load Stops

After the pgbench run finishes (5 minutes), CPU will drop below the target. After the cooldown period (300 seconds), auto-scaling will remove the extra reader.

Monitor the reader count every 2 minutes:

```bash
watch -n 120 "aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==\`false\`]|length(@)' \
  --output text \
  --region us-east-1"
```

You should see the count decrease back to your minimum (the auto-scaling-created reader will be removed).

---

## Step 8 - View the Auto-Scaling Policy

**In your terminal:**

```bash
aws application-autoscaling describe-scaling-policies \
  --service-namespace rds \
  --resource-id cluster:devops-lab-cluster \
  --region us-east-1
```

This shows your active policies, target values, and cooldown settings.

---

## Key Takeaways

1. Aurora Auto Scaling adds/removes readers based on CloudWatch metrics
2. Target tracking is the recommended policy type - set a target CPU and Aurora handles the rest
3. Auto-scaling creates CloudWatch alarms automatically for scale-out and scale-in
4. Cooldown periods prevent rapid add/remove cycles (flapping)
5. New readers take 8-15 minutes to create - auto-scaling is not instant
6. Scale-in waits for the cooldown period after load drops before removing readers
7. The reader endpoint automatically includes new readers in DNS rotation

---

## Clean Up

Remove the auto-scaling policy and deregister the target:

```bash
aws application-autoscaling delete-scaling-policy \
  --service-namespace rds \
  --resource-id cluster:devops-lab-cluster \
  --scalable-dimension rds:cluster:ReadReplicaCount \
  --policy-name devops-lab-cpu-scaling \
  --region us-east-1
```

```bash
aws application-autoscaling deregister-scalable-target \
  --service-namespace rds \
  --resource-id cluster:devops-lab-cluster \
  --scalable-dimension rds:cluster:ReadReplicaCount \
  --region us-east-1
```

Keep the cluster running for BUILD 05.
