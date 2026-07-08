# Linux Storage - Concepts Reference

This is a full reference for how storage works on Linux. Use it next to the
BUILD guides. Come back to it whenever you need to look something up.

Storage is core safety work for a DBA. A full or broken disk is one of the
fastest ways to take a database down.

---

## 1. The Storage Stack - Disks to Files

Storage on Linux is built in layers. Data passes through every layer before it
becomes a file you can use. Once you know the layers, you can find problems
fast.

```
Physical / virtual disk        (e.g. /dev/nvme0n1, /dev/sda)
        |
        v
Partition                      (e.g. /dev/nvme0n1p1) - a slice of the disk
        |
        v
[optional] LVM layer           PV -> VG -> LV
        |
        v
Filesystem                     (xfs, ext4) - written onto the partition or LV
        |
        v
Mount point                    (a directory like / or /opt/pgdata)
        |
        v
Files and directories          what applications actually use
```

| Layer | What it is | Command to inspect |
|-------|-----------|--------------------|
| Disk | Whole storage device | `lsblk`, `sudo fdisk -l` |
| Partition | A slice of a disk | `lsblk`, `sudo fdisk -l` |
| Physical Volume (LVM) | A disk/partition given to LVM | `sudo pvs` |
| Volume Group (LVM) | A pool of PVs | `sudo vgs` |
| Logical Volume (LVM) | A slice carved from a VG | `sudo lvs` |
| Filesystem | Structure that holds files | `blkid`, `lsblk -f`, `df -hT` |
| Mount | Filesystem attached to a directory | `mount`, `findmnt`, `/proc/mounts` |

---

## 2. Disks vs Partitions vs Filesystems

These three are easy to mix up. But they are different things:

- A **disk** is the whole device. It has a total size and a `/dev` name like
  `/dev/nvme0n1` or `/dev/sda`.
- A **partition** is a slice of a disk. One disk can hold several partitions.
  Each one gets a number added to the name (`/dev/nvme0n1p1`, `/dev/sda2`). You
  do not have to partition a disk. LVM often uses whole disks directly.
- A **filesystem** is the structure written onto a partition (or LV, or whole
  disk). It turns raw blocks into named files. It tracks free space and stores
  permissions. "Formatting" means writing a fresh filesystem. That erases
  whatever was there.

You put a filesystem on a device. Then you **mount** it to make it usable.

### /dev Naming

| Pattern | Meaning |
|---------|---------|
| `/dev/sda`, `/dev/sdb` | SCSI/SATA/virtio disks, in discovery order |
| `/dev/sda1` | Partition 1 on `sda` |
| `/dev/nvme0n1` | First NVMe SSD (common on AWS) |
| `/dev/nvme0n1p1` | Partition 1 on that NVMe disk (note the `p`) |
| `/dev/xvda` | Xen virtual disk (older AWS instances) |
| `/dev/loop0` | Loopback device - a file treated as a disk (used for practice) |
| `/dev/mapper/vg-lv` | An LVM logical volume |

Device names are handed out in the order Linux finds the disks. They can change
between boots. So when a name has to stay stable, refer to a filesystem by its
**UUID** or **label**, not by its device name. This matters most in
`/etc/fstab`.

---

## 3. Filesystems - ext4 and xfs

CentOS Stream 9 uses two main filesystems.

| Feature | ext4 | xfs |
|---------|------|-----|
| CentOS/RHEL default | Common, but not default | Default (root filesystem) |
| Grow online | Yes (`resize2fs`) | Yes (`xfs_growfs`) |
| Shrink | Yes | No - xfs cannot shrink |
| Strengths | Mature, flexible, shrinkable | Large files, high concurrency, big volumes |
| Typical DBA use | When you may need to shrink | Default for database data volumes |

Create a filesystem with the `mkfs` family of commands: `mkfs.xfs`,
`mkfs.ext4`, `mkfs.vfat`. Every filesystem gets a UUID on its own. It can also
carry a friendly label (`xfs_admin -L` for xfs, `e2label` for ext4).

> **Danger:** `mkfs` destroys all data on the target device. Always confirm the
> device name (with `lsblk`) before formatting, and practice on loopback files,
> never on a disk that holds data - especially never the root disk.

---

## 4. Mounts and /etc/fstab

A filesystem is not usable until it is **mounted** onto a directory. That
directory is called the mount point. The root filesystem is mounted at `/`.
Other filesystems attach to subdirectories like `/boot` or `/opt/pgdata`.

- Manual mounts (`sudo mount DEVICE DIR`) are temporary and vanish on reboot.
- `/etc/fstab` lists filesystems to mount automatically at boot.

### The six fstab fields

```
UUID=e5f6a7b8-...   /opt/pgdata   xfs   defaults,noatime   0 2
     device          mountpoint   fs      options         dump  fsck
```

| # | Field | Notes |
|---|-------|-------|
| 1 | Device | Use `UUID=` (stable), not `/dev/sdb` (can change) |
| 2 | Mount point | Directory to attach to |
| 3 | Filesystem type | `xfs`, `ext4`, `vfat`, `swap` |
| 4 | Options | `defaults`, `noatime`, etc. |
| 5 | Dump | Legacy backup flag, almost always `0` |
| 6 | fsck order | `0` = skip, `1` = root, `2` = other filesystems |

> **Danger:** A wrong device, typo, or missing filesystem in fstab can halt the
> boot in emergency mode. Always: back up fstab first, use UUIDs, and test with
> `sudo mount -a` before rebooting.

A common option is `noatime`. It stops Linux from writing an access timestamp
on every read. This is a standard tweak for database volumes that get read a
lot.

---

## 5. LVM - Logical Volume Manager

LVM adds a flexible layer between disks and filesystems. This lets you resize
and pool volumes with no downtime.

```
Disks/partitions  ->  PV  ->  VG  ->  LV  ->  filesystem  ->  mount
```

| Layer | Full name | Create with | Inspect with |
|-------|-----------|-------------|--------------|
| PV | Physical Volume | `pvcreate` | `pvs` |
| VG | Volume Group (pool of PVs) | `vgcreate` | `vgs` |
| LV | Logical Volume (slice of VG) | `lvcreate` | `lvs` |

### The DBA superpower: grow with no downtime

To grow a mounted, in-use volume:

1. `sudo lvextend -L +150M /dev/vg/lv` - enlarge the logical volume.
2. `sudo xfs_growfs /mountpoint` - grow the filesystem to fill it (for ext4:
   `resize2fs`).

Need more room in the pool first? Attach a disk, run `pvcreate` on it, then
`vgextend` it into the VG. None of this needs unmounting or stopping the
database.

---

## 6. Monitoring Disk Space

| Command | What it tells you |
|---------|-------------------|
| `df -h` | Free/used space per mounted filesystem (watch `Use%`) |
| `df -hT` | Same, plus filesystem type |
| `df -i` | Inode usage (a disk can be "full" of inodes with free bytes) |
| `du -sh /path` | Total size of one directory |
| `du -sh /var/* \| sort -h` | Rank children by size - the disk-hunting workhorse |
| `free -h` | Memory and swap usage |
| `swapon --show` | Active swap devices |

### Two ways a disk runs "out"

- **Out of bytes:** `df -h` shows `Use%` at 100%. Usual cause: runaway logs,
  old WAL archives that were never cleaned up, forgotten backups, or temp
  files.
- **Out of inodes:** `df -i` shows `IUse%` at 100% but bytes are still free.
  Cause: millions of tiny files. The fix is the same. Find and clean the
  directory holding them.

---

## 7. Why Storage Matters to a DBA

- **A full disk crashes the database.** When the filesystem holding WAL or data
  hits 100%, PostgreSQL cannot write. It will stop or crash. Set an alert at
  about 80% so you have time to act.
- **Isolation prevents outages.** Put the data directory on its own volume. Then
  a full database disk stays a database problem. It will not take down sshd,
  journald, and the whole box when `/` fills.
- **The data directory needs `postgres:postgres` ownership and `700`
  permissions.** If not, PostgreSQL refuses to start. It prints `FATAL: data
  directory has group or world access`. Wrong ownership or permissions is the
  number one reason a fresh database will not start.
- **Swap usage is an emergency.** RAM is measured in nanoseconds. Swap lives on
  disk and is measured in milliseconds. When database memory spills into swap,
  everything slows way down. Rising `Swap used` means something is using more
  memory than the box has. Find it fast.
- **LVM keeps you calm at 3 a.m.** A data volume on LVM can be grown while it
  runs. So a filling disk becomes a routine `lvextend` + `xfs_growfs`. No
  outage, no data move.

---

## 8. Quick Command Reference

```bash
# Space and usage
df -h                          # free space per filesystem
df -hT                         # with filesystem types
df -i                          # inode usage
du -sh /var/* | sort -h        # biggest directories under /var
free -h                        # memory + swap
swapon --show                  # swap devices

# Block devices
lsblk                          # disks and partitions as a tree
lsblk -f                       # with filesystem info
sudo fdisk -l                  # partition tables
sudo blkid                     # UUIDs, labels, types

# Filesystems
sudo mkfs.xfs /dev/DEVICE      # create xfs (ERASES the device)
sudo xfs_admin -L pgdata /dev/DEVICE   # set xfs label

# Mounts
mount                          # what is mounted
findmnt                        # mounts as a tree
sudo mount /dev/DEVICE /mnt/x  # temporary mount
sudo umount /mnt/x             # unmount
sudo mount -a                  # mount everything in fstab (test after editing)

# LVM
sudo pvcreate /dev/DEVICE      # physical volume
sudo vgcreate vg /dev/DEVICE   # volume group
sudo lvcreate -L 200M -n lv vg # logical volume
sudo lvextend -L +150M /dev/vg/lv   # grow the LV
sudo xfs_growfs /mountpoint    # grow the xfs filesystem to fill it
```
