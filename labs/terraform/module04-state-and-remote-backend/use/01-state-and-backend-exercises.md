# Use: State and Remote Backend Exercises (25 min)

These exercises build on the BUILD tutorial, where you moved Terraform's state from your local disk
into an S3 bucket with locking. You should have:

- Terraform installed on **tf-lab-1**
- A rough idea that "state" is Terraform's record of what it built

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. To keep AWS costs at zero, these
exercises use a built-in Terraform resource called `terraform_data`. It is a harmless placeholder that
lives only in state - it never calls AWS and never costs anything. State behaves the same way for a
placeholder as for a real database, so what you learn here transfers directly.

Reassurance: the lab box signs in to AWS with its instance role, so you never type an AWS access key.
In these exercises you do not reach AWS at all. The "password" you use below is a fake demo value.

---

## Setup: a scratch project

On **tf-lab-1**, as **ec2-user**, create a throwaway folder.

```bash
mkdir -p ~/terraform-lab/m04-practice && cd ~/terraform-lab/m04-practice
```

Open `main.tf` with vi.

```bash
vi main.tf
```

Press `i`, type the content below, then `Esc`, `:wq`, `Enter`.

```
variable "db_password" {
  type      = string
  sensitive = true
}

resource "terraform_data" "db" {
  input = "pg-primary"
}

resource "terraform_data" "secret" {
  input = var.db_password
}
```

Set a fake password for this terminal session only, then initialise. `export` sets a value that lasts
until you close the terminal; Terraform reads any variable named `TF_VAR_<name>`.

```bash
export TF_VAR_db_password='demo-only-not-a-real-password'
terraform init
```

**Expected output (yours will differ):**
```
Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

---

## Exercise 1: Look inside state, and see why it is sensitive (9 min)

**Goal:** Read state with the safe commands, then prove a "sensitive" value is still stored in plain
text.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab/m04-practice`, apply.

```bash
terraform apply
```

Type `yes` when prompted. Notice that the plan hides the password and shows `(sensitive value)`.

**Expected output (yours will differ):**
```
  + input  = (sensitive value)
  ...
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

List what Terraform manages, then look at one resource.

```bash
terraform state list
terraform state show terraform_data.db
```

`state list` prints every address Terraform owns. `state show` prints the recorded settings of one
address.

**Expected output (yours will differ):**
```
terraform_data.db
terraform_data.secret
# terraform_data.db:
resource "terraform_data" "db" {
    id     = "..."
    input  = "pg-primary"
    ...
}
```

Now look at the raw state file. `grep -n` searches a file for text and prints matching lines with their
line numbers.

```bash
grep -n "demo-only" terraform.tfstate
```

**Expected output (yours will differ):**
```
19:              "value": "demo-only-not-a-real-password",
23:              "value": "demo-only-not-a-real-password",
```

- The plan said `(sensitive value)`, yet the password is sitting in the state file in plain text. What
  does `sensitive = true` actually protect (screen output), and what does it **not** protect (the
  state file)?
- Name two rules that follow for any real database password. (Never commit `terraform.tfstate` to Git;
  keep it in an encrypted remote backend with access control.)

---

## Exercise 2: Rename a resource without destroying it (8 min)

**Goal:** See that state tracks resources by **address**, and learn the safe way to rename one.

State maps a name in your code (`terraform_data.db`) to a real object. If you rename the block, Terraform
thinks the old one was deleted and a new one was added. On **tf-lab-1**, as **ec2-user**, open
`main.tf` with vi and rename the `db` resource to `primary` - change only this line:

```
resource "terraform_data" "primary" {
```

Save and quit, then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # terraform_data.db will be destroyed
  # (because terraform_data.db is not in configuration)
  # terraform_data.primary will be created
  ...
Plan: 1 to add, 0 to change, 1 to destroy.
```

Picture `db` as a real database: this plan would delete it and build an empty one. The cure is a
`moved` block, which tells Terraform "this is the same object under a new name". Open `main.tf` with vi
and add this at the bottom:

```
moved {
  from = terraform_data.db
  to   = terraform_data.primary
}
```

Plan again.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # terraform_data.db has moved to terraform_data.primary
  ...
Plan: 0 to add, 0 to change, 0 to destroy.
```

**Check it worked:** zero adds and zero destroys. Terraform will update its state record on the next
apply without touching the real object.

- Why does a rename look like destroy plus create without the `moved` block?
- Why does it matter that you read the plan before applying a refactor?

---

## Exercise 3: Why a backend block cannot use variables (5 min)

**Goal:** Meet the "chicken and egg" rule that surprises everyone building a remote backend.

A backend tells Terraform where to keep state. It is read before variables are loaded. On **tf-lab-1**,
as **ec2-user**, make a second scratch folder so you do not disturb the first.

```bash
mkdir -p ~/terraform-lab/m04-backend && cd ~/terraform-lab/m04-backend
```

```bash
vi main.tf
```

Type this, then save and quit. It points at an S3 bucket by variable, which is a very natural thing to
try:

```
variable "bucket" {
  default = "my-team-tfstate"
}

terraform {
  backend "s3" {
    bucket       = var.bucket
    key          = "demo/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
```

```bash
terraform init
```

**Expected output (yours will differ):**
```
Initializing the backend...

│ Error: Variables not allowed
│
│   on main.tf line 5, in terraform:
│    5:     bucket       = var.bucket
│
│ Variables may not be used here.
```

This failed before touching AWS - the bucket name has to be a plain typed string. That is also why
teams create the state bucket once, by hand or in a separate bootstrap project, and then point every
other project at it with fixed text.

- Why does a backend block get read before variables? (Terraform must know where the state lives
  before it can evaluate anything that depends on state.)
- Look back at the BUILD tutorial's backend block. Which setting made two people unable to `apply` at
  the same time (`use_lockfile = true`)? Where does that lock live (in S3 next to the state file)?

---

## Clean up

Remove everything Terraform created so nothing is left behind. On **tf-lab-1**, as **ec2-user**, go back
to the first folder and destroy.

```bash
cd ~/terraform-lab/m04-practice && terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 2 destroyed.
```

Confirm state is empty before deleting the folders.

```bash
terraform state list
```

**Check it worked:** the command prints nothing. Now clear the fake password and remove both scratch
folders.

```bash
unset TF_VAR_db_password
cd ~ && rm -rf ~/terraform-lab/m04-practice ~/terraform-lab/m04-backend
```

---

## What you should be able to say now

- What state is, and how `terraform state list` and `terraform state show` read it.
- That a `sensitive` variable is hidden on screen but still stored in plain text in state - so state
  must be encrypted, access-controlled, and never committed to Git.
- Why renaming a resource looks like destroy plus create, and how a `moved` block avoids it.
- Why a backend block cannot use variables, and how S3 locking stops two people applying at once.
