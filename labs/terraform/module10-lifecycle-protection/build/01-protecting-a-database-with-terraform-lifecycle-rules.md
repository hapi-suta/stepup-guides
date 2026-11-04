# Protecting a Database with Terraform Lifecycle Rules

**Objective:** Use Terraform to create an AWS RDS PostgreSQL database and explore three lifecycle rules that protect production databases from accidental changes and deletion.

**Estimated Time:** 60-90 minutes

**Prerequisites:**
- An EC2 instance running CentOS Stream 9 (or similar RHEL-compatible Linux)
- An IAM role attached to the instance that allows RDS and EC2 actions (no access keys needed)
- Basic familiarity with the Linux terminal

---

## Part 1: Install Terraform

Terraform is not installed on the server by default. You will add HashiCorp's official package repository and then install Terraform from it.

### Step 1: Add the HashiCorp package repository

On the server, as ec2-user:

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

This tells the `yum` package manager where to find HashiCorp software. The `--add-repo` flag saves the repository address so future installs can use it.

Expected output (yours will differ):
```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line `Adding repo from:` with the HashiCorp URL.

---

### Step 2: Install Terraform

On the server, as ec2-user:

```
sudo yum -y install terraform
```

`-y` automatically answers "yes" to all prompts so the install runs without waiting for your input.

Expected output (yours will differ):
```
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Installed:
  terraform-1.17.0-1.x86_64
Complete!
```

Check it worked: you should see `Complete!` and `terraform` listed under `Installed`.

---

### Step 3: Confirm Terraform is working

On the server, as ec2-user:

```
terraform version
```

This prints the installed version of Terraform.

Expected output (yours will differ):
```
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a version number starting with `Terraform v`.

---

## Part 2: Install the AWS CLI

The AWS CLI is a command-line tool for talking to AWS services. You need it to verify your resources after Terraform creates them.

### Step 4: Install unzip

On the server, as ec2-user:

```
sudo yum install -y unzip
```

The AWS CLI installer comes as a `.zip` file. This step installs the tool needed to open it.

Expected output (yours will differ):
```
Installing:
 unzip           x86_64           6.0-59.el9             baseos           182 k
...
Installed:
  unzip-6.0-59.el9.x86_64
Complete!
```

Check it worked: you should see `Complete!` and `unzip` listed under `Installed`.

---

### Step 5: Download the AWS CLI installer

On the server, as ec2-user:

```
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

`curl` downloads a file from the internet. `-s` means silent (no progress bar). `-o` sets the name of the file to save to.

Expected output (yours will differ):
```
(no output - the file is saved silently)
```

Check it worked: the command returns with no error message. You can run `ls /tmp/awscliv2.zip` to confirm the file exists.

---

### Step 6: Unzip the installer

On the server, as ec2-user:

```
cd /tmp && unzip -q awscliv2.zip
```

`-q` means quiet, so it does not print every file name as it extracts. This unpacks the installer into a folder called `aws` inside `/tmp`.

Expected output (yours will differ):
```
(no output)
```

Check it worked: run `ls /tmp/aws` and you should see a folder called `aws` with files inside it.

---

### Step 7: Run the AWS CLI installer

On the server, as ec2-user:

```
sudo ./aws/install
```

This runs the official AWS install script. `sudo` is required because it writes to `/usr/local/bin`, which needs administrator permission.

Expected output (yours will differ):
```
You can now run: /usr/local/bin/aws --version
```

Check it worked: you should see the line `You can now run: /usr/local/bin/aws --version`.

---

### Step 8: Confirm the AWS CLI is working and your IAM role is active

On the server, as ec2-user:

```
aws sts get-caller-identity
```

`sts` is the AWS Security Token Service. `get-caller-identity` asks AWS "who am I logged in as?" This works automatically because the EC2 instance has an IAM role attached - no passwords or keys needed.

Expected output (yours will differ):
```
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-01b800812179515f1",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-01b800812179515f1"
}
```

Check it worked: you should see a JSON block containing `"Account"` and `"Arn"`. This confirms your instance has valid AWS credentials.

---

## Part 3: Create the Terraform project folder

### Step 9: Create the project directory

On the server, as ec2-user:

```
mkdir -p /home/ec2-user/tf-lab
```

`mkdir` creates a directory. `-p` means "create any missing parent folders too" and do not error if the folder already exists.

Expected output (yours will differ):
```
(no output)
```

Check it worked: run `ls /home/ec2-user/` and you should see `tf-lab` listed.

---

## Part 4: Write the Terraform configuration files

You will create three files. Each file has a specific job in a Terraform project:

| File | Job |
|---|---|
| `main.tf` | Describes every resource you want to create |
| `variables.tf` | Declares input values (like passwords) that you supply at runtime |
| `outputs.tf` | Declares information to print after resources are created |

### Step 10: Create main.tf

Why this step: `main.tf` is the heart of this lab. It tells Terraform to create an RDS PostgreSQL database inside your default VPC, and it includes the three lifecycle rules this lab is teaching.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/main.tf
```

Press `i` to enter insert mode, then type (or paste) the following content exactly:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"
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

resource "aws_db_subnet_group" "appdb" {
  name_prefix = "appdb-"
  subnet_ids  = data.aws_subnets.default.ids
  description = "Subnet group for appdb (suta-cb-spike)"
}

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
  publicly_accessible  = false
  skip_final_snapshot  = true
  deletion_protection  = false
  apply_immediately    = true

  lifecycle {
    ignore_changes = [
      password,
      engine_version,
    ]

    prevent_destroy = false
  }
}
```

What each important section does:

- `terraform { required_providers ... }` - locks the AWS plugin to version 5.x so the config does not break if a newer version changes behaviour.
- `provider "aws" { region = ... }` - tells Terraform which AWS region to create resources in.
- `default_tags` - stamps a `Project` tag on every resource created by this config, which helps with cost tracking.
- `data "aws_vpc" "default"` - looks up your account's default VPC so you do not have to hard-code its ID.
- `data "aws_subnets" "default"` - finds all subnets inside that VPC. RDS needs at least two subnets in different availability zones.
- `resource "aws_db_subnet_group" "appdb"` - RDS requires a named subnet group even when using the default VPC.
- `resource "aws_db_instance" "appdb"` - the PostgreSQL database itself.
- `password = var.db_password` - the password comes from a variable, never hard-coded.
- `skip_final_snapshot = true` - skips taking a backup snapshot when the database is deleted. Safe for a lab, not for production.
- `lifecycle { ... }` - this block contains the three safety rules this lab is about (explained in the steps below).
- `ignore_changes = [password, engine_version]` - tells Terraform to stop tracking changes to these two attributes after the first `apply`. Explained fully in Part 6.
- `prevent_destroy = false` - set to `false` now so you can clean up the lab. You will change it to `true` in Part 6 to see how it works.

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

Expected output (yours will differ):
```
(returns to the command prompt)
```

Check it worked: run `ls /home/ec2-user/tf-lab/` and you should see `main.tf` listed.

---

### Step 11: Create variables.tf

Why this step: This file declares the `db_password` variable so Terraform knows to expect it. Marking it `sensitive = true` tells Terraform to hide the value in all output.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/variables.tf
```

Press `i`, then type:

```hcl
variable "db_password" {
  description = "Master password for the appdb RDS instance. Supply via TF_VAR_db_password or -var flag. NEVER commit a real password."
  type        = string
  sensitive   = true
}
```

What each line does:

- `variable "db_password"` - declares an input variable named `db_password`.
- `type = string` - the value must be plain text.
- `sensitive = true` - Terraform will show `(sensitive value)` instead of the actual password in plan and apply output.

PostgreSQL password rules: 8 to 128 characters, must not start with `/`, letters and numbers are always safe.

Press `Esc`, then `:wq`, then `Enter`.

Expected output (yours will differ):
```
(returns to the command prompt)
```

Check it worked: run `ls /home/ec2-user/tf-lab/` and you should see `variables.tf` listed.

---

### Step 12: Create outputs.tf

Why this step: After Terraform creates the database, you need to know its hostname so you can connect to it. Output values print that information automatically at the end of `terraform apply`.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/outputs.tf
```

Press `i`, then type:

```hcl
output "db_instance_id" {
  description = "The RDS instance identifier (includes the random suffix)."
  value       = aws_db_instance.appdb.identifier
}

output "db_endpoint" {
  description = "The connection endpoint (host:port) for the database."
  value       = aws_db_instance.appdb.endpoint
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.appdb.name
}
```

What each output does:

- `db_instance_id` - the unique name AWS assigned to the instance.
- `db_endpoint` - the hostname and port you would use in a database connection string.
- `db_subnet_group_name` - the name of the subnet group that was created.

Press `Esc`, then `:wq`, then `Enter`.

Expected output (yours will differ):
```
(returns to the command prompt)
```

Check it worked: run `ls /home/ec2-user/tf-lab/` and you should see all three files: `main.tf`, `variables.tf`, `outputs.tf`.

---

## Part 5: Initialise, validate, and apply

### Step 13: Move into the project folder

On the server, as ec2-user:

```
cd /home/ec2-user/tf-lab
```

All remaining Terraform commands must be run from this folder.

Expected output (yours will differ):
```
(no output, your prompt changes to show the new directory)
```

Check it worked: run `pwd` and you should see `/home/ec2-user/tf-lab`.

---

### Step 14: Initialise Terraform

Why this step: `terraform init` downloads the AWS provider plugin (the code that knows how to talk to AWS). You must run this once before any other Terraform command.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform init
```

Expected output (yours will differ):
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Check it worked: you should see `Terraform has been successfully initialized!`.

---

### Step 15: Validate the configuration

Why this step: `terraform validate` checks your `.tf` files for syntax errors before you spend any time (or money) trying to apply them.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform validate
```

Expected output (yours will differ):
```
Success! The configuration is valid.
```

Check it worked: you should see `Success! The configuration is valid.`

---

### Step 16: Set your database password as an environment variable

Why this step: Terraform reads environment variables that start with `TF_VAR_` and uses them as variable values. This is a safe way to supply a password - it never touches a file and never appears in the Terraform code.

On the server, as ec2-user:

```
export TF_VAR_db_password="YOUR_DB_PASSWORD"
```

Replace `YOUR_DB_PASSWORD` with a strong password of your own choosing. Requirements: 8-128 characters, do not start with `/`.

Expected output (yours will differ):
```
(no output)
```

Check it worked: run `echo $TF_VAR_db_password` and you should see the password you just set printed to the screen. Remember: do not share this value with others.

---

### Step 17: Apply the configuration to create the database

Why this step: `terraform apply` compares your configuration files to the real state of AWS and creates or changes resources to match. Creating an RDS instance takes several minutes - this is normal.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform apply -auto-approve
```

`-auto-approve` skips the interactive yes/no prompt. In a real team environment you would omit this flag to review the plan before approving.

Expected output (yours will differ):
```
...
aws_db_instance.appdb: Still creating... [04m50s elapsed]
aws_db_instance.appdb: Creation complete after 5m14s [id=db-BP6ZPXZENBCSQL7DSQGEI5WATQ]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

db_endpoint = "appdb-20261026175448546400000001.cyn0wsqma5in.us-east-1.rds.amazonaws.com:5432"
db_instance_id = "appdb-20261026175448546400000001"
db_subnet_group_name = "appdb-20261026175416806700000001"
```

Check it worked: you should see `Apply complete! Resources: 1 added` and the three output values printed below it. Copy the `db_endpoint` value - you will need it if you want to connect.

**If you hit this - engine version error:**

If you see an error like `InvalidParameterCombination` mentioning engine version, it means the version `16.3` is not available in your region. Check which versions are available:

```
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[?starts_with(EngineVersion,'16.')].EngineVersion" --output text --region us-east-1
```

You should see a list like `16.3  16.4  16.9  16.10 ...`. Open `main.tf` in vi and change `engine_version` to one of the versions shown, then re-run `terraform apply -auto-approve`.

---

### Step 18: Confirm the database is in a healthy state

On the server, as ec2-user:

```
aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].DBInstanceStatus" --output text --region us-east-1
```

`describe-db-instances` fetches details about your RDS instances. `--query` filters the response to show only the status field of instances whose name starts with `appdb-`. `--output text` prints it as plain text instead of JSON.

Expected output (yours will differ):
```
available
```

Check it worked: you should see the word `available`.

---

### Step 19: List all resources Terraform is tracking

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab state list
```

`state list` shows every resource recorded in Terraform's state file - its memory of what it created. `-chdir=` tells Terraform which folder to look in (useful when you are not already in that folder).

Expected output (yours will differ):
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_instance.appdb
aws_db_subnet_group.appdb
```

Check it worked: you should see `aws_db_instance.appdb` in the list.

---

## Part 6: Explore the three lifecycle rules

### Rule 1: ignore_changes - stopping Terraform from fighting out-of-band changes

The database already has `ignore_changes = [password, engine_version]` in its lifecycle block. Here is why that matters:

**The problem it solves:** Imagine an on-call engineer rotates the database password at 3 AM directly in the AWS Console during an emergency. Without `ignore_changes`, the next `terraform apply` would detect that the real password no longer matches Terraform's saved state and revert it - potentially locking the team out of the database.

The same problem applies to `engine_version`: AWS can automatically apply minor version upgrades (for example 16.3 to 16.6). Without `ignore_changes`, Terraform would try to fight this and downgrade the engine on the next apply.

**What the rule does:** After the first `apply`, Terraform stops tracking those attributes. Any future changes to `password` or `engine_version` - whether made by AWS automatically or by a DBA manually - will never be reverted by Terraform.

You can confirm this rule is in place:

### Step 20: Run terraform plan to confirm Terraform sees no drift

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform plan
```

`terraform plan` shows what Terraform would do if you ran apply right now. Because `ignore_changes` covers the attributes most likely to drift, Terraform should report nothing to do.

Expected output (yours will differ):
```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Check it worked: you should see `No changes. Your infrastructure matches the configuration.`

---

### Rule 2: prevent_destroy - refusing plans that would delete the database

Right now `prevent_destroy = false` in `main.tf`. You will change it to `true`, apply it, and then try to destroy the database to see what happens.

### Step 21: Open main.tf to enable prevent_destroy

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/main.tf
```

Press `/` then type `prevent_destroy` and press `Enter` to search. Press `n` to jump to the line inside the lifecycle block (not the comments). Change `false` to `true` so that line reads:

```hcl
    prevent_destroy = true
```

Press `Esc`, then `:wq`, then `Enter` to save.

Expected output (yours will differ):
```
(returns to the command prompt)
```

Check it worked: run `grep prevent_destroy /home/ec2-user/tf-lab/main.tf` and you should see the line `prevent_destroy = true` (inside the lifecycle block, not a comment).

---

### Step 22: Apply the change to record prevent_destroy in state

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform apply -auto-approve
```

Expected output (yours will differ):
```
No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

db_endpoint = "appdb-20261026175448546400000001.cyn0wsqma5in.us-east-1.rds.amazonaws.com:5432"
db_instance_id = "appdb-20261026175448546400000001"
db_subnet_group_name = "appdb-20261026175416806700000001"
```

Check it worked: you should see `Apply complete!` and the three output values. Because the resource itself did not change, the counts show `0 added, 0 changed, 0 destroyed`.

---

### Step 23: Try to destroy the database - watch prevent_destroy block it

Why this step: `terraform plan -destroy` shows what Terraform would delete if you ran `terraform destroy`. With `prevent_destroy = true`, Terraform should refuse even to plan the deletion.

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform plan -destroy
```

Expected output (yours will differ):
```
...
Error: Instance cannot be destroyed

  on main.tf line 58:
  58: resource "aws_db_instance" "appdb" {

Resource aws_db_instance.appdb has lifecycle.prevent_destroy set, but the
plan calls for this resource to be destroyed. To avoid this error and
continue with the plan, either disable lifecycle.prevent_destroy or reduce
the scope of the plan using the -target option.
```

Check it worked: you should see `Error: Instance cannot be destroyed` and the explanation that `lifecycle.prevent_destroy` is set. This is exactly what you want to see - Terraform refused to produce a destruction plan.

---

### Rule 3: create_before_destroy - eliminating downtime during replacements

This rule is not enabled in the lab's configuration, but it is important to understand.

**The problem it solves:** By default, when Terraform needs to replace a resource (for example you rename a subnet group while an RDS instance is using it), it destroys the old resource first, then creates the new one. This causes a gap in service.

**What the rule does:** When you add `create_before_destroy = true` to a resource's lifecycle block, Terraform builds the new resource first, switches all references to point at it, and only then deletes the old one. This eliminates the gap.

**Where it is most useful with RDS:** You would use `create_before_destroy = true` on the `aws_db_subnet_group` or `aws_db_parameter_group` resources, not on the `aws_db_instance` itself. Two RDS instances cannot share the same name at the same time, so the pattern does not directly apply to the instance - but it does apply to the supporting resources the instance depends on.

---

## Part 7: Clean up

### Step 24: Re-open main.tf to disable prevent_destroy

Why this step: You must set `prevent_destroy` back to `false` before Terraform will allow you to destroy the lab resources.

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/main.tf
```

Press `/`, type `prevent_destroy = true`, press `Enter`. Change `true` to `false` so the line reads:

```hcl
    prevent_destroy = false
```

Press `Esc`, then `:wq`, then `Enter`.

Expected output (yours will differ):
```
(returns to the command prompt)
```

Check it worked: run `grep prevent_destroy /home/ec2-user/tf-lab/main.tf` and confirm the lifecycle block line reads `prevent_destroy = false`.

---

### Step 25: Apply the change to update state

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform apply -auto-approve
```

Expected output (yours will differ):
```
No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

db_endpoint = "appdb-20261026175448546400000001.cyn0wsqma5in.us-east-1.rds.amazonaws.com:5432"
db_instance_id = "appdb-20261026175448546400000001"
db_subnet_group_name = "appdb-20261026175416806700000001"
```

Check it worked: you should see `Apply complete!` with no errors.

---

### Step 26: Destroy all lab resources

On the server, as ec2-user, inside `/home/ec2-user/tf-lab`:

```
terraform destroy -auto-approve
```

This removes every resource Terraform created - the RDS instance and the subnet group. RDS deletion can take several minutes.

Expected output (yours will differ):
```
...
aws_db_instance.appdb: Destroying...
aws_db_instance.appdb: Still destroying... [01m00s elapsed]
...
Destroy complete! Resources: 2 destroyed.
```

Check it worked: you should see `Destroy complete! Resources: 2 destroyed.`

---

## Summary

In this lab you:

1. Installed Terraform and the AWS CLI on a CentOS server.
2. Wrote a three-file Terraform configuration that creates an RDS PostgreSQL instance inside your account's default VPC.
3. Used a `TF_VAR_` environment variable to supply a sensitive password without hard-coding it.
4. Demonstrated `ignore_changes` - which stops Terraform reverting emergency changes made outside Terraform (such as a password rotation or an AWS automatic engine upgrade).
5. Demonstrated `prevent_destroy = true` - which causes Terraform to refuse even to plan a deletion of the protected resource.
6. Learned where `create_before_destroy` applies - on supporting resources like subnet groups and parameter groups, to eliminate the downtime gap that normally occurs when Terraform replaces a resource.
