# Tier 0 - Foundations
## Guide 04: VPC Networking for Databases

**Objective:** Understand the core AWS networking concepts that directly affect how your RDS and Aurora databases are accessed - VPCs, subnets, route tables, security groups, and DB subnet groups.
**Time:** 30 minutes
**Prerequisites:** Guide 03 (AWS Account, IAM, and Regions). AWS CLI configured and working.
**Infrastructure:** None required - you will explore the default VPC that already exists in your account.

---

## 1. What Is a VPC?

A VPC - Virtual Private Cloud - is your own private network inside AWS. It is logically isolated from every other customer's network on AWS. Resources you create inside your VPC (EC2 instances, RDS databases, Lambda functions in a VPC) can only talk to each other if you explicitly allow it.

Think of a VPC like a private office building:
- The building has its own internal network.
- Visitors from outside need to enter through controlled doors.
- Internal rooms (subnets) can be restricted so not all employees have access to every room.
- Security guards (security groups) check who is allowed in before letting anyone through.

Every AWS account comes with a **default VPC** in each region. It is pre-configured and ready to use. In production environments, most teams create custom VPCs with more specific configurations. For this curriculum, you will explore the default VPC to understand the concepts.

---

## 2. IP Address Ranges and CIDR Notation

Before getting into subnets, you need to understand CIDR notation - the way network address ranges are written in AWS.

A CIDR block looks like this: `10.0.0.0/16`

- The part before the slash (`10.0.0.0`) is the network address.
- The number after the slash (`/16`) is the prefix length - it tells you how many IP addresses are in this range.
- `/16` means 65,536 possible IP addresses.
- `/24` means 256 possible IP addresses.
- `/28` means 16 possible IP addresses (the smallest AWS subnet).

The default VPC uses `172.31.0.0/16` as its CIDR block. This means it has 65,536 private IP addresses available for resources inside it.

You do not need to become a networking expert here. The key things to remember:
- Larger prefix numbers = smaller networks (fewer IPs)
- VPCs typically use `/16` - large ranges
- Subnets inside a VPC use `/24` or similar - smaller slices of the VPC range

---

## 3. Subnets: Public vs Private

A subnet is a smaller network carved out of your VPC's IP range. You place resources (EC2 instances, RDS databases) inside subnets.

Subnets are either **public** or **private**. The distinction matters enormously for security.

### Public Subnets

A public subnet has a route to the Internet Gateway (explained in the next section). Resources placed in a public subnet can be reached directly from the internet if they have a public IP address.

Public subnets are used for:
- Load balancers that need to accept traffic from the internet
- Bastion hosts (jump boxes) used to SSH into private resources
- NAT Gateways that allow private resources to reach the internet

**Databases do not belong in public subnets.** A database in a public subnet with a public IP is reachable from any IP address on the internet. Even with a strong password, this is an unacceptable security posture for any real-world deployment.

### Private Subnets

A private subnet has no route to the Internet Gateway. Resources in a private subnet are not directly reachable from the internet. They can only be reached by other resources inside the VPC, or through controlled access paths like a VPN or bastion host.

**Databases always go in private subnets.**

Your application servers (in public or private subnets) can connect to the database because they are inside the same VPC. External traffic - including your developer's laptop - cannot reach the database directly from the internet.

### The Default VPC's Subnets

The default VPC has one public subnet in each Availability Zone. By default, everything in the default VPC is in public subnets. This is fine for learning and exploration. For production, you create a VPC with private subnets and place databases there.

---

## 4. Route Tables and Internet Gateways

### Internet Gateway

An Internet Gateway (IGW) is a VPC component that allows traffic to flow between your VPC and the internet. Without an Internet Gateway, your VPC is completely isolated - nothing can reach the internet, and nothing from the internet can reach it.

The default VPC already has an Internet Gateway attached.

### Route Tables

A route table is a set of rules that determine where network traffic is directed. Every subnet is associated with a route table.

A simple route table for a public subnet looks like this:

| Destination | Target |
|-------------|--------|
| `172.31.0.0/16` | local |
| `0.0.0.0/0` | igw-xxxxxxxx |

Reading this table:
- Traffic destined for addresses within the VPC (`172.31.0.0/16`) stays local - it routes within the VPC.
- Traffic destined for anything else (`0.0.0.0/0` means "all other addresses") is sent to the Internet Gateway (`igw-xxxxxxxx`).

A private subnet's route table has only the local route. There is no `0.0.0.0/0` entry pointing to the Internet Gateway. This is what makes a subnet private - the absence of an internet route.

---

## 5. Security Groups

A security group is a virtual firewall that controls inbound and outbound traffic for a specific resource. When you create an RDS instance, you attach one or more security groups to it.

Security groups have two types of rules:

**Inbound rules** - control traffic coming INTO the resource.
**Outbound rules** - control traffic going OUT from the resource.

Each rule specifies:
- **Protocol** - TCP, UDP, ICMP, or All
- **Port range** - which ports the rule applies to
- **Source/Destination** - an IP address range (CIDR), another security group ID, or "Anywhere" (0.0.0.0/0)

### Example: RDS Security Group

For a PostgreSQL RDS instance, you need an inbound rule allowing TCP traffic on port 5432 from your application servers. A good setup looks like this:

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| PostgreSQL | TCP | 5432 | sg-app-servers | Allow app servers |

Notice the source is another security group (`sg-app-servers`) rather than an IP range. This is called **security group referencing** and is a best practice. When you reference a security group as the source, it means: allow traffic from any resource that has that security group attached. This is more flexible than IP-based rules because IP addresses change when instances are replaced.

**What NOT to do:**

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| PostgreSQL | TCP | 5432 | 0.0.0.0/0 | WRONG - open to internet |

Opening port 5432 to `0.0.0.0/0` exposes your database to the entire internet. Never do this, even temporarily.

### Security Groups Are Stateful

Security groups are stateful. If you allow inbound traffic on a port, the return traffic is automatically allowed - you do not need a separate outbound rule for the response. This is different from network ACLs (another AWS networking concept you do not need to worry about at this level).

---

## 6. DB Subnet Groups

A DB Subnet Group is an RDS-specific concept. It is a collection of subnets (in at least 2 Availability Zones) that you designate as valid locations for your RDS or Aurora instances.

When you launch an RDS instance, you specify a DB Subnet Group instead of a single subnet. RDS uses this group to:
1. Place the primary instance in one of the subnets (and therefore one AZ).
2. Place the standby (if Multi-AZ is enabled) in a different AZ's subnet from the same group.
3. Give Aurora replicas a choice of AZs within the group.

**Requirements for a DB Subnet Group:**
- Must contain at least 2 subnets.
- The subnets must be in at least 2 different Availability Zones.
- All subnets must be in the same VPC.

In practice, you create one DB Subnet Group per environment (dev, staging, production) using private subnets. A typical production setup has 3 private subnets across 3 AZs, all included in the DB Subnet Group.

---

## 7. Hands-On: Explore Your Default VPC

You can do all of these steps using either the AWS Console (web browser) or the AWS CLI (terminal). We show both methods for every step.

Make sure your AWS CLI is configured (from Guide 03) if using the CLI.

### Step 1: List your VPCs

**Using the AWS Console:**
1. Open your web browser and go to the AWS Management Console.
2. In the search bar at the top, type `VPC` and click **VPC** from the results.
3. In the left sidebar, click **Your VPCs**.
4. You will see a table listing your VPCs. Look at the columns: VPC ID, State, IPv4 CIDR, and Default VPC (Yes/No).
5. Find the row where Default VPC says **Yes**. Note the VPC ID (it starts with `vpc-`).

**Using the AWS CLI:**

```bash
aws ec2 describe-vpcs --query "Vpcs[*].{ID:VpcId,CIDR:CidrBlock,Default:IsDefault,State:State}" --output table
```

This lists all VPCs in your default region and shows the key fields.
- `describe-vpcs` - calls the VPC listing API
- `--query` - filters the response to show only the columns we care about
- `--output table` - formats the output as a readable table

Expected output (yours will differ):
```
------------------------------------------------------
|                    DescribeVpcs                    |
+---------+----------------+----------------------------+
|  CIDR   |   Default  |    ID       |  State  |
+---------+----------------+----------------------------+
|  172.31.0.0/16  |  True  |  vpc-0abc12345  |  available  |
+---------+----------------+----------------------------+
```

Note the VPC ID (starts with `vpc-`). You will see it referenced in the next steps.

### Step 2: List your subnets

**Using the AWS Console:**
1. In the VPC dashboard, click **Subnets** in the left sidebar.
2. You will see a table listing all subnets. Key columns: Subnet ID, VPC, Availability Zone, IPv4 CIDR, and Auto-assign public IPv4 address.
3. Look at the **Auto-assign public IPv4 address** column. If it says **Yes**, that subnet is a public subnet.
4. Notice the default VPC has one subnet per Availability Zone.

**Using the AWS CLI:**

```bash
aws ec2 describe-subnets --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Public:MapPublicIpOnLaunch}" --output table
```

This lists all subnets in your default region and shows their AZ and whether they auto-assign public IPs (which indicates they are public subnets).
- `describe-subnets` - calls the subnet listing API
- `MapPublicIpOnLaunch` - if `true`, resources launched here get public IPs automatically - this is a public subnet

Expected output (yours will differ):
```
-------------------------------------------------------------------
|                        DescribeSubnets                         |
+----------+------------------+-------------------+--------+
|    AZ    |      CIDR        |        ID         | Public |
+----------+------------------+-------------------+--------+
| us-east-1a | 172.31.0.0/20  | subnet-0abc12345  | True   |
| us-east-1b | 172.31.16.0/20 | subnet-0def67890  | True   |
| us-east-1c | 172.31.32.0/20 | subnet-0ghi11112  | True   |
...
```

Observe that the default VPC's subnets all show `Public: True`. This confirms they are public subnets. In production, you would have private subnets here instead for your databases.

### Step 3: List your security groups

**Using the AWS Console:**
1. In the VPC dashboard, click **Security groups** in the left sidebar.
2. You will see a table listing all security groups. Key columns: Security group ID, Name, VPC ID, and Description.
3. You should see at least one security group named `default`. Every VPC has one.
4. Click on the `default` security group to see its details.
5. Click the **Inbound rules** tab to see what traffic is allowed in.

**Using the AWS CLI:**

```bash
aws ec2 describe-security-groups --query "SecurityGroups[*].{ID:GroupId,Name:GroupName,Description:Description}" --output table
```

This lists all security groups in your default region.
- `describe-security-groups` - calls the security group listing API

Expected output (yours will differ):
```
---------------------------------------------------------------
|                    DescribeSecurityGroups                   |
+----------------+-----------------------+--------------------+
|  Description   |          ID          |       Name         |
+----------------+-----------------------+--------------------+
|  default VPC   |  sg-0abc12345        |  default           |
+----------------+-----------------------+--------------------+
```

You will see at least one security group called `default`. Every VPC has a default security group. For RDS, you will create a dedicated security group rather than reusing this one.

### Step 4: View the inbound rules on the default security group

**Using the AWS Console:**
1. If you are not already on the security group detail page, click **Security groups** in the left sidebar, then click the `default` security group.
2. Click the **Inbound rules** tab.
3. You will see a table showing each rule: Type, Protocol, Port range, and Source.
4. The default security group usually allows all traffic from itself (the source is the same security group ID).
5. Click the **Outbound rules** tab to see what traffic is allowed out. The default allows all outbound traffic.

**Using the AWS CLI:**

Take the security group ID from Step 3 and run:

```bash
aws ec2 describe-security-groups --group-ids sg-0abc12345 --query "SecurityGroups[0].IpPermissions" --output json
```

Replace `sg-0abc12345` with your actual security group ID from Step 3.
- `--group-ids` - filters to a specific security group by ID
- `IpPermissions` - this is the field that holds inbound rules

Expected output (yours will differ):
```json
[
    {
        "IpProtocol": "-1",
        "UserIdGroupPairs": [
            {
                "GroupId": "sg-0abc12345",
                "UserId": "123456789012"
            }
        ],
        "IpRanges": [],
        "Ipv6Ranges": [],
        "PrefixListIds": []
    }
]
```

The default security group typically allows all inbound traffic from other resources in the same security group. `"IpProtocol": "-1"` means all protocols. This is a permissive default that you should replace with explicit rules in production.

---

## 8. Putting It Together: What Happens When an App Connects to RDS

Here is the full networking path when your application connects to an RDS database:

1. Your application sends a connection request to the RDS endpoint (a DNS name like `mydb.c9abcdefgh.us-east-1.rds.amazonaws.com`) on port 5432.

2. DNS resolves the RDS endpoint to a private IP address inside your VPC.

3. The traffic travels through your VPC's internal network.

4. Before reaching the RDS instance, it hits the **security group** attached to RDS. The security group checks: is this traffic on port 5432? Is the source allowed? If the security group has a rule allowing port 5432 from the application's security group, the traffic passes.

5. The RDS instance receives the connection and PostgreSQL handles authentication (username, password, or IAM auth).

6. If everything checks out, the connection is established.

If any step fails - wrong port, wrong source IP, wrong security group rule - the connection is refused before PostgreSQL even sees it.

---

## Summary

- A VPC is your private, isolated network in AWS. All databases live inside a VPC.
- Public subnets have a route to the Internet Gateway - used for load balancers and bastion hosts.
- Private subnets have no internet route - always put your databases here.
- Route tables define where traffic goes. A `0.0.0.0/0` route to an IGW makes a subnet public.
- Security groups are stateful virtual firewalls. They control which traffic is allowed to reach your RDS instance. Never open port 5432 to `0.0.0.0/0`.
- DB Subnet Groups are RDS-specific collections of subnets across at least 2 AZs. RDS requires one to determine where to place instances and standbys.
- The default VPC is usable for learning. Production databases use custom VPCs with private subnets.
- The `aws ec2 describe-vpcs`, `describe-subnets`, and `describe-security-groups` commands let you inspect your networking configuration from the CLI.

**Next:** [Guide 05 - PostgreSQL Refresher](./05-postgresql-refresher.md)
