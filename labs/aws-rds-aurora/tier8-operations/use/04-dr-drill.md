# USE Exercise 04: Complete DR Drill

**Objective:** Execute a full disaster recovery drill for an Aurora PostgreSQL cluster, measure actual RTO and RPO against designed targets, and produce a DR test report.
**Time:** 45-60 minutes
**Level:** Expert
**infra_required:** true - Requires an Aurora PostgreSQL cluster. A Global Database is required for Section 3; a standard Aurora cluster is sufficient for Sections 1-2.
**Prerequisites:** Build Guide 07 completed. At least one Aurora cluster available. Monitoring in place to measure connection recovery time.

---

## Pre-Drill Checklist

Complete all pre-drill items before starting the timed sections.

**System state documentation:**
- [ ] Cluster endpoint recorded: _________________________
- [ ] Current writer instance: _________________________
- [ ] Current reader instance(s): _________________________
- [ ] Replication lag < 5 seconds: (check `AuroraReplicaLag`) YES / NO
- [ ] Application baseline healthy (no ongoing incidents): YES / NO
- [ ] Team notified (on-call, app team leads): YES / NO
- [ ] Rollback procedure documented and ready: YES / NO

**Your designed RTO target:** _____________ seconds
**Your designed RPO target:** _____________ seconds

---

## Part 1: Verify DR Readiness Before the Drill

A DR drill that fails because of missing prerequisites is not a useful drill - it just creates confusion. Verify readiness first.

**Task 1.1:** Confirm the cluster has at least one reader instance (required for Aurora automatic failover):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [CLUSTER-ID] \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}' \
  --output table \
  --region [REGION]
```

If there are no reader instances, the failover will take significantly longer (Aurora must provision a new writer). Add a reader before continuing if you want to test realistic production conditions.

**Task 1.2:** Verify the cluster endpoint is what your "application" will use during the drill:

```bash
CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier [CLUSTER-ID] \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region [REGION])

echo "Cluster endpoint: $CLUSTER_ENDPOINT"
```

**Task 1.3:** Establish your continuous monitoring. Open a second terminal and run:

```bash
# Continuous connection probe - run this before, during, and after the failover
while true; do
  TIMESTAMP=$(date +%H:%M:%S.%3N)
  RESULT=$(psql \
    --host=[CLUSTER-ENDPOINT] \
    --port=5432 \
    --username=[DB-USER] \
    --dbname=[DBNAME] \
    --command="SELECT 'ok' AS status, now() AS ts, pg_is_in_recovery() AS is_replica;" \
    --no-psqlrc \
    --tuples-only \
    --connect-timeout=3 2>&1)
  echo "$TIMESTAMP: $RESULT"
  sleep 1
done
```

Save this output to a file for RTO measurement:

```bash
while true; do
  TIMESTAMP=$(date +%H:%M:%S.%3N)
  RESULT=$(psql ... 2>&1)
  echo "$TIMESTAMP: $RESULT"
  sleep 1
done | tee /tmp/dr-drill-probe.log
```

**Deliverable:** Screenshot or paste of probe output showing steady state before the drill starts.

---

## Part 2: Execute the Aurora Cluster Failover

**Record T0 precisely.**

**Task 2.1 (Console):**
1. Open the RDS console.
2. Select **Databases** and click your cluster identifier.
3. Click **Actions > Failover**.
4. Confirm the failover.
5. **Record T0:** The exact time (HH:MM:SS) you clicked confirm.

**Task 2.2 (CLI - alternative):**

```bash
# Record T0
T0=$(date +%H:%M:%S.%3N)
echo "T0 (failover initiated): $T0"

aws rds failover-db-cluster \
  --db-cluster-identifier [CLUSTER-ID] \
  --region [REGION]
```

**Task 2.3:** Monitor the probe output in the second terminal.

Document the following from the probe log:
- **T1:** The timestamp of the first failed connection after T0
- **T3:** The timestamp when the first successful connection returned after T1
- **pg_is_in_recovery():** Verify it returns `f` (false) on T3, confirming the new writer is serving connections

**Task 2.4:** Monitor AWS events during the failover:

```bash
aws rds describe-events \
  --source-identifier [CLUSTER-ID] \
  --source-type db-cluster \
  --duration 30 \
  --region [REGION]
```

Record the event sequence and timestamps.

**Deliverable:** The probe log excerpt showing T0 through T3. Annotated with timestamps.

---

## Part 3: (Optional - Global Database Required) Cross-Region Failover

If you have an Aurora Global Database, perform a managed planned failover to the secondary region.

**Pre-conditions:**
- Replication lag to secondary region < 1 second
- Application team briefed (this drill changes the write endpoint to another region)
- Secondary region credentials and endpoint documented

**Task 3.1:** Record current global cluster state:

```bash
aws rds describe-global-clusters \
  --region [PRIMARY-REGION] \
  --query 'GlobalClusters[*].GlobalClusterMembers[*].{Cluster:DBClusterArn,IsWriter:IsWriter}'
```

**Task 3.2:** Initiate managed planned failover:

```bash
T0=$(date +%H:%M:%S.%3N)
echo "T0 (global failover initiated): $T0"

aws rds failover-global-cluster \
  --global-cluster-identifier [GLOBAL-CLUSTER-ID] \
  --target-db-cluster-identifier [SECONDARY-CLUSTER-ARN] \
  --region [PRIMARY-REGION]
```

**Task 3.3:** Monitor the failover:

```bash
# Poll until secondary becomes writer
watch -n 3 'aws rds describe-global-clusters \
  --region [SECONDARY-REGION] \
  --query "GlobalClusters[*].GlobalClusterMembers[*].{Cluster:DBClusterArn,IsWriter:IsWriter}" \
  --output table'
```

**Task 3.4:** Update the application connection string to the secondary region cluster endpoint:

```bash
NEW_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier [SECONDARY-CLUSTER-ID] \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region [SECONDARY-REGION])

echo "New primary endpoint: $NEW_ENDPOINT"
```

In a production environment, this is where you would update your Route 53 record or application configuration.

**Task 3.5:** Record T4 - the time your application (probe script updated to the new endpoint) confirms healthy connections.

**Deliverable:** T0, T3, T4 timestamps. Calculated cross-region RTO.

---

## Part 4: Verify Data Integrity After Failover

**Task 4.1:** Verify no data loss occurred. Before the drill, note the latest transaction in a test table:

```sql
-- Run this BEFORE the failover
CREATE TABLE IF NOT EXISTS dr_drill_log (
  id serial PRIMARY KEY,
  recorded_at timestamptz DEFAULT now(),
  note text
);

INSERT INTO dr_drill_log (note) VALUES ('pre-failover marker');
SELECT max(id) AS last_id, max(recorded_at) AS last_recorded FROM dr_drill_log;
```

After failover, verify on the new primary:

```sql
-- Run this AFTER the failover, on the new primary
SELECT max(id) AS last_id, max(recorded_at) AS last_recorded FROM dr_drill_log;
```

The `last_id` should match what you recorded before the failover. If it does not, you have measured actual data loss (RPO violation).

**Task 4.2:** Verify the new primary is accepting writes:

```sql
INSERT INTO dr_drill_log (note) VALUES ('post-failover write test');
SELECT * FROM dr_drill_log ORDER BY id DESC LIMIT 3;
```

**Task 4.3:** Verify the old primary is now a reader (for same-region failover):

```sql
-- Connect to the old primary instance endpoint directly
SELECT pg_is_in_recovery();
-- Should return: t (true = now a replica)
```

---

## Part 5: Fail Back

**Task 5.1:** Initiate failback to the original primary (same-region):

The same `failover-db-cluster` command runs another failover back to the original instance:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier [CLUSTER-ID] \
  --target-db-instance [ORIGINAL-WRITER-INSTANCE-ID] \
  --region [REGION]
```

**Task 5.2:** For a Global Database failback, run `failover-global-cluster` again with the original primary cluster as the target.

**Task 5.3:** Verify the original writer is restored as primary:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [CLUSTER-ID] \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
  --output text \
  --region [REGION]
```

---

## Part 6: Produce the DR Test Report

Complete the DR test report using the template from Build Guide 07:

```
DR DRILL REPORT
Date: [DATE]
Environment: [staging/production]
Cluster: [CLUSTER-ID]
Conducted by: [YOUR NAME]

PRE-DRILL STATE
Primary instance: [INSTANCE-ID]
Cluster endpoint: [ENDPOINT]
Baseline healthy: YES/NO
Replication lag at start: [N] seconds

FAILOVER MEASUREMENTS
T0 (failover initiated):   [HH:MM:SS]
T1 (first failure):        [HH:MM:SS] (delta: [N] seconds)
T3 (new primary ready):    [HH:MM:SS] (delta from T0: [N] seconds)
T4 (application healthy):  [HH:MM:SS] (delta from T0: [N] seconds)

RESULTS
Actual RTO: [N] seconds
Designed RTO: [N] seconds
RTO Result: PASS / FAIL

Actual RPO: [N] seconds (data loss)
Designed RPO: [N] seconds
RPO Result: PASS / FAIL

DATA INTEGRITY
Pre-failover last transaction ID: [N]
Post-failover last transaction ID: [N]
Data loss: NONE / [N rows / N seconds]

FAILBACK
Failback RTO: [N] seconds
Original architecture restored: YES / NO

OBSERVATIONS
[What went smoothly]
[What was unexpected]
[Any manual interventions required]

ACTION ITEMS
[List any gaps found. For each: what the gap is, who owns it, expected close date]
```

---

## Reflection Questions

1. Your actual RTO was 47 seconds. Your designed RTO is 30 seconds. The gap is 17 seconds. You traced it to DNS TTL propagation in the application connection pool. What change would you make to close this gap?

2. During the drill, you observed that the connection probe failed for 40 seconds (T1 to T3). Your application team says their real error rate was elevated for 4 minutes because their connection pool took longer to recover. Why would the database being ready (T3) and the application recovering (T4) have such different timelines?

3. You are about to run this same drill in production next month. The application team wants to reschedule because "it will cause customer impact." How do you respond? What evidence can you point to from this staging drill?

4. Your company has 15 Aurora clusters across 4 environments. The business wants annual DR drills on all of them. Estimate how long the annual DR testing program would take and design a schedule that minimizes operational risk.
