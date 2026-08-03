# SURVIVE 02: RDS Storage Full - Database Locked

**Module 03 - Cloud Database Services**
**Difficulty:** Intermediate
**Time Limit:** 30 minutes

---

## The Scenario

It is 7 AM on a Monday. PagerDuty wakes you up. Your production RDS PostgreSQL instance (db.r6g.xlarge, 200 GB gp3) has hit its storage limit. The database is in a `storage-full` state. All writes are failing. Applications are returning 500 errors.

The monitoring dashboard shows:
- `FreeStorageSpace`: 0 bytes
- `DatabaseConnections`: climbing (app retrying failed writes)
- `WriteIOPS`: 0 (no writes possible)

**Your job:** Get writes working again, prevent this from happening again, and understand what consumed the storage.

---

## The Symptoms

1. Application error: `ERROR: could not extend file "base/16384/12345": No space left on device`
2. psql connections still work (reads succeed), but any INSERT, UPDATE, or DELETE fails
3. `VACUUM` cannot run (needs to write)
4. RDS instance status shows: `storage-full`

---

## Your Tasks

### Task 1: Immediate Relief - Increase Storage (10 minutes)

RDS lets you increase storage on a running instance. This is the fastest way to restore writes.

1. Check current storage allocation:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier YOUR_INSTANCE \
     --query "DBInstances[0].{Storage:AllocatedStorage,Status:DBInstanceStatus,StorageType:StorageType}"
   ```

2. Increase storage by 20% (minimum increase is 10%):
   ```bash
   aws rds modify-db-instance \
     --db-instance-identifier YOUR_INSTANCE \
     --allocated-storage 240 \
     --apply-immediately
   ```

   **Note:** Storage increases take 10-30 minutes. During this time, the instance shows `modifying` status but writes should resume within a few minutes as AWS provisions the additional space.

3. Monitor the modification:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier YOUR_INSTANCE \
     --query "DBInstances[0].{Status:DBInstanceStatus,PendingStorage:PendingModifiedValues.AllocatedStorage}"
   ```

4. **Important:** You cannot increase storage again for 6 hours after a modification. Make sure you add enough.

### Task 2: Enable Storage Autoscaling (5 minutes)

Prevent this from ever happening again by enabling storage autoscaling:

```bash
aws rds modify-db-instance \
  --db-instance-identifier YOUR_INSTANCE \
  --max-allocated-storage 500 \
  --apply-immediately
```

**How autoscaling works:**
- RDS monitors `FreeStorageSpace`
- When free space drops below 10% of allocated storage AND the low-space condition lasts 5 minutes, RDS automatically increases storage
- It increases by whichever is greater: 5 GB or 10% of current allocation
- It will not exceed `--max-allocated-storage`
- There is a 6-hour cooldown between scaling events

**Set `--max-allocated-storage` thoughtfully.** Too low and you will hit the ceiling. Too high and a runaway process could generate a massive AWS bill. For a 200 GB database, 500 GB is reasonable - it gives you time to investigate before hitting the cap.

### Task 3: Investigate What Consumed the Storage (10 minutes)

Once writes are working again, find the cause.

1. Connect with psql and check database sizes:
   ```sql
   SELECT
     datname,
     pg_size_pretty(pg_database_size(datname)) AS size
   FROM pg_database
   ORDER BY pg_database_size(datname) DESC;
   ```

2. Check table sizes in the largest database:
   ```sql
   SELECT
     schemaname || '.' || relname AS table_name,
     pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
     pg_size_pretty(pg_relation_size(relid)) AS table_size,
     pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
     n_dead_tup,
     n_live_tup,
     CASE WHEN n_live_tup > 0
       THEN round(100.0 * n_dead_tup / n_live_tup, 1)
       ELSE 0
     END AS dead_pct
   FROM pg_stat_user_tables
   ORDER BY pg_total_relation_size(relid) DESC
   LIMIT 20;
   ```

3. Check for bloat - tables with high dead tuple counts could not be vacuumed because of the storage-full state:
   ```sql
   SELECT
     relname,
     n_dead_tup,
     last_autovacuum,
     last_vacuum
   FROM pg_stat_user_tables
   WHERE n_dead_tup > 10000
   ORDER BY n_dead_tup DESC;
   ```

4. Check for large temporary files or uncommitted transactions:
   ```sql
   -- Long-running transactions that prevent vacuum
   SELECT
     pid,
     now() - xact_start AS duration,
     state,
     query
   FROM pg_stat_activity
   WHERE xact_start IS NOT NULL
   AND state != 'idle'
   ORDER BY xact_start;
   ```

5. Check WAL-related storage (in RDS, transaction logs count toward storage):
   ```sql
   SELECT
     pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) AS total_wal_generated;
   ```

**Common causes of storage exhaustion:**

| Cause | Evidence | Fix |
|---|---|---|
| Table bloat (dead tuples) | High `n_dead_tup`, no recent vacuum | Run VACUUM FULL on worst tables |
| Unvacuumable bloat | Long-running transaction blocking vacuum | Kill the blocking transaction, then vacuum |
| Log table growth | One table much larger than expected | Implement partitioning with retention |
| WAL accumulation | Replication slot preventing WAL cleanup | Drop unused replication slots |
| Temp files | Large sorts/hashes spilling to disk | Tune work_mem, optimize queries |

### Task 4: Set Up Prevention Alarms (5 minutes)

```bash
# Get or create SNS topic
TOPIC_ARN=$(aws sns create-topic --name db-storage-alerts --query "TopicArn" --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint your-email@example.com

# Warning alarm at 80% storage used (40 GB free on 200 GB)
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-storage-warning" \
  --alarm-description "Free storage below 20% - investigate and plan" \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=YOUR_INSTANCE \
  --statistic Average \
  --period 300 \
  --threshold 42949672960 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching

# Critical alarm at 90% storage used (20 GB free on 200 GB)
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-storage-critical" \
  --alarm-description "Free storage below 10% - immediate action needed" \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=YOUR_INSTANCE \
  --statistic Average \
  --period 60 \
  --threshold 21474836480 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching
```

---

## Root Cause Analysis Template

Fill this out after the incident:

```
Incident: RDS Storage Full
Duration: [TIME FROM ALERT TO RESOLUTION]
Impact: All writes failed for [DURATION]

Timeline:
- [TIME]: FreeStorageSpace alarm triggered
- [TIME]: DBA acknowledged alert
- [TIME]: Storage increase initiated
- [TIME]: Writes resumed
- [TIME]: Root cause identified

Root Cause: [WHAT CONSUMED THE STORAGE]

Contributing Factors:
- Storage autoscaling was not enabled
- No CloudWatch alarm for storage usage
- [OTHER FACTORS]

Action Items:
- [x] Enable storage autoscaling (max: 500 GB)
- [x] Create warning alarm at 80% usage
- [x] Create critical alarm at 90% usage
- [ ] Address root cause: [SPECIFIC ACTION]
- [ ] Review all production instances for same risk
```

---

## Validation

You have succeeded when:

1. Writes are working again on the instance
2. Storage autoscaling is enabled with a reasonable maximum
3. You have identified what consumed the storage
4. CloudWatch alarms are set at 80% (warning) and 90% (critical) usage
5. You can explain why VACUUM could not run during the storage-full state
