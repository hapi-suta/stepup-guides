# Concepts: CI/CD for Database Changes

**Module 05 Reference Material**

---

## Migration Tool Comparison Table

| Feature | Flyway | Liquibase | Atlas | Bytebase | sqitch |
|---------|--------|-----------|-------|----------|--------|
| **Approach** | Imperative (SQL files) | Imperative (changesets) | Declarative (desired state) | Imperative + UI | Dependency graph |
| **Change format** | Plain SQL | XML, YAML, JSON, SQL | HCL or SQL | SQL | Plain SQL |
| **Rollback (free)** | No | Yes | Auto-generated | Yes | Required per change |
| **Tracking table** | `flyway_schema_history` | `databasechangelog` | `atlas_schema_revisions` | Internal | `sqitch.changes` |
| **Drift detection** | Checksum comparison | Full schema diff | Full schema diff | Full schema diff | Verify scripts |
| **CI/CD integration** | CLI, Docker, Maven, Gradle | CLI, Docker, Maven, Gradle | CLI, Docker, GitHub Actions | GitOps, webhooks | CLI |
| **Multi-database** | PostgreSQL, MySQL, Oracle, SQL Server, 20+ | PostgreSQL, MySQL, Oracle, SQL Server, 30+ | PostgreSQL, MySQL, MariaDB, SQLite | PostgreSQL, MySQL, Snowflake, others | PostgreSQL, MySQL, SQLite, Oracle, others |
| **Approval workflows** | External (GitHub PRs) | External (GitHub PRs) | External (GitHub PRs) | Built-in web UI | External |
| **SQL lint/review** | No | No | Yes (atlas lint) | Yes | No |
| **Pricing** | Community (free), Teams ($), Enterprise ($$) | Community (free), Pro ($$) | Community (free), Pro ($) | Community (free), Pro ($$) | Free (open source) |
| **Best for** | SQL-first teams | Enterprise multi-DB | Terraform/IaC teams | Large orgs needing UI governance | Dependency-aware teams |
| **Install (Mac)** | `brew install flyway` | `brew install liquibase` | `brew install ariga/tap/atlas` | Docker | `brew install sqitch` |

---

## GitHub Actions Workflow Anatomy

```
.github/workflows/migration-ci.yml
|
+-- name: "Database Migration CI"          # Workflow name (shown in GitHub UI)
|
+-- on:                                     # TRIGGERS - when does this run?
|   +-- push:
|   |   +-- branches: [main, develop]      # Which branches
|   |   +-- paths: ['migrations/**']       # Only when these files change
|   +-- pull_request:
|   |   +-- branches: [main]
|   +-- schedule:
|       +-- cron: '0 6 * * 1'             # Weekly Monday 6 AM (optional)
|
+-- jobs:                                   # JOBS - what work to do
    |
    +-- test-migrations:                    # Job name
    |   +-- runs-on: ubuntu-latest          # Runner (machine type)
    |   +-- services:                       # SERVICE CONTAINERS
    |   |   +-- postgres:                   # Temporary PostgreSQL for testing
    |   |       +-- image: postgres:16
    |   |       +-- env: POSTGRES_*
    |   |       +-- ports: [5432:5432]
    |   |       +-- options: --health-cmd   # Wait for PG to be ready
    |   +-- steps:                          # STEPS - sequential commands
    |       +-- uses: actions/checkout@v4   # Check out code
    |       +-- run: flyway migrate         # Apply migrations
    |       +-- run: psql -f validate.sql   # Verify schema
    |
    +-- deploy-staging:
    |   +-- needs: test-migrations          # Runs AFTER test passes
    |   +-- environment: staging            # GitHub Environment
    |
    +-- deploy-production:
        +-- needs: deploy-staging           # Runs AFTER staging succeeds
        +-- environment: production         # Has manual approval gate
```

### Trigger Types

| Trigger | Fires When | Use Case |
|---------|-----------|----------|
| `push` | Code pushed to branch | Deploy on merge to main |
| `pull_request` | PR opened/updated | Test before merging |
| `schedule` | Cron expression | Nightly drift detection |
| `workflow_dispatch` | Manual button click | On-demand deploy |
| `repository_dispatch` | External API call | Trigger from other systems |

---

## Zero-Downtime Migration Patterns Cheat Sheet

### Pattern 1: Add Column Safely

```sql
-- PG 11+: instant, no table rewrite
ALTER TABLE t ADD COLUMN new_col VARCHAR(100) DEFAULT 'value';
```

### Pattern 2: Add Index Without Blocking Writes

```sql
-- Must NOT be inside a transaction
CREATE INDEX CONCURRENTLY idx_name ON t (column);
```

### Pattern 3: Add Constraint Without Table Scan

```sql
-- Step 1: Add as NOT VALID (brief lock, no scan)
ALTER TABLE t ADD CONSTRAINT chk_name CHECK (col > 0) NOT VALID;

-- Step 2: Validate separately (weaker lock, allows reads/writes)
ALTER TABLE t VALIDATE CONSTRAINT chk_name;
```

### Pattern 4: Add NOT NULL Safely (PG 12+)

```sql
-- Step 1: Add CHECK constraint as NOT VALID
ALTER TABLE t ADD CONSTRAINT chk_col_nn CHECK (col IS NOT NULL) NOT VALID;

-- Step 2: Validate
ALTER TABLE t VALIDATE CONSTRAINT chk_col_nn;

-- Step 3: Set NOT NULL (PG sees the validated CHECK and skips the scan)
ALTER TABLE t ALTER COLUMN col SET NOT NULL;

-- Step 4: Drop the now-redundant CHECK
ALTER TABLE t DROP CONSTRAINT chk_col_nn;
```

### Pattern 5: Rename Column (Expand-Contract)

```sql
-- Migration 1: Add new column
ALTER TABLE t ADD COLUMN new_name VARCHAR(100);

-- Migration 2: Backfill in batches
UPDATE t SET new_name = old_name WHERE new_name IS NULL;

-- (Update application code to use new_name)

-- Migration 3: Drop old column
ALTER TABLE t DROP COLUMN old_name;
```

### Pattern 6: Change Column Type

```sql
-- Migration 1: Add new column with desired type
ALTER TABLE t ADD COLUMN col_new BIGINT;

-- Migration 2: Backfill
UPDATE t SET col_new = col_old::BIGINT WHERE col_new IS NULL;

-- Migration 3: Swap columns
ALTER TABLE t DROP COLUMN col_old;
ALTER TABLE t RENAME COLUMN col_new TO col_old;
```

### Pattern 7: Batched Backfill Template

```sql
DO $$
DECLARE
    batch_size INT := 10000;
    rows_updated INT := 1;
BEGIN
    WHILE rows_updated > 0 LOOP
        WITH batch AS (
            SELECT id FROM t WHERE new_col IS NULL LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        )
        UPDATE t SET new_col = compute_value(old_col)
        FROM batch WHERE t.id = batch.id;

        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        PERFORM pg_sleep(0.1);  -- breathe between batches
    END LOOP;
END $$;
```

### Safety Settings for Every Production Migration

```sql
SET lock_timeout = '5s';       -- Fail if lock not acquired in 5s
SET statement_timeout = '300s'; -- Fail if statement runs > 5 min
```

---

## Database CI/CD Pipeline Stages Reference

| Stage | Purpose | Tools | Who Approves |
|-------|---------|-------|-------------|
| **1. Lint** | Check SQL syntax and anti-patterns | atlas lint, sqlfluff, squawk | Automated |
| **2. Test (CI)** | Apply migrations to fresh database, run validation | Flyway + PG service container | Automated |
| **3. Diff Check** | Compare schema against expected state | atlas schema diff, liquibase diff | Automated |
| **4. Code Review** | Human review of migration SQL | GitHub PR review | DBA / Tech Lead |
| **5. Deploy Staging** | Apply to staging environment | Flyway migrate | Automated (after CI) |
| **6. Integration Test** | Run application tests against staging | App test suite | Automated |
| **7. Deploy Production** | Apply to production | Flyway migrate | DBA (manual approval) |
| **8. Verify** | Confirm schema matches expected state | flyway validate, smoke tests | Automated |
| **9. Monitor** | Watch for errors, lock issues, performance | pg_stat_activity, logs | Automated + DBA |

---

## Lock-Safe DDL Operations Table for PostgreSQL

| Operation | Lock Acquired | Blocks Reads? | Blocks Writes? | Table Rewrite? | Safe for Production? |
|-----------|--------------|---------------|----------------|---------------|---------------------|
| `CREATE TABLE` | None on existing tables | No | No | N/A | Yes |
| `DROP TABLE` | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | N/A | Yes (if no FKs) |
| `ADD COLUMN` (no default) | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Yes |
| `ADD COLUMN DEFAULT` (PG 11+) | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Yes |
| `ADD COLUMN DEFAULT` (PG <11) | `ACCESS EXCLUSIVE` | Yes (long) | Yes (long) | Yes | NO |
| `DROP COLUMN` | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Yes |
| `ALTER COLUMN TYPE` (same size) | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Maybe |
| `ALTER COLUMN TYPE` (rewrite) | `ACCESS EXCLUSIVE` | Yes (long) | Yes (long) | Yes | NO |
| `ALTER COLUMN SET NOT NULL` | `ACCESS EXCLUSIVE` | Yes | Yes | No | Use CHECK pattern |
| `ALTER COLUMN SET DEFAULT` | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Yes |
| `RENAME COLUMN` | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Use expand-contract |
| `CREATE INDEX` | `SHARE` | No | Yes (long) | N/A | NO |
| `CREATE INDEX CONCURRENTLY` | Weak | No | No | N/A | Yes |
| `DROP INDEX` | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | N/A | Yes |
| `DROP INDEX CONCURRENTLY` | Weak | No | No | N/A | Yes |
| `ADD CONSTRAINT` | `ACCESS EXCLUSIVE` | Yes | Yes | Scans table | NO |
| `ADD CONSTRAINT NOT VALID` | `ACCESS EXCLUSIVE` | Yes (brief) | Yes (brief) | No | Yes |
| `VALIDATE CONSTRAINT` | `SHARE UPDATE EXCLUSIVE` | No | No | Scans table | Yes |
| `ADD FOREIGN KEY` | `SHARE ROW EXCLUSIVE` on both | No | Yes (both tables) | Scans table | Use NOT VALID |
| `CREATE TRIGGER` | `SHARE ROW EXCLUSIVE` | No | Yes (brief) | No | Yes |

**Rule of thumb:** If an operation says "NO" in the safe column, use the corresponding safe pattern from the cheat sheet above.

---

## Quick Reference: Flyway Commands

| Command | Purpose | Safe for Production? |
|---------|---------|---------------------|
| `flyway migrate` | Apply pending migrations | Yes |
| `flyway info` | Show migration status | Yes (read-only) |
| `flyway validate` | Check migration checksums | Yes (read-only) |
| `flyway repair` | Fix failed migration entries | Use with caution |
| `flyway clean` | Drop all objects | NEVER in production |
| `flyway baseline` | Mark existing schema as baseline | One-time setup |
| `flyway undo` | Reverse last migration | Teams/Enterprise only |
