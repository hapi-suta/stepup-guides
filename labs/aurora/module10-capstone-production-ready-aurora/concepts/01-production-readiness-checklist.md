# Module 10 - Concepts: Production Readiness Checklist for Aurora PostgreSQL

**Objective:** Understand every dimension of production readiness for an Aurora PostgreSQL stack - security, high availability, backup and disaster recovery, monitoring, cost optimization, compliance, and operational maturity.
**Time:** 30 minutes reading
**Level:** Senior / Staff

---

## Why a Checklist Matters

Production readiness is not a single decision. It is dozens of decisions across security, availability, performance, cost, and compliance - all made before traffic hits your cluster. Missing even one item can cause an outage, a data breach, or a surprise bill.

This checklist is organized into seven categories. Each item includes:
- **What** - the requirement
- **Why** - what goes wrong if you skip it
- **How to verify** - the CLI or console check

Use this as a gate before going live. Every item should be PASS before you route production traffic.

---

## Category 1: Security (11 items)

### 1.1 Storage Encryption Enabled

**What:** Aurora storage encryption uses AWS KMS to encrypt data at rest - including automated backups, snapshots, and replicas.

**Why:** Without encryption at rest, anyone with physical access to the underlying storage (or a compromised snapshot) can read your data. Most compliance frameworks (SOC 2, HIPAA, PCI-DSS) require encryption at rest.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].StorageEncrypted' \
  --output text
```

Expected output (yours will differ):
```
True
```

If this returns `False`, you cannot enable encryption on an existing cluster. You must create a new encrypted cluster and migrate data.

### 1.2 SSL/TLS Enforced for All Connections

**What:** Set `rds.force_ssl = 1` in the cluster parameter group so PostgreSQL rejects any unencrypted connection.

**Why:** Without forced SSL, credentials and query data travel in plaintext over the network. An attacker on the same network segment can capture passwords and sensitive data with a simple packet sniffer.

**How to verify:**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" \
  --output text
```

Expected output (yours will differ):
```
1
```

### 1.3 No Public Access on Any Instance

**What:** Every instance in the cluster must have `PubliclyAccessible = false`. Instances should live in private subnets with no direct internet route.

**Why:** A publicly accessible database instance is reachable from the internet. Even with strong passwords, you are exposed to brute-force attacks, credential stuffing, and zero-day exploits against the PostgreSQL protocol.

**How to verify:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,PubliclyAccessible]' \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------
|         DescribeDBInstances            |
+---------------------------+-----------+
|  devops-lab-cluster-w1    | False     |
|  devops-lab-cluster-r1    | False     |
+---------------------------+-----------+
```

Every row must show `False`.

### 1.4 IAM Database Authentication Enabled

**What:** Enable IAM authentication on the cluster so applications can authenticate using temporary IAM tokens instead of static passwords.

**Why:** Static passwords are a liability. They get hardcoded in config files, shared in Slack, and never rotated. IAM tokens expire in 15 minutes and are generated from IAM credentials that you already manage.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
  --output text
```

Expected output (yours will differ):
```
True
```

### 1.5 Secrets Manager for Master Password

**What:** Store the master password in AWS Secrets Manager with automatic rotation enabled.

**Why:** A master password stored in a `.env` file, a Terraform state file, or a CI/CD variable is a ticking time bomb. Secrets Manager rotates the password on a schedule and provides audit logging of every access.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].MasterUserSecret' \
  --output json
```

Expected output (yours will differ):
```json
{
  "SecretArn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!cluster-abc-xyz",
  "SecretStatus": "active"
}
```

### 1.6 Security Groups Follow Least Privilege

**What:** The cluster security group should allow inbound traffic only on port 5432, only from specific CIDR blocks or security groups that need database access.

**Why:** A security group with `0.0.0.0/0` on port 5432 allows the entire internet to attempt connections. Even `0.0.0.0/0` on port 443 is too broad - restrict to application subnets only.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].VpcSecurityGroups[*].VpcSecurityGroupId' \
  --output text
```

Then check each security group:

```bash
aws ec2 describe-security-groups \
  --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json
```

Verify no rule has `CidrIp: 0.0.0.0/0`.

### 1.7 Custom KMS Key (Not Default)

**What:** Use a customer-managed KMS key (CMK) instead of the default `aws/rds` key for storage encryption.

**Why:** The default `aws/rds` key cannot be rotated on your schedule, cannot be shared across accounts, and cannot be audited with a custom key policy. A CMK gives you full control over who can use the key and when.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].KmsKeyId' \
  --output text
```

If this returns an ARN containing `alias/aws/rds`, you are using the default key. Switch to a CMK.

### 1.8 Deletion Protection Enabled

**What:** Enable deletion protection on the cluster so it cannot be accidentally deleted via the console or CLI.

**Why:** A single mistyped CLI command or a rogue automation can delete your production cluster. Deletion protection adds a required extra step - you must first disable protection, which creates a deliberate confirmation.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DeletionProtection' \
  --output text
```

Expected output (yours will differ):
```
True
```

### 1.9 Audit Logging Enabled (pgaudit)

**What:** Install the `pgaudit` extension and configure `pgaudit.log` to capture DDL, role changes, and optionally read/write operations.

**Why:** Without audit logging, you have no record of who changed a table schema, who granted superuser access, or who ran a `DELETE FROM users`. Compliance frameworks require audit trails. Incident response requires them.

**How to verify:**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='pgaudit.log'].ParameterValue" \
  --output text
```

Expected output (yours will differ):
```
ddl,role
```

### 1.10 Network Isolation (Private Subnets Only)

**What:** The DB subnet group should contain only private subnets - subnets whose route tables do NOT have a route to an internet gateway.

**Why:** Even with `PubliclyAccessible = false`, placing instances in public subnets creates unnecessary exposure. Defense in depth means the network itself prevents direct internet routing.

**How to verify:**

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name devops-lab-subnet-group \
  --query 'DBSubnetGroups[0].Subnets[*].[SubnetIdentifier,SubnetAvailabilityZone.Name]' \
  --output table
```

Then for each subnet, check its route table:

```bash
aws ec2 describe-route-tables \
  --filters Name=association.subnet-id,Values=subnet-0123456789abcdef0 \
  --query 'RouteTables[0].Routes[?GatewayId!=`local`].GatewayId' \
  --output text
```

If any route shows `igw-*`, that subnet has a route to an internet gateway - it is a public subnet and should not be in your DB subnet group.

### 1.11 Password Policy for Database Users

**What:** Create database users with strong passwords and enforce password expiration using `VALID UNTIL` in PostgreSQL.

**Why:** Weak or never-rotated database passwords are a common finding in security audits. Even with IAM auth enabled, the master user and any legacy users still use passwords.

**How to verify:** Connect to the database and run:

```sql
SELECT usename, valuntil
FROM pg_user
WHERE usename NOT IN ('rdsadmin', 'rds_superuser');
```

Any user with `valuntil` set to `NULL` or a date far in the future should be investigated.

---

## Category 2: High Availability (8 items)

### 2.1 Multi-AZ Deployment

**What:** The cluster must have at least one reader instance in a different Availability Zone than the writer.

**Why:** If the AZ hosting the writer goes down (hardware failure, network partition, power outage), Aurora promotes a reader from another AZ. Without a reader in a different AZ, failover has no target and your database is down until the AZ recovers.

**How to verify:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,AvailabilityZone,DBInstanceStatus]' \
  --output table
```

Verify at least two instances show different AZ values.

### 2.2 Failover Priority Configuration

**What:** Set failover priority (tier 0-15) on reader instances so Aurora promotes the instance you prefer during failover.

**Why:** Without explicit priority, Aurora picks the reader with the most recent data. If you have a reader sized `db.t3.medium` for lightweight reporting and a reader sized `db.r6g.xlarge` for production reads, you want the larger one promoted.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].[DBInstanceIdentifier,IsClusterWriter,PromotionTier]' \
  --output table
```

### 2.3 Connection Endpoint Strategy

**What:** Applications should use the cluster endpoint for writes and the reader endpoint for reads.

**Why:** Using the instance endpoint directly means your application does not automatically follow failover. When the writer changes, the cluster endpoint updates automatically, but a hardcoded instance endpoint does not.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[Endpoint,ReaderEndpoint]' \
  --output table
```

Check your application connection strings to confirm they use these endpoints, not instance-level endpoints.

### 2.4 Application-Level Retry Logic

**What:** Applications must handle transient connection failures gracefully - retry with exponential backoff during failover events.

**Why:** Aurora failover typically completes in 30-60 seconds. During that window, connections to the old writer fail. Without retry logic, your application throws 500 errors for every request during failover.

**How to verify:** This is an application-level check. Review connection pool configuration for:
- Connection timeout: 5-10 seconds
- Retry count: 3-5 retries
- Backoff: exponential with jitter

### 2.5 DNS TTL Configuration

**What:** Ensure the DNS resolver used by your application respects short TTLs. Aurora endpoints use 5-second TTLs.

**Why:** If your DNS resolver caches the old writer IP for minutes after failover, your application keeps connecting to the demoted instance (now a reader) or to a non-existent endpoint.

**How to verify:**

```bash
dig +short devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com
```

Check your application's DNS resolver configuration. Java applications are particularly problematic - the JVM caches DNS indefinitely by default unless you set `networkaddress.cache.ttl=5` in `java.security`.

### 2.6 Cluster Has Minimum Two Instances

**What:** Production clusters should have at least two instances (one writer, one reader).

**Why:** A single-instance cluster has no failover target. If the instance fails, Aurora must provision a new instance from storage - this takes several minutes instead of the typical 30-second failover.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers | length(@)' \
  --output text
```

This should return `2` or higher.

### 2.7 Maintenance Window During Low Traffic

**What:** Set the preferred maintenance window to a period of low traffic - typically weekday early morning or weekend.

**Why:** Maintenance operations (minor version upgrades, OS patching) can cause brief availability interruptions. Scheduling these during peak traffic maximizes the blast radius.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].PreferredMaintenanceWindow' \
  --output text
```

### 2.8 Instance Class Matches Across Writer and Reader

**What:** The failover target reader should use the same instance class as the writer.

**Why:** If the writer is `db.r6g.xlarge` and the reader is `db.t3.medium`, after failover the new writer (formerly `db.t3.medium`) cannot handle the same workload. This causes performance degradation immediately after failover.

**How to verify:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass]' \
  --output table
```

---

## Category 3: Backup and Disaster Recovery (7 items)

### 3.1 Automated Backup Retention >= 7 Days

**What:** Set the backup retention period to at least 7 days. For production, 14-35 days is recommended.

**Why:** Automated backups enable point-in-time recovery (PITR). A 1-day retention means you can only recover to the last 24 hours. If data corruption goes unnoticed for 48 hours, you have lost your recovery window.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].BackupRetentionPeriod' \
  --output text
```

### 3.2 Backup Window Does Not Overlap Maintenance Window

**What:** The preferred backup window and the preferred maintenance window should not overlap.

**Why:** If a maintenance operation runs during the backup window, the backup may be delayed or the maintenance may conflict with the backup process.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[PreferredBackupWindow,PreferredMaintenanceWindow]' \
  --output table
```

### 3.3 Cross-Region Snapshot Copy Configured

**What:** Set up automatic cross-region snapshot copy to a second AWS region.

**Why:** If your primary region experiences a complete outage, your backups are in the same region - inaccessible. Cross-region copies ensure you have a backup in an independent region.

**How to verify:** Check for recent snapshots in the target region:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type manual \
  --region us-west-2 \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

### 3.4 PITR Test Performed Recently

**What:** Perform a test restore from a point-in-time at least once per quarter. Document the process and the time it takes.

**Why:** Backups that have never been tested are not backups - they are hopes. A test restore verifies the backup chain is intact, the restore process works, and you know how long recovery takes.

**How to verify:** This is a process check. Look for documentation of the last PITR test, including:
- Date of test
- Target restore time selected
- Actual time to complete restore
- Data integrity verification results

### 3.5 Manual Snapshot Before Major Changes

**What:** Take a manual snapshot before any major operation - engine upgrades, schema migrations, instance class changes.

**Why:** Manual snapshots are not subject to the automated retention period - they persist until you delete them. If an upgrade fails, you have an explicit rollback point.

**How to verify:**

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type manual \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

### 3.6 Snapshot Encryption Key Accessible in DR Region

**What:** If using cross-region snapshots with a CMK, the KMS key must be replicated or a separate CMK must exist in the DR region.

**Why:** A snapshot encrypted with a KMS key from `us-east-1` cannot be restored in `us-west-2` unless the key is a multi-region key or you re-encrypt the snapshot with a key that exists in `us-west-2`.

**How to verify:** Check if your KMS key is multi-region:

```bash
aws kms describe-key \
  --key-id alias/aurora-cmk \
  --query 'KeyMetadata.MultiRegion' \
  --output text
```

### 3.7 Recovery Time Objective (RTO) and Recovery Point Objective (RPO) Documented

**What:** Document your RTO (how long recovery can take) and RPO (how much data loss is acceptable).

**Why:** Without documented RTO and RPO, you cannot design your DR strategy. A 1-hour RTO requires hot standby; a 24-hour RTO can use snapshot restores.

**How to verify:** This is a documentation check. Your DR plan should state:
- RTO: e.g., 30 minutes for single-AZ failure, 4 hours for region failure
- RPO: e.g., 0 for single-AZ (Aurora replication is synchronous), 5 minutes for cross-region (snapshot copy interval)

---

## Category 4: Monitoring and Alerting (9 items)

### 4.1 Performance Insights Enabled

**What:** Enable Performance Insights on all instances in the cluster.

**Why:** Performance Insights provides the `db.load` metric - the most important single metric for database health. It shows how many sessions are active and what they are waiting on (CPU, I/O, locks, etc.).

**How to verify:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,PerformanceInsightsEnabled]' \
  --output table
```

### 4.2 Enhanced Monitoring Enabled

**What:** Enable Enhanced Monitoring with a granularity of 1, 5, or 15 seconds.

**Why:** Standard CloudWatch metrics have 1-minute granularity. Enhanced Monitoring provides OS-level metrics (CPU per process, memory breakdown, swap usage) at up to 1-second granularity. This is essential for diagnosing short-lived spikes.

**How to verify:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,MonitoringInterval]' \
  --output table
```

Values greater than 0 mean Enhanced Monitoring is enabled.

### 4.3 CloudWatch Alarms for Critical Metrics

**What:** Create CloudWatch Alarms for at minimum: CPU utilization, database connections, freeable memory, and replica lag.

**Why:** Without alarms, you learn about problems from your users - or worse, from Twitter. Alarms enable proactive response before impact.

**How to verify:**

```bash
aws cloudwatch describe-alarms \
  --query "MetricAlarms[?Dimensions[?Name=='DBClusterIdentifier' && Value=='devops-lab-cluster']].[AlarmName,MetricName,StateValue]" \
  --output table
```

### 4.4 PostgreSQL Logs Exported to CloudWatch

**What:** Enable CloudWatch Logs export for the `postgresql` log type.

**Why:** Without log export, PostgreSQL logs are only accessible through the RDS console or `download-db-log-file-portion` API. CloudWatch Logs enables search, metric filters, alerts on log patterns, and long-term retention.

**How to verify:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].EnabledCloudwatchLogsExports' \
  --output json
```

Should include `"postgresql"`.

### 4.5 Slow Query Logging Configured

**What:** Set `log_min_duration_statement` to a value appropriate for your workload (typically 1000ms for OLTP, 5000ms for analytics).

**Why:** Without slow query logging, you cannot identify the queries that degrade performance. `pg_stat_statements` shows aggregate stats, but slow query logs show individual executions with their parameters.

**How to verify:**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='log_min_duration_statement'].ParameterValue" \
  --output text
```

### 4.6 Log Metric Filters for Critical Events

**What:** Create CloudWatch Logs metric filters for: deadlocks, authentication failures, out-of-memory errors, and transaction ID wraparound warnings.

**Why:** These events may happen infrequently but are always critical. A metric filter turns a log line into a CloudWatch metric that you can alarm on.

**How to verify:**

```bash
aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --query 'metricFilters[*].[filterName,filterPattern]' \
  --output table
```

### 4.7 Dashboard Exists for the Cluster

**What:** Create a CloudWatch Dashboard with widgets for CPU, connections, latency, free memory, replica lag, and custom metrics.

**Why:** A dashboard gives the on-call engineer a single view of cluster health. Without it, every investigation starts with "let me find the right metric in CloudWatch" - wasting minutes during an incident.

**How to verify:**

```bash
aws cloudwatch list-dashboards \
  --query 'DashboardEntries[?contains(DashboardName, `devops-lab`)]' \
  --output table
```

### 4.8 Alarm Notifications Route to the Right Team

**What:** CloudWatch Alarm actions should send notifications to an SNS topic that routes to PagerDuty, Slack, or email - whatever your team uses.

**Why:** An alarm that fires but notifies nobody is worse than no alarm. At least with no alarm, you know you are flying blind. A silently firing alarm creates false confidence.

**How to verify:**

```bash
aws cloudwatch describe-alarms \
  --alarm-names devops-lab-cpu-alarm \
  --query 'MetricAlarms[0].AlarmActions' \
  --output json
```

Verify the SNS topic ARN leads to an active subscription.

### 4.9 pg_stat_statements Enabled

**What:** Include `pg_stat_statements` in `shared_preload_libraries` and create the extension in each database.

**Why:** `pg_stat_statements` captures query execution statistics - total calls, total time, rows returned, blocks hit vs read. This is the primary tool for identifying which queries consume the most resources.

**How to verify:**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='shared_preload_libraries'].ParameterValue" \
  --output text
```

Should include `pg_stat_statements`.

---

## Category 5: Cost Optimization (6 items)

### 5.1 Instance Class Right-Sized

**What:** The instance class should match actual workload requirements. Do not use `db.r6g.4xlarge` for a cluster that averages 15% CPU.

**Why:** Over-provisioning wastes money. Under-provisioning causes performance issues. Right-sizing is an ongoing process, not a one-time decision.

**How to verify:** Check average CPU over the last 7 days:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 86400 \
  --statistics Average \
  --output table
```

If average CPU is consistently below 20%, investigate downsizing.

### 5.2 Storage Type Evaluated (Standard vs I/O-Optimized)

**What:** Evaluate whether Aurora Standard or Aurora I/O-Optimized storage is more cost-effective for your workload.

**Why:** I/O-heavy workloads can save 20-40% by switching to I/O-Optimized. I/O-light workloads save money on Standard. The crossover point is when I/O charges exceed roughly 25% of total Aurora spend.

**How to verify:** Check current storage type:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].StorageType' \
  --output text
```

### 5.3 Reserved Instance Coverage for Stable Workloads

**What:** If the cluster will run for 1+ years, purchase Reserved Instances to reduce hourly cost by 30-60%.

**Why:** On-Demand pricing is the most expensive option. A 1-year All Upfront RI typically saves 37% vs On-Demand.

**How to verify:**

```bash
aws rds describe-reserved-db-instances \
  --query 'ReservedDBInstances[*].[ReservedDBInstanceId,DBInstanceClass,State,Duration]' \
  --output table
```

### 5.4 Graviton Instances Used

**What:** Use Graviton-based instance classes (`db.r6g`, `db.r7g`) instead of Intel-based classes (`db.r6i`, `db.r5`).

**Why:** Graviton instances provide approximately 10-20% better price-performance than equivalent Intel instances. PostgreSQL runs well on ARM64.

**How to verify:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass]' \
  --output table
```

Look for `g` in the instance family (e.g., `db.r6g` = Graviton, `db.r6i` = Intel).

### 5.5 Unused Resources Cleaned Up

**What:** Delete old manual snapshots, unused parameter groups, and orphaned subnet groups.

**Why:** Manual snapshots incur storage charges. Unused parameter groups and subnet groups do not cost money but create operational clutter.

**How to verify:**

```bash
aws rds describe-db-cluster-snapshots \
  --snapshot-type manual \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

### 5.6 Cost Alerts Configured

**What:** Set up AWS Budgets with alerts at 80%, 90%, and 100% of expected monthly spend.

**Why:** Without cost alerts, you discover budget overruns when the bill arrives - weeks after the spending occurred.

**How to verify:**

```bash
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --query 'Budgets[*].[BudgetName,BudgetLimit.Amount]' \
  --output table
```

---

## Category 6: Compliance and Governance (5 items)

### 6.1 Resource Tagging Complete

**What:** Every resource (cluster, instances, parameter groups, subnet groups, snapshots) must have tags: `Environment`, `Application`, `Team`, `CostCenter`, and `ManagedBy`.

**Why:** Tags enable cost allocation, ownership identification, and compliance scoping. Untagged resources are invisible to governance tools.

**How to verify:**

```bash
aws rds list-tags-for-resource \
  --resource-name arn:aws:rds:us-east-1:123456789012:cluster:devops-lab-cluster \
  --output table
```

### 6.2 AWS Config Rules Active for RDS

**What:** Enable AWS Config rules: `rds-storage-encrypted`, `rds-multi-az-support`, `rds-instance-deletion-protection-enabled`, `rds-logging-enabled`.

**Why:** Config rules provide continuous compliance evaluation. Without them, you rely on manual audits that happen too infrequently to catch drift.

**How to verify:**

```bash
aws configservice describe-config-rules \
  --query "ConfigRules[?contains(ConfigRuleName, 'rds')].[ConfigRuleName,ConfigRuleState]" \
  --output table
```

### 6.3 CloudTrail Logging API Calls

**What:** AWS CloudTrail must be enabled and logging all RDS API calls.

**Why:** CloudTrail records who called what API, when, and from where. This is your audit trail for infrastructure changes - who modified the parameter group, who deleted the snapshot, who created a new user.

**How to verify:**

```bash
aws cloudtrail get-trail-status \
  --name management-events \
  --query 'IsLogging' \
  --output text
```

### 6.4 Infrastructure as Code (IaC) Used

**What:** All infrastructure should be defined in Terraform, CloudFormation, or CDK - not created via the console.

**Why:** Console-created resources are undocumented, unreproducible, and invisible to code review. IaC provides version control, peer review, and the ability to recreate the entire stack from scratch.

**How to verify:** Check the `ManagedBy` tag on the cluster. Then verify the Terraform state or CloudFormation stack includes all resources.

### 6.5 Change Management Process Documented

**What:** Document the process for making changes to the production cluster - who approves, what testing is required, what rollback looks like.

**Why:** Ad-hoc changes to production databases cause outages. A change management process ensures every change is reviewed, tested, and reversible.

**How to verify:** This is a process check. Look for documentation covering:
- Change request template
- Approval workflow
- Testing requirements (staging environment)
- Rollback procedure
- Post-change verification

---

## Category 7: Operational Maturity (6 items)

### 7.1 Runbook Exists for Common Incidents

**What:** Written runbooks for: failover event, high CPU, connection exhaustion, storage full, replication lag spike, deadlocks.

**Why:** During an incident at 3 AM, the on-call engineer needs step-by-step instructions, not tribal knowledge. Runbooks reduce MTTR and prevent mistakes made under pressure.

### 7.2 On-Call Rotation Defined

**What:** A clear on-call rotation with primary and secondary contacts, escalation paths, and handoff procedures.

**Why:** Without a defined rotation, incidents go unresponded or everyone responds at once (bystander effect). An explicit rotation creates clear accountability.

### 7.3 Post-Incident Review Process

**What:** After every P1/P2 incident, conduct a blameless post-incident review documenting: timeline, root cause, contributing factors, and action items.

**Why:** Incidents that do not lead to improvements will recur. Post-incident reviews are how organizations learn.

### 7.4 Capacity Planning Process

**What:** Review cluster capacity monthly: storage growth rate, connection count trends, CPU utilization trends.

**Why:** Running out of connections or storage is a preventable outage. Trending analysis gives you weeks of lead time to scale up.

### 7.5 Schema Migration Process

**What:** Schema migrations should be version-controlled, peer-reviewed, tested in staging, and applied through a CI/CD pipeline.

**Why:** A manual `ALTER TABLE` on production is the #1 cause of database outages. Automated migrations with rollback capability are table stakes.

### 7.6 DR Drill Schedule

**What:** Schedule and perform disaster recovery drills at least once per quarter.

**Why:** A DR plan that has never been tested will fail when you need it most. Regular drills identify gaps in the plan, train the team, and verify that recovery procedures work.

---

## Production Readiness Scorecard

Use this scorecard to track your status. Mark each item as PASS, FAIL, or N/A.

| # | Category | Item | Status |
|---|----------|------|--------|
| 1.1 | Security | Storage encryption enabled | |
| 1.2 | Security | SSL/TLS enforced | |
| 1.3 | Security | No public access | |
| 1.4 | Security | IAM authentication enabled | |
| 1.5 | Security | Secrets Manager for master password | |
| 1.6 | Security | Security groups least privilege | |
| 1.7 | Security | Custom KMS key | |
| 1.8 | Security | Deletion protection enabled | |
| 1.9 | Security | Audit logging (pgaudit) | |
| 1.10 | Security | Private subnets only | |
| 1.11 | Security | Password policy for DB users | |
| 2.1 | HA | Multi-AZ deployment | |
| 2.2 | HA | Failover priority set | |
| 2.3 | HA | Cluster endpoint strategy | |
| 2.4 | HA | Application retry logic | |
| 2.5 | HA | DNS TTL configuration | |
| 2.6 | HA | Minimum two instances | |
| 2.7 | HA | Maintenance window during low traffic | |
| 2.8 | HA | Instance class matches writer/reader | |
| 3.1 | Backup/DR | Backup retention >= 7 days | |
| 3.2 | Backup/DR | Backup and maintenance windows separate | |
| 3.3 | Backup/DR | Cross-region snapshot copy | |
| 3.4 | Backup/DR | PITR test performed | |
| 3.5 | Backup/DR | Manual snapshot before changes | |
| 3.6 | Backup/DR | KMS key accessible in DR region | |
| 3.7 | Backup/DR | RTO and RPO documented | |
| 4.1 | Monitoring | Performance Insights enabled | |
| 4.2 | Monitoring | Enhanced Monitoring enabled | |
| 4.3 | Monitoring | CloudWatch Alarms for critical metrics | |
| 4.4 | Monitoring | PostgreSQL logs to CloudWatch | |
| 4.5 | Monitoring | Slow query logging configured | |
| 4.6 | Monitoring | Log metric filters for critical events | |
| 4.7 | Monitoring | Dashboard exists | |
| 4.8 | Monitoring | Alarm notifications routed | |
| 4.9 | Monitoring | pg_stat_statements enabled | |
| 5.1 | Cost | Instance class right-sized | |
| 5.2 | Cost | Storage type evaluated | |
| 5.3 | Cost | Reserved Instance coverage | |
| 5.4 | Cost | Graviton instances used | |
| 5.5 | Cost | Unused resources cleaned up | |
| 5.6 | Cost | Cost alerts configured | |
| 6.1 | Compliance | Resource tagging complete | |
| 6.2 | Compliance | AWS Config rules active | |
| 6.3 | Compliance | CloudTrail logging | |
| 6.4 | Compliance | Infrastructure as Code | |
| 6.5 | Compliance | Change management documented | |
| 7.1 | Operations | Runbooks exist | |
| 7.2 | Operations | On-call rotation defined | |
| 7.3 | Operations | Post-incident review process | |
| 7.4 | Operations | Capacity planning process | |
| 7.5 | Operations | Schema migration process | |
| 7.6 | Operations | DR drill schedule | |

**Total items: 52**

**Scoring:**
- 48-52 PASS: Production ready - go live with confidence
- 40-47 PASS: Nearly ready - address remaining items before launch
- 30-39 PASS: Significant gaps - do not go live until critical items are resolved
- Below 30: Not ready - return to the BUILD guides

---

## Summary

Production readiness is a spectrum, not a binary. The checklist above covers the full range from basic security to operational maturity. At minimum, every item in Security and High Availability must be PASS before routing production traffic. Monitoring and Backup items should follow within the first week. Cost, Compliance, and Operations items should be addressed within the first month.

The most dangerous state is "mostly ready" - where the cluster works fine under normal conditions but falls apart during the first real incident. The items in this checklist are designed to surface those gaps before they become incidents.

**Next:** [Build 01 - Architecture Design](../build/01-architecture-design.md)
