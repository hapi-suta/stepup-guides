# Build 06: File Permissions Basics

You will learn how Linux controls who can read, write, and execute files.
Wrong permissions are the number one reason databases fail to start, so this
is critical knowledge for every DBA.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. Decoding ls -l output

Run this command:

```bash
ls -la /etc/hosts
```

```
Expected output (yours will differ):
-rw-r--r--. 1 root root 158 Apr 19 10:00 /etc/hosts
```

Every piece of this output tells you something. Let's decode it left to right:

```
-  rw-  r--  r--  .  1  root  root  158  Apr 19 10:00  /etc/hosts
|  |    |    |    |  |  |     |     |    |              |
|  |    |    |    |  |  |     |     |    |              └── filename
|  |    |    |    |  |  |     |     |    └── last modified date
|  |    |    |    |  |  |     |     └── size in bytes
|  |    |    |    |  |  |     └── group owner
|  |    |    |    |  |  └── user owner
|  |    |    |    |  └── number of hard links
|  |    |    |    └── SELinux context marker
|  |    |    └── permissions for others (everyone else)
|  |    └── permissions for group
|  └── permissions for owner (user)
└── file type (- = regular file, d = directory, l = symlink)
```

### File type character

The very first character tells you what kind of thing this is:

| Character | Meaning |
|-----------|---------|
| `-` | Regular file |
| `d` | Directory |
| `l` | Symbolic link (shortcut) |
| `b` | Block device (disk) |
| `c` | Character device (terminal) |

### The permission characters

The next 9 characters are three groups of three:

- Characters 2-4: what the **owner** can do
- Characters 5-7: what the **group** can do
- Characters 8-10: what **everyone else** can do

Each group has three positions:

| Position | Character | Meaning |
|----------|-----------|---------|
| 1 | `r` or `-` | Read permission (can view the file contents) |
| 2 | `w` or `-` | Write permission (can modify the file) |
| 3 | `x` or `-` | Execute permission (can run the file as a program) |

So `-rw-r--r--` means:

- `-` - this is a regular file
- `rw-` - the owner can read and write (but not execute)
- `r--` - the group can read only
- `r--` - everyone else can read only

Let's look at a directory:

```bash
ls -la /home/
```

```
Expected output (yours will differ):
total 0
drwxr-xr-x.  3 root     root       22 Apr 19 10:00 .
dr-xr-xr-x. 17 root     root      224 Apr 19 10:00 ..
drwx------.  3 ec2-user ec2-user  111 Apr 19 10:00 ec2-user
```

Look at the `ec2-user` directory: `drwx------`

- `d` - this is a directory
- `rwx` - the owner (ec2-user) can read, write, and enter the directory
- `---` - the group has no permissions
- `---` - everyone else has no permissions

> **Concept - Permissions on Directories:** For directories, the permission
> letters mean slightly different things:
> - `r` (read) = list the contents with `ls`
> - `w` (write) = create, delete, or rename files inside
> - `x` (execute) = enter the directory with `cd`
>
> A directory with `r--` lets you list files but not enter it. A directory
> with `--x` lets you enter it but not list contents (you can access files
> only if you already know the name).

---

## 2. Read, Write, Execute explained

### For regular files

| Permission | What it means |
|------------|--------------|
| `r` (read) | You can view the file contents with `cat`, `less`, etc. |
| `w` (write) | You can change the file contents with a text editor, or overwrite it with `>` |
| `x` (execute) | You can run the file as a program or script |

### For directories

| Permission | What it means |
|------------|--------------|
| `r` (read) | You can list the directory contents with `ls` |
| `w` (write) | You can create, delete, or rename files inside the directory |
| `x` (execute) | You can enter the directory with `cd` and access files in it |

---

## 3. chmod with numeric notation

`chmod` changes permissions on a file or directory. The numeric notation uses
three digits, one for each group (owner, group, others).

Each permission has a numeric value:

| Permission | Value |
|------------|-------|
| Read (`r`) | 4 |
| Write (`w`) | 2 |
| Execute (`x`) | 1 |
| None (`-`) | 0 |

You add the values together for each group. For example:

- `rwx` = 4 + 2 + 1 = **7**
- `rw-` = 4 + 2 + 0 = **6**
- `r--` = 4 + 0 + 0 = **4**
- `r-x` = 4 + 0 + 1 = **5**
- `---` = 0 + 0 + 0 = **0**

### Practice with numeric permissions

Create a test file:

```bash
touch ~/practice/scripts/test-perms.sh
```

Check its current permissions:

```bash
ls -l ~/practice/scripts/test-perms.sh
```

```
Expected output (yours will differ):
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/practice/scripts/test-perms.sh
```

### chmod 644 (the standard file permission)

```bash
chmod 644 ~/practice/scripts/test-perms.sh
```

- `6` = owner gets `rw-` (read + write)
- `4` = group gets `r--` (read only)
- `4` = others get `r--` (read only)

```bash
ls -l ~/practice/scripts/test-perms.sh
```

```
Expected output (yours will differ):
-rw-r--r--. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/practice/scripts/test-perms.sh
```

This is the standard permission for most files. Anyone can read it, but only
the owner can change it.

### chmod 755 (for scripts and programs)

```bash
chmod 755 ~/practice/scripts/test-perms.sh
```

- `7` = owner gets `rwx` (read + write + execute)
- `5` = group gets `r-x` (read + execute)
- `5` = others get `r-x` (read + execute)

```bash
ls -l ~/practice/scripts/test-perms.sh
```

```
Expected output (yours will differ):
-rwxr-xr-x. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/practice/scripts/test-perms.sh
```

This is the standard permission for scripts and programs. Everyone can read
and execute it, but only the owner can change it.

### chmod 600 (for sensitive files)

```bash
chmod 600 ~/practice/scripts/test-perms.sh
```

- `6` = owner gets `rw-` (read + write)
- `0` = group gets `---` (nothing)
- `0` = others get `---` (nothing)

```bash
ls -l ~/practice/scripts/test-perms.sh
```

```
Expected output (yours will differ):
-rw-------. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/practice/scripts/test-perms.sh
```

Only the owner can access this file. No one else can read, write, or execute
it. This is the permission for sensitive files like SSH keys, passwords, and
database configuration files.

### chmod 700 (for sensitive directories)

```bash
chmod 700 ~/practice/data
```

- `7` = owner gets `rwx` (full access)
- `0` = group gets `---` (nothing)
- `0` = others get `---` (nothing)

```bash
ls -ld ~/practice/data
```

Note: the `-d` flag with `ls` shows information about the directory itself,
not its contents.

```
Expected output (yours will differ):
drwx------. 2 ec2-user ec2-user 26 Apr 19 14:05 /home/ec2-user/practice/data
```

Only the owner can enter this directory or see what is inside.

---

## 4. chmod with symbolic notation

Symbolic notation uses letters instead of numbers. It is often easier to read
when you want to change just one permission.

The format is: `chmod WHO+WHAT FILE` or `chmod WHO-WHAT FILE`

- **WHO:** `u` = user (owner), `g` = group, `o` = others, `a` = all
- **WHAT:** `r` = read, `w` = write, `x` = execute
- **OPERATION:** `+` = add, `-` = remove, `=` = set exactly

### Add execute permission for the owner

```bash
chmod 644 ~/practice/scripts/test-perms.sh
```

```bash
chmod u+x ~/practice/scripts/test-perms.sh
```

`u+x` means "for the user (owner), add execute permission".

```bash
ls -l ~/practice/scripts/test-perms.sh
```

```
Expected output (yours will differ):
-rwxr--r--. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/practice/scripts/test-perms.sh
```

The owner now has `rwx` (execute was added). Group and others are unchanged.

### Remove write permission from group

```bash
chmod g-w ~/practice/scripts/test-perms.sh
```

`g-w` means "for the group, remove write permission".

### Set exact permissions for others

```bash
chmod o=r ~/practice/scripts/test-perms.sh
```

`o=r` means "for others, set permissions to exactly read only". Any existing
permissions are replaced.

### Multiple changes at once

```bash
chmod u=rwx,g=rx,o=r ~/practice/scripts/test-perms.sh
```

This sets owner to `rwx`, group to `r-x`, and others to `r--` in one command.
This is equivalent to `chmod 754`.

---

## 5. Common DBA permissions

Here are the permissions you will use most as a DBA:

| Permission | Numeric | Symbolic | Use for |
|------------|---------|----------|---------|
| `rwx------` | 700 | `u=rwx,go=` | Database data directories |
| `rw-------` | 600 | `u=rw,go=` | Config files, SSH keys, certificates |
| `rwxr-xr-x` | 755 | `u=rwx,go=rx` | Scripts, program directories |
| `rw-r--r--` | 644 | `u=rw,go=r` | Regular files, documentation |

Let's set up the practice directory with proper DBA permissions:

```bash
chmod 700 ~/practice/data
```

```bash
chmod 755 ~/practice/logs
```

```bash
chmod 755 ~/practice/backups
```

```bash
chmod 755 ~/practice/scripts
```

Verify:

```bash
ls -la ~/practice/
```

```
Expected output (yours will differ):
total 0
drwxr-xr-x. 6 ec2-user ec2-user  72 Apr 19 14:05 .
drwx------. 4 ec2-user ec2-user 128 Apr 19 14:00 ..
drwxr-xr-x. 2 ec2-user ec2-user  52 Apr 19 14:05 backups
drwx------. 2 ec2-user ec2-user  26 Apr 19 14:05 data
drwxr-xr-x. 2 ec2-user ec2-user  92 Apr 19 15:00 logs
drwxr-xr-x. 2 ec2-user ec2-user  28 Apr 19 15:00 scripts
```

Notice `data` has `drwx------` (700) while the others have `drwxr-xr-x` (755).
The data directory is locked down tightest because it contains the actual
database files.

> **DBA Context - Why Permissions Matter:** PostgreSQL refuses to start if the
> data directory has permissions other than 700. The database checks on startup
> and will print: `FATAL: data directory "/var/lib/pgsql/data" has group or
> world access`. This is a security feature - the data directory contains
> everything: tables, indexes, user passwords, and configuration. Wrong
> permissions are the number one thing DBAs check when a database fails to
> start after a change.

---

## 6. Understanding owner and group

Every file has an owner (user) and a group. You can see them in the `ls -l`
output:

```bash
ls -l /etc/hosts
```

```
Expected output (yours will differ):
-rw-r--r--. 1 root root 158 Apr 19 10:00 /etc/hosts
```

The first `root` is the owner. The second `root` is the group. This means:

- The `root` user can read and write this file (owner permissions: `rw-`)
- Anyone in the `root` group can read this file (group permissions: `r--`)
- Everyone else can read this file (others permissions: `r--`)

Your files are owned by `ec2-user`:

```bash
ls -l ~/practice/scripts/test-perms.sh
```

```
Expected output (yours will differ):
-rwxr--r--. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/practice/scripts/test-perms.sh
```

The owner is `ec2-user` and the group is `ec2-user`. You will learn how to
change ownership with `chown` in Module 02 (Users, Groups, and Ownership).

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Read the full `ls -l` output and identify: file type, permissions, owner, group, size, date, name
- [ ] Explain the difference between read, write, and execute for files
- [ ] Explain the difference between read, write, and execute for directories
- [ ] Use `chmod 644` to set standard file permissions
- [ ] Use `chmod 755` to set script/program permissions
- [ ] Use `chmod 600` to set sensitive file permissions
- [ ] Use `chmod 700` to set sensitive directory permissions
- [ ] Use symbolic notation like `chmod u+x` to add specific permissions
- [ ] Explain why 700 is used for database data directories
- [ ] Explain why 600 is used for configuration files
