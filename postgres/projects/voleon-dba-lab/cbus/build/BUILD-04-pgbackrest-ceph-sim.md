# Build Guide 04: Setup pgBackRest with Simulated Ceph RBD Storage

| | |
|---|---|
| **Time** | 60 minutes |
| **Servers** | pg-primary (3.90.199.62), pg-replica (3.91.32.84) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- What Ceph RBD is and why Voleon uses it for database storage
- How to simulate Ceph block storage using a loopback device and LVM
- How to install and configure pgBackRest on both servers
- How to configure PostgreSQL WAL archiving for pgBackRest
- How to create a backup stanza and run full and differential backups
- How to verify backup integrity using pgBackRest info

## Prerequisites

- BUILD-01 complete: PostgreSQL 17 running on pg-primary with archive_mode = on
- BUILD-03 complete: pg-replica is running as a standby
- You can SSH into both servers

---

## Step 1: Understand Ceph RBD and Why We Simulate It

Voleon runs PostgreSQL on Ceph RBD (RADOS Block Device) volumes in production. Here is what that means and why it matters for a DBA.

**What is Ceph?**
Ceph is a distributed storage system. Instead of data living on one disk inside the server, it is spread across multiple storage nodes in the cluster. If one storage node fails, the data is still available from the others.

**What is RBD?**
RBD (RADOS Block Device) is how Ceph presents storage to a server. From the operating system's perspective, it looks exactly like a regular block device (like `/dev/sdb`). You can format it with a filesystem and mount it like any disk.

**Why does Voleon use it for databases?**
- Data redundancy - the storage itself is replicated across nodes
- Snapshots - Ceph can snapshot a volume in seconds (useful for fast backups)
- Shared storage - multiple servers can access the same volume (needed for certain HA setups)
- The tradeoff: Ceph adds network latency compared to local NVMe. A local NVMe write takes microseconds. A Ceph write goes over the network and takes hundreds of microseconds.

**Why are we simulating it?**
We do not have a Ceph cluster in this lab. Instead, we create a file on disk, attach it as a loopback device, and put LVM on top of it. From the filesystem's perspective, it behaves identically to a real block device. This is how infrastructure teams test Ceph-adjacent workflows without a full Ceph cluster.

---

## Step 2: Create the Simulated Ceph RBD Storage on pg-replica

We will create the simulated storage on pg-replica. In production, the backup repository would live on dedicated backup infrastructure. In this lab, pg-replica serves double duty as the backup storage host.

SSH into pg-replica.

On your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

Now you are on **pg-replica**, as **ec2-user**.

Create a 10GB sparse image file. This file will act as our simulated block device. `dd` creates it by writing zeros. `bs=1M` means write in 1MB chunks. `count=10240` means 10240 chunks of 1MB = 10GB.

```bash
sudo dd if=/dev/zero of=/opt/ceph-sim.img bs=1M count=10240
```

```
Expected output (yours will differ):
10240+0 records in
10240+0 records out
10737418240 bytes (11 GB, 10.0 GiB) copied, 12.5 s, 860 MB/s
```

This will take 10-30 seconds depending on the server. Wait for it to finish.

Attach the image file as a loopback block device. A loopback device makes a file look like a physical disk to the kernel. `/dev/loop0` is the first available loopback device.

```bash
sudo losetup /dev/loop0 /opt/ceph-sim.img
```

This command produces no output on success. Verify the attachment:

```bash
sudo losetup -l
```

```
Expected output (yours will differ):
NAME       SIZELIMIT OFFSET AUTOCLEAR RO BACK-FILE         DIO LOG-SEC
/dev/loop0         0      0         0  0 /opt/ceph-sim.img   0     512
```

Install LVM2 tools. LVM (Logical Volume Manager) lets you create flexible volumes on top of block devices. `lvm2` is the package that provides the `pvcreate`, `vgcreate`, and `lvcreate` commands.

```bash
sudo dnf install -y lvm2
```

```
Expected output (yours will differ):
...
Installed:
  lvm2-x.x...
Complete!
```

---

## Step 3: Build the LVM Stack on the Loopback Device

LVM has three layers. Think of them like this:
- **Physical Volume (PV)** - the raw block device (our loopback)
- **Volume Group (VG)** - a pool that combines one or more PVs
- **Logical Volume (LV)** - a named slice of the pool that you actually format and mount

On **pg-replica**, as **ec2-user**:

Create a physical volume on the loopback device. This marks `/dev/loop0` as usable by LVM.

```bash
sudo pvcreate /dev/loop0
```

```
Expected output (yours will differ):
  Physical volume "/dev/loop0" successfully created.
```

Create a volume group named `ceph-vg`. A volume group is a named pool of storage. We are naming it `ceph-vg` to remind us it simulates a Ceph volume group.

```bash
sudo vgcreate ceph-vg /dev/loop0
```

```
Expected output (yours will differ):
  Volume group "ceph-vg" successfully created
```

Create a logical volume named `pg-lv` using 100% of the available space in `ceph-vg`. `-l 100%FREE` means "use all free extents." `-n pg-lv` names the logical volume.

```bash
sudo lvcreate -l 100%FREE -n pg-lv ceph-vg
```

```
Expected output (yours will differ):
  Logical volume "pg-lv" created.
```

Format the logical volume with XFS. XFS is the recommended filesystem for PostgreSQL on RHEL/CentOS. It handles large files well and has excellent performance for sequential writes.

```bash
sudo mkfs.xfs /dev/ceph-vg/pg-lv
```

```
Expected output (yours will differ):
meta-data=/dev/ceph-vg/pg-lv     isize=512    agcount=4, agsize=655104 blks
...
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
...
```

Create the mount point directory and mount the filesystem:

```bash
sudo mkdir -p /mnt/ceph-sim
```

```bash
sudo mount /dev/ceph-vg/pg-lv /mnt/ceph-sim
```

Set ownership so the postgres user can write to it. pgBackRest runs as postgres and needs to create directories and files under this path.

```bash
sudo chown postgres:postgres /mnt/ceph-sim
```

---

## Step 4: Make the Mount Persistent Across Reboots

The loopback device and mount will disappear after a reboot unless you configure them to persist. We need two things: a systemd unit to re-attach the loopback, and an fstab entry to remount.

On **pg-replica**, as **ec2-user**:

First, get the UUID of the filesystem so fstab can identify it reliably:

```bash
sudo blkid /dev/ceph-vg/pg-lv
```

```
Expected output (yours will differ):
/dev/ceph-vg/pg-lv: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" BLOCK_SIZE="512" TYPE="xfs"
```

Copy the UUID from your output. Open fstab:

```bash
sudo vi /etc/fstab
```

Add this line at the bottom. Replace `YOUR-UUID-HERE` with the UUID from the blkid output above.

```
UUID=YOUR-UUID-HERE  /mnt/ceph-sim  xfs  defaults,nofail  0  2
```

The `nofail` option means the server will still boot even if this mount fails (important for cloud instances). Save and exit: press `Esc`, type `:wq`, press Enter.

Create a systemd service to re-attach the loopback device at boot (before the mount):

```bash
sudo vi /etc/systemd/system/ceph-sim-loopback.service
```

Paste the following content exactly:

```
[Unit]
Description=Attach ceph-sim loopback device
Before=local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/sbin/losetup /dev/loop0 /opt/ceph-sim.img
RemainAfterExit=yes

[Install]
WantedBy=local-fs-pre.target
```

Save and exit vi: press `Esc`, type `:wq`, press Enter.

Enable the loopback service:

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl enable ceph-sim-loopback.service
```

```
Expected output (yours will differ):
Created symlink /etc/systemd/system/local-fs-pre.target.wants/ceph-sim-loopback.service ...
```

---

## Step 5: Verify the Simulated Storage

Confirm everything looks correct before moving on.

On **pg-replica**, as **ec2-user**:

Check the mounted filesystem:

```bash
df -h /mnt/ceph-sim
```

```
Expected output (yours will differ):
Filesystem                 Size  Used Avail Use% Mounted on
/dev/mapper/ceph--vg-pg--lv  10G   90M  9.9G   1% /mnt/ceph-sim
```

List logical volumes:

```bash
sudo lvs
```

```
Expected output (yours will differ):
  LV    VG      Attr       LSize   Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  pg-lv ceph-vg -wi-ao---- <10.00g
```

List physical volumes:

```bash
sudo pvs
```

```
Expected output (yours will differ):
  PV         VG      Fmt  Attr PSize   PFree
  /dev/loop0 ceph-vg lvm2 a--  <10.00g    0
```

The simulated Ceph storage is ready.

---

## Step 6: Install pgBackRest on Both Servers

pgBackRest needs to be installed on both the primary (which runs backups) and any server that hosts a backup repository. Install it on pg-primary first, then pg-replica.

On your **pg-replica terminal**, as **ec2-user**:

```bash
sudo dnf install -y pgbackrest
```

```
Expected output (yours will differ):
...
Installed:
  pgbackrest-2.x.x...
Complete!
```

Now open your **pg-primary terminal**. SSH into pg-primary if needed:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user**:

```bash
sudo dnf install -y pgbackrest
```

```
Expected output (yours will differ):
...
Installed:
  pgbackrest-2.x.x...
Complete!
```

Verify the version on both servers (run on each):

```bash
pgbackrest version
```

```
Expected output (yours will differ):
pgBackRest 2.x.x
```

---

## Step 7: Configure pgBackRest on pg-primary

pgBackRest uses a single configuration file at `/etc/pgbackrest/pgbackrest.conf`. You will configure two sections: `[global]` for general settings and `[voleon-lab]` for the specific database cluster (called a "stanza").

On **pg-primary**, as **ec2-user**:

The config directory may already exist from the package install. Check:

```bash
ls /etc/pgbackrest/
```

If the directory is missing, create it:

```bash
sudo mkdir -p /etc/pgbackrest
```

Open the configuration file:

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

Enter the following content. Read the comments - they explain what each setting does.

```ini
[global]
# Path where backups are stored. In production this would point to /mnt/ceph-sim
# or an S3 bucket. For simplicity in this lab, we use a local path on the primary.
repo1-path=/var/lib/pgbackrest

# How many full backups to keep. Older full backups (and their dependents) are deleted.
repo1-retention-full=2

# How many differential backups to keep per full backup.
repo1-retention-diff=7

# Compression algorithm. lz4 is fast with good compression ratio.
compress-type=lz4

# How many parallel processes to use for backup and restore.
process-max=2

# What to show on the console during operations.
log-level-console=info

# What detail level to write to the log file.
log-level-file=detail

[voleon-lab]
# Path to the PostgreSQL data directory.
pg1-path=/var/lib/pgsql/17/data

# Port PostgreSQL is listening on.
pg1-port=5432
```

Save and exit vi: press `Esc`, type `:wq`, press Enter.

---

## Step 8: Create Backup Directories on pg-primary

pgBackRest needs a directory to store the backup repository. This must be owned by the postgres user.

On **pg-primary**, as **ec2-user**:

Create the directory:

```bash
sudo mkdir -p /var/lib/pgbackrest
```

Set ownership:

```bash
sudo chown postgres:postgres /var/lib/pgbackrest
```

Set permissions so only postgres can read it (backup files may contain sensitive data):

```bash
sudo chmod 750 /var/lib/pgbackrest
```

Verify:

```bash
ls -la /var/lib/ | grep pgbackrest
```

```
Expected output (yours will differ):
drwxr-x--- 2 postgres postgres   6 Jun 15 14:30 pgbackrest
```

---

## Step 9: Configure PostgreSQL WAL Archiving for pgBackRest

pgBackRest uses WAL archiving to make point-in-time recovery possible. When PostgreSQL finishes a WAL segment, it calls the `archive_command` to copy that file to the backup repository. pgBackRest provides this command.

On **pg-primary**, as **ec2-user** - switch to postgres:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**. Connect to psql:

```bash
psql
```

Check the current archive settings:

```sql
SHOW archive_mode;
SHOW archive_command;
```

```
Expected output (yours will differ):
 archive_mode
--------------
 on
(1 row)

     archive_command
--------------------------
 (disabled)
(1 row)
```

`archive_mode` should already be `on` from BUILD-01. Now set the archive command. This tells PostgreSQL to call pgBackRest whenever it needs to archive a WAL file. `%p` is replaced by PostgreSQL with the full path to the WAL file.

```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=voleon-lab archive-push %p';
```

```
Expected output (yours will differ):
ALTER SYSTEM
```

Exit psql:

```sql
\q
```

Exit the postgres shell:

```bash
exit
```

On **pg-primary**, as **ec2-user** - reload PostgreSQL to apply the new archive_command. A reload is enough (no restart needed) because archive_command is not a restart-required parameter.

```bash
sudo systemctl reload postgresql-17
```

Verify the setting took effect. Switch back to postgres:

```bash
sudo su - postgres
```

```bash
psql -c "SHOW archive_command;"
```

```
Expected output (yours will differ):
                       archive_command
--------------------------------------------------------------
 pgbackrest --stanza=voleon-lab archive-push %p
(1 row)
```

Exit the postgres shell:

```bash
exit
```

---

## Step 10: Create the pgBackRest Stanza

A stanza is pgBackRest's term for a named configuration for one PostgreSQL cluster. Creating the stanza initializes the backup repository directory structure and records metadata about the PostgreSQL cluster.

On **pg-primary**, as **ec2-user** - switch to postgres:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**. Create the stanza:

```bash
pgbackrest --stanza=voleon-lab stanza-create
```

```
Expected output (yours will differ):
2026-06-15 14:35:01.123 P00   INFO: stanza-create command begin 2.x.x: ...
2026-06-15 14:35:01.234 P00   INFO: stanza-create for stanza 'voleon-lab' on repo1
2026-06-15 14:35:01.456 P00   INFO: stanza-create command end: completed successfully ...
```

The stanza-create command:
- Creates subdirectories in `/var/lib/pgbackrest` for archive WAL and backups
- Connects to PostgreSQL to read its version and system identifier
- Writes this metadata so pgBackRest can validate future backups against it

Verify the stanza was created by checking the archive and backup directories:

```bash
ls /var/lib/pgbackrest/
```

```
Expected output (yours will differ):
archive  backup
```

---

## Step 11: Run the Initial Full Backup

A full backup copies the entire PostgreSQL data directory. It is the foundation that differential and incremental backups build on.

On **pg-primary**, as **postgres**:

```bash
pgbackrest --stanza=voleon-lab --type=full backup
```

```
Expected output (yours will differ):
2026-06-15 14:36:01.100 P00   INFO: backup command begin 2.x.x: ...
2026-06-15 14:36:01.200 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint ...
2026-06-15 14:36:02.300 P00   INFO: backup start archive = 000000010000000000000006, lsn = 0/6000028
2026-06-15 14:36:05.400 P01   INFO: backup file /var/lib/pgsql/17/data/base/... (... KB, ...%)
...
2026-06-15 14:36:15.500 P00   INFO: full backup size = ... MB
2026-06-15 14:36:15.600 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2026-06-15 14:36:16.700 P00   INFO: backup stop archive = 000000010000000000000006, lsn = 0/6000100
2026-06-15 14:36:16.800 P00   INFO: new backup label = 20260615-143601F
2026-06-15 14:36:16.900 P00   INFO: full backup total ... MB
2026-06-15 14:36:17.000 P00   INFO: backup command end: completed successfully ...
```

The backup label (`20260615-143601F`) encodes the date, time, and type (`F` for full). Keep a note of it - you will reference it during restore exercises.

---

## Step 12: Verify the Backup

pgBackRest's `info` command shows all backups in the repository and validates their integrity.

On **pg-primary**, as **postgres**:

```bash
pgbackrest --stanza=voleon-lab info
```

```
Expected output (yours will differ):
stanza: voleon-lab
    status: ok
    cipher: none

    db (current)
        wal archive min/max (17): 000000010000000000000006/000000010000000000000006

        full backup: 20260615-143601F
            timestamp start/stop: 2026-06-15 14:36:01 / 2026-06-15 14:36:16
            wal start/stop: 000000010000000000000006 / 000000010000000000000006
            database size: ... MB, database backup size: ... MB
            repo1: backup set size: ... MB, backup size: ... MB
```

What to look for:
- `status: ok` - the stanza is healthy
- `wal archive min/max` - confirms WAL archiving is working (the WAL segment numbers should not be empty)
- The backup entry shows the start/stop timestamps and sizes

---

## Step 13: Run a Differential Backup

A differential backup copies only the data that changed since the last full backup. It is smaller and faster than a full backup. You need the full backup to restore from a differential - pgBackRest handles this automatically.

On **pg-primary**, as **postgres** - first insert some new data so the differential has something to capture:

```bash
psql -c "INSERT INTO replication_test (message) VALUES ('Before differential backup');"
```

Now run the differential backup:

```bash
pgbackrest --stanza=voleon-lab --type=diff backup
```

```
Expected output (yours will differ):
2026-06-15 14:45:01.100 P00   INFO: backup command begin 2.x.x: ...
2026-06-15 14:45:01.200 P00   INFO: last backup label = 20260615-143601F, version = 2.x.x
2026-06-15 14:45:02.300 P00   INFO: backup start archive = 000000010000000000000008, lsn = 0/8000028
...
2026-06-15 14:45:05.500 P00   INFO: new backup label = 20260615-144501F_20260615-144502D
2026-06-15 14:45:05.600 P00   INFO: diff backup total ... KB
2026-06-15 14:45:05.700 P00   INFO: backup command end: completed successfully ...
```

The differential backup label (`20260615-144501F_20260615-144502D`) contains both the full backup timestamp (`F`) and the differential timestamp (`D`). This tells you which full backup it depends on.

---

## Step 14: Verify Both Backups in pgBackRest Info

On **pg-primary**, as **postgres**:

```bash
pgbackrest --stanza=voleon-lab info
```

```
Expected output (yours will differ):
stanza: voleon-lab
    status: ok
    cipher: none

    db (current)
        wal archive min/max (17): 000000010000000000000006/000000010000000000000009

        full backup: 20260615-143601F
            timestamp start/stop: 2026-06-15 14:36:01 / 2026-06-15 14:36:16
            wal start/stop: 000000010000000000000006 / 000000010000000000000006
            database size: ... MB, database backup size: ... MB
            repo1: backup set size: ... MB, backup size: ... MB

        diff backup: 20260615-144501F_20260615-144502D
            timestamp start/stop: 2026-06-15 14:45:01 / 2026-06-15 14:45:05
            wal start/stop: 000000010000000000000008 / 000000010000000000000009
            database size: ... MB, database backup size: ... KB
            repo1: backup set size: ... MB, backup size: ... KB
```

You should see two backup entries:
- One full backup (`F` suffix)
- One differential backup (`D` suffix) that references the full

Notice the differential `database backup size` is much smaller than the full - it only captured the changed blocks.

Exit the postgres shell:

```bash
exit
```

---

## Step 15: Force a WAL Switch and Verify Archiving

Confirm that WAL archiving is working end-to-end by forcing a WAL segment switch and checking that pgBackRest receives it.

On **pg-primary**, as **ec2-user** - switch to postgres:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql
```

Force a WAL segment switch. This causes PostgreSQL to complete the current WAL segment and archive it immediately:

```sql
SELECT pg_switch_wal();
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 0/9000000
(1 row)
```

Exit psql:

```sql
\q
```

Check the pgBackRest archive directory to confirm the WAL segment was archived:

```bash
ls /var/lib/pgbackrest/archive/voleon-lab/17-1/
```

```
Expected output (yours will differ):
0000000100000000/
```

```bash
ls /var/lib/pgbackrest/archive/voleon-lab/17-1/0000000100000000/
```

```
Expected output (yours will differ):
000000010000000000000009.lz4
00000001000000000000000A.lz4
...
```

The `.lz4` extension confirms the WAL segments are being compressed (we set `compress-type=lz4` in the config). Each file here is a WAL segment that pgBackRest can use for point-in-time recovery.

Exit the postgres shell:

```bash
exit
```

---

## Summary

You have built a complete pgBackRest backup setup:

- A 10GB simulated Ceph RBD volume using loopback + LVM on pg-replica
- pgBackRest installed on both servers
- WAL archiving configured on pg-primary (archive_command calls pgbackrest)
- A stanza named `voleon-lab` initialized
- A full backup in `/var/lib/pgbackrest`
- A differential backup on top of the full
- WAL segments archiving successfully with lz4 compression

In the SURVIVE scenarios, you will use these backups to restore from simulated failures - including point-in-time recovery to a specific timestamp.
