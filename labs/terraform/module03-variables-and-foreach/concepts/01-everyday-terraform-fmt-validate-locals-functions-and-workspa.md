# Everyday Terraform: fmt, validate, locals, functions, and workspaces

The lessons so far cover how to build and import real database infrastructure. This handout rounds
out the everyday craft: the two commands you should run on every change, two language features that
keep your config clean, and how teams separate dev from prod. None of these need their own lab - you
will use them constantly once you know they exist.

## Two commands to run on every change

### `terraform fmt`

`terraform fmt` rewrites your `.tf` files into the one canonical style (consistent indentation,
aligned `=` signs). It is not cosmetic: when every file is formatted the same way, a code review
shows only the real change, not whitespace noise.

Run it before every commit:

```
terraform fmt
```

Expected output (yours will differ) - it prints the names of the files it reformatted:

```
main.tf
variables.tf
```

If it prints nothing, everything was already formatted. In a team, add `terraform fmt -check` to CI
so a badly formatted file fails the build instead of landing in the repo.

### `terraform validate`

`terraform validate` checks your configuration for errors - a misspelled attribute, a missing
required argument, a type mismatch - WITHOUT touching AWS. It is a fast, free, offline sanity check
you run before `plan`.

```
terraform validate
```

Expected output (yours will differ):

```
Success! The configuration is valid.
```

The habit that saves you: `terraform fmt` then `terraform validate` then `terraform plan`, every
time. The first two are instant and catch the silly mistakes before the slow, real `plan` runs.

## Locals: name a value once

A **local value** is a named expression you compute once and reuse. Where a variable is an input the
caller supplies, a local is something you derive inside the configuration - so you do not repeat the
same string or calculation in ten places.

```hcl
locals {
  name_prefix = "appdb-${var.environment}"
  common_tags = {
    Project     = "payments"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

Then reference them with `local.<name>`:

```hcl
resource "aws_db_instance" "main" {
  identifier_prefix = local.name_prefix
  tags              = local.common_tags
  # ...
}
```

Change the prefix or the tag set in one place and every resource that uses it updates. For a DBA
managing many databases, locals are how you keep naming and tagging consistent without copy-paste.

## Functions: Terraform's built-in helpers

Terraform has built-in **functions** for shaping values - no plugins needed. A few you will reach for:

- `jsonencode(...)` - turn a Terraform map into a JSON string. You used this to store a
  `{ username, password }` secret in Secrets Manager.
- `merge(map1, map2)` - combine tag maps, for example `merge(local.common_tags, { Role = "reader" })`.
- `lookup(map, key, default)` - read a key from a map with a fallback.
- `format("...", ...)` - build a string, like `format("appdb-%s", var.environment)`.

You can try any function in the Terraform console without applying anything:

```
echo 'merge({a="1"}, {b="2"})' | terraform console
```

Expected output (yours will differ):

```
{
  "a" = "1"
  "b" = "2"
}
```

`terraform console` is an interactive sandbox for expressions - a safe place to check what a function
or a reference evaluates to before you put it in a resource.

## Workspaces: one config, separate state per environment

A **workspace** lets you stand up the SAME configuration multiple times with SEPARATE state - for
example a `dev` copy and a `prod` copy of your database stack - without duplicating the code.

```
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
terraform workspace list
```

Expected output (yours will differ) - the `*` marks the current workspace:

```
  default
* dev
  prod
```

Inside the configuration, `terraform.workspace` gives the current name, so you can size resources per
environment:

```hcl
instance_class = terraform.workspace == "prod" ? "db.r6g.large" : "db.t3.micro"
```

One caution for a DBA: workspaces share the same backend and the same code, so a risky change is one
`workspace select` away from production. Many teams prefer SEPARATE directories (or separate state
keys) for prod to make that boundary physical, not just a selected name. Workspaces are great for
short-lived or identical environments; a production database often deserves its own isolated
configuration.

## The mental model

- `fmt` and `validate` are your pre-flight check - run them on every change, for free.
- `locals` name a derived value once; `variables` take an input from the caller.
- `functions` shape values; `terraform console` lets you try them safely.
- `workspaces` run one config many times with separate state - convenient, but put a hard boundary
  around production.
