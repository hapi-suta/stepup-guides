# Use: Secrets and Configuration Exercises (20 min)

These exercises build on the BUILD tutorial, where you created a PostgreSQL RDS instance with a
random password stored in AWS Secrets Manager, plus a parameter group holding your tuning. You
should already understand:

- Why `random_password` + `aws_secretsmanager_secret_version` is better than typing a password
- That the parameter group (`log_min_duration_statement`, `log_connections`) is database config
  written as code

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. These exercises are a thinking partner: you run the commands and
explain what you see. Everything here runs in a small scratch folder and creates **nothing
billable** - the only provider used is `random`, which makes a value locally and never calls AWS.

---

## Exercise 1: Find the leaked password (5 min)

**Goal:** Learn to spot a hardcoded secret in a `.tf` file by eye and with `grep`.

On **tf-lab-1**, as **ec2-user**, create a scratch folder.

```bash
mkdir -p ~/terraform-lab/secrets-practice && cd ~/terraform-lab/secrets-practice
```

`mkdir -p` creates the folder (and does not complain if it exists). `cd` moves you into it.

Create a sample file that shows **bad habits**. We name it `.txt` so Terraform ignores it. Open it
with vi.

```bash
vi audit-sample.txt
```

Press `i`, paste this, then press `Esc` and type `:wq` to save and quit:

```
resource "aws_db_instance" "orders" {
  identifier = "orders-prod"
  username   = "dbadmin"
  password   = "Summer2026!"
}

resource "aws_db_instance" "billing" {
  identifier = "billing-prod"
  username   = "dbadmin"
  password   = var.billing_password
}

resource "aws_db_instance" "reports" {
  identifier = "reports-prod"
  username   = "dbadmin"
  password   = random_password.reports.result
}
```

Now hunt for literal passwords. Search for any `password =` line whose value starts with a quote.

```bash
grep -n 'password *= *"' audit-sample.txt
```

`grep -n` prints matching lines with their line numbers. The pattern means "the word password, an
equals sign, then an opening quote" - which is exactly what a hardcoded string looks like.

**Expected output (yours will differ):**
```
4:  password   = "Summer2026!"
```

- Only one of the three databases matches. Why are `var.billing_password` and
  `random_password.reports.result` not flagged - what is different about them?
- If this file was committed to Git last month and removed today, is the password safe? (Think
  about Git history.)
- What would you do first if you found this in a real repository: rotate the password, or delete
  the line? Why that order?

---

## Exercise 2: See what `sensitive` hides - and what it does not (10 min)

**Goal:** Understand that `sensitive = true` hides a value from the screen, but the value is still
written in the state file.

On **tf-lab-1**, as **ec2-user**, still in `~/terraform-lab/secrets-practice`, create a tiny
project.

```bash
vi main.tf
```

Press `i`, paste this, then `Esc` and `:wq`:

```
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_password" "demo" {
  length  = 16
  special = false
}

output "demo_password" {
  value = random_password.demo.result
}
```

Download the `random` provider.

```bash
terraform init
```

**Expected output (yours will differ):**
```
Initializing provider plugins...
- Installing hashicorp/random v3.x.x...
- Installed hashicorp/random v3.x.x (signed by HashiCorp)
...
Terraform has been successfully initialized!
```

Now plan. Notice we forgot to mark the output sensitive.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: Output refers to sensitive values
│
│   on main.tf line 16:
│   16: output "demo_password" {
│
│ To represent that this is intended, mark the output as sensitive...
╵
```

- Terraform refused to continue. The provider marks `result` as sensitive. Is this Terraform
  protecting you, or getting in your way?

Fix it. Open `main.tf` again, add `sensitive = true` inside the output block so it reads:

```bash
vi main.tf
```

```
output "demo_password" {
  value     = random_password.demo.result
  sensitive = true
}
```

Apply (type `yes` when prompted).

```bash
terraform apply
```

**Expected output (yours will differ):**
```
random_password.demo: Creation complete after 0s [id=none]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

demo_password = <sensitive>
```

Now look inside the state file, which is where Terraform keeps its memory.

```bash
grep -n '"result"' terraform.tfstate
```

`terraform.tfstate` is a plain JSON file. `grep` finds the line holding the generated value.

**Expected output (yours will differ):**
```
20:            "result": "Kx9...",
```

(The real file shows the whole password in clear text.)

**Check it worked:** The screen said `<sensitive>`, yet the state file holds the real value.

- Who can read `terraform.tfstate` on a real team, and what does that mean for how you store it?
  (Think back to remote backends from the state module.)
- The RDS resource also stores `password` in state. So does Secrets Manager remove the password
  from state, or only from your `.tf` code? What RDS option would keep it out of state entirely?

---

## Exercise 3: Config is code too - read a parameter group (5 min)

**Goal:** See that DBA tuning (not just secrets) belongs in version-controlled files.

Think through this snippet from the BUILD tutorial. You do not need to run anything.

```
resource "aws_db_parameter_group" "appdb" {
  name_prefix = "appdb-"
  family      = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
}
```

- What does `log_min_duration_statement = 500` do to the PostgreSQL log, and why would a DBA want
  it on from day one?
- What breaks if `family` says `postgres15` but the instance runs PostgreSQL 16?
- A teammate changes this value by hand in the console at 2 AM. How would Terraform tell you,
  and which command shows it without changing anything? (Hint: you used it in the core loop
  module.)

---

## Clean up

On **tf-lab-1**, as **ec2-user**, still in `~/terraform-lab/secrets-practice`, remove what
Terraform created (it is only a local random value, but we always destroy).

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
random_password.demo: Destroying... [id=none]
random_password.demo: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

Then delete the scratch folder, including the state file that held the password.

```bash
cd ~/terraform-lab && rm -rf ~/terraform-lab/secrets-practice
```

**Check it worked:** `ls ~/terraform-lab` no longer shows `secrets-practice`.

---

## What you should be able to say now

- How to spot a hardcoded secret in a `.tf` file and why deleting it from Git is not enough.
- That `sensitive = true` hides a value from the screen but **not** from the state file.
- Why the state file must be treated like a password vault.
- Why database tuning (parameter groups) is written as code just like secrets are generated by code.
