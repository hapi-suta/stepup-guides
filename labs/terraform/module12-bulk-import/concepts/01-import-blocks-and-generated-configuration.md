# Import Blocks and Generated Configuration

This explains how to adopt many existing resources at once with `import` blocks, how that differs
from the older `terraform import` command, and what generated configuration is. It is reading only -
the commands are in the BUILD guide.

## What it is

An `import` block is a few lines of code that say "adopt this real object into this address".
Terraform reads the block during `plan`, shows you the import as part of the plan, and performs it
on `apply`. It arrived in Terraform 1.5.

```
import {
  to = aws_db_instance.legacy
  id = "legacy-app"
}
```

- `to` - the address in your code where the resource will live.
- `id` - the real identifier in AWS (for RDS, the instance identifier).

## Why a DBA wants it

A real database rarely stands alone. One application has an RDS instance, a subnet group, a
parameter group, and a security group, all built by hand. Importing them one command at a time is
slow and leaves no record. With import blocks you can:

- Declare the whole set in one file and review it like any other change.
- See `4 to import, 0 to add, 0 to change, 0 to destroy` in a plan **before** anything happens.
- Keep a record in Git of exactly what was adopted and when.

## import block vs the `terraform import` command

| | `terraform import` command | `import {}` block |
|---|---|---|
| How it runs | You type a command per resource | Declared in a file, run by plan and apply |
| Preview | None - it changes state immediately | Shown in the plan first |
| Reviewable | No, only in shell history | Yes, in a pull request |
| Many resources | One command each | One block each, all at once |
| Writes config | No | Optionally, with generation |
| Needs Terraform | Any version | 1.5 or newer |

The command is still fine for a quick one-off. For anything a team will repeat or review, prefer
blocks.

## Generated configuration

A block needs a matching `resource` block that describes the object. Writing dozens of attributes
by hand is tedious, so Terraform can generate it:

```
terraform plan -generate-config-out=generated.tf
```

Terraform reads each real object from AWS and writes a starter `resource` block into the file. The
target file must not already exist - Terraform will not overwrite your work.

Treat generated code as a **first draft**, never the finished product:

- It is a snapshot of what AWS reported, including noisy defaults and many `null` values.
- It cannot know secrets, so a master password will be missing.
- It can occasionally contain a combination the validator rejects (for example a field that
  conflicts with another), which you fix by deleting the offending line.
- You should tidy it, move it into your normal `.tf` files, and use variables where appropriate.

## Reading the plan

The summary line is your safety check:

`Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.`

- **to import** - how many objects Terraform will adopt. This is what you want.
- **0 to add** - nothing new will be created.
- **0 to change** - config already matches reality.
- **0 to destroy** - the number that must stay at zero. Never apply an import plan that destroys or
  replaces a database.

If "to change" is not zero, read each `~` line and decide whether the config or reality is right.

## Common failures

- **Configuration for import target does not exist** - the block has no matching `resource` block.
  Write one, or generate it.
- **Cannot import non-existent remote object** - the `id` does not exist in AWS. Check with the
  AWS CLI.
- **Config generation target already exists** - the output file is already there. Review it and
  move it into place, or delete and regenerate.

## After the import

Once applied, the resource is in state and fully managed. The `import` blocks have done their job;
leaving them is harmless, and many teams delete them afterwards. Remember that `terraform destroy`
now deletes the real object, so protect databases with `deletion_protection` and
`lifecycle { prevent_destroy = true }`.

## Where this goes next

You now have the full brownfield toolkit: import a single database carefully, then adopt many
related resources with blocks and generated code - the real task most DBAs eventually face.
