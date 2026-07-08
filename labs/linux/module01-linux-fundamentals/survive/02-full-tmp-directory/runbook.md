# Scenario 02 - Full /tmp Directory

**Severity:** P2 - High
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application cannot create temporary files
/tmp partition is nearly full.
Database sort operations and temp table creation may fail.
```

---

## Key Concepts for Revision

- **df** - "disk free". Shows how much space is available on each filesystem/partition. `df -h` shows sizes in human-readable format (GB, MB).

- **du** - "disk usage". Shows how much space files and directories consume. `du -sh /tmp/*` shows the size of each item in `/tmp`.

- **/tmp** - A directory for temporary files. Programs write scratch files here during operations. Database engines use it for sorting large result sets and creating temporary tables. If `/tmp` fills up, these operations fail.

- **tmpwatch/systemd-tmpfiles** - On CentOS 9, `systemd-tmpfiles` automatically cleans old files from `/tmp`. By default, files older than 10 days are removed. But this does not help if the partition filled up today.

---

## Diagnostic Steps

### Step 1 - Check disk usage

```bash
df -h
```

Look for the row containing `/tmp` (it might be part of `/` or a separate partition). The `Use%` column shows how full it is.

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G   18G  1.8G  91% /
...
```

### Step 2 - Find what is using space in /tmp

```bash
sudo du -sh /tmp/*
```

`du -sh` shows the size of each item. `-s` means summary (total per item). `-h` means human-readable sizes.

```
Expected output (yours will differ):
500M    /tmp/chaos-bigfile-01.dat
500M    /tmp/chaos-bigfile-02.dat
500M    /tmp/chaos-bigfile-03.dat
500M    /tmp/chaos-old-sort-result.tmp
4.0K    /tmp/other-small-files
```

### Step 3 - Identify which files are safe to delete

List the files with details:

```bash
sudo ls -lhS /tmp/
```

The `-S` flag sorts by size (largest first). Look for unusually large files. Files named `chaos-*` or `*.tmp` are likely safe to remove.

### Step 4 - Remove the large files

Delete the identified large files one at a time:

```bash
sudo rm /tmp/chaos-bigfile-01.dat
```

```bash
sudo rm /tmp/chaos-bigfile-02.dat
```

```bash
sudo rm /tmp/chaos-bigfile-03.dat
```

```bash
sudo rm /tmp/chaos-old-sort-result.tmp
```

### Step 5 - Verify space is recovered

```bash
df -h /tmp
```

The `Use%` should be well below 80%.

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G  5.2G   15G  27% /
```

---

## Root Cause

Large temporary files filled the `/tmp` directory (or the partition it lives on). This can happen when database sort operations write large temp files, when backup scripts stage data in `/tmp`, or when applications create temp files and crash before cleaning them up.

---

## Prevention

- Monitor disk usage with alerts at 80% and 90% thresholds.
- Use a separate partition for `/tmp` so it cannot fill up the root filesystem.
- Configure database temp directories to use a dedicated disk (PostgreSQL: `temp_tablespaces`).
- Set up `systemd-tmpfiles` or a cron job to clean old files from `/tmp` regularly.
- Never write large files to `/tmp` in scripts - use a dedicated staging directory on a disk with enough space.
