# Build 07: Install and Configure pgBackRest

Move from manual WAL archiving to enterprise-grade backup management. pgBackRest
handles archiving, compression, encryption, retention, and multi-repository
support - replacing your hand-rolled archive_command with a battle-tested tool.

---

## 1. Install pgBackRest on NODE1

**Run on NODE1 (pg-primary):**

Switch to root to install packages:

```bash
sudo -i
```

**You are now root.**

First, install EPEL. EPEL (Extra Packages for Enterprise Linux) is an additional software repository. CentOS Stream 9 comes with a limited set of packages, and pgBackRest requires libraries that are only available in EPEL.

```bash
dnf install -y epel-release
```

Now install pgBackRest. This pulls in the pgBackRest binary and all its dependencies from the PGDG and EPEL repositories:

```bash
dnf install -y pgbackrest
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Verify the install by checking the version. This confirms the binary is in your PATH and working:

```bash
pgbackrest version
```

Expected: version string (e.g., `pgBackRest 2.x.x`).

```
Expected output (yours will differ):
pgBackRest 2.54.2
```

## 2. Install pgBackRest on NODE2

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

Switch to root:

```bash
sudo -i
```

**You are now root.**

Install EPEL. EPEL (Extra Packages for Enterprise Linux) is an additional software repository. CentOS Stream 9 comes with a limited set of packages, and pgBackRest requires libraries that are only available in EPEL.

```bash
dnf install -y epel-release
```

Install pgBackRest:

```bash
dnf install -y pgbackrest
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Verify the version matches NODE1:

```bash
pgbackrest version
```

Expected: same version as NODE1.

Exit back to NODE1:

```bash
exit
```

> **Concept - Matching versions**: pgBackRest should be the same version on all
> nodes. Version mismatches between the pg host and the repo host can cause
> protocol errors. Always upgrade both sides together.

## 3. Create the pgBackRest configuration on NODE1

**Run on NODE1 (pg-primary):**

A stanza is pgBackRest's name for a database cluster configuration. Think of it as a label that groups your backup settings together. We named ours `main`.

Create the configuration directory. The `-p` flag means "create parent directories if they don't exist":

```bash
sudo mkdir -p /etc/pgbackrest
```

Write the configuration file. The `tee` command writes text to a file. `sudo tee` is needed because the config file requires root privileges to create.

```bash
sudo tee /etc/pgbackrest/pgbackrest.conf > /dev/null <<EOF
[main]
pg1-path=/opt/pgsql/data

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=4

process-max=2
log-level-console=info
log-level-file=detail
start-fast=y
delta=y

[global:archive-push]
compress-level=3
EOF
```

Set ownership so postgres owns the config file. The `chown` command changes the file's owner and group:

```bash
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
```

Restrict permissions so only postgres can read it. `640` means the owner can read/write, the group can read, and nobody else has access:

```bash
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
```

### Configuration breakdown

| Setting | Meaning |
| ------- | ------- |
| `pg1-path` | Path to the PostgreSQL data directory |
| `repo1-path` | Where backups are stored (local in this lab) |
| `repo1-retention-full` | Keep the last 2 full backups |
| `repo1-retention-diff` | Keep the last 4 differential backups per full |
| `process-max` | Parallel compression/transfer threads |
| `start-fast` | Trigger immediate checkpoint (same as --checkpoint=fast) |
| `delta` | Only restore files that differ (speeds up restores) |
| `compress-level` | Compression level for WAL archive-push (1-9) |

> **Concept - Stanza**: A stanza is pgBackRest's term for a backup configuration.
> It groups a PostgreSQL cluster with its repository settings. The stanza name
> (`main` in our case) appears in every command. In multi-cluster environments,
> you would have separate stanzas for each cluster (e.g., `main`, `analytics`,
> `reporting`).

## 4. Create the pgBackRest configuration on NODE2

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

Create the config directory:

```bash
sudo mkdir -p /etc/pgbackrest
```

Write the configuration file. The `tee` command writes text to a file. `sudo tee` is needed because the config file requires root privileges to create.

Notice NODE2's config has two extra lines (`repo1-host` and `repo1-host-user`). This is because backups are stored on NODE1, so NODE2 needs to know how to reach NODE1's repository over SSH.

This SSH connection works because you set up passwordless SSH between the postgres users in Build 01.

```bash
sudo tee /etc/pgbackrest/pgbackrest.conf > /dev/null <<EOF
[main]
pg1-path=/opt/pgsql/data

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-host=pg-primary
repo1-host-user=postgres
repo1-retention-full=2
repo1-retention-diff=4

process-max=2
log-level-console=info
log-level-file=detail
EOF
```

Set ownership so postgres owns the config file:

```bash
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
```

Restrict permissions:

```bash
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
```

Create the repository directory where backups will be stored:

```bash
sudo mkdir -p /opt/pgsql/backup/pgbackrest
```

Set ownership on the repository directory:

```bash
sudo chown postgres:postgres /opt/pgsql/backup/pgbackrest
```

Exit back to NODE1:

```bash
exit
```

> **Concept - Remote repository access**: The backup repository lives on NODE1
> at `/opt/pgsql/backup/pgbackrest`. NODE2's config uses `repo1-host=pg-primary`
> so pgBackRest on NODE2 can SSH to NODE1 to read backup data during restore
> operations. In production, the repository would typically live on a dedicated
> backup server or object storage (S3, GCS, Azure Blob).

## 5. Update PostgreSQL archive_command to use pgBackRest

**Run on NODE1 (pg-primary):**

Switch to the postgres user on NODE1:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Open postgresql.conf for editing:

```bash
vim /opt/pgsql/data/postgresql.conf
```

Change the archive_command to use pgBackRest instead of rsync. The `--stanza=main` flag tells pgBackRest which backup configuration to use:

```
archive_command = 'pgbackrest --stanza=main archive-push %p'
```

Keep these settings as they are:

```
wal_level = replica
archive_mode = on
archive_timeout = 60
```

Save and exit vim.

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Reload the configuration. The archive_command change only needs a reload, not a full restart:

```bash
sudo systemctl reload postgresql-16
```

Switch to postgres and verify the new archive_command:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

```bash
psql -c "SHOW archive_command;"
```

Expected: `pgbackrest --stanza=main archive-push %p`.

```
Expected output:
             archive_command
------------------------------------------
 pgbackrest --stanza=main archive-push %p
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

> **Concept - pgBackRest vs manual archive_command**: The old rsync-based
> archive_command was fragile - no compression, no parallelism, no verification,
> no encryption. pgBackRest's archive-push handles all of this:
> - Compresses WAL segments before transfer
> - Verifies checksums on both ends
> - Handles network retries automatically
> - Supports async archiving (queue WAL locally, push in background)
> - Can push to multiple repositories simultaneously
>
> The manual approach works for learning. pgBackRest is what you run in production.

## 6. Create the stanza

**Run on NODE1 (pg-primary):**

The stanza-create command initializes the backup repository and verifies
connectivity.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Create the stanza. The `--stanza=main` flag tells pgBackRest which configuration to initialize:

```bash
pgbackrest --stanza=main stanza-create
```

Expected: completes without error. Behind the scenes, pgBackRest:
1. Creates the repository directory structure under `/opt/pgsql/backup/pgbackrest/`
2. Writes metadata about the PostgreSQL cluster (version, system identifier)

```
Expected output (yours will differ):
2026-04-19 01:26:02.575 P00   INFO: stanza-create command begin 2.54.2: ...
2026-04-19 01:26:02.586 P00   INFO: stanza-create command end: completed successfully
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Verify the repository directories were created. The `-la` flags show all files in long format with permissions:

```bash
ls -la /opt/pgsql/backup/pgbackrest/
```

Expected: `archive/` and `backup/` directories.

```
Expected output (yours will differ):
total 0
drwxr-xr-x. 3 postgres postgres 18 Apr 19 01:26 archive
drwxr-xr-x. 3 postgres postgres 18 Apr 19 01:26 backup
```

## 7. Verify the stanza

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Run the check command. This performs an end-to-end verification:

```bash
pgbackrest --stanza=main check
```

Expected: completes without error. This command:
1. Verifies the repository exists and is accessible
2. Verifies PostgreSQL is running and reachable
3. Forces a WAL switch and verifies that archive-push works
4. Verifies the archived WAL file in the repository

```
Expected output (yours will differ):
2026-04-19 01:26:02.575 P00   INFO: check command begin 2.54.2: ...
2026-04-19 01:26:02.586 P00   INFO: check repo1 configuration (primary)
2026-04-19 01:26:02.718 P00   INFO: check repo1 archive for WAL (primary)
2026-04-19 01:26:03.019 P00   INFO: WAL segment 000000010000000100000026 successfully archived to '...' on repo1
2026-04-19 01:26:03.020 P00   INFO: check command end: completed successfully (448ms)
```

If this command passes, your pgBackRest setup is fully operational.

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

> **Concept - Trust but verify**: Always run `pgbackrest check` after any
> configuration change. It is the single command that proves the entire pipeline
> works - from PostgreSQL generating WAL, to pgBackRest compressing and
> storing it, to the repository being accessible. Put this in a cron
> job or monitoring check.

## 8. Verify WAL archiving through pgBackRest

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Generate some WAL activity by inserting 1,000 rows into the pgbench_history table:

```bash
psql -d labdb -c "
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime)
SELECT (random() * 32)::int + 1,
       (random() * 32)::int + 1,
       (random() * 32999999)::int + 1,
       (random() * 10000)::int,
       now()
FROM generate_series(1, 1000) g;
"
```

Force a WAL switch so the current segment gets archived. This tells PostgreSQL to close the current WAL file and start a new one:

```bash
psql -c "SELECT pg_switch_wal();"
```

Wait a moment for the archive to complete:

```bash
sleep 5
```

List recent WAL files in the pgBackRest repository. The `--sort=desc` flag shows newest first, and `head -5` limits to the 5 most recent:

```bash
pgbackrest --stanza=main repo-ls archive/main --sort=desc | head -5
```

Expected: recent WAL segment files.

Check the archiver stats to confirm no failures. This queries PostgreSQL's built-in archiver statistics:

```bash
psql -c "SELECT archived_count, last_archived_wal, failed_count FROM pg_stat_archiver;"
```

Expected: `archived_count` increased, `failed_count` still 0.

```
Expected output (yours will differ):
 archived_count |    last_archived_wal     | failed_count
----------------+--------------------------+--------------
             29 | 000000010000000100000024 |            0
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

## 9. Inspect the repository structure

**Run on NODE1 (pg-primary):**

Look at how pgBackRest organizes the repository. The `find` command lists all directories (`-type d`) under the backup path, and `head -20` limits the output to 20 lines:

```bash
find /opt/pgsql/backup/pgbackrest -type d | head -20
```

Expected: a structured directory tree.

```
Expected output (yours will differ):
/opt/pgsql/backup/pgbackrest/
/opt/pgsql/backup/pgbackrest/archive/
/opt/pgsql/backup/pgbackrest/archive/main/
/opt/pgsql/backup/pgbackrest/archive/main/16-1/
/opt/pgsql/backup/pgbackrest/backup/
/opt/pgsql/backup/pgbackrest/backup/main/
```

> **Concept - Repository layout**: pgBackRest organizes the repository by
> stanza and PostgreSQL system identifier. The `archive/` directory holds WAL
> segments (compressed). The `backup/` directory holds base backups. The system
> identifier prevents accidentally mixing WAL from different clusters - a mistake
> that would cause silent data corruption during recovery.

---

## Checkpoint

NODE1 (primary) has:
- [x] pgBackRest installed
- [x] `/etc/pgbackrest/pgbackrest.conf` configured with pg1-path=/opt/pgsql/data
- [x] `archive_command` updated to use pgBackRest
- [x] Stanza created and verified
- [x] Repository at `/opt/pgsql/backup/pgbackrest/`

NODE2 (backup server) has:
- [x] pgBackRest installed
- [x] `/etc/pgbackrest/pgbackrest.conf` configured
- [x] WAL segments arriving in the archive

Proceed to `08-pgbackrest-operations.md`.
