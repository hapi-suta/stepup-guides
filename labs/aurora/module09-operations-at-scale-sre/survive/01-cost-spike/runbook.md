# Runbook: Cost Spike - Aurora Costs Triple

**Severity:** High
**Last Updated:** 2026-06-09
**Owner:** DBA Team

---

## Symptoms

- AWS Budget alert fires: RDS spend exceeds 200% of baseline
- Cost Explorer shows unexpected spikes in:
  - CloudWatch Logs ingestion charges
  - RDS snapshot storage charges
  - Aurora I/O charges
- Cost allocation reports show "untagged" resources

---

## Impact

- Monthly database bill increases from baseline to 3x baseline
- Untagged resources are invisible in cost reports - teams cannot track spend
- Unbounded log retention accumulates storage charges indefinitely
- Orphaned snapshots consume storage that serves no purpose

---

## Diagnosis

### Step 1: Check Logging Configuration

Check whether verbose logging is enabled:

```bash
aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --query "Parameters[?ParameterName=='log_min_duration_statement'].{Name:ParameterName,Value:ParameterValue}" \
    --output table
```

If the value is `0`, every query is being logged. This generates enormous CloudWatch Logs volume.

### Step 2: Check CloudWatch Log Retention

```bash
aws logs describe-log-groups \
    --log-group-name-prefix /aws/rds/cluster/devops-lab-cluster \
    --query 'logGroups[].{Name:logGroupName,RetentionDays:retentionInDays,StoredBytes:storedBytes}' \
    --output table
```

If `RetentionDays` is empty (null), logs are retained forever.

### Step 3: Check for Orphaned Snapshots

```bash
aws rds describe-db-cluster-snapshots \
    --db-cluster-identifier devops-lab-cluster \
    --snapshot-type manual \
    --query 'DBClusterSnapshots[].{Snapshot:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
    --output table
```

Look for snapshots that are not tagged for retention or are older than 90 days.

### Step 4: Check Cost Allocation Tags

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

Required tags: `CostCenter`, `Environment`, `Team`, `Application`.

---

## Remediation

### Fix 1: Set Logging to Production Level

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

This sets the threshold to 1 second (1000ms). Only queries slower than 1 second will be logged.

### Fix 2: Set CloudWatch Log Retention

```bash
aws logs put-retention-policy \
    --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
    --retention-in-days 90
```

90 days is sufficient for operational troubleshooting. For compliance requirements, export to S3 with lifecycle policies.

### Fix 3: Delete Orphaned Snapshots

For each orphaned snapshot identified:

```bash
aws rds delete-db-cluster-snapshot \
    --db-cluster-snapshot-identifier m09-chaos-cost-spike-snapshot
```

### Fix 4: Restore Cost Allocation Tags

```bash
CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].DBClusterArn' \
    --output text)

aws rds add-tags-to-resource \
    --resource-name "${CLUSTER_ARN}" \
    --tags \
    Key=CostCenter,Value=CC-LAB \
    Key=Environment,Value=lab \
    Key=Team,Value=dba-training
```

---

## Verification

After applying all fixes, verify:

1. `log_min_duration_statement` is set to `1000` (not `0`)
2. CloudWatch log retention is set to a specific number of days (not null/forever)
3. The orphaned snapshot has been deleted
4. All required tags are present on the cluster

Run `validate.sh` to confirm all checks pass.

---

## Prevention

1. Create an AWS Budget alert at 120% of baseline RDS spend
2. Include `log_min_duration_statement` in quarterly parameter review
3. Audit manual snapshots monthly - delete anything > 90 days without retention tag
4. Use AWS Config rule `REQUIRED_TAGS` to detect untagged resources automatically
5. Set CloudWatch log retention via infrastructure-as-code (Terraform/CloudFormation)

---

## Escalation

- If cost spike exceeds 300% of baseline: escalate to engineering leadership
- If untagged resources span multiple accounts: escalate to cloud governance team
- If log volume exceeds CloudWatch service limits: contact AWS support
