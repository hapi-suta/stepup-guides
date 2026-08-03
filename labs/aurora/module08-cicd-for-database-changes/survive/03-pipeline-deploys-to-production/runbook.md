# SURVIVE 03: Pipeline Deploys to Production

**Module 08: CI/CD for Database Changes**
**Difficulty:** Hard
**Estimated Time:** 45 minutes
**Cluster:** devops-lab-cluster

---

## The Scenario

It is 11:45 AM on a Friday. A developer pushed a migration to the wrong branch. The CI/CD pipeline picked it up and deployed it to production instead of staging. The migration was a test script that:

1. Dropped the `phone` column from the `customers` table
2. Created a `test_load_data` table with 10,000 test rows
3. Reset all customer tiers to `'free'`

The damage:
- **50,000 customer phone numbers are gone** (column dropped)
- **A test table with fake data exists in production**
- **All customer tiers (free/pro/enterprise) were reset to 'free'** - billing and access control are affected

The application is still running. Customers with `pro` and `enterprise` tiers are now being treated as `free` users. They are losing access to premium features.

---

## Setup

Run the inject script:

**On your Mac terminal:**

```bash
export AURORA_ENDPOINT=YOUR_AURORA_ENDPOINT
export DB_USER=postgres
```

```bash
chmod +x inject.sh
```

```bash
./inject.sh
```

---

## Your Mission

1. Assess the full damage
2. Determine what can be recovered
3. Remediate what you can
4. Document what is permanently lost
5. Implement guardrails to prevent recurrence

---

## Investigation

### Step 1: Assess Schema Damage

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d survive_production
```

Compare production schema against staging:

```sql
-- What columns does production have?
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'customers'
ORDER BY ordinal_position;
```

Open a second terminal and check staging:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d survive_staging -c "
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'customers'
ORDER BY ordinal_position;
"
```

You will see that production is missing the `phone` column.

### Step 2: Assess Data Damage

Back in the production psql session:

```sql
-- Check tier distribution (all should be 'free' - the damage)
SELECT tier, count(*) FROM customers GROUP BY tier;
```

Expected output:
```
 tier  | count
-------+-------
 free  | 50000
```

All 50,000 customers are now `free`. Before the migration, approximately 1/3 were `pro` and 1/3 were `enterprise`.

```sql
-- Check for the test table
SELECT count(*) FROM test_load_data;
```

Expected output:
```
 count
-------
 10000
```

10,000 test rows exist in production.

### Step 3: Assess What Can Be Recovered

| Damage | Recoverable? | Method |
|--------|-------------|--------|
| Phone column dropped | **NO** (without backup) | Column data is gone. Need backup or PITR. |
| Tiers reset to 'free' | **PARTIALLY** | If order history correlates with tier, can re-derive. |
| Test table in production | **YES** | Drop the table. |

---

## Remediation

### Step 4: Remove the Test Table

```sql
DROP TABLE IF EXISTS test_load_data;
```

Expected output:
```
DROP TABLE
```

### Step 5: Re-Add the Phone Column

The phone data is lost, but you can re-add the column structure:

```sql
SET lock_timeout = '5s';
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
```

The column is back, but all values are NULL. In a real incident, you would restore phone numbers from:
- A backup or Aurora PITR/backtrack
- The application's backup systems
- A data warehouse or analytics database
- Customer communication logs

### Step 6: Restore Customer Tiers

In this lab, we can use order count as a proxy for tier assignment (same logic the original migration used):

```sql
UPDATE customers c
SET tier = CASE
    WHEN order_count >= 10 THEN 'enterprise'
    WHEN order_count >= 3 THEN 'pro'
    ELSE 'free'
END
FROM (
    SELECT customer_id, count(*) AS order_count
    FROM orders
    GROUP BY customer_id
) sub
WHERE c.customer_id = sub.customer_id;
```

Verify the distribution looks reasonable:

```sql
SELECT tier, count(*) FROM customers GROUP BY tier ORDER BY tier;
```

You should now see a mix of free, pro, and enterprise tiers. The exact distribution will differ from the original, but it is better than everyone being `free`.

**Important:** In production, you would verify this logic with the product team before applying it. The tier assignment rules might be more complex than order count.

### Step 7: Verify Remediation

```sql
-- Phone column exists (values are NULL - data loss accepted)
SELECT column_name FROM information_schema.columns
WHERE table_name = 'customers' AND column_name = 'phone';
```

```sql
-- Test table is gone
SELECT count(*) FROM information_schema.tables
WHERE table_name = 'test_load_data';
```

Expected: 0

```sql
-- Tiers are distributed (not all 'free')
SELECT tier, count(*) FROM customers GROUP BY tier;
```

Expected: a mix of free, pro, enterprise.

```sql
\q
```

---

## Implementing Guardrails

After the incident, implement these safeguards to prevent it from happening again.

### Guardrail 1: Environment Validation in Migrations

Add a check at the top of every migration that verifies the target environment:

```sql
-- Fail if this migration runs against production
DO $$
BEGIN
    IF current_database() = 'production' OR current_database() LIKE '%prod%' THEN
        RAISE EXCEPTION 'This migration is not approved for production. Database: %', current_database();
    END IF;
END $$;
```

### Guardrail 2: Separate Credentials per Environment

Production should use a different database user than staging. The staging pipeline should not have production credentials.

In GitHub Actions:
- Staging workflow uses `STAGING_DB_*` secrets
- Production workflow uses `PROD_DB_*` secrets
- The staging user's password does not work on production

### Guardrail 3: Branch Protection

- Staging migrations deploy from the `develop` branch
- Production migrations deploy only from `main`
- `main` requires PR review and CI pass before merge

### Guardrail 4: Migration Naming Convention

Prefix staging-only migrations:

```
V10_STAGING__load_test_data.sql
```

Add a CI lint rule that blocks `*_STAGING*` files from being deployed to production.

### Guardrail 5: Destructive Operation Check

Add a CI step that checks for dangerous operations:

```bash
# Fail if any migration contains DROP COLUMN or DROP TABLE
if grep -rn "DROP COLUMN\|DROP TABLE\|TRUNCATE\|DELETE FROM" migrations/sql/ | grep -v "^--" | grep -v "IF EXISTS"; then
    echo "WARNING: Destructive operation found. Requires DBA approval."
    exit 1
fi
```

### Guardrail 6: Pre-Deploy Snapshot

Before every production deployment, automatically create an Aurora snapshot:

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-snapshot-identifier "pre-migration-$(date +%Y%m%d-%H%M%S)"
```

Add this as a step in the production deployment job, before running Flyway.

---

## Incident Documentation Template

Every production incident should have a post-incident document:

```
## Incident: Wrong Environment Deployment
**Date:** 2026-06-09
**Duration:** 45 minutes (detection to remediation)
**Severity:** High (data loss, customer impact)

### What Happened
A staging migration was deployed to production due to [cause].

### Impact
- 50,000 customer phone numbers lost
- All customer tiers reset to 'free'
- Premium features inaccessible for ~45 minutes

### Root Cause
[Pipeline misconfiguration / wrong branch / missing environment check]

### Remediation
- Test table dropped
- Phone column re-added (data permanently lost)
- Tiers restored from order history approximation
- [X] customers notified to re-enter phone numbers

### Prevention
1. Added environment validation check to all migrations
2. Separated credentials between staging and production
3. Added destructive operation lint check to CI
4. Enabled pre-deploy snapshots for production
```

---

## Validation

Run the validation script:

```bash
chmod +x validate.sh
```

```bash
./validate.sh
```

All checks should show PASS.
