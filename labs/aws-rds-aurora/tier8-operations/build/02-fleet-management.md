# Tier 8 - Build Guide 02: Fleet Management

**Objective:** Implement a production-grade fleet management system for RDS using a consistent tagging strategy, AWS Config compliance rules, drift detection, and automated remediation via SSM Automation.
**Time:** 40 minutes
**Level:** Expert
**infra_required:** true - Requires at least one running RDS or Aurora instance. AWS Config must be enabled in your account.
**Prerequisites:** Tier 8 Build 01 completed. AWS Config enabled (Settings > Turn on AWS Config in the Config console).

---

## 1. Tagging Strategy for RDS Fleet

Tags are the organizational backbone of fleet management. Without consistent tags, cost reports are meaningless, compliance audits are manual, and operational ownership is unclear.

### Required tags for every RDS instance/cluster

Define these as mandatory in your organization's tagging policy:

| Tag Key | Example Values | Purpose |
|---------|---------------|---------|
| `Environment` | `production`, `staging`, `development`, `sandbox` | Determines alerting thresholds and change control requirements |
| `Application` | `payments-api`, `user-service`, `analytics` | Maps database to the owning application |
| `Team` | `platform`, `backend`, `data-engineering` | Ownership for incident escalation |
| `CostCenter` | `CC-1042`, `CC-2201` | Financial chargeback |
| `DataClass` | `public`, `internal`, `confidential`, `restricted` | Drives encryption and access control requirements |
| `Compliance` | `hipaa`, `pci`, `fedramp`, `none` | Determines audit requirements |
| `BackupRequired` | `true`, `false` | Used by backup automation to determine backup targets |
| `ManagedBy` | `terraform`, `cdk`, `console`, `manual` | Identifies infrastructure source of truth |

### Apply tags to an existing RDS instance (Console)

1. Open the RDS console.
2. Select **Databases**.
3. Click the instance identifier.
4. Scroll down to the **Tags** section.
5. Click **Manage tags**.
6. Add each required tag as a key-value pair.
7. Click **Save**.

### Apply tags to an RDS instance (CLI)

First, get the instance ARN:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].DBInstanceArn' \
  --output text \
  --region [REGION]
```

Then apply the tags:

```bash
aws rds add-tags-to-resource \
  --resource-name [INSTANCE-ARN] \
  --tags \
    Key=Environment,Value=production \
    Key=Application,Value=[APP-NAME] \
    Key=Team,Value=[TEAM-NAME] \
    Key=CostCenter,Value=[COST-CENTER] \
    Key=DataClass,Value=confidential \
    Key=Compliance,Value=none \
    Key=BackupRequired,Value=true \
    Key=ManagedBy,Value=terraform \
  --region [REGION]
```

### Audit tag coverage across your fleet (CLI)

Find all RDS instances missing required tags:

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,Tags:TagList}' \
  --output json \
  --region [REGION]
```

For a cleaner audit, use the Resource Groups Tagging API:

```bash
aws resourcegroupstaggingapi get-resources \
  --resource-type-filters rds:db \
  --tag-filters Key=Environment \
  --region [REGION] \
  --query 'ResourceTagMappingList[*].ResourceARN' \
  --output text
```

This returns all RDS instances that have an `Environment` tag. Compare this list against your full instance list to find untagged resources.

---

## 2. AWS Config Rules for RDS Compliance

AWS Config evaluates your resources continuously against rules you define. Any resource that does not comply generates a finding.

### Enable AWS Config (if not already enabled) (Console)

1. Open the **AWS Config** console.
2. Click **Get started** or **Settings**.
3. Select **Record all resources supported in this region**.
4. Choose an S3 bucket for Config data storage (create new or use existing).
5. Choose an SNS topic for notifications (optional but recommended).
6. Click **Save**.

### Add managed Config rules for RDS (Console)

1. In the AWS Config console, click **Rules** in the left navigation.
2. Click **Add rule**.
3. Select **AWS managed rule**.
4. Search for and add each of the following rules:

**Rule 1: rds-storage-encrypted**
- Flags any RDS instance where storage encryption is not enabled.
- No additional parameters required.

**Rule 2: rds-multi-az-support**
- Flags RDS instances not configured for Multi-AZ.
- Scope this rule to production instances only using the tag filter: `Environment=production`.

**Rule 3: rds-instance-deletion-protection-enabled**
- Flags instances without deletion protection enabled.
- Apply to production instances.

**Rule 4: rds-automatic-minor-version-upgrade-enabled**
- Flags instances not configured for automatic minor version upgrades.

**Rule 5: rds-enhanced-monitoring-enabled**
- Flags instances without Enhanced Monitoring enabled.
- Set parameter `monitoringInterval` to `1` (acceptable values: 1, 5, 10, 15, 30, 60 seconds).

**Rule 6: rds-logging-enabled**
- Flags instances not exporting logs to CloudWatch Logs.
- Set parameter `additionalLogs` to `postgresql`.

### Add managed Config rules for RDS (CLI)

```bash
# Deploy rds-storage-encrypted
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "rds-storage-encrypted",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "RDS_STORAGE_ENCRYPTED"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::RDS::DBInstance"]
    }
  }' \
  --region [REGION]
```

```bash
# Deploy rds-multi-az-support (production only via tag filter)
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "rds-multi-az-production",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "RDS_MULTI_AZ_SUPPORT"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::RDS::DBInstance"],
      "TagKey": "Environment",
      "TagValue": "production"
    }
  }' \
  --region [REGION]
```

```bash
# Deploy rds-logging-enabled
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "rds-logging-enabled",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "RDS_LOGGING_ENABLED"
    },
    "InputParameters": "{\"additionalLogs\":\"postgresql\"}",
    "Scope": {
      "ComplianceResourceTypes": ["AWS::RDS::DBInstance"]
    }
  }' \
  --region [REGION]
```

### View compliance results (CLI)

```bash
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name rds-storage-encrypted \
  --compliance-types NON_COMPLIANT \
  --region [REGION]
```

Expected output (yours will differ):
```json
{
  "EvaluationResults": [
    {
      "EvaluationResultIdentifier": {
        "EvaluationResultQualifier": {
          "ConfigRuleName": "rds-storage-encrypted",
          "ResourceType": "AWS::RDS::DBInstance",
          "ResourceId": "dev-postgres-01"
        }
      },
      "ComplianceType": "NON_COMPLIANT",
      "ResultRecordedTime": "2026-01-15T14:32:00Z"
    }
  ]
}
```

---

## 3. Drift Detection

Drift occurs when an instance's actual configuration diverges from the expected state. This section shows how to detect it systematically.

### What constitutes drift for an RDS fleet

Define your expected state for each environment. Example expected state for production instances:

```
MultiAZ:                      true
StorageEncrypted:             true
DeletionProtection:           true
AutoMinorVersionUpgrade:      true
BackupRetentionPeriod:        >= 7 days
MonitoringInterval:           <= 60
PerformanceInsightsEnabled:   true
EnabledCloudwatchLogsExports: includes "postgresql"
```

### Check for drift across your fleet (CLI)

The following command retrieves key configuration attributes for all instances and outputs them for review:

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].{
    ID: DBInstanceIdentifier,
    MultiAZ: MultiAZ,
    Encrypted: StorageEncrypted,
    DeletionProtection: DeletionProtection,
    AutoMinorUpgrade: AutoMinorVersionUpgrade,
    BackupDays: BackupRetentionPeriod,
    Monitoring: MonitoringInterval,
    PIEnabled: PerformanceInsightsEnabled
  }' \
  --output table \
  --region [REGION]
```

Expected output (yours will differ):
```
--------------------------------------------------------------------------------------
|                           DescribeDBInstances                                      |
+---------------------+--------+----------+------------+---------------+------+------+
|  prod-pg-primary    | True   | True     | True       | True          | 7    | 1    |
|  dev-postgres-01    | False  | False    | False      | True          | 1    | 0    |
+---------------------+--------+--------+------------+---------------+--------+------+
```

`dev-postgres-01` shows drift: not encrypted, no Multi-AZ (expected for dev), no deletion protection, no Enhanced Monitoring.

### Tag-based drift detection

Check instances where `ManagedBy=terraform` but that were recently modified via the console (Config records this):

```bash
aws configservice get-resource-config-history \
  --resource-type AWS::RDS::DBInstance \
  --resource-id [INSTANCE-ID] \
  --limit 5 \
  --region [REGION]
```

This returns the last 5 configuration snapshots. Compare the `configurationItemCaptureTime` against your last Terraform apply to identify out-of-band changes.

---

## 4. Automated Remediation with SSM

AWS Config can trigger automatic remediation when a non-compliant resource is found. Remediation runs via SSM Automation documents.

### Create an SSM Automation document for enabling deletion protection (Console)

1. Open the **Systems Manager** console.
2. Select **Documents** under **Shared Resources**.
3. Click **Create document**.
4. Select **Automation** as the document type.
5. Name it `EnableRDSDeletionProtection`.
6. Paste the following YAML content:

```yaml
description: Enable deletion protection on an RDS instance
schemaVersion: '0.3'
assumeRole: '{{ AutomationAssumeRole }}'
parameters:
  DBInstanceIdentifier:
    type: String
    description: The RDS instance identifier to remediate
  AutomationAssumeRole:
    type: String
    description: IAM role ARN for this automation to assume
mainSteps:
  - name: EnableDeletionProtection
    action: aws:executeAwsApi
    inputs:
      Service: rds
      Api: ModifyDBInstance
      DBInstanceIdentifier: '{{ DBInstanceIdentifier }}'
      DeletionProtection: true
      ApplyImmediately: true
    outputs:
      - Name: DBInstanceIdentifier
        Selector: $.DBInstance.DBInstanceIdentifier
        Type: String
```

7. Click **Create document**.

### Create an SSM Automation document (CLI)

Save the document content to a file first:

```bash
cat > /tmp/enable-deletion-protection.yaml << 'EOF'
description: Enable deletion protection on an RDS instance
schemaVersion: '0.3'
assumeRole: '{{ AutomationAssumeRole }}'
parameters:
  DBInstanceIdentifier:
    type: String
    description: The RDS instance identifier to remediate
  AutomationAssumeRole:
    type: String
    description: IAM role ARN for this automation to assume
mainSteps:
  - name: EnableDeletionProtection
    action: aws:executeAwsApi
    inputs:
      Service: rds
      Api: ModifyDBInstance
      DBInstanceIdentifier: '{{ DBInstanceIdentifier }}'
      DeletionProtection: true
      ApplyImmediately: true
    outputs:
      - Name: DBInstanceIdentifier
        Selector: $.DBInstance.DBInstanceIdentifier
        Type: String
EOF
```

```bash
aws ssm create-document \
  --name EnableRDSDeletionProtection \
  --document-type Automation \
  --document-format YAML \
  --content file:///tmp/enable-deletion-protection.yaml \
  --region [REGION]
```

### Link the Config rule to automated remediation (Console)

1. In the Config console, click **Rules**.
2. Click the `rds-instance-deletion-protection-enabled` rule.
3. Click **Actions > Manage remediation**.
4. Select **Automatic remediation**.
5. Choose **SSM document** and select `EnableRDSDeletionProtection`.
6. Map the parameter: `DBInstanceIdentifier` = `RESOURCE_ID`.
7. Set the execution role to an IAM role that has `rds:ModifyDBInstance` and `ssm:StartAutomationExecution` permissions.
8. Set **Maximum automatic attempts** to `3`.
9. Click **Save changes**.

### Link the Config rule to automated remediation (CLI)

```bash
aws configservice put-remediation-configurations \
  --remediation-configurations '[
    {
      "ConfigRuleName": "rds-instance-deletion-protection-enabled",
      "TargetType": "SSM_DOCUMENT",
      "TargetId": "EnableRDSDeletionProtection",
      "Parameters": {
        "DBInstanceIdentifier": {
          "ResourceValue": {"Value": "RESOURCE_ID"}
        },
        "AutomationAssumeRole": {
          "StaticValue": {"Values": ["arn:aws:iam::[ACCOUNT-ID]:role/ConfigRemediationRole"]}
        }
      },
      "Automatic": true,
      "MaximumAutomaticAttempts": 3,
      "RetryAttemptSeconds": 60
    }
  ]' \
  --region [REGION]
```

### Verify remediation ran correctly

After a non-compliant instance is detected and remediation runs:

```bash
aws configservice describe-remediation-execution-statuses \
  --config-rule-name rds-instance-deletion-protection-enabled \
  --region [REGION]
```

Expected output (yours will differ):
```json
{
  "RemediationExecutionStatuses": [
    {
      "ResourceKey": {
        "ResourceType": "AWS::RDS::DBInstance",
        "ResourceId": "dev-postgres-01"
      },
      "State": "SUCCEEDED",
      "LastUpdatedTime": "2026-01-15T14:45:00Z"
    }
  ]
}
```

---

## Summary

- Consistent tagging enables cost allocation, ownership clarity, and compliance scoping. Define required tags and enforce them.
- AWS Config rules provide continuous compliance evaluation without manual auditing. Use the managed rules as a baseline; add custom rules for organization-specific requirements.
- Drift detection requires comparing actual state (Config snapshots, CLI describe calls) against expected state (your IaC definitions or standards document).
- Automated remediation via SSM closes the loop - a Config rule detects the violation, SSM fixes it, and the remediation history provides an audit trail.
- Apply remediation cautiously. Auto-remediation of encryption violations on production instances requires a full recreate workflow, not a simple modify. Test auto-remediation in dev before enabling it on production resources.

**Next:** [Guide 03 - Observability Pipelines](./03-observability-pipelines.md)
