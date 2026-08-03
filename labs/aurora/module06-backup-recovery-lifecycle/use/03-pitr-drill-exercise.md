# USE 03 - PITR Drill Exercise
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Format:** Hands-on timed exercise against a live AWS environment
**Goal:** Execute a complete PITR drill from simulated data loss through verified recovery. Measure and record your actual RTO.

**Important:** Run this drill on a non-production cluster. You will intentionally destroy data.

---

## Before You Start

Set a timer. Your target RTO for this drill is 30 minutes from the moment you detect the "incident" to when the data is verified as restored.

Have your variables ready:

```bash
export CLUSTER_ID="devops-lab-cluster"
export RESTORED_CLUSTER="devops-lab-drill-restore"
export RESTORED_INSTANCE="devops-lab-drill-inst"
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="your-subnet-group"
export VPC_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

---

## Phase 1 - Setup (Before the Drill)

This phase simulates the "before" state. Complete it before starting the timer.

### Step 1.1 - Create the Dataset

Get the cluster endpoint:

```bash
export CLUSTER_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

Connect and create a realistic dataset:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres
```

```sql
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    company_name TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    tier TEXT CHECK (tier IN ('bronze','silver','gold','platinum')),
    contract_value NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE invoices (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(id),
    invoice_number TEXT UNIQUE NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    status TEXT DEFAULT 'pending',
    issued_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO customers (company_name, contact_email, tier, contract_value)
SELECT
    '[COMPANY] ' || i,
    'contact' || i || '@company' || i || '.example.com',
    (ARRAY['bronze','silver','gold','platinum'])[floor(random()*4+1)],
    (random() * 100000)::NUMERIC(12,2)
FROM generate_series(1, 50) AS s(i);

INSERT INTO invoices (customer_id, invoice_number, amount, status)
SELECT
    floor(random()*50+1)::INTEGER,
    'INV-2026-' || LPAD(i::TEXT, 5, '0'),
    (random() * 5000)::NUMERIC(10,2),
    (ARRAY['pending','paid','overdue'])[floor(random()*3+1)]
FROM generate_series(1, 200) AS s(i);

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'invoices', COUNT(*) FROM invoices;
```

Expected output:

```
 table_name | row_count
------------+-----------
 customers  |        50
 invoices   |       200
```

Record a verification fingerprint:

```sql
SELECT SUM(contract_value)::NUMERIC(12,2) AS total_contract_value
FROM customers;
```

Write down the total_contract_value. You will verify this matches after recovery.

Exit psql:

```sql
\q
```

### Step 1.2 - Record the "Good State" Time

```bash
date -u
```

Write down this timestamp. Example: `2026-06-09 15:00:00 UTC`

Wait 5 minutes before the next step. This gives backup data time to sync to S3.

---

## Phase 2 - The Incident (Start Your Timer Here)

**START TIMER NOW.**

You have just received an alert:

```
@oncall - URGENT: someone ran a script in prod DB.
tables customers and invoices are GONE.
application is returning 500 errors.
RTO: 30 min. Go.
```

### Step 2.1 - Simulate the Drop

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "DROP TABLE invoices; DROP TABLE customers CASCADE;"
```

Confirm the tables are gone:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
```

Expected output:

```
 table_name
------------
(0 rows)
```

Record the incident time:

```bash
date -u
```

---

## Phase 3 - Recovery

### Step 3.1 - Check the Latest Restorable Time

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].LatestRestorableTime' \
  --output text
```

Confirm this timestamp is AFTER your good-state timestamp from Step 1.2.

### Step 3.2 - Set Your Target Restore Time

```bash
export RESTORE_TIME="2026-06-09T14:58:00Z"
```

Replace with a time 2 minutes before your recorded incident time.

### Step 3.3 - Initiate PITR

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier $CLUSTER_ID \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --restore-to-time $RESTORE_TIME \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION
```

Add an instance to the restored cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION
```

### Step 3.4 - Wait for the Restore

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

While waiting, prepare the reimport commands (do not waste time idle).

### Step 3.5 - Verify the Recovered Data

```bash
export RESTORED_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT 'customers' AS t, COUNT(*) FROM customers UNION ALL SELECT 'invoices', COUNT(*) FROM invoices;"
```

Expected: customers=50, invoices=200

Verify the fingerprint:

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT SUM(contract_value)::NUMERIC(12,2) AS total FROM customers;"
```

This must match the value from Step 1.1.

### Step 3.6 - Export and Reimport to Production

```bash
pg_dump -h $RESTORED_HOST -U postgres -d postgres \
  -t customers -t invoices \
  -f /tmp/dr_recovery.sql
```

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -f /tmp/dr_recovery.sql
```

Verify on production:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT 'customers' AS t, COUNT(*) FROM customers UNION ALL SELECT 'invoices', COUNT(*) FROM invoices;"
```

**STOP TIMER NOW.**

---

## Phase 4 - Cleanup

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION

aws rds delete-db-cluster \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION

rm -f /tmp/dr_recovery.sql
```

---

## Phase 5 - Post-Drill Review

Record these metrics:

```
DR DRILL RESULTS
=================

Date: [DATE]
Incident detected: [TIME]
PITR initiated: [TIME]
PITR completed: [TIME]
Data verified on restored cluster: [TIME]
Data reimported to production: [TIME]

Total RTO (timer stop - timer start): [MINUTES]

Did we meet the 30-minute target? YES / NO

If NO - what caused the delay?
  [ ] Slow restore (cluster size)
  [ ] Could not find the right restore timestamp
  [ ] Verification took longer than expected
  [ ] Import step was slower than expected
  [ ] Other: _______________
```

---

## Drill Variants (Advanced)

Once you complete the standard drill in under 30 minutes, try these:

**Variant A - Corrupted Data (Not Dropped)**
Instead of DROP TABLE, run: `UPDATE customers SET contract_value = 0;`
Recovery is harder because the table exists but data is wrong.

**Variant B - Full Cluster Cutover**
Instead of exporting one table, update the application connection string to the restored cluster.

**Variant C - Cross-Region DR**
Restore from a cross-region snapshot copy in `us-west-2`. Measure how much longer it takes.
