# Build 05: Day Two Operations

Day Two is everything after the initial deployment. This guide covers common operational tasks: adding tables with migrations, creating read replicas, minor version upgrades, performance troubleshooting, capacity planning, and security audits.

Run all steps on the **primary** server unless noted otherwise.

---

## Prerequisites

- Completed Build 01-04
- Production PostgreSQL 16 running with replication, backups, and monitoring

---

## 1. Adding a New Table with Migration

Never run DDL directly in production. Use a migration workflow: write the SQL, review it, test it, then apply it with a record of what changed.

### 1.1 Create a migrations directory

```bash
su - postgres
```

```bash
mkdir -p /opt/pgsql/scripts/migrations
```

### 1.2 Write the migration

```bash
vi /opt/pgsql/scripts/migrations/001-add-products-table.sql
```

Add:

```sql
-- Migration 001: Add products table
-- Author: [YOUR NAME]
-- Date: 2026-04-19
-- Ticket: JIRA-1234

BEGIN;

-- Create the table
CREATE TABLE IF NOT EXISTS app.products (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku             text NOT NULL,
    name            text NOT NULL,
    description     text,
    price_cents     bigint NOT NULL CHECK (price_cents >= 0),
    stock_quantity  int NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    category        text NOT NULL DEFAULT 'uncategorized',
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Create indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_sku ON app.products (sku);
CREATE INDEX IF NOT EXISTS idx_products_category ON app.products (category) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON app.products USING gin (name gin_trgm_ops);

-- Add audit trigger
CREATE TRIGGER trg_products_audit
    AFTER INSERT OR UPDATE OR DELETE ON app.products
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON app.products TO app_readwrite;
GRANT SELECT ON app.products TO app_readonly;
GRANT USAGE, SELECT ON SEQUENCE app.products_id_seq TO app_readwrite;

-- Record the migration
CREATE TABLE IF NOT EXISTS app.schema_migrations (
    version     text PRIMARY KEY,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    description text
);

INSERT INTO app.schema_migrations (version, description)
VALUES ('001', 'Add products table')
ON CONFLICT (version) DO NOTHING;

COMMIT;
```

Save and exit (`:wq`).

Key practices:
- Wrap everything in a transaction (`BEGIN`/`COMMIT`). If any statement fails, nothing is applied.
- Use `IF NOT EXISTS` guards so the migration is idempotent (safe to run twice).
- Record the migration in a tracking table.
- Include ticket number and author for audit trail.

### 1.3 Review the migration

Before applying, check for potential issues:

```bash
cat /opt/pgsql/scripts/migrations/001-add-products-table.sql
```

Checklist:
- Does it wrap in a transaction? Yes.
- Does it use IF NOT EXISTS? Yes.
- Does it create appropriate indexes? Yes.
- Does it grant permissions? Yes.
- Does it have an audit trigger? Yes.
- Will any statement take a long lock? No - CREATE TABLE is fast on empty tables.

### 1.4 Apply the migration

```bash
/usr/pgsql-16/bin/psql -d appdb -f /opt/pgsql/scripts/migrations/001-add-products-table.sql
```

Expected output:
```
BEGIN
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE TRIGGER
GRANT
GRANT
GRANT
CREATE TABLE
INSERT 0 1
COMMIT
```

### 1.5 Verify on the standby

On the **standby**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'products';"
```

Expected output:
```
 count
-------
     1
```

The table replicated to the standby automatically via streaming replication.

```bash
exit
```

### 1.6 Write a rollback migration

Always write the reverse migration in case you need to undo:

```bash
vi /opt/pgsql/scripts/migrations/001-add-products-table-rollback.sql
```

Add:

```sql
-- Rollback Migration 001: Remove products table
BEGIN;

DROP TABLE IF EXISTS app.products CASCADE;

DELETE FROM app.schema_migrations WHERE version = '001';

COMMIT;
```

Save and exit (`:wq`).

```bash
exit
```

---

## 2. Creating a Read Replica

A read replica is a standby server that applications query directly for read-heavy workloads. It offloads SELECT queries from the primary.

### 2.1 When to add a read replica

Add a read replica when:
- Read queries are consuming more than 60% of primary CPU
- You need to run analytics without affecting OLTP performance
- You need geographic read locality

### 2.2 Provision the new server

Follow Build 01 sections 1-3 on the new server to prepare the OS, filesystem, and install PostgreSQL 16.

### 2.3 Create a replication slot on the primary

On the **primary**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_create_physical_replication_slot('read_replica_1');"
```

### 2.4 Take a base backup

On the **new replica server**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/pg_basebackup -h [PRIMARY_IP] -U replicator -D /opt/pgsql/data --waldir=/opt/pgsql/wal -X stream -P -R -S read_replica_1
```

### 2.5 Configure for read-only workloads

```bash
vi /opt/pgsql/data/postgresql.conf
```

Add or update:

```
hot_standby = on
hot_standby_feedback = on
max_standby_streaming_delay = 30s
max_standby_archive_delay = 60s
```

Save and exit (`:wq`).

- `max_standby_streaming_delay = 30s` - Allow queries on the replica to delay WAL replay by up to 30 seconds. This prevents query cancellations at the cost of slightly stale data.
- `max_standby_archive_delay = 60s` - Same concept but for archive replay.

### 2.6 Start and verify

Start PostgreSQL on the replica, then verify:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output:
```
 pg_is_in_recovery
--------------------
 t
```

### 2.7 Route read traffic

Update your application's connection string to use the replica for reads:

```
# Primary (writes)
postgresql://app_readwrite:password@pg-prod-primary:5432/appdb

# Replica (reads)
postgresql://app_readonly:password@pg-read-replica-1:5432/appdb
```

Or configure pgBouncer to route by database alias:

```ini
[databases]
appdb = host=pg-prod-primary port=5432 dbname=appdb
appdb_ro = host=pg-read-replica-1 port=5432 dbname=appdb
```

```bash
exit
```

---

## 3. Minor Version Upgrade (16.x to 16.y)

Minor version upgrades fix bugs and security issues. They do not change the data format and do not require pg_upgrade or dump/restore.

### 3.1 Check the current version

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT version();"
```

Expected output (yours will differ):
```
                          version
-------------------------------------------------------
 PostgreSQL 16.2 on x86_64-pc-linux-gnu, compiled by ...
```

```bash
exit
```

### 3.2 Read the release notes

Before upgrading, always read the release notes:

```bash
curl -s https://www.postgresql.org/docs/16/release-16-3.html | head -50
```

Check for:
- Bug fixes that affect your workload
- Security fixes (upgrade urgently)
- Any special migration notes

### 3.3 Upgrade the standby first

On the **standby** as root:

```bash
systemctl stop postgresql-16
```

```bash
dnf update -y postgresql16-server postgresql16-contrib
```

```bash
systemctl start postgresql-16
```

Verify replication is working:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT version();"
```

Confirm the version number increased and the standby is in recovery mode.

```bash
exit
```

### 3.4 Upgrade the primary

On the **primary** as root:

```bash
systemctl stop postgresql-16
```

```bash
dnf update -y postgresql16-server postgresql16-contrib
```

```bash
systemctl start postgresql-16
```

Verify:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT version();"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state FROM pg_stat_replication;"
```

Confirm the version is updated and replication resumed.

```bash
exit
```

> **Concept - Upgrade order**: Upgrade standbys first, then the primary. This way, if the upgrade breaks something on the standby, the primary is unaffected and you can investigate safely. The standby can replay WAL from a newer minor version to an older one without issues.

---

## 4. Handling Performance Degradation

### 4.1 The triage process

When performance drops, follow this order:

1. **Is it the database?** Check pg_stat_activity for active queries.
2. **Is it a single query?** Check pg_stat_statements for top consumers.
3. **Is it the system?** Check CPU, memory, disk I/O.
4. **Is it locks?** Check pg_locks for blocking.

### 4.2 Step 1 - Check active queries

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT pid, now() - query_start AS runtime, state, left(query, 80) AS query FROM pg_stat_activity WHERE state != 'idle' AND pid != pg_backend_pid() ORDER BY runtime DESC LIMIT 20;"
```

Expected output (yours will differ):
```
  pid  |  runtime  | state  |                     query
-------+-----------+--------+-----------------------------------------------
 12345 | 00:05:23  | active | SELECT * FROM app.orders WHERE status = 'pen...
 12346 | 00:00:01  | active | INSERT INTO app.order_items ...
```

Look for queries running longer than expected.

### 4.3 Step 2 - Check top queries by total time

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT left(query, 60) AS query, calls, round(total_exec_time::numeric, 1) AS total_ms, round(mean_exec_time::numeric, 1) AS avg_ms, rows FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"
```

Expected output (yours will differ):
```
                         query                         | calls | total_ms | avg_ms | rows
-------------------------------------------------------+-------+----------+--------+------
 SELECT * FROM app.orders WHERE status = $1            |  5000 |  45000.0 |    9.0 | 25000
 INSERT INTO app.order_items (order_id, product_name...|  3000 |  12000.0 |    4.0 |  3000
```

### 4.4 Step 3 - Explain a slow query

```bash
/usr/pgsql-16/bin/psql -d appdb -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT * FROM app.orders WHERE status = 'pending';"
```

Expected output (yours will differ):
```
                                    QUERY PLAN
---------------------------------------------------------------------------
 Index Scan using idx_orders_status on orders  (cost=0.29..8.31 rows=1 ...)
   Index Cond: (status = 'pending')
   Buffers: shared hit=4
 Planning Time: 0.1 ms
 Execution Time: 0.05 ms
```

Key things to look for:
- `Seq Scan` on large tables - needs an index
- `Buffers: shared read=` (large number) - data not in cache
- `Rows Removed by Filter:` (large number) - index not selective enough
- `Sort Method: external merge Disk` - work_mem too low

### 4.5 Step 4 - Check for lock contention

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT blocked.pid AS blocked_pid, blocked.query AS blocked_query, blocking.pid AS blocking_pid, blocking.query AS blocking_query FROM pg_stat_activity AS blocked JOIN pg_locks AS bl ON bl.pid = blocked.pid JOIN pg_locks AS kl ON kl.locktype = bl.locktype AND kl.database IS NOT DISTINCT FROM bl.database AND kl.relation IS NOT DISTINCT FROM bl.relation AND kl.page IS NOT DISTINCT FROM bl.page AND kl.tuple IS NOT DISTINCT FROM bl.tuple AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid AND kl.classid IS NOT DISTINCT FROM bl.classid AND kl.objid IS NOT DISTINCT FROM bl.objid AND kl.objsubid IS NOT DISTINCT FROM bl.objsubid AND kl.pid != bl.pid JOIN pg_stat_activity AS blocking ON kl.pid = blocking.pid WHERE NOT bl.granted LIMIT 10;"
```

If you see results, some queries are blocked by others. Common causes:
- Long-running transactions holding locks
- DDL statements (ALTER TABLE) blocking DML
- Explicit LOCK TABLE commands

### 4.6 Fix common issues

**Missing index:**

```bash
/usr/pgsql-16/bin/psql -d appdb -c "CREATE INDEX CONCURRENTLY idx_orders_created_at ON app.orders (created_at);"
```

The `CONCURRENTLY` keyword builds the index without locking the table. Always use it in production.

**Stale statistics:**

```bash
/usr/pgsql-16/bin/psql -d appdb -c "ANALYZE app.orders;"
```

This updates the table statistics so the query planner makes better decisions.

**Bloated table:**

```bash
/usr/pgsql-16/bin/psql -d appdb -c "VACUUM ANALYZE app.orders;"
```

```bash
exit
```

---

## 5. Capacity Planning Review

### 5.1 Current database sizes

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY pg_database_size(datname) DESC;"
```

Expected output (yours will differ):
```
 datname |  size
---------+--------
 appdb   | 125 MB
 repmgr  | 8 MB
 postgres| 7 MB
```

### 5.2 Table sizes

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname || '.' || relname AS table, pg_size_pretty(pg_total_relation_size(relid)) AS total_size, pg_size_pretty(pg_relation_size(relid)) AS table_size, pg_size_pretty(pg_indexes_size(relid)) AS index_size FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"
```

### 5.3 Growth rate

Check how fast tables are growing:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT relname, n_tup_ins AS inserts, n_tup_upd AS updates, n_tup_del AS deletes, stats_reset FROM pg_stat_user_tables ORDER BY n_tup_ins DESC LIMIT 10;"
```

### 5.4 Connection usage over time

```bash
/usr/pgsql-16/bin/psql -c "SELECT count(*) AS total, count(*) FILTER (WHERE state = 'active') AS active, count(*) FILTER (WHERE state = 'idle') AS idle, count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn, (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn FROM pg_stat_activity;"
```

### 5.5 Cache hit ratio

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT sum(heap_blks_hit)::float / greatest(sum(heap_blks_hit) + sum(heap_blks_read), 1) * 100 AS cache_hit_ratio FROM pg_statio_user_tables;"
```

Expected output:
```
  cache_hit_ratio
-------------------
 99.2
```

A cache hit ratio below 95% indicates you may need more shared_buffers or RAM.

### 5.6 Disk usage projections

Calculate how much disk you need for the next 6 months:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT pg_size_pretty(pg_database_size('appdb')) AS current_size, pg_size_pretty(pg_database_size('appdb') * 2) AS projected_6mo, pg_size_pretty(pg_database_size('appdb') * 4) AS projected_12mo;"
```

This is a rough projection assuming 2x growth per 6 months. Adjust the multiplier based on your actual growth rate from step 5.3.

```bash
exit
```

---

## 6. Security Audit Checklist

### 6.1 Check for superuser roles

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication FROM pg_roles WHERE rolsuper = true ORDER BY rolname;"
```

Expected output:
```
 rolname  | rolsuper | rolcreaterole | rolcreatedb | rolreplication
----------+----------+---------------+-------------+----------------
 postgres | t        | t             | t           | t
 repmgr   | t        | t             | t           | t
```

Only `postgres` and `repmgr` should be superusers. If you see other roles, investigate.

### 6.2 Check pg_hba.conf for trust or md5

```bash
cat /opt/pgsql/data/pg_hba.conf | grep -v '^#' | grep -v '^$'
```

Look for:
- `trust` - No password required. Never use for remote connections.
- `md5` - Weak hashing. Replace with `scram-sha-256`.
- `0.0.0.0/0` without `hostssl` - Unencrypted remote access.

### 6.3 Check SSL is enforced

```bash
/usr/pgsql-16/bin/psql -c "SHOW ssl;"
```

Expected output:
```
 ssl
-----
 on
```

### 6.4 Check password encryption

```bash
/usr/pgsql-16/bin/psql -c "SHOW password_encryption;"
```

Expected output:
```
 password_encryption
---------------------
 scram-sha-256
```

### 6.5 Check for roles without passwords

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname FROM pg_authid WHERE rolcanlogin AND rolpassword IS NULL;"
```

Any results here are roles that can log in without a password (via peer or other methods). Verify this is intentional.

### 6.6 Check logging is enabled

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_connections;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_disconnections;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_statement;"
```

All should be `on` or `ddl` (for log_statement).

### 6.7 Check for public schema permissions

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT nspname, nspacl FROM pg_namespace WHERE nspname = 'public';"
```

In PostgreSQL 15+, the default is restricted. But verify no one granted broad access.

```bash
exit
```

---

## Summary

Day Two operations covered:

- **Migrations**: Transactional DDL with rollback scripts and tracking table
- **Read replicas**: Offload reads with minimal configuration
- **Minor upgrades**: Standby-first rolling upgrades with zero downtime
- **Performance triage**: 4-step process from symptoms to fix
- **Capacity planning**: Size, growth rate, cache ratio, and projections
- **Security audit**: 7-point checklist for roles, auth, SSL, and logging

These tasks make up 80% of a production DBA's daily work. Master them, and you can manage any PostgreSQL deployment with confidence.

This completes the Build section of Module 20.
