# Retention Policy and Automated Scheduling

**Estimated time:** 20 minutes

**What you'll learn:**
- How retention policies control how many backups are kept
- How to see old backups automatically expire
- How to configure differential retention
- How to schedule automated backups with cron

**Prerequisites:**
- Completed guides 01-06 (pgBackRest installed, configured, backups taken, restore tested)
- PostgreSQL 16 is running

---

## Why do you need a retention policy?

Every backup takes up disk space. If you take daily backups and never delete old ones, your backup repository will eventually fill the entire disk. A retention policy tells pgBackRest how many backups to keep. When a new backup is taken, pgBackRest automatically deletes (expires) the oldest backups that exceed your retention limit.

---

## Step 1: Connect to your server

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Check the current retention setting

Let's look at your current pgBackRest configuration.

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

The key setting is `repo1-retention-full=2`. This means pgBackRest keeps the 2 most recent full backups. When a 3rd full backup is taken, the oldest one is automatically deleted.

> **Concept: Retention = how long your recovery window is**
> If you keep 2 full backups taken weekly, your recovery window is about 2 weeks. If a customer reports data was accidentally deleted 3 weeks ago, you can't recover it because those backups have already been expired. Choose your retention based on how far back you might need to go.

---

## Step 3: Switch to the postgres user

```bash
sudo -i -u postgres
```

---

## Step 4: Check current backups

Let's see what backups we have right now.

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        ...
        full backup: 20260420-121000F
            ...
```

You should have at least one full backup from guide 06. Note how many full backups are listed.

---

## Step 5: Take a full backup (backup 1 of 3)

You may already have several full backups from previous guides. With retention set to 2, any full backup beyond the two most recent will be expired automatically. We'll take enough full backups here to see expiration in action.

```bash
pgbackrest --stanza=main --type=full backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin 2.54: ...
...
P00   INFO: backup command end: completed successfully
...
```

Check the info.

```bash
pgbackrest --stanza=main info
```

Count the number of full backups listed. Write down the label of the oldest one.

---

## Step 6: Take another full backup

```bash
pgbackrest --stanza=main --type=full backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin ...
...
P00   INFO: backup command end: completed successfully
...
```

Check the info again.

```bash
pgbackrest --stanza=main info
```

If you already had 2 or more full backups, you may see expiration messages during this backup. That's normal - pgBackRest is enforcing the retention limit of 2.

---

## Step 7: Take one more full backup (ensure expiration triggers)

By now you should have more than 2 full backups, which means this backup will trigger expiration of the oldest ones.

```bash
pgbackrest --stanza=main --type=full backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin ...
...
P00   INFO: expire full backup ...
P00   INFO: remove expired backup ...
...
P00   INFO: backup command end: completed successfully
...
```

Look for the `expire` and `remove expired backup` lines. pgBackRest automatically deleted the oldest full backup(s) to stay within the retention limit of 2. If you don't see expiration messages, it means you had fewer than 3 full backups - take one more to trigger it.

Now check the info.

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        ...
        full backup: 20260420-130500F
            ...

        full backup: 20260420-131000F
            ...
```

Only 2 full backups remain. The oldest one was automatically expired and removed.

> **Concept: Count vs time-based retention**
> `repo1-retention-full=2` is count-based - keep 2 full backups regardless of age. You can also use time-based retention by setting `repo1-retention-full-type=time` and `repo1-retention-full=14` (keep backups for 14 days). Time-based is useful when your backup schedule isn't perfectly consistent.

---

## Step 8: Add differential retention

Right now we only have retention for full backups. Let's also configure how many differential backups to keep between full backups.

Exit the postgres user first.

```bash
exit
```

Open the pgBackRest configuration file.

```bash
sudo vi /etc/pgbackrest.conf
```

Find the `[global]` section. You need to add one new line after the `repo1-retention-full=2` line. Here's how:

1. Use the arrow keys to move your cursor to the line that says `repo1-retention-full=2`.
2. Press `o` to open a new line below and enter insert mode.
3. Type the following:

```
repo1-retention-diff=3
```

4. Press `Esc` to exit insert mode.
5. Type `:wq` and press `Enter` to save and quit.

The `[global]` section should now look like this:

```ini
[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=3
process-max=2
log-level-console=info
log-level-file=detail
start-fast=y
compress-type=lz4
```

The `repo1-retention-diff=3` setting means pgBackRest keeps the 3 most recent differential backups per full backup. Older differential backups are expired when a new one is taken.

---

## Step 9: Set up automated backups with cron

Instead of manually running backup commands, we'll schedule them to run automatically using cron - a built-in Linux scheduler.

> **Concept: Cron scheduling**
> Cron runs commands on a schedule. Each cron entry has 5 time fields: minute, hour, day-of-month, month, day-of-week. For example, `0 2 * * 0` means "at 2:00 AM every Sunday." The asterisk `*` means "every" - so `* * *` in the last three fields means "every day of every month."

Switch to the postgres user (cron jobs should run as the same user that owns the database).

```bash
sudo -i -u postgres
```

Open the crontab editor. This is where you define scheduled tasks for the postgres user.

```bash
crontab -e
```

This opens vi (or your default editor) with the current crontab. It may be empty or have some comments.

Press `i` to enter insert mode and add the following two lines:

```
# pgBackRest full backup every Sunday at 2:00 AM
0 2 * * 0 pgbackrest --stanza=main --type=full backup

# pgBackRest differential backup Mon-Sat at 2:00 AM
0 2 * * 1-6 pgbackrest --stanza=main --type=diff backup
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Let's break down the cron fields:

```
0 2 * * 0 = minute(0) hour(2) day(*) month(*) weekday(0=Sunday)
0 2 * * 1-6 = minute(0) hour(2) day(*) month(*) weekday(1-6=Mon-Sat)
```

So the schedule is:
- **Sunday at 2:00 AM**: full backup (fresh start for the week)
- **Monday through Saturday at 2:00 AM**: differential backup (only changes since Sunday's full)

---

## Step 10: Verify the cron entries were saved

```bash
crontab -l
```

```
Expected output (yours will differ):
# pgBackRest full backup every Sunday at 2:00 AM
0 2 * * 0 pgbackrest --stanza=main --type=full backup

# pgBackRest differential backup Mon-Sat at 2:00 AM
0 2 * * 1-6 pgbackrest --stanza=main --type=diff backup
```

`crontab -l` lists all cron entries for the current user. You should see both lines.

---

## Step 11: Test the cron command manually

Let's make sure the command that cron will run actually works. Run the differential backup command manually.

```bash
pgbackrest --stanza=main --type=diff backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin 2.54: ...
...
P00   INFO: backup command end: completed successfully
...
```

If this works manually, it will work from cron.

---

## Step 12: Check pgBackRest log files

pgBackRest writes detailed logs for every operation. Let's find them.

```bash
ls /var/log/pgbackrest/
```

```
Expected output (yours will differ):
main-backup.log
main-expire.log
main-restore.log
main-stanza-create.log
...
```

You should see log files for backup, expire, restore, and other operations you've run. The exact files depend on which pgBackRest commands you've used. Each log file is named after the stanza and the command. Let's look at the latest backup log.

```bash
tail -20 /var/log/pgbackrest/main-backup.log
```

```
Expected output (yours will differ):
...
P00   INFO: backup command begin 2.54: ...
P00 DETAIL: backup file /opt/pgsql/data/base/16384/16421 (8.0MB, 1.0%) checksum abc123...
P00 DETAIL: backup file /opt/pgsql/data/base/16384/16422 (1.0MB, 1.1%) checksum def456...
...
P00   INFO: backup command end: completed successfully
```

`tail -20` shows the last 20 lines of a file. The `DETAIL` level shows individual files being backed up - this is useful for troubleshooting slow or failed backups.

Now exit the postgres user.

```bash
exit
```

---

## What you built

- Watched retention automatically expire old full backups (3rd backup triggered deletion)
- Added differential retention policy
- Set up automated cron jobs for weekly full + daily differential backups
- Explored pgBackRest log files for monitoring and troubleshooting

## Verification

Switch to the postgres user and check the current state.

```bash
sudo -i -u postgres
```

Verify the backup schedule is set.

```bash
crontab -l
```

You should see two cron entries - one for Sunday full backups and one for Mon-Sat differential backups.

Verify all backups are healthy.

```bash
pgbackrest --stanza=main info
```

You should see 2 full backups and at least 1 differential backup, all with status `ok`.

```bash
exit
```

## Congratulations!

You have completed the entire pgBackRest BUILD series. Here's what you've accomplished:

1. **Installed** pgBackRest on CentOS Stream 9
2. **Configured** a stanza to connect pgBackRest to your PostgreSQL cluster
3. **Enabled** WAL archiving so every transaction is safely stored
4. **Took** a full backup of your entire database
5. **Took** differential and incremental backups to save time and space
6. **Restored** from a backup after a simulated disaster
7. **Performed** point-in-time recovery to travel back to a specific moment
8. **Set up** retention policies and automated scheduling

Your PostgreSQL database now has a complete, automated backup and recovery solution. In a production environment, this setup would protect you against hardware failures, accidental data deletion, and application bugs.
