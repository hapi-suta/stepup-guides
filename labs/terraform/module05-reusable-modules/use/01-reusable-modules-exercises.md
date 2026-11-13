# Use: Reusable Modules Exercises (25 min)

These exercises build on the BUILD tutorial, where you wrote a reusable module for an AWS security group
and called it twice, once for `dev` and once for `prod`. You should have:

- Terraform installed on **tf-lab-1**
- A rough idea that a module is "a folder of `.tf` files you can call more than once"

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. To keep AWS costs at zero, these
exercises use a built-in Terraform resource called `terraform_data`. It is a harmless placeholder that
lives only in state - it never calls AWS and never costs anything. Modules work identically whether the
thing inside is a placeholder or a real database.

Reassurance: the lab box signs in to AWS with its instance role, so you never type an AWS access key.
In these exercises you do not reach AWS at all.

---

## Setup: a small module and a root that calls it

On **tf-lab-1**, as **ec2-user**, create a scratch project with a module folder inside it.

```bash
mkdir -p ~/terraform-lab/m05-practice/modules/db-label && cd ~/terraform-lab/m05-practice
```

`mkdir -p` creates every folder in the path, including missing parents. You are now in the **root**
folder (the one you run Terraform commands from); the `modules/db-label` folder inside it is the module.

Create the module's three files. First the inputs.

```bash
vi modules/db-label/variables.tf
```

Press `i`, type this, then `Esc`, `:wq`, `Enter`:

```
variable "env" {
  description = "Environment name, for example dev or prod"
  type        = string
}

variable "port" {
  description = "TCP port for the database"
  type        = number
}
```

Then the resource.

```bash
vi modules/db-label/main.tf
```

```
resource "terraform_data" "this" {
  input = "db-${var.env}-port-${var.port}"
}
```

Then the output - the only door through which the root can read anything from the module.

```bash
vi modules/db-label/outputs.tf
```

```
output "label" {
  description = "The label for this environment"
  value       = terraform_data.this.input
}
```

Finally the root file that calls the module twice.

```bash
vi main.tf
```

```
module "dev" {
  source = "./modules/db-label"
  env    = "dev"
  port   = 5432
}

module "prod" {
  source = "./modules/db-label"
  env    = "prod"
  port   = 5432
}

output "dev_label" {
  value = module.dev.label
}

output "prod_label" {
  value = module.prod.label
}
```

---

## Exercise 1: Why plan says "Module not installed" (6 min)

**Goal:** Learn that Terraform must `init` to find modules, and read the address a module gives its
resources.

On **tf-lab-1**, as **ec2-user**, in `~/terraform-lab/m05-practice`, try a plan **before** initialising.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
│ Error: Module not installed
│
│   on main.tf line 1:
│    1: module "dev" {
│
│ This module is not yet installed. Run "terraform init" to install all modules
│ required by this configuration.
```

Do what it says. `terraform init` reads every `source =` line and registers the module.

```bash
terraform init
```

**Expected output (yours will differ):**
```
Initializing modules...
- dev in modules/db-label
- prod in modules/db-label
...
Terraform has been successfully initialized!
```

Plan again.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # module.dev.terraform_data.this will be created
  # module.prod.terraform_data.this will be created
  ...
Plan: 2 to add, 0 to change, 0 to destroy.
```

- Read the address `module.dev.terraform_data.this`. Which part is the module call, and which part is
  the resource inside it? (The module's resource is always called `this` here, in every copy.)
- The module code exists once but produced two resources. Why is that better than copy-pasting two
  nearly identical resource blocks?

---

## Exercise 2: One input changes one environment (7 min)

**Goal:** Prove each module call is independent, so you can change `prod` without touching `dev`.

First build both. On **tf-lab-1**, as **ec2-user**:

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
dev_label = "db-dev-port-5432"
prod_label = "db-prod-port-5432"
```

Now open `main.tf` with vi and change **only** the `prod` module's `port` from `5432` to `5433`. Save and
quit, then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # module.prod.terraform_data.this will be updated in-place
  ~ input  = "db-prod-port-5432" -> "db-prod-port-5433"
  ...
Plan: 0 to add, 1 to change, 0 to destroy.
```

`module.dev` is not mentioned. Change the port back to `5432` so your project is clean.

- Why is it valuable that a plan for a prod-only input change never mentions dev?
- If the module's `main.tf` itself is edited (say, to add a tag), which environments change? (Both -
  that is the whole point of sharing one module: a fix lands everywhere. It is also why you read the
  plan carefully.)

---

## Exercise 3: Turn two module calls into one with for_each, safely (10 min)

**Goal:** Refactor repeated module calls into a loop, and use `moved` blocks so nothing is destroyed.

Two near-identical `module` blocks is a sign you can loop. `for_each` works on modules just as it does
on resources. On **tf-lab-1**, as **ec2-user**, open `main.tf` with vi and **replace everything** with:

```
variable "envs" {
  type = map(number)
  default = {
    dev  = 5432
    prod = 5432
  }
}

module "env" {
  source   = "./modules/db-label"
  for_each = var.envs
  env      = each.key
  port     = each.value
}

output "labels" {
  value = { for name, m in module.env : name => m.label }
}
```

Because there is a new module call named `env`, run init again.

```bash
terraform init
terraform plan
```

**Expected output (yours will differ):**
```
  # module.dev.terraform_data.this will be destroyed
  # module.env["dev"].terraform_data.this will be created
  # module.env["prod"].terraform_data.this will be created
  # module.prod.terraform_data.this will be destroyed
  ...
Plan: 2 to add, 0 to change, 2 to destroy.
```

Same problem as renaming a resource: the **address** changed, so Terraform sees "delete the old ones,
create new ones". For real databases that is a rebuild. Tell Terraform the objects are the same with
`moved` blocks. Open `main.tf` with vi and add at the bottom:

```
moved {
  from = module.dev
  to   = module.env["dev"]
}

moved {
  from = module.prod
  to   = module.env["prod"]
}
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
  # module.dev.terraform_data.this has moved to module.env["dev"].terraform_data.this
  # module.prod.terraform_data.this has moved to module.env["prod"].terraform_data.this
  ...
Plan: 0 to add, 0 to change, 0 to destroy.
```

**Check it worked:** zero adds and zero destroys. Apply to record the new addresses, then confirm.

```bash
terraform apply
terraform state list
```

Type `yes` for the apply.

**Expected output (yours will differ):**
```
module.env["dev"].terraform_data.this
module.env["prod"].terraform_data.this
```

- What did `moved` save you from? Why must you always read a refactor plan before applying?
- Adding a third environment is now one line in the map. What would it have taken before?

---

## Clean up

Remove everything Terraform created so nothing is left behind. On **tf-lab-1**, as **ec2-user**:

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
cd ~ && rm -rf ~/terraform-lab/m05-practice
```

---

## What you should be able to say now

- What a module is (a folder of `.tf` files), what the root is, and how a `module` block calls one.
- Why `terraform init` is needed after adding or changing a module call.
- How to read a module resource address like `module.prod.terraform_data.this`.
- That inputs go in through variables and results come out only through outputs.
- How to loop over a module with `for_each` and use `moved` blocks so a refactor destroys nothing.
