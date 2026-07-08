# Linux & PostgreSQL DBA Training Track

A private, hands-on training path from Linux fundamentals through PostgreSQL mastery. Built with the CBUS methodology (Concepts, BUILD, USE, SURVIVE).

---

## Methodology

Every module follows the same four-phase cycle:

| Phase | What You Do | Goal |
|-------|-------------|------|
| **Concepts** | Read the reference material | Understand the "why" before the "how" |
| **BUILD** | Follow step-by-step guides on a real server | Build muscle memory with guided practice |
| **USE** | Complete exercises without handholding | Prove you can do it independently |
| **SURVIVE** | Fix chaos scenarios injected into your server | Learn to troubleshoot under pressure |

---

## Track 1: Linux for DBAs

Master the Linux skills every DBA needs - from basic navigation to performance tuning.

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 01 | [Linux Fundamentals](labs/linux/module01-linux-fundamentals/) | 6-8 hrs | 1 |
| 02 | [Users, Groups, and Ownership](labs/linux/module02-users-groups-ownership/) | 5-7 hrs | 1 |
| 03 | [Package Management](labs/linux/module03-package-management/) | 4-6 hrs | 1 |
| 04 | [Systemd and Service Management](labs/linux/module04-systemd-service-management/) | 5-7 hrs | 1 |
| 05 | [Storage, Disks, and LVM for DBAs](labs/linux/module05-storage-lvm-for-dbas/) | 6-8 hrs | 1 |
| 06 | [Networking for DBAs](labs/linux/module06-networking-for-dbas/) | 5-7 hrs | 1 |
| 07 | [Firewall and Security](labs/linux/module07-firewall-security/) | 5-7 hrs | 1 |
| 08 | [Shell Scripting for DBAs](labs/linux/module08-shell-scripting-for-dbas/) | 6-8 hrs | 1 |
| 09 | [Performance Monitoring](labs/linux/module09-performance-monitoring/) | 5-7 hrs | 1 |
| 10 | [Cron, Logging, and Log Rotation](labs/linux/module10-cron-logging/) | 4-6 hrs | 1 |

## Track 2: PostgreSQL DBA

The complete PostgreSQL 16 curriculum - from architecture through cloud deployment.

### Foundation (Modules 01-05)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 01 | [History and Evolution](labs/postgres/module01-history/) | 2 hrs | 0 (reading) |
| 02 | [Architecture](labs/postgres/module02-architecture/) | 7-9 hrs | 1 |
| 03 | [Installation](labs/postgres/module03-installation/) | 6-8 hrs | 1 |
| 04 | [Instance Management](labs/postgres/module04-instance-management/) | 7-9 hrs | 1 |
| 05 | [SQL Fundamentals](labs/postgres/module05-sql-fundamentals/) | 6-8 hrs | 1 |

### Security & Administration (Modules 06-08)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 06 | [Users, Roles, and Connections](labs/postgres/module06-users-roles-connections/) | 7-9 hrs | 1 |
| 07 | [Security, Privileges, and RLS](labs/postgres/module07-security-privileges-rls/) | 7-9 hrs | 1 |
| 08 | [MVCC and Vacuum](labs/postgres/module08-mvcc-vacuum/) | 7-9 hrs | 1 |

### Backup, Recovery & Monitoring (Modules 09-10, 15)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 09 | [Backup and PITR](labs/postgres/module09-backup-pitr/) | 8-10 hrs | 1 |
| 10 | [Monitoring](labs/postgres/module10-monitoring/) | 7-9 hrs | 1 |
| 15 | [Advanced Monitoring (Prometheus/Grafana)](labs/postgres/module15-advanced-monitoring/) | 8-10 hrs | 2 |

### Replication & High Availability (Modules 11)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 11a | [Streaming Replication](labs/postgres/module11-streaming-replication/) | 7-9 hrs | 2 |
| 11b | [Repmgr HA](labs/postgres/module11-repmgr-ha/) | 8-10 hrs | 3 |

### Performance & Advanced Topics (Modules 12-14)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 12 | [Performance Tuning](labs/postgres/module12-performance-tuning/) | 7-9 hrs | 1 |
| 13 | [Upgrades](labs/postgres/module13-upgrades/) | 6-8 hrs | 1 |
| 14 | [Partitioning](labs/postgres/module14-partitioning/) | 6-8 hrs | 1 |

### Cloud & DevOps (Modules 16-19)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 16 | [AWS RDS PostgreSQL](labs/postgres/module16-aws-rds/) | 6-8 hrs | managed |
| 17 | [Azure PostgreSQL](labs/postgres/module17-azure-postgresql/) | 6-8 hrs | managed |
| 18 | [GCP Cloud SQL](labs/postgres/module18-gcp-cloudsql/) | 6-8 hrs | managed |
| 19 | [DevOps for PostgreSQL](labs/postgres/module19-devops/) | 6-8 hrs | 1 |

### Capstone (Module 20)

| Module | Topic | Time | Nodes |
|--------|-------|------|-------|
| 20 | [Production Capstone](labs/postgres/module20-capstone/) | 8-10 hrs | 3 |

---

## How to Use This Repo

1. Your instructor will provision a CentOS Stream 9 server for you
2. You will receive a welcome email with your server IP and SSH key
3. Start with Module 01 and work through each module in order
4. Complete all four phases (Concepts -> BUILD -> USE -> SURVIVE) before moving on
5. Each module builds on the previous one - do not skip ahead

---

## Infrastructure

- **OS:** CentOS Stream 9
- **Cloud:** AWS EC2
- **SSH user:** ec2-user
- **Package manager:** dnf

---

## Getting Help

If you get stuck:
1. Re-read the BUILD guide for the step you are on
2. Check the Concepts reference for the module
3. Ask your instructor
