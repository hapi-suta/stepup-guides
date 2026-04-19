# Module 19 - BUILD 01: Schema Migration Tools

## Overview

Database schema changes are the most dangerous part of any deployment. A missing column, a bad index, or a dropped table can take down production in seconds. Schema migration tools give you version control for your database - every change is tracked, ordered, and repeatable.

This guide covers pg_dump/pg_restore for schema versioning, Flyway, Liquibase, and how they compare.

---

## Prerequisites

- CentOS Stream 9 server with PostgreSQL 16 installed and running
- `postgres` OS user configured
- A test database to work with

---

## Part 1: pg_dump and pg_restore for Schema Versioning

### 1.1 Create a Test Database

Switch to the postgres user first.

```bash
sudo -iu postgres
```

Create a database for this lab.

```bash
createdb migration_lab
```

Connect to the new database. The `-d` flag specifies which database to connect to.

```bash
psql -d migration_lab
```

Create some initial schema to work with.

```sql
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    department VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
);
```

```sql
CREATE INDEX idx_employees_department ON employees (department);
```

```sql
INSERT INTO employees (name, email, department) VALUES
    ('Alice Johnson', 'alice@company.com', 'Engineering'),
    ('Bob Smith', 'bob@company.com', 'Marketing');
```

Exit psql.

```sql
\q
```

### 1.2 Dump Schema Only

The `--schema-only` flag tells pg_dump to export table definitions, indexes, and constraints - but no row data. This is your "schema snapshot."

```bash
pg_dump --schema-only -d migration_lab -f /tmp/schema_v1.sql
```

Look at what pg_dump produced. The `-n` flag shows line numbers.

```bash
cat -n /tmp/schema_v1.sql
```

Expected output (yours will differ):
```
     1  --
     2  -- PostgreSQL database dump
     3  --
     ...
    15  CREATE TABLE public.employees (
    16      id integer NOT NULL,
    17      name character varying(100) NOT NULL,
    18      email character varying(255),
    ...
```

### 1.3 Make a Schema Change

Connect to the database again.

```bash
psql -d migration_lab
```

Add a new column.

```sql
ALTER TABLE employees ADD COLUMN salary NUMERIC(10,2);
```

Exit psql.

```sql
\q
```

### 1.4 Dump the New Schema Version

```bash
pg_dump --schema-only -d migration_lab -f /tmp/schema_v2.sql
```

### 1.5 Diff the Two Versions

The `diff` command compares two files line by line. The `-u` flag gives unified format which is easier to read. Lines starting with `+` are additions, `-` are removals.

```bash
diff -u /tmp/schema_v1.sql /tmp/schema_v2.sql
```

Expected output (yours will differ):
```
---  /tmp/schema_v1.sql    2026-04-19 10:00:00
+++  /tmp/schema_v2.sql    2026-04-19 10:05:00
@@ -15,6 +15,7 @@
     name character varying(100) NOT NULL,
     email character varying(255),
     department character varying(50),
+    salary numeric(10,2),
     created_at timestamp without time zone DEFAULT now()
 );
```

### 1.6 Restore Schema to a Fresh Database

Create a new empty database.

```bash
createdb migration_lab_v2
```

Restore the v2 schema into it. The `-f` flag specifies the input file.

```bash
psql -d migration_lab_v2 -f /tmp/schema_v2.sql
```

Verify the schema was restored.

```bash
psql -d migration_lab_v2 -c "\dt"
```

Expected output (yours will differ):
```
           List of relations
 Schema |   Name    | Type  |  Owner
--------+-----------+-------+----------
 public | employees | table | postgres
(1 row)
```

### 1.7 Store Schema Dumps in Git

Exit the postgres user.

```bash
exit
```

Create a directory for schema versions.

```bash
mkdir -p /opt/pgsql/schema-versions
```

Copy the schema files there.

```bash
sudo cp /tmp/schema_v1.sql /opt/pgsql/schema-versions/
```

```bash
sudo cp /tmp/schema_v2.sql /opt/pgsql/schema-versions/
```

In a real workflow, you would `git init` this directory and commit each schema version. This gives you a full audit trail of every database change.

---

## Part 2: Flyway Setup and Migration Files

Flyway is the most popular open-source schema migration tool. It uses numbered SQL files and tracks which migrations have been applied.

### 2.1 Install Flyway

Download Flyway. The `-L` flag follows redirects. The `-o` flag specifies the output filename.

```bash
curl -L -o /tmp/flyway-commandline-10.10.0-linux-x64.tar.gz https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/10.10.0/flyway-commandline-10.10.0-linux-x64.tar.gz
```

Extract it. The `-C` flag specifies the target directory.

```bash
sudo tar -xzf /tmp/flyway-commandline-10.10.0-linux-x64.tar.gz -C /opt/
```

Create a symlink so you can run `flyway` from anywhere.

```bash
sudo ln -s /opt/flyway-10.10.0/flyway /usr/local/bin/flyway
```

Verify the install.

```bash
flyway --version
```

Expected output (yours will differ):
```
Flyway Community Edition 10.10.0 by Redgate
```

### 2.2 Understand Flyway Naming Convention

Flyway migration files follow a strict naming pattern:

```
V{version}__{description}.sql
```

Key rules:
- `V` prefix means a versioned migration (runs once)
- Version number uses dots or underscores: `V1`, `V1.1`, `V1_1`
- Double underscore `__` separates version from description
- Description uses underscores for spaces
- Extension must be `.sql`

Examples:
- `V1__create_employees_table.sql`
- `V2__add_salary_column.sql`
- `V3.1__create_departments_table.sql`

Flyway also supports:
- `R__` prefix for repeatable migrations (re-run when file changes)
- `U__` prefix for undo migrations (Flyway Teams only)

### 2.3 Create a Flyway Project

Switch to the postgres user.

```bash
sudo -iu postgres
```

Create a database for Flyway.

```bash
createdb flyway_lab
```

Exit the postgres user.

```bash
exit
```

Create the project directory structure.

```bash
mkdir -p /opt/pgsql/flyway-project/sql
```

### 2.4 Configure Flyway

Open the config file with vi.

```bash
sudo vi /opt/pgsql/flyway-project/flyway.conf
```

Add this content:

```
flyway.url=jdbc:postgresql://localhost:5432/flyway_lab
flyway.user=postgres
flyway.locations=filesystem:/opt/pgsql/flyway-project/sql
flyway.baselineOnMigrate=true
```

Line-by-line explanation:
- `flyway.url` - JDBC connection string to your database
- `flyway.user` - Database user for running migrations
- `flyway.locations` - Where Flyway looks for SQL migration files
- `flyway.baselineOnMigrate` - Allows Flyway to work with an existing database

### 2.5 Create Migration Files

Create the first migration.

```bash
sudo vi /opt/pgsql/flyway-project/sql/V1__create_employees.sql
```

```sql
CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

Create the second migration.

```bash
sudo vi /opt/pgsql/flyway-project/sql/V2__add_department_column.sql
```

```sql
ALTER TABLE employees ADD COLUMN IF NOT EXISTS department VARCHAR(50);
CREATE INDEX IF NOT EXISTS idx_emp_dept ON employees (department);
```

Create the third migration.

```bash
sudo vi /opt/pgsql/flyway-project/sql/V3__create_audit_log.sql
```

```sql
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by VARCHAR(100) DEFAULT current_user,
    changed_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_changed_at ON audit_log (changed_at);
```

### 2.6 Run Migrations

Run Flyway with the `-configFiles` flag pointing to your config.

```bash
flyway -configFiles=/opt/pgsql/flyway-project/flyway.conf migrate
```

Expected output (yours will differ):
```
Flyway Community Edition 10.10.0 by Redgate
Database: jdbc:postgresql://localhost:5432/flyway_lab (PostgreSQL 16.2)
Successfully validated 3 migrations
Current version of schema "public": << Empty Schema >>
Migrating schema "public" to version "1 - create employees"
Migrating schema "public" to version "2 - add department column"
Migrating schema "public" to version "3 - create audit log"
Successfully applied 3 migrations to schema "public"
```

### 2.7 Check Migration Status

```bash
flyway -configFiles=/opt/pgsql/flyway-project/flyway.conf info
```

Expected output (yours will differ):
```
+-----------+---------+---------------------+----------+---------------------+
| Category  | Version | Description         | Type     | Installed On        |
+-----------+---------+---------------------+----------+---------------------+
| Versioned | 1       | create employees    | SQL      | 2026-04-19 10:15:00 |
| Versioned | 2       | add department col  | SQL      | 2026-04-19 10:15:00 |
| Versioned | 3       | create audit log    | SQL      | 2026-04-19 10:15:01 |
+-----------+---------+---------------------+----------+---------------------+
```

### 2.8 Verify in the Database

Switch to postgres user.

```bash
sudo -iu postgres
```

Check what Flyway created.

```bash
psql -d flyway_lab -c "\dt"
```

Expected output (yours will differ):
```
              List of relations
 Schema |         Name          | Type  |  Owner
--------+-----------------------+-------+----------
 public | audit_log             | table | postgres
 public | employees             | table | postgres
 public | flyway_schema_history | table | postgres
(3 rows)
```

Look at Flyway's tracking table. This is how Flyway knows which migrations have already run.

```bash
psql -d flyway_lab -c "SELECT installed_rank, version, description, success FROM flyway_schema_history;"
```

Expected output (yours will differ):
```
 installed_rank | version |      description      | success
----------------+---------+-----------------------+---------
              1 | 1       | create employees      | t
              2 | 2       | add department column | t
              3 | 3       | create audit log      | t
(3 rows)
```

Exit the postgres user.

```bash
exit
```

---

## Part 3: Liquibase - Changelog Format and Changesets

Liquibase is an alternative to Flyway. It uses "changelogs" (XML, YAML, JSON, or SQL) instead of numbered files. Its key advantage is database-agnostic changesets.

### 3.1 Install Liquibase

```bash
curl -L -o /tmp/liquibase-4.25.1.tar.gz https://github.com/liquibase/liquibase/releases/download/v4.25.1/liquibase-4.25.1.tar.gz
```

```bash
sudo mkdir -p /opt/liquibase
```

```bash
sudo tar -xzf /tmp/liquibase-4.25.1.tar.gz -C /opt/liquibase/
```

```bash
sudo ln -s /opt/liquibase/liquibase /usr/local/bin/liquibase
```

Verify the install.

```bash
liquibase --version
```

### 3.2 Download the PostgreSQL JDBC Driver

Liquibase needs a JDBC driver to connect to PostgreSQL.

```bash
curl -L -o /opt/liquibase/lib/postgresql-42.7.1.jar https://jdbc.postgresql.org/download/postgresql-42.7.1.jar
```

### 3.3 Create a Liquibase Project

Switch to postgres user first.

```bash
sudo -iu postgres
```

Create a database.

```bash
createdb liquibase_lab
```

Exit postgres user.

```bash
exit
```

Create the project directory.

```bash
sudo mkdir -p /opt/pgsql/liquibase-project
```

### 3.4 Create the Liquibase Properties File

```bash
sudo vi /opt/pgsql/liquibase-project/liquibase.properties
```

```
changeLogFile=changelog-master.xml
url=jdbc:postgresql://localhost:5432/liquibase_lab
username=postgres
```

### 3.5 Create a Master Changelog

The master changelog includes other changelog files. This keeps things organized.

```bash
sudo vi /opt/pgsql/liquibase-project/changelog-master.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.25.xsd">

    <include file="changelog-001-employees.xml"
             relativeToChangelogFile="true"/>
    <include file="changelog-002-audit.xml"
             relativeToChangelogFile="true"/>

</databaseChangeLog>
```

### 3.6 Create Individual Changelogs

Create the first changelog.

```bash
sudo vi /opt/pgsql/liquibase-project/changelog-001-employees.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.25.xsd">

    <changeSet id="1" author="dba-team">
        <comment>Create employees table</comment>
        <createTable tableName="employees">
            <column name="id" type="SERIAL" autoIncrement="true">
                <constraints primaryKey="true"/>
            </column>
            <column name="name" type="VARCHAR(100)">
                <constraints nullable="false"/>
            </column>
            <column name="email" type="VARCHAR(255)">
                <constraints unique="true"/>
            </column>
            <column name="created_at" type="TIMESTAMP" defaultValueComputed="NOW()"/>
        </createTable>
    </changeSet>

    <changeSet id="2" author="dba-team">
        <comment>Add department column</comment>
        <addColumn tableName="employees">
            <column name="department" type="VARCHAR(50)"/>
        </addColumn>
        <createIndex tableName="employees" indexName="idx_emp_dept">
            <column name="department"/>
        </createIndex>
    </changeSet>

</databaseChangeLog>
```

Create the second changelog.

```bash
sudo vi /opt/pgsql/liquibase-project/changelog-002-audit.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.25.xsd">

    <changeSet id="3" author="dba-team">
        <comment>Create audit log table</comment>
        <createTable tableName="audit_log">
            <column name="id" type="BIGSERIAL" autoIncrement="true">
                <constraints primaryKey="true"/>
            </column>
            <column name="table_name" type="VARCHAR(100)">
                <constraints nullable="false"/>
            </column>
            <column name="operation" type="VARCHAR(10)">
                <constraints nullable="false"/>
            </column>
            <column name="old_data" type="JSONB"/>
            <column name="new_data" type="JSONB"/>
            <column name="changed_by" type="VARCHAR(100)" defaultValueComputed="current_user"/>
            <column name="changed_at" type="TIMESTAMP" defaultValueComputed="NOW()"/>
        </createTable>
    </changeSet>

    <changeSet id="4" author="dba-team">
        <comment>Add indexes to audit_log</comment>
        <createIndex tableName="audit_log" indexName="idx_audit_table">
            <column name="table_name"/>
        </createIndex>
        <createIndex tableName="audit_log" indexName="idx_audit_changed_at">
            <column name="changed_at"/>
        </createIndex>
    </changeSet>

</databaseChangeLog>
```

### 3.7 Run Liquibase Migrations

Change to the project directory first.

```bash
cd /opt/pgsql/liquibase-project
```

Run the update command.

```bash
liquibase update
```

Expected output (yours will differ):
```
Running Changeset: changelog-001-employees.xml::1::dba-team
Running Changeset: changelog-001-employees.xml::2::dba-team
Running Changeset: changelog-002-audit.xml::3::dba-team
Running Changeset: changelog-002-audit.xml::4::dba-team
Liquibase command 'update' was executed successfully.
```

### 3.8 Check Liquibase Status

```bash
liquibase status
```

Expected output (yours will differ):
```
4 changesets have already been applied
Liquibase command 'status' was executed successfully.
```

### 3.9 Generate a Rollback SQL Preview

One of Liquibase's strengths is rollback support. Preview what rollback would do.

```bash
liquibase rollbackCountSQL 1
```

This shows the SQL that would run to undo the last changeset, without actually executing it.

---

## Part 4: Comparison - Flyway vs Liquibase vs Sqitch

### Feature Matrix

| Feature | Flyway | Liquibase | Sqitch |
|---------|--------|-----------|--------|
| **Config format** | SQL files | XML/YAML/JSON/SQL | Pure SQL |
| **Tracking table** | flyway_schema_history | databasechangelog | sqitch metadata |
| **Rollback (free)** | Manual SQL only | Built-in | Built-in (deploy/revert) |
| **Database support** | 20+ databases | 50+ databases | 20+ databases |
| **Learning curve** | Low | Medium | Medium |
| **CI/CD integration** | Excellent | Excellent | Good |
| **Diff generation** | No | Yes (Pro) | No |
| **Repeatable migrations** | Yes (R__ prefix) | Yes | No |
| **Dependency tracking** | Sequential only | Sequential | DAG (dependency graph) |

### When to Use Each

**Choose Flyway when:**
- You want the simplest setup
- Your team prefers writing raw SQL
- You have a single database vendor
- You want fast onboarding for new team members

**Choose Liquibase when:**
- You support multiple database vendors
- You need built-in rollback in the free tier
- You want XML/YAML changelogs (some teams prefer this for code review)
- You need diff generation between environments

**Choose Sqitch when:**
- You want dependency-based ordering (not just sequential)
- You need revert scripts for every change
- You prefer a Unix-philosophy tool (small, composable)
- You are already comfortable with Git workflows

### 4.1 Install Sqitch (for reference)

```bash
sudo dnf install -y perl-App-Sqitch perl-DBD-Pg
```

Sqitch uses a plan file and deploy/revert/verify scripts:

```
sqitch/
  sqitch.plan          # Tracks migration order and dependencies
  deploy/
    001-employees.sql  # Forward migration
  revert/
    001-employees.sql  # Rollback migration
  verify/
    001-employees.sql  # Verification query
```

---

## Part 5: Version Control for Database Changes

### 5.1 Best Practices

**Rule 1: Never modify a migration that has been applied.**

Once a migration runs in any environment (dev, staging, production), treat it as immutable. Create a new migration to fix mistakes.

**Rule 2: Every migration must be idempotent when possible.**

Use guards like `IF NOT EXISTS` and `IF EXISTS`:

```sql
CREATE TABLE IF NOT EXISTS employees (...);
ALTER TABLE employees ADD COLUMN IF NOT EXISTS salary NUMERIC(10,2);
DROP INDEX IF EXISTS idx_old_name;
```

**Rule 3: Store migrations in the same repo as application code.**

```
my-app/
  src/
  tests/
  db/
    migrations/
      V1__initial_schema.sql
      V2__add_users.sql
      V3__add_audit_log.sql
    seeds/
      dev_data.sql
    flyway.conf
```

**Rule 4: Review migrations like code.**

Every migration should go through a pull request. Reviewers should check:
- Does it have a rollback strategy?
- Will it lock tables for too long?
- Does it handle existing data correctly?
- Is it idempotent?

**Rule 5: Test migrations against a copy of production.**

Never run a migration in production for the first time. Always test against a restored backup first.

### 5.2 Migration Naming Convention

Adopt a consistent naming scheme across your team:

```
V{YYYYMMDD}_{sequence}__{description}.sql
```

Examples:
- `V20260419_001__create_employees_table.sql`
- `V20260419_002__add_salary_column.sql`
- `V20260420_001__create_departments_table.sql`

The date prefix prevents version collisions when multiple developers create migrations on the same day. The sequence number handles ordering within a single day.

---

## Cleanup

Switch to postgres user.

```bash
sudo -iu postgres
```

Drop the test databases.

```bash
dropdb migration_lab
```

```bash
dropdb migration_lab_v2
```

```bash
dropdb flyway_lab
```

```bash
dropdb liquibase_lab
```

Exit postgres user.

```bash
exit
```

---

## Key Takeaways

1. `pg_dump --schema-only` gives you point-in-time schema snapshots you can diff and version
2. Flyway is the simplest migration tool - numbered SQL files with a tracking table
3. Liquibase offers more features (rollback, multi-format, diff) at the cost of complexity
4. Sqitch uses dependency graphs instead of sequential numbering
5. Never modify an applied migration - always create a new one
6. Store migrations in the same repository as your application code
7. Review database migrations with the same rigor as application code
