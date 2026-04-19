# Exercise 02 - Multi-Version Management

**Time estimate:** 25-30 minutes
**Prerequisites:** BUILD phase complete - CentOS Stream 9 with PostgreSQL 16 (RPM) running on port 5432, PostgreSQL 15 (RPM) running on port 5433, source-compiled PG at `/opt/pg-src/bin/`. PGDATA at `/opt/pgsql/data`. Database `labdb` exists on PG16. Extensions installed: pg_stat_statements, pgcrypto, pg_trgm, pageinspect.

---

## Scenario

A developer needs to test their application against PostgreSQL 15 before your team upgrades the production cluster from PG15 to PG16. Your job is to set up a test database on PG15 that mirrors their workflow, compare behavior between versions, and demonstrate how to manage both services.

---

## Step 1 - Connect to Both Versions and Compare

Verify both clusters are accepting connections. The `pg_isready` command checks connectivity without requiring authentication. The `-p` flag specifies the port:

```bash
pg_isready -p 5432
```

**Expected:**

```
/var/run/postgresql:5432 - accepting connections
```

```bash
pg_isready -p 5433
```

**Expected:**

```
/var/run/postgresql:5433 - accepting connections
```

Now connect to each and confirm the version. Switch to the postgres user:

```bash
sudo -iu postgres
```

Connect to PG16 on port 5432:

```bash
psql -p 5432 -c "SELECT version();"
```

**Expected:**

```
                                                version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

Connect to PG15 on port 5433:

```bash
psql -p 5433 -c "SELECT version();"
```

**Expected:**

```
                                                version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 15.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

> **Concept: Port-Based Version Switching**
> When multiple PostgreSQL versions run on the same server, the `-p` flag is your version selector. Everything else - `psql`, `pg_dump`, `createdb` - works the same way. The client tools are generally backward-compatible, so you can use PG16's `psql` to connect to a PG15 server. The reverse (PG15 psql connecting to PG16 server) also works but may not display newer features correctly.

---

## Step 2 - Create a Test Database on PG15

You should still be the postgres user. Create a database called `devtest` on the PG15 cluster. The `-p` flag directs `createdb` to the PG15 server on port 5433:

```bash
createdb -p 5433 devtest
```

**Expected:** No output means success.

Connect to the new database:

```bash
psql -p 5433 -d devtest
```

Create a test table and insert sample data:

```sql
CREATE TABLE employees (
    id serial PRIMARY KEY,
    name text NOT NULL,
    department text,
    salary numeric(10,2),
    hire_date date DEFAULT current_date
);
```

**Expected:**

```
CREATE TABLE
```

```sql
INSERT INTO employees (name, department, salary) VALUES
    ('Alice Chen', 'Engineering', 125000),
    ('Bob Martinez', 'Engineering', 118000),
    ('Carol Singh', 'Marketing', 95000),
    ('David Kim', 'Engineering', 132000),
    ('Eva Johansson', 'Marketing', 102000);
```

**Expected:**

```
INSERT 0 5
```

Run a basic query to verify:

```sql
SELECT department, count(*), avg(salary)::numeric(10,2)
FROM employees
GROUP BY department
ORDER BY avg(salary) DESC;
```

**Expected:**

```
 department  | count |    avg
-------------+-------+-----------
 Engineering |     3 | 125000.00
 Marketing   |     2 |  98500.00
(2 rows)
```

Exit psql:

```sql
\q
```

---

## Step 3 - Run the Same Queries on PG16

Now create the same table and data on PG16 to compare behavior. Connect to PG16's `labdb`:

```bash
psql -p 5432 -d labdb
```

Create the same table:

```sql
CREATE TABLE employees (
    id serial PRIMARY KEY,
    name text NOT NULL,
    department text,
    salary numeric(10,2),
    hire_date date DEFAULT current_date
);
```

**Expected:**

```
CREATE TABLE
```

```sql
INSERT INTO employees (name, department, salary) VALUES
    ('Alice Chen', 'Engineering', 125000),
    ('Bob Martinez', 'Engineering', 118000),
    ('Carol Singh', 'Marketing', 95000),
    ('David Kim', 'Engineering', 132000),
    ('Eva Johansson', 'Marketing', 102000);
```

**Expected:**

```
INSERT 0 5
```

Run the same aggregation query:

```sql
SELECT department, count(*), avg(salary)::numeric(10,2)
FROM employees
GROUP BY department
ORDER BY avg(salary) DESC;
```

**Expected:** Same results as PG15. Basic SQL behavior is identical across versions.

Exit psql:

```sql
\q
```

> **Concept: Cross-Version Compatibility**
> Standard SQL behavior is consistent across PostgreSQL major versions. Simple queries (SELECT, INSERT, UPDATE, DELETE, JOINs, aggregations) produce the same results on PG15 and PG16. The differences appear in system views, new SQL features, query planner improvements, and extension capabilities. When testing an application upgrade, focus on edge cases - not basic CRUD.

---

## Step 4 - Compare Version-Specific Features

One of the differences between PG15 and PG16 is the `pg_stat_statements` extension. PG16 added new columns. Let's compare.

Connect to PG16:

```bash
psql -p 5432 -d labdb
```

Check the columns available in `pg_stat_statements`:

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'pg_stat_statements'
ORDER BY ordinal_position;
```

**Expected (partial - PG16 has many columns):**

```
       column_name
--------------------------
 userid
 dbid
 toplevel
 queryid
 query
 plans
 total_plan_time
 ...
 jit_functions
 jit_generation_time
 jit_inlining_count
 jit_inlining_time
 jit_optimization_count
 jit_optimization_time
 jit_emission_count
 jit_emission_time
```

Note the number of columns. Exit psql:

```sql
\q
```

Now install `pg_stat_statements` on PG15 and compare. First, configure PG15 to preload the extension. Open the PG15 config file:

```bash
vi /opt/pgsql/data15/postgresql.conf
```

Find the `shared_preload_libraries` line and set it to:

```
shared_preload_libraries = 'pg_stat_statements'
```

Save and exit vi (`:wq`).

Exit the postgres user:

```bash
exit
```

Restart PG15 to load the shared library:

```bash
sudo systemctl restart postgresql-15
```

Verify PG15 restarted:

```bash
pg_isready -p 5433
```

**Expected:**

```
/var/run/postgresql:5433 - accepting connections
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Connect to PG15 and install the extension:

```bash
psql -p 5433 -d devtest
```

```sql
CREATE EXTENSION pg_stat_statements;
```

**Expected:**

```
CREATE EXTENSION
```

Check the columns available on PG15:

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'pg_stat_statements'
ORDER BY ordinal_position;
```

**Expected:** Fewer columns than PG16. PG15's `pg_stat_statements` (version 1.10) does not include some columns that PG16 added - for example, PG16 added `min_exec_time` and `max_exec_time` improvements and better JIT tracking.

Count the columns on each version to quantify the difference:

```sql
SELECT count(*)
FROM information_schema.columns
WHERE table_name = 'pg_stat_statements';
```

Note the count. Exit psql:

```sql
\q
```

> **Concept: Extension Version Differences**
> Extensions evolve across PostgreSQL major versions. Even though the extension name is the same (`pg_stat_statements`), PG16 ships version 1.10 while PG15 might ship 1.9 or 1.10 with different underlying functionality. When planning a major-version upgrade, check the extension release notes for breaking changes - especially for monitoring tools that query these views.

---

## Step 5 - Manage Both Services

You should still be the postgres user. Exit back to ec2-user:

```bash
exit
```

Check the status of both services with one command:

```bash
sudo systemctl list-units --type=service --state=running | grep postgresql
```

**Expected:**

```
  postgresql-15.service   loaded active running   PostgreSQL 15 database server (port 5433)
  postgresql-16.service   loaded active running   PostgreSQL 16 database server
```

Stop the PG15 service:

```bash
sudo systemctl stop postgresql-15
```

Verify it stopped:

```bash
pg_isready -p 5433
```

**Expected:**

```
/var/run/postgresql:5433 - no response
```

Confirm PG16 is unaffected:

```bash
pg_isready -p 5432
```

**Expected:**

```
/var/run/postgresql:5432 - accepting connections
```

Start PG15 again:

```bash
sudo systemctl start postgresql-15
```

Verify it is back:

```bash
pg_isready -p 5433
```

**Expected:**

```
/var/run/postgresql:5433 - accepting connections
```

Check which services are enabled for auto-start on boot:

```bash
sudo systemctl is-enabled postgresql-15
```

**Expected:**

```
enabled
```

```bash
sudo systemctl is-enabled postgresql-16
```

**Expected:**

```
enabled
```

> **Concept: Service Independence**
> Each PostgreSQL version runs as a completely independent systemd service. Stopping PG15 has zero effect on PG16. They share CPU, memory, and disk I/O, but their processes, data directories, and configuration files are fully separate. In production, if you need to restart one version for a configuration change, users connected to the other version will not notice.

---

## Step 6 - Clean Up the Test Database

Switch to the postgres user:

```bash
sudo -iu postgres
```

Drop the test database on PG15. The `-p` flag tells `dropdb` which server to connect to:

```bash
dropdb -p 5433 devtest
```

**Expected:** No output means success.

Drop the employees table from PG16's labdb:

```bash
psql -p 5432 -d labdb -c "DROP TABLE employees;"
```

**Expected:**

```
DROP TABLE
```

Exit the postgres user:

```bash
exit
```

---

## Checkpoint

Before moving on, confirm you can:

- [ ] Connect to both PG versions using the `-p` flag to specify the port
- [ ] Create databases and tables on either version independently
- [ ] Compare extension capabilities between versions using `information_schema.columns`
- [ ] Start, stop, and check status of each service independently
- [ ] Verify auto-start configuration with `systemctl is-enabled`
- [ ] Drop databases and tables to clean up after testing

---

**Next:** Exercise 03 - Source vs. Package
