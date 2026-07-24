# Scenario 05 - Read-Only Filesystem

**Severity:** P2 - High
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Cannot write to /opt directory
Attempts to create files or directories in /opt fail with
'Read-only file system' error.
Database installation and updates cannot proceed.
```

---

## Key Concepts for Revision

- **mount** - The command that attaches a filesystem (disk, partition, or virtual mount) to a directory in the filesystem tree. Every directory you see is part of a mounted filesystem.

- **Read-only mount** - A filesystem can be mounted as read-only (`ro`), which means no files can be created, modified, or deleted. This is used for protection (e.g., boot partitions) but causes failures when applications need to write.

- **Bind mount** - A way to mount a directory on top of itself or another location. A read-only bind mount can make a normally writable directory read-only.

- **mount command** - `mount` with no arguments shows all current mounts and their options. Look for `ro` (read-only) in the mount options.

- **remount** - `mount -o remount,rw /path` changes mount options without unmounting. This is how you switch from read-only to read-write.

---

## Diagnostic Steps

### Step 1 - Confirm the problem

```bash
sudo touch /opt/test-file
```

Expected: `touch: cannot touch '/opt/test-file': Read-only file system`

### Step 2 - Check mount options

```bash
mount | grep "/opt"
```

```
Expected output (yours will differ):
/dev/xvda1 on /opt type xfs (ro,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota)
```

Look at the options in parentheses. You should see `ro` which means read-only.

### Step 3 - Check if /opt is a separate mount or a bind mount

```bash
findmnt /opt
```

```
Expected output (yours will differ):
TARGET SOURCE    FSTYPE OPTIONS
/opt   /dev/xvda1 xfs   ro,relatime,...
```

This shows what is mounted at `/opt` and its options.

### Step 4 - Remount /opt as read-write

```bash
sudo mount -o remount,rw /opt
```

The `-o remount,rw` option changes the mount from read-only to read-write without unmounting.

If /opt has a bind mount, you may need to unmount the bind mount first:

```bash
sudo umount /opt
```

If that gives an error about the filesystem being busy, try the remount approach instead.

### Step 5 - Verify the fix

```bash
mount | grep "/opt"
```

Confirm that `rw` (read-write) appears in the options instead of `ro`.

Test by creating and removing a file:

```bash
sudo touch /opt/test-write
```

```bash
sudo rm /opt/test-write
```

Both commands should succeed without errors.

```bash
findmnt /opt
```

If `/opt` no longer appears as a separate mount point (it is just part of `/`), that is correct - the bind mount was removed.

---

## Root Cause

A read-only bind mount was placed over `/opt`, preventing any writes. This can happen through misconfigured mount commands, security hardening scripts, or accidental changes to `/etc/fstab`.

---

## Prevention

- Carefully review `/etc/fstab` entries - a typo can mount a filesystem as read-only.
- Test mount changes on non-production servers first.
- After security hardening, verify that directories needed by databases are still writable.
- Monitor for read-only filesystem alerts in your monitoring system.
