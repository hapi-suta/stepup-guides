# Survive: Import mismatches and the dreaded replace (15 min)

## The Scenario

Your team lead asks you to bring a hand-built database under Terraform. You wrote the resource
block, ran `terraform import`, and now `terraform plan` is showing things you do not like: first an
import that will not even start, then a plan that wants to **destroy and recreate** the resource.
On a real Aurora cluster that would mean an outage and lost data. Your job is to diagnose each
problem and get to a plan with no destroy. We use a free S3 bucket as the stand-in so nothing
billable runs.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. Nothing is left running if you
finish Step 5.

---

## Step 1: Set up the hand-built resource

On **tf-lab-1**, as **ec2-user**, create the scratch project and a "legacy" bucket outside
Terraform.

```bash
mkdir -p ~/survive-import && cd ~/survive-import
```

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket survive-import-$ACCOUNT_ID --region us-east-1
```

**Expected output (yours will differ):**
```
{
    "Location": "/survive-import-2036xxxxxxxx"
}
```

Create the config. Open `main.tf` with vi.

```bash
vi main.tf
```

Put this inside (replace `2036xxxxxxxx` with your account ID), then save and quit (`Esc`, then `:wq`).
Notice the resource is named `legacy`:

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

resource "aws_s3_bucket" "legacy" {
  bucket = "survive-import-2036xxxxxxxx"
}
```

```bash
terraform init
```

---

## Step 2: Failure one - the wrong address

On **tf-lab-1**, as **ec2-user**, import using an address that is not in your config (a typo, a
renamed resource, or a copied command from a colleague's project):

```bash
terraform import aws_s3_bucket.old survive-import-$ACCOUNT_ID
```

**Expected output (yours will differ):**
```
╷
│ Error: Resource adding to state: aws_s3_bucket.old
│ ... resource address "aws_s3_bucket.old" does not exist in the configuration.
│
│ Before importing this resource, please create its configuration in the root module.
╵
```

**What the message is telling you:** The first argument to `terraform import` must match a
`resource` block that already exists in your config. Terraform will not invent the config for you
with the CLI command. The fix is to use the exact address - type, then name.

Now try the correct address but the **wrong ID**:

```bash
terraform import aws_s3_bucket.legacy survive-import-wrong-name
```

**Expected output (yours will differ):**
```
╷
│ Error: Cannot import non-existent remote object
│ ... while attempting to import an existing object to "aws_s3_bucket.legacy",
│ the provider detected that no object exists with the given id.
╵
```

**The lesson:** Two separate mistakes, two separate errors. Address wrong = "does not exist in the
configuration". ID wrong = "non-existent remote object". For RDS the ID is usually the instance
or cluster identifier (for example `legacy-aurora`), not the ARN.

Now import correctly.

```bash
terraform import aws_s3_bucket.legacy survive-import-$ACCOUNT_ID
```

**Check it worked:** You see `Import successful!`.

---

## Step 3: Failure two - the plan wants to replace it

On **tf-lab-1**, as **ec2-user**, imagine a colleague "tidied" the config and changed an
identifier that AWS cannot change in place. Open `main.tf`:

```bash
vi main.tf
```

Change the bucket line to `bucket = "survive-import-renamed"`, save and quit, then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_s3_bucket.legacy must be replaced
-/+ resource "aws_s3_bucket" "legacy" {
      ~ bucket = "survive-import-2036..." -> "survive-import-renamed" # forces replacement
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

**What the message is telling you:** The `-/+` and `# forces replacement` mean the changed argument
cannot be updated in place, so Terraform would delete the real object and build a new one. For a
database that means data loss. The rule from the BUILD guide: **never apply a plan that destroys an
imported database**.

**Fix:** The config must describe reality, not the other way round. Put the real value back.

```bash
vi main.tf
```

Set `bucket = "survive-import-2036xxxxxxxx"` again, save and quit.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

---

## Step 4: Failure three - drift after the import

On **tf-lab-1**, as **ec2-user**, simulate someone changing the bucket in the console after you
imported it. Add a tag with the AWS CLI (this edits AWS and not Terraform):

```bash
aws s3api put-bucket-tagging --bucket survive-import-$ACCOUNT_ID --tagging 'TagSet=[{Key=ChangedBy,Value=console}]'
```

Now see what Terraform thinks.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_s3_bucket.legacy will be updated in-place
  ~ resource "aws_s3_bucket" "legacy" {
      ~ tags = {
          - "ChangedBy" = "console" -> null
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**What the message is telling you:** Import is a one-time snapshot. Once the resource is in state,
Terraform compares the code to reality on every plan, so manual changes show up as drift. A `~`
in-place change is safe to apply; the code wins and the tag is removed.

- Decide: re-apply (code wins), or add `tags = { ChangedBy = "console" }` to the config (reality
  wins)? For a database, who should you ask before choosing?

---

## Step 5: Clean up

On **tf-lab-1**, as **ec2-user**, destroy the imported bucket. This really deletes it from AWS,
which is what you would never want on a production database but is correct for this throwaway.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 1 destroyed.
```

```bash
cd ~ && rm -rf ~/survive-import
```

**Check it worked:** `Destroy complete! Resources: 1 destroyed.` appears and the scratch directory
is gone.

---

## What you practised

- Telling apart "address not in configuration" from "non-existent remote object".
- Reading `-/+` and `# forces replacement` as a stop sign, and fixing the config to match reality.
- Understanding that an imported resource drifts like any other and plan shows it.
- Remembering that destroy on an imported resource deletes the real thing.
