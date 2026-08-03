# BUILD 04: Multi-Account Management

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 45-60 minutes
**Level:** Intermediate

---

## Objective

Set up a multi-account Aurora PostgreSQL management strategy for dev, staging, and production environments. By the end of this guide, you will have cross-account IAM roles, standardized parameter groups, and a fleet inventory system.

---

## Prerequisites

- At least two AWS accounts (or simulate with separate IAM roles in one account)
- AWS CLI configured with appropriate permissions
- Aurora PostgreSQL cluster `devops-lab-cluster` running in the "production" account

---

## Section 1: Account Strategy for Aurora

### 1.1 Understand the Multi-Account Model

Enterprise organizations separate environments into different AWS accounts for isolation, billing, and security.

| Account | Purpose | Aurora Config | Who Has Access |
|---------|---------|--------------|---------------|
| Development | Feature testing, experiments | db.r6g.medium, no Multi-AZ | Developers (read/write) |
| Staging | Pre-production validation | db.r6g.large, Multi-AZ | DBA team + QA |
| Production | Live customer traffic | db.r6g.xlarge+, Multi-AZ, readers | DBA team only |

### 1.2 Create the Fleet Inventory

Track all Aurora clusters across accounts in a single inventory file:

```bash
mkdir -p ~/sre-practice/fleet
```

```bash
vi ~/sre-practice/fleet/inventory.yml
```

```yaml
---
fleet_name: devops-lab-fleet
last_updated: "2026-06-09"
owner: dba-team

accounts:
  development:
    account_id: "111111111111"
    region: us-east-1
    clusters:
      - name: devops-dev-cluster
        engine: aurora-postgresql
        version: "16.4"
        instance_class: db.r6g.medium
        instances: 1
        multi_az: false
        storage_type: aurora
        parameter_group: devops-dev-params
        tags:
          Environment: development
          CostCenter: CC-DEV
          Team: platform

  staging:
    account_id: "222222222222"
    region: us-east-1
    clusters:
      - name: devops-staging-cluster
        engine: aurora-postgresql
        version: "16.4"
        instance_class: db.r6g.large
        instances: 2
        multi_az: true
        storage_type: aurora
        parameter_group: devops-staging-params
        tags:
          Environment: staging
          CostCenter: CC-STAGING
          Team: platform

  production:
    account_id: "333333333333"
    region: us-east-1
    clusters:
      - name: devops-lab-cluster
        engine: aurora-postgresql
        version: "16.4"
        instance_class: db.r6g.xlarge
        instances: 3
        multi_az: true
        storage_type: aurora-iopt1
        parameter_group: devops-prod-params
        tags:
          Environment: production
          CostCenter: CC-PROD
          Team: platform
```

Save and exit vi (`:wq`).

---

## Section 2: Standardized Parameter Groups

### 2.1 Define the Base Parameter Template

All environments share a base configuration. Environment-specific overrides are layered on top.

```bash
vi ~/sre-practice/fleet/base-parameters.json
```

```json
[
    {
        "ParameterName": "shared_preload_libraries",
        "ParameterValue": "pg_stat_statements",
        "ApplyMethod": "pending-reboot",
        "Description": "Required for query performance monitoring"
    },
    {
        "ParameterName": "log_min_duration_statement",
        "ParameterValue": "1000",
        "ApplyMethod": "immediate",
        "Description": "Log queries taking longer than 1 second"
    },
    {
        "ParameterName": "log_connections",
        "ParameterValue": "1",
        "ApplyMethod": "immediate",
        "Description": "Log all connection attempts"
    },
    {
        "ParameterName": "log_disconnections",
        "ParameterValue": "1",
        "ApplyMethod": "immediate",
        "Description": "Log all disconnections"
    },
    {
        "ParameterName": "log_lock_waits",
        "ParameterValue": "1",
        "ApplyMethod": "immediate",
        "Description": "Log lock waits longer than deadlock_timeout"
    },
    {
        "ParameterName": "idle_in_transaction_session_timeout",
        "ParameterValue": "300000",
        "ApplyMethod": "immediate",
        "Description": "Kill idle-in-transaction sessions after 5 minutes (300000ms)"
    },
    {
        "ParameterName": "statement_timeout",
        "ParameterValue": "30000",
        "ApplyMethod": "immediate",
        "Description": "Kill queries running longer than 30 seconds (30000ms)"
    }
]
```

Save and exit vi (`:wq`).

### 2.2 Define Environment-Specific Overrides

```bash
vi ~/sre-practice/fleet/dev-overrides.json
```

```json
[
    {
        "ParameterName": "log_min_duration_statement",
        "ParameterValue": "0",
        "ApplyMethod": "immediate",
        "Description": "Log all queries in dev for debugging"
    },
    {
        "ParameterName": "statement_timeout",
        "ParameterValue": "60000",
        "ApplyMethod": "immediate",
        "Description": "Allow longer queries in dev (60 seconds)"
    }
]
```

Save and exit vi (`:wq`).

```bash
vi ~/sre-practice/fleet/prod-overrides.json
```

```json
[
    {
        "ParameterName": "log_min_duration_statement",
        "ParameterValue": "1000",
        "ApplyMethod": "immediate",
        "Description": "Only log queries over 1 second in production"
    },
    {
        "ParameterName": "statement_timeout",
        "ParameterValue": "30000",
        "ApplyMethod": "immediate",
        "Description": "Strict 30-second query timeout in production"
    },
    {
        "ParameterName": "idle_in_transaction_session_timeout",
        "ParameterValue": "60000",
        "ApplyMethod": "immediate",
        "Description": "Strict 1-minute idle-in-transaction timeout in production"
    }
]
```

Save and exit vi (`:wq`).

### 2.3 Create the Parameter Group

```bash
aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params \
    --db-parameter-group-family aurora-postgresql16 \
    --description "Production parameter group for devops fleet"
```

The `--db-parameter-group-family` flag must match your Aurora PostgreSQL major version. For PostgreSQL 16.x, use `aurora-postgresql16`.

Expected output (yours will differ):
```json
{
    "DBClusterParameterGroup": {
        "DBClusterParameterGroupName": "devops-prod-params",
        "DBParameterGroupFamily": "aurora-postgresql16",
        ...
    }
}
```

### 2.4 Apply Base Parameters

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params \
    --parameters file://~/sre-practice/fleet/base-parameters.json
```

Expected output:
```json
{
    "DBClusterParameterGroupName": "devops-prod-params"
}
```

### 2.5 Apply Production Overrides

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params \
    --parameters file://~/sre-practice/fleet/prod-overrides.json
```

### 2.6 Verify Parameter Values

```bash
aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name devops-prod-params \
    --query "Parameters[?ParameterName=='log_min_duration_statement' || ParameterName=='statement_timeout' || ParameterName=='idle_in_transaction_session_timeout'].{Name:ParameterName,Value:ParameterValue,Source:Source}" \
    --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------
|               DescribeDBClusterParameters                  |
+-------------------------------------+---------+------------+
|                Name                 |  Source  |   Value    |
+-------------------------------------+---------+------------+
| idle_in_transaction_session_timeout | user    | 60000      |
| log_min_duration_statement          | user    | 1000       |
| statement_timeout                   | user    | 30000      |
+-------------------------------------+---------+------------+
```

---

## Section 3: Cross-Account IAM Roles

### 3.1 Create the Cross-Account Trust Policy

In multi-account setups, the DBA team in the management account assumes roles in other accounts. This is done through cross-account IAM role assumption.

```bash
vi ~/sre-practice/fleet/cross-account-trust.json
```

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::333333333333:role/dba-team-role"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "Bool": {
                    "aws:MultiFactorAuthPresent": "true"
                }
            }
        }
    ]
}
```

Save and exit vi (`:wq`).

This trust policy allows the `dba-team-role` in account `333333333333` (production) to assume this role. The MFA condition requires multi-factor authentication for added security.

### 3.2 Create the DBA Role in Each Account

In each target account (dev, staging), create a role that the DBA team can assume:

```bash
aws iam create-role \
    --role-name devops-dba-cross-account \
    --assume-role-policy-document file://~/sre-practice/fleet/cross-account-trust.json \
    --description "Cross-account role for DBA fleet management"
```

### 3.3 Attach RDS Permissions

```bash
aws iam attach-role-policy \
    --role-name devops-dba-cross-account \
    --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
```

For production, use a more restrictive custom policy instead of full access:

```bash
vi ~/sre-practice/fleet/prod-dba-policy.json
```

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowRDSReadAndModify",
            "Effect": "Allow",
            "Action": [
                "rds:Describe*",
                "rds:List*",
                "rds:ModifyDBClusterParameterGroup",
                "rds:ModifyDBInstance",
                "rds:RebootDBInstance",
                "rds:CreateDBClusterSnapshot",
                "rds:FailoverDBCluster"
            ],
            "Resource": "*"
        },
        {
            "Sid": "DenyDestructiveActions",
            "Effect": "Deny",
            "Action": [
                "rds:DeleteDBCluster",
                "rds:DeleteDBInstance",
                "rds:RemoveFromGlobalCluster"
            ],
            "Resource": "*"
        }
    ]
}
```

Save and exit vi (`:wq`).

This policy allows DBAs to manage clusters but explicitly denies deletion of production databases.

### 3.4 Test Role Assumption

```bash
aws sts assume-role \
    --role-arn arn:aws:iam::111111111111:role/devops-dba-cross-account \
    --role-session-name dba-fleet-check \
    --query 'Credentials.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey,SessionToken:SessionToken}' \
    --output json
```

The `--role-session-name` flag creates a named session that appears in CloudTrail logs, making it easy to trace who did what.

---

## Section 4: Fleet Health Check Script

### 4.1 Create the Fleet Check Script

```bash
vi ~/sre-practice/fleet/fleet-check.sh
```

```bash
#!/bin/bash
# Fleet Health Check - checks all Aurora clusters in the fleet
# Usage: ./fleet-check.sh

set -euo pipefail

CLUSTERS=(
    "devops-lab-cluster"
)

echo "========================================="
echo "Fleet Health Check - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "========================================="

for CLUSTER in "${CLUSTERS[@]}"; do
    echo ""
    echo "--- Cluster: ${CLUSTER} ---"

    # Get cluster status
    STATUS=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${CLUSTER}" \
        --query 'DBClusters[0].Status' \
        --output text 2>/dev/null || echo "UNREACHABLE")
    echo "  Status: ${STATUS}"

    # Get instance details
    aws rds describe-db-instances \
        --filters Name=db-cluster-id,Values="${CLUSTER}" \
        --query 'DBInstances[].{Instance:DBInstanceIdentifier,Class:DBInstanceClass,Status:DBInstanceStatus,AZ:AvailabilityZone}' \
        --output table 2>/dev/null || echo "  Could not fetch instances"

    # Get storage used
    STORAGE=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name VolumeBytesUsed \
        --dimensions Name=DBClusterIdentifier,Value="${CLUSTER}" \
        --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 3600 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")

    if [ "${STORAGE}" != "N/A" ] && [ "${STORAGE}" != "None" ]; then
        STORAGE_GB=$(echo "scale=2; ${STORAGE} / 1073741824" | bc)
        echo "  Storage Used: ${STORAGE_GB} GB"
    else
        echo "  Storage Used: N/A"
    fi

    # Get CPU utilization (last hour average)
    CPU=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name CPUUtilization \
        --dimensions Name=DBClusterIdentifier,Value="${CLUSTER}" \
        --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 3600 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")
    echo "  CPU (1hr avg): ${CPU}%"

done

echo ""
echo "========================================="
echo "Fleet check complete"
echo "========================================="
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/sre-practice/fleet/fleet-check.sh
```

The `chmod +x` command makes the script executable.

### 4.2 Run the Fleet Check

```bash
~/sre-practice/fleet/fleet-check.sh
```

Expected output (yours will differ):
```
=========================================
Fleet Health Check - 2026-06-09T14:30:00Z
=========================================

--- Cluster: devops-lab-cluster ---
  Status: available
----------------------------------------------------
| Instance              | Class        | Status    | AZ          |
+-----------------------+--------------+-----------+-------------+
| devops-lab-...-1      | db.r6g.large | available | us-east-1a  |
| devops-lab-...-2      | db.r6g.large | available | us-east-1b  |
+-----------------------+--------------+-----------+-------------+
  Storage Used: 2.45 GB
  CPU (1hr avg): 12.3%

=========================================
Fleet check complete
=========================================
```

---

## Section 5: Drift Detection

### 5.1 Compare Parameter Groups Across Environments

```bash
vi ~/sre-practice/fleet/check-drift.sh
```

```bash
#!/bin/bash
# Parameter Group Drift Detection
# Compares key parameters across environments

set -euo pipefail

PARAM_GROUPS=(
    "devops-prod-params"
)

KEY_PARAMS=(
    "log_min_duration_statement"
    "statement_timeout"
    "idle_in_transaction_session_timeout"
    "shared_preload_libraries"
    "log_connections"
)

echo "Parameter Drift Report - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "========================================================="

for PG in "${PARAM_GROUPS[@]}"; do
    echo ""
    echo "Parameter Group: ${PG}"
    echo "---------------------------------------------------------"

    for PARAM in "${KEY_PARAMS[@]}"; do
        VALUE=$(aws rds describe-db-cluster-parameters \
            --db-cluster-parameter-group-name "${PG}" \
            --query "Parameters[?ParameterName=='${PARAM}'].ParameterValue" \
            --output text 2>/dev/null || echo "NOT_FOUND")

        SOURCE=$(aws rds describe-db-cluster-parameters \
            --db-cluster-parameter-group-name "${PG}" \
            --query "Parameters[?ParameterName=='${PARAM}'].Source" \
            --output text 2>/dev/null || echo "N/A")

        printf "  %-45s = %-15s (%s)\n" "${PARAM}" "${VALUE}" "${SOURCE}"
    done
done
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/sre-practice/fleet/check-drift.sh
```

```bash
~/sre-practice/fleet/check-drift.sh
```

Expected output (yours will differ):
```
Parameter Drift Report - 2026-06-09T14:35:00Z
=========================================================

Parameter Group: devops-prod-params
---------------------------------------------------------
  log_min_duration_statement                  = 1000            (user)
  statement_timeout                           = 30000           (user)
  idle_in_transaction_session_timeout         = 60000           (user)
  shared_preload_libraries                    = pg_stat_statements (user)
  log_connections                             = 1               (user)
```

---

## Cleanup

The files created in `~/sre-practice/fleet/` are useful for ongoing fleet management. To remove the parameter group created in this lab:

```bash
aws rds delete-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-prod-params
```

Note: You cannot delete a parameter group that is currently in use by a cluster.

---

## Summary

| What You Did | Why It Matters |
|-------------|---------------|
| Created fleet inventory | Single source of truth for all clusters across accounts |
| Standardized parameter groups | Consistent configuration prevents environment drift |
| Built environment-specific overrides | Dev needs different settings than production |
| Set up cross-account IAM | DBAs manage all environments from one account |
| Created fleet health check script | One command shows the state of every cluster |
| Built drift detection | Catch configuration divergence before it causes incidents |

**Next:** [BUILD 05 - Compliance and Tagging](./05-compliance-and-tagging.md)
