# BUILD 02: Flyway Setup for Aurora

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster
**Estimated Time:** 45-60 minutes

---

## What You Will Learn

How to set up a production-ready Flyway project for Aurora PostgreSQL - multiple environment configs, environment variables for secrets, project structure, baseline migrations, and the Flyway commands you will use daily.

---

## Prerequisites

- Flyway installed (`brew install flyway`)
- Aurora PostgreSQL cluster (`devops-lab-cluster`) running
- Completed BUILD 01 (Schema Migration Fundamentals)

---

## Step 1: Create a Production Project Structure

A real migration project needs more than a `sql/` folder. Here is the structure you will build.

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/aurora-migrations/migrations/sql
```

```bash
mkdir -p ~/dba-labs/aurora-migrations/migrations/seed
```

```bash
mkdir -p ~/dba-labs/aurora-migrations/scripts
```

```bash
mkdir -p ~/dba-labs/aurora-migrations/.github/workflows
```

This creates four directories:

- `migrations/sql/` - versioned and repeatable migration files
- `migrations/seed/` - test data scripts (not managed by Flyway)
- `scripts/` - helper scripts for validation, drift detection, etc.
- `.github/workflows/` - GitHub Actions workflow files (BUILD 03)

Move into the project:

```bash
cd ~/dba-labs/aurora-migrations
```

---

## Step 2: Create Environment-Specific Configuration

In production, you have multiple environments. Each needs its own Flyway config.

**Create the dev config:**

```bash
vi migrations/flyway-dev.conf
```

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/cicd_dev
flyway.user=flyway_user
flyway.password=${FLYWAY_PASSWORD}
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
flyway.baselineOnMigrate=false
flyway.outOfOrder=false
flyway.validateOnMigrate=true
```

What each setting means:

- `flyway.url` - JDBC connection string. Replace `YOUR_AURORA_ENDPOINT` with your Aurora writer endpoint.
- `flyway.user` - A dedicated migration user (not postgres). We create this in Step 4.
- `flyway.password=${FLYWAY_PASSWORD}` - Reads the password from an environment variable. Never hardcode passwords in config files that get committed to Git.
- `flyway.locations` - Directory containing migration SQL files.
- `flyway.cleanDisabled=false` - Allows `flyway clean` in dev. Set to `true` for production.
- `flyway.baselineOnMigrate=false` - Do not auto-baseline. We control when baselining happens.
- `flyway.outOfOrder=false` - Migrations must be applied in strict version order.
- `flyway.validateOnMigrate=true` - Run validation before each migration to catch tampering.

**Create the staging config:**

```bash
vi migrations/flyway-staging.conf
```

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/cicd_staging
flyway.user=flyway_user
flyway.password=${FLYWAY_PASSWORD}
flyway.locations=filesystem:./sql
flyway.cleanDisabled=true
flyway.baselineOnMigrate=false
flyway.outOfOrder=false
flyway.validateOnMigrate=true
```

Note: `cleanDisabled=true` for staging. You do not want anyone accidentally wiping staging.

**Create the production config:**

```bash
vi migrations/flyway-prod.conf
```

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/cicd_prod
flyway.user=flyway_user
flyway.password=${FLYWAY_PASSWORD}
flyway.locations=filesystem:./sql
flyway.cleanDisabled=true
flyway.baselineOnMigrate=false
flyway.outOfOrder=false
flyway.validateOnMigrate=true
flyway.lockRetryCount=10
```

- `flyway.lockRetryCount=10` - If Flyway cannot acquire its internal lock (another migration is running), retry up to 10 times. This prevents failures when two deployments overlap.

---

## Step 3: Create the Databases

**On your Mac terminal:**

Connect to your Aurora cluster and create the three databases:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE cicd_dev;"
```

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE cicd_staging;"
```

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE cicd_prod;"
```

Expected output for each:
```
CREATE DATABASE
```

---

## Step 4: Create a Dedicated Migration User

Never run migrations as the `postgres` superuser. Create a dedicated user with only the permissions it needs.

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres
```

Inside psql, run these statements one at a time:

```sql
CREATE USER flyway_user WITH PASSWORD 'your_secure_password_here';
```

- Creates a user named `flyway_user`. Replace the password with something strong.

```sql
GRANT CONNECT ON DATABASE cicd_dev TO flyway_user;
```

- Allows `flyway_user` to connect to the dev database.

```sql
GRANT CONNECT ON DATABASE cicd_staging TO flyway_user;
```

```sql
GRANT CONNECT ON DATABASE cicd_prod TO flyway_user;
```

Now connect to each database and grant schema permissions:

```sql
\c cicd_dev
```

```sql
GRANT ALL ON SCHEMA public TO flyway_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO flyway_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO flyway_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO flyway_user;
```

Repeat for staging and production:

```sql
\c cicd_staging
GRANT ALL ON SCHEMA public TO flyway_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO flyway_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO flyway_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO flyway_user;
```

```sql
\c cicd_prod
GRANT ALL ON SCHEMA public TO flyway_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO flyway_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO flyway_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO flyway_user;
```

Exit psql:

```sql
\q
```

---

## Step 5: Set the Password Environment Variable

Instead of hardcoding the password, set it as an environment variable.

**On your Mac terminal:**

```bash
export FLYWAY_PASSWORD='your_secure_password_here'
```

- `export` makes the variable available to child processes (like Flyway).

To make this permanent, add it to your shell profile:

```bash
echo 'export FLYWAY_PASSWORD="your_secure_password_here"' >> ~/.zshrc
```

Verify it is set:

```bash
echo $FLYWAY_PASSWORD
```

Expected output:
```
your_secure_password_here
```

---

## Step 6: Write the Initial Migration Set

Create a set of migrations for the project.

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

**Migration 1 - Create the customers table:**

```bash
vi migrations/sql/V1__create_customers_table.sql
```

```sql
-- V1: Core customers table
SET lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS customers (
    customer_id  SERIAL PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(255) NOT NULL UNIQUE,
    phone        VARCHAR(20),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE customers IS 'Customer accounts';
```

Note: `SET lock_timeout = '5s'` is included in every migration. If the lock cannot be acquired in 5 seconds, the migration fails fast instead of blocking other queries.

**Migration 2 - Create the products table:**

```bash
vi migrations/sql/V2__create_products_table.sql
```

```sql
-- V2: Products catalog
SET lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS products (
    product_id   SERIAL PRIMARY KEY,
    sku          VARCHAR(50) NOT NULL UNIQUE,
    name         VARCHAR(200) NOT NULL,
    description  TEXT,
    price        NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock_qty    INTEGER NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_sku ON products (sku);
CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);
```

**Migration 3 - Create the orders and order_items tables:**

```bash
vi migrations/sql/V3__create_orders_tables.sql
```

```sql
-- V3: Orders and order items
SET lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS orders (
    order_id    SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
    status      VARCHAR(20) NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','confirmed','shipped','delivered','cancelled')),
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    ordered_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
    item_id     SERIAL PRIMARY KEY,
    order_id    INTEGER NOT NULL REFERENCES orders(order_id),
    product_id  INTEGER NOT NULL REFERENCES products(product_id),
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at ON orders (ordered_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items (product_id);
```

**Repeatable migration - Reporting views:**

```bash
vi migrations/sql/R__reporting_views.sql
```

```sql
-- Repeatable: Reporting views (re-applied when content changes)
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    c.full_name,
    c.email,
    COUNT(o.order_id)                AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS lifetime_value,
    MAX(o.ordered_at)                AS last_order_date
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.full_name, c.email;

CREATE OR REPLACE VIEW v_product_sales AS
SELECT
    p.sku,
    p.name,
    p.price                          AS current_price,
    COALESCE(SUM(oi.quantity), 0)    AS total_units_sold,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_revenue
FROM products p
LEFT JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.product_id, p.sku, p.name, p.price;
```

---

## Step 7: Apply Migrations to Dev

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

First, check what Flyway sees:

```bash
cd ~/dba-labs/aurora-migrations/migrations
```

```bash
flyway -configFiles=flyway-dev.conf info
```

Expected output (yours will differ):
```
Schema version: << Empty Schema >>
+-----------+---------+---------------------------+------+--------------+---------+
| Category  | Version | Description               | Type | Installed On | State   |
+-----------+---------+---------------------------+------+--------------+---------+
| Versioned | 1       | create customers table    | SQL  |              | Pending |
| Versioned | 2       | create products table     | SQL  |              | Pending |
| Versioned | 3       | create orders tables      | SQL  |              | Pending |
| Repeatable|         | reporting views           | SQL  |              | Pending |
+-----------+---------+---------------------------+------+--------------+---------+
```

Apply all migrations:

```bash
flyway -configFiles=flyway-dev.conf migrate
```

Expected output (yours will differ):
```
Migrating schema "public" to version 1 - create customers table
Migrating schema "public" to version 2 - create products table
Migrating schema "public" to version 3 - create orders tables
Migrating schema "public" with repeatable migration reporting views
Successfully applied 4 migrations to schema "public" (execution time 00:00.156s)
```

Validate:

```bash
flyway -configFiles=flyway-dev.conf validate
```

Expected output (yours will differ):
```
Successfully validated 4 migrations (execution time 00:00.023s)
```

---

## Step 8: Apply to Staging and Production

Now apply the same migrations to the other environments.

**On your Mac terminal, in ~/dba-labs/aurora-migrations/migrations:**

```bash
flyway -configFiles=flyway-staging.conf migrate
```

```bash
flyway -configFiles=flyway-prod.conf migrate
```

All three environments now have identical schemas. This is the core benefit of migration-based workflow - every environment gets the exact same DDL in the exact same order.

---

## Step 9: Create a Validation Script

Create a script that verifies the schema after migrations. This will be used in CI/CD pipelines.

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

```bash
vi scripts/validate_schema.sql
```

```sql
-- Schema validation: run after migrations to verify correctness
-- Any assertion failure causes the script to exit with an error

DO $$
BEGIN
    -- Check that all expected tables exist
    ASSERT (
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name IN ('customers', 'products', 'orders', 'order_items')
    ) = 4,
    'Expected 4 tables (customers, products, orders, order_items)';

    -- Check customers table columns
    ASSERT (
        SELECT COUNT(*) FROM information_schema.columns
        WHERE table_name = 'customers'
        AND column_name IN ('customer_id', 'full_name', 'email', 'phone', 'created_at', 'updated_at')
    ) = 6,
    'customers table missing expected columns';

    -- Check foreign keys on orders
    ASSERT (
        SELECT COUNT(*) FROM information_schema.table_constraints
        WHERE table_name = 'orders'
        AND constraint_type = 'FOREIGN KEY'
    ) >= 1,
    'orders table should have at least 1 foreign key';

    -- Check foreign keys on order_items
    ASSERT (
        SELECT COUNT(*) FROM information_schema.table_constraints
        WHERE table_name = 'order_items'
        AND constraint_type = 'FOREIGN KEY'
    ) >= 2,
    'order_items table should have at least 2 foreign keys';

    -- Check indexes exist
    ASSERT (
        SELECT COUNT(*) FROM pg_indexes
        WHERE schemaname = 'public'
        AND indexname LIKE 'idx_%'
    ) >= 7,
    'Expected at least 7 custom indexes';

    -- Check views exist
    ASSERT (
        SELECT COUNT(*) FROM information_schema.views
        WHERE table_schema = 'public'
        AND table_name IN ('v_order_summary', 'v_product_sales')
    ) = 2,
    'Expected 2 reporting views';

    RAISE NOTICE 'All schema validations passed';
END $$;
```

Test it:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d cicd_dev -f scripts/validate_schema.sql
```

Expected output (yours will differ):
```
NOTICE:  All schema validations passed
DO
```

---

## Step 10: Understand Flyway Baseline

What if you adopt Flyway for a database that already has a schema? You cannot run V1__create_users.sql if the table already exists.

Flyway's `baseline` command handles this:

```bash
flyway -configFiles=flyway-dev.conf baseline -baselineVersion=3
```

- `baseline` - marks the database as already at a specific version.
- `-baselineVersion=3` - tells Flyway "the database is already at V3, start applying from V4."

This inserts a baseline record into `flyway_schema_history`. All migrations up to V3 are considered "already applied" and will be skipped.

**When to use baseline:**
- Adopting Flyway for an existing database
- Migrating from another tool (Liquibase, manual scripts)
- Resetting the history after a database rebuild

**Do not run this now** - it is a concept exercise. Your lab databases are already set up correctly.

---

## Step 11: The .gitignore File

Create a `.gitignore` to prevent committing sensitive files:

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

```bash
vi .gitignore
```

```
# Flyway passwords
**/flyway-*.conf

# Environment files
.env
*.env

# OS files
.DS_Store

# Editor files
*.swp
*.swo
*~
```

Wait - we put the config files in `.gitignore`? Yes. Config files with database credentials should not be committed. Instead, commit a template:

```bash
vi migrations/flyway.conf.template
```

```properties
# Copy this file to flyway-{env}.conf and fill in your values
flyway.url=jdbc:postgresql://AURORA_ENDPOINT:5432/DATABASE_NAME
flyway.user=flyway_user
flyway.password=${FLYWAY_PASSWORD}
flyway.locations=filesystem:./sql
flyway.cleanDisabled=true
flyway.baselineOnMigrate=false
flyway.outOfOrder=false
flyway.validateOnMigrate=true
```

Commit the template but not the actual configs. In CI/CD, configs are generated from environment variables and secrets.

---

## Step 12: Flyway Command Reference

Here is every Flyway command you will use:

| Command | Purpose | Safe for Production? |
|---------|---------|---------------------|
| `flyway migrate` | Apply pending migrations | Yes |
| `flyway info` | Show migration status | Yes (read-only) |
| `flyway validate` | Check migration checksums | Yes (read-only) |
| `flyway repair` | Fix failed migration entries | Use with caution |
| `flyway clean` | Drop all objects in the schema | NEVER in production |
| `flyway baseline` | Mark existing schema as a version | One-time setup only |

**Repair details:** When a migration fails (syntax error, timeout), Flyway records it as `failed` in the history table. The next `migrate` will refuse to run because of the failed entry. `flyway repair` removes the failed entry so you can fix the migration file and retry.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Project structure | Separate directories for SQL, seed data, scripts, and workflows |
| Multi-env configs | One config file per environment (dev, staging, prod) |
| Environment variables | `${FLYWAY_PASSWORD}` reads from env vars - never hardcode secrets |
| Dedicated user | Create a `flyway_user` with minimal permissions - not postgres |
| lock_timeout | Include `SET lock_timeout = '5s'` in every migration file |
| IF NOT EXISTS | Guards on CREATE TABLE/INDEX make migrations safer to re-run |
| Validation script | SQL assertions that verify schema correctness after migrations |
| Baseline | Mark an existing database as "at version N" for Flyway adoption |
| .gitignore | Commit config templates, not actual configs with credentials |
| flyway repair | Cleans up failed migration entries so you can retry |

---

**Next:** [BUILD 03: GitHub Actions Pipeline](03-github-actions-pipeline.md) - automate testing and deployment of these migrations.
