# Runbook: Reader Instance Missing
## Survive Scenario 03

**What is being tested:** Your ability to detect a missing reader instance in an Aurora cluster, understand the impact on read traffic, and restore the cluster to its expected topology.

**Why this matters:** In production, a missing reader means reduced read capacity. If the cluster had only one reader and it disappears, the reader endpoint has no healthy targets and read queries may fail or route to the writer (adding load to it). You need to detect this quickly and add a replacement reader.

**Symptom:** Reader endpoint returning errors or all read traffic hitting a single instance. Monitoring shows fewer cluster members than expected.
**Severity:** Medium to High - depends on how many readers remain
**Time to resolve:** 15 to 25 minutes (mostly waiting for new instance to become available)

---

## Your Starting Point

The monitoring dashboard shows the Aurora cluster has fewer instances than expected. A reader instance has disappeared. The reader endpoint may be returning intermittent errors, or all traffic is landing on a single remaining reader.

You check the cluster status and notice only 2 instances where there should be 3.

---

## Symptoms

You will observe these symptoms:

1. Cluster member count is lower than expected (e.g., 2 instances instead of 3)
2. Reader endpoint may intermittently fail or route all connections to one reader
3. CloudWatch shows increased CPU/connections on the remaining reader
4. The writer is still working fine - write operations are not affected
5. No alarms from the writer, but the reader metrics show increased load

The key clue: the writer is fine, but reader capacity is reduced.

---

## Diagnostic Steps

### Step 1 - Check Cluster Members

List all current members of the cluster:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}" \
  --output table
```

How many members do you see? If you expect 3 (1 writer + 2 readers) but see only 2, a reader is missing.

### Step 2 - List All Instances in the Cluster

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass,AZ:AvailabilityZone}" \
  --output table
```

**Hint:** Compare this list to what you expect. Which instance is missing?

### Step 3 - Check Recent Events

Look for deletion or failure events:

```bash
aws rds describe-events \
  --source-type db-instance \
  --duration 120 \
  --query "Events[*].{Time:Date,Source:SourceIdentifier,Message:Message}" \
  --output table
```

**Hint:** Look for events with "deleted" or "stopped" in the message. This tells you what happened to the missing reader.

### Step 4 - Check the Reader Endpoint Behavior

Test the reader endpoint to see if it still works:

```bash
psql -h YOUR_READER_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -t -A -c "SELECT inet_server_addr();"
```

Run this a few times. If only one IP comes back every time, all read traffic is going to a single reader.

### Step 5 - Check Writer Load

The writer should not be overloaded, but verify:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -t -A -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
```

If the writer has more connections than usual, some read traffic may have been redirected there.

### Step 6 - Add a Replacement Reader

Create a new reader instance to replace the missing one:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-2 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --publicly-accessible
```

**Hint:** Use the same instance class as the original reader. Check the backup file at `/tmp/devops-reader-backup-03.json` for the original class and AZ.

### Step 7 - Wait for the New Instance

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-reader-2
```

This takes 5 to 10 minutes.

### Step 8 - Verify the Cluster Is Restored

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,Tier:PromotionTier}" \
  --output table
```

You should now see 3 members again: 1 writer + 2 readers.

### Step 9 - Test the Reader Endpoint Again

```bash
for i in $(seq 1 6); do
  IP=$(psql -h YOUR_READER_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
    -t -A -c "SELECT inet_server_addr();" 2>/dev/null)
  echo "Connection $i: $IP"
done
```

You should now see two different IPs, confirming the reader endpoint is distributing across both readers.

---

## Resolution Approach

1. Identify which reader is missing by comparing expected vs actual cluster members
2. Check events to understand why it disappeared (deletion, failure, etc.)
3. Create a replacement reader with the same instance class
4. Wait for it to become available (5-10 minutes)
5. Verify the reader endpoint distributes traffic to both readers

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | Reader instance was deleted (manually, by automation, or due to a failure) |
| Impact | Reduced read capacity. All read traffic on remaining reader(s). |
| Write impact | None - writer is unaffected |
| How to detect | Cluster member count is lower than expected |
| Fix | Create a replacement reader instance |
| Time to recover | 5 to 10 minutes for new instance provisioning |

---

## Prevention

1. **CloudWatch alarm on cluster instance count** - Create a custom metric alarm that fires when the number of cluster members drops below the expected count.

2. **Auto Scaling for Aurora readers** - Configure Aurora Auto Scaling to automatically add or remove readers based on load. If a reader is deleted, auto scaling can provision a replacement automatically.

3. **IAM restrictions** - Restrict `rds:DeleteDBInstance` permissions in production. Only the DBA team should be able to delete instances.

4. **Terraform / CloudFormation drift detection** - If infrastructure is managed by IaC, drift detection alerts you when the real infrastructure no longer matches the desired state.

5. **Minimum 2 readers for production** - Always maintain at least 2 readers so losing one does not put all read traffic on a single instance.

---

## Interview Questions

**Q1: A reader instance in your Aurora cluster disappears. The writer is still running. What is the impact and how do you respond?**

Strong answer: The impact depends on how many readers remain. If there are other readers, the reader endpoint redistributes traffic to them. If it was the only reader, read queries either fail or route to the writer (depending on configuration), which increases writer load. I would check cluster members to confirm which reader is missing, check events to understand why, and immediately create a replacement reader. I would also check if Aurora Auto Scaling is configured - if not, I would set it up to prevent this in the future.

**Q2: Can you stop an Aurora cluster instance the same way you stop a regular RDS instance?**

Strong answer: No. You cannot use `stop-db-instance` on individual Aurora cluster members. You can only stop an entire Aurora cluster (which stops all instances). To "stop" a single reader, you have to delete it. This is by design - Aurora's shared storage architecture means individual instances cannot be stopped independently. If you need fewer readers, you delete them. If you need them back, you create new ones.

**Q3: After adding a new reader to an Aurora cluster, how long before it has all the data?**

Strong answer: Immediately. Aurora readers do not need to copy data from the writer because they share the same storage volume. When a new reader instance starts, it connects to the existing Aurora storage layer and can serve read queries right away. There is no initial sync period like there would be with traditional PostgreSQL streaming replication. The new reader is ready to serve traffic as soon as its status becomes "available."

---

## Key Terminology

| Term | Definition |
|------|-----------|
| Cluster member | An Aurora instance (writer or reader) that belongs to a cluster |
| Reader endpoint | DNS name that load-balances across all reader instances |
| Aurora Auto Scaling | Feature that automatically adds or removes readers based on CloudWatch metrics |
| Promotion tier | Priority ranking (0-15) that determines which reader becomes writer during failover |
| Shared storage | Aurora's architecture where all instances access the same storage volume |

---

## Red Flags

These are answers that would concern an interviewer:

- "I would try to start the reader with start-db-instance" - You cannot start individual Aurora instances. You must create a new one.
- "The new reader needs to sync data from the writer first" - Aurora uses shared storage. No data sync is needed.
- "I would failover to fix this" - Failover promotes a reader to writer. It does not create new readers.
- Not checking the instance class of the original reader before creating the replacement

---

## Now Run the Validate Script

```bash
export CLUSTER_ID=devops-lab-cluster
export REGION=us-east-1
export PGPASSWORD=YourPassword
bash validate.sh
```
