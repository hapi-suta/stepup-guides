# BUILD 01: Schema Migration Fundamentals

**Module 05: CI/CD for Database Changes**
**Estimated Time: 45-60 minutes**

---

## What You Will Learn

How to track and version database schema changes using Flyway - the same way you version application code with Git, but for DDL.

---

## The Problem: Untracked Schema Changes

If you have managed PostgreSQL across multiple environments, you have run into this scenario:

- You add a column to `dev` and forget to add it to `staging`.
- A colleague creates a table in production but does not document it.
- Nobody knows which environment has which schema version.

Think of it this way: before Git, developers emailed code changes to each other. That is what most DBA teams still do with DDL - they run manual scripts and hope everyone stays in sync.

**Schema migrations solve this problem.** They are version control for your DDL. Every change is a numbered file, applied in order, tracked in a history table.

---

## Step 1: Migration-Based vs State-Based Approaches

There are two schools of thought for managing schema changes:

### Migration-Based (Flyway, Liquibase, sqitch)

You write individual change scripts that are applied in sequence:

```
V1__create_users_table.sql      -- Creates the users table
V2__add_email_column.sql        -- Adds email to users
V3__create_orders_table.sql     -- Creates the orders table
```

**DBA Analogy:** This is like keeping a sequential log of every ALTER TABLE and CREATE TABLE you have ever run - similar to how PostgreSQL's WAL records every change in order.

### State-Based (Atlas declarative, Redgate)

You define the desired end state, and the tool generates the DDL to get there:

```
-- desired_schema.sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE
);
```

The tool compares the desired state against the current database and generates the diff.

**DBA Analogy:** This is like `pg_dump --schema-only` of your ideal database - then diffing it against what actually exists.

### Which to Choose?

| Factor | Migration-Based | State-Based |
|--------|----------------|-------------|
| Control over DDL | Full - you write every statement | Partial - tool generates DDL |
| Rollback | Manual (write undo scripts) | Auto-generated |
| Team adoption | Easy - just write SQL files | Steeper learning curve |
| Complex migrations (data transforms) | Natural fit | Awkward |

For this module, we start with **migration-based** using Flyway because it is the most intuitive for DBAs - you are already writing SQL, you just need to number your files.

---

## Step 2: Install Flyway on Mac

**On your Mac terminal:**

```bash
brew install flyway
```

Expected output (yours will differ):
```
==> Downloading https://formulae.brew.sh/api/formula.jws
==> Fetching flyway
==> Downloading https://ghcr.io/v2/homebrew/core/flyway/blobs/sha256:...
==> Pouring flyway--10.x.x.arm64_sonoma.bottle.tar.gz
==> Summary
  /opt/homebrew/Cellar/flyway/10.x.x: 55 files, 85.2MB
```

Verify the installation:

```bash
flyway --version
```

Expected output (yours will differ):
```
Flyway Community Edition 10.x.x by Redgate
```

---

## Step 3: Understand Flyway Naming Conventions

Flyway relies on a strict file naming convention to determine the order and type of each migration.

### Versioned Migrations

Format: `V{version}__{description}.sql`

- `V` - prefix indicating a versioned migration
- `{version}` - a version number (1, 2, 3 or 1.1, 1.2, 2.0)
- `__` - two underscores (this is not a typo - Flyway requires exactly two)
- `{description}` - human-readable description using underscores for spaces
- `.sql` - file extension

Examples:
```
V1__create_users_table.sql
V2__add_email_to_users.sql
V3__create_orders_table.sql
V1.1__add_index_on_email.sql
```

### Repeatable Migrations

Format: `R__{description}.sql`

- Applied every time their checksum changes (the file content changes)
- Always run after all versioned migrations
- Good for views, functions, and stored procedures that you redefine entirely each time

Examples:
```
R__create_reporting_views.sql
R__update_helper_functions.sql
```

### Undo Migrations

Format: `U{version}__{description}.sql`

- Reverses the corresponding versioned migration
- Only available in Flyway Teams/Enterprise (not Community)
- We will discuss rollback strategies that work without paid undo support

Examples:
```
U1__undo_create_users_table.sql
U2__undo_add_email_to_users.sql
```

---

## Step 4: Set Up a Project Directory

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/flyway-demo/sql
cd ~/dba-labs/flyway-demo
```

Create the Flyway configuration file:

```bash
vi flyway.conf
```

Add the following content:

```properties
flyway.url=jdbc:postgresql://localhost:5432/flyway_lab
flyway.user=postgres
flyway.password=postgres
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
```

What each setting means:

- `flyway.url` - JDBC connection string to your PostgreSQL database. If your local PostgreSQL runs on a different port, adjust accordingly.
- `flyway.user` - The database user. Using `postgres` for this lab.
- `flyway.password` - The password. In production, you would use environment variables instead.
- `flyway.locations` - Where Flyway looks for migration SQL files. `filesystem:./sql` means the `sql/` subdirectory.
- `flyway.cleanDisabled=false` - Allows `flyway clean` to drop all objects. In production, you would set this to `true`.

---

## Step 5: Create the Lab Database

**On your Mac terminal (still in ~/dba-labs/flyway-demo):**

```bash
psql -U postgres -c "CREATE DATABASE flyway_lab;"
```

Expected output:
```
CREATE DATABASE
```

If you use a different superuser or connection method, adjust accordingly. The key requirement is that the `flyway_lab` database exists and the user in `flyway.conf` can connect to it.

---

## Step 6: Write Your First Five Migrations

Create five migration files that build a small e-commerce schema.

**Migration 1 - Create the users table:**

```bash
vi sql/V1__create_users_table.sql
```

```sql
-- V1: Create the core users table
CREATE TABLE users (
    user_id     SERIAL PRIMARY KEY,
    username    VARCHAR(50) NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE users IS 'Core user accounts';
```

**Migration 2 - Add email column to users:**

```bash
vi sql/V2__add_email_to_users.sql
```

```sql
-- V2: Add email to users (should have been in V1, but this is real life)
ALTER TABLE users ADD COLUMN email VARCHAR(255) UNIQUE;
```

**Migration 3 - Create the products table:**

```bash
vi sql/V3__create_products_table.sql
```

```sql
-- V3: Products catalog
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    name         VARCHAR(200) NOT NULL,
    price        NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_name ON products (name);
```

**Migration 4 - Create the orders table with foreign keys:**

```bash
vi sql/V4__create_orders_table.sql
```

```sql
-- V4: Orders table - references users and products
CREATE TABLE orders (
    order_id     SERIAL PRIMARY KEY,
    user_id      INTEGER NOT NULL REFERENCES users(user_id),
    product_id   INTEGER NOT NULL REFERENCES products(product_id),
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    total_price  NUMERIC(10,2) NOT NULL,
    ordered_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_orders_product_id ON orders (product_id);
CREATE INDEX idx_orders_ordered_at ON orders (ordered_at);
```

**Migration 5 - Add a status column and audit trigger:**

```bash
vi sql/V5__add_order_status_and_audit.sql
```

```sql
-- V5: Add order status and a simple audit log
ALTER TABLE orders ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending';

CREATE TABLE order_audit (
    audit_id    SERIAL PRIMARY KEY,
    order_id    INTEGER NOT NULL,
    old_status  VARCHAR(20),
    new_status  VARCHAR(20),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_audit (order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_status_audit
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION log_order_status_change();
```

---

## Step 7: Run Flyway Info (Dry Run Check)

Before applying anything, check what Flyway sees:

**On your Mac terminal, in ~/dba-labs/flyway-demo:**

```bash
flyway -configFiles=flyway.conf info
```

Expected output (yours will differ):
```
Schema version: << Empty Schema >>
+-----------+---------+------------------------------+------+--------------+---------+----------+
| Category  | Version | Description                  | Type | Installed On | State   | Undoable |
+-----------+---------+------------------------------+------+--------------+---------+----------+
| Versioned | 1       | create users table           | SQL  |              | Pending |          |
| Versioned | 2       | add email to users           | SQL  |              | Pending |          |
| Versioned | 3       | create products table        | SQL  |              | Pending |          |
| Versioned | 4       | create orders table          | SQL  |              | Pending |          |
| Versioned | 5       | add order status and audit   | SQL  |              | Pending |          |
+-----------+---------+------------------------------+------+--------------+---------+----------+
```

All five migrations show as `Pending` - Flyway found them but has not applied them yet.

---

## Step 8: Run Flyway Migrate

Apply all pending migrations:

```bash
flyway -configFiles=flyway.conf migrate
```

Expected output (yours will differ):
```
Current version of schema "public": << Empty Schema >>
Migrating schema "public" to version 1 - create users table
Migrating schema "public" to version 2 - add email to users
Migrating schema "public" to version 3 - create products table
Migrating schema "public" to version 4 - create orders table
Migrating schema "public" to version 5 - add order status and audit
Successfully applied 5 migrations to schema "public" (execution time 00:00.089s)
```

Run `info` again to see the updated state:

```bash
flyway -configFiles=flyway.conf info
```

Expected output (yours will differ):
```
Schema version: 5
+-----------+---------+------------------------------+------+---------------------+---------+----------+
| Category  | Version | Description                  | Type | Installed On        | State   | Undoable |
+-----------+---------+------------------------------+------+---------------------+---------+----------+
| Versioned | 1       | create users table           | SQL  | 2026-06-09 10:00:00 | Success |          |
| Versioned | 2       | add email to users           | SQL  | 2026-06-09 10:00:00 | Success |          |
| Versioned | 3       | create products table        | SQL  | 2026-06-09 10:00:00 | Success |          |
| Versioned | 4       | create orders table          | SQL  | 2026-06-09 10:00:00 | Success |          |
| Versioned | 5       | add order status and audit   | SQL  | 2026-06-09 10:00:00 | Success |          |
+-----------+---------+------------------------------+------+---------------------+---------+----------+
```

---

## Step 9: Explore the flyway_schema_history Table

Flyway tracks every migration it has applied in a metadata table called `flyway_schema_history`. This is the core of how Flyway knows what has been applied and what is pending.

**DBA Analogy:** Think of this as a changelog - like `pg_stat_activity` for schema changes. It records who changed what, when, and whether it succeeded.

```bash
psql -U postgres -d flyway_lab -c "SELECT installed_rank, version, description, type, checksum, installed_on, success FROM flyway_schema_history ORDER BY installed_rank;"
```

Expected output (yours will differ):
```
 installed_rank | version |         description          |  type   |  checksum   |     installed_on        | success
----------------+---------+------------------------------+---------+-------------+-------------------------+---------
              1 | 1       | create users table           | SQL     |  -839201456 | 2026-06-09 10:00:00.123 | t
              2 | 2       | add email to users           | SQL     |  1029384756 | 2026-06-09 10:00:00.145 | t
              3 | 3       | create products table        | SQL     | -1234567890 | 2026-06-09 10:00:00.167 | t
              4 | 4       | create orders table          | SQL     |   987654321 | 2026-06-09 10:00:00.189 | t
              5 | 5       | add order status and audit   | SQL     |  -567890123 | 2026-06-09 10:00:00.211 | t
```

Key columns:

- **installed_rank** - The order in which migrations were applied
- **version** - The migration version number
- **checksum** - A hash of the file contents. If you modify a migration file after it has been applied, `flyway validate` will catch the mismatch.
- **success** - Whether the migration completed without errors

---

## Step 10: Flyway Validate

Validate checks that your migration files match what was applied to the database. This catches a common mistake: someone edits a migration file after it has already been applied.

```bash
flyway -configFiles=flyway.conf validate
```

Expected output (yours will differ):
```
Successfully validated 5 migrations (execution time 00:00.025s)
```

Now try breaking it intentionally. Edit `sql/V1__create_users_table.sql` and add a comment:

```bash
echo "-- I changed this file after it was applied" >> ~/dba-labs/flyway-demo/sql/V1__create_users_table.sql
```

Run validate again:

```bash
flyway -configFiles=flyway.conf validate
```

Expected output (yours will differ):
```
ERROR: Validate failed: Migrations have failed validation
Migration checksum mismatch for migration version 1
-> Applied to database : -839201456
-> Resolved locally    : 1122334455
```

Flyway detected that the file changed. Undo your change before proceeding:

```bash
vi sql/V1__create_users_table.sql
```

Remove the comment line you added, save, and exit.

---

## Step 11: Repeatable Migrations

Repeatable migrations are re-applied every time their content changes. They are ideal for database objects you redefine entirely each time - views, functions, and materialized view refreshes.

**DBA Analogy:** Think of `CREATE OR REPLACE FUNCTION` - you always redefine the entire function, not patch it incrementally. Repeatable migrations work the same way.

Create a repeatable migration for a reporting view:

```bash
vi sql/R__reporting_views.sql
```

```sql
-- Repeatable: reporting views (re-applied when this file changes)
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    u.username,
    u.email,
    COUNT(o.order_id)           AS total_orders,
    COALESCE(SUM(o.total_price), 0) AS total_spent
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.username, u.email;
```

Apply it:

```bash
flyway -configFiles=flyway.conf migrate
```

Expected output (yours will differ):
```
Current version of schema "public": 5
Migrating schema "public" with repeatable migration reporting views
Successfully applied 1 migration to schema "public" (execution time 00:00.032s)
```

Now modify the view - add a column:

```bash
vi sql/R__reporting_views.sql
```

Update the SQL to add `MAX(o.ordered_at) AS last_order_date` to the SELECT list. Save and run migrate again:

```bash
flyway -configFiles=flyway.conf migrate
```

Flyway detects the checksum changed and re-applies the repeatable migration. The old view is replaced with the new definition.

---

## Step 12: Undo Migrations (Concept)

Undo migrations reverse the effect of a versioned migration. In Flyway Community Edition, undo is not available - this is a Teams/Enterprise feature. However, understanding the concept matters.

Format: `U{version}__{description}.sql`

Example:

```sql
-- U2__undo_add_email_to_users.sql
ALTER TABLE users DROP COLUMN IF EXISTS email;
```

The undo for version 2 drops the column that version 2 added.

**In practice, most teams use forward-only migrations instead of undo.** If migration V5 causes a problem, you write V6 to fix or revert it. This is safer because:

1. Undo migrations can lose data (dropping a column destroys its data)
2. Forward-only keeps a clear audit trail
3. In production, you rarely want to "undo" - you want to "fix forward"

We will cover rollback strategies in detail in BUILD 03 (Zero-Downtime Migrations).

---

## Step 13: Running Flyway Idempotently

Run migrate again with no new files:

```bash
flyway -configFiles=flyway.conf migrate
```

Expected output (yours will differ):
```
Current version of schema "public": 5
Schema "public" is up to date. No migration necessary.
```

**DBA Analogy:** This is like `CREATE TABLE IF NOT EXISTS` - running it again changes nothing. Flyway is idempotent. You can safely run `flyway migrate` in a CI/CD pipeline on every deployment, and it will only apply what is new.

---

## Step 14: Clean Up (Optional)

If you want to start fresh, `flyway clean` drops all objects in the schema:

```bash
flyway -configFiles=flyway.conf clean
```

Expected output (yours will differ):
```
Successfully cleaned schema "public" (execution time 00:00.045s)
```

**WARNING:** `flyway clean` drops everything - tables, views, functions, data. Never run this against production. The `flyway.cleanDisabled=true` setting prevents accidental execution.

After cleaning, you can re-apply all migrations with `flyway migrate` and they will run from scratch.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Schema migrations | Version control for DDL - numbered SQL files applied in order |
| Migration-based vs state-based | Migration-based gives you full control over every DDL statement |
| Flyway naming | `V{version}__{description}.sql` with exactly two underscores |
| flyway migrate | Applies all pending migrations in version order |
| flyway info | Shows the status of all migrations (pending, success, failed) |
| flyway validate | Ensures migration files have not been modified after being applied |
| flyway_schema_history | Metadata table that tracks every applied migration |
| Repeatable migrations | `R__` prefix - re-applied when file content changes, good for views and functions |
| Undo migrations | `U{version}__` prefix - reverse a migration (Teams/Enterprise only) |
| Idempotency | Running migrate twice changes nothing - safe for automation |
| flyway.conf | Configuration file for connection details and migration locations |

---

**Next:** BUILD 02 - GitHub Actions for Database CI/CD - automate these migrations so they run on every code push.
