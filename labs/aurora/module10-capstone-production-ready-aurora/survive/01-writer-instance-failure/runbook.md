# SURVIVE Scenario 01: Writer Instance Failure - Runbook

## Scenario

The Aurora writer instance has crashed. Aurora should automatically failover to the reader. Your job is to verify the failover completed, confirm the application can reconnect, and document the recovery time.

---

## Step 1: Confirm the Failover Started

**On your local workstation:**

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 10 \
  --query 'Events[*].[Date,Message]' \
  --output table \
  --region us-east-1
```

Look for events containing "failover" or "promoted."

---

## Step 2: Wait for Cluster to Become Available

**On your local workstation:**

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier devops-lab-cluster \
  --region us-east-1
```

This command blocks until the cluster status returns to `available`. Typical failover takes 30-60 seconds.

---

## Step 3: Identify the New Writer

**On your local workstation:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].[DBInstanceIdentifier,IsClusterWriter]' \
  --output table \
  --region us-east-1
```

The instance with `IsClusterWriter: True` is the new writer.

---

## Step 4: Verify the Cluster Endpoint Resolves

**On your local workstation:**

```bash
CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].Endpoint' --output text --region us-east-1)
```

```bash
dig +short $CLUSTER_ENDPOINT
```

The resolved IP should point to the new writer instance.

---

## Step 5: Test Database Connectivity

**On your local workstation:**

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=dbadmin sslmode=require" \
  -c "SELECT inet_server_addr(), current_setting('server_version');"
```

If this succeeds, the failover is complete and the cluster is operational.

---

## Step 6: Verify All Alarms Return to OK

**On your local workstation:**

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[?StateValue!=`OK`].[AlarmName,StateValue]' \
  --output table \
  --region us-east-1
```

If any alarms are still in ALARM state after 5 minutes, investigate further.

---

## Step 7: Document Recovery

Record:
- Failover start time (from inject.sh output)
- Failover end time (when cluster returned to available)
- Total failover duration
- Which instance became the new writer
- Whether application reconnected automatically
