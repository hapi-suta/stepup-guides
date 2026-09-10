# SUTA Labs - PostgreSQL Hands-On Guides

Step-by-step lab guides for learning PostgreSQL administration. Built from real production experience across 20+ companies and 15,000+ databases.

## Available Labs

| Module | Topic | BUILD | USE | SURVIVE |
|--------|-------|-------|-----|---------|
| [01 - History](postgres/module01-history/) | PostgreSQL History and Evolution | - | - | - |
| [02 - Architecture](postgres/module02-architecture/) | Process, Memory, Storage, Query Pipeline | 4 | 7 | 10 |
| [03 - Installation](postgres/module03-installation/) | PostgreSQL Installation on Linux | 4 | 6 | 8 |
| [04 - Instance Management](postgres/module04-instance-management/) | Start, Stop, Configuration, Logging | 4 | 7 | 10 |
| [05 - SQL Fundamentals](postgres/module05-sql-fundamentals/) | DDL, DML, Joins, Aggregations | 5 | 6 | 8 |
| [06 - Users, Roles, Connections](postgres/module06-users-roles-connections/) | Authentication, Roles, pg_hba.conf | 5 | 6 | 10 |
| [07 - Security & RLS](postgres/module07-security-privileges-rls/) | Privileges, Row-Level Security, pgAudit | 5 | 6 | 10 |
| [08 - MVCC & Vacuum](postgres/module08-mvcc-vacuum/) | MVCC Internals, Vacuum, Autovacuum, Wraparound | 5 | 6 | 10 |
| [09 - Backup & PITR](postgres/module09-backup-pitr/) | Logical/Physical Backup, PITR, pgBackRest | 8 | 7 | 10 |
| [10 - Monitoring](postgres/module10-monitoring/) | pg_stat Views, Log Analysis, Alerting | 5 | 6 | 10 |
| [11 - Streaming Replication](postgres/module11-streaming-replication/) | Primary/Standby, WAL Shipping | 5 | 5 | 1 |
| [11 - Repmgr HA](postgres/module11-repmgr-ha/) | Repmgr, Automated Failover, Switchover | 7 | 6 | 10 |
| [12 - Performance Tuning](postgres/module12-performance-tuning/) | EXPLAIN, Indexing, Memory, Query Optimization | 12 | 10 | 11 |
| [13 - Upgrades](postgres/module13-upgrades/) | pg_upgrade, pg_dump, Version Migration | 4 | 5 | 8 |
| [14 - Partitioning](postgres/module14-partitioning/) | Range, List, Hash Partitioning | 4 | 5 | 8 |
| [15 - Advanced Monitoring](postgres/module15-advanced-monitoring/) | Advanced Observability | - | - | - |
| [16 - AWS RDS](postgres/module16-aws-rds/) | RDS, Aurora, Parameter Groups, Snapshots | 5 | 6 | 8 |
| [17 - Azure PostgreSQL](postgres/module17-azure-postgresql/) | Azure Database for PostgreSQL | 5 | 6 | 8 |
| [18 - GCP Cloud SQL](postgres/module18-gcp-cloudsql/) | Cloud SQL for PostgreSQL | 5 | 6 | 8 |
| [19 - DevOps](postgres/module19-devops/) | CI/CD, Terraform, Ansible, Flyway | 5 | 6 | 8 |
| [20 - Capstone](postgres/module20-capstone/) | Full Stack DBA Project | 5 | 6 | 8 |

### Instructor-led classroom

[Patroni HA with an instructor-provided app](labs/postgres/patroni-mattermost-ha/classroom/README.md) — configure etcd, Patroni and HAProxy, then verify the application.

### Standalone Projects

| Project | Topic | BUILD | USE | SURVIVE |
|---------|-------|-------|-----|---------|
| [pgBackRest](postgres/projects/pgbackrest/) | Dedicated pgBackRest Deep Dive | 7 | 6 | 8 |

## How to Use

1. Your instructor will provide you with server IPs and SSH keys
2. Follow the BUILD guides in order for your assigned module
3. Each guide builds on the previous one - do not skip ahead
4. After BUILD, work through USE exercises to reinforce what you learned
5. SURVIVE scenarios simulate real production incidents for you to diagnose and fix
6. Message your instructor when you complete each phase

## Lab Structure

Each lab follows the **BUS methodology** (BUILD - USE - SURVIVE):

- **build/** - Step-by-step setup guides (start here)
- **use/** - Practice exercises that reinforce BUILD knowledge
- **survive/** - Real-world incident runbooks and troubleshooting scenarios
- **concepts/** - Reference material and deep-dive explanations

## Questions?

Contact your instructor for help with any step.

<!-- branch-protection end-to-end test, 2026-08-17 -->
