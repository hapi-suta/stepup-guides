# Tier 5 - Backup, Recovery, and Lifecycle
## AWS RDS and Aurora PostgreSQL

**Level:** Intermediate to Advanced
**Audience:** DBAs and engineers who already know how to launch and connect to RDS/Aurora
**Prerequisites:** Tiers 1-4 complete, or equivalent hands-on RDS/Aurora experience

---

## What You Will Learn

By the end of this tier you will be able to:

- Explain the difference between automated backups and manual snapshots
- Perform a point-in-time recovery (PITR) to a specific second in time
- Clone an Aurora cluster using copy-on-write (fast clone) and explain why it is faster than a restore
- Execute a major version upgrade with a documented rollback plan
- Set up and switch over a Blue/Green Deployment for zero-downtime upgrades
- Control maintenance windows and predict reboot behavior during patching

---

## Important Note on Aurora Backtrack

Aurora Backtrack is **MySQL-only**. It is NOT available for Aurora PostgreSQL.

For Aurora PostgreSQL, the equivalent tools are:
- **PITR** (Point-In-Time Recovery) - restore to any second within the retention window
- **Fast Database Cloning** - copy-on-write clone for near-instant copies

This tier covers both. Any AWS documentation or exam question that mentions Backtrack for PostgreSQL is incorrect.

---

## Module Map

| # | Topic | Type | Time |
|---|-------|------|------|
| T5.1 | Automated Backups and Snapshots | Build | 40 min |
| T5.2 | Point-In-Time Recovery | Build | 45 min |
| T5.3 | Aurora Fast Cloning | Build | 35 min |
| T5.4 | Engine Version Upgrades | Build | 45 min |
| T5.5 | Blue/Green Deployments | Build | 50 min |
| T5.6 | Maintenance Windows | Build | 25 min |
| - | Backup Strategy Design | Use | 30 min |
| - | Disaster Recovery Drill | Use | 45 min |
| - | Clone for Testing | Use | 30 min |
| - | Upgrade Planning | Use | 40 min |
| - | Blue/Green Cutover | Use | 45 min |
| 01 | Accidental Table Drop | Survive | 30 min |
| 02 | Backup Retention Expired | Survive | 30 min |
| 03 | Upgrade Failure | Survive | 30 min |
| 04 | Blue/Green Replication Lag | Survive | 30 min |
| 05 | Maintenance Window Surprise | Survive | 30 min |

---

## Lab Environment

You use your own AWS account. All resources created in this lab cost real money. Estimated cost for a full run-through: **$3-8 USD** if you delete resources promptly.

**Resources you will create:**
- 1-2 RDS PostgreSQL instances (db.t3.micro)
- 1 Aurora PostgreSQL cluster (db.t3.medium)
- Multiple snapshots (storage cost per GB-month)
- 1 Blue/Green deployment pair (2x instance cost while active)

**Cleanup rule:** Every BUILD guide ends with a cleanup section. Run it.

---

## Required Tools

```
aws --version          # AWS CLI v2
psql --version         # PostgreSQL client 14+
jq --version           # JSON parser
```

Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

---

## Folder Structure

```
tier5-backup-recovery/
  README.md                     <- You are here
  concepts/
    backup-recovery.md          <- Read this first
  build/
    01-automated-backups-snapshots.md
    02-point-in-time-recovery.md
    03-aurora-fast-cloning.md
    04-engine-upgrades.md
    05-blue-green-deployments.md
    06-maintenance-windows.md
  use/
    01-backup-strategy.md
    02-disaster-recovery-drill.md
    03-clone-for-testing.md
    04-upgrade-planning.md
    05-blue-green-cutover.md
  survive/
    config.sh
    lib/common.sh
    01-accidental-table-drop/
    02-backup-retention-expired/
    03-upgrade-failure/
    04-blue-green-lag/
    05-maintenance-window-surprise/
  interview/
    tier5-interview-questions.md
```

---

## How to Work Through This Tier

1. Read `concepts/backup-recovery.md` completely before touching the console.
2. Work through BUILD guides in order - each one builds on the last.
3. Complete USE exercises after each BUILD or at the end.
4. SURVIVE scenarios are timed. Set a timer. Work alone first.
5. Review interview questions after each topic - not just at the end.

---

## Naming Conventions Used in This Tier

All example resource names follow this pattern:

```
suta-t5-[purpose]-[your-initials]
```

Examples:
- `suta-t5-primary-hfa`
- `suta-t5-clone-hfa`
- `suta-t5-restored-hfa`

Replace `hfa` with your own initials throughout.
