# Build 01: Users and Passwords

In this guide you will learn what a Linux user account is. You will see who you
are, read the user list in `/etc/passwd`, and create and delete user accounts.

Every program on a Linux server runs as some user. That includes your database.
So user accounts are a core skill for a DBA.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first as `ec2-user`.

---

## 1. Who are you?

Every command you run on Linux runs as some user. First, let's find out which
user that is.

Run this command:

```bash
whoami
```

This prints the username you are logged in as. On your lab server, that is
`ec2-user`.

```
Expected output (yours will differ):
ec2-user
```

For more detail, run:

```bash
id
```

`id` shows more detail. It prints your user ID number (UID), your main group ID
number (GID), and every group you belong to. You use names like `ec2-user`, but
Linux tracks users by number behind the scenes.

```
Expected output (yours will differ):
uid=1000(ec2-user) gid=1000(ec2-user) groups=1000(ec2-user),4(adm),190(systemd-journal) context=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
```

Reading this:

- `uid=1000(ec2-user)` - your numeric user ID is 1000, name `ec2-user`
- `gid=1000(ec2-user)` - your primary group ID is 1000, name `ec2-user`
- `groups=...` - every group you are a member of (more on groups in Build 02)
- `context=...` - the SELinux security context. CentOS Stream 9 ships with SELinux on, so `id` appends this. You can ignore it for now.

> **Concept - Users Are Numbers:** Linux does not really care about usernames.
> Under the hood, every user is a number (the UID). The username is just a
> friendly label for that number. This matters to a DBA. When you copy database
> files from one server to another, the owner is saved as a UID number. Say the
> `postgres` user is UID 26 on one server but UID 999 on another. The files can
> end up owned by the wrong account.

---

## 2. The user database: /etc/passwd

Every local user account on the server is listed in a plain text file called
`/etc/passwd`. Despite the name, it holds no passwords anymore. Those moved to
a separate file, `/etc/shadow`, years ago for better security.

View your own entry:

```bash
grep ec2-user /etc/passwd
```

`grep` searches a file for text and prints the lines that match. Here it prints
only the line for `ec2-user`.

```
Expected output (yours will differ):
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

Each line has seven fields separated by colons (`:`):

```
ec2-user  :  x  :  1000  :  1000  :  Cloud User  :  /home/ec2-user  :  /bin/bash
   |          |     |        |          |                 |               |
   |          |     |        |          |                 |               └── login shell
   |          |     |        |          |                 └── home directory
   |          |     |        |          └── comment / full name (GECOS field)
   |          |     |        └── primary group ID (GID)
   |          |     └── user ID (UID)
   |          └── password placeholder (x = stored in /etc/shadow)
   └── username
```

Look at the whole file to see the system accounts:

```bash
cat /etc/passwd
```

`cat` prints the entire file. On a fresh server this is short enough to read.

```
Expected output (yours will differ):
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/sbin/nologin
daemon:x:2:2:daemon:/sbin:/sbin/nologin
...
sshd:x:74:74:Privilege-separated SSH:/usr/share/empty.sshd:/usr/sbin/nologin
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

Notice most accounts have `/sbin/nologin` as their shell. That is on purpose.
Service accounts should never be able to log in and type commands. You will see
this again with the `postgres` user in Build 06.

> **DBA Context - UID 0 Is Special:** Look at the `root` line. Its UID is `0`.
> UID 0 means unlimited power. That account can do anything on the system.
> Any account with UID 0 is really root, no matter what it is named. When you
> check a server, always confirm that no surprise account has UID 0.

---

## 3. Types of users

There are three broad categories of user account on a Linux server.

| Type | UID range | Purpose | Example |
|------|-----------|---------|---------|
| root | 0 | The all-powerful administrator | `root` |
| System / service | 1-999 | Runs background services, cannot log in | `postgres`, `sshd`, `chrony` |
| Regular / human | 1000+ | Real people who log in | `ec2-user` |

The `postgres` user is a system account. It lets the database run without root
powers, which is safer. You will meet it properly in Build 06.

Check the system's cutoff for regular users:

```bash
grep -E "^UID_MIN|^UID_MAX" /etc/login.defs
```

`grep -E` turns on a more powerful search mode. The `^` means "match at the
start of the line." So this prints only the two lines that set where regular
user IDs begin and end.

```
Expected output (yours will differ):
UID_MIN                  1000
UID_MAX                 60000
```

This confirms that regular human users start at UID 1000.

---

## 4. Creating a user with useradd

Creating users needs root powers, so we use `sudo`. You will learn `sudo` in
depth in Build 03. For now, just know it runs one command as the administrator.

On your lab server, as `ec2-user`, create a practice user named `dbstudent`:

```bash
sudo useradd dbstudent
```

`useradd` creates a new user account. On CentOS Stream 9, even with no extra
options, it also makes a home folder at `/home/dbstudent`. It also creates a
matching primary group named `dbstudent`.

Confirm the account was created:

```bash
grep dbstudent /etc/passwd
```

```
Expected output (yours will differ):
dbstudent:x:1001:1001::/home/dbstudent:/bin/bash
```

The new user got UID 1001. That is the next free number after `ec2-user`, which
is 1000.

### Useful useradd flags

You can control how the account is made. This example sets a comment, a home
directory, and a shell, all in one command:

```bash
sudo useradd -c "Practice DBA account" -m -s /bin/bash appuser
```

- `-c "Practice DBA account"` - sets the comment/full-name field
- `-m` - make the home directory if it does not already exist
- `-s /bin/bash` - set the login shell to bash

Verify:

```bash
grep appuser /etc/passwd
```

```
Expected output (yours will differ):
appuser:x:1002:1002:Practice DBA account:/home/appuser:/bin/bash
```

### Creating a service account (no login)

Service accounts should not be able to log in. Create one that uses `nologin`
as its shell:

```bash
sudo useradd -r -s /sbin/nologin svcdemo
```

- `-r` - create a system account (UID below 1000, no home directory by default)
- `-s /sbin/nologin` - deny interactive login

```bash
grep svcdemo /etc/passwd
```

```
Expected output (yours will differ):
svcdemo:x:996:995::/home/svcdemo:/sbin/nologin
```

This is exactly how the PostgreSQL installer creates the real `postgres`
account.

---

## 5. Setting a password with passwd

A brand new account made with `useradd` has no password yet. It cannot log in
with one until you set it. Set a password for `dbstudent`:

```bash
sudo passwd dbstudent
```

`passwd` sets or changes a user's password. You ran it with `sudo` and named a
user, so you set that user's password. You will be asked to type the new
password twice. Nothing shows on screen as you type. That is normal.

```
Expected output (yours will differ):
Changing password for user dbstudent.
New password:
Retype new password:
passwd: all authentication tokens updated successfully.
```

To change your own password, run `passwd` with no username:

```bash
passwd
```

This changes the password for whoever you currently are (`ec2-user`).

> **DBA Context - Passwords vs Keys:** On real database servers, people usually
> log in with SSH keys, not passwords. Login for service accounts like
> `postgres` is turned off completely. So why learn `passwd`? It still matters
> for emergency "break-glass" accounts. It also helps you see how `/etc/shadow`
> stores the scrambled password. And a rule to keep: never put a real password
> in a script or a config file.

---

## 6. Deleting a user with userdel

When you no longer need a practice account, remove it. Delete `appuser` and its
home folder:

```bash
sudo userdel -r appuser
```

`userdel` removes a user account. The `-r` flag also removes the user's home
folder and mail files. Without `-r`, the account goes away but the home folder
stays behind. That can leave stray files owned by a UID with no name.

Confirm it is gone:

```bash
grep appuser /etc/passwd
```

This time `grep` finds nothing, so it prints nothing. An empty result means the
user is gone.

Clean up the other practice accounts:

```bash
sudo userdel -r dbstudent
```

```bash
sudo userdel svcdemo
```

We skip `-r` for `svcdemo`. It was made with `-r` as a system account, so it
has no real home folder to remove.

> **Concept - Orphaned Files:** Say you delete a user but leave files they
> owned. Now `ls -l` shows a bare number instead of a name for the owner, like
> `drwxr-xr-x 2 1002 1002`. The UID no longer maps to any name. This trips
> people up when cleaning up old database installs. Always track down files
> owned by the deleted service account.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Run `whoami` and `id` and explain the difference
- [ ] Read a line from `/etc/passwd` and name all seven fields
- [ ] Explain why UID 0 is special and what `/sbin/nologin` does
- [ ] Explain the difference between root, system, and regular user accounts
- [ ] Create a regular user with `useradd -m -s /bin/bash`
- [ ] Create a service account with `useradd -r -s /sbin/nologin`
- [ ] Set a password with `passwd`
- [ ] Delete a user with `userdel -r` and explain what `-r` does
- [ ] Explain why ownership stored as a UID number can cause problems when moving database files
