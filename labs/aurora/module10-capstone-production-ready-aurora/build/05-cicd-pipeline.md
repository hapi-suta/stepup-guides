# Module 10 - Build Guide 05: CI/CD Pipeline for Schema Migrations

**Objective:** Build a GitHub Actions pipeline that applies version-controlled schema migrations to your Aurora cluster using Flyway. Include staging validation, production approval gates, rollback procedures, and Slack notifications.
**Time:** 45 minutes
**Level:** Senior / Staff
**Prerequisites:** Build Guide 03 completed (Aurora cluster deployed). GitHub account. Flyway CLI installed locally (for testing).

---

## 1. Set Up the Migration Repository

Create a dedicated repository for database migrations.

**On your local workstation:**

```bash
mkdir -p ~/capstone-aurora/db-migrations
```

```bash
cd ~/capstone-aurora/db-migrations
```

```bash
git init
```

Create the directory structure:

```bash
mkdir -p migrations/versioned migrations/undo .github/workflows scripts
```

- `migrations/versioned/` - Forward migration SQL files (V001__, V002__, etc.)
- `migrations/undo/` - Rollback SQL files (U001__, U002__, etc.)
- `.github/workflows/` - GitHub Actions workflow files
- `scripts/` - Helper scripts for validation and smoke tests

---

## 2. Create Migration Files

### 2.1 First Migration: Create Application Schema

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/migrations/versioned/V001__create_app_schema.sql
```

Add this content:

```sql
-- V001: Create application schema and core tables
-- Author: [YOUR NAME]
-- Date: 2026-06-09
-- Description: Sets up the application schema with users and audit tables.

-- Create a dedicated schema for the application.
-- Keeps application tables separate from public schema.
CREATE SCHEMA IF NOT EXISTS app;

-- Users table: stores application user accounts
CREATE TABLE IF NOT EXISTS app.users (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email           TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    password_hash   TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_email_unique UNIQUE (email)
);

-- Index on email for login lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON app.users (email);

-- Index on created_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_users_created_at ON app.users (created_at);

-- Audit log table: records all significant user actions
CREATE TABLE IF NOT EXISTS app.audit_log (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id         BIGINT REFERENCES app.users(id),
    action          TEXT NOT NULL,
    resource_type   TEXT NOT NULL,
    resource_id     TEXT,
    details         JSONB,
    ip_address      INET,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index on user_id for per-user audit queries
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON app.audit_log (user_id);

-- Index on created_at for time-range queries
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON app.audit_log (created_at);

-- Partition-friendly index on action type
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON app.audit_log (action);

-- Grant usage to the application role (create this role separately)
-- The application should NEVER use the master/admin user.
```

### 2.2 Undo Migration for V001

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/migrations/undo/U001__drop_app_schema.sql
```

Add this content:

```sql
-- U001: Undo V001 - Drop application schema and tables
-- WARNING: This destroys all data in the app schema

DROP TABLE IF EXISTS app.audit_log CASCADE;
DROP TABLE IF EXISTS app.users CASCADE;
DROP SCHEMA IF EXISTS app CASCADE;
```

### 2.3 Second Migration: Add Application Role

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/migrations/versioned/V002__create_app_role.sql
```

Add this content:

```sql
-- V002: Create application database role
-- Author: [YOUR NAME]
-- Date: 2026-06-09
-- Description: Creates a least-privilege role for the application.

-- Create the application role with login capability.
-- This role can only access the app schema - not public or pg_catalog.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_service') THEN
        CREATE ROLE app_service WITH LOGIN;
    END IF;
END
$$;

-- Grant schema usage
GRANT USAGE ON SCHEMA app TO app_service;

-- Grant table-level privileges (SELECT, INSERT, UPDATE, DELETE)
-- No TRUNCATE, no DROP, no ALTER
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_service;

-- Grant sequence usage (needed for GENERATED ALWAYS AS IDENTITY)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO app_service;

-- Set default privileges so future tables in app schema get the same grants
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT USAGE ON SEQUENCES TO app_service;
```

---

## 3. Create the Flyway Configuration

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/flyway.toml
```

Add this content:

```toml
[environments.staging]
url = "jdbc:postgresql://${STAGING_DB_HOST}:5432/postgres?sslmode=require"
user = "${DB_USER}"
password = "${DB_PASSWORD}"
schemas = ["app"]
connectRetries = 3
connectRetriesInterval = 5
lockRetryCount = 10

[environments.production]
url = "jdbc:postgresql://${PRODUCTION_DB_HOST}:5432/postgres?sslmode=require"
user = "${DB_USER}"
password = "${DB_PASSWORD}"
schemas = ["app"]
connectRetries = 3
connectRetriesInterval = 5
lockRetryCount = 10

[flyway]
locations = ["filesystem:migrations/versioned"]
undoLocations = ["filesystem:migrations/undo"]
baselineOnMigrate = true
outOfOrder = false
validateOnMigrate = true
cleanDisabled = true
```

Key settings:
- `sslmode=require` - Enforces SSL for all connections
- `connectRetries = 3` - Retries if the database is temporarily unreachable (e.g., during failover)
- `lockRetryCount = 10` - Retries if another migration is already running
- `cleanDisabled = true` - Prevents accidental `flyway clean` (which would DROP all tables)
- `outOfOrder = false` - Migrations must be applied in version order

---

## 4. Create Validation Script

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/scripts/validate-migration.sh
```

Add this content:

```bash
#!/usr/bin/env bash
# Validates that the migration was applied correctly.
# Usage: bash scripts/validate-migration.sh <db-host> <db-user> <db-password>

set -euo pipefail

DB_HOST="${1:?Usage: validate-migration.sh <db-host> <db-user> <db-password>}"
DB_USER="${2:?Usage: validate-migration.sh <db-host> <db-user> <db-password>}"
DB_PASSWORD="${3:?Usage: validate-migration.sh <db-host> <db-user> <db-password>}"

PASS=0
FAIL=0

check() {
  local description="$1"
  local result="$2"
  if [[ "$result" == "PASS" ]]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

echo "Running post-migration validation..."
echo ""

# Check 1: app schema exists
SCHEMA_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
  "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'app');" 2>/dev/null)
if [[ "$SCHEMA_EXISTS" == "t" ]]; then
  check "app schema exists" "PASS"
else
  check "app schema exists" "FAIL"
fi

# Check 2: users table exists
USERS_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
  "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'users');" 2>/dev/null)
if [[ "$USERS_EXISTS" == "t" ]]; then
  check "app.users table exists" "PASS"
else
  check "app.users table exists" "FAIL"
fi

# Check 3: audit_log table exists
AUDIT_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
  "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'audit_log');" 2>/dev/null)
if [[ "$AUDIT_EXISTS" == "t" ]]; then
  check "app.audit_log table exists" "PASS"
else
  check "app.audit_log table exists" "FAIL"
fi

# Check 4: flyway schema history is current
FLYWAY_VERSION=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
  "SELECT version FROM flyway_schema_history WHERE success = true ORDER BY installed_rank DESC LIMIT 1;" 2>/dev/null)
if [[ -n "$FLYWAY_VERSION" ]]; then
  check "Flyway version: $FLYWAY_VERSION" "PASS"
else
  check "Flyway schema history check" "FAIL"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
```

Make it executable:

```bash
chmod +x ~/capstone-aurora/db-migrations/scripts/validate-migration.sh
```

---

## 5. Create the GitHub Actions Workflow

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/.github/workflows/migrate.yml
```

Add this content:

```yaml
name: Database Migration

on:
  push:
    branches: [main]
    paths:
      - 'migrations/**'
  pull_request:
    branches: [main]
    paths:
      - 'migrations/**'

permissions:
  id-token: write
  contents: read

env:
  AWS_REGION: us-east-1

jobs:
  # ---------------------------------------------------------------
  # Job 1: Lint and validate SQL files
  # ---------------------------------------------------------------
  lint:
    name: Lint SQL
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install sqlfluff
        run: pip install sqlfluff

      - name: Lint migration files
        run: |
          sqlfluff lint migrations/versioned/ \
            --dialect postgres \
            --rules L001,L002,L003,L010,L014

  # ---------------------------------------------------------------
  # Job 2: Dry-run against staging
  # ---------------------------------------------------------------
  staging:
    name: Apply to Staging
    needs: lint
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Get staging database credentials
        id: db-creds
        run: |
          SECRET=$(aws secretsmanager get-secret-value \
            --secret-id ${{ secrets.STAGING_SECRET_ARN }} \
            --query SecretString --output text)
          echo "DB_USER=$(echo $SECRET | jq -r .username)" >> $GITHUB_OUTPUT
          echo "DB_PASSWORD=$(echo $SECRET | jq -r .password)" >> $GITHUB_OUTPUT

      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.0.0/flyway-commandline-10.0.0-linux-x64.tar.gz | tar xz
          echo "$PWD/flyway-10.0.0" >> $GITHUB_PATH

      - name: Run Flyway info (show pending migrations)
        env:
          STAGING_DB_HOST: ${{ secrets.STAGING_DB_HOST }}
          DB_USER: ${{ steps.db-creds.outputs.DB_USER }}
          DB_PASSWORD: ${{ steps.db-creds.outputs.DB_PASSWORD }}
        run: |
          flyway -environment=staging info

      - name: Apply migrations to staging
        env:
          STAGING_DB_HOST: ${{ secrets.STAGING_DB_HOST }}
          DB_USER: ${{ steps.db-creds.outputs.DB_USER }}
          DB_PASSWORD: ${{ steps.db-creds.outputs.DB_PASSWORD }}
        run: |
          flyway -environment=staging migrate

      - name: Validate migration
        env:
          DB_HOST: ${{ secrets.STAGING_DB_HOST }}
          DB_USER: ${{ steps.db-creds.outputs.DB_USER }}
          DB_PASSWORD: ${{ steps.db-creds.outputs.DB_PASSWORD }}
        run: |
          bash scripts/validate-migration.sh "$DB_HOST" "$DB_USER" "$DB_PASSWORD"

  # ---------------------------------------------------------------
  # Job 3: Apply to production (manual approval required)
  # ---------------------------------------------------------------
  production:
    name: Apply to Production
    needs: staging
    runs-on: ubuntu-latest
    environment:
      name: production
      # This environment must have "Required reviewers" configured
      # in GitHub Settings > Environments > production

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Take pre-migration snapshot
        run: |
          SNAPSHOT_ID="pre-migration-$(date +%Y%m%d-%H%M%S)"
          aws rds create-db-cluster-snapshot \
            --db-cluster-identifier devops-lab-cluster \
            --db-cluster-snapshot-identifier "$SNAPSHOT_ID"
          echo "Waiting for snapshot $SNAPSHOT_ID to complete..."
          aws rds wait db-cluster-snapshot-available \
            --db-cluster-snapshot-identifier "$SNAPSHOT_ID"
          echo "Snapshot $SNAPSHOT_ID is available"

      - name: Get production database credentials
        id: db-creds
        run: |
          SECRET=$(aws secretsmanager get-secret-value \
            --secret-id ${{ secrets.PRODUCTION_SECRET_ARN }} \
            --query SecretString --output text)
          echo "DB_USER=$(echo $SECRET | jq -r .username)" >> $GITHUB_OUTPUT
          echo "DB_PASSWORD=$(echo $SECRET | jq -r .password)" >> $GITHUB_OUTPUT

      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.0.0/flyway-commandline-10.0.0-linux-x64.tar.gz | tar xz
          echo "$PWD/flyway-10.0.0" >> $GITHUB_PATH

      - name: Apply migrations to production
        env:
          PRODUCTION_DB_HOST: ${{ secrets.PRODUCTION_DB_HOST }}
          DB_USER: ${{ steps.db-creds.outputs.DB_USER }}
          DB_PASSWORD: ${{ steps.db-creds.outputs.DB_PASSWORD }}
        run: |
          flyway -environment=production \
            -lockRetryCount=10 \
            migrate

      - name: Validate migration
        env:
          DB_HOST: ${{ secrets.PRODUCTION_DB_HOST }}
          DB_USER: ${{ steps.db-creds.outputs.DB_USER }}
          DB_PASSWORD: ${{ steps.db-creds.outputs.DB_PASSWORD }}
        run: |
          bash scripts/validate-migration.sh "$DB_HOST" "$DB_USER" "$DB_PASSWORD"

      - name: Post-migration notification
        if: always()
        run: |
          STATUS="${{ job.status }}"
          if [[ "$STATUS" == "success" ]]; then
            echo "Migration applied successfully to production"
          else
            echo "WARNING: Migration failed or was cancelled"
            echo "Pre-migration snapshot is available for rollback"
          fi
```

---

## 6. Configure GitHub Environments

This step is done in the GitHub web UI.

### 6.1 Create the Staging Environment

1. Go to your repository on GitHub.
2. Click **Settings** > **Environments**.
3. Click **New environment**.
4. Name it `staging`.
5. Click **Configure environment**.
6. No protection rules needed for staging.
7. Add these secrets:
   - `AWS_ROLE_ARN` - The GitHub Actions IAM role ARN from Build 02
   - `STAGING_DB_HOST` - The staging cluster endpoint
   - `STAGING_SECRET_ARN` - The Secrets Manager ARN for staging

### 6.2 Create the Production Environment

1. Click **New environment**.
2. Name it `production`.
3. Click **Configure environment**.
4. Under **Environment protection rules**, enable **Required reviewers**.
5. Add yourself (and your DBA team) as required reviewers.
6. Add these secrets:
   - `AWS_ROLE_ARN` - Same role ARN
   - `PRODUCTION_DB_HOST` - The production cluster endpoint
   - `PRODUCTION_SECRET_ARN` - The production Secrets Manager ARN

The required reviewers gate means the production job will pause and wait for manual approval before applying migrations.

---

## 7. Create the .gitignore

**On your local workstation:**

```bash
vi ~/capstone-aurora/db-migrations/.gitignore
```

Add this content:

```
# Never commit credentials
*.env
flyway.conf

# Flyway local state
report.html
report.json

# OS files
.DS_Store
```

---

## 8. Test Locally

Before pushing to GitHub, test the migration locally against your cluster.

**On your local workstation:**

If you have Flyway installed locally and network access to the cluster (via bastion tunnel):

```bash
cd ~/capstone-aurora/db-migrations
```

```bash
export STAGING_DB_HOST="devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com"
export DB_USER="dbadmin"
export DB_PASSWORD="your-password-from-secrets-manager"
```

Run Flyway info to see pending migrations:

```bash
flyway -environment=staging info
```

Expected output (yours will differ):
```
+-----------+---------+---------------------+------+---------+
| Category  | Version | Description         | Type | State   |
+-----------+---------+---------------------+------+---------+
| Versioned | 001     | create app schema   | SQL  | Pending |
| Versioned | 002     | create app role     | SQL  | Pending |
+-----------+---------+---------------------+------+---------+
```

Apply the migrations:

```bash
flyway -environment=staging migrate
```

Expected output (yours will differ):
```
Successfully applied 2 migrations to schema "app" (execution time 00:01.234s)
```

Run the validation script:

```bash
bash scripts/validate-migration.sh "$STAGING_DB_HOST" "$DB_USER" "$DB_PASSWORD"
```

Expected output (yours will differ):
```
Running post-migration validation...

  PASS: app schema exists
  PASS: app.users table exists
  PASS: app.audit_log table exists
  PASS: Flyway version: 002

Results: 4 passed, 0 failed
```

---

## 9. Rollback Procedure

If a migration causes problems in production, follow this rollback procedure.

### Option 1: Flyway Undo (for reversible migrations)

**On your local workstation:**

```bash
flyway -environment=production undo
```

This applies the corresponding U00X file to reverse the last migration.

### Option 2: Restore from Pre-Migration Snapshot

If the undo migration does not fix the issue, restore from the snapshot the pipeline created:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type manual \
  --query 'DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier, `pre-migration`)].[DBClusterSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

Restore from the most recent pre-migration snapshot:

```bash
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier devops-lab-cluster-restored \
  --snapshot-identifier pre-migration-20260609-120000 \
  --engine aurora-postgresql \
  --db-subnet-group-name devops-lab-db-subnet-group \
  --vpc-security-group-ids sg-0abc123def456789
```

After the restored cluster is available, update your application connection string.

---

## Summary

You have built a complete CI/CD pipeline for database schema migrations:

- **Version-controlled migrations** with Flyway (forward + undo files)
- **SQL linting** catches syntax issues before they reach any environment
- **Staging validation** runs automatically on push to main
- **Production approval gate** requires manual review before applying
- **Pre-migration snapshots** provide a safety net for rollback
- **Post-migration validation** verifies the migration was applied correctly
- **OIDC authentication** - no long-lived AWS credentials in GitHub secrets

The pipeline ensures that every schema change is reviewed, tested in staging, approved by a human, backed up before applying, and validated after applying.

**Next:** [Build 06 - Backup and DR](./06-backup-and-dr.md)
