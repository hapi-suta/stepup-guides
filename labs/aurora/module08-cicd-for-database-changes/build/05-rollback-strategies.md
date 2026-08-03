# BUILD 05: Rollback Strategies

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster
**Estimated Time:** 45-60 minutes

---

## What You Will Learn

When and how to roll back a database migration that went wrong. You will practice four rollback strategies and learn which one to use in each situation.

---

## Prerequisites

- Aurora PostgreSQL cluster (`devops-lab-cluster`) running
- Completed BUILD 01-04
- `psql` installed on your Mac

---

## Why Rollback Is Harder for Databases

Rolling back application code is simple - you redeploy the previous version. Rolling back a database migration is different because:

1. **Data may have changed** - If the migration added a column and users entered data, dropping the column destroys that data.
2. **Other migrations depend on it** - If V5 added a column that V6 references, you cannot undo V5 without first undoing V6.
3. **The migration tool tracks state** - Flyway's `flyway_schema_history` table records what was applied. You need to update it too.

The first question when a migration fails is not "how do I roll back?" - it is "should I roll back at all?"

---

## Step 1: Set Up the Lab

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE rollback_lab;"
```

Expected output:
```
CREATE DATABASE
```

Create the base schema and simulate some migration history:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_lab
```

Inside psql:

```sql
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(255) UNIQUE,
    created_at  TIMESTAMPTZ DEFAULT now()
);
```

```sql
INSERT INTO customers (name, email)
SELECT 'Customer ' || i, 'cust' || i || '@example.com'
FROM generate_series(1, 100000) AS i;
```

Expected output:
```
INSERT 0 100000
```

```sql
\q
```

---

## Step 2: Strategy 1 - Forward-Only (Recommended)

The forward-only strategy means you never undo a migration. If V5 is broken, you write V6 to fix it.

### The Scenario

You deployed a migration that adds a constraint rejecting valid data:

```sql
-- V5__add_email_constraint.sql (the broken migration)
ALTER TABLE customers ADD CONSTRAINT chk_email_format
    CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
```

This regex rejects valid emails like `user@co` or emails with international characters.

### The Fix

Instead of undoing V5, write V6:

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_lab
```

First, apply the broken constraint:

```sql
ALTER TABLE customers ADD CONSTRAINT chk_email_format
    CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
```

Now fix it with a forward migration:

```sql
-- This is what V6__fix_email_constraint.sql would contain
ALTER TABLE customers DROP CONSTRAINT chk_email_format;

ALTER TABLE customers ADD CONSTRAINT chk_email_format
    CHECK (email ~ '.+@.+');
```

- First statement drops the overly strict constraint.
- Second statement adds a more permissive one that still validates basic email structure.

```sql
\q
```

### Why Forward-Only Is Recommended

- **Clear audit trail** - the history shows what was broken and how it was fixed
- **No data loss** - you never drop columns or tables
- **Works with Flyway Community** - no paid undo feature needed
- **Matches application workflow** - developers fix bugs with new code, not "un-deploys"

---

## Step 3: Strategy 2 - Transaction Wrapping

PostgreSQL (and Aurora) supports transactional DDL. You can wrap schema changes in a transaction and roll back if something goes wrong.

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_lab
```

```sql
BEGIN;
```

```sql
ALTER TABLE customers ADD COLUMN loyalty_tier VARCHAR(20) DEFAULT 'bronze';
```

Check that the column exists:

```sql
SELECT customer_id, name, loyalty_tier FROM customers LIMIT 3;
```

Expected output:
```
 customer_id |    name     | loyalty_tier
-------------+-------------+--------------
           1 | Customer 1  | bronze
           2 | Customer 2  | bronze
           3 | Customer 3  | bronze
```

Now roll it back:

```sql
ROLLBACK;
```

Verify the column is gone:

```sql
SELECT customer_id, name FROM customers LIMIT 3;
```

Expected output:
```
 customer_id |    name
-------------+-------------
           1 | Customer 1
           2 | Customer 2
           3 | Customer 3
```

The column was never committed. This is safe because no data was permanently changed.

### Limitations

Transaction wrapping does not work for:

- `CREATE INDEX CONCURRENTLY` - cannot run inside a transaction
- Multi-statement migrations that include CONCURRENTLY operations
- Migrations that have already been committed

### In Practice

Use transaction wrapping as a **testing technique**, not a production rollback strategy. Test your migration in a `BEGIN; ... ROLLBACK;` block to see what it does, then run it for real.

```sql
\q
```

---

## Step 4: Strategy 3 - Pre-Migration Snapshots

Before running a risky migration, create a backup you can restore from.

### Table-Level Backup

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_lab
```

```sql
CREATE TABLE customers_backup_20260609 AS SELECT * FROM customers;
```

- `CREATE TABLE ... AS SELECT *` creates an exact copy of the table with all data.

Expected output (yours will differ):
```
SELECT 100000
```

Now run a risky migration:

```sql
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
```

```sql
UPDATE customers SET phone = '+1-555-' || lpad(customer_id::text, 7, '0');
```

If something goes wrong, you can restore:

```sql
-- Drop the modified table
DROP TABLE customers;

-- Restore from backup
ALTER TABLE customers_backup_20260609 RENAME TO customers;
```

**Warning:** This approach loses any data inserted between the backup and the restore. In production, use Aurora-specific features instead.

```sql
\q
```

### Aurora-Specific Snapshots

Aurora provides three options that are better than table-level backups:

**Aurora Clones:**

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier devops-lab-cluster \
  --db-cluster-identifier migration-test-clone \
  --restore-type copy-on-write \
  --use-latest-restorable-time
```

- Creates a zero-cost clone of the entire cluster. Only modified pages consume storage.
- Use this to test migrations on production-scale data before applying to the real cluster.

**Aurora Backtrack:**

```bash
aws rds backtrack-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --backtrack-to "2026-06-09T14:00:00Z"
```

- Rewinds the entire cluster to a specific point in time.
- Much faster than restoring from a snapshot.
- Must be enabled on the cluster beforehand with a backtrack window (e.g., 24 hours).
- Does not work across certain DDL operations (like table drops).

**Manual Snapshots:**

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-snapshot-identifier pre-migration-20260609
```

- Takes a snapshot of the entire cluster before the migration.
- Restore takes longer than backtrack but works for any scenario.

---

## Step 5: Strategy 4 - Flyway Repair

When a migration fails partway through, Flyway records it as `failed` in `flyway_schema_history`. The next `migrate` command refuses to run because of the failed entry.

### Simulate a Failed Migration

**On your Mac terminal:**

Set up Flyway for the rollback_lab database:

```bash
mkdir -p ~/dba-labs/rollback-demo/sql
```

```bash
cd ~/dba-labs/rollback-demo
```

```bash
vi flyway.conf
```

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/rollback_lab
flyway.user=postgres
flyway.password=YOUR_PASSWORD
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
```

Baseline at V0 since we already have tables:

```bash
flyway -configFiles=flyway.conf baseline -baselineVersion=0
```

- `baseline -baselineVersion=0` - marks the database as "at version 0" so Flyway knows to start applying from V1.

Create a migration with a deliberate error:

```bash
vi sql/V1__broken_migration.sql
```

```sql
SET lock_timeout = '5s';
ALTER TABLE customers ADD COLUMN status VARCHAR(20) DEFAULT 'active';
-- This next line will fail: table does not exist
ALTER TABLE nonexistent_table ADD COLUMN foo TEXT;
```

Run the migration:

```bash
flyway -configFiles=flyway.conf migrate
```

Expected output (yours will differ):
```
Migrating schema "public" to version 1 - broken migration
ERROR: Migration V1__broken_migration.sql failed
...
relation "nonexistent_table" does not exist
```

Check Flyway's state:

```bash
flyway -configFiles=flyway.conf info
```

You will see V1 with state `Failed`. The next `migrate` will refuse to run.

### Repair and Retry

First, check what actually happened in the database. Because PostgreSQL wraps the migration in a transaction, the entire migration was rolled back - the `status` column was not added:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_lab -c "\d customers"
```

Now fix the migration file:

```bash
vi sql/V1__broken_migration.sql
```

Remove the line referencing `nonexistent_table`. The file should only contain:

```sql
SET lock_timeout = '5s';
ALTER TABLE customers ADD COLUMN status VARCHAR(20) DEFAULT 'active';
```

Save and exit.

Run `flyway repair` to clean up the failed entry:

```bash
flyway -configFiles=flyway.conf repair
```

- `repair` - removes failed migration entries from `flyway_schema_history` and realigns checksums.

Expected output (yours will differ):
```
Repair of failed migration in Schema History table "public"."flyway_schema_history" succeeded.
```

Now retry the migration:

```bash
flyway -configFiles=flyway.conf migrate
```

Expected output (yours will differ):
```
Migrating schema "public" to version 1 - broken migration
Successfully applied 1 migration to schema "public"
```

---

## Step 6: Decision Framework - Roll Forward or Roll Back?

When a migration fails in production, use this framework:

| Question | If Yes | If No |
|----------|--------|-------|
| Is the application currently broken? | Act immediately | You have time to plan |
| Did the migration partially apply DDL? | Roll forward (complete it or fix it) | Retry with `flyway repair` |
| Was data modified (DML)? | Assess data state, likely roll forward | Safe to retry |
| Can you fix it with a new migration? | Write V_next and deploy | Consider restore from backup |
| Is data lost or corrupted? | Restore from snapshot/backtrack | Roll forward |

**The rule of thumb:** Roll forward unless data is lost or corrupted. A new migration to fix the problem is almost always safer than trying to undo work.

---

## Step 7: Clean Up

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "DROP DATABASE IF EXISTS rollback_lab;"
```

Expected output:
```
DROP DATABASE
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Forward-only | Fix broken migrations with a new migration (V6 fixes V5) |
| Transaction wrapping | Wrap DDL in BEGIN/ROLLBACK for testing - PostgreSQL supports transactional DDL |
| Pre-migration snapshots | Table backups, Aurora clones, Aurora backtrack, manual snapshots |
| flyway repair | Removes failed entries so you can fix the file and retry |
| Decision framework | Roll forward unless data is lost - new migrations are safer than undos |
| Aurora backtrack | Rewind the cluster to a point before the migration |
| Aurora clones | Zero-cost copies for testing migrations on production-scale data |

---

**Next:** [BUILD 06: Terraform and Flyway Together](06-terraform-and-flyway-together.md) - combine infrastructure provisioning with schema migrations in a single pipeline.
