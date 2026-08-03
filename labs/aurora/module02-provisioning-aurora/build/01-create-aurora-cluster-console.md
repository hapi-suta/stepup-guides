# Build 01 - Create an Aurora Cluster (Console)
## Module 02 - Provisioning Aurora (CLI + Console)

**Estimated time:** 45 minutes
**Difficulty:** Beginner
**Cost:** ~$0.20 for this lab session (Aurora db.t3.medium is ~$0.082/hour, two instances)
**Prerequisite:** Module 01 complete (VPC, subnets, security group, and subnet group created)

---

## What You Will Do

You will create an Aurora PostgreSQL cluster with one writer and one reader using the AWS Console. By the end you will:

- Have a running Aurora cluster named `devops-lab-cluster`
- Have two instances: `devops-lab-writer-1` and `devops-lab-reader-1`
- Know all four endpoints (cluster, reader, writer instance, reader instance)

> **Cost warning:** Aurora db.t3.medium costs approximately $0.082 per hour per instance. With two instances, that is $0.164/hour or about $3.94/day. Delete the cluster when you are done with the lab to avoid charges.

---

## Before You Start

You need these resources from Module 01:

- A VPC (the default VPC is fine)
- A DB subnet group with subnets in at least 2 Availability Zones
- A security group allowing inbound TCP on port 5432 from your IP

If you do not have these, go back to Module 01 and create them first.

Also have ready:
- Your security group name or ID
- Your DB subnet group name

---

## Step 1 - Open the RDS Console

**In the AWS Console** (browser):

1. Go to https://console.aws.amazon.com
2. Make sure your region is set to **US East (N. Virginia) us-east-1** in the top-right corner.
3. In the search bar at the top, type `RDS` and click **RDS** in the results.
4. In the left sidebar, click **Databases**.
5. Click the orange **Create database** button.

---

## Step 2 - Choose Creation Method

**In the AWS Console** (RDS > Create database):

1. Under **Choose a database creation method**, select **Standard create**.

Do not use "Easy create" - it hides important options and makes assumptions you need to understand.

---

## Step 3 - Choose Engine

**In the AWS Console** (RDS > Create database):

1. Under **Engine options**, click **Amazon Aurora**.
2. Under **Edition**, select **Amazon Aurora PostgreSQL-Compatible Edition**.
3. Under **Available versions**, select the latest PostgreSQL 16.x version shown (e.g., `Aurora PostgreSQL 16.6`).

> **Why Aurora PostgreSQL?** Aurora is wire-compatible with PostgreSQL. You use the same psql client, same drivers, same SQL. The difference is under the hood - Aurora uses a distributed storage layer that gives you faster failover and replication.

---

## Step 4 - Choose a Template

**In the AWS Console** (RDS > Create database):

1. Under **Templates**, select **Production**.

We choose Production so you can see the full set of configuration options. The Dev/Test template works too but hides some settings. Do not choose "Easy create" from the previous screen, as it skips configuration entirely.

---

## Step 5 - Configure the Cluster

**In the AWS Console** (RDS > Create database > Settings):

1. Under **DB cluster identifier**, type: `devops-lab-cluster`

   This is the unique name for your Aurora cluster. It must be lowercase, can include hyphens, and must be unique in your region.

2. Under **Master username**, clear the default and type: `labadmin`

   This is the admin user Aurora creates for you. It is a member of the `rds_superuser` role.

3. Under **Credentials management**, select **Self managed**.

4. Under **Master password**, type a strong password and confirm it.

   Write this password down. You will need it to connect.

---

## Step 6 - Choose the Instance Class

**In the AWS Console** (RDS > Create database > Instance configuration):

1. Under **Cluster storage configuration**, confirm it says **Aurora Standard**. (Aurora I/O-Optimized is for write-heavy workloads and costs more.)

2. Under **DB instance class**, select **Burstable classes (includes t classes)**.

3. From the dropdown, select **db.t3.medium**.

   db.t3.medium has 2 vCPUs and 4 GB RAM. This is the smallest instance class available for Aurora clusters. Aurora does not support db.t3.micro.

---

## Step 7 - Availability and Durability

**In the AWS Console** (RDS > Create database > Availability & durability):

1. Under **Multi-AZ deployment**, select **Create an Aurora Replica or Reader node in a different AZ (recommended for scaled availability)**.

This tells Aurora to create two instances:
- A writer instance in one AZ
- A reader instance in a different AZ

If you select "Don't create an Aurora Replica", you get only a writer with no readers. We want both for this lab.

---

## Step 8 - Connectivity

**In the AWS Console** (RDS > Create database > Connectivity):

1. Under **Compute resource**, select **Don't connect to an EC2 compute resource**.

   We will connect from our local machine, not from an EC2 instance.

2. Under **Network type**, leave **IPv4** selected.

3. Under **Virtual private cloud (VPC)**, select your VPC (the default VPC is fine).

4. Under **DB subnet group**, select the subnet group you created in Module 01.

   If you see "default", that works for this lab but a custom subnet group is better practice.

5. Under **Public access**, select **Yes**.

   This allows connections from outside the VPC (like your laptop). In production, you would choose "No" and connect through a bastion host or VPN.

6. Under **VPC security group (firewall)**, select **Choose existing**.

7. Remove the default security group by clicking the X next to it.

8. Select the security group you created in Module 01 (the one that allows port 5432 from your IP).

9. Under **Availability Zone**, leave **No preference**. Aurora will choose AZs automatically.

10. Under **Database port**, confirm it shows **5432**.

---

## Step 9 - Database Authentication

**In the AWS Console** (RDS > Create database > Database authentication):

1. Select **Password authentication**.

   This is standard username/password authentication. IAM authentication and Kerberos are available but not needed for this lab.

---

## Step 10 - Additional Configuration

**In the AWS Console** (RDS > Create database):

1. Click the arrow next to **Additional configuration** to expand it.

2. Under **Initial database name**, type: `labdb`

   If you leave this blank, Aurora creates the cluster with only the default `postgres` database. We want a dedicated lab database.

3. Under **DB cluster parameter group**, leave the default: `default.aurora-postgresql16`.

   We will create a custom parameter group later in Build 03.

4. Under **DB parameter group**, leave the default: `default.aurora-postgresql16`.

5. Under **Backup**:
   - Set **Backup retention period** to **1 day**. (The default is 7 days. For a lab, 1 day is enough.)
   - Leave **Backup window** as "No preference".

6. Under **Encryption**, leave **Enable encryption** checked. AWS manages the key.

7. Under **Log exports**, check **PostgreSQL log**. This sends PostgreSQL logs to CloudWatch Logs, which makes them easier to view.

8. Under **Maintenance**, leave "Enable auto minor version upgrade" checked.

9. Under **Deletion protection**, **uncheck** this box. Deletion protection prevents accidental deletion. For a lab, we want to be able to delete easily.

---

## Step 11 - Create the Cluster

**In the AWS Console** (RDS > Create database):

1. Review your settings one more time. Key values to confirm:
   - Engine: Aurora PostgreSQL 16.x
   - Cluster identifier: `devops-lab-cluster`
   - Instance class: db.t3.medium
   - Multi-AZ: Yes (one reader)
   - Public access: Yes
   - Initial database: `labdb`

2. Click **Create database**.

3. You will see a blue banner: "Successfully created database devops-lab-cluster." Click **View credential details** to see the password one more time if you need it.

---

## Step 12 - Wait for the Cluster to Be Available

**In the AWS Console** (RDS > Databases):

You will see the cluster and its instances in the database list:

```
devops-lab-cluster              (Regional cluster)    Creating
  devops-lab-cluster-instance-1 (Writer instance)     Creating
  devops-lab-cluster-instance-2 (Reader instance)     Creating
```

> **Note:** The Console auto-generates instance names like `devops-lab-cluster-instance-1`. In Build 02 (CLI), you control the exact instance names.

Wait 10 to 15 minutes until all three items show status **Available**.

You can click the refresh button (circular arrow icon) in the top-right of the database list to check progress.

---

## Step 13 - Find All Endpoints

**In the AWS Console** (RDS > Databases):

1. Click on the cluster name **devops-lab-cluster** (not an instance - click the row that says "Regional cluster").

2. Click the **Connectivity & security** tab.

3. Under **Endpoints**, you will see:

   | Endpoint type | Endpoint name |
   |---------------|---------------|
   | Writer | `devops-lab-cluster.cluster-XXXXXX.us-east-1.rds.amazonaws.com` |
   | Reader | `devops-lab-cluster.cluster-ro-XXXXXX.us-east-1.rds.amazonaws.com` |

4. Write down both endpoints. You will use them to connect.

5. Now click on the writer instance name (e.g., `devops-lab-cluster-instance-1`).

6. Under **Connectivity & security**, find the **Endpoint** field. This is the instance endpoint for the writer.

7. Go back and click on the reader instance. Note its instance endpoint too.

You now have four endpoints:

```
Cluster (writer):   devops-lab-cluster.cluster-XXXXXX.us-east-1.rds.amazonaws.com
Reader:             devops-lab-cluster.cluster-ro-XXXXXX.us-east-1.rds.amazonaws.com
Writer instance:    devops-lab-cluster-instance-1.XXXXXX.us-east-1.rds.amazonaws.com
Reader instance:    devops-lab-cluster-instance-2.XXXXXX.us-east-1.rds.amazonaws.com
```

Save all four. You will use the cluster and reader endpoints most often.

---

## Step 14 - Quick Verification

Let's verify the cluster is working with a quick psql connection.

**In your terminal** (local machine):

```bash
psql -h YOUR_WRITER_ENDPOINT -U labadmin -d labdb -p 5432
```

Replace `YOUR_WRITER_ENDPOINT` with the cluster (writer) endpoint from Step 13.

You will be prompted for the password. Type the password you set in Step 5.

Expected output (yours will differ):
```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

labdb=>
```

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

Exit psql:

```sql
\q
```

---

## Summary

| What You Did | Result |
|-------------|--------|
| Created Aurora cluster via Console | `devops-lab-cluster` with Aurora PostgreSQL 16.x |
| Created two instances automatically | One writer, one reader in different AZs |
| Configured connectivity | Public access, custom security group, custom subnet group |
| Found all endpoints | Cluster, reader, and two instance endpoints |
| Verified connection | Connected with psql, confirmed PostgreSQL version |

---

## What is Different About the Console Approach

The Console auto-generates instance names (like `devops-lab-cluster-instance-1`). In Build 02, you will create the same type of cluster using the CLI, where you control every name and setting explicitly. The CLI approach is better for:

- Scripting and automation
- Repeatable deployments
- Documenting exactly what was created

**Next:** [Build 02 - Create Aurora Cluster (CLI)](02-create-aurora-cluster-cli.md) - the same cluster, but with full control via the command line.
