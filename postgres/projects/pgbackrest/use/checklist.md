# pgBackRest - Self-Assessment Checklist

Use this checklist to verify you have mastered the skills from the BUILD guides and USE exercises. You should be able to answer "yes" to every item below.

If you cannot check an item, go back to the referenced exercise and work through it again.

---

## Core Knowledge

- [ ] Can you explain what pgBackRest does in one sentence?
  - *It is a backup and restore tool for PostgreSQL that supports full/differential/incremental backups, WAL archiving, and point-in-time recovery.*
  - Covered in: BUILD 01

- [ ] Can you explain what a stanza is?
  - *A stanza is a configuration section in pgBackRest that defines a specific PostgreSQL cluster and its backup settings.*
  - Covered in: BUILD 02

- [ ] Can you explain the difference between differential and incremental backups?
  - *A diff backs up all changes since the last full. An incr backs up all changes since the last backup of any type. Diff is safer (independent chain links); incr is smaller.*
  - Covered in: BUILD 05, USE 05

---

## Backup Operations

- [ ] Can you take a full backup?
  - `pgbackrest --stanza=main --type=full backup`
  - Covered in: BUILD 04

- [ ] Can you take a differential backup?
  - `pgbackrest --stanza=main --type=diff backup`
  - Covered in: BUILD 05

- [ ] Can you take an incremental backup?
  - `pgbackrest --stanza=main --type=incr backup`
  - Covered in: BUILD 05

- [ ] Can you check backup status and interpret pgbackrest info output?
  - `pgbackrest --stanza=main info`
  - *You should be able to read: backup type, timestamps, sizes, compression ratio, WAL archive range.*
  - Covered in: USE 01

---

## WAL Archiving

- [ ] Can you check if WAL archiving is working?
  - *Query pg_stat_archiver for last_archived_time, failed_count. Run pgbackrest --stanza=main check for end-to-end validation.*
  - Covered in: USE 02

- [ ] Can you explain what happens if WAL archiving stops?
  - *WAL files pile up in pg_wal, disk fills up, PostgreSQL crashes. You also lose the ability to do PITR for the gap period.*
  - Covered in: USE 02

---

## Restore and Recovery

- [ ] Can you restore from a backup?
  - *Stop PostgreSQL, run pgbackrest restore, start PostgreSQL.*
  - Covered in: BUILD 06, USE 03

- [ ] Can you perform PITR to a specific timestamp?
  - `pgbackrest --stanza=main --type=time --target="TIMESTAMP" --target-action=promote restore`
  - Covered in: BUILD 06, USE 04

- [ ] Can you explain why a new full backup is needed after PITR?
  - *PITR creates a new timeline. Old backups are on the old timeline and cannot serve as a base for new differential/incremental backups.*
  - Covered in: USE 04

---

## Scheduling and Retention

- [ ] Can you explain retention policies?
  - *Retention controls how many backups to keep. pgBackRest can auto-expire old backups based on count or time. Retention is driven by business needs, regulatory requirements, and storage constraints.*
  - Covered in: BUILD 07

- [ ] Can you set up automated backups with cron?
  - *Add pgbackrest commands to the postgres user's crontab: full weekly, diff or incr daily.*
  - Covered in: BUILD 07

---

## Strategy and Planning

- [ ] Can you explain RPO and RTO?
  - *RPO = maximum acceptable data loss (time). RTO = maximum acceptable downtime (time). These two numbers drive every backup design decision.*
  - Covered in: USE 05

- [ ] Can you design a backup strategy for a production database?
  - *Choose full backup frequency, diff/incr schedule, retention policy, monitoring alerts, and restore testing cadence - all based on RPO/RTO requirements.*
  - Covered in: USE 05

---

## How to Use This Checklist

1. **Before class ends:** Go through every item. Check the ones you can do confidently.
2. **Items you cannot check:** These are your study priorities. Revisit the referenced BUILD guide or USE exercise.
3. **The real test:** Can you do these tasks on a server with no notes in front of you? That is production-ready knowledge.
4. **Keep practicing:** Set up pgBackRest on a personal VM and run through these operations until they are second nature.
