# Exercise 02: Shared Responsibility Classification

**Duration:** 20 minutes
**Objective:** Classify 20 database operational tasks as "AWS manages" or "You manage" for both RDS and Aurora, and understand where the responsibility boundary shifts between the two services.
**Prerequisites:** Module 01 BUILD guides complete

---

## Background

You are a new DBA at [COMPANY]. Your team runs both RDS PostgreSQL and Aurora PostgreSQL clusters. During an incident review meeting, it became clear that nobody on the team has a clear understanding of what AWS handles versus what the team owns. Your manager asks you to build a reference chart.

Below are 20 operational tasks. For each one, classify it as:

- **AWS** - AWS handles this automatically, no action from you
- **You** - Your team must do this; AWS does not handle it
- **Shared** - Both parties have a role (describe the split)

Some tasks have the same classification for both RDS and Aurora. Others shift. Pay attention to the differences.

Work through all 20 before checking the answers.

---

## The 20 Tasks

| # | Operational Task |
|---|------------------|
| 1 | Replacing a failed physical hard drive |
| 2 | Choosing which PostgreSQL version to run |
| 3 | Writing efficient SQL queries |
| 4 | Applying PostgreSQL minor version patches |
| 5 | Designing the database schema (tables, columns, indexes) |
| 6 | Taking automated daily backups |
| 7 | Restoring from a backup after data loss |
| 8 | Deciding whether to enable Multi-AZ |
| 9 | Performing the Multi-AZ failover when hardware fails |
| 10 | Setting up security group rules for port 5432 |
| 11 | Managing database user accounts and passwords |
| 12 | Monitoring CPU and memory usage |
| 13 | Scaling storage when the database grows |
| 14 | Tuning PostgreSQL parameters (work_mem, shared_buffers) |
| 15 | Encrypting data at rest |
| 16 | Repairing storage-level data corruption (bit rot) |
| 17 | Fixing logical data corruption from a bad application deploy |
| 18 | Rotating SSL/TLS certificates on the database endpoint |
| 19 | Creating and managing read replicas |
| 20 | Running VACUUM to reclaim dead row space |

---

## Your Classification Table

Copy this table and fill in your answers before checking the solutions.

| # | Task | RDS Classification | Aurora Classification |
|---|------|-------------------|----------------------|
| 1 | Replacing a failed hard drive | | |
| 2 | Choosing PostgreSQL version | | |
| 3 | Writing efficient SQL queries | | |
| 4 | Applying minor version patches | | |
| 5 | Designing database schema | | |
| 6 | Taking automated daily backups | | |
| 7 | Restoring from a backup | | |
| 8 | Deciding to enable Multi-AZ | | |
| 9 | Performing Multi-AZ failover | | |
| 10 | Setting security group rules | | |
| 11 | Managing database users/passwords | | |
| 12 | Monitoring CPU and memory | | |
| 13 | Scaling storage | | |
| 14 | Tuning PostgreSQL parameters | | |
| 15 | Encrypting data at rest | | |
| 16 | Repairing storage-level corruption | | |
| 17 | Fixing logical data corruption | | |
| 18 | Rotating SSL/TLS certificates | | |
| 19 | Creating and managing read replicas | | |
| 20 | Running VACUUM | | |

---

## Answers

<details>
<summary>Show All Answers</summary>

### Task 1: Replacing a Failed Hard Drive
**RDS: AWS | Aurora: AWS**

Hardware management is entirely AWS's responsibility for both services. You never interact with physical infrastructure. If a drive fails, AWS replaces it transparently. With Multi-AZ, failover happens automatically. Aurora's distributed storage makes this even more seamless - data is replicated six ways across three AZs, so a single drive failure is handled without any service interruption.

---

### Task 2: Choosing Which PostgreSQL Version to Run
**RDS: You | Aurora: You**

You choose the engine version when creating the instance and when upgrading. AWS makes versions available, but you decide which one to use. This applies equally to RDS and Aurora. AWS will eventually deprecate old versions and force upgrades, but the timing of your upgrade within the supported window is your decision.

---

### Task 3: Writing Efficient SQL Queries
**RDS: You | Aurora: You**

Query design, optimization, and performance are entirely your responsibility. AWS runs the engine - what you execute inside it is your domain. This includes choosing proper indexes, writing efficient JOINs, avoiding full table scans, and using EXPLAIN ANALYZE to diagnose slow queries. No difference between RDS and Aurora here.

---

### Task 4: Applying PostgreSQL Minor Version Patches
**RDS: Shared | Aurora: Shared**

AWS builds and releases the patched engine version. You control when it is applied by setting the maintenance window and choosing whether to enable auto minor version upgrades. If you disable auto upgrades, you must manually trigger the update. AWS will force critical security patches in rare cases, but normally you control the timing.

---

### Task 5: Designing the Database Schema
**RDS: You | Aurora: You**

Tables, columns, data types, constraints, indexes, and relationships are entirely your design decisions. AWS provides the engine - how you structure your data inside it is your responsibility. Poor schema design leads to poor performance regardless of which managed service you use.

---

### Task 6: Taking Automated Daily Backups
**RDS: Shared | Aurora: Shared**

AWS provides the automated backup feature and executes the backups. You must configure the retention period (1-35 days), set the backup window, and decide whether to enable cross-region backup copies. If you leave retention at 0 (disabled), no automated backups run. AWS provides the tool; you configure it. Aurora continuous backups have the same model - AWS runs them, you set retention.

---

### Task 7: Restoring from a Backup After Data Loss
**RDS: You | Aurora: You**

AWS stores the backups and provides the restore mechanism. But the decision to restore, choosing the correct point in time, executing the restore, validating the data, and pointing applications to the restored instance - all of that is your job. AWS does not know your data was lost. You must detect the problem, decide on a recovery strategy, and execute it.

---

### Task 8: Deciding Whether to Enable Multi-AZ
**RDS: You | Aurora: You**

This is an architecture decision you make. AWS provides Multi-AZ as a feature - you decide whether to enable it based on your availability requirements and budget. If you choose single-AZ and the AZ goes down, that was your decision. For Aurora, you decide how many reader instances to deploy and in which AZs.

---

### Task 9: Performing Multi-AZ Failover When Hardware Fails
**RDS: AWS | Aurora: AWS**

Once Multi-AZ is enabled, the failover process is fully automated by AWS. When AWS detects a failure on the primary, it promotes the standby and updates the DNS endpoint. You do not trigger this - AWS does it automatically. Your responsibility is to have Multi-AZ enabled in the first place (Task 8) and to ensure your application handles brief connection interruptions during failover.

---

### Task 10: Setting Up Security Group Rules
**RDS: You | Aurora: You**

Security group configuration is entirely your responsibility. AWS provides the firewall mechanism - you write the rules. Which source IPs or security groups can connect on port 5432 is your decision. A misconfigured security group (like 0.0.0.0/0) is your mistake, not AWS's. Same for both RDS and Aurora.

---

### Task 11: Managing Database User Accounts and Passwords
**RDS: You | Aurora: You**

Database users, roles, passwords, and privilege grants inside PostgreSQL are your responsibility. AWS manages the infrastructure and the master user credential during creation. After that, creating application users, granting permissions, enforcing password policies, and revoking access when people leave - all yours. AWS does not audit your GRANT statements.

---

### Task 12: Monitoring CPU and Memory Usage
**RDS: Shared | Aurora: Shared**

AWS automatically collects and publishes CloudWatch metrics for CPU, memory, storage, and connections. That part is automatic. You are responsible for creating alarms on those metrics, defining thresholds, setting up notification channels (SNS topics), and actually responding when an alarm fires. AWS gives you the data - you must watch it and act on it.

---

### Task 13: Scaling Storage When the Database Grows
**RDS: Shared | Aurora: AWS (mostly)**

This is where RDS and Aurora differ significantly.

- **RDS:** You can enable storage autoscaling, but you must set a maximum threshold. If autoscaling is off, you must manually increase storage via a modification. Large storage changes can take time and may briefly affect performance.
- **Aurora:** Storage scales automatically in 10 GB increments up to 128 TB with no action from you. You do not provision storage or set a maximum. Aurora's storage grows and shrinks based on actual data usage. This is one of Aurora's key operational advantages.

---

### Task 14: Tuning PostgreSQL Parameters
**RDS: You | Aurora: You**

Parameter group configuration is your responsibility. AWS provides default parameter groups, but they are generic. Tuning work_mem, shared_buffers, effective_cache_size, max_connections, and other parameters for your specific workload is your job. You must create a custom parameter group, adjust the values, and associate it with your instance. AWS will not tune your database for you.

---

### Task 15: Encrypting Data at Rest
**RDS: Shared | Aurora: Shared**

AWS provides the encryption feature (using KMS) and handles the actual encryption/decryption. You must enable it at instance creation time - for RDS, it is not enabled by default. Aurora encrypts new clusters by default, but you still choose the KMS key. Once enabled, AWS manages key rotation and encryption operations transparently. The decision to encrypt is yours; the execution of encryption is AWS's.

---

### Task 16: Repairing Storage-Level Data Corruption
**RDS: AWS | Aurora: AWS**

Physical storage integrity is AWS's responsibility. For RDS, EBS volumes use checksums and replication. For Aurora, the distributed storage layer is designed to detect and self-heal block-level corruption automatically using its six data copies. You will not see this event and you do not need to take any action. This is infrastructure integrity - AWS's domain.

---

### Task 17: Fixing Logical Data Corruption from a Bad Deploy
**RDS: You | Aurora: You**

If your application writes bad data (wrong values, missing records, broken relationships), that is your problem. The database engine executed valid SQL commands correctly. AWS cannot distinguish between correct and incorrect business data. You must identify the bad data, determine the time window, potentially use PITR to restore a clean copy, and fix the application bug. Same for both services.

---

### Task 18: Rotating SSL/TLS Certificates
**RDS: Shared | Aurora: Shared**

AWS generates and rotates the RDS/Aurora CA certificates and publishes new certificates with months of advance notice. You must update your application's trusted certificate bundle before the old one expires and restart connections that pin to the old certificate. If your application uses sslmode=verify-full, it will stop connecting if you do not update the CA bundle. AWS provides the certificate - you update your application to trust it.

---

### Task 19: Creating and Managing Read Replicas
**RDS: You | Aurora: You**

You decide how many read replicas to create, which instance types to use, and how to route read traffic to them. AWS provides the replication mechanism and manages the infrastructure, but the architecture decisions are yours. Aurora makes this easier (replicas share storage, so creation is faster and lag is lower), but you still initiate the creation and manage the routing.

---

### Task 20: Running VACUUM to Reclaim Dead Row Space
**RDS: Shared | Aurora: Shared**

AWS enables autovacuum by default on both RDS and Aurora. Autovacuum runs automatically based on thresholds in the parameter group. However, you are responsible for monitoring whether autovacuum is keeping up with your write workload, tuning autovacuum parameters if it falls behind, and running manual VACUUM on heavily-written tables when needed. AWS provides the mechanism - you ensure it works for your specific workload.

</details>

---

## Scoring Rubric

After checking your answers, score yourself:

| Points | Criteria |
|--------|----------|
| 1 point | Correct classification (AWS, You, or Shared) for each task |
| 0.5 points | Partially correct (e.g., said "You" when the answer is "Shared" but explained the split correctly) |
| 0 points | Incorrect classification |
| Bonus: +1 point each | Correctly identified where RDS and Aurora classifications differ (Tasks 13 and 15) |

| Score | Level | Assessment |
|-------|-------|------------|
| 18-22 | Excellent | You understand the responsibility model clearly. Ready for production work. |
| 14-17 | Good | Solid foundation. Review the Shared tasks - that is where most teams get confused. |
| 10-13 | Needs Review | Re-read the BUILD guide on shared responsibility. Focus on the boundary between AWS tools and your configuration of those tools. |
| Below 10 | Start Over | The shared responsibility model is foundational. Go through the BUILD guide again and pay attention to who acts versus who decides. |

---

## Summary of Key Takeaways

- The responsibility boundary is at the engine level: AWS owns everything below it (hardware, OS, engine process), you own everything above it (schema, data, queries, users).
- "AWS manages it" means AWS keeps the infrastructure running. It does not mean AWS makes decisions for you about how to use it.
- Several tasks are Shared - AWS provides the tool, you must enable, configure, and monitor it. Backups, encryption, monitoring, and patching all follow this pattern.
- The biggest RDS vs Aurora difference in responsibility is storage scaling. Aurora handles it automatically. RDS requires your configuration.
- Logical data integrity (your data being correct) is always your responsibility, regardless of service. AWS guarantees physical integrity only.
