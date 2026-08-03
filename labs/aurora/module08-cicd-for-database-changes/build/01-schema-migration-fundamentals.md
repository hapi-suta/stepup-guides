# BUILD 01: Schema Migration Fundamentals

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster
**Estimated Time:** 45-60 minutes

---

## What You Will Learn

How to track and version database schema changes using migration files - the same way you version application code with Git, but for DDL. By the end, you will have created, applied, validated, and inspected migration files using Flyway.

---

## Prerequisites

- Aurora PostgreSQL cluster (`devops-lab-cluster`) running and accessible
- `psql` installed on your Mac
- Terminal access

---

## The Problem: Untracked Schema Changes

If you have managed databases across multiple environments, you have seen this happen:

- A column gets added to dev but not staging
- Someone creates a table in production without documenting it
- Nobody knows which environment has which schema version

Schema migrations fix this. They are version control for your DDL. Every change is a numbered file, applied in order, tracked in a history table.

---

## Step 1: Understand Migration-Based vs State-Based

There are two approaches to managing schema changes.

### Migration-Based (Flyway, Liquibase)

You write individual change scripts applied in sequence:

```
V1__create_users_table.sql
V2__add_email_column.sql
V3__create_orders_table.sql
```

You control every DDL statement. The tool applies them in order and tracks what has been applied.

### State-Based (Atlas)

You define the desired end state, and the tool generates the DDL:

```sql
-- You define: "users table should have id, name, email"
-- Tool generates: ALTER TABLE users ADD COLUMN email TEXT;
```

### Which to Choose?

For this module, we use **migration-based with Flyway** because it is the most intuitive for DBAs. You are already writing SQL - you just need to number your files.

---

## Step 2: Install Flyway

**On your Mac terminal:**

```bash
brew install flyway
```

Expected output (yours will differ):
```
==> Downloading https://formulae.brew.sh/api/formula.jws
==> Fetching flyway
==> Pouring flyway--10.x.x.arm64_sonoma.bottle.tar.gz
==> Summary
  /opt/homebrew/Cellar/flyway/10.x.x: 55 files, 85.2MB
```

Verify the installation:

```bash
flyway --version
```

- `--version` - prints the installed Flyway version and exits.

Expected output (yours will differ):
```
Flyway Community Edition 10.x.x by Redgate
```

---

## Step 3: Understand Flyway Naming Conventions

Flyway uses a strict file naming convention to determine the order and type of each migration.

### Versioned Migrations

Format: `V{version}__{description}.sql`

- `V` - prefix for a versioned migration (applied once, in order)
- `{version}` - version number (1, 2, 3 or 1.1, 1.2, 2.0)
- `__` - exactly two underscores (Flyway requires this separator)
- `{description}` - human-readable name using underscores for spaces
- `.sql` - file extension

Examples:

```
V1__create_users_table.sql
V2__add_email_to_users.sql
V3__create_orders_table.sql
```

### Repeatable Migrations

Format: `R__{description}.sql`

- Applied every time their content changes (checksum changes)
- Always run after all versioned migrations
- Good for views, functions, and stored procedures that you redefine entirely

Examples:

```
R__create_reporting_views.sql
R__update_helper_functions.sql
```

### Undo Migrations

Format: `U{version}__{description}.sql`

- Reverses the corresponding versioned migration
- Only available in Flyway Teams/Enterprise (not Community)
- We will cover rollback strategies that work without paid undo support

---

## Step 4: Set Up the Project Directory

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/flyway-aurora/sql
```

This creates two directories:
- `~/dba-labs/flyway-aurora/` - the project root
- `~/dba-labs/flyway-aurora/sql/` - where migration files go

Move into the project directory:

```bash
cd ~/dba-labs/flyway-aurora
```

Create the Flyway configuration file:

```bash
vi flyway.conf
```

Add the following content. Replace `YOUR_AURORA_ENDPOINT` with your actual Aurora writer endpoint:

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/flyway_lab
flyway.user=postgres
flyway.password=YOUR_PASSWORD
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
```

What each setting means:

- `flyway.url` - JDBC connection string to your Aurora PostgreSQL cluster. Use the writer endpoint.
- `flyway.user` - The database user Flyway connects as.
- `flyway.password` - The password. In production, you would use environment variables instead of hardcoding.
- `flyway.locations` - Where Flyway looks for migration SQL files. `filesystem:./sql` means the `sql/` subdirectory relative to where you run the command.
- `flyway.cleanDisabled=false` - Allows `flyway clean` to drop all objects. In production, set this to `true` to prevent accidental drops.

---

## Step 5: Create the Lab Database

**On your Mac terminal:**

Connect to your Aurora cluster and create the lab database:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE flyway_lab;"
```

- `-h` - the hostname of your Aurora writer endpoint.
- `-U postgres` - connect as the postgres user.
- `-c` - run a single SQL command and exit.

Expected output:
```
CREATE DATABASE
```

---

## Step 6: Write Your First Five Migrations

Create five migration files that build a small e-commerce schema.

**Migration 1 - Create the users table.**

**On your Mac terminal, in ~/dba-labs/flyway-aurora:**

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

**Migration 2 - Add email column to users.**

```bash
vi sql/V2__add_email_to_users.sql
```

```sql
-- V2: Add email to users
ALTER TABLE users ADD COLUMN email VARCHAR(255) UNIQUE;
```

**Migration 3 - Create the products table.**

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

**Migration 4 - Create the orders table with foreign keys.**

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

**Migration 5 - Add a status column and audit trigger.**

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

Before applying anything, check what Flyway sees.

**On your Mac terminal, in ~/dba-labs/flyway-aurora:**

```bash
flyway -configFiles=flyway.conf info
```

- `-configFiles=flyway.conf` - tells Flyway which configuration file to use.
- `info` - shows the status of all migrations without applying anything.

Expected output (yours will differ):
```
Schema version: << Empty Schema >>
+-----------+---------+------------------------------+------+--------------+---------+
| Category  | Version | Description                  | Type | Installed On | State   |
+-----------+---------+------------------------------+------+--------------+---------+
| Versioned | 1       | create users table           | SQL  |              | Pending |
| Versioned | 2       | add email to users           | SQL  |              | Pending |
| Versioned | 3       | create products table        | SQL  |              | Pending |
| Versioned | 4       | create orders table          | SQL  |              | Pending |
| Versioned | 5       | add order status and audit   | SQL  |              | Pending |
+-----------+---------+------------------------------+------+--------------+---------+
```

All five migrations show as `Pending` - Flyway found them but has not applied them yet.

---

## Step 8: Run Flyway Migrate

Apply all pending migrations:

```bash
flyway -configFiles=flyway.conf migrate
```

- `migrate` - applies all pending migrations in version order.

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

Run `info` again to confirm all migrations are applied:

```bash
flyway -configFiles=flyway.conf info
```

Expected output (yours will differ):
```
Schema version: 5
+-----------+---------+------------------------------+------+---------------------+---------+
| Category  | Version | Description                  | Type | Installed On        | State   |
+-----------+---------+------------------------------+------+---------------------+---------+
| Versioned | 1       | create users table           | SQL  | 2026-06-09 10:00:00 | Success |
| Versioned | 2       | add email to users           | SQL  | 2026-06-09 10:00:00 | Success |
| Versioned | 3       | create products table        | SQL  | 2026-06-09 10:00:00 | Success |
| Versioned | 4       | create orders table          | SQL  | 2026-06-09 10:00:00 | Success |
| Versioned | 5       | add order status and audit   | SQL  | 2026-06-09 10:00:00 | Success |
+-----------+---------+------------------------------+------+---------------------+---------+
```

---

## Step 9: Explore the flyway_schema_history Table

Flyway tracks every migration in a metadata table called `flyway_schema_history`. This is how Flyway knows what has been applied and what is still pending.

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d flyway_lab -c "SELECT installed_rank, version, description, type, checksum, installed_on, success FROM flyway_schema_history ORDER BY installed_rank;"
```

Expected output (yours will differ):
```
 installed_rank | version |         description          | type |  checksum   |     installed_on        | success
----------------+---------+------------------------------+------+-------------+-------------------------+---------
              1 | 1       | create users table           | SQL  |  -839201456 | 2026-06-09 10:00:00.123 | t
              2 | 2       | add email to users           | SQL  |  1029384756 | 2026-06-09 10:00:00.145 | t
              3 | 3       | create products table        | SQL  | -1234567890 | 2026-06-09 10:00:00.167 | t
              4 | 4       | create orders table          | SQL  |   987654321 | 2026-06-09 10:00:00.189 | t
              5 | 5       | add order status and audit   | SQL  |  -567890123 | 2026-06-09 10:00:00.211 | t
```

Key columns:

- **installed_rank** - The order in which migrations were applied
- **version** - The migration version number from the file name
- **checksum** - A hash of the file contents. If you modify a migration file after it has been applied, `flyway validate` catches the mismatch.
- **success** - Whether the migration completed without errors (`t` = true)

---

## Step 10: Flyway Validate

Validate checks that your migration files on disk match what was applied to the database. This catches the common mistake of editing a migration file after it has already been applied.

```bash
flyway -configFiles=flyway.conf validate
```

- `validate` - compares file checksums against the database records.

Expected output (yours will differ):
```
Successfully validated 5 migrations (execution time 00:00.025s)
```

Now break it intentionally. Add a comment to V1:

```bash
echo "-- I changed this file after it was applied" >> ~/dba-labs/flyway-aurora/sql/V1__create_users_table.sql
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

Remove the comment line you added at the bottom. Save and exit (`:wq`).

---

## Step 11: Repeatable Migrations

Repeatable migrations are re-applied every time their content changes. They are ideal for database objects you redefine entirely - views, functions, and materialized view refreshes.

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
    COUNT(o.order_id)               AS total_orders,
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

Now modify the view. Open the file:

```bash
vi sql/R__reporting_views.sql
```

Add `MAX(o.ordered_at) AS last_order_date` to the SELECT list (before the FROM line). Save and run migrate again:

```bash
flyway -configFiles=flyway.conf migrate
```

Flyway detects the checksum changed and re-applies the repeatable migration, replacing the view with the new definition.

---

## Step 12: Idempotent Runs

Run migrate again with no new files:

```bash
flyway -configFiles=flyway.conf migrate
```

Expected output (yours will differ):
```
Current version of schema "public": 5
Schema "public" is up to date. No migration necessary.
```

Flyway is idempotent. Running `migrate` with nothing new changes nothing. You can safely run `flyway migrate` in a CI/CD pipeline on every deployment, and it only applies what is new.

---

## Step 13: Clean and Rebuild (Lab Only)

If you want to start fresh, `flyway clean` drops all objects:

```bash
flyway -configFiles=flyway.conf clean
```

- `clean` - drops every table, view, function, and index in the schema.

Expected output (yours will differ):
```
Successfully cleaned schema "public" (execution time 00:00.045s)
```

**WARNING:** `flyway clean` drops everything including data. Never run this against production. The `flyway.cleanDisabled=true` setting prevents accidental execution.

After cleaning, re-apply all migrations:

```bash
flyway -configFiles=flyway.conf migrate
```

All five versioned migrations and the repeatable migration apply from scratch.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Schema migrations | Version control for DDL - numbered SQL files applied in order |
| Migration-based vs state-based | Migration-based gives full control over every DDL statement |
| Flyway naming | `V{version}__{description}.sql` with exactly two underscores |
| flyway migrate | Applies all pending migrations in version order |
| flyway info | Shows migration status (pending, success, failed) without changing anything |
| flyway validate | Ensures files have not been modified after being applied |
| flyway_schema_history | Metadata table tracking every applied migration |
| Repeatable migrations | `R__` prefix - re-applied when file content changes |
| Idempotency | Running migrate twice changes nothing - safe for automation |
| flyway.conf | Configuration file for connection details and migration locations |

---

**Next:** [BUILD 02: Flyway Setup](02-flyway-setup.md) - configure Flyway for Aurora environments, manage multiple configs, and structure a production project.
