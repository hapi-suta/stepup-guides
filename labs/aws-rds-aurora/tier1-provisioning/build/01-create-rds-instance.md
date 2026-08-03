# Build 01 - Create an RDS PostgreSQL Instance
## Tier 1: Provisioning and Connectivity

**Estimated time:** 45 minutes
**Difficulty:** Beginner
**Cost:** ~$0.02 for this lab session

---

## What You Will Do

You will create a PostgreSQL database on Amazon RDS. By the end of this guide you will have:
- A running RDS PostgreSQL instance
- A security group that allows your laptop to connect
- A successful psql connection to the database

---

## Before You Start

Confirm these are ready:

1. AWS CLI is configured. Test it:

```bash
aws sts get-caller-identity
```

Expected output (yours will differ):
```
{
    "UserId": "AIDAEXAMPLEID",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/myuser"
}
```

2. You know your current public IP address. Find it:

```bash
curl -s https://checkip.amazonaws.com
```

Expected output (yours will differ):
```
203.0.113.42
```

Write this IP down. You will need it for the security group.

3. You know your default VPC ID:

```bash
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" --output text
```

Expected output (yours will differ):
```
vpc-0abc1234def56789a
```

Write this down too.

---

## Part A - Console Steps (Click-by-Click)

### Step 1 - Open RDS in the Console

1. Open your browser and go to: https://console.aws.amazon.com
2. Sign in with your IAM user.
3. In the top search bar, type `RDS` and press Enter.
4. Click on **RDS** (it says "Managed Relational Database Service").
5. You are now on the RDS Dashboard.

### Step 2 - Start Creating an Instance

1. On the left sidebar, click **Databases**.
2. Click the orange button that says **Create database**.

### Step 3 - Choose a Database Creation Method

1. Under "Choose a database creation method", select **Standard create**.

> **Concept:** Standard create shows you every option. Easy create hides most settings and picks defaults for you. Use Standard create so you learn what each setting does.

### Step 4 - Choose the Engine

1. Under "Engine options", click on **PostgreSQL**.
2. Under "Engine version", leave the default (it will be the latest stable version, such as 15.x or 16.x).

### Step 5 - Choose a Template

1. Under "Templates", click on **Free tier**.

> **Concept:** The free tier template limits you to db.t3.micro (which qualifies for AWS free tier) and single-AZ. This is fine for learning.

### Step 6 - Set the Instance Identifier

1. Under "DB instance identifier", delete the default text.
2. Type: `suta-rds-lab`

> **Concept:** The instance identifier is the name you use to find this database in the AWS Console and CLI. It must be unique within your region.

### Step 7 - Set Master Credentials

1. Under "Master username", leave it as `postgres`.
2. Under "Credentials management", select **Self managed**.
3. Under "Master password", type a strong password. Write it down.
4. Under "Confirm master password", type the same password again.

### Step 8 - Configure the Instance

1. Under "DB instance class", confirm it shows **db.t3.micro** (the free tier option).
2. Under "Storage type", confirm it shows **gp2** or change it to **gp3** if available.
3. Under "Allocated storage", set it to **20**.
4. Uncheck "Enable storage autoscaling" for this lab (keeps cost predictable).

### Step 9 - Connectivity Settings

1. Under "Compute resource", select **Don't connect to an EC2 compute resource**.
2. Under "VPC", leave the default VPC selected.
3. Under "DB Subnet group", leave it as **default**.
4. Under "Public access", click **Yes**.

> **Concept:** Public access = Yes means your laptop can connect directly. In production you would set this to No and use a VPN or bastion host.

5. Under "VPC security group (firewall)", click **Create new**.
6. Under "New VPC security group name", type: `suta-rds-lab-sg`

### Step 10 - Database Options

1. Scroll down to "Additional configuration".
2. Click the arrow to expand it.
3. Under "Initial database name", type: `labdb`

> **Concept:** If you skip this, RDS creates the instance but does not create a database inside it. You would have to create one manually after connecting.

### Step 11 - Disable Backups (for this lab only)

1. Under "Backup", uncheck **Enable automated backups**.

> **Concept:** Backups are critical in production. We disable them here only to speed up the lab and reduce cost.

### Step 12 - Create the Instance

1. Scroll to the bottom of the page.
2. Click the orange **Create database** button.
3. You will see a green banner: "Creating database suta-rds-lab".
4. Click on **View credential details** to see the password one more time.

### Step 13 - Wait for the Instance to Become Available

1. On the Databases list, you will see `suta-rds-lab` with a status of **Creating**.
2. Wait 5 to 10 minutes. Refresh the page every 2 minutes.
3. When the status changes to **Available**, proceed to the next step.

### Step 14 - Get the Endpoint

1. Click on `suta-rds-lab` to open it.
2. Scroll down to the **Connectivity & security** tab.
3. Under "Endpoint & port", copy the Endpoint address. It looks like:
   `suta-rds-lab.abc123xyz.us-east-1.rds.amazonaws.com`

Write this endpoint down.

### Step 15 - Update the Security Group

The security group AWS created allows traffic from anywhere. Tighten it:

1. On the instance page, click the **VPC security groups** link. It opens the security group in a new tab.
2. Click on the security group ID (starts with `sg-`).
3. Click the **Inbound rules** tab.
4. Click **Edit inbound rules**.
5. You will see a rule that says Type: PostgreSQL, Port: 5432, Source: 0.0.0.0/0
6. Change the Source from `0.0.0.0/0` to **My IP**. The console fills in your current IP.
7. Click **Save rules**.

---

## Part B - AWS CLI Steps (Same Result)

If you prefer the command line, here are the equivalent steps. Run these in order.

### Step 1 - Find Your Default VPC and Subnets

```bash
aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text
```

Save the output. Replace `YOUR_VPC_ID` in the commands below.

```bash
aws ec2 describe-subnets \
  --filters "Name=vpcId,Values=YOUR_VPC_ID" \
  --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone}" \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------
|            DescribeSubnets                  |
+------+--------------------------------------+
|  AZ  |          ID                          |
+------+--------------------------------------+
|  us-east-1a  |  subnet-0abc123              |
|  us-east-1b  |  subnet-0def456              |
|  us-east-1c  |  subnet-0ghi789              |
+------+--------------------------------------+
```

### Step 2 - Create a DB Subnet Group

Replace `SUBNET1`, `SUBNET2`, `SUBNET3` with the actual subnet IDs from the previous step.

```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name suta-rds-lab-subnetgroup \
  --db-subnet-group-description "Subnet group for SUTA RDS lab" \
  --subnet-ids subnet-0abc123 subnet-0def456 subnet-0ghi789
```

Expected output (yours will differ):
```json
{
    "DBSubnetGroup": {
        "DBSubnetGroupName": "suta-rds-lab-subnetgroup",
        "DBSubnetGroupDescription": "Subnet group for SUTA RDS lab",
        "VpcId": "vpc-0abc1234def56789a",
        "SubnetGroupStatus": "Complete",
        ...
    }
}
```

### Step 3 - Create a Security Group

Replace `YOUR_VPC_ID` with your actual VPC ID.

```bash
aws ec2 create-security-group \
  --group-name suta-rds-lab-sg \
  --description "Security group for SUTA RDS lab" \
  --vpc-id YOUR_VPC_ID
```

Expected output (yours will differ):
```json
{
    "GroupId": "sg-0abc123def456789a"
}
```

Save the GroupId. Replace `YOUR_SG_ID` in the next step.

### Step 4 - Add an Inbound Rule for PostgreSQL

Replace `YOUR_SG_ID` with the security group ID. Replace `YOUR_IP` with your IP address from `curl https://checkip.amazonaws.com`.

```bash
aws ec2 authorize-security-group-ingress \
  --group-id YOUR_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr YOUR_IP/32
```

The `/32` after your IP means "only this exact IP address". No output means success.

### Step 5 - Create the RDS Instance

Replace `YOUR_SG_ID` and `YOUR_PASSWORD` with your actual values.

```bash
aws rds create-db-instance \
  --db-instance-identifier suta-rds-lab \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YOUR_PASSWORD \
  --allocated-storage 20 \
  --storage-type gp3 \
  --db-name labdb \
  --vpc-security-group-ids YOUR_SG_ID \
  --db-subnet-group-name suta-rds-lab-subnetgroup \
  --publicly-accessible \
  --no-multi-az \
  --no-enable-performance-insights \
  --backup-retention-period 0
```

What each flag does:
- `--db-instance-identifier` - name for this instance
- `--db-instance-class` - the server size (db.t3.micro is free tier eligible)
- `--engine postgres` - tells RDS this is PostgreSQL (not MySQL, etc.)
- `--engine-version 16.6` - which PostgreSQL version to install
- `--master-username` - the admin username
- `--master-user-password` - the admin password
- `--allocated-storage 20` - 20 GB of disk space
- `--storage-type gp3` - use gp3 SSD storage
- `--db-name labdb` - create a database called labdb
- `--vpc-security-group-ids` - attach this security group
- `--db-subnet-group-name` - which subnets to use
- `--publicly-accessible` - allow connections from outside the VPC
- `--no-multi-az` - single AZ only (saves cost for the lab)
- `--no-enable-performance-insights` - skip Performance Insights (saves cost)
- `--backup-retention-period 0` - disable automated backups (lab only)

### Step 6 - Wait for the Instance to Become Available

This command polls the instance status every 30 seconds until it is available.

```bash
aws rds wait db-instance-available \
  --db-instance-identifier suta-rds-lab
```

This will take 5 to 10 minutes. The cursor just sits there - that is normal. It returns to the prompt when the instance is ready.

### Step 7 - Get the Endpoint

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

Expected output (yours will differ):
```
suta-rds-lab.abc123xyz.us-east-1.rds.amazonaws.com
```

---

## Part C - Connect with psql

Now that the instance is available, connect to it.

### Step 1 - Connect

Replace `YOUR_ENDPOINT` with the endpoint from above.

```bash
psql -h YOUR_ENDPOINT -U postgres -d labdb -p 5432
```

What each flag does:
- `-h` - the hostname (your RDS endpoint)
- `-U` - the username
- `-d` - the database name to connect to
- `-p` - the port number (PostgreSQL default is 5432)

You will be prompted for the password. Type it and press Enter.

Expected output (yours will differ):
```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

labdb=>
```

You are connected. The `labdb=>` prompt is the psql prompt.

### Step 2 - Verify the Connection

Run a few checks inside psql:

```sql
SELECT version();
```

Expected output (yours will differ):
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.6 on aarch64-unknown-linux-gnu, compiled by aarch64-unknown-linux-musl-gcc 12.2.1, 64-bit
(1 row)
```

```sql
SELECT current_user;
```

Expected output:
```
 current_user
--------------
 postgres
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

`f` (false) means this is a primary database, not a replica.

### Step 3 - Check Your User's Roles

```sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles
WHERE rolname = 'postgres';
```

Expected output:
```
 rolname  | rolsuper | rolcreatedb | rolcreaterole
----------+----------+-------------+---------------
 postgres | f        | t           | t
(1 row)
```

Notice `rolsuper = f`. Your master user is NOT a true superuser on RDS. It has the `rds_superuser` role instead.

### Step 4 - Create a Test Table

```sql
CREATE TABLE test_connection (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO test_connection (message) VALUES ('Hello from Tier 1!');

SELECT * FROM test_connection;
```

Expected output:
```
 id |      message       |          created_at
----+--------------------+-------------------------------
  1 | Hello from Tier 1! | 2025-01-15 14:23:10.123456+00
(1 row)
```

### Step 5 - Exit psql

```sql
\q
```

---

## Cleanup (Important - Avoid Charges)

When you are done with the lab, delete the instance to avoid ongoing charges.

### Console cleanup
1. Go to RDS > Databases.
2. Click on `suta-rds-lab`.
3. Click **Actions** > **Delete**.
4. Uncheck "Create final snapshot".
5. Check "I acknowledge...".
6. Type `delete me` in the confirmation box.
7. Click **Delete**.

### CLI cleanup

```bash
aws rds delete-db-instance \
  --db-instance-identifier suta-rds-lab \
  --skip-final-snapshot
```

Then wait for deletion and clean up the subnet group:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier suta-rds-lab

aws rds delete-db-subnet-group \
  --db-subnet-group-name suta-rds-lab-subnetgroup

aws ec2 delete-security-group \
  --group-id YOUR_SG_ID
```

---

## Summary

You created an RDS PostgreSQL instance using both the Console and CLI. Key things you did:

- Created a DB Subnet Group (required for all RDS instances)
- Created a Security Group with a PostgreSQL inbound rule locked to your IP
- Created the RDS instance with the `postgres` engine and `db.t3.micro` class
- Waited for the instance to become available
- Connected with psql and confirmed the instance type

**Next:** Build 02 explores instance classes and storage types in more depth.
