# SURVIVE 01 - Accidental Table Drop
## Runbook: Recovery via PITR

**Scenario:** A critical table was dropped. The application is returning errors. Recover the data within 30 minutes.

**What the student sees:**
```
ALERT: Application throwing 500 errors
ERROR: relation "critical_orders" does not exist
Table critical_orders is missing from the database.
```

---

## Your Objective

Recover the `critical_orders` table and all its rows to the production database within **30 minutes**.

Do NOT look at the validate.sh script until you have attempted recovery.

---

## Step 1 - Confirm the Incident

Connect to the database and verify:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "\dt critical_orders"
```

Expected:

```
Did not find any relation named "critical_orders".
```

Confirmed. The table is gone.

---

## Step 2 - Check the Latest Restorable Time

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].LatestRestorableTime' \
  --output text
```

This must be a time AFTER the table was created and data was inserted.

---

## Step 3 - Find the Right Restore Timestamp

You need to restore to a point BEFORE the DROP TABLE but AFTER the data was inserted.

Check the application logs or the CloudWatch log group for the RDS instance to find when the DROP TABLE was executed. Look for the PostgreSQL log line:

```
LOG:  statement: DROP TABLE critical_orders;
```

Your target restore time is 2-3 minutes before that log entry.

If you do not have logs available, recover to 10 minutes ago and verify the table exists. Adjust if needed.

---

## Step 4 - Set Your Target Restore Time

```bash
# Set to 5 minutes before the incident
export RESTORE_TIME="YYYY-MM-DDTHH:MM:SSZ"
export RESTORED_INSTANCE="suta-t5-survive01-restore"
```

Replace the timestamp with your calculated target.

---

## Step 5 - Initiate PITR

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

---

## Step 6 - Wait for the Restore

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

Estimated time: 10-20 minutes for db.t3.micro.

---

## Step 7 - Verify the Table on the Restored Instance

```bash
export RESTORED_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM critical_orders;"
```

Expected: `1000`

If you see 0 or the table does not exist, your restore time was too late. Delete the restored instance and try again with an earlier timestamp.

---

## Step 8 - Export the Table from Restored Instance

```bash
pg_dump -h $RESTORED_HOST -U postgres -d postgres \
  -t critical_orders \
  --data-only \
  --column-inserts \
  -f /tmp/critical_orders_recovery.sql
```

---

## Step 9 - Reimport to Production

Recreate the table schema on production:

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
CREATE TABLE critical_orders (
    id SERIAL PRIMARY KEY,
    customer_ref TEXT NOT NULL,
    order_total NUMERIC(12,2) NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);
EOF
```

Import the data:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -f /tmp/critical_orders_recovery.sql
```

---

## Step 10 - Verify Production Recovery

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
SELECT COUNT(*) AS row_count FROM critical_orders;
SELECT SUM(order_total)::NUMERIC(12,2) AS total_value FROM critical_orders;
SELECT status, COUNT(*) FROM critical_orders GROUP BY status ORDER BY status;
EOF
```

---

## Step 11 - Cleanup

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

rm -f /tmp/critical_orders_recovery.sql
```

---

## Run Validate Script

```bash
bash validate.sh
```

---

## Key Lessons

1. PITR can recover any data that existed within the backup retention window
2. The restore creates a new instance - it does NOT modify the original
3. For a single-table recovery, pg_dump + reimport is faster than a full cutover
4. Knowing the exact DROP TABLE timestamp is critical - application logs are your friend
5. PITR restore time scales with instance size and how much WAL needs to be replayed
