# Build 01 - Security Groups and Network

**Time:** 40 minutes
**Goal:** Configure VPC security groups for your Aurora cluster, understand NACLs, and verify network isolation.

---

## Before You Start

Read `concepts/01-database-security-layers.md` first (Layer 1 - Network Security).

You need:
- A running Aurora PostgreSQL cluster (from Module 01 or 02)
- AWS CLI configured with credentials that have VPC and RDS permissions
- psql installed on your local machine or bastion host

Set these variables now. You will use them throughout the guide.

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
export VPC_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].DBSubnetGroup' \
  --output text \
  --region $AWS_REGION)
```

Get your cluster's VPC ID:

```bash
export VPC_ID=$(aws ec2 describe-security-groups \
  --group-ids $(aws rds describe-db-clusters \
    --db-cluster-identifier $CLUSTER_ID \
    --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text \
    --region $AWS_REGION) \
  --query 'SecurityGroups[0].VpcId' \
  --output text \
  --region $AWS_REGION)

echo "VPC ID: $VPC_ID"
```

Expected output (yours will differ):

```
VPC ID: vpc-0abc123def456789a
```

---

## Step 1 - See What Security Group Your Cluster Uses

Every Aurora cluster has at least one security group attached to it. Find yours:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].VpcSecurityGroups' \
  --output table \
  --region $AWS_REGION
```

`--query` filters the output to show only the security groups section.
`--output table` formats it as a readable table.

Expected output (yours will differ):

```
+------------------+----------------------------+
|     Status       |   VpcSecurityGroupId       |
+------------------+----------------------------+
|  active          |  sg-0abc123def456789a      |
+------------------+----------------------------+
```

Save the security group ID:

```bash
export CLUSTER_SG=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text \
  --region $AWS_REGION)

echo "Cluster security group: $CLUSTER_SG"
```

---

## Step 2 - Inspect the Current Security Group Rules

View the inbound rules (these control who can connect to your cluster):

```bash
aws ec2 describe-security-groups \
  --group-ids $CLUSTER_SG \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json \
  --region $AWS_REGION
```

Expected output (yours will differ):

```json
[
    {
        "FromPort": 5432,
        "IpProtocol": "tcp",
        "IpRanges": [
            {
                "CidrIp": "0.0.0.0/0"
            }
        ],
        "ToPort": 5432
    }
]
```

If you see `0.0.0.0/0` as the source, this means anyone on the internet can reach port 5432. This is a security risk. We will fix this.

View the outbound rules:

```bash
aws ec2 describe-security-groups \
  --group-ids $CLUSTER_SG \
  --query 'SecurityGroups[0].IpPermissionsEgress' \
  --output json \
  --region $AWS_REGION
```

Outbound rules for a database security group are less critical because the database does not initiate connections to the outside. The default "allow all outbound" is usually fine.

---

## Step 3 - Create a Dedicated Application Security Group

In production, your application servers have their own security group. The database security group references the app security group as the source.

Create the application security group:

```bash
export APP_SG=$(aws ec2 create-security-group \
  --group-name "devops-lab-app-sg" \
  --description "Security group for application servers that access Aurora" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text \
  --region $AWS_REGION)

echo "App security group: $APP_SG"
```

`--group-name` is a human-readable name.
`--description` explains the purpose.
`--vpc-id` places the security group in the same VPC as your Aurora cluster.

Expected output (yours will differ):

```
App security group: sg-0def456abc789012b
```

Tag it for easy identification:

```bash
aws ec2 create-tags \
  --resources $APP_SG \
  --tags Key=Name,Value="devops-lab-app-sg" \
  --region $AWS_REGION
```

---

## Step 4 - Create a Proper Database Security Group

Create a new security group for the Aurora cluster that only allows traffic from the application security group:

```bash
export DB_SG=$(aws ec2 create-security-group \
  --group-name "devops-lab-db-sg" \
  --description "Security group for Aurora cluster - allows only app servers" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text \
  --region $AWS_REGION)

echo "DB security group: $DB_SG"
```

Tag it:

```bash
aws ec2 create-tags \
  --resources $DB_SG \
  --tags Key=Name,Value="devops-lab-db-sg" \
  --region $AWS_REGION
```

Add an inbound rule that allows PostgreSQL traffic only from the application security group:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $APP_SG \
  --region $AWS_REGION
```

`--protocol tcp` specifies TCP (PostgreSQL uses TCP).
`--port 5432` is the PostgreSQL port.
`--source-group` references the application security group. Only resources in that security group can connect.

Expected output (yours will differ):

```json
{
    "Return": true,
    "SecurityGroupRules": [
        {
            "SecurityGroupRuleId": "sgr-0abc123...",
            "GroupId": "sg-0def456...",
            "IpProtocol": "tcp",
            "FromPort": 5432,
            "ToPort": 5432,
            "ReferencedGroupInfo": {
                "GroupId": "sg-0def456abc789012b"
            }
        }
    ]
}
```

Verify the rules:

```bash
aws ec2 describe-security-groups \
  --group-ids $DB_SG \
  --query 'SecurityGroups[0].IpPermissions' \
  --output table \
  --region $AWS_REGION
```

You should see one inbound rule allowing TCP 5432 from the app security group. No `0.0.0.0/0` anywhere.

---

## Step 5 - Add a Bastion/Admin Access Rule

You also need to connect from your bastion host or workstation for administration. Add a rule for your specific IP address:

Find your current public IP:

```bash
curl -s https://checkip.amazonaws.com
```

Expected output (yours will differ):

```
203.0.113.42
```

Add the rule:

```bash
export MY_IP=$(curl -s https://checkip.amazonaws.com)

aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG \
  --protocol tcp \
  --port 5432 \
  --cidr "${MY_IP}/32" \
  --region $AWS_REGION
```

`--cidr "${MY_IP}/32"` allows only your exact IP address. The `/32` means a single IP, not a range.

> **Note:** In production, you would use a bastion host security group instead of your personal IP. Personal IPs change frequently and should not be in production security groups.

---

## Step 6 - Attach the New Security Group to Your Aurora Cluster

Replace the cluster's security group with the new one:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --vpc-security-group-ids $DB_SG \
  --region $AWS_REGION
```

`--vpc-security-group-ids` replaces all security groups on the cluster with the ones you specify. This takes effect immediately - no reboot needed.

Verify the change:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].VpcSecurityGroups' \
  --output table \
  --region $AWS_REGION
```

Expected output (yours will differ):

```
+------------------+----------------------------+
|     Status       |   VpcSecurityGroupId       |
+------------------+----------------------------+
|  active          |  sg-0def456...  (your DB_SG)|
+------------------+----------------------------+
```

---

## Step 7 - Test Connectivity

Get your cluster endpoint:

```bash
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region $AWS_REGION)

echo "Cluster endpoint: $CLUSTER_ENDPOINT"
```

Test the connection from your workstation (which should be allowed by the IP rule you added):

```bash
psql \
  --host=$CLUSTER_ENDPOINT \
  --port=5432 \
  --username=postgres \
  --dbname=postgres
```

Enter your master password when prompted.

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

If this works, your security group is correctly configured to allow your IP.

Exit psql:

```sql
\q
```

---

## Step 8 - Understand NACLs

Check which NACLs are applied to your Aurora cluster's subnets:

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name $(aws rds describe-db-clusters \
    --db-cluster-identifier $CLUSTER_ID \
    --query 'DBClusters[0].DBSubnetGroup' \
    --output text \
    --region $AWS_REGION) \
  --query 'DBSubnetGroups[0].Subnets[*].SubnetIdentifier' \
  --output text \
  --region $AWS_REGION
```

Expected output (yours will differ):

```
subnet-0abc123	subnet-0def456
```

Check the NACL for the first subnet:

```bash
export FIRST_SUBNET=$(aws rds describe-db-subnet-groups \
  --db-subnet-group-name $(aws rds describe-db-clusters \
    --db-cluster-identifier $CLUSTER_ID \
    --query 'DBClusters[0].DBSubnetGroup' \
    --output text \
    --region $AWS_REGION) \
  --query 'DBSubnetGroups[0].Subnets[0].SubnetIdentifier' \
  --output text \
  --region $AWS_REGION)

aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$FIRST_SUBNET" \
  --query 'NetworkAcls[0].Entries' \
  --output table \
  --region $AWS_REGION
```

If the NACL has the default "allow all" rules, that is normal. The security group is the primary firewall for your Aurora cluster.

---

## Step 9 - Check Public Accessibility

Verify your Aurora instances are not publicly accessible:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_ID" \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,PubliclyAccessible:PubliclyAccessible}' \
  --output table \
  --region $AWS_REGION
```

Expected output:

```
+---------------------------------+---------------------+
|           Instance              | PubliclyAccessible   |
+---------------------------------+---------------------+
|  devops-lab-cluster-instance-1  | False                |
+---------------------------------+---------------------+
```

`PubliclyAccessible: False` is correct. If it says `True`, fix it:

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-cluster-instance-1 \
  --no-publicly-accessible \
  --apply-immediately \
  --region $AWS_REGION
```

---

## Step 10 - Console Reference

You can view and edit security groups in the AWS Console:

1. Open the AWS Console in your browser
2. Search for **VPC** in the top search bar
3. Click **Security groups** in the left sidebar
4. Find your database security group (`devops-lab-db-sg`)
5. Click the **Inbound rules** tab to see who can connect
6. Click **Edit inbound rules** to modify

To verify the Aurora cluster's security group:
1. Go to **RDS > Databases**
2. Click your cluster name
3. Scroll down to **Connectivity & security**
4. The security group is listed under **VPC security groups**

---

## What You Built

- Identified your Aurora cluster's current security group
- Created a dedicated application security group
- Created a database security group that only allows traffic from the app security group
- Added an admin access rule scoped to your IP
- Attached the new security group to your Aurora cluster
- Verified connectivity and public accessibility settings
- Reviewed NACLs on the database subnets

---

## Clean Up (Optional)

If you need to revert to the original security group:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --vpc-security-group-ids $CLUSTER_SG \
  --region $AWS_REGION
```

To delete the security groups you created:

```bash
aws ec2 delete-security-group --group-id $DB_SG --region $AWS_REGION
aws ec2 delete-security-group --group-id $APP_SG --region $AWS_REGION
```

---

## Key Rules to Remember

1. Never use `0.0.0.0/0` as a source for database security groups
2. Reference other security groups as sources, not IP ranges
3. Aurora instances should always have `PubliclyAccessible: False`
4. Place Aurora in private subnets with no internet gateway route
5. Security group changes take effect immediately - no reboot needed
