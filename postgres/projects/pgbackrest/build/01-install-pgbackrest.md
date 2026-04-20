# Install pgBackRest

**Estimated time:** 20 minutes

**What you'll learn:**
- What pgBackRest is and why you need it
- How to check if your current backup setup is broken
- How to install pgBackRest on CentOS Stream 9
- How to verify the installation

**Prerequisites:**
- SSH access to your server as `ec2-user`
- PostgreSQL 16 installed and running

---

## What is pgBackRest?

pgBackRest is a backup and restore tool for PostgreSQL. It replaces your entire backup pipeline - it handles creating backups, compressing them, archiving WAL files, and restoring your database when things go wrong. Without a working backup tool, your database has no safety net. If the server crashes or someone accidentally deletes data, you lose everything.

Right now, your PostgreSQL server is configured with `archive_command = '/bin/false'`. This means every time PostgreSQL tries to archive a WAL file, the command fails on purpose. Your backups are broken. Let's fix that by installing pgBackRest.

---

## Step 1: Connect to your server

Open your terminal and SSH into your server.

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Verify PostgreSQL is running

Let's make sure PostgreSQL is up before we start.

```bash
sudo systemctl status postgresql-16
```

```
Expected output (yours will differ):
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; preset: disabled)
     Active: active (running) since ...
...
```

You should see `active (running)` in green. If it says `inactive` or `failed`, ask your instructor for help before continuing.

---

## Step 3: Check the current broken state

Let's see proof that WAL archiving is failing. Switch to the `postgres` user first.

```bash
sudo -i -u postgres
```

This switches you to the `postgres` operating system user, which owns the PostgreSQL database.

Now open psql (the PostgreSQL command-line tool).

```bash
psql
```

Run this query to check the archive status.

```sql
SELECT archived_count, failed_count, last_failed_time FROM pg_stat_archiver;
```

```
Expected output (yours will differ):
 archived_count | failed_count |      last_failed_time
----------------+--------------+-------------------------------
              0 |          147 | 2026-04-20 10:23:45.123456+00
(1 row)
```

> **Concept: What is a WAL archive?**
> WAL stands for Write-Ahead Log. It's PostgreSQL's transaction journal - every change to your data is written to WAL files first. Archiving means copying those WAL files to a safe location so you can replay them later during a restore. Without archiving, you can only restore to the exact moment of your last backup.

Notice `failed_count` is a large number and `archived_count` is 0. Every single archive attempt has failed.

Let's see why. Check the current archive command.

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

> **Concept: Why archive_command = '/bin/false' is dangerous**
> The Linux command `/bin/false` always exits with an error code. PostgreSQL runs this command every time it tries to archive a WAL file, and it fails every time. This means WAL files pile up in `pg_wal` and are never safely archived. If you lose your server, those WAL files are gone forever.

Exit psql.

```
\q
```

Exit the postgres user.

```bash
exit
```

---

## Step 4: Install the EPEL repository

pgBackRest is available in the EPEL repository. EPEL (Extra Packages for Enterprise Linux) is a free collection of additional software packages for CentOS and RHEL that aren't included by default.

```bash
sudo dnf install -y epel-release
```

```
Expected output (yours will differ):
...
Installed:
  epel-release-9-7.el9.noarch
Complete!
```

The `-y` flag means "answer yes to all prompts" so you don't have to type `y` during the install.

---

## Step 5: Install pgBackRest

Now install pgBackRest.

```bash
sudo dnf install -y pgbackrest
```

```
Expected output (yours will differ):
...
Installed:
  pgbackrest-2.54-1.el9.x86_64
...
Complete!
```

`dnf` is the package manager on CentOS Stream 9. It downloads and installs software from online repositories.

---

## Step 6: Verify the installation

Check that pgBackRest is installed and see the version number.

```bash
pgbackrest version
```

```
Expected output (yours will differ):
pgBackRest 2.54
```

---

## Step 7: Find where pgBackRest was installed

Let's see where the pgBackRest binary lives.

```bash
which pgbackrest
```

```
Expected output (yours will differ):
/usr/bin/pgbackrest
```

`which` tells you the full path to a command. This confirms pgBackRest is in your system PATH and can be run from anywhere.

Now let's see all the files that were installed by the pgBackRest package.

```bash
rpm -ql pgbackrest | head -20
```

```
Expected output (yours will differ):
/etc/pgbackrest.conf
/usr/bin/pgbackrest
/usr/lib/tmpfiles.d/pgbackrest.conf
/usr/share/doc/pgbackrest
...
```

`rpm -ql` lists all files belonging to an installed package. The `head -20` shows just the first 20 lines so the output doesn't overwhelm your screen.

Notice that the package created `/etc/pgbackrest.conf` - that's where the configuration file lives. We'll edit that in the next guide.

---

## What you built

- Confirmed that WAL archiving was broken (`archive_command = '/bin/false'`)
- Installed the EPEL repository
- Installed pgBackRest on your server
- Verified the installation works

## Verification

Run this command to confirm everything is in place.

```bash
pgbackrest version
```

You should see a version number like `pgBackRest 2.54` (your version may be slightly different).

## What's next

In the next guide, you'll configure pgBackRest by creating a stanza - a named configuration that links pgBackRest to your PostgreSQL cluster.
