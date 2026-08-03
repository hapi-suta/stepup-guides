# AWS RDS & Aurora PostgreSQL - Tier 0: Foundations
**SUTA Labs | [COMPANY] | [TEAM NAME]**

---

## Table of Contents

1. [Managed vs Self-Managed Databases](#1-managed-vs-self-managed-databases)
2. [RDS for PostgreSQL vs Aurora PostgreSQL](#2-rds-for-postgresql-vs-aurora-postgresql)
3. [AWS Account, IAM, Regions, and AZs](#3-aws-account-iam-regions-and-azs)
4. [VPC Networking for Databases](#4-vpc-networking-for-databases)
5. [PostgreSQL Refresher](#5-postgresql-refresher)

---

## 1. Managed vs Self-Managed Databases

### What "Managed" Means

When you run PostgreSQL yourself on a server (EC2, bare metal, VPS), you own everything:
installation, configuration, patching, backups, failover, monitoring, storage expansion. Every
single layer is your responsibility.

A **managed database service** like RDS shifts most of that operational work to AWS. You hand AWS
the heavy lifting and focus on the database itself - schema design, queries, access control,
performance tuning.

### The Shared Responsibility Model

```
+------------------------------------------------------------------+
|                  SELF-MANAGED (EC2 + PostgreSQL)                 |
+------------------------------------------------------------------+
| YOU own ALL of this:                                             |
|   OS patches     PostgreSQL upgrades    Backups                  |
|   HA/Failover    Storage expansion      Monitoring               |
|   Replication    Parameter tuning       Connection pooling        |
+------------------------------------------------------------------+

+------------------------------------------------------------------+
|                  MANAGED (AWS RDS / Aurora)                      |
+------------------------------------------------------------------+
|  AWS MANAGES:                  YOU MANAGE:                       |
|  +--------------------------+  +------------------------------+  |
|  | Hardware & OS patches    |  | Database schema & objects    |  |
|  | PostgreSQL engine patch  |  | Users and roles              |  |
|  | Automated backups        |  | Query performance            |  |
|  | Multi-AZ failover        |  | Parameter groups (tuning)    |  |
|  | Storage auto-scaling     |  | Application connection logic |  |
|  | Encryption at rest       |  | Security groups (network)    |  |
|  | Read replica replication |  | Backup retention policy      |  |
|  +--------------------------+  +------------------------------+  |
+------------------------------------------------------------------+
```

### Why Teams Choose Managed Services

| Situation | Self-Managed | Managed (RDS/Aurora) |
|-----------|-------------|----------------------|
| DBA team size | Large team, deep ops experience | Small team or no DBA |
| Patching overhead | You schedule and execute | AWS handles it |
| Failover setup | Manual replication + keepalived | Click a checkbox |
| Backup strategy | Write your own scripts | Built in, point-in-time |
| Cost model | Pay for EC2 + your time | Pay for RDS instance |
| Control over internals | Full access | Limited (no OS access) |
| Compliance requirements | You prove it | AWS has certs (SOC2, PCI) |

### Why This Matters

At [COMPANY], if your team is spending weekends patching PostgreSQL servers or debugging
replication lag instead of building features, managed services exist to fix that. The tradeoff is
giving up OS-level access and paying a premium over raw EC2. For most product teams, that trade
is worth it.

---

## 2. RDS for PostgreSQL vs Aurora PostgreSQL

### The Core Difference

Both run PostgreSQL and accept standard PostgreSQL connections. The difference is the storage
layer underneath.

```
RDS for PostgreSQL                    Aurora PostgreSQL
+---------------------+               +------------------------+
|   PostgreSQL 16     |               |   PostgreSQL 16        |
|   (community)       |               |   (Aurora-compatible)  |
+---------------------+               +------------------------+
|   Single EBS Volume |               |   Aurora Storage Layer |
|   (one AZ)          |               |   (distributed, 6-way  |
|                     |               |    replicated, 3 AZs)  |
|   Multi-AZ = second |               |                        |
|   standby on        |               |   Up to 15 read        |
|   another EBS vol   |               |   replicas, lag <10ms  |
+---------------------+               +------------------------+
|   Storage: EBS gp3  |               |   Storage: auto-grows  |
|   up to 64 TB,      |               |   10 GB to 128 TB,     |
|   you set size      |               |   no pre-provisioning  |
+---------------------+               +------------------------+
```

### Comparison Table

| Feature | RDS for PostgreSQL | Aurora PostgreSQL |
|---------|--------------------|-------------------|
| Engine | Community PostgreSQL | Aurora-compatible PostgreSQL |
| Max storage | 64 TB | 128 TB (auto-grows) |
| Read replicas | Up to 5, replication lag varies | Up to 15, lag typically <10ms |
| Multi-AZ failover | ~60-120 seconds | ~30 seconds (usually faster) |
| Replication method | Physical (streaming) | Shared distributed storage |
| Point-in-time restore | Yes | Yes |
| Cost (ballpark) | Lower | ~20% higher than RDS |
| PostgreSQL wire protocol | Standard psql, drivers | Identical - same clients work |
| pg_dump / pg_restore | Yes | Yes |
| Extensions | Most community extensions | Most, but some blocked |
| Serverless option | No | Aurora Serverless v2 |
| Best for | Familiar PostgreSQL, cost-sensitive, smaller workloads | High throughput, read-heavy, HA-critical apps |

### When to Pick Each

**Pick RDS for PostgreSQL when:**
- Your workload is under 1,000 connections and moderate write load
- You want the closest thing to community PostgreSQL
- Cost is the primary constraint
- You need a specific PostgreSQL extension that Aurora does not support

**Pick Aurora PostgreSQL when:**
- You need fast failover (under 30 seconds matters to your SLA)
- Read-heavy workload that benefits from 15 low-lag replicas
- Storage growth is unpredictable (Aurora auto-scales, no capacity planning)
- You want Aurora Serverless v2 for variable or bursty workloads

### Why This Matters

Both use the same PostgreSQL wire protocol. Your application code, your psql commands, your
pg_dump scripts - they all work unchanged. The choice is about availability, scale, and cost.
For [ENV] production at [COMPANY], the right answer depends on RTO requirements and expected
database size growth.

---

## 3. AWS Account, IAM, Regions, and AZs

### AWS Account Structure

An AWS account is a billing and security boundary. Everything you create - RDS instances, VPCs,
EC2 servers - lives inside one account. [COMPANY] may use multiple accounts (one per environment)
connected by AWS Organizations.

```
AWS Organization ([COMPANY])
+----------------------------------------------+
|  Management Account (billing only)           |
|  +------------------+  +------------------+  |
|  | dev account      |  | prod account     |  |
|  | us-east-1        |  | us-east-1        |  |
|  | RDS: dev-pg-01   |  | RDS: prod-pg-01  |  |
|  +------------------+  +------------------+  |
+----------------------------------------------+
```

### IAM - Identity and Access Management

IAM controls who (or what) can do what in your AWS account.

| Concept | What It Is | Example |
|---------|-----------|---------|
| IAM User | A person with a username and password | `john.doe` DBA user |
| IAM Role | An identity assumed by a service or app | EC2 role that can call RDS |
| IAM Policy | A JSON document listing allowed/denied actions | `AllowRDSDescribe` policy |
| IAM Group | A collection of users sharing policies | `dba-team` group |
| Root User | The original account email - has unlimited power | Never use for daily work |

**Example policy - read-only RDS access:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

**Key rule:** Never use root. Create an IAM user or role with only the permissions needed.

### Regions and Availability Zones

```
AWS Region: [REGION] (e.g., us-east-1 "N. Virginia")
+------------------------------------------------------------+
|                                                            |
|  AZ: us-east-1a          AZ: us-east-1b                  |
|  +--------------------+  +--------------------+           |
|  | Physical datacenter|  | Physical datacenter|           |
|  | (separate power,   |  | (separate power,   |           |
|  | networking, flood  |  | networking, flood  |           |
|  | zone)              |  | zone)              |           |
|  |                    |  |                    |           |
|  | RDS Primary        |  | RDS Standby        |           |
|  | Subnet: 10.0.1.0   |  | Subnet: 10.0.2.0   |           |
|  +--------------------+  +--------------------+           |
|                                                            |
|  AZ: us-east-1c                                           |
|  +--------------------+                                   |
|  | Physical datacenter|                                   |
|  | RDS Read Replica   |                                   |
|  | or Aurora replica  |                                   |
|  +--------------------+                                   |
+------------------------------------------------------------+
```

**Region** - A geographic cluster of datacenters (us-east-1, eu-west-1, ap-southeast-1).
Each region is completely independent. Data does not leave a region unless you explicitly move it.

**Availability Zone (AZ)** - One or more physical datacenters within a region, with independent
power, cooling, and networking. AZs in the same region have low-latency private fiber between
them. Spread your database across AZs to survive a datacenter failure.

### How to Pick a Region for Database Work

1. **Latency** - Put the database in the same region as your application servers.
2. **Data residency** - Some regulations require data to stay in a specific country (GDPR for EU).
3. **Service availability** - Not all AWS services are in every region.
4. **Cost** - Prices vary by region. us-east-1 is typically cheapest.

For [COMPANY] [ENV], use `[REGION]` unless compliance requires otherwise.

### Why This Matters

When you create an RDS instance, you choose a region and a set of AZs. Getting this wrong means
higher latency for your application or a compliance violation. Get it right once at setup time.

---

## 4. VPC Networking for Databases

### The Core Concept

A **VPC (Virtual Private Cloud)** is your private network inside AWS. Think of it as your own
isolated section of the AWS datacenter where you control IP ranges, routing, and firewalls.

Databases should **never** be placed in a public subnet. They go in a private subnet and are only
reachable from inside the VPC.

### VPC Anatomy

```
VPC: 10.0.0.0/16  ([COMPANY]-[ENV]-vpc)
+----------------------------------------------------------------+
|                                                                |
|  Public Subnet: 10.0.1.0/24 (us-east-1a)                     |
|  Public Subnet: 10.0.2.0/24 (us-east-1b)                     |
|  +----------------------------------------------------------+  |
|  |  EC2 Bastion Host (has public IP, reachable from internet)|  |
|  |  EC2 App Server  (has public IP or load balancer in front)|  |
|  +----------------------------------------------------------+  |
|        |                                                       |
|        | private traffic (stays inside VPC)                   |
|        v                                                       |
|  Private Subnet: 10.0.3.0/24 (us-east-1a)                    |
|  Private Subnet: 10.0.4.0/24 (us-east-1b)                    |
|  +----------------------------------------------------------+  |
|  |  RDS Primary    (port 5432, NO public IP)                |  |
|  |  RDS Standby    (port 5432, NO public IP)                |  |
|  +----------------------------------------------------------+  |
|                                                                |
+-------------------------------|--------------------------------+
                                |
                    Internet Gateway (IGW)
                                |
                          The Internet
```

### Key Networking Components

| Component | What It Does | For Databases |
|-----------|-------------|---------------|
| VPC | Your private network boundary | Container for everything |
| Subnet | A slice of VPC IP space, tied to one AZ | Put RDS in private subnets |
| Route Table | Rules for where traffic goes | Private subnets route locally only |
| Internet Gateway | Connects VPC to the public internet | Public subnets use this |
| Security Group | Stateful firewall (allow rules only) | Restrict port 5432 to app servers |
| DB Subnet Group | A named set of subnets for RDS | Required by RDS at creation |

### Security Group Rules for RDS

RDS uses port **5432** for PostgreSQL. Your security group should only allow inbound 5432 from
your application servers or bastion host - not from 0.0.0.0/0 (the entire internet).

```
Security Group: [ENV]-rds-sg
Inbound Rules:
  Type        Port   Source
  PostgreSQL  5432   sg-xxxxxxxx (app server security group)
  PostgreSQL  5432   10.0.1.10/32 (bastion host IP, for DBA access)

Outbound Rules:
  All traffic  All   0.0.0.0/0  (default, RDS needs to reach AWS services)
```

### DB Subnet Group

Before creating an RDS instance, you must create a **DB Subnet Group** - a named collection of
at least two private subnets in different AZs. RDS uses this to know where to place the primary
and standby instances.

```bash
# AWS CLI example - create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name [ENV]-db-subnet-group \
  --db-subnet-group-description "[ENV] private subnets for RDS" \
  --subnet-ids subnet-aaa111 subnet-bbb222 \
  --region [REGION]
```

### Why This Matters

A misconfigured VPC is the most common reason new RDS instances are unreachable. The database
must be in a private subnet, the security group must allow port 5432 from your source, and your
application must be in the same VPC (or connected via VPC peering). Get this right before
creating the RDS instance.

---

## 5. PostgreSQL Refresher

This section covers the PostgreSQL concepts you need before connecting to RDS or Aurora. If you
have worked with PostgreSQL before, use this as a quick review.

### Object Hierarchy

```
PostgreSQL Server (one RDS instance)
+----------------------------------------------+
|  Cluster (the entire RDS instance)           |
|  +----------------------------------------+  |
|  |  Database: app_db                      |  |
|  |  +----------------------------------+  |  |
|  |  |  Schema: public                  |  |  |
|  |  |  +------------------------------+|  |  |
|  |  |  | Table: users                 ||  |  |
|  |  |  | Table: orders                ||  |  |
|  |  |  | View: active_users           ||  |  |
|  |  |  +------------------------------+|  |  |
|  |  |  Schema: reporting               |  |  |
|  |  |  +------------------------------+|  |  |
|  |  |  | Table: daily_summary         ||  |  |
|  |  |  +------------------------------+|  |  |
|  |  +----------------------------------+  |  |
|  |  Database: analytics_db               |  |
|  +----------------------------------------+  |
+----------------------------------------------+
```

- **Cluster** - The PostgreSQL server process. One RDS instance = one cluster.
- **Database** - A named logical container. Connections target a specific database.
- **Schema** - A namespace inside a database. `public` is the default schema.
- **Table, View, Function** - Objects that live inside a schema.

### Roles (Users)

PostgreSQL uses "roles" for both users and groups. A role with LOGIN permission is a user.

```sql
-- Create a login role (a user)
CREATE ROLE app_user WITH LOGIN PASSWORD 'strongpassword';

-- Create a role without login (a group)
CREATE ROLE readonly_group;

-- Grant group to user
GRANT readonly_group TO app_user;

-- Grant table privileges
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_group;

-- Check existing roles
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles ORDER BY rolname;
```

**RDS-specific:** You do not get the `postgres` superuser on RDS. The master user you create
has elevated privileges but is not a true superuser. Some superuser-only operations are
unavailable or handled through RDS parameter groups.

### Basic SQL Reference

```sql
-- Create a table
CREATE TABLE users (
    id          SERIAL PRIMARY KEY,
    email       TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Insert a row
INSERT INTO users (email) VALUES ('student@[COMPANY].com');

-- Query
SELECT id, email, created_at
FROM users
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;

-- Update
UPDATE users SET email = 'new@[COMPANY].com' WHERE id = 1;

-- Delete
DELETE FROM users WHERE id = 1;

-- Check table size
SELECT pg_size_pretty(pg_total_relation_size('users'));
```

### Connecting with psql

**Connection string format:**
```
postgresql://[user]:[password]@[host]:[port]/[database]
```

**psql command reference:**

```bash
# Connect using flags
psql -h [RDS-ENDPOINT] -U [MASTER-USER] -d [DATABASE] -p 5432

# Connect using a connection string
psql "postgresql://[MASTER-USER]:[PASSWORD]@[RDS-ENDPOINT]:5432/[DATABASE]"

# Connect with SSL required (always use for RDS)
psql "postgresql://[MASTER-USER]:[PASSWORD]@[RDS-ENDPOINT]:5432/[DATABASE]?sslmode=require"

# Example for [ENV] environment
psql -h [RDS-ENDPOINT].rds.amazonaws.com \
     -U postgres \
     -d app_db \
     -p 5432
```

**psql meta-commands (once connected):**

| Command | What It Does |
|---------|-------------|
| `\l` | List all databases |
| `\c dbname` | Connect to a database |
| `\dn` | List schemas |
| `\dt` | List tables in current schema |
| `\dt schema.*` | List tables in a specific schema |
| `\d tablename` | Describe a table (columns, types, indexes) |
| `\du` | List roles |
| `\timing` | Toggle query execution time display |
| `\x` | Toggle expanded output (useful for wide rows) |
| `\q` | Quit psql |

**Check your connection:**
```sql
-- Who am I, where am I?
SELECT current_user, current_database(), version();

-- What is the server time?
SELECT NOW();

-- List active connections
SELECT pid, usename, application_name, client_addr, state
FROM pg_stat_activity
WHERE datname = current_database();
```

Expected output (yours will differ):
```
 current_user | current_database |                    version
--------------+------------------+-----------------------------------------------
 postgres     | app_db           | PostgreSQL 16.2 on x86_64-pc-linux-gnu ...
(1 row)
```

### SSL on RDS

RDS enforces SSL by default. Always include `sslmode=require` (or `sslmode=verify-full` with the
RDS CA certificate for maximum security). Without SSL, RDS may reject the connection depending
on the parameter group setting.

```bash
# Download the RDS CA certificate bundle
curl -o /etc/ssl/certs/rds-ca.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Connect with full certificate verification
psql "postgresql://[MASTER-USER]:[PASSWORD]@[RDS-ENDPOINT]:5432/[DATABASE]?sslmode=verify-full&sslrootcert=/etc/ssl/certs/rds-ca.pem"
```

### Why This Matters

RDS and Aurora are PostgreSQL. Every command in this section works exactly the same on RDS as it
does on a self-managed server. The endpoint changes, the port stays 5432, SSL is required, and
the master user replaces the superuser. That is the only difference from a client perspective.

---

## Quick Reference Card

```
RDS Endpoint format:
  [instance-id].[random].[region].rds.amazonaws.com

Aurora Cluster Endpoint (writes):
  [cluster-id].cluster-[random].[region].rds.amazonaws.com

Aurora Reader Endpoint (reads, load-balanced):
  [cluster-id].cluster-ro-[random].[region].rds.amazonaws.com

Default PostgreSQL port:  5432
SSL:                      Required (sslmode=require minimum)
Master user:              Not a true superuser - elevated but limited
OS access:                None (managed service)
Logs:                     CloudWatch Logs or RDS console
Backups:                  Automated (1-35 day retention) + manual snapshots
```

---

*SUTA Labs - [TEAM NAME] - [COMPANY] - Last reviewed: [DATE]*
