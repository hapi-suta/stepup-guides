# Aurora PostgreSQL with Terraform: a cluster is not an instance

This explains how Aurora differs from a plain RDS instance and how Terraform models that
difference. Read it before the tutorial, where you build a cluster with one writer and one reader.

## What Aurora is

Aurora is AWS's own cloud-built engine that speaks PostgreSQL. The big design change from regular
RDS is that **storage is separated from compute**. The data lives in one shared, distributed storage
volume that keeps six copies across three Availability Zones and grows on its own. The database
servers (instances) attach to that volume. Because the data is not tied to any one server, adding a
reader is fast and failover is quick - a reader is promoted, with no data copy needed.

## The most important idea: two resource types

Terraform models Aurora as two separate resources, and you cannot combine them:

- `aws_rds_cluster` - the **control plane**: engine and version, database name, master credentials,
  subnet group, parameter group, endpoints, and backup settings.
- `aws_rds_cluster_instance` - the **compute plane**: each server node that actually runs queries.
  It points at the cluster with `cluster_identifier`.

A cluster can exist with zero instances (storage only, no query capacity). That is why a build can
fail halfway and leave a cluster with nothing attached. It is also why `terraform import` of an
existing Aurora cluster needs one import for the cluster and one for every instance.

## Writer, readers, and endpoints

One instance is the **writer** and the rest are **readers**. Aurora gives you hostnames that follow
the role, not the machine:

- **Cluster (writer) endpoint** - always points at the current writer. Applications send writes here.
- **Reader endpoint** - spreads read connections across all readers. Reporting and read-heavy
  queries go here.
- **Instance endpoints** - one per node. Rarely used by applications.

When the writer fails, Aurora promotes a reader and moves the cluster endpoint to it. The
application keeps the same hostname. This is why applications should never connect to an instance
name directly.

## `count` and the writer are not the same thing

The tutorial uses `count = 2` on the instance resource. Terraform numbers the copies `[0]` and
`[1]`, and removes the **highest index** first when you lower the count. Aurora decides the writer
on its own (and can change it after a failover), so index `[1]` could be the writer. Lowering
`count` can therefore destroy the current writer and trigger a failover. Always check which node is
the writer (`IsClusterWriter`) before shrinking a cluster. Instances can also be given a
`promotion_tier` to influence which reader is promoted first.

## Parameter groups come in two kinds

Aurora has a **cluster parameter group** (settings shared by every node, such as logical
replication or `rds.force_ssl`) and a **DB parameter group** (settings per instance). In Terraform
these are `aws_rds_cluster_parameter_group` and `aws_db_parameter_group`. The `family` of either
must match the engine's major version, for example `aurora-postgresql15`. A family that does not
match is rejected when you create the cluster or instance, not by `terraform validate`.

## Instance classes are not the same as RDS

Aurora PostgreSQL does not offer every size RDS does. The tiny `db.t3.micro` that works for a plain
RDS instance is not available; the smallest burstable Aurora sizes are `db.t3.medium` and
`db.t4g.medium`. A build that sets an unsupported class fails when the instance is created, after
the cluster already exists. You can ask AWS what is orderable before you apply. Aurora also has a
serverless option (Serverless v2) that scales capacity up and down, configured on the cluster plus
instances of class `db.serverless`.

## Settings you will meet

- `engine = "aurora-postgresql"` and `engine_version` - which Aurora PostgreSQL version. Look up a
  currently offered version rather than copying one from a guide.
- `skip_final_snapshot = true` - no last backup when the cluster is deleted. Lab only; production
  uses `false` plus a final snapshot name.
- `deletion_protection` - production sets this to `true` so a destroy fails until it is turned off
  on purpose.
- `lifecycle { ignore_changes = [engine_version] }` - tells Terraform to stop comparing that
  attribute, because AWS can apply a minor upgrade on its own and cause permanent drift. The side
  effect is that editing the version in your code will show no change, so a deliberate upgrade needs
  that line temporarily removed.
- `database_name`, `master_username`, `master_password` - set once at creation. As with RDS, the
  password is stored in the state file even when the variable is marked `sensitive`.

## Cost and cleanup

Aurora bills for every instance by the hour, plus storage and I/O. A two-node cluster is twice the
compute of a single RDS instance. Destroying takes a few minutes because Terraform removes the
instances first, then the cluster, then the subnet group - it knows the order from the references
between them. Run `terraform destroy` as soon as you finish a lab, and confirm with the AWS CLI
that no cluster remains.

## RDS or Aurora?

Plain RDS is simpler and cheaper for small or single-node workloads. Aurora fits when you want fast
failover, many read replicas on shared storage, and storage that grows without planning. The
Terraform code differs most in this split between cluster and instances.

## What is next

In the tutorial you write the files for a cluster with a writer and a reader, plan, apply, and check
the roles with the AWS CLI. In the exercises you inspect the split, predict what `count` changes,
and destroy the cluster.
