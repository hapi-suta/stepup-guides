# The Terraform Core Loop: plan, apply, destroy

This explains the loop you repeat every time you use Terraform, and the handful of words inside it.
Read it before the tutorial, where you run the loop for real.

## The loop

Everything in Terraform is three steps, in order:

1. **write** - describe what you want in a `.tf` file (a resource, like a database or a security
   group).
2. **plan** - Terraform compares your file to what exists and shows you exactly what it would
   create, change, or destroy. Nothing happens yet.
3. **apply** - Terraform makes those changes for real.

And when you are done with a lab resource:

4. **destroy** - Terraform removes what it created. For a DBA running labs, this is how you avoid a
   surprise bill.

## HCL, in one minute

Terraform files are written in HCL (HashiCorp Configuration Language). You will mostly write
**blocks** that look like this shape:

- `terraform { ... }` - settings for Terraform itself (which providers, which versions).
- `provider "aws" { region = "us-east-1" }` - how to talk to AWS.
- `resource "aws_db_instance" "dev" { ... }` - one thing you manage, with a type
  (`aws_db_instance`) and a name you choose (`dev`).

You do not write steps ("create this, then that"). You write the end state you want, and Terraform
works out the steps.

## Reading a plan (the most important DBA skill)

`terraform plan` prints a line in front of every resource:

- `+ create` - it will make something new.
- `~ update in place` - it will change something, no downtime.
- `-/+ replace` - it will destroy and recreate it. For a database, that can mean data loss.
- `- destroy` - it will delete something.

The golden rule: **read the plan before every apply, and never apply a plan that shows `-` or
`-/+` on a database unless you truly mean it.** Most production accidents are an apply that someone
did not read.

## What a resource and a provider are

- A **provider** is the plugin that knows how to talk to a service. The **AWS provider** turns your
  `resource` blocks into AWS API calls.
- A **resource** is one managed object: an RDS instance, an Aurora cluster, a security group, an S3
  bucket. Each has a type and the settings you give it.

## Cost discipline for lab work

Every `apply` that creates a real resource can cost money until you `destroy` it. Two habits that
save you:

- Run `terraform destroy` the moment you finish a lab.
- Keep lab resources small (a `db.t3.micro`, a single instance) while you are learning.

## What is next

In the tutorial you install Terraform, write a tiny resource, run `plan`, `apply`, inspect it, and
`destroy` it - the whole loop, start to finish, on a cheap resource.
