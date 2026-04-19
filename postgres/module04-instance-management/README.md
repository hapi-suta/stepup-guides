# Module 04 - Creating and Managing Instances

How to create, configure, and manage PostgreSQL clusters and instances. Students master initdb, postgresql.conf tuning with conf.d/, pg_hba.conf, ALTER SYSTEM, pg_ctl vs systemctl, shutdown modes, and health checks.

## BUILD Guides

| Guide | Title | Duration |
|-------|-------|----------|
| 01 | Create Your First Cluster with initdb | 30 min |
| 02 | PostgreSQL Configuration Mastery | 75 min |
| 03 | Managing Multiple Clusters | 60 min |
| 04 | Server Start, Stop, and Health Checks | 30 min |

## USE Exercises

| Exercise | Title | Duration |
|----------|-------|----------|
| 01 | initdb Detective | 20 min |
| 02 | Configuration Scavenger Hunt | 25 min |
| 03 | Tuning Challenge | 30 min |
| 04 | Multi-Cluster Operations | 25 min |
| 05 | Shutdown Scenarios | 20 min |
| 06 | Cross-Platform Cluster Management | 20 min |

## SURVIVE Scenarios

| Scenario | Title | Severity |
|----------|-------|----------|
| 01 | postgresql.conf Syntax Error | CRITICAL |
| 02 | Shared Buffers Too High | CRITICAL |
| 03 | Max Connections Exhausted | HIGH |
| 04 | Stale Postmaster PID | HIGH |
| 05 | Data Checksums Mismatch | MEDIUM |
| 06 | ALTER SYSTEM Lock | MEDIUM |
| 07 | Listen Address Wrong | HIGH |
| 08 | WAL Directory Missing | CRITICAL |
| 09 | Conflicting conf.d Override | HIGH |
| 10 | pg_hba.conf Blocks Connections | CRITICAL |

## Topics

- initdb and pg_controldata
- Data checksums
- postgresql.conf, postgresql.auto.conf, pg_hba.conf
- conf.d/ include directory pattern
- ALTER SYSTEM and RESET
- pg_settings view (context, source, sourcefile, pending_restart)
- pg_hba.conf rule evaluation (first match wins)
- pg_ctl modes (start, stop -m smart/fast/immediate, reload)
- pg_ctl vs systemctl
- pg_isready health checks
- postmaster.pid anatomy
- Multi-cluster management
- Cross-platform: CentOS vs Ubuntu/Debian (pg_lsclusters, pg_createcluster)

## Prerequisites

- CentOS Stream 9 with PostgreSQL 16 installed (from backup-pitr lab)
- PG15 installed on port 5433 (from Module 03)
- Single node (NODE1 only)

## Status

Built - pending live server validation.
