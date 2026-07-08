# Build 02: Navigating the Filesystem

You will learn how the Linux filesystem is organized and how to move around
it. These are commands you will use hundreds of times a day as a DBA.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first (see Build 01).

---

## 1. The Linux filesystem tree

On Windows, you have drives like `C:\` and `D:\`. Linux is different. Everything
starts from a single root directory called `/` (forward slash). Every file,
directory, and device on the entire system lives under `/`.

Think of it like an upside-down tree:

```
/                    <-- root (the very top)
├── home/            <-- user home directories
│   └── ec2-user/    <-- your files
├── etc/             <-- configuration files
├── var/             <-- variable data (logs, databases)
├── opt/             <-- optional software
├── tmp/             <-- temporary files
├── usr/             <-- system programs
└── proc/            <-- live system information
```

> **Concept - Everything is a File:** In Linux, everything is represented as
> a file. Regular files, directories, hard drives, USB devices, network
> connections - they all appear as files somewhere in the filesystem tree.
> This is a fundamental design principle of Linux that you will see over and
> over.

---

## 2. pwd - Where am I?

When you first log in, you are in your home directory. Confirm this:

```bash
pwd
```

`pwd` stands for "print working directory". It tells you exactly where you
are in the filesystem tree.

```
Expected output (yours will differ):
/home/ec2-user
```

You are in the `/home/ec2-user` directory. This is your home directory - it
is where your personal files go and where you land when you log in.

---

## 3. ls - What is here?

To see what files and directories exist in your current location:

```bash
ls
```

`ls` stands for "list". It shows the names of files and directories in the
current directory.

```
Expected output (yours will differ):
```

Your home directory is probably empty right now. That is normal for a fresh
server.

### ls with the -l flag (long format)

```bash
ls -l
```

The `-l` flag means "long format". It shows detailed information about each
file: permissions, owner, size, and date. Even if the directory is empty, this
is the flag you will use most often.

Let's look at a directory that has files in it:

```bash
ls -l /etc
```

```
Expected output (yours will differ):
total 1284
drwxr-xr-x.  3 root root      78 Mar 15 10:00 alternatives
-rw-r--r--.  1 root root      16 Mar 15 10:00 adjtime
drwxr-xr-x.  2 root root    4096 Mar 15 10:00 bash_completion.d
-rw-r--r--.  1 root root    2853 Mar 15 10:00 bashrc
...
```

Each column means something (you will learn the full breakdown in Build 06):

- `drwxr-xr-x` - permissions and file type (`d` means directory, `-` means regular file)
- `root root` - the owner and group
- `78` - the file size in bytes
- `Mar 15 10:00` - when the file was last modified
- `alternatives` - the name

### ls with the -a flag (show hidden files)

```bash
ls -a
```

The `-a` flag means "all". It shows hidden files. In Linux, any file or
directory whose name starts with a `.` (dot) is hidden. They are not secret -
they are just hidden from the normal `ls` listing to keep things clean.

```
Expected output (yours will differ):
.  ..  .bash_history  .bash_logout  .bash_profile  .bashrc  .ssh
```

- `.` - the current directory (a shortcut that means "here")
- `..` - the parent directory (a shortcut that means "one level up")
- `.bash_history` - a record of commands you have typed
- `.bash_profile` - runs when you log in (sets up your environment)
- `.bashrc` - runs when you open a new shell
- `.ssh` - contains your SSH configuration

### ls with the -h flag (human-readable sizes)

```bash
ls -lh /var/log
```

The `-h` flag means "human-readable". Instead of showing file sizes in bytes
(like `1048576`), it shows them in KB, MB, or GB (like `1.0M`). You almost
always want this when checking file sizes.

```
Expected output (yours will differ):
total 2.1M
-rw-r--r--. 1 root root  32K Apr 19 10:00 dnf.log
-rw-------. 1 root root 1.5M Apr 19 14:00 messages
-rw-r--r--. 1 root root  12K Apr 19 10:00 secure
...
```

### ls with -la (the combination you will use most)

```bash
ls -la
```

This combines `-l` (long format) and `-a` (show hidden files). This is the
most common way DBAs use `ls`.

```
Expected output (yours will differ):
total 16
drwx------. 3 ec2-user ec2-user  111 Apr 19 10:00 .
drwxr-xr-x. 3 root     root       22 Apr 19 10:00 ..
-rw-------. 1 ec2-user ec2-user  145 Apr 19 14:00 .bash_history
-rw-r--r--. 1 ec2-user ec2-user   18 Mar 15 10:00 .bash_logout
-rw-r--r--. 1 ec2-user ec2-user  141 Mar 15 10:00 .bash_profile
-rw-r--r--. 1 ec2-user ec2-user  492 Mar 15 10:00 .bashrc
drwx------. 2 ec2-user ec2-user   29 Apr 19 10:00 .ssh
```

> **DBA Context - ls -la:** When a database fails to start, one of the first
> things you check is permissions on the data directory. You run `ls -la` on
> the data directory to see if the ownership and permissions are correct. Wrong
> permissions are the number one reason databases fail to start after a change.

---

## 4. cd - Move around

`cd` stands for "change directory". It moves you to a different location in
the filesystem tree.

### Move to the root directory

```bash
cd /
```

The `/` is the very top of the filesystem tree. Everything lives under it.

Confirm where you are:

```bash
pwd
```

```
Expected output (yours will differ):
/
```

List what is here:

```bash
ls
```

```
Expected output (yours will differ):
bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
```

These are the top-level directories of your Linux server. Each has a specific
purpose.

### Move into a subdirectory

```bash
cd etc
```

```bash
pwd
```

```
Expected output (yours will differ):
/etc
```

Notice you did not type `/etc` - you typed just `etc`. When you do not start
with `/`, Linux treats it as a relative path (relative to where you are now).
Since you were in `/`, typing `cd etc` moved you to `/etc`.

### Move up one level

```bash
cd ..
```

The `..` shortcut always means "the parent directory" (one level up).

```bash
pwd
```

```
Expected output (yours will differ):
/
```

You moved from `/etc` back up to `/`.

### Move to your home directory

From anywhere on the server, you can jump straight back home:

```bash
cd ~
```

The `~` symbol is a shortcut for your home directory. You can also just type
`cd` with nothing after it:

```bash
cd
```

Both do the same thing - take you back to `/home/ec2-user`.

```bash
pwd
```

```
Expected output (yours will differ):
/home/ec2-user
```

### Jump to the previous directory

```bash
cd /var/log
```

```bash
cd /etc
```

Now jump back to where you just were:

```bash
cd -
```

The `-` shortcut means "the directory I was just in". This is extremely useful
when you are bouncing between two directories.

```
Expected output (yours will differ):
/var/log
```

### Absolute vs relative paths

There are two ways to specify a location:

- **Absolute path** - starts with `/` and spells out the full path from root. Example: `/var/log/messages`
- **Relative path** - does NOT start with `/` and is relative to where you are now. Example: `log/messages` (only works if you are already in `/var`)

When in doubt, use absolute paths. They work no matter where you are.

```bash
cd /var/log
```

This is an absolute path. It works from anywhere on the server.

```bash
cd ~
```

Go home first.

```bash
cd ../../var/log
```

This is a relative path. `../..` means "up two levels" (from `/home/ec2-user`
up to `/home`, then up to `/`), then down into `var/log`. It works, but it is
harder to read than the absolute path.

---

## 5. Key directories for DBAs

Go back home first:

```bash
cd ~
```

Now let's visit the directories you will use most as a DBA. For each one, use
`cd` to go there and `ls` to look around.

### /var - Variable data

```bash
ls -l /var
```

```
Expected output (yours will differ):
total 8
drwxr-xr-x.  2 root root    6 Mar 15 10:00 adm
drwxr-xr-x.  5 root root   44 Mar 15 10:00 cache
drwxr-xr-x.  2 root root    6 Mar 15 10:00 db
...
drwxr-xr-x.  8 root root 4096 Apr 19 10:00 log
drwxr-xr-x.  2 root root    6 Mar 15 10:00 tmp
```

> **DBA Context - /var:** This is where "variable" data lives - data that
> changes while the server runs. Database data directories are often under
> `/var/lib` (for example, `/var/lib/pgsql` for PostgreSQL). Database logs go
> under `/var/log`. When a disk fills up, `/var` is usually the first place to
> check because logs and data grow over time.

### /opt - Optional software

```bash
ls -l /opt
```

> **DBA Context - /opt:** This is where custom-installed software goes. Many
> organizations install PostgreSQL under `/opt/pgsql` to keep it separate from
> the operating system packages. This makes upgrades easier because you can
> install a new version alongside the old one.

### /etc - Configuration files

```bash
ls -l /etc
```

This directory has a LOT of files. Scroll through and notice files ending in
`.conf` - those are configuration files.

> **DBA Context - /etc:** Every important service on a Linux server keeps its
> configuration in `/etc`. PostgreSQL's main config files (`postgresql.conf`,
> `pg_hba.conf`) live under `/etc` when installed from packages, or in the data
> directory when installed from source. When something is misconfigured, `/etc`
> is where you look.

### /tmp - Temporary files

```bash
ls -l /tmp
```

> **DBA Context - /tmp:** Programs use this for temporary files. Some database
> operations (like large sorts) create temp files here. If `/tmp` fills up,
> database queries can fail. The system automatically cleans old files from
> `/tmp`, but during heavy workloads it can still fill up.

### /home - User home directories

```bash
ls -l /home
```

```
Expected output (yours will differ):
total 0
drwx------. 3 ec2-user ec2-user 111 Apr 19 10:00 ec2-user
```

Each user on the server gets a directory under `/home`. Your directory is
`/home/ec2-user`.

### /root - Root user's home directory

```bash
ls -la /root
```

You will probably get "Permission denied". That is expected - only the root
user can see inside `/root`. This is the home directory for the root
(administrator) user. It is NOT the same as `/` (the root of the filesystem).

### /usr - System programs

```bash
ls -l /usr
```

> **DBA Context - /usr:** System programs and libraries live here. Commands
> like `ls`, `grep`, and `cat` are actually programs stored in `/usr/bin`. When
> you install PostgreSQL from packages, the binaries go in `/usr/bin` and
> libraries go in `/usr/lib64`.

### /proc - Live system information

```bash
ls /proc
```

This directory is special. It does not contain real files on disk. Instead,
the Linux kernel creates virtual files here that show live system information.

```bash
cat /proc/cpuinfo
```

This shows information about the CPU. We will use `/proc` more in the
performance monitoring module.

---

## 6. The tree command

The `tree` command shows a visual representation of directory structure. It
is not installed by default, so install it first:

```bash
sudo dnf install -y tree
```

`sudo` runs a command as the root user (you will learn more about this in
Module 02). `dnf` is the package manager on CentOS Stream 9. `install -y`
installs a package and automatically answers "yes" to any prompts.

```
Expected output (yours will differ):
Last metadata expiration check: 0:30:00 ago on Sat 19 Apr 2026 10:00:00 UTC.
Dependencies resolved.
...
Installed:
  tree-1.8.0-10.el9.x86_64
Complete!
```

Now use it to see a directory structure:

```bash
tree /etc/ssh
```

```
Expected output (yours will differ):
/etc/ssh
├── moduli
├── ssh_config
├── ssh_config.d
│   └── 50-redhat.conf
├── sshd_config
├── sshd_config.d
│   └── 50-redhat.conf
├── ssh_host_ecdsa_key
├── ssh_host_ecdsa_key.pub
├── ssh_host_ed25519_key
├── ssh_host_ed25519_key.pub
├── ssh_host_rsa_key
└── ssh_host_rsa_key.pub

2 directories, 10 files
```

The `tree` command is great for understanding how directories are organized.
You can limit how deep it goes:

```bash
tree -L 1 /
```

The `-L 1` flag means "only show 1 level deep". This gives you a clean
overview of the top-level directories.

```
Expected output (yours will differ):
/
├── bin -> usr/bin
├── boot
├── dev
├── etc
├── home
├── lib -> usr/lib
├── lib64 -> usr/lib64
├── media
├── mnt
├── opt
├── proc
├── root
├── run
├── sbin -> usr/sbin
├── srv
├── sys
├── tmp
├── usr
└── var

19 directories, 0 files
```

Notice some directories have `->` arrows. These are symbolic links (shortcuts)
that point to other directories. For example, `/bin -> usr/bin` means `/bin` is
actually a shortcut to `/usr/bin`. You will learn about symlinks later.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Use `pwd` to see your current directory
- [ ] Use `ls -la` to see all files with details
- [ ] Use `ls -lh` to see file sizes in human-readable format
- [ ] Use `cd /path` to move to an absolute path
- [ ] Use `cd ..` to move up one level
- [ ] Use `cd ~` or `cd` to go home
- [ ] Use `cd -` to jump to your previous directory
- [ ] Explain the difference between absolute and relative paths
- [ ] Name at least 4 key directories and what they contain (/var, /etc, /opt, /tmp)
- [ ] Use the `tree` command to view directory structure
