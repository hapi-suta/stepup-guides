# Module 10 - Use Exercise 03: Security Audit

**Objective:** Perform a comprehensive security audit of the complete Aurora stack. Check every layer - network, encryption, authentication, authorization, logging, and compliance. Produce a findings report with severity ratings.
**Time:** 30 minutes
**Level:** Senior / Staff

---

## Context

Your company's security team has requested a pre-launch security audit of the Aurora stack. You must evaluate every security control, document findings with severity ratings, and provide remediation recommendations for any gaps.

---

## Exercise

<details>
<summary>Part 1: Network Security Audit (click to expand)</summary>

### Checklist

Run each check and record the result as PASS, FAIL, or WARN.

**1. VPC Flow Logs enabled?**

```bash
aws ec2 describe-flow-logs \
  --filter Name=resource-id,Values=$(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].DBSubnetGroup' --output text | head -1) \
  --query 'FlowLogs[*].[FlowLogId,FlowLogStatus]' \
  --output table
```

If no flow logs exist, this is a WARN finding. VPC Flow Logs capture all network traffic metadata - critical for incident investigation.

**2. Security group allows only port 5432?**

```bash
AURORA_SG=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$AURORA_SG \
  --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId]' \
  --output table
```

PASS if only port 5432 with SG references. FAIL if any CIDR rule or port range other than 5432.

**3. No public subnets in DB subnet group?**

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name devops-lab-db-subnet-group \
  --query 'DBSubnetGroups[0].Subnets[*].SubnetIdentifier' --output text | tr '\t' '\n' | while read SUBNET; do
  echo -n "$SUBNET: "
  aws ec2 describe-route-tables \
    --filters Name=association.subnet-id,Values=$SUBNET \
    --query 'RouteTables[0].Routes[?contains(GatewayId, `igw`)].GatewayId' --output text
done
```

PASS if no `igw-*` routes found. FAIL if any subnet has an internet gateway route.

**4. Network ACLs restrict traffic?**

```bash
aws ec2 describe-network-acls \
  --filters Name=association.subnet-id,Values=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name devops-lab-db-subnet-group \
    --query 'DBSubnetGroups[0].Subnets[0].SubnetIdentifier' --output text) \
  --query 'NetworkAcls[0].Entries' --output table
```

WARN if using default NACLs (allow all). Consider adding explicit DENY rules for known bad ranges.

</details>

<details>
<summary>Part 2: Encryption Audit (click to expand)</summary>

### Checklist

**5. Storage encryption with CMK?**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[StorageEncrypted,KmsKeyId]' --output table
```

PASS if `True` and KMS key is a CMK (not `aws/rds`). FAIL if not encrypted.

**6. SSL/TLS enforced?**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" --output text
```

PASS if value is `1`. CRITICAL FAIL if not set.

**7. KMS key rotation enabled?**

```bash
aws kms get-key-rotation-status \
  --key-id alias/devops-lab-aurora-cmk
```

PASS if `KeyRotationEnabled: true`. WARN if false.

**8. Snapshots encrypted?**

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type manual \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,StorageEncrypted]' --output table
```

PASS if all snapshots show `True`. CRITICAL FAIL if any are unencrypted.

**9. Performance Insights encrypted with CMK?**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,PerformanceInsightsKMSKeyId]' --output table
```

PASS if using the CMK. WARN if using default key.

</details>

<details>
<summary>Part 3: Authentication and Authorization Audit (click to expand)</summary>

### Checklist

**10. IAM database authentication enabled?**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' --output text
```

PASS if `True`. HIGH finding if `False`.

**11. Master password in Secrets Manager?**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].MasterUserSecret.SecretStatus' --output text
```

PASS if `active`. HIGH finding if not configured.

**12. No unnecessary superusers?**

Connect to the database and run:

```sql
SELECT usename, usesuper FROM pg_user WHERE usesuper = true;
```

PASS if only `rdsadmin` is a superuser. CRITICAL FAIL if any application user is superuser.

**13. Application role has least privilege?**

```sql
SELECT grantee, privilege_type, table_schema, table_name
FROM information_schema.role_table_grants
WHERE grantee = 'app_service'
ORDER BY table_schema, table_name;
```

PASS if only SELECT, INSERT, UPDATE, DELETE on app schema tables. FAIL if TRUNCATE, DROP, or access to other schemas.

**14. Deletion protection enabled?**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DeletionProtection' --output text
```

PASS if `True`. HIGH finding if `False`.

</details>

<details>
<summary>Part 4: Logging and Monitoring Audit (click to expand)</summary>

### Checklist

**15. pgaudit enabled and configured?**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='pgaudit.log'].ParameterValue" --output text
```

PASS if set to at least `ddl,role`. WARN if `read` or `write` not included.

**16. PostgreSQL logs exported to CloudWatch?**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].EnabledCloudwatchLogsExports' --output json
```

PASS if includes `postgresql`. HIGH finding if empty.

**17. CloudTrail logging RDS API calls?**

```bash
aws cloudtrail get-trail-status \
  --name management-events \
  --query 'IsLogging' --output text
```

PASS if `True`. CRITICAL finding if CloudTrail is not enabled.

**18. Log retention policy set?**

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/rds/cluster/devops-lab-cluster \
  --query 'logGroups[*].[logGroupName,retentionInDays]' --output table
```

PASS if retention is set. WARN if `null` (indefinite retention - unnecessary cost and potential compliance issue).

**19. Authentication failure alerting?**

```bash
aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --query "metricFilters[?filterPattern=='authentication failed']" --output json
```

PASS if a metric filter exists. MEDIUM finding if not - brute-force attacks go undetected.

</details>

<details>
<summary>Part 5: Compliance Checks (click to expand)</summary>

### Checklist

**20. All resources tagged?**

```bash
aws rds list-tags-for-resource \
  --resource-name $(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].DBClusterArn' --output text) \
  --query 'TagList[*].[Key,Value]' --output table
```

PASS if Environment, Application, Team, ManagedBy tags present. WARN if missing tags.

**21. AWS Config rules active?**

```bash
aws configservice describe-config-rules \
  --query "ConfigRules[?contains(ConfigRuleName, 'rds')].[ConfigRuleName,ConfigRuleState]" --output table
```

PASS if encryption and Multi-AZ rules active. MEDIUM finding if no Config rules.

**22. No public instances?**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,PubliclyAccessible]' --output table
```

PASS if all `False`. CRITICAL FAIL if any `True`.

</details>

---

## Deliverable

Create a security findings report:

```markdown
# Security Audit Report

## Summary
- Critical findings: [COUNT]
- High findings: [COUNT]
- Medium findings: [COUNT]
- Low/Informational: [COUNT]

## Findings

### [SEVERITY] - [Finding Title]
- **Description:** What was found
- **Risk:** What could happen if not remediated
- **Evidence:** CLI command output
- **Remediation:** Specific steps to fix
- **Due date:** Based on severity (Critical: 24h, High: 1 week, Medium: 1 month)
```

---

## Summary

A security audit is not a one-time event. Schedule quarterly audits using the automated security audit script from Build 07. Track findings in a centralized system and verify remediation. The script catches the automated checks, but manual review (database role grants, IAM policies, change management processes) requires human judgment.
