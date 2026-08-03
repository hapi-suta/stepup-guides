# BUILD 02: GitHub Actions for Database CI/CD

**Module 05: CI/CD for Database Changes**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to automate database migration testing and deployment using GitHub Actions - so every schema change is tested before it reaches production.

---

## What is CI/CD?

CI/CD stands for Continuous Integration and Continuous Deployment. Here is the DBA translation:

- **Continuous Integration (CI):** Every time someone pushes a schema change, an automated system tests it against a fresh database. If the migration breaks, the team knows immediately - before it ever touches staging or production.

- **Continuous Deployment (CD):** Once migrations pass CI, they are automatically deployed to dev, then staging, then production (with approval gates).

**DBA Analogy:** Imagine you have a robot DBA that, every time someone commits a new `.sql` file:
1. Spins up a fresh PostgreSQL instance
2. Applies all migrations from scratch
3. Runs validation queries to make sure nothing broke
4. Reports back PASS or FAIL

That is exactly what GitHub Actions gives you.

---

## Step 1: Understand GitHub Actions Concepts

Before writing workflows, you need to understand the building blocks:

| Concept | What It Is | DBA Analogy |
|---------|-----------|-------------|
| **Workflow** | An automated process defined in a YAML file | A runbook - a documented sequence of steps |
| **Trigger** | What starts the workflow (push, pull request, schedule) | An event trigger - like a cron job or a pgaudit event |
| **Job** | A set of steps that run on the same machine | A maintenance window task set |
| **Step** | A single command or action within a job | One command in your runbook |
| **Runner** | The machine that executes the job | The server where your maintenance script runs |
| **Action** | A reusable, pre-built step (from GitHub Marketplace) | A shared function you import into your script |
| **Service Container** | A Docker container that runs alongside your job | A temporary database instance for testing |
| **Secret** | An encrypted variable (passwords, API keys) | Environment variables in `.pgpass` |

---

## Step 2: Set Up a GitHub Repository

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/db-migrations
cd ~/dba-labs/db-migrations
git init
```

Expected output (yours will differ):
```
Initialized empty Git repository in /Users/you/dba-labs/db-migrations/.git/
```

Create the directory structure:

```bash
mkdir -p .github/workflows
mkdir -p migrations/sql
```

The `.github/workflows/` directory is where GitHub Actions looks for workflow definitions. Any `.yml` file in that directory is automatically recognized as a workflow.

---

## Step 3: Create Your Migration Files

Copy over migration files from BUILD 01, or create new ones.

**On your Mac terminal, in ~/dba-labs/db-migrations:**

```bash
vi migrations/sql/V1__create_users_table.sql
```

```sql
CREATE TABLE users (
    user_id     SERIAL PRIMARY KEY,
    username    VARCHAR(50) NOT NULL UNIQUE,
    email       VARCHAR(255) UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

```bash
vi migrations/sql/V2__create_products_table.sql
```

```sql
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    name         VARCHAR(200) NOT NULL,
    price        NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_name ON products (name);
```

```bash
vi migrations/sql/V3__create_orders_table.sql
```

```sql
CREATE TABLE orders (
    order_id     SERIAL PRIMARY KEY,
    user_id      INTEGER NOT NULL REFERENCES users(user_id),
    product_id   INTEGER NOT NULL REFERENCES products(product_id),
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    total_price  NUMERIC(10,2) NOT NULL,
    ordered_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_orders_ordered_at ON orders (ordered_at);
```

Create the Flyway configuration:

```bash
vi migrations/flyway.conf
```

```properties
flyway.url=jdbc:postgresql://localhost:5432/test_db
flyway.user=postgres
flyway.password=postgres
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
```

---

## Step 4: Create a Validation Script

This script runs after migrations to verify the schema is correct. Think of it as automated smoke tests for your DDL.

```bash
vi migrations/validate.sql
```

```sql
-- Validation queries: these should all succeed after migrations
-- If any fail, the CI pipeline fails

-- Check that all expected tables exist
DO $$
BEGIN
    ASSERT (SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_name IN ('users', 'products', 'orders')) = 3,
           'Expected 3 tables (users, products, orders)';

    -- Check users table has expected columns
    ASSERT (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_name = 'users'
            AND column_name IN ('user_id', 'username', 'email', 'created_at')) = 4,
           'users table missing expected columns';

    -- Check that foreign keys exist on orders
    ASSERT (SELECT COUNT(*) FROM information_schema.table_constraints
            WHERE table_name = 'orders'
            AND constraint_type = 'FOREIGN KEY') = 2,
           'orders table should have 2 foreign keys';

    -- Check that indexes exist
    ASSERT (SELECT COUNT(*) FROM pg_indexes
            WHERE tablename = 'orders'
            AND indexname LIKE 'idx_%') >= 2,
           'orders table should have at least 2 custom indexes';

    RAISE NOTICE 'All validations passed';
END $$;
```

---

## Step 5: Write Your First GitHub Actions Workflow

This is the core of the exercise. You will create a workflow that:
1. Triggers on every push and pull request
2. Starts a PostgreSQL service container (a temporary test database)
3. Runs Flyway migrations against it
4. Runs validation queries

**On your Mac terminal, in ~/dba-labs/db-migrations:**

```bash
vi .github/workflows/migration-ci.yml
```

```yaml
name: Database Migration CI

# When does this workflow run?
on:
  push:
    branches: [main, develop]
    paths:
      - 'migrations/**'      # Only run when migration files change
  pull_request:
    branches: [main]
    paths:
      - 'migrations/**'

jobs:
  test-migrations:
    name: Test Database Migrations
    runs-on: ubuntu-latest

    # Service containers: spin up a PostgreSQL instance for testing
    # This is like creating a temporary database server just for this test
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        ports:
          - 5432:5432
        # Health check: wait for PostgreSQL to be ready before running steps
        # Similar to pg_isready in your monitoring scripts
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    steps:
      # Step 1: Check out the repository code
      - name: Checkout code
        uses: actions/checkout@v4

      # Step 2: Install Flyway
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
          flyway --version

      # Step 3: Wait for PostgreSQL to be fully ready
      - name: Wait for PostgreSQL
        run: |
          until pg_isready -h localhost -p 5432 -U postgres; do
            echo "Waiting for PostgreSQL..."
            sleep 2
          done
          echo "PostgreSQL is ready"

      # Step 4: Run Flyway migrations
      - name: Run migrations
        working-directory: ./migrations
        run: |
          flyway -configFiles=flyway.conf info
          flyway -configFiles=flyway.conf migrate
          flyway -configFiles=flyway.conf info

      # Step 5: Validate the schema
      - name: Validate schema
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: test_db
        run: |
          psql -f migrations/validate.sql

      # Step 6: Run Flyway validate to check consistency
      - name: Flyway validate
        working-directory: ./migrations
        run: flyway -configFiles=flyway.conf validate
```

---

## Step 6: Understand the Workflow File

Let's break down each section:

### Triggers (`on:`)

```yaml
on:
  push:
    branches: [main, develop]
    paths:
      - 'migrations/**'
```

This workflow runs when:
- Code is pushed to `main` or `develop` branches
- A pull request targets `main`
- Only if files in the `migrations/` directory changed

**DBA Analogy:** This is like a trigger that fires only on specific tables (branches) and only for specific operations (migration file changes).

### Service Containers (`services:`)

```yaml
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: test_db
```

GitHub Actions starts a fresh PostgreSQL 16 container before your job runs. When the job finishes, the container is destroyed. Every CI run gets a clean database.

**DBA Analogy:** This is like `initdb` - you get a fresh cluster every time. No leftover data from previous runs.

### Health Checks (`options:`)

```yaml
options: >-
  --health-cmd="pg_isready -U postgres"
  --health-interval=10s
  --health-timeout=5s
  --health-retries=5
```

GitHub Actions polls PostgreSQL using `pg_isready` until it is accepting connections. This prevents your migration step from running before PostgreSQL is ready.

---

## Step 7: Environment Secrets for Database Credentials

Hardcoding passwords in `flyway.conf` is fine for a test database inside CI. But for deploying to real environments, you use GitHub Secrets.

**In your GitHub repository:**
1. Go to Settings > Secrets and variables > Actions
2. Click "New repository secret"
3. Add secrets:
   - `STAGING_DB_URL` = `jdbc:postgresql://staging-host:5432/myapp`
   - `STAGING_DB_USER` = `deploy_user`
   - `STAGING_DB_PASSWORD` = `(your password)`

**In your workflow, reference them with `${{ secrets.SECRET_NAME }}`:**

```yaml
- name: Run migrations on staging
  run: |
    flyway \
      -url="${{ secrets.STAGING_DB_URL }}" \
      -user="${{ secrets.STAGING_DB_USER }}" \
      -password="${{ secrets.STAGING_DB_PASSWORD }}" \
      -locations=filesystem:./migrations/sql \
      migrate
```

Secrets are encrypted at rest and masked in logs. If your password accidentally appears in output, GitHub replaces it with `***`.

---

## Step 8: Multi-Environment Pipeline

A real pipeline has multiple stages. Here is how you structure dev, staging, and production:

```bash
vi .github/workflows/migration-deploy.yml
```

```yaml
name: Database Migration Deploy

on:
  push:
    branches: [main]
    paths:
      - 'migrations/**'

jobs:
  # Job 1: Test against a fresh database
  test:
    name: Test Migrations
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Run migrations
        working-directory: ./migrations
        run: |
          flyway -configFiles=flyway.conf migrate
          flyway -configFiles=flyway.conf validate
      - name: Validate schema
        env:
          PGPASSWORD: postgres
        run: psql -h localhost -U postgres -d test_db -f migrations/validate.sql

  # Job 2: Deploy to staging (only if tests pass)
  deploy-staging:
    name: Deploy to Staging
    needs: test               # Wait for test job to succeed
    runs-on: ubuntu-latest
    environment: staging      # Ties to GitHub Environment settings
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Deploy to staging
        run: |
          flyway \
            -url="${{ secrets.STAGING_DB_URL }}" \
            -user="${{ secrets.STAGING_DB_USER }}" \
            -password="${{ secrets.STAGING_DB_PASSWORD }}" \
            -locations=filesystem:./migrations/sql \
            migrate

  # Job 3: Deploy to production (manual approval required)
  deploy-production:
    name: Deploy to Production
    needs: deploy-staging     # Wait for staging to succeed
    runs-on: ubuntu-latest
    environment: production   # Has manual approval configured
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Deploy to production
        run: |
          flyway \
            -url="${{ secrets.PROD_DB_URL }}" \
            -user="${{ secrets.PROD_DB_USER }}" \
            -password="${{ secrets.PROD_DB_PASSWORD }}" \
            -locations=filesystem:./migrations/sql \
            migrate
```

---

## Step 9: Manual Approval Gates

The `environment: production` line in the workflow ties to a GitHub Environment that you configure with protection rules.

**To set up manual approval:**

1. Go to your repository on GitHub
2. Navigate to Settings > Environments
3. Click "New environment" and name it `production`
4. Under "Environment protection rules," click "Required reviewers"
5. Add yourself (or the DBA team lead) as a required reviewer
6. Save

Now, when the pipeline reaches the production deployment job, it pauses and waits for you to click "Approve" in the GitHub Actions UI.

**DBA Analogy:** This is the equivalent of a DBA review gate. No DDL reaches production without a human clicking "approve." The CI pipeline handles the testing, but you make the final call.

---

## Step 10: Branch Protection Rules

To prevent anyone from pushing broken migrations directly to `main`, configure branch protection:

1. Go to Settings > Branches
2. Click "Add rule" for the `main` branch
3. Enable "Require status checks to pass before merging"
4. Select the "Test Migrations" job as a required check
5. Enable "Require pull request reviews before merging"
6. Save

Now the workflow is:

1. Developer creates a branch, adds a migration file
2. Opens a pull request to `main`
3. GitHub Actions automatically runs the migration CI test
4. If tests pass AND a reviewer approves, the PR can be merged
5. Merging to `main` triggers the deploy pipeline (staging, then production with approval)

---

## Step 11: Commit and Push

**On your Mac terminal, in ~/dba-labs/db-migrations:**

```bash
git add .
git commit -m "feat: add database migration CI/CD pipeline"
```

Create a GitHub repository and push:

```bash
gh repo create db-migrations --private --source=. --push
```

If you do not have the `gh` CLI, you can create the repository on GitHub's website and push manually:

```bash
git remote add origin git@github.com:YOUR_USERNAME/db-migrations.git
git branch -M main
git push -u origin main
```

After pushing, go to the Actions tab in your GitHub repository. You should see the workflow running (or queued).

---

## Step 12: Watch the Pipeline Run

Navigate to your repository on GitHub and click the **Actions** tab. You will see:

1. The workflow name: "Database Migration CI"
2. The trigger: push to main
3. The job: "Test Database Migrations"
4. Each step with a green checkmark (or red X if something failed)

Click into the job to see the logs for each step. You should see Flyway applying your migrations and the validation script confirming the schema.

---

## Step 13: Test the CI Pipeline with a New Migration

Create a new branch and add a migration:

```bash
git checkout -b feature/add-reviews-table
```

```bash
vi migrations/sql/V4__create_reviews_table.sql
```

```sql
CREATE TABLE reviews (
    review_id   SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(user_id),
    product_id  INTEGER NOT NULL REFERENCES products(product_id),
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_reviews_product_id ON reviews (product_id);
CREATE UNIQUE INDEX idx_reviews_user_product ON reviews (user_id, product_id);
```

Update the validation script to check for the new table:

```bash
vi migrations/validate.sql
```

Change the table count assertion from 3 to 4 and add `'reviews'` to the IN list.

Commit and push:

```bash
git add .
git commit -m "feat: add reviews table migration"
git push -u origin feature/add-reviews-table
```

Open a pull request on GitHub. The CI pipeline will automatically run against your new migration. If it passes, the PR shows a green check.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| CI/CD | Automated testing and deployment of schema changes |
| GitHub Actions | Workflow automation triggered by code events (push, PR) |
| Workflow file | YAML file in `.github/workflows/` defining triggers, jobs, and steps |
| Service containers | Temporary PostgreSQL instances spun up for CI testing |
| Health checks | Ensure PostgreSQL is ready before running migrations |
| Secrets | Encrypted variables for database credentials - never hardcode passwords |
| Multi-environment pipeline | test -> staging -> production with dependencies between jobs |
| Manual approval gates | GitHub Environments with required reviewers for production deploys |
| Branch protection | Require CI to pass before merging to main |
| Validation scripts | SQL assertions that verify schema correctness after migrations |

---

**Next:** BUILD 03 - Zero-Downtime Database Migrations - how to apply schema changes without locking your production tables.
