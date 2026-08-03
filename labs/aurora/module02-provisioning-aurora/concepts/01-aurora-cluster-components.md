# Concepts: Aurora Cluster Components
## Module 02 - Provisioning Aurora (CLI + Console)

Read this before doing any build guide in this module. These concepts are referenced throughout.

---

## What is an Aurora Cluster?

An Aurora cluster is not a single database server. It is a group of database instances that share a single distributed storage layer. The storage holds your data. The instances are compute nodes that read from and write to that storage.

This is fundamentally different from standard RDS PostgreSQL, where each instance has its own EBS volume.

```
Standard RDS PostgreSQL:
------------------------
[Instance A]           [Instance B - Read Replica]
     |                        |
     v                        v
[EBS Volume A]         [EBS Volume B]  <- separate copies of data
     (primary)              (replica, data shipped via WAL)


Aurora PostgreSQL:
------------------
[Writer Instance]      [Reader Instance 1]    [Reader Instance 2]
     |                        |                       |
     +------------------------+-----------------------+
                              |
                              v
              [Shared Aurora Storage Layer]
              6 copies across 3 AZs  <- one shared storage volume
```

In Aurora, the instances are just compute. They do not store your data locally. All instances - writer and readers - access the same shared storage.

---

## Writer Instance (Primary)

Every Aurora cluster has exactly one writer instance. This instance handles:

- All INSERT, UPDATE, and DELETE operations
- DDL changes (CREATE TABLE, ALTER TABLE, etc.)
- SELECT queries (it can also read)

The writer is the only instance that can modify data. If the writer goes down, Aurora promotes one of the reader instances to become the new writer.

Key facts about the writer:
- There is always exactly one writer per cluster
- It runs on a specific instance class you choose (e.g., db.t3.medium)
- It has its own instance endpoint (a DNS name pointing directly to it)
- `pg_is_in_recovery()` returns `false` on the writer

---

## Reader Instances (Replicas)

Reader instances handle read-only queries. You can have zero to fifteen readers in a single Aurora cluster.

```
                    Aurora Cluster
    +-------------------------------------------+
    |                                           |
    |   [Writer]   [Reader 1]   [Reader 2]      |
    |      |            |            |          |
    |      +------------+------------+          |
    |                   |                       |
    |      [Shared Storage - 6 copies, 3 AZs]  |
    +-------------------------------------------+
```

Key facts about readers:
- Accept SELECT queries only
- Refuse INSERT, UPDATE, DELETE, and DDL with the error: `cannot execute ... in a read-only transaction`
- Replication lag is typically under 100 milliseconds (because readers share the same storage)
- Each reader has its own instance endpoint
- `pg_is_in_recovery()` returns `true` on readers
- Can be different instance classes than the writer (e.g., writer is db.r6g.xlarge, readers are db.r6g.large)

### Why Readers Are So Fast in Aurora

In standard PostgreSQL streaming replication, the primary ships WAL (Write-Ahead Log) records to replicas. The replicas apply those records to their own storage. This involves network transfer and disk writes on each replica.

Aurora skips all of that. Because readers share the same storage as the writer, there is no data to ship. When the writer writes to storage, readers can see those changes almost immediately. The only delay is cache invalidation - the reader needs to know that a cached page has changed.

```
Standard PostgreSQL Replication:
  Writer -> WAL stream over network -> Replica applies WAL to its own disk
  Lag: seconds to minutes

Aurora Replication:
  Writer -> writes to shared storage <- Reader reads from same storage
  Lag: typically 10-50 milliseconds
```

---

## Cluster vs Instance - The Key Distinction

This confuses many beginners. In Aurora, a "cluster" and an "instance" are different things.

### The Cluster

The cluster is the logical container. It includes:
- All instances (writer + readers)
- The shared storage volume
- Cluster-level configuration (cluster parameter group)
- Cluster endpoints (writer endpoint, reader endpoint)
- Backup settings
- Encryption settings

When you run `aws rds create-db-cluster`, you create this container. No compute instances exist yet. You have a cluster with storage but no way to access it.

### The Instance

An instance is a compute node inside the cluster. It includes:
- A specific instance class (CPU + RAM)
- An instance-level parameter group
- Its own instance endpoint
- A role: writer or reader

When you run `aws rds create-db-instance` and point it to the cluster, you add a compute node. Aurora automatically assigns the first instance as the writer and subsequent instances as readers.

```
Step 1: Create cluster (storage + config, no compute)
  aws rds create-db-cluster --db-cluster-identifier devops-lab-cluster ...

Step 2: Add writer instance (first compute node)
  aws rds create-db-instance --db-instance-identifier devops-lab-writer-1 \
    --db-cluster-identifier devops-lab-cluster ...

Step 3: Add reader instance (second compute node)
  aws rds create-db-instance --db-instance-identifier devops-lab-reader-1 \
    --db-cluster-identifier devops-lab-cluster ...
```

This two-step process (create cluster, then add instances) is unique to Aurora. Standard RDS creates the instance and storage in a single command.

---

## Endpoints - Four Types

Aurora provides multiple DNS endpoints. Each serves a different purpose.

### 1. Cluster Endpoint (Writer Endpoint)

```
devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com
                   ^^^^^^^
                   note "cluster" in the hostname
```

- Always points to the current writer instance
- If the writer fails and a reader is promoted, this endpoint automatically updates to point to the new writer
- Use this endpoint for all write operations (INSERT, UPDATE, DELETE)
- Your application's write connection string should always use this endpoint

### 2. Reader Endpoint

```
devops-lab-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com
                   ^^^^^^^^^^
                   note "cluster-ro" (read-only)
```

- Load-balances connections across all reader instances
- If you have 3 readers, each new connection goes to one of the 3 readers (round-robin via DNS)
- Use this endpoint for read-heavy queries that do not need the latest data
- If there are no readers, the reader endpoint routes to the writer

### 3. Instance Endpoints

```
devops-lab-writer-1.abc123.us-east-1.rds.amazonaws.com
devops-lab-reader-1.abc123.us-east-1.rds.amazonaws.com
```

- Each instance has its own endpoint
- Points directly to one specific instance
- Does not change during failovers
- Use for maintenance tasks or debugging (e.g., checking a specific reader's lag)
- Do NOT use in application connection strings - these do not follow failovers

### 4. Custom Endpoints

Custom endpoints let you group specific instances together. For example, you might create a custom endpoint that only routes to readers with a large instance class for analytics queries.

```
analytics.cluster-custom-abc123.us-east-1.rds.amazonaws.com
          ^^^^^^^^^^^^^^
          note "cluster-custom"
```

Custom endpoints are an advanced feature. You will not use them in this module, but knowing they exist is important.

### Endpoint Decision Guide

```
What operation are you doing?
  |
  +-- Writing data (INSERT/UPDATE/DELETE) -> Cluster (writer) endpoint
  |
  +-- Reading data (SELECT) -> Reader endpoint
  |
  +-- Debugging a specific instance -> Instance endpoint
  |
  +-- Routing reads to a subset of instances -> Custom endpoint
```

### What Happens During Failover

```
Before failover:
  Cluster endpoint  -> devops-lab-writer-1  (writer)
  Reader endpoint   -> devops-lab-reader-1  (reader)

Writer instance fails. Aurora promotes devops-lab-reader-1.

After failover (30 seconds later):
  Cluster endpoint  -> devops-lab-reader-1  (now the writer)
  Reader endpoint   -> (no readers until you add one or old writer recovers)
```

Your application does not need to change connection strings. The cluster endpoint automatically resolves to the new writer.

---

## DB Subnet Groups

A DB subnet group tells Aurora which subnets it can place instances in. Aurora needs subnets in multiple Availability Zones so it can spread instances across AZs for high availability.

### What a Subnet Group Contains

A subnet group is a named collection of subnets from your VPC:

```
DB Subnet Group: "devops-lab-subnet-group"
  |
  +-- subnet-0aaa (us-east-1a) - 10.0.1.0/24
  |
  +-- subnet-0bbb (us-east-1b) - 10.0.2.0/24
  |
  +-- subnet-0ccc (us-east-1c) - 10.0.3.0/24
```

### Requirements

1. All subnets must be in the same VPC
2. Subnets must span at least 2 Availability Zones
3. Each subnet must have available IP addresses (at least 2 free)

### Why Subnet Groups Matter for Aurora

Aurora places each instance in a different AZ when possible. The writer might go in us-east-1a, and the reader in us-east-1b. If us-east-1a has an outage, the reader in us-east-1b is promoted to writer. Your database stays available.

```
us-east-1a          us-east-1b          us-east-1c
+-----------+       +-----------+       +-----------+
| Writer    |       | Reader 1  |       | Reader 2  |
| Instance  |       | Instance  |       | Instance  |
+-----------+       +-----------+       +-----------+
      |                   |                   |
      +-------------------+-------------------+
                          |
              [Aurora Shared Storage]
              (6 copies across all 3 AZs)
```

If your subnet group only has subnets in one AZ, Aurora cannot protect you from an AZ failure.

---

## Parameter Groups

Parameter groups control database configuration - they replace the `postgresql.conf` file that you would edit on a self-managed PostgreSQL server.

Aurora has TWO types of parameter groups:

### 1. Cluster Parameter Group

- Applies to ALL instances in the cluster
- Holds most configuration settings
- Example settings: `log_statement`, `timezone`, `rds.force_ssl`
- Family name: `aurora-postgresql16`

### 2. DB (Instance) Parameter Group

- Applies to ONE specific instance
- Holds a small number of instance-specific settings
- Lets you override cluster-level settings for one instance
- Family name: `aurora-postgresql16`

```
Cluster Parameter Group: "devops-lab-cluster-params"
  |
  +-- log_statement = 'all'          (applies to writer AND all readers)
  +-- timezone = 'UTC'               (applies to writer AND all readers)
  +-- shared_preload_libraries = 'pg_stat_statements'
  |
  |   DB Parameter Group: "devops-lab-writer-params"
  |     |
  |     +-- (instance-specific overrides, if any)
  |
  |   DB Parameter Group: "devops-lab-reader-params"
  |     |
  |     +-- (instance-specific overrides, if any)
```

> **Rule of thumb:** Put settings in the cluster parameter group unless you have a specific reason to set them per-instance. Most DBAs never need instance-level overrides.

The default parameter groups (`default.aurora-postgresql16`) cannot be modified. You must create custom parameter groups to change any settings.

---

## Engine Versions and Families

### Engine Versions

Aurora PostgreSQL versions follow PostgreSQL's numbering but are managed by AWS. You will see versions like:

- `16.6` - Aurora compatible with PostgreSQL 16.6
- `15.8` - Aurora compatible with PostgreSQL 15.8

Aurora does not support every PostgreSQL minor version. AWS selects specific versions and backports security patches.

To see available versions:

```
aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --query "DBEngineVersions[?starts_with(EngineVersion, '16')].EngineVersion" \
  --output table
```

### Parameter Group Families

The parameter group family determines which engine versions a parameter group is compatible with:

| Family | Compatible With |
|--------|----------------|
| `aurora-postgresql16` | Aurora PostgreSQL 16.x |
| `aurora-postgresql15` | Aurora PostgreSQL 15.x |
| `aurora-postgresql14` | Aurora PostgreSQL 14.x |

When you create a cluster with engine version `16.6`, your parameter groups must use the `aurora-postgresql16` family.

---

## Putting It All Together

Here is how all the components connect:

```
                        Aurora Cluster
                    (devops-lab-cluster)
                            |
         +------------------+------------------+
         |                                     |
   Cluster Endpoint                     Reader Endpoint
   (writes)                             (reads, load-balanced)
         |                                     |
         v                                     v
   [Writer Instance]                    [Reader Instance(s)]
   devops-lab-writer-1                  devops-lab-reader-1
   db.t3.medium                         db.t3.medium
   us-east-1a                           us-east-1b
         |                                     |
         +------------------+------------------+
                            |
                  [Shared Storage Layer]
                  6 copies, 3 AZs
                  Auto-grows up to 128 TB

   Configuration:
     Cluster Parameter Group -> all instances
     DB Parameter Group      -> per instance
     DB Subnet Group         -> where instances can be placed
     Security Group          -> who can connect (firewall)
```

---

## Summary

| Component | What It Is | Key Detail |
|-----------|-----------|------------|
| Cluster | Logical container for instances + storage | Created first, before any instances |
| Writer instance | Compute node that handles reads and writes | Exactly one per cluster |
| Reader instance | Compute node for read-only queries | Zero to fifteen per cluster |
| Cluster endpoint | DNS name pointing to current writer | Survives failovers automatically |
| Reader endpoint | DNS name load-balancing across readers | Round-robin across all readers |
| Instance endpoint | DNS name for one specific instance | Use for debugging, not applications |
| Custom endpoint | DNS name for a subset of instances | Advanced - not covered in this module |
| DB subnet group | Collection of subnets in 2+ AZs | Controls where instances are placed |
| Cluster parameter group | Config settings for all instances | Replaces postgresql.conf |
| DB parameter group | Config overrides for one instance | Usually left at defaults |
| Engine version | PostgreSQL-compatible version (e.g., 16.6) | Must match parameter group family |

**Next:** Read [02-configuration-management.md](02-configuration-management.md) before starting the build guides.
