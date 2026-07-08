# Build 04: Ownership

In this guide you will learn that every file has an owner (a user) and a group.
You will change the owner with `chown` and the group with `chgrp`. You will
also apply changes to a whole directory tree at once with `-R`.

You will finish by rebuilding the exact ownership PostgreSQL expects on its data
directory. This is the most common "permission denied" fix a DBA makes.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first as `ec2-user`.

---

## 1. Every file has an owner and a group

You saw this in Module 01. It is worth repeating, because ownership is half of
the permission story. Permissions are the other half, covered in Build 05.

Look at a file's ownership:

```bash
ls -l /etc/hosts
```

`ls -l` lists files in long format, showing owner and group.

```
Expected output (yours will differ):
-rw-r--r--. 1 root root 158 Apr 19 10:00 /etc/hosts
```

In this line:

- The first `root` is the **owner** (the user who owns the file)
- The second `root` is the **group** (the group that owns the file)

There are three sets of permissions: the owner's (`rw-`), the group's (`r--`),
and everyone else's (`r--`). Which set applies depends on WHO you are. Linux
checks in order. Are you the owner? If not, are you in the group? If not, you
get the "other" permissions. So ownership decides which permission set applies
to you.

> **Concept - Ownership + Permissions Together:** Permissions mean nothing
> without ownership. A file with `rwx` for the owner only helps you if you ARE
> the owner. This is why fixing a "permission denied" problem takes two checks.
> First, who owns the file? Second, what are the permission bits? Get ownership
> wrong and no permission setting will save you.

---

## 2. Setting up a practice file

Create a file to experiment with. As `ec2-user`:

```bash
touch ~/ownership-demo.txt
```

`touch` creates an empty file if it does not exist.

Check its ownership:

```bash
ls -l ~/ownership-demo.txt
```

```
Expected output (yours will differ):
-rw-r--r--. 1 ec2-user ec2-user 0 Apr 19 15:00 /home/ec2-user/ownership-demo.txt
```

The file is owned by `ec2-user`, and its group is `ec2-user` too. When you
create a file, you own it, and it gets your primary group.

---

## 3. Changing the owner with chown

`chown` (short for "change owner") sets who owns a file. Giving a file to
another user needs root, so we use `sudo`.

First create a user to give the file to:

```bash
sudo useradd -m -s /bin/bash bob
```

Now transfer ownership of the demo file to `bob`:

```bash
sudo chown bob ~/ownership-demo.txt
```

`chown bob FILE` sets the owner to `bob`. The group stays the same.

Check the result:

```bash
ls -l ~/ownership-demo.txt
```

```
Expected output (yours will differ):
-rw-r--r--. 1 bob ec2-user 0 Apr 19 15:00 /home/ec2-user/ownership-demo.txt
```

The owner is now `bob`, but the group is still `ec2-user`.

### Changing owner AND group at once

`chown` can set the owner and the group in one command. Use the `owner:group`
form:

```bash
sudo chown bob:bob ~/ownership-demo.txt
```

`bob:bob` sets both the owner and the group to `bob` at once. The colon
separates the owner from the group.

```bash
ls -l ~/ownership-demo.txt
```

```
Expected output (yours will differ):
-rw-r--r--. 1 bob bob 0 Apr 19 15:00 /home/ec2-user/ownership-demo.txt
```

Both the owner and group are now `bob`. You will use this `owner:group` form
most often as a DBA.

---

## 4. Changing only the group with chgrp

If you only need to change the group and leave the owner alone, use `chgrp`
(short for "change group").

Create a group first:

```bash
sudo groupadd webteam
```

Change just the group of the file:

```bash
sudo chgrp webteam ~/ownership-demo.txt
```

`chgrp webteam FILE` sets the group to `webteam` and leaves the owner alone.

```bash
ls -l ~/ownership-demo.txt
```

```
Expected output (yours will differ):
-rw-r--r--. 1 bob webteam 0 Apr 19 15:00 /home/ec2-user/ownership-demo.txt
```

The owner is still `bob`, and the group is now `webteam`. You could do the same
thing with `chown :webteam FILE`. A colon at the start means "change group
only".

---

## 5. Recursive changes with -R

Real ownership problems are rarely about one file. They are about a whole
directory tree. The `-R` flag (short for "recursive") applies the change to a
directory and everything inside it.

Build a small tree to practice on. Switch to root so you can create it
anywhere:

```bash
sudo su -
```

Your prompt changes to `#`. Now, as root, create a nested directory with files:

```bash
mkdir -p /srv/app/config /srv/app/data
```

`mkdir -p` makes parent directories as needed. So this creates `/srv/app`,
`/srv/app/config`, and `/srv/app/data` in one go.

```bash
touch /srv/app/config/settings.conf /srv/app/data/records.db
```

Check the current ownership of the tree:

```bash
ls -lR /srv/app
```

`ls -lR` lists recursively. It shows every subdirectory and its files.
Everything is owned by `root`, because root created it.

```
Expected output (yours will differ):
/srv/app:
total 0
drwxr-xr-x. 2 root root 27 Apr 19 15:10 config
drwxr-xr-x. 2 root root 24 Apr 19 15:10 data

/srv/app/config:
total 0
-rw-r--r--. 1 root root 0 Apr 19 15:10 settings.conf
...
```

Now hand the entire tree to `bob:webteam` in one command:

```bash
chown -R bob:webteam /srv/app
```

`chown -R` goes into every subdirectory. It changes the owner and group of
every file and directory it finds.

Verify the whole tree changed:

```bash
ls -lR /srv/app
```

```
Expected output (yours will differ):
/srv/app:
total 0
drwxr-xr-x. 2 bob webteam 27 Apr 19 15:10 config
drwxr-xr-x. 2 bob webteam 24 Apr 19 15:10 data

/srv/app/config:
total 0
-rw-r--r--. 1 bob webteam 0 Apr 19 15:10 settings.conf
...
```

Every file and directory now belongs to `bob:webteam`. One command fixed the
entire tree.

> **Concept - The Power and Danger of -R:** `-R` is essential for fixing a data
> directory, but it is also dangerous. Say you type `chown -R postgres:postgres
> /` with a stray slash, or you run it from the wrong directory. That would
> change ownership of the ENTIRE filesystem and break the server. Always
> double-check the target path before you press Enter on a recursive command.
> There is no undo.

Stay as root for the next section.

---

## 6. The postgres:postgres data directory example

This is the payoff. PostgreSQL keeps all its files in one data directory:
tables, indexes, WAL, and configuration. On CentOS with PostgreSQL 16 that is
usually `/var/lib/pgsql/16/data`. PostgreSQL will refuse to start unless the
`postgres` user and group own that directory.

Let's copy the classic failure, then fix it. Still as root, create a fake data
directory owned by the wrong user:

```bash
mkdir -p /var/lib/pgsql/demo/data
```

```bash
touch /var/lib/pgsql/demo/data/PG_VERSION
```

Right now `root` owns this. That is exactly the mistake that happens when
someone unpacks a backup or copies files as root:

```bash
ls -ld /var/lib/pgsql/demo/data
```

```
Expected output (yours will differ):
drwxr-xr-x. 2 root root 24 Apr 19 15:20 /var/lib/pgsql/demo/data
```

If this were a real PostgreSQL data directory, the database would fail to
start. You would see an error like `could not open file "PG_VERSION":
Permission denied`. That happens because the `postgres` user cannot read
root's files.

Fix it the way every DBA does. Set ownership to `postgres:postgres`
recursively:

```bash
chown -R postgres:postgres /var/lib/pgsql/demo
```

This makes the `postgres` user and group own the whole directory tree.

Note: this command only works if the `postgres` user exists, which happens once
PostgreSQL is installed. On a bare lab server you will see
`chown: invalid user: 'postgres:postgres'`. That is expected. To practice the
exact `chown -R` mechanics before PostgreSQL is installed, target any user that
does exist, for example the `bob` account from earlier
(`chown -R bob:bob /var/lib/pgsql/demo`). The `-R` behavior is identical. Now the
database process (which runs as `postgres`) can read and write its own files.

Verify:

```bash
ls -ld /var/lib/pgsql/demo/data
```

```
Expected output (yours will differ):
drwxr-xr-x. 2 postgres postgres 24 Apr 19 15:20 /var/lib/pgsql/demo/data
```

The directory is now owned by `postgres:postgres`. In Build 05 you will lock
its permissions down to `700`. In Build 06 you will meet the `postgres` user
properly.

Clean up the practice directories and users. Still as root:

```bash
rm -rf /srv/app /var/lib/pgsql/demo /home/ec2-user/ownership-demo.txt
```

Now exit the root shell:

```bash
exit
```

Back as `ec2-user`, remove the practice user and group:

```bash
sudo userdel -r bob
```

```bash
sudo groupdel webteam
```

> **DBA Context - The #1 Startup Failure:** A PostgreSQL server refuses to
> start after a restore, migration, or file copy. What does an experienced DBA
> check first? They run `ls -ld` on the data directory. If it is not owned by
> `postgres:postgres`, the fix is `chown -R postgres:postgres` on that
> directory. This one pattern solves a huge share of real production problems.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Read `ls -l` output and identify the owner and the group of a file
- [ ] Explain why ownership decides which permission set applies to you
- [ ] Change a file's owner with `chown USER`
- [ ] Change owner and group together with `chown USER:GROUP`
- [ ] Change only the group with `chgrp GROUP`
- [ ] Apply an ownership change to a whole tree with `chown -R`
- [ ] Explain why a recursive `chown` on the wrong path is dangerous
- [ ] Fix a data directory with `chown -R postgres:postgres`
- [ ] Explain why PostgreSQL fails to start when its data directory is owned by root
- [ ] State the first thing to check when PostgreSQL will not start after a restore
