# SURVIVE 04 - Replica Lag Critical

## Symptom

A read replica is falling behind the primary. Application reads are returning stale data. CloudWatch shows ReplicaLag climbing steadily.

---

## Diagnosis

### Step 1 - Check replica lag metric

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab-replica \
    --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average Maximum \
    --query "sort_by(Datapoints, &Timestamp)[-5:].{Time:Timestamp,AvgLag:Average,MaxLag:Maximum}" \
    --output table
```

ReplicaLag is in seconds. Under 5 seconds is healthy. Over 60 seconds needs attention. Over 300 seconds is critical.

Expected output (yours will differ):

```
--------------------------------------------------------------
|               GetMetricStatistics                          |
+--------+----------------------------+----------+-----------+
| AvgLag |           Time             |  MaxLag  |           |
+--------+----------------------------+----------+-----------+
|  125.3 | 2024-01-15T14:20:00+00:00  |  180.5   |           |
|  145.7 | 2024-01-15T14:21:00+00:00  |  210.2   |           |
|  160.1 | 2024-01-15T14:22:00+00:00  |  245.8   |           |
+--------+----------------------------+----------+-----------+
```

### Step 2 - Check primary write activity

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name WriteIOPS \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    --query "sort_by(Datapoints, &Timestamp)[-5:].{Time:Timestamp,WriteIOPS:Average}" \
    --output table
```

High WriteIOPS on the primary means heavy write load is generating more WAL than the replica can replay.

### Step 3 - Compare primary and replica instance classes

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Instance:'primary',Class:DBInstanceClass}" \
    --output table
```

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab-replica \
    --query "DBInstances[0].{Instance:'replica',Class:DBInstanceClass}" \
    --output table
```

If the replica has a smaller instance class than the primary, it may not have enough CPU or I/O to keep up with replication.

### Step 4 - Check replica CPU and I/O

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab-replica \
    --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    --query "sort_by(Datapoints, &Timestamp)[-3:].{Time:Timestamp,CPU:Average}" \
    --output table
```

If CPU is above 80%, the replica is struggling.

---

## Fix

### Step 5 - Scale up the replica

If the replica is undersized, increase its instance class:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab-replica \
    --db-instance-class db.t3.medium \
    --apply-immediately
```

This changes the replica to a larger instance class. The replica will briefly go offline during the class change (1-5 minutes).

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab-replica
```

### Step 6 - Reduce write load on primary (if applicable)

If the lag is caused by a runaway job, identify and stop it:

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Find long-running write queries:

```sql
SELECT pid, now() - query_start AS duration, state, substring(query, 1, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration DESC
LIMIT 10;
```

Cancel a specific query if needed:

```sql
SELECT pg_cancel_backend(PID_NUMBER);
```

Replace PID_NUMBER with the actual process ID from the previous query.

For a more aggressive termination:

```sql
SELECT pg_terminate_backend(PID_NUMBER);
```

Exit psql:

```sql
\q
```

### Step 7 - Clean up the data causing lag

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
DROP DATABASE IF EXISTS lag_test;
```

Exit psql:

```sql
\q
```

### Step 8 - Monitor lag recovery

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab-replica \
    --start-time "$(date -u -v-10M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    --query "sort_by(Datapoints, &Timestamp)[-5:].{Time:Timestamp,LagSeconds:Average}" \
    --output table
```

Lag should be decreasing. Wait until it drops below 5 seconds.

---

## Verification

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab-replica \
    --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    --query "sort_by(Datapoints, &Timestamp) | [-1].Average"
```

Expected output (yours will differ):

```
2.3
```

The value should be under 5 seconds. If it is still above 5, wait a few more minutes and check again.

---

## Discussion Questions

1. What causes replica lag in standard RDS vs Aurora?
2. Should read replicas always match the primary's instance class?
3. At what lag threshold would you stop routing reads to the replica?
4. How does Aurora's storage-level replication reduce lag compared to streaming replication?
