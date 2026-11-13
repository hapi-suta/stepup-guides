# Survive: Overlapping windows and the silent alarm (25 min)

## The Scenario

An auditor asked your team two questions: "Can you prove you can restore this database to any
point in the last two weeks?" and "How do you find out when the disk is nearly full?" Your
teammate tried to answer by editing the Terraform config this morning. The change went through
`terraform plan` happily, then failed at `apply`. And when you looked at the monitoring, you found
the storage alarm exists but has never notified anyone. You need to fix the backup settings and
make the alarm actually reach a human.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. The database and alarm are
billable until you destroy them in Step 7.

---

## Step 1: Start from a working database

On **tf-lab-1**, as **ec2-user**, move into the module 9 project (use `~/tf-lab` instead if that is
where your BUILD files are) and see what Terraform tracks.

```bash
cd ~/terraform-lab && terraform state list
```

If `aws_db_instance.appdb` is not in the list, supply the master password for this session. `read
-s` hides what you type. Choose any password of 8+ characters that does not start with `/`.

```bash
read -s -p "DB password: " TF_VAR_db_password && export TF_VAR_db_password
```

Then create it (type `yes`; about 5 minutes).

```bash
terraform apply
```

**Expected output (yours will differ):**
```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

Make a safe copy of the working file.

```bash
cp ~/terraform-lab/main.tf ~/terraform-lab/main.tf.good
```

**Check it worked:** `terraform plan` says `No changes.`

---

## Step 2: Reproduce the teammate's change

Open `main.tf` in vi.

```bash
vi ~/terraform-lab/main.tf
```

Change the maintenance window so it **overlaps** the backup window, and raise retention to 14.
The two lines should read:

```
  backup_retention_period = 14
  maintenance_window = "sun:03:30-sun:04:30"
```

(The backup window stays `03:00-04:00`, so 03:30 to 04:00 on Sunday now belongs to both.) Save and
quit with `Esc` then `:wq`.

---

## Step 3: Plan passes, apply fails

On **tf-lab-1**, as **ec2-user**, run a plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  ~ resource "aws_db_instance" "appdb" {
      ~ backup_retention_period    = 7 -> 14
      ~ maintenance_window         = "sun:04:30-sun:05:30" -> "sun:03:30-sun:04:30"
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Nothing looks wrong. Terraform checks the **shape** of the values, not whether AWS will accept the
combination. Now apply (type `yes`).

```bash
terraform apply
```

**Expected output (yours will differ):**
```
╷
│ Error: updating RDS DB Instance (appdb-...): InvalidParameterValue:
│ The backup window and maintenance window must not overlap.
│   with aws_db_instance.appdb,
│   on main.tf line 40, in resource "aws_db_instance" "appdb":
╵
```

**What the message is telling you:** AWS rejected the change at apply time. The plan could not
catch it because only AWS knows this rule. Because AWS refused the whole modification, the
retention change to 14 did not happen either. Prove it (read-only).

```bash
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].[BackupRetentionPeriod,PreferredMaintenanceWindow]" --output text
```

**Expected output (yours will differ):**
```
7	sun:04:30-sun:05:30
```

**Check it worked:** AWS still shows the old values. Knowing this stops you assuming the apply
half-worked.

---

## Step 4: Fix the windows and apply

On **tf-lab-1**, as **ec2-user**, move the maintenance window to a time **after** the backup window.

```bash
vi ~/terraform-lab/main.tf
```

Set:

```
  backup_retention_period = 14
  maintenance_window = "sun:04:30-sun:05:30"
```

Apply (type `yes`).

```bash
terraform apply
```

**Expected output (yours will differ):**
```
aws_db_instance.appdb: Modifying... [id=db-...]
aws_db_instance.appdb: Modifications complete after ...

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

Confirm in AWS.

```bash
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].[BackupRetentionPeriod,PreferredBackupWindow,PreferredMaintenanceWindow]" --output text
```

**Expected output (yours will differ):**
```
14	03:00-04:00	sun:04:30-sun:05:30
```

**Check it worked:** Retention is `14` and the windows no longer overlap. You can now truthfully
tell the auditor you can restore to any point in the last 14 days.

---

## Step 5: Find the silent alarm

On **tf-lab-1**, as **ec2-user**, look at what the alarm does when it fires.

```bash
aws cloudwatch describe-alarms --region us-east-1 --alarm-names rds-appdb-low-free-storage --query "MetricAlarms[0].[StateValue,AlarmActions]" --output json
```

**Expected output (yours will differ):**
```
[
    "OK",
    []
]
```

`AlarmActions` is empty. The alarm would change colour on a dashboard nobody is watching, and
nobody would be told. That is monitoring that looks done but is not.

---

## Step 6: Make the alarm reach a human

On **tf-lab-1**, as **ec2-user**, open `main.tf`.

```bash
vi ~/terraform-lab/main.tf
```

Add an SNS topic (a free notification channel) at the bottom of the file:

```
resource "aws_sns_topic" "dba_alerts" {
  name = "dba-alerts-lab"
}
```

Then, inside the `aws_cloudwatch_metric_alarm` block, change `alarm_actions = []` to:

```
  alarm_actions = [aws_sns_topic.dba_alerts.arn]
```

Save and quit, then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_cloudwatch_metric_alarm.rds_low_storage will be updated in-place
  ~ alarm_actions = [
      + (known after apply),
    ]
  # aws_sns_topic.dba_alerts will be created

Plan: 1 to add, 1 to change, 0 to destroy.
```

Apply (type `yes`).

```bash
terraform apply
```

**Expected output (yours will differ):**
```
aws_sns_topic.dba_alerts: Creation complete after 1s [id=arn:aws:sns:us-east-1:...]

Apply complete! Resources: 1 added, 1 changed, 0 destroyed.
```

Verify the alarm now points at the topic.

```bash
aws cloudwatch describe-alarms --region us-east-1 --alarm-names rds-appdb-low-free-storage --query "MetricAlarms[0].AlarmActions" --output json
```

**Expected output (yours will differ):**
```
[
    "arn:aws:sns:us-east-1:...:dba-alerts-lab"
]
```

**Check it worked:** the alarm lists your topic ARN. (In real life you would also subscribe an
email address or paging tool to the topic; a topic with no subscribers is the same silence one step
later.)

---

## Step 7: Clean up

On **tf-lab-1**, as **ec2-user**, destroy everything so nothing keeps billing. This takes several
minutes.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
aws_sns_topic.dba_alerts: Destruction complete after 0s
aws_db_instance.appdb: Destruction complete after ...

Destroy complete! Resources: 4 destroyed.
```

Remove the practice copy and forget the password.

```bash
rm -f ~/terraform-lab/main.tf.good && unset TF_VAR_db_password
```

**Check it worked:** `terraform state list` returns nothing.

---

## What you practised

- Recognising that `plan` cannot catch a rule only AWS knows (overlapping backup and maintenance
  windows) and reading the apply-time error.
- Verifying in AWS, not assuming, that a failed apply changed nothing.
- Setting retention to meet a restore requirement and proving it from the CLI.
- Spotting an alarm with empty `alarm_actions` and wiring it to an SNS topic.
- Ending a billable lab with `terraform destroy`.
