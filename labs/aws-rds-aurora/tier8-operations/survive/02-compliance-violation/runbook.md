# Runbook: Unencrypted Instance Found in Production

**Severity:** Critical (compliance violation - HIPAA if PHI is present)
**Scenario:** An automated scan found an unencrypted RDS instance tagged as production with DataClass=confidential.

---

## Symptoms

- AWS Config rule `rds-storage-encrypted` fires a NON_COMPLIANT finding
- Security team alert: "Unencrypted RDS instance detected in production"
- HIPAA audit scheduled within 15 days

---

## Impact

- Regulatory exposure if the instance contains PHI and is truly unencrypted
- Potential HIPAA breach notification requirement if data was accessed by unauthorized parties
- Audit finding that must be remediated and documented

---

## Immediate Actions (first 5 minutes)

1. Confirm the violation is real (not a false positive):

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].{Encrypted:StorageEncrypted,Public:PubliclyAccessible,Tags:TagList}' \
  --region [REGION]
```

If `StorageEncrypted: false`, the violation is confirmed.

2. Assess who can reach the instance:

```bash
# Get the security group
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId' \
  --output text \
  --region [REGION]

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids [SG-ID] \
  --query 'SecurityGroups[0].IpPermissions' \
  --region [REGION]
```

If access is restricted to trusted security groups (not open to `0.0.0.0/0`), the immediate risk is lower.

3. Determine if the instance contains real PHI or is empty/test data:

```sql
-- Connect and check data presence
SELECT schemaname, relname, n_live_tup
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY n_live_tup DESC
LIMIT 10;
```

---

## Diagnosis

### Establish the timeline

Check CloudTrail to find when this instance was created and by whom:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=[INSTANCE-ID] \
  --region [REGION] \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' \
  --output table
```

This tells you who created the instance, when, and whether it was created without encryption intentionally or accidentally.

### Check Config rule history

```bash
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name rds-storage-encrypted \
  --compliance-types NON_COMPLIANT \
  --region [REGION]
```

---

## Remediation

**Important:** You cannot enable encryption on a running RDS instance in-place. You must create an encrypted copy.

### Option A: Snapshot + encrypt + restore (for instances with data)

Step 1: Take a final snapshot of the unencrypted instance:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier [INSTANCE-ID] \
  --db-snapshot-identifier [INSTANCE-ID]-final-unencrypted \
  --region [REGION]
```

Wait for the snapshot to complete:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier [INSTANCE-ID]-final-unencrypted \
  --region [REGION]
```

Step 2: Copy the snapshot with encryption enabled:

```bash
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier [INSTANCE-ID]-final-unencrypted \
  --target-db-snapshot-identifier [INSTANCE-ID]-encrypted-copy \
  --kms-key-id [KMS-KEY-ARN] \
  --region [REGION]
```

Wait for the encrypted copy to complete:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier [INSTANCE-ID]-encrypted-copy \
  --region [REGION]
```

Step 3: Restore from the encrypted snapshot to a new encrypted instance:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier [INSTANCE-ID]-encrypted \
  --db-snapshot-identifier [INSTANCE-ID]-encrypted-copy \
  --db-instance-class [SAME-INSTANCE-CLASS] \
  --no-publicly-accessible \
  --deletion-protection \
  --region [REGION]
```

Step 4: Verify the new instance is encrypted:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID]-encrypted \
  --query 'DBInstances[0].StorageEncrypted' \
  --region [REGION]
# Expected: true
```

Step 5: Update application connection strings to the new instance.

Step 6: Delete the unencrypted instance:

```bash
# First disable deletion protection if set
aws rds modify-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --no-deletion-protection \
  --apply-immediately \
  --region [REGION]

aws rds delete-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --skip-final-snapshot \
  --region [REGION]
```

### Option B: Delete and recreate (for instances with no data)

If the instance is empty (newly created or a test instance), simply delete it and recreate it with encryption enabled.

```bash
# Delete the unencrypted instance
aws rds delete-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --skip-final-snapshot \
  --region [REGION]
```

---

## Verification

After remediation:

1. Confirm the unencrypted instance is deleted:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --region [REGION]
# Expected: error - instance not found
```

2. Confirm the replacement is encrypted:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID]-encrypted \
  --query 'DBInstances[0].StorageEncrypted' \
  --region [REGION]
# Expected: true
```

3. Re-evaluate the AWS Config rule to confirm compliance:

```bash
aws configservice start-config-rules-evaluation \
  --config-rule-names rds-storage-encrypted \
  --region [REGION]
```

---

## Prevention

1. **Enforce encryption at instance creation via Service Control Policy (SCP):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "rds:CreateDBInstance",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "rds:StorageEncrypted": "false"
        },
        "StringEquals": {
          "aws:RequestedRegion": "[REGION]"
        }
      }
    }
  ]
}
```

2. **Enable AWS Config rule with automatic remediation** (see Build Guide 02).

3. **Tag enforcement via Config:** A custom Config rule that flags any production-tagged instance without encryption.

4. **IaC policy:** Require encryption in all Terraform/CDK RDS modules. Enforce via automated policy scanning in CI/CD.

---

## Escalation

If the unencrypted instance was confirmed to contain PHI and was accessible from outside the trusted network, escalate immediately to:
- CISO or Security Lead
- Legal/compliance team for breach notification assessment
- Your DPO (Data Protection Officer) if applicable under GDPR

Document the timeline precisely: when the instance was created, when the violation was detected, when it was remediated.
