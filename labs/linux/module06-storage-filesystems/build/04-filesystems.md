# Build 04: Filesystems

You will learn what a filesystem is. You will learn the difference between
`ext4` and `xfs` on CentOS. And you will learn how to create one with `mkfs`.
Creating a filesystem erases everything on the target device. So you will
practice on a safe loopback file, never on a real disk.

**Time estimate:** 50 minutes

All steps run on your lab server as the `ec2-user`. Storage commands need
`sudo`. Connect with SSH first.

---

## 1. What a filesystem is

A raw partition is just a blank stretch of blocks. A **filesystem** is the
structure written onto it. It is the bookkeeping that turns raw blocks into
named files and directories. It tracks free space and records permissions.
"Formatting" a device means writing a fresh filesystem onto it.

You already saw filesystems in `df -hT` and `lsblk -f`. Now you will make one.

---

## 2. ext4 vs xfs on CentOS

CentOS Stream 9 comes with two main filesystem choices. You will meet both.

| Feature | ext4 | xfs |
|---------|------|-----|
| Default on CentOS/RHEL | No (but very common) | Yes (root filesystem) |
| Best at | Rock-solid, well understood, can shrink | Large files, high parallelism, big volumes |
| Can grow online | Yes | Yes (`xfs_growfs`) |
| Can shrink | Yes | No (xfs cannot shrink) |
| Typical DBA use | General purpose | Large database data volumes |

> **DBA Context - Which to pick:** For most PostgreSQL data volumes, `xfs` is
> the safe default on CentOS. It is the OS default. It handles large files and
> many writes at once. And it grows while mounted (you will do this in Build
> 05). The one thing to remember: `xfs` cannot shrink. If you might need to make
> a volume smaller, pick `ext4`. In practice DBAs rarely shrink volumes. So
> `xfs` wins most of the time.

Check what your root filesystem uses:

```bash
df -hT /
```

```
Expected output (yours will differ):
Filesystem     Type  Size  Used Avail Use% Mounted on
/dev/nvme0n1p2 xfs    10G  1.2G  8.9G  12% /
```

---

## 3. Creating a safe practice device (loopback file)

> **Warning - mkfs erases everything:** `mkfs` writes a brand-new filesystem
> and destroys all existing data on the target. Running it on the wrong device
> (like `/dev/nvme0n1` - your root disk) will wipe the server. NEVER run `mkfs`
> on a device that holds data. In this lab you will create a harmless "loopback
> file" and format that instead, so there is zero risk to real storage.

A loopback file is an ordinary file. Linux can treat it as if it were a disk.
It is the standard safe way to practice storage commands.

### Step 1 - create an empty 512 MB file

```bash
sudo dd if=/dev/zero of=/var/tmp/lab-disk.img bs=1M count=512 status=progress
```

Breaking this down:

- `dd` copies data block by block.
- `if=/dev/zero` reads from the zero device (an endless stream of zero bytes).
- `of=/var/tmp/lab-disk.img` writes to our practice file.
- `bs=1M` uses a 1 MB block size. `count=512` writes 512 of them, which is 512
  MB.
- `status=progress` shows a progress line.

```
Expected output (yours will differ):
512+0 records in
512+0 records out
536870912 bytes (537 MB, 512 MiB) copied, 1.31828 s, 407 MB/s
```

### Step 2 - attach it as a loop device

```bash
sudo losetup -f --show /var/tmp/lab-disk.img
```

`losetup` connects a file to a `/dev/loopN` block device. `-f` picks the first
free loop number. `--show` prints which one it chose.

```
Expected output (yours will differ):
/dev/loop0
```

Remember the device name it prints (here `/dev/loop0`). You will use it below.
Confirm it shows up as a block device:

```bash
lsblk /dev/loop0
```

```
Expected output (yours will differ):
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop0    7:0    0  512M  0 loop
```

---

## 4. Making an xfs filesystem

Now format the loop device (NOT a real disk) with xfs:

```bash
sudo mkfs.xfs /dev/loop0
```

`mkfs.xfs` writes an xfs filesystem onto the device. There is a whole family of
these commands: `mkfs.ext4`, `mkfs.xfs`, `mkfs.vfat`, and so on.

```
Expected output (yours will differ):
meta-data=/dev/loop0             isize=512    agcount=4, agsize=32768 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
data     =                       bsize=4096   blocks=131072, imaxpct=25
log      =internal log           bsize=4096   blocks=16384, version=2
realtime =none                   extsz=4096   blocks=0, rtextents=0
Discarding blocks...Done.
```

### Try ext4 too

You can reformat the same loop device with ext4 to see the difference. This is
safe. It is only the practice file:

```bash
sudo mkfs.ext4 /dev/loop0
```

```
Expected output (yours will differ):
mke2fs 1.46.5 (30-Dec-2021)
Creating filesystem with 131072 4k blocks and 32768 inodes
Filesystem UUID: 1bd08a80-8ebc-4629-9351-f215ff3631ca
...
Writing superblocks and filesystem accounting information: 0/4   done
```

For the rest of this guide, put xfs back so it matches a typical database
volume:

```bash
sudo mkfs.xfs -f /dev/loop0
```

The `-f` flag forces `mkfs.xfs` to overwrite the existing ext4 filesystem
without complaining. Use `-f` with care. Its whole job is to skip the "a
filesystem already exists" safety prompt.

---

## 5. Labels and UUIDs

Every filesystem gets a UUID (a unique ID) on its own. It can also have a
friendly label. You use these to identify filesystems in a reliable way,
exactly as fstab does.

### See the UUID with blkid

```bash
sudo blkid /dev/loop0
```

```
Expected output (yours will differ):
/dev/loop0: UUID="9f8e7d6c-..." TYPE="xfs"
```

### Set a label

```bash
sudo xfs_admin -L pgdata /dev/loop0
```

`xfs_admin -L` sets the label on an xfs filesystem. For ext4 the same job is
done by `e2label`. Labels make it obvious what a volume is for. Confirm it:

```bash
sudo blkid /dev/loop0
```

```
Expected output (yours will differ):
/dev/loop0: LABEL="pgdata" UUID="9f8e7d6c-..." TYPE="xfs"
```

> **DBA Context - Labels and UUIDs:** On a server with several volumes, a
> label like `pgdata` or `pgwal` tells you at a glance which disk is which.
> That is far clearer than `/dev/nvme3n1`. Both labels and UUIDs stay with the
> filesystem no matter how Linux numbers the devices. So they are what you use
> in `/etc/fstab` to mount the right volume every time.

---

## 6. Cleaning up the practice device

When you are done, detach the loop device and delete the file. This leaves the
server clean:

```bash
sudo losetup -d /dev/loop0
```

`losetup -d` detaches the loop device. Then remove the backing file:

```bash
sudo rm /var/tmp/lab-disk.img
```

Confirm the loop device is gone:

```bash
losetup -a
```

```
Expected output (yours will differ):
(no output means no loop devices are attached)
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a filesystem is and what "formatting" means
- [ ] State the key differences between ext4 and xfs (and that xfs cannot shrink)
- [ ] Explain why `mkfs` is dangerous and why you practice on a loopback file
- [ ] Create a loopback file with `dd` and attach it with `losetup`
- [ ] Create an xfs filesystem with `sudo mkfs.xfs`
- [ ] Understand the `-f` force flag and when it is used
- [ ] View a filesystem UUID with `sudo blkid`
- [ ] Set a filesystem label with `xfs_admin -L`
- [ ] Detach a loop device and clean up the practice file
