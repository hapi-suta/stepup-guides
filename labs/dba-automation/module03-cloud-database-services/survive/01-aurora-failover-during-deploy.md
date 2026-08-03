# SURVIVE 01: Failover During Application Deploy

**Module 03 - Cloud Database Services**
**Difficulty:** Intermediate
**Time Limit:** 30 minutes

---

## The Scenario

It is 2 PM on a Tuesday. Your team is deploying a schema migration to the production Aurora PostgreSQL cluster. The migration adds a new column and backfills data for 5 million rows.

Midway through the migration, the Aurora writer instance fails over to a reader. The migration script crashes. Your application starts throwing connection errors. Slack is blowing up.

**Your job:** Restore service, understand what happened, and prevent it next time.

---

## The Symptoms

1. The migration script exited with: `FATAL: terminating connection due to administrator command`
2. Application logs show: `Connection refused` errors for 15-30 seconds, then connections resume but all writes fail with `cannot execute INSERT in a read-only transaction`
3. CloudWatch shows a failover event at 14:07 UTC
4. The Aurora cluster endpoint DNS has updated, but your application is still holding stale connections

---

## Your Tasks

### Task 1: Restore Write Access (10 minutes)

1. Confirm the failover happened:
   ```bash
   aws rds describe-events \
     --source-identifier YOUR_CLUSTER \
     --source-type db-cluster \
     --duration 60
   ```

2. Identify which instance is now the writer:
   ```bash
   aws rds describe-db-clusters \
     --db-cluster-identifier YOUR_CLUSTER \
     --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}"
   ```

3. Connect to the cluster endpoint (NOT an instance endpoint) and verify write access:
   ```bash
   psql -h YOUR_CLUSTER_ENDPOINT -U labadmin -d production -c "SELECT pg_is_in_recovery();"
   ```
   - `f` means writer (good)
   - `t` means reader (still stale DNS - wait and retry)

4. If the application is still connecting to the old writer (now a reader), the issue is DNS caching or connection pooling. Solutions:
   - Restart the application to force new connections
   - If using a connection pool (PgBouncer, application-level), drain and reset the pool
   - Verify DNS resolution: `nslookup YOUR_CLUSTER_ENDPOINT`

### Task 2: Handle the Failed Migration (10 minutes)

The migration was partially applied when the failover happened. You need to determine the state:

1. Check if the new column exists:
   ```sql
   SELECT column_name, data_type
   FROM information_schema.columns
   WHERE table_name = 'target_table'
   ORDER BY ordinal_position;
   ```

2. Check if the backfill completed:
   ```sql
   SELECT
     count(*) AS total_rows,
     count(new_column) AS filled_rows,
     count(*) - count(new_column) AS null_rows
   FROM target_table;
   ```

3. If partially complete, you have two options:
   - **Resume:** Run the backfill for remaining NULL rows only
   - **Rollback:** Drop the column and start over

4. Best practice for next time: use idempotent migration scripts that can be safely re-run:
   ```sql
   -- Idempotent: safe to run multiple times
   ALTER TABLE target_table ADD COLUMN IF NOT EXISTS new_column TEXT;

   -- Backfill in batches (can resume from where it stopped)
   UPDATE target_table
   SET new_column = compute_value(id)
   WHERE new_column IS NULL
   AND id BETWEEN :start_id AND :end_id;
   ```

### Task 3: Implement Retry Logic (10 minutes)

Write a connection wrapper that handles failover gracefully. The key behaviors:

1. **Detect read-only state:** After connecting, check `pg_is_in_recovery()`. If true on a writer endpoint, the DNS has not updated yet - wait and retry.

2. **Retry with backoff:** When connections fail, retry with exponential backoff (1s, 2s, 4s, 8s) up to 60 seconds.

3. **Use the correct endpoints:**
   - Writes go to the cluster (writer) endpoint
   - Reads can go to the reader endpoint
   - Never hardcode instance endpoints

4. **Connection pooling awareness:** If using PgBouncer or application-level pooling, configure health checks that detect read-only state and evict stale connections.

---

## Root Cause Analysis

Aurora failovers happen for several reasons:

| Cause | How to Identify | Prevention |
|---|---|---|
| Instance failure | CloudWatch `EngineUptime` resets to 0 | Nothing - this is why HA exists |
| Maintenance window | RDS events show "maintenance" | Schedule maintenance windows during low traffic |
| Manual failover | RDS events show "manual failover" | Communication before failovers |
| Storage issue | CloudWatch `VolumeReadIOPS` spike | Monitor storage metrics |
| Out of memory | Enhanced Monitoring shows OOM | Right-size instance, tune work_mem |

---

## Prevention Checklist

- [ ] Application connects via cluster endpoint, never instance endpoint
- [ ] Connection retry logic with exponential backoff is implemented
- [ ] Connection pool health checks detect read-only state
- [ ] Migration scripts are idempotent (can be re-run safely)
- [ ] Large migrations run in batches with progress tracking
- [ ] Maintenance windows are scheduled during low traffic
- [ ] Team is notified before planned failovers
- [ ] CloudWatch alarm exists for failover events

---

## Validation

You have succeeded when:

1. The application is writing to the new writer instance
2. The migration is either completed or cleanly rolled back
3. You can explain why the application saw "read-only transaction" errors
4. You have documented the retry logic needed for failover resilience
