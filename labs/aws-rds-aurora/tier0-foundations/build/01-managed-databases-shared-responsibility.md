# Tier 0 - Foundations
## Guide 01: Managed Databases and the Shared Responsibility Model

**Objective:** Understand what "managed" means in the AWS context and clearly identify which responsibilities belong to AWS versus which belong to you as a DBA or engineer.
**Time:** 20 minutes
**Prerequisites:** Basic familiarity with what a database is (tables, queries, users)
**Infrastructure:** None required (conceptual)

---

## 1. What Does "Managed" Mean?

When engineers say a database is "managed," they mean that a cloud provider - in this case AWS - takes over many of the operational tasks that your team would otherwise handle manually.

Think about what it takes to run PostgreSQL on a server you own or rent:

- You purchase or provision a server
- You install the operating system
- You patch the OS regularly for security vulnerabilities
- You install PostgreSQL
- You upgrade PostgreSQL when new versions release
- You configure storage volumes
- You set up automated backups
- You monitor disk usage and add capacity when needed
- You configure replication for high availability
- You monitor the database for crashes and restart it if it goes down
- You replace failed hardware

That is a long list. When you move to a managed service like Amazon RDS, AWS handles most of that list. You focus on what the database holds and how it performs - not on whether the underlying server is patched or the disk is healthy.

This is the core promise of managed databases: **operational burden shifts from you to the provider.**

---

## 2. The Shared Responsibility Model

AWS publishes something called the Shared Responsibility Model. It is a framework that draws a line between what AWS is responsible for and what the customer (you) is responsible for.

The mental model is simple:

- **AWS is responsible for the security and availability OF the cloud** - the physical infrastructure, the hardware, the hypervisor, the network, and the managed service software itself.
- **You are responsible for security and compliance IN the cloud** - your data, your users, your access controls, your application logic, and your configuration choices.

This distinction matters because:
1. It tells you where to focus your security effort.
2. It tells you what you can rely on AWS to handle automatically.
3. It helps you understand where incidents are your problem versus AWS's problem.

---

## 3. RDS Shared Responsibility - What AWS Manages

For Amazon RDS specifically, AWS handles the following:

**Hardware and Physical Layer**
- Physical servers in AWS data centers
- Storage hardware (the actual disks)
- Network infrastructure inside the data center
- Hardware failure replacement

**Operating System**
- The OS that RDS runs on is managed by AWS
- You cannot SSH into an RDS instance - there is no OS access
- OS patches and security updates are applied by AWS on a maintenance schedule

**Database Software**
- AWS installs and maintains the PostgreSQL binaries
- Minor version patches are available and can be applied automatically
- Major version upgrades are initiated by you but performed by AWS

**Infrastructure Services**
- Automated backups (you configure the window, AWS runs them)
- Storage volume management and expansion
- Multi-AZ failover mechanics (if you enable Multi-AZ)
- Replication setup (if you enable read replicas)
- Monitoring agents that feed into CloudWatch

---

## 4. What You Still Manage

Even though RDS removes a lot of burden, you are still responsible for a significant set of tasks:

**Data and Schema**
- The tables you create and the data inside them
- Schema design and migrations
- Data quality and integrity

**Database Configuration**
- Parameter groups (PostgreSQL configuration settings like `work_mem`, `max_connections`)
- Which PostgreSQL version you run
- Whether you enable Multi-AZ or not
- Whether you enable automated backups and how long to retain them
- Storage size (you choose the initial size; AWS can autoscale if you enable it)

**Access and Security**
- Database users and roles (the PostgreSQL `CREATE USER` and `GRANT` commands)
- Who has access to the database and at what privilege level
- IAM policies that control who can launch, modify, or delete the RDS instance
- Security group rules that control which IP addresses or services can connect
- Whether you enable encryption at rest and in transit (you turn this on; AWS enforces it)
- Secrets management - where you store database passwords

**Application Layer**
- How your application connects to the database
- Connection pooling decisions
- Query performance - slow queries are your responsibility to find and fix
- Index creation and maintenance
- VACUUM and autovacuum tuning

**Compliance**
- Whether your configuration meets your industry's regulatory requirements
- Data residency (you choose the region; you are responsible for the implications)
- Audit logging configuration (you enable and configure `pgaudit` if needed)

---

## 5. Self-Managed PostgreSQL vs RDS - Side by Side

This table compares the responsibilities across two deployment models.

| Task | Self-Managed (EC2 or bare metal) | Amazon RDS |
|------|----------------------------------|------------|
| Provision a server | You | You (choose instance type) |
| Install OS | You | AWS |
| Patch OS | You | AWS |
| Install PostgreSQL | You | AWS |
| Minor version patches | You | AWS (optional auto-apply) |
| Major version upgrades | You | You initiate, AWS runs |
| Configure storage | You | You choose size and type |
| Expand storage | You (manual) | AWS (auto or manual) |
| Automated backups | You set up | AWS (you configure window) |
| Point-in-time recovery | You set up | AWS (built-in) |
| Multi-AZ failover | You configure | AWS (toggle on/off) |
| Read replica replication | You configure | AWS (click to create) |
| Monitor disk/CPU/memory | You | AWS CloudWatch (built-in) |
| Restart on crash | You (manual or scripts) | AWS (automatic) |
| Hardware replacement | You (or data center) | AWS |
| Security group / firewall | You (OS firewall) | AWS Security Groups |
| Database users and grants | You | You |
| Schema and data | You | You |
| Slow query tuning | You | You |
| Connection management | You | You |

The pattern is clear: RDS removes almost everything at and below the database binary level. Above that - data, users, queries, schema - remains your domain.

---

## 6. Exercise: Classify These Tasks

Read each task below. Decide whether it is managed by **AWS** or by **You** in an RDS deployment. Write your answers before reading the key below.

1. Replacing a failed SSD in the server running your RDS instance
2. Creating a new PostgreSQL role with read-only access to a specific schema
3. Setting the `max_connections` parameter in your RDS parameter group
4. Applying an OS security patch to the server running RDS
5. Adding an index to a slow query
6. Enabling automated backups with a 7-day retention window
7. Configuring a security group to allow port 5432 from your application servers
8. Deciding which AWS region your RDS instance lives in
9. Upgrading PostgreSQL from 15.x to 16.x on RDS
10. Running `VACUUM ANALYZE` on a bloated table

**Answer Key:**

| # | Task | Managed By |
|---|------|------------|
| 1 | Replace failed SSD | **AWS** - you never touch the hardware |
| 2 | Create PostgreSQL role | **You** - database users are always your responsibility |
| 3 | Set `max_connections` in parameter group | **You** - you configure parameter groups |
| 4 | Apply OS security patch | **AWS** - the OS is not accessible to you |
| 5 | Add index to slow query | **You** - query tuning is always yours |
| 6 | Enable automated backups | **You configure, AWS runs** - you set the policy, AWS executes |
| 7 | Configure security group rules | **You** - you define which IPs can connect |
| 8 | Choose the AWS region | **You** - you make this decision at launch |
| 9 | Upgrade PostgreSQL major version | **You initiate, AWS runs** - you schedule it, AWS performs it |
| 10 | Run `VACUUM ANALYZE` | **You** - autovacuum runs automatically but manual VACUUM is yours |

---

## 7. Why This Model Matters for DBAs

Understanding the shared responsibility model changes how you approach your work:

**Incidents:** If RDS goes down because of hardware failure, that is AWS's problem. If queries are slow because of a missing index, that is your problem. Knowing the boundary helps you route incidents correctly.

**Compliance audits:** Auditors will ask who is responsible for patching. For RDS, you point to AWS's SOC 2 and ISO certifications for the OS layer. For your database users and data access, you provide your own evidence.

**Cost of operations:** Managed databases cost more per compute unit than running your own PostgreSQL on EC2. But the labor you save on OS management, backup scripting, and HA configuration often justifies the premium. The shared responsibility model helps you make that cost argument clearly.

**Security posture:** Misconfigurations in what you manage - overly permissive security groups, weak passwords, unencrypted storage - are your liability, not AWS's. The model makes this explicit.

---

## Summary

- "Managed" means AWS handles the hardware, OS, and database binary layer for you.
- The Shared Responsibility Model defines a clear line: AWS owns the infrastructure layer, you own what runs on it.
- For RDS, AWS manages: physical hardware, OS, PostgreSQL installation, patching, automated backups, failover mechanics, and storage hardware.
- You manage: database users, schema, queries, parameter configuration, security group rules, encryption choices, compliance, and application connectivity.
- The model helps you understand where to focus security work, how to route incidents, and how to justify managed service costs.

**Next:** [Guide 02 - RDS for PostgreSQL vs Aurora PostgreSQL](./02-rds-vs-aurora-architecture.md)
