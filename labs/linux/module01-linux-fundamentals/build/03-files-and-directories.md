# Build 03: Files and Directories

You will learn how to create, copy, move, rename, and delete files and
directories. Then you will build a real DBA-style directory structure.

**Time estimate:** 60 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. mkdir - Create directories

Go to your home directory first:

```bash
cd ~
```

Create a new directory called `practice`:

```bash
mkdir practice
```

`mkdir` stands for "make directory". It creates a new, empty directory.

Verify it was created:

```bash
ls -l
```

```
Expected output (yours will differ):
total 0
drwxr-xr-x. 2 ec2-user ec2-user 6 Apr 19 14:00 practice
```

Now try to create a nested directory structure:

```bash
mkdir practice/level1/level2
```

```
Expected output (yours will differ):
mkdir: cannot create directory 'practice/level1/level2': No such file or directory
```

This fails because `level1` does not exist yet, so `mkdir` cannot create
`level2` inside it.

### The -p flag (create parent directories)

```bash
mkdir -p practice/level1/level2
```

The `-p` flag means "create parent directories as needed". If `level1` does
not exist, it creates it first, then creates `level2` inside it. No error if
the directory already exists.

Verify the structure:

```bash
tree practice
```

```
Expected output (yours will differ):
practice
└── level1
    └── level2

2 directories, 0 files
```

You can create multiple directories at once:

```bash
mkdir -p practice/{alpha,bravo,charlie}
```

This creates three directories inside `practice` in one command. The curly
braces `{}` expand into separate names.

```bash
tree practice
```

```
Expected output (yours will differ):
practice
├── alpha
├── bravo
├── charlie
└── level1
    └── level2

5 directories, 0 files
```

> **DBA Context - Directory Structure:** Database installations need specific
> directories for data, logs, backups, and configuration. Using `mkdir -p` to
> create the entire structure in one command is faster and safer than creating
> each directory one at a time.

---

## 2. touch - Create empty files

The `touch` command creates an empty file. If the file already exists, it
updates the file's timestamp without changing its contents.

```bash
touch practice/notes.txt
```

Verify:

```bash
ls -l practice/notes.txt
```

```
Expected output (yours will differ):
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 practice/notes.txt
```

Notice the file size is `0` - the file exists but is empty.

Create multiple files at once:

```bash
touch practice/alpha/file1.txt practice/alpha/file2.txt practice/alpha/file3.txt
```

```bash
ls -l practice/alpha/
```

```
Expected output (yours will differ):
total 0
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 file1.txt
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 file2.txt
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 file3.txt
```

> **Concept - touch for Timestamps:** DBAs sometimes use `touch` to update a
> file's timestamp. For example, `touch /var/lib/pgsql/last-backup-check` can
> serve as a simple way to record when you last checked backups. A monitoring
> script can then check how old that timestamp is.

---

## 3. cp - Copy files and directories

### Copy a file

```bash
cp practice/notes.txt practice/notes-backup.txt
```

`cp` stands for "copy". The first argument is the source (what to copy), and
the second is the destination (where to copy it).

```bash
ls -l practice/notes*.txt
```

```
Expected output (yours will differ):
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 practice/notes-backup.txt
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 practice/notes.txt
```

### Copy a file into a directory

```bash
cp practice/notes.txt practice/alpha/
```

When the destination is a directory (ends with `/`), the file is copied into
that directory with the same name.

```bash
ls -l practice/alpha/
```

```
Expected output (yours will differ):
total 0
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 file1.txt
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 file2.txt
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 file3.txt
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:06 notes.txt
```

### Copy a directory (the -r flag)

Try copying a directory:

```bash
cp practice/alpha practice/alpha-copy
```

```
Expected output (yours will differ):
cp: -r not specified; omitting directory 'practice/alpha'
```

Directories cannot be copied without the `-r` flag.

```bash
cp -r practice/alpha practice/alpha-copy
```

The `-r` flag means "recursive" - copy the directory and everything inside it.

```bash
tree practice/alpha-copy
```

```
Expected output (yours will differ):
practice/alpha-copy
├── file1.txt
├── file2.txt
├── file3.txt
└── notes.txt

0 directories, 4 files
```

---

## 4. mv - Move and rename

The `mv` command does two things: move files to a different location, and
rename files. The syntax is the same either way.

### Rename a file

```bash
mv practice/notes.txt practice/readme.txt
```

This renames `notes.txt` to `readme.txt`. The file does not move - it stays
in the same directory.

```bash
ls -l practice/readme.txt
```

```
Expected output (yours will differ):
-rw-rw-r--. 1 ec2-user ec2-user 0 Apr 19 14:05 practice/readme.txt
```

The original `notes.txt` is gone. `mv` does not make a copy - it moves (or
renames) the original.

### Move a file to a different directory

```bash
mv practice/readme.txt practice/bravo/
```

```bash
ls practice/bravo/
```

```
Expected output (yours will differ):
readme.txt
```

The file moved from `practice/` into `practice/bravo/`.

### Rename a directory

```bash
mv practice/charlie practice/delta
```

```bash
ls practice/
```

```
Expected output (yours will differ):
alpha  alpha-copy  bravo  delta  level1  notes-backup.txt
```

`charlie` is now `delta`. Renaming directories works the same as renaming
files.

---

## 5. rm - Remove files

**This is the most dangerous command you will learn.** Deleted files in Linux
are gone forever. There is no recycle bin. There is no undo.

### Remove a single file

```bash
rm practice/notes-backup.txt
```

`rm` stands for "remove". The file is deleted immediately.

```bash
ls practice/notes-backup.txt
```

```
Expected output (yours will differ):
ls: cannot access 'practice/notes-backup.txt': No such file or directory
```

### Remove a directory (the -r flag)

```bash
rm practice/alpha-copy
```

```
Expected output (yours will differ):
rm: cannot remove 'practice/alpha-copy': Is a directory
```

Just like `cp`, you need the `-r` flag for directories:

```bash
rm -r practice/alpha-copy
```

The `-r` flag means "recursive" - delete the directory and everything inside
it.

### The -f flag (force)

```bash
rm -f practice/nonexistent-file.txt
```

The `-f` flag means "force". It suppresses errors when files do not exist and
skips confirmation prompts. By itself, `-f` is useful for scripts.

### DANGER - rm -rf

```bash
rm -rf practice/delta
```

`rm -rf` means "recursively delete everything, no questions asked". This
command is extremely dangerous if you point it at the wrong place.

**Never, ever run these commands:**

- `rm -rf /` - deletes the entire server
- `rm -rf *` - deletes everything in the current directory
- `rm -rf ~` - deletes your entire home directory

Always double-check your path before pressing Enter. Always use `ls` first to
verify what you are about to delete.

> **DBA Context - rm Safety:** As a DBA, you will regularly delete old backup
> files and log files to free disk space. Always list the files first with
> `ls` before using `rm`. A production horror story: a DBA meant to type
> `rm -rf /var/lib/pgsql/old-backup/` but typed `rm -rf /var/lib/pgsql/`
> instead - deleting the live database. Always double-check the path.

---

## 6. rmdir - Remove empty directories

```bash
mkdir practice/empty-dir
```

```bash
rmdir practice/empty-dir
```

`rmdir` only removes empty directories. If the directory has anything in it,
the command fails:

```bash
rmdir practice/alpha
```

```
Expected output (yours will differ):
rmdir: failed to remove 'practice/alpha': Directory not empty
```

This makes `rmdir` safer than `rm -r` - it cannot accidentally delete files.

---

## 7. Practice - Build a DBA-style directory structure

Now put it all together. Create a directory structure that mimics a real
PostgreSQL installation.

Clean up the practice directory first:

```bash
rm -r practice
```

Create the full structure:

```bash
mkdir -p /home/ec2-user/practice/{data,logs,backups,scripts}
```

Create some sample files:

```bash
touch /home/ec2-user/practice/data/database.dat
```

```bash
touch /home/ec2-user/practice/logs/server.log
```

```bash
touch /home/ec2-user/practice/backups/backup-2026-04-19.tar.gz
```

```bash
touch /home/ec2-user/practice/scripts/daily-backup.sh
```

Verify the entire structure:

```bash
tree /home/ec2-user/practice
```

```
Expected output (yours will differ):
/home/ec2-user/practice
├── backups
│   └── backup-2026-04-19.tar.gz
├── data
│   └── database.dat
├── logs
│   └── server.log
└── scripts
    └── daily-backup.sh

4 directories, 4 files
```

> **DBA Context - Directory Layout:** Real PostgreSQL installations follow
> this exact pattern. The data directory holds the actual database files. Logs
> go in a separate directory so they do not fill up the data disk. Backups go
> on a separate disk entirely. Scripts hold your automation. Keeping these
> separated is critical - if logs fill up the data disk, the database crashes.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Create a single directory with `mkdir`
- [ ] Create nested directories with `mkdir -p`
- [ ] Create empty files with `touch`
- [ ] Copy files with `cp` and directories with `cp -r`
- [ ] Move and rename files and directories with `mv`
- [ ] Delete files with `rm` and directories with `rm -r`
- [ ] Explain why `rm -rf` is dangerous
- [ ] Use `rmdir` to safely remove empty directories
- [ ] Build a multi-level directory structure from scratch
- [ ] Your `practice` directory has the correct structure (data, logs, backups, scripts)
