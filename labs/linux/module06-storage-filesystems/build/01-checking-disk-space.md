# Build 01: Checking Disk Space

You will learn how to see how much disk space is used and how much is free. You
will also learn how to track down exactly what is filling a disk. A full disk
is one of the most common reasons a database crashes. So this is core safety
work.

**Time estimate:** 45 minutes

All steps run on your lab server as the `ec2-user`. Connect with SSH first
(see Module 01, Build 01).

---

## 1. df - How much space is free?

`df` stands for "disk free". It shows how much space each mounted filesystem is
using. It also shows how much space is left.

```bash
df -h
```

The `-h` flag means "human-readable". Without it, sizes show as raw 1-kilobyte
blocks. Those are hard to read. With it, you get GB, MB, and KB instead.

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
devtmpfs        794M     0  794M   0% /dev
tmpfs           835M     0  835M   0% /dev/shm
tmpfs           334M  4.7M  330M   2% /run
/dev/nvme0n1p2   10G  1.2G  8.9G  12% /
tmpfs           167M     0  167M   0% /run/user/1000
```

Each column tells you something:

- `Filesystem` - the device or virtual filesystem
- `Size` - total capacity
- `Used` - how much is used
- `Avail` - how much is free
- `Use%` - percentage used (the number you watch)
- `Mounted on` - where in the tree it is attached

> **DBA Context - Use%:** The `Use%` column is the number you care about most.
> When the filesystem holding your database data or WAL hits 100%, PostgreSQL
> can no longer write. It will stop or crash. Many teams set an alert at 80% so
> they have time to react before the disk fills.

### Check a specific filesystem

You can point `df` at a path to see only the filesystem that holds it:

```bash
df -h /var
```

```
Expected output (yours will differ):
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p2   10G  1.2G  8.9G  12% /
```

Notice the "Mounted on" says `/`, not `/var`. That tells you `/var` is not its
own separate filesystem here. It lives on the root filesystem. Knowing which
filesystem a path really lives on matters a lot when a disk fills up.

### See filesystem types

```bash
df -hT
```

The `-T` flag adds a "Type" column. It shows the filesystem type (xfs, ext4,
tmpfs, and so on). CentOS Stream 9 uses `xfs` by default for the root
filesystem.

```
Expected output (yours will differ):
Filesystem     Type      Size  Used Avail Use% Mounted on
/dev/nvme0n1p2 xfs        10G  1.2G  8.9G  12% /
tmpfs          tmpfs     835M     0  835M   0% /dev/shm
tmpfs          tmpfs     334M  4.7M  330M   2% /run
...
```

---

## 2. du - What is using the space?

`df` tells you a filesystem is full. `du` tells you *what* is filling it. `du`
stands for "disk usage". It measures the size of directories and everything
inside them.

### Measure a single directory

```bash
sudo du -sh /var/log
```

- `sudo` runs as root so `du` can read protected log directories (like
  `audit` and `sssd`). Without it you get "Permission denied" noise mixed
  into the total.
- `-s` means "summary" - show one total for the whole directory instead of
  every file inside it.
- `-h` means "human-readable" (GB, MB, KB).

```
Expected output (yours will differ):
5.0M	/var/log
```

### Rank the children of a directory

This is the single most useful disk-hunting command you will learn:

```bash
sudo du -sh /var/* | sort -h
```

Let's break it down:

- `sudo` runs as root so you can read directories your user cannot. `/var`
  holds root-owned data. Without `sudo` you get "Permission denied" noise.
- `du -sh /var/*` shows a summary size for each item directly inside `/var`.
- The pipe `|` sends that list into `sort`.
- `sort -h` sorts by human-readable size. So the biggest directory lands at the
  bottom of the list, right where your eye goes.

```
Expected output (yours will differ):
0	/var/adm
0	/var/games
4.0K	/var/tmp
28K	/var/cache
5.0M	/var/log
58M	/var/lib
```

The biggest one here is `/var/lib` at 58M. On a database server that is often
where the data directory lives. So that would make sense.

> **DBA Context - Hunting a full disk:** When a disk fills, you work from the
> top down. Start at the root of the full filesystem. Run `du -sh */ | sort -h`
> and `cd` into the biggest directory. Repeat until you find the culprit. On
> database servers the usual suspects are runaway logs, old WAL archive files,
> leftover temp files, and forgotten backups.

### Warning about du on huge trees

`du` walks every single file. So running it on the whole root filesystem can
take a while. It also adds load on a busy server. Point it at one specific
directory. Do not run `du -sh /` blindly on a production box.

---

## 3. Finding the biggest files

Sometimes it is not a directory eating the disk. It is one huge file, like a
log that was never rotated. Find the largest files under a path:

```bash
sudo find /var -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -5
```

Breaking this down:

- `find /var -type f` finds regular files (not directories) under `/var`.
- `-printf '%s %p\n'` prints each file's size in bytes (`%s`) then its path
  (`%p`).
- `2>/dev/null` throws away "Permission denied" error messages so the output
  stays clean.
- `sort -rn` sorts numerically (`-n`) in reverse (`-r`), biggest first.
- `head -5` keeps only the top 5.

```
Expected output (yours will differ):
37851136 /var/lib/rpm/rpmdb.sqlite
4128272 /var/lib/dnf/history.sqlite-wal
3522359 /var/lib/selinux/targeted/active/policy.linked
3516575 /var/log/anaconda/journal.log
...
```

The number is in bytes. `37851136` bytes is about 36 MB. This tells you right
away which single files are worth a look.

---

## 4. Checking inodes (the hidden way to run out of space)

A filesystem can show free space and still refuse to create files. That happens
when it runs out of inodes. An inode is the internal record that tracks each
file. Millions of tiny files can use up all the inodes before the bytes run
out. This is a common WAL-archive or temp-file problem.

```bash
df -i
```

The `-i` flag shows inode usage instead of byte usage.

```
Expected output (yours will differ):
Filesystem      Inodes IUsed   IFree IUse% Mounted on
/dev/nvme0n1p2 5241840 30282 5211558    1% /
tmpfs           213665     2  213663    1% /dev/shm
...
```

Is `IUse%` at 100% while `df -h` shows free space? Then you have an inode
problem, not a byte problem. The fix is the same. Find and clean up the
directory holding all the tiny files.

---

## 5. Why swap usage is an emergency

Swap is disk space Linux uses as overflow. It kicks in when physical memory
(RAM) fills up. Check it with:

```bash
free -h
```

`free` shows memory usage. The `-h` flag makes it human-readable.

```
Expected output (yours will differ):
               total        used        free      shared  buff/cache   available
Mem:           1.6Gi       294Mi       1.3Gi       4.0Mi       222Mi       1.3Gi
Swap:             0B          0B          0B
```

Look at the `Swap` row. On this lab server no swap is configured, so every
value is `0B`. On a host that has swap you will see a total like `2.0Gi`. What
matters most is the `used` value: as long as it stays at `0B`, swap is healthy.

> **DBA Context - Swap on a database server:** For a database, active swap
> usage is close to an emergency. RAM is measured in nanoseconds. Disk is
> measured in milliseconds, thousands of times slower. When PostgreSQL's shared
> buffers or a big sort get pushed into swap, queries slow to a crawl. The
> whole database feels frozen. If you see the `Swap used` value climbing on a
> database host, treat it as a red flag. Something is using more memory than the
> server has. Find it fast. It is often a runaway query, a too-large `work_mem`,
> or another process on the box.

You can also see swap devices directly:

```bash
swapon --show
```

On a host with swap you get a table like the one below. On this lab server no
swap is configured, so `swapon --show` prints nothing at all and just returns
you to the prompt. That is expected here.

```
Expected output (yours will differ):
NAME      TYPE      SIZE USED PRIO
/swapfile file        2G   0B   -2
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Use `df -h` to see free space per filesystem and read the `Use%` column
- [ ] Use `df -hT` to see filesystem types
- [ ] Explain why a path like `/var` might live on the `/` filesystem
- [ ] Use `du -sh /path` to measure one directory
- [ ] Use `du -sh /var/* | sort -h` to rank the biggest directories
- [ ] Find the biggest single files under a directory with `find` and `sort`
- [ ] Use `df -i` to check inode usage and explain why a disk can be "full" with free bytes
- [ ] Use `free -h` and `swapon --show` to check swap
- [ ] Explain why active swap usage on a database server is an emergency
