# Module 06: Backup, Recovery and Lifecycle

**Track:** DevOps DBA Training
**Duration:** ~12 hours
**Week:** 4
**Prerequisites:** Module 01-05

---

## What You Will Learn

This module covers how to protect data and manage Aurora over its lifecycle. By the end, you will:

- Understand Aurora continuous backups and how they differ from traditional snapshot-based backups
- Configure automated backup retention and manual snapshots
- Perform point-in-time recovery (PITR) to restore data to any second within the retention window
- Clone clusters for testing without doubling storage costs
- Export snapshots to S3 for long-term archival and compliance
- Plan and manage maintenance windows with minimal downtime

---

## Module Contents

### Concepts (read first)
1. [Backup Strategies](concepts/01-backup-strategies.md) - Continuous backups, snapshots, PITR, backup retention, RPO implications
2. [Lifecycle Management](concepts/02-lifecycle-management.md) - Versioning, upgrades, maintenance windows, end-of-life planning

### BUILD (hands-on, follow step by step)
1. [Automated Backups](build/01-automated-backups.md) - Verify continuous backup, set retention period (20 min)
2. [Manual Snapshots](build/02-manual-snapshots.md) - Create, copy, and share snapshots (30 min)
3. [Point-in-Time Recovery](build/03-point-in-time-recovery.md) - Insert data, delete it, restore to the second before (45 min)
4. [Cluster Cloning](build/04-cluster-cloning.md) - Clone for dev/test, verify copy-on-write behavior (30 min)
5. [Snapshot Export to S3](build/05-snapshot-export-to-s3.md) - Export to Parquet, set up IAM role and KMS key (45 min)
6. [Maintenance Windows](build/06-maintenance-windows.md) - Schedule windows, test minor version upgrade (30 min)

### USE (practice with less hand-holding)
1. [Backup Strategy Exercise](use/01-backup-strategy-exercise.md)
2. [PITR Recovery Exercise](use/02-pitr-recovery-exercise.md)
3. [Clone Testing Exercise](use/03-clone-testing-exercise.md)
4. [Snapshot Management Exercise](use/04-snapshot-management-exercise.md)
5. [Disaster Recovery Exercise](use/05-disaster-recovery-exercise.md)

### SURVIVE (break it, fix it)
1. [Accidental Table Drop](survive/01-accidental-table-drop/) - Recover a dropped table using PITR
2. [Snapshot Restore Failure](survive/02-snapshot-restore-failure/) - Diagnose why a restore fails and fix it
3. [Backup Retention Expired](survive/03-backup-retention-expired/) - Data needed beyond retention window, find alternatives
4. [Clone Divergence](survive/04-clone-divergence/) - Clone drifted from production, reconcile safely
5. [Maintenance Window Surprise](survive/05-maintenance-window-surprise/) - Unplanned patching during peak hours, respond and reschedule

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## What is Next

After completing this module, you will move to [Module 07: Performance, Monitoring and Observability](../module07-performance-monitoring-observability/) where you build dashboards, set up alerts, and learn to diagnose performance problems.

---

## Cost Warning

Snapshot storage and PITR testing cost approximately $1-2 per session. Cluster clones use copy-on-write storage so initial cost is near zero - charges grow only as the clone diverges. Delete test snapshots and clones when finished to avoid ongoing storage charges.
