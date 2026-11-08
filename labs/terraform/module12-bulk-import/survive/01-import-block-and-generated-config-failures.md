# Survive: Import block and generated config failures (15 min)

## The Scenario

You have been asked to adopt a handful of hand-built resources using `import` blocks and generated
configuration. Instead of a tidy plan you get a series of errors: a missing resource block, a
generated file that refuses to be written, and an import ID that AWS does not recognise. Each one
is common, and each one has a one-line cause. Your job is to diagnose them in turn and finish with
a clean `terraform apply`. We use a free S3 bucket so nothing billable runs.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. Nothing is left running if you
finish Step 5.

---

## Step 1: Set up the hand-built resource

On **tf-lab-1**, as **ec2-user**, create a scratch project and one bucket outside Terraform.

```bash
mkdir -p ~/survive-bulk && cd ~/survive-bulk
```

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket survive-bulk-$ACCOUNT_ID --region us-east-1
```

**Expected output (yours will differ):**
```
{
    "Location": "/survive-bulk-2036xxxxxxxx"
}
```

Create the provider config with vi.

```bash
vi versions.tf
```

Put this inside, then save and quit (`Esc`, then `:wq`):

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

Now create `imports.tf` with an import block - but make a deliberate mistake in the ID.

```bash
vi imports.tf
```

```
import {
  to = aws_s3_bucket.legacy
  id = "survive-bulk-typo"
}
```

```bash
terraform init
```

---

## Step 2: Failure one - import target has no configuration

On **tf-lab-1**, as **ec2-user**, run a normal plan. There is no `resource "aws_s3_bucket" "legacy"`
block anywhere.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: Configuration for import target does not exist
│
│ The configuration for the given import aws_s3_bucket.legacy does not exist.
│ All target instances must have an associated configuration to be imported.
╵
```

**What the message is telling you:** An `import` block only says *where* to adopt the object. You
still need a `resource` block - either write it by hand, or let Terraform generate it (next step).

---

## Step 3: Failure two - generated config, and the wrong ID

On **tf-lab-1**, as **ec2-user**, generate the block. `-generate-config-out=generated.tf` writes
starter code for each import target.

```bash
terraform plan -generate-config-out=generated.tf
```

**Expected output (yours will differ):**
```
aws_s3_bucket.legacy: Preparing import... [id=survive-bulk-typo]
╷
│ Error: Cannot import non-existent remote object
│ ... while attempting to import an existing object to "aws_s3_bucket.legacy",
│ the provider detected that no object exists with the given id.
╵
```

**What the message is telling you:** The `id` in the import block does not exist in AWS - the typo
we planted. Generation reads the real object, so a wrong ID stops it. Check what really exists:

```bash
aws s3api list-buckets --query "Buckets[].Name" --output text
```

**Expected output (yours will differ):**
```
survive-bulk-2036xxxxxxxx
```

Fix the ID in `imports.tf`.

```bash
vi imports.tf
```

Set `id = "survive-bulk-2036xxxxxxxx"` (your account ID), save and quit. Generate again.

```bash
terraform plan -generate-config-out=generated.tf
```

**Expected output (yours will differ):**
```
aws_s3_bucket.legacy: Preparing import... [id=survive-bulk-2036...]
Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.

Terraform has generated configuration and written it to generated.tf...
```

---

## Step 4: Failure three - generating over an existing file

On **tf-lab-1**, as **ec2-user**, run the same generate command a second time, as a colleague might
after re-running a history command.

```bash
terraform plan -generate-config-out=generated.tf
```

**Expected output (yours will differ):**
```
╷
│ Error: Config generation target already exists
│
│ The target file generated.tf already exists. Terraform will not overwrite it...
╵
```

**What the message is telling you:** Terraform refuses to overwrite a file, to protect your edits.
The fix is to review the file, then **move it into your real configuration** (or delete it and
regenerate). Never leave a generated file you have not read.

Read it, and then confirm the plan is clean without the flag now that the resource block exists.

```bash
cat generated.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

**Check it worked:** The summary says `1 to import` and `0 to destroy`. That last number is the one
that matters.

Apply it.

```bash
terraform apply
```

Type `yes`.

**Expected output (yours will differ):**
```
Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
```

---

## Step 5: Clean up

On **tf-lab-1**, as **ec2-user**, destroy the imported bucket. This deletes the real bucket - the
same thing it would do to an imported production database, so only do it on a throwaway.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 1 destroyed.
```

```bash
cd ~ && rm -rf ~/survive-bulk
```

**Check it worked:** `Destroy complete! Resources: 1 destroyed.` appears and the scratch directory
is gone.

---

## What you practised

- Recognising "Configuration for import target does not exist" and fixing it with a resource block
  or generated config.
- Telling a wrong import ID ("non-existent remote object") from a missing resource block.
- Handling "Config generation target already exists" and reviewing generated code before keeping it.
- Using `N to import, 0 to destroy` as the safety check before apply.
