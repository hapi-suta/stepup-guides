# Survive: RDS create failures (20 min)

## The Scenario

A teammate handed you a Terraform project that is supposed to build a PostgreSQL RDS instance. You
run `terraform apply` and it fails - then you fix the error and it fails differently, three times
in a row. Each failure is a real mistake DBAs hit when they first provision RDS with code: a subnet
group that does not span enough Availability Zones, a parameter group for the wrong PostgreSQL
version, and a password RDS refuses. Your job is to read each error, find the cause, fix it, and
finish with nothing billable left behind.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. AWS authentication is keyless
(the instance role), so you never type an access key. Every failure here happens **before** a
database is created, so nothing expensive should run. If you ever see `Apply complete!` with an
`aws_db_instance` in it, jump straight to Step 6 and destroy.

---

## Step 1: Gather the facts you need

On **tf-lab-1**, as **ec2-user**, ask AWS which PostgreSQL 16 versions it currently offers.

```bash
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[?starts_with(EngineVersion,'16.')].EngineVersion" --output text --region us-east-1
```

`describe-db-engine-versions` lists the engine versions RDS supports. `--query` keeps only versions
starting with `16.`. `--output text` prints them on one line.

**Expected output (yours will differ):**
```
16.4	16.6	16.8	16.9	16.10 ...
```

Pick one version from your own output and note it. Old minor versions are retired over time, so a
version that worked in an old guide can fail today.

Find the parameter group family that belongs to PostgreSQL 16.

```bash
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[?starts_with(EngineVersion,'16.')].DBParameterGroupFamily | [0]" --output text --region us-east-1
```

**Expected output (yours will differ):**
```
postgres16
```

---

## Step 2: Build the "broken" project

On **tf-lab-1**, as **ec2-user**, create a scratch project.

```bash
mkdir -p ~/survive-rds && cd ~/survive-rds
```

Create the variables file with vi.

```bash
vi variables.tf
```

Press `i`, paste this, then press `Esc` and type `:wq` to save and quit:

```
variable "db_password" {
  type      = string
  sensitive = true
}
```

Now create `main.tf`.

```bash
vi main.tf
```

Press `i`, paste this (replace `16.X` with the version you noted in Step 1), then `Esc` and `:wq`:

```
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

resource "aws_db_subnet_group" "survive" {
  name_prefix = "survive-"
  subnet_ids  = [data.aws_subnets.default.ids[0]]
}

resource "aws_db_parameter_group" "survive" {
  name_prefix = "survive-"
  family      = "postgres15"
}

resource "aws_db_instance" "survive" {
  identifier_prefix    = "survive-"
  engine               = "postgres"
  engine_version       = "16.X"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  db_name              = "appdb"
  username             = "dbadmin"
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.survive.name
  parameter_group_name = aws_db_parameter_group.survive.name
  skip_final_snapshot  = true
}
```

The file has **three planted mistakes**. Do not fix them yet. Set a valid password (letters and
digits only, your own choice) in an environment variable for this terminal.

```bash
read -s -p "DB password (hidden): " TF_VAR_db_password
```

```bash
export TF_VAR_db_password
```

Initialise, then validate.

```bash
terraform init
```

```bash
terraform validate
```

**Expected output (yours will differ):**
```
Success! The configuration is valid.
```

**Notice:** validate passes. It only checks syntax. Every mistake in this file is a *value* that
AWS will reject, and Terraform only finds out when it calls AWS.

---

## Step 3: Failure 1 - the subnet group

On **tf-lab-1**, as **ec2-user**, apply.

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
│ Error: creating RDS DB Subnet Group (survive-...): DBSubnetGroupDoesNotCoverEnoughAZs:
│ The DB subnet group doesn't meet Availability Zone (AZ) coverage requirement.
│ Current AZ coverage: us-east-1a. Add subnets to cover at least 2 AZs.
```

**What the message is telling you:** RDS requires a subnet group to include subnets in at least two
Availability Zones, even for a single-AZ database, so it can fail over later. The planted mistake
is `subnet_ids = [data.aws_subnets.default.ids[0]]` - only the first subnet.

Check what Terraform recorded. A failed apply does not roll back what already worked, and the
parameter group has no dependency on the subnet group, so it may have been created.

```bash
terraform state list
```

**Expected output (yours will differ):**
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_parameter_group.survive
```

Fix it. Open `main.tf` with vi, and change the subnet group line to use all subnets:

```bash
vi main.tf
```

```
  subnet_ids  = data.aws_subnets.default.ids
```

Save and quit (`Esc`, `:wq`).

---

## Step 4: Failure 2 - the parameter group family

On **tf-lab-1**, as **ec2-user**, apply again.

```bash
terraform apply
```

Type `yes`.

**Expected output (yours will differ):**
```
aws_db_subnet_group.survive: Creation complete after 1s [id=survive-...]
│ Error: creating RDS DB Instance (survive-...): InvalidParameterCombination:
│ The parameter group ... with DBParameterGroupFamily postgres15 cannot be used
│ for this instance. Please use a parameter group with DBParameterGroupFamily postgres16.
```

**What the message is telling you:** the subnet group now succeeds, so Terraform moved on to the
database and AWS refused it. The parameter group's `family` must match the engine's major version.
The planted mistake is `family = "postgres15"` with a version 16 engine. AWS even names the family
you need, and it matches what you found in Step 1.

Fix it. Change the family in `main.tf`.

```bash
vi main.tf
```

```
  family      = "postgres16"
```

Save and quit. A parameter group cannot change family in place, so Terraform will replace it - and
that is fine here because nothing uses it yet.

---

## Step 5: Failure 3 - the password

On **tf-lab-1**, as **ec2-user**, apply again, but this time override the password with a
deliberately bad throwaway value on the command line.

```bash
terraform apply -var='db_password=Bad@Pass/1234'
```

`-var` sets a variable for this one command and wins over the environment variable. The `@` and `/`
characters are what RDS refuses. Type `yes`.

**Expected output (yours will differ):**
```
│ Error: creating RDS DB Instance (survive-...): InvalidParameterValue:
│ The parameter MasterUserPassword is not a valid password. Only printable ASCII
│ characters besides '/', '@', '"', ' ' may be used.
```

**What the message is telling you:** the subnet group and parameter group were now fine; only the
password was rejected. RDS forbids `/`, `@`, `"`, and spaces in the master password. The fix is a
password using letters and digits, which your `TF_VAR_db_password` already is.

Prove no database was created, in AWS itself.

```bash
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'survive-')].DBInstanceIdentifier" --output text
```

**Expected output (yours will differ):**
```
(no output)
```

**Check it worked:** no output means no database exists. You have now seen all three failures, and
each one named its own cause in the first line.

---

## Step 6: Clean up so nothing is left

On **tf-lab-1**, as **ec2-user**, destroy what the failed applies did create (the free subnet group
and parameter group).

```bash
terraform destroy
```

Type `yes`.

**Expected output (yours will differ):**
```
aws_db_subnet_group.survive: Destroying...
aws_db_parameter_group.survive: Destroying...
...
Destroy complete! Resources: 2 destroyed.
```

Remove the scratch folder and clear the password from this terminal.

```bash
cd ~ && rm -rf ~/survive-rds
```

```bash
unset TF_VAR_db_password
```

**Check it worked:** `Destroy complete!` appeared and the folder is gone. If your destroy listed an
`aws_db_instance`, that is expected only if you completed an apply by mistake - let it finish.

---

## What you practised

- Using the AWS CLI to look up valid engine versions and parameter group families before writing code.
- Reading the first line of an RDS error to find the exact cause: subnet AZ coverage, parameter
  group family, or an illegal password character.
- Knowing that `validate` passes on all three because they are value errors, and that a failed
  apply does not roll back what already succeeded.
- Cleaning up with `terraform destroy` and proving with the AWS CLI that no database was left.
