# Runbook: Unexpected Cost Spike from I/O Charges

**Severity:** High (financial impact)
**Scenario:** Aurora RDS costs have increased 340% unexpectedly. Finance has flagged it.

---

## Symptoms

- AWS Cost Explorer shows a dramatic increase in the RDS service line
- The increase appeared without a corresponding increase in database traffic or data volume
- The `Aurora:StorageIOUsage` usage type shows unusually high charges
- The `AmazonCloudWatch` bill shows large increases in log ingestion

---

## Impact

- Unexpected cloud spend. Depending on severity, this can affect team budgets and require executive-level explanation.
- High log volume can reduce CloudWatch query performance and increase ingestion costs significantly.

---

## Diagnosis

### Step 1: Identify cost drivers in Cost Explorer

1. Open **Billing and Cost Management > Cost Explorer**.
2. Set date range to the current vs previous month.
3. Group by **Usage type**.
4. Filter by **Service: Relational Database Service**.
5. Look for the following high-cost line items:
   - `Aurora:StorageIOUsage` - per-I/O charges on Standard storage
   - `RDS:ChargedIOOptimized` - I/O-Optimized cluster charges (higher storage rate, zero I/O)
   - Compare: which is larger?

6. Switch to CloudWatch service filter.
7. Look for `AmazonCloudWatch:DataProcessing-Bytes` (log ingestion) - check if this has spiked.

### Step 2: Check Aurora storage mode for each cluster

```bash
aws rds describe-db-clusters \
  --query 'DBClusters[?Engine==`aurora-postgresql`].[DBClusterIdentifier,StorageType,AllocatedStorage]' \
  --output table \
  --region [REGION]
```

- `StorageType: aurora` = Standard (I/O charges apply)
- `StorageType: aurora-iopt1` = I/O-Optimized (flat storage rate, no per-I/O charge)

### Step 3: Check CloudWatch Logs volume

```bash
# Check log group storage and ingest rate
aws logs describe-log-groups \
  --log-group-name-prefix /aws/rds/instance \
  --query 'logGroups[*].[logGroupName,storedBytes,retentionInDays]' \
  --output table \
  --region [REGION]
```

Large `storedBytes` values combined with a recent spike indicate high log volume.

### Step 4: Check PostgreSQL logging parameters

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --query 'Parameters[?ParameterName==`log_min_duration_statement`]' \
  --region [REGION]
```

A value of `0` means all queries are logged - this generates enormous log volume on any moderately busy instance.

---

## Remediation

### Fix 1: Restore appropriate log_min_duration_statement

Set to a sensible threshold. For production: 1000ms (1 second) is a common starting point.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate \
  --region [REGION]
```

This takes effect immediately (it is a dynamic parameter).

### Fix 2: Switch Aurora cluster to I/O-Optimized (if cost-justified)

First, calculate break-even: if `Aurora:StorageIOUsage` exceeds 25% of total Aurora spend, I/O-Optimized is likely cheaper.

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier [CLUSTER-ID] \
  --storage-type aurora-iopt1 \
  --apply-immediately \
  --region [REGION]
```

This change is online (no downtime) and takes effect immediately.

### Fix 3: Clean up the I/O workload table (if injected by the scenario)

```sql
DROP TABLE IF EXISTS t8_cost_spike_test;
```

---

## Verification

```bash
# Verify storage type is now I/O-Optimized
aws rds describe-db-clusters \
  --db-cluster-identifier [CLUSTER-ID] \
  --query 'DBClusters[0].StorageType' \
  --output text \
  --region [REGION]
# Expected: aurora-iopt1

# Verify logging parameter is restored
aws rds describe-db-parameters \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --query 'Parameters[?ParameterName==`log_min_duration_statement`].[ParameterValue]' \
  --output text \
  --region [REGION]
# Expected: 1000 (or your chosen value, not 0)
```

---

## Prevention

1. **Set AWS Budgets for RDS:** Create a budget alert when RDS spend exceeds 120% of the previous month. This catches cost spikes before finance notices them.

```bash
aws budgets create-budget \
  --account-id [ACCOUNT-ID] \
  --budget file://rds-budget.json \
  --notifications-with-subscribers file://rds-budget-notifications.json
```

2. **Standardize logging parameters via Config:** Create an AWS Config custom rule that flags parameter groups with `log_min_duration_statement = 0`.

3. **Tag and review storage modes quarterly:** During the quarterly cost review, run the `describe-db-clusters` query above to verify all clusters are on the intended storage mode.

4. **CloudWatch Logs retention policy:** Set retention on all RDS log groups. Unbounded retention allows unbounded log storage costs.

---

## Escalation

If I/O charges are very high (> $10,000/month unexpected increase) and cannot be explained by configuration changes, open an AWS Support case. Rarely, billing anomalies occur on AWS's side.

If the spike corresponds to a legitimate increase in write traffic (application growth), present a capacity plan with a recommendation to switch to I/O-Optimized and model the cost at projected growth.
