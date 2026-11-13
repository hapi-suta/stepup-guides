# Survive: Apply failures and configuration drift (12 min)

## The Scenario

Two things went wrong on your team this morning. First, a `terraform apply` failed halfway with an
AWS error. Second, someone changed a resource by hand in the AWS Console, and now Terraform and
reality disagree - this is called **drift**. You need to diagnose both and get back to a state
where the code is the source of truth.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. Nothing here leaves billable
resources running if you finish Step 4.

---

## Step 1: Cause an apply to fail on a bad value

On **tf-lab-1**, as **ec2-user**, open `~/terraform-lab/main.tf`. Find your resource and give it a
name AWS will reject - for example an S3 bucket name with capital letters and spaces, or set an
invalid instance type like `t3.enormous`. Save the file.

```bash
cd ~/terraform-lab && terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
│ Error: creating ... : InvalidParameterValue: ...
│   with aws_..., on main.tf line ...
```

**What happened:** `plan` passed because the syntax was fine, but AWS refused the value at
`apply` time. Read the error's first line - it names the AWS error and the exact resource.

---

## Step 2: Confirm nothing half-built was left behind

On **tf-lab-1**, as **ec2-user**, check what Terraform actually recorded.

```bash
terraform state list
```

**What to look for:** A failed create usually records nothing (empty output) or only the resources
that succeeded before the error. Terraform does not roll back the ones that already worked - knowing
this is what stops a DBA from assuming "the apply failed so nothing changed."

Fix the bad value in `main.tf` back to a valid one, save, and apply cleanly.

```bash
terraform apply
```

Type `yes`.

**Expected output (yours will differ):**
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

---

## Step 3: Simulate and detect drift

Someone changed the resource by hand. Simulate that by changing a tag directly with the AWS CLI
(this edits AWS without touching Terraform). On **tf-lab-1**, as **ec2-user**, first find the
resource id.

```bash
terraform state show aws_... | grep -i "id\|arn" | head
```

Now ask Terraform to compare its records against real AWS.

```bash
terraform plan -refresh-only
```

**Expected output (yours will differ):**
```
Note: Objects have changed outside of Terraform

  ~ resource "aws_..." "..." {
      ~ tags = { ... }
    }

This is a refresh-only plan...
```

**What this proves:** Terraform noticed reality no longer matches its state. `-refresh-only` is the
safe way to *see* drift without changing anything.

- Would a normal `terraform plan` have shown you the same drift? What would `terraform apply` then
  do - match AWS to the code, or the code to AWS?

---

## Step 4: Decide, then clean up

Drift has two cures: **re-apply** (force reality back to match the code) or **update the code** to
accept the change. For practice, re-apply so the code wins.

```bash
terraform apply
```

Type `yes`. Then destroy everything so nothing keeps costing money.

```bash
terraform destroy
```

Type `yes`.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 1 destroyed.
```

**Check it worked:** `terraform state list` returns nothing.

---

## What you practised

- Reading an `apply`-time AWS error and knowing `plan` cannot catch value rejections.
- Understanding that a failed apply does **not** roll back what already succeeded.
- Detecting drift safely with `terraform plan -refresh-only`.
- Choosing between re-applying (code wins) and updating code (reality wins).
