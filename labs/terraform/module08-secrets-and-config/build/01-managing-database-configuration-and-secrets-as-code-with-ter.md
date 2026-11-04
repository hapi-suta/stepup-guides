# Managing Database Configuration and Secrets as Code with Terraform

**Objective:** Install Terraform and the AWS CLI on a CentOS server, then use Terraform to create a PostgreSQL RDS instance with a randomly generated password stored in AWS Secrets Manager.

**Estimated Time:** 60-90 minutes

**Prerequisites:**
- An EC2 instance running CentOS Stream 9 with an IAM role attached that has permissions to create RDS, Secrets Manager, and VPC resources
- SSH access to the instance as ec2-user
- Internet access from the instance

---

## Part 1 - Install Terraform

### Step 1: Check whether Terraform is already installed

On the server, as ec2-user:

```
which terraform
```

This asks the shell to locate the `terraform` command. If it prints a path, Terraform is already installed and you can skip to Step 4.

```
Expected output (yours will differ):
/usr/bin/which: no terraform in (/home/ec2-user/.local/bin:/home/ec2-user/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin)
```

Check it worked: if you see the "no terraform in" message, Terraform is not installed and you need to continue with the next steps.

---

### Step 2: Install the yum-utils package

On the server, as ec2-user:

```
sudo yum install -y yum-utils
```

`yum install` installs packages. `-y` answers "yes" automatically to any prompts. `yum-utils` provides the `yum-config-manager` tool you need in the next step.

```
Expected output (yours will differ):
Package yum-utils-4.3.0-27.el9.noarch is already installed.
...
Complete!
```

Check it worked: you should see the word "Complete!" or "already installed" near the bottom.

---

### Step 3: Add the HashiCorp package repository

On the server, as ec2-user:

Why this step: Terraform is not in the default CentOS package list. You need to tell `yum` where to find it by adding HashiCorp's own repository.

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

This adds a new source of packages (the HashiCorp repository) to your system so that `yum` knows where to download Terraform from.

```
Expected output (yours will differ):
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see "Adding repo from:" followed by the HashiCorp URL.

---

### Step 4: Install Terraform

On the server, as ec2-user:

```
sudo yum -y install terraform
```

This downloads and installs Terraform from the HashiCorp repository you just added. `-y` accepts all prompts automatically.

```
Expected output (yours will differ):
Hashicorp Stable - x86_64                        31 MB/s | 1.9 MB     00:00
...
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Complete!
```

Check it worked: you should see "terraform" listed under "Installing:" and the word "Complete!" at the end.

---

### Step 5: Confirm Terraform is installed and check its version

On the server, as ec2-user:

```
terraform version
```

This prints the installed version of Terraform.

```
Expected output (yours will differ):
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a version number beginning with "Terraform v".

---

## Part 2 - Install the AWS CLI

### Step 6: Check whether the AWS CLI is already installed

On the server, as ec2-user:

```
which aws
```

This checks whether the `aws` command is available. If it prints a path, skip to Step 10.

```
Expected output (yours will differ):
/usr/bin/which: no aws in (...)
```

Check it worked: if you see "no aws in", the CLI is not installed and you must continue with the next steps.

---

### Step 7: Confirm the EC2 instance has an IAM role attached

On the server, as ec2-user:

Why this step: The AWS CLI will use the IAM role attached to this EC2 instance instead of a username and password. This step confirms the role is present before you go any further.

```
curl -s http://169.254.169.254/latest/meta-data/iam/info
```

`curl` fetches a URL. The address `169.254.169.254` is a special AWS-internal address (only reachable from inside EC2) that provides information about the current instance. `-s` means silent - no progress bar.

```
Expected output (yours will differ):
{
  "Code" : "Success",
  "LastUpdated" : "2026-10-25T20:45:41Z",
  "InstanceProfileArn" : "arn:aws:iam::339276916173:instance-profile/suta-cb-spike-tf",
  "InstanceProfileId" : "AIPAU57T24XG3TVTHASJW"
}
```

Check it worked: you should see `"Code" : "Success"` and an `InstanceProfileArn` value. If you see an error instead, stop and ask your instructor to attach an IAM role to the instance.

---

### Step 8: Install the unzip utility

On the server, as ec2-user:

```
sudo yum install -y unzip
```

The AWS CLI installer comes as a `.zip` file, so you need `unzip` to open it.

```
Expected output (yours will differ):
Installing:
 unzip           x86_64           6.0-59.el9             baseos           182 k
...
Complete!
```

Check it worked: you should see "unzip" listed under "Installing:" and "Complete!" at the end.

---

### Step 9: Download the AWS CLI installer

On the server, as ec2-user:

```
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

This downloads the official AWS CLI v2 installer for 64-bit Linux. `-s` suppresses the progress display. `-o /tmp/awscliv2.zip` saves the file to the `/tmp` directory with that filename.

```
Expected output (yours will differ):
(no output - the file downloads silently)
```

Check it worked: no error messages means the download succeeded. You can verify by running `ls /tmp/awscliv2.zip` and confirming the file exists.

---

### Step 10: Move into the /tmp directory

On the server, as ec2-user:

```
cd /tmp
```

This changes your current working directory to `/tmp`, where the downloaded zip file is located.

```
Expected output (yours will differ):
(no output)
```

Check it worked: run `pwd` and you should see `/tmp`.

---

### Step 11: Unzip the AWS CLI installer

On the server, as ec2-user:

```
unzip -q awscliv2.zip
```

This extracts the contents of the zip file. `-q` means quiet - it suppresses the list of files being extracted.

```
Expected output (yours will differ):
(no output - extracts silently)
```

Check it worked: run `ls /tmp/aws` and you should see a directory called `aws` was created.

---

### Step 12: Run the AWS CLI installer

On the server, as ec2-user:

```
sudo ./aws/install
```

This runs the install script inside the extracted `aws` directory. `sudo` is needed because it copies files into `/usr/local/bin/`, which requires administrator permission.

```
Expected output (yours will differ):
You can now run: /usr/local/bin/aws --version
```

Check it worked: you should see the message "You can now run: /usr/local/bin/aws --version".

---

### Step 13: Confirm the AWS CLI works and the IAM role is usable

On the server, as ec2-user:

```
aws sts get-caller-identity --region us-east-1
```

`aws sts get-caller-identity` asks AWS "who am I?" - it returns the account number and the identity being used. `--region us-east-1` tells the CLI which AWS region to contact.

```
Expected output (yours will differ):
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-00047946d694329c8",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-00047946d694329c8"
}
```

Check it worked: you should see an "Account" number and an "Arn" that contains "assumed-role", confirming the IAM role is active.

---

## Part 3 - Create the Terraform Project Files

### Step 14: Create the project directory

On the server, as ec2-user:

```
mkdir -p /home/ec2-user/tf-lab
```

This creates a new directory called `tf-lab` in your home directory. `-p` means "create parent directories too if they do not exist" (and do not complain if the directory already exists).

```
Expected output (yours will differ):
(no output)
```

Check it worked: run `ls /home/ec2-user/` and confirm `tf-lab` appears in the list.

---

### Step 15: Create the versions.tf file

On the server, as ec2-user:

Why this step: Terraform needs to know which version of itself and which "providers" (plugins that talk to AWS) to use. This file pins those versions so your results are reproducible.

```
vi /home/ec2-user/tf-lab/versions.tf
```

Press `i` to enter insert mode, then type the following content exactly:

```
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```

What each important line does:
- `required_version = ">= 1.5"` - refuses to run if your Terraform is older than version 1.5
- `hashicorp/aws` with `version = "~> 5.0"` - allows any 5.x version of the AWS provider but not version 6 or above
- `hashicorp/random` - a provider that generates random values such as passwords

When finished typing, press `Esc`, then type `:wq` and press `Enter` to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: run `cat /home/ec2-user/tf-lab/versions.tf` and confirm the file content appears correctly.

---

### Step 16: Create the variables.tf file

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/variables.tf
```

Press `i` to enter insert mode, then type:

```
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_tag" {
  description = "Value for the Project tag applied to all resources"
  type        = string
  default     = "suta-cb-spike"
}
```

What each important section does:
- Each `variable` block defines an input you could override when running Terraform
- `default` values mean you do not have to type anything extra - Terraform uses these automatically
- `type = string` tells Terraform what kind of value to expect

Press `Esc`, then `:wq` and `Enter` to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: run `cat /home/ec2-user/tf-lab/variables.tf` and confirm the content is correct.

---

### Step 17: Create the main.tf file

On the server, as ec2-user:

Why this step: This is the main configuration file. It describes every AWS resource Terraform will create. It is the longest file - take your time with it.

```
vi /home/ec2-user/tf-lab/main.tf
```

Press `i` to enter insert mode, then type the following content exactly. Use only plain hyphens (-) in comments, not any other dash character:

```
# =============================================================================
# Provider
# =============================================================================
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "suta-cb-spike"
    }
  }
}

# =============================================================================
# Network: default VPC + subnets
# =============================================================================
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "appdb" {
  name_prefix = "appdb-"
  subnet_ids  = data.aws_subnets.default.ids
  description = "Subnet group for appdb RDS instance"
}

# =============================================================================
# Random master password (never written by a human)
# =============================================================================
resource "random_password" "db_master" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}?"
}

# =============================================================================
# AWS Secrets Manager: store { username, password } as JSON
# =============================================================================
resource "aws_secretsmanager_secret" "appdb" {
  name_prefix             = "appdb-"
  description             = "Master credentials for the appdb PostgreSQL instance"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "appdb" {
  secret_id = aws_secretsmanager_secret.appdb.id

  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db_master.result
  })
}

# =============================================================================
# Parameter group: DBA tuning lives in code
# =============================================================================
resource "aws_db_parameter_group" "appdb" {
  name_prefix = "appdb-"
  family      = "postgres16"
  description = "Custom parameter group for appdb - slow-query logging + connection audit"

  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

# =============================================================================
# RDS PostgreSQL instance
# =============================================================================
resource "aws_db_instance" "appdb" {
  identifier_prefix = "appdb-"

  engine         = "postgres"
  engine_version = "16.3"

  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "appdb"
  username = "dbadmin"
  password = random_password.db_master.result

  db_subnet_group_name = aws_db_subnet_group.appdb.name
  parameter_group_name = aws_db_parameter_group.appdb.name

  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true
}
```

What each important resource does:
- `provider "aws"` - tells Terraform to use the AWS plugin and apply the "suta-cb-spike" tag to every resource it creates
- `data "aws_vpc" "default"` - looks up your existing default VPC (read-only, creates nothing)
- `data "aws_subnets" "default"` - finds all subnets inside that VPC
- `aws_db_subnet_group` - groups those subnets so RDS knows which networks it can use
- `random_password` - generates a 20-character password with special characters; `override_special` limits which special characters are allowed to avoid ones that break database connection strings
- `aws_secretsmanager_secret` - creates a named slot in AWS Secrets Manager to hold credentials; `recovery_window_in_days = 0` means it can be deleted immediately (useful in a lab)
- `aws_secretsmanager_secret_version` - puts the actual username and password into that slot as a JSON string
- `aws_db_parameter_group` - a named collection of PostgreSQL settings; `family = "postgres16"` means it applies to PostgreSQL version 16; `log_min_duration_statement = 500` logs any query that takes more than 500 milliseconds; `log_connections = 1` logs every new connection
- `aws_db_instance` - the actual RDS database; `db.t3.micro` is a small instance suitable for a lab; `skip_final_snapshot = true` allows deletion without taking a backup first

Press `Esc`, then `:wq` and `Enter` to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: run `cat /home/ec2-user/tf-lab/main.tf` and confirm the file content looks correct with no strange characters.

---

### Step 18: Create the outputs.tf file

On the server, as ec2-user:

Why this step: Outputs are values Terraform prints at the end of a run. They let you see the results - like the database address - without digging through the AWS console.

```
vi /home/ec2-user/tf-lab/outputs.tf
```

Press `i` to enter insert mode, then type:

```
output "db_instance_identifier" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.appdb.identifier
}

output "db_instance_endpoint" {
  description = "The connection endpoint (host:port) - never contains the password"
  value       = aws_db_instance.appdb.endpoint
}

output "db_instance_status" {
  description = "Current status of the RDS instance"
  value       = aws_db_instance.appdb.status
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding { username, password }"
  value       = aws_secretsmanager_secret.appdb.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.appdb.name
}

output "parameter_group_name" {
  description = "Name of the DB parameter group applied to the instance"
  value       = aws_db_parameter_group.appdb.name
}
```

Notice that the password is intentionally not included in any output. The endpoint and secret name are safe to display; the password is not.

Press `Esc`, then `:wq` and `Enter` to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: run `cat /home/ec2-user/tf-lab/outputs.tf` and confirm the content is correct.

---

### Step 19: Confirm all four files are present

On the server, as ec2-user:

```
ls -la /home/ec2-user/tf-lab/
```

`ls -la` lists all files including hidden ones, with their sizes and permissions.

```
Expected output (yours will differ):
total 16
drwxr-xr-x. 2 ec2-user ec2-user   78 Oct 25 20:48 .
drwx------. 6 ec2-user ec2-user  120 Oct 25 20:47 ..
-rw-r--r--. 1 ec2-user ec2-user 3069 Oct 25 20:48 main.tf
-rw-r--r--. 1 ec2-user ec2-user 1173 Oct 25 20:48 outputs.tf
-rw-r--r--. 1 ec2-user ec2-user  273 Oct 25 20:48 variables.tf
-rw-r--r--. 1 ec2-user ec2-user  228 Oct 25 20:47 versions.tf
```

Check it worked: you should see all four files - `main.tf`, `outputs.tf`, `variables.tf`, and `versions.tf` - each with a non-zero size.

---

## Part 4 - Run Terraform

### Step 20: Move into the project directory

On the server, as ec2-user:

```
cd /home/ec2-user/tf-lab
```

All Terraform commands must be run from the directory containing your `.tf` files.

```
Expected output (yours will differ):
(no output)
```

Check it worked: run `pwd` and you should see `/home/ec2-user/tf-lab`.

---

### Step 21: Initialize Terraform

On the server, as ec2-user:

Why this step: Before Terraform can do anything, it needs to download the provider plugins (the code that actually talks to AWS). This only needs to be done once per project.

```
terraform init
```

This reads your `versions.tf` file, downloads the `hashicorp/aws` and `hashicorp/random` plugins, and sets up the project.

```
Expected output (yours will differ):
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/random versions matching "~> 3.6"...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/random v3.9.1...
- Installed hashicorp/random v3.9.1 (signed by HashiCorp)
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
```

Check it worked: you should see "Terraform has been successfully initialized!" near the bottom.

---

### Step 22: Preview what Terraform will create

On the server, as ec2-user:

Why this step: `terraform plan` is a dry run - it shows you exactly what will be created, changed, or destroyed without actually doing anything. Always review this before applying.

```
terraform plan
```

Terraform reads your configuration, checks what already exists in AWS, and prints a list of actions it will take. Resources marked with `+` will be created.

```
Expected output (yours will differ):
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 0s [id=vpc-09a1c840cf0697b9a]
data.aws_subnets.default: Reading...
data.aws_subnets.default: Read complete after 0s [id=us-east-1]

Terraform will perform the following actions:

  # aws_db_instance.appdb will be created
  + resource "aws_db_instance" "appdb" {
      + allocated_storage = 20
      ...
```

Check it worked: you should see several resources listed with `+` (create) symbols and no errors. The plan should show resources including `aws_db_instance`, `aws_db_parameter_group`, `aws_db_subnet_group`, `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version`, and `random_password`.

---

### Step 23: Apply the Terraform configuration

On the server, as ec2-user:

Why this step: This is the step that actually creates the resources in AWS. Creating an RDS instance takes several minutes - this is normal.

```
terraform apply -auto-approve
```

`terraform apply` creates all the resources described in your configuration. `-auto-approve` skips the interactive confirmation prompt (the plan was already reviewed in the previous step).

```
Expected output (yours will differ):
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

db_instance_endpoint   = "appdb-20261025205006540900000002.cyn0wsqma5in.us-east-1.rds.amazonaws.com:5432"
db_instance_identifier = "appdb-20261025205006540900000002"
db_instance_status     = "available"
parameter_group_name   = "appdb-20261025205005980100000001"
secret_arn             = "arn:aws:secretsmanager:us-east-1:339276916173:secret:appdb-20261025204902835300000002-FgBMHa"
secret_name            = "appdb-20261025204902835300000002"
```

Check it worked: you should see "Apply complete!" and `db_instance_status = "available"` in the outputs section.

**If you hit this - RDS parameter group description error:**

If you see an error like:
```
Error: creating RDS DB Parameter Group: api error InvalidParameterValue:
The parameter Description must not contain non-printable control characters.
```

This means your `main.tf` was saved with special invisible characters (such as a Unicode em dash) in the `description` line of `aws_db_parameter_group`. Open the file in vi and check line 58. The description must read exactly:

```
description = "Custom parameter group for appdb - slow-query logging + connection audit"
```

The character between "appdb" and "slow-query" must be a plain hyphen-minus (`-`), not a dash or any other special character. Edit the line in vi, save, and run `terraform apply -auto-approve` again. Terraform will pick up from where it left off.

---

## Part 5 - Verify the Results

### Step 24: List all resources in the Terraform state

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab state list
```

`terraform state list` shows every resource Terraform is currently managing. `-chdir=/home/ec2-user/tf-lab` tells Terraform to look in that directory (useful if you are not already inside it).

```
Expected output (yours will differ):
data.aws_subnets.default
data.aws_vpc.default
aws_db_instance.appdb
aws_db_parameter_group.appdb
aws_db_subnet_group.appdb
aws_secretsmanager_secret.appdb
aws_secretsmanager_secret_version.appdb
random_password.db_master
```

Check it worked: you should see all 6 resources plus the 2 data sources listed.

---

### Step 25: Confirm the RDS instance status directly from AWS

On the server, as ec2-user:

```
aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].DBInstanceStatus" --output text --region us-east-1
```

`aws rds describe-db-instances` queries AWS for RDS instance details. `--query` filters the results - here it finds any instance whose name starts with "appdb-" and returns only its status field. `--output text` prints the result as plain text rather than JSON.

```
Expected output (yours will differ):
available
```

Check it worked: you should see the single word "available".

---

### Step 26: Get the Terraform output for the secret name

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab output -raw secret_name
```

`terraform output` prints the value of a named output. `-raw` prints just the value with no surrounding quotes. This prints the name of the Secrets Manager secret so you can use it in the next step.

```
Expected output (yours will differ):
appdb-20261025204902835300000002
```

Check it worked: you should see a string beginning with "appdb-". Copy this value - you will use it in the next step.

---

### Step 27: Confirm the secret exists in AWS Secrets Manager

On the server, as ec2-user:

Replace `YOUR_SECRET_NAME` below with the value you copied from the previous step.

```
aws secretsmanager describe-secret --secret-id YOUR_SECRET_NAME --region us-east-1
```

`aws secretsmanager describe-secret` asks AWS for metadata about the secret. It shows the name, description, tags, and version information - but not the actual password value.

```
Expected output (yours will differ):
{
    "ARN": "arn:aws:secretsmanager:us-east-1:...",
    "Name": "appdb-20261025204902835300000002",
    "Description": "Master credentials for the appdb PostgreSQL instance",
    ...
    "Tags": [
        {
            "Key": "Project",
            "Value": "suta-cb-spike"
        }
    ],
    ...
}
```

Check it worked: you should see `"Description": "Master credentials for the appdb PostgreSQL instance"` and a "Project" tag with the value "suta-cb-spike".

---

### Step 28: Confirm the RDS instance details and parameter group

On the server, as ec2-user:

```
aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].[DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,DBParameterGroups[0].DBParameterGroupName,DBInstanceStatus]" --output table --region us-east-1
```

This queries AWS for details about the RDS instance and formats the result as a table. The `--query` argument selects the identifier, instance class, database engine, version, parameter group name, and status.

```
Expected output (yours will differ):
--------------------------------------------------------------------------------------------------------------------------
|                                                   DescribeDBInstances                                                  |
+-----------------------------------+--------------+-----------+-------+------------------------------------+------------+
|  appdb-20261025205006540900000002 |  db.t3.micro |  postgres |  16.3 |  appdb-20261025205005980100000001  |  available |
+-----------------------------------+--------------+-----------+-------+------------------------------------+------------+
```

Check it worked: you should see a single row showing your instance with engine "postgres", version "16.3", instance class "db.t3.micro", and status "available".

---

### Step 29: Confirm the custom database parameters are applied

On the server, as ec2-user:

First, get the parameter group name from Terraform:

```
terraform -chdir=/home/ec2-user/tf-lab output -raw parameter_group_name
```

Copy the value that is printed. Then run the following command, replacing `YOUR_PARAMETER_GROUP_NAME` with that value:

```
aws rds describe-db-parameters --db-parameter-group-name YOUR_PARAMETER_GROUP_NAME --region us-east-1 --query "Parameters[?ParameterName=='log_min_duration_statement' || ParameterName=='log_connections'].[ParameterName,ParameterValue,ApplyMethod]" --output table
```

`aws rds describe-db-parameters` retrieves the settings inside a parameter group. The `--query` filter asks for only the two parameters you set in `main.tf`.

```
Expected output (yours will differ):
----------------------------------------------------
|               DescribeDBParameters               |
+-----------------------------+------+-------------+
|  log_connections            |  1   |  immediate  |
|  log_min_duration_statement |  500 |  immediate  |
+-----------------------------+------+-------------+
```

Check it worked: you should see both `log_connections` with value `1` and `log_min_duration_statement` with value `500`, both with apply method `immediate`.

---

Congratulations - you have successfully installed Terraform and the AWS CLI, written a four-file Terraform configuration, and used it to create a PostgreSQL RDS instance with a randomly generated password stored safely in AWS Secrets Manager. The database is running, the custom parameter group is applied, and none of the password material was ever visible on your terminal or written by hand.
