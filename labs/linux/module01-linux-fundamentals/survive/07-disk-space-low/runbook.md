# Scenario 07 - Disk Space Low

**Severity:** P1 - Critical
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Low disk space warning on /var partition
Database operations may fail if disk becomes full.
Investigate and free space immediately.
```

---

## Key Concepts for Revision

- **df** - "disk free". Shows space usage for each mounted filesystem. `df -h` shows human-readable sizes. The `Use%` column shows how full each partition is.

- **du** - "disk usage". Shows how much space files and directories consume. `du -sh /var/*` shows the size of each item in `/var`. The `-s` flag summarizes each argument. The `-h` flag shows human-readable sizes.

- **find -size** - Finds files by size. `find /var -size +100M -type f` finds files larger than 100MB. This is the fastest way to find large files that are consuming space.

- **/var** - Where variable data lives. Database data, logs, and package caches all live here. This is the most common partition to fill up on a database server.

---

## Diagnostic Steps

### Step 1 - Check overall disk usage

```bash
df -h
```

Look for partitions with high `Use%`. Focus on the one containing `/var`.

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G   18G  1.8G  91% /
...
```

### Step 2 - Find what is using space in /var

```bash
sudo du -sh /var/* | sort -rh | head -10
```

The `sort -rh` sorts by size in reverse order (largest first) with human-readable format. This shows you which subdirectories are the biggest.

```
Expected output (yours will differ):
1.1G    /var/chaos-old-backup-full.dump
120M    /var/log
52M     /var/cache
...
```

### Step 3 - Find specific large files

```bash
sudo find /var -size +50M -type f
```

This finds all files larger than 50MB in `/var`.

```
Expected output (yours will differ):
/var/chaos-old-backup-full.dump
/var/log/chaos-old-audit.log.1
/var/log/chaos-old-audit.log.2
```

Get more details on each:

```bash
sudo find /var -size +50M -type f -exec ls -lh {} \;
```

The `-exec ls -lh {} \;` runs `ls -lh` on each file found, showing you the exact size and modification date.

```
Expected output (yours will differ):
-rw-r--r--. 1 root root 1.0G Apr 19 16:00 /var/chaos-old-backup-full.dump
-rw-r--r--. 1 root root  50M Apr 19 16:00 /var/log/chaos-old-audit.log.1
-rw-r--r--. 1 root root  50M Apr 19 16:00 /var/log/chaos-old-audit.log.2
```

### Step 4 - Verify the files are safe to delete

Before deleting, make sure these are not files the system needs. In this case, `chaos-old-backup-full.dump` is clearly an old dump file, and the `chaos-old-audit.log.*` files are old rotated logs.

### Step 5 - Remove the large files

```bash
sudo rm /var/chaos-old-backup-full.dump
```

```bash
sudo rm /var/log/chaos-old-audit.log.1
```

```bash
sudo rm /var/log/chaos-old-audit.log.2
```

### Step 6 - Verify space is recovered

```bash
df -h /var
```

The `Use%` should be significantly lower.

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G  5.2G   15G  27% /
```

---

## Root Cause

Large files accumulated in `/var` - a 1GB old backup dump and two 50MB old log files. Without regular cleanup, these files consumed most of the available disk space.

---

## Prevention

- Set up monitoring alerts at 80% and 90% disk usage.
- Implement automated backup cleanup (delete backups older than retention period).
- Configure log rotation (`logrotate`) to compress and remove old logs.
- Use separate partitions for `/var/log` and database data so one cannot fill the other.
- Run a weekly `find /var -size +100M -type f` to identify large files before they cause problems.
