# USE 02 - Extension Setup: Monitoring Stack

**Time:** 25 minutes
**Level:** Intermediate
**Prerequisite:** BUILD 03 completed

---

## Scenario

[TEAM NAME]'s new PostgreSQL RDS instance is going into production next week. Your job is to set up a complete monitoring foundation using pg_stat_statements and pgaudit before launch.

**Requirements from the security and ops team:**
1. All DDL changes must be logged (compliance requirement)
2. All INSERT/UPDATE/DELETE on the `customer_data` schema must be logged
3. Top 20 slowest queries must be visible at any time
4. Queries running longer than 5 seconds must be logged automatically
5. Temp file usage must be logged (to catch missing indexes)
6. Data must be queryable from psql - not just from CloudWatch

---

## Task 1 - Verify Extensions Are Installed

Before configuring anything, confirm the extensions are active.

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name IN ('pg_stat_statements', 'pgaudit')
ORDER BY name;
```

If either shows `installed_version = null`, install it:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

If you get an error that pgaudit is not in `shared_preload_libraries`, go back to BUILD 03 and complete the preload step first.

---

## Task 2 - Configure pg_stat_statements

**Apply the recommended configuration:**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --parameters \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=pg_stat_statements.track_planning,ParameterValue=1,ApplyMethod=pending-reboot" \
    "ParameterName=pg_stat_statements.max,ParameterValue=10000,ApplyMethod=pending-reboot" \
    "ParameterName=track_activity_query_size,ParameterValue=4096,ApplyMethod=pending-reboot"
```

`track_planning=1` records planning time separately from execution time - useful for identifying parameter sniffing issues. `track_activity_query_size=4096` increases the query text captured from the default 1024 bytes.

**If you need a reboot for the static parameters:**

```bash
aws rds reboot-db-instance --db-instance-identifier [YOUR-INSTANCE-ID]
aws rds wait db-instance-available --db-instance-identifier [YOUR-INSTANCE-ID]
```

---

## Task 3 - Configure pgaudit

**Set the audit scope in the parameter group:**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --parameters \
    "ParameterName=pgaudit.log,ParameterValue=ddl,ApplyMethod=immediate" \
    "ParameterName=pgaudit.log_relation,ParameterValue=on,ApplyMethod=immediate" \
    "ParameterName=pgaudit.log_parameter,ParameterValue=on,ApplyMethod=immediate" \
    "ParameterName=log_min_duration_statement,ParameterValue=5000,ApplyMethod=immediate" \
    "ParameterName=log_temp_files,ParameterValue=0,ApplyMethod=immediate"
```

`pgaudit.log_parameter=on` logs the bind parameters for parameterized queries. `log_min_duration_statement=5000` logs all queries over 5 seconds. `log_temp_files=0` logs any query that creates a temporary file (sign of a missing index or sort with insufficient work_mem).

---

## Task 4 - Set Up Object-Level Audit for customer_data Schema

Session-level audit (set via parameter group) applies to all statements. For object-level audit on a specific schema, use database-level configuration.

**Connect to psql:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d [DBNAME]
```

**Create the customer_data schema and a test table:**

```sql
CREATE SCHEMA IF NOT EXISTS customer_data;

CREATE TABLE IF NOT EXISTS customer_data.customers (
  id         serial PRIMARY KEY,
  email      text UNIQUE NOT NULL,
  full_name  text,
  created_at timestamptz DEFAULT now()
);
```

**Enable object-level audit for the app user on this schema:**

```sql
-- Audit all write operations on the schema by the app user
ALTER ROLE [APP-USERNAME] SET pgaudit.log TO 'write';
ALTER ROLE [APP-USERNAME] SET pgaudit.log_relation TO 'on';
```

Replace `[APP-USERNAME]` with your application's database user.

This means: whenever `[APP-USERNAME]` runs INSERT, UPDATE, DELETE, or TRUNCATE, pgaudit will log it.

---

## Task 5 - Build the Monitoring Queries

Create a set of reusable monitoring queries. Save these for your team's runbooks.

**Query 1 - Top 20 slowest queries by average time:**

```sql
SELECT
  LEFT(query, 120) AS query,
  calls,
  round(mean_exec_time::numeric, 1) AS avg_ms,
  round(total_exec_time::numeric, 0) AS total_ms,
  rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;
```

**Query 2 - Queries with the worst planning time (identify param sniffing):**

```sql
SELECT
  LEFT(query, 120) AS query,
  calls,
  round(mean_plan_time::numeric, 1) AS avg_plan_ms,
  round(mean_exec_time::numeric, 1) AS avg_exec_ms,
  round((mean_plan_time / NULLIF(mean_exec_time, 0) * 100)::numeric, 1) AS plan_pct
FROM pg_stat_statements
WHERE mean_plan_time > 10
ORDER BY mean_plan_time DESC
LIMIT 10;
```

**Query 3 - Most frequently called queries:**

```sql
SELECT
  LEFT(query, 120) AS query,
  calls,
  round(mean_exec_time::numeric, 1) AS avg_ms,
  round(calls * mean_exec_time / 1000 / 60, 2) AS total_minutes
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 20;
```

**Query 4 - Queries consuming the most total time (optimization priority):**

```sql
SELECT
  LEFT(query, 120) AS query,
  calls,
  round(total_exec_time::numeric / 1000 / 60, 2) AS total_minutes,
  round(mean_exec_time::numeric, 1) AS avg_ms
FROM pg_stat_statements
WHERE total_exec_time > 60000  -- queries that consumed more than 1 minute total
ORDER BY total_exec_time DESC
LIMIT 10;
```

---

## Task 6 - Test the Audit Configuration

**Run some DDL to trigger audit logging:**

```sql
CREATE TABLE customer_data.orders (
  id          serial PRIMARY KEY,
  customer_id integer REFERENCES customer_data.customers(id),
  total       numeric(10,2),
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE customer_data.orders ADD COLUMN status text DEFAULT 'pending';

DROP TABLE customer_data.orders;
```

**Run some DML:**

```sql
INSERT INTO customer_data.customers (email, full_name)
VALUES ('test@example.com', 'Test User');

UPDATE customer_data.customers
SET full_name = 'Test User Updated'
WHERE email = 'test@example.com';

DELETE FROM customer_data.customers
WHERE email = 'test@example.com';
```

**Check the logs in CloudWatch:**

1. Open the AWS Console and go to **CloudWatch**.
2. Click **Log groups** in the left sidebar.
3. Find the log group for your RDS instance (format: `/aws/rds/instance/[INSTANCE-ID]/postgresql`).
4. Click on the most recent log stream.
5. Search for `AUDIT:` entries.

You should see entries for the DDL and DML statements you ran.

---

## Task 7 - Create a Monitoring View

Create a view that wraps the most useful pg_stat_statements query for easy access:

```sql
CREATE OR REPLACE VIEW monitoring.slow_queries AS
SELECT
  queryid,
  LEFT(query, 200) AS query_preview,
  calls,
  round(mean_exec_time::numeric, 2) AS avg_exec_ms,
  round(mean_plan_time::numeric, 2) AS avg_plan_ms,
  round(total_exec_time::numeric, 0) AS total_exec_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  temp_blks_written,
  CASE
    WHEN (shared_blks_hit + shared_blks_read) = 0 THEN NULL
    ELSE round(shared_blks_hit * 100.0 / (shared_blks_hit + shared_blks_read), 1)
  END AS cache_hit_pct
FROM pg_stat_statements
ORDER BY mean_exec_time DESC;
```

First create the schema:

```sql
CREATE SCHEMA IF NOT EXISTS monitoring;
```

Then create the view:

```sql
CREATE OR REPLACE VIEW monitoring.slow_queries AS
SELECT
  queryid,
  LEFT(query, 200) AS query_preview,
  calls,
  round(mean_exec_time::numeric, 2) AS avg_exec_ms,
  round(mean_plan_time::numeric, 2) AS avg_plan_ms,
  round(total_exec_time::numeric, 0) AS total_exec_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  temp_blks_written,
  CASE
    WHEN (shared_blks_hit + shared_blks_read) = 0 THEN NULL
    ELSE round(shared_blks_hit * 100.0 / (shared_blks_hit + shared_blks_read), 1)
  END AS cache_hit_pct
FROM pg_stat_statements
ORDER BY mean_exec_time DESC;
```

Grant access to the app team:

```sql
GRANT USAGE ON SCHEMA monitoring TO [APP-USERNAME];
GRANT SELECT ON monitoring.slow_queries TO [APP-USERNAME];
```

Now the app team can run:

```sql
SELECT * FROM monitoring.slow_queries LIMIT 20;
```

---

## Checklist

Before marking this complete, verify all requirements:

- [ ] pg_stat_statements installed and tracking all queries
- [ ] Top 20 slowest queries visible via psql query
- [ ] pgaudit logging all DDL statements
- [ ] pgaudit logging INSERT/UPDATE/DELETE on customer_data schema
- [ ] Queries > 5 seconds appear in logs
- [ ] Temp file creation appears in logs
- [ ] `monitoring.slow_queries` view created and accessible to app user
- [ ] Audit log entries visible in CloudWatch

---

## Discussion Questions

1. Why should you use `pg_stat_statements_reset()` carefully in production?

2. A security auditor asks for logs of all SELECT statements on `customer_data`. What do you add to the pgaudit config?

3. `pgaudit.log_parameter=on` logs bind parameters. What is the privacy risk of this setting?

4. Your slow_queries view shows `cache_hit_pct = 45%` for a specific query. What does that tell you?
