# SURVIVE 02: CI Pipeline Broken - Runbook

## Symptom

The database CI pipeline fails on every push. Migrations cannot connect to the PostgreSQL service container. The error looks like "could not connect to server: Connection refused."

---

## Step 1: Read the Error Message

In a real CI failure, the GitHub Actions log would show something like:

```
psql: error: connection to server at "localhost" (127.0.0.1), port 5433 failed: Connection refused
    Is the server running on that host and accepting TCP/IP connections?
```

The key detail: **port 5433**. PostgreSQL service containers run on 5432 by default.

---

## Step 2: Examine the Workflow File

```bash
cat -n /tmp/ci-broken-lab/.github/workflows/db-ci.yml
```

Look at the `env` section. Find the DATABASE_URL.

The bug: The port in DATABASE_URL is `5433` but the service container exposes port `5432`.

---

## Step 3: Fix the Workflow

Open the workflow file.

```bash
vi /tmp/ci-broken-lab/.github/workflows/db-ci.yml
```

Find this line:

```yaml
      DATABASE_URL: postgresql://postgres:postgres@localhost:5433/testdb
```

Change `5433` to `5432`:

```yaml
      DATABASE_URL: postgresql://postgres:postgres@localhost:5432/testdb
```

Save and exit.

---

## Step 4: Examine the Test Script

```bash
cat -n /tmp/ci-broken-lab/tests/test_schema.sh
```

Look at the fallback DATABASE_URL.

The bug: The fallback URL uses database name `test_db` (with underscore) but the service container creates `testdb` (no underscore).

---

## Step 5: Fix the Test Script

```bash
vi /tmp/ci-broken-lab/tests/test_schema.sh
```

Find this line:

```bash
DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/test_db}"
```

Change `test_db` to `testdb`:

```bash
DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/testdb}"
```

Save and exit.

---

## Step 6: Test Locally

Create a local test database to verify the fixes work.

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
createdb testdb
```

Exit the postgres user.

```bash
exit
```

Run the migration.

```bash
sudo -iu postgres psql -d testdb -f /tmp/ci-broken-lab/db/migrations/V1__create_users.sql
```

Run the test script.

```bash
DATABASE_URL="postgresql://postgres@localhost:5432/testdb" /tmp/ci-broken-lab/tests/test_schema.sh
```

Expected output:
```
=== Schema Tests ===
users table exists... PASS
```

---

## Prevention

1. Never hardcode connection details - always use the environment variable
2. Make sure fallback URLs in test scripts match the CI service container settings
3. Use a shared .env.ci file that both the workflow and test scripts reference
4. Add a "verify database connection" step early in the pipeline to catch connection issues before running migrations
5. Log the DATABASE_URL (with password masked) at the start of CI runs for debugging
