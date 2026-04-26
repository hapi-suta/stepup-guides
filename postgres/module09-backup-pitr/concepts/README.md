# Concepts - Backup and Recovery

Read these before starting the BUILD guides. They explain the WHY behind each tool, architecture decision, and configuration choice you'll encounter in the labs.

## Documents

| Document | Topic | Description |
| -------- | ----- | ----------- |
| [backup-and-recovery.md](backup-and-recovery.md) | Backup & Recovery | Logical backups (pg_dump/pg_restore), physical backups (WAL archiving, pg_basebackup), PITR (recovery targets, timelines, side-restore), RPO/RTO, backup strategy design, format comparison, troubleshooting |
| [pgbackrest.md](pgbackrest.md) | pgBackRest | Architecture, core concepts, features, configuration patterns, best practices, and troubleshooting for pgBackRest - the enterprise backup tool used in Build Guides 07-08 |
