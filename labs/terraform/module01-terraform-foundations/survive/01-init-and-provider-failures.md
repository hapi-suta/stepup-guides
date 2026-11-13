# Survive: Terraform init and provider failures (10 min)

## The Scenario

You cloned a teammate's Terraform project onto your lab server, ran `terraform plan`, and got a
wall of red text instead of a plan. The project will not run. Your job is to diagnose why
Terraform cannot start, fix it, and get to a clean `terraform validate`. This is the most common
"it won't even begin" situation a DBA hits with Terraform.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH.

---

## Step 1: Reproduce the failure

On **tf-lab-1**, as **ec2-user**, create a scratch project that mimics the broken state.

```bash
mkdir -p ~/survive-init && cd ~/survive-init
```

Create a config that asks for a provider but never ran init. Open `main.tf` with vi.

```bash
vi main.tf
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

Now try to plan **before** initialising.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: Inconsistent dependency lock file
│
│ ... provider registry.terraform.io/hashicorp/aws: required by this
│ configuration but no version is selected...
│
│ To make the initial dependency selections ... run:
│   terraform init
╵
```

**What the message is telling you:** Terraform cannot plan because it has not downloaded the AWS
provider yet. The provider is the code that actually talks to AWS.

---

## Step 2: Fix the "not initialised" error

On **tf-lab-1**, as **ec2-user**, run the command Terraform asked for.

```bash
terraform init
```

**Expected output (yours will differ):**
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.xx.x...
Terraform has been successfully initialized!
```

**Check it worked:** You see `Terraform has been successfully initialized!` and a `.terraform/`
directory now exists:

```bash
ls -a ~/survive-init
```

---

## Step 3: A second, trickier failure - a bad region

On **tf-lab-1**, as **ec2-user**, edit `main.tf`. Change the region to something invalid **and**
add a small data source that asks AWS "who am I" - this forces Terraform to actually call AWS
during a plan, which is what surfaces the bad region.

```bash
vi main.tf
```

Set `region = "us-east-99"` (a region that does not exist), and add these two lines below the
provider block, then save and quit:

```
data "aws_caller_identity" "current" {}
output "account_id" { value = data.aws_caller_identity.current.account_id }
```

Run validate first.

```bash
terraform validate
```

**Expected output (yours will differ):**
```
Success! The configuration is valid.
```

Notice validate **passes** - it only checks that the syntax is well-formed, not that the values
make sense to AWS. Now run a plan, which makes Terraform contact AWS for the data source.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: invalid AWS Region: us-east-99
│
│   with provider["registry.terraform.io/hashicorp/aws"],
│   on main.tf line ...
╵
```

**The lesson:** `validate` catches broken syntax; only a `plan`/`apply` that actually reaches AWS
catches values AWS will reject - and that only happens when the config references a real resource
or data source. Both checks matter.

---

## Step 4: Restore a healthy state

On **tf-lab-1**, as **ec2-user**, fix the region back to a real one.

```bash
vi main.tf
```

Set `region = "us-east-1"`, save and quit, then confirm plan runs cleanly. Now that the region is
valid, Terraform can reach AWS and read the data source.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
data.aws_caller_identity.current: Read complete after 0s [id=2036...]

Changes to Outputs:
  + account_id = "2036..."

You can apply this plan to save these new output values to the Terraform
state, without changing any real infrastructure.
```

**Check it worked:** The bad-region error is gone, and the data source reads your real account ID -
proof Terraform is now talking to AWS successfully. (No real infrastructure changes, only the
output value.)

Clean up the scratch directory.

```bash
cd ~ && rm -rf ~/survive-init
```

---

## What you practised

- Recognising the "run `terraform init` first" error and fixing it.
- Knowing the difference between a syntax error (`validate` catches it) and a value error (only
  `plan`/`apply` catch it).
- Reading the error's first line to find the real cause instead of panicking at red text.
