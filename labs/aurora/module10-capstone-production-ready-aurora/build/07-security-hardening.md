# Module 10 - Build Guide 07: Security Hardening

**Objective:** Perform a full security audit and hardening of your Aurora stack. Verify encryption, network isolation, IAM authentication, audit logging, and create a security findings report.
**Time:** 35 minutes
**Level:** Senior / Staff
**Prerequisites:** Build Guides 02-03 completed (VPC, security groups, Aurora cluster deployed).

---

## 1. Encryption Audit

### 1.1 Storage Encryption

**On your local workstation:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[StorageEncrypted,KmsKeyId]' \
  --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------------
|  True  | arn:aws:kms:us-east-1:123456789012:key/abc-def-123      |
--------------------------------------------------------------------
```

Verify the KMS key is your CMK (not the default `aws/rds` key):

```bash
aws kms describe-key \
  --key-id $(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].KmsKeyId' --output text) \
  --query 'KeyMetadata.[Description,KeyManager,KeyRotationEnabled]' \
  --output table
```

- `KeyManager` should be `CUSTOMER` (not `AWS`). `AWS` means default key.
- `KeyRotationEnabled` should be `True`.

### 1.2 SSL/TLS Enforcement

**On your local workstation:**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='rds.force_ssl'].[ParameterName,ParameterValue]" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------
| rds.force_ssl  |  1         |
-------------------------------
```

Test SSL enforcement by attempting an unencrypted connection (this should fail):

```bash
psql "host=devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com port=5432 dbname=postgres user=dbadmin sslmode=disable" 2>&1 | head -3
```

Expected output (yours will differ):
```
psql: error: connection to server failed: FATAL: no pg_hba.conf entry for host "10.0.11.x", user "dbadmin", database "postgres", no encryption
```

The connection should be rejected when `sslmode=disable`.

### 1.3 Performance Insights Encryption

**On your local workstation:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,PerformanceInsightsEnabled,PerformanceInsightsKMSKeyId]' \
  --output table
```

Both instances should have Performance Insights enabled with your CMK.

---

## 2. Network Isolation Audit

### 2.1 Public Access Check

**On your local workstation:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,PubliclyAccessible]' \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------
|  devops-lab-cluster-w1  |  False      |
|  devops-lab-cluster-r1  |  False      |
-----------------------------------------
```

Every instance must show `False`.

### 2.2 Security Group Audit

**On your local workstation:**

Get the security group attached to the cluster:

```bash
AURORA_SG=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)
```

```bash
echo "Aurora security group: $AURORA_SG"
```

Check all inbound rules:

```bash
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$AURORA_SG \
  --query 'SecurityGroupRules[?IsEgress==`false`].[SecurityGroupRuleId,IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId]' \
  --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------
| sgr-abc123 | tcp | 5432 | 5432 | None     | sg-app-123    |
| sgr-def456 | tcp | 5432 | 5432 | None     | sg-bastion-456|
--------------------------------------------------------------
```

Verify:
- Only port 5432 is allowed
- No CIDR rules (only security group references)
- No `0.0.0.0/0` anywhere

If you find any CIDR-based rules, replace them with security group references:

```bash
aws ec2 revoke-security-group-ingress \
  --group-id $AURORA_SG \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0
```

### 2.3 Subnet Isolation Check

Verify DB subnets have no internet route:

```bash
DB_SUBNET_GROUP=$(aws rds describe-db-subnet-groups \
  --db-subnet-group-name devops-lab-db-subnet-group \
  --query 'DBSubnetGroups[0].Subnets[*].SubnetIdentifier' \
  --output text)
```

```bash
for SUBNET in $DB_SUBNET_GROUP; do
  echo "Checking subnet: $SUBNET"
  RT_ID=$(aws ec2 describe-route-tables \
    --filters Name=association.subnet-id,Values=$SUBNET \
    --query 'RouteTables[0].RouteTableId' --output text)
  ROUTES=$(aws ec2 describe-route-tables \
    --route-table-ids $RT_ID \
    --query 'RouteTables[0].Routes[?GatewayId!=`local`].GatewayId' \
    --output text)
  if [[ -z "$ROUTES" || "$ROUTES" == "None" ]]; then
    echo "  PASS: No internet route"
  else
    echo "  FAIL: Found route to $ROUTES"
  fi
done
```

Expected output (yours will differ):
```
Checking subnet: subnet-0abc123
  PASS: No internet route
Checking subnet: subnet-0def456
  PASS: No internet route
Checking subnet: subnet-0ghi789
  PASS: No internet route
```

---

## 3. Authentication Audit

### 3.1 IAM Database Authentication

**On your local workstation:**

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

### 3.2 Secrets Manager Integration

**On your local workstation:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].MasterUserSecret.[SecretArn,SecretStatus]' \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------
| arn:aws:secretsmanager:...:secret:rds!cluster-...| active |
-----------------------------------------------------------
```

Verify the secret has rotation configured:

```bash
SECRET_ARN=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].MasterUserSecret.SecretArn' \
  --output text)
```

```bash
aws secretsmanager describe-secret \
  --secret-id $SECRET_ARN \
  --query '[RotationEnabled,RotationRules]' \
  --output json
```

### 3.3 Database User Audit

Connect to the database and audit all users:

```sql
SELECT usename, usesuper, usecreatedb, valuntil
FROM pg_user
ORDER BY usename;
```

Expected output (yours will differ):
```
  usename   | usesuper | usecreatedb |           valuntil
------------+----------+-------------+-------------------------------
 dbadmin    | f        | f           |
 rdsadmin   | t        | t           |
 app_service| f        | f           |
(3 rows)
```

Check for:
- No unnecessary superusers (only `rdsadmin` should be superuser)
- Application users have `valuntil` set for password expiration
- No unused/orphaned users

### 3.4 Deletion Protection

**On your local workstation:**

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

---

## 4. Audit Logging Verification

### 4.1 pgaudit Configuration

**On your local workstation:**

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?starts_with(ParameterName, 'pgaudit') || ParameterName=='shared_preload_libraries'].[ParameterName,ParameterValue]" \
  --output table
```

Expected output (yours will differ):
```
---------------------------------------------------
| shared_preload_libraries | pg_stat_statements,pgaudit |
| pgaudit.log              | ddl,role,write             |
---------------------------------------------------
```

### 4.2 Log Export Verification

**On your local workstation:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].EnabledCloudwatchLogsExports' \
  --output json
```

Expected output (yours will differ):
```json
["postgresql"]
```

### 4.3 Test Audit Logging

Connect to the database and run a DDL statement:

```sql
CREATE TABLE IF NOT EXISTS app.audit_test (id int);
```

```sql
DROP TABLE IF EXISTS app.audit_test;
```

Wait 2 minutes, then check CloudWatch Logs for the audit entry:

```bash
aws logs filter-log-events \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-pattern "AUDIT" \
  --start-time $(date -u -v-5M +%s000) \
  --limit 5 \
  --query 'events[*].message' \
  --output text
```

You should see lines containing `AUDIT:` with the DDL statements you ran.

---

## 5. Create Security Findings Report

Create a consolidated security audit report.

**On your local workstation:**

```bash
vi ~/capstone-aurora/security-audit-report.md
```

Add this template and fill in results:

```markdown
# Security Audit Report: devops-lab-cluster
**Date:** 2026-06-09
**Auditor:** [YOUR NAME]

## Encryption
| Check | Status | Details |
|-------|--------|---------|
| Storage encryption | PASS/FAIL | CMK or default key |
| SSL/TLS enforced | PASS/FAIL | rds.force_ssl value |
| KMS key rotation | PASS/FAIL | enabled/disabled |
| PI encryption | PASS/FAIL | CMK or default key |

## Network
| Check | Status | Details |
|-------|--------|---------|
| Public access disabled | PASS/FAIL | All instances |
| SG least privilege | PASS/FAIL | No 0.0.0.0/0 |
| DB subnets isolated | PASS/FAIL | No internet route |

## Authentication
| Check | Status | Details |
|-------|--------|---------|
| IAM auth enabled | PASS/FAIL | |
| Secrets Manager | PASS/FAIL | Rotation status |
| No extra superusers | PASS/FAIL | User list |
| Deletion protection | PASS/FAIL | |

## Audit
| Check | Status | Details |
|-------|--------|---------|
| pgaudit enabled | PASS/FAIL | Log categories |
| Logs exported | PASS/FAIL | CloudWatch Logs |
| Audit entries verified | PASS/FAIL | DDL test |

## Findings Summary
- Critical: [COUNT]
- High: [COUNT]
- Medium: [COUNT]
- Low: [COUNT]

## Remediation Actions
1. [Finding] - [Action required] - [Due date]
```

---

## 6. Automated Security Check Script

Create a script that runs all security checks in one pass.

**On your local workstation:**

```bash
vi ~/capstone-aurora/scripts/security-audit.sh
```

Add this content:

```bash
#!/usr/bin/env bash
# Security audit script for Aurora cluster
# Usage: bash security-audit.sh

set -euo pipefail

CLUSTER_ID="devops-lab-cluster"
PARAM_GROUP="devops-lab-cluster-params"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local status="$2"
  if [[ "$status" == "PASS" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc - $3"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Security Audit: $CLUSTER_ID ==="
echo ""

CLUSTER_JSON=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0]' --output json)

# 1. Storage encryption
ENCRYPTED=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StorageEncrypted',False))")
if [[ "$ENCRYPTED" == "True" ]]; then
  check "Storage encryption enabled" "PASS"
else
  check "Storage encryption enabled" "FAIL" "Requires cluster recreation"
fi

# 2. SSL forced
FORCE_SSL=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP" \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" --output text)
if [[ "$FORCE_SSL" == "1" ]]; then
  check "SSL/TLS enforced" "PASS"
else
  check "SSL/TLS enforced" "FAIL" "Set rds.force_ssl = 1"
fi

# 3. IAM auth
IAM=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('IAMDatabaseAuthenticationEnabled',False))")
if [[ "$IAM" == "True" ]]; then
  check "IAM authentication enabled" "PASS"
else
  check "IAM authentication enabled" "FAIL" "Enable IAM auth"
fi

# 4. Deletion protection
DEL_PROT=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('DeletionProtection',False))")
if [[ "$DEL_PROT" == "True" ]]; then
  check "Deletion protection enabled" "PASS"
else
  check "Deletion protection enabled" "FAIL" "Enable deletion protection"
fi

# 5. Public access (check all instances)
INSTANCES=$(aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values="$CLUSTER_ID" \
  --query 'DBInstances[*].[DBInstanceIdentifier,PubliclyAccessible]' --output json)
PUBLIC_FOUND=$(echo "$INSTANCES" | python3 -c "import sys,json; data=json.load(sys.stdin); print(any(i[1] for i in data))")
if [[ "$PUBLIC_FOUND" == "False" ]]; then
  check "No public access on instances" "PASS"
else
  check "No public access on instances" "FAIL" "Disable public access"
fi

# 6. pgaudit enabled
PGAUDIT=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP" \
  --query "Parameters[?ParameterName=='pgaudit.log'].ParameterValue" --output text)
if [[ -n "$PGAUDIT" && "$PGAUDIT" != "None" && "$PGAUDIT" != "none" ]]; then
  check "pgaudit logging enabled ($PGAUDIT)" "PASS"
else
  check "pgaudit logging enabled" "FAIL" "Configure pgaudit.log"
fi

# 7. Log export
LOG_EXPORTS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin).get('EnabledCloudwatchLogsExports',[])))")
if echo "$LOG_EXPORTS" | grep -q "postgresql"; then
  check "PostgreSQL logs exported to CloudWatch" "PASS"
else
  check "PostgreSQL logs exported to CloudWatch" "FAIL" "Enable log export"
fi

# 8. Secrets Manager
SECRET_STATUS=$(echo "$CLUSTER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); s=d.get('MasterUserSecret',{}); print(s.get('SecretStatus','not-configured'))")
if [[ "$SECRET_STATUS" == "active" ]]; then
  check "Secrets Manager master password" "PASS"
else
  check "Secrets Manager master password" "FAIL" "Enable managed master password"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
```

Make it executable:

```bash
chmod +x ~/capstone-aurora/scripts/security-audit.sh
```

Run it:

```bash
bash ~/capstone-aurora/scripts/security-audit.sh
```

Expected output (yours will differ):
```
=== Security Audit: devops-lab-cluster ===

  PASS: Storage encryption enabled
  PASS: SSL/TLS enforced
  PASS: IAM authentication enabled
  PASS: Deletion protection enabled
  PASS: No public access on instances
  PASS: pgaudit logging enabled (ddl,role,write)
  PASS: PostgreSQL logs exported to CloudWatch
  PASS: Secrets Manager master password

=== Results: 8 passed, 0 failed ===
```

---

## Summary

You have performed a complete security audit and hardening of your Aurora stack:

- **Encryption** verified at rest (CMK), in transit (SSL/TLS), and for Performance Insights
- **Network isolation** confirmed - no public access, security groups use SG references only, DB subnets fully isolated
- **Authentication** - IAM auth enabled, Secrets Manager managing master password, no unnecessary superusers
- **Audit logging** - pgaudit capturing DDL, role, and write operations, logs exported to CloudWatch
- **Deletion protection** enabled as a safety net
- **Automated security audit script** for repeatable verification

Run the security audit script after every infrastructure change to catch regressions.

**Next:** [Build 08 - Chaos Testing](./08-chaos-testing.md)
