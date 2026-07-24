# Build 05: LVM Basics

You will learn what LVM (Logical Volume Manager) is and why DBAs love it. LVM
lets you grow a database volume while the database keeps running, with no
downtime. You will build a small LVM setup on safe loopback files. Then you
will grow it live.

**Time estimate:** 55 minutes

All steps run on your lab server as the `ec2-user`. Storage commands need
`sudo`. Connect with SSH first.

---

## 1. Why LVM exists

Without LVM, a filesystem sits right on a partition of a fixed size. If the
partition fills up, growing it is painful. You often have to move data,
repartition, or add a whole new disk with a new mount point.

LVM adds a flexible layer between the disks and the filesystem. It pools your
storage. So you can carve out volumes of any size, resize them on the fly, and
add more disk capacity to the pool later. You do not touch the filesystem's
mount point. You do not take anything offline.

> **Concept - The three LVM layers:** LVM has three stacked pieces. Learn these
> names. Every LVM command maps to one of them:
> - **PV (Physical Volume):** a raw disk or partition handed to LVM, e.g.
>   `/dev/loop0`. This is the raw capacity.
> - **VG (Volume Group):** a pool made of one or more PVs. Think of it as a
>   bucket of storage you draw from.
> - **LV (Logical Volume):** a slice carved out of the VG. You put a filesystem
>   on the LV and mount it. This is what your database actually uses.
>
> The flow is: disks -> PV -> VG -> LV -> filesystem -> mount. To grow an LV,
> you pull more free space from the VG. To grow the VG, you add another PV.

---

## 2. Check whether LVM tools are installed

```bash
which pvcreate vgcreate lvcreate
```

`which` shows the path of each command if it exists. If any are missing,
install the LVM package below:

```bash
sudo dnf install -y lvm2
```

`dnf` is the CentOS Stream 9 package manager. `install -y lvm2` installs the
LVM tools and answers "yes" for you.

```
Expected output (yours will differ):
Installed:
  lvm2-2.03.23-2.el9.x86_64
Complete!
```

---

## 3. Create two safe practice disks

> **Warning - use loopback files, never real disks:** The `pvcreate` command
> claims a device for LVM and wipes its existing signature. Running it on a
> real disk destroys the data on it. As in Build 04, you will practice on
> harmless loopback files. That way there is zero risk to real storage.

Create two 256 MB loopback files and attach them:

```bash
sudo dd if=/dev/zero of=/var/tmp/lvm-disk1.img bs=1M count=256 status=progress
```

```bash
sudo dd if=/dev/zero of=/var/tmp/lvm-disk2.img bs=1M count=256 status=progress
```

Now attach each as a loop device:

```bash
sudo losetup -f --show /var/tmp/lvm-disk1.img
```

```bash
sudo losetup -f --show /var/tmp/lvm-disk2.img
```

```
Expected output (yours will differ):
/dev/loop0
/dev/loop1
```

Note the two device names it prints. This guide assumes `/dev/loop0` and
`/dev/loop1`. Use whatever names your server reports instead.

---

## 4. Build the LVM stack

### Step 1 - create the Physical Volumes (PVs)

```bash
sudo pvcreate /dev/loop0 /dev/loop1
```

`pvcreate` sets up each device as an LVM physical volume.

```
Expected output (yours will differ):
  Physical volume "/dev/loop0" successfully created.
  Physical volume "/dev/loop1" successfully created.
```

Verify with `pvs` (physical volume summary):

```bash
sudo pvs
```

```
Expected output (yours will differ):
  PV         VG   Fmt  Attr PSize   PFree
  /dev/loop0      lvm2 ---  252.00m 252.00m
  /dev/loop1      lvm2 ---  252.00m 252.00m
```

### Step 2 - create the Volume Group (VG)

Pool the two PVs into one volume group named `pgvg`:

```bash
sudo vgcreate pgvg /dev/loop0 /dev/loop1
```

`vgcreate NAME PV...` builds a volume group from the listed physical volumes.

```
Expected output (yours will differ):
  Volume group "pgvg" successfully created
```

Verify with `vgs` (volume group summary):

```bash
sudo vgs
```

```
Expected output (yours will differ):
  VG   #PV #LV #SN Attr   VSize   VFree
  pgvg   2   0   0 wz--n- 504.00m 504.00m
```

Notice the two 252 MB PVs pooled into one ~504 MB VG.

### Step 3 - create a Logical Volume (LV)

Carve a 200 MB logical volume named `pgdata` out of the pool:

```bash
sudo lvcreate -L 200M -n pgdata pgvg
```

- `-L 200M` sets the size to 200 MB.
- `-n pgdata` names the logical volume.
- `pgvg` is the volume group the space comes from.

```
Expected output (yours will differ):
  Logical volume "pgdata" created.
```

Verify with `lvs` (logical volume summary):

```bash
sudo lvs
```

```
Expected output (yours will differ):
  LV     VG   Attr       LSize   ...
  pgdata pgvg -wi-a----- 200.00m ...
```

The LV appears at the path `/dev/pgvg/pgdata` (volume group / logical volume).

### Step 4 - put a filesystem on it and mount it

```bash
sudo mkfs.xfs /dev/pgvg/pgdata
```

```bash
sudo mkdir -p /mnt/pgdata
```

```bash
sudo mount /dev/pgvg/pgdata /mnt/pgdata
```

Confirm and note the size:

```bash
df -h /mnt/pgdata
```

```
Expected output (yours will differ):
Filesystem              Size  Used Avail Use% Mounted on
/dev/mapper/pgvg-pgdata 195M  6.5M  189M   4% /mnt/pgdata
```

About 195 MB usable, mounted and ready.

---

## 5. The DBA win - grow the volume with no downtime

This is why LVM matters. Your VG still has free space. We used only 200 MB of
~504 MB. You can grow the mounted, in-use volume without unmounting it.

### Step 1 - extend the logical volume

```bash
sudo lvextend -L +150M /dev/pgvg/pgdata
```

`lvextend -L +150M` adds 150 MB to the logical volume from the VG's free space.
The `+` means "add to the current size", not "set the size to this".

```
Expected output (yours will differ):
  Size of logical volume pgvg/pgdata changed from 200.00 MiB to 350.00 MiB.
  Logical volume pgvg/pgdata successfully resized.
```

### Step 2 - grow the filesystem to fill the bigger volume

The LV is bigger now. But the filesystem inside it does not know that yet. Grow
it:

```bash
sudo xfs_growfs /mnt/pgdata
```

`xfs_growfs` expands an xfs filesystem to fill its device. Note that you point
it at the **mount point** (`/mnt/pgdata`), not the device. xfs can only grow
while it is mounted. That is exactly what makes this zero-downtime. (For ext4
the same job is done by `resize2fs`.)

```
Expected output (yours will differ):
data blocks changed from 51200 to 89600
```

### Step 3 - confirm the new size, still mounted

```bash
df -h /mnt/pgdata
```

```
Expected output (yours will differ):
Filesystem              Size  Used Avail Use% Mounted on
/dev/mapper/pgvg-pgdata 345M  6.5M  339M   2% /mnt/pgdata
```

The volume grew from ~195 MB to ~345 MB and was never unmounted.

> **DBA Context - Zero-downtime disk growth:** This is one of the biggest wins
> LVM gives a DBA. When a PostgreSQL data volume is filling up, you can add
> space while the database keeps serving queries. Attach a new disk, run
> `pvcreate` on it, `vgextend` it into the pool, then `lvextend` +
> `xfs_growfs`. No maintenance window, no downtime, no data move. Doing this
> under pressure at 3 a.m. is far calmer when the volume is on LVM.

---

## 6. Clean up the practice setup

Unmount and tear down the LVM stack, then detach the loop files:

```bash
sudo umount /mnt/pgdata
```

```bash
sudo lvremove -y /dev/pgvg/pgdata
```

```bash
sudo vgremove -y pgvg
```

```bash
sudo pvremove /dev/loop0 /dev/loop1
```

The `-y` flag answers "yes" to the confirmation prompts. Now detach the loop
devices and delete the files below:

```bash
sudo losetup -d /dev/loop0 /dev/loop1
```

```bash
sudo rm /var/tmp/lvm-disk1.img /var/tmp/lvm-disk2.img
```

Confirm nothing is left:

```bash
sudo vgs
```

```
Expected output (yours will differ):
  No volume groups found
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain why LVM exists and the problem it solves
- [ ] Name the three LVM layers (PV, VG, LV) and the flow between them
- [ ] Create loopback practice disks and initialize them as PVs with `pvcreate`
- [ ] Pool PVs into a volume group with `vgcreate` and inspect it with `vgs`
- [ ] Carve out a logical volume with `lvcreate` and inspect it with `lvs`
- [ ] Put a filesystem on an LV, mount it, and confirm with `df -h`
- [ ] Grow a mounted volume with `lvextend` then `xfs_growfs` - no downtime
- [ ] Explain why zero-downtime disk growth is a major DBA win
- [ ] Tear down an LVM stack cleanly with `lvremove`, `vgremove`, `pvremove`
