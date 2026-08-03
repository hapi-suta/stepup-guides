# BUILD 03: GitHub Actions Pipeline

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster
**Estimated Time:** 60-75 minutes

---

## What You Will Learn

How to automate database migration testing and deployment using GitHub Actions. By the end, you will have a working CI pipeline that lints, tests, and validates migrations on every pull request, plus a CD pipeline that deploys to staging and production with approval gates.

---

## Prerequisites

- Completed BUILD 01 and BUILD 02
- A GitHub account
- `git` and `gh` (GitHub CLI) installed on your Mac
- Migration files from BUILD 02

---

## What is CI/CD?

- **Continuous Integration (CI):** Every time someone pushes a schema change, an automated system tests it against a fresh database. If the migration breaks, the team knows before it reaches staging or production.
- **Continuous Deployment (CD):** Once migrations pass CI, they are deployed to dev, staging, and production - with approval gates before production.

---

## Step 1: Understand GitHub Actions Concepts

| Concept | What It Is |
|---------|-----------|
| **Workflow** | An automated process defined in a YAML file |
| **Trigger** | What starts the workflow (push, PR, schedule) |
| **Job** | A set of steps that run on the same machine |
| **Step** | A single command or action within a job |
| **Runner** | The machine that executes the job (GitHub-hosted or self-hosted) |
| **Action** | A reusable, pre-built step from GitHub Marketplace |
| **Service Container** | A Docker container running alongside your job (e.g., PostgreSQL) |
| **Secret** | An encrypted variable (passwords, API keys) |
| **Environment** | A deployment target with protection rules (e.g., production) |

---

## Step 2: Initialize the Git Repository

**On your Mac terminal:**

```bash
cd ~/dba-labs/aurora-migrations
```

```bash
git init
```

Expected output (yours will differ):
```
Initialized empty Git repository in /Users/you/dba-labs/aurora-migrations/.git/
```

Create the workflow directory:

```bash
mkdir -p .github/workflows
```

---

## Step 3: Write the CI Workflow

This workflow runs on every push and pull request. It spins up a fresh PostgreSQL container, applies all migrations, and validates the schema.

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

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
      - 'migrations/**'
  pull_request:
    branches: [main]
    paths:
      - 'migrations/**'

jobs:
  lint-migrations:
    name: Lint Migration Files
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Check for dangerous patterns in migration files
      - name: Check for CREATE INDEX without CONCURRENTLY
        run: |
          echo "Checking for unsafe CREATE INDEX statements..."
          if grep -rn "CREATE INDEX" migrations/sql/ \
            | grep -v "CONCURRENTLY" \
            | grep -v "^--" \
            | grep -v "flyway_schema_history" \
            | grep -v "IF NOT EXISTS" \
            | grep -v "\.sql:--"; then
            echo ""
            echo "FAIL: Found CREATE INDEX without CONCURRENTLY."
            echo "Use CREATE INDEX CONCURRENTLY to avoid blocking writes."
            exit 1
          fi
          echo "PASS: All CREATE INDEX statements use CONCURRENTLY or IF NOT EXISTS."

      # Check that every migration has lock_timeout
      - name: Check for lock_timeout
        run: |
          echo "Checking that versioned migrations include lock_timeout..."
          MISSING=""
          for f in migrations/sql/V*.sql; do
            if [ -f "$f" ] && ! grep -q "lock_timeout" "$f"; then
              MISSING="$MISSING $f"
            fi
          done
          if [ -n "$MISSING" ]; then
            echo "FAIL: These migrations are missing SET lock_timeout:"
            echo "$MISSING"
            exit 1
          fi
          echo "PASS: All versioned migrations include lock_timeout."

  test-migrations:
    name: Test Database Migrations
    needs: lint-migrations
    runs-on: ubuntu-latest

    # Spin up a PostgreSQL 16 container for testing
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
      - name: Checkout code
        uses: actions/checkout@v4

      # Install Flyway
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
          flyway --version

      # Wait for PostgreSQL to be fully ready
      - name: Wait for PostgreSQL
        run: |
          until pg_isready -h localhost -p 5432 -U postgres; do
            echo "Waiting for PostgreSQL..."
            sleep 2
          done
          echo "PostgreSQL is ready."

      # Show pending migrations
      - name: Flyway info (before)
        working-directory: ./migrations
        env:
          FLYWAY_PASSWORD: postgres
        run: |
          flyway \
            -url="jdbc:postgresql://localhost:5432/test_db" \
            -user=postgres \
            -password=postgres \
            -locations=filesystem:./sql \
            info

      # Apply all migrations from scratch
      - name: Run Flyway migrate
        working-directory: ./migrations
        run: |
          flyway \
            -url="jdbc:postgresql://localhost:5432/test_db" \
            -user=postgres \
            -password=postgres \
            -locations=filesystem:./sql \
            migrate

      # Show applied migrations
      - name: Flyway info (after)
        working-directory: ./migrations
        run: |
          flyway \
            -url="jdbc:postgresql://localhost:5432/test_db" \
            -user=postgres \
            -password=postgres \
            -locations=filesystem:./sql \
            info

      # Validate checksums
      - name: Flyway validate
        working-directory: ./migrations
        run: |
          flyway \
            -url="jdbc:postgresql://localhost:5432/test_db" \
            -user=postgres \
            -password=postgres \
            -locations=filesystem:./sql \
            validate

      # Run schema validation queries
      - name: Validate schema
        env:
          PGHOST: localhost
          PGPORT: "5432"
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: test_db
        run: |
          psql -f scripts/validate_schema.sql
```

---

## Step 4: Understand the Workflow File

### Triggers (`on:`)

```yaml
on:
  push:
    branches: [main, develop]
    paths:
      - 'migrations/**'
```

The workflow runs when:
- Code is pushed to `main` or `develop`
- A pull request targets `main`
- **Only** if files in `migrations/` changed (path filtering)

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

GitHub Actions starts a fresh PostgreSQL 16 container before the job runs. When the job finishes, the container is destroyed. Every CI run gets a clean database.

### Health Checks (`options:`)

```yaml
options: >-
  --health-cmd="pg_isready -U postgres"
  --health-interval=10s
  --health-timeout=5s
  --health-retries=5
```

GitHub Actions uses `pg_isready` to confirm PostgreSQL is accepting connections before running any steps. This prevents the migration step from running before the database is ready.

### Job Dependencies (`needs:`)

```yaml
test-migrations:
  needs: lint-migrations
```

The `test-migrations` job only runs if `lint-migrations` passes. If lint finds unsafe patterns, the entire pipeline stops.

---

## Step 5: Write the CD Workflow (Deploy Pipeline)

This workflow runs when code is merged to `main`. It deploys to staging automatically and to production with manual approval.

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

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
          flyway \
            -url="jdbc:postgresql://localhost:5432/test_db" \
            -user=postgres \
            -password=postgres \
            -locations=filesystem:./sql \
            migrate
      - name: Validate
        working-directory: ./migrations
        run: |
          flyway \
            -url="jdbc:postgresql://localhost:5432/test_db" \
            -user=postgres \
            -password=postgres \
            -locations=filesystem:./sql \
            validate
      - name: Schema checks
        env:
          PGPASSWORD: postgres
        run: psql -h localhost -U postgres -d test_db -f scripts/validate_schema.sql

  # Job 2: Deploy to staging (auto after test passes)
  deploy-staging:
    name: Deploy to Staging
    needs: test
    runs-on: ubuntu-latest
    environment: staging
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
            -cleanDisabled=true \
            info
          flyway \
            -url="${{ secrets.STAGING_DB_URL }}" \
            -user="${{ secrets.STAGING_DB_USER }}" \
            -password="${{ secrets.STAGING_DB_PASSWORD }}" \
            -locations=filesystem:./migrations/sql \
            -cleanDisabled=true \
            migrate

  # Job 3: Deploy to production (manual approval required)
  deploy-production:
    name: Deploy to Production
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Show pending migrations
        run: |
          flyway \
            -url="${{ secrets.PROD_DB_URL }}" \
            -user="${{ secrets.PROD_DB_USER }}" \
            -password="${{ secrets.PROD_DB_PASSWORD }}" \
            -locations=filesystem:./migrations/sql \
            -cleanDisabled=true \
            info
      - name: Deploy to production
        run: |
          flyway \
            -url="${{ secrets.PROD_DB_URL }}" \
            -user="${{ secrets.PROD_DB_USER }}" \
            -password="${{ secrets.PROD_DB_PASSWORD }}" \
            -locations=filesystem:./migrations/sql \
            -cleanDisabled=true \
            migrate
      - name: Validate production
        run: |
          flyway \
            -url="${{ secrets.PROD_DB_URL }}" \
            -user="${{ secrets.PROD_DB_USER }}" \
            -password="${{ secrets.PROD_DB_PASSWORD }}" \
            -locations=filesystem:./migrations/sql \
            -cleanDisabled=true \
            validate
```

---

## Step 6: Configure GitHub Secrets

Database credentials must never appear in workflow files. Use GitHub Secrets.

**In your GitHub repository:**

1. Go to Settings > Secrets and variables > Actions
2. Click "New repository secret"
3. Add these secrets:

| Secret Name | Value |
|------------|-------|
| `STAGING_DB_URL` | `jdbc:postgresql://your-aurora-endpoint:5432/cicd_staging` |
| `STAGING_DB_USER` | `flyway_user` |
| `STAGING_DB_PASSWORD` | Your staging password |
| `PROD_DB_URL` | `jdbc:postgresql://your-aurora-endpoint:5432/cicd_prod` |
| `PROD_DB_USER` | `flyway_user` |
| `PROD_DB_PASSWORD` | Your production password |

Secrets are encrypted at rest, injected as environment variables at runtime, and masked in logs. If a secret value accidentally appears in output, GitHub replaces it with `***`.

---

## Step 7: Configure Manual Approval for Production

**In your GitHub repository:**

1. Go to Settings > Environments
2. Click "New environment" and name it `production`
3. Under "Environment protection rules," click "Required reviewers"
4. Add yourself (or the DBA team) as a required reviewer
5. Click "Save protection rules"

Now, when the pipeline reaches the `deploy-production` job, it pauses and waits for you to click "Approve" in the GitHub Actions UI.

Optionally, create a `staging` environment too (without required reviewers) to track staging deployments.

---

## Step 8: Configure Branch Protection

Prevent anyone from pushing broken migrations directly to `main`.

**In your GitHub repository:**

1. Go to Settings > Branches (under Code and automation)
2. Click "Add branch protection rule"
3. Branch name pattern: `main`
4. Enable "Require status checks to pass before merging"
5. Search for and select the "Test Database Migrations" job
6. Enable "Require pull request reviews before merging"
7. Click "Create"

The enforced workflow is now:

1. Developer creates a branch and adds a migration file
2. Opens a pull request to `main`
3. GitHub Actions automatically runs the lint + test CI pipeline
4. If tests pass AND a reviewer approves, the PR can be merged
5. Merging to `main` triggers the deploy pipeline (staging auto, production with approval)

---

## Step 9: Commit and Push

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

```bash
git add migrations/sql/ migrations/flyway.conf.template scripts/ .github/workflows/ .gitignore
```

```bash
git commit -m "feat: add database migration CI/CD pipeline"
```

Create a GitHub repository and push:

```bash
gh repo create aurora-migrations --private --source=. --push
```

- `gh repo create` - creates a new repository on GitHub.
- `--private` - makes the repository private.
- `--source=.` - uses the current directory as the source.
- `--push` - pushes the code after creating the repository.

If you do not have `gh` installed, create the repository on GitHub's website and push manually:

```bash
git remote add origin git@github.com:YOUR_USERNAME/aurora-migrations.git
```

```bash
git branch -M main
```

```bash
git push -u origin main
```

After pushing, go to the Actions tab in your GitHub repository. You should see the workflow running.

---

## Step 10: Test the Pipeline with a New Migration

Create a new branch and add a migration.

**On your Mac terminal, in ~/dba-labs/aurora-migrations:**

```bash
git checkout -b feature/add-reviews-table
```

```bash
vi migrations/sql/V4__create_reviews_table.sql
```

```sql
-- V4: Product reviews
SET lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS reviews (
    review_id   SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
    product_id  INTEGER NOT NULL REFERENCES products(product_id),
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title       VARCHAR(200),
    body        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reviews_product_id ON reviews (product_id);
CREATE INDEX IF NOT EXISTS idx_reviews_customer_id ON reviews (customer_id);
```

Commit and push:

```bash
git add migrations/sql/V4__create_reviews_table.sql
```

```bash
git commit -m "feat: add reviews table migration"
```

```bash
git push -u origin feature/add-reviews-table
```

Open a pull request:

```bash
gh pr create --title "Add reviews table" --body "Adds V4 migration for product reviews table with indexes on product_id and customer_id."
```

Go to the Actions tab. The CI pipeline automatically runs:

1. **Lint** - checks for unsafe patterns
2. **Test** - applies all four migrations to a fresh PostgreSQL container
3. **Validate** - runs schema validation queries

If everything passes, the PR shows a green checkmark. A reviewer can then approve and merge.

---

## Step 11: Watch the Pipeline Run

Navigate to your repository on GitHub and click the **Actions** tab. You will see:

1. The workflow name: "Database Migration CI"
2. The trigger: push to feature branch
3. Two jobs: "Lint Migration Files" and "Test Database Migrations"
4. Each step with a green checkmark (or red X if something failed)

Click into the "Test Database Migrations" job to see the logs for each step. You should see Flyway applying your migrations and the validation script confirming the schema.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| CI pipeline | Lint + test migrations on every push and PR |
| CD pipeline | Test -> staging (auto) -> production (manual approval) |
| Workflow file | YAML in `.github/workflows/` defining triggers, jobs, and steps |
| Service containers | Temporary PostgreSQL instances for CI testing |
| Health checks | `pg_isready` ensures database is ready before migrations run |
| Path filtering | Only trigger pipeline when migration files change |
| Lint step | Catch unsafe DDL patterns (missing CONCURRENTLY, missing lock_timeout) |
| Secrets | Encrypted variables for database credentials |
| Environments | GitHub Environments with required reviewers for production |
| Branch protection | Require CI pass + PR review before merging to main |

---

**Next:** [BUILD 04: Zero-Downtime Migrations](04-zero-downtime-migrations.md) - how to apply schema changes without locking your production tables.
