# Runbook: Compliance Violation - Unencrypted DB and Missing Audit

**Severity:** Critical
**Last Updated:** 2026-06-09
**Owner:** DBA Team

---

## Symptoms

- AWS Config rule `devops-rds-encryption-enabled` shows NON_COMPLIANT
- Security audit reveals databases without audit logging
- Compliance scan detects missing required tags
- Deletion protection disabled on production databases

---

## Impact

- HIPAA/SOC2 compliance violation if database stores protected data
- No audit trail for database changes (who did what, when)
- Production databases can be accidentally deleted
- Missing tags prevent proper data classification and access control

---

## Diagnosis

### Step 1: Check Audit Logging

```bash
aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --query "Parameters[?ParameterName=='pgaudit.log'].{Name:ParameterName,Value:ParameterValue}" \
    --output table
```

If the value is `none` or empty, audit logging is disabled.

### Step 2: Check Deletion Protection

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].{DeletionProtection:DeletionProtection,IAMAuth:IAMDatabaseAuthenticationEnabled}' \
    --output table
```

Both `DeletionProtection` and `IAMDatabaseAuthenticationEnabled` should be `True` for production.

### Step 3: Check Compliance Tags

```bash
CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].DBClusterArn' \
    --output text)

aws rds list-tags-for-resource \
    --resource-name "${CLUSTER_ARN}" \
    --query 'TagList[].{Key:Key,Value:Value}' \
    --output table
```

Required compliance tags: `DataClassification`, `Compliance`.

### Step 4: Check Encryption at Rest

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].StorageEncrypted' \
    --output text
```

Must return `True`. Note: encryption at rest cannot be enabled on an existing unencrypted cluster - it requires creating a new cluster from an encrypted snapshot.

---

## Remediation

### Fix 1: Enable Audit Logging

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --parameters "ParameterName=pgaudit.log,ParameterValue=ddl,ApplyMethod=immediate"
```

The `ddl` setting logs CREATE, ALTER, and DROP statements. For stricter compliance, use `ddl,role` to also log GRANT and REVOKE.

### Fix 2: Enable Deletion Protection

```bash
aws rds modify-db-cluster \
    --db-cluster-identifier devops-lab-cluster \
    --deletion-protection \
    --apply-immediately
```

### Fix 3: Restore Compliance Tags

```bash
CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].DBClusterArn' \
    --output text)

aws rds add-tags-to-resource \
    --resource-name "${CLUSTER_ARN}" \
    --tags \
    Key=DataClassification,Value=internal \
    Key=Compliance,Value=soc2
```

### Fix 4: Enable IAM Authentication

```bash
aws rds modify-db-cluster \
    --db-cluster-identifier devops-lab-cluster \
    --enable-iam-database-authentication \
    --apply-immediately
```

---

## Verification

After applying all fixes, verify each:

1. `pgaudit.log` is set to `ddl` or a more comprehensive value
2. `DeletionProtection` is `True`
3. `DataClassification` and `Compliance` tags are present
4. `IAMDatabaseAuthenticationEnabled` is `True`

Run `validate.sh` to confirm all checks pass.

---

## Prevention

1. Use AWS Config rules to continuously monitor compliance:
   - `RDS_STORAGE_ENCRYPTED` for encryption at rest
   - `REQUIRED_TAGS` for mandatory tags
   - Custom rule for pgaudit.log verification
2. Enable AWS Config auto-remediation for tag compliance
3. Use Service Control Policies (SCPs) to prevent disabling deletion protection
4. Include compliance checks in quarterly operational review
5. Set up SNS notifications for Config rule state changes

---

## Escalation

- If production database is unencrypted: escalate to CISO immediately
- If audit logging has been disabled for > 24 hours: file a compliance incident
- If deletion protection was disabled without a change ticket: investigate for unauthorized access
