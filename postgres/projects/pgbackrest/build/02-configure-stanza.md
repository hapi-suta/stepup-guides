# Configure Your First Stanza

**Estimated time:** 25 minutes

**What you'll learn:**
- What a pgBackRest stanza is
- How to write the pgBackRest configuration file
- How to create and verify a stanza
- What pgBackRest builds inside the backup repository

**Prerequisites:**
- Completed guide 01 (pgBackRest is installed)
- PostgreSQL 16 is running

---

## What is a stanza?

A stanza is a named backup configuration. Think of it as a label that links pgBackRest to a specific PostgreSQL cluster. The stanza name is used in every pgBackRest command so it knows which database cluster you're talking about. In this lab, we'll name our stanza `main`.

---

## Step 1: Connect to your server

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Create the pgBackRest configuration file

The configuration file tells pgBackRest where your database lives and where to store backups. Open the configuration file with `vi`.

```bash
sudo vi /etc/pgbackrest.conf
```

The file may be empty or contain comments. We'll replace everything. Here's how:

1. If there is existing content, delete all lines first. Press `Esc` to make sure you're in normal mode, then type `ggdG` and press `Enter`. This selects all lines and deletes them.
2. Press `i` to enter insert mode. You'll see `-- INSERT --` at the bottom of the screen.
3. Type the following configuration exactly as shown:

```ini
[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
process-max=2
log-level-console=info
log-level-file=detail
start-fast=y
compress-type=lz4

[main]
pg1-path=/opt/pgsql/data
```

4. Press `Esc` to exit insert mode.
5. Type `:wq` and press `Enter` to save and quit.

Let's explain each setting:

**[global] section** - applies to all stanzas:
- `repo1-path` - where pgBackRest stores all backups and archived WAL files
- `repo1-retention-full=2` - keep the 2 most recent full backups (older ones get deleted)
- `process-max=2` - use 2 CPU threads for compression (faster backups)
- `log-level-console=info` - show informational messages on screen when you run commands
- `log-level-file=detail` - write detailed logs to the log file for troubleshooting
- `start-fast=y` - trigger an immediate checkpoint when starting a backup
- `compress-type=lz4` - use lz4 compression (fast and good compression ratio)

**[main] section** - configuration for our stanza named "main":
- `pg1-path` - the location of your PostgreSQL data directory

> **Concept: What is a stanza?**
> A stanza is a named configuration block that links pgBackRest to a specific PostgreSQL cluster. If you managed multiple PostgreSQL clusters on different servers, each would have its own stanza name. We use `main` because this is our primary (and only) cluster.

---

## Step 3: Verify the configuration file

Let's make sure the file was saved correctly.

```bash
sudo cat /etc/pgbackrest.conf
```

```
Expected output (yours will differ):
[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
process-max=2
log-level-console=info
log-level-file=detail
start-fast=y
compress-type=lz4

[main]
pg1-path=/opt/pgsql/data
```

Make sure there are no typos. If something looks wrong, open the file again with `sudo vi /etc/pgbackrest.conf` and fix it.

---

## Step 4: Create the backup repository directory

pgBackRest needs a directory to store backups. This is the path we set in `repo1-path`.

```bash
sudo mkdir -p /opt/pgsql/backup/pgbackrest
```

`mkdir -p` creates the directory and any parent directories that don't exist yet. The `-p` flag prevents an error if the directory already exists.

Now set the owner to `postgres` so pgBackRest (which runs as the postgres user) can write to it.

```bash
sudo chown postgres:postgres /opt/pgsql/backup/pgbackrest
```

`chown` changes the owner of a file or directory. `postgres:postgres` means the user `postgres` and the group `postgres`.

---

## Step 5: Make sure postgres owns the config file too

pgBackRest runs as the `postgres` user, so it needs to read the configuration file.

```bash
sudo chown postgres:postgres /etc/pgbackrest.conf
```

---

## Step 6: Create the stanza

Now we initialize the stanza. This command creates the internal directory structure that pgBackRest uses to organize backups and WAL archives.

Switch to the postgres user first.

```bash
sudo -i -u postgres
```

Run the stanza-create command.

```bash
pgbackrest --stanza=main stanza-create
```

```
Expected output (yours will differ):
P00   INFO: stanza-create command begin 2.54: ...
P00   INFO: stanza-create for stanza 'main' on repo1
P00   INFO: stanza-create command end: completed successfully
```

> **Concept: What does stanza-create do?**
> The stanza-create command initializes the repository structure. It creates subdirectories for backups and WAL archives, and writes metadata files that pgBackRest uses to track everything. You only run this once per stanza.

---

## Step 7: Verify the stanza

Run the check command to make sure the stanza is properly configured and can communicate with PostgreSQL.

```bash
pgbackrest --stanza=main check
```

```
Expected output (yours will differ):
P00   INFO: check command begin 2.54: ...
P00   INFO: check repo1 configuration (primary)
P00   INFO: check repo1 archive for WAL (primary)
P00  ERROR: [068]: archive_command must be set ...
```

You may see an error about `archive_command`. That's expected! We haven't configured the `archive_command` yet - that happens in guide 03. The important thing is that there's no configuration error.

> **Concept: start-fast=y**
> When pgBackRest starts a backup, PostgreSQL needs to do a checkpoint first (writing all buffered data to disk). Normally PostgreSQL waits until the next scheduled checkpoint. With `start-fast=y`, pgBackRest tells PostgreSQL to do the checkpoint immediately, so your backup starts right away instead of waiting minutes.

---

## Step 8: Explore the repository structure

Let's look at what stanza-create built inside the backup repository.

```bash
ls /opt/pgsql/backup/pgbackrest/
```

```
Expected output (yours will differ):
archive  backup
```

Two directories were created:
- `archive` - where archived WAL files will be stored
- `backup` - where full, differential, and incremental backups will be stored

Let's go deeper.

```bash
ls /opt/pgsql/backup/pgbackrest/archive/
```

```
Expected output (yours will differ):
main
```

```bash
ls /opt/pgsql/backup/pgbackrest/backup/
```

```
Expected output (yours will differ):
main
```

Each directory has a `main` subdirectory - that's our stanza name. If we had a second stanza called "reporting", there would be a `reporting` subdirectory next to `main`.

```bash
ls /opt/pgsql/backup/pgbackrest/backup/main/
```

```
Expected output (yours will differ):
backup.info  backup.info.copy
```

These are metadata files that pgBackRest uses to track all backups. The `.copy` file is a redundant copy for safety.

Now exit the postgres user.

```bash
exit
```

---

## What you built

- Created the pgBackRest configuration file at `/etc/pgbackrest.conf`
- Created the backup repository at `/opt/pgsql/backup/pgbackrest`
- Initialized the `main` stanza
- Explored the repository directory structure

## Verification

Switch to the postgres user and run the info command.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: error (no valid backups)
    cipher: none

    db (current)
        wal archive min/max (16): none present
```

You should see the stanza named `main` with status "no valid backups". That's correct - we haven't taken any backups yet.

```bash
exit
```

## What's next

In the next guide, you'll fix the broken `archive_command` so PostgreSQL starts sending WAL files to pgBackRest.
