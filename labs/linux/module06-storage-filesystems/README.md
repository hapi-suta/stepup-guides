# Module 06 - Storage, Disks & Filesystems

This module shows how storage works on a Linux server. It also shows how a DBA
keeps that storage safe.

You will learn how to check disk space and read block devices. You will mount
filesystems and make those mounts survive a reboot. You will create
filesystems, use LVM to grow volumes with no downtime, and place a database
data directory on its own volume with the right owner.

A full or broken disk is one of the fastest ways to crash a database. So every
skill here is core safety work.

---

## Prerequisites

- Completion of Module 01 (Linux Fundamentals) - especially permissions
- Server access (CentOS Stream 9) - provided by your instructor
- SSH key from your welcome email
- A terminal application (Terminal on Mac, MobaXterm on Windows)

## Infrastructure

| Resource | Details |
|----------|---------|
| Nodes | 1 (your lab server) |
| OS | CentOS Stream 9 |
| SSH user | ec2-user |
| Package manager | dnf |

> **Safety note:** Several guides create filesystems and volumes. You will
> always practice on harmless loopback files, never on a real disk. Never run
> `mkfs`, partitioning, or `pvcreate` against a device that holds data -
> especially the root disk.

---

## Directory Structure

```
module06-storage-filesystems/
  build/          Step-by-step guided labs
  use/            Independent exercises
  survive/        Chaos scenarios to troubleshoot
  concepts/       Reference material
```

---

## Phases

### Phase 1 - BUILD

Work through these guides in order. Each one builds on the previous.

| # | Guide | Time | Topics |
|---|-------|------|--------|
| 01 | [Checking Disk Space](build/01-checking-disk-space.md) | 45 min | df -h, du -sh, sort -h, finding what fills a disk, inodes, swap emergencies |
| 02 | [Block Devices](build/02-block-devices.md) | 40 min | lsblk, fdisk -l, /dev naming, disks vs partitions |
| 03 | [Mounts and fstab](build/03-mounts-and-fstab.md) | 45 min | mount, /proc/mounts, /etc/fstab fields, persistent mounts, bad-fstab danger |
| 04 | [Filesystems](build/04-filesystems.md) | 50 min | ext4 vs xfs, mkfs on a spare device, labels and UUIDs |
| 05 | [LVM Basics](build/05-lvm-basics.md) | 55 min | PV/VG/LV, lvextend + xfs_growfs, zero-downtime growth |
| 06 | [Data Directory Placement](build/06-data-directory-placement.md) | 50 min | dedicated volume, postgres:postgres ownership, 700 perms |

### Phase 2 - USE

Complete these exercises without looking back at the BUILD guides.

| # | Exercise | Time | Focus |
|---|----------|------|-------|
| 01 | Disk Space Investigator | 15-20 min | Track down what is filling a filesystem |
| 02 | Volume Builder | 20 min | Format, mount, and verify a practice volume |
| 03 | LVM Grow Challenge | 20 min | Grow a mounted volume with no downtime |
| 04 | Data Directory Prep | 15-20 min | Place and permission a data directory correctly |
| - | Knowledge Checklist | 20 min | Self-assessment before Phase 3 |

### Phase 3 - SURVIVE

Your instructor will break something on your server. You must find the problem
and fix it. Use only the runbook and what you learned in BUILD.

| # | Scenario | Alert |
|---|----------|-------|
| 01 | Disk Full | PostgreSQL stopped writing - filesystem at 100% |
| 02 | Data Directory Permissions | Database refuses to start after a permissions change |
| 03 | Unmounted Data Volume | Data directory is empty after a reboot |
| 04 | Broken fstab | Server dropped to emergency mode on boot |

### Concepts

| Document | Topics |
|----------|--------|
| [Linux Storage](concepts/linux-storage.md) | Storage stack, disks/partitions/filesystems, mounts and fstab, LVM, monitoring, DBA relevance |

---

## Time Estimate

| Phase | Time |
|-------|------|
| BUILD | 4.5-5 hours |
| USE | 1.5-2 hours |
| SURVIVE | 2-3 hours |
| **Total** | **8-10 hours** |

Work at your own pace. Take breaks between BUILD guides. Do not rush.

---

## Getting Help

If you get stuck:

1. Re-read the BUILD guide for the topic you are working on
2. Check the Concepts reference
3. Ask your instructor
