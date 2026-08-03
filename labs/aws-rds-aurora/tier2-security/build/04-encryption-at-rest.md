# Build 04 - Encryption at Rest

**Time:** 25 minutes
**Goal:** Create encrypted RDS instances using AWS managed and customer managed KMS keys, verify encryption status, and learn the snapshot-copy-restore method for encrypting existing instances.

---

## Before You Start

Read `concepts/security.md` section T2.4 first.

You need:
- AWS account with permissions for RDS and KMS
- AWS CLI configured
- No existing RDS instance required for Steps 1-4 (you will create one)

Set these variables:

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ENCRYPTED_INSTANCE_ID="my-encrypted-db"
export UNENCRYPTED_INSTANCE_ID="my-unencrypted-db"
export DB_SUBNET_GROUP="my-db-subnet-group"
```

> Note: You need a DB subnet group already created. If you completed Tier 1, you should have one. Run `aws rds describe-db-subnet-groups` to list available subnet groups.

---

## Step 1 - Create an Encrypted RDS Instance with AWS Managed Key

### Using the AWS Console

1. Open the AWS Console in your browser
2. Search for **RDS** in the top search bar
3. Click **Databases** in the left sidebar
4. Click **Create database**
5. Choose **Standard create**
6. Engine: **PostgreSQL**
7. Version: Choose the latest available
8. Template: **Free tier** (for lab purposes)
9. DB instance identifier: `my-encrypted-db`
10. Master username: `postgres`
11. Master password: enter a strong password
12. Scroll down to **Storage**
13. Find **Encryption**
14. Make sure **Enable encryption** is checked
15. For **AWS KMS key**, leave as `aws/rds` (this is the AWS managed key)
16. Complete the rest of the settings and click **Create database**

### Using the AWS CLI

```bash
aws rds create-db-instance \
  --db-instance-identifier $ENCRYPTED_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password "StrongPass1!" \
  --allocated-storage 20 \
  --storage-encrypted \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --region $AWS_REGION
```

`--storage-encrypted` enables encryption at rest.
Without `--kms-key-id`, RDS uses the AWS managed key for RDS (`aws/rds`) automatically.
`--no-publicly-accessible` keeps the instance inside your VPC - this is correct for all production databases.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-encrypted-db",
        "StorageEncrypted": true,
        "KmsKeyId": "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123...",
        "DBInstanceStatus": "creating",
        ...
    }
}
```

Notice `"StorageEncrypted": true` in the output. That confirms encryption is enabled.

---

## Step 2 - Create a Customer Managed KMS Key

A customer managed key (CMK) gives you control over key policy, rotation, and the ability to disable or delete the key instantly.

### Using the AWS Console

1. Open the AWS Console
2. Search for **KMS** in the top search bar
3. Click **Customer managed keys**
4. Click **Create key**
5. Key type: **Symmetric**
6. Key usage: **Encrypt and decrypt**
7. Click **Next**
8. Alias: `rds-encryption-key`
9. Description: `Key for encrypting RDS instances`
10. Click **Next**
11. Key administrators: add your IAM user
12. Click **Next**
13. Key users: add your IAM user and the `AWSServiceRoleForRDS` role
14. Click **Next**
15. Review and click **Finish**

### Using the AWS CLI

Create the key:

```bash
aws kms create-key \
  --description "Key for encrypting RDS instances" \
  --key-usage ENCRYPT_DECRYPT \
  --region $AWS_REGION
```

`--key-usage ENCRYPT_DECRYPT` creates a symmetric key suitable for encryption.

Expected output (yours will differ):

```json
{
    "KeyMetadata": {
        "KeyId": "abc12345-ab12-ab12-ab12-abc123456789",
        "Arn": "arn:aws:kms:us-east-1:123456789012:key/abc12345-ab12-ab12-ab12-abc123456789",
        "KeyUsage": "ENCRYPT_DECRYPT",
        "KeyState": "Enabled",
        ...
    }
}
```

Save the key ID:

```bash
export KMS_KEY_ID=$(aws kms create-key \
  --description "Key for encrypting RDS instances" \
  --key-usage ENCRYPT_DECRYPT \
  --query 'KeyMetadata.KeyId' \
  --output text \
  --region $AWS_REGION)

echo "KMS Key ID: $KMS_KEY_ID"
```

Create an alias for easier reference:

```bash
aws kms create-alias \
  --alias-name alias/rds-encryption-key \
  --target-key-id $KMS_KEY_ID \
  --region $AWS_REGION
```

`--alias-name` must start with `alias/`.
`--target-key-id` is the key ID you just created.

Enable automatic annual rotation:

```bash
aws kms enable-key-rotation \
  --key-id $KMS_KEY_ID \
  --region $AWS_REGION
```

`enable-key-rotation` schedules automatic rotation every 365 days. The old key material remains available to decrypt existing data.

Verify rotation is enabled:

```bash
aws kms get-key-rotation-status \
  --key-id $KMS_KEY_ID \
  --region $AWS_REGION
```

Expected output:

```json
{
    "KeyRotationEnabled": true
}
```

---

## Step 3 - Create an RDS Instance with Your Customer Managed Key

```bash
aws rds create-db-instance \
  --db-instance-identifier "my-cmk-encrypted-db" \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password "StrongPass1!" \
  --allocated-storage 20 \
  --storage-encrypted \
  --kms-key-id "alias/rds-encryption-key" \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --region $AWS_REGION
```

`--kms-key-id "alias/rds-encryption-key"` tells RDS to use your customer managed key.
You can use the alias (`alias/rds-encryption-key`), key ID, or full ARN here.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-cmk-encrypted-db",
        "StorageEncrypted": true,
        "KmsKeyId": "arn:aws:kms:us-east-1:123456789012:key/abc12345-...",
        ...
    }
}
```

---

## Step 4 - Verify Encryption Status

For any instance, check if encryption is enabled:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $ENCRYPTED_INSTANCE_ID \
  --query 'DBInstances[0].{Encrypted:StorageEncrypted,KeyId:KmsKeyId}' \
  --output table \
  --region $AWS_REGION
```

`--query` extracts only the fields we care about.
`--output table` formats the result as a readable table.

Expected output (yours will differ):

```
----------------------------------------------------------------------
|                         DescribeDBInstances                        |
+----------+---------------------------------------------------------+
| Encrypted|  True                                                   |
| KeyId    |  arn:aws:kms:us-east-1:123456789012:key/abc12345-...    |
+----------+---------------------------------------------------------+
```

Check all your instances at once:

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,Encrypted:StorageEncrypted,Key:KmsKeyId}' \
  --output table \
  --region $AWS_REGION
```

Any instance with `Encrypted: False` is not encrypted and should be addressed.

---

## Step 5 - The Snapshot-Copy-Restore Method

You cannot enable encryption on an existing unencrypted instance. There is no toggle. But you can encrypt a copy using this three-step method.

### Overview

```
Unencrypted Instance --> Snapshot --> Copy with Encryption --> Restore --> New Encrypted Instance
```

### Step 5a - Create an Unencrypted Instance (to practice the migration)

```bash
aws rds create-db-instance \
  --db-instance-identifier $UNENCRYPTED_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password "StrongPass1!" \
  --allocated-storage 20 \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Notice there is no `--storage-encrypted` flag. This instance will be unencrypted.

Wait for it to become available (5-10 minutes):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $UNENCRYPTED_INSTANCE_ID \
  --region $AWS_REGION
```

### Step 5b - Take a Snapshot of the Unencrypted Instance

```bash
aws rds create-db-snapshot \
  --db-instance-identifier $UNENCRYPTED_INSTANCE_ID \
  --db-snapshot-identifier "unencrypted-snap-$(date +%Y%m%d)" \
  --region $AWS_REGION
```

`--db-snapshot-identifier` is the name for the snapshot.
`$(date +%Y%m%d)` adds today's date to the name (e.g., `unencrypted-snap-20240115`).

Expected output (yours will differ):

```json
{
    "DBSnapshot": {
        "DBSnapshotIdentifier": "unencrypted-snap-20240115",
        "DBInstanceIdentifier": "my-unencrypted-db",
        "Encrypted": false,
        "Status": "creating",
        ...
    }
}
```

Save the snapshot ID:

```bash
export SNAP_ID="unencrypted-snap-$(date +%Y%m%d)"
```

Wait for the snapshot to complete:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier $SNAP_ID \
  --region $AWS_REGION
```

This takes 2-5 minutes.

### Step 5c - Copy the Snapshot with Encryption Enabled

```bash
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier $SNAP_ID \
  --target-db-snapshot-identifier "${SNAP_ID}-encrypted" \
  --kms-key-id "alias/rds-encryption-key" \
  --region $AWS_REGION
```

`--source-db-snapshot-identifier` is the original unencrypted snapshot.
`--target-db-snapshot-identifier` is the name for the new encrypted copy.
`--kms-key-id` specifies which KMS key to encrypt with.

Expected output (yours will differ):

```json
{
    "DBSnapshot": {
        "DBSnapshotIdentifier": "unencrypted-snap-20240115-encrypted",
        "Encrypted": true,
        "KmsKeyId": "arn:aws:kms:...",
        "Status": "pending",
        ...
    }
}
```

Wait for the copy to complete:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier "${SNAP_ID}-encrypted" \
  --region $AWS_REGION
```

### Step 5d - Restore the Encrypted Snapshot

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "my-newly-encrypted-db" \
  --db-snapshot-identifier "${SNAP_ID}-encrypted" \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --region $AWS_REGION
```

`restore-db-instance-from-db-snapshot` creates a new RDS instance from a snapshot.
The new instance will be encrypted because the snapshot is encrypted.

Wait for the new instance to be available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "my-newly-encrypted-db" \
  --region $AWS_REGION
```

### Step 5e - Verify the New Instance is Encrypted

```bash
aws rds describe-db-instances \
  --db-instance-identifier "my-newly-encrypted-db" \
  --query 'DBInstances[0].{Encrypted:StorageEncrypted,KeyId:KmsKeyId}' \
  --output table \
  --region $AWS_REGION
```

Expected output:

```
+----------+-------------------------------------------------------+
| Encrypted|  True                                                 |
| KeyId    |  arn:aws:kms:us-east-1:123456789012:key/abc12345-..   |
+----------+-------------------------------------------------------+
```

### Step 5f - Update Your Application and Clean Up

After restoring the encrypted instance:

1. Update your application's connection string to point to the new endpoint
2. Test the application thoroughly
3. Once you confirm everything works, delete the old unencrypted instance

```bash
aws rds delete-db-instance \
  --db-instance-identifier $UNENCRYPTED_INSTANCE_ID \
  --skip-final-snapshot \
  --region $AWS_REGION
```

`--skip-final-snapshot` skips creating a snapshot on deletion. Use this only for test instances. In production, remove this flag.

> **Concept:** The snapshot-copy-restore method requires a downtime window unless you use read replicas or other traffic-shifting techniques. Plan the migration during a maintenance window and communicate to your users in advance.

---

## Step 6 - KMS Key Policy (Advanced)

By default, AWS creates a key policy that allows the root account and IAM to manage access. For production, you should customize the key policy to restrict who can use your encryption key.

View the current key policy:

```bash
aws kms get-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --region $AWS_REGION
```

The policy controls:
- Who can manage the key (administrators)
- Who can use the key to encrypt/decrypt (users)
- Which AWS services can use the key

A properly restricted key policy means that even if an attacker gains console access, they cannot read your encrypted data without also having permission to use the KMS key.

---

## What You Built

- Created an encrypted RDS instance using the AWS managed key
- Created a customer managed KMS key with automatic rotation
- Created an RDS instance with the customer managed key
- Verified encryption status using the CLI
- Completed the full snapshot-copy-restore migration from unencrypted to encrypted

---

## Clean Up

Delete instances you no longer need to avoid charges:

```bash
aws rds delete-db-instance \
  --db-instance-identifier $ENCRYPTED_INSTANCE_ID \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds delete-db-instance \
  --db-instance-identifier "my-cmk-encrypted-db" \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds delete-db-instance \
  --db-instance-identifier "my-newly-encrypted-db" \
  --skip-final-snapshot \
  --region $AWS_REGION
```

Delete the snapshots:

```bash
aws rds delete-db-snapshot \
  --db-snapshot-identifier $SNAP_ID \
  --region $AWS_REGION

aws rds delete-db-snapshot \
  --db-snapshot-identifier "${SNAP_ID}-encrypted" \
  --region $AWS_REGION
```

---

## Key Rules to Remember

1. Encryption must be enabled at creation time - you cannot add it later
2. Use the snapshot-copy-restore method to encrypt existing instances
3. Customer managed keys give you control and auditability
4. Enable automatic key rotation on all customer managed keys
5. Encrypted backups, read replicas, and snapshots inherit the key from the primary
6. If you delete a KMS key, you permanently lose access to all data encrypted with it
