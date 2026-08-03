# Concepts: Provisioning and Connectivity
## AWS RDS and Aurora PostgreSQL - Tier 1

Read this before doing any build guide. These concepts will be referenced throughout the tier.

---

## T1.1 - Creating an RDS PostgreSQL Instance

### What is Amazon RDS?

Amazon RDS (Relational Database Service) is a managed database service. AWS handles the operating system, patching, backups, and hardware. You just manage the database itself.

> **Concept:** "Managed" means AWS does the heavy lifting. You do not SSH into the server. You cannot install software on it. You interact with it only through PostgreSQL connections.

### Three Ways to Create an RDS Instance

#### 1. AWS Console (GUI)
You click through a web interface. Best for learning. Slow for doing the same thing many times.

#### 2. AWS CLI (Command Line)
You run commands in your terminal. Fast once you know the flags. Easy to repeat and script.

#### 3. Infrastructure as Code (IaC)
Tools like Terraform or CloudFormation define your infrastructure in files. You commit those files to git, and the tool creates (or updates) your AWS resources. Best for production.

### What Happens When You Create an RDS Instance

```
You submit a CreateDBInstance request
         |
         v
AWS picks a physical host in your chosen AZ
         |
         v
AWS provisions an EBS volume for storage
         |
         v
AWS installs PostgreSQL on the host
         |
         v
AWS applies your parameter group settings
         |
         v
AWS registers the instance in DNS (your endpoint)
         |
         v
Status changes from "creating" to "available"
         |
         v
You can now connect using the endpoint
```

This whole process takes 5 to 10 minutes.

### Key Components of an RDS Instance

| Component | What It Is | Example |
|-----------|-----------|---------|
| DB Instance Identifier | Unique name for this instance in your account/region | `myapp-postgres-dev` |
| DB Instance Class | The CPU and RAM of the server | `db.t3.micro` |
| Engine Version | Which version of PostgreSQL | `16.6` |
| Master Username | The admin user AWS creates | `postgres` or `dbadmin` |
| Master Password | Password for the admin user | Set by you at creation |
| DB Name | An initial database AWS creates | `myappdb` (optional) |
| Storage | EBS volume attached to the instance | 20 GB gp3 |
| VPC | The virtual network the instance lives in | `vpc-0abc123` |
| Subnet Group | Which subnets to place the instance in | `my-rds-subnet-group` |
| Security Group | Firewall rules controlling who can connect | `sg-0abc123` |
| Parameter Group | PostgreSQL configuration settings | `default.postgres15` |

---

## T1.2 - Instance Classes and Storage Types

### Instance Class Families

AWS groups instance classes into families. Each family has a purpose.

```
db.t3.micro     <- T family (burstable)
db.t3.small
db.t3.medium
db.t3.large

db.m6g.large    <- M family (general purpose)
db.m6g.xlarge
db.m6g.2xlarge

db.r6g.large    <- R family (memory optimized)
db.r6g.xlarge
db.r6g.2xlarge
```

#### T Family - Burstable (for dev/test)

T instances have a baseline CPU level. When the database is busy, they can "burst" above baseline using CPU credits. When idle, they earn credits back.

- Good for: dev environments, small apps, low-traffic databases
- Avoid for: production workloads with sustained CPU load

```
CPU Usage
100% |    *
     |   * *
 50% |  *   *  *             <- baseline is around 20%
     | *     **
  0% +-------------------> time

     Credits earned when below baseline.
     Credits spent when above baseline.
     If credits run out, CPU is throttled.
```

#### M Family - General Purpose

M instances give you a consistent full CPU. No bursting or credit system.

- Good for: most production workloads, mixed read/write, OLTP
- More expensive than T, but predictable performance

#### R Family - Memory Optimized

R instances have more RAM per vCPU than M instances. PostgreSQL performance is heavily tied to how much of your working set fits in RAM (shared_buffers + OS cache).

- Good for: large databases, analytical queries, high-connection counts
- Most expensive, but worth it when your database is RAM-bound

### Graviton vs Intel

AWS makes its own ARM-based CPUs called Graviton. The `g` in `m6g` means Graviton.

| Feature | Intel (m6i) | Graviton (m6g) |
|---------|------------|----------------|
| Architecture | x86_64 | ARM64 |
| Performance | Baseline | Up to 35% better perf/dollar |
| Cost | 100% | ~20% cheaper |
| PostgreSQL support | Full | Full |
| Recommendation | Legacy | Prefer Graviton for new instances |

Use Graviton (`m6g`, `r6g`, `t4g`) unless you have a specific reason not to.

### Storage Types

#### gp3 (General Purpose SSD v3) - Recommended Default

gp3 separates storage size from IOPS. You can have 20 GB of storage but pay for 3000 IOPS separately.

| Spec | Value |
|------|-------|
| Min size | 20 GB |
| Max size | 64 TB |
| Baseline IOPS | 3000 (included in price) |
| Max IOPS | 64,000 |
| Baseline throughput | 125 MB/s (included) |
| Max throughput | 1000 MB/s |
| Cost | ~$0.115/GB/month + IOPS above baseline |

> **Concept:** IOPS = Input/Output Operations Per Second. A database doing 100 small writes per second uses 100 write IOPS.

#### io1 / io2 - Provisioned IOPS (for demanding workloads)

io1 and io2 let you provision a specific IOPS level tied to your storage size. io2 has better durability (99.999% vs 99.8% for io1).

| Spec | io1 | io2 |
|------|-----|-----|
| Min IOPS | 100 | 100 |
| Max IOPS | 64,000 | 256,000 |
| IOPS:GB ratio | 50:1 | 500:1 |
| Durability | 99.8% | 99.999% |
| Use case | High-throughput production | Mission-critical production |

**Storage Type Decision Guide:**

```
Is this dev/test?
  YES -> gp3, default settings
  NO -> Is your workload > 3000 IOPS sustained?
    NO -> gp3 with tuned IOPS
    YES -> io2 (new) or io1 (existing)
```

### Comparing Instance Classes for a Given Workload

| Workload | Recommended Class | Storage |
|----------|------------------|---------|
| Dev/test blog | db.t3.micro | gp3 20 GB |
| Small e-commerce | db.t3.medium or db.m6g.large | gp3 100 GB |
| Mid-size SaaS | db.m6g.xlarge | gp3 500 GB, 6000 IOPS |
| Financial app, high TPS | db.r6g.2xlarge | io2 1 TB, 20000 IOPS |
| Data warehouse queries | db.r6g.4xlarge | gp3 5 TB |

---

## T1.3 - Aurora PostgreSQL Clusters

### What is Aurora?

Aurora is AWS's own database engine that is compatible with PostgreSQL. You write the same SQL and use the same drivers. Under the hood, Aurora uses a distributed storage system that is different from regular RDS.

> **Concept:** Aurora is not PostgreSQL running on an EC2 instance. It is a PostgreSQL-compatible engine built by AWS. The wire protocol is identical, so your apps do not need to change.

### Aurora Architecture vs RDS Architecture

```
RDS PostgreSQL:
--------------
[Your App]
    |
    v
[EC2-like host running PostgreSQL]
    |
    v
[EBS Volume - single AZ storage]


Aurora PostgreSQL:
-----------------
[Your App]
    |
    +----------+----------+
    |                     |
    v                     v
[Writer Instance]   [Reader Instance(s)]
    |                     |
    +----------+----------+
               |
               v
[Aurora Distributed Storage - 6 copies across 3 AZs]
```

Aurora always stores 6 copies of your data across 3 Availability Zones. You do not configure this - it is automatic.

### Aurora Cluster Components

#### Writer Instance (Primary)
- One per cluster
- Accepts reads AND writes
- Has its own instance endpoint

#### Reader Instance(s) (Replicas)
- Zero to 15 per cluster
- Accepts reads ONLY
- Replication lag is typically under 100 milliseconds
- Has its own instance endpoint

#### Cluster Endpoint (Writer Endpoint)
- DNS name that always points to the current writer
- If the writer fails and a reader is promoted, this endpoint automatically updates
- Use this for write operations

#### Reader Endpoint
- DNS name that load-balances across all readers
- If you have 2 readers, the reader endpoint rotates connections between them
- Use this for read-heavy queries

#### Instance Endpoints
- Each instance has its own DNS name
- Points to one specific instance, never changes
- Use when you need to target a specific instance (e.g., for maintenance)

```
aurora-cluster.cluster-abc123.us-east-1.rds.amazonaws.com   <- Cluster endpoint (writer)
aurora-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com <- Reader endpoint
aurora-instance-1.abc123.us-east-1.rds.amazonaws.com         <- Instance 1 endpoint
aurora-instance-2.abc123.us-east-1.rds.amazonaws.com         <- Instance 2 endpoint
```

### Aurora vs RDS Comparison Table

| Feature | RDS PostgreSQL | Aurora PostgreSQL |
|---------|---------------|-------------------|
| Engine | Standard PostgreSQL | Aurora-compatible |
| Storage | EBS (1 copy, 1 AZ) | Distributed (6 copies, 3 AZs) |
| Max storage | 64 TB | 128 TB |
| Replicas | Up to 5 (cross-region possible) | Up to 15 |
| Failover time | 60-120 seconds | Under 30 seconds |
| Replication | Logical/Physical | Storage-layer (faster) |
| Cost | Lower | ~20% more than RDS |
| Best for | Smaller workloads, cost-sensitive | High availability, large workloads |

### When to Choose Aurora Over RDS

Choose Aurora when you need:
- Failover in under 30 seconds
- More than 5 read replicas
- Global databases (Aurora Global Database)
- Serverless scaling (Aurora Serverless v2)

Choose RDS when you:
- Are in dev/test and cost matters
- Need the latest PostgreSQL version (Aurora lags by 1-2 major versions sometimes)
- Have a small database (under 50 GB) with simple requirements

---

## T1.4 - Connectivity: Endpoints, Ports, Subnet Groups, Security Groups

### How an RDS Connection Works

```
[Your App / psql]
      |
      | TCP port 5432
      v
[Security Group] -- inbound rule: allow 5432 from [your IP or CIDR]
      |
      v
[RDS Endpoint DNS] -- resolves to private IP inside your VPC
      |
      v
[RDS Instance] -- PostgreSQL process listening on 5432
      |
      v
[Authenticates with username + password]
      |
      v
[Connected]
```

Every piece of this chain must work. If any one piece is broken, you get a connection error.

### What is a DB Subnet Group?

A DB Subnet Group is a collection of subnets that RDS can use to place your instance. You must create one before you can create an RDS instance.

Requirements for a DB Subnet Group:
- Must include subnets in at least 2 Availability Zones
- All subnets must be in the same VPC
- RDS chooses which subnet to place the instance in

```
VPC: 10.0.0.0/16
  |
  +-- Subnet A (us-east-1a): 10.0.1.0/24  <-- in your subnet group
  |
  +-- Subnet B (us-east-1b): 10.0.2.0/24  <-- in your subnet group
  |
  +-- Subnet C (us-east-1c): 10.0.3.0/24  <-- in your subnet group
```

RDS places the instance in one subnet. For Multi-AZ, RDS places a standby in a different subnet.

### Security Groups

A security group is a virtual firewall. It controls what traffic can reach your RDS instance.

For PostgreSQL, you need an inbound rule:
- Type: PostgreSQL
- Protocol: TCP
- Port: 5432
- Source: Your IP address, or a CIDR block, or another security group

> **Concept:** Never set source to `0.0.0.0/0` (everywhere) on a production database. Anyone on the internet could attempt to connect. Use your specific IP or a VPC CIDR.

### Public vs Private Access

#### Publicly Accessible = Yes
- RDS instance gets a public IP address
- DNS endpoint resolves to a public IP from outside the VPC
- You can connect from your laptop directly
- Requires your security group to allow your IP
- Fine for training, risky for production

#### Publicly Accessible = No
- RDS instance only has a private IP inside the VPC
- You cannot connect directly from your laptop
- You must connect through a bastion host or VPN
- Required for most production setups

```
Publicly Accessible = YES:
[Your Laptop] --> [Internet] --> [Public IP] --> [RDS]

Publicly Accessible = NO:
[Your Laptop] --> [Internet] --> [Bastion Host] --> [Private VPC] --> [RDS]
     OR
[Your Laptop] --> [VPN] --> [Private VPC] --> [RDS]
```

For training in this lab, we use publicly accessible instances with a security group locked to your IP.

### Common Connection Errors and What They Mean

| Error Message | Likely Cause |
|--------------|--------------|
| `Connection timed out` | Security group blocking traffic, or instance is stopped |
| `Connection refused` | Instance is not running, or wrong port |
| `could not translate host name` | Wrong endpoint (typo or copy-paste error) |
| `FATAL: password authentication failed` | Wrong username or password |
| `FATAL: database does not exist` | Database name does not match |
| `SSL connection required` | You need to add `?sslmode=require` or `sslrootcert` |

---

## T1.5 - Connecting with Clients

### The psql Client

psql is the official command-line client for PostgreSQL. Use it for:
- Quick queries and checks
- Running SQL scripts
- Database administration tasks

Connection string format:
```
postgresql://username:password@endpoint:5432/dbname
```

Or flags format:
```
psql -h endpoint -U username -d dbname -p 5432
```

### pgAdmin 4

pgAdmin is a GUI tool for PostgreSQL. Use it for:
- Browsing database objects visually
- Running queries with a results panel
- Visualizing query execution plans

### App Drivers

Each programming language has PostgreSQL libraries:

| Language | Library |
|----------|---------|
| Python | psycopg2, asyncpg |
| Node.js | pg, postgres.js |
| Java | JDBC PostgreSQL driver |
| Go | pgx |
| Ruby | pg gem |

All of them connect using the same endpoint, port, username, and password.

### The Master User and rds_superuser

When you create an RDS instance, you set a master username and password. This user is powerful but is NOT a true PostgreSQL superuser.

> **Concept:** A true PostgreSQL superuser can do anything, including reading `pg_shadow` (password hashes) and bypassing all security. AWS does not give you true superuser because that would let you break things that AWS manages.

Instead, the master user is a member of the `rds_superuser` role. This role has most superuser privileges:

| Privilege | True Superuser | rds_superuser |
|-----------|---------------|---------------|
| Create databases | Yes | Yes |
| Create users | Yes | Yes |
| Grant any privilege | Yes | Yes |
| Read pg_shadow | Yes | No |
| Run pg_read_file() | Yes | No |
| Replication | Yes | Yes (via rds_replication role) |
| Install extensions | Yes | Only allowed extensions |

For 99% of DBA work, `rds_superuser` is sufficient.

### SSL Connections

All RDS connections support SSL. RDS provides a certificate authority bundle you download from AWS. For production, always verify the certificate.

```bash
# Download the AWS RDS certificate bundle
curl -o /tmp/global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Connect with SSL verification
psql "host=mydb.abc123.us-east-1.rds.amazonaws.com \
      user=postgres \
      dbname=myappdb \
      sslmode=verify-full \
      sslrootcert=/tmp/global-bundle.pem"
```

SSL modes explained:

| sslmode | What It Does |
|---------|-------------|
| disable | No SSL. Never use this. |
| allow | Use SSL if server wants it |
| prefer | Use SSL if available (default) |
| require | Always use SSL, but do not verify cert |
| verify-ca | SSL + verify cert is from a trusted CA |
| verify-full | SSL + verify cert + verify hostname matches |

For production: use `verify-full`.
For training: `require` is acceptable.
