# Interview Questions: CI/CD for Database Changes

**Module 05**

---

## Question 1: How do you handle database schema changes in a CI/CD pipeline?

### What the interviewer is looking for
- Understanding of migration tools (Flyway, Liquibase, Atlas)
- Awareness of testing migrations before production
- Multi-environment promotion strategy
- Rollback planning

### Strong Answer Framework

**Start with the problem:**
"Without a pipeline, schema changes are error-prone. Someone runs a script manually, forgets an environment, or applies changes out of order. A CI/CD pipeline automates testing and deployment of schema changes the same way we automate application deployments."

**Describe the pipeline stages:**

1. **Version control:** All schema changes are stored as numbered migration files in Git (e.g., Flyway's `V1__create_table.sql` format). No one runs DDL directly against production.

2. **CI testing:** On every pull request, GitHub Actions (or similar) spins up a fresh PostgreSQL container, applies all migrations from scratch, and runs validation queries. If migrations fail or the schema does not match expectations, the PR is blocked.

3. **Code review:** A DBA or senior engineer reviews the migration SQL in the pull request. They check for locking issues, missing indexes, and safe DDL patterns.

4. **Staging deployment:** After merging, migrations are automatically applied to staging. Integration tests run against the staged database.

5. **Production deployment:** After staging passes, a manual approval gate requires a DBA to click "approve" before migrations run on production. This is configured as a GitHub Environment with required reviewers.

6. **Post-deploy verification:** After production deployment, `flyway validate` confirms the applied migrations match the source files, and monitoring checks for errors.

**Key details to mention:**
- Migration files are immutable once applied - never edit a migration that has run
- `CREATE INDEX CONCURRENTLY` for all index operations
- `SET lock_timeout = '5s'` in every production migration
- Forward-only rollback strategy (write V6 to fix V5, not an undo script)

---

## Question 2: Explain the expand-contract pattern for zero-downtime migrations

### What the interviewer is looking for
- Understanding of why direct ALTER TABLE can be dangerous
- Knowledge of the three-phase approach
- Practical examples with real DDL
- Awareness of application coordination

### Strong Answer Framework

"The expand-contract pattern allows schema changes without downtime by ensuring old and new code can work simultaneously during the transition. It has three phases:"

**Phase 1 - Expand:** Add new structures alongside old ones. Both old and new application code work.
- Example: Need to rename `name` to `full_name`? Add `full_name` column, do not remove `name` yet.

**Phase 2 - Migrate:** Copy/transform data from old structure to new. Both code paths still work.
- Backfill `full_name` from `name` in batches (10K rows at a time to avoid long locks)
- Add constraints using `NOT VALID` + `VALIDATE CONSTRAINT` pattern

**Phase 3 - Contract:** Remove old structures after all code is updated.
- Drop the `name` column once every consumer uses `full_name`
- This phase often deploys days or weeks after the expand phase

"The key insight is that each phase is a separate deployment. You can pause between phases, verify, and roll back if needed. The expand phase is low-risk because it only adds. The contract phase is low-risk because you have already verified the new structure works."

**Real-world considerations:**
- Feature flags decouple schema changes from code changes
- Views can provide backward compatibility during the transition
- Application-level dual-writes help during the migrate phase

---

## Question 3: A migration fails in production. How do you handle rollback?

### What the interviewer is looking for
- Calm, structured incident response
- Understanding of forward-only vs undo strategies
- Practical knowledge of Flyway/migration tool recovery
- Risk assessment skills

### Strong Answer Framework

"First, I assess the damage before doing anything:"

**Immediate assessment:**
1. What did the migration do before it failed? (Check the migration SQL and `pg_stat_activity`)
2. Is the application affected? (Check for errors, lock queues, connection issues)
3. Is data at risk? (Was there a data-modifying step that partially completed?)
4. What state is the migration tool in? (Check `flyway_schema_history` for failed entries)

**Decision framework:**

- **If the migration was DDL-only and failed cleanly** (e.g., syntax error before any changes): Fix the migration, run `flyway repair` to clean the failed entry, redeploy.

- **If the migration partially applied** (e.g., column added but backfill failed): Usually roll forward. The column exists, so write a new migration (V_next) to complete the work. Use `flyway repair` to remove the failed entry.

- **If the migration caused data corruption**: This is the only case where I consider rolling back. Restore from the last known good backup or use point-in-time recovery if available. This is why we take pre-migration snapshots.

"I use a forward-only approach in almost all cases. Writing a V6 to fix V5 is safer than undoing V5, because undo migrations can lose data (dropping a column destroys its data). The audit trail is also cleaner - you can see exactly what happened and when."

**Post-incident:**
- Write a post-incident review documenting what happened
- Add validation to CI to prevent similar failures
- Test future migrations on production-scale data copies

---

## Question 4: How do you test database migrations before applying to production?

### What the interviewer is looking for
- Multi-layer testing strategy
- Awareness of production-scale testing
- CI/CD integration knowledge
- Lock and performance testing

### Strong Answer Framework

"I test migrations at four levels, from fastest to most production-like:"

**Level 1 - CI with fresh database (every PR):**
- GitHub Actions spins up a PostgreSQL service container
- Apply all migrations from scratch (`flyway migrate`)
- Run validation queries checking table structure, indexes, constraints
- Run `flyway validate` to ensure no tampering
- This catches syntax errors, ordering issues, and referential integrity problems

**Level 2 - CI with seed data (every PR):**
- After applying migrations, load representative test data
- Run the application's test suite against the migrated schema
- Catches issues like "this query used to work but the new index changes the plan"

**Level 3 - Staging with production-like data (pre-deploy):**
- Staging database has a recent anonymized copy of production data
- Apply the migration and measure execution time
- Check for lock duration using `SET log_lock_waits = on; SET deadlock_timeout = '1s';`
- A migration that takes 2ms on an empty database might take 20 minutes on production data

**Level 4 - Production copy (for risky migrations):**
- For migrations touching large tables (10M+ rows), clone the production database
- Run the migration with `\timing on` and note the duration
- Check `pg_stat_progress_create_index` for index builds
- Verify that lock duration is acceptable (under 5 seconds for ACCESS EXCLUSIVE)

"The key principle: never let production be the first place you discover a migration is slow. If a migration takes 10 minutes on a copy of prod data, you know it will lock the table for 10 minutes in production - and that tells you to rewrite it using CONCURRENTLY or batched operations."

---

## Question 5: Compare Flyway and Liquibase - when would you choose each?

### What the interviewer is looking for
- Practical experience with both tools
- Understanding of trade-offs
- Ability to make technology decisions based on team needs
- Awareness of the broader ecosystem

### Strong Answer Framework

"Both are excellent tools. The choice depends on the team and the problem."

**Choose Flyway when:**
- Your team writes raw SQL and wants to keep it simple
- You are PostgreSQL-only (no need for database-agnostic migrations)
- You want minimal learning curve - just put numbered SQL files in a directory
- Your rollback strategy is forward-only (write V6 to fix V5)
- You want tight integration with Java/Spring Boot applications

**Choose Liquibase when:**
- You need to support multiple database engines (PostgreSQL, MySQL, Oracle)
- You want built-in rollback in the free tier
- You need to filter changesets by context (apply some changes only to dev, others to all)
- Your team prefers a structured format (YAML/XML) over raw SQL
- You need `liquibase diff` to compare schemas across environments

**Key technical differences:**

| Aspect | Flyway | Liquibase |
|--------|--------|-----------|
| Format | SQL files with strict naming | YAML, XML, JSON, or SQL changesets |
| Rollback | Paid (Teams/Enterprise) | Free (if rollback block defined) |
| Ordering | Sequential version numbers | Changelog order + id/author |
| Diff capability | None | Built-in `liquibase diff` |
| Database agnostic | No (SQL is DB-specific) | Yes (abstract types) |
| Tracking table | `flyway_schema_history` | `databasechangelog` |

"If I had to pick one rule: if you are a DBA team that thinks in SQL, choose Flyway. If you are supporting multiple database platforms or need rollback automation, choose Liquibase."

"I would also mention Atlas as a third option for teams that use Terraform and think declaratively. Atlas lets you define the desired schema state and generates the DDL, which is a fundamentally different approach from both Flyway and Liquibase."
