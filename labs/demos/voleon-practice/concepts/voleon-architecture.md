# Voleon Architecture - DBA Context

## Company Overview

The Voleon Group is an AI/ML-driven quantitative hedge fund based in Berkeley, California. They manage multibillion-dollar assets under management (AUM) using machine learning models - not traditional quantitative factor models. The distinction matters: ML models generate signals from enormous datasets, which drives their infrastructure requirements.

Unlike most hedge funds that rent cloud infrastructure or outsource engineering, Voleon owns and self-manages its entire stack: HPC clusters, storage, databases, networking, and services. The DBA role sits inside the infrastructure team, not a product team, meaning you work directly with systems engineers, storage engineers, and networking engineers every day.

---

## Why the Tech Stack Looks Like This

Before walking through each component, it helps to understand the driving constraint: Voleon trains machine learning models on large historical datasets (market data, alternative data, etc.), runs those models continuously, and executes trades based on signals. Every part of the infrastructure exists to serve this pipeline reliably and at low latency.

The data pipeline looks roughly like this:

```
Market data feeds
  -> Ingestion layer (Python producers)
  -> PostgreSQL (structured storage, feature store)
  -> ML feature extraction (Python, C++, Go workers on Slurm)
  -> Model training (Slurm HPC nodes, GPU clusters)
  -> Signal generation (scoring services in Kubernetes)
  -> Position management (PostgreSQL, Redis)
  -> Trade execution (low-latency C++ systems)
```

Every component in this guide connects back to one or more stages of that pipeline.

---

## Compute: HPC Clusters with Slurm

### What It Is

Slurm (Simple Linux Utility for Resource Management) is a workload manager for HPC clusters. Think of it as a job scheduler that assigns work to compute nodes based on resource requests (CPUs, memory, GPUs, time limits).

### Why Voleon Uses It

ML model training is batch workloads, not continuous services. You submit a training job, it runs for hours or days on dozens of nodes with terabytes of data, and it finishes. Slurm is purpose-built for this pattern. Kubernetes would be wasteful and poorly suited for large MPI-style distributed training.

### What the DBA Needs to Know

- Slurm jobs read from and write to databases (PostgreSQL, InfluxDB) for experiment tracking and results storage.
- High-concurrency bursts happen when many jobs start or finish simultaneously - this causes connection spikes to PostgreSQL.
- PgBouncer sits in front of PostgreSQL specifically to absorb these spikes from Slurm workers.
- Storage volumes for HPC workloads are served by Lustre and GPFS, not Ceph - because Lustre/GPFS are optimized for parallel I/O at scale.

---

## Compute: Kubernetes for Services

### What It Is

Kubernetes (K8s) runs the always-on service layer: APIs, signal generation services, monitoring stacks, internal tooling, and supporting databases (test/staging PostgreSQL instances, Redis caches).

### Why Both Slurm AND Kubernetes

They serve different purposes:
- Slurm: batch, HPC, ML training
- Kubernetes: stateless/stateful services, long-running daemons, web APIs

### What the DBA Needs to Know

- PostgreSQL instances for dev/test run as Kubernetes StatefulSets.
- Production PostgreSQL runs on bare metal or dedicated VMs - NOT in Kubernetes. Performance, durability, and operational complexity all favor bare metal for primary databases.
- Redis runs in Kubernetes, serving caching for scoring services that need sub-millisecond lookups.
- DBAs need to understand PersistentVolumeClaims (PVCs), StorageClasses, and how Ceph RBD provides block storage to K8s pods.
- Operators (like the CloudNativePG operator) may manage PostgreSQL lifecycle in non-production clusters.

---

## Storage: Ceph

### What It Is

Ceph is a self-managed distributed storage system that provides:
- **RBD (RADOS Block Device)** - block storage for VMs and containers (analogous to AWS EBS)
- **CephFS** - a POSIX-compliant distributed filesystem (analogous to NFS, but distributed)
- **RGW (RADOS Gateway)** - object storage compatible with S3 API

### RBD for Databases

PostgreSQL and MySQL instances that run on VMs or Kubernetes get their storage from Ceph RBD. The database sees it as a normal block device - a disk to format and mount. Underneath, Ceph stripes data across many OSDs (Object Storage Daemons) across multiple physical nodes.

Key characteristics vs local NVMe:
- Latency: 1-5ms for Ceph RBD vs 0.1ms for local NVMe
- Throughput: depends on network fabric - on a 100Gbps network, Ceph can saturate local bandwidth
- Redundancy: built-in replication at the storage layer (typically 3x)
- Snapshots: consistent block-level snapshots, useful for database backups

### CephFS for Shared Access

CephFS is used where multiple nodes need simultaneous read/write access to the same data - for example, shared application configuration, or datasets that both Slurm workers and Kubernetes services need to read.

Databases generally do NOT use CephFS as their primary data directory - concurrent multi-writer access to a database data directory would corrupt it. CephFS is for shared read workloads or tooling that needs a common filesystem.

### What the DBA Needs to Know

- WAL write latency is the most sensitive database operation on Ceph RBD. A 3-5ms fsync latency means PostgreSQL commits are bounded by storage, not CPU.
- Ceph rebalancing events (OSD failures, additions, capacity thresholds) temporarily increase latency across all RBD volumes. Monitor for this.
- Snapshot-based backups require coordination: use `pg_start_backup()` / `pg_stop_backup()` or pgBackRest with Ceph snapshots to ensure consistency.
- CRUSH maps determine where data lands physically. If OSDs on the same server hold replicas of your database volume, you lose redundancy. Work with the storage team on CRUSH rule design.

---

## Storage: Lustre and GPFS

### Lustre

Lustre is a parallel distributed filesystem designed for HPC. It separates metadata (MDS - Metadata Server) from data (OSS - Object Storage Server), allowing thousands of compute nodes to read/write simultaneously at aggregate bandwidth.

**Why the DBA cares:** ML training jobs read raw market data and write feature tables in bulk. If those reads/writes hit PostgreSQL directly, the database gets destroyed. Lustre absorbs the bulk I/O; PostgreSQL stores structured, indexed results.

### GPFS (IBM Spectrum Scale)

GPFS (now called IBM Spectrum Scale) is similar to Lustre - a parallel filesystem used in financial and scientific HPC environments. It provides fine-grained I/O management, tiering, and high availability.

**Why it exists alongside Lustre:** Different workloads, different licensing, different operational characteristics. Large shops often have both.

---

## Databases

### PostgreSQL (Primary)

PostgreSQL is the main transactional and analytical database. It stores:
- Market data (tick data, OHLCV, corporate actions)
- Feature tables (computed inputs for ML models)
- Position data (current and historical)
- Operational data (job metadata, experiment results, system state)

It runs on dedicated bare metal or VMs with Ceph RBD storage. Replication is streaming (physical) for high availability. Logical replication may be used for table-level replication to read replicas.

### MySQL

MySQL is used for internal tooling, third-party applications (monitoring systems, ticket trackers, etc.), and legacy systems. The DBA manages MySQL alongside PostgreSQL.

### Oracle

Oracle appears in certain legacy or vendor-mandated contexts. Oracle licensing is expensive and operationally heavy, so its footprint is limited. DBAs at Voleon need to know enough Oracle to keep it running and perform migrations away from it.

### SQL Server

Similar to Oracle - present for specific applications or vendor tools that require it. The DBA manages it, ensures backups work, and handles compatibility issues.

---

## Caching: Redis

### Role at Voleon

Redis serves sub-millisecond lookups for:
- Scoring pipelines: ML model feature lookups during signal generation
- Session/state data for trading services
- Leaderboards and sorted sets for monitoring dashboards
- Message queues (Redis Streams or Pub/Sub) between services

### Relationship to PostgreSQL

The pattern is: PostgreSQL is the source of truth; Redis is a materialized view in memory. A Python service reads from PostgreSQL, populates Redis, and then high-frequency scoring services read only from Redis. The DBA needs to know when Redis is stale relative to PostgreSQL, and how to reason about cache invalidation.

### What the DBA Needs to Know

- Redis persistence modes: RDB (snapshot), AOF (append-only log), and combined. For caching workloads, RDB is sufficient. For queues, AOF matters.
- Redis Cluster vs Sentinel: Cluster for horizontal scaling, Sentinel for automatic failover of a single primary.
- Memory limits: Redis is an in-memory database. Eviction policies (LRU, LFU, allkeys-lru) determine behavior when memory is full.
- Redis does not support ACID transactions across multiple keys the way PostgreSQL does.

---

## Configuration Management: Ansible, Puppet, Chef

All three config management tools appear in Voleon's environment:

- **Ansible** - agentless, Python-based, uses SSH and YAML playbooks. The preferred tool for database provisioning, configuration drift remediation, and ad-hoc tasks.
- **Puppet** - agent-based, declarative, good for enforcing state continuously across large fleets. Older but deeply embedded in many on-prem environments.
- **Chef** - Ruby DSL, similar to Puppet but with a code-first philosophy.

**What the DBA needs to know:** You write and maintain Ansible roles for PostgreSQL configuration, pg_hba.conf management, pgBackRest setup, and failover automation. You do not need to be a Chef or Puppet developer, but you need to read and modify existing resources.

---

## Monitoring: Prometheus, Grafana, InfluxDB

### Prometheus

Time-series metrics collection. The `postgres_exporter` exposes PostgreSQL internals as Prometheus metrics:
- `pg_stat_activity` (connections, wait events)
- `pg_stat_bgwriter` (checkpoint rates, buffer hit ratios)
- `pg_replication_*` (replication lag)
- `pg_locks` (lock contention)
- `pg_stat_statements` (per-query performance)

### Grafana

Visualization layer on top of Prometheus and InfluxDB. DBAs build dashboards for:
- Replication lag across all replicas
- TPS (transactions per second) and QPS (queries per second)
- Checkpoint frequency and completion
- Bloat over time
- Vacuum progress

### InfluxDB

A specialized time-series database, better than PostgreSQL for high-cardinality metrics with frequent writes. Used for operational metrics (server health, network counters, storage I/O) where insert rates would overwhelm a relational database.

---

## Languages

- **Python** - dominant language for data pipelines, automation, DBA scripts, monitoring, and tooling
- **Go** - used for services that need higher performance than Python (internal APIs, monitoring agents)
- **Java** - some legacy systems and middleware
- **C++** - trading systems, latency-sensitive signal generation, HPC data processing

**DBA relevance:** You write Python heavily. Understanding Go is useful for reading source code of tools (pgBouncer alternatives, exporters). C++ is production code you won't touch but need to support.

---

## Data Formats

### Parquet

Columnar storage format for large analytical datasets. Parquet files are stored on Lustre/CephFS and read by Spark, Pandas, or custom C++ code. PostgreSQL's `COPY` command can export to CSV which gets converted to Parquet by downstream tools.

### Apache Iceberg

An open table format that adds ACID transactions, schema evolution, and time travel on top of Parquet files in a data lake. Think of it as "version control for Parquet datasets." Used for ML feature stores where you need reproducible point-in-time reads.

### BigQuery

Google's serverless analytical data warehouse. Voleon may push data to BigQuery for ad-hoc analysis, reporting, or sharing with external parties. This is a GCP service, not on-prem.

---

## Cloud: AWS, GCP, OpenStack

Voleon is primarily on-prem but uses cloud strategically:
- **AWS** - S3 for offsite backup storage, EC2 for burst compute, RDS may appear for non-critical workloads
- **GCP** - BigQuery for analytics, Vertex AI for supplemental ML workflows
- **OpenStack** - private cloud layer running on-prem hardware. Provides VM provisioning, networking, and object storage (Swift, compatible with S3 API) on Voleon-owned servers

**DBA note:** pgBackRest stanza configurations point at S3 (or S3-compatible OpenStack Swift) for offsite WAL archiving and full backup storage.

---

## CI/CD: Jenkins, GitHub Actions, Bazel

- **Jenkins** - traditional CI server, still common in on-prem environments. Runs database migration pipelines, test suites.
- **GitHub Actions** - used for newer projects, triggers Ansible playbooks and infrastructure tests on code changes.
- **Bazel** - Google's build system, used for large monorepo builds. The C++/Go codebase benefits from Bazel's deterministic, incremental builds.

**DBA relevance:** Database schema migrations run through CI. You review migration PRs, ensure backward compatibility, and confirm that rollback paths exist.

---

## IaC: Terraform, Pulumi

- **Terraform** - declarative IaC for provisioning VMs, networks, storage volumes, DNS records. You write Terraform to provision new PostgreSQL hosts or Ceph RBD volumes.
- **Pulumi** - similar to Terraform but uses real programming languages (Python, TypeScript). Preferred for complex infrastructure logic.

---

## Networking: 100Gbps+ Fabric, RDMA

Voleon runs a high-performance network fabric:
- 100Gbps+ Ethernet between compute, storage, and database nodes
- RDMA (Remote Direct Memory Access) - allows nodes to read/write each other's memory without involving the CPU. Used in HPC for MPI workloads and in storage (RoCE - RDMA over Converged Ethernet for Ceph).

**DBA relevance:**
- Network bandwidth is rarely the bottleneck between PostgreSQL and application servers at these speeds.
- Ceph RBD benefits from RDMA-capable networking (RoCE) which reduces latency.
- Streaming replication latency is extremely low on 100Gbps fabric - synchronous replication is viable without significant performance penalty.
- Firewall rules and network policies are managed by the networking team, but the DBA needs to understand which ports are required (5432, 6432, 6380, etc.) and request changes through the right channels.

---

## DBA Role in the Infrastructure Team

Unlike product-team DBAs who focus on application databases for a single product, the Voleon DBA is an infrastructure engineer who happens to specialize in databases. Responsibilities include:

- Database platform ownership: PostgreSQL, MySQL, Oracle, SQL Server
- Storage integration: working with Ceph team on RBD volumes, snapshots, performance tuning
- Config management: Ansible roles for database provisioning and configuration
- Monitoring: building and maintaining database observability in Prometheus/Grafana
- Backup/recovery: pgBackRest, PITR testing, RTO/RPO compliance
- High availability: streaming replication, failover (patroni or manual), connection pooling with PgBouncer
- Capacity planning: working with the storage team to size Ceph volumes, plan for data growth
- Security: SCRAM-SHA-256, role-based access, pg_hba.conf, audit logging
- Developer support: query tuning, schema review, migration support for the Python/C++/Go teams
- Incident response: on-call for database outages, replication failures, bloat crises
