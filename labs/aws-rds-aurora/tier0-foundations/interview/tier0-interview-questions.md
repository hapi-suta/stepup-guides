# Tier 0 - Foundations: Interview Questions

Interview questions graduated by experience level. Use these for self-assessment or mock interviews.

---

## Topic 1: Managed Databases and Shared Responsibility

### Junior Level

1. **Q:** What is a managed database service, and how is it different from running PostgreSQL on an EC2 instance?
   **What they're looking for:** Basic understanding that AWS handles infrastructure tasks, not just "AWS runs it for you."
   **Strong answer:** A managed database service like RDS handles OS patching, hardware provisioning, storage management, and automated backups. You install PostgreSQL on EC2 yourself and own all of that. With RDS, you focus on schema design, queries, and application logic - not keeping the server running.

2. **Q:** What does AWS handle in RDS, and what are you still responsible for?
   **What they're looking for:** A clear list on both sides, not a vague "AWS handles everything."
   **Strong answer:** AWS handles: hardware, OS patching, engine patching (with your approval window), storage provisioning, automated backups, and Multi-AZ failover. You handle: schema design, indexing, query optimization, application-level security, parameter group tuning, access control (IAM and database users), and data integrity.

3. **Q:** What is the AWS shared responsibility model?
   **What they're looking for:** That responsibility is split - AWS secures the cloud, you secure what's in it.
   **Strong answer:** AWS is responsible for the security OF the cloud - physical datacenters, hypervisors, managed service infrastructure. You are responsible for security IN the cloud - what data you store, who can access it, how it's encrypted, and how your application connects to it.

### Mid Level

4. **Q:** How does the shared responsibility model change your backup strategy when using RDS?
   **What they're looking for:** Understanding that automated backups exist but are not sufficient on their own - you still need to think about retention, cross-region copies, and restore testing.
   **Strong answer:** RDS automated backups cover point-in-time recovery within the retention window (up to 35 days). But you are still responsible for: setting an appropriate retention period, enabling cross-region backup copies for DR, taking manual snapshots before major changes, and - critically - regularly testing restores. AWS backing up your data does not mean you have a working recovery plan.

5. **Q:** RDS handles minor version patching automatically. What risks does this introduce, and how do you manage them?
   **What they're looking for:** Awareness that auto-patching can break applications, and a process to manage it.
   **Strong answer:** Minor version updates can introduce behavior changes that break application queries or extensions. To manage this: pin your preferred minor version when stability matters, use maintenance windows that align with low-traffic periods, test patches in staging before they hit production, and monitor for query plan regressions after any patch. For critical databases, disable auto minor version upgrade and manage patching manually.

6. **Q:** A developer asks why they can't SSH into the RDS instance to check PostgreSQL logs directly. How do you explain this, and what do you offer instead?
   **What they're looking for:** Ability to explain the managed model clearly and redirect to the correct tools.
   **Strong answer:** RDS runs on infrastructure managed by AWS - you never have OS access. That is part of what makes it managed. For logs, you have several options: publish PostgreSQL logs to CloudWatch Logs for querying and alerting, use the RDS console to download log files, or query `pg_stat_activity`, `pg_stat_statements`, and `pg_logs` through the database connection itself.

### Senior Level

7. **Q:** When would you choose self-managed PostgreSQL on EC2 over RDS? Walk me through your decision process.
   **What they're looking for:** Judgment and trade-off reasoning, not a preference for one option.
   **Strong answer:** I would choose self-managed when: I need PostgreSQL extensions not supported by RDS (e.g., certain contrib modules or custom extensions), I need direct OS tuning for very specific workloads (huge pages, NUMA settings), I need full control over WAL archiving and replication topology, or the licensing and instance costs at scale make EC2 more economical. RDS wins in most cases because the operational overhead of self-managing - patching, HA, backups, monitoring - is significant. The break-even point is usually when you have dedicated DBA capacity and very specific technical requirements.

8. **Q:** What are the hidden costs of using a managed database service that are easy to overlook?
   **What they're looking for:** Financial and operational awareness beyond the instance price.
   **Strong answer:** The obvious cost is the instance hourly rate. The hidden costs include: storage I/O charges (especially with gp2 volumes under heavy write load), data transfer out of the region, Multi-AZ doubles your instance cost, read replicas billed separately, snapshot storage beyond the retention window, and Parameter Store or Secrets Manager API calls if you use them heavily. On the operational side: you lose the ability to do OS-level tuning, you are dependent on AWS's patching schedule, and you can hit limits on max connections or extensions that require workarounds like PgBouncer.

9. **Q:** You inherit a fleet of 30 RDS databases with no tagging strategy, inconsistent parameter groups, and no documented maintenance windows. How do you approach remediating this?
   **What they're looking for:** A systematic approach to operational hygiene at scale, not just "fix each one."
   **Strong answer:** First, inventory everything using AWS Config and the RDS API - export all instances with their parameter groups, maintenance windows, backup retention, and tags to a spreadsheet. Then establish standards: a tagging taxonomy (environment, owner, team, cost-center), two or three baseline parameter groups by workload type, and approved maintenance windows by environment tier. Then remediate incrementally - start with production, use Terraform or CloudFormation to codify the target state, and migrate databases to managed parameter groups so future changes are tracked in code. Build a Config rule to flag new databases that violate the standards.

### Principal/Staff Level

10. **Q:** How do you design an organization's database strategy around managed services? What governance structures are required?
    **What they're looking for:** Org-level thinking - standards, enforcement, cost visibility, exception handling.
    **Strong answer:** Start with a platform team that owns the database standards and tooling. Define: which managed services are approved (RDS, Aurora, DynamoDB), what workloads belong where, and when an exception process is required. Governance requires: a tagging and cost allocation policy enforced via SCPs, a service catalog of approved database configurations teams can self-serve, automated compliance checks via AWS Config rules (encryption at rest, backup enabled, Multi-AZ for production), and a review process for non-standard requests. The goal is making the right thing easy and the wrong thing visible - teams should be able to spin up a compliant database in minutes, but spinning up a non-compliant one should require an approval gate.

---

## Topic 2: RDS for PostgreSQL vs Aurora PostgreSQL

### Junior Level

1. **Q:** What is the basic difference between Amazon RDS for PostgreSQL and Amazon Aurora PostgreSQL?
   **What they're looking for:** That they are both managed PostgreSQL, but Aurora uses a different underlying storage architecture.
   **Strong answer:** Both run PostgreSQL and are managed by AWS, but they are built differently. RDS for PostgreSQL runs standard PostgreSQL on EBS storage - one primary, optional replicas. Aurora PostgreSQL uses a distributed storage layer built by AWS that automatically replicates across six storage nodes in three AZs. Aurora is faster to fail over and has higher durability by design, but costs more and has some behavioral differences from vanilla PostgreSQL.

2. **Q:** Can you use the same PostgreSQL client and SQL queries against both RDS and Aurora?
   **What they're looking for:** Yes - but awareness that there are some Aurora-specific behaviors.
   **Strong answer:** Yes. Aurora PostgreSQL is wire-compatible with PostgreSQL, so psql, pgAdmin, JDBC, and application ORMs all connect the same way. Your SQL queries work identically. The differences show up at the infrastructure layer - failover behavior, replication lag, storage limits - not at the query level. Some edge cases around extensions and PostgreSQL internals differ, but for most applications the two are interchangeable.

3. **Q:** What is a read replica, and why would you use one?
   **What they're looking for:** Basic replication concept and a real use case.
   **Strong answer:** A read replica is a copy of your database that receives streaming replication from the primary and handles SELECT queries. You use them to offload read traffic from the primary - reporting queries, analytics, or read-heavy application tiers connect to the replica so the primary handles only writes. In RDS you can have up to 5 read replicas. In Aurora, replicas share the same storage layer and fail over faster than RDS replicas.

### Mid Level

4. **Q:** How does Aurora's storage architecture differ from RDS? How does this difference affect failover time?
   **What they're looking for:** Understanding of Aurora's distributed storage layer and its failover implications.
   **Strong answer:** RDS uses EBS volumes attached to the instance. Replication happens at the database layer - the replica streams WAL from the primary. During failover, a replica must be promoted and finish replaying WAL before it can accept writes, which takes 60-120 seconds typically. Aurora separates compute from storage. The storage layer is a distributed system across six nodes in three AZs - all Aurora instances in the cluster read from and write to the same shared storage. During failover, a replica just needs to be promoted to primary at the compute layer, because it already has access to all the data. Aurora failover typically completes in under 30 seconds, often under 15.

5. **Q:** What is an Aurora cluster endpoint vs a reader endpoint, and when do you use each?
   **What they're looking for:** Endpoint routing awareness and how to build read/write separation correctly.
   **Strong answer:** The cluster endpoint always points to the current primary writer. Your application's write connections go here. When failover occurs, this endpoint automatically updates to point to the new primary - your application reconnects and continues. The reader endpoint load-balances across all Aurora replicas. Read-heavy traffic like reporting queries or background jobs connect here. If you have a single replica, it still makes sense to use the reader endpoint because AWS will handle routing as you add or remove replicas without application changes.

6. **Q:** Aurora costs more per vCPU-hour than RDS. How do you justify the cost to a non-technical stakeholder?
   **What they're looking for:** Ability to frame infrastructure cost in business terms.
   **Strong answer:** Aurora's higher compute cost buys faster failover (30 seconds vs 2 minutes), higher durability (6-way replication vs 2-way EBS mirror), and up to 15 read replicas vs 5 for RDS. For a production database where downtime costs money - say $10,000 per hour in lost revenue - reducing failover time from 2 minutes to 30 seconds saves $2,500 per incident. The break-even on Aurora's premium is usually less than one avoided outage per year. The math changes for dev/test or low-traffic workloads where RDS is the better choice.

### Senior Level

7. **Q:** When would you migrate an existing RDS for PostgreSQL database to Aurora? What are the risks?
   **What they're looking for:** A thoughtful migration assessment, not just "Aurora is better so always migrate."
   **Strong answer:** I would consider migrating when: failover time is a documented problem, we are hitting the 5 read replica limit, we need Aurora Serverless for variable workloads, or storage costs on EBS are significant relative to Aurora's model. The risks are real: Aurora PostgreSQL is not identical to community PostgreSQL - some extensions are unsupported, internal behavior (vacuum, WAL settings) differs, and some pg_internal views behave differently. Migration path is a snapshot restore or DMS replication, both requiring a maintenance window or blue-green deployment for zero downtime. I always run the target workload on Aurora in parallel for at least two weeks before cutting over, with query plan regression testing against pg_stat_statements.

8. **Q:** When is Aurora the wrong choice?
   **What they're looking for:** Honest evaluation of Aurora's limitations - not everyone defaults to Aurora.
   **Strong answer:** Aurora is wrong when: the database is dev/test and paying for Aurora's premium is waste, you need a PostgreSQL extension Aurora does not support (aurora does not support all contrib modules), you need full community PostgreSQL compatibility for compliance or portability reasons, the workload is write-heavy with small storage (Aurora's minimum 10GB in 10GB increments can be more expensive for tiny databases), or you are running in a region where Aurora is not available. Aurora Serverless v2 helps with cost on variable workloads but introduces connection latency during cold scaling that is unacceptable for some latency-sensitive applications.

9. **Q:** You have an Aurora cluster where one read replica is consistently 30 seconds behind the primary. What do you investigate?
   **What they're looking for:** Systematic diagnosis of replication lag in Aurora, which differs from standard PostgreSQL replication.
   **Strong answer:** In Aurora, replication lag is almost always a compute bottleneck on the replica, not a storage bottleneck - because all nodes share storage. I check: instance size of the replica (is it undersized relative to write volume?), CPU and memory on the replica during the lag period, whether there are long-running queries on the replica blocking transaction application, and `AuroraReplicaLag` in CloudWatch for trends. I also check if the primary has a sudden burst of write activity correlating with the lag. The fix is usually upsizing the replica instance, adding DDL query timeouts, or enabling `aurora_replica_read_consistency` settings depending on the workload.

### Principal/Staff Level

10. **Q:** How do you evaluate total cost of ownership between RDS and Aurora for a fleet of 50+ databases? Walk me through your framework.
    **What they're looking for:** A structured TCO model, not just compute pricing.
    **Strong answer:** I build a TCO model with four categories. Compute: instance hours times hourly rate - Aurora runs about 20% more expensive per vCPU. Storage: RDS is per-GB EBS provisioned, Aurora is per-GB consumed with I/O charges (or the Aurora I/O-Optimized pricing model if I/O is high). Operations: Aurora's faster failover and higher durability reduce on-call burden - I quantify this as avoided incident hours. Data transfer: same for both, negligible difference. For a fleet of 50+, I also factor in: Reserved Instance vs Savings Plan discounts (Aurora uses Compute Savings Plans, RDS uses Reserved Instances), the cost of migration itself, and whether Aurora Serverless v2 reduces over-provisioning on variable workloads. In my experience, high-traffic production databases almost always favor Aurora on true TCO when you include incident costs. Dev/test and low-traffic databases almost always favor RDS.

---

## Topic 3: AWS Account, IAM, Regions, and AZs

### Junior Level

1. **Q:** What is the difference between an IAM user and an IAM role?
   **What they're looking for:** Users are long-lived credentials, roles are assumed temporarily - and why that matters.
   **Strong answer:** An IAM user has permanent credentials - an access key ID and secret. An IAM role has no credentials of its own. Instead, it is assumed by a trusted entity (an EC2 instance, a Lambda function, another AWS account, or a human via SSO), and AWS issues temporary credentials that expire. Roles are preferred because temporary credentials reduce the blast radius of a leaked key, and you do not have to rotate them manually.

2. **Q:** What is an AWS Region, and what is an Availability Zone?
   **What they're looking for:** Geographic separation, and that AZs are separate failure domains within a region.
   **Strong answer:** A Region is a geographic area like us-east-1 (Northern Virginia) or eu-west-1 (Ireland). Each Region has multiple Availability Zones - physically separate datacenters with independent power, cooling, and networking, but connected by low-latency fiber. AZs within a region are close enough for synchronous replication between them but far enough apart that a failure in one (power outage, flooding) does not affect the others. Multi-AZ RDS uses this - the standby is in a different AZ than the primary.

3. **Q:** What is an IAM policy, and how does it attach to a user or role?
   **What they're looking for:** JSON document, allow/deny, actions and resources, and how it attaches.
   **Strong answer:** An IAM policy is a JSON document that defines what actions are allowed or denied on which resources. For example, a policy might allow `rds:DescribeDBInstances` on all resources, or restrict `rds:CreateDBSnapshot` to a specific database ARN. Policies attach to users, groups, or roles. An identity can have multiple policies attached - permissions are the union of all attached policies, minus any explicit denies. The two main types are AWS managed policies (maintained by AWS) and customer managed policies (you write and control).

### Mid Level

4. **Q:** How would you structure IAM for a DBA team? What permissions should DBAs have vs developers?
   **What they're looking for:** Least privilege design and separation of concerns, not just "DBAs get admin."
   **Strong answer:** I create IAM roles, not users, and assign them via SSO groups. DBA role permissions: full RDS read access (`rds:Describe*`), snapshot creation and restore, parameter group and option group management, and CloudWatch read for database metrics. Developers get read-only RDS describe permissions so they can see instance info, but no ability to modify instances, change parameter groups, or access snapshots. No one gets direct access to production - DBAs use a separate production-access role that requires MFA and logs to CloudTrail. Credentials for database users (passwords) live in Secrets Manager with resource-based policies scoped to the services that need them.

5. **Q:** Why should applications use IAM roles instead of IAM users with access keys?
   **What they're looking for:** Security reasoning around credential rotation and blast radius.
   **Strong answer:** Access keys are long-lived - if they leak (committed to git, exposed in logs), they remain valid until manually rotated. IAM roles issue temporary credentials that expire in 15 minutes to 12 hours. An EC2 instance, ECS task, or Lambda function that assumes a role never needs a hardcoded key. If the instance is compromised, the credentials expire quickly. AWS SDKs automatically retrieve and refresh role credentials from the instance metadata service, so there is no application code change needed. It is strictly better in every security dimension.

6. **Q:** A developer says their application cannot connect to RDS. They have the correct endpoint and credentials. What IAM or networking issues do you investigate?
   **What they're looking for:** Systematic troubleshooting across both IAM and network layers.
   **Strong answer:** First, clarify the error - "connection refused" vs "connection timed out" vs "auth failure" point to different root causes. For IAM: if the application uses IAM database authentication, check that the IAM role has `rds-db:connect` permission and the database user is configured correctly. For networking: check security groups - is port 5432 open from the application's security group or IP? Check if the RDS instance is in a private subnet - can the application reach it (same VPC, peering, VPN)? Check NACLs for outbound ephemeral port rules. Finally, check if the RDS instance is in "available" state and not in a maintenance window or failing over.

### Senior Level

7. **Q:** How do you design a multi-account AWS strategy for database environments? What is the role of Organizations and SCPs?
   **What they're looking for:** Enterprise-grade account structure and policy enforcement at the organization level.
   **Strong answer:** I use an account-per-environment model: separate accounts for production, staging, and development, plus a shared services account for centralized tooling (monitoring, logging, secrets). AWS Organizations groups these into OUs - Production OU, NonProduction OU, Shared OU. SCPs (Service Control Policies) apply guardrails at the OU level that no account admin can override: production databases must be Multi-AZ, encryption at rest is mandatory, deletion protection is on, and direct public access is denied. This means even if someone in the production account tries to create an unencrypted single-AZ database, the SCP blocks it. SCPs do not grant permissions - they restrict the maximum permissions available in the account. IAM policies in each account then grant the actual permissions within those guardrails.

8. **Q:** How do you handle cross-account access to RDS - for example, a centralized DBA tooling account that needs to take snapshots of databases in 10 production accounts?
   **What they're looking for:** Cross-account role assumption and trust relationships, not just "give it access keys."
   **Strong answer:** The tooling account assumes a role in each production account using cross-account role assumption. In each production account, I create a role (e.g., `suta-dba-tooling-role`) with a trust policy that allows the tooling account's IAM principal to assume it. The role has permissions scoped to what the tooling needs - in this case `rds:CreateDBSnapshot`, `rds:CopyDBSnapshot`, and `rds:DescribeDBInstances`. The tooling account uses `sts:AssumeRole` to get temporary credentials for each production account and runs the snapshot jobs. No long-lived credentials ever leave the tooling account. I audit all role assumptions via CloudTrail in a centralized log archive account.

### Principal/Staff Level

9. **Q:** How do you enforce least privilege at scale across hundreds of databases and dozens of teams without creating a ticket-driven bottleneck?
   **What they're looking for:** Scalable governance architecture - self-service within guardrails, not manual approval for everything.
   **Strong answer:** The key is making the self-service path also the compliant path. I do this in layers. SCPs block catastrophically bad actions at the organization level - no human intervention needed. A service catalog publishes pre-approved IAM role templates for common personas (app developer, analyst, DBA) that teams can deploy themselves. Permission boundaries on all human roles prevent privilege escalation even if someone attaches an admin policy. For database credentials specifically, Secrets Manager with automatic rotation means no team ever holds long-lived passwords. AWS Config rules continuously audit and alert on non-compliant configurations - a daily report goes to team leads, not to a central bottleneck. The only things requiring central approval are exceptions to standards, and those go through a lightweight RFC process with a 48-hour SLA.

---

## Topic 4: VPC Networking for Databases

### Junior Level

1. **Q:** What is a VPC, and why do databases go in private subnets?
   **What they're looking for:** Basic VPC concept and the security reason for private subnets.
   **Strong answer:** A VPC (Virtual Private Cloud) is a logically isolated network in AWS that you control - you define the IP range, subnets, routing, and firewall rules. Private subnets have no route to the internet gateway, so resources in them cannot receive inbound traffic from the internet or initiate outbound connections without a NAT gateway. Databases go in private subnets because they should never be directly reachable from the internet. Your application servers in public or private subnets connect to the database, but an attacker on the internet cannot reach port 5432 even if they know the endpoint.

2. **Q:** What is a security group, and how does it control traffic to RDS?
   **What they're looking for:** Stateful firewall rules at the instance level.
   **Strong answer:** A security group is a stateful firewall attached to an AWS resource. Stateful means if you allow inbound traffic on port 5432, the response traffic is automatically allowed without an explicit outbound rule. For RDS, you attach a security group that controls which sources can connect. Best practice is to allow inbound 5432 only from the security group of your application servers - not from an IP range. This means only resources in that application security group can reach the database, regardless of IP.

3. **Q:** What is a DB subnet group in RDS, and why is it required?
   **What they're looking for:** Understanding that RDS needs to know which subnets it can place instances in, especially for Multi-AZ.
   **Strong answer:** A DB subnet group is a collection of subnets in different AZs that RDS can use to place database instances. It is required because Multi-AZ needs to place the primary and standby in different AZs - it uses the subnet group to find suitable subnets in those AZs. Best practice is to create a DB subnet group with private subnets in at least two AZs. RDS will not let you create a Multi-AZ instance without a subnet group that spans multiple AZs.

### Mid Level

4. **Q:** How do security groups and NACLs differ? When would you use each?
   **What they're looking for:** Stateful vs stateless, resource vs subnet level, and practical use cases.
   **Strong answer:** Security groups are stateful and operate at the resource level - rules apply to specific instances or RDS clusters. If you allow inbound, the return traffic is automatic. NACLs (Network Access Control Lists) are stateless and operate at the subnet level - they apply to all traffic crossing a subnet boundary. Because NACLs are stateless, you must explicitly allow both inbound and outbound traffic, including the ephemeral ports (1024-65535) for return traffic. Security groups are the primary tool for database access control because they are easier to manage and reference each other by group ID. NACLs are a secondary layer for subnet-wide policies - for example, blocking a known malicious IP range at the subnet boundary regardless of which security group a resource has.

5. **Q:** A developer reports "connection timed out" when connecting to RDS from an EC2 instance. Walk me through your troubleshooting steps.
   **What they're looking for:** Systematic elimination of networking issues - not jumping to conclusions.
   **Strong answer:** "Connection timed out" means the TCP connection is not completing - the packet is being dropped, not rejected. I work through the layers: First, verify the RDS instance is in "available" state. Second, check the security group on the RDS instance - is there an inbound rule on port 5432 that allows the EC2 instance's security group? Third, check the security group on the EC2 instance - is outbound traffic on port 5432 allowed (default yes, but check if someone restricted outbound)? Fourth, check NACLs on both the RDS subnet and the EC2 subnet - inbound and outbound rules for port 5432 and ephemeral ports. Fifth, check route tables - can the EC2 subnet reach the RDS subnet? Sixth, confirm the RDS endpoint DNS resolves to a private IP and that the EC2 instance can resolve it. Usually it is a security group rule missing on the RDS side.

6. **Q:** What is a VPC endpoint for RDS, and when do you need one?
   **What they're looking for:** Understanding of PrivateLink and when traffic routing matters.
   **Strong answer:** A VPC endpoint for RDS (via PrivateLink) keeps traffic between your VPC and RDS on the AWS private network instead of routing through the internet. For RDS specifically, this matters when you access the RDS API (not the database port) - for example, when using the AWS CLI to describe instances or take snapshots from within a VPC. Without a VPC endpoint for the RDS API, those API calls traverse the internet. For the actual database connection (port 5432), the endpoint already resolves to a private IP within your VPC, so database traffic stays private by default. You would add a VPC endpoint for RDS when your private subnets have no internet access (no NAT gateway) and you need API access to RDS from within the VPC.

### Senior Level

7. **Q:** Design a network topology for a three-tier web application that uses RDS PostgreSQL. Explain every component and why it is placed where it is.
   **What they're looking for:** A complete, defensible architecture - not just "put it in a private subnet."
   **Strong answer:** Three-tier: public subnets for load balancers, private app subnets for application servers, private data subnets for RDS. The VPC spans at least two AZs. The internet-facing Application Load Balancer sits in public subnets in both AZs. Application servers (EC2 or ECS) in private app subnets receive traffic from the ALB only - their security group allows inbound from the ALB security group on the app port. RDS is in private data subnets with a security group that allows inbound 5432 only from the application server security group. Application servers reach the internet for package updates via a NAT gateway in the public subnet. RDS has no outbound internet route at all. A bastion host (or AWS Systems Manager Session Manager - better, no open port 22) provides DBA access to RDS without a public endpoint. CloudWatch, Secrets Manager, and other AWS service calls from the app tier go through VPC endpoints to avoid NAT costs and keep traffic private.

8. **Q:** How do you handle cross-VPC database access - for example, a microservice in VPC-B that needs to query a database in VPC-A?
   **What they're looking for:** VPC peering vs PrivateLink vs Transit Gateway trade-offs.
   **Strong answer:** Three options. VPC peering: direct connectivity between two VPCs using private IPs. Simple to set up, no bandwidth bottleneck, but does not scale well beyond a handful of VPC pairs (non-transitive, and the peering mesh gets complicated with many VPCs). PrivateLink: expose the database (or a proxy in front of it) as a private endpoint service. The consumer VPC creates an interface endpoint. Traffic stays on AWS backbone, fully private, and scales well. The limitation is it is one-directional and requires a load balancer in front of RDS. Transit Gateway: a regional hub that connects many VPCs and on-premises networks. Good for organizations with many VPCs that need flexible routing. More complex and has per-GB transfer costs. For most cases with 2-5 VPCs I use peering. For large organizations with many VPCs I use Transit Gateway. For exposing a shared database to many VPCs cleanly, I prefer a proxy with PrivateLink.

---

## Topic 5: PostgreSQL Fundamentals

### Junior Level

1. **Q:** What is the difference between a database and a schema in PostgreSQL?
   **What they're looking for:** The hierarchy - instance, database, schema, table - and that connections are per-database.
   **Strong answer:** A PostgreSQL instance (cluster) can contain many databases. A database is an isolated namespace - you connect to one database at a time, and you cannot query across databases in a single query. Within a database, schemas are namespaces for organizing objects (tables, views, functions). The default schema is `public`. You can have tables with the same name in different schemas within the same database. A common pattern is one schema per application or per tenant within a shared database.

2. **Q:** What does `\dt` show in psql, and how do you list tables in a specific schema?
   **What they're looking for:** psql meta-commands and schema awareness.
   **Strong answer:** `\dt` lists tables in the current search path, which defaults to the `public` schema. To list tables in a specific schema, use `\dt schema_name.*`. To list tables in all schemas, use `\dt *.*`. You can also query the information schema: `SELECT table_name FROM information_schema.tables WHERE table_schema = 'myschema'`. The `\dn` command lists all schemas in the current database.

3. **Q:** What is the difference between a PostgreSQL role and a user?
   **What they're looking for:** That in PostgreSQL, users and roles are the same thing - users are roles with login privilege.
   **Strong answer:** In PostgreSQL, there is no structural difference between a user and a role. `CREATE USER` is shorthand for `CREATE ROLE ... WITH LOGIN`. A role with the LOGIN attribute can connect to the database - that is a user. A role without LOGIN is used for grouping privileges. You create a role like `app_readonly`, grant it permissions on tables, then grant that role to user accounts. When those users connect, they inherit the role's permissions. This is how you manage permissions without duplicating grants across many individual accounts.

### Mid Level

4. **Q:** Explain PostgreSQL's role-based access model. How do you structure roles for a production database with multiple application tiers?
   **What they're looking for:** Role hierarchy, least privilege, and practical schema for app access.
   **Strong answer:** PostgreSQL's access model uses role inheritance. You create functional roles that represent privilege sets, then assign user accounts to those roles. For a production database I typically create: `app_read` (SELECT on all tables in the app schema), `app_write` (SELECT, INSERT, UPDATE, DELETE), `app_admin` (DDL privileges for schema changes during deployments), `reporting_read` (SELECT on reporting schema or materialized views only). Application service accounts get `app_read` or `app_write` depending on what they need. No application service account gets `app_admin`. DBA accounts get `app_admin` only through an elevated session, not as their default role. Default privileges (`ALTER DEFAULT PRIVILEGES`) ensure new tables automatically inherit the correct grants without manual intervention after each migration.

5. **Q:** A developer runs a migration that adds a new table, but the application's read-only user gets "permission denied" on that table. What happened and how do you fix it?
   **What they're looking for:** Understanding of default privileges and how grants do not automatically apply to new objects.
   **Strong answer:** PostgreSQL grants are not retroactive. When the migration created the new table, it was owned by the migration user. Existing GRANT statements on old tables do not apply to the new one. The fix is to run `GRANT SELECT ON new_table TO app_read`. To prevent this from happening again, set default privileges: `ALTER DEFAULT PRIVILEGES FOR ROLE migration_user IN SCHEMA app GRANT SELECT ON TABLES TO app_read`. This ensures any future table created by `migration_user` in the `app` schema automatically gets SELECT granted to `app_read`. This should be part of the database setup runbook.

6. **Q:** How does `search_path` work, and what security risk does it introduce?
   **What they're looking for:** Implicit schema resolution and schema injection risk.
   **Strong answer:** `search_path` is a session-level variable that lists schemas PostgreSQL searches when you reference an object without an explicit schema prefix. The default is `"$user", public` - first a schema matching your username, then public. If you `SELECT * FROM orders`, PostgreSQL looks for `orders` in each schema in the path and uses the first match. The security risk is search_path manipulation: if a user can create objects in a schema that appears before your application schema in the path, they can intercept queries by creating a table or function with the same name. Mitigation: always qualify object names with the schema in application code, revoke CREATE on the public schema from PUBLIC (`REVOKE CREATE ON SCHEMA public FROM PUBLIC`), and set a fixed search_path for application roles.

7. **Q:** What is MVCC in PostgreSQL, and how does it affect query behavior?
   **What they're looking for:** Core concurrency mechanism and its practical implications - bloat, vacuum, read consistency.
   **Strong answer:** MVCC (Multi-Version Concurrency Control) is how PostgreSQL handles concurrent reads and writes without blocking. Instead of locks, PostgreSQL keeps multiple versions of a row. A writer creates a new version; readers see the version that was current when their transaction started. Readers never block writers and writers never block readers. The implication for query behavior: a long-running query sees a consistent snapshot of the database from when it started, even if other transactions are committing changes during it. The operational implication: old row versions accumulate and must be cleaned up by VACUUM. On RDS, autovacuum runs automatically, but heavy write workloads can accumulate bloat faster than autovacuum keeps up, leading to table bloat and eventually transaction ID wraparound if left unmanaged.

### Senior Level

8. **Q:** How does MVCC interact with RDS-specific constraints - specifically autovacuum behavior and transaction ID wraparound risk?
   **What they're looking for:** Deep understanding of vacuum mechanics in a managed environment and how to tune it.
   **Strong answer:** Transaction ID wraparound is one of the most dangerous failure modes in PostgreSQL - if a database reaches the wraparound limit, PostgreSQL shuts down to protect data integrity. Every row version has an XID, and XIDs are 32-bit integers that wrap around at ~2 billion. VACUUM freezes old rows, marking them as permanently visible and resetting their XID counter. On RDS, autovacuum is enabled by default but uses conservative defaults. On high-write tables, autovacuum can fall behind - especially if long-running queries hold transaction snapshots that prevent vacuum from cleaning old versions. I monitor `pg_stat_user_tables.n_dead_tup` for dead tuple accumulation, `age(datfrozenxid)` per database for wraparound distance, and CloudWatch's `MaximumUsedTransactionIDs` metric. If a table is consistently behind, I tune `autovacuum_vacuum_scale_factor`, `autovacuum_vacuum_cost_delay`, and `autovacuum_max_workers` at the parameter group level. For emergency situations, I run manual VACUUM FREEZE on the affected table.

### Principal/Staff Level

9. **Q:** How do you standardize PostgreSQL configuration and role management across 100+ RDS instances without requiring manual work per instance?
    **What they're looking for:** Infrastructure-as-code, automated enforcement, and drift detection - not manual runbooks.
    **Strong answer:** Three layers. Configuration: manage RDS parameter groups as code in Terraform. Define baseline groups by workload type (OLTP, analytics, reporting), version them, and use Terraform to apply them across all instances in the correct environment. Any change goes through code review and is applied consistently. Role management: use a bootstrapping Lambda or Flyway migration that runs on instance creation and applies the standard role structure - functional roles, default privileges, revoke public schema permissions, set search_path. This runs via an automation account, not manual DBA steps. Drift detection: a scheduled Lambda queries `pg_roles` and `pg_default_acl` on every instance and compares against the expected baseline. Any deviation triggers a CloudWatch alarm. For parameter drift, use AWS Config to detect parameter group changes and alert. The goal is that after day one, no DBA ever manually configures a database - all configuration is declarative and audited.

---
