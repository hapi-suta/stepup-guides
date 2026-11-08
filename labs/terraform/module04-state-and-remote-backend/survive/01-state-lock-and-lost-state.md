# Survive: A stuck state lock and a lost state file (15 min)

## The Scenario

It is 2 a.m. and the on-call DBA needs to apply a fix. `terraform apply` refuses to start with
"Error acquiring the state lock". Later, a colleague "tidied up" a project folder and deleted the state
file, and the next plan wants to create every database again. Both problems come down to understanding
what state is and how Terraform protects it. You will reproduce each one safely and recover.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. The scratch project uses only the
built-in `terraform_data` placeholder, so nothing here touches AWS or costs anything. (The box signs in
to AWS with its instance role - you never type an access key.) Step 2 needs **two terminals** open in
VS Code, which we call Terminal A and Terminal B.

---

## Step 1: Build a small project with some history

On **tf-lab-1**, as **ec2-user**, in Terminal A, create the scratch project.

```bash
mkdir -p ~/survive-state && cd ~/survive-state
```

```bash
vi main.tf
```

Press `i`, type this, then `Esc`, `:wq`, `Enter`:

```
resource "terraform_data" "db" {
  for_each = toset(["primary", "replica"])
  input    = "pg-${each.key}-v1"
}
```

```bash
terraform init
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Now change `v1` to `v2` in `main.tf` (use vi, save, quit) and apply a second time. This second apply
makes Terraform save a **backup** of the state as it was before the change.

```bash
terraform apply
```

Type `yes` when prompted.

```bash
ls
```

**Expected output (yours will differ):**
```
main.tf
terraform.tfstate
terraform.tfstate.backup
```

**What to notice:** `terraform.tfstate.backup` is the state from just before your most recent apply.
Keep that fact in mind for Step 3.

---

## Step 2: Cause and read a state lock error

Terraform locks the state while it works so two runs cannot write at once. You will hold the lock open
on purpose.

In Terminal A, change `v2` to `v3` in `main.tf` (vi, save, quit), then start an apply and **do not
answer the question**.

```bash
terraform apply
```

**Expected output (yours will differ):**
```
Plan: 0 to add, 2 to change, 0 to destroy.

Do you want to perform these actions?
  Enter a value:
```

Leave Terminal A waiting at the prompt. Terraform holds the lock while it waits for you.

Open a second terminal (Terminal B). On **tf-lab-1**, as **ec2-user**:

```bash
cd ~/survive-state && terraform plan
```

**Expected output (yours will differ):**
```
│ Error: Error acquiring the state lock
│
│ Error message: resource temporarily unavailable
│ Lock Info:
│   ID:        748fbca7-39ca-...
│   Path:      terraform.tfstate
│   Operation: OperationTypeApply
│   Who:       ec2-user@tf-lab-1
```

**How to read it:** the `Lock Info` block tells you who holds the lock, when, and doing what
(`OperationTypeApply`). Here the holder is real - Terminal A is mid-apply. The right move is to wait
or ask that person, not to break the lock.

You can ask Terraform to wait a little instead of failing at once. `-lock-timeout=10s` means "retry for
up to 10 seconds before giving up".

```bash
terraform plan -lock-timeout=10s
```

**Expected output (yours will differ):**
```
Acquiring state lock. This may take a few moments...
│ Error: Error acquiring the state lock
```

Now go back to Terminal A and answer the prompt with `no`. That cancels the apply and releases the lock.

```
no
```

**Expected output (yours will differ):**
```
Apply cancelled.
```

Back in Terminal B, the same plan now works.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
Plan: 0 to add, 2 to change, 0 to destroy.
```

**The decision rule for a real stuck lock:** with a remote backend, a crashed job can leave a lock
behind with nobody holding it. The command `terraform force-unlock <LOCK_ID>` removes it, using the ID
from the error. Only run it after you have confirmed no apply is still running - force-unlocking a live
run lets two writers corrupt the state. You are not running it here because the lock was real and has
already cleared itself. Close Terminal B when you are done.

---

## Step 3: Lose the state file and recover it

First confirm the backup exists, because the recovery depends on it. On **tf-lab-1**, as **ec2-user**,
in Terminal A:

```bash
ls -l ~/survive-state/terraform.tfstate ~/survive-state/terraform.tfstate.backup
```

**Check it worked:** both files are listed. If either is missing, stop and do not continue.

Only after that check passes, simulate the accident. Use `mv` rather than `rm` so you keep a copy.

```bash
mv ~/survive-state/terraform.tfstate ~/survive-state/lost.tfstate.saved
```

`mv` moves (renames) a file. Nothing is deleted - you have just taken the state out of the place
Terraform looks.

Now plan.

```bash
cd ~/survive-state && terraform plan
```

**Expected output (yours will differ):**
```
  # terraform_data.db["primary"] will be created
  # terraform_data.db["replica"] will be created
  ...
Plan: 2 to add, 0 to change, 0 to destroy.
```

**What this proves:** with no state, Terraform believes nothing exists and wants to create everything.
Against real databases that means duplicates, name clashes, or a second empty database next to the
original. Never apply this plan.

Recover from the backup.

```bash
cp ~/survive-state/terraform.tfstate.backup ~/survive-state/terraform.tfstate
terraform plan
```

`cp` copies a file. You are putting the pre-last-apply state back where Terraform expects it.

**Expected output (yours will differ):**
```
  # terraform_data.db["primary"] will be updated in-place
  # terraform_data.db["replica"] will be updated in-place
  ...
Plan: 0 to add, 2 to change, 0 to destroy.
```

**What to notice:** the plan is no longer "create everything" - Terraform knows both objects exist
again. It shows 2 changes because the backup is one apply behind; applying brings it fully up to date.

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Apply complete! Resources: 0 added, 2 changed, 0 destroyed.
```

In real life, the stronger protection is a remote backend with **versioning** on the bucket (you built
this in the BUILD tutorial): every earlier version of the state file stays recoverable, and nobody can
delete state by tidying a laptop folder.

---

## Step 4: Clean up

On **tf-lab-1**, as **ec2-user**, destroy what you created.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 2 destroyed.
```

Confirm state is empty before deleting the folder.

```bash
terraform state list
```

**Check it worked:** the command prints nothing. Now remove the scratch folder.

```bash
cd ~ && rm -rf ~/survive-state
```

---

## What you practised

- Reading a state lock error: the `Lock Info` block shows who holds the lock and what they are doing.
- Knowing when to wait (a live apply) and when `terraform force-unlock` is appropriate (a crashed run,
  after confirming nothing is running).
- Seeing that a missing state file makes Terraform want to recreate everything - and that you never
  apply that plan.
- Recovering from `terraform.tfstate.backup`, and why remote state with versioning is the real safety
  net.
