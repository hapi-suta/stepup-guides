# Build 11 - Query Plan Management (Aurora PostgreSQL)

**Time:** 35 minutes
**Goal:** Enable Aurora Query Plan Management, capture query plans, approve stable plans, and prevent performance regressions from plan changes.
**Prerequisites:** Aurora PostgreSQL cluster (not RDS PostgreSQL - QPM is Aurora-only). psql access to the writer endpoint. `$DB_CLUSTER_ID`, `$AURORA_WRITER_ENDPOINT`, `$REGION` set.

---

## Background

PostgreSQL re-plans every statement execution (unless prepared statements are used). When table statistics change - after ANALYZE, a large data load, or a PostgreSQL minor version upgrade - the planner may choose a different execution plan. The new plan is sometimes better. Sometimes it is 100x slower.

Aurora Query Plan Management (QPM) captures execution plans for your SQL statements and lets you approve the plans that work well. Once approved, the planner is constrained to use only those approved plans, even if statistics change and the planner would prefer a different plan.

> **Concept:** QPM uses the `apg_plan_mgmt` extension, which is preloaded on Aurora PostgreSQL. Unlike pg_hint_plan (which requires you to embed hints in query text), QPM stores plan preferences externally in the `apg_plan_mgmt` schema.

---

## Step 1 - Enable apg_plan_mgmt

### Add to Parameter Group

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "aurora-pg16-ccm" \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=apg_plan_mgmt,ApplyMethod=pending-reboot" \
  --region "$REGION"
```

If you need both `pg_stat_statements` and `apg_plan_mgmt`:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "aurora-pg16-ccm" \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue='pg_stat_statements\,apg_plan_mgmt',ApplyMethod=pending-reboot" \
  --region "$REGION"
```

Reboot the writer instance to apply:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE_ID" \
  --region "$REGION"
```

Wait for the instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$WRITER_INSTANCE_ID" \
  --region "$REGION"
```

### Create the Extension

Connect to your Aurora writer:

```bash
psql -h "$AURORA_WRITER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
CREATE EXTENSION IF NOT EXISTS apg_plan_mgmt;
```

Verify:

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'apg_plan_mgmt';
```

Expected output (yours will differ):
```
    extname     | extversion
----------------+------------
 apg_plan_mgmt  | 2.0
```

---

## Step 2 - Create Test Tables and Data

```sql
CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGSERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    country TEXT NOT NULL,
    tier TEXT NOT NULL DEFAULT 'standard',
    total_spend NUMERIC(15,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS purchases (
    purchase_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT REFERENCES customers(customer_id),
    product_sku TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    purchased_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_purchases_customer ON purchases(customer_id);
CREATE INDEX idx_purchases_date ON purchases(purchased_at);
CREATE INDEX idx_customers_country ON customers(country);
CREATE INDEX idx_customers_tier ON customers(tier);

-- Insert test data
INSERT INTO customers (email, country, tier, total_spend)
SELECT
    'user' || g || '@example.com',
    CASE (g % 4)
        WHEN 0 THEN 'US'
        WHEN 1 THEN 'UK'
        WHEN 2 THEN 'DE'
        ELSE 'FR'
    END,
    CASE (g % 3)
        WHEN 0 THEN 'standard'
        WHEN 1 THEN 'premium'
        ELSE 'enterprise'
    END,
    (random() * 50000)::NUMERIC(15,2)
FROM generate_series(1, 100000) g;

INSERT INTO purchases (customer_id, product_sku, amount, purchased_at)
SELECT
    (random() * 100000 + 1)::BIGINT,
    'SKU-' || (random() * 1000)::INT,
    (random() * 500)::NUMERIC(12,2),
    now() - (random() * interval '365 days')
FROM generate_series(1, 1000000);

ANALYZE customers, purchases;
```

---

## Step 3 - Enable Automatic Plan Capture

```sql
-- Enable automatic plan capture for the current session
SET apg_plan_mgmt.capture_plan_baselines = automatic;
```

With `automatic`, Aurora captures execution plans for every SQL statement. Plans start with `Unapproved` status.

Verify:

```sql
SHOW apg_plan_mgmt.capture_plan_baselines;
```

Expected output:
```
 apg_plan_mgmt.capture_plan_baselines
---------------------------------------
 automatic
```

---

## Step 4 - Run Queries to Capture Plans

Run the queries you want to manage. QPM will capture their plans:

```sql
-- Query 1: Customer lookup by country and tier
SELECT
    c.customer_id,
    c.email,
    c.total_spend,
    count(p.purchase_id) AS purchase_count,
    sum(p.amount) AS recent_spend
FROM customers c
LEFT JOIN purchases p ON c.customer_id = p.customer_id
WHERE c.country = 'US'
  AND c.tier = 'premium'
  AND p.purchased_at > now() - interval '90 days'
GROUP BY c.customer_id, c.email, c.total_spend
ORDER BY recent_spend DESC
LIMIT 100;

-- Query 2: Top customers by spend
SELECT
    customer_id,
    email,
    total_spend,
    country
FROM customers
WHERE country = $1
ORDER BY total_spend DESC
LIMIT 50;

-- Query 3: Purchase history for a customer
SELECT
    purchase_id,
    product_sku,
    amount,
    purchased_at
FROM purchases
WHERE customer_id = $1
ORDER BY purchased_at DESC
LIMIT 20;
```

For parameterized queries, use prepared statements so QPM captures the pattern:

```sql
PREPARE customer_purchases (bigint) AS
SELECT
    purchase_id,
    product_sku,
    amount,
    purchased_at
FROM purchases
WHERE customer_id = $1
ORDER BY purchased_at DESC
LIMIT 20;

EXECUTE customer_purchases(12345);
EXECUTE customer_purchases(67890);
EXECUTE customer_purchases(11111);
```

---

## Step 5 - View Captured Plans

```sql
SELECT
    sql_hash,
    plan_hash,
    status,
    enabled,
    estimated_total_cost,
    planning_time,
    executions,
    total_exec_time,
    left(sql_text, 80) AS sql_snippet
FROM apg_plan_mgmt.dba_plans
ORDER BY total_exec_time DESC;
```

Expected output (yours will differ):
```
  sql_hash  | plan_hash  | status     | enabled | estimated_total_cost | executions | total_exec_time | sql_snippet
------------+------------+------------+---------+---------------------+------------+-----------------+------------------------
 -1234567890 | -987654321 | Unapproved | t       |           4829.33   |          5 |         1284.23 | SELECT c.customer_id...
  1234512345 | 1122334455 | Unapproved | t       |            234.12   |          3 |           23.41 | SELECT customer_id...
```

All captured plans start as `Unapproved`.

---

## Step 6 - Review and Approve Plans

Get the details of a plan to review it:

```sql
-- See the full query text and execution plan
SELECT
    sql_text,
    plan_outline
FROM apg_plan_mgmt.dba_plans
WHERE sql_hash = -1234567890
  AND plan_hash = -987654321;
```

`plan_outline`: The execution plan in JSON format showing join types, index usage, and estimated costs.

Approve a plan that you have reviewed and confirmed is efficient:

```sql
SELECT apg_plan_mgmt.set_plan_status(
    -1234567890,   -- sql_hash
    -987654321,    -- plan_hash
    'Approved'     -- new status
);
```

Approve all currently captured plans (bulk approval for initial setup):

```sql
SELECT apg_plan_mgmt.set_plan_status(sql_hash, plan_hash, 'Approved')
FROM apg_plan_mgmt.dba_plans
WHERE status = 'Unapproved';
```

Verify:

```sql
SELECT sql_hash, plan_hash, status, enabled
FROM apg_plan_mgmt.dba_plans;
```

Expected output (yours will differ):
```
  sql_hash   | plan_hash  | status   | enabled
-------------+------------+----------+---------
 -1234567890 | -987654321 | Approved | t
  1234512345 | 1122334455 | Approved | t
```

---

## Step 7 - Enable Plan Enforcement

Now tell Aurora to only use approved plans:

```sql
SET apg_plan_mgmt.use_plan_baselines = true;
```

With this enabled:
- Approved plans are used
- New unapproved plans are still captured (so you can review them)
- If no approved plan exists for a query, the planner's choice is used (no enforcement yet for uncaptured queries)

Set this in the parameter group for permanent enforcement:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "aurora-pg16-ccm" \
  --parameters "ParameterName=apg_plan_mgmt.use_plan_baselines,ParameterValue=true,ApplyMethod=immediate" \
  --region "$REGION"
```

---

## Step 8 - Simulate a Plan Change and See QPM Protect You

Simulate what happens when statistics change and the planner would choose a different plan:

```sql
-- Insert a lot more data to change the statistics distribution
INSERT INTO customers (email, country, tier, total_spend)
SELECT
    'newuser' || g || '@example.com',
    'US',   -- heavily skewed to US now
    'premium',
    (random() * 100000)::NUMERIC(15,2)
FROM generate_series(1, 500000) g;

-- Run analyze to update statistics
ANALYZE customers;

-- Now run the country query again
-- QPM should still use the approved plan despite the statistics change
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    customer_id,
    email,
    total_spend,
    country
FROM customers
WHERE country = 'US'
ORDER BY total_spend DESC
LIMIT 50;
```

Check if QPM used an approved plan:

```sql
-- QPM annotates the plan with plan management info
-- Look for "SQL Plan Baseline" in the EXPLAIN output
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT customer_id, email, total_spend, country
FROM customers
WHERE country = 'US'
ORDER BY total_spend DESC
LIMIT 50;
```

In the explain output, look for a line like:
```
Query Identifier: ...
SQL Plan Baseline: Approved
```

This confirms QPM is enforcing the approved plan.

---

## Step 9 - Evolve Plans (Test New Plans Against Approved)

When a potential better plan is captured, use `evolve_plan_baselines` to test it:

```sql
-- Find unapproved plans that might be better
SELECT sql_hash, plan_hash, status, estimated_total_cost
FROM apg_plan_mgmt.dba_plans
WHERE status = 'Unapproved'
ORDER BY estimated_total_cost;

-- Test if the unapproved plan is actually faster than the approved one
-- This function executes both plans and compares results
SELECT apg_plan_mgmt.evolve_plan_baselines(
    sql_hash,
    plan_hash,
    0.10,          -- approval threshold: approve if new plan is 10% faster
    'approve'      -- action to take if threshold is met: 'approve' or 'reject'
)
FROM apg_plan_mgmt.dba_plans
WHERE status = 'Unapproved';
```

`evolve_plan_baselines` actually executes both plans. Run this during a maintenance window, not during peak load.

---

## Step 10 - Reject a Bad Plan

If you discover a plan that caused a performance regression, reject it so it is never used again:

```sql
SELECT apg_plan_mgmt.set_plan_status(
    sql_hash,
    plan_hash,
    'Rejected'
);
```

`Rejected` plans are permanently blocked, even if the planner would prefer them. The next time that query runs, the planner must use an Approved plan or (if none exists) choose a different non-rejected plan.

---

## Step 11 - Export and Import Plans

For testing changes in a staging environment before production:

Export plans:

```sql
-- Export to a JSON file
SELECT apg_plan_mgmt.export_plans_to_file(
    '/tmp/plan_baselines.json'
);
```

Import plans:

```sql
-- Import from file (on target instance)
SELECT apg_plan_mgmt.import_plans_from_file(
    '/tmp/plan_baselines.json',
    'Approved'   -- import with this status
);
```

On Aurora, use S3 for file exchange if the instances cannot share a filesystem.

---

## Cleanup

```sql
-- Disable plan management
SET apg_plan_mgmt.use_plan_baselines = false;
SET apg_plan_mgmt.capture_plan_baselines = off;

-- Remove all captured plans
SELECT apg_plan_mgmt.delete_plan(sql_hash, plan_hash)
FROM apg_plan_mgmt.dba_plans;

-- Drop test tables
DROP TABLE IF EXISTS purchases;
DROP TABLE IF EXISTS customers;
```

---

## Summary

You have:
- Enabled `apg_plan_mgmt` on Aurora PostgreSQL
- Captured plans automatically and reviewed them
- Approved good plans and enabled plan enforcement
- Simulated a statistics change and confirmed QPM protected the query
- Used `evolve_plan_baselines` to test candidate plans before approving
- Rejected a bad plan to permanently block it

Use QPM in these situations:
- Before a PostgreSQL minor version upgrade (capture and approve plans first)
- After a large data migration that changes statistics
- For your 10-20 most critical queries that must have stable performance

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| apg_plan_mgmt | Aurora PostgreSQL extension providing Query Plan Management |
| capture_plan_baselines | Parameter controlling whether plans are captured: off, manual, or automatic |
| use_plan_baselines | Parameter enforcing that only Approved plans are used |
| sql_hash | Hash identifying a normalized SQL statement in apg_plan_mgmt |
| plan_hash | Hash identifying a specific execution plan for a SQL statement |
| Unapproved | Plan has been captured but not yet reviewed |
| Approved | Plan has been reviewed and can be used |
| Rejected | Plan is permanently blocked |
| evolve_plan_baselines | Function that executes two plans and compares their actual performance |
