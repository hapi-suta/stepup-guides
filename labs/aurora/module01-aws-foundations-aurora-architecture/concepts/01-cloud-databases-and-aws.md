# Cloud Databases and AWS

## Module 01 - Concept 01 | DevOps DBA Training Track

---

## What You Will Learn

By the end of this concept doc, you will understand:

- What a database is and how data lives inside it
- The difference between managing your own database and letting AWS manage it for you
- How AWS splits responsibility between you and them (the shared responsibility model)
- Which AWS services matter most for database work
- Why Aurora PostgreSQL is the engine we focus on in this track
- How cloud database pricing works so you never get a surprise bill

---

## What Is a Database?

Before we talk about clouds and services, let's start at the beginning.

A database is a program that stores, organizes, and retrieves data. Think of it like a
spreadsheet application that runs on a server instead of your laptop - but far more powerful
and built to handle thousands of requests at the same time.

### Tables, Rows, and Columns

Data in a relational database lives in **tables**. A table looks like this:

```
+----+-----------+------------------+------------+
| id | name      | email            | created_at |
+----+-----------+------------------+------------+
|  1 | Aisha     | aisha@email.com  | 2026-01-15 |
|  2 | Carlos    | carlos@email.com | 2026-02-20 |
|  3 | Mei       | mei@email.com    | 2026-03-10 |
+----+-----------+------------------+------------+
```

- **Table** - a collection of related data (like "customers" or "orders")
- **Row** - a single record (one customer, one order)
- **Column** - a specific piece of information (name, email, date)
- **Primary key** - a unique identifier for each row (the `id` column above)

### SQL - The Language of Databases

To talk to a database, you use **SQL** (Structured Query Language). SQL has been around
since the 1970s and is still the most important language in data.

Here are the four basic operations:

```sql
-- Create a new record
INSERT INTO customers (name, email) VALUES ('Aisha', 'aisha@email.com');

-- Read records
SELECT name, email FROM customers WHERE id = 1;

-- Update a record
UPDATE customers SET email = 'newemail@email.com' WHERE id = 1;

-- Delete a record
DELETE FROM customers WHERE id = 3;
```

These four operations - Create, Read, Update, Delete - are called **CRUD**. Almost every
application in the world is doing CRUD operations against a database thousands of times
per second.

### Why This Matters

Every company you will ever work for runs on databases. E-commerce stores, banks, hospitals,
social media platforms, government systems - all of them depend on databases being fast,
reliable, and available 24/7. The person responsible for making that happen is the DBA.

---

## Self-Managed vs Managed Databases - The Shift

### The Old Way: Self-Managed

Ten years ago, if [COMPANY] needed a database, the DBA would:

1. Order a physical server (wait 2-6 weeks for delivery)
2. Rack it in the data center (physically bolt it into a server rack)
3. Install the operating system (Linux, usually)
4. Install the database software (PostgreSQL, MySQL, etc.)
5. Configure storage (set up RAID arrays, mount drives)
6. Set up backups (write scripts, test restores)
7. Set up monitoring (install tools, configure alerts)
8. Set up high availability (configure replication to a standby server)
9. Patch the OS and database software regularly
10. Handle hardware failures at 3 AM

This is **self-managed**. You own everything. You control everything. You are also
responsible for everything - including getting paged when a disk fills up on a Saturday night.

### The New Way: Managed Databases

With managed databases, AWS (or another cloud provider) handles the undifferentiated
heavy lifting:

1. You click a few buttons (or run a Terraform script)
2. AWS provisions the server, installs the OS, installs the database
3. AWS handles backups automatically
4. AWS handles patching
5. AWS handles replication and failover
6. You focus on schema design, query performance, and security

This is **managed**. AWS owns the infrastructure. You own the data and the application logic.

### Comparison Table

| Task                        | Self-Managed | Managed (RDS/Aurora) |
|-----------------------------|:------------:|:--------------------:|
| Hardware procurement        | You          | AWS                  |
| OS installation             | You          | AWS                  |
| Database installation       | You          | AWS                  |
| OS patching                 | You          | AWS                  |
| Database patching           | You          | AWS (you pick window)|
| Automated backups           | You          | AWS                  |
| Storage scaling             | You          | AWS (auto for Aurora)|
| Replication setup           | You          | AWS                  |
| Failover handling           | You          | AWS (automatic)      |
| Schema design               | You          | You                  |
| Query optimization          | You          | You                  |
| Security (users, roles)     | You          | You                  |
| Application connection      | You          | You                  |
| Compliance/audit            | You          | Shared               |

### Why This Matters

The shift to managed databases does not eliminate the DBA role - it transforms it. Instead
of spending 60% of your time on infrastructure tasks (patching, backups, hardware), you
spend that time on higher-value work: performance tuning, security hardening, cost
optimization, and building automation. That is exactly what a DevOps DBA does.

---

## The Shared Responsibility Model

AWS does not take care of everything. Security, compliance, and operations are split between
you and AWS. Understanding this split is critical - if something goes wrong in your area
of responsibility, AWS will not fix it for you.

### ASCII Diagram - Shared Responsibility for Aurora

```
+================================================================+
|                    YOUR RESPONSIBILITY                          |
|                    (Security IN the Cloud)                      |
|                                                                |
|  +----------------------------------------------------------+  |
|  |  Application layer                                        |  |
|  |  - Connection strings, credentials management             |  |
|  |  - SQL injection prevention in app code                   |  |
|  +----------------------------------------------------------+  |
|  |  Data layer                                               |  |
|  |  - Schema design, indexes                                 |  |
|  |  - Encryption at rest (you enable it)                     |  |
|  |  - Row-level security, roles, grants                      |  |
|  +----------------------------------------------------------+  |
|  |  Network layer                                            |  |
|  |  - VPC configuration, security groups                     |  |
|  |  - Subnet placement (public vs private)                   |  |
|  |  - TLS/SSL enforcement for connections                    |  |
|  +----------------------------------------------------------+  |
|  |  Identity and Access                                      |  |
|  |  - IAM policies (who can create/delete/modify instances)  |  |
|  |  - Database users and passwords                           |  |
|  |  - Multi-factor authentication for AWS console            |  |
|  +----------------------------------------------------------+  |
|                                                                |
+================================================================+
|                    AWS RESPONSIBILITY                           |
|                    (Security OF the Cloud)                      |
|                                                                |
|  +----------------------------------------------------------+  |
|  |  Managed service layer                                    |  |
|  |  - Database engine patching                               |  |
|  |  - Automated backups (retention up to 35 days)            |  |
|  |  - Automatic failover between writer and reader           |  |
|  |  - Storage replication (6 copies across 3 AZs)            |  |
|  +----------------------------------------------------------+  |
|  |  Infrastructure layer                                     |  |
|  |  - Physical servers, networking, power, cooling           |  |
|  |  - Hypervisor security                                    |  |
|  |  - Data center physical security                          |  |
|  |  - Hardware replacement                                   |  |
|  +----------------------------------------------------------+  |
|                                                                |
+================================================================+
```

### The Key Takeaway

If someone gains unauthorized access to your database because you left the security group
open to `0.0.0.0/0` (the entire internet) - that is your fault, not AWS's. AWS provides
the tools to lock things down. Using them correctly is your job.

---

## AWS Services That Matter for Database Work

AWS has over 200 services. You do not need to know all of them. For database work, focus
on these:

### Core Database Services

| Service       | What It Does                                          | When You Use It                    |
|---------------|-------------------------------------------------------|------------------------------------|
| **RDS**       | Managed relational databases (PostgreSQL, MySQL, etc.)| Standard workloads                 |
| **Aurora**    | AWS-engineered relational database (PostgreSQL/MySQL) | High-performance, high-availability|
| **DynamoDB**  | Managed NoSQL key-value database                      | Low-latency, flexible schema apps  |
| **ElastiCache**| Managed Redis or Memcached                           | Caching layer in front of databases|

### Supporting Services

| Service         | What It Does                                        | Why DBAs Care                      |
|-----------------|-----------------------------------------------------|------------------------------------|
| **IAM**         | Identity and Access Management - controls who can do what | You set permissions for DB access |
| **VPC**         | Virtual Private Cloud - your private network in AWS | Databases live inside VPCs         |
| **CloudWatch**  | Monitoring, logs, and alerts                        | You monitor DB health and set alarms|
| **S3**          | Object storage (files, backups, exports)            | Store database exports, snapshots  |
| **KMS**         | Key Management Service - encryption keys            | Encrypt databases at rest          |
| **Secrets Manager** | Stores and rotates credentials securely        | Store DB passwords, rotate them    |
| **CloudFormation/Terraform** | Infrastructure as Code             | Provision databases repeatably     |

### Why This Matters

As a DevOps DBA at [COMPANY], you will not just "manage databases." You will configure
VPCs so databases are not exposed to the internet. You will set up CloudWatch alarms so
[TEAM NAME] gets paged before the database runs out of connections. You will write
Terraform code so every database is provisioned the same way, every time.

---

## Why Aurora PostgreSQL?

### Why PostgreSQL?

PostgreSQL is the world's most advanced open-source relational database. It has been in
active development since 1986 and has a reputation for:

- **Standards compliance** - follows the SQL standard closely
- **Extensibility** - supports custom data types, operators, and extensions
- **Reliability** - trusted by banks, governments, and Fortune 500 companies
- **Community** - large, active open-source community
- **Features** - JSON support, full-text search, geospatial data, partitioning

According to the DB-Engines ranking, PostgreSQL has been gaining popularity faster than
any other database engine for over a decade. Job postings requiring PostgreSQL skills have
grown steadily year over year.

### Why Aurora Specifically?

Aurora is AWS's re-engineered version of PostgreSQL (and MySQL). It uses the same PostgreSQL
engine on the compute side, but replaces the storage layer with a custom distributed storage
system. This gives you:

- **Higher availability** - 6 copies of your data across 3 data centers
- **Faster replication** - readers get updates in milliseconds, not seconds
- **Auto-scaling storage** - starts at 10 GB, grows automatically to 128 TB
- **Faster failover** - typically under 30 seconds (vs minutes for standard RDS)
- **Backtrack** - rewind your database to a point in time without restoring from backup

### Market Demand

Aurora is the fastest-growing service in AWS history (by revenue). Companies migrating from
on-premises Oracle and SQL Server frequently choose Aurora PostgreSQL as their target. This
means strong demand for DBAs who know how to run Aurora in production.

---

## Cost Model Basics

Cloud databases are not free. Understanding the pricing model prevents surprise bills and
helps you make smart architectural decisions.

### What You Pay For

```
+------------------------------------------------------------------+
|                     Aurora Cost Breakdown                         |
|                                                                  |
|   1. COMPUTE (instance hours)                                    |
|      - Pay per hour for each instance (writer + readers)         |
|      - Example: db.r6g.large = ~$0.26/hour = ~$190/month        |
|                                                                  |
|   2. STORAGE (per GB-month)                                      |
|      - $0.10 per GB-month                                        |
|      - Auto-grows, no pre-allocation needed                      |
|      - Example: 100 GB = $10/month                               |
|                                                                  |
|   3. I/O (per million requests)                                  |
|      - $0.20 per million read/write requests                     |
|      - This is the sneaky one - high-throughput apps add up      |
|      - Aurora I/O Optimized eliminates this (higher base cost)   |
|                                                                  |
|   4. BACKUPS (beyond free tier)                                  |
|      - Backup storage up to total DB size = free                 |
|      - Beyond that: $0.021 per GB-month                          |
|                                                                  |
|   5. DATA TRANSFER                                               |
|      - Data in = free                                            |
|      - Data out to internet = $0.09/GB (first 10 TB)             |
|      - Cross-AZ within cluster = free for Aurora                 |
+------------------------------------------------------------------+
```

### Quick Cost Estimate

A typical small production Aurora PostgreSQL setup:

| Component              | Monthly Cost |
|------------------------|-------------:|
| 1 Writer (db.r6g.large)| $190         |
| 1 Reader (db.r6g.large)| $190         |
| 50 GB storage          | $5           |
| I/O (moderate traffic) | $30-80       |
| Backups                | $0 (within free tier) |
| **Total**              | **$415-465** |

Compare this to running your own servers:

| Component              | Monthly Cost |
|------------------------|-------------:|
| 2 physical servers     | $600-1,200   |
| SAN storage            | $200-500     |
| Data center space/power| $300-600     |
| DBA time (40% infra)   | $4,000+      |
| **Total**              | **$5,100+**  |

### Why This Matters

At [COMPANY], when [TEAM NAME] asks "can we spin up a new database for this project?",
you need to answer with a cost estimate - not just a "yes." Understanding the pricing model
lets you recommend the right instance size, decide between provisioned and serverless, and
avoid the classic mistake of over-provisioning "just in case."

---

## Key Takeaways

1. **Databases store data in tables** with rows and columns. You interact with them using SQL.

2. **Managed databases shift work to AWS** - you stop managing hardware, patching, and
   backups, and focus on schema design, performance, and security.

3. **The shared responsibility model means AWS secures the infrastructure, but you secure
   the data and access.** Misconfigured security groups are your problem.

4. **Six AWS services matter most for database work:** RDS/Aurora (compute), VPC (network),
   IAM (access), CloudWatch (monitoring), S3 (storage), and KMS (encryption).

5. **Aurora PostgreSQL combines the open-source PostgreSQL engine with a custom
   high-availability storage layer.** It is the most in-demand managed database on AWS.

6. **Cloud costs have four main components:** compute (instance hours), storage (GB-month),
   I/O (request volume), and data transfer. The I/O cost is the one that catches people
   off guard.

---

## What Is Next?

In the next concept doc, we take a deep dive into Aurora's architecture - how the storage
layer works, why 6 copies across 3 availability zones matters, and what endpoints are
and how to use them. This is the foundation for everything you will build in the hands-on
labs.

---

*Module 01 - Concept 01 | DevOps DBA Training Track*
*[COMPANY] - [TEAM NAME]*
