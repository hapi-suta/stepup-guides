# What Is Terraform? Infrastructure as Code for DBAs

This explains what Terraform is, what "infrastructure as code" means, and why a database
administrator should care.

## What it is

Terraform is a free tool that lets you describe your cloud infrastructure - databases, networks,
security groups - in plain text files, and then creates, changes, or deletes that infrastructure for
you, the same way every time.

## What "infrastructure as code" means

Instead of clicking through the AWS Console to create an Aurora cluster - picking the engine, the
instance size, the subnet group, the parameter group, one screen at a time - you write what you want
in a file:

- The file is the single source of truth. Anyone can read it and see exactly how the database is set
  up.
- You keep it in Git, so every change is reviewed and has history (who changed the backup window, and
  when).
- You can build an identical database in dev, test, and production from the same file.
- You can tear it all down and rebuild it on demand.

Clicking in the console is fine for one thing once. Code is how you manage many things, repeatably,
with a record.

## Why a DBA should care

Databases are high-stakes and repetitive - exactly the work that benefits from being written down and
automated:

- **Repeatable provisioning** - stand up the same Postgres or Aurora setup every time, no missed
  setting.
- **Change safely** - see a preview of exactly what will change before it happens (a parameter group
  value, a backup retention) and get it reviewed.
- **Drift detection** - if someone changes the database by hand in the console, Terraform can tell you
  it no longer matches the code.
- **Disaster recovery** - your infrastructure is in a file, so rebuilding in another region is running
  the code again, not remembering 40 console clicks.
- **Audit** - every change is a reviewed commit, which auditors love.

## The three ideas you will use constantly

- **Provider** - the plugin that talks to a cloud. For us, the AWS provider.
- **Resource** - one thing you manage: an `aws_db_instance`, an `aws_rds_cluster`, a security group.
- **State** - Terraform's record of what it has created, so it knows the difference between "what you
  asked for" and "what exists".

## The core loop

Everything you do follows the same three steps:

1. **plan** - Terraform shows you what it *would* create, change, or destroy. You read it first.
2. **apply** - Terraform makes those changes for real.
3. **destroy** - Terraform removes what it created (important for keeping lab costs down).

The golden rule for a DBA: **read the plan before every apply**, and never let an apply destroy a
database unless you mean it.

## Where this course goes

1. Install Terraform and the AWS provider (the next tutorial).
2. The core loop on a cheap resource, then variables and reusable code.
3. State, and a remote backend so a team can share it safely.
4. Provisioning PostgreSQL on RDS, then Aurora clusters.
5. Configuration, secrets, backups and monitoring as code.
6. **Capstone:** import a database that was built by hand in the console into Terraform, so it is
   managed as code from then on - the real brownfield task most DBAs eventually face.
