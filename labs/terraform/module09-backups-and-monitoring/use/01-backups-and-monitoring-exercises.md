# Use: Backups and Monitoring Exercises (25 min)

These exercises build on the BUILD tutorial, where you wrote an RDS PostgreSQL instance with
explicit backup settings (retention, backup window, maintenance window), CloudWatch log exports,
and a low-storage CloudWatch alarm. You should already have:

- The module 9 project (`main.tf`, `variables.tf`, `outputs.tf`) in `~/terraform-lab`. If your
  BUILD files live in `~/tf-lab`, use that folder wherever you see `~/terraform-lab`.
- The database from the BUILD still running, or the willingness to re-create it (about 5 minutes).

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. These exercises are a thinking partner: you run the commands and
explain what you see. Exercises 1 to 3 only **read** and **plan**. The database is billable, so you
destroy it at the end.

---

## Exercise 0: Make sure the database exists (5 min, mostly waiting)

**Goal:** Start from a known state.

On **tf-lab-1**, as **ec2-user**, move into the project and check what Terraform is tracking.

```bash
cd ~/terraform-lab && terraform state list
```

**Expected output (yours will differ):**
```
data.aws_subnets.default
data.aws_vpc.default
aws_cloudwatch_metric_alarm.rds_low_storage
aws_db_instance.appdb
aws_db_subnet_group.appdb
```

If `aws_db_instance.appdb` is listed, skip to Exercise 1. If the list is empty, supply the master
password for this terminal session. `read -s` types nothing on screen, so nobody can read it over
your shoulder; type a password of your choosing (8+ characters, not starting with `/`) and press
Enter.

```bash
read -s -p "DB password: " TF_VAR_db_password && export TF_VAR_db_password
```

Then create the database and alarm (type `yes` when prompted; it takes about 5 minutes).

```bash
terraform apply
```

**Check it worked:** You see `Apply complete!` and the output `db_instance_status = "available"`.

---

## Exercise 1: Read the windows like an on-call DBA (7 min)

**Goal:** Be able to say, from the file alone, when your data is backed up and when it is patched.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab`, pull out the lines that matter.

```bash
grep -nE 'backup_|maintenance_window|threshold|evaluation_periods|period ' main.tf
```

`grep -nE` searches with an extended pattern and shows line numbers. The `|` means "or".

**Expected output (yours will differ):**
```
53:  backup_retention_period = 7
54:  backup_window           = "03:00-04:00"
55:  copy_tags_to_snapshot   = true
57:  maintenance_window = "sun:04:30-sun:05:30"
72:  threshold           = 2147483648
73:  evaluation_periods  = 3
74:  period              = 300
```

Now ask AWS what it actually has, to compare with the file (read-only).

```bash
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].[BackupRetentionPeriod,PreferredBackupWindow,PreferredMaintenanceWindow]" --output text
```

**Expected output (yours will differ):**
```
7	03:00-04:00	sun:04:30-sun:05:30
```

Answer these for yourself, then explain them to the tutor:

- Are the backup window and the maintenance window in UTC or your local time? What is the danger
  of assuming local time?
- Do the two windows overlap? Why does it matter that they do not?
- With a retention of 7, how far back in time can you restore this database? What would
  `backup_retention_period = 0` do to that ability?
- The threshold is `2147483648`. How many GiB is that, and why is it written in bytes?

---

## Exercise 2: Predict the plan for a retention change (7 min)

**Goal:** Practise reading a plan for a backup change before it can hurt anything.

On **tf-lab-1**, as **ec2-user**, make a safe copy first.

```bash
cp ~/terraform-lab/main.tf ~/terraform-lab/main.tf.bak
```

Open `main.tf` in VS Code (or `vi ~/terraform-lab/main.tf`) and change
`backup_retention_period = 7` to `backup_retention_period = 14`. Save the file.

Before running anything, **write down**: will Terraform create, change in place, or replace the
database? Now plan. (If you opened a fresh terminal, run the `read -s` command from Exercise 0 first
so the password variable is set.)

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_db_instance.appdb will be updated in-place
  ~ resource "aws_db_instance" "appdb" {
      ~ backup_retention_period = 7 -> 14
        # (... unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

- Did your prediction match? Why is this change safe to apply on a live database?
- The config has `apply_immediately = true`. What would happen on a database where it is `false`?
- You are not applying this. Restore your file and confirm the plan is clean again:

```bash
cp ~/terraform-lab/main.tf.bak ~/terraform-lab/main.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

**Check it worked:** You see `No changes.` again.

---

## Exercise 3: Who gets woken up? (6 min)

**Goal:** Notice that an alarm with no action is a silent alarm.

On **tf-lab-1**, as **ec2-user**, ask CloudWatch about the alarm you built (read-only).

```bash
aws cloudwatch describe-alarms --region us-east-1 --alarm-names rds-appdb-low-free-storage --query "MetricAlarms[0].[AlarmName,StateValue,AlarmActions]" --output json
```

`--query` picks the name, current state, and the list of actions to take when it fires.

**Expected output (yours will differ):**
```
[
    "rds-appdb-low-free-storage",
    "OK",
    []
]
```

- The last item is an empty list. If free storage dropped below 2 GiB tonight, what would happen,
  and who would find out?
- Which AWS service would you attach in `alarm_actions` to page the team?
- The alarm uses `evaluation_periods = 3` and `period = 300`. How long must storage stay low
  before it fires, and what false alarm does that prevent?
- Why is `treat_missing_data = "notBreaching"` a judgement call? When would you choose
  `"breaching"` instead?

---

## Clean up

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab`, destroy the database and alarm so nothing
keeps billing. This takes several minutes.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
aws_cloudwatch_metric_alarm.rds_low_storage: Destruction complete after 0s
aws_db_instance.appdb: Destroying...
...
Destroy complete! Resources: 3 destroyed.
```

Remove the backup file and forget the password for this session.

```bash
rm -f ~/terraform-lab/main.tf.bak && unset TF_VAR_db_password
```

**Check it worked:** `terraform state list` returns nothing.

---

## What you should be able to say now

- Where retention, the backup window, and the maintenance window are set, and that all are UTC.
- Why backup and maintenance windows must not overlap, and what retention gives you (a restore
  point-in-time range).
- How to read a plan that changes a backup setting, and that it is an in-place update.
- Why an alarm with an empty `alarm_actions` tells nobody anything.
