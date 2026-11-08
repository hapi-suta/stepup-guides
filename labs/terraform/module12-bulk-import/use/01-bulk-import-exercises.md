# Use: Bulk Import with import Blocks Exercises (25 min)

These exercises build on the BUILD tutorial, where you imported four hand-built resources (an RDS
instance, a subnet group, a parameter group and a security group) using `import {}` blocks and
`terraform plan -generate-config-out`. RDS takes about ten minutes to start and costs money, so
here you practise the **same workflow on two free resources** - two empty S3 buckets. You should
already have:

- Terraform 1.5 or newer (`import {}` blocks arrived in 1.5)
- Comfort with `init`, `plan`, `apply`, and `state list`
- The idea from the previous module: the plan for an import must show no destroy

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. AWS access is keyless through the instance role - you never type an
access key. These exercises are a thinking partner: you run the commands and explain what you see.
The two buckets are empty and removed at the end.

---

## Exercise 1: Create two "legacy" buckets by hand (4 min)

**Goal:** Make a small batch of resources outside Terraform to import in one go.

On **tf-lab-1**, as **ec2-user**, store your AWS account ID so bucket names are unique to you.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $ACCOUNT_ID
```

**Expected output (yours will differ):**
```
2036xxxxxxxx
```

Create two buckets with the AWS CLI. `s3api create-bucket` creates a bucket and `--bucket` names it.

```bash
aws s3api create-bucket --bucket bulk-a-$ACCOUNT_ID --region us-east-1
aws s3api create-bucket --bucket bulk-b-$ACCOUNT_ID --region us-east-1
```

**Expected output (yours will differ):**
```
{
    "Location": "/bulk-a-2036xxxxxxxx"
}
{
    "Location": "/bulk-b-2036xxxxxxxx"
}
```

**Check it worked:** You see two `Location` lines.

---

## Exercise 2: Declare the imports (6 min)

**Goal:** Write `import {}` blocks, which are a plan you can review before anything is adopted.

On **tf-lab-1**, as **ec2-user**, create a fresh folder.

```bash
mkdir -p ~/terraform-lab/bulk-practice && cd ~/terraform-lab/bulk-practice
```

Create `versions.tf` with vi.

```bash
vi versions.tf
```

Type this, then save and quit (`Esc`, then `:wq`):

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
```

Now create `imports.tf`.

```bash
vi imports.tf
```

Type this (replace `2036xxxxxxxx` with your real account ID), then save and quit:

```
import {
  to = aws_s3_bucket.a
  id = "bulk-a-2036xxxxxxxx"
}

import {
  to = aws_s3_bucket.b
  id = "bulk-b-2036xxxxxxxx"
}
```

- Each block has a `to` and an `id`. Which one is the address in your code and which is the real
  AWS name? How is this different from the arguments of the `terraform import` command?
- Why is a declared import easier to review in a pull request than a terminal command someone ran?

Initialise.

```bash
terraform init
```

---

## Exercise 3: Let Terraform write the resource blocks (8 min)

**Goal:** Use config generation instead of typing each `resource` block by hand.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab/bulk-practice`, ask Terraform to generate
the missing resource blocks. `-generate-config-out=generated.tf` reads each real object from AWS
and writes a starter `resource` block into the named file. The file must not already exist.

```bash
terraform plan -generate-config-out=generated.tf
```

**Expected output (yours will differ):**
```
aws_s3_bucket.a: Preparing import... [id=bulk-a-2036...]
aws_s3_bucket.b: Preparing import... [id=bulk-b-2036...]
...
Plan: 2 to import, 0 to add, 0 to change, 0 to destroy.

Terraform has generated configuration and written it to generated.tf. Please review the
configuration and edit it as necessary before adding it to version control.
```

Read what it wrote.

```bash
cat generated.tf
```

**Expected output (yours will differ):**
```
# __generated__ by Terraform
resource "aws_s3_bucket" "a" {
  bucket        = "bulk-a-2036..."
  force_destroy = null
  ...
}
...
```

- Which values did Terraform copy from AWS, and which are `null`? Why must you **review** generated
  code before trusting it?
- The summary says `2 to import`. What is the one number in that line you must keep at 0?

---

## Exercise 4: Apply the import, verify, and clean up (7 min)

**Goal:** Adopt both buckets, prove it worked, and remove them.

On **tf-lab-1**, as **ec2-user**, apply. This writes the buckets into state; it does not change AWS.

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
aws_s3_bucket.a: Importing... [id=bulk-a-2036...]
aws_s3_bucket.a: Import complete
...
Apply complete! Resources: 2 imported, 0 added, 0 changed, 0 destroyed.
```

Prove both are tracked and that a fresh plan is clean.

```bash
terraform state list
terraform plan
```

**Expected output (yours will differ):**
```
aws_s3_bucket.a
aws_s3_bucket.b
...
No changes. Your infrastructure matches the configuration.
```

- The `import` blocks are still in `imports.tf`. Why is that harmless now, and when would you
  delete them? (Hint: they only matter the first time.)

Now tear down. Because these are imported, destroy **really deletes the buckets**. That is what
you must remember about any imported database.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 2 destroyed.
```

Remove the practice folder.

```bash
cd ~/terraform-lab && rm -rf ~/terraform-lab/bulk-practice
```

**Check it worked:** `Destroy complete! Resources: 2 destroyed.` appears and
`aws s3api head-bucket --bucket bulk-a-$ACCOUNT_ID` now reports a 404 Not Found.

---

## What you should be able to say now

- How an `import {}` block differs from the `terraform import` command, and why a block is
  reviewable.
- What `terraform plan -generate-config-out` writes and why you must review it.
- Which summary line proves an import is safe: `N to import, 0 to add, 0 to change, 0 to destroy`.
- That destroy on an imported resource deletes the real object, so clean up throwaways only.
