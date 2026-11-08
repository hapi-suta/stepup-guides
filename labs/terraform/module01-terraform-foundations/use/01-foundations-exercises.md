# Use: Terraform Foundations Exercises (20 min)

These exercises build on the BUILD tutorial, where you installed Terraform and initialised your
first AWS provider project in `~/terraform-lab`. You should already have:

- Terraform installed (you ran `terraform version` and saw `Terraform v1.9.x`)
- A project directory `~/terraform-lab` with a `main.tf` that configures the AWS provider
- A successful `terraform init` (the provider plugin downloaded) and `terraform validate`

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. These exercises are a thinking partner: you run the commands and
explain what you see. Nothing here creates billable AWS resources.

---

## Exercise 1: Read your own configuration out loud (5 min)

**Goal:** Be able to explain every line of the `main.tf` you wrote, because a DBA who cannot read
the code cannot trust it.

On **tf-lab-1**, as **ec2-user**, open your project folder in VS Code and show the file in the
terminal.

```bash
cat ~/terraform-lab/main.tf
```

**Expected output (yours will differ):**
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
...
```

Answer these for yourself, then explain them to the tutor:

- What does the `required_providers` block do, and why pin a `version`?
- What is the difference between the `terraform {}` block and the `provider "aws" {}` block?
- Where does Terraform get the AWS credentials from on this box? (Hint: you never typed a key -
  the instance role provides them.)

---

## Exercise 2: Prove the version pin works (5 min)

**Goal:** See that `terraform init` records exactly which provider version it installed.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab`:

```bash
cd ~/terraform-lab
```

Show the lock file Terraform wrote during init.

```bash
cat .terraform.lock.hcl
```

**Expected output (yours will differ):**
```
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.xx.x"
  constraints = "~> 5.0"
  hashes = [
    "h1:....",
  ]
}
```

- Why does Terraform write a lock file, and why should you commit it to Git?
- If a teammate runs `terraform init` next week and AWS has released a newer 5.x provider, which
  version do they get - the newest, or the one in this lock file? Why does that matter for a
  production database?

---

## Exercise 3: Make validate fail on purpose, then fix it (10 min)

**Goal:** Learn to read Terraform's error messages - the single most useful skill when you are
stuck.

On **tf-lab-1**, as **ec2-user**, make a safe backup of your file first.

```bash
cp ~/terraform-lab/main.tf ~/terraform-lab/main.tf.bak
```

Now open `main.tf` in VS Code (or with `vi ~/terraform-lab/main.tf`) and **delete the closing
brace `}`** of the `provider "aws"` block. Save the file.

Run validate.

```bash
terraform validate
```

**Expected output (yours will differ):**
```
╷
│ Error: Unclosed configuration block
│
│   on main.tf line 10, in provider "aws":
│   10: provider "aws" {
│
│ There is no closing brace for this block before the end of the file...
╵
```

- Which line number does Terraform point you to? Is that where the real problem is, or where it
  gave up reading?
- Restore your working file and confirm validate passes again:

```bash
cp ~/terraform-lab/main.tf.bak ~/terraform-lab/main.tf
```

```bash
terraform validate
```

**Expected output (yours will differ):**
```
Success! The configuration is valid.
```

**Check it worked:** You see `Success! The configuration is valid.` again.

---

## What you should be able to say now

- What Terraform is and why a DBA uses it instead of clicking in the console.
- What `init`, the provider plugin, and the lock file each do.
- How to read a Terraform error and find the real cause.
- Where this lab box gets its AWS permissions (the instance role - no keys on disk).
