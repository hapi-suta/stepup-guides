# Interview Questions - Tier 1: Provisioning and Connectivity
## AWS RDS and Aurora PostgreSQL

50 questions covering all five Tier 1 topics.
Graduated by level: Junior | Mid | Senior | Principal

---

## How to Use This Guide

Read the question. Formulate your answer without reading the hint. Then compare your answer to "What they're looking for" and "Strong answer".

If your answer misses key points, go back to the relevant Build guide and re-read that section.

---

## Topic T1.1 - Creating an RDS PostgreSQL Instance

---

### Q1 (Junior)

**Question:** What is Amazon RDS and why would you use it instead of running PostgreSQL on an EC2 instance?

**What they're looking for:**
Understanding of managed vs self-managed services. The candidate should name concrete things AWS handles.

**Strong answer:**
RDS is AWS's managed relational database service. Instead of provisioning an EC2 instance, installing PostgreSQL, configuring storage, setting up backups, and patching the OS yourself, AWS handles all of that. You just create a database instance and connect to it. The main reasons to use RDS over a self-managed PostgreSQL on EC2 are: automated backups and point-in-time recovery, automated OS and engine patching, Multi-AZ failover without manual setup, and monitoring through CloudWatch without extra agent installation. The trade-off is that you give up OS-level access - you cannot SSH into the host, install custom extensions, or run OS commands. For most teams that trade-off is worth it.

---

### Q2 (Junior)

**Question:** You are creating an RDS PostgreSQL instance for a new development environment. Walk me through the decisions you make before clicking "Create".

**What they're looking for:**
Awareness of the key settings: instance class, storage, VPC/subnet group, security group, parameter group, public access.

**Strong answer:**
Before creating the instance I decide on: (1) instance class - for dev I would use `db.t3.micro` or `db.t3.small` since cost matters more than performance; (2) storage - gp3 at 20 GB minimum, no extra IOPS needed for dev; (3) VPC and subnet group - which VPC to place it in, making sure the subnet group covers at least 2 AZs; (4) security group - a new SG with an inbound rule on port 5432, locked to the dev team's IPs or a VPN CIDR; (5) public access - for dev, yes public access so developers can connect from their laptops directly; (6) parameter group - either the default or a custom one if we need specific PostgreSQL settings; (7) initial database name - create one at launch so developers have something to connect to immediately; (8) Multi-AZ - no for dev, costs double; (9) backups - minimal, maybe 1-day retention. For prod I would revisit all of these with different answers.

---

### Q3 (Mid)

**Question:** What is a DB Subnet Group and why is it required?

**What they're looking for:**
Understanding that RDS is placed inside a VPC, subnet groups define where, and they require multi-AZ coverage.

**Strong answer:**
A DB Subnet Group is a collection of subnets within a VPC that RDS uses to decide where to place your database instance. It is required for two reasons. First, RDS needs to know which network segment to place the instance in. Without a subnet group, RDS cannot determine the network configuration. Second, AWS requires the subnet group to include subnets in at least two Availability Zones. This is because Multi-AZ deployments need to place the primary and standby in different AZs, and even Single-AZ instances need the group to be multi-AZ-capable for future flexibility. In practice you create the subnet group once per VPC, include all your private subnets, and reuse it for all RDS instances in that VPC.

---

### Q4 (Mid)

**Question:** Explain the difference between the Console's "Standard create" and "Easy create" options. When would you use each?

**What they're looking for:**
Understanding that Easy create hides options and applies defaults. Standard create exposes everything. Production needs Standard create.

**Strong answer:**
Easy create hides most configuration options and applies AWS-recommended defaults for instance class, storage, backups, and security. It is useful for quickly spinning up a throwaway instance for testing or learning without needing to know every setting. Standard create exposes every configuration option, which is what you need for production. In production you need control over the VPC, subnet group, security group, parameter group, encryption key, backup window, maintenance window, and monitoring settings. I always use Standard create so I understand exactly what is being created and can reproduce it with infrastructure as code. Easy create is for demos and quick experiments only.

---

### Q5 (Senior)

**Question:** A junior engineer asks: "We are using Terraform to create our RDS instances. Do we still need to use the Console or CLI?" How do you answer?

**What they're looking for:**
Understanding of IaC and its relationship to the Console/CLI. Also: understanding when you still need the Console (troubleshooting, monitoring) even with IaC.

**Strong answer:**
For creating and modifying infrastructure, Terraform is the right tool and they should not use the Console or CLI for those operations. Changing things outside of Terraform creates "drift" - the real infrastructure no longer matches the Terraform state, which causes problems the next time Terraform runs. However, the Console and CLI are still used for: (1) reading - checking instance status, viewing CloudWatch metrics, reading logs, examining security group rules; (2) troubleshooting - when something is wrong, you diagnose it interactively with the CLI; (3) emergency response - if Terraform is unavailable (pipeline down, permission issue), you may need the CLI to make a critical fix. The rule I follow: use Terraform for changes, use Console/CLI for observation and diagnosis.

---

### Q6 (Senior)

**Question:** What happens at the infrastructure level when you create an RDS PostgreSQL instance?

**What they're looking for:**
Understanding that RDS is EC2 + EBS under the hood, plus DNS registration, parameter group application, and the "available" state meaning PostgreSQL is listening.

**Strong answer:**
When you submit a CreateDBInstance API call, AWS: (1) selects a physical host in the Availability Zone you specified (or AWS chooses one within your subnet group); (2) provisions an EBS volume of the size and type you requested and attaches it to the host; (3) installs and starts the PostgreSQL engine on the host; (4) applies the parameter group settings (some settings require a restart, which happens automatically during creation); (5) registers a DNS entry mapping your endpoint hostname to the private (and optionally public) IP of the instance; (6) applies the security groups as a virtual firewall; (7) creates the master user and initial database if specified; (8) marks the instance as "available" when PostgreSQL is accepting connections. The entire process takes 5-10 minutes because provisioning and formatting EBS storage takes time, and PostgreSQL initialization takes time. You cannot SSH into the host because it is managed by AWS - you only interact with PostgreSQL through the network.

---

### Q7 (Principal)

**Question:** Your company wants to provision RDS instances for 50 development teams, each in their own AWS account. What is your approach?

**What they're looking for:**
Multi-account strategy, IaC, AWS Organizations, Service Control Policies, standardization vs autonomy.

**Strong answer:**
I would use an AWS Organizations structure with a Landing Zone approach. Each team account would have guardrails via Service Control Policies - for example, SCPs that prevent creating RDS instances outside approved regions, or that enforce certain tags for cost attribution. I would provide a Terraform module in an internal registry that teams use to create RDS instances. The module encodes our standards: approved instance classes, required tags, mandatory encryption, minimum backup retention, CloudWatch alarm setup. Teams call the module with their specific inputs (instance name, size, VPC ID) and get a compliant RDS instance. They cannot create non-compliant infrastructure because the module is the only approved path and the SCPs block manual creation of non-compliant resources. A baseline CloudWatch dashboard and alerting would be provisioned automatically by the module. This gives teams autonomy within guardrails and keeps the DBA team's standards consistent across all 50 accounts.

---

### Q8 (Principal)

**Question:** You need to migrate a 5 TB PostgreSQL database from on-premises to RDS with no more than 30 minutes of downtime. Describe your approach.

**What they're looking for:**
AWS DMS, logical replication, cutover planning. The candidate should not say "just use pg_dump" for 5 TB - that would cause hours of downtime.

**Strong answer:**
For a 5 TB database with a 30-minute downtime constraint, a dump/restore approach is out of the question - it would take many hours. The approach is: (1) set up the RDS target instance and tune it for the migration (increase max_connections, set checkpoint_timeout high, disable autovacuum temporarily); (2) use AWS Database Migration Service (DMS) or logical replication to stream changes from the source database continuously; (3) during the streaming phase (which runs for days), the source database is fully operational; (4) monitor replication lag daily - wait until lag is under 5 seconds consistently; (5) schedule the cutover window (the 30 minutes); (6) during cutover: stop writes on the source (put the app in maintenance mode or take a brief read-only mode), let replication catch up to zero lag, verify row counts match on key tables, update the app's database endpoint to the RDS instance, restart the app, verify functionality; (7) monitor closely for the first hour. The key risk is any source database feature not supported by RDS (custom C extensions, OS-level file reads) which must be addressed before migration.

---

### Q9 (Junior)

**Question:** How long does it take for an RDS instance to become available after you click "Create"? What should you do while waiting?

**What they're looking for:**
5-10 minutes understanding. During the wait: note down credentials, document the endpoint, review security group settings.

**Strong answer:**
Creating an RDS instance typically takes 5 to 10 minutes. During that time the status shows "creating". While waiting, I would: (1) make sure I saved the master password securely - the Console only shows it once during creation; (2) note down the subnet group and security group IDs for documentation; (3) go check the security group and confirm the inbound rules are correct before I need them; (4) prepare my psql connection command so I am ready the moment the instance is available; (5) if this is production, add the endpoint and credentials to the secrets management system now. I use `aws rds wait db-instance-available` in scripts so the script automatically pauses and resumes when ready.

---

### Q10 (Mid)

**Question:** What is the difference between the RDS master user and a PostgreSQL superuser?

**What they're looking for:**
rds_superuser vs superuser distinction. What is blocked on RDS and why.

**Strong answer:**
A true PostgreSQL superuser can do absolutely anything: read password hashes from pg_shadow, load custom C extensions, read arbitrary OS files with pg_read_file(), and bypass all security checks. AWS does not grant this to RDS users because true superuser access could be used to break things AWS needs to manage - for example, modifying the RDS agent configuration or reading host-level files. Instead, the RDS master user is a member of `rds_superuser`, which has almost all superuser privileges: creating databases, creating users, granting any privilege, using pg_stat_statements, managing replication slots, and installing approved extensions. For 99% of DBA work, rds_superuser is sufficient. The restrictions you notice are: you cannot read pg_shadow, you cannot install arbitrary C extensions (only those in the approved list), and you cannot run functions that read the OS filesystem. These are acceptable trade-offs for the managed service model.

---

## Topic T1.2 - Instance Classes and Storage Types

---

### Q11 (Junior)

**Question:** What is the difference between db.t3, db.m6g, and db.r6g instance classes? How do you decide which to use?

**What they're looking for:**
T = burstable (credits), M = general purpose, R = memory optimized. Clear use-case guidance.

**Strong answer:**
The T family (db.t3.micro, db.t3.small, etc.) uses a CPU credit model. The instance has a baseline CPU percentage and earns credits when idle. When busy, it uses those credits to burst above baseline. If credits run out, the CPU is throttled. T instances are for development, testing, and low-traffic applications where the database is mostly idle. The M family (db.m6g.large, etc.) gives consistent full CPU - no credit system. These are the most common production instances for OLTP workloads with steady CPU demand. The R family (db.r6g.large, etc.) has more RAM per vCPU than M instances - typically 2x. Use R instances when the working set of your database does not fit in RAM, causing excessive disk I/O, or when you have high connection counts that consume a lot of RAM per connection. In short: dev/test = T, production general-purpose = M, production data-heavy or RAM-bound = R.

---

### Q12 (Junior)

**Question:** What does the `g` mean in db.m6g? Should you choose Graviton by default?

**What they're looking for:**
Graviton = ARM64. Yes, choose by default for new instances. Understand that it is ~20% cheaper with equal or better performance.

**Strong answer:**
The `g` means the instance runs on AWS Graviton, which is AWS's custom ARM64 processor. Graviton instances (db.m6g, db.r6g, db.t4g) are generally 20% cheaper than their Intel equivalents (db.m6i, db.r6i, db.t3) while delivering equal or better performance for PostgreSQL workloads. For any new RDS instance, I choose Graviton by default. The only reason not to is if you have a dependency on x86-specific behavior, which is extremely rare in PostgreSQL since PostgreSQL handles architecture differences internally. Your application code runs on your own servers, not on the RDS instance, so the ARM architecture is invisible to your application.

---

### Q13 (Mid)

**Question:** Explain the difference between gp3 and gp2 storage. Why should you use gp3 for new instances?

**What they're looking for:**
gp3 decouples IOPS from storage size. gp3 includes 3,000 IOPS. gp3 is cheaper for most workloads.

**Strong answer:**
gp2 was the previous generation. With gp2, IOPS were tied to storage size at 3 IOPS per GB. So a 100 GB gp2 volume got 300 IOPS, and to get 3,000 IOPS you needed a 1 TB volume even if your data only needed 100 GB. gp3 breaks this link. You get 3,000 IOPS and 125 MB/s throughput included in the base price regardless of volume size, and you can independently provision additional IOPS (up to 64,000) and throughput (up to 1,000 MB/s) without increasing storage size. For most workloads, gp3 is both cheaper and more flexible than gp2. For a new instance, always choose gp3.

---

### Q14 (Mid)

**Question:** A customer reports their PostgreSQL database is "slow". You check CloudWatch and see CPUUtilization at 15%, FreeableMemory at 50 MB out of 8 GB, and ReadLatency at 80ms. What is the likely root cause and what would you change?

**What they're looking for:**
Low FreeableMemory means the working set is spilling to disk. High ReadLatency confirms it. Recommendation: bigger R-family instance for more RAM.

**Strong answer:**
The CPU at 15% rules out a CPU bottleneck. FreeableMemory at 50 MB on an 8 GB instance means the system is using 99.4% of RAM - almost none is available for the OS page cache or additional shared_buffers caching. PostgreSQL relies heavily on the OS page cache. When data cannot fit in cache, it must be read from EBS, which is what's causing the 80ms ReadLatency (EBS reads are measured in milliseconds; cache reads are sub-millisecond). The fix is to move to an R-family instance with more RAM. For example, if the current instance is `db.m6g.xlarge` (4 vCPU, 16 GB RAM) and 8 GB is used for the OS + PostgreSQL internal structures, switching to `db.r6g.xlarge` (4 vCPU, 32 GB RAM) doubles the available RAM and allows a much larger cache. Alternatively, check `shared_buffers` in the parameter group - it may need to be increased to use more RAM.

---

### Q15 (Mid)

**Question:** What is io2 storage and when should you use it over gp3?

**What they're looking for:**
io2 for > 64,000 IOPS or 99.999% durability requirement. gp3 is the default; io2 is for demanding workloads.

**Strong answer:**
io2 (and its more powerful variant io2 Block Express) provides provisioned IOPS up to 256,000 with a very high storage durability of 99.999%. I use io2 in two scenarios: when the workload requires more than 64,000 IOPS (which is the maximum gp3 supports), or when the application requires the 99.999% durability guarantee for regulatory or business continuity reasons. io2 also has a much better IOPS-to-storage ratio: up to 500 IOPS per GB compared to gp3 which does not tie IOPS to storage at all (you can mix and match). For most production PostgreSQL workloads, gp3 with additional provisioned IOPS is the right choice and more cost-effective. io2 is for financial databases, high-frequency trading systems, or any workload with extreme IOPS requirements.

---

### Q16 (Senior)

**Question:** You are reviewing a production RDS instance and notice the BurstBalance metric is consistently at 0%. What are the implications and what should you do?

**What they're looking for:**
0% BurstBalance on a T instance means CPU is throttled to baseline. This is a sustained performance problem. Solution: upgrade to M family.

**Strong answer:**
A T-family instance at 0% BurstBalance means the instance has exhausted its CPU credits and is now throttled to the baseline CPU percentage (which is 10-40% depending on the exact instance class). Any CPU-intensive operation (index builds, large queries, autovacuum) is being artificially slowed. This manifests as high latency, slow query times, and query timeouts. The solution is to change the instance class from the T family to the M family. The equivalent M instance for a `db.t3.large` is `db.m6g.large` - same vCPU count, slightly less RAM, but full consistent CPU with no credit system. There is a short-term workaround called "T3 Unlimited" mode where the instance runs above baseline and you pay per-vCPU-hour for the extra credit usage, but for a sustained workload this becomes more expensive than just using an M instance. Use M instances for any production workload with consistent CPU demand.

---

### Q17 (Senior)

**Question:** You have a 2 TB io1 volume with 10,000 IOPS provisioned. You are paying $1,500/month for storage. You notice the actual peak IOPS usage is 6,000. How can you save money?

**What they're looking for:**
Migrate from io1 to gp3. Calculate the cost difference. gp3 at 6,000 IOPS is cheaper than io1 at 10,000 IOPS.

**Strong answer:**
Migrating from io1 to gp3 would save significant money here. Let me calculate. The io1 cost: 2,000 GB at $0.125/GB = $250/month storage, plus 10,000 IOPS at $0.10/IOPS = $1,000/month IOPS, total $1,250/month (plus instance cost). For gp3 to match 6,000 IOPS (the actual peak usage): 2,000 GB at $0.115/GB = $230/month, the first 3,000 IOPS are free, additional 3,000 IOPS at $0.006/IOPS = $18/month, throughput at the default 125 MB/s is included. Total gp3 cost: $248/month for storage+IOPS - a saving of roughly $1,000/month compared to the io1 configuration. I would validate the storage migration during a maintenance window. The modification is online and AWS handles the data migration. I would also monitor IOPS closely after the change and provision more if needed.

---

### Q18 (Junior)

**Question:** What is storage autoscaling on RDS? Should you enable it?

**What they're looking for:**
Autoscaling expands storage automatically when it gets close to full. Yes, enable it in production. Set a sensible max.

**Strong answer:**
Storage autoscaling automatically increases the allocated storage of an RDS instance when free space gets low. Specifically, AWS expands the storage when: free space is less than 10% of total, the low free space condition has lasted at least 5 minutes, and the instance has not been scaled in the last 6 hours. You set a maximum allocation limit when enabling it. I enable storage autoscaling on all production instances because a full storage volume causes the database to go read-only, which is a bad outage. The only configuration decision is the maximum size - set it to 2x to 3x the current allocated storage. The downside: once storage is expanded, you cannot shrink it. But that is a minor concern compared to the risk of a storage-full outage.

---

### Q19 (Mid)

**Question:** How do you modify an RDS instance class without causing downtime?

**What they're looking for:**
Multi-AZ instances can be changed with minimal downtime (30-60 second failover). Single-AZ causes 2-5 minutes of downtime. Apply immediately vs maintenance window.

**Strong answer:**
For a Single-AZ instance, modifying the instance class causes a brief outage of 2-5 minutes because the host needs to restart with a new configuration. For a Multi-AZ instance, AWS applies the change to the standby first (no downtime), then performs a failover (typically 30-60 seconds of downtime), and then the old primary becomes the new standby and gets the new configuration. So for minimal impact, I would: (1) ensure Multi-AZ is enabled before starting; (2) schedule the change during a low-traffic window; (3) use `--apply-immediately` if it is urgent or schedule it for the next maintenance window if it is not; (4) have the application retry database connections on failure since the endpoint DNS will still work but existing connections will be dropped during the failover. For a scheduled change, I also inform the team about the expected brief outage.

---

### Q20 (Junior)

**Question:** You create a db.t3.micro instance. The next day, queries start timing out. You check CloudWatch and see BurstBalance dropping to 10%. What is happening?

**What they're looking for:**
CPU credits are being consumed by sustained activity. Once credits run out, CPU throttles to baseline (10% for t3.micro). Queries queue up and time out.

**Strong answer:**
The database is running out of CPU credits. A `db.t3.micro` has a baseline CPU of 10% - it can only sustain that level indefinitely. During light load it earns credits, and during bursts it spends them. When BurstBalance hits 10%, the instance is almost out of credits. Once credits hit 0%, the CPU is throttled back to 10% baseline. At baseline, even moderately complex queries will be slow because the CPU cannot process them quickly enough. The queries queue up, exceed their timeout, and fail. Short-term fix: check if there is a long-running query or unexpected heavy load (check pg_stat_activity). Longer term: if the workload is consistently consuming credits, this instance is undersized and should be upgraded to `db.t3.small` (20% baseline) or an M-family instance.

---

## Topic T1.3 - Aurora PostgreSQL Clusters

---

### Q21 (Junior)

**Question:** What is the difference between Amazon Aurora PostgreSQL and standard RDS PostgreSQL?

**What they're looking for:**
Same wire protocol, different internal architecture. Aurora has 6-copy distributed storage, faster replication, faster failover, up to 15 replicas.

**Strong answer:**
Aurora PostgreSQL and standard RDS PostgreSQL both speak the same PostgreSQL wire protocol - your psql client, drivers, and SQL are the same. The difference is the internal architecture. Standard RDS PostgreSQL runs the official PostgreSQL engine on an EBS volume. Aurora replaces the storage engine with AWS's own distributed storage system. Aurora automatically writes 6 copies of your data across 3 Availability Zones. You do not configure this. The benefits: Aurora supports up to 15 read replicas (vs 5 for RDS), replication lag is typically under 100ms because replication happens at the storage layer (not through sending WAL over the network), failover takes under 30 seconds (vs 60-120 seconds for standard RDS Multi-AZ), and the maximum storage is 128 TB (vs 64 TB for RDS). The trade-offs: Aurora costs about 20% more, does not always support the absolute latest PostgreSQL minor versions, and you cannot stop an Aurora cluster as easily as a standard RDS instance.

---

### Q22 (Junior)

**Question:** In an Aurora PostgreSQL cluster, what is the difference between the cluster endpoint, the reader endpoint, and instance endpoints?

**What they're looking for:**
Cluster endpoint = always points to current writer. Reader endpoint = load-balances reads across all readers. Instance endpoint = one specific instance.

**Strong answer:**
The cluster endpoint (also called the writer endpoint) is a DNS name that always resolves to the current writer instance. If the writer fails and Aurora promotes a reader, the cluster endpoint is automatically updated to point to the new writer within seconds. This is the endpoint your application uses for write operations. The reader endpoint is a DNS name that load-balances connections across all reader instances. If you have 3 readers, each new connection through the reader endpoint gets distributed across them. This is the endpoint your application uses for read-only queries. Instance endpoints point to one specific instance and never change unless the instance is replaced. Use instance endpoints when you need to do maintenance on a specific instance or when troubleshooting a specific node. Applications should almost never use instance endpoints directly.

---

### Q23 (Mid)

**Question:** How does replication work in Aurora PostgreSQL? Why is the replication lag typically lower than standard RDS replicas?

**What they're looking for:**
Storage-level replication vs WAL streaming. Aurora readers share the same storage layer, so "replication" is almost zero-latency.

**Strong answer:**
Standard RDS read replicas work by sending WAL (Write-Ahead Log) records from the primary to replicas over the network, where the replica applies them to its own copy of the database. This can lag by seconds or more depending on network latency, the size of transactions, and replica load. Aurora uses a fundamentally different approach. All instances in an Aurora cluster - both writer and readers - share the same underlying distributed storage. When the writer commits a transaction, it writes to that shared storage. Readers pick up the change almost immediately because they are reading from the same storage. The "replication" is really just the readers updating their in-memory buffer caches to reflect what is already on disk. This is why Aurora replication lag is typically under 100 milliseconds and often under 20 milliseconds. The Aurora replica is not waiting for WAL records to arrive - the data is already on disk and the replica just needs to apply it to its cache.

---

### Q24 (Mid)

**Question:** You have an Aurora cluster with the writer in us-east-1a and two readers in us-east-1b and us-east-1c. The writer instance fails. What happens next?

**What they're looking for:**
Aurora detects the failure, promotes the reader with the lowest PromotionTier (or random if equal tiers), updates the cluster endpoint DNS, all within ~30 seconds.

**Strong answer:**
Aurora's monitoring detects that the writer is unresponsive within seconds. Aurora then promotes one of the readers to be the new writer. The reader that gets promoted is determined by the PromotionTier setting - the reader with tier 1 (lowest number = highest priority) is promoted first. If multiple readers share the same tier, Aurora picks one at random. The promotion process takes 10-30 seconds. During this time, the cluster endpoint temporarily does not resolve to any healthy writer. After promotion, the cluster endpoint DNS record is updated to point to the newly promoted instance. The old readers continue as readers with the new writer. Your application's connection to the old writer is dropped when the failure happens - the application needs to reconnect, at which point the cluster endpoint directs it to the new writer. This is why applications should implement connection retry logic and not cache the resolved IP of the cluster endpoint.

---

### Q25 (Mid)

**Question:** How do you verify that you are connected to the Aurora writer vs a reader?

**What they're looking for:**
pg_is_in_recovery() returns false on writer, true on reader. Also aurora_replica_status() for Aurora-specific status.

**Strong answer:**
Run this query after connecting: `SELECT pg_is_in_recovery();`. If it returns `f` (false), you are connected to the writer. If it returns `t` (true), you are on a reader. The reason: `pg_is_in_recovery()` is a standard PostgreSQL function that returns true when the instance is in recovery mode (replaying WAL or storage-level changes). Readers are always in recovery mode. You can also use `inet_server_addr()` to get the IP of the instance you are connected to and cross-reference it with the instance endpoints. For Aurora-specific details, you can query `SELECT * FROM aurora_replica_status()` to see all cluster members, their roles, and the replication lag.

---

### Q26 (Senior)

**Question:** When should you choose Aurora Serverless v2 instead of a regular Aurora cluster?

**What they're looking for:**
Serverless v2 for unpredictable or variable workloads. Regular Aurora for consistent high-load workloads. Understand ACU scaling.

**Strong answer:**
Aurora Serverless v2 automatically scales compute capacity in Aurora Capacity Units (ACUs) between a minimum and maximum you define, in increments as small as 0.5 ACU. This makes it ideal for: (1) unpredictable workloads where you do not know how much compute you need - it scales up in seconds when load increases and scales down when idle; (2) development environments where the database is idle most of the time but needs to handle full production-like load during testing; (3) multi-tenant SaaS applications where each tenant's database is rarely under load simultaneously. A regular Aurora provisioned cluster is better when: you have consistent high load (provisioned instances handle sustained load more cheaply than Serverless scaling); you need the lowest possible latency (Serverless scaling has slight delays during scale-up events); or you need fine-grained control over instance class. In practice I recommend Serverless v2 for new projects because it removes the guesswork of instance sizing during early growth.

---

### Q27 (Senior)

**Question:** You have an Aurora cluster with 3 readers. Application engineers want to direct long-running analytics queries to specific readers without affecting the OLTP readers. How do you do this?

**What they're looking for:**
Custom endpoints in Aurora. Create a custom endpoint pointing to specific reader instances.

**Strong answer:**
Aurora supports custom endpoints. A custom endpoint is a DNS name you define that routes connections to a specific subset of cluster instances. I would create a custom endpoint for the analytics reader: `DEFINE CUSTOM ENDPOINT suta-analytics-cluster.cluster-custom-abc.us-east-1.rds.amazonaws.com` pointing only to the dedicated analytics reader instance (or the 2 analytics readers if I have that many). The analytics application connects to this custom endpoint, guaranteeing it hits the analytics reader. The OLTP readers are not included in the custom endpoint, so OLTP queries are not affected. I would also size the analytics reader larger (maybe `db.r6g.2xlarge`) while keeping the OLTP readers at `db.m6g.large`. This is a common pattern for read/write splitting with workload isolation.

---

### Q28 (Junior)

**Question:** What does `pg_is_in_recovery()` return on an Aurora reader instance and why?

**What they're looking for:**
Returns true because readers are always applying changes from storage. They are technically "in recovery" mode.

**Strong answer:**
`pg_is_in_recovery()` returns `true` on an Aurora reader instance. In standard PostgreSQL, "in recovery" means the server is replaying WAL to bring the database up to date - this is the state during crash recovery or when a standby/replica is applying changes from a primary. Aurora readers are always in this state because they continuously apply changes from the shared Aurora storage to their in-memory buffer caches. Even though Aurora's replication mechanism is fundamentally different from WAL streaming, PostgreSQL's `pg_is_in_recovery()` still returns `true` on the readers. This is actually a reliable way to check if you are on the writer (returns false) or a reader (returns true).

---

### Q29 (Mid)

**Question:** An Aurora cluster has one writer and no readers. What happens if the writer instance fails?

**What they're looking for:**
Aurora can recreate the writer in a new AZ even without readers (multi-AZ storage is always maintained). But it takes longer than promoting an existing reader.

**Strong answer:**
Aurora's distributed storage always maintains 6 copies across 3 AZs regardless of how many instances you have. So even with a single writer and no readers, your data is safe. If the writer fails, Aurora detects the failure and creates a new writer instance from the existing storage. This process takes several minutes because Aurora is provisioning a new instance from scratch (similar to creating a new database). If there had been a reader, the failover would take only 30 seconds because promoting an existing reader is much faster than creating a new instance. This is why Aurora recommends having at least one reader even if you do not need read scaling - the reader serves as a warm standby for fast failover. Without readers, you have data durability but slower failover.

---

### Q30 (Principal)

**Question:** What is Aurora Global Database and when would you use it?

**What they're looking for:**
Cross-region replication with sub-second lag. DR with low RPO. Read scaling in other regions. Managed promotion for regional failover.

**Strong answer:**
Aurora Global Database extends an Aurora cluster across multiple AWS regions. One region is the primary with a writer. Up to five secondary regions each have read replicas. Replication from primary to secondaries happens at the storage layer and achieves a Recovery Point Objective (RPO) of typically under 1 second. If the primary region suffers a disaster, you can promote a secondary region to primary in under a minute - the Recovery Time Objective (RTO) for a managed failover is under 1 minute. Use cases: (1) disaster recovery with near-zero data loss for regulated industries; (2) globally distributed applications where users in Europe should read from a European Aurora cluster with low latency, not from us-east-1; (3) compliance requirements for data residency - you can have your EU data served from a European region cluster while still having it durably replicated. The cost is significant (replication I/O charges plus running instances in multiple regions) so I use it for critical workloads where RTO/RPO requirements justify it.

---

## Topic T1.4 - Connectivity

---

### Q31 (Junior)

**Question:** You try to connect to an RDS instance and get "Connection timed out". What are the first three things you check?

**What they're looking for:**
Instance status, security group rules (port 5432 allowed for your IP), public access setting.

**Strong answer:**
First: is the instance running? I run `aws rds describe-db-instances --query "DBInstances[0].DBInstanceStatus"`. If it says `stopped`, I start it. Second: is my IP allowed in the security group? I run `aws ec2 describe-security-groups` on the attached SG and look for an inbound rule allowing TCP port 5432 from my IP. "Connection timed out" means the SYN packet is being dropped, which is the signature of a firewall (security group) blocking the traffic. If there is no rule for my IP, I add one. Third: is public access enabled? If `PubliclyAccessible` is false and I am connecting from outside the VPC, the endpoint resolves to a private IP that is not routable from the internet. I would need to enable public access or connect through a bastion host.

---

### Q32 (Junior)

**Question:** What is the difference between "Connection timed out" and "Connection refused"?

**What they're looking for:**
Timed out = SYN sent, no response, security group or instance is down. Refused = RST received, something is listening on the port but rejecting the connection.

**Strong answer:**
"Connection timed out" means your computer sent a connection attempt (TCP SYN packet) and got no response. The request just hung there until your client gave up. This happens when a firewall (security group) is silently dropping packets, or when the host is completely unreachable. "Connection refused" means something responded with a TCP RST (reset) packet, actively rejecting the connection. This happens when the host is reachable but nothing is listening on that port, or the process that should be listening has crashed. For RDS: "Connection timed out" usually means security group issue or instance is stopped. "Connection refused" usually means the instance is in a transition state (starting up, stopping) or the PostgreSQL process crashed. I use `nc -zv hostname port` to test connectivity without involving PostgreSQL authentication - this quickly distinguishes between network and database issues.

---

### Q33 (Mid)

**Question:** You need to allow your EC2 application servers to connect to RDS without hardcoding IPs. What is the recommended security group configuration?

**What they're looking for:**
Source security group reference, not a CIDR range. Any EC2 in the app security group can connect to RDS.

**Strong answer:**
I use a security group reference as the source in the RDS security group's inbound rule. Instead of allowing a CIDR range (IP addresses), I allow traffic from the application server's security group ID. The RDS security group inbound rule says: allow TCP port 5432 from source SG `sg-appservers`. Any EC2 instance that is a member of `sg-appservers` can connect to RDS. This is better than CIDR for three reasons: (1) EC2 instances can change their private IPs if they are stopped and restarted - with a CIDR rule, the new IP might not be covered; (2) as you add or remove app servers from the fleet, you do not need to update the RDS security group - just add/remove them from the app security group; (3) it is a cleaner mental model: "app servers can talk to the database" rather than "these specific IPs can talk to the database".

---

### Q34 (Mid)

**Question:** What does it mean for an RDS endpoint to have a 5-second DNS TTL? Why does this matter?

**What they're looking for:**
Low TTL allows fast failover. If your app caches DNS for too long, it will keep trying to connect to the old (failed) IP.

**Strong answer:**
DNS TTL (Time To Live) is how long a DNS resolver caches a DNS lookup result before checking again. RDS endpoints have a 5-second TTL. This matters during failover: when a Multi-AZ failover happens or an Aurora reader is promoted, AWS updates the DNS record of the endpoint to point to the new instance. If your application or a DNS cache had cached the old IP, it would keep trying to connect to the dead instance. With a 5-second TTL, the cached result expires quickly and the next DNS lookup returns the new IP. The practical implication: your application should not hardcode the IP address of an RDS instance. Always use the hostname. Also, some Java applications and connection pools cache DNS aggressively despite the low TTL - configure them to respect the TTL or set `networkaddress.cache.ttl=5` in Java.

---

### Q35 (Senior)

**Question:** You need to connect an application in VPC-A to an RDS instance in VPC-B. Both are in the same AWS account and region. How would you set this up?

**What they're looking for:**
VPC Peering or AWS PrivateLink. VPC peering is simpler for this scenario. Also need route tables and security groups.

**Strong answer:**
I would use VPC peering. The steps: (1) create a VPC peering connection between VPC-A and VPC-B; (2) accept the peering connection; (3) add routes in both VPCs' route tables - VPC-A's route table needs a route sending traffic destined for VPC-B's CIDR to the peering connection, and vice versa; (4) update the RDS security group in VPC-B to allow inbound port 5432 from VPC-A's CIDR block; (5) the application in VPC-A can now use the RDS endpoint (which resolves to a private IP in VPC-B) to connect. VPC peering is simple for two VPCs in the same region. For more complex scenarios (many VPCs peered to a central RDS, or cross-account/cross-region), I would consider AWS Transit Gateway instead, which is a hub that multiple VPCs can attach to rather than creating N-to-N peering connections. AWS PrivateLink is another option and is better when you need to expose a service without full VPC routing.

---

### Q36 (Senior)

**Question:** Explain the concept of a Multi-AZ RDS instance. How is it different from an Aurora cluster?

**What they're looking for:**
Multi-AZ RDS = synchronous standby replica. Failover takes 60-120 seconds. Aurora = distributed storage, fast failover. Multi-AZ is HA for standard RDS; Aurora's architecture is inherently HA.

**Strong answer:**
Multi-AZ for standard RDS adds a synchronous standby replica in a second Availability Zone. Every write to the primary is synchronously replicated to the standby before the primary acknowledges the write to the client. The standby is not accessible for reads - it is purely a warm standby for failover. When the primary fails or is taken offline for maintenance, RDS promotes the standby to primary and updates the endpoint DNS. This takes 60-120 seconds. The application must reconnect (the TCP connection drops during failover). Aurora is different fundamentally. Aurora's storage is distributed across 3 AZs with 6 copies by default - this is always true, even for a single-instance Aurora cluster. The "HA" in Aurora is built into the storage layer. Aurora readers are not standbys in the same sense - they serve live reads and can be promoted in 30 seconds or less. Aurora does not have a "primary plus a hidden standby" model. Instead it has a writer and zero to 15 readers, all sharing the same distributed storage.

---

### Q37 (Junior)

**Question:** What port does PostgreSQL use? What information do you need to connect to an RDS PostgreSQL instance?

**What they're looking for:**
Port 5432. Endpoint hostname, port, database name, username, password, and SSL preference.

**Strong answer:**
PostgreSQL uses port 5432 by default. To connect to an RDS PostgreSQL instance you need: (1) the endpoint hostname - something like `mydb.abc123xyz.us-east-1.rds.amazonaws.com`; (2) the port - 5432; (3) the database name - the name of the specific database within PostgreSQL to use; (4) the username; (5) the password; (6) SSL settings - at minimum `sslmode=require` for RDS, or `sslmode=verify-full` with the AWS CA bundle for full certificate verification. In psql, you can combine these as flags (`-h`, `-U`, `-d`, `-p`) or as a connection string (`postgresql://user:pass@host:5432/dbname`). In application code, you pass these as separate parameters to the database driver.

---

### Q38 (Mid)

**Question:** A developer wants to connect to the production RDS from their laptop "just to run a quick query". What are the security concerns and what is the safe way to allow this?

**What they're looking for:**
Production access is risky. Prefer bastion host or SSM Session Manager tunnel. Lock down IPs. Log access. Use read-only user.

**Strong answer:**
There are several concerns. First, production databases should not be publicly accessible - if they are, you are one security group misconfiguration away from exposing them to the internet. Second, developer laptops are less secure than production infrastructure (they get lost, infected, or connect from coffee shops). Third, "quick queries" on production have caused data loss (accidental DELETE, UPDATE without WHERE). The safe approach: (1) the database should have `PubliclyAccessible = false`; (2) access goes through an AWS Systems Manager Session Manager port-forwarding tunnel - no SSH keys needed, all sessions are logged to CloudWatch, and access requires the developer to have specific IAM permissions that can be audited; (3) the developer uses a read-only IAM database user (not the master user) so accidental writes are impossible; (4) any change queries require a second person to review (four-eyes principle for production changes). The convenience trade-off is worth the security gain.

---

### Q39 (Junior)

**Question:** What is a VPC and why does every RDS instance need to be in one?

**What they're looking for:**
VPC = private virtual network. Network isolation. All modern AWS resources must be in a VPC.

**Strong answer:**
A VPC (Virtual Private Cloud) is a private, isolated virtual network within AWS. You control the IP address range, subnets, routing tables, and internet gateways. Every RDS instance must be in a VPC because that is how AWS provides network isolation. The VPC determines which subnets the instance can be placed in, which security groups can be applied, and whether the instance is publicly accessible or private. Without a VPC, there is no network isolation - any instance could potentially communicate with any other. The VPC ensures that your database is in a controlled network environment. AWS has moved away from "EC2-Classic" (pre-VPC) for all services. For RDS, there is no option to create an instance outside a VPC.

---

### Q40 (Senior)

**Question:** You are designing a production multi-tier application with a web tier, application tier, and database tier in AWS. How do you structure the networking for the RDS database?

**What they're looking for:**
Database in private subnets. Security group allowing only app tier. No public access. Multi-AZ.

**Strong answer:**
The database tier uses private subnets (no internet gateway route). The DB subnet group includes private subnets in at least 2 AZs. The RDS instance has `PubliclyAccessible = false`. The RDS security group has one inbound rule: TCP port 5432 from the application tier's security group (not from IPs). The application tier's security group is assigned to all application server EC2 instances. This means only application servers can connect to the database - nothing else, even if someone compromises the web tier. Outbound rules on the RDS security group are unrestricted (RDS needs to connect to AWS services for patching, backup, etc.). The database is Multi-AZ for high availability. Audit logs go to CloudWatch Logs. No developer access directly to the database - only through an approved bastion or SSM Session Manager tunnel with a read-only IAM database user.

---

## Topic T1.5 - Connecting Clients

---

### Q41 (Junior)

**Question:** What is psql and how do you use it to connect to an RDS instance?

**What they're looking for:**
psql = official PostgreSQL CLI client. Flags -h -U -d -p. Connection string format. PGPASSWORD env var.

**Strong answer:**
psql is the official command-line client for PostgreSQL. You use it to connect to any PostgreSQL instance including RDS. The basic connection command is: `psql -h endpoint -U username -d database -p 5432`. The flags: `-h` is the hostname (the RDS endpoint), `-U` is the username, `-d` is the database name, `-p` is the port. psql will prompt for the password. To avoid the prompt in scripts, set the `PGPASSWORD` environment variable before running psql, or create a `.pgpass` file with the credentials (which psql reads automatically). Once connected, the psql prompt shows the database name followed by `=>` for regular users or `=#` for superusers. Common commands inside psql: `\l` to list databases, `\dt` to list tables, `\q` to quit, and any SQL statement followed by a semicolon.

---

### Q42 (Mid)

**Question:** Your application is a Python Flask API. How do you connect it to RDS PostgreSQL? What library do you use and what connection settings matter most?

**What they're looking for:**
psycopg2 (or SQLAlchemy for an ORM). Connection pool. Environment variables for credentials. sslmode=require. Parameterized queries.

**Strong answer:**
For a Flask application I use psycopg2 as the database adapter. In production I wrap it with a connection pool using `psycopg2.pool.ThreadedConnectionPool` (thread-safe for Flask's multi-threaded mode). The connection settings that matter most: (1) `sslmode=require` or `sslmode=verify-full` with the AWS CA bundle - never connect to production without SSL; (2) `connect_timeout=10` to fail fast rather than hanging if the database is unreachable; (3) pool size tuned to the expected concurrency - too small causes connection waits, too large wastes memory on the RDS side; (4) credentials from environment variables, never hardcoded. I also always use parameterized queries with `%s` placeholders to prevent SQL injection. For more complex applications I use SQLAlchemy as an ORM layer, which handles connection pooling and provides additional safety. The credentials are stored in AWS Secrets Manager and the application retrieves them at startup.

---

### Q43 (Mid)

**Question:** What is connection pooling and why is it important for database-backed web applications?

**What they're looking for:**
Creating a connection is expensive. Pool reuses connections. Prevents max_connections exhaustion. Improves throughput.

**Strong answer:**
Opening a database connection is expensive - it involves a TCP handshake, PostgreSQL authentication, and session initialization. A connection can take 10-100 milliseconds to establish. In a web application that handles thousands of requests per minute, creating a new connection for every request would be a significant performance bottleneck. Connection pooling solves this by maintaining a pool of pre-opened connections. When a request needs a database connection, it borrows one from the pool, uses it, and returns it. The connection stays open for the next request. The pool has a minimum size (connections always open) and a maximum size (cap to prevent overwhelming the database). For PostgreSQL, each connection consumes memory on the server side (~5-10 MB). PostgreSQL's `max_connections` setting limits the total connections. Without pooling, 200 concurrent web requests create 200 connections. With a pool of 20, all 200 requests share 20 connections and the database is not overwhelmed.

---

### Q44 (Junior)

**Question:** Why does RDS not give you a true PostgreSQL superuser? Does this cause practical problems?

**What they're looking for:**
rds_superuser has almost all privileges. AWS reserves true superuser to manage the host. Practical impact is minimal.

**Strong answer:**
RDS does not give true superuser because AWS needs to maintain control of the managed service. A true PostgreSQL superuser can do things that would break AWS's management layer - like reading files from the host filesystem, modifying pg_shadow, or loading arbitrary C extensions. By giving you `rds_superuser` instead, AWS ensures you cannot accidentally or intentionally break things that AWS manages. In practice this causes almost no problems. You can create databases, create users, grant any privilege, enable approved extensions (there are many - pg_stat_statements, PostGIS, pg_trgm, etc.), manage replication, and do all DBA work. The limitations you might notice: you cannot install a custom C extension that is not in AWS's approved list, and you cannot use `pg_read_file()` to read OS files. These are edge cases. For 99% of PostgreSQL DBA and development work, `rds_superuser` is sufficient.

---

### Q45 (Senior)

**Question:** How do you handle database password rotation in production without causing downtime?

**What they're looking for:**
AWS Secrets Manager rotation. Dual user rotation pattern. Application reads secrets dynamically.

**Strong answer:**
The best approach is AWS Secrets Manager with automatic rotation enabled. Here is how it works: Secrets Manager stores the database credentials. The application fetches them from Secrets Manager at connection time, not from a config file. When Secrets Manager rotates the password, it uses the "dual user" rotation strategy: it creates a second user as a clone of the first, updates the secret to use the new user, updates the database password for the new user, and only then removes the old user after confirming the new one works. This means at no point during rotation are there no valid credentials. The application must fetch credentials fresh from Secrets Manager on each connection attempt, not cache them indefinitely - or at least refresh them periodically. I configure the application to catch authentication errors and retry after refreshing credentials from Secrets Manager, which handles the brief window between when the secret is updated and when the application's cached version expires.

---

### Q46 (Mid)

**Question:** What SSL mode should you use in production when connecting to RDS? What is the difference between `sslmode=require` and `sslmode=verify-full`?

**What they're looking for:**
verify-full is the secure production setting. require encrypts but doesn't verify the certificate. Explain MITM risk.

**Strong answer:**
For production, use `sslmode=verify-full`. Here is the difference: `sslmode=require` encrypts the connection but does not verify that the server's TLS certificate is genuine. This protects against passive eavesdropping but is vulnerable to a man-in-the-middle attack where a malicious party intercepts the connection and presents their own certificate. `sslmode=verify-full` checks two things: the certificate is signed by a trusted Certificate Authority (you provide the AWS RDS CA bundle), and the hostname in the certificate matches the hostname you connected to. This prevents MITM attacks. To use `verify-full`, download the AWS global CA bundle from `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem` and pass it as `sslrootcert=/path/to/global-bundle.pem`. For development and training, `sslmode=require` is acceptable since there is no sensitive data at risk. Never use `sslmode=disable`.

---

### Q47 (Junior)

**Question:** You want multiple team members to access the same RDS database. Should they all use the master user credentials? Why or why not?

**What they're looking for:**
No. Create individual users. Least privilege. Ability to revoke individual access. Audit logging tracks individual users.

**Strong answer:**
No. Each person should have their own database user with the minimum privileges they need. Using the master user credentials for everyone creates several problems: (1) if someone leaves the team you have to change the master password and update it everywhere; (2) audit logs show `postgres` (the master user) for every action - you cannot tell which team member ran a destructive query; (3) everyone has maximum privileges even if they only need read access. The correct approach: create individual users (`CREATE USER alice WITH PASSWORD '...'`), grant each user only the privileges they need (read-only users get SELECT on their tables; developers get SELECT, INSERT, UPDATE, DELETE; no one gets DROP unless they need it), and manage credentials through AWS Secrets Manager one secret per user. When someone leaves, run `REVOKE` and `DROP USER` for their account. Their actions are in the audit log forever under their username.

---

### Q48 (Senior)

**Question:** Your application is connecting to an Aurora cluster using the cluster endpoint. During a failover, the application starts throwing "connection refused" errors for 45 seconds. How do you make this more resilient?

**What they're looking for:**
Retry logic in the application. Exponential backoff. Use appropriate connection pool settings. Consider Aurora's RDS Proxy for managed failover.

**Strong answer:**
During Aurora failover, the cluster endpoint DNS is updated (this happens within seconds), but existing TCP connections to the old writer are dropped. New connections during the promotion window may briefly fail. To minimize impact: (1) implement retry logic in the application - catch connection errors and retry with exponential backoff, at least 3 retries over 30-60 seconds; (2) configure the connection pool to validate connections before use (`testOnBorrow` or equivalent) so stale connections from the old writer are detected and replaced; (3) set the DNS TTL awareness correctly - some Java applications cache DNS aggressively, set `networkaddress.cache.ttl=5` in the JVM; (4) consider Amazon RDS Proxy, which sits between the application and Aurora, maintains warm connection pools to both writer and readers, and reroutes connections during failover transparently - the application never sees the failover because RDS Proxy handles it; (5) test failover regularly in staging by running `aws rds failover-db-cluster` to make sure your retry logic actually works.

---

### Q49 (Mid)

**Question:** What is RDS Proxy and what problems does it solve?

**What they're looking for:**
RDS Proxy manages connection pooling between the app and RDS. Solves max_connections exhaustion from Lambda/serverless. Also handles failover more gracefully.

**Strong answer:**
RDS Proxy is a fully managed database proxy that sits between your application and RDS or Aurora. It maintains a pool of connections to the database and multiplexes many application connections onto a smaller number of database connections. This solves two main problems. First: serverless and Lambda applications. AWS Lambda functions can scale to thousands of concurrent executions instantly. Each Lambda invocation might try to open its own database connection, instantly exhausting PostgreSQL's `max_connections`. RDS Proxy absorbs these thousands of incoming connections and maintains a small, stable pool of actual database connections. Second: failover resilience. During an RDS or Aurora failover, RDS Proxy automatically routes connections to the new primary. Applications connected to RDS Proxy experience only a few seconds of pause rather than having to implement their own retry logic. RDS Proxy also integrates with AWS Secrets Manager, so you can rotate database credentials without changing application config.

---

### Q50 (Principal)

**Question:** You are building a multi-region active-passive application. The primary region is us-east-1, and the disaster recovery region is eu-west-1. How do you design the database layer?

**What they're looking for:**
Aurora Global Database. RPO < 1 second. RTO < 1 minute with managed failover. Application config management across regions. DNS-based routing for failover.

**Strong answer:**
For a multi-region active-passive design with PostgreSQL-compatible database: (1) Use Aurora Global Database with us-east-1 as the primary cluster and eu-west-1 as the secondary. Aurora Global Database replicates at the storage layer with typically under 1 second lag (RPO). (2) The application in eu-west-1 is inactive (passive) but deployed and configured to use the eu-west-1 Aurora cluster endpoint as its database. This endpoint points to reader instances that can be promoted in a disaster. (3) For DNS-based failover: use Amazon Route 53 with health checks on the primary application endpoint. If the primary goes unhealthy, Route 53 automatically routes traffic to the eu-west-1 endpoint. (4) Database failover: Aurora Global Database managed failover promotes eu-west-1 to primary in under 1 minute (RTO). Run `aws rds failover-global-cluster` to initiate. (5) After failover, the application in eu-west-1 is now the primary. The us-east-1 region becomes the DR site. Regularly test the failover procedure (at least quarterly) to ensure RTO/RPO commitments can actually be met. Consider Aurora Global Database's "switchover" feature for planned maintenance, which has near-zero RPO and RTO under 1 minute.

---

## Quick Reference: Level Expectations

| Level | Expected Knowledge |
|-------|-------------------|
| Junior | Can create and connect to RDS. Knows instance families. Understands security groups. Knows psql basics. |
| Mid | Can design the full RDS setup from scratch. Can troubleshoot connectivity. Understands Aurora basics. Can explain connection pooling. |
| Senior | Can make sizing and architecture decisions. Understands Multi-AZ, Aurora failover, IaC approach. Can handle password rotation and security design. |
| Principal | Can design multi-region database architectures. Understands organizational governance of databases at scale. Can evaluate trade-offs between Aurora, RDS, and serverless approaches. |
