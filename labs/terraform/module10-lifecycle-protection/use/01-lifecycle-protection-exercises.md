# Use: Lifecycle Protection Exercises (25 min)

These exercises build on the BUILD tutorial, where you added a `lifecycle` block to an RDS
PostgreSQL instance and saw `ignore_changes` and `prevent_destroy` in action. You should already
know:

- The three lifecycle rules by name: `ignore_changes`, `prevent_destroy`, `create_before_destroy`
- That the BUILD finished with `terraform destroy`, so you may need to re-create the database

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. The project folder is `~/terraform-lab` (use `~/tf-lab` instead if
that is where your BUILD files are). These exercises are a thinking partner: you run the commands
and explain what you see. Exercises 1 to 3 only **read** and **plan**. The database is billable,
so you destroy it at the end.

---

## Exercise 0: Make sure the database exists (5 min, mostly waiting)

**Goal:** Start from a known state.

On **tf-lab-1**, as **ec2-user**, check what Terraform is tracking.

```bash
cd ~/terraform-lab && terraform state list
```

**Expected output (yours will differ):**
```
data.aws_subnets.default
data.aws_vpc.default
aws_db_instance.appdb
aws_db_subnet_group.appdb
```

If `aws_db_instance.appdb` is listed, skip to Exercise 1. If the list is empty, supply the master
password for this terminal session. `read -s` hides what you type. Choose a password of 8+
characters that does not start with `/`.

```bash
read -s -p "DB password: " TF_VAR_db_password && export TF_VAR_db_password
```

Create the database (type `yes`; about 5 minutes).

```bash
terraform apply
```

**Check it worked:** You see `Apply complete! Resources: 2 added`.

---

## Exercise 1: Read the lifecycle block (4 min)

**Goal:** Be able to say what each line of protection does before you trust it.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab`, show the block.

```bash
grep -n -A8 'lifecycle' main.tf
```

`grep -n -A8` prints each match with line numbers plus the 8 lines after it, so you see the whole
block.

**Expected output (yours will differ):**
```
39:  lifecycle {
40-    ignore_changes = [
41-      password,
42-      engine_version,
43-    ]
44-
45-    prevent_destroy = false
46-  }
```

- In one sentence each: what does `ignore_changes` stop, and what does `prevent_destroy` stop?
- Why would a team choose to ignore `password` and `engine_version` specifically? (Think: who or
  what changes them outside Terraform?)
- Which of the three rules is **not** in this block, and which resources would you use it on?

---

## Exercise 2: Prove ignore_changes works (7 min)

**Goal:** See Terraform deliberately look away from an ignored attribute.

On **tf-lab-1**, as **ec2-user**, make a safe copy of your file.

```bash
cp ~/terraform-lab/main.tf ~/terraform-lab/main.tf.bak
```

Open `main.tf` and change `engine_version = "16.3"` to `engine_version = "16.4"`. Save the file.

```bash
vi ~/terraform-lab/main.tf
```

Before running anything, **write down**: will the plan show a change to the engine version?

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

The config and the real database now disagree about the version, yet Terraform reports nothing -
because `engine_version` is in the `ignore_changes` list.

- Was your prediction right? Why is this exactly what you want when AWS applies a minor upgrade
  overnight?
- What is the **cost** of this rule? If a teammate later sets the wrong version in the file,
  who will notice?

Restore the file.

```bash
cp ~/terraform-lab/main.tf.bak ~/terraform-lab/main.tf
```

**Check it worked:** `grep engine_version ~/terraform-lab/main.tf` shows `"16.3"` again.

---

## Exercise 3: Watch prevent_destroy refuse (7 min)

**Goal:** Read a destroy plan with and without protection.

On **tf-lab-1**, as **ec2-user**, first read what a destroy would do while protection is **off**.
This only plans; it deletes nothing.

```bash
terraform plan -destroy
```

**Expected output (yours will differ):**
```
  # aws_db_instance.appdb will be destroyed
  # aws_db_subnet_group.appdb will be destroyed

Plan: 0 to add, 0 to change, 2 to destroy.
```

Now turn protection on. Open `main.tf`, change `prevent_destroy = false` to `prevent_destroy = true`
inside the `lifecycle` block, and save.

```bash
vi ~/terraform-lab/main.tf
```

Plan the destroy again.

```bash
terraform plan -destroy
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
│ plan calls for this resource to be destroyed...
╵
```

- Terraform refused even to **plan** the deletion. Why is failing early better than failing at
  the prompt?
- The error also suggests using `-target`. Is following that hint a fix or a way around the
  safety? Who should decide?
- Think about three ways the database could still be deleted: (1) someone deletes the
  `resource` block from the file, (2) someone deletes it in the AWS console, (3) someone runs the
  AWS CLI. Which of these does `prevent_destroy` stop? Which AWS setting stops the other two?

---

## Clean up

First turn protection off again, because a protected resource cannot be destroyed. On **tf-lab-1**,
as **ec2-user**, restore your original file.

```bash
cp ~/terraform-lab/main.tf.bak ~/terraform-lab/main.tf
```

Then destroy everything so nothing keeps billing (several minutes).

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
rm -f ~/terraform-lab/main.tf.bak && unset TF_VAR_db_password
```

**Check it worked:** `terraform state list` returns nothing.

---

## What you should be able to say now

- What each of the three lifecycle rules does and which resources suit each.
- That `ignore_changes` makes Terraform blind to an attribute on purpose, and the price of that.
- That `prevent_destroy` stops Terraform plans only - not the console, the CLI, or removing the
  block.
- Why you must switch protection off in code before an intentional destroy.
