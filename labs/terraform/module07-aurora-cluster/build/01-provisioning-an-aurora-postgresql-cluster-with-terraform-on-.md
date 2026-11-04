# Provisioning an Aurora PostgreSQL Cluster with Terraform on AWS

**Objective:** Install Terraform and the AWS CLI on an Amazon Linux server, write Terraform configuration files, and use them to create a running Aurora PostgreSQL cluster with one writer and one reader instance.

**Estimated Time:** 60-90 minutes

**Prerequisites:**
- An EC2 instance running Amazon Linux 9 (RHEL-compatible) with an IAM role attached that has RDS and EC2 describe permissions
- SSH access to the instance as `ec2-user`
- Basic comfort navigating the terminal and editing files in vi

---

## Background: The most important concept in this lab

An Aurora cluster in Terraform is made of separate, independent resources:

- `aws_rds_cluster` - the control plane: endpoints, master credentials, engine version, database name
- `aws_rds_cluster_instance` - the compute plane: the actual server nodes that run queries

You cannot create one combined resource. You must define the cluster first, then attach instances to it. This also means if you ever import an existing Aurora cluster into Terraform state, you must run `terraform import` separately for the cluster AND for each instance.

---

## Part 1: Install Terraform

### Step 1: Add the HashiCorp package repository

Why this step: Terraform is not in the default Amazon Linux package list. HashiCorp provides their own repository that you must register before you can install from it.

On the server, as ec2-user:

```
sudo yum install -y yum-utils
```

This installs `yum-utils`, a helper package that provides the `yum-config-manager` command used in the next step. The `-y` flag answers "yes" automatically to any prompts.

Expected output (yours will differ):
```
Last metadata expiration check: 0:00:01 ago on Sun 25 Oct 2026 07:28:51 PM UTC.
Package yum-utils-4.3.0-27.el9.noarch is already installed.
...
Complete!
```

Check it worked: you should see the word `Complete!` at the end.

### Step 2: Register the HashiCorp repository

On the server, as ec2-user:

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

This tells `yum` to look at HashiCorp's package server when you search for packages like Terraform. `--add-repo` saves the URL as a new repo definition.

Expected output (yours will differ):
```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line starting with `Adding repo from:`.

### Step 3: Install Terraform

On the server, as ec2-user:

```
sudo yum -y install terraform
```

This downloads and installs the latest Terraform package from the HashiCorp repository. The `-y` flag skips the confirmation prompt.

Expected output (yours will differ):
```
Installed:
  terraform-1.17.0-1.x86_64

Complete!
```

Check it worked: you should see `terraform-1.17.0` (or a similar version) in the `Installed:` section.

### Step 4: Confirm Terraform is installed

On the server, as ec2-user:

```
terraform version
```

This prints the installed Terraform version to the screen.

Expected output (yours will differ):
```
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a line starting with `Terraform v`.

---

## Part 2: Install the AWS CLI

The AWS CLI lets you talk to AWS services from the command line. Terraform uses the same underlying credentials, so you need it installed and working.

### Step 5: Install unzip

Why this step: The AWS CLI comes as a zip file. Amazon Linux 9 does not include `unzip` by default.

On the server, as ec2-user:

```
sudo yum install -y unzip
```

This installs the `unzip` utility so you can extract the AWS CLI package.

Expected output (yours will differ):
```
unzip-6.0-59.el9.x86_64

Complete!
```

Check it worked: you should see `unzip` listed under the installed packages and the word `Complete!`.

### Step 6: Download the AWS CLI installer

On the server, as ec2-user:

```
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

This downloads the AWS CLI v2 zip file to `/tmp/awscliv2.zip`. `-s` means silent mode (no progress bar). `-o` sets the output filename.

Expected output (yours will differ):
```
(no output - the file downloads silently)
```

Check it worked: the command returns with no error message. You can confirm the file exists in the next step.

### Step 7: Move into the /tmp directory

On the server, as ec2-user:

```
cd /tmp
```

This changes your working directory to `/tmp` where the downloaded file is stored.

Expected output (yours will differ):
```
(no output)
```

Check it worked: your prompt will now show `/tmp` or you can confirm by typing `pwd` and seeing `/tmp`.

### Step 8: Unzip the AWS CLI package

On the server, as ec2-user:

```
unzip -q awscliv2.zip
```

This extracts the downloaded zip file. `-q` means quiet mode so it does not print every filename as it extracts.

Expected output (yours will differ):
```
(no output - extracts silently)
```

Check it worked: no error messages appear. The extraction creates an `aws` folder in `/tmp`.

### Step 9: Run the AWS CLI installer

On the server, as ec2-user:

```
sudo /tmp/aws/install
```

This runs the official installer script that copies the AWS CLI binary to `/usr/local/bin/aws`.

Expected output (yours will differ):
```
You can now run: /usr/local/bin/aws --version
```

Check it worked: you should see the line `You can now run: /usr/local/bin/aws --version`.

### Step 10: Confirm the AWS CLI is installed

On the server, as ec2-user:

```
aws --version
```

This prints the installed AWS CLI version.

Expected output (yours will differ):
```
aws-cli/2.38.5 Python/3.14.8 Linux/5.14.0-759.el9.x86_64 exe/x86_64.centos.9
```

Check it worked: you should see a line starting with `aws-cli/`.

### Step 11: Verify your AWS credentials work

On the server, as ec2-user:

```
aws sts get-caller-identity
```

This asks AWS "who am I?" and returns the identity attached to the server's IAM role. `sts` is the AWS Security Token Service. `get-caller-identity` is the command that returns the current identity.

Expected output (yours will differ):
```
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-023ed56929012118f",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-023ed56929012118f"
}
```

Check it worked: you should see a JSON block containing `UserId`, `Account`, and `Arn` with no error.

---

## Part 3: Look up information you need before writing Terraform

Before writing your configuration, confirm that a PostgreSQL 15 engine version is available and find out which VPC and subnets you will use.

### Step 12: Find an available Aurora PostgreSQL 15 engine version

On the server, as ec2-user:

```
aws rds describe-db-engine-versions --engine aurora-postgresql --query "DBEngineVersions[?starts_with(EngineVersion,'15.')].EngineVersion" --output text --region us-east-1
```

This asks AWS to list all Aurora PostgreSQL engine versions that start with `15.`. The `--query` argument filters the results down to just version strings. `--output text` prints them one per line.

Expected output (yours will differ):
```
15.10
15.12
15.13
15.14
15.15
15.17
15.18
15.19
```

Check it worked: you should see a list of version numbers beginning with `15.`. Make a note of the first one - you will use `15.10` in your Terraform configuration.

### Step 13: Find your default VPC ID

On the server, as ec2-user:

```
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region us-east-1
```

This lists VPCs and filters for the one marked as the default VPC. `--query "Vpcs[0].VpcId"` extracts just the VPC ID from the first result.

Expected output (yours will differ):
```
vpc-09a1c840cf0697b9a
```

Check it worked: you should see a single VPC ID starting with `vpc-`. Note this value.

### Step 14: Confirm subnets are available in the VPC

On the server, as ec2-user:

```
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-09a1c840cf0697b9a" --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone}" --output table --region us-east-1
```

Replace `vpc-09a1c840cf0697b9a` with the VPC ID from the previous step. This lists all subnets in that VPC and shows which Availability Zone each one is in. Aurora requires subnets in at least two different AZs.

Expected output (yours will differ):
```
--------------------------------------------
|              DescribeSubnets             |
+-------------+----------------------------+
|     AZ      |            ID              |
+-------------+----------------------------+
|  us-east-1c |  subnet-07538e84ecf825ba7  |
|  us-east-1e |  subnet-057baec8868186f3b  |
|  us-east-1b |  subnet-04965629f04131232  |
|  us-east-1a |  subnet-07b4380865b5763b1  |
|  us-east-1f |  subnet-0eea330f969a586fb  |
|  us-east-1d |  subnet-00a5ef44c5f9d485a  |
+--------------------------------------------+
```

Check it worked: you should see subnets listed across multiple AZs (for example `us-east-1a`, `us-east-1b`, etc.). You need at least two different AZs.

---

## Part 4: Create the Terraform project directory and files

### Step 15: Create the project directory

On the server, as ec2-user:

```
mkdir -p /home/ec2-user/tf-lab
```

This creates the folder `/home/ec2-user/tf-lab` where all your Terraform files will live. `-p` means "create any missing parent directories without error".

Expected output (yours will differ):
```
(no output)
```

Check it worked: no error message appears.

---

### Step 16: Create variables.tf

Why this step: Storing the database password as a Terraform variable keeps it out of your main configuration file. Marking it `sensitive = true` tells Terraform to hide the value in plan and apply output so it is never accidentally printed to the screen.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/variables.tf
```

In vi, press `i` to enter insert mode, then type the following content exactly:

```hcl
variable "db_master_password" {
  description = "Master password for the Aurora cluster."
  type        = string
  sensitive   = true
}
```

When you are done typing, press `Esc`, then type `:wq` and press `Enter` to save and quit.

Line by line explanation:
- `variable "db_master_password"` - declares a variable named `db_master_password`
- `description` - a human-readable note explaining what this variable is for
- `type = string` - the value must be text (not a number or list)
- `sensitive = true` - Terraform will never print this value in output or logs

Expected output (yours will differ):
```
(vi opens and closes silently - no terminal output)
```

Check it worked: run `ls /home/ec2-user/tf-lab/` and confirm `variables.tf` appears in the list.

---

### Step 17: Create main.tf

Why this step: This is the core configuration file. It tells Terraform which cloud provider to use, discovers the VPC and subnets automatically, and defines the three main resources: the subnet group, the cluster, and two instances.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/main.tf
```

Press `i` to enter insert mode and type the following content:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "suta-cb-spike"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "aurora" {
  name_prefix  = "aurora-"
  subnet_ids   = data.aws_subnets.default.ids
  description  = "Subnet group for Aurora lab cluster"
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier_prefix = "aurora-"
  engine                    = "aurora-postgresql"
  engine_version            = "15.10"

  database_name   = "appdb"
  master_username = "dbadmin"
  master_password = var.db_master_password

  db_subnet_group_name = aws_db_subnet_group.aurora.name

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster_instance" "aurora" {
  count = 2

  identifier_prefix  = "aurora-"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  apply_immediately = true
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Section by section explanation:

- `terraform { required_providers ... }` - tells Terraform to download the official AWS provider plugin. `~> 5.0` means "any version 5.x but not 6.0 or higher".
- `provider "aws"` - configures the AWS provider to use the `us-east-1` region. `default_tags` automatically adds a `Project` tag to every resource created.
- `data "aws_vpc" "default"` - a data source (read-only lookup). It finds your existing default VPC so you do not have to hard-code its ID.
- `data "aws_subnets" "default"` - looks up all subnets inside that VPC. The `filter` block narrows the search to subnets belonging to the VPC found above.
- `resource "aws_db_subnet_group" "aurora"` - creates the subnet group Aurora requires. `name_prefix` lets AWS generate a unique name. `subnet_ids` uses all the subnets found by the data source.
- `resource "aws_rds_cluster" "aurora"` - creates the cluster control plane. Key lines:
  - `cluster_identifier_prefix` - AWS will generate a unique cluster name starting with `aurora-`
  - `engine_version = "15.10"` - the PostgreSQL version confirmed in Step 12
  - `master_password = var.db_master_password` - reads the value from your variable
  - `skip_final_snapshot = true` - safe for a lab; in production always set this to false
  - `lifecycle { ignore_changes = [engine_version] }` - prevents Terraform from trying to "fix" the version string after AWS normalises it
- `resource "aws_rds_cluster_instance" "aurora"` - creates the compute nodes. Key lines:
  - `count = 2` - Terraform creates two instances: index `[0]` becomes the writer, index `[1]` becomes the reader
  - `cluster_identifier = aws_rds_cluster.aurora.id` - links each instance to the cluster above

Expected output (yours will differ):
```
(vi opens and closes silently)
```

Check it worked: run `ls /home/ec2-user/tf-lab/` and confirm `main.tf` appears.

---

### Step 18: Create outputs.tf

Why this step: Outputs tell Terraform to print specific values after a successful apply. These values (like the cluster endpoint) are what you would use to connect an application to the database.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/outputs.tf
```

Press `i` and type the following:

```hcl
output "cluster_endpoint" {
  description = "Writer endpoint - connect your app here for read/write."
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint - Aurora load-balances reads across all readers."
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_id" {
  description = "Cluster identifier - used in terraform import for the cluster resource."
  value       = aws_rds_cluster.aurora.cluster_identifier
}

output "instance_ids" {
  description = "Instance identifiers - used in terraform import for each instance resource."
  value       = aws_rds_cluster_instance.aurora[*].identifier
}
```

Press `Esc`, then `:wq` and `Enter`.

Line by line explanation:
- `cluster_endpoint` - the hostname your application connects to for writes
- `reader_endpoint` - a separate hostname Aurora provides for read traffic; it load-balances across all reader instances
- `cluster_id` - the unique cluster name; you would need this if you ever ran `terraform import` to bring an existing cluster under Terraform management
- `instance_ids` - the list of instance names; `[*]` collects the identifier from both instances (index 0 and 1)

Expected output (yours will differ):
```
(vi opens and closes silently)
```

Check it worked: run `ls /home/ec2-user/tf-lab/` and confirm `outputs.tf` appears.

### Step 19: Confirm all three files are present

On the server, as ec2-user:

```
ls -la /home/ec2-user/tf-lab/
```

This lists the contents of your project directory with file sizes and timestamps.

Expected output (yours will differ):
```
total 12
drwxr-xr-x. 2 ec2-user ec2-user   59 Oct 25 19:30 .
drwx------. 6 ec2-user ec2-user  120 Oct 25 19:30 ..
-rw-r--r--. 1 ec2-user ec2-user 3583 Oct 25 19:30 main.tf
-rw-r--r--. 1 ec2-user ec2-user  680 Oct 25 19:30 outputs.tf
-rw-r--r--. 1 ec2-user ec2-user  265 Oct 25 19:30 variables.tf
```

Check it worked: you should see all three files - `main.tf`, `outputs.tf`, and `variables.tf`.

---

## Part 5: Run Terraform

### Step 20: Initialize the Terraform project

Why this step: Before Terraform can do anything it must download the AWS provider plugin declared in `main.tf`. This only needs to be done once per project.

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab init
```

This runs `terraform init` inside the `tf-lab` directory. `-chdir=` tells Terraform which directory to treat as the project root, so you do not have to `cd` into it first.

Expected output (yours will differ):
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
```

Check it worked: you should see the line `Terraform has been successfully initialized!`.

### Step 21: Preview what Terraform will create

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab plan
```

This asks Terraform to compare your configuration files with the current state of AWS and show you exactly what it would create, change, or destroy - without actually doing anything yet. Review the output carefully before proceeding.

Expected output (yours will differ):
```
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 0s [id=vpc-09a1c840cf0697b9a]
...
Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + cluster_endpoint = (known after apply)
  + cluster_id       = (known after apply)
  + instance_ids     = [...]
  + reader_endpoint  = (known after apply)
```

Check it worked: you should see `Plan: 4 to add, 0 to change, 0 to destroy.` The number 4 means: 1 subnet group + 1 cluster + 2 instances.

### Step 22: Apply the configuration and create the resources

Why this step: This is the step that actually creates real AWS resources. Aurora instances take several minutes to become available.

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab apply -auto-approve -var="db_master_password=YOUR_DB_PASSWORD"
```

Replace `YOUR_DB_PASSWORD` with a strong password of your choice (at least 8 characters, no special characters like `@`, `/`, or `"`). The `-auto-approve` flag skips the interactive confirmation prompt. `-var` passes the password directly so it is not stored in any file.

Note: choose your own strong password. Never use an example password from a guide.

Expected output (yours will differ):
```
data.aws_vpc.default: Reading...
...
aws_db_subnet_group.aurora: Creating...
aws_db_subnet_group.aurora: Creation complete after 1s
aws_rds_cluster.aurora: Creating...
aws_rds_cluster.aurora: Creation complete after ...
aws_rds_cluster_instance.aurora[0]: Creating...
aws_rds_cluster_instance.aurora[1]: Creating...
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

The instances will take 5-15 minutes to reach the `available` state. The command will wait and show progress.

Check it worked: you should see `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.`

---

## Part 6: Verify the cluster is running

### Step 23: Check the cluster status in AWS

On the server, as ec2-user:

```
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'aurora-')].{ID:DBClusterIdentifier,Status:Status}" --output table
```

This asks AWS directly (not Terraform) to list all RDS clusters whose name begins with `aurora-` and show their current status. `--query` filters and reshapes the JSON response. `--output table` formats it as a readable table.

Expected output (yours will differ):
```
----------------------------------------------------
|                DescribeDBClusters                |
+------------------------------------+-------------+
|                 ID                 |   Status    |
+------------------------------------+-------------+
|  aurora-20261025193120565400000002 |  available  |
+------------------------------------+-------------+
```

Check it worked: the `Status` column should show `available`.

### Step 24: Check which instance is the writer and which is the reader

On the server, as ec2-user:

```
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'aurora-')].{ID:DBClusterIdentifier,Status:Status,Members:DBClusterMembers}" --output json
```

This returns the same cluster information but also includes the `DBClusterMembers` list, which tells you which instance is the writer (`IsClusterWriter: true`) and which is the reader (`IsClusterWriter: false`).

Expected output (yours will differ):
```
[
    {
        "ID": "aurora-20261025193120565400000002",
        "Status": "available",
        "Members": [
            {
                "DBInstanceIdentifier": "aurora-20261025193152319000000003",
                "IsClusterWriter": false,
                ...
            },
            {
                "DBInstanceIdentifier": "aurora-20261025193152320300000004",
                "IsClusterWriter": true,
                ...
            }
        ]
    }
]
```

Check it worked: you should see two entries under `Members` - one with `IsClusterWriter: true` and one with `IsClusterWriter: false`.

### Step 25: Check what Terraform knows about your resources

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab state list
```

This lists every resource that Terraform is currently tracking in its state file. The state file is how Terraform remembers what it created so it can manage changes later.

Expected output (yours will differ):
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_subnet_group.aurora
aws_rds_cluster.aurora
aws_rds_cluster_instance.aurora[0]
aws_rds_cluster_instance.aurora[1]
```

Check it worked: you should see all six lines including both `aws_rds_cluster_instance.aurora[0]` and `aws_rds_cluster_instance.aurora[1]`.

### Step 26: Confirm cluster status one more time

On the server, as ec2-user:

```
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'aurora-')].Status" --output text
```

This is a quick single-value check that returns just the status word for your cluster.

Expected output (yours will differ):
```
available
```

Check it worked: the output should be exactly the word `available`.

### Step 27: View the Terraform outputs

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab output
```

This prints all the values declared in `outputs.tf`. These are the connection details for your Aurora cluster.

Expected output (yours will differ):
```
cluster_endpoint = "aurora-20261025193120565400000002.cluster-cyn0wsqma5in.us-east-1.rds.amazonaws.com"
cluster_id = "aurora-20261025193120565400000002"
instance_ids = [
  "aurora-20261025193152320300000004",
  "aurora-20261025193152319000000003",
]
reader_endpoint = "aurora-20261025193120565400000002.cluster-ro-cyn0wsqma5in.us-east-1.rds.amazonaws.com"
```

Check it worked: you should see four output values including a `cluster_endpoint` hostname ending in `.rds.amazonaws.com` and a separate `reader_endpoint`.

### Step 28: Verify both instances are available

On the server, as ec2-user:

```
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'aurora-')].{ID:DBInstanceIdentifier,Class:DBInstanceClass,Status:DBInstanceStatus}" --output table
```

This queries the individual instances (not the cluster) and shows their class and status.

Expected output (yours will differ):
```
---------------------------------------------------------------------------------------
|                                 DescribeDBInstances                                 |
+--------------+-------------------------------------+------------+
|     Class    |                 ID                  |  Status    |
+--------------+-------------------------------------+------------+
|  db.t3.medium|  aurora-20261025193152319000000003  |  available |
|  db.t3.medium|  aurora-20261025193152320300000004  |  available |
+--------------+-------------------------------------+------------+
```

Check it worked: both instances should show `available` in the `Status` column.

---

## Troubleshooting

**If you hit this - `unzip: command not found` when downloading the AWS CLI:**

The engineer hit this too. Amazon Linux 9 does not include `unzip` by default. Fix it by installing `unzip` first:

```
sudo yum install -y unzip
```

Then re-run the `curl` download and `unzip` steps.

---

**If you hit this - `terraform: command not found` after installation:**

This means the HashiCorp repository was not added before the install, or the install did not complete. Re-run Steps 1 and 2 to add the repository, then re-run Step 3 to install.

---

**If you hit this - `aws: command not found` after installing the AWS CLI:**

The installer places the binary at `/usr/local/bin/aws`. Your shell may not have refreshed its command path. Run:

```
hash -r
```

This clears the shell's cached command locations and forces it to look again. Then retry `aws --version`.

---

**If the `apply` fails with a password validation error:**

Aurora PostgreSQL rejects passwords containing certain special characters such as `@`, `/`, `"`, or spaces. Choose a password that uses only letters, numbers, and underscores, for example `MyLabPass2024` or `Secure_Pass_99`.

---

## Summary of what you built

You now have a running Aurora PostgreSQL 15.10 cluster in AWS consisting of:

- One subnet group spanning all six subnets in your default VPC
- One Aurora cluster (the control plane - endpoints, engine, credentials)
- Two Aurora instances attached to that cluster: one writer and one reader, both `db.t3.medium`

The key lesson: `aws_rds_cluster` and `aws_rds_cluster_instance` are always separate Terraform resources. The cluster defines what the database is; the instances define the compute that runs it. If you ever need to bring an existing Aurora cluster into Terraform management using `terraform import`, you must import the cluster resource once and then import each instance resource separately.
