# Survive: Aurora cluster failures (25 min)

## The Scenario

A teammate wrote Terraform for an Aurora PostgreSQL cluster with a custom cluster parameter group,
and it will not build. You hit three different failures in a row: a missing argument that Terraform
catches immediately, a cluster parameter group built for the wrong PostgreSQL version, and an
instance size Aurora does not offer. The second and third only appear when Terraform actually calls
AWS, and the third leaves a half-built cluster behind. Your job is to diagnose each one, fix it,
and finish with nothing billable left running.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. AWS authentication is keyless
(the instance role), so you never type an access key. This lab deliberately never creates an Aurora
**instance**, which is the part that costs real money. If you ever see an
`aws_rds_cluster_instance` finish creating, go straight to Step 6 and destroy.

---

## Step 1: Gather the facts you need

On **tf-lab-1**, as **ec2-user**, find the parameter group family that belongs to the engine
version you will use.

```bash
aws rds describe-db-engine-versions --engine aurora-postgresql --engine-version 15.10 --query "DBEngineVersions[0].DBParameterGroupFamily" --output text --region us-east-1
```

`describe-db-engine-versions` returns details for one Aurora PostgreSQL version. The query keeps
only the parameter group family.

**Expected output (yours will differ):**
```
aurora-postgresql15
```

If `15.10` has been retired when you run this, list current versions with
`aws rds describe-db-engine-versions --engine aurora-postgresql --query "DBEngineVersions[?starts_with(EngineVersion,'15.')].EngineVersion" --output text --region us-east-1`
and use one of those wherever this guide says `15.10`.

Note the family you got. Now create the scratch project.

```bash
mkdir -p ~/survive-aurora && cd ~/survive-aurora
```

---

## Step 2: Build the "broken" project and meet failure 1

On **tf-lab-1**, as **ec2-user**, create the variables file with vi.

```bash
vi variables.tf
```

Press `i`, paste this, then press `Esc` and type `:wq` to save and quit:

```
variable "db_master_password" {
  type      = string
  sensitive = true
}
```

Now create `main.tf`.

```bash
vi main.tf
```

Press `i`, paste this, then `Esc` and `:wq`:

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
  subnet_ids  = data.aws_subnets.default.ids
}

resource "aws_rds_cluster_parameter_group" "survive" {
  name_prefix = "survive-"
  family      = "aurora-postgresql14"

  parameter {
    name         = "log_min_duration_statement"
    value        = "500"
    apply_method = "immediate"
  }
}

resource "aws_rds_cluster" "survive" {
  cluster_identifier_prefix       = "survive-"
  engine                          = "aurora-postgresql"
  engine_version                  = "15.10"
  database_name                   = "appdb"
  master_username                 = "dbadmin"
  master_password                 = var.db_master_password
  db_subnet_group_name            = aws_db_subnet_group.survive.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.survive.name
  skip_final_snapshot             = true
}

resource "aws_rds_cluster_instance" "survive" {
  identifier_prefix  = "survive-"
  cluster_identifier = aws_rds_cluster.survive.id
  instance_class     = "db.t3.micro"
}
```

The file has **three planted mistakes**. Do not fix them yet. Set a valid password (letters and
digits only, your own choice) for this terminal.

```bash
read -s -p "DB master password (hidden): " TF_VAR_db_master_password
```

```bash
export TF_VAR_db_master_password
```

Initialise and validate.

```bash
terraform init
```

```bash
terraform validate
```

**Expected output (yours will differ):**
```
╷
│ Error: Missing required argument
│
│   on main.tf line ..., in resource "aws_rds_cluster_instance" "survive":
│   ...: resource "aws_rds_cluster_instance" "survive" {
│
│ The argument "engine" is required, but no definition was found.
╵
```

**What the message is telling you:** this one is a *structure* problem, so `validate` catches it
without calling AWS. An Aurora instance must say which engine it runs. Open `main.tf` with vi and
add this line inside the `aws_rds_cluster_instance` block, below `instance_class`:

```bash
vi main.tf
```

```
  engine             = aws_rds_cluster.survive.engine
```

Save and quit, then validate again.

```bash
terraform validate
```

**Expected output (yours will differ):**
```
Success! The configuration is valid.
```

**Notice:** validate now passes, yet two more mistakes remain. They are *value* errors, and only
AWS can reject a value.

---

## Step 3: Failure 2 - the cluster parameter group family

On **tf-lab-1**, as **ec2-user**, apply.

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
aws_rds_cluster_parameter_group.survive: Creation complete after 1s
│ Error: creating RDS Cluster (survive-...): InvalidParameterCombination:
│ The DB cluster parameter group ... family ... aurora-postgresql14 ...
│ does not match the engine version 15.10 ...
```

**What the message is telling you:** the parameter group itself was created fine (family
`aurora-postgresql14` is a valid family), but AWS refused to attach it to a version 15 cluster.
The family must match the engine's major version - compare it with what you found in Step 1.

Check what Terraform recorded. A failed apply does not roll back the pieces that succeeded.

```bash
terraform state list
```

**Expected output (yours will differ):**
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_subnet_group.survive
aws_rds_cluster_parameter_group.survive
```

Fix it. Change the family in `main.tf` to the one from Step 1.

```bash
vi main.tf
```

```
  family      = "aurora-postgresql15"
```

Save and quit. Terraform will replace the parameter group, which is fine because nothing uses it.

---

## Step 4: Failure 3 - the instance class, and a half-built cluster

On **tf-lab-1**, as **ec2-user**, apply again. This time the cluster itself is created, which takes
a few minutes.

```bash
terraform apply
```

Type `yes`.

**Expected output (yours will differ):**
```
aws_rds_cluster.survive: Still creating... [01m30s elapsed]
aws_rds_cluster.survive: Creation complete after 2m10s [id=survive-...]
│ Error: creating RDS Cluster Instance (survive-...): InvalidParameterCombination:
│ RDS does not support creating a DB instance with the following combination:
│ DBInstanceClass=db.t3.micro, Engine=aurora-postgresql, EngineVersion=15.10 ...
```

**What the message is telling you:** `db.t3.micro` is a size RDS PostgreSQL offers but Aurora
PostgreSQL does not. The cluster succeeded, the instance did not. Look at the damage: you now have
a cluster with **zero** instances, because the cluster and its instances are separate resources.

```bash
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'survive-')].{ID:DBClusterIdentifier,Status:Status,Instances:length(DBClusterMembers)}" --output table
```

`length(DBClusterMembers)` counts the instances attached to the cluster.

**Expected output (yours will differ):**
```
-----------------------------------------------------
|                 DescribeDBClusters                |
+-----------------------+------------+--------------+
|          ID           |  Instances |   Status     |
+-----------------------+------------+--------------+
|  survive-2026110...   |  0         |  available   |
+-----------------------+------------+--------------+
```

Now ask AWS directly which instance classes are orderable for this engine. First the bad one.

```bash
aws rds describe-orderable-db-instance-options --engine aurora-postgresql --engine-version 15.10 --db-instance-class db.t3.micro --query "length(OrderableDBInstanceOptions)" --region us-east-1
```

**Expected output (yours will differ):**
```
0
```

Zero means AWS offers no such combination. Now check the size the tutorial used.

```bash
aws rds describe-orderable-db-instance-options --engine aurora-postgresql --engine-version 15.10 --db-instance-class db.t3.medium --query "length(OrderableDBInstanceOptions)" --region us-east-1
```

**Expected output (yours will differ):**
```
1
```

Any number above 0 means the class is orderable. Fix `main.tf` with vi:

```bash
vi main.tf
```

```
  instance_class     = "db.t3.medium"
```

Save and quit. **Do not apply.** An applied `db.t3.medium` instance bills by the hour, and you have
already proved what you came to prove. Instead run a plan, which only shows what would happen.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_rds_cluster_instance.survive will be created
  + resource "aws_rds_cluster_instance" "survive" {
      + instance_class = "db.t3.medium"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

**Check it worked:** the plan adds exactly the one missing instance - the cluster is already there.
That is the signature of a failure in the instance half of an Aurora build.

---

## Step 5: Compare this with the "password" failure you know

The Aurora tutorial warned that Aurora rejects master passwords containing `@`, `/`, `"`, or spaces.
That error appears at cluster creation, before any instance exists - the same place family
mismatches appear. Write down for yourself: in which of the three failures above did a billable
resource get created, and which one was it? (Answer: none - the cluster alone has no instance hours,
but you still destroy it.)

---

## Step 6: Clean up so nothing is left

On **tf-lab-1**, as **ec2-user**, destroy the cluster, parameter group, and subnet group.

```bash
terraform destroy
```

Type `yes`. This takes a few minutes while the cluster is deleted.

**Expected output (yours will differ):**
```
aws_rds_cluster.survive: Destroying... [id=survive-...]
...
Destroy complete! Resources: 3 destroyed.
```

Confirm in AWS itself that no cluster is left.

```bash
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'survive-')].DBClusterIdentifier" --output text
```

**Expected output (yours will differ):**
```
(no output)
```

Remove the scratch folder and clear the password from this terminal.

```bash
cd ~ && rm -rf ~/survive-aurora
```

```bash
unset TF_VAR_db_master_password
```

**Check it worked:** `Destroy complete!` appeared and the AWS query printed nothing.

---

## What you practised

- Telling a `validate`-time error (a missing required argument) from `apply`-time value errors.
- Matching the cluster parameter group `family` to the Aurora engine's major version.
- Knowing Aurora offers different instance classes from RDS, and checking them with
  `describe-orderable-db-instance-options` before applying.
- Seeing why `aws_rds_cluster` and `aws_rds_cluster_instance` can fail independently, leaving a
  cluster with no instances.
- Cleaning up with `terraform destroy` and proving it with the AWS CLI.
