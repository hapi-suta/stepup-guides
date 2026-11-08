# Use: Importing Existing Infrastructure Exercises (25 min)

These exercises build on the BUILD tutorial, where you brought a hand-built Aurora PostgreSQL
cluster under Terraform with `terraform import`. Aurora costs money to run, so here you practise
the **same import workflow on a free, throwaway resource** - an empty S3 bucket - and then apply
what you learn to reading the Aurora config. You should already have:

- Terraform installed and the AWS CLI available on the box
- Comfort with `init`, `plan`, and `state list` from the earlier modules
- The idea from the BUILD guide: with an import, you must never see a destroy in the plan

Work in **VS Code connected to your lab server (`tf-lab-1`) over Remote-SSH**, in the integrated
terminal, as the **ec2-user**. AWS access is keyless - the instance role provides it, so you never
type an access key. These exercises are a thinking partner: you run the commands and explain what
you see. The only AWS resource created is one empty S3 bucket, and you remove it at the end.

---

## Exercise 1: Build the "legacy" resource by hand (5 min)

**Goal:** Create something Terraform knows nothing about, exactly like a database a colleague
clicked together in the console.

On **tf-lab-1**, as **ec2-user**, find your AWS account ID and keep it in a shell variable so the
bucket name is unique to you. `aws sts get-caller-identity` asks AWS "who am I", and `--query`
picks one field out of the answer.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $ACCOUNT_ID
```

**Expected output (yours will differ):**
```
2036xxxxxxxx
```

Create the bucket with the AWS CLI. `s3api create-bucket` makes the bucket, `--bucket` names it.

```bash
aws s3api create-bucket --bucket legacy-import-$ACCOUNT_ID --region us-east-1
```

**Expected output (yours will differ):**
```
{
    "Location": "/legacy-import-2036xxxxxxxx"
}
```

**Check it worked:** You see a `Location` line. This bucket exists in AWS but not in any Terraform
state - that is what "brownfield" means.

---

## Exercise 2: Write the resource block and import it with the CLI (8 min)

**Goal:** Do the classic `terraform import` workflow: config first, then adopt.

On **tf-lab-1**, as **ec2-user**, make a fresh project folder so you do not disturb your other work.

```bash
mkdir -p ~/terraform-lab/import-practice && cd ~/terraform-lab/import-practice
```

Open a new file with vi.

```bash
vi main.tf
```

Type this (replace `2036xxxxxxxx` with your real account ID from Exercise 1), then save and quit
(`Esc`, then `:wq`):

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
  bucket = "legacy-import-2036xxxxxxxx"
}
```

Initialise the project so the AWS provider downloads.

```bash
terraform init
```

Before importing, **predict**: what will `terraform plan` say right now? Then check.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_s3_bucket.legacy will be created
  + resource "aws_s3_bucket" "legacy" {
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

- Terraform wants to **create** a bucket that already exists. Why? (Hint: it has no state entry
  for it.) What would happen if you applied now?

Now adopt the bucket. `terraform import` takes two arguments: the **address** in your config
(`aws_s3_bucket.legacy`) and the **real ID** in AWS (for a bucket, its name).

```bash
terraform import aws_s3_bucket.legacy legacy-import-$ACCOUNT_ID
```

**Expected output (yours will differ):**
```
aws_s3_bucket.legacy: Importing from ID "legacy-import-2036..."...
aws_s3_bucket.legacy: Import prepared!
aws_s3_bucket.legacy: Refreshing state...

Import successful!
```

**Check it worked:** You see `Import successful!`.

---

## Exercise 3: Read back the real values and reach a clean plan (7 min)

**Goal:** Prove the import changed nothing in AWS and reconcile config against reality.

On **tf-lab-1**, as **ec2-user**, list what Terraform now tracks, then read the bucket's recorded
attributes. `state show` prints every value Terraform learned from AWS.

```bash
terraform state list
terraform state show aws_s3_bucket.legacy
```

**Expected output (yours will differ):**
```
aws_s3_bucket.legacy
# aws_s3_bucket.legacy:
resource "aws_s3_bucket" "legacy" {
    arn    = "arn:aws:s3:::legacy-import-2036..."
    bucket = "legacy-import-2036..."
    region = "us-east-1"
    ...
}
```

Now run the plan again.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
aws_s3_bucket.legacy: Refreshing state... [id=legacy-import-2036...]

No changes. Your infrastructure matches the configuration.
```

- The plan went from "1 to add" to "No changes". What exactly did `import` write, and what did it
  not touch?
- For the Aurora cluster in the BUILD guide, the final plan still showed a `~` in-place change on
  `master_password`. Why can a password never be read back by import, and why is that change safe
  while a `-/+` would not be?
- In the BUILD guide, which line in the plan summary told you the import was safe?

---

## Exercise 4: Force a replace warning, then clean up (5 min)

**Goal:** See the danger sign you hunt for on a real database - and then remove the lab resource.

On **tf-lab-1**, as **ec2-user**, open `main.tf` and change the `bucket` value to a different name
(for example add `-v2` on the end). Save it, then plan only - do not apply.

```bash
vi main.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # aws_s3_bucket.legacy must be replaced
-/+ resource "aws_s3_bucket" "legacy" {
      ~ bucket = "legacy-import-2036..." -> "legacy-import-2036...-v2" # forces replacement
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

- What does `# forces replacement` mean? Which Aurora/RDS settings (for example the cluster
  identifier or engine) would give you the same `-/+` on a real database?
- You must never apply a `-/+` on a hand-built production database. What do you change in the
  config instead?

Undo the edit in `vi` so the name matches AWS again, and confirm `No changes`.

```bash
vi main.tf
```

```bash
terraform plan
```

Now clean up. Because the bucket is imported, **`terraform destroy` really deletes it from AWS** -
exactly what it would do to an imported production database. That is fine here: the bucket is empty
and throwaway.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
aws_s3_bucket.legacy: Destroying... [id=legacy-import-2036...]
aws_s3_bucket.legacy: Destruction complete after 1s

Destroy complete! Resources: 1 destroyed.
```

Confirm AWS agrees the bucket is gone, then remove the practice folder.

```bash
aws s3api head-bucket --bucket legacy-import-$ACCOUNT_ID
```

**Expected output (yours will differ):**
```
An error occurred (404) when calling the HeadBucket operation: Not Found
```

```bash
cd ~/terraform-lab && rm -rf ~/terraform-lab/import-practice
```

**Check it worked:** The 404 proves the bucket no longer exists, so nothing keeps costing money.

---

## What you practised

- Creating a "legacy" resource outside Terraform and spotting that plan wants to create it again.
- Running `terraform import <address> <id>` and reading `state show` to see real values.
- Reaching `No changes`, and recognising `-/+` / `forces replacement` as the stop sign.
- Remembering that destroy on an imported resource deletes the real thing.
