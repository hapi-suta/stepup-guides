# Exercise 01: AWS Architecture Quiz

**Duration:** 25 minutes
**Objective:** Test your understanding of core AWS services, regions, availability zones, and the shared responsibility model through 15 multiple-choice questions.
**Prerequisites:** Module 01 BUILD guides complete

---

## How to Use This Exercise

Read each question carefully and select the best answer before expanding the solution. Keep track of your score - there is a scoring guide at the end.

---

## Section 1: AWS Regions and Availability Zones

### Question 1

What is an AWS Region?

A) A single datacenter building owned by AWS
B) A geographic area containing multiple isolated datacenters
C) A virtual private network inside AWS
D) A group of user accounts in the same country

<details>
<summary>Show Answer</summary>

**B) A geographic area containing multiple isolated datacenters**

An AWS Region (like us-east-1 or eu-west-1) is a geographic area that contains multiple Availability Zones. Each AZ is a physically separate datacenter (or group of datacenters) with independent power, cooling, and networking. Regions are fully isolated from each other - a failure in one region does not affect another.

</details>

---

### Question 2

How many Availability Zones does a typical AWS Region have?

A) Exactly 2
B) At least 3 (most regions have 3 or more)
C) Exactly 5
D) It depends on how many you pay for

<details>
<summary>Show Answer</summary>

**B) At least 3 (most regions have 3 or more)**

Most AWS Regions have 3 or more Availability Zones. Some newer or smaller regions may have only 2, but the standard is 3+. You do not pay for the existence of AZs - they are part of the region infrastructure. You pay for the resources you run in them.

</details>

---

### Question 3

Why does AWS recommend deploying databases across multiple Availability Zones?

A) It makes queries run faster
B) It reduces your AWS bill
C) It protects against the failure of a single datacenter
D) It is required by AWS Terms of Service

<details>
<summary>Show Answer</summary>

**C) It protects against the failure of a single datacenter**

Each AZ is an independent failure domain. If one AZ experiences a power outage, network issue, or hardware failure, resources in other AZs continue operating. For databases, Multi-AZ deployment means a standby copy exists in a different AZ and can take over automatically if the primary fails. This does not make individual queries faster - it protects availability.

</details>

---

### Question 4

What happens when you create an RDS instance in us-east-1 with Multi-AZ enabled?

A) AWS creates two identical instances in two different AWS Regions
B) AWS creates a primary instance in one AZ and a synchronous standby in a different AZ within the same region
C) AWS creates read replicas in all available AZs
D) AWS backs up your data to a different region automatically

<details>
<summary>Show Answer</summary>

**B) AWS creates a primary instance in one AZ and a synchronous standby in a different AZ within the same region**

Multi-AZ creates a standby replica in a different AZ within the same region. The standby receives synchronous replication from the primary - meaning every write is confirmed on both copies before it is acknowledged to the application. If the primary fails, RDS automatically fails over to the standby. This is within a single region, not across regions. Cross-region replication requires a separate feature (Aurora Global Database or cross-region read replicas).

</details>

---

## Section 2: AWS Services for Databases

### Question 5

Which AWS service is a fully managed relational database that supports PostgreSQL, MySQL, MariaDB, Oracle, and SQL Server?

A) Amazon DynamoDB
B) Amazon Redshift
C) Amazon RDS
D) Amazon ElastiCache

<details>
<summary>Show Answer</summary>

**C) Amazon RDS**

Amazon RDS (Relational Database Service) is the managed relational database service that supports multiple engines. DynamoDB is a NoSQL key-value store. Redshift is a data warehouse for analytics. ElastiCache is a managed in-memory cache (Redis or Memcached). Knowing which service handles which workload is fundamental to AWS architecture.

</details>

---

### Question 6

What is Amazon Aurora?

A) A completely different database engine built from scratch by AWS
B) A MySQL and PostgreSQL-compatible database built on a custom distributed storage layer
C) A NoSQL database optimized for key-value lookups
D) A tool for migrating on-premises databases to AWS

<details>
<summary>Show Answer</summary>

**B) A MySQL and PostgreSQL-compatible database built on a custom distributed storage layer**

Aurora is wire-compatible with MySQL and PostgreSQL - you can use the same drivers, tools, and SQL. What makes it different from standard RDS is the storage layer: Aurora uses a distributed, fault-tolerant storage system that replicates data six ways across three AZs. This gives it faster failover, higher durability, and up to 15 read replicas (vs 5 for standard RDS). It is not a brand-new engine - it runs PostgreSQL or MySQL on top of a custom storage backend.

</details>

---

### Question 7

Which AWS service would you use to store database credentials securely and rotate them automatically?

A) AWS IAM
B) Amazon S3
C) AWS Secrets Manager
D) AWS CloudTrail

<details>
<summary>Show Answer</summary>

**C) AWS Secrets Manager**

Secrets Manager stores sensitive information like database passwords, API keys, and tokens. It can automatically rotate credentials on a schedule without requiring application downtime. IAM handles identity and permissions but does not store database passwords. S3 is object storage. CloudTrail logs API calls for auditing but does not store secrets.

</details>

---

### Question 8

What does Amazon CloudWatch do for RDS databases?

A) Encrypts data at rest
B) Collects and displays metrics like CPU utilization, storage space, and database connections
C) Manages database schema migrations
D) Creates read replicas automatically

<details>
<summary>Show Answer</summary>

**B) Collects and displays metrics like CPU utilization, storage space, and database connections**

CloudWatch is AWS's monitoring service. For RDS, it automatically collects metrics including CPUUtilization, FreeStorageSpace, DatabaseConnections, ReadIOPS, WriteIOPS, and FreeableMemory. You can set alarms on these metrics to get notified when thresholds are breached (for example, when free storage drops below 10 GB). CloudWatch does not manage encryption, schema changes, or replication.

</details>

---

### Question 9

Which AWS service records all API calls made in your AWS account, including who created or deleted an RDS instance?

A) Amazon CloudWatch
B) AWS CloudTrail
C) AWS Config
D) Amazon Inspector

<details>
<summary>Show Answer</summary>

**B) AWS CloudTrail**

CloudTrail records every API call made in your AWS account - who called it, when, from what IP, and what parameters were used. If someone deletes an RDS instance, CloudTrail has the record. CloudWatch monitors metrics and performance. AWS Config tracks resource configuration changes over time. Amazon Inspector scans for security vulnerabilities. CloudTrail is the audit log for API activity.

</details>

---

## Section 3: Shared Responsibility Model

### Question 10

In the AWS shared responsibility model, who is responsible for patching the operating system on an RDS instance?

A) You (the customer)
B) AWS
C) It depends on the instance type
D) A third-party vendor

<details>
<summary>Show Answer</summary>

**B) AWS**

With managed services like RDS and Aurora, AWS is responsible for the underlying operating system. You never have SSH access to the OS on an RDS instance. AWS handles OS patching, security updates, and kernel maintenance. On EC2 (self-managed), you own OS patching. This is one of the key benefits of managed databases - you do not manage the operating system.

</details>

---

### Question 11

A developer accidentally runs `DELETE FROM customers WHERE 1=1;` in production, deleting all rows. Whose responsibility is this?

A) AWS - they should prevent destructive queries
B) You - data integrity and access controls are your responsibility
C) Shared - AWS should have warned the developer
D) The database engine vendor (PostgreSQL community)

<details>
<summary>Show Answer</summary>

**B) You - data integrity and access controls are your responsibility**

AWS keeps the database engine running reliably. What SQL you execute inside the engine is entirely your responsibility. AWS cannot distinguish between intentional and accidental queries - both are valid SQL. Your responsibility includes: controlling who can run destructive queries in production, setting up backup and recovery procedures, and testing restores regularly. AWS provides the tools (automated backups, PITR, snapshots), but whether you use them effectively is on you.

</details>

---

### Question 12

Who is responsible for encrypting data at rest on an RDS instance?

A) AWS handles it automatically with no action from you
B) You must enable it - AWS provides the feature, but you decide whether to use it
C) Only third-party encryption tools work with RDS
D) Encryption is not available on RDS

<details>
<summary>Show Answer</summary>

**B) You must enable it - AWS provides the feature, but you decide whether to use it**

AWS provides encryption at rest using AWS KMS (Key Management Service), but you must enable it when creating the instance. Once enabled, AWS manages the encryption keys and handles all encryption/decryption transparently. If you do not enable it, data is stored unencrypted. This is a shared responsibility - AWS provides the capability, you decide to use it. Note: Aurora encrypts storage at rest by default on new clusters, but RDS PostgreSQL requires you to enable it.

</details>

---

### Question 13

An RDS instance runs out of storage and stops accepting writes. Whose fault is this?

A) AWS - they should auto-expand storage
B) You - capacity planning and monitoring are your responsibility
C) Shared - AWS provides autoscaling, but you must enable and configure it
D) It depends on whether you have a support plan

<details>
<summary>Show Answer</summary>

**C) Shared - AWS provides autoscaling, but you must enable and configure it**

AWS provides storage autoscaling for RDS, which can automatically expand storage when usage approaches the limit. However, this feature must be enabled and configured with a maximum storage threshold. If you did not enable it, or if your maximum threshold was too low, the instance runs out of space. AWS provides the tool. You decide whether to use it, configure the limits, and set up CloudWatch alarms to monitor free storage. Both parties have a role.

</details>

---

### Question 14

Your RDS security group allows inbound connections from 0.0.0.0/0 on port 5432. A hacker brute-forces the database password and steals data. Who is responsible?

A) AWS - they should block suspicious login attempts
B) You - security group configuration and access controls are your responsibility
C) The hacker
D) The ISP that provided the hacker's internet connection

<details>
<summary>Show Answer</summary>

**B) You - security group configuration and access controls are your responsibility**

Security group rules are entirely your responsibility. Opening port 5432 to 0.0.0.0/0 means the entire internet can attempt connections. AWS provides security groups as a tool, but you configure the rules. AWS does not override your security group decisions or block brute-force attempts at the network level. Properly configured security groups should allow inbound database connections only from your application servers' security group - never from 0.0.0.0/0.

</details>

---

### Question 15

A physical hard drive in the datacenter hosting your RDS instance fails. What happens?

A) Your database is permanently lost
B) You must file a support ticket and wait for AWS to replace the drive
C) AWS automatically handles the hardware failure - you may see a brief interruption if Multi-AZ failover occurs
D) AWS sends you a replacement drive to install

<details>
<summary>Show Answer</summary>

**C) AWS automatically handles the hardware failure - you may see a brief interruption if Multi-AZ failover occurs**

Hardware failure is entirely AWS's responsibility. RDS runs on managed infrastructure - you never interact with physical hardware. With Multi-AZ enabled, the standby takes over automatically and you may see a brief connection interruption (typically 60-120 seconds). Without Multi-AZ, AWS still handles the recovery, but it takes longer. You do not file hardware tickets, replace drives, or rebuild RAID arrays. This is one of the core benefits of managed database services.

</details>

---

## Scoring Guide

| Score | Level | Assessment |
|-------|-------|------------|
| 13-15 | Excellent | You have a solid understanding of AWS fundamentals. Ready to move to hands-on labs. |
| 10-12 | Good | You understand the basics but should review the topics where you missed questions. |
| 7-9 | Needs Review | Re-read the BUILD guides for Sections 2 and 3 before continuing. |
| Below 7 | Start Over | Go through all BUILD guides again carefully. These are foundational concepts you will use daily. |

---

## Summary of Key Takeaways

- AWS Regions are geographic areas with multiple Availability Zones. AZs are independent failure domains - Multi-AZ deployments protect against single-AZ failure.
- Know which service does what: RDS (managed relational), Aurora (RDS with custom storage), CloudWatch (metrics), CloudTrail (API audit logs), Secrets Manager (credential storage), IAM (identity and permissions).
- The shared responsibility model splits at the infrastructure boundary: AWS owns hardware, OS, and engine process. You own data, queries, access controls, encryption decisions, and capacity planning.
- Security groups are your responsibility. An open security group is never AWS's fault.
- AWS provides tools (backups, encryption, autoscaling, Multi-AZ). Whether you configure and use them is your decision.
