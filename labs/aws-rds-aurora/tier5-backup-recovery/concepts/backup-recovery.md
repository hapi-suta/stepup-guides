# Concepts: Backup, Recovery, and Lifecycle
## Tier 5 - AWS RDS and Aurora PostgreSQL

Read this before starting any BUILD guide. These concepts explain the "why" behind every command you will run.

---

## T5.1 Automated Backups, Manual Snapshots, Retention, and Copying

### How Automated Backups Work

RDS takes a full backup of your instance once per day during your backup window. Between those full backups, it continuously streams transaction logs (WAL for PostgreSQL) to S3. Together, these give you point-in-time recovery anywhere within your retention window.

```
Timeline diagram - Automated Backup System
===========================================

Day 1           Day 2           Day 3           Day 4
  |               |               |               |
  v               v               v               v
[FULL SNAPSHOT] [FULL SNAPSHOT] [FULL SNAPSHOT] [FULL SNAPSHOT]
  |_______________|_______________|_______________|
        ^               ^               ^
        |               |               |
  Continuous WAL logs stream to S3 between snapshots
  (This is what makes PITR possible at any second)

Retention Window = 7 days (default, max 35 days)
Everything older than 7 days is automatically deleted.
```

Key facts:
- Automated backups are stored in S3 managed by AWS (you cannot see the bucket directly)
- Deleting the RDS instance also deletes all automated backups by default
- You can take a "final snapshot" when deleting - this is a manual snapshot and persists

### Manual Snapshots

A manual snapshot is a user-triggered full backup. It is NOT deleted when the instance is deleted. It persists until you explicitly delete it.

```
Automated vs Manual Snapshot Comparison
========================================

AUTOMATED BACKUP                    MANUAL SNAPSHOT
- Triggered by AWS on schedule      - Triggered by you anytime
- Deleted with instance             - Survives instance deletion
- Retention: 1-35 days              - Retention: indefinite
- Used for PITR                     - Used for restore to that point only
- No extra cost within retention    - Costs $0.095/GB-month (approx)
- Cannot copy across accounts*      - Can copy across regions/accounts

* You CAN share automated backup snapshots, but need to copy first
```

### Cross-Region Copy

Copying a snapshot to another region is how you build geographic disaster recovery. The copy is a full standalone snapshot in the destination region.

```
Cross-Region Copy Flow
=======================

us-east-1                          eu-west-1
+-----------------------+          +-----------------------+
| Manual Snapshot       |  ------> | Copy of Snapshot      |
| suta-t5-snap-20250530 |  copy    | suta-t5-snap-20250530 |
|                       |          | (independent copy)    |
+-----------------------+          +-----------------------+

Network cost: Data transfer out of region
Storage cost: Full snapshot size in destination region
```

### Cross-Account Sharing

You can share a manual snapshot with another AWS account. The other account can then copy it into their own account.

```
Account Sharing Flow
=====================

Account A (123456789012)         Account B (987654321098)
+-------------------------+      +-------------------------+
| Manual Snapshot         |      | Cannot access yet       |
| "suta-t5-snap"          |      |                         |
|                         |      |                         |
| Modify permissions:     | ---> | Can now see the shared  |
| + Add account B         |      | snapshot                |
+-------------------------+      |                         |
                                 | Account B copies it to  |
                                 | own account to use it   |
                                 +-------------------------+
```

---

## T5.2 Point-In-Time Recovery (PITR)

### How PITR Works

PITR works because RDS saves your full daily snapshots PLUS all the WAL (Write-Ahead Log) records generated between those snapshots. To recover to a specific time, AWS:

1. Takes the most recent full snapshot before your target time
2. Replays all WAL records up to your target time
3. Returns a brand-new RDS instance at that exact state

```
PITR Recovery Mechanics
========================

            Your target: Tuesday 14:37:22

Day 1 (Mon)            Day 2 (Tue)            Day 3 (Wed)
00:00                  00:00                  00:00
  |                      |                      |
  v                      v                      v
[FULL SNAP]--WAL--WAL--[FULL SNAP]--WAL--WAL--[FULL SNAP]
                          |___WAL replay___|
                          ^               ^
                    snapshot at        your target
                    Day 2 00:00        14:37:22

AWS starts from Day 2 full snapshot, then applies 14 hours
and 37 minutes of WAL records to reach your target.
```

### What PITR Creates

PITR always creates a NEW instance. It does NOT modify your existing database. This is important: your original instance keeps running. You get a separate restored instance, rename it, update your connection string, and decommission the original.

```
PITR Creates a New Instance
============================

BEFORE PITR:
  [Original DB] - running, has corrupted/deleted data

AFTER PITR:
  [Original DB] - still running (you leave it alone)
  [Restored DB] - new instance, data state from target time

YOUR JOB:
  1. Verify restored DB has the right data
  2. Update application connection string to restored DB
  3. Delete original DB (or keep it temporarily)
```

### Recovery Window

The recovery window is defined by your backup retention period. If retention is 7 days, you can restore to any second in the last 7 days. You can check the "Latest Restorable Time" in the console or CLI - it lags a few minutes behind real-time because WAL needs to be uploaded to S3.

---

## T5.3 Aurora Fast Database Cloning (Copy-on-Write)

### The Problem with Traditional Restores

A traditional restore (from snapshot) copies all data physically. A 2 TB database takes hours to restore because AWS has to copy 2 TB of data.

### How Fast Clone Works (Copy-on-Write)

Aurora Fast Clone does NOT copy data initially. Both the original and the clone point to the same underlying storage pages. Only when a page is modified (by either the original or the clone) does Aurora create a separate physical copy of that page.

```
Aurora Copy-on-Write Clone Mechanics
======================================

IMMEDIATELY AFTER CLONE (near-instant):
  Original Cluster          Clone Cluster
  +--------------+          +--------------+
  |              |          |              |
  | Points to -> | =======> | Points to -> |
  |  Storage A   |          |  Storage A   |
  +--------------+          +--------------+
         ^                        ^
         |________________________|
                    |
             Shared pages
             (no data copied yet)

AFTER WRITES TO CLONE:
  Original Cluster          Clone Cluster
  +--------------+          +--------------+
  | Points to -> |          | Points to -> |
  |  Storage A   |          |  Storage A   |  <- unchanged pages
  |              |          |  Storage B   |  <- modified pages (new copy)
  +--------------+          +--------------+
```

### Clone vs Restore vs Snapshot Restore

```
Comparison: Three Ways to Get a Copy
======================================

                    FAST CLONE       RESTORE FROM    SNAPSHOT
                    (Aurora only)    SNAPSHOT        RESTORE

Time to create      Seconds          Hours           Hours
Initial cost        Near zero        Full copy cost  Full copy cost
Ongoing cost        Changed pages    Full copy       Full copy
Cross-cluster?      Same account     Any             Any
Cross-region?       No               Yes             Yes
Best for            Dev/test copies  DR              Archive restore
Modifies original?  No               No              No
```

### Primary Use Case

Fast clone is ideal for testing schema changes against real production data. You clone production, run your ALTER TABLE or data migration on the clone, verify it works, then apply to production with confidence.

---

## T5.4 Engine Version Upgrades

### Minor vs Major Upgrades

```
Version Number Anatomy
=======================

  15  .  4  .  2
  ^       ^     ^
  |       |     |
Major   Minor  Patch

MINOR UPGRADE: 16.4 -> 16.6 (same major version)
- Usually backward compatible
- Can be automatic (if auto minor upgrade enabled)
- Generally low risk
- Requires a reboot

MAJOR UPGRADE: 14.x -> 15.x (different major version)
- NOT backward compatible in some cases
- Always manual - AWS will not do this automatically
- Higher risk - requires pre-upgrade testing
- Requires a reboot (and longer maintenance window)
- Extensions may need upgrading too
```

### Pre-Upgrade Checks

Before a major upgrade you should check:
- Extensions: are all installed extensions available in the new version?
- Parameter groups: custom parameters may not exist or have different defaults
- SQL compatibility: deprecated syntax or functions
- Application drivers: does your app's PostgreSQL driver support the new version?

AWS provides a pre-upgrade check via the `--no-apply-immediately` flag behavior and the `describe-db-engine-versions` CLI command.

### Upgrade Flow

```
Safe Major Upgrade Flow
========================

1. Create manual snapshot (your rollback point)
2. Test upgrade on a clone or non-production instance
3. Review pre-upgrade logs for warnings
4. Schedule upgrade in low-traffic maintenance window
5. Monitor application after upgrade
6. If OK: delete old snapshot after 1 week
7. If FAIL: restore from snapshot taken in step 1

ROLLBACK: You cannot downgrade an RDS instance in-place.
Rollback means restoring from the pre-upgrade snapshot.
```

---

## T5.5 Blue/Green Deployments

### What Blue/Green Means

Blue is your current production. Green is a copy that receives the same writes via logical replication. When you are ready, you switchover - green becomes production, blue becomes standby or is deleted.

```
Blue/Green Deployment Architecture
====================================

                    BEFORE SWITCHOVER

Application
    |
    v
[BLUE - Production]  ---logical replication--->  [GREEN - Staging]
(current version,                                 (new version,
 old schema,                                       new schema,
 receiving all writes)                             receiving replicated writes)
    ^
    |
 Traffic

                    AFTER SWITCHOVER

Application
    |
    v
[GREEN - Now Production]     [BLUE - Now Standby/Deleted]
(new version, new schema,    (kept for rollback, then deleted)
 receiving all writes)
```

### Logical Replication

Blue/Green uses PostgreSQL logical replication (not physical). This means:
- You can upgrade the major engine version between blue and green
- You can make schema changes on green before switchover
- Replication lag must be near zero before switchover is safe

### Switchover Behavior

During switchover:
1. AWS stops new writes to blue (brief write pause, typically under 1 minute)
2. Green catches up on any remaining replication lag
3. DNS endpoint is updated to point to green
4. Green becomes primary

Applications that retry on connection failure handle this transparently.

---

## T5.6 Maintenance Windows, OS Patching, and Reboots

### Maintenance Window

Every RDS instance has a weekly maintenance window - a 30-minute window where AWS can apply patches. You choose the day and time. AWS uses this window for:
- OS patching
- Minor engine version upgrades (if auto minor upgrade is on)
- Security patches

```
Maintenance Window Timing
==========================

Weekly schedule example: Sun 03:00-03:30 UTC

Mon  Tue  Wed  Thu  Fri  Sat  Sun
                               |
                           [WINDOW]
                           03:00-03:30 UTC

AWS may patch here. If nothing needs patching, nothing happens.
If there is a pending maintenance action, it fires here.
```

### Multi-AZ During Patching

With Multi-AZ enabled, AWS patches the standby first, then fails over, then patches the old primary. You get a brief failover event (typically 20-60 seconds) but no extended downtime.

```
Multi-AZ Patching Sequence
============================

Step 1: Patch standby (no impact to production)
  [Primary AZ-a] (serving traffic)
  [Standby AZ-b] <-- being patched

Step 2: Failover - standby becomes primary
  [Old Primary AZ-a] (now standby)   Brief blip ~30 seconds
  [New Primary AZ-b] (serving traffic)

Step 3: Patch old primary (now standby)
  [Standby AZ-a] <-- being patched
  [Primary AZ-b] (serving traffic)

Total downtime: ~30 seconds (just the failover)
```

### Reboot Behavior

A reboot is needed when:
- You change a static parameter in a parameter group (dynamic parameters apply without reboot)
- AWS needs to apply an OS patch
- You are doing a manual minor or major version upgrade

A reboot of a Multi-AZ instance can optionally failover to the standby first. This is called a "reboot with failover" and reduces downtime.

### Pending Maintenance Actions

AWS queues pending maintenance actions. You can see them in the console ("Maintenance" column). States:
- `required` - will be applied at next maintenance window
- `available` - you can choose when to apply
- `next-maintenance` - scheduled for next window
- `in-progress` - being applied now

You can apply pending maintenance early using the console or CLI to avoid surprises.
