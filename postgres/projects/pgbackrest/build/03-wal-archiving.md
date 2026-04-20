# Enable WAL Archiving with pgBackRest

**Estimated time:** 20 minutes

**What you'll learn:**
- Why WAL archiving matters for backups
- How to fix the broken archive_command
- How to verify WAL files are being archived
- How to check archived WAL files in the repository

**Prerequisites:**
- Completed guides 01 and 02 (pgBackRest installed, stanza created)
- PostgreSQL 16 is running

---

## The problem

Right now, `archive_command` is set to `/bin/false`. Every time PostgreSQL finishes writing a WAL file and tries to archive it, the command fails. This means:
- No WAL files are being saved to a safe location
- You can't do point-in-time recovery
- Your future backups won't have the WAL files needed for a complete restore

Let's fix this.

---

## Step 1: Connect to your server

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Check the current damage

Let's see how many archive attempts have failed. Switch to the postgres user.

```bash
sudo -i -u postgres
```

Open psql.

```bash
psql
```

Check the archive statistics.

```sql
SELECT archived_count, failed_count, last_failed_time FROM pg_stat_archiver;
```

```
Expected output (yours will differ):
 archived_count | failed_count |      last_failed_time
----------------+--------------+-------------------------------
              0 |          283 | 2026-04-20 11:05:12.456789+00
(1 row)
```

The `failed_count` has been climbing since PostgreSQL started. Every failed attempt means a WAL file that should have been archived but wasn't.

Now check the current archive command.

```sql
SHOW archive_command;
```

```
Expected output (yours will differ):
 archive_command
-----------------
 /bin/false
(1 row)
```

---

## Step 3: Fix the archive_command

We'll use `ALTER SYSTEM` to change the archive_command. This is the safest way to change PostgreSQL settings because it writes to a separate file (`postgresql.auto.conf`) and doesn't touch the main `postgresql.conf`.

Still in psql, run this command.

```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';
```

```
Expected output (yours will differ):
ALTER SYSTEM
```

> **Concept: What does archive-push do?**
> The `archive-push` command copies a single WAL file from PostgreSQL's `pg_wal` directory to the pgBackRest repository. PostgreSQL calls this command automatically every time a WAL file is full and ready to be archived. pgBackRest compresses the file and stores it safely.

> **Concept: What is %p?**
> The `%p` is a placeholder. When PostgreSQL runs the archive command, it replaces `%p` with the full file path of the WAL file that needs to be archived. For example, it might become `/opt/pgsql/data/pg_wal/000000010000000000000001`.

---

## Step 4: Reload PostgreSQL configuration

The `ALTER SYSTEM` command wrote the new setting to disk, but PostgreSQL hasn't read it yet. We need to reload the configuration. This does NOT restart the database - it just tells PostgreSQL to re-read its config files.

Still in psql, run this.

```sql
SELECT pg_reload_conf();
```

```
Expected output (yours will differ):
 pg_reload_conf
----------------
 t
(1 row)
```

The `t` means true - the reload was successful.

> **Concept: Why ALTER SYSTEM instead of editing postgresql.conf?**
> `ALTER SYSTEM` writes your change to `postgresql.auto.conf`, a separate file that PostgreSQL reads after `postgresql.conf`. This is safer because you can't accidentally break the main config file with a typo, and your changes are clearly separated from the default settings.

---

## Step 5: Verify the new archive_command

Let's confirm PostgreSQL picked up the change.

```sql
SHOW archive_command;
```

```
Expected output (yours will differ):
                    archive_command
------------------------------------------------------
 pgbackrest --stanza=main archive-push %p
(1 row)
```

You should see the pgBackRest command instead of `/bin/false`.

---

## Step 6: Force a WAL switch to test archiving

PostgreSQL only archives a WAL file when it's full (usually 16 MB). We don't want to wait for that, so we'll force PostgreSQL to switch to a new WAL file right now. This makes the current WAL file eligible for archiving.

Still in psql, run this.

```sql
SELECT pg_switch_wal();
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 0/5000100
(1 row)
```

The output is a WAL position (yours will be different). This is normal.

---

## Step 7: Check if archiving is working now

Wait a few seconds for the archive to complete, then check the archiver statistics again.

```sql
SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;
```

```
Expected output (yours will differ):
 archived_count | failed_count |     last_archived_wal      |      last_archived_time
----------------+--------------+----------------------------+-------------------------------
              1 |          283 |  000000010000000000000005   | 2026-04-20 11:12:33.789012+00
(1 row)
```

The key change: `archived_count` is now greater than 0, and `last_archived_wal` shows the name of the WAL file that was just archived. The `failed_count` is still high from before, but it should stop increasing now.

If `archived_count` is still 0, wait 10 seconds and run the query again. The archiver process runs in the background and may need a moment.

Now exit psql.

```
\q
```

---

## Step 8: Look at archived WAL files in the repository

Let's see the archived WAL files in the pgBackRest repository.

```bash
ls /opt/pgsql/backup/pgbackrest/archive/main/
```

```
Expected output (yours will differ):
16-1
```

The `16-1` directory is named after the PostgreSQL version and timeline. Let's look inside.

```bash
ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/
```

```
Expected output (yours will differ):
0000000100000000
```

```bash
ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/0000000100000000/
```

```
Expected output (yours will differ):
000000010000000000000005-abc123def456.lz4
```

There's your archived WAL file. Notice the `.lz4` extension - pgBackRest compressed it automatically to save disk space.

---

## Step 9: Run a full stanza check

Let's run the pgBackRest check command to make sure everything is working end-to-end.

```bash
pgbackrest --stanza=main check
```

```
Expected output (yours will differ):
P00   INFO: check command begin 2.54: ...
P00   INFO: check repo1 configuration (primary)
P00   INFO: check repo1 archive for WAL (primary)
P00   INFO: WAL segment ... successfully archived to ...
P00   INFO: check command end: completed successfully
```

You should see "completed successfully" this time. No more errors about missing WAL archives.

Now exit the postgres user.

```bash
exit
```

---

## What you built

- Fixed the broken `archive_command` to use pgBackRest
- Verified that WAL files are now being archived successfully
- Confirmed archived WAL files are compressed and stored in the repository
- Passed the pgBackRest stanza check

## Verification

Switch to the postgres user and check the archive status one more time.

```bash
sudo -i -u postgres
```

```bash
psql -c "SELECT archived_count, failed_count FROM pg_stat_archiver;"
```

```
Expected output (yours will differ):
 archived_count | failed_count
----------------+--------------
              1 |          283
(1 row)
```

`archived_count` should be at least 1, and `failed_count` should no longer be increasing.

```bash
exit
```

## What's next

In the next guide, you'll take your first full backup of the entire database.
