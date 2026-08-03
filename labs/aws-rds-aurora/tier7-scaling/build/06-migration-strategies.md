# Tier 7 - Scaling, Integration, and Modern Patterns
## Guide 06: Migration Strategies - DMS, Blue/Green, and Dump/Restore

**Objective:** Execute each major RDS migration strategy, understand when to choose each one, and build a decision framework for real-world migrations.
**Time:** 50 minutes
**Prerequisites:** Two RDS PostgreSQL instances (source and target). IAM permissions to create DMS resources. Understanding of logical replication from Build 05.
**Infrastructure:** You will create a DMS replication instance. Tear it down when done. DMS instances cost approximately $0.10-$0.50/hour depending on size.

---

## The Decision Matrix

Before executing any migration, decide which strategy fits. Use this matrix:

| Scenario | Strategy | Why |
|----------|----------|-----|
| Same engine, same version, small DB (<50 GiB), downtime OK | pg_dump / pg_restore | Simplest, most reliable |
| Same engine, major version upgrade, production | Blue/Green Deployment | Minimal downtime, built-in rollback |
| Cross-engine (Oracle/MySQL to PostgreSQL) | DMS full load + CDC | Only option for engine changes |
| Large DB (>200 GiB), minimal downtime, same engine | DMS full load + CDC | Parallel load, then CDC for cutover |
| On-premises to RDS, moderate size, some downtime | pg_dump to S3, restore via bastion | No DMS license needed |
| Ongoing sync (not one-time) | Logical replication or DMS CDC | Permanent replication relationship |

---

## Part A: pg_dump / pg_restore Migration

This is the most reliable migration method for same-engine migrations where downtime is acceptable.

### A1. Dump the Source Database

Connect from a bastion host or EC2 instance that can reach both source and target.

**Step 1.** Install the matching PostgreSQL client on your bastion:

```bash
sudo dnf install -y postgresql15
```

Use the version that matches your source database.

**Step 2.** Create the dump in custom format:

```bash
pg_dump \
  -h [SOURCE-ENDPOINT] \
  -U postgres \
  -d [DATABASE-NAME] \
  -Fc \
  -v \
  -f /tmp/migration_dump.pgdump
```

Breaking down the flags:
- `-Fc`: Custom format. This is compressed and parallel-restore compatible. Always use this over plain SQL for production dumps.
- `-v`: Verbose. Shows progress during the dump so you know it is working.
- `-f /tmp/migration_dump.pgdump`: Output file path.

Expected output (truncated):
```
pg_dump: last built-in OID is 16383
pg_dump: reading schemas
pg_dump: reading user-defined tables
pg_dump: reading extensions
pg_dump: reading user-defined functions
...
pg_dump: dumping contents of table "public.orders"
pg_dump: finished dumping contents of table "public.orders"
...
```

**Step 3.** Check the dump file size:

```bash
ls -lh /tmp/migration_dump.pgdump
```

**Step 4.** (Optional) Upload to S3 for durability and transfer:

```bash
aws s3 cp /tmp/migration_dump.pgdump \
  s3://[YOUR-BUCKET]/migrations/migration_dump_$(date +%Y%m%d).pgdump \
  --region [REGION]
```

### A2. Restore to the Target

**Step 1.** Create the target database if it does not exist:

```bash
psql -h [TARGET-ENDPOINT] -U postgres -c "CREATE DATABASE [DATABASE-NAME];"
```

**Step 2.** Restore using pg_restore with parallel jobs:

```bash
pg_restore \
  -h [TARGET-ENDPOINT] \
  -U postgres \
  -d [DATABASE-NAME] \
  -Fc \
  -j 4 \
  -v \
  /tmp/migration_dump.pgdump
```

Breaking down the flags:
- `-Fc`: Custom format (must match the dump format).
- `-j 4`: Run 4 parallel restore jobs. Use the number of vCPUs on the target instance. Speeds up restore by restoring multiple tables simultaneously.
- `-v`: Verbose.

**Step 3.** Validate row counts:

On the source:

```sql
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

On the target (same query). Row counts should match. Small differences are normal if the source had writes during the dump - this is expected for `pg_dump` which is not a point-in-time snapshot for active databases.

**Step 4.** Update sequences:

pg_restore migrates sequence current values, but verify they are correct on the target to avoid primary key conflicts:

```sql
SELECT sequence_name, last_value FROM information_schema.sequences
JOIN pg_sequences ON sequencename = sequence_name;
```

If any sequences are behind the max ID in their table, reset them:

```sql
SELECT setval('orders_order_id_seq', (SELECT MAX(order_id) FROM orders));
```

---

## Part B: AWS DMS Full Load and CDC Migration

DMS is the right tool when you need minimal downtime on a large database, when migrating between engines, or when you cannot take an extended maintenance window.

### B1. Create the DMS Subnet Group

DMS replication instances live in VPC subnets.

**Console:**

1. Go to **AWS DMS** in the console.
2. Click **Subnet groups** in the left sidebar.
3. Click **Create subnet group**.
4. Name: `tier7-dms-subnet-group`.
5. VPC: Select your Tier 1 VPC.
6. Add at least two subnets from different AZs.
7. Click **Create subnet group**.

**CLI:**

```bash
aws dms create-replication-subnet-group \
  --replication-subnet-group-identifier tier7-dms-subnet-group \
  --replication-subnet-group-description "DMS subnet group for Tier 7 lab" \
  --subnet-ids [SUBNET-ID-1] [SUBNET-ID-2] \
  --region [REGION]
```

### B2. Create the DMS Replication Instance

The replication instance is the EC2 machine that runs the migration task. Size it appropriately - it is the I/O bottleneck.

**Console:**

1. Click **Replication instances** in the left sidebar.
2. Click **Create replication instance**.
3. Name: `tier7-dms-replication`.
4. Instance class: `dms.t3.medium` (sufficient for lab).
5. Engine version: latest available.
6. Multi-AZ: No (lab only).
7. VPC: Your Tier 1 VPC.
8. Subnet group: `tier7-dms-subnet-group`.
9. Publicly accessible: No (DMS stays within VPC).
10. Click **Create**.

**CLI:**

```bash
aws dms create-replication-instance \
  --replication-instance-identifier tier7-dms-replication \
  --replication-instance-class dms.t3.medium \
  --replication-subnet-group-identifier tier7-dms-subnet-group \
  --no-multi-az \
  --publicly-accessible \
  --region [REGION]
```

Wait 5-10 minutes for the replication instance to become available.

### B3. Create Source and Target Endpoints

**Step 1.** Create the source endpoint (RDS PostgreSQL):

```bash
aws dms create-endpoint \
  --endpoint-identifier tier7-dms-source \
  --endpoint-type source \
  --engine-name postgres \
  --server-name [SOURCE-RDS-ENDPOINT] \
  --port 5432 \
  --database-name [DATABASE-NAME] \
  --username postgres \
  --password [SOURCE-PASSWORD] \
  --region [REGION]
```

Note the `EndpointArn` from the output.

**Step 2.** Create the target endpoint (target RDS PostgreSQL):

```bash
aws dms create-endpoint \
  --endpoint-identifier tier7-dms-target \
  --endpoint-type target \
  --engine-name postgres \
  --server-name [TARGET-RDS-ENDPOINT] \
  --port 5432 \
  --database-name [DATABASE-NAME] \
  --username postgres \
  --password [TARGET-PASSWORD] \
  --region [REGION]
```

**Step 3.** Test the connections:

```bash
aws dms test-connection \
  --replication-instance-arn [REPLICATION-INSTANCE-ARN] \
  --endpoint-arn [SOURCE-ENDPOINT-ARN] \
  --region [REGION]
```

Run the same for the target endpoint. Both must return `successful`.

Check connection test results:

```bash
aws dms describe-connections \
  --filters Name=endpoint-arn,Values=[ENDPOINT-ARN] \
  --region [REGION] \
  --query 'Connections[0].{Status:Status,LastFailureMessage:LastFailureMessage}' \
  --output table
```

Expected output:
```
-----------------------------
|    DescribeConnections    |
+--------+------------------+
|  Status|  successful      |
+--------+------------------+
```

### B4. Create the Migration Task

**Step 1.** Create a table mapping file:

```bash
cat > /tmp/dms-table-mapping.json << 'EOF'
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "include-all-tables",
      "object-locator": {
        "schema-name": "public",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
EOF
```

The `%` wildcard under `table-name` includes all tables in the `public` schema. You can specify individual table names to replicate only specific tables.

**Step 2.** Create the task with full-load-and-cdc mode:

```bash
aws dms create-replication-task \
  --replication-task-identifier tier7-migration-task \
  --source-endpoint-arn [SOURCE-ENDPOINT-ARN] \
  --target-endpoint-arn [TARGET-ENDPOINT-ARN] \
  --replication-instance-arn [REPLICATION-INSTANCE-ARN] \
  --migration-type full-load-and-cdc \
  --table-mappings file:///tmp/dms-table-mapping.json \
  --replication-task-settings '{
    "TargetMetadata": {
      "TargetSchema": "public",
      "SupportLobs": false
    },
    "FullLoadSettings": {
      "TargetTablePrepMode": "DROP_AND_CREATE",
      "CreatePkAfterFullLoad": true,
      "MaxFullLoadSubTasks": 8,
      "TransactionConsistencyTimeout": 600
    },
    "Logging": {
      "EnableLogging": true,
      "LogComponents": [
        {"Id": "SOURCE_UNLOAD", "Severity": "LOGGER_SEVERITY_DEFAULT"},
        {"Id": "TARGET_LOAD",   "Severity": "LOGGER_SEVERITY_DEFAULT"},
        {"Id": "TASK_MANAGER",  "Severity": "LOGGER_SEVERITY_DEFAULT"}
      ]
    }
  }' \
  --region [REGION]
```

Key settings explained:
- `TargetTablePrepMode: DROP_AND_CREATE`: DMS will drop existing target tables and recreate them. Only use this when the target is clean.
- `CreatePkAfterFullLoad: true`: Primary keys are created after data load for performance. Loading without indexes is faster.
- `MaxFullLoadSubTasks: 8`: Load up to 8 tables in parallel.
- `TransactionConsistencyTimeout: 600`: Wait up to 10 minutes for open transactions on the source to close before starting the full load.

**Step 3.** Start the task:

```bash
aws dms start-replication-task \
  --replication-task-arn [TASK-ARN] \
  --start-replication-task-type start-replication \
  --region [REGION]
```

### B5. Monitor the Migration Task

```bash
aws dms describe-replication-tasks \
  --filters Name=replication-task-arn,Values=[TASK-ARN] \
  --region [REGION] \
  --query 'ReplicationTasks[0].{Status:Status,FullLoad:ReplicationTaskStats.FullLoadProgressPercent,Latency:ReplicationTaskStats.ApplyLatency}' \
  --output table
```

Expected output during full load:
```
---------------------------------------------
|       DescribeReplicationTasks             |
+----------+----------+---------------------+
|  FullLoad|  45      |                     |
|  Latency |  0       |                     |
|  Status  |  running |                     |
+----------+----------+---------------------+
```

During CDC phase (after full load), `FullLoad` will be 100 and `Latency` will show replication lag in seconds.

### B6. Perform the Cutover

When you are ready to cut traffic over to the target:

1. Stop writes to the source (maintenance page, application config change, etc.).
2. Wait for DMS replication latency to reach 0 seconds (target is fully caught up).
3. Verify row counts match between source and target.
4. Update your application's database connection string to point to the target.
5. Re-enable writes on the application.
6. Monitor the target for errors.

After confirming success, stop the DMS task:

```bash
aws dms stop-replication-task \
  --replication-task-arn [TASK-ARN] \
  --region [REGION]
```

---

## Part C: Blue/Green Deployment for Major Version Upgrade

Blue/Green is the recommended AWS method for major PostgreSQL version upgrades (e.g., PostgreSQL 14 to 16) with minimal downtime.

### C1. Create the Blue/Green Deployment

**Console:**

1. Go to **RDS** and click your database.
2. Click **Actions** > **Create Blue/Green deployment**.
3. **Blue/Green deployment identifier**: `tier7-pg-upgrade`.
4. Under **Green environment settings**:
   - **DB engine version**: Select the target major version (e.g., PostgreSQL 16.x).
   - Optionally change the instance class.
5. Click **Create Blue/Green deployment**.

AWS creates the green environment and sets up logical replication from blue to green. This takes 10-30 minutes.

**CLI:**

```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name tier7-pg-upgrade \
  --source [SOURCE-DB-ARN] \
  --target-engine-version "16.2" \
  --region [REGION]
```

The `--source` is the ARN of your current (blue) database. The `--target-engine-version` is the PostgreSQL version you want to upgrade to.

**Step 1.** Wait for the green environment to be available:

```bash
aws rds describe-blue-green-deployments \
  --region [REGION] \
  --query 'BlueGreenDeployments[?BlueGreenDeploymentName==`tier7-pg-upgrade`].{Status:Status,GreenDB:Target}' \
  --output table
```

Wait for `Status` to show `AVAILABLE`.

### C2. Validate the Green Environment

Before switching over, validate the green environment is working correctly.

Connect to the green database endpoint (found in the blue/green deployment details) and run your application's validation queries:

```sql
-- Verify version
SELECT version();

-- Verify row counts
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY tablename;

-- Verify sequences
SELECT sequence_name, last_value FROM information_schema.sequences;
```

### C3. Perform the Switchover

The switchover stops writes to blue, waits for green to catch up, then promotes green. Downtime is typically under 60 seconds.

**Console:**

1. On the Blue/Green deployment page, click **Switch over**.
2. Review the switchover details.
3. Set a `--switchover-timeout` if needed (default 300 seconds).
4. Click **Switch over**.

**CLI:**

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier [BLUE-GREEN-DEPLOYMENT-ID] \
  --switchover-timeout 300 \
  --region [REGION]
```

The `--switchover-timeout` is the maximum time in seconds to wait for the green to catch up before aborting. If the timeout is exceeded, the switchover aborts and blue remains primary.

Monitor the switchover:

```bash
aws rds describe-blue-green-deployments \
  --region [REGION] \
  --query 'BlueGreenDeployments[0].{Status:Status}' \
  --output text
```

Status will progress through `SWITCHOVER_IN_PROGRESS` to `SWITCHOVER_COMPLETED`.

### C4. After Switchover

After switchover, the old blue environment exists as a stopped cluster. You have a rollback window.

**To roll back:** Not easily reversible. The blue database is kept but is no longer receiving writes. To roll back, you would need to redirect traffic back to blue and accept data loss for the period after switchover.

**To clean up** (after confirming green is stable):

```bash
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier [BLUE-GREEN-DEPLOYMENT-ID] \
  --delete-target \
  --region [REGION]
```

The `--delete-target` flag deletes the old blue environment. Without this flag, only the Blue/Green metadata is removed and both databases continue running.

---

## Part D: DMS Tear Down

```bash
# Stop and delete the task
aws dms delete-replication-task \
  --replication-task-arn [TASK-ARN] \
  --region [REGION]

# Delete endpoints
aws dms delete-endpoint \
  --endpoint-arn [SOURCE-ENDPOINT-ARN] \
  --region [REGION]

aws dms delete-endpoint \
  --endpoint-arn [TARGET-ENDPOINT-ARN] \
  --region [REGION]

# Delete the replication instance
aws dms delete-replication-instance \
  --replication-instance-arn [REPLICATION-INSTANCE-ARN] \
  --region [REGION]
```

Replication instance deletion takes 5-10 minutes.

---

## Summary

What you did in this lab:

- Performed a pg_dump/pg_restore migration with parallel restore jobs.
- Validated row counts and sequences after restore.
- Created DMS infrastructure: subnet group, replication instance, source and target endpoints.
- Created a full-load-and-CDC migration task and monitored its progress.
- Performed a simulated cutover: waiting for zero replication lag, then switching traffic.
- Created a Blue/Green deployment for a major version upgrade.
- Executed and monitored the Blue/Green switchover with a sub-60-second downtime window.

**Key things to remember:**
- pg_dump `-Fc` with pg_restore `-j [NUM-CPUS]` is the fastest dump/restore. Never use plain SQL format for production migrations.
- DMS does NOT migrate sequences, DDL, or all PostgreSQL-specific features. Always run a schema-only dump first, then use DMS for data.
- Blue/Green switchover requires all tables to have primary keys or `REPLICA IDENTITY FULL`. Check this before starting.
- For the cutover, always measure replication latency - do not guess. Stop writes, confirm zero lag, then switch.
- DMS replication instances cost money even when idle. Delete them immediately after use.
