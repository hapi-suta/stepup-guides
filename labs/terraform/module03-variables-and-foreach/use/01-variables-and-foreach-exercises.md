# Use: Variables, for_each, and Locals Exercises (25 min)

These exercises build on the BUILD tutorial, where you used a typed variable and `for_each` to create
two AWS security groups from one resource block. You should have:

- Terraform installed on **tf-lab-1** (`terraform version` prints a version)
- Comfort with the core loop: `init`, `plan`, `apply`, `destroy`

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. To keep AWS costs at zero, these
exercises use a built-in Terraform resource called `terraform_data`. It is a harmless placeholder
that lives only in Terraform's state - it never calls AWS, so it never costs anything. The `for_each`,
variable, and `locals` rules you practise are exactly the same ones that apply to real security groups
and databases.

Reassurance: the lab box authenticates to AWS with its instance role, so you never type an AWS access
key. In these exercises you do not even reach AWS.

---

## Setup: a scratch project

On **tf-lab-1**, as **ec2-user**, create a throwaway folder so you do not disturb your real project.

```bash
mkdir -p ~/terraform-lab/m03-practice && cd ~/terraform-lab/m03-practice
```

`mkdir -p` creates the folder (and any missing parents) and does not complain if it already exists.
`cd` moves you into it.

Open the file with vi.

```bash
vi main.tf
```

Press `i` to enter Insert mode, type the content below, then press `Esc` and type `:wq` and `Enter`
to save and quit.

```
variable "db_ports" {
  description = "Map of database engine names to their TCP ports"
  type        = map(number)
  default = {
    postgres = 5432
    mysql    = 3306
  }
}

resource "terraform_data" "sg" {
  for_each = var.db_ports
  input    = "allow-${each.key}-on-${each.value}"
}

output "rules" {
  value = { for name, res in terraform_data.sg : name => res.input }
}
```

Now initialise the folder.

```bash
terraform init
```

**Expected output (yours will differ):**
```
Initializing the backend...
Initializing provider plugins...
- Reusing previous version of terraform.io/builtin/terraform...
Terraform has been successfully initialized!
```

---

## Exercise 1: Make a bad input fail loudly (8 min)

**Goal:** See how a typed variable and a `validation` block stop bad input before anything is built.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab/m03-practice`, first see the healthy plan.

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

Notice the resource addresses: `["mysql"]` and `["postgres"]` - the map **key** is part of the name.

Now pass a value of the wrong type. `-var` sets a variable for this one run only.

```bash
terraform plan -var 'db_ports={postgres="five"}'
```

**Expected output (yours will differ):**
```
│ Error: Invalid value for input variable
│
│   on main.tf line 1:
│    1: variable "db_ports" {
│
│ Unsuitable value for var.db_ports set using -var="db_ports=...": a number
│ is required.
```

The `type = map(number)` line did that job - Terraform refused the text `"five"` where a number
belongs.

Next, add a rule about what values are *sensible*. Open `main.tf` with vi, and inside the
`variable "db_ports"` block (below the `default = { ... }` part, before the closing `}`) add:

```
  validation {
    condition     = alltrue([for port in values(var.db_ports) : port >= 1 && port <= 65535])
    error_message = "Every port must be between 1 and 65535."
  }
```

Save and quit, then try a number that is the right type but a nonsense value.

```bash
terraform plan -var 'db_ports={postgres=70000}'
```

**Expected output (yours will differ):**
```
│ Error: Invalid value for variable
│
│   on main.tf line 1:
│ ...
│ Every port must be between 1 and 65535.
```

- A type says "this must be a number". A `validation` says "and it must make sense". Which of the two
  caught `"five"`? Which caught `70000`?
- Why is failing at plan time (before anything is created) better than letting AWS reject the value
  during an apply?

---

## Exercise 2: for_each versus count - what happens when you remove one (12 min)

**Goal:** Prove why `for_each` with a map is safer than `count` with a list when an item is removed.

First add a second, `count`-based resource next to the first. On **tf-lab-1**, as **ec2-user**, open a
new file.

```bash
vi count-demo.tf
```

Type this, then save and quit:

```
variable "engines" {
  type    = list(string)
  default = ["postgres", "mysql", "redis"]
}

resource "terraform_data" "by_count" {
  count = length(var.engines)
  input = var.engines[count.index]
}
```

`count` makes one copy per list entry and numbers them 0, 1, 2. Now build everything.

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

(Two from the `for_each` map and three from the `count` list.)

**Part A - change the map.** Open `main.tf` with vi and change the `default` map so `mysql` is gone
and `redis = 6379` is in its place. Then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # terraform_data.sg["mysql"] will be destroyed
  # terraform_data.sg["redis"] will be created
  ...
Plan: 1 to add, 0 to change, 1 to destroy.
```

`postgres` is not mentioned at all. Each map key is its own stable name, so removing `mysql` touches
only `mysql`.

Put the map back the way it was (`postgres` and `mysql`), save, and confirm the plan is clean again.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
No changes. Your infrastructure matches the configuration.
```

**Part B - change the list.** Open `count-demo.tf` with vi and delete the **first** entry so the list
reads `["mysql", "redis"]`. Save and plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # terraform_data.by_count[0] will be updated in-place
  # terraform_data.by_count[1] will be updated in-place
  # terraform_data.by_count[2] will be destroyed
  ...
Plan: 0 to add, 2 to change, 1 to destroy.
```

- You removed *one* item from the list. Why did Terraform touch *all three* copies? (Hint: `count`
  names things by position - 0, 1, 2 - and removing the first item shifts everyone up one place.)
- Picture the three copies being three real databases instead of placeholders. Why does the `for_each`
  version feel safer?

Restore `count-demo.tf` to `["postgres", "mysql", "redis"]` so the plan is clean again.

---

## Exercise 3: locals, the console, and the fmt-validate habit (5 min)

**Goal:** Name a value once with `locals`, test it safely in the console, and run the pre-flight checks.

On **tf-lab-1**, as **ec2-user**, create a locals file. Type it with the messy spacing on purpose - it
gives `terraform fmt` something to fix.

```bash
vi locals.tf
```

```
locals {
common_tags = { Project = "payments", ManagedBy = "terraform" }
  reader_tags   = merge(local.common_tags, { Role = "reader" })
}
```

Save and quit. First check formatting without changing anything.

```bash
terraform fmt -check
```

`-check` only reports. It prints the name of any file that is not formatted correctly and changes
nothing.

**Expected output (yours will differ):**
```
locals.tf
```

Now let `fmt` fix it, then run the syntax check.

```bash
terraform fmt
terraform validate
```

**Expected output (yours will differ):**
```
locals.tf
Success! The configuration is valid.
```

Finally, ask the console what `reader_tags` evaluates to. `terraform console` is a safe sandbox that
never changes anything.

```bash
echo 'local.reader_tags' | terraform console
```

**Expected output (yours will differ):**
```
{
  "ManagedBy" = "terraform"
  "Project" = "payments"
  "Role" = "reader"
}
```

- What is the difference between a `variable` and a `local`? (One is an input from the caller, one is
  computed inside the config.)
- Why run `fmt` then `validate` then `plan` in that order?

---

## Clean up

Remove everything Terraform created so nothing is left behind. On **tf-lab-1**, as **ec2-user**:

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 5 destroyed.
```

Confirm state is empty before deleting the folder.

```bash
terraform state list
```

**Check it worked:** The command prints nothing.

Only now remove the scratch folder.

```bash
cd ~ && rm -rf ~/terraform-lab/m03-practice
```

---

## What you should be able to say now

- Why a typed variable (`type = map(number)`) plus a `validation` block rejects bad input at plan time.
- Why `for_each` over a map gives every item a stable name, and `count` over a list does not.
- What `each.key` and `each.value` are, and why resource addresses look like `...["postgres"]`.
- The difference between a variable (input) and a local (derived value), and how to test either with
  `terraform console`.
- The pre-flight habit: `fmt`, then `validate`, then `plan`.
