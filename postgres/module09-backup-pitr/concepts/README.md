# Concepts - Backup and Recovery

Reference documents that explain the theory and architecture behind PostgreSQL
backup and recovery tools. Read these before or alongside the build guides to
understand the WHY behind each configuration choice.

## Documents

| Document | Topic | Description |
| -------- | ----- | ----------- |
| [pgbackrest.md](pgbackrest.md) | pgBackRest | Architecture, core concepts, features, configuration patterns, best practices, and troubleshooting for pgBackRest - the primary backup tool used in this lab |

## Planned

The following concept documents will be added as the lab expands:

| Document | Topic |
| -------- | ----- |
| `wal-archiving.md` | WAL internals, archive modes, continuous archiving vs streaming |
| `pitr.md` | Point-in-time recovery theory, timelines, recovery targets |
| `logical-vs-physical.md` | When to use pg_dump vs pg_basebackup vs pgBackRest |
| `backup-strategies.md` | Designing backup schedules, RTO/RPO planning, the 3-2-1 rule |
