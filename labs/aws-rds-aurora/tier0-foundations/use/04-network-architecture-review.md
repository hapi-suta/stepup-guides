# Exercise 04: Network Architecture Review

**Duration:** 20 minutes
**Objective:** Identify security and availability problems in a flawed VPC architecture diagram and design a correct production-ready network layout for RDS.
**Prerequisites:** Build guide 04 (VPC and Network Configuration) complete

---

## Background

You are reviewing the AWS infrastructure for [CLIENT], a mid-sized company that recently migrated their database to RDS PostgreSQL. Their cloud engineer set it up quickly to meet a deadline and "will fix it later." You have been hired to audit the architecture before it goes into production next month.

Study the diagram below carefully. Assume this is their only database environment and it handles real customer data.

---

## Task 1: Find the Problems

**Business question:** What is wrong with this architecture, and what is the risk of each problem?

The diagram below represents their current setup. Read it carefully before answering.

```
AWS Region: us-east-1
+-----------------------------------------------------------------------+
|  VPC: 10.0.0.0/16                                                     |
|                                                                        |
|  +---------------------------+   +---------------------------+         |
|  | Availability Zone A       |   | Availability Zone B       |         |
|  | us-east-1a                |   | us-east-1b                |         |
|  |                           |   |                           |         |
|  |  +---------------------+  |   |   (no resources here)     |         |
|  |  | PUBLIC SUBNET       |  |   |                           |         |
|  |  | 10.0.1.0/24         |  |   |                           |         |
|  |  |                     |  |   |                           |         |
|  |  | [EC2 App Server]    |  |   |                           |         |
|  |  | [RDS PostgreSQL]    |  |   |                           |         |
|  |  |   db.t3.large       |  |   |                           |         |
|  |  |   Multi-AZ: No      |  |   |                           |         |
|  |  |                     |  |   |                           |         |
|  |  +---------------------+  |   +---------------------------+         |
|  |                           |                                         |
|  +---------------------------+                                         |
|                                                                        |
|  Internet Gateway: igw-abc123                                          |
|  Route Table for subnet 10.0.1.0/24:                                   |
|    0.0.0.0/0 -> igw-abc123   (all traffic -> internet)                 |
|                                                                        |
+-----------------------------------------------------------------------+

RDS Security Group: sg-rds-prod
  Inbound rules:
    Port 5432  Protocol: TCP  Source: 0.0.0.0/0  (ALL IPv4)
    Port 5432  Protocol: TCP  Source: ::/0        (ALL IPv6)

  Outbound rules:
    All traffic  All protocols  Destination: 0.0.0.0/0

EC2 Security Group: sg-app-prod
  Inbound rules:
    Port 443   Protocol: TCP  Source: 0.0.0.0/0
    Port 80    Protocol: TCP  Source: 0.0.0.0/0
    Port 22    Protocol: TCP  Source: 0.0.0.0/0

DB Subnet Group: manual-subnet-group
  Subnets: subnet-10.0.1.0/24 only (1 subnet, 1 AZ)

Parameter Group: default.postgres15
  (default AWS parameter group, unmodified)

Deletion Protection: Disabled
Public Accessibility: Yes
```

For each problem you find:
1. Name the problem
2. Explain the specific risk
3. State the fix

---

## Task 2: Design the Correct Architecture

After identifying the problems, sketch or describe the correct network architecture for this client. Include:

- Subnet layout (how many, what type, which AZs)
- Security group rules (what source, what port)
- DB subnet group configuration
- Multi-AZ configuration
- Any additional controls you would recommend

You do not need to draw ASCII art - a structured description with subnet names, CIDR blocks, and security group rules is sufficient.

---

## Answers

### Problem 1: RDS Instance in a Public Subnet

**What is wrong:** The RDS instance is in subnet `10.0.1.0/24`, which is a public subnet (it has a route to the Internet Gateway). This means the RDS instance has a network path to and from the public internet.

**Risk:** Combined with Problem 2 (the security group), this is a direct internet-facing database. Any attacker who finds the RDS endpoint (which is a resolvable DNS name) can attempt to connect. Even if the security group were correct, placing a database in a public subnet violates defense-in-depth. If a security group is misconfigured for even a moment, the database is exposed.

**Fix:** Move the RDS instance to a private subnet with no route to the Internet Gateway. Private subnets route to a NAT Gateway (for outbound-only internet access) or have no internet route at all. Databases typically need no outbound internet access, so they can sit in isolated private subnets with no NAT Gateway.

---

### Problem 2: Security Group Allows 0.0.0.0/0 on Port 5432

**What is wrong:** The inbound rule on `sg-rds-prod` allows all IPv4 (`0.0.0.0/0`) and all IPv6 (`::/0`) traffic on port 5432 - the PostgreSQL port.

**Risk:** This is the most critical problem. The PostgreSQL service is accessible from any IP address on the internet. Anyone can attempt to connect, brute-force credentials, probe for known vulnerabilities in the PostgreSQL protocol, or exploit any future CVEs. Even with strong passwords, this is an unacceptable attack surface for a production database.

**Fix:** Change the inbound rule to allow port 5432 only from the EC2 application security group (`sg-app-prod`) as the source. Security groups can reference other security groups, not just IP ranges. This means: only EC2 instances attached to `sg-app-prod` can connect to the database. No IP-based rule is needed.

Correct inbound rule:
```
Port 5432  Protocol: TCP  Source: sg-app-prod
```

Remove both `0.0.0.0/0` and `::/0` rules entirely.

---

### Problem 3: Single AZ Deployment (Multi-AZ: No)

**What is wrong:** The RDS instance is deployed in a single Availability Zone with no standby.

**Risk:** If us-east-1a has any kind of failure (hardware fault, power event, networking issue), the database goes down and stays down until AWS recovers the AZ or you manually restore from backup. RTO in this scenario is measured in hours, not minutes. For a database with real customer data, this is an unacceptable availability posture.

**Fix:** Enable Multi-AZ. RDS will create a synchronous standby replica in a second AZ. Failover is automatic and takes typically 60-120 seconds. For Aurora, use at least 2 instances across 2 AZs in the cluster.

---

### Problem 4: DB Subnet Group Spans Only One AZ

**What is wrong:** The DB subnet group `manual-subnet-group` contains only one subnet in one AZ.

**Risk:** A DB subnet group with only one AZ cannot support Multi-AZ deployments. Even if you tried to enable Multi-AZ, RDS would not be able to place the standby because there is no subnet in a second AZ for it to use. This configuration makes it structurally impossible to achieve Multi-AZ without rebuilding the subnet group.

**Fix:** Create a DB subnet group that includes at least 2 subnets in at least 2 different Availability Zones. AWS recommends 3 subnets in 3 AZs for maximum resilience. All subnets in the DB subnet group should be private subnets.

---

### Problem 5: Public Accessibility Enabled

**What is wrong:** `Public Accessibility: Yes` gives the RDS instance a publicly resolvable DNS endpoint. The instance is assigned a public IP address in addition to its private IP.

**Risk:** Even if you fix the security group, a publicly accessible RDS instance has a public IP and a public DNS name. This makes it discoverable via DNS enumeration and increases the attack surface. The instance is visible to the internet even if security groups are blocking connections.

**Fix:** Set `Public Accessibility: No`. The RDS instance should only be reachable via its private IP within the VPC. Applications connect using the private DNS endpoint, which resolves to the private IP.

---

### Problem 6: Port 22 Open to 0.0.0.0/0 on the App Server

**What is wrong:** The EC2 application server security group allows SSH (port 22) from any IP address.

**Risk:** This is not a database problem directly, but it is relevant because the EC2 instance has database credentials or can reach the database. If the EC2 instance is compromised via brute-forced SSH, the attacker gains access to the application environment and can connect to the database from inside the VPC where security group rules allow it.

**Fix:** Restrict SSH access to specific IP ranges (e.g., your office IP, a VPN IP, or a bastion host). Better: use AWS Systems Manager Session Manager for remote access instead of SSH entirely, which eliminates the need for port 22 to be open at all.

---

### Problem 7: Deletion Protection Disabled

**What is wrong:** `Deletion Protection: Disabled` means the instance can be deleted with a single API call or console click.

**Risk:** Accidental deletion, a misconfigured automation script running `aws rds delete-db-instance`, or a compromised IAM account can permanently destroy the database. Recovery requires restoring from the most recent automated backup - which means data loss up to the backup interval and hours of downtime.

**Fix:** Enable `Deletion Protection: Enabled`. This adds a guardrail that requires explicitly disabling deletion protection before the instance can be deleted. It prevents accidental deletions and adds friction for malicious ones.

---

### Problem 8: Default Unmodified Parameter Group

**What is wrong:** The instance uses the default AWS parameter group `default.postgres15` which is not modifiable (default groups are read-only).

**Risk:** This is a lower-severity operational issue rather than a security risk, but it means you cannot tune any parameters. If you need to enable `pgaudit` for query logging, change `shared_preload_libraries`, or adjust `work_mem` or `max_connections`, you cannot do it without a custom parameter group. Attempting to use a custom parameter group later requires an instance modification and may require a restart depending on the parameter type (static vs. dynamic).

**Fix:** Create a custom parameter group (even if initially identical to the default) and associate it with the instance from the start. This allows future tuning without scrambling during an incident or audit.

---

## Task 2 Answer - Correct Architecture

### Subnet Layout

```
VPC: 10.0.0.0/16

Public Subnets (for load balancers and NAT gateways):
  public-1a:  10.0.1.0/24   us-east-1a
  public-1b:  10.0.2.0/24   us-east-1b
  public-1c:  10.0.3.0/24   us-east-1c

Private Subnets (for EC2 application servers):
  app-1a:     10.0.11.0/24  us-east-1a
  app-1b:     10.0.12.0/24  us-east-1b
  app-1c:     10.0.13.0/24  us-east-1c

Isolated Subnets (for RDS - no internet route, no NAT):
  db-1a:      10.0.21.0/24  us-east-1a
  db-1b:      10.0.22.0/24  us-east-1b
  db-1c:      10.0.23.0/24  us-east-1c
```

### Route Tables

```
Public subnets:
  0.0.0.0/0 -> Internet Gateway

Private (app) subnets:
  0.0.0.0/0 -> NAT Gateway (in public subnet, same AZ)
  10.0.0.0/16 -> local

Isolated (db) subnets:
  10.0.0.0/16 -> local
  (no internet route - neither inbound nor outbound)
```

### DB Subnet Group

```
Name: prod-db-subnet-group
Subnets: db-1a, db-1b, db-1c
AZs covered: us-east-1a, us-east-1b, us-east-1c
```

### Security Groups

```
sg-alb (Application Load Balancer):
  Inbound:
    Port 443  TCP  0.0.0.0/0    (HTTPS from internet)
    Port 80   TCP  0.0.0.0/0    (redirect to 443)
  Outbound:
    Port 8080 TCP  sg-app       (to app servers)

sg-app (EC2 Application Servers):
  Inbound:
    Port 8080 TCP  sg-alb       (from load balancer only)
  Outbound:
    Port 5432 TCP  sg-rds       (to database)
    Port 443  TCP  0.0.0.0/0    (for AWS API calls, package updates via NAT)

sg-rds (RDS PostgreSQL):
  Inbound:
    Port 5432 TCP  sg-app       (from app servers only)
  Outbound:
    (no outbound rules needed - databases do not initiate connections)
```

### RDS Configuration

```
Multi-AZ: Enabled
Public Accessibility: No
Deletion Protection: Enabled
DB Subnet Group: prod-db-subnet-group
Parameter Group: custom-postgres15-prod (custom, not default)
Storage Encrypted: Yes (KMS key)
Enhanced Monitoring: Enabled (60-second intervals)
Performance Insights: Enabled
Automated Backups: 7-day retention minimum (30 days for production)
Backup Window: 03:00-04:00 UTC (lowest traffic period)
Maintenance Window: Sunday 04:00-05:00 UTC
```

### Additional Recommended Controls

- Enable VPC Flow Logs on the VPC to capture all network traffic for audit and incident investigation.
- Enable RDS CloudTrail logging to capture all API calls made against the RDS service.
- Set up CloudWatch alarms on: FreeStorageSpace, CPUUtilization, DatabaseConnections, FreeableMemory, and ReplicaLag.
- Enable AWS Config rules to enforce: `rds-instance-public-access-check`, `rds-multi-az-support`, `rds-storage-encrypted`, and `rds-deletion-protection-enabled`.
- If developers need direct database access for debugging, route connections through AWS Systems Manager Port Forwarding to the RDS private endpoint - no bastion host or open SSH ports needed.

---

## Summary of Key Takeaways

- Databases must never be in public subnets. Public subnet means routable from the internet. Databases should be in isolated private subnets with no internet route in either direction.
- Security group source should be another security group, not an IP range, when the clients are AWS resources. `Source: sg-app` means only instances in that security group can connect - IP changes do not break the rule.
- A DB subnet group must span at least 2 AZs before Multi-AZ is possible. Plan the subnet layout before creating the database, not after.
- `0.0.0.0/0` on port 5432 is never acceptable in any environment, including development. Use security group references or specific IP ranges.
- Defense in depth means multiple layers: private subnet (no route), security group (no public access), parameter group (logging enabled), deletion protection, and monitoring. No single layer is sufficient on its own.
- Public Accessibility and Public Subnet are two separate settings that both need to be correct. An instance can be in a private subnet but still have Public Accessibility enabled, which assigns it a public IP.
