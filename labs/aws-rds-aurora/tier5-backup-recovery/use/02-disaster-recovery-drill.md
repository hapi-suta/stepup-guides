# USE 02 - Disaster Recovery Drill
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Format:** Hands-on timed exercise against a live AWS environment
**Goal:** Execute a complete DR drill from simulated data loss through verified recovery. Measure and record your actual RTO.

**Important:** Run this drill on a non-production instance. You will intentionally destroy data.

---

## Before You Start

Set a timer. Your target RTO for this drill is 30 minutes from the moment you detect the "incident" to when the data is verified as restored.

Have your variables ready:

```bash
export DB_INSTANCE="suta-t5-primary-hfa"
export RESTORED_INSTANCE="suta-t5-drill-restore-hfa"
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="your-subnet-group"
export VPC_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

---

## Phase 1 - Setup (Before the Drill)

This phase simulates the "before" state. Complete it before starting the timer.

### Step 1.1 - Create the Dataset

Connect to your instance:

```bash
export DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $DB_HOST -U postgres -d postgres
```

Create a realistic dataset:

```sql
-- Create schema
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

-- Insert customers
INSERT INTO customers (company_name, contact_email, tier, contract_value)
SELECT
    '[COMPANY] ' || i,
    'contact' || i || '@company' || i || '.example.com',
    (ARRAY['bronze','silver','gold','platinum'])[floor(random()*4+1)],
    (random() * 100000)::NUMERIC(12,2)
FROM generate_series(1, 50) AS s(i);

-- Insert invoices
INSERT INTO invoices (customer_id, invoice_number, amount, status)
SELECT
    floor(random()*50+1)::INTEGER,
    'INV-2025-' || LPAD(i::TEXT, 5, '0'),
    (random() * 5000)::NUMERIC(10,2),
    (ARRAY['pending','paid','overdue'])[floor(random()*3+1)]
FROM generate_series(1, 200) AS s(i);

-- Verify data
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

Record a row count fingerprint:

```sql
SELECT
    SUM(contract_value)::NUMERIC(12,2) AS total_contract_value,
    COUNT(DISTINCT tier) AS tier_count
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

Write down this timestamp. Example: `2025-05-30 15:00:00 UTC`

Wait 5 minutes before the next step. This gives WAL time to upload to S3 and ensures your "incident" is clearly after your good state.

---

## Phase 2 - The Incident (Start Your Timer Here)

**START TIMER NOW.**

You have just received a Slack message:

```
@oncall - URGENT: someone ran a script in prod DB.
tables customers and invoices are GONE.
application is returning 500 errors.
RTO: 30 min. Go.
```

### Step 2.1 - Verify the Damage

Connect and confirm:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "\dt"
```

Then simulate the actual drop (do this NOW to start the incident clock):

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "DROP TABLE invoices; DROP TABLE customers CASCADE;"
```

Confirm the tables are gone:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
```

Expected output (confirming the drop):

```
 table_name
------------
(0 rows)
```

Record the incident time:

```bash
date -u
```

Example: `2025-05-30 15:06:22 UTC`

---

## Phase 3 - Recovery

### Step 3.1 - Check the Latest Restorable Time

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].LatestRestorableTime' \
  --output text
```

Make sure this timestamp is AFTER your good-state timestamp from Step 1.2 (it should be, unless backups were disabled).

### Step 3.2 - Calculate Your Target Restore Time

Your target is 1-2 minutes before the DROP TABLE. Use your good-state timestamp from Step 1.2.

```bash
# Set to your good-state time (2 minutes before the drop)
export RESTORE_TIME="2025-05-30T15:04:00Z"
```

Replace with a time 2 minutes before your recorded incident time.

### Step 3.3 - Initiate PITR

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier $DB_INSTANCE \
  --target-db-instance-identifier $RESTORED_INSTANCE \
  --restore-time $RESTORE_TIME \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Record the time you submitted this command.

### Step 3.4 - Monitor the Restore

While restore is running, do NOT sit idle. In a real incident you would:
- Update the incident ticket
- Notify the application team of estimated ETA
- Prepare the reimport commands

Monitor restore progress:

```bash
watch -n 30 "aws rds describe-db-instances \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text"
```

`watch -n 30` re-runs the command every 30 seconds. Press Ctrl+C to stop.

Or use the wait command and take notes while it runs:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

### Step 3.5 - Get the Restored Instance Endpoint

```bash
export RESTORED_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo $RESTORED_HOST
```

### Step 3.6 - Verify the Recovered Data

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
```

Expected output:

```
 table_name
------------
 customers
 invoices
(2 rows)
```

Verify the row counts:

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT 'customers' AS table_name, COUNT(*) FROM customers UNION ALL SELECT 'invoices', COUNT(*) FROM invoices;"
```

Expected output:

```
 table_name | count
------------+-------
 customers  |    50
 invoices   |   200
```

Verify the fingerprint matches:

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT SUM(contract_value)::NUMERIC(12,2) AS total_contract_value FROM customers;"
```

This must match the value you recorded in Step 1.1.

---

## Phase 4 - Data Reimport to Production

### Step 4.1 - Export Recovered Data

```bash
pg_dump -h $RESTORED_HOST -U postgres -d postgres \
  -t customers \
  -t invoices \
  --section=data \
  -f /tmp/dr_recovery_$(date +%Y%m%d_%H%M%S).sql
```

`--section=data` exports only INSERT statements, not CREATE TABLE. The tables need to be recreated manually first.

### Step 4.2 - Recreate Tables on Production

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
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
EOF
```

### Step 4.3 - Import the Recovered Data

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -f /tmp/dr_recovery_*.sql
```

### Step 4.4 - Verify Production is Restored

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT 'customers' AS table_name, COUNT(*) FROM customers UNION ALL SELECT 'invoices', COUNT(*) FROM invoices;"
```

Expected output:

```
 table_name | count
------------+-------
 customers  |    50
 invoices   |   200
```

**STOP TIMER NOW.**

---

## Phase 5 - Cleanup

Delete the restored instance (it served its purpose):

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION
```

Remove the dump file:

```bash
rm /tmp/dr_recovery_*.sql
```

---

## Phase 6 - Post-Drill Review

Record these metrics:

```
DR DRILL RESULTS
=================

Date: [DATE]
Incident detected: [TIME]
PITR initiated: [TIME]
PITR completed: [TIME]
Data verified on restored instance: [TIME]
Data reimported to production: [TIME]

Total RTO (timer stop - timer start): [MINUTES]

Did we meet the 30-minute target? YES / NO

If NO - what caused the delay?
  [ ] Slow restore (database size)
  [ ] Could not find the right restore timestamp
  [ ] Verification took longer than expected
  [ ] Import step was slower than expected
  [ ] Other: _______________
```

### What Would Shorten This RTO?

- Pre-written runbook: yes, you have one now
- Knowing the exact drop timestamp from application logs (saves guessing)
- Smaller database size (larger databases = longer restore)
- Pre-staging the pg_dump and import commands before the restore finishes
- Having the subnet group and security group IDs already in a runbook

---

## Drill Variants (Advanced)

Once you can complete the standard drill in under 30 minutes, try these variations:

**Variant A - Corrupted Data (Not Dropped)**
Instead of DROP TABLE, run: `UPDATE customers SET contract_value = 0;`
Recovery is harder because the table exists but data is wrong. You need to:
1. Identify exactly when the corruption started
2. Restore to just before that point
3. Export the specific rows that differ from production

**Variant B - Aurora Clone Instead of PITR**
For Aurora clusters: instead of PITR, create a fast clone at the current time, then recover the data from the clone. Measure how much faster this is.

**Variant C - Cross-Region DR**
Simulate a regional failure. Restore from a cross-region snapshot copy in `us-west-2`. You will need to have set up cross-region copies (BUILD 01, Step 6) in advance.
