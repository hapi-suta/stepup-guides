# Video Script: Concepts - pgBackRest Fundamentals

**Video file:** `pgbackrest-concepts-fundamentals.mp4`
**Estimated length:** 12-15 minutes
**Guide:** [pgBackRest Fundamentals](../../concepts/pgbackrest-fundamentals.md)
**Server state required:** None (this is a theory video, but have a server ready for quick demos)

---

## INTRO [0:00]

[SAY] "Before we touch a single command, let's understand what pgBackRest is, why it exists, and how it works. This is the concepts video - watch this first, then do the BUILD guides."

[SAY] "If you're coming from a world of pg_basebackup scripts and cron jobs, pgBackRest replaces all of that with one tool."

[PAUSE]

---

## SECTION 1: What Is pgBackRest? [0:30]

[SAY] "pgBackRest is an enterprise backup and restore tool built specifically for PostgreSQL. It handles four things: creating backups, compressing them, archiving WAL files, and restoring your database."

[SAY] "Without pgBackRest, you're stitching together pg_basebackup, rsync, custom archive scripts, retention cron jobs - all fragile. pgBackRest replaces the whole pipeline with one binary and one config file."

[CONCEPT] "Think of it this way. pg_basebackup is a screwdriver. pgBackRest is a power drill with every attachment. Same job, completely different experience."

[PAUSE]

---

## SECTION 2: Architecture [1:30]

[SAY] "pgBackRest has three components that you need to understand."

[SAY] "First: the stanza. A stanza is a named configuration that links pgBackRest to a specific PostgreSQL cluster. If you manage three clusters, you have three stanzas. We'll use 'main' for our single cluster."

[SAY] "Second: the repository. This is where pgBackRest stores everything - your backups AND your archived WAL files. In our lab, it lives at /opt/pgsql/backup/pgbackrest."

[SAY] "Third: the archive. Every WAL file PostgreSQL produces gets pushed to the repository. This is what enables point-in-time recovery - we can replay transactions up to any moment in time."

[PAUSE]

---

## SECTION 3: Backup Types [3:00]

[SAY] "pgBackRest supports three backup types: full, differential, and incremental."

[SAY] "A full backup copies everything. Every file, every table, every index. It's self-contained - you can restore from it alone. But it's the largest and slowest."

[SAY] "A differential backup only copies what changed since the last full backup. To restore, you need the full plus the diff. Two pieces."

[SAY] "An incremental backup only copies what changed since the last backup of any type. To restore, you need the full plus every incremental in the chain. More pieces, but each one is tiny."

[CONCEPT] "Here's how I think about it. Imagine moving apartments. A full backup is packing everything into boxes. A diff backup is packing only what you bought since the last full move. An incr backup is packing only what you bought since yesterday. The more incremental you go, the faster the packing - but the more boxes you need to unpack during a restore."

[SAY] "In production, the most common strategy: weekly full, daily differential. Simple and fast to restore."

[PAUSE]

---

## SECTION 4: WAL Archiving [5:00]

[SAY] "WAL stands for Write-Ahead Log. Every change to your database is written to a WAL file first - before the actual data file is updated. This is how PostgreSQL guarantees no data loss after a crash."

[SAY] "WAL archiving means copying those WAL files to a safe location. pgBackRest does this with the archive-push command. PostgreSQL calls it automatically through the archive_command setting."

[SAY] "Why does this matter? Because WAL files are what make point-in-time recovery possible. Your backup captures a snapshot at one moment. The WAL files capture every transaction between snapshots. Combine them, and you can restore to any second."

[CONCEPT] "Think of a backup as a photograph and WAL files as a video recording. The photograph shows one moment. The video shows everything that happened after. Together, you can reconstruct any frame."

[PAUSE]

---

## SECTION 5: How Restore Works [7:00]

[SAY] "When you run pgbackrest restore, here's what happens behind the scenes."

[SAY] "Step 1: pgBackRest picks the best backup to restore from. Usually the most recent."

[SAY] "Step 2: It recreates your data directory from the backup files. Decompresses everything, puts files in the right place."

[SAY] "Step 3: It configures PostgreSQL to replay WAL files from the archive. If you specified a PITR target, it sets the recovery target."

[SAY] "Step 4: You start PostgreSQL. It reads the WAL files and replays transactions. If PITR, it stops at your target time. Then it promotes to accept new writes."

[SAY] "The delta flag makes this faster. Instead of deleting everything and restoring from scratch, delta compares what's on disk to the backup and only restores files that differ."

[PAUSE]

---

## SECTION 6: Retention [9:00]

[SAY] "Every backup takes disk space. Without retention, your repository grows forever. Retention tells pgBackRest how many backups to keep."

[SAY] "repo1-retention-full=2 means keep the 2 most recent full backups. When you take a 3rd full backup, the oldest one is automatically deleted. pgBackRest also cleans up any differential and incremental backups that depended on the expired full."

[SAY] "There are two types: count-based and time-based. Count-based is simple - keep N backups. Time-based keeps backups for N days. Use count-based unless your backup schedule is irregular."

[CONCEPT] "Retention defines your recovery window. If you keep 2 weekly full backups, you can go back about 2 weeks. If someone reports data was deleted 3 weeks ago - you're out of luck. Choose retention based on how far back you might ever need to go."

[PAUSE]

---

## SECTION 7: Configuration [10:30]

[SAY] "pgBackRest uses one config file: /etc/pgbackrest.conf. It's INI format - simple key=value pairs organized in sections."

[SAY] "The global section applies to all stanzas. This is where you set the repo path, retention, compression, parallelism, and logging."

[SAY] "Each stanza section has just one critical setting: pg1-path, which tells pgBackRest where your PostgreSQL data directory is."

[SAY] "In the BUILD guides, we'll write this file together. It's about 10 lines. That's all it takes."

[PAUSE]

---

## SECTION 8: Key Commands [11:30]

[SAY] "You need to know six pgBackRest commands."

[SAY] "stanza-create - run once to initialize the repository. backup - take a backup. restore - restore from a backup. check - verify everything is healthy. info - show backup inventory. expire - manually clean up old backups, though this usually runs automatically."

[SAY] "In day-to-day operations, you'll mostly use info and check. Backups run on cron. Restores are rare but critical."

[PAUSE]

---

## OUTRO [12:30]

[SAY] "That's the theory. You understand stanzas, backup types, WAL archiving, restore mechanics, and retention. Now let's build it."

[SAY] "Start with BUILD 01: Install pgBackRest. Open the guide, follow along, and type every command yourself. I'll see you there."
