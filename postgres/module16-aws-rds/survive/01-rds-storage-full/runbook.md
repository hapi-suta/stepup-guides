# SURVIVE 01 - RDS Storage Full

## Symptom

The RDS instance is running out of storage. Writes may fail with "could not extend file" errors. The instance may become read-only if storage is completely exhausted.

---

## Diagnosis

### Step 1 - Check free storage space

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average \
    --query "sort_by(Datapoints, &Timestamp)[-3:].{Time:Timestamp,FreeBytes:Average}" \
    --output table
```

This shows the storage trend over the last hour. If the values are dropping rapidly, the situation is urgent.

### Step 2 - Check current allocated storage

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{AllocatedGB:AllocatedStorage,StorageType:StorageType,Status:DBInstanceStatus}" \
    --output table
```

Expected output (yours will differ):

```
----------------------------------------------
|          DescribeDBInstances               |
+--------------+-----------+-----------------+
| AllocatedGB  | StorageType |    Status     |
+--------------+-------------+---------------+
|  20          | gp3         |  available    |
+--------------+-------------+---------------+
```

Note the current AllocatedStorage value. You will increase it.

### Step 3 - Check instance events

```bash
aws rds describe-events \
    --source-identifier suta-pg-lab \
    --source-type db-instance \
    --duration 60 \
    --query "Events[*].{Time:Date,Message:Message}" \
    --output table
```

Look for messages containing "storage" or "space".

### Step 4 - Identify what is consuming storage

Connect to the instance (if still accessible):

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Find the largest tables:

```sql
SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 10;
```

Exit psql:

```sql
\q
```

---

## Fix

### Step 5 - Scale storage up

Increase the allocated storage. RDS storage can only go up, never down.

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --allocated-storage 100 \
    --apply-immediately
```

The `--allocated-storage 100` increases to 100 GB. Replace with whatever size gives you sufficient headroom. The `--apply-immediately` starts the scaling now.

**Important**: Storage scaling can take several minutes. The instance remains available during scaling but may have reduced I/O performance.

### Step 6 - Monitor the scaling operation

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,Storage:AllocatedStorage,PendingStorage:PendingModifiedValues.AllocatedStorage}" \
    --output table
```

If `PendingStorage` has a value, the scaling is in progress.

### Step 7 - Wait for completion

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

### Step 8 - Clean up the space hog (if applicable)

If a table was accidentally created or filled with junk data, remove it:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
DROP TABLE IF EXISTS storage_filler;
```

```sql
VACUUM FULL;
```

The `VACUUM FULL` reclaims dead space and returns it to the OS. This may take several minutes.

Exit psql:

```sql
\q
```

### Step 9 - Enable storage autoscaling (prevention)

To prevent this from happening again, enable storage autoscaling:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --max-allocated-storage 200 \
    --apply-immediately
```

The `--max-allocated-storage 200` allows RDS to automatically increase storage up to 200 GB when free space drops below 10% of allocated storage.

### Step 10 - Set up a storage alarm

```bash
TOPIC_ARN=$(aws sns list-topics --query "Topics[0].TopicArn" --output text)
```

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name suta-rds-storage-low \
    --alarm-description "Free storage below 10 GB" \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --statistic Average \
    --period 300 \
    --threshold 10737418240 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "${TOPIC_ARN}"
```

The threshold is 10 GB in bytes (10737418240). This will alert before storage becomes critical.

---

## Verification

Confirm storage has been increased and the instance is healthy:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,AllocatedGB:AllocatedStorage,MaxAllocatedGB:MaxAllocatedStorage}" \
    --output table
```

Test that writes work:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
CREATE TABLE storage_test (id int);
```

```sql
DROP TABLE storage_test;
```

```sql
\q
```

Expected output (yours will differ):

```
CREATE TABLE
DROP TABLE
```

---

## Discussion Questions

1. Why can you only increase RDS storage, not decrease it?
2. What is the cooldown period between storage scaling operations?
3. How does storage autoscaling decide when to scale?
4. What happens to IOPS during a storage scaling operation?
