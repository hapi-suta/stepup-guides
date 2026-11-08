# RDS PostgreSQL with Terraform: the pieces behind one database

This explains what Terraform builds when you ask for an RDS PostgreSQL instance, and the handful of
settings that decide whether a change is safe. Read it before the tutorial, where you create one.

## What RDS is, in a DBA's words

Amazon RDS is managed PostgreSQL. AWS runs the operating system, patching, backups, and failover
tooling; you run the database inside it. You do not get OS access or a true superuser. Your master
user gets the `rds_superuser` role, which is powerful but not unlimited. Terraform does not change
that - it just lets you describe the instance in a file instead of clicking through a wizard.

## One database is several resources

An RDS instance is never created alone. The tutorial builds a small chain, and the order matters:

1. **DB subnet group** (`aws_db_subnet_group`) - a named list of subnets the database may live in.
   RDS insists the list covers at least two Availability Zones, even for a single-AZ database.
2. **DB parameter group** (`aws_db_parameter_group`) - the engine settings, like `postgresql.conf`
   as an AWS object. Its `family` (for example `postgres16`) must match the engine's major version.
3. **DB instance** (`aws_db_instance`) - the database itself. It points at the other two.

Terraform works out the order itself, because the instance refers to
`aws_db_subnet_group.appdb.name`. That reference is a dependency. In production you also attach a
security group (`vpc_security_group_ids`) that decides who can reach port 5432.

## Data sources: reading, not creating

`data "aws_vpc" "default"` and `data "aws_subnets" "default"` do not create anything. They look up
the default VPC and its subnets so you never hard-code an ID. They appear in `terraform state list`
with a `data.` prefix. Destroying never deletes them.

## Parameter groups, dynamic and static

Some PostgreSQL settings can change on a running database (dynamic, such as
`log_min_duration_statement`). Others need a restart (static, such as `shared_buffers`). In
Terraform each `parameter` block has an `apply_method`: `immediate` for dynamic settings and
`pending-reboot` for static ones. Setting a static parameter as `immediate` is an error. A DBA
should know which kind each setting is before editing.

## In place versus replacement

Every plan labels the change, and for a database this is the most important thing to read:

- `~ update in place` - for example changing `instance_class`. The database keeps its data, but a
  resize usually restarts it, so there is brief downtime.
- `-/+ replace` - the database is destroyed and a new empty one is built. Changing `db_name`,
  `username`, or turning on storage encryption on an existing instance does this. The plan marks
  the cause with `# forces replacement`.

Never apply a plan that replaces a database unless you mean to lose its contents.

## Settings that trade safety for convenience

The tutorial uses lab settings. Know what each one means before copying it anywhere real:

- `skip_final_snapshot = true` - when the database is deleted, no last backup is taken. Lab only.
  Production uses `false` with a `final_snapshot_identifier`.
- `deletion_protection = false` - lets Terraform or the console delete the database. Production
  uses `true`, which makes a destroy fail until someone turns it off on purpose.
- `publicly_accessible = false` - the database has no public address. Keep it this way.
- `apply_immediately = true` - apply changes now instead of waiting for the next maintenance window.
  Convenient in a lab, risky on a busy primary.
- `multi_az`, `backup_retention_period`, `storage_encrypted` - the high availability, backup, and
  encryption settings the lab leaves out and production needs.

## The password problem

`sensitive = true` on a variable hides the value from plan and apply output. It does **not** keep it
out of the state file. The master password is stored in `terraform.tfstate` in readable form, so
state must be protected like a credential. RDS also rejects `/`, `@`, `"`, and spaces in the master
password. Later modules cover remote encrypted state and proper secrets handling.

## Versions and names

`engine_version` must be a version RDS currently offers; old minor versions are retired, so look
them up with the AWS CLI rather than copying a number from a guide. `name_prefix` and
`identifier_prefix` let AWS add a unique suffix, which avoids name collisions when you rebuild.

## Time and cost

An RDS instance takes roughly 5 to 10 minutes to create and a few minutes to delete. It bills by the
hour while it exists, even when idle. The habit that keeps your bill at zero: run
`terraform destroy` the moment you finish a lab, and keep lab databases on a `db.t3.micro`.

## What is next

In the tutorial you write the three Terraform files, plan, apply, and verify the instance from both
Terraform and the AWS CLI. Then in the exercises you predict in-place and replacement changes and
destroy the database.
