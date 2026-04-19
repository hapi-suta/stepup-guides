# Module 19 - USE 02: GitHub Actions Pipeline Exercise

## Objective

Write a complete GitHub Actions CI workflow that spins up a PostgreSQL service container, runs schema migrations, executes tests, and performs a schema diff check.

---

## Setup

You need a GitHub account and a repository. If you do not have one, create a new repo named `pg-ci-lab`.

Create the local project.

```bash
mkdir -p /opt/pgsql/pg-ci-lab
```

```bash
cd /opt/pgsql/pg-ci-lab
```

```bash
git init
```

---

## Exercise 1: Create Project Structure

```bash
mkdir -p .github/workflows
```

```bash
mkdir -p db/migrations
```

```bash
mkdir -p tests
```

---

## Exercise 2: Write Migration Scripts

Create V1 migration.

```bash
vi db/migrations/V1__create_users.sql
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

Create V2 migration.

```bash
vi db/migrations/V2__create_sessions.sql
```

```sql
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions (token);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions (expires_at);
```

---

## Exercise 3: Write Test Scripts

Create the schema test script.

```bash
vi tests/test_schema.sh
```

```bash
#!/bin/bash
set -e

DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/testdb}"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local query="$2"
    echo -n "  $name... "
    RESULT=$(psql "$DB_URL" -tAc "$query" 2>&1)
    if [ "$RESULT" = "t" ]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (got: $RESULT)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Schema Tests ==="

run_test "users table exists" \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users');"

run_test "sessions table exists" \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sessions');"

run_test "users.username is unique" \
    "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'users_username_key');"

run_test "sessions.token index exists" \
    "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_sessions_token');"

run_test "sessions has foreign key to users" \
    "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_type = 'FOREIGN KEY' AND table_name = 'sessions');"

run_test "insert and query user" \
    "INSERT INTO users (username, email) VALUES ('ci_test_user', 'ci@test.com') ON CONFLICT DO NOTHING; SELECT EXISTS (SELECT 1 FROM users WHERE username = 'ci_test_user');"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

```bash
chmod +x tests/test_schema.sh
```

Create the migration safety check.

```bash
vi tests/safety_check.sh
```

```bash
#!/bin/bash
set -e

MIGRATIONS_DIR="${1:-db/migrations}"
ERRORS=0

echo "=== Migration Safety Check ==="

for file in "$MIGRATIONS_DIR"/V*.sql; do
    [ -f "$file" ] || continue
    BASENAME=$(basename "$file")
    echo "Checking: $BASENAME"

    # No DROP TABLE without IF EXISTS
    if grep -iq "DROP TABLE " "$file"; then
        if ! grep -iq "DROP TABLE IF EXISTS" "$file"; then
            echo "  ERROR: DROP TABLE without IF EXISTS"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # No TRUNCATE
    if grep -iq "TRUNCATE" "$file"; then
        echo "  ERROR: TRUNCATE detected (data loss)"
        ERRORS=$((ERRORS + 1))
    fi

    # Warn on CREATE INDEX without CONCURRENTLY
    if grep -iq "CREATE INDEX " "$file"; then
        if ! grep -iq "CONCURRENTLY" "$file"; then
            echo "  WARNING: CREATE INDEX without CONCURRENTLY (locks table)"
        fi
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS error(s)"
    exit 1
fi

echo "All checks passed"
```

```bash
chmod +x tests/safety_check.sh
```

---

## Exercise 4: Write the GitHub Actions Workflow

This is the core deliverable.

```bash
vi .github/workflows/db-ci.yml
```

```yaml
name: Database CI

on:
  push:
    branches: [main]
    paths:
      - 'db/**'
      - 'tests/**'
      - '.github/workflows/db-ci.yml'
  pull_request:
    branches: [main]

jobs:
  database-ci:
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

      - name: Verify database connection
        run: |
          psql "$DATABASE_URL" -c "SELECT version();"

      - name: Run migration safety checks
        run: |
          chmod +x tests/safety_check.sh
          ./tests/safety_check.sh db/migrations

      - name: Apply migrations
        run: |
          for migration in db/migrations/V*.sql; do
            echo "Applying: $(basename $migration)"
            psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
          done

      - name: Run schema tests
        run: |
          chmod +x tests/test_schema.sh
          ./tests/test_schema.sh

      - name: Schema diff check
        run: |
          pg_dump --schema-only "$DATABASE_URL" > /tmp/current_schema.sql
          if [ -f "db/expected_schema.sql" ]; then
            echo "Comparing against expected schema..."
            if diff -u db/expected_schema.sql /tmp/current_schema.sql > /tmp/schema_diff.txt; then
              echo "PASS: Schemas match"
            else
              echo "WARNING: Schema differences detected"
              cat /tmp/schema_diff.txt
            fi
          else
            echo "No expected schema file found. Saving current as baseline."
            cat /tmp/current_schema.sql
          fi

      - name: Save schema artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: schema-dump
          path: /tmp/current_schema.sql
          retention-days: 14
```

---

## Exercise 5: Test Locally

If you have PostgreSQL running locally, you can test the workflow steps manually.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Create a test database.

```bash
createdb testdb
```

Exit the postgres user.

```bash
exit
```

Set the environment variable.

```bash
export DATABASE_URL="postgresql://postgres@localhost:5432/testdb"
```

Run the safety check.

```bash
/opt/pgsql/pg-ci-lab/tests/safety_check.sh /opt/pgsql/pg-ci-lab/db/migrations
```

Expected output (yours will differ):
```
=== Migration Safety Check ===
Checking: V1__create_users.sql
  WARNING: CREATE INDEX without CONCURRENTLY (locks table)
Checking: V2__create_sessions.sql
  WARNING: CREATE INDEX without CONCURRENTLY (locks table)
All checks passed
```

The warnings are expected - in CI we use regular CREATE INDEX because the tables are empty.

Run the migrations.

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
psql -d testdb -f /opt/pgsql/pg-ci-lab/db/migrations/V1__create_users.sql
```

```bash
psql -d testdb -f /opt/pgsql/pg-ci-lab/db/migrations/V2__create_sessions.sql
```

Exit the postgres user.

```bash
exit
```

Run the schema tests.

```bash
DATABASE_URL="postgresql://postgres@localhost:5432/testdb" /opt/pgsql/pg-ci-lab/tests/test_schema.sh
```

Expected output (yours will differ):
```
=== Schema Tests ===
  users table exists... PASS
  sessions table exists... PASS
  users.username is unique... PASS
  sessions.token index exists... PASS
  sessions has foreign key to users... PASS
  insert and query user... PASS

Results: 6 passed, 0 failed
```

---

## Exercise 6: Push to GitHub

Add the remote. Replace `YOUR_USERNAME` with your GitHub username.

```bash
cd /opt/pgsql/pg-ci-lab
```

```bash
git add .github/workflows/db-ci.yml db/migrations/V1__create_users.sql db/migrations/V2__create_sessions.sql tests/test_schema.sh tests/safety_check.sh
```

```bash
git commit -m "feat: add database CI pipeline with schema tests"
```

```bash
git remote add origin https://github.com/YOUR_USERNAME/pg-ci-lab.git
```

```bash
git push -u origin main
```

After pushing, go to the Actions tab in your GitHub repository. You should see the workflow running.

---

## Cleanup

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
dropdb testdb
```

Exit the postgres user.

```bash
exit
```

---

## Checklist

- [ ] Created .github/workflows/db-ci.yml with PostgreSQL service container
- [ ] Service container uses health checks to wait for PostgreSQL readiness
- [ ] Migrations run with -v ON_ERROR_STOP=1 for fail-fast behavior
- [ ] Safety check script catches dangerous migration patterns
- [ ] Schema tests verify tables, indexes, and constraints
- [ ] Schema dump saved as CI artifact
- [ ] Workflow triggers on relevant path changes only
- [ ] Tested locally before pushing
