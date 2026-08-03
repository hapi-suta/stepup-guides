# USE: CI/CD Exercises

**Module 05: CI/CD for Database Changes**

---

## Exercise 1: Migration Chain - Build a Complete Schema

**Objective:** Write 10 Flyway migrations that build a complete e-commerce schema from scratch.

### Requirements

Create the following migrations in order:

| Version | Description | Tables/Objects |
|---------|-------------|---------------|
| V1 | Create users table | `users` (user_id, username, email, password_hash, created_at) |
| V2 | Create products table | `products` (product_id, name, description, price, stock_quantity, created_at) |
| V3 | Create categories table | `categories` (category_id, name, parent_category_id self-ref) |
| V4 | Link products to categories | `product_categories` (product_id, category_id) - junction table |
| V5 | Create orders table | `orders` (order_id, user_id, status, total_amount, ordered_at) |
| V6 | Create order items | `order_items` (item_id, order_id, product_id, quantity, unit_price) |
| V7 | Add indexes | Performance indexes on foreign keys and common query columns |
| V8 | Create views | `v_order_summary`, `v_product_catalog` |
| V9 | Add audit trigger | Audit trigger on orders table for status changes |
| V10 | Add constraints | CHECK constraints on price, quantity, status values |

### Setup

```bash
mkdir -p ~/dba-labs/exercise-migration-chain/sql
cd ~/dba-labs/exercise-migration-chain
```

Create `flyway.conf`:
```properties
flyway.url=jdbc:postgresql://localhost:5432/migration_exercise
flyway.user=postgres
flyway.password=postgres
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
```

```bash
psql -U postgres -c "CREATE DATABASE migration_exercise;"
```

### Acceptance Criteria

- [ ] All 10 migrations apply cleanly with `flyway migrate`
- [ ] `flyway validate` passes with no errors
- [ ] All foreign keys are properly defined
- [ ] Indexes exist on all foreign key columns
- [ ] Views return data after inserting test rows
- [ ] Audit trigger fires on order status update
- [ ] `flyway clean` followed by `flyway migrate` works (full idempotent rebuild)

### Verification

After applying all migrations, run:

```sql
-- Should return 10
SELECT count(*) FROM flyway_schema_history WHERE success = true;

-- Should list all tables
SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

-- Insert test data and verify views
INSERT INTO users (username, email, password_hash) VALUES ('testuser', 'test@test.com', 'hash123');
INSERT INTO products (name, description, price, stock_quantity) VALUES ('Widget', 'A widget', 9.99, 100);
INSERT INTO orders (user_id, status, total_amount) VALUES (1, 'pending', 9.99);
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (1, 1, 1, 9.99);

SELECT * FROM v_order_summary;
```

---

## Exercise 2: GitHub Actions Pipeline

**Objective:** Create a complete GitHub Actions workflow that tests database migrations against a PostgreSQL service container.

### Requirements

1. Create a GitHub repository with the migrations from Exercise 1
2. Write a workflow file (`.github/workflows/migration-ci.yml`) that:
   - Triggers on push to `main` and on pull requests
   - Spins up a PostgreSQL 16 service container
   - Installs Flyway
   - Runs `flyway migrate`
   - Runs `flyway validate`
   - Executes a validation SQL script that checks:
     - All expected tables exist
     - All expected indexes exist
     - Foreign key constraints are in place
     - Views return correct column counts

### Starter Template

```yaml
name: Database Migration CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test-migrations:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          # Fill in the environment variables
        ports:
          - 5432:5432
        options: >-
          # Fill in health check options

    steps:
      # Fill in the steps:
      # 1. Checkout code
      # 2. Install Flyway
      # 3. Wait for PostgreSQL
      # 4. Run migrations
      # 5. Validate schema
      # 6. Run Flyway validate
```

### Acceptance Criteria

- [ ] Workflow triggers correctly on push and PR
- [ ] PostgreSQL service container starts and is healthy
- [ ] All migrations apply successfully
- [ ] Validation script catches schema issues
- [ ] Workflow shows green checkmark in GitHub Actions UI

---

## Exercise 3: Zero-Downtime Challenge

**Objective:** Migrate a table with 1M rows without causing any locking that would block reads or writes.

### Scenario

You have a `customers` table with 1 million rows:

```sql
CREATE DATABASE zdt_exercise;
\c zdt_exercise

CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    signup_date DATE DEFAULT CURRENT_DATE
);

INSERT INTO customers (full_name, email, signup_date)
SELECT
    'Customer ' || i,
    'cust' || i || '@example.com',
    CURRENT_DATE - (random() * 365)::int
FROM generate_series(1, 1000000) AS i;
```

### Required Changes

Write migrations to accomplish ALL of the following without blocking reads or writes:

1. **Add a column:** `phone VARCHAR(20)` with a default of `'unknown'`
2. **Add an index:** On the `email` column (must use CONCURRENTLY)
3. **Add a composite index:** On `(signup_date, full_name)` (must use CONCURRENTLY)
4. **Add a CHECK constraint:** `email` must contain `@` (use NOT VALID + VALIDATE pattern)
5. **Backfill data:** Set `phone` to `'+1-555-' || lpad(id::text, 7, '0')` for all rows (batched, 10K at a time)

### Rules

- Every migration file must include `SET lock_timeout = '5s';`
- Index creation must use `CONCURRENTLY` (and `executeInTransaction=false` for Flyway)
- Backfill must be batched (not a single UPDATE on 1M rows)
- Constraints must use the NOT VALID + VALIDATE two-step pattern

### Acceptance Criteria

- [ ] All changes applied without errors
- [ ] No `ACCESS EXCLUSIVE` lock held for more than 5 seconds
- [ ] All 1M rows have the `phone` column populated
- [ ] Index on email exists and is VALID
- [ ] CHECK constraint is validated

### Verification

```sql
-- All rows should have phone populated
SELECT count(*) FROM customers WHERE phone IS NULL OR phone = 'unknown';
-- Should return 0

-- Index should be valid
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'customers' AND indexname LIKE 'idx_%';

-- Constraint should be valid
SELECT conname, convalidated FROM pg_constraint WHERE conrelid = 'customers'::regclass;
```

---

## Exercise 4: Multi-Environment Deploy

**Objective:** Create a complete multi-environment deployment pipeline with approval gates.

### Requirements

Create three Flyway configuration files:

1. `flyway-dev.conf` - connects to a local dev database
2. `flyway-staging.conf` - connects to a staging database (use localhost with a different DB name)
3. `flyway-prod.conf` - connects to a production database (use localhost with a different DB name)

Write a GitHub Actions workflow (`migration-deploy.yml`) with three jobs:

```
test -> deploy-staging -> deploy-production
         (auto)            (manual approval)
```

### Setup

```bash
psql -U postgres -c "CREATE DATABASE deploy_dev;"
psql -U postgres -c "CREATE DATABASE deploy_staging;"
psql -U postgres -c "CREATE DATABASE deploy_prod;"
```

### Workflow Requirements

- `test` job: fresh PostgreSQL container, apply all migrations, validate
- `deploy-staging` job: depends on `test`, applies to staging automatically
- `deploy-production` job: depends on `deploy-staging`, requires manual approval via GitHub Environment

### Acceptance Criteria

- [ ] Three separate config files with correct database URLs
- [ ] Workflow has three jobs with proper `needs:` dependencies
- [ ] Production job uses `environment: production`
- [ ] All three databases have identical schemas after deployment
- [ ] Manual approval is required for production

### Verification

```bash
# Compare schemas across environments
pg_dump -U postgres --schema-only deploy_dev > /tmp/dev.sql
pg_dump -U postgres --schema-only deploy_staging > /tmp/staging.sql
pg_dump -U postgres --schema-only deploy_prod > /tmp/prod.sql

diff /tmp/dev.sql /tmp/staging.sql   # Should be empty
diff /tmp/staging.sql /tmp/prod.sql  # Should be empty
```

---

## Exercise 5: Schema Drift Detection

**Objective:** Detect and fix schema differences between two databases.

### Scenario

You have two databases that should be identical, but someone ran manual DDL on one of them.

### Setup

```bash
psql -U postgres -c "CREATE DATABASE drift_source;"
psql -U postgres -c "CREATE DATABASE drift_target;"
```

Apply the same schema to both:

```bash
psql -U postgres -d drift_source -c "
CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), email VARCHAR(255));
CREATE TABLE orders (id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id), amount NUMERIC(10,2));
CREATE INDEX idx_orders_user_id ON orders (user_id);
"

psql -U postgres -d drift_target -c "
CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), email VARCHAR(255));
CREATE TABLE orders (id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id), amount NUMERIC(10,2));
CREATE INDEX idx_orders_user_id ON orders (user_id);
"
```

Now introduce drift on the target:

```bash
psql -U postgres -d drift_target -c "
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
DROP INDEX idx_orders_user_id;
ALTER TABLE orders ADD COLUMN notes TEXT;
CREATE TABLE temp_imports (id SERIAL, data JSONB);
"
```

### Tasks

1. **Detect the drift** using at least two methods:
   - `pg_dump --schema-only` + `diff`
   - Atlas `schema diff` (or Liquibase `diff`)

2. **Document the differences** in a report:
   - What tables/columns/indexes were added to target?
   - What was removed from target?

3. **Generate a migration** that syncs target back to match source

4. **Apply the migration** and verify both databases match

### Acceptance Criteria

- [ ] All differences identified correctly
- [ ] Migration script generated (manually or with tool)
- [ ] After applying migration, `pg_dump --schema-only` of both databases produces identical output
- [ ] Drift report documents each difference with impact assessment
