# Build 04 - Connectivity Deep Dive
## Tier 1: Provisioning and Connectivity

**Estimated time:** 35 minutes
**Difficulty:** Beginner
**Prerequisite:** Build 01 complete (running RDS instance)

---

## What You Will Do

You will investigate how RDS connectivity works at each layer. By the end you will:

- Use `dig` and `nslookup` to see what an RDS endpoint resolves to
- Understand DB subnet groups: what they require and how to inspect them
- Understand security group rules for RDS
- Know when to use public vs private access
- Be able to diagnose and fix a "connection timed out" error

---

## Part A - Endpoints and DNS Resolution

The RDS endpoint looks like a hostname but it is really a DNS alias. Understanding what it resolves to helps you troubleshoot.

### Step 1 - Resolve the RDS Endpoint

First, get your endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

Save the output as `RDS_ENDPOINT`. Replace it in the commands below.

Now resolve the DNS name using `dig`:

```bash
dig +short YOUR_RDS_ENDPOINT
```

Expected output (yours will differ):
```
54.234.189.12
```

Or on some setups you might see a private IP:
```
10.0.1.45
```

> **Concept:** If you see a public IP (like 54.x.x.x), your instance has public access enabled. If you see a private IP (like 10.x.x.x or 172.x.x.x), the instance is private and can only be accessed from inside the VPC.

### Step 2 - Resolve with nslookup

```bash
nslookup YOUR_RDS_ENDPOINT
```

Expected output (yours will differ):
```
Server:         8.8.8.8
Address:        8.8.8.8#53

Non-authoritative answer:
Name:   suta-rds-lab.abc123.us-east-1.rds.amazonaws.com
Address: 54.234.189.12
```

### Step 3 - What Happens When RDS Fails Over

With Multi-AZ RDS, when the primary fails, AWS updates the DNS record to point to the standby (which has been promoted to primary). This DNS change happens in 60 to 120 seconds.

Your application needs to reconnect after a failover because the TCP connection is broken when the original host goes down. The DNS TTL on RDS endpoints is 5 seconds, so your reconnect will quickly get the new IP.

```
Normal state:
  dig suta-rds-lab.abc123.us-east-1.rds.amazonaws.com -> 54.234.189.12 (primary AZ-a)

After failover:
  dig suta-rds-lab.abc123.us-east-1.rds.amazonaws.com -> 54.198.77.33 (standby AZ-b, now primary)
```

> **Concept:** Never hardcode the IP address of an RDS instance. Always use the endpoint hostname. The IP can change during failover, maintenance, or when you change the instance class.

### Step 4 - Trace the Route to Your Endpoint

```bash
traceroute YOUR_RDS_ENDPOINT
```

Expected output (yours will differ):
```
traceroute to suta-rds-lab.abc123.us-east-1.rds.amazonaws.com (54.234.189.12)
 1  192.168.1.1  2.4 ms
 2  ...
 5  54.234.189.12  18.3 ms  19.1 ms  18.8 ms
```

If `traceroute` hangs (shows `* * *`), the path is being blocked. This usually means a security group is blocking ICMP (which traceroute uses). That is expected in many AWS setups. Try with TCP instead:

```bash
traceroute -T -p 5432 YOUR_RDS_ENDPOINT
```

---

## Part B - DB Subnet Groups

A DB Subnet Group is a collection of subnets within a VPC. RDS uses it to decide where to place your instance.

### Requirements for a Valid Subnet Group

1. All subnets must be in the same VPC.
2. You must include subnets in at least 2 different Availability Zones.
3. Each subnet must have enough IP addresses (at least 2 free).

### Step 1 - List Your Subnet Groups

```bash
aws rds describe-db-subnet-groups \
  --query "DBSubnetGroups[*].{Name:DBSubnetGroupName,VPC:VpcId,Status:SubnetGroupStatus}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------------
|              DescribeDBSubnetGroups                       |
+--------+----------+-----------------------+
| Name   | Status   |       VPC             |
+--------+----------+-----------------------+
| default| Complete | vpc-0abc1234def56789a |
| suta-rds-lab-subnetgroup | Complete | vpc-0abc1234def56789a |
+--------+----------+-----------------------+
```

### Step 2 - Inspect a Subnet Group in Detail

#### Using the CLI

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name suta-rds-lab-subnetgroup \
  --query "DBSubnetGroups[0].Subnets[*].{SubnetID:SubnetIdentifier,AZ:SubnetAvailabilityZone.Name,Status:SubnetStatus}" \
  --output table
```

Expected output:
```
-------------------------------------------------------------
|              DescribeDBSubnetGroups                       |
+-------------------+----------+---------------------------+
|      AZ           |  Status  |       SubnetID            |
+-------------------+----------+---------------------------+
|  us-east-1a       |  Active  |  subnet-0abc123           |
|  us-east-1b       |  Active  |  subnet-0def456           |
|  us-east-1c       |  Active  |  subnet-0ghi789           |
+-------------------+----------+---------------------------+
```

Three subnets, three different AZs. This is valid.

#### Using the Console

1. Open the AWS Console at https://console.aws.amazon.com
2. In the search bar at the top, type `RDS` and click **RDS** in the results.
3. In the left sidebar, click **Subnet groups**.
4. You will see a list of all subnet groups. Click the name of the subnet group you want to inspect (for example, **suta-rds-lab-subnetgroup**).
5. The detail page opens. Scroll down to the **Subnets** section.
6. You will see a table with columns: **Subnet ID**, **Availability Zone**, **CIDR**, **Status**. Confirm that:
   - There are subnets in at least 2 different Availability Zones (shown in the **Availability Zone** column).
   - All subnets show **Active** in the **Status** column.

> If you only see one Availability Zone listed, the subnet group is not valid for Multi-AZ deployments. You must add subnets from at least one other AZ.

### Step 3 - View Subnet Details (CIDR, Available IPs)

```bash
aws ec2 describe-subnets \
  --subnet-ids subnet-0abc123 \
  --query "Subnets[0].{CIDR:CidrBlock,AvailableIPs:AvailableIpAddressCount,AZ:AvailabilityZone}" \
  --output table
```

Expected output:
```
---------------------------------------------
|          DescribeSubnets                  |
+----------------+----------+--------------+
|      AZ        | Available|     CIDR     |
|                |   IPs    |              |
+----------------+----------+--------------+
|  us-east-1a    |  4091    | 10.0.1.0/24  |
+----------------+----------+--------------+
```

4091 available IPs in this subnet. More than enough.

### What the "default" Subnet Group Is

When you create an RDS instance in the default VPC and do not specify a subnet group, AWS uses the "default" subnet group. It automatically includes all default subnets in your VPC.

For production, always create a dedicated subnet group with private subnets (not the default public subnets).

---

## Part C - Security Groups for RDS

A security group is a stateful firewall. "Stateful" means if you allow an inbound connection, the return traffic is automatically allowed without a separate outbound rule.

### Step 1 - Find Your RDS Security Group

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId" \
  --output text
```

Expected output:
```
sg-0abc123def456789a
```

### Step 2 - View the Security Group Rules

#### Using the CLI

Replace `YOUR_SG_ID` with the security group ID from above.

```bash
aws ec2 describe-security-groups \
  --group-ids YOUR_SG_ID \
  --query "SecurityGroups[0].IpPermissions" \
  --output json
```

Expected output:
```json
[
    {
        "FromPort": 5432,
        "IpProtocol": "tcp",
        "IpRanges": [
            {
                "CidrIp": "203.0.113.42/32",
                "Description": "My laptop"
            }
        ],
        "ToPort": 5432
    }
]
```

This shows one inbound rule: allow TCP on port 5432 from one specific IP.

#### Using the Console

1. Open the AWS Console at https://console.aws.amazon.com
2. In the search bar at the top, type `EC2` and click **EC2** in the results.
3. In the left sidebar, scroll down and click **Security Groups** (it is under the **Network & Security** section).
4. In the search box on the security groups page, paste your security group ID (for example, `sg-0abc123def456789a`) and press **Enter**.
5. Click the security group name in the results to open it.
6. Click the **Inbound rules** tab (near the middle of the page).
7. You will see a table showing all inbound rules. Look for a row where:
   - **Type** is **PostgreSQL** (or **Custom TCP**)
   - **Port range** is **5432**
   - **Source** shows the IP address or CIDR that is allowed

> If you do not see port 5432 in this list, no one is allowed to connect to your RDS instance. That is why you are getting "Connection timed out".

### Step 3 - Add Another IP to the Security Group

If you are working from a different network (like a coffee shop), you need to add your new IP.

#### Using the CLI

First, get your new IP:

```bash
curl -s https://checkip.amazonaws.com
```

Then add it:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id YOUR_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr NEW_IP/32
```

#### Using the Console

1. Open the AWS Console at https://console.aws.amazon.com
2. In the search bar at the top, type `EC2` and click **EC2** in the results.
3. In the left sidebar, click **Security Groups** (under **Network & Security**).
4. Find and click your security group (search by ID if needed).
5. Click the **Inbound rules** tab.
6. Click the **Edit inbound rules** button (top right of the inbound rules table).
7. On the **Edit inbound rules** page, click **Add rule** at the bottom.
8. A new row appears. Fill it in:
   - **Type**: Click the dropdown and select **PostgreSQL**. The port fills in automatically as **5432**.
   - **Source**: Click the dropdown and select **My IP**. The Console automatically detects and fills in your current public IP address. You will see something like `203.0.113.42/32`.
   - **Description** (optional but recommended): Type something like `My laptop - coffee shop`.
9. Click **Save rules** (bottom right).
10. You will return to the security group page and see a green **Inbound rules updated** banner. Your new rule now appears in the **Inbound rules** tab.

### Step 4 - Remove an IP from the Security Group

When you no longer need access from an IP:

```bash
aws ec2 revoke-security-group-ingress \
  --group-id YOUR_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr OLD_IP/32
```

### Step 5 - Allow Access from a VPC CIDR (App Server Pattern)

If your app server is in the same VPC (10.0.0.0/16), allow the whole VPC to connect:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id YOUR_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr 10.0.0.0/16
```

### Security Group Reference Pattern (Recommended for Production)

Instead of allowing an IP range, you can allow a source security group. This means "allow traffic from any EC2 instance that is in this security group".

This is safer because:
- You do not hardcode IPs
- If an app server changes IP, it still works as long as it is in the allowed security group
- You can revoke access by removing an instance from the app security group

```bash
# Allow traffic from app servers (replace with your app server security group)
aws ec2 authorize-security-group-ingress \
  --group-id YOUR_RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group YOUR_APP_SG_ID
```

---

## Part D - Public vs Private Access

### What "Publicly Accessible" Actually Controls

When you set "Publicly Accessible = Yes" on an RDS instance:
- AWS assigns a public IP to the instance
- DNS resolves the endpoint to that public IP from outside the VPC
- You can connect from your laptop without being in the VPC

When you set "Publicly Accessible = No":
- AWS only gives the instance a private IP
- DNS resolves the endpoint to a private IP from outside the VPC (which you cannot reach)
- You must be inside the VPC to connect

### Check Current Public Access Setting and View the Endpoint

#### Using the CLI

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].PubliclyAccessible" \
  --output text
```

Expected output:
```
True
```

To also see the endpoint in the same command:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].{Endpoint:Endpoint.Address,Port:Endpoint.Port,PubliclyAccessible:PubliclyAccessible}" \
  --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------------
|                      DescribeDBInstances                         |
+---------------------+-------+------------------------------------+
|      Endpoint       | Port  |       PubliclyAccessible           |
+---------------------+-------+------------------------------------+
|  suta-rds-lab.abc123.us-east-1.rds.amazonaws.com | 5432 | True  |
+---------------------+-------+------------------------------------+
```

#### Using the Console

1. Open the AWS Console at https://console.aws.amazon.com
2. In the search bar at the top, type `RDS` and click **RDS** in the results.
3. In the left sidebar, click **Databases**.
4. Click the name of your database (for example, **suta-rds-lab**) to open the detail page.
5. On the detail page, click the **Connectivity & security** tab (it is one of the tabs near the top of the page).
6. You will see the **Endpoint & port** section at the top. It shows:
   - **Endpoint**: the full DNS hostname you use to connect (for example, `suta-rds-lab.abc123.us-east-1.rds.amazonaws.com`)
   - **Port**: `5432`
   - Copy this endpoint exactly - use the copy icon next to it.
7. Scroll down on the same **Connectivity & security** tab to the **Security** section. Look for the **Publicly accessible** field. It will show either **Yes** or **No**.

> If **Publicly accessible** shows **No** and you are connecting from your laptop, you cannot reach this instance directly. You need to either change this setting or connect through a bastion host inside the VPC.

### Changing Public Access

You can modify this setting on an existing instance.

#### Using the CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-rds-lab \
  --no-publicly-accessible \
  --apply-immediately
```

Or to make it public again:

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-rds-lab \
  --publicly-accessible \
  --apply-immediately
```

#### Using the Console

1. Open the AWS Console at https://console.aws.amazon.com
2. In the search bar at the top, type `RDS` and click **RDS** in the results.
3. In the left sidebar, click **Databases**.
4. Click the name of your database (for example, **suta-rds-lab**).
5. In the top right of the page, click the **Modify** button.
6. On the **Modify DB instance** page, scroll down to the **Connectivity** section.
7. Under **Additional configuration**, find **Publicly accessible**.
   - To allow direct connections from the internet: select **Publicly accessible**.
   - To restrict to VPC-only access: select **Not publicly accessible**.
8. Scroll to the bottom and click **Continue**.
9. On the review page, under **Scheduling of modifications**, select **Apply immediately**.
10. Click **Modify DB instance** to confirm.
11. You are returned to the database list. The status will briefly change to **Modifying** and then return to **Available**. The change is complete when the status is **Available** again.

### When to Use Each Setting

| Scenario | Publicly Accessible |
|----------|-------------------|
| Learning lab (your laptop connects directly) | Yes |
| Dev/test instance (team connects from office IP) | Yes, with strict SG rules |
| Production database | No - use bastion or VPN |
| Internal microservices (app in same VPC) | No |
| Analytics tool running on a separate VM | No - peer VPCs or use a bastion |

---

## Part E - Troubleshooting "Connection Timed Out"

"Connection timed out" is the most common RDS connectivity problem beginners face. Here is the systematic way to fix it.

> **Concept:** "Connection timed out" means your computer sent a connection request (SYN packet) but never received a response. Something is blocking the traffic before it reaches PostgreSQL.

### The Troubleshooting Checklist

Work through this list in order. Stop when you find the problem.

#### Check 1 - Is the instance running?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text
```

Expected: `available`
If you see `stopped`, `starting`, or `creating`, wait or start the instance.

**Start a stopped instance:**

```bash
aws rds start-db-instance \
  --db-instance-identifier suta-rds-lab
```

Then wait:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier suta-rds-lab
```

#### Check 2 - Are you using the right endpoint?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

Compare this output to what you are using in your connection string. They must match exactly.

#### Check 3 - Does the DNS name resolve?

```bash
dig +short YOUR_RDS_ENDPOINT
```

If this returns nothing, the endpoint is wrong. Copy it fresh from the CLI or Console.

If it returns an IP, continue to the next check.

#### Check 4 - Is public access enabled?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].PubliclyAccessible" \
  --output text
```

If this returns `False` and you are connecting from your laptop (outside the VPC), that is your problem. Either enable public access or use a bastion.

#### Check 5 - Is your IP allowed in the security group?

First, get your current IP:

```bash
curl -s https://checkip.amazonaws.com
```

Then get the security group ID:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" \
  --output text
```

Then check the rules:

```bash
aws ec2 describe-security-groups \
  --group-ids YOUR_SG_ID \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\`]" \
  --output json
```

Look at the `CidrIp` values. Does any of them match your current IP? If not, add it:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id YOUR_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr YOUR_IP/32
```

#### Check 6 - Test Port Connectivity Directly

Use `nc` (netcat) to test if port 5432 is reachable without involving PostgreSQL at all:

```bash
nc -zv YOUR_RDS_ENDPOINT 5432
```

Expected output when port is open:
```
Connection to suta-rds-lab.abc123.us-east-1.rds.amazonaws.com 5432 port [tcp/postgresql] succeeded!
```

If you see `Connection refused` or the command hangs, the port is not reachable. Go back and fix the security group or public access setting.

#### Check 7 - Try Connecting with Verbose Output

psql's `-W` flag forces a password prompt. Adding the connection string in verbose mode shows more detail:

```bash
PGPASSWORD=YOUR_PASSWORD psql \
  "host=YOUR_RDS_ENDPOINT port=5432 dbname=labdb user=postgres sslmode=require connect_timeout=10"
```

The `connect_timeout=10` means fail after 10 seconds instead of waiting forever.

### Summary of Error Messages and Fixes

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `Connection timed out` | Security group blocking port 5432 | Add your IP to SG inbound rule |
| `Connection timed out` | Instance is stopped | Start the instance |
| `Connection timed out` | Public access = No | Enable public access or use bastion |
| `Connection refused` | PostgreSQL not running | Check instance status |
| `Name or service not known` | Wrong endpoint hostname | Copy endpoint fresh from Console/CLI |
| `could not translate host name` | DNS cannot resolve endpoint | Check endpoint spelling |
| `FATAL: password authentication failed` | Wrong password or username | Reset password in Console |
| `FATAL: database "xyz" does not exist` | Wrong database name | Connect to `postgres` db or `labdb` |
| `SSL SYSCALL error` | SSL mismatch | Add `sslmode=require` to connection |

---

## Summary

| Topic | Key Point |
|-------|-----------|
| DNS resolution | RDS endpoint is a DNS alias. Always use the hostname, never the IP. |
| Subnet groups | Need subnets in 2+ AZs. All in same VPC. |
| Security groups | Stateful firewall. Must have inbound rule for port 5432. |
| Public access | Yes = direct from internet. No = must be inside VPC. |
| Connection timed out | Work through the 7-step checklist: status, endpoint, DNS, public access, SG, nc, psql. |

**Next:** Build 05 covers connecting with different clients (psql, pgAdmin, Python) and explains the master user and SSL.
