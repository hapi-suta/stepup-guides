# Tier 7 - USE Exercise 04: Migration Execution

**Exercise type:** Hands-on implementation + scenario analysis
**Time:** 50 minutes
**Goal:** Execute a simulated production migration from a source RDS instance to a target RDS instance using pg_dump/restore with validation, then produce a migration runbook for a hypothetical DMS migration.
**Prerequisites:** Build 06 completed. Source RDS instance with data. Target RDS instance (empty).

---

## Scenario

You are migrating the `ecomm` database from an RDS PostgreSQL 14 instance to a new RDS PostgreSQL 15 instance. This is a major version upgrade. The database is 8 GiB. The business has a 2-hour maintenance window on Saturday at 2 AM UTC.

For this exercise, your lab databases represent the source (PostgreSQL 14-era data) and target (PostgreSQL 15-compatible schema).

---

## Part 1: Pre-Migration Checklist

Complete every item before executing the migration. This checklist is non-negotiable in production.

**Step 1.** Check PostgreSQL version compatibility:

```sql
-- On source
SELECT version();
SHOW server_version;
```

```sql
-- On target
SELECT version();
SHOW server_version;
```

Record both versions. Note any version difference.

**Step 2.** Inventory all database objects:

```sql
-- On source: count objects by type
SELECT
  pg_class.relkind,
  CASE pg_class.relkind
    WHEN 'r' THEN 'table'
    WHEN 'i' THEN 'index'
    WHEN 'S' THEN 'sequence'
    WHEN 'v' THEN 'view'
    WHEN 'm' THEN 'materialized view'
    WHEN 'f' THEN 'foreign table'
  END AS object_type,
  COUNT(*) AS count
FROM pg_class
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_namespace.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
AND pg_class.relkind IN ('r','i','S','v','m')
GROUP BY pg_class.relkind
ORDER BY object_type;
```

Record the output. You will verify the target matches after migration.

**Step 3.** Get exact row counts for all tables:

```sql
SELECT
  schemaname,
  tablename,
  n_live_tup AS estimated_rows
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

Save this output to a file. You will compare it against the target after restore.

**Step 4.** Check for extensions that must be installed on the target:

```sql
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

Any extension listed here must be pre-installed on the target RDS instance before the restore.

**Step 5.** Check database size:

```sql
SELECT
  pg_database.datname,
  pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
WHERE datname = current_database();
```

**Step 6.** Identify any active long-running connections that could interfere:

```sql
SELECT pid, usename, application_name, state, query_start,
  NOW() - query_start AS duration
FROM pg_stat_activity
WHERE state <> 'idle'
AND pid <> pg_backend_pid()
ORDER BY duration DESC;
```

In production, you would terminate long-running transactions before the dump to ensure consistency.

---

## Part 2: Schema-Only Migration

For a major version upgrade (14 to 15), migrate the schema first, validate it, then migrate data.

**Step 1.** Dump schema only:

```bash
pg_dump \
  -h [SOURCE-ENDPOINT] \
  -U postgres \
  -d [DATABASE-NAME] \
  --schema-only \
  -Fc \
  -f /tmp/schema_only.pgdump
```

The `--schema-only` flag dumps only DDL - table definitions, indexes, sequences, views, functions - without any data rows.

**Step 2.** Create the target database:

```bash
psql -h [TARGET-ENDPOINT] -U postgres \
  -c "CREATE DATABASE [DATABASE-NAME];"
```

**Step 3.** Restore schema to target:

```bash
pg_restore \
  -h [TARGET-ENDPOINT] \
  -U postgres \
  -d [DATABASE-NAME] \
  --schema-only \
  -v \
  /tmp/schema_only.pgdump 2>&1 | tee /tmp/schema_restore.log
```

The `2>&1 | tee` captures both stdout and stderr to the log file while also printing to your terminal.

**Step 4.** Check for schema restore errors:

```bash
grep -i "error\|failed" /tmp/schema_restore.log
```

No output means no errors.

**Step 5.** Verify object count on target matches source:

```sql
-- On target (same query as Step 2 above)
SELECT
  pg_class.relkind,
  CASE pg_class.relkind
    WHEN 'r' THEN 'table'
    WHEN 'i' THEN 'index'
    WHEN 'S' THEN 'sequence'
    WHEN 'v' THEN 'view'
    WHEN 'm' THEN 'materialized view'
  END AS object_type,
  COUNT(*) AS count
FROM pg_class
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_namespace.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
AND pg_class.relkind IN ('r','i','S','v','m')
GROUP BY pg_class.relkind
ORDER BY object_type;
```

The counts should match the source exactly.

---

## Part 3: Data Migration

**Step 1.** Dump data only:

```bash
pg_dump \
  -h [SOURCE-ENDPOINT] \
  -U postgres \
  -d [DATABASE-NAME] \
  --data-only \
  -Fc \
  -v \
  -f /tmp/data_only.pgdump
```

**Step 2.** Record the start time:

```bash
echo "Data restore started at: $(date -u)"
```

**Step 3.** Restore data with parallel jobs (use the target's vCPU count):

```bash
pg_restore \
  -h [TARGET-ENDPOINT] \
  -U postgres \
  -d [DATABASE-NAME] \
  --data-only \
  -j 4 \
  -v \
  /tmp/data_only.pgdump 2>&1 | tee /tmp/data_restore.log
```

**Step 4.** Record the end time and calculate duration:

```bash
echo "Data restore completed at: $(date -u)"
```

**Step 5.** Check for errors:

```bash
grep -i "error\|failed" /tmp/data_restore.log
```

---

## Part 4: Post-Migration Validation

Never declare a migration complete without validation.

**Step 1.** Compare row counts:

```bash
cat << 'EOF' > /tmp/validate_rowcounts.sql
SELECT
  schemaname,
  tablename,
  n_live_tup AS estimated_rows
FROM pg_stat_user_tables
ORDER BY tablename;
EOF

# Run on source
psql -h [SOURCE-ENDPOINT] -U postgres -d [DATABASE-NAME] \
  -f /tmp/validate_rowcounts.sql > /tmp/source_counts.txt

# Run on target
psql -h [TARGET-ENDPOINT] -U postgres -d [DATABASE-NAME] \
  -f /tmp/validate_rowcounts.sql > /tmp/target_counts.txt

# Compare
diff /tmp/source_counts.txt /tmp/target_counts.txt
```

No output from `diff` means the counts match exactly.

**Step 2.** Validate sequences:

```sql
-- On source: get max IDs
SELECT 'SELECT MAX(order_id) FROM orders' AS query
UNION ALL
SELECT 'SELECT MAX(customer_id) FROM customers';
```

Run the actual max queries on both source and target and compare values.

**Step 3.** Reset sequences on the target to match source maximums:

```sql
-- On target (run for each table with a serial/identity primary key)
SELECT setval('orders_order_id_seq',
  (SELECT COALESCE(MAX(order_id), 1) FROM orders));

SELECT setval('customers_customer_id_seq',
  (SELECT COALESCE(MAX(customer_id), 1) FROM customers));
```

**Step 4.** Run a data integrity check query:

```sql
-- Compare a sample hash of data between source and target
SELECT
  COUNT(*) AS total_orders,
  SUM(unit_price * quantity) AS total_revenue,
  AVG(unit_price)::NUMERIC(10,4) AS avg_price
FROM orders;
```

Run this on both source and target. All three values must match.

**Step 5.** Test application connectivity:

```bash
psql -h [TARGET-ENDPOINT] -U [APP-USER] -d [DATABASE-NAME] \
  -c "SELECT 1 AS connectivity_test;"
```

Test with the application's credentials, not the admin user. Confirm the application user exists and has the correct permissions.

---

## Part 5: Write the Cutover Runbook

Based on what you executed in Parts 1-4, write a production cutover runbook. This is a document your on-call engineer could follow at 2 AM with no prior context.

Your runbook must include:

**Header:**
- Migration name and date
- Source and target endpoint identifiers
- Maintenance window: start time, maximum duration, rollback decision time
- Contacts: DBA lead, engineering lead, on-call

**Pre-Cutover (30 minutes before window):**
- [ ] Verify target health (describe-db-instances status = available)
- [ ] Verify last backup on source is recent
- [ ] Notify stakeholders that maintenance is starting
- [ ] Pre-warm the target connection (connect once, confirm response)

**Cutover Execution (T+0 to T+30 minutes):**
- [ ] Stop application writes (maintenance page on, read-only mode on)
- [ ] Confirm write count drops to zero (check `pg_stat_activity`)
- [ ] Record final sequence values on source
- [ ] Execute final incremental sync if using CDC (wait for zero lag)
- [ ] Update connection string in application config
- [ ] Restart application services
- [ ] Run smoke test queries

**Validation (T+30 to T+60 minutes):**
- [ ] Application health checks passing
- [ ] Error rate within normal range
- [ ] Query latency within normal range
- [ ] Log files clean (no connection errors)

**Rollback Decision Point (T+60 minutes):**
If any validation fails, describe exactly what you do:
- Which config change to revert
- Which services to restart
- Who to notify

---

## Part 6: DMS vs pg_dump Decision Scenarios

For each scenario, decide whether you would use pg_dump/restore or DMS. Justify each answer.

1. **Scenario A:** 5 GiB PostgreSQL 12 database on EC2, migrating to RDS PostgreSQL 15. The business can take a 2-hour maintenance window on Sunday. No ongoing sync needed after migration.

2. **Scenario B:** 800 GiB MySQL 8.0 database on-premises, migrating to Aurora PostgreSQL. Maximum acceptable downtime is 15 minutes. The migration must preserve all data with zero loss.

3. **Scenario C:** 50 GiB PostgreSQL 14 database on RDS, upgrading to PostgreSQL 16. This is a production database for a global application - some region will always be active. Maximum downtime is 60 seconds.

4. **Scenario D:** 200 GiB PostgreSQL 15 database on Heroku, migrating to RDS. Heroku does not expose WAL replication. The team can script a 3-hour maintenance window.

5. **Scenario E:** Two PostgreSQL 15 databases that must stay permanently synchronized - source in us-east-1, replica in eu-west-1 - for read-only access to European users.

---

## Validation Checklist

- [ ] Pre-migration checklist completed with all values recorded.
- [ ] Schema-only dump and restore succeeded with zero errors.
- [ ] Object counts match between source and target.
- [ ] Data-only dump and restore succeeded.
- [ ] Row counts match between source and target.
- [ ] Sequences reset to max values from source.
- [ ] Data integrity check query returns identical values on both instances.
- [ ] Application credentials work on the target.
- [ ] Production cutover runbook written with all six sections.
- [ ] Five DMS vs pg_dump decision scenarios answered with justification.
