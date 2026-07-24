# Build 05: Permissions Deep Dive

This guide takes you past the basics. You will recap octal (numeric)
permissions. You will learn symbolic `chmod` for precise changes like `u+x` and
`g-w`. You will understand `umask`, which sets the default permissions of new
files. And you will meet the special permission bits: the sticky bit, setuid,
and setgid.

This depth matters. It separates a DBA who guesses at permissions from one who
fixes them with confidence.

**Time estimate:** 50 minutes

All steps run on your lab server. Connect with SSH first as `ec2-user`.

---

## 1. Octal recap

You met numeric (octal) permissions in Module 01. Here is a quick recap.
Everything else in this guide builds on it.

Each permission has a value:

| Permission | Value |
|------------|-------|
| Read (`r`) | 4 |
| Write (`w`) | 2 |
| Execute (`x`) | 1 |
| None (`-`) | 0 |

You add the values for each of the three classes (owner, group, other):

- `rwx` = 4 + 2 + 1 = **7**
- `rw-` = 4 + 2 + 0 = **6**
- `r-x` = 4 + 0 + 1 = **5**
- `r--` = 4 + 0 + 0 = **4**
- `---` = 0 + 0 + 0 = **0**

So `chmod 640` means owner `rw-` (6), group `r--` (4), other `---` (0).

Create a practice file to work with:

```bash
touch ~/perms-demo.txt
```

Set it to `640`:

```bash
chmod 640 ~/perms-demo.txt
```

```bash
ls -l ~/perms-demo.txt
```

```
Expected output (yours will differ):
-rw-r-----. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/perms-demo.txt
```

Octal is best when you want to set ALL permissions at once from a known start.

---

## 2. Symbolic chmod: surgical changes

Octal always sets all three classes at once. Symbolic notation is different. It
changes only the bits you name and leaves the rest alone. That makes it perfect
for small tweaks.

The format is `chmod WHO OP WHAT FILE`:

- **WHO:** `u` = user/owner, `g` = group, `o` = other, `a` = all
- **OP:** `+` = add, `-` = remove, `=` = set exactly
- **WHAT:** `r` = read, `w` = write, `x` = execute

### Add execute for the owner (u+x)

Our demo file is currently `640` (`rw-r-----`). Add execute for the owner:

```bash
chmod u+x ~/perms-demo.txt
```

`u+x` means "for the user/owner, add execute". Nothing else changes.

```bash
ls -l ~/perms-demo.txt
```

```
Expected output (yours will differ):
-rwxr-----. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/perms-demo.txt
```

The owner went from `rw-` to `rwx`. Group and other are untouched.

### Remove write from the group (g-w)

```bash
chmod g-w ~/perms-demo.txt
```

`g-w` means "for the group, remove write". The group had no write bit here to
start with, so nothing visibly changes. Still, the command is safe and precise.

Now try it on a file where it matters. Reset to `660` first:

```bash
chmod 660 ~/perms-demo.txt
```

```bash
chmod g-w ~/perms-demo.txt
```

```bash
ls -l ~/perms-demo.txt
```

```
Expected output (yours will differ):
-rw-r-----. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/perms-demo.txt
```

The group went from `rw-` to `r--`. Owner and other were left alone. This
precision is why symbolic notation is safer when you edit live files.

### Combine multiple changes

You can separate several changes with commas:

```bash
chmod u=rw,g=r,o= ~/perms-demo.txt
```

- `u=rw` - set owner to exactly read+write
- `g=r` - set group to exactly read
- `o=` - set other to exactly nothing

```bash
ls -l ~/perms-demo.txt
```

```
Expected output (yours will differ):
-rw-r-----. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/perms-demo.txt
```

This is `640` expressed symbolically.

> **Concept - When to Use Which:** Use octal (`chmod 600`) when you know the
> exact final state you want. Locking down a key file is a good example. Use
> symbolic (`chmod g-w`) when you want to flip one bit and leave the others
> alone. For example, you might remove write from a group on a shared log
> directory without touching the owner or the world bits.

---

## 3. umask: the default permission filter

When you create a new file, why does it come out as `644` and not `777`? The
answer is `umask`. A `umask` is a filter. It REMOVES permission bits from the
default whenever new files and directories are created.

See your current umask:

```bash
umask
```

`umask` with no arguments prints the current mask as an octal number.

```
Expected output (yours will differ):
0022
```

Here is how it works:

- The default starting point is `666` for files and `777` for directories
- The umask is SUBTRACTED (bitwise) from that default
- With a umask of `022`: files become `666 - 022 = 644`, directories become
  `777 - 022 = 755`

Prove it. Create a fresh file and directory:

```bash
touch ~/umask-file.txt
```

```bash
mkdir ~/umask-dir
```

Check their permissions:

```bash
ls -l ~/umask-file.txt
```

```
Expected output (yours will differ):
-rw-r--r--. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/umask-file.txt
```

```bash
ls -ld ~/umask-dir
```

```
Expected output (yours will differ):
drwxr-xr-x. 2 ec2-user ec2-user 6 Apr 19 15:00 /home/ec2-user/umask-dir
```

The file is `644` and the directory is `755`, just as the umask predicts.

### Changing umask for tighter defaults

Set a stricter umask so new files are private to you:

```bash
umask 077
```

A umask of `077` removes ALL permissions from group and other. So new files
become `600` and new directories become `700`.

Create another file to see it:

```bash
touch ~/umask-private.txt
```

```bash
ls -l ~/umask-private.txt
```

```
Expected output (yours will differ):
-rw-------. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/umask-private.txt
```

The new file is `600`, owner only. Now reset your umask back to the default.
This keeps things predictable later in this session:

```bash
umask 022
```

> **DBA Context - umask and Backups:** The umask matters when scripts create
> files. A backup script with a loose umask can leave database dump files
> readable by everyone. That is a real security problem. So DBAs often set
> `umask 077` at the top of backup scripts. Then every file the script creates
> is owner-only by default, with no need for a separate `chmod` on each one.

---

## 4. The sticky bit

The three special bits sit in front of the normal three-digit permission. They
act as a fourth, leading digit. The first one to know is the sticky bit.

The sticky bit applies to directories. When it is set, you can only delete or
rename files you own inside that directory. This holds true even if the
directory is writable by everyone. The classic example is `/tmp`. Everyone can
create files there, but nobody can delete anyone else's.

Look at `/tmp`:

```bash
ls -ld /tmp
```

```
Expected output (yours will differ):
drwxrwxrwt. 11 root root 4096 Apr 19 15:00 /tmp
```

Notice the final character is `t` instead of `x`: `drwxrwxrwt`. That trailing
`t` is the sticky bit. Without it, any user could delete anyone else's temp
files.

Now set the sticky bit on a directory yourself. First create a shared dir:

```bash
mkdir ~/shared-demo
```

```bash
chmod 1777 ~/shared-demo
```

The leading `1` is the sticky bit. The `777` makes it writable by everyone. The
`1` in front adds the sticky protection.

```bash
ls -ld ~/shared-demo
```

```
Expected output (yours will differ):
drwxrwxrwt. 2 ec2-user ec2-user 6 Apr 19 15:00 /home/ec2-user/shared-demo
```

The trailing `t` confirms the sticky bit is set.

---

## 5. setuid and setgid (introduction)

The other two special bits change WHICH user or group a program runs as. They
can also change which group new files inherit. You will not set these often as
a DBA. But you do need to recognize them.

### setuid: run as the file owner

When the setuid bit is set on a program, it runs with the privileges of the
file's OWNER, not the person running it. The classic example is `passwd`. A
regular user runs it, but it needs to write to root-owned `/etc/shadow`. So it
runs as root through setuid.

Find it:

```bash
ls -l /usr/bin/passwd
```

```
Expected output (yours will differ):
-rwsr-xr-x. 1 root root 32648 Aug 10  2021 /usr/bin/passwd
```

Notice the `s` where the owner's `x` normally sits: `-rwsr-xr-x`. That `s` is
the setuid bit. It is why an ordinary user can change their password even though
`/etc/shadow` is root-only.

### setgid: inherit the directory's group

When the setgid bit is set on a DIRECTORY, new files created inside it take on
the directory's GROUP instead of the creator's primary group. This is the
secret behind a properly shared team directory.

Set it on a demo directory:

```bash
sudo groupadd sharedteam
```

```bash
chmod 2775 ~/shared-demo
```

The leading `2` is the setgid bit. The `775` gives owner and group full access,
and gives others read+execute.

```bash
sudo chgrp sharedteam ~/shared-demo
```

```bash
ls -ld ~/shared-demo
```

```
Expected output (yours will differ):
drwxrwsr-x. 2 ec2-user sharedteam 6 Apr 19 15:00 /home/ec2-user/shared-demo
```

Notice the `s` in the GROUP position: `drwxrwsr-x`. That is the setgid bit. Any
file created inside now gets the `sharedteam` group automatically. So teammates
can access each other's files without running `chgrp` by hand every time.

Here is a summary of the special bits:

| Bit | Leading digit | On files | On directories | Shows as |
|-----|---------------|----------|----------------|----------|
| setuid | 4 | Run as file owner | (no effect) | `s` in owner's x slot |
| setgid | 2 | Run as file group | New files inherit dir group | `s` in group's x slot |
| sticky | 1 | (no effect) | Only owner can delete their files | `t` in other's x slot |

Clean up the practice resources:

```bash
rm -rf ~/shared-demo ~/perms-demo.txt ~/umask-file.txt ~/umask-private.txt ~/umask-dir
```

```bash
sudo groupdel sharedteam
```

> **DBA Context - setgid on Shared Directories:** For a DBA team, the most
> useful special bit is setgid on a shared backups or scripts directory. Pair it
> with a `dbateam` group (Build 02). Now every file a teammate drops in there is
> automatically group-owned by `dbateam` and readable by the whole team. No more
> "I created the backup but nobody else can read it" tickets.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Convert between symbolic (`rw-r-----`) and octal (`640`) permissions
- [ ] Use symbolic `chmod u+x` to add one bit without disturbing others
- [ ] Use symbolic `chmod g-w` to remove one bit surgically
- [ ] Explain what `umask` does and predict the result of `umask 022` and `umask 077`
- [ ] Explain why a loose umask in a backup script is a security risk
- [ ] Identify the sticky bit (`t`) on `/tmp` and explain what it protects
- [ ] Set the sticky bit with `chmod 1777`
- [ ] Recognize the setuid bit (`s`) on `/usr/bin/passwd` and explain why it is there
- [ ] Recognize the setgid bit and explain how it helps a shared team directory
- [ ] State which special bit is most useful for a DBA team and why
