# USE Exercise 01: Connect and Explore quantdb

| | |
|---|---|
| **Time** | 30 minutes |
| **Server** | pg-primary (3.90.199.62), pg-replica (3.91.32.84), pg-container (34.235.89.112) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice
- Connecting to quantdb as different roles
- Connecting via PgBouncer (port 6432) vs direct (port 5432)
- Navigating schemas and listing tables
- Checking table sizes and partition structures
- Verifying index usage on key tables
- Reviewing role permissions
- Verifying the replica is read-only
- Connecting to the Docker PostgreSQL instance on pg-container
- Checking Redis health

---

## Exercise 1: SSH into the primary server

On your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

Expected output (yours will differ):
```
Last login: Sun Jun 15 12:00:00 2026 from 1.2.3.4
[ec2-user@pg-primary ~]$
```

---

## Exercise 2: Connect as the postgres superuser

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

Now as **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Expected output (yours will differ):
```
psql (17.x)
Type "help" for help.

quantdb=#
```

---

## Exercise 3: List all schemas and tables

Still as **postgres** in the psql session on **pg-primary**:

List all schemas:

```sql
\dn
```

Expected output (yours will differ):
```
  List of schemas
   Name   |  Owner
----------+----------
 ops      | postgres
 public   | postgres
 quant    | postgres
(3 rows)
```

List all tables in the quant schema:

```sql
\dt quant.*
```

Expected output (yours will differ):
```
              List of relations
 Schema |      Name       | Type  |  Owner
--------+-----------------+-------+----------
 quant  | backtests       | table | postgres
 quant  | instruments     | table | postgres
 quant  | market_data     | table | postgres
 quant  | model_features  | table | postgres
 quant  | models          | table | postgres
 quant  | positions       | table | postgres
 quant  | signals         | table | postgres
(7 rows)
```

List all tables in the ops schema:

```sql
\dt ops.*
```

Expected output (yours will differ):
```
             List of relations
 Schema |      Name      | Type  |  Owner
--------+----------------+-------+----------
 ops    | alerts         | table | postgres
 ops    | deployments    | table | postgres
 ops    | pipeline_runs  | table | postgres
(3 rows)
```

---

## Exercise 4: Check table sizes

Still as **postgres** in the psql session on **pg-primary**:

```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size
FROM pg_tables
WHERE schemaname IN ('quant', 'ops')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
```

Expected output (yours will differ):
```
 schemaname |   tablename    | total_size | table_size
------------+----------------+------------+------------
 quant      | market_data    | 1432 MB    | 980 MB
 quant      | signals        | 412 MB     | 310 MB
 quant      | positions      | 88 MB      | 64 MB
 ...
```

---

## Exercise 5: Check partition structure for market_data

Still as **postgres** in the psql session on **pg-primary**:

```sql
SELECT
  parent.relname AS parent_table,
  child.relname AS partition_name,
  pg_size_pretty(pg_relation_size(child.oid)) AS partition_size
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
WHERE parent.relname = 'market_data'
ORDER BY child.relname;
```

Also check partition details for signals:

```sql
SELECT
  parent.relname AS parent_table,
  child.relname AS partition_name,
  pg_size_pretty(pg_relation_size(child.oid)) AS partition_size
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
WHERE parent.relname = 'signals'
ORDER BY child.relname;
```

---

## Exercise 6: Check index usage on key tables

Still as **postgres** in the psql session on **pg-primary**:

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS scans,
  idx_tup_read AS tuples_read
FROM pg_stat_user_indexes
WHERE schemaname IN ('quant', 'ops')
ORDER BY idx_scan DESC
LIMIT 15;
```

---

## Exercise 7: Check role permissions on quant tables

Still as **postgres** in the psql session on **pg-primary**:

```sql
\dp quant.instruments
```

```sql
\dp quant.market_data
```

Exit the psql session:

```sql
\q
```

Exit the postgres user shell:

```bash
exit
```

You are now back as **ec2-user** on **pg-primary**.

---

## Exercise 8: Connect as quant_app (direct port 5432)

On **pg-primary**, as **ec2-user**:

```bash
PGPASSWORD=quant_app_2026 /usr/pgsql-17/bin/psql -h 127.0.0.1 -p 5432 -U quant_app -d quantdb
```

Test that quant_app can write to quant schema:

```sql
INSERT INTO quant.instruments (symbol, name, asset_class)
VALUES ('TEST-APP', 'App Write Test', 'equity')
RETURNING id, symbol;
```

Clean up the test row:

```sql
DELETE FROM quant.instruments WHERE symbol = 'TEST-APP';
```

Exit:

```sql
\q
```

---

## Exercise 9: Connect as quant_research (read-only on quant)

On **pg-primary**, as **ec2-user**:

```bash
PGPASSWORD=quant_research_2026 /usr/pgsql-17/bin/psql -h 127.0.0.1 -p 5432 -U quant_research -d quantdb
```

Confirm reads work:

```sql
SELECT COUNT(*) FROM quant.instruments;
```

Confirm writes are blocked:

```sql
INSERT INTO quant.instruments (symbol, name, asset_class)
VALUES ('TEST-DENY', 'Should Fail', 'equity');
```

Expected output (yours will differ):
```
ERROR:  permission denied for table instruments
```

Exit:

```sql
\q
```

---

## Exercise 10: Connect via PgBouncer (port 6432) vs direct (port 5432)

On **pg-primary**, as **ec2-user**:

Connect directly to PostgreSQL on port 5432:

```bash
PGPASSWORD=quant_readonly_2026 /usr/pgsql-17/bin/psql -h 127.0.0.1 -p 5432 -U quant_readonly -d quantdb -c "SELECT current_setting('port'), inet_server_addr();"
```

Now connect through PgBouncer on port 6432:

```bash
PGPASSWORD=quant_readonly_2026 /usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U quant_readonly -d quantdb -c "SELECT current_setting('port'), inet_server_addr();"
```

Note: Both connections reach quantdb, but PgBouncer on port 6432 manages connection pooling. The client connects to PgBouncer, which holds a smaller pool of backend connections to PostgreSQL.

Check PgBouncer pool stats:

```bash
PGPASSWORD=quant_readonly_2026 /usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U quant_readonly -d pgbouncer -c "SHOW POOLS;"
```

---

## Exercise 11: Connect to the replica and verify it is read-only

On your local machine, open a second terminal and SSH into the replica:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

On **pg-replica**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Confirm this is a standby:

```sql
SELECT pg_is_in_recovery();
```

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 t
(1 row)
```

Try to write (this should fail):

```sql
INSERT INTO quant.instruments (symbol, name, asset_class)
VALUES ('TEST-REPLICA', 'Should Fail', 'equity');
```

Expected output (yours will differ):
```
ERROR:  cannot execute INSERT in a read-only transaction
```

Exit psql and the postgres shell:

```sql
\q
```

```bash
exit
```

---

## Exercise 12: Connect to Docker PostgreSQL on pg-container (port 5433)

On your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

On **pg-container**, as **ec2-user**:

```bash
PGPASSWORD=quant_readonly_2026 /usr/pgsql-17/bin/psql -h 127.0.0.1 -p 5433 -U quant_readonly -d quantdb
```

Check the PostgreSQL version in the container:

```sql
SELECT version();
```

List schemas:

```sql
\dn
```

Exit:

```sql
\q
```

---

## Exercise 13: Check Redis health

On **pg-primary**, as **ec2-user**:

```bash
redis-cli -a redis_voleon_2026 ping
```

Expected output (yours will differ):
```
PONG
```

Check Redis info summary:

```bash
redis-cli -a redis_voleon_2026 info server | grep -E "redis_version|uptime|tcp_port"
```

Expected output (yours will differ):
```
redis_version:7.x.x
uptime_in_seconds:86400
tcp_port:6379
```

Check memory usage:

```bash
redis-cli -a redis_voleon_2026 info memory | grep -E "used_memory_human|maxmemory_human"
```

Check the number of keys in the default database:

```bash
redis-cli -a redis_voleon_2026 dbsize
```

---

## Summary

In this exercise you:
- Connected to quantdb as postgres, quant_app, quant_research, and quant_readonly
- Verified that quant_research cannot write to the quant schema
- Navigated schemas and tables using psql meta-commands
- Checked table sizes and partition structures for market_data and signals
- Reviewed index usage and role permissions
- Confirmed the replica is read-only
- Connected to the Docker PostgreSQL instance on port 5433
- Verified Redis is running and accepting connections
