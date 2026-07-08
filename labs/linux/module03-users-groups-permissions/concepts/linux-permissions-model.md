# Concepts: The Linux Permissions Model

This is a reference for Module 03. Read it next to the BUILD guides.
It explains how users, groups, ownership, and permissions fit together.
It also shows why each one matters to you as a DBA.
Come back here whenever "permission denied" leaves you stuck.

---

## 1. The big picture

Every time you touch a file, Linux asks two questions in order:

1. **Who are you?** (your user, and the groups you belong to)
2. **What are you allowed to do?** (the permission bits on the file, matched
   against your identity via the file's owner and group)

Ownership decides WHICH set of permission bits applies to you.
Permissions decide WHAT that set lets you do.
You need both halves to understand who can access a file.

```
   You (user + groups)
          |
          v
   Is this file's OWNER you?  --- yes ---> use the "owner" permission bits
          | no
          v
   Are you in the file's GROUP? --- yes --> use the "group" permission bits
          | no
          v
   Otherwise ------------------------------> use the "other" permission bits
```

Linux stops at the first match. If you are the owner, only the owner bits apply
to you. That is true even if the group bits are more generous.

---

## 2. Users

A user is an account. Inside Linux, every user is really a number called the
UID. The username is just a friendly label for that number.
Users come in three types:

| Type | UID range | Logs in? | Example | DBA relevance |
|------|-----------|----------|---------|---------------|
| root | 0 | yes (but discouraged) | `root` | Unlimited power; used only via `sudo` |
| System / service | 1-999 | no (`/sbin/nologin`) | `postgres` (26), `sshd` (74) | The DB runs as an unprivileged service account |
| Regular / human | 1000+ | yes | `ec2-user` (1000) | Your daily login; you elevate with `sudo` |

Key files:

- `/etc/passwd` - the list of users (username, UID, GID, home, shell). It holds
  no passwords, despite the name.
- `/etc/shadow` - the scrambled (hashed) passwords. Only root can read it.

Key commands: `whoami`, `id`, `useradd`, `passwd`, `userdel`.

> **Why a DBA cares:** PostgreSQL runs as the `postgres` system account. When
> you copy data files between servers, ownership travels as a UID number, not a
> name. So if the same name has a different UID on each server, the copied
> files can throw "permission denied."

---

## 3. Groups

A group is a named set of users. Groups let you give access to many people at
once. Every user has exactly one **primary group** plus any number of
**secondary groups**.

- Primary group: listed in `/etc/passwd`. It becomes the group owner of any
  file you create.
- Secondary groups: extra memberships in `/etc/group` that give you shared
  access.

Key files:

- `/etc/group` - the group database (group name, GID, member list).

Key commands: `groups`, `groupadd`, `usermod -aG`, `gpasswd -d`, `groupdel`.

| Group | Purpose | DBA relevance |
|-------|---------|---------------|
| `wheel` | Members may use `sudo` (CentOS) | Adding a user here grants admin rights |
| `postgres` | Primary group of the postgres user | Add teammates here to share DB logs |
| custom (e.g. `dbateam`) | Model a team | One group governs access to backups/scripts |

> **The `-aG` warning:** `usermod -aG group user` adds a group to the list.
> But if you drop the `-a` (`usermod -G group user`), it replaces every
> secondary group instead. That can quietly remove `wheel` and lock a user out
> of `sudo`. Always keep `-a` and `G` together as `-aG`.

---

## 4. Ownership

Every file and directory has an owner (a user) and a group. Ownership decides
which set of permissions applies to each person.

Key commands:

| Command | What it changes | Example |
|---------|-----------------|---------|
| `chown user file` | Owner only | `chown bob file.txt` |
| `chown user:group file` | Owner and group | `chown postgres:postgres data/` |
| `chgrp group file` | Group only | `chgrp dbateam backups/` |
| `chown -R user:group dir` | Whole tree, recursively | `chown -R postgres:postgres /var/lib/pgsql/16/data` |

> **The recursive danger:** `chown -R` on the wrong path can re-own the whole
> filesystem and break the server. A stray `/` or the wrong current directory
> is all it takes. There is no undo. Always double-check the path before you
> press Enter.

> **Why a DBA cares:** The most common reason PostgreSQL will not start is a
> data directory that is not owned by `postgres:postgres`. This usually happens
> after a restore, migration, or file copy that you ran as root. The fix is
> `chown -R postgres:postgres /var/lib/pgsql/16/data`.

---

## 5. Permissions: the two notations

Each file has three permission bits: read, write, and execute.
It has one set of these bits for each class: owner, group, and other.
That is nine bits in total. `ls -l` shows them as a string like `-rwxr-x---`.

### What r, w, x mean

| Bit | On a file | On a directory |
|-----|-----------|----------------|
| `r` (read) | View contents (`cat`, `less`) | List contents (`ls`) |
| `w` (write) | Modify contents | Create/delete/rename files inside |
| `x` (execute) | Run as a program | Enter the directory (`cd`) |

### Octal (numeric) notation

Add the values per class:

| | r | w | x |
|-|---|---|---|
| value | 4 | 2 | 1 |

| Octal | Bits | Common use |
|-------|------|-----------|
| 700 | `rwx------` | Database data directory; private dirs |
| 750 | `rwxr-x---` | Data dir when a read-only group is allowed |
| 644 | `rw-r--r--` | Regular files, docs |
| 640 | `rw-r-----` | Config readable by a group only |
| 600 | `rw-------` | SSH keys, `.pgpass`, certificates |
| 755 | `rwxr-xr-x` | Scripts, program directories |
| 770 | `rwxrwx---` | Shared team directory |

Use octal when you want to set all the bits at once, starting fresh.

### Symbolic notation

Format: `chmod WHO OP WHAT file`.

- WHO: `u` (owner), `g` (group), `o` (other), `a` (all)
- OP: `+` (add), `-` (remove), `=` (set exactly)
- WHAT: `r`, `w`, `x`

| Example | Meaning |
|---------|---------|
| `chmod u+x file` | Add execute for the owner |
| `chmod g-w file` | Remove write from the group |
| `chmod o= file` | Remove all permissions from other |
| `chmod u=rw,g=r,o= file` | Set each class exactly (= octal 640) |

Use symbolic when you want to change one bit and leave the rest alone.
It is safer when you edit files that are already in use.

---

## 6. umask: default permissions

New files start at `666`, and new directories start at `777`.
The `umask` takes bits away from that starting point.

| umask | New file | New dir | Effect |
|-------|----------|---------|--------|
| 022 (default) | 644 | 755 | Group/other can read |
| 077 | 600 | 700 | Owner only |
| 002 | 664 | 775 | Group can write (shared teams) |

> **Why a DBA cares:** A backup script with a loose umask can leave database
> dumps readable by everyone. Set `umask 077` at the top of your backup scripts.
> Then every file they create is owner-only by default.

---

## 7. Special bits

You set the special bits with a fourth digit, added in front of the usual three.

| Bit | Leading digit | Effect | Shows as | Example |
|-----|---------------|--------|----------|---------|
| setuid | 4 | Executable runs as its OWNER | `s` in owner-x slot | `/usr/bin/passwd` runs as root |
| setgid | 2 | New files in a dir inherit the dir's GROUP | `s` in group-x slot | Shared team directory |
| sticky | 1 | Only a file's owner may delete it | `t` in other-x slot | `/tmp` |

> **Most useful for a DBA:** put setgid on a shared backups or scripts directory
> (for example `chmod 2775` plus `chgrp dbateam`). Then every file a teammate
> creates is automatically owned by the team group, so everyone can read it.

---

## 8. sudo, su, and root

You almost never log in as root directly. Instead, you use one of these:

| Command | Use | Notes |
|---------|-----|-------|
| `sudo command` | Run ONE command as root | Logged to `/var/log/secure`; asks for YOUR password |
| `sudo -u user command` | Run one command as another user | e.g. as `postgres` |
| `sudo su -` | Open a full root shell | `-` loads root's login environment; `exit` to leave |
| `sudo su - postgres` | Become the postgres user | The `-` is required so `psql`/`pg_ctl` are found |

You get `sudo` access by being a member of the `wheel` group. That is set by
the line `%wheel ALL=(ALL) ALL` in `/etc/sudoers`. Always edit that file with
`visudo`.

> **Why not log in as root:** `sudo` records who ran what, so you have a clear
> audit trail. It also limits the damage, since you elevate one command at a
> time, and it avoids a shared root password. Logging in as root directly hides
> who did what.

---

## 9. The DBA permission cheat sheet

| Situation | Command |
|-----------|---------|
| Become the postgres user | `sudo su - postgres` |
| Fix data-dir ownership | `sudo chown -R postgres:postgres /var/lib/pgsql/16/data` |
| Fix data-dir permission | `sudo chmod 700 /var/lib/pgsql/16/data` |
| Lock down a key/config file | `chmod 600 file` |
| Share a directory with a team | `chgrp dbateam dir && chmod 2770 dir` |
| Add a teammate to the DBA group | `sudo usermod -aG dbateam alice` |
| Make script files private by default | `umask 077` at the top of the script |

### The golden PostgreSQL startup checklist

When PostgreSQL will not start, check in this order:

1. Is the data directory owned by `postgres:postgres`? (`ls -ld`)
2. Is it `700` (or `750`)? (`ls -ld`)
3. Is the postgres process actually running as the `postgres` user?

These ownership and permission checks fix most real startup problems.
They solve more of them than digging through logs ever will.
