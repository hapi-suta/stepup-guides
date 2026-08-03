# Concepts: Database Change Management

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Why This Matters

Every database team eventually faces the same nightmare: someone runs an ALTER TABLE on production without telling anyone, two environments drift out of sync, and nobody can figure out which version of the schema is deployed where. Database change management solves this by applying the same discipline to DDL that developers apply to application code - version control, testing, review, and automated deployment.

This document covers the concepts you need before touching any tools. Read it before starting the BUILD guides.

---

## The Problem: Ad-Hoc DDL

In most organizations, database changes happen like this:

1. A developer asks the DBA to add a column
2. The DBA writes an ALTER TABLE statement
3. The DBA runs it against dev, then staging, then production
4. Somewhere along the way, an environment gets missed
5. Three months later, someone discovers that staging has a column production does not

This workflow has several failure modes:

- **No audit trail** - Who added that column? When? Why?
- **No testing** - The first time the DDL runs against real data is production
- **No rollback plan** - If the ALTER TABLE breaks something, what do you do?
- **Environment drift** - Dev, staging, and production slowly diverge
- **Ordering problems** - Migration scripts depend on each other, but nobody tracks the order

**The core insight:** Application code has had version control (Git), automated testing (CI), and automated deployment (CD) for years. Database schemas deserve the same treatment.

---

## Schema Migrations

A schema migration is a versioned, ordered SQL file that changes the database schema. Migrations are applied in sequence, and the migration tool tracks which ones have been applied.

### How Migrations Work

```
V1__create_users_table.sql        -- Applied first
V2__add_email_to_users.sql        -- Applied second
V3__create_orders_table.sql       -- Applied third
V4__add_index_on_email.sql        -- Applied fourth
```

Each file contains the DDL for one logical change. The migration tool:

1. Reads the list of migration files on disk
2. Checks a tracking table in the database to see which have been applied
3. Applies any pending migrations in version order
4. Records each applied migration in the tracking table

The tracking table (called `flyway_schema_history` in Flyway, `databasechangelog` in Liquibase) is the source of truth for what version the database is at.

### Migration Files Are Immutable

Once a migration has been applied to any environment, you must not edit it. If you change a file after it has been applied, the migration tool detects the checksum mismatch and refuses to proceed.

If you need to change something that a previous migration did, write a new migration. This preserves the audit trail and prevents the "but it worked on my machine" problem.

### Naming Conventions

Different tools use different naming schemes, but they all follow the same principle - a version identifier, a separator, and a description:

| Tool | Format | Example |
|------|--------|---------|
| Flyway | `V{version}__{description}.sql` | `V1__create_users.sql` |
| Liquibase | `changelog.yaml` with id/author | `id: 1, author: dba-team` |
| Atlas | `{timestamp}_{description}.sql` | `20260609120000_create_users.sql` |
| sqitch | Named changes with dependencies | `sqitch add create_users` |

For Flyway specifically:

- `V` prefix means versioned (applied once, in order)
- `R` prefix means repeatable (re-applied when the file content changes)
- `U` prefix means undo (reverses a versioned migration - Teams/Enterprise only)
- Two underscores (`__`) separate the version from the description
- Underscores in the description replace spaces

---

## Types of Database Changes

Not all database changes are the same. Understanding the categories helps you choose the right migration strategy.

### Schema Migrations (DDL)

These change the structure of the database:

- CREATE TABLE, ALTER TABLE, DROP TABLE
- CREATE INDEX, DROP INDEX
- ADD CONSTRAINT, DROP CONSTRAINT
- CREATE VIEW, CREATE FUNCTION

Schema migrations are typically fast (except on very large tables) and transactional in PostgreSQL-compatible engines like Aurora. If a DDL statement fails partway through, the transaction rolls back cleanly.

### Data Migrations (DML)

These change the data inside the tables:

- Backfilling a new column with computed values
- Transforming data from one format to another
- Splitting or merging columns
- Populating lookup tables

Data migrations can be slow on large tables and may need batching. They also carry risk because they modify existing data.

### Seed Data

Initial data that the application needs to function:

- Lookup tables (countries, currencies, status codes)
- Default configuration values
- Admin user accounts

Seed data is typically loaded once during initial setup.

### Reference Data Changes

Updates to lookup tables or configuration:

- Adding a new country code
- Changing a status label
- Adding a new permission type

These are often treated as versioned migrations because they need to be applied consistently across environments.

---

## Migration-Based vs State-Based Approaches

There are two fundamentally different philosophies for managing schema changes.

### Migration-Based (Imperative)

You write individual change scripts that say "do this, then do this, then do this":

```sql
-- V1: Create the table
CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT);

-- V2: Add a column
ALTER TABLE users ADD COLUMN email TEXT;

-- V3: Add an index
CREATE INDEX idx_users_email ON users (email);
```

You control every DDL statement. The tool simply applies them in order.

**Tools:** Flyway, Liquibase, sqitch

**Strengths:**
- Full control over exactly what DDL runs
- Natural fit for data migrations (UPDATE, INSERT)
- Easy for DBAs to review - it is just SQL
- Clear, linear history of changes

**Weaknesses:**
- You must write every ALTER TABLE yourself
- No automatic drift detection
- Rollback requires manual undo scripts (or paid features)

### State-Based (Declarative)

You define what the schema should look like, and the tool figures out the DDL to get there:

```hcl
table "users" {
  column "id"    { type = serial }
  column "name"  { type = text }
  column "email" { type = text }

  index "idx_users_email" {
    columns = [column.email]
  }
}
```

The tool compares this desired state against the actual database and generates the necessary ALTER TABLE, CREATE INDEX, etc.

**Tools:** Atlas, Terraform (for infrastructure), Redgate SQL Compare

**Strengths:**
- Schema definition is readable and self-documenting
- Automatic drift detection - the tool shows what is different
- No version numbering to manage
- Rollback DDL can be auto-generated

**Weaknesses:**
- Less control over complex migrations (data transforms)
- Generated DDL may not be optimal for large tables
- Learning curve for the schema definition language

### Which Should You Choose?

| Factor | Migration-Based | State-Based |
|--------|----------------|-------------|
| Team is SQL-first | Best choice | Awkward |
| Complex data transforms | Natural fit | Difficult |
| Multi-database support | Each DB needs its own SQL | Tool translates |
| Drift detection | Limited | Built-in |
| Rollback automation | Manual or paid | Automatic |
| Terraform/IaC shop | Separate workflow | Natural fit |

For Aurora environments, **migration-based with Flyway** is the most common choice because:

1. Aurora is PostgreSQL-compatible, so you write PostgreSQL DDL
2. Flyway has excellent PostgreSQL support
3. Most DBA teams prefer writing their own SQL
4. CI/CD integration is straightforward

---

## Rollback Strategies

When a migration goes wrong, you need a plan. There are four main rollback strategies.

### Strategy 1: Forward-Only (Recommended)

If migration V5 causes a problem, write V6 to fix it:

```sql
-- V5__add_strict_constraint.sql (the broken migration)
ALTER TABLE orders ADD CONSTRAINT chk_amount
    CHECK (amount > 0 AND amount < 10000);
-- Problem: rejects valid orders over $10,000

-- V6__fix_amount_constraint.sql (the fix)
ALTER TABLE orders DROP CONSTRAINT chk_amount;
ALTER TABLE orders ADD CONSTRAINT chk_amount
    CHECK (amount > 0 AND amount < 1000000);
```

**Why this is recommended:**
- Clear audit trail - you can see what was broken and how it was fixed
- No data loss - you never drop columns or tables
- Works with every migration tool (no paid features needed)
- Matches how application bugs are fixed - you deploy a fix, not "un-deploy"

### Strategy 2: Undo Migrations

Write a corresponding undo script for each migration:

```sql
-- V5__add_email_column.sql
ALTER TABLE users ADD COLUMN email TEXT;

-- U5__undo_add_email_column.sql
ALTER TABLE users DROP COLUMN email;
```

**Caution:** Dropping a column destroys all data in that column. If users have entered email addresses, the undo migration deletes them permanently.

**Availability:** Flyway undo is Teams/Enterprise only. Liquibase rollback is available in the free tier if you define rollback blocks.

### Strategy 3: Transaction Wrapping

Wrap the migration in a transaction so it can be rolled back atomically:

```sql
BEGIN;

ALTER TABLE orders ADD COLUMN status TEXT DEFAULT 'pending';
-- If something goes wrong here: ROLLBACK;

COMMIT;
```

This works for DDL in PostgreSQL and Aurora because they support transactional DDL. However, it does not work for operations that cannot run inside a transaction (like `CREATE INDEX CONCURRENTLY`).

### Strategy 4: Pre-Migration Snapshots

Before running a risky migration, create a backup:

```sql
CREATE TABLE orders_backup_20260609 AS SELECT * FROM orders;
```

Or use Aurora-specific features:

- **Aurora clones** - create a zero-cost clone before the migration
- **Snapshots** - take a manual snapshot before deployment
- **Backtrack** - rewind the cluster to a point before the migration (if enabled)

Aurora backtrack is particularly powerful because it lets you rewind the entire cluster to a specific point in time without restoring from backup.

---

## Version Control for Database Changes

Database migration files belong in Git, just like application code. Here is the standard project structure:

```
project-root/
  migrations/
    sql/
      V1__create_users_table.sql
      V2__add_email_to_users.sql
      V3__create_orders_table.sql
      R__reporting_views.sql
    flyway.conf
    validate.sql
  .github/
    workflows/
      migration-ci.yml
      migration-deploy.yml
```

### Branch Strategy for Migrations

Migrations interact with branches differently than application code:

- **Feature branch adds V4:** Developer creates a branch, adds `V4__add_reviews.sql`, opens a PR
- **Another branch also adds V4:** Conflict. Two branches cannot both claim version 4
- **Resolution:** Rebase or renumber. The second developer changes their file to V5

Some teams use timestamps instead of sequential numbers to avoid conflicts:

```
V20260609120000__create_users.sql
V20260609120100__add_email.sql
```

Flyway supports both formats.

### Pull Request Reviews for Migrations

Every migration should go through a pull request with DBA review. The reviewer checks:

1. **Locking impact** - Will this ALTER TABLE lock the table for too long?
2. **Index strategy** - Are new indexes necessary? Is CONCURRENTLY used?
3. **Backward compatibility** - Can the current application code still work?
4. **Rollback plan** - What happens if this migration fails?
5. **Data safety** - Does any DML risk data loss?
6. **Naming conventions** - Does the file follow Flyway naming rules?
7. **Idempotency** - Would running this twice cause problems?

---

## Tool Comparison

Here is a detailed comparison of the major migration tools:

| Feature | Flyway | Liquibase | Atlas | Bytebase |
|---------|--------|-----------|-------|----------|
| **Approach** | Imperative (SQL) | Imperative (changesets) | Declarative (desired state) | Imperative + Web UI |
| **Change format** | Plain SQL files | XML, YAML, JSON, SQL | HCL or SQL | SQL |
| **Rollback (free)** | No | Yes | Auto-generated | Yes |
| **Tracking table** | `flyway_schema_history` | `databasechangelog` | `atlas_schema_revisions` | Internal |
| **Drift detection** | Checksum only | Full schema diff | Full schema diff | Full schema diff |
| **SQL lint** | No | No | Yes (`atlas lint`) | Yes |
| **CI/CD integration** | CLI, Docker, Maven | CLI, Docker, Maven | CLI, Docker, GitHub Actions | GitOps, webhooks |
| **Aurora support** | Yes (PostgreSQL mode) | Yes | Yes | Yes |
| **Install (Mac)** | `brew install flyway` | `brew install liquibase` | `brew install ariga/tap/atlas` | Docker |
| **Best for** | SQL-first DBA teams | Enterprise multi-DB | Terraform/IaC shops | Large orgs with UI needs |

### Quick Decision Guide

- **You write raw SQL and want simplicity** - Flyway
- **You need free rollback support** - Liquibase
- **You use Terraform and think declaratively** - Atlas
- **You need a web UI with approval workflows** - Bytebase
- **You need dependency-graph migrations** - sqitch

---

## Aurora-Specific Considerations

Aurora PostgreSQL is compatible with standard PostgreSQL migration tools, but there are a few differences to be aware of:

### What Works the Same

- All DDL statements (CREATE TABLE, ALTER TABLE, etc.)
- Flyway, Liquibase, and Atlas all connect to Aurora as PostgreSQL
- `CREATE INDEX CONCURRENTLY` works on Aurora
- Transaction wrapping works for DDL

### What Is Different

- **Aurora clones** provide zero-cost database copies for testing migrations
- **Aurora backtrack** can rewind the cluster if a migration goes wrong
- **Reader endpoints** should not be used for migrations (read-only)
- **Connection pooling** (RDS Proxy) may need session pinning disabled for DDL
- **Parameter groups** control settings like `lock_timeout` at the cluster level
- **Multi-AZ failover** means a failed migration could trigger failover if it crashes the writer

### Aurora Clone Strategy for Migration Testing

Before running migrations on production Aurora:

1. Create a clone of the production cluster (takes seconds, zero storage cost initially)
2. Run the migration against the clone
3. Measure execution time and check for errors
4. If successful, run the migration against production
5. Delete the clone

This gives you production-scale testing without risk.

---

## Key Takeaways

| Concept | Summary |
|---------|---------|
| Schema migrations | Versioned SQL files applied in order, tracked in a history table |
| Immutability | Never edit a migration after it has been applied |
| Migration-based | You write the DDL (Flyway, Liquibase) |
| State-based | You define the goal, tool writes the DDL (Atlas) |
| Forward-only rollback | Fix broken migrations with a new migration, not an undo |
| Environment drift | When databases diverge from expected schema |
| Pull request reviews | Every migration goes through code review before production |
| Aurora clones | Zero-cost database copies for testing migrations safely |

---

**Next:** Read [02-cicd-pipelines-for-databases.md](02-cicd-pipelines-for-databases.md) before starting the BUILD guides.
