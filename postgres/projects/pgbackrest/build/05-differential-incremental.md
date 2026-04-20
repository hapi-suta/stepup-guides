# Differential and Incremental Backups

**Estimated time:** 25 minutes

**What you'll learn:**
- The difference between full, differential, and incremental backups
- How to take differential and incremental backups
- How backup sizes compare to a full backup
- How the dependency chain works
- When to use each backup type

**Prerequisites:**
- Completed guides 01-04 (pgBackRest installed, configured, WAL archiving working, one full backup taken)
- PostgreSQL 16 is running

---

## Why not just take full backups every time?

Full backups copy everything - even data that hasn't changed. If your database is 800 MB and only 10 MB changed today, a full backup still copies all 800 MB. That wastes time, disk space, and network bandwidth. Differential and incremental backups solve this by only backing up what changed.

---

## Step 1: Connect to your server

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Switch to the postgres user

```bash
sudo -i -u postgres
```

---

## Step 3: Generate some data changes

Before taking a differential backup, let's create some new data so there's something that changed since the full backup. We'll use `pgbench` to generate transactions against the `labdb` database for 30 seconds. On CentOS, pgbench is not in the default PATH, so we use the full path.

```bash
/usr/pgsql-16/bin/pgbench -c 2 -T 30 labdb
```

The `-c 2` flag means use 2 concurrent connections. The `-T 30` flag means run for 30 seconds. `labdb` is the database to run against.

```
Expected output (yours will differ):
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: ...
query mode: simple
number of clients: 2
number of threads: 1
maximum number of tries: 1
duration: 30 s
number of transactions actually processed: 12847
number of failed transactions: 0
latency average = 4.671 ms
...
```

This created thousands of small changes in the database.

---

## Step 4: Take a differential backup

A differential backup only includes data that changed since the last **full** backup.

```bash
pgbackrest --stanza=main --type=diff backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin ...
P00   INFO: last backup label = ..., version = ...
P00   INFO: execute non-exclusive backup start: ...
P00   INFO: new backup label = ..._...D
P00   INFO: backup command end: completed successfully
...
```

Notice two things:
- The backup label ends with `D` (for Differential)
- When you check `info` in the next step, the **repo backup size will be much smaller** than the full backup. pgBackRest only backed up the pages that changed.

> **Concept: Diff vs Incr**
> A **differential** backup includes everything that changed since the last **full** backup. An **incremental** backup includes everything that changed since the last backup of **any** type. Differential backups are larger but simpler to restore. Incremental backups are smaller but need the entire chain to restore.

---

## Step 5: Check the info

Let's see both backups listed.

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): ...

        full backup: ...F
            timestamp start/stop: ...
            wal start/stop: ...
            database size: ..., database backup size: ...
            repo size: ..., repo backup size: ...
            backup reference total: ...

        diff backup: ...F_...D
            timestamp start/stop: ...
            wal start/stop: ...
            database size: ..., database backup size: ...
            repo size: ..., repo backup size: ...
            backup reference total: 1 full
```

Note: The exact format may vary by pgBackRest version. Look at the differential backup for these key details:
- **database backup size** is much smaller than the full backup - only changed data
- **repo backup size** is even smaller - that's the compressed size on disk
- **backup reference** shows this backup depends on the full backup

---

## Step 6: Generate more changes

Let's create more changes for the incremental backup. On CentOS, pgbench is not in the default PATH, so we use the full path.

```bash
/usr/pgsql-16/bin/pgbench -c 2 -T 30 labdb
```

```
Expected output (yours will differ):
pgbench (16.x)
...
number of transactions actually processed: 13102
...
```

---

## Step 7: Take an incremental backup

An incremental backup only includes data that changed since the last backup of any type (full, differential, or incremental).

```bash
pgbackrest --stanza=main --type=incr backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin ...
P00   INFO: last backup label = ..._...D, version = ...
P00   INFO: execute non-exclusive backup start: ...
P00   INFO: new backup label = ..._...I
P00   INFO: backup command end: completed successfully
...
```

Notice:
- The backup label ends with `I` (for Incremental)
- The repo size is even smaller than the differential because it only has changes since the diff backup, not since the full backup

> **Concept: Backup manifest**
> pgBackRest tracks exactly which files (and which pages within files) changed since the last backup. It uses checksums and a manifest file to compare. This is why differential and incremental backups are so efficient - they only copy the specific pages that are different.

---

## Step 8: Compare all three backups

Let's see all three backups side by side.

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): ...

        full backup: ...F
            ...
            repo size: ..., repo backup size: ...
            backup reference total: ...

        diff backup: ...F_...D
            ...
            repo size: ..., repo backup size: ...
            backup reference total: 1 full

        incr backup: ...F_...I
            ...
            repo size: ..., repo backup size: ...
            backup reference total: 1 full, 1 diff
```

Note: The exact format and field names may vary by pgBackRest version. Compare the `repo backup size` values:
- **Full:** largest (everything)
- **Diff:** smaller (changes since full)
- **Incr:** smallest (changes since diff)

And look at the `backup reference list` for the incremental - it depends on BOTH the full backup and the differential backup. This is the dependency chain.

---

## Step 9: Understand the dependency chain

Here's how the three backup types relate to each other:

```
FULL backup (standalone - needs nothing else)
  |
  +--- DIFF backup (depends on FULL only)
  |
  +--- INCR ---- INCR ---- INCR (each depends on FULL + all previous INCRs)
```

Think of it this way:
- To **restore from a Full backup**: you only need that one backup
- To **restore from a Diff backup**: you need the Full + the Diff (2 backups)
- To **restore from an Incr backup**: you need the Full + every Incr in the chain (could be many backups)

> **Concept: Restore time trade-off**
> More incremental backups mean faster backups (less data to copy each time), but slower restores (pgBackRest has to reconstruct from the whole chain). A common strategy is weekly full + daily differential. This keeps backups fast during the week and ensures restores never need more than 2 backups.

---

## Step 10: When to use each type

Here's a practical scheduling strategy:

| Day       | Backup Type | Why                                              |
|-----------|-------------|--------------------------------------------------|
| Sunday    | Full        | Fresh start for the week                         |
| Mon-Sat   | Differential| Only changes since Sunday, fast to restore       |

Another common strategy:

| Day       | Backup Type | Why                                              |
|-----------|-------------|--------------------------------------------------|
| Sunday    | Full        | Fresh start for the week                         |
| Wednesday | Differential| Mid-week safety net                              |
| Other days| Incremental | Minimal size, depends on last diff or full       |

The right choice depends on your database size, how fast it changes, and how quickly you need to be able to restore.

Now exit the postgres user.

```bash
exit
```

---

## What you built

- Took a differential backup (changes since last full)
- Took an incremental backup (changes since last any backup)
- Compared backup sizes across all three types
- Understood the dependency chain between backup types

## Verification

Switch to the postgres user and check that all three backups are listed.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main info
```

You should see three backups: one full, one diff, and one incr. All with status `ok`.

```bash
exit
```

## What's next

In the next guide, you'll learn how to restore from a backup and perform point-in-time recovery (PITR) - recovering your database to a specific moment in time.
