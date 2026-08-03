# Module 01 - AWS Foundations and Aurora Architecture
## Guide 02: VPC Networking Basics

**Objective:** Build a complete VPC from scratch using the AWS CLI - with public subnets, private subnets, an internet gateway, route tables, a DB subnet group, and a security group - so you have the networking foundation ready for Aurora in later modules.
**Time:** 45 minutes
**Prerequisites:** Guide 01 (AWS Account Setup) completed. AWS CLI configured and verified with `aws sts get-caller-identity`.
**Infrastructure:** All resources created via CLI. Cost: VPCs, subnets, route tables, and security groups are free. The Internet Gateway is free as long as no traffic flows through it.

---

## 1. What Is a VPC?

A VPC - Virtual Private Cloud - is your own private network inside AWS. Think of it as a walled-off section of the AWS cloud that belongs only to you. Nothing gets in or out unless you explicitly allow it.

Every resource you create - EC2 instances, RDS databases, Aurora clusters - lives inside a VPC. If two resources are in different VPCs, they cannot talk to each other by default. If they are in the same VPC, they can communicate (subject to security group rules).

Your AWS account comes with a default VPC in each region, but for production workloads (and for this training track), you will create a custom VPC with a deliberate network design.

---

## 2. The Plan

Here is what you are going to build in this guide:

```
VPC: 10.0.0.0/16 (65,536 IP addresses)
│
├── Public Subnet 1:  10.0.1.0/24 (256 IPs) - AZ: us-east-1a
├── Public Subnet 2:  10.0.2.0/24 (256 IPs) - AZ: us-east-1b
│
├── Private Subnet 1: 10.0.10.0/24 (256 IPs) - AZ: us-east-1a
├── Private Subnet 2: 10.0.20.0/24 (256 IPs) - AZ: us-east-1b
│
├── Internet Gateway (attached to VPC)
│
├── Public Route Table  (0.0.0.0/0 -> Internet Gateway)
├── Private Route Table (no internet route)
│
├── DB Subnet Group (private subnets only)
│
└── Security Group: db-access (port 5432, restricted source)
```

> **Note on regions:** This guide uses `us-east-1` as the region and `us-east-1a` / `us-east-1b` as Availability Zones. If your CLI is configured for a different region, substitute your region's AZ names. Run `aws ec2 describe-availability-zones --output table` to see your AZs.

---

## 3. Create the VPC

**In your terminal** (local machine):

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=aurora-lab-vpc}]'
```

- `create-vpc` - creates a new Virtual Private Cloud
- `--cidr-block 10.0.0.0/16` - the IP address range for your VPC. The `/16` gives you 65,536 addresses - plenty of room for subnets
- `--tag-specifications` - adds a Name tag so you can identify this VPC later. Without tags, you are left guessing which `vpc-0abc123` is which

Expected output (yours will differ):
```json
{
    "Vpc": {
        "CidrBlock": "10.0.0.0/16",
        "VpcId": "vpc-0a1b2c3d4e5f67890",
        "State": "available",
        "Tags": [
            {
                "Key": "Name",
                "Value": "aurora-lab-vpc"
            }
        ]
    }
}
```

Copy the `VpcId` value. You will use it in every command that follows. To save yourself from retyping it, store it in a variable:

**In your terminal** (local machine):

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=aurora-lab-vpc" --query "Vpcs[0].VpcId" --output text)
```

- `describe-vpcs` - lists VPCs matching the filter
- `--filters` - narrows results to VPCs with the Name tag `aurora-lab-vpc`
- `--query` - extracts just the VPC ID from the JSON response
- `--output text` - returns plain text instead of JSON (easier to store in a variable)

Verify the variable is set:

**In your terminal** (local machine):

```bash
echo $VPC_ID
```

Expected output (yours will differ):
```
vpc-0a1b2c3d4e5f67890
```

Now enable DNS hostnames on the VPC. Aurora needs this to generate DNS endpoints for your cluster:

**In your terminal** (local machine):

```bash
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value": true}'
```

- `modify-vpc-attribute` - changes a setting on an existing VPC
- `--enable-dns-hostnames` - allows instances in the VPC to receive public DNS names. Aurora uses DNS to give you cluster endpoints

---

## 4. Create Public Subnets

You need two public subnets in different Availability Zones. Public subnets are for resources that need internet access - like bastion hosts or NAT gateways. Your databases will NOT go here.

**In your terminal** (local machine):

```bash
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=aurora-lab-public-1a}]'
```

- `create-subnet` - carves out a slice of your VPC's IP range
- `--cidr-block 10.0.1.0/24` - this subnet gets 256 IP addresses (10.0.1.0 through 10.0.1.255)
- `--availability-zone us-east-1a` - places this subnet in a specific data center. Change this if your region is different

Expected output (yours will differ):
```json
{
    "Subnet": {
        "SubnetId": "subnet-0aaa111222333",
        "AvailabilityZone": "us-east-1a",
        "CidrBlock": "10.0.1.0/24",
        "VpcId": "vpc-0a1b2c3d4e5f67890"
    }
}
```

**In your terminal** (local machine):

```bash
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=aurora-lab-public-1b}]'
```

Store both subnet IDs in variables:

**In your terminal** (local machine):

```bash
PUB_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=aurora-lab-public-1a" --query "Subnets[0].SubnetId" --output text)
```

**In your terminal** (local machine):

```bash
PUB_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=aurora-lab-public-1b" --query "Subnets[0].SubnetId" --output text)
```

---

## 5. Create Private Subnets

Private subnets have no route to the internet. This is where your Aurora databases will live. Two private subnets in different AZs are required for a DB subnet group.

**In your terminal** (local machine):

```bash
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.10.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=aurora-lab-private-1a}]'
```

**In your terminal** (local machine):

```bash
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.20.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=aurora-lab-private-1b}]'
```

Store both private subnet IDs:

**In your terminal** (local machine):

```bash
PRIV_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=aurora-lab-private-1a" --query "Subnets[0].SubnetId" --output text)
```

**In your terminal** (local machine):

```bash
PRIV_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=aurora-lab-private-1b" --query "Subnets[0].SubnetId" --output text)
```

---

## 6. Create and Attach an Internet Gateway

An Internet Gateway (IGW) connects your VPC to the public internet. Without it, nothing in your VPC can reach the outside world, and nothing from outside can reach in.

**In your terminal** (local machine):

```bash
aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=aurora-lab-igw}]'
```

- `create-internet-gateway` - creates a new IGW. It does not do anything until you attach it to a VPC

Expected output (yours will differ):
```json
{
    "InternetGateway": {
        "InternetGatewayId": "igw-0abc123def456",
        "Tags": [
            {
                "Key": "Name",
                "Value": "aurora-lab-igw"
            }
        ]
    }
}
```

Store the IGW ID:

**In your terminal** (local machine):

```bash
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=aurora-lab-igw" --query "InternetGateways[0].InternetGatewayId" --output text)
```

Attach the IGW to your VPC:

**In your terminal** (local machine):

```bash
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
```

- `attach-internet-gateway` - connects the IGW to your VPC. Now traffic CAN flow to the internet - but only if a route table points to it

---

## 7. Create Route Tables

Route tables are the traffic rules for your subnets. They tell AWS where to send network traffic based on its destination.

### Public Route Table

**In your terminal** (local machine):

```bash
aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=aurora-lab-public-rt}]'
```

- `create-route-table` - creates a new route table inside your VPC

Store the route table ID:

**In your terminal** (local machine):

```bash
PUB_RT=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=aurora-lab-public-rt" --query "RouteTables[0].RouteTableId" --output text)
```

Add a route that sends all internet-bound traffic (0.0.0.0/0) to the Internet Gateway:

**In your terminal** (local machine):

```bash
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

- `create-route` - adds a routing rule to the route table
- `--destination-cidr-block 0.0.0.0/0` - this means "all traffic not destined for the VPC itself." It is the catch-all route
- `--gateway-id` - sends that traffic to the Internet Gateway

Expected output (yours will differ):
```json
{
    "Return": true
}
```

Now associate both public subnets with this route table:

**In your terminal** (local machine):

```bash
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET_1
```

**In your terminal** (local machine):

```bash
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET_2
```

- `associate-route-table` - links a subnet to a route table. A subnet can only be associated with one route table at a time

### Private Route Table

The private subnets get their own route table with no internet route. This is what makes them private.

**In your terminal** (local machine):

```bash
aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=aurora-lab-private-rt}]'
```

**In your terminal** (local machine):

```bash
PRIV_RT=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=aurora-lab-private-rt" --query "RouteTables[0].RouteTableId" --output text)
```

**In your terminal** (local machine):

```bash
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET_1
```

**In your terminal** (local machine):

```bash
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET_2
```

Notice you did NOT add a `0.0.0.0/0` route to this table. The private route table only has the automatic local route (`10.0.0.0/16 -> local`), which means traffic stays within the VPC. No internet access in or out.

---

## 8. Create a DB Subnet Group

A DB subnet group is an RDS/Aurora-specific concept. It tells Aurora which subnets (and therefore which Availability Zones) are valid locations for your database instances. Aurora requires subnets in at least 2 different AZs.

**In your terminal** (local machine):

```bash
aws rds create-db-subnet-group --db-subnet-group-name aurora-lab-db-subnets --db-subnet-group-description "Private subnets for Aurora lab" --subnet-ids "$PRIV_SUBNET_1" "$PRIV_SUBNET_2"
```

- `create-db-subnet-group` - creates a named group of subnets for RDS/Aurora to use
- `--db-subnet-group-name` - the identifier you will reference when creating an Aurora cluster
- `--subnet-ids` - the subnets to include. Using private subnets here ensures your database is not directly reachable from the internet

Expected output (yours will differ):
```json
{
    "DBSubnetGroup": {
        "DBSubnetGroupName": "aurora-lab-db-subnets",
        "DBSubnetGroupDescription": "Private subnets for Aurora lab",
        "VpcId": "vpc-0a1b2c3d4e5f67890",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {
                "SubnetIdentifier": "subnet-0priv111222",
                "SubnetAvailabilityZone": {
                    "Name": "us-east-1a"
                }
            },
            {
                "SubnetIdentifier": "subnet-0priv333444",
                "SubnetAvailabilityZone": {
                    "Name": "us-east-1b"
                }
            }
        ]
    }
}
```

---

## 9. Create a Security Group for Database Access

A security group is a virtual firewall that controls which traffic can reach your database. You will create one that allows PostgreSQL connections (port 5432) only from within the VPC.

**In your terminal** (local machine):

```bash
aws ec2 create-security-group --group-name aurora-lab-db-sg --description "Allow PostgreSQL access from within VPC" --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=aurora-lab-db-sg}]'
```

- `create-security-group` - creates a new firewall rule set
- `--group-name` - the logical name for the security group
- `--description` - a human-readable description (required by AWS)

Expected output (yours will differ):
```json
{
    "GroupId": "sg-0abc123def456",
    "Tags": [
        {
            "Key": "Name",
            "Value": "aurora-lab-db-sg"
        }
    ]
}
```

Store the security group ID:

**In your terminal** (local machine):

```bash
DB_SG=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=aurora-lab-db-sg" --query "SecurityGroups[0].GroupId" --output text)
```

Add an inbound rule allowing PostgreSQL traffic (TCP port 5432) from anywhere within the VPC:

**In your terminal** (local machine):

```bash
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 5432 --cidr 10.0.0.0/16 --tag-specifications 'ResourceType=security-group-rule,Tags=[{Key=Name,Value=postgres-from-vpc}]'
```

- `authorize-security-group-ingress` - adds an inbound (incoming traffic) rule
- `--protocol tcp` - PostgreSQL uses TCP connections
- `--port 5432` - the default PostgreSQL port
- `--cidr 10.0.0.0/16` - allows connections from any IP in the VPC range. In production, you would restrict this further to specific application subnets or security groups

> **Security note:** Never set the source CIDR to `0.0.0.0/0` for a database security group. That opens your database to the entire internet.

---

## 10. Verify Everything

Time to confirm all your resources are in place.

### Verify the VPC

**In your terminal** (local machine):

```bash
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].{ID:VpcId,CIDR:CidrBlock,State:State}" --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------
|                    DescribeVpcs                      |
+----------------+-------------------+-----------+
|      CIDR      |        ID         |   State   |
+----------------+-------------------+-----------+
|  10.0.0.0/16   |  vpc-0a1b2c3d4e   |  available |
+----------------+-------------------+-----------+
```

### Verify the subnets

**In your terminal** (local machine):

```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].{Name:Tags[?Key=='Name']|[0].Value,AZ:AvailabilityZone,CIDR:CidrBlock}" --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------
|                     DescribeSubnets                      |
+---------------+--------------+---------------------------+
|      AZ       |     CIDR     |           Name            |
+---------------+--------------+---------------------------+
|  us-east-1a   | 10.0.1.0/24  | aurora-lab-public-1a      |
|  us-east-1b   | 10.0.2.0/24  | aurora-lab-public-1b      |
|  us-east-1a   | 10.0.10.0/24 | aurora-lab-private-1a     |
|  us-east-1b   | 10.0.20.0/24 | aurora-lab-private-1b     |
+---------------+--------------+---------------------------+
```

You should see 4 subnets - 2 public and 2 private, across 2 different AZs.

### Verify the security group rules

**In your terminal** (local machine):

```bash
aws ec2 describe-security-groups --group-ids $DB_SG --query "SecurityGroups[0].IpPermissions" --output json
```

Expected output (yours will differ):
```json
[
    {
        "FromPort": 5432,
        "IpProtocol": "tcp",
        "IpRanges": [
            {
                "CidrIp": "10.0.0.0/16"
            }
        ],
        "ToPort": 5432
    }
]
```

Confirm that port 5432 is open only from `10.0.0.0/16` (your VPC range) and not `0.0.0.0/0`.

---

## 11. Save Your Resource IDs

You will reference these resources in later modules when you create your Aurora cluster. Run this to see all your IDs in one place:

**In your terminal** (local machine):

```bash
echo "VPC_ID:        $VPC_ID"
```

**In your terminal** (local machine):

```bash
echo "PUB_SUBNET_1:  $PUB_SUBNET_1"
```

**In your terminal** (local machine):

```bash
echo "PUB_SUBNET_2:  $PUB_SUBNET_2"
```

**In your terminal** (local machine):

```bash
echo "PRIV_SUBNET_1: $PRIV_SUBNET_1"
```

**In your terminal** (local machine):

```bash
echo "PRIV_SUBNET_2: $PRIV_SUBNET_2"
```

**In your terminal** (local machine):

```bash
echo "DB_SG:         $DB_SG"
```

Copy these values somewhere safe - a notes file or a `.env` file that is in your `.gitignore`. You will need them in Module 02 when you launch your first Aurora cluster.

---

## Summary

- A VPC is your private, isolated network in AWS. All databases live inside a VPC.
- Public subnets have a route to the Internet Gateway - used for load balancers and bastion hosts. Never put databases here.
- Private subnets have no internet route - always put your databases in private subnets.
- Route tables define where traffic goes. A `0.0.0.0/0` route to an IGW makes a subnet public. No such route makes it private.
- A DB subnet group is a collection of subnets across at least 2 AZs. Aurora requires one to know where to place your database instances.
- Security groups are virtual firewalls. They control which traffic reaches your database. Never open port 5432 to `0.0.0.0/0`.
- You built: 1 VPC, 4 subnets, 1 IGW, 2 route tables, 1 DB subnet group, and 1 security group - all from the CLI.

**Next:** [Guide 03 - RDS vs Aurora Comparison](./03-rds-vs-aurora-comparison.md)
