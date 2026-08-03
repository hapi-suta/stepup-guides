# Interview Questions - Module 02: Provisioning Aurora
## DevOps DBA Training Track

20 questions covering provisioning, endpoints, parameter groups, connectivity, and cleanup.
Graduated by level: Junior | Mid | Senior

---

## How to Use This Guide

Read the question. Formulate your answer without reading the hint. Then compare your answer to "What they're looking for" and "Strong answer".

If your answer misses key points, go back to the relevant BUILD guide and review that section.

---

## Topic 1 - Aurora Cluster Provisioning

---

### Q1 (Junior)

**Question:** What is the difference between Amazon RDS PostgreSQL and Amazon Aurora PostgreSQL? Why would you choose one over the other?

**What they're looking for:**
Understanding that Aurora is a different engine with a different storage architecture, not just "RDS but better."

**Strong answer:**
Aurora PostgreSQL and RDS PostgreSQL both run PostgreSQL, but the underlying architecture is different. RDS PostgreSQL uses standard EBS volumes for storage - one volume per instance. Aurora uses a distributed storage layer that replicates data across three Availability Zones automatically. This gives Aurora faster replication (sub-20ms lag vs seconds for RDS replicas), automatic storage scaling (up to 128 TiB without pre-allocation), and faster failover (typically 30 seconds vs 60-120 seconds for RDS Multi-AZ). Aurora costs about 20% more than RDS for the same instance class. I would choose RDS for simple workloads where cost is the primary concern, and Aurora for production workloads that need high availability, low replication lag, or automatic storage scaling.

**Red flags:**
- "Aurora is just a faster version of RDS" - misses the architectural difference
- "They are the same thing" - completely wrong
- Not mentioning the shared storage architecture

---

### Q2 (Junior)

**Question:** Walk me through the resources you need to create before you can launch an Aurora PostgreSQL cluster.

**What they're looking for:**
Awareness of the dependency chain: VPC, subnets, subnet group, security group, parameter group, then cluster, then instances.

**Strong answer:**
Before creating the Aurora cluster, I need: (1) a VPC with subnets in at least two Availability Zones; (2) a DB Subnet Group that includes those subnets - this tells Aurora where it can place instances; (3) a Security Group with an inbound rule allowing TCP port 5432 from the IPs or CIDR ranges that need to connect; (4) optionally, a custom Cluster Parameter Group if I need non-default PostgreSQL settings. After those are in place, I create the Aurora cluster first (which creates the shared storage volume), then add instances to the cluster. The first instance becomes the writer; additional instances become readers.

**Red flags:**
- Not mentioning the subnet group
- Thinking you create instances before the cluster
- Forgetting the security group

---

### Q3 (Junior)

**Question:** What happens when you create an Aurora cluster but add no instances to it?

**What they're looking for:**
Understanding that the cluster and instances are separate resources. A cluster with no instances has storage but nothing to process queries.

**Strong answer:**
The cluster is created successfully - it provisions the shared storage volume and generates cluster endpoints. But you cannot connect to it or run any queries because there are no compute instances to process SQL. The cluster endpoint and reader endpoint exist in DNS but have no target. You must add at least one instance (which becomes the writer) before the cluster is usable. This two-step process (cluster then instances) is different from standard RDS, where you create a single resource that is both compute and storage.

**Red flags:**
- "It would fail" - it does not fail, it just has no compute
- Not knowing that cluster and instances are separate resources

---

### Q4 (Mid)

**Question:** Explain the difference between a Cluster Parameter Group and an Instance Parameter Group in Aurora. When would you use each?

**What they're looking for:**
Understanding the two levels of configuration and that instance-level overrides cluster-level.

**Strong answer:**
A Cluster Parameter Group applies settings to all instances in the cluster - both the writer and all readers. An Instance Parameter Group applies to a specific instance only. If the same parameter is set in both, the instance-level value takes precedence for that instance. I use the Cluster Parameter Group for settings that should be consistent across all instances, like `log_statement`, `log_min_duration_statement`, and `shared_preload_libraries`. I use Instance Parameter Groups when I need different settings on specific instances - for example, a higher `work_mem` on a reader dedicated to analytics queries, or more aggressive logging on a debug reader.

**Red flags:**
- Thinking Aurora only has one parameter group level
- Not knowing which takes precedence when both are set

---

### Q5 (Mid)

**Question:** What is the difference between a static parameter and a dynamic parameter in an Aurora parameter group? Give an example of each.

**What they're looking for:**
Practical understanding of what requires a reboot and what does not.

**Strong answer:**
A dynamic parameter takes effect immediately when you change it - no reboot required. Examples: `log_statement`, `log_min_duration_statement`, `work_mem`. A static parameter requires a reboot of each affected instance before it takes effect. Examples: `shared_buffers`, `shared_preload_libraries`, `max_connections`. In production, I batch static parameter changes together and apply them during a maintenance window to minimize reboots. Dynamic changes I can apply any time. To check whether a parameter is static or dynamic, I use `aws rds describe-db-cluster-parameters` and look at the `ApplyType` field.

**Red flags:**
- Not knowing that static requires a reboot
- Thinking all parameter changes require a reboot

---

### Q6 (Mid)

**Question:** You need to enable `pg_stat_statements` on an Aurora PostgreSQL cluster. What steps are involved?

**What they're looking for:**
This requires a static parameter change AND a CREATE EXTENSION - a multi-step process.

**Strong answer:**
Three steps: (1) modify the cluster parameter group to add `pg_stat_statements` to `shared_preload_libraries` - this is a static parameter, so it will not take effect until reboot; (2) reboot each instance in the cluster to load the shared library; (3) connect with psql and run `CREATE EXTENSION IF NOT EXISTS pg_stat_statements` in each database where I want to use it. After that, the `pg_stat_statements` view will show query performance data. I would also set `pg_stat_statements.track` to `all` in the parameter group if I want to track queries inside functions as well.

**Red flags:**
- Thinking you can just CREATE EXTENSION without modifying shared_preload_libraries
- Not knowing this requires a reboot
- Forgetting the CREATE EXTENSION step after the reboot

---

## Topic 2 - Aurora Endpoints

---

### Q7 (Junior)

**Question:** How many endpoints does an Aurora cluster with 1 writer and 2 readers have? Name each type and its purpose.

**What they're looking for:**
Understanding of the five endpoint types (2 cluster-level + 3 instance-level).

**Strong answer:**
Five endpoints total. At the cluster level: (1) the Cluster Endpoint (also called the writer endpoint) - always routes to the current writer instance, use it for all write operations; (2) the Reader Endpoint - load-balances connections across all reader instances using DNS round-robin, use it for read-only queries. At the instance level: (3) the writer's instance endpoint - connects directly to the writer; (4) reader-1's instance endpoint; (5) reader-2's instance endpoint. For applications, always use the cluster endpoint for writes and the reader endpoint for reads. Instance endpoints are for DBA use cases like checking a specific replica's replication lag.

**Red flags:**
- Not knowing the reader endpoint exists
- Thinking there is only one endpoint per cluster

---

### Q8 (Mid)

**Question:** After an Aurora failover, the cluster endpoint points to the new writer. But the application is still getting "read-only transaction" errors. What could cause this?

**What they're looking for:**
DNS caching as the most common post-failover issue.

**Strong answer:**
DNS caching. The cluster endpoint is a DNS CNAME that gets updated during failover to point to the new writer. But if the application, the OS, or the connection pool has cached the old DNS entry, it will still connect to the old IP address - which is now a reader. The solutions are: (1) configure the DNS TTL on the client to be short (5-10 seconds); (2) use a connection pool that respects DNS TTL and refreshes connections periodically; (3) in an emergency, restart the application to clear the DNS cache; (4) for Java applications, set the JVM DNS cache TTL with `-Dsun.net.inetaddress.ttl=5`.

**Red flags:**
- "I would change the endpoint" - the endpoint already changed, the client is caching the old IP
- Not mentioning DNS caching at all
- Suggesting a database-side fix for a client-side problem

---

### Q9 (Mid)

**Question:** A developer asks: "Can I just use the writer endpoint for all queries, both reads and writes?" What do you tell them?

**What they're looking for:**
Understanding that it works but misses the point of having readers.

**Strong answer:**
Technically yes - the writer endpoint accepts both reads and writes. But this defeats the purpose of having reader instances. If all queries go to the writer, the readers sit idle while the writer handles everything. The benefits of using the reader endpoint for reads are: (1) offload read traffic from the writer, reducing its CPU and connection usage; (2) scale read capacity by adding more readers; (3) isolate heavy analytics queries from write operations so they do not compete for resources. I would tell the developer to use the cluster endpoint for writes and the reader endpoint for reads. If their application framework does not support separate endpoints, I would help them set it up.

**Red flags:**
- "No, you cannot read from the writer" - incorrect, you can
- Not explaining why separating reads and writes is important

---

### Q10 (Senior)

**Question:** Your application uses the reader endpoint for analytics queries. A developer complains that their long-running analytics query sometimes returns inconsistent results. What could be happening?

**What they're looking for:**
Understanding that the reader endpoint distributes connections - a long-running query stays on one reader, but separate connections may hit different readers with slightly different replication states.

**Strong answer:**
Two possible causes. First, if the developer opens multiple connections (or the connection pool rotates connections), each connection may land on a different reader via the DNS round-robin. If there is even a small replication lag difference between readers, queries on different connections may see slightly different data. Second, if the application runs a query, disconnects, and reconnects to run a follow-up query, the second connection may land on a different reader that has not yet received the latest writes. The fix depends on the use case: for consistency within a session, use the instance endpoint of a specific reader instead of the reader endpoint. For read-after-write consistency, read from the cluster (writer) endpoint.

**Red flags:**
- Not considering replication lag between readers
- "Aurora has zero replication lag so this cannot happen" - Aurora has near-zero lag, not zero

---

## Topic 3 - Connectivity and Security Groups

---

### Q11 (Junior)

**Question:** A developer gets "Connection timed out" when connecting to an Aurora cluster. The cluster shows "available." What is the most likely cause?

**What they're looking for:**
Security group is the first thing to check.

**Strong answer:**
The most likely cause is a security group issue. "Connection timed out" means packets are being dropped before reaching Aurora. The security group attached to the cluster either does not have an inbound rule for port 5432, or the rule exists but does not include the developer's IP address. I would check the security group rules with `aws ec2 describe-security-groups --group-ids SG_ID` and verify the developer's IP is allowed. Other possible causes: the developer is outside the VPC and PubliclyAccessible is set to false, or a Network ACL on the subnet is blocking the traffic.

**Red flags:**
- "Restart the database" - the database is fine
- Jumping to PostgreSQL troubleshooting before checking network

---

### Q12 (Mid)

**Question:** What is the difference between "Connection timed out," "Connection refused," and "password authentication failed"? What does each tell you about where the problem is?

**What they're looking for:**
Understanding the network stack layers and which error maps to which layer.

**Strong answer:**
"Connection timed out" - packets are being silently dropped. The client sends SYN packets but never gets a response. This is a network-layer problem: security group, NACL, routing, or the instance is unreachable. "Connection refused" - the client reached the server, but nothing is listening on that port. The server sent back a TCP RST. This means the network path is fine but PostgreSQL is either not running, listening on a different port, or the instance is stopped. "Password authentication failed" - the TCP connection was established, TLS handshake completed, and PostgreSQL responded. The network and the database are fine - the credentials are wrong (wrong username, wrong password, or the user does not exist in PostgreSQL).

**Red flags:**
- Treating all three as the same error
- Not knowing that "password failed" means the network path is working

---

### Q13 (Senior)

**Question:** You manage 15 Aurora clusters across 3 AWS accounts. How do you standardize security group management across all of them?

**What they're looking for:**
IaC, shared modules, AWS Organizations, SCPs, automation.

**Strong answer:**
I would use Terraform modules in a shared registry. The module defines the security group structure: port 5432 allowed from specified CIDR blocks (VPN ranges, application subnets), no public access by default. Each team calls the module with their specific inputs. I would use AWS Organizations with Service Control Policies to enforce that RDS instances cannot be created with security groups that allow 0.0.0.0/0 on port 5432. AWS Config rules would detect drift - if someone manually adds a permissive rule, Config flags it and optionally auto-remediates via a Lambda function. CloudTrail logs all security group changes across all accounts. I would also set up a monthly audit that reviews all security group rules attached to RDS resources.

**Red flags:**
- "I would manage each one manually through the Console"
- No mention of IaC or automation
- No mention of preventing overly permissive rules

---

## Topic 4 - Operations and Cleanup

---

### Q14 (Junior)

**Question:** You need to delete an Aurora cluster with 1 writer and 2 readers. What order do you delete things in?

**What they're looking for:**
Understanding the dependency chain: readers first, then writer, then cluster.

**Strong answer:**
Delete in this order: (1) delete both reader instances first - order between readers does not matter; (2) delete the writer instance; (3) wait for all instances to be fully deleted; (4) delete the cluster itself (with --skip-final-snapshot for lab environments, or take a final snapshot for production); (5) then delete the dependent resources: subnet group, security group, and parameter groups. You cannot delete the cluster while it still has instances, and you cannot delete the subnet group while the cluster uses it.

**Red flags:**
- Trying to delete the cluster first (will fail)
- Not mentioning snapshots
- Forgetting to delete dependent resources (subnet group, SG, parameter groups)

---

### Q15 (Junior)

**Question:** You forgot to delete a lab Aurora cluster and it ran for a full month. How would you estimate the cost?

**What they're looking for:**
Basic understanding of Aurora pricing: instance hours + storage + I/O.

**Strong answer:**
Aurora costs have three components: (1) Instance hours - each instance is billed per second with a 10-minute minimum. A `db.r6g.large` costs about $0.26/hour, so one instance running for 30 days is about $190. If the cluster had 3 instances, that is roughly $570. (2) Storage - $0.10 per GB-month. If the cluster stored 10 GB, that is $1. (3) I/O - $0.20 per million I/O requests. If the cluster was idle, this would be near zero. So the total for a 3-instance idle cluster is approximately $570 for a month. I would check AWS Cost Explorer filtered by Amazon RDS service to see the exact charges.

**Red flags:**
- Not knowing that instances are billed per-second
- Forgetting about the storage cost component
- "Aurora is free tier" - Aurora is NOT included in the AWS free tier

---

### Q16 (Mid)

**Question:** How does Aurora storage differ from standard RDS storage when it comes to cleanup? You drop a 50 GB table on Aurora - what happens to the space?

**What they're looking for:**
Understanding that Aurora storage reclamation is asynchronous.

**Strong answer:**
On standard RDS, when you DROP TABLE, the underlying EBS files are deleted and the space is freed immediately. You see FreeStorageSpace increase in CloudWatch right away. On Aurora, it is different. When you DROP TABLE, Aurora marks the space as available for reuse internally, but the VolumeBytesUsed CloudWatch metric may not decrease immediately. Aurora's storage subsystem reclaims space asynchronously - it can take hours or even days for the metric to reflect the freed space. Inside PostgreSQL, `pg_database_size()` will show the reduced size immediately after the drop. So the data is gone, the space is logically freed, but the metric catches up later. This surprises people who expect to see an immediate drop in the CloudWatch graph.

**Red flags:**
- "It works the same as regular RDS" - it does not
- Panic that the space was not freed when the metric does not change
- Suggesting VACUUM FULL to reclaim Aurora storage

---

### Q17 (Mid)

**Question:** You are setting up a new Aurora cluster for production. What CloudWatch alarms would you create on day one?

**What they're looking for:**
Proactive monitoring - not just reactive troubleshooting.

**Strong answer:**
At minimum: (1) CPUUtilization > 80% sustained for 5 minutes on each instance; (2) DatabaseConnections approaching max_connections (e.g., > 80% of the limit); (3) VolumeBytesUsed exceeding a threshold (e.g., 100 GB, and also the growth rate); (4) AuroraReplicaLag > 100ms on readers (indicates replication issues); (5) FreeableMemory < 500 MB on any instance; (6) Deadlocks > 0 (any deadlock should be investigated); (7) DMLLatency > 50ms (write performance degradation). I would also set up an alarm if the cluster member count drops below the expected number, and an alarm on DatabaseConnections dropping to zero (complete outage).

**Red flags:**
- Not mentioning replication lag monitoring
- Only setting up CPU and storage alarms
- "I would check CloudWatch manually" - alarms should be automated

---

### Q18 (Senior)

**Question:** Your company is migrating from self-managed PostgreSQL on EC2 to Aurora PostgreSQL. The team is worried about losing DBA control. What do you tell them?

**What they're looking for:**
Honest trade-off discussion, not a sales pitch for Aurora.

**Strong answer:**
There are real trade-offs. What you lose: SSH access to the host OS, ability to install arbitrary extensions (only AWS-approved ones), full superuser access (you get rds_superuser instead), control over PostgreSQL minor version timing (AWS pushes maintenance updates on a schedule), and direct access to pg_hba.conf and postgresql.conf (managed through parameter groups instead). What you gain: automated backups and PITR, automated patching (no more patching Linux kernels at 2am), sub-minute failover with Aurora replicas, storage that auto-scales without DBA intervention, built-in monitoring through CloudWatch, and a smaller operational surface area. For most production workloads, the trade-off is worth it. The exceptions are: workloads that require custom C extensions not in the Aurora approved list, or workloads that need very specific PostgreSQL configuration at the OS level (huge pages tuning, kernel parameters).

**Red flags:**
- "You do not lose anything" - you do lose things, be honest
- "Never use Aurora, self-managed is always better" - ignores operational benefits
- Not mentioning the extension limitation

---

### Q19 (Senior)

**Question:** You have an Aurora cluster with 1 writer and 3 readers. During peak hours, one reader's CPU is at 95% while the other two are at 20%. The reader endpoint is supposed to balance traffic. What is happening?

**What they're looking for:**
Understanding of DNS round-robin limitations and connection pool behavior.

**Strong answer:**
The reader endpoint uses DNS round-robin, which distributes connections, not queries. If the application opens a connection pool at startup and holds those connections for hours, all connections may have been assigned to the same reader by DNS at pool creation time. Later connections are not redistributed. To fix this: (1) configure the connection pool to recycle connections periodically (e.g., max lifetime of 15 minutes); (2) reduce the DNS TTL on the client side; (3) consider using Aurora's RDS Proxy, which handles connection distribution more intelligently; (4) if one specific reader is getting hammered, check if there is a cron job or batch process that connects directly to that reader's instance endpoint instead of the reader endpoint.

**Red flags:**
- "The reader endpoint should handle this automatically" - it distributes connections, not queries
- Not considering connection pool behavior
- Suggesting you increase the overloaded reader's instance size without investigating why traffic is uneven

---

### Q20 (Senior)

**Question:** An Aurora cluster has been running for a year. A developer asks you to change `max_connections` from the default to 500. How do you handle this?

**What they're looking for:**
Awareness that max_connections is a static parameter, impacts memory, and requires a reboot.

**Strong answer:**
First, I check why they need 500 connections. Each PostgreSQL connection uses approximately 5-10 MB of RAM. On a `db.r6g.large` with 16 GB RAM, 500 connections would consume 2.5-5 GB just for connection overhead. I would ask if they are using connection pooling - if not, that is the first fix (PgBouncer or RDS Proxy can multiplex hundreds of application connections onto 50 database connections). If they genuinely need 500 database connections, I modify the cluster parameter group to set `max_connections = 500`. This is a static parameter, so it requires a reboot of every instance in the cluster. I schedule the reboot during the maintenance window, reboot the readers first (one at a time), then reboot the writer (Aurora will failover to a reader during the writer reboot, causing 10-30 seconds of write unavailability). After the reboot, I verify with `SHOW max_connections` and monitor FreeableMemory to ensure the instances are not memory-starved.

**Red flags:**
- Changing the parameter without asking why they need that many connections
- Not knowing it is a static parameter that requires a reboot
- Rebooting all instances at the same time
- Not mentioning connection pooling as an alternative
