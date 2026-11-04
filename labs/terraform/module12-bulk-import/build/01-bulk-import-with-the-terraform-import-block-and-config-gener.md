# Bulk Import with the Terraform import Block and Config Generation

**Objective:** Install Terraform and the AWS CLI on a CentOS server, manually create an RDS PostgreSQL database and its supporting resources, then bring all four resources under Terraform management using the declarative import feature introduced in Terraform 1.5.

**Estimated Time:** 45-60 minutes (most of the wait is the RDS instance starting up, about 10 minutes)

**Prerequisites:**
- An EC2 instance running CentOS Stream 9 with an IAM role that has permissions to create and describe RDS, EC2, and VPC resources
- SSH access to that instance as ec2-user
- Basic familiarity with the Linux command line

---

## Part 1 - Install Terraform

**Why this step:** Terraform is not installed by default on CentOS. You need to add HashiCorp's official package repository so the yum package manager knows where to find it.

### Step 1

On the server, as ec2-user:

```bash
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

This adds HashiCorp's RPM repository to your system. The `--add-repo` flag takes a URL pointing to a `.repo` file and saves it locally so future `yum install` commands can find HashiCorp packages.

```
Expected output (yours will differ):
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line `Adding repo from:` with the HashiCorp URL.

---

### Step 2

On the server, as ec2-user:

```bash
sudo yum install -y terraform
```

This downloads and installs Terraform from the HashiCorp repository. The `-y` flag automatically answers "yes" to any confirmation prompts.

```
Expected output (yours will differ):
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Complete!
```

Check it worked: you should see `terraform` listed under `Installing:` and `Complete!` at the end.

---

### Step 3

On the server, as ec2-user:

```bash
terraform version
```

Confirms Terraform is on the PATH and shows the installed version.

```
Expected output (yours will differ):
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a version line starting with `Terraform v`.

---

## Part 2 - Install the AWS CLI

**Why this step:** The AWS CLI is not present on this server either. You will use it to create RDS resources by hand before Terraform imports them.

### Step 4

On the server, as ec2-user:

```bash
sudo yum install -y unzip
```

The AWS CLI installer is a zip archive. This step installs the `unzip` tool needed to open it. The `-y` flag skips confirmation prompts.

```
Expected output (yours will differ):
Installing:
 unzip           x86_64           6.0-59.el9             baseos           182 k
...
Complete!
```

Check it worked: you should see `unzip` listed under `Installing:` and `Complete!` at the end.

---

### Step 5

On the server, as ec2-user:

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

Downloads the AWS CLI v2 installer zip to the `/tmp` directory. The `-o` flag names the output file.

```
Expected output (yours will differ):
  % Total    % Received % Xferd ...
100 70.9M  100 70.9M    0     0   412M      0 --:--:-- --:--:-- --:--:--  412M
```

Check it worked: the final line should show `100` in the first column, meaning the download completed fully.

---

### Step 6

On the server, as ec2-user:

```bash
unzip -q /tmp/awscliv2.zip -d /tmp
```

Extracts the installer archive into `/tmp`. The `-q` flag runs quietly (no file-by-file output), and `-d /tmp` sets the destination directory.

```
Expected output (yours will differ):
(no output - the -q flag suppresses it)
```

Check it worked: no error messages means the extraction succeeded.

---

### Step 7

On the server, as ec2-user:

```bash
sudo /tmp/aws/install
```

Runs the official AWS CLI installer script, which copies the CLI binary to `/usr/local/bin/aws`.

```
Expected output (yours will differ):
You can now run: /usr/local/bin/aws --version
```

Check it worked: you should see the line `You can now run: /usr/local/bin/aws --version`.

---

### Step 8

On the server, as ec2-user:

```bash
aws --version
```

Verifies the AWS CLI is installed and on the PATH.

```
Expected output (yours will differ):
aws-cli/2.x.x Python/3.x.x Linux/...
```

Check it worked: you should see a version string beginning with `aws-cli/2`.

---

### Step 9

On the server, as ec2-user:

```bash
aws sts get-caller-identity
```

Calls AWS Security Token Service to confirm this server's IAM role is working. No credentials need to be typed because the EC2 instance role provides them automatically.

```
Expected output (yours will differ):
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-03e4be5f1c36d9b6b",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-03e4be5f1c36d9b6b"
}
```

Check it worked: you should see a JSON block containing `UserId`, `Account`, and `Arn`.

---

### Step 10

On the server, as ec2-user:

```bash
aws configure set region us-east-1
```

Sets the default AWS region for all subsequent CLI commands. Without this, every command would need a `--region` flag.

```
Expected output (yours will differ):
(no output means success)
```

Check it worked: no error message means the region was saved successfully.

---

## Part 3 - Create the Working Directory

### Step 11

On the server, as ec2-user:

```bash
mkdir -p /home/ec2-user/tf-lab
```

Creates the directory where all Terraform files will live. The `-p` flag means "create parent directories too, and do not error if the directory already exists."

```
Expected output (yours will differ):
(no output means success)
```

Check it worked: no error message means the directory was created.

---

## Part 4 - Create the AWS Resources by Hand

These four resources exist outside Terraform. The goal of this lab is to import them into Terraform management without recreating them.

### Step 12

**Why this step:** You need to know the ID of the default VPC so you can place resources inside it.

On the server, as ec2-user:

```bash
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text
```

Lists VPCs filtered to only the default one. The `--query` argument uses JMESPath syntax to extract just the VPC ID from the JSON response. The `--output text` flag prints it as plain text instead of JSON. Write down the VPC ID - you will need it in the next few steps.

```
Expected output (yours will differ):
vpc-09a1c840cf0697b9a
```

Check it worked: you should see a single string beginning with `vpc-`.

---

### Step 13

**Why this step:** RDS requires subnets in at least two availability zones. You need to pick two from the default VPC.

On the server, as ec2-user:

```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=YOUR_VPC_ID" --query "Subnets[*].[SubnetId,AvailabilityZone]" --output text
```

Replace `YOUR_VPC_ID` with the VPC ID from the previous step. This lists all subnets in that VPC along with which availability zone each one sits in. Write down any two subnet IDs from different availability zones.

```
Expected output (yours will differ):
subnet-07538e84ecf825ba7    us-east-1c
subnet-057baec8868186f3b    us-east-1e
subnet-04965629f04131232    us-east-1b
subnet-07b4380865b5763b1    us-east-1a
...
```

Check it worked: you should see a list of subnet IDs each paired with an availability zone name.

---

### Step 14

**Why this step:** A DB subnet group tells RDS which subnets it is allowed to place the database instance in. It must contain subnets from at least two availability zones for high availability.

On the server, as ec2-user:

```bash
aws rds create-db-subnet-group --db-subnet-group-name legacy-app-subnets --db-subnet-group-description "Legacy app subnet group" --subnet-ids YOUR_SUBNET_1 YOUR_SUBNET_2 --tags Key=Project,Value=suta-cb-spike --query "DBSubnetGroup.DBSubnetGroupName" --output text
```

Replace `YOUR_SUBNET_1` and `YOUR_SUBNET_2` with two subnet IDs from different availability zones that you noted in the previous step. The `--tags` flag applies a `Project` tag that Terraform will later match. The `--query` flag extracts just the name from the response.

```
Expected output (yours will differ):
legacy-app-subnets
```

Check it worked: you should see `legacy-app-subnets` printed on its own line.

---

### Step 15

**Why this step:** A parameter group is a named collection of PostgreSQL configuration settings. Creating a custom one lets you tune settings like query logging without touching the default group shared by all instances.

On the server, as ec2-user:

```bash
aws rds create-db-parameter-group --db-parameter-group-name legacy-app-params --db-parameter-group-family postgres16 --description "Legacy app PostgreSQL 16 parameters" --tags Key=Project,Value=suta-cb-spike --query "DBParameterGroup.DBParameterGroupName" --output text
```

`--db-parameter-group-family postgres16` means this group applies to PostgreSQL version 16 databases. The `--query` flag extracts just the name from the response.

```
Expected output (yours will differ):
legacy-app-params
```

Check it worked: you should see `legacy-app-params` printed on its own line.

---

### Step 16

**Why this step:** This sets a custom parameter inside the group you just created. `log_min_duration_statement=500` tells PostgreSQL to log any query that takes longer than 500 milliseconds - useful for finding slow queries.

On the server, as ec2-user:

```bash
aws rds modify-db-parameter-group --db-parameter-group-name legacy-app-params --parameters "ParameterName=log_min_duration_statement,ParameterValue=500,ApplyMethod=immediate" --query "DBParameterGroupName" --output text
```

The `--parameters` value is a comma-separated string with three parts: the parameter name, its value, and `ApplyMethod=immediate` which means the change takes effect without a reboot. The `--query` flag extracts just the group name from the response.

```
Expected output (yours will differ):
legacy-app-params
```

Check it worked: you should see `legacy-app-params` printed on its own line.

---

### Step 17

**Why this step:** A security group acts as a virtual firewall. The RDS instance needs one assigned to it. You will create an empty one now - it can have rules added later.

On the server, as ec2-user:

```bash
aws ec2 create-security-group --group-name legacy-app-sg --description "Legacy app security group" --vpc-id YOUR_VPC_ID --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=suta-cb-spike}]" --query "GroupId" --output text
```

Replace `YOUR_VPC_ID` with your VPC ID. The `--query "GroupId"` flag extracts just the new security group ID from the response. Write down this ID - it starts with `sg-` and you will need it in the next step and later in the Terraform files.

```
Expected output (yours will differ):
sg-04262c0839bbecc8a
```

Check it worked: you should see a single string beginning with `sg-`.

---

### Step 18

**Why this step:** Before creating the RDS instance you need to confirm which PostgreSQL 16 minor versions are actually available in your region. The version you type must match exactly or the command will fail.

On the server, as ec2-user:

```bash
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[*].EngineVersion" --output text
```

This lists every available PostgreSQL version. The `--query` flag selects only the version strings from the JSON response.

```
Expected output (yours will differ):
...  16.3  16.4  16.9  16.10  ...
```

Check it worked: you should see a list of version numbers. Note any version beginning with `16.` - you will use one in the next step.

---

### Step 19

**Why this step:** This is the main resource - the actual PostgreSQL database. It references all three supporting resources you just created.

On the server, as ec2-user:

```bash
aws rds create-db-instance --db-instance-identifier legacy-app --engine postgres --engine-version 16.3 --db-instance-class db.t3.micro --allocated-storage 20 --master-username dbadmin --master-user-password YOUR_DB_PASSWORD --db-subnet-group-name legacy-app-subnets --db-parameter-group-name legacy-app-params --vpc-security-group-ids YOUR_SG_ID --no-publicly-accessible --no-deletion-protection --tags Key=Project,Value=suta-cb-spike --query "DBInstance.DBInstanceStatus" --output text
```

Replace `YOUR_DB_PASSWORD` with a strong password of your choice (for example at least 12 characters, mixed case, numbers, and symbols). Replace `YOUR_SG_ID` with the security group ID from Step 17. Replace `16.3` with any available 16.x version you noted in the previous step if 16.3 is not listed. Important flags:
- `--db-instance-identifier legacy-app` - the unique name for this database; this is also the import ID Terraform will use
- `--db-instance-class db.t3.micro` - the server size; t3.micro is the smallest and cheapest option
- `--allocated-storage 20` - 20 GB of disk
- `--no-publicly-accessible` - the database cannot be reached from the internet
- `--no-deletion-protection` - allows the instance to be deleted without extra steps (fine for a lab)

```
Expected output (yours will differ):
creating
```

Check it worked: you should see the word `creating`, which means AWS accepted the request and is building the instance.

---

**If you hit this:** If you see `Cannot find version 16.6 for postgres` (or any version number), it means that exact minor version is not available in your region. Run Step 18 again, pick a version from the output that starts with `16.`, and rerun Step 19 with that version instead.

---

## Part 5 - Write the Terraform Configuration Files

While the RDS instance is starting up (about 10 minutes), write the two Terraform files.

### Step 20

**Why this step:** Every Terraform project needs a file that declares which provider (in this case AWS) it uses and which versions are acceptable. This is the standard starting point.

On the server, as ec2-user, open the file in vi:

```bash
vi /home/ec2-user/tf-lab/versions.tf
```

Press `i` to enter insert mode, then type the following content exactly:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "suta-cb-spike"
    }
  }
}
```

What the important lines mean:
- `version = "~> 5.0"` means "use any 5.x version but not 6.0 or higher"
- `required_version = ">= 1.5.0"` means the import block feature (used later) requires at least Terraform 1.5
- `default_tags` automatically applies the `Project = "suta-cb-spike"` tag to every resource this workspace manages; this is how Terraform will match the tags you set when creating resources by hand

Press `Esc`, then type `:wq` and press Enter to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: no error message means the file was saved.

---

### Step 21

**Why this step:** Terraform 1.5 introduced `import {}` blocks. Instead of running a separate `terraform import` command for each resource, you declare all imports in a file. Terraform then shows you a preview before making any changes.

On the server, as ec2-user, open the file in vi:

```bash
vi /home/ec2-user/tf-lab/imports.tf
```

Press `i` to enter insert mode, then type the following content. Replace `YOUR_SG_ID` with your actual security group ID from Step 17.

```hcl
import {
  to = aws_db_instance.legacy
  id = "legacy-app"
}

import {
  to = aws_db_subnet_group.legacy
  id = "legacy-app-subnets"
}

import {
  to = aws_db_parameter_group.legacy
  id = "legacy-app-params"
}

import {
  to = aws_security_group.legacy
  id = "YOUR_SG_ID"
}
```

What each part means:
- `to` is the Terraform resource address - the type and name Terraform will use internally (for example `aws_db_instance.legacy` means resource type `aws_db_instance`, local name `legacy`)
- `id` is the identifier AWS uses for that resource. For the RDS instance and groups it is the name you gave them. For the security group it is the `sg-` ID because security groups do not have unique names across a VPC

Press `Esc`, then type `:wq` and press Enter to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: no error message means the file was saved.

---

## Part 6 - Initialize Terraform

### Step 22

On the server, as ec2-user:

```bash
cd /home/ec2-user/tf-lab
```

Changes into the lab directory. All Terraform commands must be run from the directory that contains the `.tf` files.

```
Expected output (yours will differ):
(no output means success)
```

Check it worked: no error message means the directory change succeeded.

---

### Step 23

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```bash
terraform init
```

Downloads the AWS provider plugin declared in `versions.tf` and sets up the local Terraform working directory. This must be run before any other Terraform command.

```
Expected output (yours will differ):
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
```

Check it worked: you should see `Terraform has been successfully initialized!` near the end.

---

## Part 7 - Wait for the RDS Instance

### Step 24

**Why this step:** Terraform cannot import the RDS instance until it is fully available. This command pauses and waits automatically instead of you checking manually.

On the server, as ec2-user:

```bash
aws rds wait db-instance-available --db-instance-identifier legacy-app
```

This command blocks (does nothing, just waits) until the RDS instance named `legacy-app` reaches the `available` state. It can take up to 10 minutes. When it returns to the prompt, the instance is ready.

```
Expected output (yours will differ):
(no output - the command just returns to the prompt when done)
```

Check it worked: the command returning to the shell prompt without an error means the instance is now available.

---

### Step 25

On the server, as ec2-user:

```bash
aws rds describe-db-instances --db-instance-identifier legacy-app --query "DBInstances[0].DBInstanceStatus" --output text
```

Double-checks the RDS instance status. The `--query` argument extracts just the status field from the JSON response.

```
Expected output (yours will differ):
available
```

Check it worked: you should see the single word `available`.

---

## Part 8 - Generate and Review Terraform Resource Blocks

### Step 26

**Why this step:** The import blocks in `imports.tf` tell Terraform what to import, but Terraform also needs a matching `resource` block for each one - the HCL that describes the resource's configuration. The `-generate-config-out` flag makes Terraform write those blocks automatically by reading the real resource from AWS. This saves you from writing hundreds of lines by hand.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```bash
terraform plan -generate-config-out=generated.tf
```

This reads the live AWS resources listed in `imports.tf` and writes a starter `resource` block for each one into `generated.tf`. It also shows you a preview of what will be imported. The command may exit with an error about validation - that is expected and handled in the next steps.

```
Expected output (yours will differ):
aws_db_subnet_group.legacy: Preparing import... [id=legacy-app-subnets]
aws_security_group.legacy: Preparing import... [id=sg-04262c0839bbecc8a]
aws_db_parameter_group.legacy: Preparing import... [id=legacy-app-params]
aws_db_instance.legacy: Preparing import... [id=legacy-app]
...
Terraform planned the following actions, but then encountered a problem:
...
```

Check it worked: even if the command exits with an error, the important thing is that `generated.tf` was written. You will fix any issues in the next step.

---

### Step 27

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/generated.tf
```

Displays the file Terraform generated so you can read it and understand what was created before editing it.

```
Expected output (yours will differ):
# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.
...
resource "aws_db_instance" "legacy" {
  allocated_storage = 20
  ...
}
...
```

Check it worked: you should see `resource` blocks for all four resources.

---

**If you hit this:** The `terraform plan -generate-config-out` step may fail with a validation error such as `domain_dns_ips` cannot be set when `domain` is null, or a `description` field conflict inside an `egress` block. This is a known issue where the generator writes a field that the validator then rejects. The fix is to open `generated.tf` in vi and remove the offending line. The next step does exactly that.

---

### Step 28

**Why this step:** The auto-generated file may contain one or two fields that cause a validation error when `domain` is set to null. You need to clean up those fields so `terraform plan` passes cleanly.

On the server, as ec2-user, open the file in vi:

```bash
vi /home/ec2-user/tf-lab/generated.tf
```

Look through the file for these two potential problems and remove those specific lines if you see them:
- A line containing `domain_dns_ips` inside the `aws_db_instance` block (remove the whole line)
- Inside the `aws_security_group` block's `egress` entry, a `description` field that conflicts with the block style (remove the `description = ""` line if present)

All other lines should be kept exactly as generated. Press `Esc`, then type `:wq` and press Enter to save.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: no error message means the file was saved.

---

## Part 9 - Import the Resources into Terraform State

### Step 29

**Why this step:** Before applying, always run `terraform plan` to see exactly what Terraform will do. You want to confirm it shows "4 to import, 0 to add, 0 to change, 0 to destroy" - meaning it will adopt the existing resources without modifying or replacing anything.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```bash
terraform plan
```

Terraform reads your `.tf` files, contacts AWS to compare the real resource state, and prints a preview of every action it would take. No changes are made yet.

```
Expected output (yours will differ):
aws_security_group.legacy: Preparing import... [id=sg-04262c0839bbecc8a]
...
Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.
```

Check it worked: the final summary line should read `4 to import, 0 to add, 0 to change, 0 to destroy`.

---

### Step 30

**Why this step:** Once the plan looks correct, `apply` actually writes the resources into Terraform state. After this step Terraform owns these resources and any future `terraform plan` will detect drift if someone changes them outside Terraform.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```bash
terraform apply -auto-approve
```

Executes the import plan. The `-auto-approve` flag skips the interactive yes/no confirmation prompt. After the import, Terraform immediately runs a second comparison and should find no differences between your config and the real resources.

```
Expected output (yours will differ):
aws_security_group.legacy: Preparing import... [id=sg-04262c0839bbecc8a]
...
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

Check it worked: you should see `Apply complete!` and the line `No changes. Your infrastructure matches the configuration.`

---

## Part 10 - Verify Everything

### Step 31

On the server, as ec2-user:

```bash
terraform -chdir=/home/ec2-user/tf-lab state list
```

Lists every resource currently tracked in Terraform state. The `-chdir=` flag tells Terraform which directory contains the state file, so you can run this from anywhere. A "state file" is Terraform's record of which real AWS resources it manages.

```
Expected output (yours will differ):
aws_db_instance.legacy
aws_db_parameter_group.legacy
aws_db_subnet_group.legacy
aws_security_group.legacy
```

Check it worked: you should see all four resource addresses listed, one per line.

---

### Step 32

On the server, as ec2-user:

```bash
aws rds describe-db-instances --db-instance-identifier legacy-app --query "DBInstances[0].DBInstanceStatus" --output text
```

Confirms the real RDS instance in AWS is still running and was not disrupted by the import process.

```
Expected output (yours will differ):
available
```

Check it worked: you should see the single word `available`.

---

### Step 33

On the server, as ec2-user:

```bash
ls -lh /home/ec2-user/tf-lab/
```

Lists the files in your Terraform working directory so you can confirm the expected files are all present.

```
Expected output (yours will differ):
total 28K
-rw-r--r--. 1 ec2-user ec2-user 4.5K Oct 26 15:03 generated.tf
-rw-r--r--. 1 ec2-user ec2-user 1.6K Oct 26 14:53 imports.tf
-rw-r--r--. 1 ec2-user ec2-user 8.2K Oct 26 15:04 terraform.tfstate
-rw-r--r--. 1 ec2-user ec2-user  422 Oct 26 14:53 versions.tf
```

Check it worked: you should see `generated.tf`, `imports.tf`, `terraform.tfstate`, and `versions.tf` all listed.

---

You have successfully installed Terraform and the AWS CLI, created four AWS resources by hand (an RDS PostgreSQL instance, a DB subnet group, a DB parameter group, and a security group), and imported all four into Terraform state using declarative `import {}` blocks. The resources are now managed by Terraform - any future changes should be made through your `.tf` files rather than the AWS Console or CLI directly.
