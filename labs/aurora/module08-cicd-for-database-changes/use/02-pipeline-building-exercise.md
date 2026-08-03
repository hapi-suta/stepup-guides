# USE 02: Pipeline Building Exercise

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Objective

Create a complete GitHub Actions workflow that tests, validates, and deploys database migrations. This exercise tests your ability to write workflow YAML, configure service containers, manage secrets, and set up multi-environment deployment with approval gates.

---

## Setup

Use the migration files from USE 01 (or create a simple set of 3-4 migrations if you skipped that exercise).

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/use-pipeline/migrations/sql
```

```bash
mkdir -p ~/dba-labs/use-pipeline/scripts
```

```bash
mkdir -p ~/dba-labs/use-pipeline/.github/workflows
```

```bash
cd ~/dba-labs/use-pipeline
```

```bash
git init
```

Create at least three migration files in `migrations/sql/`:

- `V1__create_users.sql`
- `V2__create_products.sql`
- `V3__create_orders.sql`

Each should include `SET lock_timeout = '5s';` and use `IF NOT EXISTS` guards.

---

## Requirements

### Part 1: CI Workflow

Create `.github/workflows/migration-ci.yml` that:

1. Triggers on push to `main` and `develop`, and on pull requests to `main`
2. Only triggers when files in `migrations/` change (path filtering)
3. Has a **lint** job that checks for:
   - `CREATE INDEX` without `CONCURRENTLY`
   - Missing `lock_timeout` in versioned migrations
4. Has a **test** job that:
   - Depends on the lint job (`needs:`)
   - Spins up a PostgreSQL 16 service container with health checks
   - Installs Flyway
   - Runs `flyway migrate`
   - Runs `flyway validate`
   - Executes a validation SQL script

### Part 2: CD Workflow

Create `.github/workflows/migration-deploy.yml` that:

1. Triggers only on push to `main` when migration files change
2. Has three jobs: `test` -> `deploy-staging` -> `deploy-production`
3. Uses `needs:` for job dependencies
4. Uses GitHub Secrets for database credentials (not hardcoded)
5. The `deploy-production` job uses `environment: production` for manual approval
6. Every Flyway command includes `-cleanDisabled=true`

### Part 3: Validation Script

Create `scripts/validate_schema.sql` that checks:

- All expected tables exist
- Expected column counts per table
- Foreign key constraints are in place
- At least N custom indexes exist
- Raises NOTICE on success, raises EXCEPTION on failure

---

## Acceptance Criteria

<details>
<summary>Click to expand the checklist</summary>

- [ ] CI workflow triggers on push and PR with path filtering
- [ ] Lint job catches `CREATE INDEX` without `CONCURRENTLY`
- [ ] Test job spins up PostgreSQL 16 service container
- [ ] Health check uses `pg_isready`
- [ ] Flyway is installed and runs `migrate` + `validate`
- [ ] Validation script catches missing tables
- [ ] CD workflow has three jobs with correct dependencies
- [ ] Production job uses `environment: production`
- [ ] No hardcoded passwords in workflow files
- [ ] All Flyway commands in CD include `-cleanDisabled=true`

</details>

---

## Verification

### Test your lint step locally

Create a migration with a bad pattern to test your lint:

```bash
vi migrations/sql/V99__test_bad_index.sql
```

```sql
SET lock_timeout = '5s';
CREATE INDEX idx_test ON users (email);
```

Run your lint check manually:

```bash
grep -rn "CREATE INDEX" migrations/sql/ | grep -v "CONCURRENTLY" | grep -v "^--" | grep -v "IF NOT EXISTS"
```

Expected: the grep should find `V99__test_bad_index.sql`. Delete it after testing:

```bash
rm migrations/sql/V99__test_bad_index.sql
```

### Test your validation script locally

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d cicd_dev -f scripts/validate_schema.sql
```

### Push and verify

```bash
git add .
```

```bash
git commit -m "feat: add migration CI/CD pipeline"
```

```bash
gh repo create use-pipeline-exercise --private --source=. --push
```

Go to the Actions tab and verify the CI workflow runs and passes.

---

## Hints

<details>
<summary>Click if you are stuck on the lint job</summary>

```yaml
lint-migrations:
  name: Lint Migrations
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Check for unsafe CREATE INDEX
      run: |
        if grep -rn "CREATE INDEX" migrations/sql/ \
          | grep -v "CONCURRENTLY" \
          | grep -v "^--" \
          | grep -v "IF NOT EXISTS"; then
          echo "FAIL: Found CREATE INDEX without CONCURRENTLY"
          exit 1
        fi
        echo "PASS"
```

</details>

<details>
<summary>Click if you are stuck on the service container</summary>

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

</details>

<details>
<summary>Click if you are stuck on environment secrets</summary>

```yaml
- name: Deploy to staging
  run: |
    flyway \
      -url="${{ secrets.STAGING_DB_URL }}" \
      -user="${{ secrets.STAGING_DB_USER }}" \
      -password="${{ secrets.STAGING_DB_PASSWORD }}" \
      -locations=filesystem:./migrations/sql \
      -cleanDisabled=true \
      migrate
```

</details>

---

## Bonus Challenge

Add a notification step that posts to a Slack channel when the production deployment completes:

```yaml
- name: Notify Slack
  if: success()
  uses: slackapi/slack-github-action@v1
  with:
    channel-id: 'C01234DBATEAM'
    slack-message: "Migration deployed to production: ${{ github.sha }}"
  env:
    SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```
