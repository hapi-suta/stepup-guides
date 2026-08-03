# USE 05 - Blue/Green Cutover
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Format:** End-to-end exercise. You execute a real Blue/Green deployment and switchover.
**Goal:** Deploy a schema change and engine version upgrade to a production-like RDS instance using Blue/Green deployment with zero write-blocking downtime.

**Prerequisites:**
- An RDS PostgreSQL instance (version 15.x)
- Backup retention period > 0
- AWS CLI configured

---

## Scenario

[CLIENT] runs a PostgreSQL 15.6 instance. The team wants to:
1. Add a new `tags` column to the `products` table
2. Create a GIN index for tag searches
3. Upgrade the engine to PostgreSQL 16.2

All of this must happen with less than 60 seconds of application impact. Blue/Green Deployments will handle this.

---

## Step 1 - Setup

```bash
export BLUE_INSTANCE="suta-t5-primary-hfa"
export BG_NAME="suta-t5-cutover-bg"
export AWS_REGION="us-east-1"
```

Confirm the blue instance is ready:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $BLUE_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Version:EngineVersion,BackupRetention:BackupRetentionPeriod}' \
  --output table
```

Status must be `available`. BackupRetention must be `> 0`.

---

## Step 2 - Prepare the Blue Environment

Make sure the Blue database has data to work with. Connect and verify:

```bash
export BLUE_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $BLUE_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;"
```

If the products table does not exist, create it:

```bash
psql -h $BLUE_HOST -U postgres -d postgres << 'EOF'
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    category TEXT
);

INSERT INTO products (name, price, category)
SELECT 'Product ' || i, (random()*1000)::NUMERIC(10,2),
    (ARRAY['Electronics','Clothing','Food','Books'])[floor(random()*4+1)]
FROM generate_series(1, 5000) AS s(i)
ON CONFLICT DO NOTHING;
EOF
```

Record the current state:

```bash
psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) AS product_count, SUM(price)::NUMERIC(12,2) AS total_value FROM products;"
```

Write down these numbers. They are your verification checksum.

---

## Step 3 - Create the Blue/Green Deployment with Version Upgrade

This creates Green with PostgreSQL 16.2 (if available in your region - check with `describe-db-engine-versions` first):

```bash
export TARGET_VERSION="16.2"

aws rds create-blue-green-deployment \
  --blue-green-deployment-name $BG_NAME \
  --source $BLUE_INSTANCE \
  --target-engine-version $TARGET_VERSION \
  --region $AWS_REGION
```

If PostgreSQL 16.2 is not available, use the latest available PG16 version:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --major-engine-version "16" \
  --region $AWS_REGION \
  --query 'DBEngineVersions[*].EngineVersion' \
  --output table
```

Use the highest version number listed.

Get the deployment ID:

```bash
export BG_ID=$(aws rds describe-blue-green-deployments \
  --region $AWS_REGION \
  --query "BlueGreenDeployments[?BlueGreenDeploymentName=='${BG_NAME}'].BlueGreenDeploymentIdentifier" \
  --output text)

echo "Deployment ID: $BG_ID"
```

Wait for provisioning to complete:

```bash
aws rds wait blue-green-deployment-available \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION
```

---

## Step 4 - Verify the Green Environment

Get Green instance details:

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].{Status:Status,Target:Target}' \
  --output table
```

The `Target` field is the Green instance ARN. Extract the instance name:

```bash
export GREEN_INSTANCE=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].SwitchoverDetails[0].TargetMember' \
  --output text | sed 's|.*db/||')

echo "Green instance: $GREEN_INSTANCE"
```

Verify Green is running the target version:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $GREEN_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].EngineVersion' \
  --output text
```

Expected output: `16.2` (or your target version)

---

## Step 5 - Verify Replication on Green

Get the Green endpoint:

```bash
export GREEN_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $GREEN_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
```

Check replication lag:

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"
```

Expected output: lag under 1 second

Check the data matches Blue:

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) AS product_count, SUM(price)::NUMERIC(12,2) AS total_value FROM products;"
```

This must match your checksum from Step 2.

---

## Step 6 - Apply the Schema Changes to Green

With Green verified and replicating, apply the schema migration:

```bash
psql -h $GREEN_HOST -U postgres -d postgres << 'EOF'
\timing on

-- Step 1: Add tags column
ALTER TABLE products ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

-- Step 2: Seed some tags
UPDATE products SET tags = ARRAY['sale', 'featured'] WHERE price > 800;
UPDATE products SET tags = ARRAY['clearance'] WHERE price < 50;

-- Step 3: Create GIN index for array search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_tags
    ON products USING GIN(tags);

-- Verify
SELECT
    COUNT(*) FILTER (WHERE array_length(tags, 1) > 0) AS tagged_products,
    COUNT(*) FILTER (WHERE 'sale' = ANY(tags)) AS sale_products
FROM products;
EOF
```

Expected output (yours will differ):

```
 tagged_products | sale_products
-----------------+---------------
             874 |           874
```

Record the timing for each step. This is your production migration estimate.

---

## Step 7 - Verify Schema Change Does NOT Exist on Blue

```bash
psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'tags';"
```

Expected output:

```
 column_name
-------------
(0 rows)
```

Good. Blue does not have the tags column. This is expected - schema changes on Green do not propagate back to Blue automatically.

---

## Step 8 - Final Pre-Switchover Checklist

Run through this checklist before triggering switchover:

```
PRE-SWITCHOVER CHECKLIST
==========================

[ ] Green is in AVAILABLE state
[ ] Replication lag < 1 second
[ ] Green has the correct engine version
[ ] Schema changes applied and verified on Green
[ ] Application team is standing by
[ ] Rollback procedure is documented (Blue still running)
[ ] CloudWatch alerts are active
[ ] Incident channel is open in Slack
[ ] It is within the agreed maintenance window
```

Check lag one final time:

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS final_lag_check;"
```

If lag is > 5 seconds, wait. Do not switchover with high lag.

---

## Step 9 - Execute the Switchover

Start your timer.

### Console

1. Go to **RDS > Blue/green deployments**.
2. Select your deployment.
3. Click **Switch over**.
4. Click **Switch over** to confirm.

### CLI

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION
```

Monitor the switchover:

```bash
watch -n 5 "aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].Status' \
  --output text"
```

Stop when you see `SWITCHOVER_COMPLETED`.

Stop your timer. Record elapsed seconds.

---

## Step 10 - Post-Switchover Validation

The Blue DNS endpoint now points to what was Green. Validate:

```bash
psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

You should see PostgreSQL 16.x because the Blue endpoint now points to the upgraded Green instance.

Verify the schema change is present:

```bash
psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'products' ORDER BY ordinal_position;"
```

The `tags` column should now appear.

Verify the row counts match your original checksum:

```bash
psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*), SUM(price)::NUMERIC(12,2) FROM products;"
```

Verify the GIN index:

```bash
psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT indexname FROM pg_indexes WHERE tablename = 'products';"
```

---

## Step 11 - Test a Tag Search Query

```bash
psql -h $BLUE_HOST -U postgres -d postgres << 'EOF'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, price, tags
FROM products
WHERE 'sale' = ANY(tags)
ORDER BY price DESC
LIMIT 10;
EOF
```

The query should use `idx_products_tags` (Bitmap Index Scan or Index Scan). If it uses a sequential scan, the index may not have been replicated. Check by listing indexes.

---

## Step 12 - Cleanup

After 24 hours of confirming production is healthy, delete the old Blue environment.

```bash
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier $BG_ID \
  --delete-target \
  --region $AWS_REGION
```

---

## Drill Results

Record your results:

```
BLUE/GREEN CUTOVER RESULTS
============================

Date: [DATE]
Deployment ID: [BG_ID]
Blue version (before): PostgreSQL 15.6
Green version: PostgreSQL 16.2
Schema change: Added tags column + GIN index

Provisioning time: [X] minutes
Schema migration time: [X] seconds
Switchover duration: [X] seconds

Application write pause during switchover: [X] seconds
Total user-visible impact: [X] seconds

RTO target: 60 seconds
Actual RTO: [X] seconds
Target met: [ ] Yes  [ ] No

Issues encountered: [NONE / DESCRIBE]
Rollback triggered: [ ] No  [ ] Yes - reason: [REASON]
```

---

## Reflection

1. In this exercise, Blue/Green let you do a major version upgrade AND a schema change together. Why would you NOT want to combine multiple changes in one Blue/Green deployment for a highly sensitive system?

2. You noticed that schema changes on Green do not replicate back to Blue. What does this mean for application compatibility during the period between schema change deployment and switchover? How should your application handle this?

3. Compare the downtime from a Blue/Green switchover to the downtime from an in-place major version upgrade. Which approach would you recommend for a database with 10,000 concurrent users?

4. What is the maximum safe replication lag before switchover? Justify your answer.
