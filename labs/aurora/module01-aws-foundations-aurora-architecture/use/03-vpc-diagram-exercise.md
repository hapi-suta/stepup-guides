# Exercise 03: VPC Architecture Design

**Duration:** 30 minutes
**Objective:** Design a VPC architecture for a secure database deployment, then verify your existing lab VPC matches the design using AWS CLI commands.
**Prerequisites:** Module 01 BUILD guides complete (especially the VPC/networking guide)

---

## Background

You are a DevOps DBA at [COMPANY]. The development team has asked for a new Aurora PostgreSQL cluster that meets these requirements:

- The database must be accessible only from the application servers - never from the internet
- The application servers serve HTTPS traffic from the internet through a load balancer
- The architecture must survive the failure of one Availability Zone
- The DBA team needs a way to connect to the database for maintenance without opening it to the internet

Your job is to design the VPC architecture, then verify your lab environment matches the design.

---

## Task 1: Design the Architecture

Based on the requirements above, answer the following questions. Write your answers down before checking the solutions.

### Question 1: Subnet Layout

How many subnets do you need, and what type should each be (public or private)?

Think about:
- Where does the load balancer go?
- Where do the application servers go?
- Where does the Aurora cluster go?
- How many AZs do you need for high availability?

<details>
<summary>Show Answer</summary>

**You need at least 6 subnets across 2 AZs (3 AZs is better):**

**Public subnets (2-3, one per AZ):**
- These hold the Application Load Balancer (ALB). The ALB needs public subnets because it receives traffic from the internet.
- A NAT Gateway also goes in a public subnet so private-subnet resources can make outbound internet calls (for updates, AWS API calls).

**Private application subnets (2-3, one per AZ):**
- These hold the EC2 or ECS application servers. They receive traffic only from the ALB, not directly from the internet.
- Their route table points 0.0.0.0/0 to the NAT Gateway for outbound-only internet access.

**Private database subnets (2-3, one per AZ):**
- These hold the Aurora cluster. They have no internet route at all - not even through a NAT Gateway.
- Databases rarely need outbound internet access. Isolating them in subnets with no internet route adds a layer of defense.

Example layout for 2 AZs:

```
Public:    10.0.1.0/24 (us-east-1a)    10.0.2.0/24 (us-east-1b)
App:       10.0.11.0/24 (us-east-1a)   10.0.12.0/24 (us-east-1b)
Database:  10.0.21.0/24 (us-east-1a)   10.0.22.0/24 (us-east-1b)
```

</details>

---

### Question 2: Security Group Rules

What inbound rules should the database security group have?

Think about:
- What source should be allowed to connect on port 5432?
- Should you use an IP range or a security group reference?
- Should you allow any outbound traffic from the database?

<details>
<summary>Show Answer</summary>

**Database security group (sg-aurora):**

Inbound:
```
Port 5432  |  TCP  |  Source: sg-app  (the application server security group)
```

That is it. One rule. Only instances attached to the application security group can connect to the database. No IP addresses, no CIDR ranges, no 0.0.0.0/0.

Outbound:
```
No outbound rules needed
```

Databases do not initiate outbound connections in most architectures. If you need outbound access for a specific reason (like calling an external service via a PostgreSQL extension), add only that specific rule.

**Why security group references are better than IP ranges:**
- If application servers scale up/down (auto-scaling), new instances automatically get access through the security group - no rule changes needed.
- IP addresses change. Security group membership does not.
- It is self-documenting: the rule says "app servers can connect" rather than "10.0.11.0/24 can connect."

</details>

---

### Question 3: DB Subnet Group

What is a DB subnet group, and what subnets should be in it?

<details>
<summary>Show Answer</summary>

**A DB subnet group tells Aurora which subnets it can place database instances in.**

It must contain subnets in at least 2 different AZs. Aurora uses the subnet group to:
- Place the primary writer instance in one AZ
- Place reader instances in other AZs
- Place the standby (for Multi-AZ) in a different AZ from the primary

Your DB subnet group should include only the private database subnets:
```
DB Subnet Group: aurora-db-subnet-group
  - 10.0.21.0/24 (us-east-1a)
  - 10.0.22.0/24 (us-east-1b)
```

Never include public subnets in a DB subnet group. Databases should not be placed in subnets with internet routes.

</details>

---

### Question 4: DBA Access

How should DBAs connect to the Aurora cluster for maintenance without exposing the database to the internet?

<details>
<summary>Show Answer</summary>

**Option 1 (Recommended): AWS Systems Manager Session Manager with port forwarding**

Session Manager lets you open a tunnel to the RDS endpoint through an EC2 instance without opening port 22 or any public-facing ports. The DBA runs a command like:

```bash
aws ssm start-session \
    --target i-0abc123def456 \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters '{"host":["aurora-cluster.cluster-abc123.us-east-1.rds.amazonaws.com"],"portNumber":["5432"],"localPortNumber":["15432"]}'
```

Then connects locally:
```bash
psql -h 127.0.0.1 -p 15432 -U dbadmin -d appdb
```

No bastion host security group changes needed. All access is logged in CloudTrail.

**Option 2: Bastion host (jump box)**

A small EC2 instance in a private subnet that DBAs SSH into, then connect to Aurora from there. SSH access to the bastion is restricted to the DBA team's IP addresses or routed through a VPN. The bastion's security group is added as an allowed source in the Aurora security group.

**What NOT to do:**
- Never set `Public Accessibility: Yes` on the Aurora cluster
- Never open port 5432 to DBA IP addresses in the database security group
- Never put the database in a public subnet "just for debugging"

</details>

---

### Question 5: Draw (or Describe) the Complete Architecture

Put it all together. Describe the complete VPC architecture including:
- VPC CIDR
- All subnets with types and AZs
- Route tables
- Security groups with rules
- DB subnet group
- Internet Gateway and NAT Gateway placement

<details>
<summary>Show Answer</summary>

```
VPC: 10.0.0.0/16
Region: us-east-1

=== PUBLIC SUBNETS ===
public-1a:  10.0.1.0/24   us-east-1a   Route: 0.0.0.0/0 -> Internet Gateway
public-1b:  10.0.2.0/24   us-east-1b   Route: 0.0.0.0/0 -> Internet Gateway
Contains: Application Load Balancer, NAT Gateway

=== PRIVATE APP SUBNETS ===
app-1a:     10.0.11.0/24  us-east-1a   Route: 0.0.0.0/0 -> NAT Gateway
app-1b:     10.0.12.0/24  us-east-1b   Route: 0.0.0.0/0 -> NAT Gateway
Contains: Application servers (EC2/ECS)

=== PRIVATE DB SUBNETS ===
db-1a:      10.0.21.0/24  us-east-1a   Route: local only (no internet)
db-1b:      10.0.22.0/24  us-east-1b   Route: local only (no internet)
Contains: Aurora PostgreSQL cluster

=== SECURITY GROUPS ===
sg-alb:
  Inbound:  Port 443/TCP from 0.0.0.0/0 (HTTPS)
  Outbound: Port 8080/TCP to sg-app

sg-app:
  Inbound:  Port 8080/TCP from sg-alb
  Outbound: Port 5432/TCP to sg-aurora
            Port 443/TCP to 0.0.0.0/0 (AWS API, updates via NAT)

sg-aurora:
  Inbound:  Port 5432/TCP from sg-app
  Outbound: None

=== DB SUBNET GROUP ===
aurora-db-subnet-group: db-1a, db-1b

=== AURORA CLUSTER ===
Public Accessibility: No
Deletion Protection: Enabled
Encryption: Enabled (KMS)
```

Key principle: traffic flows in one direction through layers of security. Internet -> ALB (public) -> App (private) -> Database (isolated). Each layer only accepts traffic from the layer above it. The database is two network hops away from the internet, with security groups at each boundary.

</details>

---

## Task 2: Verify Your Lab VPC

Now that you understand the correct architecture, verify that your lab VPC from the BUILD guides is set up properly. Run each command below and compare the output to the expected design.

### Step 1: List your VPC

```bash
aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=*aurora*" \
    --query "Vpcs[*].{VpcId:VpcId,CIDR:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" \
    --output table
```

This shows your VPC ID and CIDR block. Confirm you have a VPC with a /16 CIDR block.

---

### Step 2: List all subnets in your VPC

Replace `vpc-XXXX` with your actual VPC ID from Step 1.

```bash
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=vpc-XXXX" \
    --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" \
    --output table
```

Verify:
- You have subnets in at least 2 AZs
- You can identify which are public and which are private by their names or CIDR ranges

---

### Step 3: Check route tables for each subnet

This command shows you all route tables and their associations.

```bash
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=vpc-XXXX" \
    --query "RouteTables[*].{RouteTableId:RouteTableId,Routes:Routes[*].{Dest:DestinationCidrBlock,Target:GatewayId||NatGatewayId},Associations:Associations[*].SubnetId}" \
    --output json
```

Verify:
- Public subnets have a route to an Internet Gateway (igw-XXXX)
- Private app subnets route 0.0.0.0/0 to a NAT Gateway (nat-XXXX)
- Database subnets have only the local route (10.0.0.0/16 -> local), or route through a NAT Gateway

---

### Step 4: Check the database security group

First, find the security group attached to your Aurora cluster.

```bash
aws rds describe-db-clusters \
    --query "DBClusters[*].{ClusterID:DBClusterIdentifier,SecurityGroups:VpcSecurityGroups[*].VpcSecurityGroupId}" \
    --output json
```

Then inspect the rules on that security group. Replace `sg-XXXX` with the actual ID.

```bash
aws ec2 describe-security-groups \
    --group-ids sg-XXXX \
    --query "SecurityGroups[*].{GroupName:GroupName,InboundRules:IpPermissions[*].{Port:FromPort,Sources:UserIdGroupPairs[*].GroupId,CIDRs:IpRanges[*].CidrIp}}" \
    --output json
```

Verify:
- Inbound port 5432 is allowed from a security group reference (sg-XXXX), not from 0.0.0.0/0
- There are no rules allowing 0.0.0.0/0 or ::/0 on any port

---

### Step 5: Check Public Accessibility setting

```bash
aws rds describe-db-instances \
    --query "DBInstances[*].{InstanceID:DBInstanceIdentifier,PublicAccess:PubliclyAccessible,MultiAZ:MultiAZ,DeletionProtection:DeletionProtection}" \
    --output table
```

Verify:
- PubliclyAccessible is False
- MultiAZ is True (or you have multiple Aurora instances across AZs)
- DeletionProtection is True

---

### Step 6: Check the DB subnet group

```bash
aws rds describe-db-subnet-groups \
    --query "DBSubnetGroups[*].{Name:DBSubnetGroupName,VpcId:VpcId,Subnets:Subnets[*].{AZ:SubnetAvailabilityZone.Name,SubnetId:SubnetIdentifier}}" \
    --output json
```

Verify:
- The DB subnet group contains subnets in at least 2 different AZs
- The subnets are your private database subnets (not public ones)

---

## Checklist

After completing all verification steps, check off each item:

- [ ] VPC has a /16 CIDR block
- [ ] Subnets exist in at least 2 AZs
- [ ] Public subnets route to Internet Gateway
- [ ] Database subnets do not route to Internet Gateway
- [ ] Database security group allows port 5432 from application security group only
- [ ] No security group rule allows 0.0.0.0/0 on port 5432
- [ ] Aurora cluster has PubliclyAccessible set to False
- [ ] Deletion Protection is enabled
- [ ] DB subnet group spans at least 2 AZs

If any item fails the check, go back to the relevant BUILD guide and fix it before continuing.

---

## Summary of Key Takeaways

- Databases belong in isolated private subnets with no internet route. Two layers of isolation (private subnet + security group) provide defense in depth.
- Security groups should reference other security groups, not IP ranges, when the clients are AWS resources. This handles auto-scaling and IP changes automatically.
- A DB subnet group must span at least 2 AZs for Multi-AZ to work. Plan your subnet layout before creating the database.
- Use AWS Systems Manager Session Manager for DBA access instead of bastion hosts or public database endpoints. It is more secure and fully auditable.
- Always verify your infrastructure with CLI commands. The console can be misleading - CLI output is definitive.
