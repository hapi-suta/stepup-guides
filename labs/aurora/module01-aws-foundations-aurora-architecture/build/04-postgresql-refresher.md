# Module 01 - AWS Foundations and Aurora Architecture
## Guide 04: PostgreSQL Refresher

**Objective:** Install the PostgreSQL client, connect to a practice database, and run through the essential SQL operations and data types you will use daily when managing Aurora PostgreSQL - so you are ready to hit the ground running in Module 02.
**Time:** 45 minutes
**Prerequisites:** A terminal on your local machine. No AWS resources needed.
**Infrastructure:** You will use either a local PostgreSQL instance (via Docker) or a free online PostgreSQL sandbox. No cost.

---

## 1. Install the psql Client

`psql` is the official PostgreSQL command-line client. You will use it throughout this training track to connect to Aurora clusters, run queries, inspect performance, and troubleshoot issues.

You do not need to install a full PostgreSQL server - just the client tools.

### On macOS

**In your terminal** (local machine):

```bash
brew install libpq
```

- `brew` - the Homebrew package manager for macOS
- `libpq` - the PostgreSQL client library, which includes the `psql` command-line tool

**In your terminal** (local machine):

```bash
brew link --force libpq
```

- `link --force` - creates symlinks so `psql` is available directly from your terminal without typing the full path

Verify it installed:

**In your terminal** (local machine):

```bash
psql --version
```

Expected output (yours will differ):
```
psql (PostgreSQL) 16.3
```

### On Linux (Debian/Ubuntu)

**In your terminal** (local machine):

```bash
sudo apt update
```

**In your terminal** (local machine):

```bash
sudo apt install -y postgresql-client
```

- `apt install` - installs a package from the Ubuntu/Debian repositories
- `-y` - automatically answers "yes" to the confirmation prompt
- `postgresql-client` - the psql client tools without the full server

Verify it installed:

**In your terminal** (local machine):

```bash
psql --version
```

### On Windows

**In your browser:**

1. Download the PostgreSQL installer from https://www.postgresql.org/download/windows/
2. Run the installer. When it asks which components to install, you can uncheck "PostgreSQL Server" and "pgAdmin" if you only want the command-line tools. Keep "Command Line Tools" checked.
3. Complete the installer.
4. Open a new PowerShell window and run `psql --version` to verify.

---

## 2. Get a Practice Database

You need a PostgreSQL instance to practice on. Here are two options - pick whichever is easiest for you.

### Option A: Docker (Recommended)

If you have Docker installed, this is the fastest way to get a local PostgreSQL instance.

**In your terminal** (local machine):

```bash
docker run --name pg-practice -e POSTGRES_PASSWORD=practice123 -p 5432:5432 -d postgres:16
```

- `docker run` - creates and starts a new container
- `--name pg-practice` - names the container so you can reference it later
- `-e POSTGRES_PASSWORD=practice123` - sets the postgres user's password via an environment variable
- `-p 5432:5432` - maps port 5432 on your machine to port 5432 in the container
- `-d` - runs the container in the background (detached mode)
- `postgres:16` - uses the official PostgreSQL 16 image from Docker Hub

Expected output (yours will differ):
```
Unable to find image 'postgres:16' locally
16: Pulling from library/postgres
...
Status: Downloaded newer image for postgres:16
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9
```

Now connect to it:

**In your terminal** (local machine):

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```

- `-h 127.0.0.1` - connect to localhost (your machine)
- `-p 5432` - the port PostgreSQL is listening on
- `-U postgres` - connect as the postgres superuser
- `-d postgres` - connect to the default postgres database

When prompted for a password, enter `practice123`.

Expected output (yours will differ):
```
Password for user postgres:
psql (16.3)
Type "help" for help.

postgres=#
```

The `postgres=#` prompt means you are connected. The `#` indicates superuser privileges.

### Option B: Free Online Sandbox

If you do not want to install Docker, use a free online PostgreSQL sandbox:

- **SQLFiddle:** https://sqlfiddle.com (select PostgreSQL)
- **DB Fiddle:** https://www.db-fiddle.com (select PostgreSQL 16)

These sandboxes let you run SQL directly in your browser. The tradeoff is that you cannot use `psql` meta-commands like `\dt` or `\conninfo` - those only work in the psql client. For this guide, the SQL commands will work in either environment.

---

## 3. Basic SQL: CREATE TABLE

Let's create a practice database and table. If you are using Docker, run these commands in your psql session.

**In psql** (connected to PostgreSQL):

```sql
CREATE DATABASE aurora_practice;
```

This creates a new empty database called `aurora_practice`.

**In psql** (connected to PostgreSQL):

```
\c aurora_practice
```

This switches your connection to the new database.

Expected output (yours will differ):
```
You are now connected to database "aurora_practice" as user "postgres".
```

Now create a table:

**In psql** (connected to aurora_practice):

```sql
CREATE TABLE IF NOT EXISTS employees (
    id          SERIAL PRIMARY KEY,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(255) UNIQUE,
    department  VARCHAR(50),
    salary      INTEGER,
    is_active   BOOLEAN DEFAULT true,
    hired_at    TIMESTAMP DEFAULT NOW()
);
```

Let's break down each column and its data type:

- `id SERIAL PRIMARY KEY` - `SERIAL` is an auto-incrementing integer. `PRIMARY KEY` means this column uniquely identifies each row and cannot be NULL
- `first_name VARCHAR(100) NOT NULL` - variable-length text up to 100 characters. `NOT NULL` means this column must have a value
- `last_name VARCHAR(100) NOT NULL` - same as above
- `email VARCHAR(255) UNIQUE` - up to 255 characters. `UNIQUE` means no two rows can have the same email
- `department VARCHAR(50)` - optional text field for the department name
- `salary INTEGER` - a whole number (no decimals). PostgreSQL `INTEGER` stores values from -2,147,483,648 to 2,147,483,647
- `is_active BOOLEAN DEFAULT true` - a true/false value. `DEFAULT true` means new rows get `true` if you do not specify a value
- `hired_at TIMESTAMP DEFAULT NOW()` - a date and time value. `DEFAULT NOW()` automatically sets this to the current time when a row is inserted

---

## 4. Data Types You Will Use Most

Here are the PostgreSQL data types you will encounter most often when managing Aurora databases:

| Data Type | What It Stores | Example |
|-----------|---------------|---------|
| `INTEGER` | Whole numbers | `42`, `-100`, `0` |
| `BIGINT` | Large whole numbers | `9223372036854775807` |
| `SERIAL` | Auto-incrementing integer | 1, 2, 3, 4... |
| `VARCHAR(n)` | Variable-length text, up to n characters | `'Alice'`, `'bob@example.com'` |
| `TEXT` | Variable-length text, unlimited | Long descriptions, JSON strings |
| `TIMESTAMP` | Date and time | `'2026-06-09 14:30:00'` |
| `TIMESTAMPTZ` | Date and time with timezone | `'2026-06-09 14:30:00+00'` |
| `BOOLEAN` | True or false | `true`, `false` |
| `NUMERIC(p,s)` | Exact decimal numbers | `99.99`, `1234.56` |
| `UUID` | Universally unique identifier | `'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'` |
| `JSONB` | Binary JSON data | `'{"key": "value"}'` |

> **Tip:** Use `TIMESTAMPTZ` (timestamp with timezone) instead of plain `TIMESTAMP` for any data that crosses timezones. Aurora stores everything in UTC, and `TIMESTAMPTZ` handles conversions automatically.

---

## 5. INSERT, SELECT, UPDATE, DELETE

### Insert data

**In psql** (connected to aurora_practice):

```sql
INSERT INTO employees (first_name, last_name, email, department, salary)
VALUES ('Amara', 'Diallo', 'amara@example.com', 'Engineering', 95000);
```

**In psql** (connected to aurora_practice):

```sql
INSERT INTO employees (first_name, last_name, email, department, salary)
VALUES ('Kofi', 'Asante', 'kofi@example.com', 'Engineering', 88000);
```

**In psql** (connected to aurora_practice):

```sql
INSERT INTO employees (first_name, last_name, email, department, salary)
VALUES ('Nia', 'Okafor', 'nia@example.com', 'Marketing', 72000);
```

**In psql** (connected to aurora_practice):

```sql
INSERT INTO employees (first_name, last_name, email, department, salary)
VALUES ('Tunde', 'Bakare', 'tunde@example.com', 'Engineering', 105000);
```

**In psql** (connected to aurora_practice):

```sql
INSERT INTO employees (first_name, last_name, email, department, salary)
VALUES ('Fatima', 'Hassan', 'fatima@example.com', 'Marketing', 78000);
```

### Select all data

**In psql** (connected to aurora_practice):

```sql
SELECT * FROM employees;
```

Expected output (yours will differ):
```
 id | first_name | last_name |       email        | department  | salary | is_active |         hired_at
----+------------+-----------+--------------------+-------------+--------+-----------+----------------------------
  1 | Amara      | Diallo    | amara@example.com  | Engineering |  95000 | t         | 2026-06-09 10:15:23.123456
  2 | Kofi       | Asante    | kofi@example.com   | Engineering |  88000 | t         | 2026-06-09 10:15:24.234567
  3 | Nia        | Okafor    | nia@example.com    | Marketing   |  72000 | t         | 2026-06-09 10:15:25.345678
  4 | Tunde      | Bakare    | tunde@example.com  | Engineering | 105000 | t         | 2026-06-09 10:15:26.456789
  5 | Fatima     | Hassan    | fatima@example.com | Marketing   |  78000 | t         | 2026-06-09 10:15:27.567890
(5 rows)
```

### Select with WHERE, ORDER BY, LIMIT

**In psql** (connected to aurora_practice):

```sql
SELECT first_name, last_name, salary
FROM employees
WHERE department = 'Engineering'
ORDER BY salary DESC
LIMIT 3;
```

- `WHERE department = 'Engineering'` - filters to only Engineering rows
- `ORDER BY salary DESC` - sorts by salary, highest first. `DESC` means descending. `ASC` (ascending) is the default
- `LIMIT 3` - returns only the first 3 rows

Expected output (yours will differ):
```
 first_name | last_name | salary
------------+-----------+--------
 Tunde      | Bakare    | 105000
 Amara      | Diallo    |  95000
 Kofi       | Asante    |  88000
(3 rows)
```

### Update data

**In psql** (connected to aurora_practice):

```sql
UPDATE employees
SET salary = 92000
WHERE email = 'kofi@example.com';
```

Always include a `WHERE` clause in UPDATE statements. Without one, every row in the table gets updated - a common and painful mistake.

Verify the update:

**In psql** (connected to aurora_practice):

```sql
SELECT first_name, salary FROM employees WHERE email = 'kofi@example.com';
```

Expected output (yours will differ):
```
 first_name | salary
------------+--------
 Kofi       |  92000
(1 row)
```

### Delete data

**In psql** (connected to aurora_practice):

```sql
DELETE FROM employees
WHERE email = 'fatima@example.com';
```

Always include a `WHERE` clause in DELETE statements. Without one, every row is deleted.

Verify the delete:

**In psql** (connected to aurora_practice):

```sql
SELECT count(*) FROM employees;
```

Expected output (yours will differ):
```
 count
-------
     4
(1 row)
```

---

## 6. Primary Keys and Foreign Keys

### Primary Keys

A primary key uniquely identifies each row in a table. No two rows can have the same primary key value, and it cannot be NULL. You already created one with `id SERIAL PRIMARY KEY` in the employees table.

### Foreign Keys

A foreign key creates a relationship between two tables. It ensures that a value in one table must exist in another table.

**In psql** (connected to aurora_practice):

```sql
CREATE TABLE IF NOT EXISTS projects (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    lead_id     INTEGER REFERENCES employees(id),
    budget      INTEGER,
    started_at  TIMESTAMP DEFAULT NOW()
);
```

- `lead_id INTEGER REFERENCES employees(id)` - this is the foreign key. It says: the value in `lead_id` must be an `id` that exists in the `employees` table. If you try to insert a `lead_id` of 999 and no employee has `id = 999`, PostgreSQL will reject the insert

**In psql** (connected to aurora_practice):

```sql
INSERT INTO projects (name, lead_id, budget)
VALUES ('Aurora Migration', 1, 50000);
```

**In psql** (connected to aurora_practice):

```sql
INSERT INTO projects (name, lead_id, budget)
VALUES ('Dashboard Redesign', 3, 30000);
```

---

## 7. Basic JOINs

JOINs combine data from two or more tables based on a related column.

### INNER JOIN

An INNER JOIN returns only rows that have matching values in both tables.

**In psql** (connected to aurora_practice):

```sql
SELECT
    p.name AS project_name,
    e.first_name,
    e.last_name,
    p.budget
FROM projects p
INNER JOIN employees e ON p.lead_id = e.id;
```

- `FROM projects p` - the `p` is an alias (shortcut) for `projects`, so you can write `p.name` instead of `projects.name`
- `INNER JOIN employees e ON p.lead_id = e.id` - matches rows where the project's `lead_id` equals the employee's `id`
- Only projects with a valid `lead_id` that matches an employee appear in the result

Expected output (yours will differ):
```
    project_name    | first_name | last_name | budget
--------------------+------------+-----------+--------
 Aurora Migration   | Amara      | Diallo    |  50000
 Dashboard Redesign | Nia        | Okafor    |  30000
(2 rows)
```

### LEFT JOIN

A LEFT JOIN returns all rows from the left table, plus matching rows from the right table. If there is no match, the right side columns show NULL.

**In psql** (connected to aurora_practice):

```sql
SELECT
    e.first_name,
    e.last_name,
    p.name AS project_name
FROM employees e
LEFT JOIN projects p ON e.id = p.lead_id;
```

Expected output (yours will differ):
```
 first_name | last_name | project_name
------------+-----------+--------------------
 Amara      | Diallo    | Aurora Migration
 Nia        | Okafor    | Dashboard Redesign
 Kofi       | Asante    | (null)
 Tunde      | Bakare    | (null)
(4 rows)
```

Notice that Kofi and Tunde appear even though they do not lead any project. Their `project_name` is NULL. An INNER JOIN would have excluded them entirely.

---

## 8. CREATE INDEX Basics

Indexes make queries faster by letting PostgreSQL look up rows without scanning the entire table. Think of an index like the index at the back of a textbook - instead of reading every page to find a topic, you look it up in the index and go directly to the right page.

**In psql** (connected to aurora_practice):

```sql
CREATE INDEX idx_employees_department ON employees (department);
```

- `CREATE INDEX` - builds an index on a column
- `idx_employees_department` - the name of the index. Use a naming convention like `idx_{table}_{column}` so you can identify indexes later
- `ON employees (department)` - builds the index on the `department` column of the `employees` table

After creating this index, queries that filter by `department` (like `WHERE department = 'Engineering'`) will be faster, especially on large tables.

**In psql** (connected to aurora_practice):

```sql
CREATE INDEX idx_employees_email ON employees (email);
```

Verify your indexes exist:

**In psql** (connected to aurora_practice):

```
\di
```

- `\di` - lists all indexes in the current database

Expected output (yours will differ):
```
                              List of relations
 Schema |           Name            | Type  |  Owner   |   Table
--------+---------------------------+-------+----------+-----------
 public | employees_email_key       | index | postgres | employees
 public | employees_pkey            | index | postgres | employees
 public | idx_employees_department  | index | postgres | employees
 public | idx_employees_email       | index | postgres | employees
 public | projects_pkey             | index | postgres | projects
(5 rows)
```

Notice that `employees_pkey` and `employees_email_key` were created automatically - PostgreSQL creates indexes for PRIMARY KEY and UNIQUE constraints.

> **Heads up:** You will use `pg_stat_statements` in later modules to identify slow queries that need indexes. It is a PostgreSQL extension that tracks query performance statistics. Aurora supports it out of the box - you just need to enable it in your parameter group. More on this in Module 03.

---

## 9. Clean Up

If you used Docker, clean up your practice container when you are done:

**In psql** (connected to aurora_practice):

```
\q
```

This exits psql.

**In your terminal** (local machine):

```bash
docker stop pg-practice
```

- `docker stop` - gracefully stops the running container

**In your terminal** (local machine):

```bash
docker rm pg-practice
```

- `docker rm` - removes the stopped container and frees up the container name

If you want to practice again later, just run the `docker run` command from Section 2 again.

---

## Summary

- `psql` is the PostgreSQL command-line client. Install it with `brew install libpq` on Mac or `apt install postgresql-client` on Linux.
- Core SQL operations: `CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`. Always use `WHERE` with UPDATE and DELETE.
- Key data types: `INTEGER`, `VARCHAR`, `TEXT`, `TIMESTAMP`, `BOOLEAN`, `SERIAL`. Use `TIMESTAMPTZ` for timezone-aware timestamps.
- Primary keys uniquely identify rows. Foreign keys enforce relationships between tables.
- `INNER JOIN` returns only matching rows. `LEFT JOIN` returns all rows from the left table plus matches from the right.
- `CREATE INDEX` speeds up queries on specific columns. PostgreSQL auto-creates indexes for PRIMARY KEY and UNIQUE constraints.
- `pg_stat_statements` tracks query performance - you will enable and use it on Aurora in Module 03.
- Everything you practiced here works identically on Aurora PostgreSQL. The SQL is the same - only the infrastructure underneath is different.

**Next:** [Guide 05 - Cost Awareness](./05-cost-awareness.md)
