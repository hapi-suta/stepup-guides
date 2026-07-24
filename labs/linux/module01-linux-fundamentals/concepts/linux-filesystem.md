# Linux Filesystem - Concepts Reference

This is a comprehensive reference for the Linux filesystem. Use it alongside
the BUILD guides and come back to it whenever you need to look something up.

---

## 1. The Filesystem Hierarchy

Everything in Linux starts from `/` (root). Each top-level directory has a
specific purpose defined by the Filesystem Hierarchy Standard (FHS).

| Directory | Purpose | DBA Relevance |
|-----------|---------|---------------|
| `/` | Root of the entire filesystem | Everything lives under here |
| `/bin` | Essential user commands (symlink to `/usr/bin` on CentOS 9) | Basic commands: ls, cp, cat, grep |
| `/sbin` | Essential system commands (symlink to `/usr/sbin` on CentOS 9) | System admin: fdisk, mkfs, ip |
| `/usr` | User programs, libraries, documentation | PostgreSQL binaries when installed from packages |
| `/usr/bin` | Most user commands | psql, pg_dump, pg_basebackup |
| `/usr/lib64` | Shared libraries (64-bit) | PostgreSQL client libraries |
| `/usr/share` | Architecture-independent data | Manual pages, documentation |
| `/etc` | System and service configuration files | postgresql.conf, pg_hba.conf |
| `/var` | Variable data - changes at runtime | Database data, logs, package cache |
| `/var/lib` | Application state data | PostgreSQL data directory (default: /var/lib/pgsql) |
| `/var/log` | Log files | System logs, database logs |
| `/var/tmp` | Temporary files that survive reboot | Large temp operations |
| `/opt` | Optional/custom software | Custom PostgreSQL installations |
| `/tmp` | Temporary files (cleaned on reboot) | Temp tables, sort operations |
| `/home` | User home directories | /home/ec2-user, /home/postgres |
| `/root` | Root user's home directory | Only root can access |
| `/proc` | Virtual filesystem - live kernel info | /proc/cpuinfo, /proc/meminfo |
| `/sys` | Virtual filesystem - hardware/driver info | Device information |
| `/dev` | Device files | /dev/sda (disk), /dev/null (black hole) |
| `/boot` | Boot loader files, kernel | Do not modify unless you know what you are doing |
| `/media` | Mount point for removable media | USB drives, CD-ROMs |
| `/mnt` | Temporary mount point | Manual mounts for maintenance |
| `/srv` | Service data | Web server files, FTP data |
| `/run` | Runtime data since last boot | PID files, socket files |

### CentOS 9 Specifics

On CentOS Stream 9, several directories are symlinks:

- `/bin` -> `/usr/bin`
- `/sbin` -> `/usr/sbin`
- `/lib` -> `/usr/lib`
- `/lib64` -> `/usr/lib64`

This means `/bin/ls` and `/usr/bin/ls` are the same file. This simplification
is called "usr merge" and it keeps the filesystem cleaner.

---

## 2. Everything is a File

One of the fundamental design principles of Linux is that everything is
represented as a file. This includes:

- **Regular files** - documents, scripts, data
- **Directories** - special files that contain lists of other files
- **Device files** - represent hardware devices
- **Sockets** - network and inter-process communication endpoints
- **Pipes** - data channels between processes
- **Symbolic links** - shortcuts to other files

This means you can use the same tools (`cat`, `ls`, `grep`) to interact with
hardware devices, network information, and process data - not just regular
files.

Examples:

- `cat /proc/cpuinfo` - reads CPU information as if it were a file
- `cat /dev/null` - reads from the "null device" (returns nothing)
- `echo "test" > /dev/null` - writes to the null device (data disappears)

---

## 3. Inodes - How Filesystems Work

Every file on a Linux filesystem is represented internally by an **inode**
(index node). Think of it as the file's identity card.

### What an inode stores

- File type (regular, directory, symlink, etc.)
- Permissions (rwx)
- Owner and group
- Size
- Timestamps (created, modified, accessed)
- Pointers to the actual data blocks on disk
- Number of hard links

### What an inode does NOT store

- The filename

This is important: the filename is stored in the directory, not in the inode.
A directory is just a list of (name -> inode number) pairs. This is why:

- You can have multiple names (hard links) pointing to the same inode
- Renaming a file is instant (it just changes the directory entry)
- Moving a file within the same filesystem is instant (same reason)

### Viewing inode information

```bash
ls -i /etc/hosts
```

The `-i` flag shows the inode number.

```bash
stat /etc/hosts
```

The `stat` command shows complete inode information.

### Running out of inodes

Each filesystem has a fixed number of inodes (set at creation time). If you
create millions of tiny files, you can run out of inodes even if you have
free disk space. Check with:

```bash
df -i
```

> **DBA Context - Inodes:** Database data directories can contain thousands of
> files (one per table, one per index, plus WAL files). A PostgreSQL database
> with many small tables can consume a significant number of inodes. The
> `df -i` command is something DBAs check when they get mysterious "No space
> left on device" errors despite having free disk space.

---

## 4. File Types

Linux has seven file types. You can identify them by the first character in
`ls -l` output.

| Character | Type | Example |
|-----------|------|---------|
| `-` | Regular file | `/etc/hosts`, scripts, data files |
| `d` | Directory | `/home/ec2-user`, `/var/log` |
| `l` | Symbolic link | `/bin` -> `/usr/bin` |
| `b` | Block device | `/dev/sda` (hard disk) |
| `c` | Character device | `/dev/tty` (terminal) |
| `s` | Socket | `/var/run/postgresql/.s.PGSQL.5432` |
| `p` | Named pipe (FIFO) | Created by `mkfifo` |

### Regular files

The most common type. Contains data - could be text, binary, compressed, etc.
The `file` command tells you what kind of data is inside:

```bash
file /etc/hosts
```

```
/etc/hosts: ASCII text
```

```bash
file /usr/bin/ls
```

```
/usr/bin/ls: ELF 64-bit LSB pie executable...
```

### Directories

Special files that contain a mapping of names to inode numbers. When you
`ls` a directory, you are reading this mapping.

### Symbolic links (symlinks)

A symlink is a file that contains the path to another file. When you access
a symlink, Linux automatically follows it to the target.

Creating a symlink:

```bash
ln -s /path/to/target /path/to/link
```

The `-s` flag means "symbolic". Without it, `ln` creates a hard link (which
is different - see below).

### Hard links vs symbolic links

| Feature | Hard link | Symbolic link |
|---------|-----------|---------------|
| Points to | Same inode | A file path |
| Cross filesystems? | No | Yes |
| Survives target deletion? | Yes | No (becomes broken) |
| Can link to directories? | No | Yes |

> **DBA Context - Sockets:** PostgreSQL uses a Unix socket file (typically at
> `/var/run/postgresql/.s.PGSQL.5432`) for local connections. When you connect
> with `psql` without specifying a host, it uses this socket. If the socket
> file is missing or has wrong permissions, local connections fail. This is a
> common troubleshooting scenario.

---

## 5. Permissions Deep Dive

### Basic permissions (rwx)

Every file has three sets of permissions:

| Set | Who | Description |
|-----|-----|-------------|
| Owner (u) | The user who owns the file | Usually the creator |
| Group (g) | The group assigned to the file | Can be any group |
| Others (o) | Everyone else | All other users on the system |

Each set has three permission bits:

| Bit | File meaning | Directory meaning | Numeric value |
|-----|-------------|-------------------|---------------|
| `r` (read) | View contents | List contents | 4 |
| `w` (write) | Modify contents | Create/delete files inside | 2 |
| `x` (execute) | Run as a program | Enter with cd | 1 |

### Numeric notation

Add the values for each set:

| Permission | Calculation | Common use |
|------------|-------------|------------|
| `rwx` | 4+2+1 = 7 | Executable, full access |
| `rw-` | 4+2+0 = 6 | Normal files, read+write |
| `r-x` | 4+0+1 = 5 | Read and execute, no modify |
| `r--` | 4+0+0 = 4 | Read only |
| `---` | 0+0+0 = 0 | No access |

Common permission combinations:

| Numeric | Symbolic | Use |
|---------|----------|-----|
| 700 | `rwx------` | Data directories, private directories |
| 755 | `rwxr-xr-x` | Programs, scripts, shared directories |
| 644 | `rw-r--r--` | Normal files, configs (non-sensitive) |
| 600 | `rw-------` | SSH keys, sensitive configs, certificates |
| 400 | `r--------` | Read-only sensitive files |
| 777 | `rwxrwxrwx` | NEVER use - security risk |

### Special permission bits

Beyond the standard rwx, there are three special bits:

#### SUID (Set User ID) - numeric 4000

When set on an executable, it runs as the file owner instead of the user who
executed it.

Example: `/usr/bin/passwd` has SUID set. When a regular user runs `passwd`,
it executes as root so it can modify `/etc/shadow`.

```bash
ls -l /usr/bin/passwd
```

```
-rwsr-xr-x. 1 root root 33544 ... /usr/bin/passwd
```

Notice the `s` in the owner's execute position.

#### SGID (Set Group ID) - numeric 2000

When set on a directory, files created inside inherit the directory's group
instead of the creator's primary group.

This is useful for shared directories where multiple users need group access.

#### Sticky bit - numeric 1000

When set on a directory, only the file owner (or root) can delete files inside
it. Other users can create files but cannot delete each other's files.

```bash
ls -ld /tmp
```

```
drwxrwxrwt. 8 root root 4096 ... /tmp
```

Notice the `t` in the others' execute position. This is the sticky bit. It
prevents users from deleting other users' temp files.

---

## 6. Common Filesystem Types

| Type | Description | Use case |
|------|-------------|----------|
| **xfs** | Default on CentOS/RHEL. High performance, good for large files | Database data, general purpose |
| **ext4** | The most widely used Linux filesystem. Reliable, well-tested | General purpose, boot partitions |
| **tmpfs** | RAM-based filesystem. Very fast, contents lost on reboot | /tmp, /dev/shm, /run |
| **proc** | Virtual filesystem for kernel/process info | /proc |
| **sysfs** | Virtual filesystem for hardware/driver info | /sys |
| **devtmpfs** | Virtual filesystem for device files | /dev |
| **nfs** | Network File System - remote filesystems | Shared storage between servers |

### Checking filesystem type

```bash
df -T
```

The `-T` flag shows the filesystem type column.

```bash
mount | head -5
```

Shows what is mounted and how.

> **DBA Context - XFS for Databases:** XFS is the recommended filesystem for
> PostgreSQL on CentOS/RHEL. It handles large files well (important for WAL
> and data files), supports extent-based allocation (good for sequential I/O),
> and has reliable crash recovery. When setting up a database server, always
> verify the data partition uses XFS.

---

## 7. How Databases Use the Filesystem

Understanding how databases interact with the filesystem helps you
troubleshoot problems faster.

### PostgreSQL directory layout (typical)

```
/var/lib/pgsql/16/data/       Main data directory (PGDATA)
  ├── base/                   Database files (one subdir per database)
  │   ├── 1/                  template1 database
  │   ├── 16384/              Your database
  │   └── ...
  ├── global/                 Cluster-wide tables
  ├── pg_wal/                 Write-ahead log files
  ├── pg_xact/                Transaction commit status
  ├── pg_stat/                Statistics files
  ├── pg_tblspc/              Tablespace symlinks
  ├── postgresql.conf         Main configuration
  ├── pg_hba.conf             Client authentication
  ├── pg_ident.conf           User name mapping
  ├── postmaster.pid          PID file (server running indicator)
  └── postmaster.opts         Command line options used at startup
```

### Key DBA filesystem operations

| Operation | Command | Purpose |
|-----------|---------|---------|
| Check disk space | `df -h` | Prevent disk-full crashes |
| Find large files | `find /var -size +100M -type f` | Identify space consumers |
| Watch logs live | `tail -f /var/log/postgresql/postgresql.log` | Real-time troubleshooting |
| Search logs | `grep "ERROR" /var/log/postgresql/postgresql.log` | Find specific errors |
| Check permissions | `ls -la /var/lib/pgsql/16/data` | Must be 700 |
| Check ownership | `ls -la /var/lib/pgsql/` | Must be postgres:postgres |
| Check filesystem type | `df -T /var/lib/pgsql` | Should be xfs |
| Check inode usage | `df -i /var/lib/pgsql` | For databases with many tables |

---

## 8. Quick Reference - Common Commands

### Navigation

| Command | Description |
|---------|-------------|
| `pwd` | Print current directory |
| `ls -la` | List all files with details |
| `ls -lh` | List with human-readable sizes |
| `cd /path` | Change to absolute path |
| `cd ~` | Go to home directory |
| `cd ..` | Go up one level |
| `cd -` | Go to previous directory |
| `tree -L 2` | Show directory tree (2 levels deep) |

### File operations

| Command | Description |
|---------|-------------|
| `mkdir -p dir/subdir` | Create directories (with parents) |
| `touch file` | Create empty file or update timestamp |
| `cp source dest` | Copy file |
| `cp -r source dest` | Copy directory recursively |
| `mv source dest` | Move or rename |
| `rm file` | Delete file |
| `rm -r dir` | Delete directory recursively |

### Viewing files

| Command | Description |
|---------|-------------|
| `cat file` | Show entire file (small files only) |
| `less file` | Page through file (q to quit) |
| `head -n 20 file` | First 20 lines |
| `tail -n 20 file` | Last 20 lines |
| `tail -f file` | Follow file in real time |
| `wc -l file` | Count lines |

### Searching

| Command | Description |
|---------|-------------|
| `grep "pattern" file` | Search for text in file |
| `grep -i "pattern" file` | Case-insensitive search |
| `grep -r "pattern" dir/` | Recursive search |
| `grep -n "pattern" file` | Show line numbers |
| `grep -c "pattern" file` | Count matches |
| `find /path -name "*.conf"` | Find by filename |
| `find /path -type f -size +100M` | Find large files |
| `find /path -mtime -7` | Find recently modified files |
| `which command` | Find command location |

### Pipes and redirects

| Syntax | Description |
|--------|-------------|
| `cmd > file` | Redirect stdout to file (overwrite) |
| `cmd >> file` | Append stdout to file |
| `cmd 2> file` | Redirect stderr to file |
| `cmd > file 2>&1` | Redirect both stdout and stderr |
| `cmd1 \| cmd2` | Pipe output of cmd1 into cmd2 |

### Permissions

| Command | Description |
|---------|-------------|
| `chmod 700 dir` | Owner only (data directories) |
| `chmod 755 file` | Owner rwx, others rx (scripts) |
| `chmod 644 file` | Owner rw, others r (normal files) |
| `chmod 600 file` | Owner only (sensitive files) |
| `chmod u+x file` | Add execute for owner |
| `ls -la` | View permissions |
| `stat file` | Detailed file information |

### Disk and filesystem

| Command | Description |
|---------|-------------|
| `df -h` | Show disk space usage |
| `df -i` | Show inode usage |
| `df -T` | Show filesystem types |
| `du -sh dir/*` | Show directory sizes |
| `mount` | Show mounted filesystems |
| `findmnt` | Show mount tree |
