# BUILD 05: Compliance and Tagging

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 45-60 minutes
**Level:** Intermediate

---

## Objective

Implement a tagging strategy for Aurora PostgreSQL clusters, set up AWS Config rules for compliance monitoring, and enable audit logging with pgAudit. By the end of this guide, you will have automated compliance checks that detect untagged resources, unencrypted databases, and missing audit logging.

---

## Prerequisites

- Aurora PostgreSQL cluster `devops-lab-cluster` running
- AWS CLI configured with appropriate permissions
- AWS Config enabled in your account

---

## Section 1: Tagging Strategy

### 1.1 Define Required Tags

Every RDS resource must have these tags for cost allocation, ownership tracking, and compliance:

| Tag Key | Required | Example | Purpose |
|---------|----------|---------|---------|
| Environment | Yes | production | Cost allocation, access control |
| CostCenter | Yes | CC-1042 | Finance chargeback |
| Team | Yes | platform | Ownership and escalation |
| Application | Yes | payments-api | Map database to application |
| DataClassification | Yes | confidential | Compliance and security |
| BackupRetention | No | 35 | Override default retention |
| Compliance | No | hipaa | Regulatory framework |

### 1.2 Apply Tags to Your Cluster

```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789012:cluster:devops-lab-cluster \
    --tags \
    Key=Environment,Value=production \
    Key=CostCenter,Value=CC-1042 \
    Key=Team,Value=platform \
    Key=Application,Value=devops-training \
    Key=DataClassification,Value=internal \
    Key=Compliance,Value=none
```

Replace the ARN with your actual cluster ARN. You can find it with:

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].DBClusterArn' \
    --output text
```

Expected output (yours will differ):
```
arn:aws:rds:us-east-1:123456789012:cluster:devops-lab-cluster
```

### 1.3 Verify Tags

```bash
aws rds list-tags-for-resource \
    --resource-name arn:aws:rds:us-east-1:123456789012:cluster:devops-lab-cluster \
    --query 'TagList[].{Key:Key,Value:Value}' \
    --output table
```

Expected output (yours will differ):
```
-----------------------------------------
|         ListTagsForResource           |
+---------------------+-----------------+
|        Key          |     Value       |
+---------------------+-----------------+
| Application         | devops-training |
| Compliance          | none            |
| CostCenter          | CC-1042         |
| DataClassification  | internal        |
| Environment         | production      |
| Team                | platform        |
+---------------------+-----------------+
```

### 1.4 Tag the Instances Too

Tags on the cluster do not automatically apply to instances. Tag each instance separately:

```bash
aws rds describe-db-instances \
    --filters Name=db-cluster-id,Values=devops-lab-cluster \
    --query 'DBInstances[].DBInstanceArn' \
    --output text
```

For each instance ARN returned:

```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789012:db:devops-lab-cluster-instance-1 \
    --tags \
    Key=Environment,Value=production \
    Key=CostCenter,Value=CC-1042 \
    Key=Team,Value=platform \
    Key=Application,Value=devops-training \
    Key=DataClassification,Value=internal
```

---

## Section 2: Enable Cost Allocation Tags

### 2.1 Activate Tags in Billing

Cost allocation tags must be activated in the Billing console before they appear in Cost Explorer.

**In the AWS Console:**

1. Open **Billing and Cost Management**.
2. Click **Cost allocation tags** in the left sidebar.
3. Search for the tags you created (Environment, CostCenter, Team, Application).
4. Select each tag and click **Activate**.

Tags take up to 24 hours to appear in Cost Explorer after activation.

**Using the CLI:**

```bash
aws ce update-cost-allocation-tags-status \
    --cost-allocation-tags-status \
    TagKey=Environment,Status=Active \
    TagKey=CostCenter,Status=Active \
    TagKey=Team,Status=Active \
    TagKey=Application,Status=Active
```

---

## Section 3: AWS Config Rules for Compliance

AWS Config continuously monitors your AWS resources and evaluates them against rules. If a resource violates a rule, Config marks it as non-compliant.

### 3.1 Enable AWS Config (If Not Already Enabled)

Check if Config is already recording:

```bash
aws configservice describe-configuration-recorders \
    --query 'ConfigurationRecorders[].{Name:name,Recording:recordingGroup.allSupported}' \
    --output table
```

If this returns an empty table, you need to set up AWS Config first. Follow the AWS Config Getting Started guide in the console.

### 3.2 Rule 1 - Encryption at Rest

This rule checks that all RDS instances have encryption enabled:

```bash
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "devops-rds-encryption-enabled",
        "Description": "Checks that all RDS instances have encryption at rest enabled",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "RDS_STORAGE_ENCRYPTED"
        },
        "Scope": {
            "ComplianceResourceTypes": ["AWS::RDS::DBInstance"]
        }
    }'
```

The `Source.Owner` field set to `AWS` means this is a managed rule provided by AWS. The `SourceIdentifier` is the specific managed rule name.

Expected output (yours will differ):
```json
{
    "ConfigRuleArn": "arn:aws:config:us-east-1:123456789012:config-rule/config-rule-abc123"
}
```

### 3.3 Rule 2 - Multi-AZ Enabled

```bash
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "devops-rds-multi-az",
        "Description": "Checks that production RDS instances have Multi-AZ enabled",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "RDS_MULTI_AZ_SUPPORT"
        },
        "Scope": {
            "ComplianceResourceTypes": ["AWS::RDS::DBInstance"]
        }
    }'
```

### 3.4 Rule 3 - Backup Retention

```bash
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "devops-rds-backup-retention",
        "Description": "Checks that RDS instances have backup retention of at least 7 days",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "DB_INSTANCE_BACKUP_ENABLED"
        },
        "InputParameters": "{\"backupRetentionPeriod\":\"7\"}",
        "Scope": {
            "ComplianceResourceTypes": ["AWS::RDS::DBInstance"]
        }
    }'
```

The `InputParameters` field passes configuration to the managed rule. Here it specifies that backup retention must be at least 7 days.

### 3.5 Rule 4 - Required Tags

```bash
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "devops-rds-required-tags",
        "Description": "Checks that RDS instances have required tags",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "REQUIRED_TAGS"
        },
        "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"CostCenter\",\"tag3Key\":\"Team\",\"tag4Key\":\"Application\"}",
        "Scope": {
            "ComplianceResourceTypes": ["AWS::RDS::DBInstance"]
        }
    }'
```

### 3.6 Check Compliance Status

Wait a few minutes for Config to evaluate the rules, then check:

```bash
aws configservice describe-compliance-by-config-rule \
    --config-rule-names \
    devops-rds-encryption-enabled \
    devops-rds-multi-az \
    devops-rds-backup-retention \
    devops-rds-required-tags \
    --query 'ComplianceByConfigRules[].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}' \
    --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------
|              DescribeComplianceByConfigRule              |
+-------------------------------+-------------------------+
|             Rule              |         Status          |
+-------------------------------+-------------------------+
| devops-rds-encryption-enabled | COMPLIANT               |
| devops-rds-multi-az           | COMPLIANT               |
| devops-rds-backup-retention   | COMPLIANT               |
| devops-rds-required-tags      | COMPLIANT               |
+-------------------------------+-------------------------+
```

### 3.7 Find Non-Compliant Resources

If any rule shows NON_COMPLIANT:

```bash
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name devops-rds-required-tags \
    --compliance-types NON_COMPLIANT \
    --query 'EvaluationResults[].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Rule:EvaluationResultIdentifier.EvaluationResultQualifier.ConfigRuleName}' \
    --output table
```

---

## Section 4: Audit Logging with pgAudit

### 4.1 Enable pgAudit

pgAudit provides detailed session and object audit logging for PostgreSQL. It logs WHO did WHAT to WHICH objects and WHEN.

Add pgAudit to the shared preload libraries:

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params \
    --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,pgaudit,ApplyMethod=pending-reboot"
```

Note the comma-separated values. Both extensions are listed in a single parameter.

Set the pgAudit logging level:

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params \
    --parameters \
    "ParameterName=pgaudit.log,ParameterValue=ddl,ApplyMethod=immediate" \
    "ParameterName=pgaudit.role,ParameterValue=rds_pgaudit,ApplyMethod=immediate"
```

The `pgaudit.log` parameter controls what gets logged:
- `ddl` - logs CREATE, ALTER, DROP statements
- `role` - logs GRANT, REVOKE statements
- `read` - logs SELECT statements
- `write` - logs INSERT, UPDATE, DELETE statements
- `all` - logs everything (very verbose - use carefully in production)

Starting with `ddl` is recommended. It catches schema changes without generating excessive log volume.

### 4.2 Reboot to Apply

```bash
aws rds reboot-db-instance \
    --db-instance-identifier devops-lab-cluster-instance-1
```

```bash
aws rds wait db-instance-available \
    --db-instance-identifier devops-lab-cluster-instance-1
```

### 4.3 Create the pgAudit Extension

Connect to your Aurora writer endpoint:

```bash
psql -h devops-lab-cluster.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

Expected output:
```
CREATE EXTENSION
```

Create the audit role:

```sql
CREATE ROLE rds_pgaudit;
```

Expected output:
```
CREATE ROLE
```

### 4.4 Test Audit Logging

Run a DDL statement:

```sql
CREATE TABLE audit_test (id serial PRIMARY KEY, name text);
```

```sql
DROP TABLE audit_test;
```

Exit psql:

```
\q
```

Check the PostgreSQL logs for audit entries:

```bash
aws logs filter-log-events \
    --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
    --filter-pattern "AUDIT" \
    --start-time $(date -u -d '10 minutes ago' +%s)000 \
    --query 'events[].message' \
    --output text
```

Expected output (yours will differ):
```
AUDIT: SESSION,1,1,DDL,CREATE TABLE,TABLE,public.audit_test,"CREATE TABLE audit_test (id serial PRIMARY KEY, name text);",<not logged>
AUDIT: SESSION,2,1,DDL,DROP TABLE,TABLE,public.audit_test,"DROP TABLE audit_test;",<not logged>
```

---

## Section 5: Build a Compliance Dashboard Script

### 5.1 Create the Compliance Check Script

```bash
vi ~/sre-practice/fleet/compliance-check.sh
```

```bash
#!/bin/bash
# Compliance Dashboard - checks all compliance rules
set -euo pipefail

CLUSTER="devops-lab-cluster"
PASS=0
FAIL=0

echo "========================================="
echo "Compliance Check - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Cluster: ${CLUSTER}"
echo "========================================="
echo ""

# Check 1: Encryption at rest
ENCRYPTED=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER}" \
    --query 'DBClusters[0].StorageEncrypted' \
    --output text)
if [ "${ENCRYPTED}" = "True" ]; then
    echo "[PASS] Encryption at rest: enabled"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Encryption at rest: DISABLED"
    FAIL=$((FAIL + 1))
fi

# Check 2: Deletion protection
DEL_PROTECT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER}" \
    --query 'DBClusters[0].DeletionProtection' \
    --output text)
if [ "${DEL_PROTECT}" = "True" ]; then
    echo "[PASS] Deletion protection: enabled"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Deletion protection: DISABLED"
    FAIL=$((FAIL + 1))
fi

# Check 3: Backup retention >= 7 days
RETENTION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER}" \
    --query 'DBClusters[0].BackupRetentionPeriod' \
    --output text)
if [ "${RETENTION}" -ge 7 ]; then
    echo "[PASS] Backup retention: ${RETENTION} days"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Backup retention: ${RETENTION} days (minimum 7 required)"
    FAIL=$((FAIL + 1))
fi

# Check 4: Required tags present
REQUIRED_TAGS=("Environment" "CostCenter" "Team" "Application")
CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER}" \
    --query 'DBClusters[0].DBClusterArn' \
    --output text)

for TAG in "${REQUIRED_TAGS[@]}"; do
    TAG_VALUE=$(aws rds list-tags-for-resource \
        --resource-name "${CLUSTER_ARN}" \
        --query "TagList[?Key=='${TAG}'].Value" \
        --output text)
    if [ -n "${TAG_VALUE}" ] && [ "${TAG_VALUE}" != "None" ]; then
        echo "[PASS] Tag '${TAG}': ${TAG_VALUE}"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] Tag '${TAG}': MISSING"
        FAIL=$((FAIL + 1))
    fi
done

# Check 5: IAM authentication enabled
IAM_AUTH=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER}" \
    --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
    --output text)
if [ "${IAM_AUTH}" = "True" ]; then
    echo "[PASS] IAM authentication: enabled"
    PASS=$((PASS + 1))
else
    echo "[FAIL] IAM authentication: DISABLED"
    FAIL=$((FAIL + 1))
fi

# Check 6: Auto minor version upgrade
INSTANCES=$(aws rds describe-db-instances \
    --filters Name=db-cluster-id,Values="${CLUSTER}" \
    --query 'DBInstances[].DBInstanceIdentifier' \
    --output text)
for INST in ${INSTANCES}; do
    AUTO_UPGRADE=$(aws rds describe-db-instances \
        --db-instance-identifier "${INST}" \
        --query 'DBInstances[0].AutoMinorVersionUpgrade' \
        --output text)
    if [ "${AUTO_UPGRADE}" = "True" ]; then
        echo "[PASS] Auto minor upgrade (${INST}): enabled"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] Auto minor upgrade (${INST}): DISABLED"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "========================================="
TOTAL=$((PASS + FAIL))
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL}/${TOTAL} failed"
if [ "${FAIL}" -eq 0 ]; then
    echo "Status: COMPLIANT"
else
    echo "Status: NON-COMPLIANT (${FAIL} issues require attention)"
fi
echo "========================================="
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/sre-practice/fleet/compliance-check.sh
```

### 5.2 Run the Compliance Check

```bash
~/sre-practice/fleet/compliance-check.sh
```

Expected output (yours will differ):
```
=========================================
Compliance Check - 2026-06-09T15:00:00Z
Cluster: devops-lab-cluster
=========================================

[PASS] Encryption at rest: enabled
[PASS] Deletion protection: enabled
[PASS] Backup retention: 7 days
[PASS] Tag 'Environment': production
[PASS] Tag 'CostCenter': CC-1042
[PASS] Tag 'Team': platform
[PASS] Tag 'Application': devops-training
[FAIL] IAM authentication: DISABLED
[PASS] Auto minor upgrade (devops-lab-cluster-instance-1): enabled
[PASS] Auto minor upgrade (devops-lab-cluster-instance-2): enabled

=========================================
Results: 9/10 passed, 1/10 failed
Status: NON-COMPLIANT (1 issues require attention)
=========================================
```

---

## Cleanup

To remove the AWS Config rules:

```bash
aws configservice delete-config-rule --config-rule-name devops-rds-encryption-enabled
aws configservice delete-config-rule --config-rule-name devops-rds-multi-az
aws configservice delete-config-rule --config-rule-name devops-rds-backup-retention
aws configservice delete-config-rule --config-rule-name devops-rds-required-tags
```

To remove pgAudit (revert the parameter group change):

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params \
    --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

---

## Summary

| What You Did | Why It Matters |
|-------------|---------------|
| Defined required tags | Cost allocation and ownership tracking at scale |
| Applied tags to cluster and instances | Resources without tags are invisible in cost reports |
| Activated cost allocation tags | Tags must be activated to appear in Cost Explorer |
| Created AWS Config rules | Automated compliance monitoring - no manual audits |
| Enabled pgAudit | WHO did WHAT to WHICH objects and WHEN - audit trail |
| Built compliance dashboard script | Single command shows compliance status |

**Next:** [BUILD 06 - Runbook Automation](./06-runbook-automation.md)
