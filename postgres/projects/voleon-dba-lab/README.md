# Voleon DBA Interview Practice Lab

Practice lab for the Database Administrator (DBA) role at The Voleon Group - an AI/ML quantitative finance firm managing multibillion-dollar assets. Voleon runs self-managed infrastructure with PostgreSQL on Ceph RBD storage, Kubernetes, Ansible automation, and Prometheus/Grafana observability. This lab simulates their DBA environment across 4 AWS EC2 nodes.

---

## Lab at a Glance

Voleon's infrastructure is heavily on-prem: HPC compute clusters for ML research (Slurm-scheduled), Kubernetes for services, Ceph for distributed storage, and PostgreSQL as the primary relational database. The DBA role sits inside the infrastructure team and works closely with systems, storage, and networking engineers.

**What makes this lab different from Cigna/DrFirst/Authentic8:**

- **Ceph RBD simulation** - database storage on a simulated distributed block device (loopback + LVM), teaching the I/O patterns and commit-path latency of network block storage
- **Containerized databases** - PostgreSQL and MySQL running in Docker/Podman, reflecting Voleon's K8s-based services
- **Ansible as operational tooling** - not just deployment, but rolling config changes, drift detection, and parameter management
- **Redis caching layer** - model metadata caching alongside PostgreSQL
- **Data format exposure** - Parquet export/import and RocksDB exploration for the "big data formats" JD requirement
- **Quantitative finance domain** - trading signals, ML model registry, market data, positions, backtests

---

## Architecture: 4-Node EC2 Lab

```
                     AWS us-east-1 (Default VPC)
+----------------------------------------------------------------------+
|                                                                      |
|  pg-primary (t3.medium) - CentOS Stream 9                           |
|  +-- PostgreSQL 16 (primary, wal_level=replica)                      |
|  +-- PgBouncer :6432 (transaction-mode pooling)                      |
|  +-- Redis 7 :6379 (model metadata cache)                            |
|  +-- Database: quantdb                                               |
|  |     +-- quant schema (instruments, market_data, models, signals,  |
|  |     |                 positions, backtests, model_features)        |
|  |     +-- ops schema (deployments, pipeline_runs, alerts)           |
|  |                                                                   |
|  pg-replica (t3.medium) - CentOS Stream 9                           |
|  +-- PostgreSQL 16 (hot standby, streaming replication)              |
|  +-- pgBackRest repository (/var/lib/pgbackrest)                     |
|  +-- Simulated Ceph RBD storage (loopback + LVM on /dev/loop0)      |
|      /mnt/ceph-sim/ mounted as PG data directory on this node        |
|                                                                      |
|  pg-container (t3.medium) - CentOS Stream 9                         |
|  +-- Docker CE + Podman                                              |
|  +-- PostgreSQL 16 in Docker (port 5433)                             |
|  +-- MySQL 8.0 in Docker (port 3306)                                 |
|  +-- Redis in Docker (port 6380)                                     |
|  +-- Parquet tools (pyarrow, duckdb)                                 |
|  +-- RocksDB (standalone CLI + Python bindings)                      |
|                                                                      |
|  pg-ops (t3.small) - CentOS Stream 9                                |
|  +-- Ansible control node (manages all 3 PG nodes)                   |
|  +-- Prometheus :9090 + Grafana :3000 (monitoring stack)             |
|  +-- postgres_exporter + node_exporter on all nodes                  |
|  +-- Python DBA automation scripts (~/scripts/)                      |
|  +-- psql + mysql clients                                            |
|  +-- k6 (load testing)                                               |
|                                                                      |
+----------------------------------------------------------------------+
```

---

## How to Connect

```bash
# SSH to each node
ssh -i voleon-lab.pem ec2-user@<PRIMARY_IP>      # pg-primary
ssh -i voleon-lab.pem ec2-user@<REPLICA_IP>       # pg-replica
ssh -i voleon-lab.pem ec2-user@<CONTAINER_IP>     # pg-container
ssh -i voleon-lab.pem ec2-user@<OPS_IP>           # pg-ops

# PostgreSQL connections (from pg-ops or any node)
psql -h <PRIMARY_IP> -U quant_app -d quantdb -p 5432        # Direct to primary
psql -h <PRIMARY_IP> -U quant_app -d quantdb -p 6432        # Via PgBouncer
psql -h <REPLICA_IP> -U quant_readonly -d quantdb -p 5432   # Read-only replica
psql -h <CONTAINER_IP> -U postgres -d postgres -p 5433      # Dockerized PG

# MySQL (containerized on pg-container)
mysql -h <CONTAINER_IP> -u root -p -P 3306

# Redis
redis-cli -h <PRIMARY_IP> -p 6379
redis-cli -h <CONTAINER_IP> -p 6380
```

---

## Sample Database: quantdb (Quantitative Trading Platform)

Two schemas model the dual nature of the DBA role at a quant fund - the `quant` schema powers research and trading, the `ops` schema tracks infrastructure operations.

### quant schema - Research & Trading Tables

| Table | Scale | Features |
|-------|-------|----------|
| `quant.instruments` | ~50K | Stocks, futures, options - ISIN, ticker, exchange, asset class, sector |
| `quant.market_data` | ~10M | OHLCV tick data, **partitioned by month**, source feed, exchange timestamp |
| `quant.models` | ~500 | ML model registry - version, framework, training dataset, status, metrics |
| `quant.signals` | ~5M | Trading signals from models, **partitioned by date**, score, confidence, decay |
| `quant.positions` | ~200K | Portfolio positions - instrument, quantity, entry/current price, PnL |
| `quant.backtests` | ~10K | Backtest runs - model ref, date range, sharpe ratio, max drawdown |
| `quant.model_features` | ~2M | Feature store - feature name, value, timestamp, model ref |

### ops schema - Infrastructure Operations Tables

| Table | Scale | Features |
|-------|-------|----------|
| `ops.deployments` | ~2K | Model deployment log - version, environment, promoted_by, rollback flag |
| `ops.pipeline_runs` | ~5K | Data pipeline execution log - source, rows processed, duration, status |
| `ops.alerts` | auto | Trigger-based alert log on model failures and data quality issues |

### Database Roles

| Role | Access | Simulates |
|------|--------|-----------|
| `postgres` | Superuser | DBA administration |
| `quant_app` | SELECT, INSERT, UPDATE on quant schema | Trading application service |
| `quant_research` | SELECT on quant schema | ML researchers (read-only) |
| `quant_pipeline` | ALL on ops schema, INSERT on quant.market_data/signals | Data pipeline service (Airflow jobs) |
| `quant_readonly` | SELECT on all schemas | Reporting / Grafana dashboards |
| `replicator` | REPLICATION | Streaming replication |

### Security

- SCRAM-SHA-256 authentication (not md5)
- Role separation with least-privilege grants (no DELETE on market_data for app role)
- pg_hba.conf restricted to VPC CIDR (10.0.0.0/16) for replication
- SSL/TLS enforced for all connections
- Audit triggers on models and deployments tables
- pg_stat_statements for query performance tracking

---

## Python DBA Scripts

Production-style automation scripts on pg-ops (`~/scripts/`):

| Script | Purpose |
|--------|---------|
| `check_cluster.py` | Morning health check - primary status, replication lag, connections, disk usage |
| `find_slow_queries.py` | Top N queries from pg_stat_statements, flag regressions vs baseline |
| `backup_report.py` | pgBackRest backup status, verify latest < 24hrs, retention compliance |
| `replication_monitor.py` | Real-time replication lag with alerting threshold, WAL position tracking |
| `index_usage.py` | Unused, duplicate, and missing indexes with recommendations |
| `kill_idle_sessions.py` | Terminate idle-in-transaction sessions above threshold, log actions |
| `partition_manager.py` | Create future partitions, drop expired ones (market_data, signals) |
| `container_health.py` | Docker PG/MySQL container status, resource usage, volume health |
| `ansible_drift_check.py` | Compare running PG config vs Ansible vars, flag drift |
| `export_parquet.py` | Export table to Parquet via pyarrow, compress, validate row counts |

---

## CBUS Learning Path

See [cbus/README.md](cbus/README.md) for the full learning path.

| Phase | Guides | Focus |
|-------|--------|-------|
| BUILD | 8 guides | Install PG, create quantdb, replication, pgBackRest on Ceph-sim, PgBouncer + Redis, Docker DBs, Ansible, Prometheus/Grafana |
| USE | 8 exercises | Day-to-day DBA work - explore DB, replication health, PITR drill, performance tuning, Ansible rolling changes, container ops, Parquet export, security audit |
| SURVIVE | 8 scenarios | Chaos engineering - primary failover, PgBouncer exhaustion, accidental DELETE, container crash, WAL disk full, Ansible drift, slow query locks, monitoring blackout |
| Concepts | 3 docs | Voleon architecture, Ceph storage for DBAs, containerized databases |

---

## Chaos Scenarios

Each scenario has an `inject.sh`, `runbook.md`, and `validate.sh`:

| # | Scenario | What Breaks | Severity |
|---|----------|-------------|----------|
| 01 | Primary Failover | Primary killed, manual promotion needed | Critical |
| 02 | PgBouncer Connection Exhaustion | max_client_conn hit, new connections rejected | High |
| 03 | Accidental Signal DELETE | 500K signals deleted, PITR recovery needed | Critical |
| 04 | Docker Container Crash | PG container OOM-killed, data volume issue | High |
| 05 | WAL Disk Full | WAL directory fills up, writes blocked | Critical |
| 06 | Ansible Config Drift | Bad pg_hba.conf pushed, replication breaks | High |
| 07 | Slow Query Locks Partitions | Long query blocks partition maintenance | High |
| 08 | Monitoring Blackout | Prometheus down, replica silently falls behind | Medium |

---

## Voleon Technology Stack (from JD research)

This lab covers the technologies confirmed across 8+ Voleon job postings:

| Category | Voleon Uses | Lab Coverage |
|----------|-------------|--------------|
| **Primary DB** | PostgreSQL (expert-level) | Full PG 16 cluster with replication, partitioning, tuning |
| **Secondary DBs** | MySQL, Oracle, SQL Server | MySQL 8 in Docker container |
| **Storage** | Ceph RBD, Lustre, GPFS, SAN/NAS | Simulated Ceph RBD (loopback + LVM) |
| **Containers** | Docker, Kubernetes, Singularity | Docker CE + Podman with DB workloads |
| **Config Mgmt** | Ansible, Puppet, Chef | Ansible playbooks for PG operational management |
| **Caching** | Redis | Redis 7 for model metadata caching |
| **Monitoring** | Prometheus, Grafana, InfluxDB | Prometheus + Grafana with postgres_exporter |
| **Languages** | Python, Go, Java, C++ | Python DBA automation scripts |
| **Data Formats** | Parquet, Iceberg, BigQuery | Parquet export/import via pyarrow + DuckDB |
| **Cloud** | AWS, GCP, OpenStack | AWS EC2 infrastructure |
| **IaC** | Terraform, Pulumi | Terraform for EC2 provisioning |
| **CI/CD** | Jenkins, GitHub Actions, Bazel | GitHub Actions awareness |

---

## Repository Layout

```
voleon/
+-- README.md                          <- You are here
+-- config.sh                          <- Node IPs, SSH settings, service ports
+-- terraform/                         <- EC2 provisioning (4 nodes)
+-- ansible/                           <- Ansible control (PG config, rolling changes)
|   +-- inventory/
|   +-- roles/{common,postgresql,pgbouncer,redis,monitoring,pgbackrest}/
|   +-- playbooks/                     <- Operational playbooks
+-- dataset/
|   +-- quantdb.sql                    <- Full schema + 20M+ rows seed data
+-- scripts/                           <- Python DBA automation (10 scripts)
+-- docs/
|   +-- interview-guide.md             <- 20 interview questions mapped to JD
+-- cbus/
|   +-- build/                         <- 8 step-by-step build guides
|   +-- use/                           <- 8 operational exercises
|   +-- survive/                       <- 8 chaos scenarios (inject/runbook/validate)
|   +-- concepts/                      <- Architecture reference docs
+-- chaos/
    +-- chaos.sh                       <- Chaos engineering CLI
    +-- lib/common.sh                  <- Shared bash functions
    +-- scenarios/                     <- Chaos scenarios
    +-- results/                       <- Scenario results/scores
```

---

## Key Differences from Other Labs

| | Cigna | DrFirst | Authentic8 | **Voleon** |
|---|---|---|---|---|
| **Platform** | Patroni + Aurora | Aurora only | EC2 manual | **EC2 + Docker/Podman** |
| **Industry** | Healthcare payments | E-prescribing | Secure browsing | **AI/ML Quant Finance** |
| **Unique tech** | etcd, HAProxy | RDS Proxy, IAM auth | Airbyte ETL | **Ceph sim, Docker DBs, Ansible ops, Redis, Parquet** |
| **HA model** | Automated (Patroni) | Aurora native | Manual failover | **Manual + container orchestration** |
| **Multi-DB** | No | No | No | **Yes (MySQL in container)** |
| **Config mgmt** | Ansible (deploy) | Terraform | Terraform | **Ansible (operational)** |
| **Monitoring** | Zabbix | CloudWatch | Grafana Agent | **Prometheus + Grafana (self-hosted)** |
| **Storage focus** | Standard | Aurora shared | EBS | **Simulated Ceph RBD** |
| **Data formats** | None | None | None | **Parquet, DuckDB, RocksDB** |
| **Caching** | None | None | None | **Redis** |
| **Database** | novapay | rxdb | silodb | **quantdb** |

---

## Built For

Personal practice lab for Happy Afopezi targeting the Database Administrator (DBA) role at The Voleon Group ($155K-$195K + bonus). The environment, scenarios, and exercises are designed around Voleon's confirmed technology stack: PostgreSQL on Ceph RBD, containerized database workloads, Ansible automation, Redis caching, Prometheus/Grafana monitoring, and Python scripting - all in a quantitative finance context matching Voleon's AI/ML trading platform.
