# Build 03: Mounts and fstab

You will learn how a filesystem becomes usable by "mounting" it into the
directory tree. You will learn how to see what is mounted. You will also learn
how `/etc/fstab` makes mounts survive a reboot. A mistake in `/etc/fstab` can
stop a server from booting. So you will learn how to do it safely too.

**Time estimate:** 45 minutes

All steps run on your lab server as the `ec2-user`. Storage commands need
`sudo`. Connect with SSH first.

---

## 1. What "mounting" means

A filesystem on a partition is not usable until it is attached to a directory
in the tree. That attachment is called a **mount**. The directory it attaches
to is the **mount point**.

Think of it this way. The partition holds the files. But you reach them by
walking into a directory. Mounting connects the two. For example, the root
filesystem is mounted at `/`. And `/boot` is a separate filesystem mounted at
the `/boot` directory.

> **Concept - Mount point is just a directory:** A mount point is an ordinary
> empty directory. When you mount a filesystem onto it, that filesystem's
> contents appear "inside" the directory. Did the directory already have files?
> Those files are hidden (not deleted) while the mount is active. They come back
> when you unmount. Always mount onto empty directories to avoid confusion.

---

## 2. Seeing what is mounted

### The mount command

Run `mount` with no arguments to list everything currently mounted:

```bash
mount
```

This prints a long list. To see just the real disk filesystems, filter it:

```bash
mount | grep nvme
```

The pipe `|` sends the output of `mount` into `grep`. `grep` keeps only lines
that contain `nvme` (your disk devices).

```
Expected output (yours will differ):
/dev/nvme0n1p2 on / type xfs (rw,relatime,seclabel,attr2,inode64,logbufs=8,...)
```

Each line reads: `DEVICE on MOUNTPOINT type FILESYSTEM (OPTIONS)`.

### /proc/mounts - the kernel's source of truth

```bash
cat /proc/mounts
```

`/proc/mounts` is a virtual file. Linux keeps it up to date with every active
mount. It is the source of truth. The `mount` command reads from here.

```
Expected output (yours will differ):
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
/dev/nvme0n1p2 / xfs rw,seclabel,relatime,attr2,inode64,logbufs=8,logbsize=32k,noquota 0 0
...
```

### findmnt - the readable version

```bash
findmnt
```

`findmnt` shows all mounts as a clean tree. It is the friendliest way to see
what is mounted where.

```
Expected output (yours will differ):
TARGET                SOURCE         FSTYPE   OPTIONS
/                     /dev/nvme0n1p2 xfs      rw,relatime,seclabel,attr2,inode64,...
├─/proc               proc           proc     rw,nosuid,nodev,noexec,relatime
│ └─/proc/sys/fs/...  systemd-1      autofs   rw,relatime,fd=29,pgrp=1,...
├─/sys                sysfs          sysfs    rw,nosuid,nodev,noexec,relatime,seclabel
...
```

---

## 3. Mounting a filesystem by hand

Mounting by hand is temporary. It lasts until the next reboot. It is how you
test before you make a mount permanent. The general form is:

```
sudo mount DEVICE MOUNTPOINT
```

You need a formatted device to mount. If you finished Build 04, you have one.
For now, just learn the pattern. First create the mount point directory:

```bash
sudo mkdir -p /mnt/pgdata
```

`mkdir -p` creates the directory and any missing parent directories. `/mnt` is
the traditional place for temporary mounts.

Then mount a formatted device onto it (replace the device with your real one):

```bash
sudo mount /dev/nvme1n1 /mnt/pgdata
```

Verify it worked:

```bash
findmnt /mnt/pgdata
```

```
Expected output (yours will differ):
TARGET      SOURCE      FSTYPE OPTIONS
/mnt/pgdata /dev/nvme1n1 xfs   rw,relatime,seclabel,...
```

### Unmounting

```bash
sudo umount /mnt/pgdata
```

The command is `umount` (no "n", a common typo). It detaches the filesystem. It
fails if any program is using the mount, or if your shell is sitting inside it.
So `cd` out first. To see what is holding a busy mount:

```bash
sudo lsof /mnt/pgdata
```

`lsof` lists open files. Anything it shows under the mount point is preventing
the unmount.

---

## 4. Understanding /etc/fstab

Manual mounts vanish on reboot. `/etc/fstab` ("filesystem table") is the file
that tells the system what to mount at boot, on its own. Look at yours:

```bash
cat /etc/fstab
```

```
Expected output (yours will differ):
#
# /etc/fstab
# Created by anaconda on Mon Jul  6 04:10:29 2026
#
UUID=e084c9df-9811-4b0d-bbf0-025603f3d044 /   xfs   defaults   0 0
```

Each line has **six fields**, separated by spaces or tabs:

| Field | Name | What it is |
|-------|------|-----------|
| 1 | Device | What to mount. Use a `UUID=` (stable) not `/dev/sdb` (can change) |
| 2 | Mount point | Where to attach it (e.g. `/mnt/pgdata`) |
| 3 | Filesystem type | `xfs`, `ext4`, `vfat`, `swap` |
| 4 | Options | Mount options, comma-separated (`defaults`, `noatime`, etc.) |
| 5 | Dump | Backup flag for the old `dump` tool. Almost always `0` |
| 6 | fsck order | Boot-time check order. `0` = never, `1` = root, `2` = others |

> **Concept - Why UUID instead of /dev/sdb:** Device names like `/dev/sdb` are
> handed out in the order Linux finds disks at boot. Add a disk, or let the
> cloud attach volumes in a different order, and yesterday's `/dev/sdb` might
> become today's `/dev/sdc`. Then fstab mounts the wrong disk, or nothing at
> all. A UUID is baked into the filesystem itself and never changes. So it
> always points at the right filesystem. Always use UUIDs in fstab.

Get a device's UUID:

```bash
sudo blkid /dev/nvme0n1p2
```

```
Expected output (yours will differ):
/dev/nvme0n1p2: UUID="e084c9df-9811-4b0d-bbf0-025603f3d044" TYPE="xfs" PARTUUID="00ecfb6f-..."
```

---

## 5. Adding a persistent mount safely

This is where beginners break servers. A bad fstab line can stop a machine from
booting. The boot process halts when it cannot mount a filesystem listed in
fstab. So follow this careful order.

> **Warning - fstab can break boot:** A wrong device, a typo, or a filesystem
> that is not present will cause the boot to drop into emergency mode. Never
> reboot a production server right after editing fstab without testing the
> entry first. The `mount -a` test below is your safety net - do it every time.

### Step 1 - back up the current fstab

Before editing, always keep a copy you can restore:

```bash
sudo cp /etc/fstab /etc/fstab.bak
```

`cp` copies the file. If your edit goes wrong, you can restore it with
`sudo cp /etc/fstab.bak /etc/fstab`.

### Step 2 - get the UUID of your device

```bash
sudo blkid /dev/nvme1n1
```

Copy the UUID value from the output.

### Step 3 - edit fstab with vi

```bash
sudo vi /etc/fstab
```

Press `i` to enter insert mode, then add a new line at the bottom using your
real UUID (this example mounts a database volume with sensible options):

```
UUID=your-uuid-here  /mnt/pgdata  xfs  defaults,noatime  0 2
```

The `noatime` option tells Linux not to write an "accessed" timestamp every
time a file is read. Databases read all the time. So `noatime` removes a lot of
pointless writes. It is a small but standard database tweak. When done, press
`Esc`, then type `:wq` and press Enter to save and quit.

### Step 4 - TEST before trusting it

This is the most important step. Test that the fstab entry mounts cleanly:

```bash
sudo umount /mnt/pgdata 2>/dev/null; sudo mount -a
```

`mount -a` means "mount all filesystems listed in fstab that are not mounted
yet". If your new line is correct, it mounts cleanly. On this SELinux-enabled
box a brand-new xfs volume has no SELinux labels yet, so `mount -a` prints the
warning below the first time. That warning is normal and is NOT an error - the
mount still succeeds. What you must never see is a real error like "mount:
/mnt/pgdata: special device ... does not exist" or "wrong fs type". If you see
one of those, your fstab line is wrong. **Fix it now**, before any reboot.

```
Expected output (yours will differ):
mount: /mnt/pgdata does not contain SELinux labels.
       You just mounted a file system that supports labels which does not
       contain labels, onto an SELinux box. ...
```

### Step 5 - verify

```bash
findmnt /mnt/pgdata
```

```
Expected output (yours will differ):
TARGET      SOURCE       FSTYPE OPTIONS
/mnt/pgdata /dev/nvme1n1 xfs    rw,noatime,seclabel,...
```

Did `mount -a` succeed and `findmnt` show the mount? Then the entry is safe and
will survive reboots.

> **DBA Context - fstab and database uptime:** The database data volume must be
> mounted before PostgreSQL starts. So it belongs in fstab. But a broken fstab
> keeps the whole server from booting. A small storage change becomes an
> outage. Professional DBAs always run `sudo cp /etc/fstab /etc/fstab.bak` and
> `sudo mount -a` around every fstab edit. These steps are not optional.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what mounting is and what a mount point is
- [ ] Use `mount`, `findmnt`, and `cat /proc/mounts` to see what is mounted
- [ ] Manually mount a device with `sudo mount DEVICE MOUNTPOINT`
- [ ] Unmount with `sudo umount` and find what makes a mount busy with `lsof`
- [ ] Name all six fields of an `/etc/fstab` line
- [ ] Explain why fstab uses `UUID=` instead of `/dev/sdb`
- [ ] Get a device UUID with `sudo blkid`
- [ ] Back up fstab, add an entry, and TEST it with `sudo mount -a` before rebooting
- [ ] Explain how a bad fstab line can stop a server from booting
