# BUILD 01 - Creating a PostgreSQL RDS Instance

## What You Will Build

By the end of this guide you will have a running PostgreSQL RDS instance in your own AWS account, connected and verified with psql. You will understand instance classes, storage types, networking, and parameter groups.

---

## Prerequisites

- AWS CLI v2 installed and configured (`aws configure`)
- A VPC with at least two subnets in different Availability Zones
- psql client installed locally
- Your AWS credentials loaded in your terminal

Verify your CLI is working:

```bash
aws sts get-caller-identity
```

This prints your AWS account ID and IAM user. Confirms your credentials are valid.

Expected output (yours will differ):

```
{
    "UserId": "AIDAEXAMPLEID",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/student"
}
```

---

## Step 1 - Understand Instance Classes

RDS instance classes determine CPU, memory, and network capacity. The naming follows this pattern:

```
db.<family>.<size>
```

Common families for PostgreSQL:

| Class | vCPUs | RAM | Use Case |
|-------|-------|-----|----------|
| db.t3.micro | 2 | 1 GB | Dev/test, free tier |
| db.t3.medium | 2 | 4 GB | Small workloads |
| db.r6g.large | 2 | 16 GB | Memory-intensive production |
| db.r6g.xlarge | 4 | 32 GB | Medium production |
| db.r6g.2xlarge | 8 | 64 GB | Large production |

The "t" family is burstable - good for variable workloads. The "r" family is memory-optimized - better for steady production databases.

List available instance classes for PostgreSQL 15 in your region:

```bash
aws rds describe-orderable-db-instance-options \
    --engine postgres \
    --engine-version 15.4 \
    --query "OrderableDBInstanceOptions[].DBInstanceClass" \
    --output text | tr '\t' '\n' | sort -u | head -20
```

The `--query` flag uses JMESPath to extract just the class names. `tr` converts tabs to newlines so each class appears on its own line. `sort -u` removes duplicates. `head -20` limits to 20 results.

Expected output (yours will differ):

```
db.m5.12xlarge
db.m5.16xlarge
db.m5.24xlarge
db.m5.2xlarge
db.m5.4xlarge
db.m5.large
db.m5.xlarge
db.r5.12xlarge
...
```

---

## Step 2 - Understand Storage Types

RDS offers three storage types:

| Type | IOPS | Throughput | Cost | Use Case |
|------|------|------------|------|----------|
| gp3 | 3,000 baseline (scale to 16,000) | 125 MB/s baseline | Lowest | Most workloads |
| io2 | Provisioned up to 256,000 | Provisioned | Highest | Latency-sensitive |
| magnetic | Variable | Low | Legacy | Do not use |

**gp3** is the default and recommended choice. You get 3,000 IOPS and 125 MB/s included, and can provision more independently. With gp2 (older), IOPS scaled with size - gp3 decouples them.

---

## Step 3 - Create a DB Subnet Group

RDS requires a subnet group - a collection of subnets across at least two AZs. This is where your instance will be placed.

First, find your VPC ID:

```bash
aws ec2 describe-vpcs \
    --query "Vpcs[0].VpcId" \
    --output text
```

This returns the first VPC in your account. If you have multiple VPCs, pick the correct one.

Expected output (yours will differ):

```
vpc-0a1b2c3d4e5f6g7h8
```

Store it in a variable:

```bash
VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)
```

Now list subnets in that VPC:

```bash
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[*].[SubnetId,AvailabilityZone]" \
    --output table
```

The `--filters` flag narrows results to your VPC. The `--query` extracts subnet ID and AZ. `--output table` formats as a readable table.

Expected output (yours will differ):

```
-----------------------------------------
|           DescribeSubnets             |
+---------------------------+-----------+
|  subnet-0abc123def456789a | us-east-1a|
|  subnet-0def456abc789012b | us-east-1b|
+---------------------------+-----------+
```

Pick two subnets from different AZs and create the subnet group:

```bash
aws rds create-db-subnet-group \
    --db-subnet-group-name suta-pg-subnet-group \
    --db-subnet-group-description "Subnet group for SUTA PostgreSQL labs" \
    --subnet-ids "subnet-AAAA" "subnet-BBBB"
```

Replace `subnet-AAAA` and `subnet-BBBB` with your actual subnet IDs from the previous step. The `--db-subnet-group-name` is how you reference this group later.

Expected output (yours will differ):

```json
{
    "DBSubnetGroup": {
        "DBSubnetGroupName": "suta-pg-subnet-group",
        "DBSubnetGroupDescription": "Subnet group for SUTA PostgreSQL labs",
        "VpcId": "vpc-0a1b2c3d4e5f6g7h8",
        "SubnetGroupStatus": "Complete",
        ...
    }
}
```

---

## Step 4 - Create a Security Group

The security group controls which IPs can connect to your RDS instance.

```bash
aws ec2 create-security-group \
    --group-name suta-rds-sg \
    --description "Security group for SUTA RDS PostgreSQL" \
    --vpc-id "${VPC_ID}"
```

This creates a security group in your VPC. By default it allows no inbound traffic.

Expected output (yours will differ):

```json
{
    "GroupId": "sg-0123456789abcdef0"
}
```

Save the security group ID:

```bash
SG_ID=$(aws ec2 create-security-group --group-name suta-rds-sg --description "Security group for SUTA RDS PostgreSQL" --vpc-id "${VPC_ID}" --query "GroupId" --output text)
```

Now add an inbound rule for PostgreSQL (port 5432) from your IP:

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)
```

This fetches your public IP address from an AWS service.

```bash
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 5432 \
    --cidr "${MY_IP}/32"
```

The `--cidr` flag uses /32 to allow only your exact IP. The `--port 5432` is PostgreSQL's default port. `--protocol tcp` specifies TCP traffic only.

Expected output (yours will differ):

```json
{
    "Return": true,
    "SecurityGroupRules": [
        {
            "SecurityGroupRuleId": "sgr-0abc123def456789",
            "GroupId": "sg-0123456789abcdef0",
            "IpProtocol": "tcp",
            "FromPort": 5432,
            "ToPort": 5432,
            "CidrIpv4": "203.0.113.50/32"
        }
    ]
}
```

---

## Step 5 - Create a Custom Parameter Group

Parameter groups hold PostgreSQL configuration (like shared_buffers, work_mem). Always create a custom one - you cannot modify the default.

```bash
aws rds create-db-parameter-group \
    --db-parameter-group-name suta-pg15-params \
    --db-parameter-group-family postgres15 \
    --description "Custom params for SUTA PostgreSQL 15 labs"
```

The `--db-parameter-group-family` must match your engine version. For PostgreSQL 15.x, use `postgres15`.

Expected output (yours will differ):

```json
{
    "DBParameterGroup": {
        "DBParameterGroupName": "suta-pg15-params",
        "DBParameterGroupFamily": "postgres15",
        "Description": "Custom params for SUTA PostgreSQL 15 labs"
    }
}
```

Set a few important parameters:

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name suta-pg15-params \
    --parameters \
        "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
        "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate" \
        "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

The `ApplyMethod` is important: `immediate` means the change takes effect now. `pending-reboot` means the instance must be rebooted first. `shared_preload_libraries` always requires a reboot. `log_statement=ddl` logs all DDL commands. `log_min_duration_statement=1000` logs queries taking over 1 second (in milliseconds).

---

## Step 6 - Create the RDS Instance

Now create the PostgreSQL instance:

```bash
aws rds create-db-instance \
    --db-instance-identifier suta-pg-lab \
    --db-instance-class db.t3.medium \
    --engine postgres \
    --engine-version 15.4 \
    --master-username sutaadmin \
    --master-user-password 'ChangeMe-2024!' \
    --allocated-storage 50 \
    --storage-type gp3 \
    --db-subnet-group-name suta-pg-subnet-group \
    --vpc-security-group-ids "${SG_ID}" \
    --db-parameter-group-name suta-pg15-params \
    --backup-retention-period 7 \
    --preferred-backup-window "03:00-04:00" \
    --preferred-maintenance-window "Sun:05:00-Sun:06:00" \
    --no-publicly-accessible \
    --storage-encrypted \
    --copy-tags-to-snapshot \
    --tags Key=Environment,Value=lab Key=Project,Value=suta
```

Flag breakdown:
- `--db-instance-identifier` - unique name for this instance within your account
- `--db-instance-class db.t3.medium` - burstable instance with 2 vCPUs and 4 GB RAM
- `--engine postgres` - PostgreSQL engine (not aurora-postgresql)
- `--engine-version 15.4` - specific PostgreSQL version
- `--master-username` - the superuser name (cannot be "postgres" on RDS)
- `--master-user-password` - must meet complexity requirements (8+ chars, mixed case, numbers, symbols)
- `--allocated-storage 50` - 50 GB of gp3 storage
- `--storage-type gp3` - general purpose SSD with baseline 3,000 IOPS
- `--db-subnet-group-name` - references the subnet group from Step 3
- `--vpc-security-group-ids` - references the security group from Step 4
- `--db-parameter-group-name` - custom parameter group from Step 5
- `--backup-retention-period 7` - keep automated backups for 7 days
- `--preferred-backup-window` - UTC time window for daily automated backups
- `--preferred-maintenance-window` - UTC time window for patches and minor updates
- `--no-publicly-accessible` - instance gets a private IP only (best practice)
- `--storage-encrypted` - encrypts storage at rest using AWS KMS
- `--copy-tags-to-snapshot` - copies instance tags to any snapshots
- `--tags` - metadata tags for organization and billing

The instance takes 5-10 minutes to create.

---

## Step 7 - Wait for the Instance to Become Available

Monitor the creation status:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text
```

This returns the current status. You want to see `available`.

Expected output during creation:

```
creating
```

You can wait for it automatically:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

The `wait` subcommand polls every 30 seconds until the instance reaches the `available` state. It times out after 30 minutes.

---

## Step 8 - Get the Connection Endpoint

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].Endpoint.[Address,Port]" \
    --output text
```

This extracts the hostname and port of your RDS instance.

Expected output (yours will differ):

```
suta-pg-lab.c9abcdef12gh.us-east-1.rds.amazonaws.com	5432
```

Save the endpoint:

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

---

## Step 9 - Connect with psql

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

The `-h` flag specifies the RDS hostname. `-U` is the master username you set during creation. `-d postgres` connects to the default database. You will be prompted for the password.

Expected output (yours will differ):

```
Password for user sutaadmin:
psql (15.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Notice the `SSL connection` line - RDS uses SSL by default.

Verify the PostgreSQL version:

```sql
SELECT version();
```

Expected output (yours will differ):

```
                                                   version
--------------------------------------------------------------------------------------------------------------
 PostgreSQL 15.4 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 7.3.1 20180712 (Red Hat 7.3.1-6), 64-bit
(1 row)
```

Check that your custom parameter group is applied:

```sql
SHOW shared_preload_libraries;
```

Expected output:

```
 shared_preload_libraries
--------------------------
 pg_stat_statements
(1 row)
```

If this shows an empty value, the instance needs a reboot (Step 10).

Exit psql:

```sql
\q
```

---

## Step 10 - Reboot to Apply Pending Parameters

If `shared_preload_libraries` was empty, reboot:

```bash
aws rds reboot-db-instance \
    --db-instance-identifier suta-pg-lab
```

This initiates a graceful reboot. The instance will be unavailable for 1-3 minutes.

Wait for it to come back:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

---

## Step 11 - Enable Multi-AZ (Optional)

Multi-AZ creates a synchronous standby in a different Availability Zone. Failover is automatic if the primary fails.

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --multi-az \
    --apply-immediately
```

The `--multi-az` flag enables Multi-AZ deployment. `--apply-immediately` applies the change now instead of waiting for the next maintenance window. This modification takes 10-20 minutes.

Check Multi-AZ status:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].[MultiAZ,AvailabilityZone,SecondaryAvailabilityZone]" \
    --output table
```

Expected output (yours will differ):

```
-------------------------------------------
|          DescribeDBInstances            |
+-------+-------------+------------------+
|  True |  us-east-1a |  us-east-1b      |
+-------+-------------+------------------+
```

---

## Step 12 - Verify Your Setup

Run this full check:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,Version:EngineVersion,Class:DBInstanceClass,Storage:AllocatedStorage,MultiAZ:MultiAZ,Encrypted:StorageEncrypted,ParamGroup:DBParameterGroups[0].DBParameterGroupName}" \
    --output table
```

Expected output (yours will differ):

```
-------------------------------------------------------------
|                   DescribeDBInstances                     |
+-----------+-----------------------------------------------+
| Class     | db.t3.medium                                  |
| Encrypted | True                                          |
| Engine    | postgres                                      |
| MultiAZ   | True                                          |
| ParamGroup| suta-pg15-params                              |
| Status    | available                                     |
| Storage   | 50                                            |
| Version   | 15.4                                          |
+-----------+-----------------------------------------------+
```

---

## Summary

You created:
- A DB subnet group spanning two Availability Zones
- A security group allowing PostgreSQL traffic from your IP
- A custom parameter group with pg_stat_statements and query logging
- A PostgreSQL 15 RDS instance with encrypted gp3 storage
- Connected and verified with psql
- Optionally enabled Multi-AZ for high availability

---

## Clean Up (if needed)

To delete the instance when you are done with the lab:

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-pg-lab \
    --skip-final-snapshot \
    --delete-automated-backups
```

The `--skip-final-snapshot` flag skips creating a final snapshot before deletion. `--delete-automated-backups` removes all automated backups. Only use these flags in lab environments - in production, always take a final snapshot.

Delete the other resources:

```bash
aws rds delete-db-parameter-group \
    --db-parameter-group-name suta-pg15-params
```

```bash
aws rds delete-db-subnet-group \
    --db-subnet-group-name suta-pg-subnet-group
```

```bash
aws ec2 delete-security-group \
    --group-id "${SG_ID}"
```
