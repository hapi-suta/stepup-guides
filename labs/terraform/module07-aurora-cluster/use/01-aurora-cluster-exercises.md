# Use: Aurora Cluster with Terraform Exercises (25 min)

These exercises build on the BUILD tutorial, where you created an Aurora PostgreSQL cluster with a
subnet group, one `aws_rds_cluster`, and two `aws_rds_cluster_instance` nodes (a writer and a
reader). You should already have:

- A project directory with `variables.tf`, `main.tf`, and `outputs.tf`
- A successful `terraform apply` (4 resources added)
- Both instances showing `available` in the AWS CLI

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. AWS authentication is keyless: the server's instance role provides
credentials, so you never type an AWS access key.

**Cost warning:** two `db.t3.medium` Aurora instances are a real, billable cluster and they are
probably still running from the tutorial. Exercises 1 to 3 only read or `plan`. **Exercise 4
destroys the cluster - do not skip it.**

Your tutorial files may live in `~/terraform-lab` or in `/home/ec2-user/tf-lab`. Use whichever
folder holds your `main.tf`; every command below is the same in both.

---

## Exercise 1: See the cluster and instance split in state (6 min)

**Goal:** Prove to yourself that one Aurora "database" is two kinds of Terraform resource.

On **tf-lab-1**, as **ec2-user**, move into your project folder.

```bash
cd ~/terraform-lab
```

Terraform needs the master password on every plan because `db_master_password` has no default.
Store it in an environment variable for this terminal only.

```bash
read -s -p "DB master password (hidden): " TF_VAR_db_master_password
```

`read -s` reads what you type without showing it. `-p` prints the prompt. Terraform treats any
variable named `TF_VAR_<name>` as the value of the Terraform variable `<name>`.

```bash
export TF_VAR_db_master_password
```

`export` makes the value visible to `terraform`. It lives only in this terminal session and is not
written to any file. Use the same password as the tutorial.

Now list what Terraform manages.

```bash
terraform state list
```

**Expected output (yours will differ):**
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_subnet_group.aurora
aws_rds_cluster.aurora
aws_rds_cluster_instance.aurora[0]
aws_rds_cluster_instance.aurora[1]
```

**Check it worked:** you see one `aws_rds_cluster` and two `aws_rds_cluster_instance` entries. If
the list is empty, the tutorial resources were already destroyed - run the apply from the tutorial
again (10 to 15 minutes) so the exercises have something to inspect, and remember Exercise 4.

Show the two endpoints the cluster gives you.

```bash
terraform output
```

**Expected output (yours will differ):**
```
cluster_endpoint = "aurora-....cluster-xxxx.us-east-1.rds.amazonaws.com"
cluster_id = "aurora-..."
instance_ids = [ ... ]
reader_endpoint = "aurora-....cluster-ro-xxxx.us-east-1.rds.amazonaws.com"
```

- The writer endpoint contains `cluster-` and the reader endpoint contains `cluster-ro-`. Which one
  would your application use for `INSERT` statements, and which for reporting queries?
- Neither hostname names an instance. Why is that a good thing when a failover happens?

---

## Exercise 2: Predict what `count` does (6 min)

**Goal:** Understand that `count` creates numbered copies, and that index numbers are not roles.

On **tf-lab-1**, as **ec2-user**, make a safe backup of your configuration.

```bash
cp main.tf main.tf.bak
```

First find out which instance is the writer right now, straight from AWS.

```bash
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'aurora-')].DBClusterMembers[].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}" --output table
```

`DBClusterMembers` lists the instances in the cluster, and `IsClusterWriter` is `True` for the
writer. `--output table` prints it as a table.

**Expected output (yours will differ):**
```
-------------------------------------------------
|               DescribeDBClusters              |
+------------------------------------+----------+
|              Instance              |  Writer  |
+------------------------------------+----------+
|  aurora-20261025193152319000000003 |  False   |
|  aurora-20261025193152320300000004 |  True    |
+------------------------------------+----------+
```

Now open `main.tf` in VS Code and change `count = 2` to `count = 1`. Save. **Write down** your
prediction: which instance will Terraform remove, `[0]` or `[1]`? Is it the writer?

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_rds_cluster_instance.aurora[1] will be destroyed
  # (because index [1] is not in configuration)
  - resource "aws_rds_cluster_instance" "aurora" {
      ...
    }

Plan: 0 to add, 0 to change, 1 to destroy.
```

- Terraform always drops the highest index. Compare that to the table above. Is `[1]` the writer in
  your cluster? What would happen to the application if the writer were destroyed? (Think: failover.)
- Why is "instance number" a poor way to decide which node is the primary?

Now try the other direction: change `count = 1` to `count = 3` and plan again.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_rds_cluster_instance.aurora[2] will be created
  + resource "aws_rds_cluster_instance" "aurora" {
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

- This would add a second reader. What would it cost per hour, and what would it give you?

Restore your working file.

```bash
cp main.tf.bak main.tf
```

---

## Exercise 3: Why `ignore_changes = [engine_version]`? (5 min)

**Goal:** See how a `lifecycle` block changes what a plan reports.

On **tf-lab-1**, as **ec2-user**, check which engine version AWS says the cluster is running.

```bash
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'aurora-')].EngineVersion" --output text
```

**Expected output (yours will differ):**
```
15.10
```

Open `main.tf` in VS Code. In the `aws_rds_cluster` block only, change `engine_version` to a
different 15.x value, for example `"15.12"`. Save. Predict first: will Terraform plan an upgrade?

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

- You edited the version but there is no change. Which line in the cluster block caused that?
- That line is convenient because AWS can move a minor version on its own. What is the danger -
  if you *want* Terraform to upgrade the engine, what happens when this line is present?

Restore your working file.

```bash
cp main.tf.bak main.tf
```

---

## Exercise 4: Destroy the cluster (8-12 min)

**Goal:** Remove the billable cluster and prove it is gone. Aurora instances bill by the hour.

On **tf-lab-1**, as **ec2-user**, read what a destroy would remove, without removing anything.

```bash
terraform plan -destroy
```

**Expected output (yours will differ):**
```
  # aws_db_subnet_group.aurora will be destroyed
  # aws_rds_cluster.aurora will be destroyed
  # aws_rds_cluster_instance.aurora[0] will be destroyed
  # aws_rds_cluster_instance.aurora[1] will be destroyed
  ...
Plan: 0 to add, 0 to change, 4 to destroy.
```

Now destroy.

```bash
terraform destroy
```

Type `yes` when prompted. Terraform removes the instances first, then the cluster, then the subnet
group. It knows this order because the instances refer to the cluster. This takes several minutes.

**Expected output (yours will differ):**
```
aws_rds_cluster_instance.aurora[0]: Destroying...
aws_rds_cluster_instance.aurora[1]: Still destroying... [02m00s elapsed]
...
aws_rds_cluster.aurora: Destruction complete after ...
Destroy complete! Resources: 4 destroyed.
```

Confirm in AWS itself that nothing remains.

```bash
aws rds describe-db-clusters --region us-east-1 --query "DBClusters[?starts_with(DBClusterIdentifier,'aurora-')].DBClusterIdentifier" --output text
```

**Expected output (yours will differ):**
```
(no output)
```

**Check it worked:** the AWS query prints nothing. Because the config has
`skip_final_snapshot = true`, no snapshot was kept either. Finally, clear the password from this
terminal.

```bash
unset TF_VAR_db_master_password
```

---

## What you should be able to say now

- That `aws_rds_cluster` (endpoints, credentials, engine) and `aws_rds_cluster_instance` (the
  compute nodes) are always separate resources, and why that matters for `terraform import`.
- The difference between the writer endpoint and the reader endpoint.
- That `count` indexes are not roles: Terraform removes the highest index, which may be the writer.
- What `lifecycle { ignore_changes = [engine_version] }` hides from a plan.
- Why every practice session with Aurora ends with `terraform destroy`.
