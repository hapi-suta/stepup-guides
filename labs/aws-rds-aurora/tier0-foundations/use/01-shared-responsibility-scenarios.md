# Exercise 01: Shared Responsibility Scenarios

**Duration:** 20 minutes
**Objective:** Classify real-world database incidents and tasks under the AWS shared responsibility model, including tricky edge cases where responsibility is split or ambiguous.
**Prerequisites:** Build guide 01 (Shared Responsibility Model) complete

---

## Background

You are a DBA at [COMPANY]. Your manager has asked you to document which team owns what when something goes wrong or when routine maintenance is needed. The cloud team and the application team keep pointing fingers at each other, so you need a clear reference.

Below are 10 scenarios. For each one, classify it as:

- **AWS** - AWS owns this and handles it automatically
- **You** - Your team (DBA/ops/app) owns this
- **Shared** - Both parties have a role; describe each party's portion

Take a few minutes to think through each one before checking the answers.

---

## Task 1: Classify Each Scenario

**Business question:** Which team is responsible for each of these situations?

**Requirements:**
- Classify each scenario as AWS, You, or Shared
- For Shared scenarios, briefly describe what each party owns
- Flag any scenarios where the answer depends on how the database was configured

---

### Scenario 1
A security vulnerability is discovered in the PostgreSQL engine (e.g., CVE-2024-XXXX). The patch is available.

---

### Scenario 2
A developer runs `DROP TABLE orders;` in production by mistake. The table is gone.

---

### Scenario 3
The physical disk on the server hosting your RDS instance fails.

---

### Scenario 4
Your application is running slow queries. Response times have climbed from 20ms to 4 seconds over the past week.

---

### Scenario 5
Aurora storage silently corrupts a data block at the storage layer due to a hardware fault.

---

### Scenario 6
Your database has logical data corruption - a bug in your application wrote invalid values to a column for the past 3 days.

---

### Scenario 7
Your RDS instance runs out of storage space and connections start failing.

---

### Scenario 8
The AWS availability zone your RDS instance is in goes down for 2 hours.

---

### Scenario 9
SSL/TLS certificates on your RDS instance are expiring. Applications will stop connecting if they expire.

---

### Scenario 10
A user account in your database has been granted excessive privileges and now poses a security risk.

---

## Task 2: The Tricky One

**Business question:** Which of the 10 scenarios above is most commonly misunderstood by teams new to RDS?

Write 2-3 sentences explaining why that scenario causes confusion and what the correct mental model is.

---

## Answers

### Scenario 1 - Security Patch on PostgreSQL Engine
**Classification: Shared**

- **AWS owns:** Applying the OS-level patch, the actual engine binary update, and the patching mechanism itself. AWS will release a new minor version and make it available.
- **You own:** Scheduling the maintenance window, testing the patch in non-production first, deciding when to apply it (manual vs. auto minor version upgrade), and validating your application still works after.

Key point: AWS does not force patches onto your instance without your participation unless it is a critical security emergency. You control the maintenance window and the upgrade timeline.

---

### Scenario 2 - Developer Drops a Table
**Classification: You**

AWS has no way to know that `DROP TABLE` was a mistake vs. intentional. The database engine executed a valid SQL command. AWS's job is to run the engine reliably - it did.

Your team owns: backup strategy, point-in-time recovery (PITR) execution, access controls that allowed a developer to run DDL in production, and whatever process failed to prevent this.

Note: AWS does give you the tools (automated backups, PITR, snapshots) - but whether those tools are configured correctly and whether you use them is your responsibility.

---

### Scenario 3 - Physical Disk Failure
**Classification: AWS**

Hardware failure is entirely AWS's responsibility. RDS runs on managed infrastructure. If a disk fails, AWS replaces it. With Multi-AZ, the standby takes over automatically. You may see a brief blip in connectivity, but you do not file a hardware ticket, you do not replace the drive, and you do not rebuild the RAID.

Your only action: monitor your application for the failover event and ensure your connection retry logic handles it.

---

### Scenario 4 - Slow Queries
**Classification: You**

AWS keeps the engine running. What runs inside the engine is your domain. Slow queries are caused by missing indexes, bad query plans, schema design issues, or application-level problems - none of which AWS controls or monitors on your behalf.

Your team owns: query analysis (pg_stat_statements, EXPLAIN ANALYZE), index strategy, schema design, connection pooling, and any parameter group tuning needed.

---

### Scenario 5 - Aurora Storage Corruption at Hardware Layer
**Classification: AWS**

This is one of Aurora's key selling points. Aurora's distributed storage layer is designed to detect and self-heal block-level corruption automatically. AWS replicates data across 6 copies in 3 AZs and uses checksums to detect bad blocks. If a block is corrupt, Aurora reconstructs it from the other copies without any action from you.

You will not see this event. You do not need to restore from backup.

---

### Scenario 6 - Logical Data Corruption from Application Bug
**Classification: You**

Aurora or RDS cannot distinguish between valid data and data that is "wrong" by your business rules. The database wrote exactly what your application told it to write. The engine functioned correctly.

Your team owns: identifying the bad data, writing correction scripts, using PITR or snapshots to restore a clean copy if needed, and fixing the application bug that caused the problem.

This is the most important distinction in the model: AWS protects against hardware/infrastructure failure. It does not protect against what your application does to your data.

---

### Scenario 7 - Running Out of Storage
**Classification: Shared**

- **AWS owns:** Providing the storage expansion feature (storage autoscaling) and the underlying infrastructure to expand it.
- **You own:** Enabling storage autoscaling (it is off by default on some configurations), setting the maximum storage threshold, monitoring free storage via CloudWatch, and planning capacity ahead of time.

If autoscaling is enabled and you set appropriate thresholds, AWS handles the expansion automatically. If you did not configure it, your instance will stop accepting writes when storage is full - and that is on you.

---

### Scenario 8 - Availability Zone Outage
**Classification: Shared**

- **AWS owns:** The AZ infrastructure failure itself and the automatic failover mechanism (for Multi-AZ deployments).
- **You own:** Whether you enabled Multi-AZ in the first place. A single-AZ RDS instance will be completely unavailable during an AZ outage, and that is an architecture decision you made. AWS provides the capability; you decide whether to use it.

If you have Multi-AZ enabled, AWS handles the failover. If you do not, you wait for the AZ to recover.

---

### Scenario 9 - SSL/TLS Certificate Expiration
**Classification: Shared**

- **AWS owns:** Rotating the RDS CA certificate and making the new certificate available.
- **You own:** Updating your application's trusted CA bundle to include the new certificate before the old one expires, testing the connection, and completing the rotation before the deadline. AWS provides documentation and advance notice (usually months).

AWS will not push the new certificate into your application. If your app only trusts the old CA, it will fail to connect after rotation.

---

### Scenario 10 - Excessive Database User Privileges
**Classification: You**

User accounts, roles, and privileges inside the PostgreSQL engine are your responsibility. AWS manages the infrastructure and the engine process. What happens inside the database - who can read what, who has SUPERUSER, which roles exist - is entirely your domain.

AWS does not audit your GRANT statements or alert you when a user has too much access. CloudTrail logs API calls to AWS (like who created the instance), but it does not log SQL-level permission changes.

---

## Task 2 Answer - Most Commonly Misunderstood Scenario

**Scenario 6 (logical data corruption) is most commonly confused with Scenario 5 (storage-level corruption).**

Teams that are new to managed databases often assume that because "AWS manages the database," AWS is responsible for data integrity in all forms. The correct mental model is a clear separation between infrastructure integrity (AWS's job) and data correctness (your job). AWS guarantees that the bits written to storage are the bits read back. It makes no guarantee about whether those bits represent valid business data.

---

## Summary of Key Takeaways

- The shared responsibility model splits at the engine boundary: AWS owns everything below it (hardware, OS, engine process), you own everything above it (schema, data, queries, users, backups usage).
- "AWS manages it" does not mean "AWS fixes it when something goes wrong inside the database." It means AWS keeps the infrastructure running.
- Features like Multi-AZ, storage autoscaling, and PITR are tools AWS provides. Whether you configure and use them is your responsibility.
- Logical errors (bad data, dropped tables, wrong permissions) are always your responsibility regardless of which managed service you use.
- Storage-level integrity (bit rot, hardware failure, AZ outage) is AWS's responsibility when you use managed services like RDS and Aurora.
