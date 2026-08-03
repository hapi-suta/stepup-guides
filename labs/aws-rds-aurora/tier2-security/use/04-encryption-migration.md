# Use 04 - Encryption Migration

**Time:** 30 minutes
**Prerequisite:** Build 04 (Encryption at Rest)

---

## Scenario

[COMPANY] acquired a startup six months ago. Their RDS instance is not encrypted. A new compliance requirement says all databases holding customer data must be encrypted within 30 days.

You are the DBA. You must:
1. Verify the instance is unencrypted
2. Estimate the downtime window
3. Execute the snapshot-copy-restore migration
4. Verify encryption on the new instance
5. Validate the data is intact
6. Document the process for the compliance team

---

## Setup

Create an unencrypted instance to practice with (skip if you already have one from Build 04):

```bash
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="my-db-subnet-group"

aws rds create-db-instance \
  --db-instance-identifier "unencrypted-legacy-db" \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password "LegacyPass1!" \
  --allocated-storage 20 \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Wait for it to be available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "unencrypted-legacy-db" \
  --region $AWS_REGION
```

Connect and add some test data:

```bash
export LEGACY_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "unencrypted-legacy-db" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $AWS_REGION)

psql "host=$LEGACY_HOST port=5432 dbname=postgres user=postgres"
```

```sql
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO customers (name, email) VALUES
  ('Alice Johnson', 'alice@example.com'),
  ('Bob Smith', 'bob@example.com'),
  ('Carol White', 'carol@example.com');

SELECT COUNT(*) FROM customers;
```

Expected output:

```
 count
───────
     3
```

Exit psql:

```sql
\q
```

---

## Task 1 - Confirm the Instance Is Unencrypted

```bash
aws rds describe-db-instances \
  --db-instance-identifier "unencrypted-legacy-db" \
  --query 'DBInstances[0].{Encrypted:StorageEncrypted,Engine:Engine,Version:EngineVersion}' \
  --output table \
  --region $AWS_REGION
```

Confirm `Encrypted: False` appears in the output.

---

## Task 2 - Plan the Migration

Answer these questions before starting:

1. How much data is in the database?

```bash
aws rds describe-db-instances \
  --db-instance-identifier "unencrypted-legacy-db" \
  --query 'DBInstances[0].AllocatedStorage' \
  --output text \
  --region $AWS_REGION
```

2. How long will the snapshot take? (Rule of thumb: ~1-2 minutes per GB for most instances.)

3. When is the best time to run this migration? (Consider: when is traffic lowest?)

4. What is your rollback plan if something goes wrong?

Write your answers down before proceeding.

---

## Task 3 - Take the Snapshot

```bash
export SNAP_DATE=$(date +%Y%m%d-%H%M)
export SOURCE_SNAP="legacy-db-premigration-${SNAP_DATE}"

aws rds create-db-snapshot \
  --db-instance-identifier "unencrypted-legacy-db" \
  --db-snapshot-identifier $SOURCE_SNAP \
  --region $AWS_REGION
```

Check snapshot status:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier $SOURCE_SNAP \
  --query 'DBSnapshots[0].{Status:Status,Encrypted:Encrypted,PercentProgress:PercentProgress}' \
  --output table \
  --region $AWS_REGION
```

Wait for it to complete:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier $SOURCE_SNAP \
  --region $AWS_REGION
```

Verify the snapshot is unencrypted (expected at this point):

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier $SOURCE_SNAP \
  --query 'DBSnapshots[0].Encrypted' \
  --output text \
  --region $AWS_REGION
```

Expected output:

```
False
```

---

## Task 4 - Copy the Snapshot with Encryption

```bash
export ENCRYPTED_SNAP="${SOURCE_SNAP}-encrypted"

aws rds copy-db-snapshot \
  --source-db-snapshot-identifier $SOURCE_SNAP \
  --target-db-snapshot-identifier $ENCRYPTED_SNAP \
  --kms-key-id "aws/rds" \
  --region $AWS_REGION
```

Track progress:

```bash
watch -n 10 "aws rds describe-db-snapshots \
  --db-snapshot-identifier $ENCRYPTED_SNAP \
  --query 'DBSnapshots[0].{Status:Status,Encrypted:Encrypted,PercentProgress:PercentProgress}' \
  --output table \
  --region $AWS_REGION"
```

Press `Ctrl+C` when status shows `available`.

Or just wait:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier $ENCRYPTED_SNAP \
  --region $AWS_REGION
```

Verify the copy is encrypted:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier $ENCRYPTED_SNAP \
  --query 'DBSnapshots[0].{Encrypted:Encrypted,KmsKeyId:KmsKeyId}' \
  --output table \
  --region $AWS_REGION
```

Expected output:

```
+----------+-----------------------------------------------------+
| Encrypted|  True                                               |
| KmsKeyId |  arn:aws:kms:us-east-1:123456789012:key/...         |
+----------+-----------------------------------------------------+
```

---

## Task 5 - Restore the Encrypted Instance

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "encrypted-migrated-db" \
  --db-snapshot-identifier $ENCRYPTED_SNAP \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Wait for it to be available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "encrypted-migrated-db" \
  --region $AWS_REGION
```

This takes 5-10 minutes.

---

## Task 6 - Validate the New Instance

Get the new endpoint:

```bash
export NEW_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "encrypted-migrated-db" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $AWS_REGION)

echo "New host: $NEW_HOST"
```

Check encryption status:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "encrypted-migrated-db" \
  --query 'DBInstances[0].{Encrypted:StorageEncrypted,KmsKey:KmsKeyId}' \
  --output table \
  --region $AWS_REGION
```

Confirm `Encrypted: True`.

Connect and verify the data is intact:

```bash
psql "host=$NEW_HOST port=5432 dbname=postgres user=postgres"
```

```sql
SELECT COUNT(*) FROM customers;
SELECT * FROM customers ORDER BY id;
```

Expected output:

```
 count
───────
     3

 id │     name      │       email       │         created_at
────┼───────────────┼───────────────────┼────────────────────────────
  1 │ Alice Johnson │ alice@example.com │ 2024-01-15 14:23:00+00
  2 │ Bob Smith     │ bob@example.com   │ 2024-01-15 14:23:00+00
  3 │ Carol White   │ carol@example.com │ 2024-01-15 14:23:00+00
```

All 3 rows are present. Data is intact.

---

## Task 7 - The Cutover

In a real migration:

1. Put the old database in read-only mode (or stop writes at the application layer)
2. Take a final snapshot of the old instance (to capture any data written after your first snapshot)
3. Restore the final snapshot as a new encrypted instance
4. Update the application's connection string to point to the new endpoint
5. Start the application and verify it works
6. After confirming for 24 hours: delete the old unencrypted instance

For this lab, simulate the cutover by updating your connection string variable:

```bash
export RDS_HOST=$NEW_HOST
echo "New connection target: $RDS_HOST"
```

---

## Task 8 - Write the Compliance Documentation

Write a migration record that includes:

1. Source instance ID and confirmation it was unencrypted
2. Date and time of migration
3. KMS key used for encryption (ARN)
4. New instance ID and confirmation it is encrypted
5. Data validation results (row counts match, spot checks pass)
6. Who performed the migration
7. Was there downtime? How long?

This document goes to the compliance team as evidence.

---

## Clean Up

```bash
aws rds delete-db-instance \
  --db-instance-identifier "unencrypted-legacy-db" \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds delete-db-instance \
  --db-instance-identifier "encrypted-migrated-db" \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds delete-db-snapshot \
  --db-snapshot-identifier $SOURCE_SNAP \
  --region $AWS_REGION

aws rds delete-db-snapshot \
  --db-snapshot-identifier $ENCRYPTED_SNAP \
  --region $AWS_REGION
```
