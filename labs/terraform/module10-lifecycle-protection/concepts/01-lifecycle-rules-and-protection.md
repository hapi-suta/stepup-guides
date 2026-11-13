# Lifecycle Rules and Protecting a Database

This explains the three `lifecycle` rules Terraform gives you and the other lock that guards a
database. Read it before the tutorial, where you try them on a real RDS instance.

## Why a database needs extra protection

Terraform's normal behaviour is to make reality match the file. For most resources that is
harmless. For a database, "make it match" can mean **delete it and build an empty one**. A single
careless edit in a pull request can turn into a data-loss event. Lifecycle rules let you tell
Terraform where to be careful.

## Replace versus update

Every plan marks a change. Two matter most here:

- `~` update in place - the database stays, one setting changes.
- `-/+` replace - the old object is destroyed and a new one created. A plan says
  "forces replacement" next to the attribute responsible.

Some attributes cannot be changed on an existing RDS instance - the identifier (name), for
example. Changing one looks like a tiny edit but plans as a replacement. Always read the plan for
`-/+` on a database.

## The three lifecycle rules

All three go inside a `lifecycle { ... }` block on the resource.

### prevent_destroy

`prevent_destroy = true` makes Terraform **refuse any plan that would destroy the resource**. It
fails with `Instance cannot be destroyed` before anything happens.

Know its limits:

- It only guards against **Terraform**. The console, the AWS CLI and other tools ignore it.
- If someone deletes the whole `resource` block, the rule disappears with it and the plan will
  destroy the database. Review deletions of resource blocks as carefully as anything.
- The value must be written as `true` or `false`; it cannot come from a variable.
- To destroy intentionally you must change it to `false` in code first, through a reviewed change.
- The error suggests `-target`. That avoids the check rather than fixing anything.

### ignore_changes

`ignore_changes = [attribute, ...]` makes Terraform **stop comparing** the listed attributes after
creation. It is for settings that something else legitimately changes:

- `password` - rotated by an on-call DBA or by Secrets Manager.
- `engine_version` - bumped by AWS minor-version auto-upgrade.

Without it, the next apply would "fix" the difference and could undo a rotation or downgrade the
engine. The cost: Terraform is now **blind** to those attributes. A wrong value in the file will
never be flagged. Keep the list short and write down why each item is there.

### create_before_destroy

By default, a replacement destroys the old object and then creates the new one, leaving a gap.
`create_before_destroy = true` reverses the order: build the new one first, repoint everything,
then delete the old one.

- It suits **supporting resources** such as `aws_db_subnet_group` and `aws_db_parameter_group`.
- It does not suit the database instance itself: two instances cannot share one name at once.
- The new copy must not collide with the old, so use `name_prefix` to get a unique name each time.

## The second lock: deletion_protection

`deletion_protection = true` on `aws_db_instance` is an **AWS-side** lock. RDS itself refuses a
delete request, whoever sends it - Terraform, the console or the CLI - until the setting is
turned off.

| Lock | Where it lives | Stops Terraform destroy | Stops console / CLI delete |
|---|---|---|---|
| `prevent_destroy` | Terraform config | yes | no |
| `deletion_protection` | AWS RDS setting | yes (apply fails) | yes |

Use both on production. To tear down on purpose, lift both in code, apply, then destroy.

## One more safety net: the final snapshot

`skip_final_snapshot = false` plus a `final_snapshot_identifier` makes RDS take one last backup as
the database is deleted. Locks stop accidents; a final snapshot limits the damage when someone
overrides them. The tutorial sets `skip_final_snapshot = true` only so a lab cleans up quickly.

## Habits to take with you

- Read every plan for `-/+` and "forces replacement" on a database.
- Treat `Instance cannot be destroyed` as the protection working, not as a bug.
- Never switch protection off just to get a pipeline green.
- Use `ignore_changes` sparingly, and note why each attribute is listed.
- Use both Terraform and AWS locks on anything that holds data.

## What is next

In the tutorial you add the lifecycle block to an RDS instance, prove `ignore_changes` leaves an
out-of-band change alone, watch `prevent_destroy` refuse a destroy plan, and then lift it to clean
up.
