# Use: RDS PostgreSQL with Terraform Exercises (25 min)

These exercises build on the BUILD tutorial, where you wrote `variables.tf`, `outputs.tf`, and
`main.tf` and created a PostgreSQL RDS instance with a subnet group and a parameter group. You
should already have:

- A project directory with those three files and a successful `terraform apply` (3 resources added)
- A `db.t3.micro` PostgreSQL instance that showed `available` in the AWS CLI
- Comfort reading a `terraform plan` (`+` create, `~` change in place, `-/+` replace, `-` destroy)

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. AWS authentication is keyless: the server's instance role provides
credentials, so you never type an AWS access key.

**Cost warning:** your RDS instance is a real, billable database and it is probably still running
from the tutorial. Exercises 1 to 4 only use `plan`, which never changes anything. **Exercise 5
destroys the database - do not skip it.**

Your tutorial files may live in `~/terraform-lab` or in `/home/ec2-user/tf-lab`. Use whichever
folder holds your `main.tf`; every command below is the same in both.

---

## Exercise 1: Confirm what is running and set your password (5 min)

**Goal:** Know exactly what Terraform is managing before you change anything.

On **tf-lab-1**, as **ec2-user**, move into your project folder.

```bash
cd ~/terraform-lab
```

Terraform needs the database password every time it plans, because `db_password` has no default.
Rather than typing it into every command, store it in an environment variable for this terminal
only.

```bash
read -s -p "DB password (hidden): " TF_VAR_db_password
```

`read -s` reads what you type without showing it on screen. `-p` prints the prompt text. Terraform
automatically treats any variable named `TF_VAR_<name>` as the value for the Terraform variable
`<name>`.

```bash
export TF_VAR_db_password
```

`export` makes the variable visible to the `terraform` command. It lives only in this terminal
session and is never written to a file.

**Expected output (yours will differ):**
```
DB password (hidden):
```

Use the **same password** you used in the tutorial (letters and digits only). Now list what
Terraform manages.

```bash
terraform state list
```

**Expected output (yours will differ):**
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_instance.appdb
aws_db_parameter_group.appdb
aws_db_subnet_group.appdb
```

**Check it worked:** you see `aws_db_instance.appdb`. If the list is empty, the tutorial resources
were already destroyed - run the apply from the tutorial again (about 7 minutes) so the later
exercises have something to compare against, and remember Exercise 5 at the end.

- The `data.` lines are read-only lookups. Why does a DBA not worry about those being "destroyed"?
- Which of the three real resources must exist first, and which depends on the other two?

---

## Exercise 2: Predict an in-place change (5 min)

**Goal:** Learn which edits are gentle (in place) and what "gentle" still means for a live database.

On **tf-lab-1**, as **ec2-user**, make a safe backup of your configuration first.

```bash
cp main.tf main.tf.bak
```

Open `main.tf` in VS Code and change `instance_class` from `"db.t3.micro"` to `"db.t3.small"`.
Save the file. Before running anything, **write down** your prediction: create, change, replace,
or destroy? How many resources?

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_db_instance.appdb will be updated in-place
  ~ resource "aws_db_instance" "appdb" {
      ~ instance_class = "db.t3.micro" -> "db.t3.small"
        ...
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

- The config has `apply_immediately = true`. What would that mean for the running database when
  this change is applied? (Think: a resize needs a restart.)
- If `apply_immediately` were `false`, when would AWS apply the change instead? Which setting would
  you prefer on a production primary, and why?

Restore your working file.

```bash
cp main.tf.bak main.tf
```

---

## Exercise 3: Predict a replacement - the dangerous one (5 min)

**Goal:** Spot `-/+` (destroy and recreate) before it destroys a database.

On **tf-lab-1**, as **ec2-user**, open `main.tf` and change `db_name` from `"appdb"` to
`"salesdb"`. Save. Predict first: in place, or replace?

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_db_instance.appdb must be replaced
-/+ resource "aws_db_instance" "appdb" {
      ~ db_name = "appdb" -> "salesdb" # forces replacement
        ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

- Find the words `# forces replacement`. Which attribute caused it?
- The config has `skip_final_snapshot = true`. If you applied this plan, what would happen to the
  data in `appdb`? Which two settings would you change before ever allowing this on a real system?
  (Name them: one stops accidental deletion, one keeps a last backup.)

Restore your working file and prove the plan is clean again.

```bash
cp main.tf.bak main.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

**Check it worked:** you see `No changes.` again.

---

## Exercise 4: Where does the password really live? (5 min)

**Goal:** Understand that `sensitive = true` hides a value from the screen, not from the state file.

On **tf-lab-1**, as **ec2-user**, ask Terraform to show the instance details and look for the
password.

```bash
terraform state show aws_db_instance.appdb | grep -i password
```

`grep -i password` keeps only lines containing the word "password", ignoring upper or lower case.

**Expected output (yours will differ):**
```
    password                              = (sensitive value)
```

Terraform hides it on screen. Now count how many times the word appears inside the raw state file
- this prints a number, not the password itself.

```bash
grep -c '"password"' terraform.tfstate
```

`-c` prints only the count of matching lines.

**Expected output (yours will differ):**
```
1
```

- A count of 1 means the password is stored in the state file. Who can read `terraform.tfstate` on
  this server? What does that tell you about where state files must be kept in a real team?
- You will move state to an encrypted S3 bucket in the state module and keep secrets out of
  config in the secrets module. Why is `-var` on the command line only a partial answer?

---

## Exercise 5: Destroy the database (5-8 min)

**Goal:** Remove the billable database and prove it is gone. RDS bills by the hour while it exists.

On **tf-lab-1**, as **ec2-user**, first read what a destroy would remove, without removing it.

```bash
terraform plan -destroy
```

**Expected output (yours will differ):**
```
  # aws_db_instance.appdb will be destroyed
  # aws_db_parameter_group.appdb will be destroyed
  # aws_db_subnet_group.appdb will be destroyed
  ...
Plan: 0 to add, 0 to change, 3 to destroy.
```

Now destroy.

```bash
terraform destroy
```

Type `yes` when prompted. Deleting an RDS instance takes a few minutes.

**Expected output (yours will differ):**
```
aws_db_instance.appdb: Destroying... [id=db-...]
aws_db_instance.appdb: Still destroying... [01m00s elapsed]
...
Destroy complete! Resources: 3 destroyed.
```

Confirm the database no longer exists in AWS itself (not just in Terraform).

```bash
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].DBInstanceIdentifier" --output text
```

**Expected output (yours will differ):**
```
(no output)
```

**Check it worked:** the AWS query prints nothing, and `terraform state list` shows only
`data.` lines or nothing. Finally, clear the password from this terminal.

```bash
unset TF_VAR_db_password
```

---

## What you should be able to say now

- The dependency chain behind an RDS instance: subnet group and parameter group first, instance last.
- The difference between an in-place change (`~`, such as a resize) and a replacement (`-/+`, such
  as changing `db_name`), and why replacement can mean data loss.
- What `apply_immediately`, `skip_final_snapshot`, and `deletion_protection` each control.
- That `sensitive = true` hides a value from the screen but the state file still holds it.
- Why every practice session with RDS ends with `terraform destroy`.
