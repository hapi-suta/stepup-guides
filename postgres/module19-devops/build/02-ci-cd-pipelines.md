# Module 19 - BUILD 02: CI/CD Pipelines for PostgreSQL

## Overview

Continuous Integration (CI) catches schema bugs before they reach production. Continuous Deployment (CD) automates the release process so migrations run reliably every time. This guide covers GitHub Actions for PostgreSQL CI, testing against service containers, and pre/post-deployment checks.

---

## Prerequisites

- GitHub account with a repository
- Basic understanding of YAML syntax
- Familiarity with Flyway or another migration tool (see BUILD 01)
- PostgreSQL 16 on CentOS Stream 9 for local testing

---

## Part 1: GitHub Actions for PostgreSQL CI

### 1.1 Understand the Workflow Structure

GitHub Actions workflows live in `.github/workflows/` inside your repository. Each workflow is a YAML file that defines:

- **Triggers** - when to run (push, pull request, schedule)
- **Jobs** - groups of steps that run on a runner
- **Steps** - individual commands or actions
- **Services** - containers that run alongside your job (like a PostgreSQL database)

### 1.2 Create Your Repository Structure

On your local machine, create the project layout.

```bash
mkdir -p /opt/pgsql/ci-lab
```

```bash
cd /opt/pgsql/ci-lab
```

```bash
mkdir -p .github/workflows
```

```bash
mkdir -p db/migrations
```

```bash
mkdir -p tests
```

Verify the structure.

```bash
find /opt/pgsql/ci-lab -type d
```

Expected output (yours will differ):
```
/opt/pgsql/ci-lab
/opt/pgsql/ci-lab/.github
/opt/pgsql/ci-lab/.github/workflows
/opt/pgsql/ci-lab/db
/opt/pgsql/ci-lab/db/migrations
/opt/pgsql/ci-lab/tests
```

### 1.3 Create Migration Files

Create the first migration.

```bash
vi /opt/pgsql/ci-lab/db/migrations/V1__create_users.sql
```

```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
```

Create the second migration.

```bash
vi /opt/pgsql/ci-lab/db/migrations/V2__create_orders.sql
```

```sql
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    total NUMERIC(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
```

### 1.4 Create a Test Script

This script verifies that migrations applied correctly by checking for expected tables and columns.

```bash
vi /opt/pgsql/ci-lab/tests/test_schema.sh
```

```bash
#!/bin/bash
# test_schema.sh - Verify database schema after migrations
# Exit on any error
set -e

DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/testdb}"

echo "=== Running Schema Tests ==="

# Test 1: Check that users table exists
echo -n "Test 1: users table exists... "
psql "$DB_URL" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users');" | grep -q 't'
echo "PASS"

# Test 2: Check that orders table exists
echo -n "Test 2: orders table exists... "
psql "$DB_URL" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'orders');" | grep -q 't'
echo "PASS"

# Test 3: Check foreign key from orders to users
echo -n "Test 3: orders.user_id foreign key... "
psql "$DB_URL" -tAc "
SELECT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_type = 'FOREIGN KEY'
    AND table_name = 'orders'
);" | grep -q 't'
echo "PASS"

# Test 4: Check indexes exist
echo -n "Test 4: idx_users_email index... "
psql "$DB_URL" -tAc "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_users_email');" | grep -q 't'
echo "PASS"

# Test 5: Insert and query test data
echo -n "Test 5: insert and query data... "
psql "$DB_URL" -c "
INSERT INTO users (username, email) VALUES ('testuser', 'test@example.com')
ON CONFLICT (username) DO NOTHING;
" > /dev/null 2>&1
RESULT=$(psql "$DB_URL" -tAc "SELECT count(*) FROM users WHERE username = 'testuser';")
if [ "$RESULT" -ge 1 ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo "=== All Schema Tests Passed ==="
```

Make it executable.

```bash
chmod +x /opt/pgsql/ci-lab/tests/test_schema.sh
```

---

## Part 2: Running Tests Against a PostgreSQL Service Container

### 2.1 Create the GitHub Actions Workflow

This is the core CI pipeline. It spins up a PostgreSQL container, runs migrations, and then runs tests.

```bash
vi /opt/pgsql/ci-lab/.github/workflows/db-ci.yml
```

```yaml
name: Database CI

# Run on every push and pull request to main
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  # Also allow manual trigger
  workflow_dispatch:

jobs:
  test-migrations:
    runs-on: ubuntu-latest

    # Define a PostgreSQL service container
    # This runs alongside your job and is accessible at localhost:5432
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        # Health check ensures PostgreSQL is ready before steps run
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    env:
      DATABASE_URL: postgresql://postgres:postgres@localhost:5432/testdb

    steps:
      # Step 1: Check out the repository code
      - name: Checkout code
        uses: actions/checkout@v4

      # Step 2: Install PostgreSQL client tools
      - name: Install PostgreSQL client
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client

      # Step 3: Verify database is accessible
      - name: Verify database connection
        run: |
          psql "$DATABASE_URL" -c "SELECT version();"

      # Step 4: Run migrations using psql
      # Migrations are applied in alphabetical order
      - name: Run migrations
        run: |
          for migration in db/migrations/V*.sql; do
            echo "Applying: $migration"
            psql "$DATABASE_URL" -f "$migration"
          done

      # Step 5: Run schema tests
      - name: Run schema tests
        run: |
          chmod +x tests/test_schema.sh
          ./tests/test_schema.sh

      # Step 6: Dump final schema for review
      - name: Dump schema
        run: |
          pg_dump --schema-only "$DATABASE_URL" > schema.sql

      # Step 7: Upload schema as build artifact
      # This lets you download and review the schema from any CI run
      - name: Upload schema artifact
        uses: actions/upload-artifact@v4
        with:
          name: schema-dump
          path: schema.sql
          retention-days: 30
```

### 2.2 Understand the Service Container

The `services` block in the workflow creates a Docker container running PostgreSQL 16. Key points:

- It starts before any steps run
- The health check (`pg_isready`) ensures PostgreSQL accepts connections before your steps begin
- It is accessible at `localhost:5432` from within the job
- It is destroyed after the job completes
- Environment variables set the initial user, password, and database

### 2.3 Test Locally Before Pushing

You can test the workflow locally using `act` (a tool that runs GitHub Actions locally). Install it first.

```bash
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

Run the workflow.

```bash
cd /opt/pgsql/ci-lab
```

```bash
act -j test-migrations
```

Note: `act` requires Docker to be installed and running.

---

## Part 3: Schema Migration in CI Pipeline

### 3.1 Flyway in GitHub Actions

If you use Flyway instead of raw SQL, replace the migration step.

```bash
vi /opt/pgsql/ci-lab/.github/workflows/db-ci-flyway.yml
```

```yaml
name: Database CI (Flyway)

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  migrate-and-test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Install Flyway using the official Docker image
      - name: Run Flyway migrations
        run: |
          docker run --rm --network host \
            -v $(pwd)/db/migrations:/flyway/sql \
            flyway/flyway:10 \
            -url=jdbc:postgresql://localhost:5432/testdb \
            -user=postgres \
            -password=postgres \
            migrate

      # Check migration status
      - name: Check Flyway info
        run: |
          docker run --rm --network host \
            -v $(pwd)/db/migrations:/flyway/sql \
            flyway/flyway:10 \
            -url=jdbc:postgresql://localhost:5432/testdb \
            -user=postgres \
            -password=postgres \
            info

      - name: Install PostgreSQL client
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client

      - name: Run schema tests
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/testdb
        run: |
          chmod +x tests/test_schema.sh
          ./tests/test_schema.sh
```

The `--network host` flag allows the Flyway Docker container to access the PostgreSQL service at `localhost:5432`.

---

## Part 4: Pre-Deployment Checks

### 4.1 Schema Diff Check

Before deploying, compare the expected schema against the current production schema. This catches drift.

Create a pre-deployment check script.

```bash
vi /opt/pgsql/ci-lab/tests/pre_deploy_check.sh
```

```bash
#!/bin/bash
# pre_deploy_check.sh - Compare schemas before deployment
set -e

SOURCE_URL="${1:-postgresql://postgres:postgres@localhost:5432/testdb}"
EXPECTED_SCHEMA="db/expected_schema.sql"

echo "=== Pre-Deployment Schema Check ==="

# Dump current schema from the CI database
pg_dump --schema-only "$SOURCE_URL" > /tmp/current_schema.sql

# If we have an expected schema, diff them
if [ -f "$EXPECTED_SCHEMA" ]; then
    echo "Comparing current schema against expected..."
    DIFF_OUTPUT=$(diff -u "$EXPECTED_SCHEMA" /tmp/current_schema.sql || true)

    if [ -z "$DIFF_OUTPUT" ]; then
        echo "PASS: Schemas match exactly"
    else
        echo "WARNING: Schema differences detected:"
        echo "$DIFF_OUTPUT"
        echo ""
        echo "Review the differences above."
        echo "If intentional, update db/expected_schema.sql"
        # Exit with error to fail the CI check
        exit 1
    fi
else
    echo "No expected schema file found. Generating one..."
    cp /tmp/current_schema.sql "$EXPECTED_SCHEMA"
    echo "Created $EXPECTED_SCHEMA - commit this file"
fi

echo "=== Pre-Deployment Check Complete ==="
```

```bash
chmod +x /opt/pgsql/ci-lab/tests/pre_deploy_check.sh
```

### 4.2 Migration Safety Checks

Create a script that scans migration files for dangerous operations.

```bash
vi /opt/pgsql/ci-lab/tests/migration_safety_check.sh
```

```bash
#!/bin/bash
# migration_safety_check.sh - Detect dangerous migration patterns
set -e

MIGRATIONS_DIR="${1:-db/migrations}"
ERRORS=0

echo "=== Migration Safety Check ==="

for file in "$MIGRATIONS_DIR"/V*.sql; do
    [ -f "$file" ] || continue
    echo "Checking: $file"

    # Check for DROP TABLE without IF EXISTS
    if grep -inq "DROP TABLE " "$file" && ! grep -inq "DROP TABLE IF EXISTS" "$file"; then
        echo "  ERROR: DROP TABLE without IF EXISTS in $file"
        ERRORS=$((ERRORS + 1))
    fi

    # Check for DROP COLUMN (data loss risk)
    if grep -inq "DROP COLUMN" "$file"; then
        echo "  WARNING: DROP COLUMN detected in $file (data loss risk)"
        echo "  Make sure you have a backup strategy"
    fi

    # Check for TRUNCATE
    if grep -inq "TRUNCATE" "$file"; then
        echo "  ERROR: TRUNCATE detected in $file (data loss)"
        ERRORS=$((ERRORS + 1))
    fi

    # Check for ALTER TYPE on large columns (can lock table)
    if grep -inq "ALTER.*TYPE" "$file"; then
        echo "  WARNING: ALTER TYPE detected in $file (may lock table)"
    fi

    # Check for CREATE INDEX without CONCURRENTLY
    if grep -inq "CREATE INDEX " "$file" && ! grep -inq "CREATE INDEX CONCURRENTLY" "$file"; then
        echo "  WARNING: CREATE INDEX without CONCURRENTLY in $file"
        echo "  This will lock writes on the table"
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS error(s) found"
    exit 1
fi

echo "=== Migration Safety Check Passed ==="
```

```bash
chmod +x /opt/pgsql/ci-lab/tests/migration_safety_check.sh
```

### 4.3 Add Safety Check to the Workflow

Add this step before the migration step in your workflow.

```yaml
      # Run BEFORE migrations
      - name: Migration safety check
        run: |
          chmod +x tests/migration_safety_check.sh
          ./tests/migration_safety_check.sh db/migrations
```

---

## Part 5: Post-Deployment Verification

### 5.1 Create a Post-Deployment Verification Script

After migrations run in production, verify everything is healthy.

```bash
vi /opt/pgsql/ci-lab/tests/post_deploy_verify.sh
```

```bash
#!/bin/bash
# post_deploy_verify.sh - Post-deployment health checks
set -e

DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/testdb}"

echo "=== Post-Deployment Verification ==="

# Check 1: Database is accepting connections
echo -n "Check 1: Database connectivity... "
psql "$DB_URL" -c "SELECT 1;" > /dev/null 2>&1
echo "PASS"

# Check 2: No invalid indexes
echo -n "Check 2: No invalid indexes... "
INVALID=$(psql "$DB_URL" -tAc "
    SELECT count(*) FROM pg_index WHERE NOT indisvalid;
")
if [ "$INVALID" -eq 0 ]; then
    echo "PASS"
else
    echo "FAIL - $INVALID invalid index(es) found"
    psql "$DB_URL" -c "
        SELECT schemaname, tablename, indexname
        FROM pg_indexes i
        JOIN pg_index pi ON pi.indexrelid = (schemaname || '.' || indexname)::regclass
        WHERE NOT pi.indisvalid;
    "
    exit 1
fi

# Check 3: No orphaned sequences
echo -n "Check 3: Sequence health... "
psql "$DB_URL" -tAc "
    SELECT count(*) FROM pg_sequences WHERE last_value IS NOT NULL;
" > /dev/null 2>&1
echo "PASS"

# Check 4: Migration tracking table is healthy
echo -n "Check 4: Migration tracking... "
if psql "$DB_URL" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'flyway_schema_history');" | grep -q 't'; then
    FAILED=$(psql "$DB_URL" -tAc "SELECT count(*) FROM flyway_schema_history WHERE success = false;")
    if [ "$FAILED" -eq 0 ]; then
        echo "PASS (Flyway, no failed migrations)"
    else
        echo "FAIL - $FAILED failed migration(s) in history"
        exit 1
    fi
else
    echo "SKIP (no Flyway history table)"
fi

# Check 5: Table row counts (sanity check)
echo "Check 5: Table row counts..."
psql "$DB_URL" -c "
    SELECT schemaname, relname, n_live_tup
    FROM pg_stat_user_tables
    ORDER BY n_live_tup DESC;
"

echo "=== Post-Deployment Verification Complete ==="
```

```bash
chmod +x /opt/pgsql/ci-lab/tests/post_deploy_verify.sh
```

### 5.2 Complete CI/CD Pipeline

Here is a full pipeline that includes all checks.

```bash
vi /opt/pgsql/ci-lab/.github/workflows/db-ci-complete.yml
```

```yaml
name: Database CI/CD Complete

on:
  push:
    branches: [main]
    paths:
      - 'db/**'
      - 'tests/**'
  pull_request:
    branches: [main]
    paths:
      - 'db/**'
      - 'tests/**'

jobs:
  database-pipeline:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    env:
      DATABASE_URL: postgresql://postgres:postgres@localhost:5432/testdb

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install PostgreSQL client
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client

      # PRE-DEPLOYMENT
      - name: Migration safety check
        run: |
          chmod +x tests/migration_safety_check.sh
          ./tests/migration_safety_check.sh db/migrations

      # DEPLOY
      - name: Run migrations
        run: |
          for migration in db/migrations/V*.sql; do
            echo "Applying: $migration"
            psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
          done

      # POST-DEPLOYMENT
      - name: Schema tests
        run: |
          chmod +x tests/test_schema.sh
          ./tests/test_schema.sh

      - name: Post-deployment verification
        run: |
          chmod +x tests/post_deploy_verify.sh
          ./tests/post_deploy_verify.sh

      - name: Schema diff check
        run: |
          chmod +x tests/pre_deploy_check.sh
          ./tests/pre_deploy_check.sh "$DATABASE_URL"

      # ARTIFACTS
      - name: Dump final schema
        if: always()
        run: |
          pg_dump --schema-only "$DATABASE_URL" > schema.sql

      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: database-artifacts
          path: |
            schema.sql
          retention-days: 30
```

Key flags explained:
- `paths:` - Only triggers the pipeline when database or test files change
- `-v ON_ERROR_STOP=1` - Tells psql to stop immediately on any SQL error
- `if: always()` - Runs the step even if previous steps failed (useful for artifacts)

---

## Part 6: Deployment Strategies

### 6.1 Blue/Green Database Deployment

In a blue/green deployment, you maintain two database environments:

1. **Blue** (current production) - serving live traffic
2. **Green** (new version) - receives migrations and testing

Steps:
1. Restore a production backup to the green database
2. Run migrations against green
3. Run full test suite against green
4. Switch application traffic to green
5. Blue becomes the rollback target

### 6.2 Canary Database Deployment

For canary deployments:
1. Run migrations on production (they must be backward compatible)
2. Route 5% of traffic to the new application code
3. Monitor error rates and latency
4. Gradually increase traffic if healthy
5. Roll back if errors spike

### 6.3 Feature Flags for Database Changes

Wrap new schema usage behind feature flags:

```sql
-- Migration: add new column
ALTER TABLE users ADD COLUMN IF NOT EXISTS preferences JSONB;

-- Application code checks feature flag before using the column
-- This decouples deployment from release
```

---

## Key Takeaways

1. GitHub Actions service containers give you a real PostgreSQL instance in CI - no mocks needed
2. Pre-deployment safety checks catch dangerous patterns before they hit production
3. Post-deployment verification confirms migrations applied correctly
4. Schema diffs detect environment drift before it causes incidents
5. Always use `-v ON_ERROR_STOP=1` with psql in CI to fail fast on errors
6. Store schema dumps as CI artifacts for audit trails
7. Use path filters to only run database CI when relevant files change
