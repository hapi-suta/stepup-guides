# Tier 0 - Foundations
## Guide 03: AWS Account, IAM Users, Roles, and Regions

**Objective:** Understand the structure of an AWS account, how IAM controls access to AWS resources, and how regions and Availability Zones affect where your databases live. Then install and configure the AWS CLI and verify your identity.
**Time:** 30 minutes
**Prerequisites:** An AWS account (free tier is fine). Access to a terminal on your local machine.
**Infrastructure:** None - you will use the AWS CLI against your own account only.

---

## 1. The AWS Account

An AWS account is the root container for all your AWS resources. Everything - your RDS instances, VPCs, IAM users, S3 buckets - lives inside a single account (or spread across multiple accounts if your organization uses AWS Organizations).

When you first create an AWS account, you sign in with an **email address and password**. This login is called the **root user**. The root user has unlimited access to everything in the account with no restrictions.

**Do not use the root user for day-to-day work.**

This is not just a recommendation - it is a security requirement in any professional environment. If root credentials are compromised, an attacker has unrestricted access to your entire AWS footprint. Create an IAM user for all regular work, and lock the root user behind MFA.

---

## 2. IAM - Identity and Access Management

IAM is the AWS service that controls who can do what inside your account. There are three main concepts to understand: users, roles, and policies.

### IAM Users

An IAM user is a permanent identity tied to a specific person or application. It has a username and can be given:
- A **password** for logging into the AWS Console (the web UI)
- **Access keys** (an Access Key ID and Secret Access Key) for programmatic access via the CLI or API

IAM users are appropriate for:
- Individual humans who need AWS Console access
- Legacy automation that cannot use roles

As a DBA, you will have an IAM user to log into the console and configure the CLI.

### IAM Roles

An IAM role is a temporary identity that can be assumed by an entity - a user, a service, or an application. Roles do not have permanent credentials. When a role is assumed, AWS issues temporary security credentials that expire.

Roles are appropriate for:
- EC2 instances that need to call AWS APIs (the instance assumes a role, no hardcoded keys)
- Lambda functions
- Cross-account access
- Services like RDS calling other AWS services (e.g., RDS Enhanced Monitoring assumes a role to write to CloudWatch)

You will encounter roles when you set up things like Enhanced Monitoring on RDS or when your application runs on EC2 and needs to call AWS APIs without storing access keys in the code.

### IAM Policies

A policy is a JSON document that defines what actions are allowed or denied on which resources. Policies are attached to users, roles, or groups.

A simple example - this policy allows the attached entity to describe (list/view) all RDS instances but not create or delete any:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

The key fields in a policy statement:
- `Effect` - either `Allow` or `Deny`
- `Action` - the specific API calls being controlled (e.g., `rds:CreateDBInstance`)
- `Resource` - which specific resources this applies to (`*` means all)

AWS has hundreds of pre-built policies called **Managed Policies**. `AdministratorAccess` gives full access to everything. `AmazonRDSFullAccess` gives full RDS access. For production environments, you write custom policies that grant only what is needed.

### IAM Groups

Groups are collections of IAM users. You attach policies to groups rather than individual users. When a user joins the group, they inherit the group's policies. This makes it easier to manage permissions at scale - instead of editing 20 users when a policy changes, you edit one group.

---

## 3. Principle of Least Privilege

The principle of least privilege means: **give an identity only the permissions it needs to do its job - nothing more.**

In database work, this looks like:

| Identity | What They Need | What They Should NOT Have |
|----------|---------------|--------------------------|
| DBA (dev environment) | Full RDS access in dev account | Production RDS access |
| DBA (production) | Read RDS metadata, apply parameter groups, create snapshots | Delete production databases |
| Application IAM role | Connect to RDS via IAM auth | Modify RDS instance settings |
| Monitoring tool | `rds:Describe*`, `cloudwatch:GetMetricData` | Any write access |
| Backup automation | `rds:CreateDBSnapshot`, `rds:CopyDBSnapshot` | Delete snapshots outside retention period |

Apply this same thinking to your PostgreSQL database users too - a read-only reporting role should not have `INSERT` or `DELETE` privileges on any table.

---

## 4. Regions and Availability Zones

### Regions

AWS has data centers around the world organized into **Regions**. Each region is a separate geographic area with its own completely independent infrastructure. Examples:

| Region Code | Location |
|------------|----------|
| `us-east-1` | Northern Virginia, USA |
| `us-west-2` | Oregon, USA |
| `eu-west-1` | Ireland |
| `ap-southeast-1` | Singapore |
| `af-south-1` | Cape Town, South Africa |

Resources in one region are completely isolated from resources in another region. An RDS instance in `us-east-1` cannot directly communicate with one in `eu-west-1` without going through your application or explicit cross-region configurations.

**How to pick a region:**

1. **Latency** - choose the region closest to your users or applications. A database in Singapore serving users in Nigeria will have high latency.
2. **Compliance and data residency** - some regulations (GDPR, local data laws) require data to stay in specific geographic areas. If you serve EU customers under GDPR, you may be required to keep data in an EU region.
3. **Service availability** - not all AWS services and features are available in every region. Newer features often launch in `us-east-1` first and roll out to other regions over months. Check the AWS regional services list before committing to a region.
4. **Cost** - pricing varies by region. `us-east-1` is typically the cheapest. `ap-southeast-2` (Sydney) and `af-south-1` (Cape Town) tend to be more expensive.
5. **Disaster recovery** - for cross-region DR, pick a secondary region that is geographically distant from your primary.

### Availability Zones

Within each region, AWS has multiple **Availability Zones** (AZs). Each AZ is one or more physically separate data centers with independent power, cooling, and networking.

`us-east-1` has 6 AZs: `us-east-1a`, `us-east-1b`, `us-east-1c`, `us-east-1d`, `us-east-1e`, `us-east-1f`.

AZs within a region are connected by low-latency, high-bandwidth private fiber links. They are close enough for synchronous replication to work with acceptable latency, but far enough apart that a fire or flood in one does not affect another.

For databases, this matters because:
- RDS Multi-AZ puts your primary in one AZ and standby in another. If the primary AZ goes down, failover happens to a healthy AZ.
- Aurora spreads its 6 storage copies across 3 AZs by default - giving you automatic resilience to a full AZ failure.
- DB Subnet Groups (covered in Guide 04) require subnets in at least 2 AZs.

---

## 5. Install the AWS CLI

The AWS CLI lets you interact with AWS from your terminal. You will use it throughout this curriculum to explore resources and automate tasks.

### Step 1: Check if the AWS CLI is already installed

Open your terminal and run:

```bash
aws --version
```

Expected output (yours will differ):
```
aws-cli/2.15.30 Python/3.11.8 Darwin/23.4.0 exe/x86_64 prompt/off
```

If you see a version number, skip to Step 4. If you see `command not found`, continue with Step 2.

### Step 2: Download the installer

**On macOS:**

```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
```

This command downloads the AWS CLI v2 installer package to your `/tmp` directory.
- `curl` - a tool for downloading files from URLs
- `-o "/tmp/AWSCLIV2.pkg"` - saves the download to that file path

**On Linux (x86_64):**

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
```

### Step 3: Install the CLI

**On macOS:**

```bash
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
```

This runs the macOS package installer silently.
- `sudo` - runs the command as root (required to install to system directories)
- `installer` - the macOS package installer utility
- `-pkg` - specifies the package file to install
- `-target /` - installs to the root filesystem (the whole system)

**On Linux:**

```bash
cd /tmp
```

```bash
unzip awscliv2.zip
```

```bash
sudo ./aws/install
```

### Step 4: Verify the installation

```bash
aws --version
```

Expected output (yours will differ):
```
aws-cli/2.15.30 Python/3.11.8 Darwin/23.4.0 exe/x86_64 prompt/off
```

---

## 6. Configure the AWS CLI

Now you need to tell the CLI which AWS account to use and how to authenticate.

### Step 1: Get your IAM access keys

Before running this step, you need an Access Key ID and Secret Access Key from your IAM user.

To get them:
1. Log into the AWS Console at https://console.aws.amazon.com
2. Click your username in the top-right corner
3. Click "Security credentials"
4. Under "Access keys", click "Create access key"
5. Copy both the Access Key ID and the Secret Access Key - you cannot view the secret key again after closing this screen

### Step 2: Run aws configure

```bash
aws configure
```

This launches an interactive setup prompt. Enter your details when asked:

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: [REGION]
Default output format [None]: json
```

- **Access Key ID** - the public part of your IAM credentials (starts with `AKIA`)
- **Secret Access Key** - the private part - treat this like a password, never share it
- **Default region** - the region your CLI commands will target unless you override it. Use the region code for your location (e.g., `us-east-1`, `eu-west-1`)
- **Default output format** - `json` is the most common. Other options are `text` and `table`

The CLI stores these values in two files:
- `~/.aws/credentials` - stores the access keys
- `~/.aws/config` - stores the region and output format

### Step 3: Verify your configuration

```bash
aws sts get-caller-identity
```

This command calls the AWS Security Token Service (STS) and returns the identity associated with your current credentials.
- `sts` - the Security Token Service subcommand group
- `get-caller-identity` - returns the account ID, user ID, and ARN of the calling identity

Expected output (yours will differ):
```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/happy-dba"
}
```

Verify that:
- The `Account` matches your AWS account ID (visible in the top-right of the AWS Console)
- The `Arn` shows your IAM username

If you get an error like `An error occurred (InvalidClientTokenId)`, your access key is wrong. Double-check by running `aws configure` again.

---

## 7. Explore Your Availability Zones

Now run a real AWS CLI command to see the Availability Zones available in your configured region.

```bash
aws ec2 describe-availability-zones --query "AvailabilityZones[*].{Name:ZoneName,State:State}" --output table
```

This command lists the AZs in your default region.
- `ec2 describe-availability-zones` - calls the EC2 API to list AZs (AZs are an EC2-level concept even though we use them for RDS)
- `--query` - filters the JSON response to show only the zone name and state
- `--output table` - formats the output as a readable table instead of JSON

Expected output (yours will differ):
```
---------------------------------------------
|        DescribeAvailabilityZones          |
+----------------+--------------------------+
|      Name      |          State           |
+----------------+--------------------------+
|  us-east-1a    |  available               |
|  us-east-1b    |  available               |
|  us-east-1c    |  available               |
|  us-east-1d    |  available               |
|  us-east-1e    |  available               |
|  us-east-1f    |  available               |
+----------------+--------------------------+
```

Note how many AZs your region has. This will matter when you create DB Subnet Groups in Guide 04.

---

## 8. Named Profiles (For Working With Multiple Accounts)

If you work with multiple AWS accounts - for example, a personal account, a dev account at [COMPANY], and a production account - you can use named profiles so you do not have to reconfigure every time.

### Create a named profile

```bash
aws configure --profile [ENV]-dba
```

This creates a separate set of credentials stored under the profile name `[ENV]-dba`. Fill in the prompts the same way you did before, but with the credentials for that specific account.

### Use a named profile

```bash
aws sts get-caller-identity --profile [ENV]-dba
```

Adding `--profile [ENV]-dba` to any CLI command tells the CLI to use that profile's credentials and region instead of the default.

### Set a profile as active for a session

```bash
export AWS_PROFILE=[ENV]-dba
```

This sets an environment variable so all CLI commands in your current terminal session use that profile without needing the `--profile` flag each time.

To go back to the default:

```bash
unset AWS_PROFILE
```

---

## Summary

- The AWS root user has unlimited access and should never be used for day-to-day work. Create IAM users instead.
- IAM users are permanent identities for humans. IAM roles are temporary identities for services and automation.
- IAM policies are JSON documents that define what actions are allowed or denied on which resources.
- The principle of least privilege means granting only the permissions required for a specific job - nothing more.
- Regions are geographic areas with independent infrastructure. Pick a region based on latency, compliance, cost, and service availability.
- Availability Zones are physically separate data centers within a region - used for Multi-AZ RDS and distributed Aurora storage.
- The AWS CLI is configured with `aws configure` and verified with `aws sts get-caller-identity`.
- Named profiles let you manage credentials for multiple AWS accounts cleanly.

**Next:** [Guide 04 - VPC Networking for Databases](./04-vpc-networking-for-databases.md)
