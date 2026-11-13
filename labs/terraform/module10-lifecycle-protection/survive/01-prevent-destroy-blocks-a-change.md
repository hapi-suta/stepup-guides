# Survive: prevent_destroy blocks a change (25 min)

## The Scenario

A teammate renamed the database in Terraform (changed its identifier prefix from `appdb-` to
`orders-`) and opened a pull request. The pipeline failed on `terraform plan` with
`Instance cannot be destroyed`, and the teammate's message in chat is: "prevent_destroy is broken,
just turn it off so I can merge." You are the DBA reviewing it. Your job is to work out **why**
Terraform wants to destroy the database, decide whether to switch the protection off, and show
the second protection layer that guards the database even when Terraform is out of the picture.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. The database is billable until
you destroy it in Step 7.

---

## Step 1: Start from a working database

On **tf-lab-1**, as **ec2-user**, move into the module 10 project (use `~/tf-lab` instead if that
is where your BUILD files are).

```bash
cd ~/terraform-lab && terraform state list
```

If `aws_db_instance.appdb` is not listed, supply the master password for this session. `read -s`
hides what you type. Choose a password of 8+ characters that does not start with `/`.

```bash
read -s -p "DB password: " TF_VAR_db_password && export TF_VAR_db_password
```

Create it (type `yes`; about 5 minutes).

```bash
terraform apply
```

Make a safe copy of the working file.

```bash
cp ~/terraform-lab/main.tf ~/terraform-lab/main.tf.good
```

**Check it worked:** `terraform plan` says `No changes.`

---

## Step 2: Turn on both protection layers

There are two separate locks, and they work in different places:

- `prevent_destroy` lives in **Terraform** - it makes Terraform refuse a plan.
- `deletion_protection` lives in **AWS** - it makes RDS itself refuse a delete from anywhere.

On **tf-lab-1**, as **ec2-user**, open `main.tf`.

```bash
vi ~/terraform-lab/main.tf
```

Make two edits: change `deletion_protection = false` to `deletion_protection = true` in the main
resource body, and change `prevent_destroy = false` to `prevent_destroy = true` inside the
`lifecycle` block. Save and quit.

Apply (type `yes`). The apply only changes the AWS setting in place; it does not touch your data.

```bash
terraform apply
```

**Expected output (yours will differ):**
```
  ~ resource "aws_db_instance" "appdb" {
      ~ deletion_protection = false -> true
    }

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

Confirm AWS has the lock (read-only).

```bash
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].DeletionProtection" --output text
```

**Expected output (yours will differ):**
```
True
```

**Check it worked:** AWS prints `True`.

---

## Step 3: Reproduce the teammate's pull request

On **tf-lab-1**, as **ec2-user**, edit the identifier prefix.

```bash
vi ~/terraform-lab/main.tf
```

Change `identifier_prefix = "appdb-"` to `identifier_prefix = "orders-"` in the
`aws_db_instance` block. Save and quit, then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: Instance cannot be destroyed
│
│   on main.tf line 28:
│   28: resource "aws_db_instance" "appdb" {
│
│ Resource aws_db_instance.appdb has lifecycle.prevent_destroy set, but the
│ plan calls for this resource to be destroyed. To avoid this error and
│ continue with the plan, either disable lifecycle.prevent_destroy or reduce
│ the scope of the plan using the -target option.
╵
```

**What the message is telling you:** The teammate changed a plain name, yet Terraform says
"destroy". The identifier is a setting that **cannot be changed in place** - AWS can only get a
new name by building a new database. So Terraform's plan would be "destroy the old database,
create a new empty one" (shown as `-/+` and "forces replacement" in a plan). `prevent_destroy`
refused because the change would have deleted your data. The protection is not broken. It just
caught a dangerous change in a pull request.

---

## Step 4: Resist the two tempting shortcuts

Two ways to make the red error go away - and both are traps:

- **Set `prevent_destroy = false` and merge.** The next apply deletes the old database. Because
  `skip_final_snapshot = true` here, it deletes it with **no final backup**.
- **Follow the `-target` hint.** Targeting other resources only dodges the check. The database
  stays in a half-changed plan that someone else will apply later.

Before deciding, answer these:

- What was the teammate actually trying to achieve? (A nicer name.) Is that worth replacing a
  production database for?
- If a rename truly were required, what would a safe path look like? (Think: a snapshot, a new
  instance restored from it, a cut-over, and only then the old one removed.)
- Who should approve flipping a protection flag - the author of the change, or a reviewer?

For this ticket the right call is to **revert the rename**. Restore the working file.

```bash
cp ~/terraform-lab/main.tf.good ~/terraform-lab/main.tf
```

Then set the two protections to `true` again (the saved copy has them off).

```bash
vi ~/terraform-lab/main.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

**Check it worked:** The plan is clean and still names `appdb-` as the prefix with both flags `true`.

---

## Step 5: Show that the AWS lock holds without Terraform

`prevent_destroy` only stops **Terraform**. Someone with console or CLI access could delete the
database directly. Show that the second lock catches that.

On **tf-lab-1**, as **ec2-user**, capture the instance name in a variable and **check the lock is
on before going further**.

```bash
DBID=$(terraform output -raw db_instance_id)
```

`terraform output -raw` prints one output value with no quotes; `$( ... )` stores it in `DBID`.

```bash
aws rds describe-db-instances --region us-east-1 --db-instance-identifier "$DBID" --query "DBInstances[0].DeletionProtection" --output text
```

**Expected output (yours will differ):**
```
True
```

**STOP here if the answer is anything other than `True`.** The next command would then really
delete the database. Go back to Step 2.

Only if it printed `True`, attempt the delete in this separate step.

```bash
aws rds delete-db-instance --region us-east-1 --db-instance-identifier "$DBID" --skip-final-snapshot
```

**Expected output (yours will differ):**
```
An error occurred (InvalidParameterCombination) when calling the DeleteDBInstance
operation: Cannot delete protected DB Instance, please disable deletion protection
and try again.
```

**Check it worked:** AWS refused. Two independent locks now guard the database, one for Terraform
users and one for everyone else.

---

## Step 6: Do an intentional teardown in the right order

When you **do** mean to remove a protected database, you must lift both locks, in code, through a
normal reviewed change. On **tf-lab-1**, as **ec2-user**, edit `main.tf`.

```bash
vi ~/terraform-lab/main.tf
```

Set `deletion_protection = false` and `prevent_destroy = false`, save, and apply so AWS and
Terraform both learn the new setting. (Destroying with only `prevent_destroy` lifted would fail at
AWS, because the AWS lock is still on.)

```bash
terraform apply
```

**Expected output (yours will differ):**
```
~ deletion_protection = true -> false

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

---

## Step 7: Clean up

On **tf-lab-1**, as **ec2-user**, destroy everything so nothing keeps billing (several minutes).

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
aws_db_instance.appdb: Destroying...
...
Destroy complete! Resources: 2 destroyed.
```

Remove the practice copy and forget the password.

```bash
rm -f ~/terraform-lab/main.tf.good && unset DBID TF_VAR_db_password
```

**Check it worked:** `terraform state list` returns nothing.

---

## What you practised

- Reading why a harmless-looking edit (a rename) becomes a destroy plan: some attributes force
  replacement.
- Treating `Instance cannot be destroyed` as the safety working, not a bug to switch off.
- Spotting why `-target` and flipping the flag are shortcuts, not fixes.
- Using two independent locks: `prevent_destroy` in Terraform and `deletion_protection` in AWS.
- Gating a destructive command behind a check, and ordering an intentional teardown correctly.
- Ending a billable lab with `terraform destroy`.
