# BUILD 01: AWS RDS PostgreSQL - Managed Databases

**Module 03 - Cloud Database Services**
**Time Estimate:** 90 minutes
**Prerequisites:** AWS account with CLI configured, psql installed locally, basic PostgreSQL knowledge

---

## Step 1: Understand What a Managed Database Is

Think of it this way: you have been managing PostgreSQL for years. You handle OS patching, `pg_basebackup`, replication setup, failover scripts, WAL archiving, and storage provisioning. With a managed database like RDS, AWS handles all of that. You focus on what you are best at - schema design, query tuning, and data modeling.

**What AWS manages for you:**

| Your Responsibility (Self-Managed) | AWS Handles (RDS) |
|---|---|
| OS patching and upgrades | Automated OS patches |
| pg_basebackup / pgBackRest | Automated daily backups |
| Streaming replication setup | Multi-AZ with one checkbox |
| WAL archiving configuration | Continuous WAL archiving |
| Storage provisioning | Elastic storage scaling |
| Monitoring infrastructure | CloudWatch integration |

**What you still own:**

- Schema design and migrations
- Query performance tuning
- Application connection management
- Security (users, roles, RLS)
- Parameter tuning (via parameter groups)

---

## Step 2: RDS vs Aurora vs Self-Managed - Decision Matrix

Before you provision anything, understand the three options. This decision matters because it affects cost, control, and operational overhead.

| Factor | Self-Managed (EC2) | RDS PostgreSQL | Aurora PostgreSQL |
|---|---|---|---|
| **OS Access** | Full root | None | None |
| **Extension Control** | Any extension | Supported list only | Supported list only |
| **HA Setup** | You build it | Multi-AZ checkbox | Built-in (6-way storage) |
| **Failover Time** | Minutes (manual/repmgr) | 60-120 seconds | ~30 seconds |
| **Backup** | You configure pgBackRest | Automated + PITR | Automated + PITR + Backtrack |
| **Replication** | You configure streaming rep | Read replicas (managed) | Up to 15 read replicas |
| **Cost** | EC2 + EBS only | ~20-30% more than EC2 | ~20% more than RDS |
| **Best For** | Custom extensions, compliance | Standard workloads | High throughput, fast failover |
| **DBA Effort** | High | Low | Low |

**Rule of thumb:** If you need `pg_cron`, custom C extensions, or specific kernel tuning - go self-managed. If you want to stop doing backups at 2 AM - go RDS or Aurora.

---

## Step 3: Navigate the AWS Console (Brief Overview)

You will use Terraform and the CLI for real work. But you need to recognize what the console shows you because your developers and managers will reference it.

**On your Mac, in a browser:**

1. Go to [https://console.aws.amazon.com/rds](https://console.aws.amazon.com/rds)
2. Click **Databases** in the left sidebar - this is your `pg_stat_activity` equivalent. It shows all database instances.
3. Click **Parameter groups** - this is where `postgresql.conf` settings live.
4. Click **Subnet groups** - this defines which network subnets your database can use.
5. Click **Snapshots** - these are your `pg_basebackup` equivalents.

Do not create anything in the console. We will use the CLI in the next step.

---

## Step 4: Create an RDS PostgreSQL Instance via AWS CLI

**On your Mac, in your terminal:**

First, verify your AWS CLI is configured:

```bash
aws sts get-caller-identity
```

Expected output (yours will differ):
```
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

Create a security group that allows PostgreSQL traffic from your IP:

```bash
# Get your current public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)

# Get the default VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)

# Create a security group for RDS
SG_ID=$(aws ec2 create-security-group \
  --group-name rds-postgres-lab \
  --description "Allow PostgreSQL access for lab" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text)

# Allow inbound PostgreSQL (port 5432) from your IP only
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 5432 \
  --cidr "${MY_IP}/32"

echo "Security Group: $SG_ID"
```

Expected output (yours will differ):
```
Security Group: sg-0a1b2c3d4e5f67890
```

Now create a DB subnet group. RDS requires this to know which subnets it can launch into:

```bash
# Get subnet IDs from your default VPC
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ',')

aws rds create-db-subnet-group \
  --db-subnet-group-name lab-subnet-group \
  --db-subnet-group-description "Subnet group for RDS lab" \
  --subnet-ids $(echo $SUBNET_IDS | tr ',' ' ')
```

Now create the RDS instance:

```bash
aws rds create-db-instance \
  --db-instance-identifier lab-postgres \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.4 \
  --master-username labadmin \
  --master-user-password 'ChangeMe2024!Secure' \
  --allocated-storage 20 \
  --storage-type gp3 \
  --db-subnet-group-name lab-subnet-group \
  --vpc-security-group-ids "$SG_ID" \
  --publicly-accessible \
  --backup-retention-period 7 \
  --no-multi-az \
  --tags Key=Environment,Value=lab Key=Module,Value=03
```

This takes 5-10 minutes. Wait for it to become available:

```bash
aws rds wait db-instance-available --db-instance-identifier lab-postgres
echo "RDS instance is ready"
```

**What each flag means:**

- `--db-instance-class db.t3.micro` - The compute size. Think of it as choosing your server's CPU and RAM. t3.micro = 2 vCPU, 1 GB RAM - fine for a lab.
- `--engine postgres` - We want PostgreSQL, not MySQL or MariaDB.
- `--allocated-storage 20` - 20 GB of disk. Like setting up a 20 GB EBS volume for `$PGDATA`.
- `--storage-type gp3` - General purpose SSD. The "good enough for most workloads" option.
- `--publicly-accessible` - Assigns a public DNS name so you can connect from your Mac. In production, you would NOT do this.
- `--backup-retention-period 7` - Keep automated backups for 7 days. Like setting your pgBackRest retention policy.

---

## Step 5: Understand Parameter Groups

In self-managed PostgreSQL, you edit `postgresql.conf` directly with `vi`. In RDS, you use **parameter groups**. A parameter group is a named collection of settings that you attach to your instance.

**Analogy:** Parameter groups are like version-controlled `postgresql.conf` files. You create one, set values, and attach it to instances. Multiple instances can share the same parameter group.

List the default parameter group:

```bash
aws rds describe-db-parameter-groups \
  --query "DBParameterGroups[?contains(DBParameterGroupFamily, 'postgres16')]"
```

Create a custom parameter group:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name lab-postgres16-params \
  --db-parameter-group-family postgres16 \
  --description "Custom parameters for lab PostgreSQL 16"
```

Set some parameters (like editing `postgresql.conf`):

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name lab-postgres16-params \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
    "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
    "ParameterName=idle_in_transaction_session_timeout,ParameterValue=300000,ApplyMethod=immediate"
```

**Key difference from self-managed:** Some parameters require a reboot (`ApplyMethod=pending-reboot`) and some can be applied immediately (`ApplyMethod=immediate`). This is like the distinction between parameters that require a PostgreSQL restart vs a `pg_ctl reload`.

Apply the parameter group to your instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --db-parameter-group-name lab-postgres16-params \
  --apply-immediately
```

---

## Step 6: Extensions via Option Groups

In self-managed PostgreSQL, you install extensions by placing shared libraries in the `lib` directory and running `CREATE EXTENSION`. In RDS, extensions are pre-installed but you still need to `CREATE EXTENSION` for them.

List available extensions by connecting to your RDS instance with psql and running:

```sql
SELECT name, default_version, comment FROM pg_available_extensions ORDER BY name;
```

You enable extensions in the database with `CREATE EXTENSION`, not through the AWS CLI. We will do that after connecting in the next step.

**Important for DBAs:** Not all extensions are available in RDS. Notable ones that are NOT available:
- `pg_cron` (not in standard RDS - available in Aurora)
- Custom C extensions you compiled yourself
- Anything requiring filesystem access

Notable ones that ARE available:
- `pg_stat_statements`
- `PostGIS`
- `pgvector`
- `pg_trgm`
- `hstore`
- `uuid-ossp`

---

## Step 7: Connect with psql from Your Mac

Get the endpoint of your RDS instance:

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier lab-postgres \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "Endpoint: $RDS_ENDPOINT"
```

Expected output (yours will differ):
```
Endpoint: lab-postgres.c9abcdefghij.us-east-1.rds.amazonaws.com
```

Connect with psql:

```bash
psql -h "$RDS_ENDPOINT" -U labadmin -d postgres
```

Enter the password `ChangeMe2024!Secure` when prompted.

Once connected, verify you are on RDS:

```sql
SELECT version();
SHOW server_encoding;
SELECT current_database(), current_user;
```

Enable `pg_stat_statements`:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT * FROM pg_stat_statements LIMIT 5;
```

Create a test database and load some data:

```sql
CREATE DATABASE labdb;
\c labdb
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    department TEXT NOT NULL,
    salary NUMERIC(10,2),
    hire_date DATE DEFAULT CURRENT_DATE
);

INSERT INTO employees (name, department, salary)
SELECT
    'Employee_' || g,
    (ARRAY['Engineering','Marketing','Sales','Support','Finance'])[1 + (g % 5)],
    40000 + (random() * 80000)::int
FROM generate_series(1, 10000) g;

SELECT department, count(*), round(avg(salary),2) as avg_salary
FROM employees
GROUP BY department
ORDER BY avg_salary DESC;
```

Expected output (yours will differ):
```
 department  | count | avg_salary
-------------+-------+------------
 Engineering |  2000 |   79842.31
 Finance     |  2000 |   80127.45
 Marketing   |  2000 |   79563.18
 Sales       |  2000 |   80234.67
 Support     |  2000 |   79987.52
(5 rows)
```

Exit psql:

```sql
\q
```

---

## Step 8: Multi-AZ for High Availability

**Analogy:** Multi-AZ is like having a synchronous standby in a different data center that auto-promotes when the primary fails. You do not configure `primary_conninfo`, you do not set up repmgr, you do not write failover scripts. AWS does all of it.

Enable Multi-AZ on your instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --multi-az \
  --apply-immediately
```

This takes 10-15 minutes. The instance stays available during the modification.

**How Multi-AZ works:**

1. AWS creates a synchronous replica in a different Availability Zone (a separate data center in the same region)
2. Every write to the primary is synchronously replicated before being acknowledged
3. If the primary fails, AWS automatically promotes the standby - typically 60-120 seconds
4. Your application connects to the same DNS endpoint - it does not change during failover
5. You CANNOT read from the standby. It is only for HA, not for read scaling.

**Key difference from self-managed:** In self-managed PostgreSQL, your standby can serve read queries. In RDS Multi-AZ, the standby is hidden. For read scaling, you need read replicas (next step).

---

## Step 9: Read Replicas

**Analogy:** Read replicas in RDS are like streaming replication replicas that you manage with `pg_basebackup` and `primary_conninfo` - but AWS sets it all up for you.

Create a read replica:

```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier lab-postgres-replica \
  --source-db-instance-identifier lab-postgres \
  --db-instance-class db.t3.micro \
  --no-multi-az
```

Wait for it to become available:

```bash
aws rds wait db-instance-available --db-instance-identifier lab-postgres-replica
```

Get the replica endpoint and connect:

```bash
REPLICA_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier lab-postgres-replica \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

psql -h "$REPLICA_ENDPOINT" -U labadmin -d labdb -c "SELECT count(*) FROM employees;"
```

Check replication lag:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres-replica \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --query "Datapoints | sort_by(@, &Timestamp) | [-1]"
```

**Key facts about RDS read replicas:**

- Asynchronous replication (not synchronous like Multi-AZ)
- You CAN read from them (unlike Multi-AZ standby)
- They have their own endpoint
- You can promote them to a standalone instance (breaks replication)
- Up to 15 read replicas per primary (5 for non-Aurora RDS)
- Can be in a different region (cross-region read replica)

---

## Step 10: Automated Backups and PITR

**Analogy:** Automated backups in RDS are like having `pgBackRest` configured with continuous WAL archiving and scheduled full backups - but you never touch `archive_command` or write a cron job.

Check your backup settings:

```bash
aws rds describe-db-instances \
  --db-instance-identifier lab-postgres \
  --query "DBInstances[0].{BackupRetention:BackupRetentionPeriod,BackupWindow:PreferredBackupWindow,LatestRestore:LatestRestorableTime}"
```

Expected output (yours will differ):
```
{
    "BackupRetention": 7,
    "BackupWindow": "06:00-06:30",
    "LatestRestore": "2026-06-09T14:35:00+00:00"
}
```

**How it works:**

1. AWS takes a daily snapshot during your backup window
2. AWS continuously archives WAL (transaction logs) to S3
3. You can restore to any point in time within your retention period (1-35 days)
4. Restoring always creates a NEW instance - you cannot overwrite the existing one

**Backup window tip:** Set it to a low-traffic period. In self-managed PostgreSQL terms, this is when your `pg_basebackup` runs.

---

## Step 11: Manual Snapshots

Manual snapshots are like on-demand `pg_basebackup` runs. Take one before major changes.

```bash
aws rds create-db-snapshot \
  --db-instance-identifier lab-postgres \
  --db-snapshot-identifier lab-postgres-before-migration
```

Wait for the snapshot to complete:

```bash
aws rds wait db-snapshot-available --db-snapshot-identifier lab-postgres-before-migration
echo "Snapshot complete"
```

List your snapshots:

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier lab-postgres \
  --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,Size:AllocatedStorage}" \
  --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------------
|                       DescribeDBSnapshots                        |
+----------------------------------+--------+----------+-----------+
|             Created              |  ID    |  Size    |  Status   |
+----------------------------------+--------+----------+-----------+
|  2026-06-09T15:00:00.000+00:00  | lab-...|  20      | available |
+----------------------------------+--------+----------+-----------+
```

---

## Step 12: Understand the Cost Breakdown

RDS billing has four components. Understanding them prevents surprise bills.

| Component | What It Is | DBA Analogy |
|---|---|---|
| **Instance hours** | Compute time your instance runs | Like paying for your server's uptime |
| **Storage** | GB-month of allocated storage | Like paying for your EBS volumes |
| **I/O** | Read/write operations (io1/io2 only) | Like paying per `fsync` call |
| **Backup storage** | Storage for snapshots beyond free tier | Like paying for your pgBackRest repo |

**Cost estimate for this lab (us-east-1):**

- db.t3.micro: ~$0.018/hour = ~$13/month
- 20 GB gp3 storage: ~$2.30/month
- Backup storage (20 GB, within free tier): $0
- **Total: ~$15/month**

**Production example (db.r6g.xlarge, 500 GB):**

- Instance: ~$0.48/hour = ~$350/month
- Storage (500 GB gp3): ~$57.50/month
- Multi-AZ doubles the instance cost: +$350/month
- **Total: ~$757/month**

---

## Step 13: Clean Up Lab Resources

Do this AFTER you complete the USE exercises. Leaving resources running costs money.

```bash
# Delete the read replica first
aws rds delete-db-instance \
  --db-instance-identifier lab-postgres-replica \
  --skip-final-snapshot

# Wait for replica deletion
aws rds wait db-instance-deleted --db-instance-identifier lab-postgres-replica

# Delete the primary (keep a final snapshot)
aws rds delete-db-instance \
  --db-instance-identifier lab-postgres \
  --final-db-snapshot-identifier lab-postgres-final-snapshot

# Delete the manual snapshot (optional - costs pennies)
aws rds delete-db-snapshot --db-snapshot-identifier lab-postgres-before-migration

# Delete the parameter group
aws rds delete-db-parameter-group --db-parameter-group-name lab-postgres16-params

# Delete the subnet group
aws rds delete-db-subnet-group --db-subnet-group-name lab-subnet-group

# Delete the security group
aws ec2 delete-security-group --group-id "$SG_ID"
```

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| Managed databases | AWS handles OS, backups, HA - you handle schema, queries, security |
| RDS vs Aurora vs self-managed | Trade control for operational simplicity |
| Parameter groups | Version-controlled `postgresql.conf` managed through AWS |
| Extensions | Pre-installed but still need `CREATE EXTENSION` |
| Multi-AZ | Synchronous standby with automatic failover - 60-120 seconds |
| Read replicas | Asynchronous streaming replication managed by AWS |
| Automated backups | Continuous WAL archiving + daily snapshots - always creates NEW instance on restore |
| Manual snapshots | On-demand backups - take before major changes |
| Cost model | Instance hours + storage + I/O + backup storage |
