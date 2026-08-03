# BUILD 03 - Core Extensions

**Time:** 40 minutes
**Goal:** List available extensions, install pg_stat_statements, pgaudit, and pg_repack, and understand AWS extension version policy.

---

## Prerequisites

- RDS PostgreSQL 16 instance running with your custom parameter group from BUILD 01
- psql access to the instance
- AWS CLI configured

---

## Part 1 - List Available Extensions

Before installing anything, see what extensions RDS makes available for your PostgreSQL version.

**Connect to your instance:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres
```

Replace `[YOUR-ENDPOINT]` and `[YOUR-USERNAME]` with your actual values.

**List all available extensions:**

```sql
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
ORDER BY name;
```

Expected output (yours will differ):
```
           name            | default_version | installed_version |                     comment
---------------------------+-----------------+-------------------+---------------------------------------------
 address_standardizer      | 3.4.2           |                   | Used to parse an address into constituent...
 bloom                     | 1.0             |                   | bloom access method - signature file based...
 btree_gin                 | 1.3             |                   | support for indexing common datatypes in GIN
 hstore                    | 1.8             |                   | data type for storing sets of (key, value)...
 pg_stat_statements        | 1.10            |                   | track planning and execution statistics...
 pgaudit                   | 16.0            |                   | provides auditing functionality
 pgvector                  | 0.7.0           |                   | vector data type and ivfflat and hnsw acc...
 ...
(70+ rows)
```

**Search for a specific extension:**

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name LIKE '%stat%';
```

**List only currently installed extensions:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

---

## Part 2 - Install pg_stat_statements

pg_stat_statements tracks every SQL statement's performance statistics. It is the first extension you should enable on any PostgreSQL instance.

### Step 1 - Enable in shared_preload_libraries

pg_stat_statements must load at startup. You set this in your parameter group.

**CLI:**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

**Reboot the instance:**

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

**Wait for it to come back:**

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

### Step 2 - Create the Extension

After the reboot, connect to psql and create the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

The `IF NOT EXISTS` guard prevents errors if you run this script multiple times.

**Verify it installed:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

Expected output (yours will differ):
```
        name        | installed_version
--------------------+-------------------
 pg_stat_statements | 1.10
(1 row)
```

### Step 3 - Configure pg_stat_statements Parameters

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=pg_stat_statements.max,ParameterValue=10000,ApplyMethod=pending-reboot"
```

`pg_stat_statements.track=all` means track all statements including those inside functions. The value `10000` sets the maximum number of distinct queries to track.

### Step 4 - Query the Statistics

```sql
-- Top 10 queries by total time
SELECT
  LEFT(query, 80) AS query,
  calls,
  round(mean_exec_time::numeric, 2) AS avg_ms,
  round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):
```
                     query                      | calls | avg_ms | total_ms
------------------------------------------------+-------+--------+----------
 SELECT * FROM pg_stat_statements ORDER BY t... |     1 |  12.34 |    12.34
 SELECT name, installed_version FROM pg_avai... |     3 |   2.11 |     6.33
(2 rows)
```

**Reset statistics (useful for testing):**

```sql
SELECT pg_stat_statements_reset();
```

---

## Part 3 - Install pgaudit

pgaudit provides detailed SQL-level audit logging for compliance requirements like SOC 2, PCI-DSS, and HIPAA.

> **Concept:** Standard PostgreSQL logging (log_statement) shows that something was executed. pgaudit shows WHO executed WHAT on WHICH object, with full query text including literals. That level of detail is what auditors want.

### Step 1 - Add pgaudit to shared_preload_libraries

pgaudit also needs to be preloaded at startup.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements\,pgaudit,ApplyMethod=pending-reboot"
```

> **Important:** When adding multiple libraries, comma-separate them. In bash, escape the comma with a backslash inside double quotes.

**Reboot the instance:**

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

### Step 2 - Create the Extension

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

**Verify:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'pgaudit';
```

Expected output (yours will differ):
```
   name  | installed_version
---------+-------------------
 pgaudit | 16.0
(1 row)
```

### Step 3 - Configure Audit Logging

Set the audit log level. This is a dynamic parameter - no reboot needed.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters \
    "ParameterName=pgaudit.log,ParameterValue=ddl\,write,ApplyMethod=immediate" \
    "ParameterName=pgaudit.log_relation,ParameterValue=on,ApplyMethod=immediate"
```

`pgaudit.log=ddl,write` logs all DDL statements (CREATE, DROP, ALTER) and all write statements (INSERT, UPDATE, DELETE). The `log_relation=on` flag logs the object name for each statement.

**pgaudit.log values:**

| Value | What It Logs |
|---|---|
| `read` | SELECT, COPY FROM |
| `write` | INSERT, UPDATE, DELETE, TRUNCATE, COPY TO |
| `function` | Function calls and DO blocks |
| `role` | GRANT, REVOKE, CREATE/ALTER/DROP ROLE |
| `ddl` | All DDL except ROLE |
| `misc` | DISCARD, FETCH, CHECKPOINT, VACUUM |
| `all` | Everything above |

### Step 4 - Test Audit Logging

```sql
-- Create a test table - this will appear in audit logs
CREATE TABLE audit_test (id serial, name text);

-- Insert data - will appear in audit logs
INSERT INTO audit_test (name) VALUES ('test record');

-- Drop the table
DROP TABLE audit_test;
```

**Check the logs (in RDS console or via CloudWatch):**

1. In RDS console, click on your instance.
2. Click the **Logs & events** tab.
3. Click on the most recent `postgresql.log` file.
4. Search for `AUDIT:` lines.

You should see entries like:
```
AUDIT: SESSION,1,1,DDL,CREATE TABLE,TABLE,public.audit_test,"CREATE TABLE audit_test (id serial, name text);",<not logged>
AUDIT: SESSION,2,1,WRITE,INSERT,TABLE,public.audit_test,"INSERT INTO audit_test (name) VALUES ('test record');",<not logged>
```

---

## Part 4 - Install pg_repack

pg_repack removes bloat from tables and indexes without taking the table offline. This is safer than `VACUUM FULL` for production systems.

> **Concept:** When rows are deleted or updated in PostgreSQL, the old row versions stay in the table as "dead tuples." Over time this causes bloat - the table file gets large even though it has few live rows. `VACUUM` marks dead space as reusable but doesn't shrink the file. `VACUUM FULL` shrinks the file but takes an exclusive lock, blocking all reads and writes. pg_repack shrinks the file while the table stays online.

### Step 1 - Create the Extension

pg_repack does not require preloading - you can install it without a parameter change or reboot.

```sql
CREATE EXTENSION IF NOT EXISTS pg_repack;
```

**Verify:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'pg_repack';
```

Expected output (yours will differ):
```
    name   | installed_version
-----------+-------------------
 pg_repack | 1.5.0
(1 row)
```

### Step 2 - Check a Table for Bloat

First, create a table and add some bloat to it:

```sql
-- Create a test table
CREATE TABLE bloat_test (
  id serial PRIMARY KEY,
  data text
);

-- Insert 100,000 rows
INSERT INTO bloat_test (data)
SELECT repeat('x', 100)
FROM generate_series(1, 100000);

-- Delete 80% of the rows (creates bloat)
DELETE FROM bloat_test WHERE id % 5 != 0;
```

**Check table size before repack:**

```sql
SELECT
  relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  pg_size_pretty(pg_relation_size(relid)) AS table_size,
  n_dead_tup AS dead_tuples
FROM pg_stat_user_tables
WHERE relname = 'bloat_test';
```

Expected output (yours will differ):
```
  table_name | total_size | table_size | dead_tuples
-------------+------------+------------+-------------
 bloat_test  | 17 MB      | 14 MB      |       80000
(1 row)
```

### Step 3 - Run pg_repack

pg_repack runs as a separate command, not inside psql. Open a new terminal:

```bash
pg_repack \
  -h [YOUR-ENDPOINT] \
  -U [YOUR-USERNAME] \
  -d postgres \
  -t bloat_test \
  --no-superuser-check
```

The `-t bloat_test` flag tells pg_repack to only repack that specific table. Without `-t`, it repacks all tables in the database. The `--no-superuser-check` flag is needed on RDS because your user is not a true superuser.

Expected output (yours will differ):
```
INFO: repacking table "public.bloat_test"
INFO: repacking indexes
INFO: swapping relation
INFO: cleaning up index "bloat_test_pkey"
INFO: done
```

**Check table size after repack:**

```sql
SELECT
  relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  n_dead_tup AS dead_tuples
FROM pg_stat_user_tables
WHERE relname = 'bloat_test';
```

Expected output (yours will differ):
```
  table_name | total_size | dead_tuples
-------------+------------+-------------
 bloat_test  | 3576 kB    |           0
(1 row)
```

The table shrank from 17 MB to 3.5 MB while staying fully online.

---

## Part 5 - Extension Version Policy

AWS controls which extensions and which versions of each extension are available on RDS/Aurora. You cannot install an extension that AWS hasn't packaged.

### How to Check Available Versions

```sql
SELECT name, default_version, comment
FROM pg_available_extensions
WHERE name IN ('pg_stat_statements', 'pgaudit', 'pg_repack', 'vector', 'postgis')
ORDER BY name;
```

Expected output (yours will differ):
```
         name         | default_version |                comment
----------------------+-----------------+-----------------------------------------
 pg_repack            | 1.5.0           | Reorganize tables in PostgreSQL datab...
 pg_stat_statements   | 1.10            | track planning and execution statisti...
 pgaudit              | 16.0            | provides auditing functionality
 pgvector             | 0.7.0           | vector data type and ivfflat and hnsw...
 postgis              | 3.4.2           | PostGIS geometry and geography spatial
(5 rows)
```

### Upgrading an Extension Version

When AWS releases a new extension version, upgrade like this:

```sql
ALTER EXTENSION pg_stat_statements UPDATE;
```

This upgrades to the `default_version` shown in `pg_available_extensions`. You cannot specify an exact version - AWS controls what `default_version` points to.

**Check after upgrade:**

```sql
SELECT name, installed_version, default_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

### Why AWS Controls Extension Versions

AWS validates each extension version against each PostgreSQL engine version before making it available. This ensures:
- Extensions don't crash the shared memory pool
- Extensions don't introduce security vulnerabilities
- Extensions don't break existing functionality

The trade-off is that you may lag a few weeks or months behind the latest community extension versions.

---

## Summary

| Extension | Purpose | Preload Required | Key Config |
|---|---|---|---|
| pg_stat_statements | Query performance tracking | Yes | `pg_stat_statements.track=all` |
| pgaudit | Audit logging for compliance | Yes | `pgaudit.log=ddl,write` |
| pg_repack | Online table bloat removal | No | Run as `pg_repack` command |

---

## Cleanup

```sql
-- Remove extensions (in reverse dependency order)
DROP EXTENSION IF EXISTS pg_repack;
DROP EXTENSION IF EXISTS pgaudit;
-- Keep pg_stat_statements - it's useful to leave enabled

-- Remove test tables
DROP TABLE IF EXISTS bloat_test;
```

---

## Next Steps

- [BUILD 04 - pgvector](04-pgvector.md)
- [USE 02 - Extension Setup](../use/02-extension-setup.md)
