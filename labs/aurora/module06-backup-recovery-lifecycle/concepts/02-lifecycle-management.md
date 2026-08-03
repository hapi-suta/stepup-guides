# Concepts: Lifecycle Management for Aurora PostgreSQL
## Module 06 - Backup, Recovery, and Lifecycle

This document covers how to manage the lifecycle of your Aurora PostgreSQL cluster - major upgrades, blue-green deployments, maintenance windows, and planning for long-term operations.

---

## 1. Engine Version Upgrades

### Minor vs Major Upgrades

```
Version Number Anatomy
========================

  16  .  4
  ^      ^
  |      |
Major   Minor

MINOR UPGRADE: 16.2 -> 16.4 (same major version)
- Usually backward compatible
- Can be automatic (if auto minor upgrade enabled)
- Low risk
- Requires a brief restart

MAJOR UPGRADE: 15.x -> 16.x (different major version)
- NOT guaranteed backward compatible
- Always manual - AWS will not do this automatically
- Higher risk - requires pre-upgrade testing
- Extensions may need upgrading
- Parameter groups may change
```

### Pre-Upgrade Checklist

Before any major upgrade, check these items:

```
PRE-MAJOR-UPGRADE CHECKLIST
==============================

[ ] 1. Manual snapshot taken (your rollback point)
[ ] 2. All extensions verified as available in target version
[ ] 3. Custom parameter group created for target version
[ ] 4. Application tested against target version on a clone
[ ] 5. Application team informed of maintenance window
[ ] 6. Rollback procedure documented and shared
[ ] 7. Monitoring alerts reviewed (may need threshold adjustments)
[ ] 8. Read release notes for breaking changes:
        https://www.postgresql.org/docs/release/
[ ] 9. Upgrade tested on a non-production clone
[ ] 10. Upgrade scheduled in low-traffic window
```

### Rollback Strategy

You cannot downgrade an Aurora cluster in-place. Rollback means restoring from the pre-upgrade snapshot.

```
Rollback Procedure
====================

1. Take manual snapshot BEFORE upgrade (your safety net)
2. Attempt upgrade
3. If upgrade fails or application breaks:
   a. Restore from pre-upgrade snapshot -> new cluster
   b. Verify data integrity on restored cluster
   c. Update application connection string to restored cluster
   d. Delete the failed upgraded cluster

IMPORTANT: Data written between upgrade start and rollback is LOST.
Keep the upgrade window as short as possible.
Stop writes during major upgrades if you can.
```

---

## 2. Blue/Green Deployments

### What Blue/Green Means

Blue is your current production cluster. Green is a copy that receives the same writes via logical replication. When ready, you switchover - Green becomes production, Blue becomes standby.

```
Blue/Green Deployment Architecture
====================================

                BEFORE SWITCHOVER

Application
    |
    v
[BLUE - Production]  ---logical replication--->  [GREEN - Staging]
(current version,                                 (new version,
 current schema,                                   new schema,
 receiving all writes)                             receiving replicated writes)

                AFTER SWITCHOVER

Application
    |
    v
[GREEN - Now Production]     [BLUE - Now Standby/Deleted]
(new version, new schema,    (kept for rollback, then deleted)
 receiving all writes)
```

### Why Blue/Green Is Better Than In-Place Upgrades

```
Comparison: Blue/Green vs In-Place Upgrade
=============================================

                    BLUE/GREEN              IN-PLACE UPGRADE
Write pause         ~30-60 seconds          10-60 minutes
Rollback            Switch back to Blue     Restore from snapshot
                    (seconds)               (30-60 minutes)
Test before cutover Yes (test on Green)     No
Schema changes      Can apply to Green      Must apply after upgrade
Cost during prep    2x instance cost        No extra cost
Complexity          Higher                  Lower
```

### Logical Replication Under the Hood

Blue/Green deployments use PostgreSQL logical replication internally. AWS manages this automatically, but understanding it helps troubleshoot issues.

```
Logical Replication Flow
==========================

[Blue Cluster]
    |
    | WAL generated on every write
    | (INSERT/UPDATE/DELETE)
    v
[Logical Decoding]
    |
    | Decodes WAL into logical change events
    | (not physical page-level changes)
    v
[Replication Stream]
    |
    | Transmitted to Green via network
    v
[Green Cluster]
    |
    | Applies changes as SQL-level operations
    v
[Green is now in sync with Blue]
```

Key implications:
- Large objects (LOBs) and certain data types may have limitations
- Logical replication requires `wal_level = logical` (AWS sets this automatically)
- Replication slots retain WAL on Blue until Green confirms receipt
- A stuck Green can cause WAL accumulation on Blue

### Switchover Behavior

```
Switchover Sequence (typically 30-60 seconds)
================================================

1. AWS stops new writes to Blue (brief write pause)
2. Green catches up on any remaining replication lag
3. AWS updates the DNS endpoint to point to Green
4. Green becomes the new primary (accepts writes)
5. Blue becomes read-only standby

Your application:
- Same endpoint hostname - DNS resolves to Green now
- Applications that retry on connection failure reconnect automatically
- Applications without retry logic may see brief errors during switchover
```

### Replication Lag

Replication lag is the time difference between the most recent write on Blue and the most recently applied write on Green.

```
Replication Lag
=================

Blue: last write at 14:42:00.000
Green: last applied at 14:41:58.500
                         ^
                         |
                    Lag: 1.5 seconds

Lag < 1 second:  Excellent - safe to switchover
Lag 1-5 seconds: Acceptable - monitor closely
Lag > 5 seconds: Concerning - investigate before switching
Lag > 30 seconds: Do NOT switchover - fix the cause first

Common causes of high lag:
- Long-running transaction on Blue blocking replication slot
- Heavy write workload exceeding Green's apply capacity
- Network congestion between Blue and Green
- Green instance undersized (CPU/IO bottleneck)
```

---

## 3. Maintenance Windows

### What the Maintenance Window Is

Every Aurora cluster has a weekly maintenance window - a 30-minute window where AWS can apply patches.

```
Maintenance Window Purpose
============================

Weekly schedule example: Sun 03:00-03:30 UTC

Mon  Tue  Wed  Thu  Fri  Sat  Sun
                                |
                            [WINDOW]
                            03:00-03:30 UTC

AWS may apply during this window:
- Operating system patches
- Minor engine version upgrades (if auto minor upgrade is on)
- Security patches
- Hardware maintenance

If nothing needs patching, nothing happens.
The window is just the ALLOWED time, not a guaranteed action.
```

### Maintenance Window vs Backup Window

These are different windows and must NOT overlap.

```
Window Separation
===================

Backup window:      08:00-09:00 UTC  (automated backup)
Maintenance window: 03:00-03:30 UTC  (patching/upgrades)

These CANNOT overlap. AWS enforces this.
If you set them to the same time, the API returns an error.
```

### Pending Maintenance Actions

AWS queues maintenance actions that need to be applied. You can see them and choose when they fire.

```
Pending Maintenance Action States
====================================

required          - Will be applied at next window. Cannot be stopped.
available         - You choose when to apply.
next-maintenance  - Scheduled for next maintenance window.
in-progress       - Being applied right now.

AutoAppliedAfterDate:
  This is the DEADLINE. After this date, AWS will apply the action
  at the next maintenance window regardless of your preference.

  Example: AutoAppliedAfterDate = June 15, 2026
  Your window is Sunday. AWS will force-apply on June 21 (next Sunday
  after the deadline).

  You can apply it BEFORE the deadline on your own schedule.
```

---

## 4. Multi-AZ and Maintenance Impact

### How Multi-AZ Reduces Maintenance Downtime

```
Single-AZ During Patching
============================

03:00 UTC - Window opens
03:01 UTC - AWS begins OS patch
03:01 UTC - Cluster goes offline (downtime starts)
            Application sees connection errors
03:04 UTC - Cluster comes back (downtime ends)
            ~3-5 minutes of downtime
03:30 UTC - Window closes

Multi-AZ During Patching
============================

03:00 UTC - Window opens
03:01 UTC - AWS patches reader instance first (no impact)
03:04 UTC - Reader patching complete
03:04 UTC - Failover: reader becomes writer (20-60 sec blip)
            Application reconnects automatically
03:05 UTC - Old writer is now reader, gets patched
03:08 UTC - Both instances patched, old writer returns as reader
03:30 UTC - Window closes

Total production impact: ~30 second failover event
```

This is the primary reason to have at least one reader instance in your Aurora cluster for any database that cannot tolerate minutes of downtime during patching.

---

## 5. Parameter Changes and Reboots

### Static vs Dynamic Parameters

```
Parameter Types
=================

DYNAMIC parameters (e.g., work_mem, log_min_duration_statement):
  - Apply immediately without restart
  - Status shows "in-sync"
  - Safe to change anytime

STATIC parameters (e.g., max_connections, shared_buffers):
  - Staged in parameter group
  - Require instance restart to take effect
  - Status shows "pending-reboot" until restarted

To check if a restart is needed:
  Look at DBClusterParameterGroup.ParameterApplyStatus
  "in-sync"       -> no restart needed
  "pending-reboot" -> restart needed to apply static params
```

---

## 6. Upgrade Planning Best Practices

### The Upgrade Lifecycle

```
Upgrade Lifecycle (Major Version)
====================================

Phase 1: Research (T-30 days)
  - Read PostgreSQL release notes for target version
  - Check extension compatibility
  - Review parameter group changes
  - Identify deprecated functions in application code

Phase 2: Test (T-14 days)
  - Clone production cluster
  - Upgrade the clone
  - Run application test suite against upgraded clone
  - Measure upgrade duration
  - Document any issues

Phase 3: Plan (T-7 days)
  - Write upgrade plan with all steps
  - Get sign-off from engineering lead
  - Create parameter group for target version
  - Schedule maintenance window
  - Prepare rollback procedure

Phase 4: Execute (Day of)
  - Take pre-upgrade manual snapshot
  - Execute upgrade (in-place or Blue/Green)
  - Run post-upgrade validation
  - Monitor for 30 minutes minimum

Phase 5: Follow-Up (T+1 to T+7)
  - Run ANALYZE on all tables (statistics may reset)
  - Update extensions: ALTER EXTENSION ... UPDATE
  - Monitor query performance for regressions
  - Keep pre-upgrade snapshot for 30 days
```

### Choosing Between In-Place and Blue/Green

```
Decision Framework
====================

Use IN-PLACE upgrade when:
  - Cluster is small (< 50 GB)
  - Downtime of 15-30 minutes is acceptable
  - No schema changes accompany the upgrade
  - Budget is tight (no 2x instance cost during prep)
  - Low risk tolerance (simpler procedure)

Use BLUE/GREEN when:
  - Cluster is large (> 100 GB)
  - Downtime must be < 60 seconds
  - Schema changes accompany the upgrade
  - You want to test the upgrade before committing
  - Rollback must be fast (switch back to Blue vs snapshot restore)
  - Budget allows 2x instance cost during preparation period
```

---

## 7. Long-Term Lifecycle Planning

### End-of-Life Planning

AWS announces end-of-support dates for PostgreSQL versions. Plan upgrades well before the deadline.

```
Typical End-of-Support Timeline
==================================

  Community EOL         AWS forced upgrade
  (no more patches)     (AWS auto-upgrades you)
       |                      |
       v                      v
  [-----6-12 months-----]

  Example:
  PostgreSQL 14 community EOL: November 2026
  AWS forced upgrade window: ~Q2 2027

  Start planning: 6 months BEFORE community EOL
  Execute upgrade: 3 months BEFORE AWS forced upgrade

  If AWS auto-upgrades you:
  - It happens during your maintenance window
  - You had no chance to test first
  - Rollback is harder (no pre-upgrade snapshot unless you took one)
```

### Version Skip Strategy

Not all major version jumps are direct. Always check available upgrade paths.

```
Version Skip Paths (Check with CLI)
=====================================

PostgreSQL 13 -> 14: Direct
PostgreSQL 13 -> 15: May require 13 -> 14 -> 15
PostgreSQL 14 -> 16: Check ValidUpgradeTarget

Always verify with:
  aws rds describe-db-engine-versions \
    --engine aurora-postgresql \
    --engine-version YOUR_VERSION \
    --query 'DBEngineVersions[0].ValidUpgradeTarget[*].EngineVersion'
```

---

## Key Takeaways

1. Minor upgrades are low risk and can be automatic - major upgrades are manual and require planning
2. Blue/Green deployments reduce upgrade downtime from minutes to seconds
3. Always take a manual snapshot before any major upgrade - it is your only rollback path
4. Maintenance windows are just scheduling preferences - AWS can force patches after a deadline
5. Multi-AZ reduces maintenance downtime from 3-5 minutes to 30-60 seconds
6. Test every major upgrade on a clone before touching production
7. Plan upgrades 6 months before end-of-support to avoid forced auto-upgrades
