# USE 05: Code Review Exercise

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Objective

Review five migration pull requests and identify the problems in each one. This exercise tests your ability to spot dangerous DDL patterns, missing safeguards, and backward-compatibility issues - the same skills you need when reviewing real migration PRs.

---

## How This Exercise Works

For each PR below, read the migration SQL carefully. Identify every problem. Write your review comments explaining what is wrong and how to fix it. Then check your answers against the solution.

Rate each migration: **APPROVE**, **REQUEST CHANGES**, or **BLOCK** (cannot merge, will cause outage).

---

## PR 1: Add Phone Column to Customers

**Author:** Junior developer
**Description:** "Adding phone number field to customers table for SMS notifications feature."

```sql
-- V12__add_phone_to_customers.sql

ALTER TABLE customers ADD COLUMN phone VARCHAR(15) NOT NULL;
```

### Your Review

Write your comments here before checking the answer.

<details>
<summary>Click to see the review</summary>

**Verdict: REQUEST CHANGES**

**Issues found:**

1. **Missing `SET lock_timeout`** - Every production migration must include `SET lock_timeout = '5s';` to prevent lock queue buildup.

2. **NOT NULL without DEFAULT on existing table** - The `customers` table has existing rows. Adding a `NOT NULL` column without a `DEFAULT` value will fail because PostgreSQL cannot assign a value to existing rows. Fix: either add `DEFAULT ''` or add the column as nullable first, backfill, then add the constraint.

3. **VARCHAR(15) is too short** - International phone numbers can be up to 16 characters (including the `+` prefix). Use `VARCHAR(20)` to be safe.

4. **No IF NOT EXISTS guard** - If this migration is re-run accidentally, it will fail. Use: `ALTER TABLE customers ADD COLUMN IF NOT EXISTS phone ...` (note: this requires a DO block in PostgreSQL since ALTER TABLE ADD COLUMN IF NOT EXISTS is not standard).

**Suggested fix:**

```sql
SET lock_timeout = '5s';
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
```

Then a separate migration to add the NOT NULL constraint after backfilling.

</details>

---

## PR 2: Add Index for Search Performance

**Author:** Senior developer
**Description:** "Adding indexes to improve search query performance. Tested on dev - queries went from 800ms to 2ms."

```sql
-- V13__add_search_indexes.sql

CREATE INDEX idx_products_name ON products (name);
CREATE INDEX idx_products_description ON products USING gin (to_tsvector('english', description));
CREATE INDEX idx_customers_email ON customers (email);
```

### Your Review

Write your comments here before checking the answer.

<details>
<summary>Click to see the review</summary>

**Verdict: BLOCK - will cause outage**

**Issues found:**

1. **No CONCURRENTLY on any index** - All three `CREATE INDEX` statements acquire a `SHARE` lock, blocking all writes to the table for the duration of the index build. On a production table with millions of rows, this could block writes for minutes.

2. **Missing `SET lock_timeout`** - No safety net for lock acquisition.

3. **Missing `-- flyway:executeInTransaction=false`** - `CREATE INDEX CONCURRENTLY` cannot run inside a transaction. Without this directive, Flyway wraps everything in a transaction, causing the CONCURRENTLY keyword to fail.

4. **Three indexes in one migration** - If the second index fails, the first is already committed (with `executeInTransaction=false`). Split into three separate migration files so each can be retried independently.

5. **Missing IF NOT EXISTS** - If the index already exists (from a manual run), the migration fails.

**Suggested fix:** Three separate migration files, each like:

```sql
-- flyway:executeInTransaction=false
SET lock_timeout = '5s';
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_name ON products (name);
```

</details>

---

## PR 3: Rename Column for API Consistency

**Author:** Tech lead
**Description:** "Renaming `name` to `full_name` on customers table to match the API schema."

```sql
-- V14__rename_customer_name.sql

SET lock_timeout = '5s';
ALTER TABLE customers RENAME COLUMN name TO full_name;
```

### Your Review

Write your comments here before checking the answer.

<details>
<summary>Click to see the review</summary>

**Verdict: REQUEST CHANGES**

**Issues found:**

1. **Not backward-compatible** - The moment this migration runs, every query, view, trigger, and application that references `customers.name` will break. This is a deployment-order problem: if the migration runs before the application is updated, the application fails.

2. **Should use expand-contract pattern** - The safe approach is:
   - Migration 1: Add `full_name` column
   - Update application to write to both `name` and `full_name`
   - Migration 2: Backfill `full_name` from `name`
   - Update application to read from `full_name`
   - Migration 3: Drop `name` column (weeks later)

3. **No rollback plan** - If the rename causes issues, there is no easy way to undo it without another migration.

4. **Views may break** - Any view that references `customers.name` will become invalid.

**Suggested fix:** Use the expand-contract pattern. This adds complexity but prevents outages.

</details>

---

## PR 4: Data Backfill Migration

**Author:** Senior DBA
**Description:** "Backfilling the loyalty_points column based on order history."

```sql
-- V15__backfill_loyalty_points.sql

SET lock_timeout = '5s';
SET statement_timeout = '600s';

UPDATE customers c
SET loyalty_points = (
    SELECT COALESCE(SUM(total_amount), 0)
    FROM orders o
    WHERE o.customer_id = c.customer_id
    AND o.status = 'delivered'
);
```

### Your Review

Write your comments here before checking the answer.

<details>
<summary>Click to see the review</summary>

**Verdict: REQUEST CHANGES**

**Issues found:**

1. **Single UPDATE on entire table** - This updates every row in the `customers` table in a single transaction. On a table with millions of rows, this acquires row-level locks on every row and holds them until the transaction completes. It also generates a massive WAL volume.

2. **Correlated subquery on every row** - The subquery runs once per customer. If there are 1 million customers and each has orders, this could take a very long time.

3. **No batching** - Should update in batches of 10,000-50,000 rows with `pg_sleep(0.1)` between batches to let other transactions through.

4. **No WHERE clause for incremental updates** - If the migration is interrupted and restarted, it re-processes every row. Add `WHERE loyalty_points IS NULL` (or `= 0`) to make it resumable.

**Suggested fix:**

```sql
SET lock_timeout = '5s';
SET statement_timeout = '600s';

DO $$
DECLARE
    batch_size INT := 10000;
    rows_updated INT := 1;
BEGIN
    WHILE rows_updated > 0 LOOP
        UPDATE customers c
        SET loyalty_points = sub.points
        FROM (
            SELECT c2.customer_id,
                   COALESCE(SUM(o.total_amount), 0) AS points
            FROM customers c2
            LEFT JOIN orders o ON o.customer_id = c2.customer_id
                AND o.status = 'delivered'
            WHERE c2.loyalty_points IS NULL
            GROUP BY c2.customer_id
            LIMIT batch_size
        ) sub
        WHERE c.customer_id = sub.customer_id;

        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        RAISE NOTICE 'Updated % rows', rows_updated;
        PERFORM pg_sleep(0.1);
    END LOOP;
END $$;
```

</details>

---

## PR 5: Add Foreign Key to Existing Table

**Author:** Junior developer
**Description:** "Adding foreign key from orders to shipping_addresses table that was created last sprint."

```sql
-- V16__add_shipping_fk.sql

SET lock_timeout = '5s';

ALTER TABLE orders
ADD COLUMN shipping_address_id INTEGER NOT NULL
REFERENCES shipping_addresses(address_id);
```

### Your Review

Write your comments here before checking the answer.

<details>
<summary>Click to see the review</summary>

**Verdict: REQUEST CHANGES**

**Issues found:**

1. **NOT NULL on new column without DEFAULT** - The `orders` table has existing rows. Adding a NOT NULL column without a default fails immediately.

2. **Foreign key added inline scans both tables** - Adding a FK as part of ADD COLUMN causes PostgreSQL to validate the FK on all existing rows while holding an ACCESS EXCLUSIVE lock. On large tables, this blocks everything.

3. **Should use expand-contract:**
   - Migration 1: Add column as nullable (no FK yet)
   - Migration 2: Backfill the column
   - Migration 3: Add FK with NOT VALID, then VALIDATE CONSTRAINT

4. **Missing IF NOT EXISTS** - No guard against re-running.

**Suggested fix (three migrations):**

```sql
-- V16a: Add nullable column
SET lock_timeout = '5s';
ALTER TABLE orders ADD COLUMN shipping_address_id INTEGER;

-- V16b: Backfill (batched)
-- ... batch update logic ...

-- V16c: Add FK safely
SET lock_timeout = '5s';
ALTER TABLE orders ADD CONSTRAINT fk_orders_shipping_address
    FOREIGN KEY (shipping_address_id) REFERENCES shipping_addresses(address_id)
    NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_shipping_address;
```

</details>

---

## Scoring

| PRs Correctly Reviewed | Rating |
|------------------------|--------|
| 5/5 with all issues found | Expert reviewer - ready for production DBA review duty |
| 4/5 or missed minor issues | Strong - review with a senior DBA for the first few PRs |
| 3/5 | Developing - re-read BUILD 04 (Zero-Downtime Migrations) |
| 2/5 or fewer | Needs practice - go through BUILD 04 and BUILD 05 again |

---

## Key Review Checklist

Use this checklist for every migration PR you review:

- [ ] `SET lock_timeout = '5s'` present?
- [ ] `CREATE INDEX` uses `CONCURRENTLY`?
- [ ] `executeInTransaction=false` for CONCURRENTLY?
- [ ] New columns on existing tables are nullable or have DEFAULT?
- [ ] FKs use NOT VALID + VALIDATE pattern?
- [ ] Data updates are batched (not single UPDATE on entire table)?
- [ ] Backward-compatible with current application code?
- [ ] Rollback plan documented or obvious?
- [ ] IF NOT EXISTS / IF EXISTS guards where appropriate?
- [ ] No hardcoded credentials?
