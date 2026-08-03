# Build 02 - Create an Aurora Cluster (CLI)
## Module 02 - Provisioning Aurora (CLI + Console)

**Estimated time:** 45 minutes
**Difficulty:** Beginner
**Cost:** ~$0.20 for this lab session (Aurora db.t3.medium is ~$0.082/hour, two instances)
**Prerequisite:** Module 01 complete (VPC, subnets, security group, and subnet group created)

---

## What You Will Do

You will create an Aurora PostgreSQL cluster with one writer and one reader using the AWS CLI. Unlike the Console approach in Build 01, here you control every name and parameter explicitly. By the end you will:

- Have a running Aurora cluster named `devops-lab-cluster`
- Have two instances: `devops-lab-writer-1` and `devops-lab-reader-1`
- Understand every flag in each CLI command
- Know how to wait for resources and retrieve endpoints

> **Cost warning:** Aurora db.t3.medium costs approximately $0.082 per hour per instance. Two instances run about $0.164/hour. Delete the cluster when done.

> **Note:** If you already created a cluster in Build 01 (Console), delete it first or use a different cluster identifier. You cannot have two clusters with the same name in the same region.

---

## Before You Start

You need these values from Module 01. Gather them now so you can use them in the commands below.

### Get Your VPC ID

**In your terminal** (local machine):

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)
```

This finds your default VPC ID and saves it to a variable. If you are using a custom VPC, replace the filter or set `VPC_ID` manually.

```bash
echo "VPC ID: $VPC_ID"
```

Expected output (yours will differ):
```
VPC ID: vpc-0abc1234def56789a
```

### Get Your Security Group ID

**In your terminal** (local machine):

```bash
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)
```

Replace `devops-lab-sg` with the name of the security group you created in Module 01.

```bash
echo "Security Group ID: $SG_ID"
```

Expected output (yours will differ):
```
Security Group ID: sg-0abc123def456789a
```

### Verify Your Subnet Group Exists

**In your terminal** (local machine):

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name devops-lab-subnet-group \
  --query "DBSubnetGroups[0].{Name:DBSubnetGroupName,Status:SubnetGroupStatus}" \
  --output table
```

Replace `devops-lab-subnet-group` with the name of the subnet group you created in Module 01.

Expected output (yours will differ):
```
-----------------------------------------
|       DescribeDBSubnetGroups          |
+----------------------------+----------+
|           Name             |  Status  |
+----------------------------+----------+
|  devops-lab-subnet-group   | Complete |
+----------------------------+----------+
```

If this returns an error, go back to Module 01 and create the subnet group.

### Set Your Password

**In your terminal** (local machine):

```bash
export MASTER_PASSWORD="YourStrongPassword123!"
```

Replace with a strong password of your choice. This variable is used in the commands below so the password does not appear in each command.

> **Warning:** This stores the password in your shell session. After the lab, clear it with: `unset MASTER_PASSWORD`

---

## Part A - Create the Aurora Cluster

The cluster is the logical container. It creates the shared storage layer and configures cluster-level settings. No compute instances are created yet.

### Step 1 - Create the Cluster

**In your terminal** (local machine):

```bash
aws rds create-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username labadmin \
  --master-user-password "$MASTER_PASSWORD" \
  --db-subnet-group-name devops-lab-subnet-group \
  --vpc-security-group-ids "$SG_ID" \
  --database-name labdb \
  --backup-retention-period 1 \
  --port 5432 \
  --deletion-protection \
  --no-deletion-protection
```

What each flag does:

- `--db-cluster-identifier devops-lab-cluster` - unique name for this cluster in your AWS account and region. Must be lowercase and can include hyphens.

- `--engine aurora-postgresql` - tells AWS to create an Aurora cluster with PostgreSQL compatibility. This is different from `postgres` which creates standard RDS PostgreSQL.

- `--engine-version 16.6` - the PostgreSQL-compatible version. Check available versions with `aws rds describe-db-engine-versions --engine aurora-postgresql`. If 16.6 is not available, use the latest 16.x version shown.

- `--master-username labadmin` - the admin user Aurora creates. This user is a member of `rds_superuser` (not a true superuser).

- `--master-user-password "$MASTER_PASSWORD"` - password for the admin user. Must be at least 8 characters.

- `--db-subnet-group-name devops-lab-subnet-group` - which subnets Aurora can place instances in. Must span at least 2 AZs.

- `--vpc-security-group-ids "$SG_ID"` - firewall rules controlling who can connect. Your security group should allow port 5432 from your IP.

- `--database-name labdb` - creates an initial database inside the cluster. Without this, only the default `postgres` database exists.

- `--backup-retention-period 1` - keep automated backups for 1 day. Default is 7 days. For a lab, 1 day saves storage costs.

- `--port 5432` - the PostgreSQL port. 5432 is the default.

- `--no-deletion-protection` - allows the cluster to be deleted without removing deletion protection first. In production, use `--deletion-protection`.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "Status": "creating",
        "Engine": "aurora-postgresql",
        "EngineVersion": "16.6",
        "Endpoint": "devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com",
        "ReaderEndpoint": "devops-lab-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com",
        "DatabaseName": "labdb",
        ...
    }
}
```

Notice that the cluster endpoints are returned immediately, even before the cluster is fully available. Save both endpoints now.

### Step 2 - Save the Endpoints

**In your terminal** (local machine):

```bash
WRITER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Endpoint" \
  --output text)
```

```bash
READER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].ReaderEndpoint" \
  --output text)
```

```bash
echo "Writer endpoint: $WRITER_ENDPOINT"
echo "Reader endpoint: $READER_ENDPOINT"
```

Expected output (yours will differ):
```
Writer endpoint: devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com
Reader endpoint: devops-lab-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com
```

---

## Part B - Create the Writer Instance

The cluster exists but has no compute. You need to add at least one instance to connect to the database.

### Step 1 - Create the Writer Instance

**In your terminal** (local machine):

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-writer-1 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible
```

What each flag does:

- `--db-instance-identifier devops-lab-writer-1` - unique name for this instance. Aurora automatically assigns it the writer role because it is the first instance in the cluster.

- `--db-cluster-identifier devops-lab-cluster` - which cluster this instance belongs to. Must match an existing cluster.

- `--db-instance-class db.t3.medium` - the server size. db.t3.medium has 2 vCPUs and 4 GB RAM. This is the smallest instance class available for Aurora.

- `--engine aurora-postgresql` - must match the cluster's engine. If the cluster is aurora-postgresql, the instance must also be aurora-postgresql.

- `--publicly-accessible` - assigns a public IP so you can connect from outside the VPC. In production, omit this flag.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-writer-1",
        "DBInstanceClass": "db.t3.medium",
        "Engine": "aurora-postgresql",
        "DBInstanceStatus": "creating",
        ...
    }
}
```

---

## Part C - Create the Reader Instance

### Step 1 - Create the Reader Instance

**In your terminal** (local machine):

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible
```

This command is identical to the writer command except for `--db-instance-identifier`. Aurora automatically assigns the reader role to any instance added after the first one.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-reader-1",
        "DBInstanceClass": "db.t3.medium",
        "Engine": "aurora-postgresql",
        "DBInstanceStatus": "creating",
        ...
    }
}
```

> **Why no `--db-subnet-group-name` on instances?** The subnet group is set at the cluster level. All instances in the cluster inherit the cluster's subnet group. Aurora automatically places each instance in a different AZ within the subnet group.

---

## Part D - Wait for the Cluster to Be Available

### Step 1 - Wait for the Cluster

**In your terminal** (local machine):

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier devops-lab-cluster
```

This command blocks until the cluster status changes to `available`. It polls every 30 seconds and times out after 30 minutes. Your cursor will sit still while waiting.

This typically takes 10 to 15 minutes.

### Step 2 - Wait for the Writer Instance

**In your terminal** (local machine):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-writer-1
```

### Step 3 - Wait for the Reader Instance

**In your terminal** (local machine):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-reader-1
```

> **Tip:** You can run the two instance wait commands in separate terminal tabs to wait for them in parallel.

---

## Part E - Verify the Cluster

### Step 1 - Check Cluster Status and Endpoints

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].{Status:Status,Writer:Endpoint,Reader:ReaderEndpoint,Port:Port,Engine:EngineVersion}" \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------------------------------------
|                                   DescribeDBClusters                                   |
+--------+--------+------+--------------------------+--------------------------+
| Engine | Port   | Status | Reader                 | Writer                   |
+--------+--------+--------+------------------------+--------------------------+
| 16.6   | 5432   | available | devops-lab-cluster... | devops-lab-cluster...  |
+--------+--------+--------+------------------------+--------------------------+
```

Confirm the Status is `available`.

### Step 2 - Check Cluster Members

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,PromotionTier:PromotionTier}" \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------
|                  DescribeDBClusters                      |
+---------------------+----------+----------------+
|      Instance       | IsWriter | PromotionTier  |
+---------------------+----------+----------------+
|  devops-lab-writer-1|  True    |  1             |
|  devops-lab-reader-1|  False   |  1             |
+---------------------+----------+----------------+
```

`IsWriter: True` confirms the writer role. `IsWriter: False` confirms the reader role.

The `PromotionTier` (1-15) controls failover priority. Lower numbers are promoted first. Both instances have tier 1, so Aurora would pick either one during failover.

### Step 3 - Check Instance Details

**In your terminal** (local machine):

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Class:DBInstanceClass,AZ:AvailabilityZone,Status:DBInstanceStatus,Endpoint:Endpoint.Address}" \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------------------------------------------------
|                                      DescribeDBInstances                                           |
+----------+-----------------+---------------+-----------+------------------------------------------+
|    AZ    |     Class       |      ID       |  Status   |               Endpoint                   |
+----------+-----------------+---------------+-----------+------------------------------------------+
| us-east-1a | db.t3.medium | devops-lab-writer-1 | available | devops-lab-writer-1.abc123...      |
| us-east-1b | db.t3.medium | devops-lab-reader-1 | available | devops-lab-reader-1.abc123...      |
+----------+-----------------+---------------+-----------+------------------------------------------+
```

Notice the instances are in different AZs (e.g., us-east-1a and us-east-1b). Aurora automatically placed them in separate AZs for high availability.

### Step 4 - Get All Four Endpoints in One View

**In your terminal** (local machine):

```bash
echo "=== Cluster Endpoints ==="
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint}" \
  --output table
```

```bash
echo "=== Instance Endpoints ==="
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address}" \
  --output table
```

Save all four endpoints. You will use them in Build 04 (Connect and Verify).

---

## Part F - Quick Connection Test

Let's verify you can connect.

**In your terminal** (local machine):

```bash
psql -h $WRITER_ENDPOINT -U labadmin -d labdb -p 5432
```

Type your password when prompted.

**In psql** (connected to writer endpoint):

```sql
SELECT version();
```

Expected output (yours will differ):
```
                                                  version
-----------------------------------------------------------------------------------------------------------
 PostgreSQL 16.6 on aarch64-unknown-linux-gnu, compiled by aarch64-unknown-linux-gnu-gcc (GCC) 9.5.0, ...
(1 row)
```

```sql
SELECT pg_is_in_recovery();
```

Expected output:
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

`f` (false) confirms this is the writer. Exit psql:

```sql
\q
```

---

## CLI Command Reference

Here is every command from this guide in order, for quick reference:

```
# 1. Create the cluster
aws rds create-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username labadmin \
  --master-user-password "$MASTER_PASSWORD" \
  --db-subnet-group-name devops-lab-subnet-group \
  --vpc-security-group-ids "$SG_ID" \
  --database-name labdb \
  --backup-retention-period 1 \
  --no-deletion-protection

# 2. Create the writer instance
aws rds create-db-instance \
  --db-instance-identifier devops-lab-writer-1 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible

# 3. Create the reader instance
aws rds create-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible

# 4. Wait for everything
aws rds wait db-cluster-available --db-cluster-identifier devops-lab-cluster
aws rds wait db-instance-available --db-instance-identifier devops-lab-writer-1
aws rds wait db-instance-available --db-instance-identifier devops-lab-reader-1
```

---

## Summary

| What You Did | CLI Command |
|-------------|-------------|
| Created cluster (storage + config) | `aws rds create-db-cluster` |
| Created writer instance | `aws rds create-db-instance` (first instance = writer) |
| Created reader instance | `aws rds create-db-instance` (subsequent = reader) |
| Waited for availability | `aws rds wait db-cluster-available` + `db-instance-available` |
| Verified cluster members | `aws rds describe-db-clusters --query DBClusterMembers` |
| Verified instance AZs | `aws rds describe-db-instances --query AvailabilityZone` |
| Connected and tested | `psql` + `pg_is_in_recovery()` |

**Next:** [Build 03 - Configure Parameter Groups](03-configure-parameter-groups.md).
