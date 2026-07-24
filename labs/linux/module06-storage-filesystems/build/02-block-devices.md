# Build 02: Block Devices

You will learn how Linux sees physical and virtual disks. You will learn how
disks are split into partitions. You will also learn how to read the `/dev`
naming scheme. Before you can mount storage for a database, you need to know
what storage the server actually has.

**Time estimate:** 40 minutes

All steps run on your lab server as the `ec2-user`. Connect with SSH first.

---

## 1. What is a block device?

A block device is any piece of hardware that stores data in fixed-size chunks
called blocks. You can read or write those blocks in any order. Hard drives,
SSDs, and the virtual disks your cloud server uses are all block devices.

In Linux, block devices show up as special files under `/dev`. Remember the
"everything is a file" idea from Module 01. A disk is just a file you can read
from and write to.

> **Concept - Disks vs Partitions vs Filesystems:** These are three different
> layers. Mixing them up causes confusion:
> - A **disk** is the whole physical (or virtual) storage device.
> - A **partition** is a slice of a disk. One disk can be split into several
>   partitions.
> - A **filesystem** is the structure (xfs, ext4) written onto a partition so
>   it can hold files.
> You put a filesystem on a partition. Then you mount it to make it usable. You
> will do all three in the next guides.

---

## 2. lsblk - The clearest view of your disks

`lsblk` stands for "list block devices". It shows disks and their partitions as
a tree. This is the command you will reach for most.

```bash
lsblk
```

```
Expected output (yours will differ):
NAME        MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
nvme0n1     259:0    0  10G  0 disk
├─nvme0n1p1 259:1    0   1M  0 part
└─nvme0n1p2 259:2    0  10G  0 part /
nvme1n1     259:3    0   2G  0 disk
```

Reading this:

- `nvme0n1` is the whole root disk (10G). The `TYPE` column says `disk`.
- The indented `nvme0n1p1` and `p2` are partitions on that disk. `TYPE`
  says `part`. `p1` is a tiny 1M BIOS boot partition; `p2` holds the root
  filesystem.
- `nvme1n1` is a second, whole disk (2G) with no partitions and no
  mountpoint. That is a raw spare disk you can dedicate to a database. You
  will format and use it in the next guides.
- `MOUNTPOINTS` shows where each partition is attached in the filesystem tree.
  A blank mountpoint means the device is not mounted right now.
- `SIZE` is the capacity. `RM` is 1 for removable media. `RO` is 1 for
  read-only.

### Add filesystem details

```bash
lsblk -f
```

The `-f` flag adds filesystem details: type, label, UUID, and how full each one
is.

```
Expected output (yours will differ):
NAME        FSTYPE FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
nvme0n1
├─nvme0n1p1
└─nvme0n1p2 xfs                e084c9df-9811-4b0d-bbf0-025603f3d044    8.8G    11% /
nvme1n1
```

A device with a blank `FSTYPE` has no filesystem on it yet. Both `nvme0n1p1`
and the whole spare disk `nvme1n1` show blank here. That spare disk is raw
space you could format. This is exactly what you look for when adding storage
for a database.

---

## 3. Understanding /dev naming

Device names under `/dev` follow patterns. Once you know them, you can read any
server at a glance.

| Name pattern | Meaning |
|--------------|---------|
| `/dev/sda`, `/dev/sdb` | SCSI / SATA / virtio disks. First disk `sda`, second `sdb`, and so on |
| `/dev/sda1`, `/dev/sda2` | Partitions on `sda` - a number appended to the disk name |
| `/dev/nvme0n1` | First NVMe SSD (common on AWS). `nvme0` = controller 0, `n1` = namespace 1 |
| `/dev/nvme0n1p1` | Partition 1 on that NVMe disk - note the `p` before the number |
| `/dev/xvda` | Xen virtual disk (older AWS instance types) |

The key rule is simple. The disk gets a base name. Partitions add a number to
it (with a `p` in front for NVMe devices). So `nvme0n1` is the disk and
`nvme0n1p2` is its second partition.

List the device files directly:

```bash
ls -l /dev/nvme*
```

```
Expected output (yours will differ):
crw-------. 1 root root 241, 0 Jul  8 18:33 /dev/nvme0
brw-rw----. 1 root disk 259, 0 Jul  8 18:33 /dev/nvme0n1
brw-rw----. 1 root disk 259, 1 Jul  8 18:33 /dev/nvme0n1p1
brw-rw----. 1 root disk 259, 2 Jul  8 18:33 /dev/nvme0n1p2
...
```

Notice the first character on the disk and partition lines (`nvme0n1`,
`nvme0n1p1`, `nvme0n1p2`) is `b`. That marks these as **b**lock devices,
exactly as you learned in Module 01's permissions guide. The bare controller
entries like `/dev/nvme0` start with `c` (character device) - those are not
the disks you work with.

---

## 4. fdisk -l - Detailed disk and partition tables

`fdisk` is a partition tool. With the `-l` flag it only lists partition tables.
It changes nothing, so it is safe to run. It needs `sudo` because reading raw
disks is a root-only job.

```bash
sudo fdisk -l
```

```
Expected output (yours will differ):
Disk /dev/nvme0n1: 10 GiB, 10737418240 bytes, 20971520 sectors
Disk model: Amazon Elastic Block Store
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: A87812B7-...

Device         Start      End  Sectors Size Type
/dev/nvme0n1p1  2048     4095     2048   1M BIOS boot
/dev/nvme0n1p2  4096 20971486 20967391  10G Linux filesystem


Disk /dev/nvme1n1: 2 GiB, 2147483648 bytes, 4194304 sectors
Disk model: Amazon Elastic Block Store
...
```

This shows the total disk size and the partition table type (`gpt` is modern;
older disks use `dos`/MBR). It also shows every partition with its start, end,
and size.

> **DBA Context - Reading a new server:** When someone hands you a database
> server to set up, the first thing you do is run `lsblk` and `sudo fdisk -l`
> to see what storage exists. You are looking for an unformatted disk or
> partition (no filesystem, not mounted) that you can dedicate to the database
> data directory. Putting data on its own volume is a best practice. You will
> do it in Build 06.

### Look at one disk

You can point `fdisk -l` at a single disk:

```bash
sudo fdisk -l /dev/nvme0n1
```

This is handy on a server with many disks when you care about only one.

---

## 5. Other quick device commands

### blkid - show UUIDs and labels

```bash
sudo blkid
```

`blkid` prints the UUID, type, and label of each block device that has a
filesystem. You will use UUIDs a lot in Build 03 for stable mounting. Notice
the raw spare disk `nvme1n1` does not appear at all - `blkid` only lists
devices that already carry a filesystem, and the spare has none yet.

```
Expected output (yours will differ):
/dev/nvme0n1p2: UUID="e084c9df-9811-4b0d-bbf0-025603f3d044" TYPE="xfs" PARTUUID="00ecfb6f-..."
/dev/nvme0n1p1: PARTUUID="74d9727b-..."
...
```

### lsblk with specific columns

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
```

The `-o` flag lets you pick exactly which columns to show. This gives a clean,
readable summary. It covers almost everything you need day to day.

```
Expected output (yours will differ):
NAME        SIZE TYPE FSTYPE MOUNTPOINT
nvme0n1      10G disk
├─nvme0n1p1   1M part
└─nvme0n1p2  10G part xfs    /
nvme1n1       2G disk
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a block device is and why disks appear under `/dev`
- [ ] Explain the difference between a disk, a partition, and a filesystem
- [ ] Use `lsblk` to see disks and partitions as a tree
- [ ] Use `lsblk -f` to see which partitions have filesystems and which are raw
- [ ] Read `/dev` names: tell a disk (`nvme0n1`) from a partition (`nvme0n1p4`)
- [ ] Use `sudo fdisk -l` to view partition tables safely
- [ ] Use `sudo blkid` to see UUIDs and filesystem types
- [ ] Identify an unformatted disk or partition you could dedicate to a database
