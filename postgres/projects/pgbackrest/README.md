# pgBackRest - Backup and Recovery

Learn enterprise-grade PostgreSQL backup management using pgBackRest. This project takes you from installation through full and incremental backups, point-in-time recovery, retention policies, and real-world failure scenarios.

---

## Architecture

Single-server setup with PostgreSQL and pgBackRest on the same machine:

```
┌──────────────────────────────────────────────────────────┐
│                  pg-backup (CentOS Stream 9)             │
│                                                          │
│   PostgreSQL 16              pgBackRest Repository       │
│   /opt/pgsql/data            /opt/pgsql/backup/          │
│        │                       pgbackrest/               │
│        │  archive-push            │                      │
│        └────────────────────────> │  archive/main/       │
│        │  restore (archive-get)   │  backup/main/        │
│        <──────────────────────────┘                      │
│                                                          │
│   Databases:                                             │
│   - labdb (~800 MB, pgbench)                             │
│   - appdb (employees, departments)                       │
│                                                          │
│   Config: /etc/pgbackrest.conf                │
└──────────────────────────────────────────────────────────┘
```

---

## Server Details

| Property | Value |
|---|---|
| **Hostname** | pg-backup |
| **OS** | CentOS Stream 9 |
| **Instance type** | t3.small (2 vCPU, 2 GB RAM) |
| **PostgreSQL** | 16 |
| **PGDATA** | `/opt/pgsql/data` |
| **pgBackRest repo** | `/opt/pgsql/backup/pgbackrest` |
| **pgBackRest config** | `/etc/pgbackrest.conf` |
| **Stanza name** | `main` |
| **Databases** | `labdb` (~800 MB pgbench), `appdb` (employees/departments) |

---

## BUILD Guides

Step-by-step instructions to set up pgBackRest from scratch. Complete these in order.

| # | Guide | Estimated Time |
|---|---|---|
| 01 | [Install pgBackRest](build/01-install-pgbackrest.md) | 20 min |
| 02 | [Configure Stanza](build/02-configure-stanza.md) | 20 min |
| 03 | [WAL Archiving](build/03-wal-archiving.md) | 25 min |
| 04 | [Full Backup](build/04-full-backup.md) | 20 min |
| 05 | Differential and Incremental Backups | 30 min |
| 06 | Restore and Point-in-Time Recovery | 40 min |
| 07 | Retention Policies and Scheduling | 25 min |
| | **Total** | **~3 hours** |

---

## USE Exercises

Hands-on practice using pgBackRest in realistic scenarios. Requires completed BUILD guides.

| # | Exercise | Estimated Time |
|---|---|---|
| 01 | [Backup Inventory](use/01-backup-inventory.md) | 20 min |
| 02 | [WAL Archiving Health](use/02-wal-archiving-health.md) | 25 min |
| 03 | Restore Drill | 25 min |
| 04 | PITR Precision | 30 min |
| 05 | Backup Strategy Design | 20 min |
| | **Total** | **~2 hours** |

---

## SURVIVE Scenarios

Chaos engineering exercises. Each scenario injects a real failure and gives you a runbook to diagnose and fix it.

| # | Scenario | Severity |
|---|---|---|
| 01 | [Stanza Misconfigured](survive/01-stanza-misconfigured/) | Low |
| 02 | [Archive Command Broken](survive/02-archive-command-broken/) | High |
| 03 | [Repository Corruption](survive/03-repo-corruption/) | Critical |
| 04 | [Backup Expiry Crisis](survive/04-backup-expiry-crisis/) | High |
| 05 | [WAL Accumulation](survive/05-wal-accumulation/) | High |
| 06 | [Restore - Wrong PITR Target](survive/06-restore-wrong-target/) | Medium |
| 07 | [Full Cluster Recovery](survive/07-full-cluster-recovery/) | Critical |
| 08 | [Backup Verification Failure](survive/08-backup-verification-failure/) | Medium |
| | **Total** | **~3 hours** |

---

## Concepts

Reference material - read before the BUILD guides or use during labs.

| Document | Description |
|---|---|
| [pgBackRest Fundamentals](concepts/pgbackrest-fundamentals.md) | Architecture, backup types, WAL archiving, restore/PITR, retention, configuration, monitoring, troubleshooting |

---

## Prerequisites

- SSH access to your server as `ec2-user`
- PostgreSQL 16 installed and running
- Basic SQL knowledge (SELECT, INSERT, CREATE TABLE)
- Familiarity with Linux command line (cd, ls, cat, vi)

---

## Learning Path

```
1. CONCEPTS (read/lecture)     ~40 min    Read the fundamentals document
       │
       v
2. BUILD (hands-on)           ~3 hours   Follow guides 01-07 in order
       │
       v
3. USE (practice)             ~2 hours   Complete exercises 01-05
       │
       v
4. SURVIVE (chaos)            ~3 hours   Run scenarios 01-08
```

**Recommended approach:**

1. **Concepts first** - Read [pgBackRest Fundamentals](concepts/pgbackrest-fundamentals.md) before touching the keyboard. This gives you the mental model for understanding what each BUILD step does and why.
2. **BUILD in order** - Each guide builds on the previous one. Do not skip ahead.
3. **USE after BUILD** - The exercises assume you have a working pgBackRest setup with backups already taken.
4. **SURVIVE last** - The chaos scenarios assume you can diagnose problems. The BUILD and USE phases give you that experience.

**Total estimated time: ~9 hours** (including concepts reading)
