# Terraform Modules: One Recipe, Many Environments

By now you have written the same kind of resource more than once - a security group for dev, another
for prod. A module is how you stop copy-pasting. This handout explains what a module is, how data goes
in and out, and when a module is worth creating. Read it before the tutorial, where you build one.

## What a module is

A **module** is just a folder containing `.tf` files. That is the whole definition. Every Terraform
project is already a module - the folder you run `terraform plan` in is called the **root module**.
When the root module *calls* another folder, that folder becomes a **child module**.

Think of a module as a recipe card. The recipe is written once. Each time you cook it you hand over the
ingredients (inputs) and you get a dish (a set of real resources) plus a note about what you made
(outputs).

## The three parts of a module

A well-formed module usually has three files, matching the three jobs:

- **`variables.tf` - the inputs.** Each `variable` is a setting the caller must or may provide, for
  example `env` and `port`. A variable with no `default` is **required**.
- **`main.tf` - the resources.** The real work: the security group, the database, and so on. It
  refers to inputs as `var.<name>`.
- **`outputs.tf` - the results.** Each `output` is a value the caller is allowed to read, for example
  the ID of the security group that was created.

The file names are only a convention - Terraform reads every `.tf` file in the folder - but everyone
uses them, so follow it.

## Calling a module

The root module uses a `module` block:

```hcl
module "dev" {
  source = "./modules/db-sg"
  env    = "dev"
  port   = 5432
}
```

- `module "dev"` - a name you choose for this particular call.
- `source` - where the module's code lives. A relative path like `./modules/db-sg` is the simplest.
  It can also be a Git URL or a published registry module.
- `env`, `port` - the inputs, matching the module's variables exactly.

Call the same module again with different values and you get a second, independent copy:

```hcl
module "prod" {
  source = "./modules/db-sg"
  env    = "prod"
  port   = 5432
}
```

To read a result, use `module.<call name>.<output name>`, for example `module.dev.security_group_id`.

## The module is a sealed box

This is the rule that surprises beginners: the root can **only** see a module's outputs. It cannot reach
inside and read `module.dev.aws_security_group.this.id`. If you need a value, the module author must
add an `output` for it.

That boundary is a feature. The module's internals can change - rename a resource, add a tag - without
breaking its callers, as long as the inputs and outputs stay the same. Treat the inputs and outputs as
the module's public contract.

## Where a resource lives in state

Inside state, a resource made by a module carries the module's name as a prefix:

- `module.dev.aws_security_group.this`
- `module.prod.aws_security_group.this`

The same resource name (`this`) appears twice, told apart by the module call. If you later change a
module call's name, or switch from two calls to a `for_each` loop, the address changes - and Terraform
will plan to destroy the old and create the new unless you add a `moved` block that says the object is
the same. For a database, always read that plan.

## `init` and modules

Terraform must register each module call before it can run. That is part of `terraform init`. Add or
change a `module` block and you need to run `init` again; otherwise you will see
`Module not installed`. It is a quick, free command - when in doubt, run it.

## Rules that keep modules healthy

- **No `provider` block inside a module.** Configure providers once in the root and let modules inherit
  them. That is what lets the same module work in many regions and accounts.
- **Give inputs a `type` and a `description`.** They are the module's documentation, and the type
  catches mistakes early.
- **Keep it small and focused.** One module, one job: a database security group, not "the whole
  platform".
- **Do not hide dangerous settings.** A DBA module should make the safe choice the default, for
  example deletion protection on and encryption on.

## When a module is worth creating

A module is a tool, not a goal. Build one when:

- You are about to copy the same block a second or third time.
- The pattern is a standard your team wants everyone to follow (every database gets the same tags,
  encryption, and backup settings).
- You want a single place to fix something and have it land in every environment.

Wait when you only have one use. A module adds a layer to read through, and a premature one is harder
to change than the plain resource. A common path is: write it plainly, copy it once, then extract the
module when the second copy appears.

One more caution for a DBA: a shared module is powerful because one edit changes every environment that
calls it. That is exactly why you read the plan for each environment before applying.

## The mental model

- A **module** is a folder of `.tf` files - a recipe you can use many times.
- **Variables** are the ingredients going in; **outputs** are the only things coming out.
- The **root module** calls child modules with a `module` block; each call is independent.
- State addresses carry the module name (`module.prod....`), so renaming a call needs a `moved` block.
- Run `terraform init` whenever you add or change a module call.

## What is next

In the tutorial you build a security-group module with `env` and `port` inputs and an ID output, call it
twice for dev and prod, and confirm both exist in state.
