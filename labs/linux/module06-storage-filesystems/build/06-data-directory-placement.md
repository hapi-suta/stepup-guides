# Build 06: Data Directory Placement

You will put everything together now. You will place a PostgreSQL data
directory on its own mounted volume, with the right owner and permissions. This
is exactly how a professional DBA prepares storage before starting a database.
It ties together disks, filesystems, mounts, and permissions.

**Time estimate:** 50 minutes

All steps run on your lab server as the `ec2-user`. Storage commands need
`sudo`. Connect with SSH first.

---

## 1. Why a dedicated volume for the data directory

By default, PostgreSQL's data directory lives on the root filesystem (for
example under `/var/lib/pgsql`). That works. But professionals put it on its
own volume. Here is why:

- **Isolation:** If the database fills its volume, it does not take down the
  whole operating system. The root filesystem stays healthy. So you can still
  log in, read logs, and fix the problem.
- **Growth:** A dedicated volume (especially on LVM) can be grown on its own
  without disturbing the OS.
- **Performance and clarity:** You can put the data volume on faster storage.
  You can monitor it on its own and back it up as one unit.

> **DBA Context - The classic outage:** A very common incident is logs or WAL
> filling the root filesystem to 100%. That then stops sshd, systemd journald,
> and every other service, not just the database. When the data directory is on
> its own volume, a database that fills its disk stays a database problem. It is
> not a whole-server outage. This one design choice prevents a lot of 3 a.m.
> pages.

For this guide we fake the dedicated volume with a loopback file (as in Builds
04 and 05). That keeps it completely safe. On a real server this would be a
real disk or an LVM logical volume.

---

## 2. Prepare the dedicated volume

> **Warning - mkfs erases data:** As before, `mkfs` destroys whatever is on the
> target. We only ever point it at a loopback file here, never a real disk.

Create and attach a 512 MB loopback file:

```bash
sudo dd if=/dev/zero of=/var/tmp/pgdata-disk.img bs=1M count=512 status=progress
```

```bash
sudo losetup -f --show /var/tmp/pgdata-disk.img
```

```
Expected output (yours will differ):
/dev/loop0
```

Format it with xfs (the CentOS default and a good database choice):

```bash
sudo mkfs.xfs /dev/loop0
```

```
Expected output (yours will differ):
meta-data=/dev/loop0             isize=512    agcount=4, agsize=32768 blks
...
Complete!
```

---

## 3. Create the mount point and mount

Create the directory PostgreSQL will use as its data directory:

```bash
sudo mkdir -p /opt/pgdata
```

We use `/opt/pgdata` here to keep the database storage clearly separate from
the OS. Mount the volume onto it:

```bash
sudo mount /dev/loop0 /opt/pgdata
```

Confirm the mount:

```bash
df -h /opt/pgdata
```

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      507M   26M  482M   6% /opt/pgdata
```

The "Mounted on" column reads `/opt/pgdata`. That confirms this directory is
now its own separate filesystem, not part of `/`.

---

## 4. Set ownership to postgres:postgres

PostgreSQL runs as the `postgres` user. That user must own its data directory.
If a `postgres` user does not exist on your lab box yet, create it for this
exercise:

```bash
id postgres || sudo useradd -r -m -d /var/lib/pgsql postgres
```

`id postgres` prints the user's IDs if the user exists. The `||` runs `useradd`
only if that check fails. `-r` makes it a system account. `-m` creates a home
directory. `-d` sets that home to the usual PostgreSQL location.

```
Expected output (yours will differ):
uid=26(postgres) gid=26(postgres) groups=26(postgres)
```

Now give the `postgres` user and group ownership of the mounted directory:

```bash
sudo chown postgres:postgres /opt/pgdata
```

`chown USER:GROUP PATH` changes both the owner and group. Here both are
`postgres`.

Verify the ownership:

```bash
ls -ld /opt/pgdata
```

The `-d` flag shows the directory itself, not its contents.

```
Expected output (yours will differ):
drwxr-xr-x. 2 postgres postgres 6 Apr 19 15:00 /opt/pgdata
```

The owner and group are now both `postgres`. Good. But the permissions are
still too open. Fix that next.

---

## 5. Lock permissions to 700

PostgreSQL refuses to start unless only the owner can reach its data directory.
That is permission mode `700`. You learned `700` in Module 01: the owner gets
full access, and group and others get nothing.

```bash
sudo chmod 700 /opt/pgdata
```

Verify:

```bash
ls -ld /opt/pgdata
```

```
Expected output (yours will differ):
drwx------. 2 postgres postgres 6 Apr 19 15:00 /opt/pgdata
```

The permissions now read `drwx------` (700), owned by `postgres:postgres`. This
is the exact state PostgreSQL needs.

> **DBA Context - Why 700 is mandatory:** At startup PostgreSQL checks the data
> directory's permissions. It refuses to run if the group or others have any
> access. You would see: `FATAL: data directory "/opt/pgdata" has group or
> world access`. The data directory holds tables, indexes, user password
> hashes, and configuration. So it must be owner-only. Wrong ownership or
> permissions here is the number one reason a freshly installed database will
> not start.

---

## 6. Verify the whole setup

Run a final round of checks. Confirm the volume is placed, owned, and
permissioned correctly. This checklist matches what a DBA runs before starting
a database on new storage.

Confirm it is a separate mounted filesystem:

```bash
findmnt /opt/pgdata
```

```
Expected output (yours will differ):
TARGET      SOURCE     FSTYPE OPTIONS
/opt/pgdata /dev/loop0 xfs    rw,relatime,seclabel,...
```

Confirm ownership and permissions in one shot:

```bash
stat -c '%A %U:%G %n' /opt/pgdata
```

`stat -c` prints selected fields: `%A` = permission string, `%U:%G` =
owner:group, `%n` = name.

```
Expected output (yours will differ):
drwx------ postgres:postgres /opt/pgdata
```

If you see `drwx------` and `postgres:postgres`, the directory is ready for a
database.

> **Concept - Making it survive reboot:** On a real server you would now add a
> UUID-based line to `/etc/fstab` (Build 03). That way the volume remounts on
> boot before PostgreSQL starts. You would test it with `sudo mount -a`. Our
> loopback device is temporary, so we skip fstab here. But remember: on a real
> server the data volume must be in fstab, or the database will fail to start
> after a reboot.

---

## 7. Clean up

Tear down the practice setup:

```bash
sudo umount /opt/pgdata
```

```bash
sudo losetup -d /dev/loop0
```

```bash
sudo rm /var/tmp/pgdata-disk.img
```

```bash
sudo rmdir /opt/pgdata
```

`rmdir` removes the now-empty mount point directory. Confirm the mount is gone:

```bash
findmnt /opt/pgdata
```

```
Expected output (yours will differ):
(no output means it is no longer mounted)
```

---

## Checkpoint

Before moving on, confirm you can do all of the following:

- [ ] Explain why a database data directory belongs on its own volume
- [ ] Describe the classic outage where a full root filesystem kills every service
- [ ] Prepare and format a dedicated volume (loopback file, xfs)
- [ ] Create a mount point and mount the volume, confirming with `df -h`
- [ ] Ensure a `postgres` user exists and set ownership with `chown postgres:postgres`
- [ ] Set permissions to `700` with `chmod` and explain why PostgreSQL requires it
- [ ] Verify placement, ownership, and permissions with `findmnt` and `stat`
- [ ] Explain why the data volume must be in `/etc/fstab` on a real server
- [ ] Clean up a mounted volume and its mount point
