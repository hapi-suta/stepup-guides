# Survive: for_each and variable failures (15 min)

## The Scenario

A teammate refactored your security-group Terraform to loop over a list of database engines. Now
`terraform plan` fails with red text, and the CI job that passes variables in is failing too. You need
to read each error, find the real cause, and get back to a clean plan. These are the three variable
and `for_each` mistakes a DBA hits most often.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. The scratch project uses only the
built-in `terraform_data` placeholder, so nothing here touches AWS or costs anything. (The box signs in
to AWS with its instance role - you never type an access key.)

---

## Step 1: Reproduce the for_each error

On **tf-lab-1**, as **ec2-user**, create a scratch project.

```bash
mkdir -p ~/survive-vars && cd ~/survive-vars
```

Open `main.tf` with vi.

```bash
vi main.tf
```

Press `i`, type this, then `Esc`, `:wq`, `Enter`:

```
variable "engines" {
  type    = list(string)
  default = ["postgres", "mysql"]
}

resource "terraform_data" "sg" {
  for_each = var.engines
  input    = each.key
}
```

Initialise and plan.

```bash
terraform init
terraform plan
```

**Expected output (yours will differ):**
```
│ Error: Invalid for_each argument
│
│   on main.tf line 7, in resource "terraform_data" "sg":
│    7:   for_each = var.engines
│
│ The given "for_each" argument value is unsuitable: the "for_each" argument
│ must be a map, or set of strings, and you have provided a value of type
│ list of string.
```

**What the message is telling you:** `for_each` needs each item to have a unique name (a key). A map
has keys built in. A plain list only has positions, so Terraform refuses it.

Fix it by turning the list into a **set** (a list with no duplicates, where each value becomes its own
key). Open `main.tf` with vi and change the `for_each` line to:

```
  for_each = toset(var.engines)
```

Save, quit, and plan again.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # terraform_data.sg["mysql"] will be created
  # terraform_data.sg["postgres"] will be created
  ...
Plan: 2 to add, 0 to change, 0 to destroy.
```

**Check it worked:** the error is gone and the addresses use the engine names as keys.

---

## Step 2: Fix the CI variable failures

The CI job passes variables in by name. Two things go wrong. First add a required variable (one with no
default). On **tf-lab-1**, as **ec2-user**, open `main.tf` with vi and add this near the top, and change
the `input` line to use it:

```
variable "environment" {
  type = string
}
```

```
  input    = "${var.environment}-${each.key}"
```

Run a plan the way CI does - with prompting turned off. `-input=false` tells Terraform never to stop and
ask a question, which is how a non-interactive job runs.

```bash
terraform plan -input=false
```

**Expected output (yours will differ):**
```
│ Error: No value for required variable
│
│   on main.tf line ...:
│    ...: variable "environment" {
│
│ The root module input variable "environment" is not set, and has no
│ default value. Use a -var or -var-file command line argument to provide a
│ value for this variable.
```

Supply the value two ways. First with `-var`:

```bash
terraform plan -input=false -var 'environment=dev'
```

**Expected output (yours will differ):**
```
Plan: 2 to add, 0 to change, 0 to destroy.
```

Now reproduce the type mistake. CI passed a single piece of text (note the quotes inside the quotes) where a list belongs.

```bash
terraform plan -input=false -var 'environment=dev' -var 'engines="postgres"'
```

**Expected output (yours will differ):**
```
│ Error: Invalid value for input variable
│
│   on main.tf line 1:
│    1: variable "engines" {
│
│ Unsuitable value for var.engines set using -var="engines=...": list of
│ string required.
```

**What this proves:** Terraform checks every value against the variable's `type`. The message names the
variable and the declaration line - read it before guessing.

A third way to supply a value is an environment variable named `TF_VAR_` plus the variable name. This
is handy in CI because nothing is written to disk.

```bash
export TF_VAR_environment=dev
terraform plan -input=false
```

**Expected output (yours will differ):**
```
Plan: 2 to add, 0 to change, 0 to destroy.
```

`export` sets a value for the rest of this terminal session. It disappears when you close the terminal.

---

## Step 3: The "known only after apply" for_each error

A teammate now wants a follow-up resource for every security group, keyed off the first resource's ID.
Open a new file with vi.

```bash
vi followup.tf
```

```
resource "terraform_data" "followup" {
  for_each = toset([terraform_data.sg["postgres"].id])
  input    = each.key
}
```

Save, quit, and plan.

```bash
terraform plan -input=false
```

**Expected output (yours will differ):**
```
│ Error: Invalid for_each argument
│
│ terraform_data.sg["postgres"].id is a string, known only after apply
│
│ The "for_each" set includes values derived from resource attributes that
│ cannot be determined until apply, and so Terraform cannot determine the
│ full set of keys ...
```

**What happened:** The `id` of a resource that does not exist yet is only known **after** it is created.
`for_each` must know all its keys at plan time, so it cannot be built from something that does not exist
yet.

Fix it by keying on values you already know (the engine names) and reading the ID inside the block.
Open `followup.tf` with vi and replace its contents with:

```
resource "terraform_data" "followup" {
  for_each = toset(var.engines)
  input    = terraform_data.sg[each.key].id
}
```

Plan again.

```bash
terraform plan -input=false
```

**Expected output (yours will differ):**
```
Plan: 4 to add, 0 to change, 0 to destroy.
```

**Check it worked:** the plan succeeds. The keys come from `var.engines` (known now) while the `id`
values are filled in later.

---

## Step 4: Clean up

Apply once to prove the final config really works, then destroy it. On **tf-lab-1**, as **ec2-user**:

```bash
terraform apply -input=false -auto-approve
```

`-auto-approve` skips the yes/no question. That is fine for a throwaway placeholder - never use it on a
real database.

**Expected output (yours will differ):**
```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

```bash
terraform destroy -input=false -auto-approve
```

**Expected output (yours will differ):**
```
Destroy complete! Resources: 4 destroyed.
```

Confirm state is empty before removing the folder.

```bash
terraform state list
```

**Check it worked:** the command prints nothing. Now clear the variable and delete the scratch folder.

```bash
unset TF_VAR_environment
cd ~ && rm -rf ~/survive-vars
```

---

## What you practised

- Reading the `for_each` "must be a map, or set of strings" error and fixing it with `toset()`.
- Supplying required variables three ways: `-var`, a `TF_VAR_` environment variable, and (in real teams)
  a `-var-file`.
- Recognising a type mismatch error and finding the variable it names.
- Understanding why `for_each` keys cannot depend on values that only exist after apply.
