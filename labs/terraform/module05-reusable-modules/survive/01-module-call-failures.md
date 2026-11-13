# Survive: Module call failures (15 min)

## The Scenario

Your team keeps one shared module for database settings and calls it from several projects. This morning
a teammate added a `prod` call and pushed. On your machine `terraform plan` fails, and so does the plan
after a "quick fix". You need to read each module error, find the real cause, and get back to a clean
plan. These are the four module mistakes a DBA meets most often.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. The scratch project uses only the
built-in `terraform_data` placeholder, so nothing here touches AWS or costs anything. (The box signs in
to AWS with its instance role - you never type an access key.)

---

## Step 1: Build a working project

On **tf-lab-1**, as **ec2-user**, create the scratch project with a module folder.

```bash
mkdir -p ~/survive-modules/modules/db-label && cd ~/survive-modules
```

Create the module's inputs.

```bash
vi modules/db-label/variables.tf
```

Press `i`, type this, then `Esc`, `:wq`, `Enter`:

```
variable "env" {
  type = string
}

variable "port" {
  type = number
}
```

The module's resource:

```bash
vi modules/db-label/main.tf
```

```
resource "terraform_data" "this" {
  input = "db-${var.env}-port-${var.port}"
}
```

The module's output:

```bash
vi modules/db-label/outputs.tf
```

```
output "label" {
  value = terraform_data.this.input
}
```

The root file, calling the module once:

```bash
vi main.tf
```

```
module "dev" {
  source = "./modules/db-label"
  env    = "dev"
  port   = 5432
}

output "dev_label" {
  value = module.dev.label
}
```

```bash
terraform init
terraform plan
```

**Expected output (yours will differ):**
```
  # module.dev.terraform_data.this will be created
  ...
Plan: 1 to add, 0 to change, 0 to destroy.
```

**Check it worked:** you have a clean baseline plan.

---

## Step 2: A new module call that was never initialised

Reproduce the teammate's change. Open `main.tf` with vi and add this **above** the `output` block:

```
module "prod" {
  source = "./modules/db-label"
  env    = "prod"
  port   = 5432
}
```

Plan without running init.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
│ Error: Module not installed
│
│   on main.tf line 7:
│    7: module "prod" {
│
│ This module is not yet installed. Run "terraform init" to install all modules
│ required by this configuration.
```

**What happened:** `init` registers every module call. A brand-new call (even to a module you already
use) needs `init` again. The error names the exact call, `prod`, on the exact line.

```bash
terraform init
terraform plan
```

**Expected output (yours will differ):**
```
Initializing modules...
- prod in modules/db-label
...
Plan: 2 to add, 0 to change, 0 to destroy.
```

---

## Step 3: Wrong or missing arguments in the module call

Open `main.tf` with vi and, in the `prod` call, change `port` to a misspelling: `prot   = 5432`. Save and
plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
│ Error: Missing required argument
│
│   on main.tf line 7, in module "prod":
│
│ The argument "port" is required, but no definition was found.
│
│ Error: Unsupported argument
│
│   on main.tf line 10, in module "prod":
│   10:   prot   = 5432
│
│ An argument named "prot" is not expected here. Did you mean "port"?
```

**Reading two errors from one typo:** the module's `variables.tf` is its contract. `port` has no default,
so it is **required** - and `prot` is not in the contract at all. Terraform even suggests the fix.

Change `prot` back to `port` and confirm the plan is clean.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
Plan: 2 to add, 0 to change, 0 to destroy.
```

---

## Step 4: Reaching inside a module

Someone wants the security group ID (here, the resource's `id`) and tries to read the resource directly.
Open `main.tf` with vi and add at the bottom:

```
output "peek" {
  value = module.dev.terraform_data.this.id
}
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
│ Error: Unsupported attribute
│
│   on main.tf line 19, in output "peek":
│   19:   value = module.dev.terraform_data.this.id
│
│ This object does not have an attribute named "terraform_data".
```

**What happened:** a module is a sealed box. The root can only see what the module exposes with an
`output`. The resource inside is private.

Fix it the correct way - expose the value from the module. Open the module's output file with vi.

```bash
vi modules/db-label/outputs.tf
```

Add at the bottom:

```
output "id" {
  value = terraform_data.this.id
}
```

Then change the root's `peek` output to read the module output. Open `main.tf` with vi and set:

```
  value = module.dev.id
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
Changes to Outputs:
  + peek = (known after apply)
Plan: 2 to add, 0 to change, 0 to destroy.
```

**Check it worked:** the error is gone. The module decided what to share; the root used only that.

---

## Step 5: Clean up

Apply once to prove it works, then destroy. On **tf-lab-1**, as **ec2-user**:

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 2 destroyed.
```

Confirm state is empty before removing the folder.

```bash
terraform state list
```

**Check it worked:** the command prints nothing. Now remove the scratch folder.

```bash
cd ~ && rm -rf ~/survive-modules
```

---

## What you practised

- Fixing "Module not installed" by running `terraform init` after adding any new module call.
- Reading "Missing required argument" and "Unsupported argument" against the module's `variables.tf`.
- Understanding that a module is a sealed box: the root reads only its `output` values.
- Exposing a new value correctly by adding an `output` to the module instead of reaching inside.
