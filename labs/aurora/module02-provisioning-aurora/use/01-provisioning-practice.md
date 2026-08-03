# USE 01 - Provisioning Practice
## Module 02: Provisioning Aurora

**Estimated time:** 45 minutes
**Type:** Guided exercise with requirements (no step-by-step help)
**Prerequisite:** BUILD guides for Module 02 complete

---

## Overview

You are a junior DBA at [COMPANY]. The lead engineer has submitted this request:

> "We need an Aurora PostgreSQL cluster for the new [PROJECT] microservice. This is a staging environment that mirrors production. We need encryption enabled, specific engine version pinning, and proper tagging for cost tracking. Expected load is moderate - about 50 concurrent connections at peak."

Your job: provision everything from scratch using the CLI.

---

## Requirements

Work through each requirement on your own. Reference the BUILD guides if you get stuck, but try each step yourself first.

### Requirement 1 - Create a DB Subnet Group

Create a DB subnet group called `devops-lab-subnetgroup`.

Rules:
- Must be in your default VPC
- Must include subnets in at least 2 different Availability Zones

Hints:
- Find your VPC ID first with `aws ec2 describe-vpcs`
- Then find subnet IDs with `aws ec2 describe-subnets`
- Use `aws rds create-db-subnet-group`

Confirm your subnet group is valid:

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name devops-lab-subnetgroup \
  --query "DBSubnetGroups[0].SubnetGroupStatus" \
  --output text
```

Expected output:
```
Complete
```

<details>
<summary>Solution - Create Subnet Group</summary>

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ' ')

aws rds create-db-subnet-group \
  --db-subnet-group-name devops-lab-subnetgroup \
  --db-subnet-group-description "Subnet group for DevOps lab Aurora cluster" \
  --subnet-ids $SUBNET_IDS
```

</details>

---

### Requirement 2 - Create a Security Group

Create a security group called `devops-lab-aurora-sg` in your default VPC.

Rules:
- Allow inbound PostgreSQL (port 5432) from your current IP only
- No other inbound rules

Confirm the rule exists:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-aurora-sg" \
  --query "SecurityGroups[0].IpPermissions[0]" \
  --output json
```

Expected output should show `FromPort: 5432` and a `/32` CIDR matching your IP.

<details>
<summary>Solution - Create Security Group</summary>

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

SG_ID=$(aws ec2 create-security-group \
  --group-name devops-lab-aurora-sg \
  --description "Security group for DevOps Aurora lab" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text)

MY_IP=$(curl -s https://checkip.amazonaws.com)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 5432 \
  --cidr "${MY_IP}/32"
```

</details>

---

### Requirement 3 - Create a Custom Cluster Parameter Group

Create a cluster parameter group called `devops-lab-cluster-params` for the `aurora-postgresql16` family.

Confirm it exists:

```bash
aws rds describe-db-cluster-parameter-groups \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "DBClusterParameterGroups[0].DBClusterParameterGroupName" \
  --output text
```

Expected output:
```
devops-lab-cluster-params
```

<details>
<summary>Solution - Create Cluster Parameter Group</summary>

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom cluster params for DevOps lab"
```

</details>

---

### Requirement 4 - Create the Aurora Cluster

Create an Aurora PostgreSQL cluster with these exact specifications:

| Setting | Value |
|---------|-------|
| Cluster identifier | `devops-lab-cluster` |
| Engine | `aurora-postgresql` |
| Engine version | `16.4` (or latest 16.x available) |
| Master username | `clusteradmin` |
| Initial database | `devopsdb` |
| Subnet group | `devops-lab-subnetgroup` |
| Security group | `devops-lab-aurora-sg` |
| Cluster parameter group | `devops-lab-cluster-params` |
| Backup retention | 7 days |
| Encryption | Enabled (default KMS key) |
| Deletion protection | Disabled (for lab cleanup) |
| Tags | `Environment=staging`, `Team=devops`, `Project=lab` |

<details>
<summary>Solution - Create Aurora Cluster</summary>

```bash
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-aurora-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)

aws rds create-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --engine-version 16.4 \
  --master-username clusteradmin \
  --master-user-password "YourSecurePassword123!" \
  --database-name devopsdb \
  --db-subnet-group-name devops-lab-subnetgroup \
  --vpc-security-group-ids "$SG_ID" \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --backup-retention-period 7 \
  --storage-encrypted \
  --no-deletion-protection \
  --tags Key=Environment,Value=staging Key=Team,Value=devops Key=Project,Value=lab
```

</details>

---

### Requirement 5 - Add the Writer Instance

Create a writer instance in the cluster:

| Setting | Value |
|---------|-------|
| Instance identifier | `devops-lab-cluster-writer` |
| Instance class | `db.r6g.large` |
| Engine | `aurora-postgresql` |
| Public access | Yes |

Wait until the instance status is `available` before proceeding.

<details>
<summary>Solution - Create Writer Instance</summary>

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-cluster-writer \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --publicly-accessible

aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-writer
```

</details>

---

### Requirement 6 - Verify the Cluster Configuration

After the cluster is available, answer each question by running the appropriate CLI command.

**Question A:** What is the cluster endpoint (writer)?

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Endpoint" \
  --output text
```

Write down the endpoint.

**Question B:** What engine version was installed?

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].EngineVersion" \
  --output text
```

**Question C:** Is encryption enabled?

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].StorageEncrypted" \
  --output text
```

Expected: `True`

**Question D:** What tags are attached?

```bash
CLUSTER_ARN=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterArn" \
  --output text)

aws rds list-tags-for-resource \
  --resource-name "$CLUSTER_ARN" \
  --query "TagList[*]" \
  --output table
```

You should see `Environment=staging`, `Team=devops`, and `Project=lab`.

**Question E:** What is the backup retention period?

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].BackupRetentionPeriod" \
  --output text
```

Expected: `7`

---

### Requirement 7 - Connect and Validate

Connect to the cluster and run these checks.

**Check A:** Can you connect?

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

You should reach a psql prompt.

**Check B:** Confirm the database name:

```sql
SELECT current_database();
```

Expected: `devopsdb`

**Check C:** Confirm encryption is active at the connection level:

```sql
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected: `t`

**Check D:** Confirm you are on the writer:

```sql
SELECT pg_is_in_recovery();
```

Expected: `f` (false means this is the writer)

**Check E:** Create a test table and insert data:

```sql
CREATE TABLE deployment_log (
    id SERIAL PRIMARY KEY,
    service_name TEXT NOT NULL,
    version TEXT NOT NULL,
    deployed_at TIMESTAMPTZ DEFAULT NOW(),
    deployed_by TEXT DEFAULT current_user
);

INSERT INTO deployment_log (service_name, version) VALUES
    ('auth-service', 'v2.1.0'),
    ('api-gateway', 'v1.8.3'),
    ('worker', 'v3.0.1');

SELECT count(*) FROM deployment_log;
```

Expected: `3`

**Check F:** Exit psql:

```sql
\q
```

---

### Requirement 8 - Answer the Questions

Based on what you built, answer these questions in writing.

1. Why did we use `db.r6g.large` instead of `db.t3.medium` for this staging cluster?

2. What is the difference between `--storage-encrypted` and SSL on the connection? Do you need both?

3. Why did we use a 7-day backup retention instead of 1 day?

4. A developer asks: "Can I connect from my laptop at home?" What do you check first?

5. Why did we tag the cluster with `Environment`, `Team`, and `Project`?

---

## Cleanup

Delete in this order:

1. Delete the writer instance (skip final snapshot)
2. Wait for deletion to complete
3. Delete the cluster (skip final snapshot)
4. Delete the subnet group
5. Delete the security group
6. Delete the cluster parameter group

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-writer \
  --skip-final-snapshot

aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-writer

aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --skip-final-snapshot

aws rds delete-db-subnet-group \
  --db-subnet-group-name devops-lab-subnetgroup

aws ec2 delete-security-group \
  --filters "Name=group-name,Values=devops-lab-aurora-sg"

aws rds delete-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params
```

---

## Self-Assessment

Rate yourself on each skill (1 = needed lots of help, 3 = did it independently):

| Skill | Rating |
|-------|--------|
| Creating a subnet group via CLI | 1 / 2 / 3 |
| Creating and configuring a security group | 1 / 2 / 3 |
| Creating a cluster parameter group | 1 / 2 / 3 |
| Creating an Aurora cluster with encryption and tags | 1 / 2 / 3 |
| Adding an instance to the cluster | 1 / 2 / 3 |
| Verifying cluster configuration with CLI queries | 1 / 2 / 3 |
| Connecting with psql and running validation queries | 1 / 2 / 3 |

If you rated yourself 1 on any skill, go back to the corresponding BUILD guide and do it again.
