# Lab: PostgreSQL Backup and Recovery

A comprehensive lab covering every backup and recovery method a PostgreSQL DBA
needs - from logical dumps to physical backups, point-in-time recovery, and
enterprise-grade backup management with pgBackRest.

## Objectives

By the end of this lab you can:

- Take and restore logical backups using pg_dump, pg_dumpall, and pg_restore
- Perform physical backups with pg_basebackup and WAL archiving
- Execute point-in-time recovery (PITR) to any moment in your database's history
- Install and operate pgBackRest for full, differential, and incremental backups
- Restore individual databases, tables, and specific points in time
- Explain the tradeoffs between each backup strategy and when to use which

## Prerequisites

- `postgres/streaming-replication` lab completed (you understand WAL, archiving, and replication)
- SSH access to 2 servers (provided by Happy)

## Architecture

```
+------------------------------+          +------------------------------+
|          NODE1                |          |          NODE2                |
|       pg-primary              |          |       pg-backup               |
|       CentOS Stream 9         |          |       CentOS Stream 9         |
|                               |          |                               |
|  PostgreSQL 16 (primary)      |   SSH    |  postgresql16 (client tools)   |
|  /opt/pgsql/data  (PGDATA)    | -------> |  pgBackRest (repo host)        |
|  /opt/pgsql/wal   (WAL)       |   rsync  |                               |
|  /opt/pgsql/log   (logs)      |   WAL    |  /opt/pgsql/backup/            |
|  /opt/pgsql/backup (local)    | -------> |    archive/                    |
|                               |          |    basebackup/                 |
|  Databases:                   |          |    logical/                    |
|  - labdb (5GB pgbench data)   |          |    dumps/                      |
|  - appdb (employees/depts)    |          |    pgbackrest/                 |
|  - blobdb (binary data)       |          |                               |
|                               |          |                               |
|  pgBackRest (pg host)         |          |                               |
|  archive_command -> pgbackrest|          |                               |
+------------------------------+          +------------------------------+
```

## Infrastructure

| Node | Hostname | Role | OS | Software |
| ---- | -------- | ---- | -- | -------- |
| NODE1 | pg-primary | PostgreSQL primary | CentOS Stream 9 | PostgreSQL 16, pgBackRest |
| NODE2 | pg-backup | Backup server | CentOS Stream 9 | postgresql16 (client), pgBackRest |

## Custom Mount Points (both nodes)

| Path | Purpose |
| ---- | ------- |
| `/opt/pgsql/data` | PGDATA (data directory) |
| `/opt/pgsql/wal` | WAL files (pg_wal symlinked here) |
| `/opt/pgsql/log` | PostgreSQL logs |
| `/opt/pgsql/backup` | Local backups, archive, pg_dump output |

## Topics Covered

| Section | Topic | Guide |
| ------- | ----- | ----- |
| 1 | Server preparation | `build/01-server-prep.md` |
| 2 | PostgreSQL + sample databases | `build/02-install-postgresql.md` |
| 3 | Logical backups (pg_dump, pg_dumpall) | `build/03-logical-backups.md` |
| 4 | Logical restores (psql, pg_restore) | `build/04-logical-restore.md` |
| 5 | Physical backups (pg_basebackup, WAL) | `build/05-physical-backup.md` |
| 6 | Point-in-time recovery (PITR) | `build/06-pitr.md` |
| 7 | pgBackRest installation + config | `build/07-install-pgbackrest.md` |
| 8 | pgBackRest operations | `build/08-pgbackrest-operations.md` |

## Phases

### Phase 1 - BUILD IT (~12-16 hours)

Follow the guides in `build/` in order (01 through 08). At the end, run
`build/verify.sh` to confirm your backup infrastructure is correctly set up.
Do not proceed to Phase 2 until verify passes.

### Phase 2 - USE IT (~2-4 hours)

Work through the exercises in `use/` in order. Complete the self-assessment
`checklist.md` when done. If you cannot answer every question confidently,
re-read the relevant BUILD guide.

### Phase 3 - SURVIVE IT (~3-5 hours across multiple sessions)

Tell Happy you are ready. He fires disaster scenarios against your cluster. You
get paged, diagnose, recover, and call for validation. Scenarios include data
corruption, accidental drops, storage failures, and more.

## Estimated total time

17-25 hours spread across 2-3 weeks. BUILD over multiple sessions. USE in one
sitting. SURVIVE across multiple on-call windows.
