# Module 01: Interview Prep - AWS Foundations and Aurora Architecture

Interview questions graduated by experience level. Use these for self-assessment or mock interviews.

---

## Topic 1: Managed vs Self-Managed Databases

### Junior Level

**1. Q:** What is the difference between running PostgreSQL on an EC2 instance and using Amazon RDS?

**What they are looking for:** Understanding of what "managed" means in concrete terms - not just "AWS runs it for you."

**Strong answer:** With EC2, you install PostgreSQL yourself and handle everything: OS patching, PostgreSQL upgrades, backup scripts, replication setup, storage management, and monitoring. With RDS, AWS handles the OS, engine patching, automated backups, storage provisioning, and Multi-AZ failover. You focus on schema design, query performance, user management, and application-level concerns. The trade-off is control: EC2 gives you root access and full configuration freedom; RDS gives you operational simplicity but restricts OS-level access.

**Red flag:** "RDS is easier so you should always use it." This shows no understanding of when self-managed is the right choice.

---

**2. Q:** What does AWS handle for you with RDS, and what are you still responsible for?

**What they are looking for:** A clear split on both sides, not a vague answer.

**Strong answer:** AWS handles: hardware provisioning, OS installation and patching, engine minor version patching (with your scheduling), automated backups within the retention window, Multi-AZ failover mechanics, and storage infrastructure. You handle: choosing the engine version, schema design, indexing, query optimization, database user management, parameter group tuning, deciding backup retention and testing restores, security group rules, and data integrity.

**Red flag:** "AWS handles backups so I don't need to worry about them." Automated backups exist but you must configure retention, test restores, and handle cross-region copies.

---

### Mid Level

**3. Q:** When would you choose self-managed PostgreSQL on EC2 over RDS or Aurora?

**What they are looking for:** Judgment about trade-offs, not a preference.

**Strong answer:** I would choose EC2 when: I need PostgreSQL extensions not supported by RDS or Aurora (certain contrib modules or custom C extensions), I need OS-level tuning like huge pages or NUMA configuration for very specific workloads, I need full control over WAL archiving and custom replication topologies, or when the team has deep PostgreSQL expertise and the workload characteristics make RDS constraints a problem. RDS wins in most cases because the operational overhead of patching, HA, and backup management is significant. The decision point is usually whether you have specific technical requirements that RDS cannot meet.

**Red flag:** "I always choose managed" or "I always choose self-managed." Both show inability to evaluate trade-offs.

---

## Topic 2: Aurora Architecture

### Junior Level

**4. Q:** What is Amazon Aurora, and how is it different from standard RDS PostgreSQL?

**What they are looking for:** Understanding of the storage architecture difference, not just "it's faster."

**Strong answer:** Aurora is PostgreSQL-compatible and uses the same drivers and SQL. The difference is the storage layer: standard RDS uses EBS volumes attached to each instance, while Aurora uses a distributed storage system that replicates data six ways across three Availability Zones. This gives Aurora faster failover (typically under 30 seconds vs 60-120 seconds for RDS), higher durability, and up to 15 read replicas that share the same storage. The trade-off is cost - Aurora is more expensive per compute hour - and some PostgreSQL extensions and behaviors differ from community PostgreSQL.

**Red flag:** "Aurora is just a faster version of RDS." This misses the architectural difference that drives all the behavior differences.

---

**5. Q:** What is a read replica, and how does it work differently in Aurora vs standard RDS?

**What they are looking for:** Understanding of shared storage vs streaming replication.

**Strong answer:** A read replica handles SELECT queries to offload read traffic from the primary. In standard RDS, replicas receive data via PostgreSQL streaming replication - the primary ships WAL (Write-Ahead Log) records to each replica, which replays them. This creates replication lag that can spike under heavy writes. In Aurora, all instances - writer and readers - access the same shared storage layer. Readers do not need to replay WAL because they already have access to the committed data. This results in much lower replication lag (typically under 20ms vs potentially seconds for RDS) and faster failover since the reader does not need to "catch up."

---

### Mid Level

**6. Q:** Explain Aurora's cluster endpoint vs reader endpoint. How do you use them in an application?

**What they are looking for:** Endpoint routing awareness and practical implementation.

**Strong answer:** The cluster endpoint always points to the current writer instance. When failover occurs, AWS updates this DNS record to point to the new writer. All write operations (INSERT, UPDATE, DELETE) and read operations that need the latest data should go through this endpoint. The reader endpoint load-balances connections across all reader instances using round-robin DNS. Read-heavy queries like reports, analytics, or search can use this endpoint to spread the load. In the application, you configure two connection pools: one for the cluster endpoint (reads and writes) and one for the reader endpoint (reads only). If all readers fail, the reader endpoint routes to the writer.

**Red flag:** "We just use one endpoint for everything." This means they have never implemented read-write splitting and are wasting their read replicas.

---

**7. Q:** How does Aurora handle storage differently from standard RDS, and what practical impact does this have?

**What they are looking for:** Specific knowledge of the 6-copy, 3-AZ model and its operational implications.

**Strong answer:** Aurora separates compute from storage. The storage layer is a distributed system that writes each piece of data to six storage nodes across three AZs. Aurora can sustain the loss of two copies without affecting writes and three copies without affecting reads. Practically, this means: storage grows automatically in 10 GB increments up to 128 TB with no provisioning needed, storage-level corruption is self-healed without DBA intervention, and failover is faster because a promoted reader already has access to all data. The downside is that you cannot choose your storage type (no gp2/gp3/io1 decision) and the per-GB cost is different from EBS.

---

### Senior Level

**8. Q:** When is Aurora the wrong choice? Give me specific scenarios.

**What they are looking for:** Honest evaluation, not a default recommendation.

**Strong answer:** Aurora is wrong when: the database is dev/test with minimal traffic - Aurora's cost floor makes RDS 3-4x cheaper at small scale. When you need a PostgreSQL extension that Aurora does not support - Aurora supports most but not all community extensions. When you need full community PostgreSQL compatibility for portability or compliance - Aurora has behavioral differences in vacuum settings, WAL handling, and some system catalog views. When the workload is a tiny database with infrequent access - Aurora Serverless v2 helps but still has a minimum cost. And when you are in a region where Aurora is not available yet. The decision should be driven by specific workload requirements, not by defaulting to "newer is better."

**Red flag:** "I can't think of when Aurora wouldn't be the right choice." This shows either limited experience or unwillingness to think critically.

---

**9. Q:** You have an Aurora cluster where one reader is consistently 15-30 seconds behind the writer. How do you diagnose this?

**What they are looking for:** Systematic diagnosis specific to Aurora's architecture.

**Strong answer:** In Aurora, replication lag is almost always a compute bottleneck on the reader, not a storage issue - because all instances share storage. My investigation: First, check the reader's instance size relative to the writer. An undersized reader cannot process updates fast enough. Second, check CloudWatch for CPU and memory pressure on the lagging reader during the lag periods. Third, look for long-running queries on the reader that might be blocking cache invalidation. Fourth, check `AuroraReplicaLag` in CloudWatch for trends - is it constant or does it correlate with write spikes on the primary? The fix is usually upsizing the reader instance, adding query timeouts on the reader, or distributing read traffic across more readers.

---

## Topic 3: VPC Networking for Databases

### Junior Level

**10. Q:** Why should databases go in private subnets instead of public subnets?

**What they are looking for:** Security reasoning about network isolation.

**Strong answer:** Private subnets have no route to the Internet Gateway, so resources in them cannot receive inbound traffic from the internet. Databases should never be directly reachable from the internet because they contain sensitive data and are high-value targets. Even with strong passwords and security groups, placing a database in a public subnet adds unnecessary attack surface. If a security group is misconfigured for even a moment, the database is exposed. In a private subnet, there is no network path from the internet to the database regardless of security group rules - that is defense in depth.

---

**11. Q:** What is a security group, and how should you configure the one for an RDS instance?

**What they are looking for:** Stateful firewall concept and the practice of referencing security groups.

**Strong answer:** A security group is a stateful firewall that controls inbound and outbound traffic to a resource. Stateful means if you allow inbound traffic, the response is automatically allowed without a separate outbound rule. For an RDS instance, the security group should allow inbound on port 5432 (PostgreSQL) only from the security group attached to the application servers - not from an IP range and never from 0.0.0.0/0. By referencing another security group as the source, you ensure that only instances in that group can connect, regardless of their IP addresses. This handles auto-scaling gracefully - new app instances automatically get access.

**Red flag:** "Allow 5432 from my IP address." This is acceptable for a personal dev instance but shows no understanding of production security practices.

---

### Mid Level

**12. Q:** A developer reports "connection timed out" when connecting to Aurora from an EC2 instance. Walk me through your troubleshooting.

**What they are looking for:** Systematic network troubleshooting, not guessing.

**Strong answer:** "Connection timed out" means the TCP connection never completes - packets are being dropped. I work through the layers: First, verify the Aurora cluster is in "available" state, not in maintenance or failover. Second, check the security group on the Aurora cluster - is there an inbound rule for port 5432 allowing the EC2 instance's security group? This is the most common cause. Third, check the EC2 instance's security group - are outbound connections allowed? The default allows all outbound, but someone may have restricted it. Fourth, check NACLs on both subnets - they are stateless, so both inbound and outbound rules plus ephemeral ports must be correct. Fifth, verify the EC2 instance can resolve the Aurora endpoint DNS and that the resolved IP is in the correct private subnet. Sixth, check route tables - can the EC2 subnet route to the Aurora subnet?

---

**13. Q:** What is a DB subnet group, and why does it matter for Multi-AZ?

**What they are looking for:** Understanding of placement and HA prerequisites.

**Strong answer:** A DB subnet group is a collection of subnets that RDS or Aurora can use to place database instances. It must span at least two Availability Zones. When Aurora creates a cluster with instances in multiple AZs, it uses the subnet group to find a suitable subnet in each AZ. If your subnet group only has subnets in one AZ, you cannot achieve Multi-AZ high availability. Best practice is to include private subnets from at least two (preferably three) AZs in the subnet group. Never include public subnets in a DB subnet group.

---

### Senior Level

**14. Q:** Design the network architecture for a production Aurora cluster that serves a three-tier web application. Walk me through every component.

**What they are looking for:** A complete, defensible architecture - not just "private subnet."

**Strong answer:** The VPC spans at least two AZs with three tiers of subnets. Public subnets hold the Application Load Balancer and NAT Gateways. Private app subnets hold the application servers - they receive traffic only from the ALB and route outbound internet through the NAT Gateway. Private data subnets hold the Aurora cluster - these have no internet route at all, not even through NAT. Security groups chain: the ALB allows HTTPS from the internet, app servers allow traffic only from the ALB's security group, and Aurora allows port 5432 only from the app servers' security group. DBA access goes through AWS Systems Manager Session Manager with port forwarding - no bastion host and no public database endpoint needed. The DB subnet group includes the data subnets from all AZs. Aurora has encryption at rest enabled, deletion protection on, and a custom parameter group.

---

## Topic 4: SQL and Database Fundamentals

### Junior Level

**15. Q:** What is the difference between WHERE and HAVING in SQL?

**What they are looking for:** Understanding of when filtering happens relative to grouping.

**Strong answer:** WHERE filters individual rows before any grouping happens. HAVING filters groups after aggregation. For example, if you want orders from 2025 grouped by customer with a count greater than 5: WHERE filters to 2025 orders first, then GROUP BY groups by customer, then HAVING filters to only groups with more than 5 orders. You cannot use aggregate functions in WHERE (like `WHERE COUNT(*) > 5` - that is invalid). Aggregates go in HAVING.

---

**16. Q:** What is a JOIN, and what is the difference between INNER JOIN and LEFT JOIN?

**What they are looking for:** Practical understanding of how joins combine data.

**Strong answer:** A JOIN combines rows from two tables based on a related column. INNER JOIN returns only rows that have a match in both tables - if a customer has no orders, they do not appear in the result. LEFT JOIN returns all rows from the left table, even if there is no match in the right table - customers with no orders appear with NULL values for the order columns. Use INNER JOIN when you only want matching data. Use LEFT JOIN when you need to find records that have no match - like "which customers have never ordered."

---

## Topic 5: Cost Optimization

### Mid Level

**17. Q:** A team asks you to deploy Aurora for a small internal tool with 5 GB of data and 100 requests per day. What do you recommend instead, and why?

**What they are looking for:** Cost awareness and practical judgment.

**Strong answer:** I would recommend RDS PostgreSQL on a db.t3.micro or db.t3.small instance. Aurora's minimum cost floor (around $60-80/month for the smallest practical configuration) is excessive for a database with 5 GB and 100 daily requests. RDS on db.t3.micro costs about $15-25/month including storage. Aurora's advantages - faster failover, higher durability, read replica scaling - solve problems this workload does not have. If the tool grows significantly later, migrating from RDS to Aurora via snapshot restore is straightforward.

**Red flag:** "Always use Aurora because it's the latest technology." This shows no cost awareness.

---

### Senior Level

**18. Q:** How do you evaluate total cost of ownership between RDS and Aurora for a production database?

**What they are looking for:** A structured comparison beyond just the instance price.

**Strong answer:** I build a TCO model with four categories. Compute: Aurora costs about 20% more per instance hour than equivalent RDS. Storage: RDS charges for provisioned storage (you pay for allocated space whether used or not); Aurora charges for consumed storage (actual data size). This difference compounds when RDS Multi-AZ doubles storage costs. I/O: RDS includes baseline IOPS with gp3 but charges heavily for provisioned IOPS above the baseline. Aurora charges per I/O request on Standard pricing or includes I/O with the I/O-Optimized tier. Operations: Aurora's faster failover and self-healing storage reduce on-call burden - I quantify this as avoided incident hours. The outcome: small databases favor RDS on cost. Production databases with HA, read replicas, and high I/O usually favor Aurora because the shared storage model eliminates the per-instance storage duplication that RDS requires.

---

**19. Q:** Your Aurora production cluster costs $3,000/month on-demand. What are three strategies to reduce this cost?

**What they are looking for:** Concrete optimization strategies, not just "use reserved instances."

**Strong answer:** First, Reserved Instances or Compute Savings Plans for a 1-year or 3-year commitment - this typically saves 40-60%, potentially reducing $3,000 to $1,200-1,800. Second, evaluate the I/O pricing model - if I/O charges exceed 25% of the total bill, switch to I/O-Optimized (which includes I/O in the compute price at 30% higher instance cost). Third, right-size instances by reviewing CloudWatch CPU and memory utilization - if instances consistently run below 40% CPU, downsize to the next smaller instance class. Additional strategies: use Aurora Serverless v2 for non-production reader instances that are idle most of the time, and archive old data to S3 to reduce storage volume.

---

**20. Q:** Your company is evaluating a multi-region disaster recovery strategy. Compare the cost implications of Aurora Global Database vs cross-region RDS read replicas.

**What they are looking for:** Architectural cost analysis at the DR level.

**Strong answer:** Aurora Global Database replicates to a secondary region using dedicated replication infrastructure with sub-second lag. Cost: you pay for the secondary region's reader instances plus storage (shared storage in the secondary region, not duplicated per instance) plus inter-region data transfer. Cross-region RDS read replicas replicate via standard PostgreSQL streaming replication. Cost: you pay for the replica instance, its own full provisioned EBS storage in the secondary region, and inter-region data transfer for WAL shipping. The key cost difference: Aurora's shared storage means one storage bill in each region regardless of how many readers you have. RDS pays per-instance storage in each region. Additionally, Aurora's sub-second lag means your RPO is near-zero without extra effort, while RDS cross-region replicas can lag minutes behind during heavy writes, potentially increasing your RPO. The Aurora Global Database is more expensive upfront but provides a significantly better RPO, which means less data loss during a regional failure.

**Red flag:** "Just use backups for DR." This shows no understanding of RPO/RTO requirements or the difference between backup-based recovery and active replication.

---

## How to Use This for Interview Prep

1. **Self-assessment:** Answer each question without looking at the model answer. Record yourself if possible.
2. **Identify gaps:** If you cannot answer a question at your target level, go back to the relevant BUILD guide.
3. **Practice the structure:** Strong interview answers follow a pattern: state the answer directly, explain why, give an example or trade-off, and mention a caveat.
4. **Time yourself:** Most technical interview answers should be 60-90 seconds. Longer than 2 minutes and you are losing the interviewer.
5. **Red flags matter:** Understand what weak answers look like so you can avoid them.
