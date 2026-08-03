# Build 06 - Network Isolation

**Time:** 30 minutes
**Goal:** Understand and configure VPC-level network isolation for RDS using PrivateLink, custom DNS with Route53, and security group best practices.

---

## Before You Start

Read `concepts/security.md` section T2.6 first.

You need:
- AWS account with VPC, RDS, and Route53 permissions
- AWS CLI configured
- An existing RDS instance in a VPC (from Tier 1)

Set these variables:

```bash
export AWS_REGION="us-east-1"
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"
export RDS_INSTANCE_ID="my-postgres-db"
export VPC_ID="vpc-0abc123456def7890"
export PRIVATE_SUBNET_1="subnet-0abc123"
export PRIVATE_SUBNET_2="subnet-0def456"
export APP_SG_ID="sg-0app1234"
```

Get your VPC ID if you do not have it:

```bash
aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=false" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region $AWS_REGION
```

---

## Step 1 - Verify Your RDS Instance is Not Publicly Accessible

The first rule of database network security: your database should not be reachable from the public internet.

### CLI

Check if your instance is publicly accessible:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --query 'DBInstances[0].{PubliclyAccessible:PubliclyAccessible,Endpoint:Endpoint.Address}' \
  --output table \
  --region $AWS_REGION
```

Expected output (yours will differ):

```
+-------------------+--------------------------------------------------+
| Endpoint          | my-postgres-db.abc123.us-east-1.rds.amazonaws.com|
| PubliclyAccessible| False                                            |
+-------------------+--------------------------------------------------+
```

If `PubliclyAccessible` shows `True`, disable it:

```bash
aws rds modify-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --no-publicly-accessible \
  --apply-immediately \
  --region $AWS_REGION
```

`--no-publicly-accessible` removes the public IP and DNS entry.

### Console

**Checking public accessibility:**

1. Open the [AWS Console](https://console.aws.amazon.com) and sign in.
2. In the top search bar, type **RDS** and click **RDS** under Services.
3. In the left sidebar, click **Databases**.
4. Find your instance in the list and click its name (it is a blue link in the **DB identifier** column).
5. You are now on the instance detail page. Click the **Connectivity & security** tab (it is near the top of the page, below the instance name).
6. Look for the **Public accessibility** row in the **Connectivity & security** section on the left side of that tab.

You will see either **Yes** or **No** next to **Public accessibility**. If it says **Yes**, follow the steps below to disable it.

**Disabling public access:**

1. While still on the instance detail page, click the **Modify** button in the top-right corner of the page.
2. Scroll down to the **Connectivity** section.
3. Under **Additional configuration**, find the **Public access** setting.
4. Select **Not publicly accessible** (click the radio button next to it).
5. Scroll all the way to the bottom and click **Continue**.
6. On the **Schedule modifications** page, select **Apply immediately**.
7. Click **Modify DB instance** to confirm.

You will be taken back to the instance list. The instance status will change to **Modifying** for a few minutes. When it returns to **Available**, the change is complete. Go back to the **Connectivity & security** tab and confirm **Public accessibility** now shows **No**.

> **Concept:** A publicly accessible RDS instance gets a DNS entry that resolves to a public IP. Anyone on the internet can attempt a connection. Making it non-publicly-accessible means it only has a private IP inside your VPC. External connections are impossible at the network level, before any authentication even happens.

---

## Step 2 - Review and Tighten Your RDS Security Group

Find the security group attached to your RDS instance:

### CLI

```bash
export RDS_SG_ID=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text \
  --region $AWS_REGION)

echo "RDS Security Group: $RDS_SG_ID"
```

View current inbound rules:

```bash
aws ec2 describe-security-groups \
  --group-ids $RDS_SG_ID \
  --query 'SecurityGroups[0].IpPermissions' \
  --region $AWS_REGION
```

Expected output - BAD example (yours will differ):

```json
[
    {
        "FromPort": 5432,
        "ToPort": 5432,
        "IpProtocol": "tcp",
        "IpRanges": [
            {
                "CidrIp": "0.0.0.0/0",
                "Description": "PostgreSQL"
            }
        ]
    }
]
```

`0.0.0.0/0` means anyone can reach port 5432. This is wrong for a database.

Remove the open rule:

```bash
aws ec2 revoke-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0 \
  --region $AWS_REGION
```

`revoke-security-group-ingress` removes an inbound rule.

Add a rule that only allows traffic from your application servers' security group:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $APP_SG_ID \
  --description "Allow PostgreSQL from application servers only" \
  --region $AWS_REGION
```

`--source-group` means "allow traffic from instances that are members of this security group."
This is better than using an IP range because EC2 instances change IPs when they restart.

### Console

**Finding the security group attached to your RDS instance:**

1. In the AWS Console search bar, type **RDS** and click **RDS**.
2. In the left sidebar, click **Databases**.
3. Click the name of your RDS instance.
4. Click the **Connectivity & security** tab.
5. Under the **Security** section on that tab, look for **VPC security groups**. You will see the security group name listed as a blue link (for example, `rds-postgres-sg`). Note this name - you will need it below.

**Viewing inbound rules on the security group:**

1. In the AWS Console search bar, type **EC2** and click **EC2**.
2. In the left sidebar, scroll down and click **Security Groups** (it is under the **Network & Security** heading).
3. In the search box at the top of the security groups list, paste the security group ID or name you noted from the RDS console. Press **Enter**.
4. Click the name of the security group in the results list to open it.
5. Click the **Inbound rules** tab (it is below the security group summary at the top of the page).

You will see a table of all inbound rules. Look at the **Source** column. If any rule shows **0.0.0.0/0**, that means anyone on the internet can attempt a connection on that port. This is the problem you need to fix.

**Removing the open rule and adding a restricted rule:**

1. While on the **Inbound rules** tab, click the **Edit inbound rules** button (top-right of the rules table).
2. Find the row with **Source: 0.0.0.0/0** for port 5432. Click the **Delete** button (the X icon) on the right side of that row.
3. Now click **Add rule** at the bottom of the rules table to add a new row.
4. In the **Type** dropdown for the new row, select **PostgreSQL** (this automatically sets the port to 5432).
5. In the **Source** dropdown, select **Custom**.
6. In the search box that appears next to **Source**, start typing the security group ID of your application servers (e.g., `sg-0app1234`). Select it from the dropdown.
7. In the **Description** box at the end of the row, type: `Allow PostgreSQL from application servers only`.
8. Click **Save rules** in the bottom-right corner.

You will see a green success banner at the top of the page confirming the rules were saved. The **Inbound rules** tab will now show only the new rule with your app server security group as the source.

Verify the new rule:

```bash
aws ec2 describe-security-groups \
  --group-ids $RDS_SG_ID \
  --query 'SecurityGroups[0].IpPermissions' \
  --region $AWS_REGION
```

Expected output - GOOD (yours will differ):

```json
[
    {
        "FromPort": 5432,
        "ToPort": 5432,
        "IpProtocol": "tcp",
        "UserIdGroupPairs": [
            {
                "GroupId": "sg-0app1234",
                "Description": "Allow PostgreSQL from application servers only"
            }
        ]
    }
]
```

---

## Step 3 - Create a Custom DNS Name with Route53

RDS endpoints are long and contain the instance ID. When you replace the instance, the endpoint changes. Custom DNS solves this.

### Step 3a - Check Your Hosted Zone

List your Route53 hosted zones:

```bash
aws route53 list-hosted-zones \
  --query 'HostedZones[*].{Name:Name,Id:Id,Private:Config.PrivateZone}' \
  --output table
```

Expected output (yours will differ):

```
+--------------------------------------+--------------------------+---------+
| Id                                   | Name                     | Private |
+--------------------------------------+--------------------------+---------+
| /hostedzone/Z1234567890ABC           | internal.mycompany.com.  | True    |
+--------------------------------------+--------------------------+---------+
```

A private hosted zone only resolves inside your VPC. That is what you want for database DNS.

If you do not have a private hosted zone, create one:

```bash
aws route53 create-hosted-zone \
  --name "internal.example.com" \
  --caller-reference "$(date +%s)" \
  --hosted-zone-config "Comment=Private zone for internal services,PrivateZone=true" \
  --vpc "VPCRegion=$AWS_REGION,VPCId=$VPC_ID"
```

`--caller-reference` must be unique. Using the current timestamp works.
`PrivateZone=true` makes this a private zone visible only inside the VPC.

### Step 3b - Create the CNAME Record

```bash
export HOSTED_ZONE_ID="Z1234567890ABC"
```

Create a JSON file for the Route53 change:

```bash
cat > /tmp/dns-change.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "db.internal.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "$RDS_HOST"
          }
        ]
      }
    }
  ]
}
EOF
```

`Name` is your friendly database hostname.
`Type: CNAME` means this record points to another hostname (the RDS endpoint).
`TTL: 60` means DNS resolvers cache this for 60 seconds. Short TTL is good for databases because if you need to change it during an incident, clients pick it up in 60 seconds.

Apply the change:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file:///tmp/dns-change.json
```

Expected output (yours will differ):

```json
{
    "ChangeInfo": {
        "Id": "/change/C1234567890",
        "Status": "PENDING",
        "SubmittedAt": "2024-01-15T14:23:00+00:00"
    }
}
```

### Step 3c - Test the Custom DNS (from inside the VPC)

From an EC2 instance inside the same VPC:

```bash
nslookup db.internal.example.com
```

Expected output (yours will differ):

```
Server:   10.0.0.2
Address:  10.0.0.2#53

db.internal.example.com   canonical name = my-postgres-db.abc123.us-east-1.rds.amazonaws.com.
my-postgres-db.abc123.us-east-1.rds.amazonaws.com  Address: 10.0.1.45
```

Now your application can connect to `db.internal.example.com:5432` instead of the long RDS endpoint. When you replace the database, you update the CNAME and every application picks it up automatically.

---

## Step 4 - VPC Peering vs PrivateLink Comparison

### VPC Peering

VPC peering connects two VPCs so instances in one can talk to instances in the other.

**Use case:** You have an app VPC and a data VPC. Both are yours. You want EC2 in the app VPC to reach RDS in the data VPC.

Create a peering connection:

```bash
export REQUESTER_VPC_ID="vpc-0abc123456def7890"
export ACCEPTER_VPC_ID="vpc-0xyz987654uvw3210"

aws ec2 create-vpc-peering-connection \
  --vpc-id $REQUESTER_VPC_ID \
  --peer-vpc-id $ACCEPTER_VPC_ID \
  --region $AWS_REGION
```

Expected output (yours will differ):

```json
{
    "VpcPeeringConnection": {
        "VpcPeeringConnectionId": "pcx-0abc123",
        "Status": {
            "Code": "initiating-request"
        }
    }
}
```

Save the peering ID:

```bash
export PEERING_ID="pcx-0abc123"
```

Accept the peering request (the other VPC must accept it):

```bash
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region $AWS_REGION
```

Add a route in the app VPC's route table so traffic to the data VPC goes through the peering connection:

```bash
export APP_ROUTE_TABLE_ID="rtb-0abc123"
export DATA_VPC_CIDR="10.1.0.0/16"

aws ec2 create-route \
  --route-table-id $APP_ROUTE_TABLE_ID \
  --destination-cidr-block $DATA_VPC_CIDR \
  --vpc-peering-connection-id $PEERING_ID \
  --region $AWS_REGION
```

Also update the security group in the data VPC to allow traffic from the app VPC's CIDR.

> **Concept:** VPC peering is bidirectional. Both VPCs can see all resources in the other. This is convenient but gives broad access. Also, CIDR ranges cannot overlap between peered VPCs.

---

### PrivateLink (VPC Endpoint Service)

PrivateLink is one-directional. The consumer VPC can reach a specific service in the provider VPC. The provider cannot see anything in the consumer VPC.

**Use case:** A customer wants to connect their VPC to your database. You do not want to expose your whole VPC to them.

This is a multi-step setup:

**In the provider VPC (where RDS lives):**

Step 1 - Create a Network Load Balancer targeting the RDS instance:

```bash
aws elbv2 create-load-balancer \
  --name rds-nlb \
  --type network \
  --scheme internal \
  --subnets $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --region $AWS_REGION
```

`--type network` creates a Network Load Balancer (NLB). PrivateLink requires an NLB.
`--scheme internal` keeps the NLB private inside the VPC.

Expected output (yours will differ):

```json
{
    "LoadBalancers": [
        {
            "LoadBalancerArn": "arn:aws:elasticloadbalancing:...:loadbalancer/net/rds-nlb/...",
            "DNSName": "rds-nlb-abc123.elb.us-east-1.amazonaws.com",
            ...
        }
    ]
}
```

Step 2 - Create a target group pointing to the RDS IP:

```bash
export NLB_ARN="arn:aws:elasticloadbalancing:...:loadbalancer/net/rds-nlb/..."

aws elbv2 create-target-group \
  --name rds-targets \
  --protocol TCP \
  --port 5432 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --region $AWS_REGION
```

Step 3 - Create the endpoint service:

```bash
export TARGET_GROUP_ARN="arn:aws:elasticloadbalancing:...:targetgroup/rds-targets/..."

aws ec2 create-vpc-endpoint-service-configuration \
  --network-load-balancer-arns $NLB_ARN \
  --acceptance-required \
  --region $AWS_REGION
```

`--acceptance-required` means you must approve each consumer before they can connect.

**In the consumer VPC (the other account or VPC):**

Step 4 - Create a VPC endpoint:

```bash
export SERVICE_NAME="com.amazonaws.vpce.us-east-1.vpce-svc-0abc123"
export CONSUMER_VPC_ID="vpc-0consumer123"
export CONSUMER_SUBNET_ID="subnet-0consumer456"

aws ec2 create-vpc-endpoint \
  --vpc-id $CONSUMER_VPC_ID \
  --service-name $SERVICE_NAME \
  --vpc-endpoint-type Interface \
  --subnet-ids $CONSUMER_SUBNET_ID \
  --region $AWS_REGION
```

After the provider approves the endpoint, the consumer gets a private IP and DNS name to connect to the database.

### Console - Creating a VPC Endpoint for RDS

Use this approach when you want your private EC2 instances to reach the RDS API (AWS management plane) without going through the internet. This is separate from the PrivateLink service setup above.

1. In the AWS Console search bar, type **VPC** and click **VPC**.
2. In the left sidebar, scroll down and click **Endpoints** (it is under the **PrivateLink & Lattice** heading).
3. Click the **Create endpoint** button in the top-right corner.
4. On the **Create endpoint** page:
   - In the **Name tag** field, type a name for this endpoint, for example: `rds-endpoint`.
   - Under **Service category**, select **AWS services** (this is selected by default).
5. In the **Services** search box, type `rds` and press **Enter**. A list of RDS-related services will appear.
6. Find and select the service named **com.amazonaws.[your-region].rds** (for example, `com.amazonaws.us-east-1.rds`). Click the radio button next to it.
7. Under **VPC**, click the dropdown and select the VPC where your RDS instance lives.
8. Under **Subnets**, check the boxes next to your private subnets in each Availability Zone.
9. Under **IP address type**, leave the default set to **IPv4**.
10. Under **Security groups**, click the **X** to remove the default security group if it appears. Then click the search box and select the security group attached to your RDS instance.
11. Under **Policy**, leave it set to **Full access** for now (you can restrict it later).
12. Click **Create endpoint** at the bottom of the page.

You will be taken back to the **Endpoints** list. The new endpoint will show a **Status** of **Pending**. Refresh the page after about 60 seconds. When the status changes to **Available**, the endpoint is ready.

To confirm it worked, click the endpoint name in the list. On the detail page, click the **Subnets** tab. You will see a private IP address assigned in each subnet. Your RDS API calls from inside the VPC now route through this endpoint instead of the internet.

---

## Step 5 - Bastion Host Pattern

If you need to connect from your laptop to a private RDS instance (no public access), use a bastion host (also called a jump host).

```
  Your Laptop
      │
      │ SSH (port 22)
      ▼
  Bastion Host (EC2, public subnet, has public IP)
      │
      │ psql (port 5432) - inside VPC, private subnet
      ▼
  RDS Instance (private subnet, no public IP)
```

Set up an SSH tunnel:

```bash
ssh -L 5433:$RDS_HOST:5432 ec2-user@[BASTION-PUBLIC-IP] -N -f
```

`-L 5433:$RDS_HOST:5432` forwards local port 5433 through the bastion to RDS port 5432.
`-N` means do not execute a remote command (just tunnel).
`-f` runs in the background.

Now connect to `localhost:5433` from your laptop:

```bash
psql \
  --host=localhost \
  --port=5433 \
  --username=postgres \
  --dbname=postgres
```

psql thinks it is connecting to localhost, but the tunnel forwards all traffic to the actual RDS instance.

---

## Step 6 - Network ACLs (Extra Layer)

Security groups are stateful (they track connections). Network ACLs (NACLs) are stateless and apply at the subnet level.

### CLI

View the NACL for your private subnets:

```bash
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_1" \
  --query 'NetworkAcls[0].Entries' \
  --region $AWS_REGION
```

### Console

**Viewing the Network ACL rules for your private subnet:**

1. In the AWS Console search bar, type **VPC** and click **VPC**.
2. In the left sidebar, click **Subnets** (it is under the **Virtual private cloud** heading).
3. In the subnets list, find one of your private subnets (for example, `subnet-0abc123`). Click its name or ID to open it.
4. Scroll down to the bottom of the subnet detail page. Click the **Network ACL** tab.
5. You will see the Network ACL ID associated with this subnet (for example, `acl-0abc123`). Click that ID - it is a blue link. This opens the NACL detail page.
6. On the NACL detail page, you will see two tabs: **Inbound rules** and **Outbound rules**. Click **Inbound rules**.

The table shows each rule as a numbered row. The columns are:

- **Rule number** - Rules are evaluated lowest number first. The first matching rule wins.
- **Type** - The protocol (e.g., All traffic, Custom TCP).
- **Port range** - The port or range of ports.
- **Source** - Where the traffic is coming from (CIDR block).
- **Allow/Deny** - Whether this rule allows or denies matching traffic.

Look for any rules with a **Source** of `0.0.0.0/0` and a decision of **Allow**. The default NACL has one rule that allows all traffic - this is normally fine because security groups are your primary control. If you see unexpected **Deny** rules or if traffic that should work is being blocked, this is where to look.

> **Note:** NACLs are stateless. If you add an inbound rule to allow port 5432, you must also add an outbound rule to allow the ephemeral return ports (1024-65535) or responses will be blocked. Security groups handle this automatically - NACLs do not.

For most setups, the default NACL (which allows all traffic) is fine because security groups handle the real restriction. Use custom NACLs when you need an extra compliance layer, such as blocking specific IP ranges at the subnet level.

---

## Step 7 - Audit Network Exposure

Run this command to find any RDS instances in your account that are publicly accessible:

```bash
aws rds describe-db-instances \
  --query 'DBInstances[?PubliclyAccessible==`true`].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address}' \
  --output table \
  --region $AWS_REGION
```

Any instance listed here should be reviewed. In most production environments, zero instances should be publicly accessible.

---

## What You Built

- Verified and disabled public accessibility on your RDS instance
- Tightened the security group to allow only application server traffic
- Created a custom Route53 CNAME for a friendly database hostname
- Learned VPC peering setup and when to use it
- Learned PrivateLink setup for cross-VPC or cross-account isolation
- Learned the bastion host SSH tunnel pattern for developer access

---

## Network Isolation Checklist

Before calling an RDS setup production-ready, verify:

- [ ] `PubliclyAccessible` is `False`
- [ ] Security group allows port 5432 from specific sources only (no `0.0.0.0/0`)
- [ ] RDS is in private subnets (no direct route to the internet gateway)
- [ ] A bastion or VPN exists for developer access
- [ ] Custom DNS name is set up (so changing instances does not break config files)
- [ ] VPC peering or PrivateLink is configured for any cross-VPC access needs

---

## Key Rules to Remember

1. No production database should have `PubliclyAccessible: True`
2. Security group source should reference another security group, not an IP range
3. Use CNAME DNS records with short TTL (60s) for all database hostnames
4. PrivateLink for cross-account or customer-facing database access
5. VPC peering for internal multi-VPC architectures you control
6. Bastion hosts or VPN for developer access - never open port 5432 to the internet
