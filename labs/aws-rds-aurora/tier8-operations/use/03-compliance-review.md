# USE Exercise 03: Compliance Review

**Objective:** Audit a set of RDS instances against a HIPAA-aligned compliance checklist and produce a gap report with remediation steps.
**Time:** 35-45 minutes
**Level:** Expert
**infra_required:** true - Requires a running RDS instance with sufficient permissions to check configuration.
**Prerequisites:** Build Guide 06 completed. AWS Config enabled in your account.

---

## Context

You are the lead DBA at [COMPANY], a healthcare technology company. Your compliance team has informed you that a HIPAA audit is scheduled in 30 days. You have been asked to audit all RDS instances for HIPAA readiness and produce a gap report with remediation priority.

The instances in scope are all RDS PostgreSQL instances tagged with `DataClass=confidential` or `DataClass=restricted` in your account.

---

## Part 1: Identify In-Scope Instances

**Task 1.1:** List all RDS instances tagged with `DataClass=confidential` or `DataClass=restricted`:

```bash
aws resourcegroupstaggingapi get-resources \
  --resource-type-filters rds:db \
  --tag-filters Key=DataClass,Values=confidential,restricted \
  --region [REGION] \
  --query 'ResourceTagMappingList[*].ResourceARN' \
  --output text
```

**Task 1.2:** For each in-scope instance, gather its current configuration:

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].{
    ID: DBInstanceIdentifier,
    Encrypted: StorageEncrypted,
    MultiAZ: MultiAZ,
    DeletionProtection: DeletionProtection,
    BackupRetention: BackupRetentionPeriod,
    Monitoring: MonitoringInterval,
    PIEnabled: PerformanceInsightsEnabled,
    CACert: CACertificateIdentifier,
    Engine: Engine,
    EngineVersion: EngineVersion
  }' \
  --output table \
  --region [REGION]
```

**Deliverable:** Table of in-scope instances with their current configuration values.

---

## Part 2: HIPAA Compliance Checklist

For each in-scope instance, evaluate it against the following checklist. Mark each item PASS, FAIL, or NEEDS-VERIFICATION.

### Technical Safeguards Checklist

**Encryption at Rest**
- [ ] `StorageEncrypted = true`
- [ ] KMS key is a customer-managed key (CMK), not the AWS-managed default key
  - Verify: `aws rds describe-db-instances --query 'DBInstances[0].KmsKeyId'`
  - AWS-managed key ARN contains `aws/rds`. CMK ARNs contain `key/[UUID]`.

**Encryption in Transit**
- [ ] `rds.force_ssl = 1` in the parameter group
  - Verify: `aws rds describe-db-parameters --db-parameter-group-name [PG-NAME] --query 'Parameters[?ParameterName==\`rds.force_ssl\`]'`
- [ ] CA certificate is current (not expired)
  - Verify: `aws rds describe-db-instances --query 'DBInstances[0].CACertificateIdentifier'`
  - `rds-ca-rsa2048-g1` or `rds-ca-rsa4096-g1` are current. `rds-ca-2015` is expired.

**Access Control**
- [ ] No default PostgreSQL `postgres` superuser password is in use (verified out-of-band)
- [ ] IAM database authentication is enabled (optional but recommended for HIPAA)
  - Verify: `aws rds describe-db-instances --query 'DBInstances[0].IAMDatabaseAuthenticationEnabled'`
- [ ] Security group allows only required source IPs/security groups (no `0.0.0.0/0`)
  - Verify: Get the security group IDs and check rules in the EC2 console

**Audit Logging**
- [ ] pgaudit extension is installed and enabled
  - Connect to each database: `SELECT * FROM pg_extension WHERE extname = 'pgaudit';`
- [ ] `shared_preload_libraries` contains `pgaudit`
  - Verify in parameter group
- [ ] `pgaudit.log` includes at minimum `ddl,write,role`
  - Verify in parameter group: `aws rds describe-db-parameters --db-parameter-group-name [PG-NAME] --query 'Parameters[?ParameterName==\`pgaudit.log\`]'`
- [ ] PostgreSQL logs are exported to CloudWatch Logs
  - Verify: `aws rds describe-db-instances --query 'DBInstances[0].EnabledCloudwatchLogsExports'`
- [ ] CloudWatch Log Group has retention set to >= 2192 days (6 years)
  - Verify: `aws logs describe-log-groups --log-group-name-prefix /aws/rds/instance/[INSTANCE-ID]`

**Availability and Integrity**
- [ ] Multi-AZ enabled
- [ ] Automated backup retention >= 7 days
- [ ] Deletion protection enabled
- [ ] Enhanced monitoring enabled (MonitoringInterval <= 60)

**VPC and Network**
- [ ] Instance is in a private subnet (no public accessibility)
  - Verify: `aws rds describe-db-instances --query 'DBInstances[0].PubliclyAccessible'` - must be `false`
- [ ] VPC Flow Logs enabled for the VPC containing this instance

**AWS Account Controls**
- [ ] AWS BAA (Business Associate Agreement) is executed
  - Verify in AWS Artifact console
- [ ] CloudTrail is enabled and logging all RDS API actions
  - Verify: `aws cloudtrail describe-trails`

**Deliverable:** Completed checklist for each in-scope instance. Mark each item PASS/FAIL/NEEDS-VERIFICATION with evidence (command output or observation).

---

## Part 3: Gap Report

**Task 3.1:** For each FAIL item in the checklist, document:

```
GAP: [CONTROL NAME]
Instance(s) Affected: [INSTANCE IDs]
Current State: [WHAT IS CONFIGURED NOW]
Required State: [WHAT HIPAA REQUIRES]
Remediation Steps: [HOW TO FIX]
Estimated Time to Remediate: [HOURS/DAYS]
Risk if Not Remediated: [WHAT EXPOSURE EXISTS]
Priority: [P1 IMMEDIATE / P2 WITHIN 7 DAYS / P3 WITHIN 30 DAYS]
```

**Task 3.2:** Assign priorities using this framework:

- **P1 Immediate:** The gap creates an active security or compliance risk. Examples: unencrypted storage on a database containing PHI, SSL not enforced, public accessibility enabled, audit logging disabled.
- **P2 Within 7 days:** The gap is a compliance requirement but does not represent an active risk. Examples: log retention set to 30 days instead of 6 years, no CMK for encryption, missing specific pgaudit log categories.
- **P3 Within 30 days:** The gap is a best practice or supporting control. Examples: enhanced monitoring not enabled, IAM database auth not configured, VPC Flow Logs missing.

**Task 3.3:** Estimate total remediation effort. Group items by:
- Items that can be remediated with a CLI command (< 5 minutes each)
- Items that require a restart or downtime window
- Items that require cross-team coordination (security team, application team, management)

---

## Part 4: Remediation Execution

For the highest-priority gaps you found in Part 3, execute the remediation:

**Task 4.1:** If `rds.force_ssl` is not set, enable it:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PG-NAME] \
  --parameters ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate \
  --region [REGION]
```

**Task 4.2:** If pgaudit is not enabled, enable it (use the steps from Build Guide 06).

**Task 4.3:** If log retention is too short, fix it:

```bash
aws logs put-retention-policy \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --retention-in-days 2192 \
  --region [REGION]
```

**Task 4.4:** After remediation, re-run the affected checklist items to confirm PASS status.

**Deliverable:** Before/after evidence for each remediated item.

---

## Part 5: Executive Summary for the Audit

Write a one-page executive summary structured as follows. This is what you hand to the compliance officer.

```
HIPAA COMPLIANCE AUDIT - RDS FLEET
[DATE]
Lead DBA: [YOUR NAME]
Instances Reviewed: [COUNT]
Instances Fully Compliant: [COUNT]
Instances With Gaps: [COUNT]

CRITICAL FINDINGS (P1)
[List any P1 items - be direct about what the risk is]

NON-CRITICAL GAPS (P2/P3)
[List P2 and P3 items briefly]

REMEDIATION STATUS
[Which gaps have been closed as of this report]
[Which gaps are open with expected close dates]

RISK STATEMENT
[Your professional assessment of the current HIPAA risk posture]
[This is your signed judgment as the technical lead]

OPEN QUESTIONS REQUIRING MANAGEMENT DECISION
[Items that require budget, cross-team work, or business decisions]
```

---

## Reflection Questions

1. You found that three instances use the AWS-managed default KMS key (`aws/rds`) instead of a CMK. The compliance officer says "encryption is encryption - both are AES-256, why does it matter?" What is your response?

2. Your audit found that pgaudit logs `ddl,write,role` but not `read`. The compliance officer says HIPAA requires auditing who accessed PHI, which means you need to log `SELECT` statements. The DBA team argues this will generate 10x the log volume and cost $2,000/month extra. How do you resolve this?

3. One of the in-scope instances is a read replica used exclusively for reporting. The reporting queries are run by an automated ETL tool using a service account. Does this replica need pgaudit? Defend your position.

4. The AWS Business Associate Agreement was executed by someone who left the company 18 months ago. Does this need to be re-executed? Where do you verify it is still in effect?
