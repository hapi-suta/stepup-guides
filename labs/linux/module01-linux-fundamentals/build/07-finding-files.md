# Build 07: Finding Files

You will learn how to locate files anywhere on the server using `find`,
`which`, `whereis`, and `locate`. As a DBA, you will use these commands to
find database files, old backups, large log files, and configuration files.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. find - The most powerful search command

The `find` command searches for files and directories based on name, type,
size, age, and more. The basic syntax is:

```
find WHERE -CRITERIA "VALUE"
```

### Find by name

Search for files named `hosts` starting from `/etc`:

```bash
find /etc -name "hosts" 2>/dev/null
```

- `/etc` - start searching here
- `-name "hosts"` - look for items with this exact name
- `2>/dev/null` - hides "Permission denied" messages for directories you cannot read

```
Expected output (yours will differ):
/etc/hosts
```

Search for all files ending in `.conf` in `/etc`:

```bash
find /etc -name "*.conf" 2>/dev/null
```

The `*` is a wildcard that matches any characters. So `*.conf` means "any
name ending in `.conf`".

We add `2>/dev/null` to hide "Permission denied" errors for directories you
cannot access. The errors are not important - they just mean some directories
are restricted.

```
Expected output (yours will differ):
/etc/resolv.conf
/etc/dnf/dnf.conf
/etc/chrony.conf
/etc/logrotate.conf
/etc/ssh/sshd_config
/etc/security/limits.conf
...
```

### The -iname flag (case insensitive name)

```bash
find /etc -iname "*.CONF" 2>/dev/null | head -5
```

The `-iname` flag is like `-name` but ignores case. It matches `.conf`,
`.CONF`, `.Conf`, etc.

```
Expected output (yours will differ):
/etc/resolv.conf
/etc/dnf/dnf.conf
/etc/chrony.conf
/etc/logrotate.conf
/etc/ssh/sshd_config
```

---

## 2. Find by type

The `-type` flag filters by what kind of thing you are looking for.

### Find only files

```bash
find /etc/ssh -type f
```

The `-type f` means "regular files only" (not directories).

```
Expected output (yours will differ):
/etc/ssh/moduli
/etc/ssh/ssh_config
/etc/ssh/sshd_config
/etc/ssh/ssh_host_ecdsa_key
/etc/ssh/ssh_host_ecdsa_key.pub
/etc/ssh/ssh_host_ed25519_key
/etc/ssh/ssh_host_ed25519_key.pub
/etc/ssh/ssh_host_rsa_key
/etc/ssh/ssh_host_rsa_key.pub
...
```

### Find only directories

```bash
find /etc/ssh -type d
```

The `-type d` means "directories only".

```
Expected output (yours will differ):
/etc/ssh
/etc/ssh/ssh_config.d
/etc/ssh/sshd_config.d
```

### Combine name and type

Find only `.conf` files (not directories that might end in `.conf`):

```bash
find /etc -name "*.conf" -type f 2>/dev/null | head -10
```

You can combine multiple criteria. Both conditions must be true.

---

## 3. Find by size

The `-size` flag searches for files based on their size.

### Find files larger than 10 megabytes

```bash
sudo find / -size +10M -type f 2>/dev/null | head -10
```

- `-size +10M` - larger than 10 megabytes. The `+` means "greater than". The `M` means megabytes
- We search from `/` to look everywhere on the server

```
Expected output (yours will differ):
/usr/lib/locale/locale-archive
/usr/lib64/libLLVM-17.so
/usr/share/GeoIP/GeoLite2-City.mmdb
...
```

### Find files larger than 100 megabytes

```bash
sudo find / -size +100M -type f 2>/dev/null
```

```
Expected output (yours will differ):
/usr/lib64/libLLVM-17.so
```

### Size units

| Unit | Meaning |
|------|---------|
| `c` | Bytes |
| `k` | Kilobytes |
| `M` | Megabytes |
| `G` | Gigabytes |

Examples:

- `-size +500k` - larger than 500 KB
- `-size +1G` - larger than 1 GB
- `-size -100c` - smaller than 100 bytes (the `-` means "less than")

> **DBA Context - Finding Large Files:** When a disk fills up, you need to
> quickly find what is consuming space.
> `find /var -size +100M -type f` finds large files under `/var` (where
> databases and logs live). Old backup files and large log files are the usual
> culprits.

---

## 4. Find by time

The `-mtime` flag searches for files based on when they were last modified.

### Find files modified in the last 7 days

```bash
find /var/log -mtime -7 -type f 2>/dev/null
```

- `-mtime -7` - modified less than 7 days ago. The `-` means "less than"

```
Expected output (yours will differ):
/var/log/messages
/var/log/secure
/var/log/dnf.log
/var/log/cron
/var/log/wtmp
...
```

### Find files NOT modified in the last 30 days

```bash
find /var/log -mtime +30 -type f 2>/dev/null
```

- `-mtime +30` - modified more than 30 days ago. The `+` means "more than"

### Find files modified in the last 60 minutes

```bash
find /var/log -mmin -60 -type f 2>/dev/null
```

The `-mmin` flag works like `-mtime` but uses minutes instead of days.

```
Expected output (yours will differ):
/var/log/messages
/var/log/secure
```

> **DBA Context - Finding Old Backups:** DBAs use `find` with time flags to
> locate old backup files that can be safely deleted.
> `find /opt/pgsql/backup -mtime +14 -name "*.tar.gz"` finds backup files
> older than 14 days. Many backup scripts include a cleanup step that
> automatically deletes backups older than a retention period.

---

## 5. which - Find where a command lives

`which` shows the full path to a command's executable file.

```bash
which ls
```

```
Expected output (yours will differ):
/usr/bin/ls
```

When you type `ls`, your system actually runs `/usr/bin/ls`. The `which`
command tells you where it is.

```bash
which grep
```

```
Expected output (yours will differ):
/usr/bin/grep
```

```bash
which bash
```

```
Expected output (yours will differ):
/usr/bin/bash
```

If a command is not found:

```bash
which psql
```

```
Expected output (yours will differ):
/usr/bin/which: no psql in (/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/ec2-user/.local/bin:/home/ec2-user/bin)
```

This tells you `psql` (the PostgreSQL client) is not installed yet. It also
shows you the PATH - the list of directories where Linux looks for commands.

> **Concept - PATH:** When you type a command, Linux does not search the
> entire filesystem for it. It only looks in the directories listed in a
> special variable called PATH. You can see your PATH with `echo $PATH`.
> The directories are separated by colons. If a command is "not found", it
> either is not installed or its directory is not in your PATH.

---

## 6. whereis - Find command, source, and manual pages

`whereis` is similar to `which` but also shows where the command's source
code and manual pages are located.

```bash
whereis grep
```

```
Expected output (yours will differ):
grep: /usr/bin/grep /usr/share/man/man1/grep.1.gz
```

This shows:

- `/usr/bin/grep` - the executable
- `/usr/share/man/man1/grep.1.gz` - the manual page

```bash
whereis ls
```

```
Expected output (yours will differ):
ls: /usr/bin/ls /usr/share/man/man1/ls.1.gz
```

---

## 7. locate - Fast file search (if available)

The `locate` command searches a pre-built database of filenames. It is much
faster than `find` because it does not scan the actual filesystem - it uses
an index.

First, install it:

```bash
sudo dnf install -y mlocate
```

```
Expected output (yours will differ):
...
Installed:
  mlocate-0.26-33.el9.x86_64
Complete!
```

Build the initial database:

```bash
sudo updatedb
```

This scans the entire filesystem and builds the index. It takes a few seconds.

Now search:

```bash
locate hosts
```

```
Expected output (yours will differ):
/etc/hosts
/etc/hosts.allow
/etc/hosts.deny
/etc/avahi/hosts
...
```

`locate` is fast but has a limitation: it uses the database that was built
when `updatedb` last ran. If you created a file after the last `updatedb`,
`locate` will not find it until you run `updatedb` again.

```bash
touch ~/practice/data/newfile.txt
```

```bash
locate newfile.txt
```

Nothing found. Now update the database:

```bash
sudo updatedb
```

```bash
locate newfile.txt
```

```
Expected output (yours will differ):
/home/ec2-user/practice/data/newfile.txt
```

> **DBA Context - find vs locate:** Use `find` when you need real-time
> results (the file might have just been created). Use `locate` for quick
> searches when you know the file has existed for a while. In practice, DBAs
> use `find` more often because they need accurate results, especially when
> troubleshooting.

---

## 8. Practice exercises

### Find all .conf files in /etc

```bash
find /etc -name "*.conf" -type f 2>/dev/null | wc -l
```

```
Expected output (yours will differ):
47
```

This counts all configuration files in `/etc`.

### Find files larger than 10MB anywhere on the server

```bash
sudo find / -size +10M -type f 2>/dev/null | head -10
```

### Find files modified today in /var/log

```bash
find /var/log -mtime 0 -type f 2>/dev/null
```

The `-mtime 0` means "modified within the last 24 hours" (0 days ago).

### Find all directories named "ssh" or "ssl"

```bash
find /etc -type d -name "ssh" -o -type d -name "ssl" 2>/dev/null
```

The `-o` means "or". This finds directories named either "ssh" or "ssl".

```
Expected output (yours will differ):
/etc/ssh
/etc/ssl
```

### Combine find with grep

Find all config files that contain the word "password":

```bash
find /etc -name "*.conf" -type f 2>/dev/null | xargs grep -l "password" 2>/dev/null
```

The `xargs` command takes the list of filenames from `find` and passes them
to `grep`. The `-l` flag on `grep` means "show only filenames, not the
matching lines".

```
Expected output (yours will differ):
/etc/login.defs
```

> **DBA Context - find + grep:** This combination is extremely powerful.
> "Find all PostgreSQL config files that reference a specific setting" becomes:
> `find /etc -name "postgresql.conf" | xargs grep "shared_buffers"`. When
> managing many databases, this saves enormous amounts of time.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Use `find /path -name "pattern"` to search by filename
- [ ] Use `find -iname` for case-insensitive searches
- [ ] Use `find -type f` for files and `find -type d` for directories
- [ ] Use `find -size +100M` to find large files
- [ ] Use `find -mtime -7` to find recently modified files
- [ ] Use `which` to find where a command is located
- [ ] Use `whereis` to find a command, source, and manual pages
- [ ] Use `locate` for fast filename searches
- [ ] Combine `find` with `grep` to search inside found files
- [ ] Explain the difference between `find` (real-time) and `locate` (indexed)
