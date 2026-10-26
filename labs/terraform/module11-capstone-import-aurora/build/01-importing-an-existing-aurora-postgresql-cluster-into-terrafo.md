# Importing an Existing Aurora PostgreSQL Cluster into Terraform

**Objective:** Take an Aurora PostgreSQL database cluster that was created manually with the AWS CLI, then bring it under Terraform management using `terraform import` - without deleting or recreating the database.

**Estimated Time:** 60-90 minutes

**Prerequisites:**
- An EC2 instance (CentOS Stream 9 or Amazon Linux) with an IAM role that has permissions to create and describe RDS clusters and EC2 VPCs/subnets
- SSH access to the instance as `ec2-user`
- Basic comfort with a terminal and the vi text editor

---

## Background: What is a brownfield import?

"Brownfield" means infrastructure that already exists - perhaps someone clicked through the AWS Console or ran some AWS CLI commands to create a database. Terraform knows nothing about it yet. The import workflow lets you hand that existing resource over to Terraform so you can manage it going forward. The golden rule is: **you must never get a destroy (-/+) in your plan**. Destroying and recreating a production database would cause an outage and data loss.

The workflow you will follow is:

1. Install Terraform and the AWS CLI
2. Create a "legacy" Aurora cluster manually (simulating existing click-ops infrastructure)
3. Write Terraform resource blocks that describe those existing resources
4. Run `terraform import` to tell Terraform's state file about them
5. Run `terraform state show` to read back the real attribute values
6. Adjust the config until `terraform plan` shows 0 destroys and 0 replaces

---

## Part A: Install the tools

### Step 1

On the server, as ec2-user - create a working directory for this lab:

```
mkdir -p /home/ec2-user/tf-lab
```

This creates the directory (and any missing parent directories, thanks to `-p`). You will put all your Terraform files here.

Expected output (yours will differ):
```
(no output means success)
```

Check it worked: no error message is printed.

---

### Step 2

On the server, as ec2-user - move into that directory:

```
cd /home/ec2-user/tf-lab
```

Expected output (yours will differ):
```
(no output means success)
```

Check it worked: your shell prompt should now show `tf-lab` as the current directory (run `pwd` if you are unsure).

---

### Step 3

Why this step: Terraform is not installed by default on CentOS. You need to add HashiCorp's official package repository before you can install it with `yum`.

On the server, as ec2-user - add the HashiCorp package repository:

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`yum-config-manager` adds a new repository source. `--add-repo` takes the URL of HashiCorp's repo file and saves it so that `yum` knows where to find Terraform packages.

Expected output (yours will differ):
```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you see the line `Adding repo from:` with the HashiCorp URL.

---

### Step 4

On the server, as ec2-user - install Terraform:

```
sudo yum install -y terraform
```

`-y` answers "yes" automatically to any confirmation prompts so the install runs without needing your input.

Expected output (yours will differ):
```
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Complete!
```

Check it worked: you see `Complete!` at the end of the output and `terraform` appears in the installing list.

---

### Step 5

On the server, as ec2-user - confirm Terraform is working:

```
terraform version
```

Expected output (yours will differ):
```
Terraform v1.17.0
on linux_amd64
```

Check it worked: you see a version number starting with `Terraform v`.

---

### Step 6

Why this step: The AWS CLI is also not installed. You will download it directly from Amazon as a zip file.

On the server, as ec2-user - download the AWS CLI installer:

```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

`curl` downloads a file from the internet. `-o /tmp/awscliv2.zip` saves it to `/tmp` with that filename.

Expected output (yours will differ):
```
100 70.9M  100 70.9M    0     0   400M      0 --:--:-- --:--:-- --:--:--  398M
```

Check it worked: the final line shows `100` at the start, meaning the download is complete.

---

**If you hit this:** If you try to unzip and get `bash: unzip: command not found`, install it first:

```
sudo yum install -y unzip
```

Expected output (yours will differ):
```
Installed:
  unzip-6.0-59.el9.x86_64

Complete!
```

Then continue with the next step.

---

### Step 7

On the server, as ec2-user - unzip the AWS CLI installer:

```
cd /tmp && unzip -q awscliv2.zip
```

`-q` means "quiet" - it suppresses the list of every file being extracted so your screen is not flooded.

Expected output (yours will differ):
```
(no output means success)
```

Check it worked: no error message is printed.

---

### Step 8

On the server, as ec2-user - run the AWS CLI installer:

```
sudo /tmp/aws/install
```

This runs the installer script that was inside the zip. It copies the `aws` binary to `/usr/local/bin/`.

Expected output (yours will differ):
```
You can now run: /usr/local/bin/aws --version
```

Check it worked: you see the line `You can now run: /usr/local/bin/aws --version`.

---

### Step 9

Why this step: `/usr/local/bin` may not yet be in your shell's PATH (the list of places it looks for commands). Adding it means you can type `aws` instead of the full path `/usr/local/bin/aws`.

On the server, as ec2-user - add `/usr/local/bin` to your PATH permanently:

```
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
```

`echo` prints the text. `>>` appends it to `~/.bashrc`, which is the file that runs every time you open a shell. This means the change persists after you log out.

Expected output (yours will differ):
```
(no output means success)
```

Check it worked: no error message is printed.

---

### Step 10

On the server, as ec2-user - apply the PATH change to your current session:

```
export PATH="/usr/local/bin:$PATH"
```

`export` makes the variable available to the current shell session immediately, without having to log out and back in.

Expected output (yours will differ):
```
(no output means success)
```

Check it worked: no error message is printed.

---

### Step 11

On the server, as ec2-user - verify the AWS CLI is working and your EC2 role has credentials:

```
aws sts get-caller-identity
```

`sts get-caller-identity` asks AWS "who am I?" It uses the IAM role attached to your EC2 instance automatically.

Expected output (yours will differ):
```
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-03cc26d8f00c1da1e",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-03cc26d8f00c1da1e"
}
```

Check it worked: you see a JSON block containing your `Account` number and an `Arn`. If you see `command not found`, make sure you completed steps 9 and 10.

---

## Part B: Create the "legacy" database (simulating existing infrastructure)

These steps create the database by hand, the same way someone might have done it through the AWS Console months ago. This is the infrastructure you will later import into Terraform.

### Step 12

On the server, as ec2-user - find your default VPC ID:

```
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region us-east-1
```

`describe-vpcs` lists VPCs. `--filters "Name=isDefault,Values=true"` narrows it to only the default VPC. `--query` extracts just the VPC ID. `--output text` prints it as plain text rather than JSON.

Expected output (yours will differ):
```
vpc-09a1c840cf0697b9a
```

Check it worked: you see a single value starting with `vpc-`. Write this down - you will need it in the next step.

---

### Step 13

On the server, as ec2-user - list the default subnets in your default VPC. Replace `YOUR_VPC_ID` with the value you got in step 12:

```
aws ec2 describe-subnets --filters "Name=vpc-id,Values=YOUR_VPC_ID" "Name=defaultForAz,Values=true" --query "Subnets[*].[SubnetId,AvailabilityZone]" --output text --region us-east-1
```

`describe-subnets` lists subnets. The two `--filters` limit results to the default subnets inside your VPC. `--query` extracts each subnet's ID and availability zone side by side.

Expected output (yours will differ):
```
subnet-07538e84ecf825ba7	us-east-1c
subnet-057baec8868186f3b	us-east-1e
subnet-04965629f04131232	us-east-1b
subnet-07b4380865b5763b1	us-east-1a
subnet-0eea330f969a586fb	us-east-1f
subnet-00a5ef44c5f9d485a	us-east-1d
```

Check it worked: you see a list of lines each containing a subnet ID and an availability zone. Write down **two subnet IDs** from different availability zones - you will use them in the next step.

---

### Step 14

Why this step: An RDS subnet group tells Aurora which subnets it can place database nodes in. It must span at least two availability zones for high availability.

On the server, as ec2-user - create a subnet group. Replace `YOUR_SUBNET_ID_1` and `YOUR_SUBNET_ID_2` with two subnet IDs from step 13 that are in different availability zones:

```
aws rds create-db-subnet-group --db-subnet-group-name legacy-aurora-subnets --db-subnet-group-description "Legacy Aurora subnet group (hand-built, pre-Terraform)" --subnet-ids YOUR_SUBNET_ID_1 YOUR_SUBNET_ID_2 --tags Key=Project,Value=suta-cb-spike --region us-east-1
```

`create-db-subnet-group` creates the subnet group. `--db-subnet-group-name` is the name Terraform will reference later. `--tags` adds a metadata label to the resource.

Expected output (yours will differ):
```
{
    "DBSubnetGroup": {
        "DBSubnetGroupName": "legacy-aurora-subnets",
        "SubnetGroupStatus": "Complete",
        ...
    }
}
```

Check it worked: you see `"SubnetGroupStatus": "Complete"` in the output.

---

### Step 15

On the server, as ec2-user - create the Aurora PostgreSQL cluster. Replace `YOUR_MASTER_PASSWORD` with a strong password of your choosing (at least 8 characters, mix of letters, numbers, and symbols):

```
aws rds create-db-cluster --db-cluster-identifier legacy-aurora --engine aurora-postgresql --engine-version 15.10 --master-username dbadmin --master-user-password YOUR_MASTER_PASSWORD --db-subnet-group-name legacy-aurora-subnets --no-deletion-protection --tags Key=Project,Value=suta-cb-spike --region us-east-1
```

`create-db-cluster` creates the Aurora cluster control plane. `--engine aurora-postgresql` specifies PostgreSQL-compatible Aurora. `--master-username` and `--master-user-password` set the database admin account. `--no-deletion-protection` makes it easier to clean up this lab later. Remember the password you chose - you will need it when writing the Terraform config.

Expected output (yours will differ):
```
{
    "DBCluster": {
        "DBClusterIdentifier": "legacy-aurora",
        "Status": "creating",
        "Endpoint": "legacy-aurora.cluster-cyn0wsqma5in.us-east-1.rds.amazonaws.com",
        ...
    }
}
```

Check it worked: you see `"Status": "creating"` in the output. The cluster is now being built in AWS.

---

### Step 16

On the server, as ec2-user - add a database instance to the cluster:

```
aws rds create-db-instance --db-instance-identifier legacy-aurora-1 --db-cluster-identifier legacy-aurora --engine aurora-postgresql --db-instance-class db.t3.medium --tags Key=Project,Value=suta-cb-spike --region us-east-1
```

`create-db-instance` adds an actual database server node to the cluster you just created. `--db-instance-class db.t3.medium` selects the server size. Aurora separates the cluster (networking, endpoints, storage) from the instances (compute).

Expected output (yours will differ):
```
{
    "DBInstance": {
        "DBInstanceIdentifier": "legacy-aurora-1",
        "DBInstanceStatus": "creating",
        ...
    }
}
```

Check it worked: you see `"DBInstanceStatus": "creating"` in the output.

---

### Step 17

Why this step: The cluster and instance take several minutes to become ready. You must wait until both are `available` before attempting the import.

On the server, as ec2-user - check that the cluster is available (run this every minute or two until you see `available`):

```
aws rds describe-db-clusters --db-cluster-identifier legacy-aurora --query "DBClusters[0].Status" --output text --region us-east-1
```

Expected output (yours will differ):
```
available
```

Check it worked: the output is the single word `available`. If you see `creating`, wait two minutes and run the command again.

---

### Step 18

On the server, as ec2-user - check that the instance is also available:

```
aws rds describe-db-instances --db-instance-identifier legacy-aurora-1 --query "DBInstances[0].DBInstanceStatus" --output text --region us-east-1
```

Expected output (yours will differ):
```
available
```

Check it worked: the output is the single word `available`. Both the cluster and instance must show `available` before moving on.

---

## Part C: Write the Terraform configuration files

Now you will write the Terraform files that describe the infrastructure you just created. Think of these as the "blueprint" you want Terraform to manage going forward.

### Step 19

On the server, as ec2-user - make sure you are in the Terraform lab directory:

```
cd /home/ec2-user/tf-lab
```

Expected output (yours will differ):
```
(no output means success)
```

Check it worked: no error message is printed.

---

### Step 20

Why this step: `versions.tf` tells Terraform which version of itself and which provider plugins to use. It is always the first file you create.

On the server, as ec2-user - open vi to create `versions.tf`:

```
vi /home/ec2-user/tf-lab/versions.tf
```

Expected output (yours will differ):
```
(vi opens with an empty buffer)
```

Check it worked: you see the vi editor open with an empty file named `versions.tf`.

---

### Step 21

In vi - press `i` to enter Insert mode, then type the following content exactly:

```
terraform {
  required_version = ">= 1.5"

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
```

What each important part means:
- `required_version = ">= 1.5"` - this config needs Terraform 1.5 or newer
- `source = "hashicorp/aws"` - use the official AWS provider from HashiCorp
- `version = "~> 5.0"` - use any version 5.x (the `~>` means "compatible with")
- `region = "us-east-1"` - all resources go to the US East 1 region by default
- `default_tags` - every resource Terraform creates or manages will automatically receive the tag `Project = "suta-cb-spike"` without you having to repeat it

When finished typing, press `Esc`, then type `:wq` and press `Enter` to save and quit.

Expected output (yours will differ):
```
(vi closes and you return to the shell prompt)
```

Check it worked: you are back at the shell prompt with no error.

---

### Step 22

On the server, as ec2-user - confirm `versions.tf` was saved correctly:

```
cat /home/ec2-user/tf-lab/versions.tf
```

Expected output (yours will differ):
```
terraform {
  required_version = ">= 1.5"

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
```

Check it worked: all the lines you typed are present in the output.

---

### Step 23

Why this step: `main.tf` contains the three resource blocks that describe the infrastructure you created by hand. You need one block for each AWS object you plan to import.

On the server, as ec2-user - open vi to create `main.tf`:

```
vi /home/ec2-user/tf-lab/main.tf
```

Expected output (yours will differ):
```
(vi opens with an empty buffer)
```

Check it worked: you see the vi editor open with an empty file named `main.tf`.

---

### Step 24

In vi - press `i` to enter Insert mode. Type the following content. Where you see `YOUR_SUBNET_ID_1` and `YOUR_SUBNET_ID_2`, use the actual subnet IDs you chose in step 13. Where you see `YOUR_SECURITY_GROUP_ID`, use the security group ID from the cluster output in step 15 (look for `VpcSecurityGroupId` in that output). Where you see `YOUR_MASTER_PASSWORD`, use the password you chose in step 15.

```
# These three resource blocks describe objects that already exist in AWS.
# They were created by hand - Terraform has never touched them.
# The import workflow is:
#   1. Write these blocks
#   2. terraform import <address> <real-id>  (one per block)
#   3. terraform state show <address>        (copy real values back here)
#   4. terraform plan until 0 to destroy, 0 to replace

resource "aws_db_subnet_group" "legacy" {
  name        = "legacy-aurora-subnets"
  description = "Legacy Aurora subnet group (hand-built, pre-Terraform)"

  subnet_ids = [
    "YOUR_SUBNET_ID_1",
    "YOUR_SUBNET_ID_2",
  ]
}

resource "aws_rds_cluster" "legacy" {
  cluster_identifier = "legacy-aurora"

  engine         = "aurora-postgresql"
  engine_version = "15.10"

  master_username = "dbadmin"
  master_password = "YOUR_MASTER_PASSWORD"

  db_subnet_group_name   = aws_db_subnet_group.legacy.name
  vpc_security_group_ids = ["YOUR_SECURITY_GROUP_ID"]

  deletion_protection  = false
  skip_final_snapshot  = true

  backup_retention_period      = 1
  preferred_backup_window      = "08:19-08:49"
  preferred_maintenance_window = "tue:09:09-tue:09:39"

  enable_global_write_forwarding = false
  enable_local_write_forwarding  = false
}

resource "aws_rds_cluster_instance" "legacy" {
  identifier         = "legacy-aurora-1"
  cluster_identifier = aws_rds_cluster.legacy.cluster_identifier

  engine         = aws_rds_cluster.legacy.engine
  engine_version = aws_rds_cluster.legacy.engine_version

  instance_class             = "db.t3.medium"
  auto_minor_version_upgrade = true
  publicly_accessible        = false

  promotion_tier = 1
  force_destroy  = false
}
```

What each important part means:
- `resource "aws_db_subnet_group" "legacy"` - the resource type is `aws_db_subnet_group`; the local name `legacy` is what Terraform uses internally to refer to it
- `aws_db_subnet_group.legacy.name` - Terraform reads the name from the subnet group block rather than you repeating it as a string; this keeps the config consistent
- `aws_rds_cluster.legacy.cluster_identifier` - same idea for the cluster instance; it references the cluster block
- `skip_final_snapshot = true` - when the cluster is deleted, do not create a backup snapshot; fine for a lab but you would set this to `false` in production
- `enable_global_write_forwarding = false` and `enable_local_write_forwarding = false` - these must be set explicitly because the AWS provider version 5.x always plans them if they are absent, creating noisy plan output
- `promotion_tier = 1` - this is the actual value AWS stored for this instance (you will verify this in a later step)

When finished, press `Esc`, then type `:wq` and press `Enter` to save and quit.

Expected output (yours will differ):
```
(vi closes and you return to the shell prompt)
```

Check it worked: you are back at the shell prompt with no error.

---

### Step 25

On the server, as ec2-user - confirm the file was saved:

```
cat /home/ec2-user/tf-lab/main.tf
```

Expected output (yours will differ):
```
# These three resource blocks describe objects that already exist in AWS.
...
resource "aws_db_subnet_group" "legacy" {
  name        = "legacy-aurora-subnets"
...
```

Check it worked: you can see all three resource blocks in the output.

---

## Part D: Initialize Terraform and import the resources

### Step 26

Why this step: `terraform init` downloads the AWS provider plugin (the code that knows how to talk to AWS). You must run it once before any other Terraform command.

On the server, as ec2-user - initialize the Terraform working directory:

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

Check it worked: you see the line `Terraform has been successfully initialized!`.

---

### Step 27

Why this step: `terraform import` tells Terraform's state file about an existing resource. It does NOT create or change anything in AWS - it only adds an entry to Terraform's internal bookkeeping. The format is `terraform import RESOURCE_ADDRESS REAL_AWS_ID`. You must import each resource separately.

On the server, as ec2-user - import the subnet group into Terraform state:

```
terraform import aws_db_subnet_group.legacy legacy-aurora-subnets
```

`aws_db_subnet_group.legacy` is the address from your `main.tf` (type dot local-name). `legacy-aurora-subnets` is the real name of the subnet group in AWS - the ID that AWS uses to look it up.

Expected output (yours will differ):
```
aws_db_subnet_group.legacy: Importing from ID "legacy-aurora-subnets"...
aws_db_subnet_group.legacy: Import prepared!
  Prepared aws_db_subnet_group for import
aws_db_subnet_group.legacy: Refreshing state... [id=legacy-aurora-subnets]

Import successful!
```

Check it worked: you see `Import successful!` at the end.

---

### Step 28

On the server, as ec2-user - import the Aurora cluster:

```
terraform import aws_rds_cluster.legacy legacy-aurora
```

`aws_rds_cluster.legacy` is the address in your config. `legacy-aurora` is the cluster identifier you gave it when you created it in step 15.

Expected output (yours will differ):
```
aws_rds_cluster.legacy: Importing from ID "legacy-aurora"...
aws_rds_cluster.legacy: Import prepared!
aws_rds_cluster.legacy: Refreshing state... [id=legacy-aurora]

Import successful!
```

Check it worked: you see `Import successful!`.

---

### Step 29

On the server, as ec2-user - import the Aurora cluster instance:

```
terraform import aws_rds_cluster_instance.legacy legacy-aurora-1
```

`aws_rds_cluster_instance.legacy` is the address in your config. `legacy-aurora-1` is the instance identifier you gave it in step 16.

Expected output (yours will differ):
```
aws_rds_cluster_instance.legacy: Importing from ID "legacy-aurora-1"...
aws_rds_cluster_instance.legacy: Import prepared!
aws_rds_cluster_instance.legacy: Refreshing state... [id=legacy-aurora-1]

Import successful!
```

Check it worked: you see `Import successful!`.

---

### Step 30

On the server, as ec2-user - confirm all three resources are now in Terraform's state:

```
terraform state list
```

`state list` prints every resource that Terraform is now tracking in its state file.

Expected output (yours will differ):
```
aws_db_subnet_group.legacy
aws_rds_cluster.legacy
aws_rds_cluster_instance.legacy
```

Check it worked: all three resource addresses appear in the list.

---

## Part E: Inspect the real state and reconcile your config

After importing, Terraform knows about the resources. But your config file may not match every detail AWS stored. The next steps let you read the real values and adjust your config to match.

### Step 31

On the server, as ec2-user - read what Terraform learned about the Aurora cluster:

```
terraform state show aws_rds_cluster.legacy
```

`state show` prints the complete set of attributes Terraform recorded for a resource during import.

Expected output (yours will differ):
```
# aws_rds_cluster.legacy:
resource "aws_rds_cluster" "legacy" {
    allocated_storage                     = 1
    arn                                   = "arn:aws:rds:us-east-1:..."
    backup_retention_period               = 1
    cluster_identifier                    = "legacy-aurora"
    db_cluster_parameter_group_name       = "default.aurora-postgresql15"
    db_subnet_group_name                  = "legacy-aurora-subnets"
    deletion_protection                   = false
    engine                                = "aurora-postgresql"
    engine_version                        = "15.10"
    master_password_wo                    = (write-only attribute)
    master_username                       = "dbadmin"
    ...
}
```

Check it worked: you see a long block of attributes. Pay particular attention to any attribute values that differ from what you typed in `main.tf` - those are the ones you may need to fix.

---

### Step 32

On the server, as ec2-user - read what Terraform learned about the cluster instance:

```
terraform state show aws_rds_cluster_instance.legacy
```

Expected output (yours will differ):
```
# aws_rds_cluster_instance.legacy:
resource "aws_rds_cluster_instance" "legacy" {
    auto_minor_version_upgrade            = true
    availability_zone                     = "us-east-1a"
    cluster_identifier                    = "legacy-aurora"
    engine                                = "aurora-postgresql"
    engine_version                        = "15.10"
    instance_class                        = "db.t3.medium"
    promotion_tier                        = 1
    publicly_accessible                   = false
    ...
}
```

Check it worked: you see the instance attributes. Note the value of `promotion_tier` - it should be `1`. If your output shows a different value, update that line in your `main.tf` to match.

---

### Step 33

On the server, as ec2-user - read what Terraform learned about the subnet group:

```
terraform state show aws_db_subnet_group.legacy
```

Expected output (yours will differ):
```
# aws_db_subnet_group.legacy:
resource "aws_db_subnet_group" "legacy" {
    arn         = "arn:aws:rds:us-east-1:..."
    description = "Legacy Aurora subnet group (hand-built, pre-Terraform)"
    id          = "legacy-aurora-subnets"
    name        = "legacy-aurora-subnets"
    subnet_ids  = [
        "subnet-04965629f04131232",
        "subnet-07b4380865b5763b1",
    ]
    tags_all    = {
        "Project" = "suta-cb-spike"
    }
    vpc_id      = "vpc-09a1c840cf0697b9a"
}
```

Check it worked: you see both subnet IDs listed and the `tags_all` block showing your Project tag.

---

## Part F: Run terraform plan and verify zero destroys

### Step 34

Why this step: `terraform plan` compares your config files against the state file and tells you what changes it would make. Your goal is to see 0 destroys and 0 replacements. An in-place change (`~`) is acceptable and means Terraform would update an attribute without recreating the resource.

On the server, as ec2-user - run the Terraform plan:

```
terraform plan
```

Expected output (yours will differ):
```
aws_db_subnet_group.legacy: Refreshing state... [id=legacy-aurora-subnets]
aws_rds_cluster.legacy: Refreshing state... [id=legacy-aurora]
aws_rds_cluster_instance.legacy: Refreshing state... [id=legacy-aurora-1]

Terraform will perform the following actions:

  # aws_rds_cluster.legacy will be updated in-place
  ~ resource "aws_rds_cluster" "legacy" {
      + enable_global_write_forwarding  = false
      + enable_local_write_forwarding   = false
        id                              = "legacy-aurora"
      + master_password                 = (sensitive value)
        tags                            = {}
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Check it worked: the final line says `0 to destroy`. The `~` symbol means in-place update (safe). The `+` symbols on `master_password` and the write-forwarding fields are expected - see the notes below.

---

**Understanding the remaining plan output:**

You may see two things that look alarming
