# Build 02: Groups

In this guide you will learn what a Linux group is. You will see which groups
you belong to, read `/etc/group`, create groups, and add users to them.

Groups let several users share access to the same files. You will use this a
lot as a DBA, whenever a team needs to share logs and backups.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first as `ec2-user`.

---

## 1. What is a group?

A group is a named set of users. Instead of giving access to each user one at a
time, you give it to a group. Then you add users to that group. Every member
gets the group's access automatically.

Every user has one **primary group** and can belong to any number of
**secondary groups**.

- **Primary group:** set in `/etc/passwd`, used as the group owner of files you create
- **Secondary groups:** extra memberships that grant access to other resources

See your groups:

```bash
groups
```

`groups` prints every group your user belongs to. The first one listed is
usually your primary group.

```
Expected output (yours will differ):
ec2-user adm systemd-journal
```

For the numeric detail, use `id` again:

```bash
id
```

```
Expected output (yours will differ):
uid=1000(ec2-user) gid=1000(ec2-user) groups=1000(ec2-user),4(adm),190(systemd-journal) context=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
```

- `gid=1000(ec2-user)` - your primary group
- everything in `groups=` - all your memberships, primary plus secondary
- `context=...` - the SELinux security context; ignore it for now

> **Concept - The wheel Group:** On CentOS, members of the `wheel` group are
> allowed to use `sudo`. Group membership is how the system decides who can
> become root. On many CentOS servers `ec2-user` is a member of `wheel`, so you
> would see it in the list above. On this lab server `ec2-user` instead gets its
> `sudo` rights from a cloud-init drop-in file under `/etc/sudoers.d/`, so
> `wheel` may not appear in your `groups` output. Either way, the `wheel` group
> exists and grants `sudo` to any user you add to it. You will see this again in
> Build 03.

---

## 2. The group database: /etc/group

Users live in `/etc/passwd`. In the same way, groups live in `/etc/group`.
View it:

```bash
cat /etc/group
```

`cat` prints the whole file. On a fresh server it is short.

```
Expected output (yours will differ):
root:x:0:
wheel:x:10:
adm:x:4:ec2-user
ec2-user:x:1000:
```

Each line has four fields separated by colons (`:`):

```
adm  :  x  :  4  :  ec2-user
 |      |     |       |
 |      |     |       └── comma-separated list of member usernames (secondary members)
 |      |     └── group ID (GID)
 |      └── password placeholder (rarely used)
 └── group name
```

On this line, `ec2-user` is a secondary member of the `adm` group (GID 4). The
`wheel` group is GID 10 and, on this lab server, has no members listed after the
last colon (its field is empty). On many CentOS servers you would instead see
`ec2-user` listed there, since `wheel` membership is the usual way to grant
`sudo`.

Look at one specific group:

```bash
grep wheel /etc/group
```

```
Expected output (yours will differ):
wheel:x:10:
```

If your `ec2-user` were a member of `wheel`, its name would appear after the
last colon. On a server set up that way, that membership is what gives it
`sudo` access.

> **DBA Context - The postgres Group:** Once PostgreSQL is installed, a
> `postgres` group appears with GID 26 (you would see `postgres:x:26:` in this
> file). On a fresh server it has no listed members. The `postgres` user's
> primary group is `postgres`. Say you want a monitoring user or a teammate to
> read PostgreSQL log files. You add them to the `postgres` group. That is safer
> than making the logs readable by everyone.

---

## 3. Creating a group with groupadd

Groups are how you set up a team. Imagine a DBA team that all needs to read the
database backups. Create a group for them.

On your lab server, as `ec2-user`, create a group named `dbateam`:

```bash
sudo groupadd dbateam
```

`groupadd` creates a new group. It needs root powers, so we run it with `sudo`.

Confirm it exists:

```bash
grep dbateam /etc/group
```

```
Expected output (yours will differ):
dbateam:x:1001:
```

The group got GID 1001 and has no members yet. You can tell because the field
after the last colon is empty.

---

## 4. Adding a user to a group with usermod -aG

Now add a user to the group. First create a practice user, just like you did in
Build 01:

```bash
sudo useradd -m -s /bin/bash alice
```

Add `alice` to the `dbateam` group:

```bash
sudo usermod -aG dbateam alice
```

`usermod` changes an existing user account. The flags here really matter:

- `-a` - append (add to the current group list, keeping what's there)
- `-G dbateam` - the secondary group(s) to add

> **Concept - Always Use -a with -G:** The `-a` flag means append. Say you run
> `usermod -G dbateam alice` WITHOUT the `-a`. It REPLACES all of alice's
> secondary groups with just `dbateam`. It quietly wipes every other membership.
> This is a famous, painful mistake. It has locked admins out of `sudo` by
> erasing their `wheel` membership. Always use `-aG` together.

Verify the membership:

```bash
groups alice
```

`groups` followed by a username shows that user's groups (not your own).

```
Expected output (yours will differ):
alice : alice dbateam
```

`alice` now belongs to two groups: her primary group `alice` and the secondary
group `dbateam`.

Also confirm it landed in the group file:

```bash
grep dbateam /etc/group
```

```
Expected output (yours will differ):
dbateam:x:1001:alice
```

---

## 5. Why groups matter: shared access

Here is the whole point of groups in action. We will create a shared folder
that only members of `dbateam` can use.

Switch to root to set this up cleanly:

```bash
sudo su -
```

`sudo su -` starts a full root shell. The trailing `-` loads root's full login
setup. Your prompt changes from `$` to `#`. That shows you are now root. (You
will learn more about this in Build 03.)

Now, as root, create a shared folder:

```bash
mkdir /srv/backups
```

Set the group owner of the folder to `dbateam`:

```bash
chgrp dbateam /srv/backups
```

`chgrp` changes the group owner of a file or folder. You will cover this in
depth in Build 04.

Give the group read, write, and execute rights on the folder:

```bash
chmod 770 /srv/backups
```

`770` means the owner and the group get full access (`rwx`). Everyone else gets
nothing. So only root and members of `dbateam` can use this folder.

Check the result:

```bash
ls -ld /srv/backups
```

The `-d` flag shows the folder itself, not what is inside it.

```
Expected output (yours will differ):
drwxrwx---. 2 root dbateam 6 Apr 19 15:00 /srv/backups
```

Now exit the root shell to go back to `ec2-user`:

```bash
exit
```

Your prompt returns to `$`. Because `alice` is in `dbateam`, she can write to
`/srv/backups`. A user who is not in the group gets "permission denied". That
is the power of groups. You manage access for many users by managing one group.

> **DBA Context - Real-World Use:** On real PostgreSQL servers, you often make
> a group like `pgadmin` or `dbateam` and add each DBA to it. Then you set the
> backup and log folders to that group with `chmod 770` or `chmod 750`. New
> team member joins? Add them to one group. Someone leaves? Remove them from one
> group. You never touch individual file permissions.

---

## 6. Removing a user from a group

To remove `alice` from `dbateam`, use `gpasswd`:

```bash
sudo gpasswd -d alice dbateam
```

`gpasswd -d USER GROUP` removes a user from a group. This is safer than trying
to rewrite the whole group list with `usermod`.

```
Expected output (yours will differ):
Removing user alice from group dbateam
```

Confirm:

```bash
groups alice
```

```
Expected output (yours will differ):
alice : alice
```

`alice` is back to just her primary group. Now clean up the practice items:

```bash
sudo userdel -r alice
```

```bash
sudo groupdel dbateam
```

`groupdel` removes a group. Do not delete a group that is still the primary
group of any user. Linux will refuse.

```bash
sudo rm -rf /srv/backups
```

`rm -rf` removes the folder and everything in it. Be very careful with this
command. There is no undo.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain the difference between a primary group and a secondary group
- [ ] Run `groups` and `id` and identify your primary and secondary groups
- [ ] Read a line from `/etc/group` and name all four fields
- [ ] Explain why the `wheel` group grants `sudo` access on CentOS
- [ ] Create a group with `groupadd`
- [ ] Add a user to a group with `usermod -aG`
- [ ] Explain why forgetting the `-a` in `-aG` is dangerous
- [ ] Create a shared directory owned by a group with `chgrp` and `chmod 770`
- [ ] Remove a user from a group with `gpasswd -d`
- [ ] Explain in DBA terms why groups make team access easy to manage
