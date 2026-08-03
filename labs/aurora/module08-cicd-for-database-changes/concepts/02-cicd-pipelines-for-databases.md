# Concepts: CI/CD Pipelines for Databases

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Why Databases Need Their Own Pipeline

Application CI/CD deploys code that can be rolled back in seconds - you redeploy the previous version and the old code is running again. Database CI/CD is fundamentally different because:

1. **Schema changes are stateful** - You cannot "redeploy" the previous schema version. If you added a column, it exists. If you dropped a table, the data is gone.
2. **Migrations must be ordered** - Application deployments are independent. Database migrations depend on each other (V3 cannot run before V2).
3. **Data is permanent** - A bad application deploy loses zero data. A bad migration can lose data permanently.
4. **Locks affect availability** - Running DDL on a production table can block all queries on that table.
5. **Rollback is not free** - Undoing a column addition means dropping the column and losing all data in it.

Because of these differences, database pipelines need additional stages that application pipelines do not: lock analysis, schema validation, approval gates, and pre-migration snapshots.

---

## Pipeline Architecture

A database CI/CD pipeline has nine stages. Not every migration needs all nine, but a production deployment should pass through most of them.

### Stage 1: Lint

**Purpose:** Catch syntax errors and dangerous patterns before a human even looks at the migration.

**What it checks:**
- SQL syntax is valid
- No `CREATE INDEX` without `CONCURRENTLY` on existing tables
- No `ALTER TABLE ... ALTER COLUMN TYPE` that would rewrite large tables
- Every migration includes `SET lock_timeout`
- No hardcoded passwords or connection strings

**Tools:**
- `sqlfluff` - SQL linter with configurable rules
- `squawk` - PostgreSQL-specific migration linter
- `atlas lint` - Atlas's built-in migration linter
- Custom grep/bash scripts in CI

**Example lint rule (bash):**

```bash
# Fail if any migration uses CREATE INDEX without CONCURRENTLY
if grep -rn "CREATE INDEX" migrations/sql/ | grep -v "CONCURRENTLY" | grep -v "^--" | grep -v "flyway_schema_history"; then
    echo "FAIL: Found CREATE INDEX without CONCURRENTLY"
    echo "Use CREATE INDEX CONCURRENTLY to avoid blocking writes."
    exit 1
fi
```

### Stage 2: Test (CI)

**Purpose:** Apply all migrations from scratch against a fresh database and verify the resulting schema.

**How it works:**
1. GitHub Actions spins up a PostgreSQL 16 service container (empty database)
2. Flyway applies all migrations from V1 to the latest
3. Validation queries check that all expected tables, indexes, and constraints exist
4. `flyway validate` confirms migration checksums match

**Why fresh database:** Testing against a fresh database catches ordering bugs. If V4 depends on a table from V3, and you accidentally named V3 as V5, the fresh-database test fails immediately.

**Service container definition (GitHub Actions):**

```yaml
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
```

This creates a temporary PostgreSQL instance that is destroyed after the job finishes. Every CI run gets a clean database.

### Stage 3: Diff Check

**Purpose:** Compare the resulting schema against the expected state to catch drift or unexpected changes.

**Tools:**
- `atlas schema diff` - Compares two schemas and shows differences
- `liquibase diff` - Compares two databases
- `pg_dump --schema-only` + `diff` - Quick manual check

**When this matters:** If someone manually ran DDL on staging (bypassing the pipeline), the diff check catches it. The migration might apply cleanly, but the resulting schema does not match what you expect.

### Stage 4: Code Review

**Purpose:** A human reviews the migration SQL before it can be merged.

**What the reviewer checks:**

| Check | Why It Matters |
|-------|---------------|
| Lock impact | Will this lock a table? For how long? |
| Index strategy | Is CONCURRENTLY used? Is the index needed? |
| Backward compatibility | Can the current app version still work? |
| Data safety | Does any DML risk losing data? |
| Rollback plan | What if this fails halfway? |
| Naming conventions | Does the file name follow Flyway rules? |
| Performance | Will this be slow on production-scale data? |

**Enforced via:** GitHub branch protection rules that require at least one approval before merging to main.

### Stage 5: Deploy to Staging

**Purpose:** Apply migrations to a staging environment that resembles production.

**Key requirement:** Staging should have production-like data (anonymized) and production-like volume. A migration that takes 2ms on an empty dev database might take 20 minutes on a staging database with 50 million rows.

**Automation:** This stage runs automatically after the PR is merged. No human intervention needed.

```yaml
deploy-staging:
  needs: test
  runs-on: ubuntu-latest
  environment: staging
  steps:
    - uses: actions/checkout@v4
    - name: Run migrations on staging
      run: |
        flyway \
          -url="${{ secrets.STAGING_DB_URL }}" \
          -user="${{ secrets.STAGING_DB_USER }}" \
          -password="${{ secrets.STAGING_DB_PASSWORD }}" \
          -locations=filesystem:./migrations/sql \
          migrate
```

### Stage 6: Integration Test

**Purpose:** Run the application's test suite against the staged database to verify that the schema change does not break anything.

This catches issues that migration-level testing misses:
- Queries that worked before the migration but fail or are slow after
- ORM mappings that no longer match the schema
- API endpoints that return different results

### Stage 7: Deploy to Production

**Purpose:** Apply migrations to the production database.

**Key safeguard:** This stage requires manual approval. A DBA or senior engineer must click "Approve" in the GitHub Actions UI before the pipeline proceeds.

**GitHub Environment configuration:**

1. Create a GitHub Environment named `production`
2. Add required reviewers (the DBA team)
3. Add environment secrets (production database credentials)
4. Optionally add a deployment branch restriction (only `main`)

```yaml
deploy-production:
  needs: deploy-staging
  runs-on: ubuntu-latest
  environment: production    # This triggers the approval gate
  steps:
    - uses: actions/checkout@v4
    - name: Run migrations on production
      run: |
        flyway \
          -url="${{ secrets.PROD_DB_URL }}" \
          -user="${{ secrets.PROD_DB_USER }}" \
          -password="${{ secrets.PROD_DB_PASSWORD }}" \
          -locations=filesystem:./migrations/sql \
          migrate
```

### Stage 8: Verify

**Purpose:** Confirm that the production schema matches expectations after deployment.

**Checks:**
- `flyway validate` passes
- Schema diff shows no unexpected differences
- Application health checks pass
- No error spikes in monitoring

### Stage 9: Monitor

**Purpose:** Watch for problems in the minutes and hours after deployment.

**What to watch:**
- `pg_stat_activity` for blocked queries or lock waits
- Error rates in application logs
- Query latency (is a new index helping or hurting?)
- Connection pool utilization
- Aurora CloudWatch metrics (CPU, connections, latency)

---

## GitHub Actions for Database CI/CD

GitHub Actions is the most common CI/CD platform for database migration pipelines. Here is the anatomy of a database workflow.

### Workflow File Structure

```
.github/workflows/migration-ci.yml
```

A workflow file has four main sections:

```yaml
name: Database Migration CI        # 1. Name (shown in GitHub UI)

on:                                 # 2. Triggers
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:                               # 3. Jobs (parallel or sequential)
  test-migrations:
    runs-on: ubuntu-latest          # 4. Runner (machine type)
    services:                       # Service containers
      postgres: ...
    steps:                          # Sequential commands
      - uses: actions/checkout@v4
      - run: flyway migrate
```

### Trigger Types

| Trigger | When It Fires | Use Case |
|---------|--------------|----------|
| `push` | Code pushed to a branch | Deploy after merge to main |
| `pull_request` | PR opened, updated, or reopened | Test before merging |
| `schedule` | Cron expression (e.g., nightly) | Drift detection, schema snapshots |
| `workflow_dispatch` | Manual button in GitHub UI | On-demand deployment |
| `repository_dispatch` | External API call | Trigger from Slack bot or other tooling |

### Path Filtering

You do not want the migration pipeline to run when someone edits the README. Use path filtering:

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'migrations/**'
```

This means the workflow only runs when files in the `migrations/` directory change.

### Secrets Management

Database credentials must never be hardcoded. Use GitHub Secrets:

1. Go to Settings > Secrets and variables > Actions
2. Add secrets like `STAGING_DB_URL`, `STAGING_DB_PASSWORD`
3. Reference them in workflows as `${{ secrets.SECRET_NAME }}`

Secrets are encrypted at rest, injected as environment variables at runtime, and automatically masked in logs. If a secret value accidentally appears in output, GitHub replaces it with `***`.

### Job Dependencies

Use `needs:` to create sequential jobs:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    # ... runs first

  deploy-staging:
    needs: test                    # Runs only if test succeeds
    runs-on: ubuntu-latest

  deploy-production:
    needs: deploy-staging          # Runs only if staging succeeds
    environment: production        # Requires manual approval
    runs-on: ubuntu-latest
```

This creates a pipeline: test -> staging -> production.

---

## Testing Strategies

### Level 1: Fresh Database Test (Every PR)

The minimum viable test. Apply all migrations from scratch and check the schema:

```yaml
steps:
  - name: Apply migrations
    run: flyway -configFiles=flyway.conf migrate

  - name: Validate schema
    run: psql -f validate.sql
```

**Catches:** Syntax errors, ordering bugs, missing dependencies, referential integrity violations.

### Level 2: Seed Data Test (Every PR)

After migrations, load representative data and run queries:

```yaml
steps:
  - name: Apply migrations
    run: flyway migrate

  - name: Load seed data
    run: psql -f seed.sql

  - name: Run query tests
    run: psql -f test_queries.sql
```

**Catches:** Queries that fail on the new schema, constraint violations on real-looking data.

### Level 3: Production-Scale Test (Before Risky Migrations)

Test against a clone of production data:

**For Aurora:**
```bash
# Create a clone of the production cluster
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier prod-cluster \
  --db-cluster-identifier migration-test-cluster \
  --restore-type copy-on-write \
  --use-latest-restorable-time

# Run migration against the clone
flyway -url="jdbc:postgresql://migration-test-cluster..." migrate

# Measure timing
# Delete the clone when done
```

**Catches:** Migrations that are fast on small data but slow on production-scale data. Lock durations that are acceptable on 1,000 rows but not on 100 million.

### Level 4: Dry Run with Plan Output

Some tools can show you what they would do without actually doing it:

```bash
# Atlas shows the planned SQL
atlas schema apply --to file://schema.hcl --dry-run

# Flyway shows pending migrations without applying
flyway info
```

---

## Approval Gates

Approval gates prevent migrations from reaching production without human review.

### GitHub Environment Protection Rules

1. Create a GitHub Environment named `production`
2. Enable "Required reviewers" and add the DBA team
3. Enable "Wait timer" if you want a delay (e.g., 15 minutes) before deployment

When the pipeline reaches the production job, GitHub pauses and sends a notification to the required reviewers. The reviewer sees:
- Which workflow is waiting
- What changes are included
- A link to approve or reject

### Slack/Teams Notifications

Add a notification step before the approval gate so the DBA team knows a migration is waiting:

```yaml
- name: Notify DBA team
  uses: slackapi/slack-github-action@v1
  with:
    channel-id: 'C01234DBATEAM'
    slack-message: "Migration waiting for production approval: ${{ github.event.head_commit.message }}"
```

### Emergency Bypass

For critical fixes, you may need to bypass the approval gate. Configure a "break glass" procedure:

1. A specific GitHub label (e.g., `emergency-deploy`) triggers a separate workflow
2. The workflow skips the approval gate but sends alerts to the entire DBA team
3. Post-incident review is mandatory for any emergency bypass

---

## Blue-Green Schema Deployments

Blue-green deployments for databases are more complex than for applications, but the principle is the same: deploy to an inactive environment, verify, then switch traffic.

### For Aurora

1. **Blue (current):** Production cluster serving traffic
2. **Green (new):** Aurora clone with migrations applied
3. **Verify:** Run tests against the green clone
4. **Switch:** Promote the green clone to be the new production
5. **Cleanup:** Delete the old blue cluster (after a safety period)

### Limitations

Blue-green for databases only works when:
- The migration is backward-compatible (old code can work with the new schema)
- Data written to blue during the switchover is acceptable to lose (or is replicated)
- The clone can catch up to the latest data

For most migrations, a simpler approach works: apply migrations directly with proper safeguards (lock timeouts, testing, approval gates).

---

## Pipeline Anti-Patterns

### Anti-Pattern 1: No Path Filtering

```yaml
# BAD: Runs the migration pipeline on every push, even README changes
on:
  push:
    branches: [main]
```

```yaml
# GOOD: Only runs when migration files change
on:
  push:
    branches: [main]
    paths:
      - 'migrations/**'
```

### Anti-Pattern 2: Same Credentials for All Environments

```yaml
# BAD: Using the same database user for dev, staging, and production
env:
  DB_USER: admin
  DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
```

Each environment should have its own credentials with appropriate permissions. The production user should be a dedicated migration user with only the permissions it needs.

### Anti-Pattern 3: No Lock Timeout

```sql
-- BAD: No safety net for lock acquisition
ALTER TABLE large_table ADD COLUMN status TEXT;
```

```sql
-- GOOD: Fail fast if the lock cannot be acquired
SET lock_timeout = '5s';
ALTER TABLE large_table ADD COLUMN status TEXT;
```

### Anti-Pattern 4: Skipping Staging

```yaml
# BAD: Test -> Production (no staging)
deploy-production:
  needs: test
```

Always deploy to staging first. Staging catches issues that a fresh-database CI test cannot:
- Slow migrations on production-scale data
- Conflicts with existing data
- Application compatibility issues

### Anti-Pattern 5: Manual Migration Runs

If someone can SSH into the production server and run migrations manually, the pipeline is not the single source of truth. Enforce that all migrations go through the pipeline by:

- Revoking direct DDL permissions from human users
- Creating a dedicated migration user that only the pipeline can use
- Auditing `pg_stat_activity` for unexpected DDL statements

---

## Pipeline Stages Reference Table

| Stage | Purpose | Tools | Automated? | Who Approves |
|-------|---------|-------|-----------|-------------|
| **1. Lint** | Syntax and safety checks | sqlfluff, squawk, atlas lint | Yes | Nobody (automated) |
| **2. Test** | Fresh database migration test | Flyway + PG service container | Yes | Nobody (automated) |
| **3. Diff** | Schema drift detection | atlas diff, pg_dump + diff | Yes | Nobody (automated) |
| **4. Review** | Human review of SQL | GitHub PR review | No | DBA / Tech Lead |
| **5. Staging** | Deploy to staging | Flyway migrate | Yes | Nobody (auto after merge) |
| **6. Integration** | App tests against staging | Application test suite | Yes | Nobody (automated) |
| **7. Production** | Deploy to production | Flyway migrate | No | DBA (manual approval) |
| **8. Verify** | Post-deploy schema check | flyway validate, smoke tests | Yes | Nobody (automated) |
| **9. Monitor** | Watch for issues | CloudWatch, pg_stat_activity | Yes | DBA (watches dashboards) |

---

## Key Takeaways

| Concept | Summary |
|---------|---------|
| Database pipelines are different | Schema changes are stateful, ordered, and can lose data |
| Nine pipeline stages | Lint, test, diff, review, staging, integration, production, verify, monitor |
| Service containers | Temporary databases for CI testing, destroyed after each run |
| Path filtering | Only trigger the pipeline when migration files change |
| Secrets management | Database credentials encrypted in GitHub Secrets, masked in logs |
| Approval gates | GitHub Environments with required reviewers for production |
| Testing levels | Fresh DB, seed data, production-scale, dry run |
| Anti-patterns | No path filter, shared credentials, no lock timeout, skipping staging |

---

**Next:** Start with [BUILD 01: Schema Migration Fundamentals](../build/01-schema-migration-fundamentals.md) to put these concepts into practice.
