# Interview Prep: CI/CD for Database Changes

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**18 questions - Junior to Senior**

---

## Question 1: How do you handle database schema changes in a CI/CD pipeline?

**Level:** Junior-Mid

**What the interviewer is looking for:**
- Understanding of migration tools
- Awareness of testing before production
- Multi-environment promotion strategy
- Rollback planning

**Strong answer framework:**

Start with the problem: "Without a pipeline, schema changes are error-prone. Someone runs a script manually, forgets an environment, or applies changes out of order."

Then describe the pipeline stages:
1. **Version control** - All schema changes are numbered migration files in Git (e.g., Flyway's `V1__create_table.sql`). Nobody runs DDL directly.
2. **CI testing** - On every PR, GitHub Actions spins up a fresh PostgreSQL container, applies all migrations, and runs validation queries.
3. **Code review** - A DBA reviews the migration SQL for locking issues, missing indexes, and safe DDL patterns.
4. **Staging deployment** - After merge, migrations auto-deploy to staging.
5. **Production deployment** - Manual approval gate. A DBA clicks "approve" in the GitHub Actions UI.
6. **Post-deploy verification** - `flyway validate` confirms checksums match, monitoring watches for errors.

Mention: migration immutability, `CREATE INDEX CONCURRENTLY`, `SET lock_timeout`, forward-only rollback.

---

## Question 2: Explain the expand-contract pattern for zero-downtime migrations.

**Level:** Mid

**What the interviewer is looking for:**
- Why direct ALTER TABLE can be dangerous
- Three-phase approach
- Real DDL examples
- Application coordination

**Strong answer framework:**

"The expand-contract pattern ensures schema changes do not break running applications by maintaining backward compatibility at every step."

- **Phase 1 - Expand:** Add new structures alongside old ones. Example: need to rename `name` to `full_name`? Add a `full_name` column. Do not touch `name`.
- **Phase 2 - Migrate:** Backfill data in batches (10K rows, `pg_sleep(0.1)` between batches). Add constraints with `NOT VALID` + `VALIDATE`.
- **Phase 3 - Contract:** Drop the old column after all application code uses `full_name`. This phase often deploys days or weeks after expand.

Key insight: each phase is a separate deployment. You can pause, verify, and roll back between phases.

---

## Question 3: A migration fails in production. Walk me through your response.

**Level:** Mid-Senior

**What the interviewer is looking for:**
- Calm, structured incident response
- Forward-only vs undo strategies
- Practical recovery steps
- Risk assessment

**Strong answer framework:**

"First, I assess the damage before doing anything."

1. **What did the migration do before it failed?** Check `pg_stat_activity` and the migration SQL.
2. **Is the application affected?** Check for errors, lock queues, connection issues.
3. **Is data at risk?** Was there a partially completed DML step?
4. **What state is the migration tool in?** Check `flyway_schema_history` for failed entries.

Decision framework:
- DDL-only failure (syntax error): fix the file, run `flyway repair`, redeploy.
- Partial DDL + DML: usually roll forward. Write a new migration to complete the work.
- Data corruption: restore from backup or Aurora backtrack.

"I use forward-only in almost all cases. Writing V6 to fix V5 is safer than undo, because undo can lose data."

---

## Question 4: How do you test database migrations before production?

**Level:** Mid

**What the interviewer is looking for:**
- Multi-layer testing strategy
- Production-scale awareness
- CI integration

**Strong answer framework:**

"I test at four levels, from fastest to most production-like."

1. **CI with fresh database (every PR):** PostgreSQL container, apply all migrations from V1, run validation queries.
2. **CI with seed data (every PR):** After migrations, load representative data, run the application test suite.
3. **Staging with production-like data (pre-deploy):** Measure execution time. A migration that takes 2ms on empty dev might take 20 minutes on production-scale data.
4. **Production copy (risky migrations):** Clone the Aurora cluster, run the migration, measure timing and lock duration.

"The key: never let production be the first place you discover a migration is slow."

---

## Question 5: Compare Flyway and Liquibase. When would you choose each?

**Level:** Mid

**What the interviewer is looking for:**
- Practical experience with both tools
- Ability to make technology decisions

**Strong answer framework:**

| Factor | Flyway | Liquibase |
|--------|--------|-----------|
| Format | Plain SQL files | XML/YAML/JSON/SQL |
| Rollback (free) | No | Yes |
| Learning curve | Low | Medium |
| Database-agnostic | No | Yes |
| Schema diff | No | Yes |

Choose Flyway: SQL-first teams, PostgreSQL-only, minimal learning curve.
Choose Liquibase: Multiple database engines, need rollback, need schema diff.

"I would also mention Atlas for teams that use Terraform and think declaratively."

---

## Question 6: What is `CREATE INDEX CONCURRENTLY` and why does it matter?

**Level:** Junior-Mid

**Strong answer framework:**

"Standard `CREATE INDEX` acquires a SHARE lock that blocks all writes to the table. On a large table, this can block writes for minutes. `CREATE INDEX CONCURRENTLY` builds the index using weaker locks that allow reads and writes during the build."

Key points:
- Takes longer but does not lock the table for writes
- Cannot run inside a transaction (`executeInTransaction=false` in Flyway)
- If interrupted, leaves an INVALID index - must check and clean up
- Always use `IF NOT EXISTS` with it
- Required for any production table with traffic

---

## Question 7: What is a lock queue cascade and how do you prevent it?

**Level:** Mid-Senior

**Strong answer framework:**

"When an ALTER TABLE requests an ACCESS EXCLUSIVE lock, it queues behind existing transactions. While it waits, every new query also queues behind it. You have not even started your DDL, but the entire table is effectively blocked."

Prevention:
1. `SET lock_timeout = '5s'` - fail fast if the lock is not available
2. Check `pg_stat_activity` for long-running queries before running migrations
3. Schedule migrations during low-traffic windows
4. Kill the DDL rather than letting the queue grow
5. Set `idle_in_transaction_session_timeout` to prevent abandoned transactions from holding locks

---

## Question 8: How do you handle database credentials in a CI/CD pipeline?

**Level:** Junior

**Strong answer framework:**

"Never hardcode credentials. Use GitHub Secrets for CI/CD."

- Store credentials as repository secrets (e.g., `STAGING_DB_PASSWORD`)
- Reference them as `${{ secrets.STAGING_DB_PASSWORD }}` in workflows
- Secrets are encrypted at rest, injected at runtime, and masked in logs
- Each environment has its own set of credentials
- Use a dedicated migration user (not postgres superuser)
- For local development, use environment variables (`export FLYWAY_PASSWORD=...`)

---

## Question 9: Explain the NOT VALID + VALIDATE CONSTRAINT pattern.

**Level:** Mid

**Strong answer framework:**

"Adding a constraint normally scans the entire table while holding a strong lock. The two-step pattern avoids this."

Step 1: `ALTER TABLE t ADD CONSTRAINT chk CHECK (col > 0) NOT VALID;`
- Adds the constraint to the catalog (enforced for new/modified rows)
- Does NOT scan existing rows
- Brief ACCESS EXCLUSIVE lock

Step 2: `ALTER TABLE t VALIDATE CONSTRAINT chk;`
- Scans all existing rows to verify compliance
- Uses SHARE UPDATE EXCLUSIVE lock (allows reads AND writes)
- Takes longer but does not block traffic

"This is essential for large production tables. A single ADD CONSTRAINT on a 100M row table could lock it for minutes."

---

## Question 10: What is schema drift and how do you detect it?

**Level:** Mid

**Strong answer framework:**

"Schema drift is when the actual database schema does not match what your migration tool expects. It happens when someone runs manual DDL, a migration partially fails, or environments diverge."

Detection methods:
- `flyway validate` - detects file checksum changes (limited)
- `atlas schema diff` - full structural comparison
- `liquibase diff` - compares two databases
- `pg_dump --schema-only` + `diff` - quick manual check
- Scheduled nightly CI job that compares all environments

"I recommend a nightly GitHub Actions job that diffs staging against production schemas and alerts if they diverge."

---

## Question 11: How do you roll back a migration that dropped a column?

**Level:** Senior

**Strong answer framework:**

"You cannot undo a DROP COLUMN because the data is gone. This is why prevention is more important than rollback."

If it already happened:
1. Re-add the column: `ALTER TABLE t ADD COLUMN c TYPE;`
2. Restore data from backup, PITR, or Aurora backtrack
3. If no backup: data is permanently lost. Document and notify stakeholders.

Prevention:
- Never DROP COLUMN in the same migration that adds it. Use expand-contract.
- Take pre-migration snapshots (Aurora clones or manual snapshots)
- Enable Aurora backtrack on all production clusters
- Add a CI lint step that blocks DROP COLUMN without DBA approval

---

## Question 12: What are GitHub Environments and how do they help with database deployments?

**Level:** Junior-Mid

**Strong answer framework:**

"GitHub Environments are deployment targets with configurable protection rules."

For database CI/CD:
- Create a `production` environment with required reviewers (the DBA team)
- When the pipeline reaches the production job, it pauses and sends a notification
- A DBA reviews the pending migrations and clicks Approve or Reject
- Environment-specific secrets ensure the pipeline uses the correct credentials
- Optional: add a wait timer (e.g., 15-minute delay before production deploy)

"This gives you the automation of CI/CD with the human judgment gate that database changes require."

---

## Question 13: How would you integrate Terraform and Flyway in a single pipeline?

**Level:** Senior

**Strong answer framework:**

"Terraform manages infrastructure (create the Aurora cluster). Flyway manages what is inside it (create the tables). The pipeline must run Terraform first, then Flyway."

Pipeline structure:
1. Test migrations against a fresh PostgreSQL container (parallel with Terraform plan)
2. Terraform apply (create/update infrastructure)
3. Wait for database to be ready
4. Flyway migrate (apply schema changes)
5. Validate

Key considerations:
- Job dependencies: `migrate-staging` depends on `apply-staging`
- State: Terraform state in S3, Flyway state in the database
- Drift: someone running Terraform or Flyway manually outside the pipeline breaks sync
- Secrets: Terraform needs AWS credentials, Flyway needs database credentials

---

## Question 14: What is flyway_schema_history and how does Flyway use it?

**Level:** Junior

**Strong answer framework:**

"`flyway_schema_history` is a table Flyway creates in your database to track which migrations have been applied."

Key columns:
- `version` - the migration version number
- `description` - human-readable name from the file
- `checksum` - hash of the file contents (detects tampering)
- `installed_on` - when the migration was applied
- `success` - whether it completed without errors

How Flyway uses it:
- `migrate` - reads the table, compares against files on disk, applies pending ones
- `validate` - checks that file checksums match recorded checksums
- `info` - shows the status of all migrations
- `repair` - removes failed entries so you can retry

---

## Question 15: A developer wants to rename a column in production. What do you tell them?

**Level:** Mid

**Strong answer framework:**

"Do not rename it directly. ALTER TABLE RENAME COLUMN breaks every query that references the old name."

Instead, use expand-contract:
1. **Migration 1:** Add the new column (`full_name`)
2. **Application update:** Write to both old and new columns
3. **Migration 2:** Backfill new column from old column
4. **Application update:** Read from new column only
5. **Migration 3:** Drop old column (days/weeks later)

"Each step is a separate deployment. Between steps, both the old and new application code work. This is slower but prevents outages."

---

## Question 16: How do you handle migration version conflicts when multiple developers work on the same project?

**Level:** Mid

**Strong answer framework:**

"If two developers both create V4 on different branches, Flyway will reject the second one."

Solutions:
1. **Timestamp-based versions:** `V20260609120000__create_users.sql` - virtually no conflicts
2. **Reserve version ranges:** Developer A gets V10-V19, Developer B gets V20-V29
3. **Rebase before merge:** The second developer renumbers their migration
4. **CI catches it:** The fresh-database test applies all migrations in order and fails on duplicates

"I prefer timestamp-based versions for larger teams. For small teams, sequential with rebasing works fine."

---

## Question 17: What safeguards would you add to a production database migration pipeline?

**Level:** Senior

**Strong answer framework:**

"I layer multiple safeguards. No single check catches everything."

1. **CI lint** - catch unsafe patterns (missing CONCURRENTLY, missing lock_timeout)
2. **Fresh-database test** - apply all migrations from scratch on every PR
3. **Production-scale test** - for risky migrations, test on an Aurora clone
4. **Code review** - DBA reviews every migration PR
5. **Manual approval gate** - GitHub Environment with required reviewers
6. **Pre-deploy snapshot** - Aurora snapshot before every production migration
7. **lock_timeout in every migration** - fail fast if locks are not available
8. **Destructive operation lint** - flag DROP COLUMN, TRUNCATE, DELETE
9. **Post-deploy validation** - `flyway validate` + schema checks + monitoring
10. **Nightly drift detection** - scheduled job comparing all environments

---

## Question 18: You discover that someone ran manual DDL on production. How do you handle it?

**Level:** Senior

**Strong answer framework:**

"First, I identify what changed. Then I decide whether to incorporate it into the migration history or revert it."

Investigation:
1. Run `flyway validate` - will it detect the drift?
2. Compare `pg_dump --schema-only` of production against staging
3. Check `pg_stat_activity` logs for the DDL statement (if `log_statement = 'ddl'`)
4. Identify who made the change and why

If the change is wanted:
- Write a migration that matches the manual DDL
- Apply it to all other environments
- Add it to flyway_schema_history manually or via `flyway baseline`

If the change is unwanted:
- Write a migration to revert it
- Apply to production through the normal pipeline

Prevention:
- Revoke DDL permissions from human users on production
- Create a dedicated migration user that only the pipeline can use
- Enable `log_statement = 'ddl'` to audit all DDL
- Set up alerts for DDL statements outside the pipeline

"The long-term fix is ensuring the pipeline is the only way to change the production schema. Revoking direct DDL permissions enforces this."
