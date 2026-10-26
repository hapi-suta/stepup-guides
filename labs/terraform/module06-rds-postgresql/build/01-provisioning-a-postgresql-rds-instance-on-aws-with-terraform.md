# Provisioning a PostgreSQL RDS Instance on AWS with Terraform

**Objective:** Install Terraform, write three configuration files, and use them to create a PostgreSQL RDS database instance on AWS.

**Estimated Time:** 30-40 minutes (plus up to 10 minutes for AWS to create the database)

**Prerequisites:**
- An EC2 instance running CentOS Stream 9 (or compatible RHEL-based Linux)
- The EC2 instance must have an IAM role attached that allows RDS and VPC read/describe actions (no access keys needed - the instance role handles authentication automatically)
- SSH access to the instance as `ec2-user`
- Basic familiarity with the Linux command line

---

## Part 1: Install Terraform

Terraform is not installed by default. You need to add HashiCorp's software repository so your package manager knows where to find it.

### Step 1: Add the HashiCorp repository

On the server, as ec2-user:

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

This tells `yum` (the package manager) to look at HashiCorp's official repository for software packages. `--add-repo` saves the repository address to your system.

Expected output (yours will differ):
```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line `Adding repo from:` followed by the HashiCorp URL.

### Step 2: Install Terraform

On the server, as ec2-user:

```
sudo yum install -y terraform
```

This downloads and installs Terraform from the HashiCorp repository. The `-y` flag answers "yes" automatically to any confirmation prompts.

Expected output (yours will differ):
```
Hashicorp Stable - x86_64                        27 MB/s | 1.9 MB     00:00
Dependencies resolved.
================================================================================
 Package               Arch        Version                 Repository      Size
================================================================================
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Complete!
```

Check it worked: you should see `Complete!` at the end of the output.

### Step 3: Confirm Terraform is installed and working

On the server, as ec2-user:

```
terraform version
```

This prints the version of Terraform that was just installed.

Expected output (yours will differ):
```
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a line starting with `Terraform v` followed by a version number.

---

## Part 2: Install the AWS CLI and Verify Credentials

The AWS CLI is a command-line tool for talking to AWS. You also need to confirm that your EC2 instance has the permissions it needs (via its IAM role) before running Terraform.

### Step 4: Install the AWS CLI

On the server, as ec2-user:

```
sudo yum install -y awscli2
```

This installs version 2 of the AWS CLI from the CentOS AppStream repository.

Expected output (yours will differ):
```
Installing:
 awscli2                      noarch     2.33.0-1.el9       appstream      15 M
...
Complete!
```

Check it worked: you should see `Complete!` at the end of the output.

### Step 5: Verify your AWS identity

Why this step: This confirms that the EC2 instance role is active and that AWS will accept commands from this server. Terraform will use the same role automatically - no passwords or access keys are needed.

On the server, as ec2-user:

```
aws sts get-caller-identity
```

`sts` stands for Security Token Service. `get-caller-identity` asks AWS "who am I logged in as right now?" and returns the answer.

Expected output (yours will differ):
```
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-0ccea2e72e7dc1b7d",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-0ccea2e72e7dc1b7d"
}
```

Check it worked: you should see a JSON block containing `"Account":` with a numeric AWS account ID. If you see an error about credentials, the IAM role may not be attached to your instance.

---

## Part 3: Create the Project Directory

### Step 6: Create a working directory for your Terraform files

On the server, as ec2-user:

```
mkdir -p /home/ec2-user/tf-lab
```

This creates the directory `/home/ec2-user/tf-lab`. The `-p` flag means "create any missing parent directories and do not error if the directory already exists."

Expected output (yours will differ):
```

```

Check it worked: no output and no error message means the directory was created successfully.

---

## Part 4: Write the Terraform Configuration Files

Terraform reads `.tf` files to know what infrastructure to build. You will create three files:

- `variables.tf` - declares any input values your configuration needs (like a password)
- `outputs.tf` - declares what information Terraform should print after it finishes
- `main.tf` - the main configuration describing what AWS resources to create

### Step 7: Move into the project directory

On the server, as ec2-user:

```
cd /home/ec2-user/tf-lab
```

This changes your current location to the project directory. All remaining steps assume you are in this directory.

Expected output (yours will differ):
```

```

Check it worked: no error message. You can type `pwd` to confirm you are in `/home/ec2-user/tf-lab`.

### Step 8: Create the variables file

Why this step: Terraform needs a way to accept the database password as an input rather than having it hard-coded in the main configuration. This file declares that a variable called `db_password` exists.

On the server, as ec2-user:

```
vi variables.tf
```

Press `i` to enter insert mode, then type or paste the following content exactly:

```
variable "db_password" {
  description = "Master password for the RDS PostgreSQL instance. Choose a strong password (min 8 chars, letters+numbers)."
  type        = string
  sensitive   = true
}
```

What each line means:
- `variable "db_password"` - declares a variable named `db_password` that you will supply when running Terraform
- `description` - a human-readable note explaining what this variable is for
- `type = string` - tells Terraform this value will be plain text
- `sensitive = true` - tells Terraform to hide this value in all output and logs so the password is never printed on screen

When done, press `Escape`, then type `:wq` and press `Enter` to save and close.

Expected output (yours will differ):
```

```

Check it worked: no error from vi. You can confirm by running `cat variables.tf` and seeing the content you typed.

### Step 9: Create the outputs file

Why this step: After Terraform creates your database, it would be useful to know the connection address and other details without having to log into the AWS console. This file tells Terraform what to print when it finishes.

On the server, as ec2-user:

```
vi outputs.tf
```

Press `i` to enter insert mode, then type or paste the following:

```
output "db_instance_endpoint" {
  description = "The connection endpoint of the RDS instance."
  value       = aws_db_instance.appdb.endpoint
}

output "db_instance_id" {
  description = "The RDS instance identifier."
  value       = aws_db_instance.appdb.id
}

output "db_instance_status" {
  description = "The status of the RDS instance."
  value       = aws_db_instance.appdb.status
}

output "db_subnet_group_name" {
  description = "The DB subnet group name."
  value       = aws_db_subnet_group.appdb.name
}

output "db_parameter_group_name" {
  description = "The DB parameter group name."
  value       = aws_db_parameter_group.appdb.name
}
```

What each block means:
- Each `output` block has a name and a `value`. The value uses dot notation to reference a resource: `aws_db_instance.appdb.endpoint` means "the endpoint attribute of the resource named appdb of type aws_db_instance."
- `db_instance_endpoint` - the hostname and port you would use to connect to the database
- `db_instance_id` - the unique identifier AWS gives the instance
- `db_instance_status` - whether the instance is available, creating, etc.
- `db_subnet_group_name` and `db_parameter_group_name` - the names of the supporting resources

Press `Escape`, then type `:wq` and press `Enter` to save and close.

Expected output (yours will differ):
```

```

Check it worked: no error from vi. Confirm with `cat outputs.tf`.

### Step 10: Create the main configuration file

Why this step: This is the heart of your Terraform project. It describes every AWS resource that will be created: a subnet group, a parameter group, and the RDS database instance itself.

On the server, as ec2-user:

```
vi main.tf
```

Press `i` to enter insert mode, then type or paste the following content in full:

```
# -------------------------------------------------------
# Provider
# -------------------------------------------------------
terraform {
  required_version = ">= 1.3"
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

# -------------------------------------------------------
# Data sources - default VPC and its subnets
# -------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -------------------------------------------------------
# DB Subnet Group
# -------------------------------------------------------
resource "aws_db_subnet_group" "appdb" {
  name_prefix = "appdb-"
  subnet_ids  = data.aws_subnets.default.ids
  description = "Subnet group for appdb RDS instance"

  tags = {
    Name = "appdb-subnet-group"
  }
}

# -------------------------------------------------------
# DB Parameter Group
# -------------------------------------------------------
resource "aws_db_parameter_group" "appdb" {
  name_prefix = "appdb-"
  family      = "postgres16"
  description = "Custom parameter group for PostgreSQL 16"

  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }

  tags = {
    Name = "appdb-parameter-group"
  }
}

# -------------------------------------------------------
# RDS PostgreSQL Instance
# -------------------------------------------------------
resource "aws_db_instance" "appdb" {
  identifier_prefix = "appdb-"

  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "appdb"
  username = "dbadmin"
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.appdb.name
  parameter_group_name = aws_db_parameter_group.appdb.name

  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "appdb"
  }
}
```

Key things to understand in this file:

- `terraform { required_providers { ... } }` - tells Terraform to download the official AWS plugin (called a "provider") version 5.x
- `provider "aws" { region = "us-east-1" }` - sets the AWS region for all resources; `default_tags` automatically adds a tag to every resource so you can find them easily
- `data "aws_vpc" "default"` - this is a data source, meaning Terraform reads existing information from AWS rather than creating something. It looks up your account's default VPC
- `data "aws_subnets" "default"` - reads the list of subnets that belong to the default VPC
- `resource "aws_db_subnet_group" "appdb"` - RDS requires a subnet group (a named list of subnets) to know which networks the database can use; `name_prefix` lets AWS generate a unique name starting with `appdb-`
- `resource "aws_db_parameter_group" "appdb"` - a parameter group stores database engine settings; `family = "postgres16"` must match the engine version; `log_min_duration_statement = 500` logs any query that takes longer than 500 milliseconds, which helps with troubleshooting
- `resource "aws_db_instance" "appdb"` - the actual database; important settings:
  - `engine = "postgres"` and `engine_version = "16.3"` - use PostgreSQL 16.3
  - `instance_class = "db.t3.micro"` - the smallest (cheapest) instance size
  - `allocated_storage = 20` - 20 GB of disk space
  - `password = var.db_password` - reads the password from the variable you declared in variables.tf, so it is never written in this file
  - `publicly_accessible = false` - the database cannot be reached from the internet
  - `skip_final_snapshot = true` - do not create a backup snapshot when the database is deleted (suitable for a lab)
  - `deletion_protection = false` - allows the database to be deleted without extra steps (suitable for a lab)

Press `Escape`, then type `:wq` and press `Enter` to save and close.

Expected output (yours will differ):
```

```

Check it worked: no error from vi. Confirm with `cat main.tf` and check that the file ends with the closing `}` of the `aws_db_instance` resource block.

---

## Part 5: Initialize Terraform

### Step 11: Initialize the project

Why this step: Terraform must download the AWS provider plugin before it can do anything. `terraform init` reads your `.tf` files, figures out which plugins are needed, and downloads them into a hidden `.terraform` folder.

On the server, as ec2-user (still in `/home/ec2-user/tf-lab`):

```
terraform init
```

This reads `main.tf`, sees that you need the `hashicorp/aws` provider at version `~> 5.0`, downloads it, and creates a lock file (`.terraform.lock.hcl`) that records the exact version chosen.

Expected output (yours will differ):
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

Check it worked: you should see `Terraform has been successfully initialized!` near the end of the output.

---

## Part 6: Plan and Apply

### Step 12: Preview what Terraform will create

Why this step: Before making any changes to AWS, it is good practice to run `terraform plan`. This shows exactly what resources will be created, changed, or destroyed - without actually doing anything. Think of it as a dry run.

On the server, as ec2-user (in `/home/ec2-user/tf-lab`):

```
terraform plan -var="db_password=YOUR_DB_PASSWORD"
```

Replace `YOUR_DB_PASSWORD` with a strong password of your own choosing. The password must contain only letters and numbers - do not use special characters like `@`, `/`, `"`, or spaces (AWS RDS rejects them - see the troubleshooting note below). A good example format is `MyLabPass2024` (letters and digits only).

`-var="db_password=..."` passes the value for the `db_password` variable you declared in `variables.tf`.

Expected output (yours will differ):
```
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 0s [id=vpc-09a1c840cf0697b9a]
data.aws_subnets.default: Reading...
data.aws_subnets.default: Read complete after 1s [id=us-east-1]

Terraform used the selected providers to generate the following execution plan.
...
Plan: 3 to add, 0 to change, 0 to destroy.
```

Check it worked: you should see `Plan: 3 to add, 0 to change, 0 to destroy.` at the end. The number 3 corresponds to the subnet group, parameter group, and RDS instance.

### Step 13: Apply the configuration and create the resources

Why this step: `terraform apply` actually creates the AWS resources. This will take several minutes because RDS instances take time to provision.

On the server, as ec2-user (in `/home/ec2-user/tf-lab`):

```
terraform apply -auto-approve -var="db_password=YOUR_DB_PASSWORD"
```

Use the same password you used in the plan step. `-auto-approve` skips the interactive confirmation prompt (Terraform normally asks you to type `yes`). You will see Terraform creating each resource and progress messages while it waits for the RDS instance to become ready. This step can take 5-10 minutes - that is normal.

Expected output (yours will differ):
```
aws_db_parameter_group.appdb: Creating...
aws_db_subnet_group.appdb: Creating...
...
aws_db_instance.appdb: Still creating... [03m40s elapsed]
aws_db_instance.appdb: Still creating... [04m00s elapsed]
...
aws_db_instance.appdb: Creation complete after 6m46s [id=db-OPOJWGCC722UVYECEKZ77PPZ4M]

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

Check it worked: you should see `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.` at the end.

**If you hit this - invalid password error:**

If you see an error like:
```
Error: creating RDS DB Instance: api error InvalidParameterValue: The parameter
MasterUserPassword is not a valid password. Only printable ASCII characters
besides '/', '@', '"', ' ' may be used.
```

Your password contains a character that RDS does not allow. Change your password to use only letters and numbers (for example `MyLabPass2024`) and run the `terraform apply` command again with the corrected password. Terraform will pick up where it left off and only create the resources that are still missing.

---

## Part 7: Verify the Results

### Step 14: List all resources in Terraform state

Why this step: Terraform keeps a record (called "state") of every resource it has created. Listing the state confirms that all three resources were created and are being tracked.

On the server, as ec2-user (in `/home/ec2-user/tf-lab`):

```
terraform state list
```

This prints every resource that Terraform is currently managing.

Expected output (yours will differ):
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_instance.appdb
aws_db_parameter_group.appdb
aws_db_subnet_group.appdb
```

Check it worked: you should see `aws_db_instance.appdb` in the list alongside the subnet group and parameter group.

### Step 15: Confirm there is nothing left to change

Why this step: Running `plan` again after a successful apply should show zero changes. If it shows changes, something is different between your configuration and what was actually created, which would need investigation.

On the server, as ec2-user (in `/home/ec2-user/tf-lab`):

```
terraform plan -var="db_password=YOUR_DB_PASSWORD"
```

Use the same password as before.

Expected output (yours will differ):
```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Check it worked: you should see `No changes. Your infrastructure matches the configuration.`

### Step 16: Confirm the database is available in AWS

On the server, as ec2-user:

```
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,\`appdb-\`)].[DBInstanceIdentifier,DBInstanceStatus,Engine,EngineVersion,DBInstanceClass]" --output table
```

This command asks AWS directly (not Terraform) for information about your RDS instance. Here is what each part means:
- `describe-db-instances` - retrieves details about RDS instances in your account
- `--region us-east-1` - look in the us-east-1 region where you created the instance
- `--query "..."` - filter and select only the columns you care about, for instances whose name starts with `appdb-`
- `--output table` - display the results as a formatted table instead of raw JSON

Expected output (yours will differ):
```
--------------------------------------------------------------------------------------
|                                 DescribeDBInstances                                |
+-----------------------------------+------------+-----------+-------+---------------+
|  appdb-20261025053340123500000001 |  available |  postgres |  16.3 |  db.t3.micro  |
+-----------------------------------+------------+-----------+-------+---------------+
```

Check it worked: you should see a row showing your instance with the status `available`. If the status is still `creating`, wait a few minutes and run the command again.

---

## Summary

You have successfully:

1. Installed Terraform from the HashiCorp repository
2. Installed the AWS CLI and confirmed that the EC2 instance role provides AWS credentials automatically
3. Written three Terraform configuration files: `variables.tf`, `outputs.tf`, and `main.tf`
4. Initialized Terraform to download the AWS provider plugin
5. Used `terraform plan` to preview the changes before applying them
6. Used `terraform apply` to create three AWS resources: a DB subnet group, a DB parameter group, and a PostgreSQL 16.3 RDS instance
7. Verified the database is `available` both through Terraform state and directly through the AWS CLI
