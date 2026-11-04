# Terraform State: the DBA's Source of Truth

State is the one Terraform idea that trips people up, and the one a DBA most needs to get right,
because the state file is as sensitive as a database credential. This explains what state is, how to
look at it, what drift means, and how a team shares state safely.

## What state is

When you run `terraform apply`, Terraform records what it created in a file called **state**
(`terraform.tfstate`). State is the map between your code (`aws_db_instance.dev`) and the real
resource in AWS (`db-instance-id-12345`). Without it, Terraform would have no idea which real
database belongs to which block, and every plan would try to create everything again.

State holds, for each resource: its address in your code, its real cloud ID, and a snapshot of its
settings.

## Looking at state

Two read-only commands you will use constantly:

- `terraform state list` - lists every resource Terraform manages, by address. The quickest way to
  answer "what does Terraform think it owns?"
- `terraform state show <address>` - prints the recorded settings of one resource, for example
  `terraform state show aws_db_instance.dev`.

Expected output (yours will differ):

```
$ terraform state list
aws_db_instance.dev
aws_security_group.db["postgres"]
```

## State is sensitive - treat it like a password

The state file can contain **secrets in plain text** - a database master password, a generated
token. Two rules follow:

- Never commit `terraform.tfstate` to Git.
- Store it somewhere encrypted with access control (a remote backend, below), not on a laptop.

## Drift: when reality no longer matches the code

**Drift** is when someone changes a resource outside Terraform - a colleague bumps `max_connections`
in the AWS console, or an incident fix changes a security group by hand. Now the real resource no
longer matches your code.

`terraform plan` is how you catch it: it refreshes the real state and shows the difference. A clean
plan (`Plan: 0 to add, 0 to change, 0 to destroy.`) means no drift. Anything else means reality and
code disagree, and you decide which is right:

- Keep the manual change: update your code to match, then apply.
- Reject it: `terraform apply` puts the resource back to what the code says.

For a DBA, scheduled drift detection (a nightly `terraform plan`) is an early warning that someone
changed production by hand.

## Remote state: how a team shares one truth

A state file on your laptop does not work for a team - two people applying at once would corrupt it.
The fix is a **remote backend**: the state lives in shared, encrypted storage, with a **lock** so
only one apply runs at a time.

The common AWS backend:

- An **S3 bucket** holds the state file (encrypted, versioned).
- A **DynamoDB table** (or, in Terraform 1.10+, S3 native locking) provides the **lock**, so a
  second `apply` waits instead of clobbering the first.

A backend is declared in a `terraform { backend "s3" { ... } }` block. One quirk to know: a backend
block cannot use variables - its bucket and key are fixed strings - so teams bootstrap the bucket
once, then point every project at it.

Why a DBA cares: remote state with locking is what lets a whole team manage the same databases
safely, with history of every change and no two people applying at once.

## The mental model

- **Code** = what you want.
- **State** = what Terraform last built.
- **Reality (AWS)** = what actually exists.
- `plan` compares all three and tells you the difference before you touch anything.

Keep those three in sync - read the plan, reconcile drift, share state remotely - and Terraform is a
safe way to run real database infrastructure.
