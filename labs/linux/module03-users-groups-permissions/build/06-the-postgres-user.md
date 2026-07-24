# Build 06: The postgres User

Now you bring everything together on the account that matters most to a DBA: the
`postgres` OS user. You will inspect how it is defined. You will become it the
right way with `sudo su - postgres`. You will learn WHY PostgreSQL insists on a
dedicated, unprivileged account. And you will confirm the strict `700`
permission rule on the data directory.

Master this guide and you will fix most of the "PostgreSQL won't start"
incidents you meet in the real world.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first as `ec2-user`.

Note: this guide assumes PostgreSQL 16 is installed, so the `postgres` account
exists. If it is not installed yet, the inspection commands still teach the
idea. The installer creates the account in exactly the same way.

---

## 1. Meet the postgres user

The `postgres` user is a system service account. It is created automatically
when you install the PostgreSQL package. The database server process runs as
this user.

Look at its entry in the user database:

```bash
grep postgres /etc/passwd
```

`grep` finds the `postgres` line in `/etc/passwd`.

```
Expected output (yours will differ):
postgres:x:26:26:PostgreSQL Server:/var/lib/pgsql:/bin/bash
```

Reading the fields (from Build 01):

- `postgres` - username
- `x` - password stored in `/etc/shadow`
- `26` - UID (a low number, marking it a system account)
- `26` - primary GID
- `PostgreSQL Server` - the comment field
- `/var/lib/pgsql` - the home directory
- `/bin/bash` - the login shell

Check its group:

```bash
grep postgres /etc/group
```

```
Expected output (yours will differ):
postgres:x:26:
```

The `postgres` user's primary group is also `postgres` (GID 26). This matched
user-and-group pair is the `postgres:postgres` ownership you set in Build 04.

> **Concept - Low UID = System Account:** Recall from Build 01 that UIDs below
> 1000 are system or service accounts. `postgres` at UID 26 is a system account,
> not a human login. It exists only to own and run the database. No person
> should ever set a password on it and log in with it.

---

## 2. Becoming the postgres user the right way

To manage PostgreSQL, you often need to act AS the `postgres` user. You do this
to run `psql`, `pg_ctl`, or `initdb`, for example. The safe way is a clean two
steps: switch users first, then run your commands.

On your lab server, as `ec2-user`, switch into the postgres account:

```bash
sudo su - postgres
```

Breaking it down (from Build 03):

- `sudo` - authorize using your own privileges
- `su - postgres` - substitute to the `postgres` user with a full login shell
- the `-` loads postgres's environment, including the `PATH` that finds `psql`

Your prompt changes to show you are now `postgres`.

```
Expected output (yours will differ):
[postgres@ip-10-0-1-50 ~]$
```

Confirm who you are and where you landed:

```bash
whoami
```

```
Expected output (yours will differ):
postgres
```

```bash
pwd
```

`pwd` prints your current directory. Because you used the `-`, you are in
postgres's home directory.

```
Expected output (yours will differ):
/var/lib/pgsql
```

Now, still as `postgres`, run a PostgreSQL command to prove the environment is
correct:

```bash
psql --version
```

`psql --version` prints the PostgreSQL client version. It works here because
postgres's `PATH` includes the PostgreSQL programs.

```
Expected output (yours will differ):
psql (PostgreSQL) 16.4
```

When you are finished acting as `postgres`, always exit back to `ec2-user`:

```bash
exit
```

Your prompt returns to `$` and `whoami` would again show `ec2-user`.

> **Concept - Why Not `su postgres` Without the Dash:** If you run
> `sudo su postgres` (no dash), you keep `ec2-user`'s environment. Postgres's
> program path is often missing, so `psql --version` fails with "command not
> found". This trips up a lot of beginners. The dash in `su - postgres` is not
> optional. It is what makes the tools work. Every SUTA Labs guide uses
> `sudo su - postgres` for this reason.

---

## 3. Why PostgreSQL uses a dedicated unprivileged user

PostgreSQL flatly refuses to run as root. Imagine the alternative and you will
see why.

| If PostgreSQL ran as root | Because it runs as postgres |
|---------------------------|-----------------------------|
| A SQL injection or bug could read/write ANY file on the server | Damage is limited to files owned by `postgres` |
| A compromised database = a fully compromised server | A compromised database stays boxed into the postgres account |
| Data files could accidentally clobber system files | Postgres can only touch its own data directory |
| No separation between the OS admin and the DB service | Clean separation: OS admins use `sudo`, the DB uses `postgres` |

PostgreSQL even checks for this at startup and refuses to run as root. It is a
hard safety rule built into the software. This is the principle of least
privilege (Build 03), enforced by the database itself.

> **DBA Context - Least Privilege in Practice:** This is the same idea as not
> logging in as root. The database does the most exposed work on the server. It
> listens on a network port and runs queries from clients. Running it as an
> unprivileged account means that even in a worst-case breach, the attacker is
> stuck inside the `postgres` user's files and cannot take over the whole
> machine.

---

## 4. The 700 permission requirement on the data directory

PostgreSQL has a second hard rule. Its data directory must be reachable ONLY by
the `postgres` user. That means permission `700`: owner `rwx`, group nothing,
other nothing. If the directory gives any access to group or other, PostgreSQL
refuses to start.

On CentOS with PostgreSQL 16, the data directory is
`/var/lib/pgsql/16/data`. Inspect it as `ec2-user` with a one-off `sudo`:

```bash
sudo ls -ld /var/lib/pgsql/16/data
```

`ls -ld` shows the directory itself. We use `sudo` because only `postgres` (or
root) can read inside that path.

```
Expected output (yours will differ):
drwx------. 20 postgres postgres 4096 Apr 19 10:00 /var/lib/pgsql/16/data
```

Read the permission string `drwx------`:

- `d` - it is a directory
- `rwx` - the owner (`postgres`) has full access
- `---` - the group has NO access
- `---` - everyone else has NO access

That is `700`, owned by `postgres:postgres`. This is the setup PostgreSQL wants
to see.

### What happens when it is wrong

If someone loosens the permissions, the database refuses to start. PostgreSQL
runs this check at startup. When it fails, here is the error it prints:

```
Expected output (yours will differ):
FATAL:  data directory "/var/lib/pgsql/16/data" has invalid permissions
DETAIL:  Permissions should be u=rwx (0700) or u=rwx,g=rx (0750).
```

(Recent versions also allow `0750`, so a read-only group can peek in. But
`0700` is the safe default. Use it unless you have a specific reason not to.)

The fix pulls together everything from this module. If the data directory ever
ends up with the wrong permissions, you would run this (as root or via sudo):

```bash
sudo chmod 700 /var/lib/pgsql/16/data
```

`chmod 700` sets owner-only access. And if ownership is also wrong (from
Build 04):

```bash
sudo chown -R postgres:postgres /var/lib/pgsql/16/data
```

Together these two commands set correct ownership (`postgres:postgres`) and
correct permissions (`700`). They fix the large majority of PostgreSQL startup
failures.

> **DBA Context - The Golden Startup Checklist:** When PostgreSQL will not
> start, an experienced DBA checks three things in order. All three use skills
> from this module. (1) Is the data directory owned by `postgres:postgres`? Use
> `ls -ld`. (2) Is it `700` (or `750`)? Use `ls -ld`. (3) Does the postgres
> process actually run as the `postgres` user? These ownership and permission
> checks solve more startup incidents than any amount of log-diving.

---

## 5. Putting the module together

Let's trace the full chain of ideas you now understand. The postgres user ties
them all together:

- **Build 01 (Users):** `postgres` is a system user with a low UID (26) and no
  interactive login for humans.
- **Build 02 (Groups):** its primary group is `postgres`; you add teammates to
  it to share access to logs.
- **Build 03 (sudo):** you become it safely with `sudo su - postgres` and never
  run the database as root.
- **Build 04 (Ownership):** the data directory must be owned
  `postgres:postgres`, fixed with `chown -R`.
- **Build 05 (Permissions):** the data directory must be `700`, and a strict
  `umask` keeps new backup files private.
- **Build 06 (this guide):** all of it comes together in a database that runs
  unprivileged, isolated, and secure.

Run one last check that you can become postgres and see its identity:

```bash
sudo su - postgres
```

```bash
id
```

```
Expected output (yours will differ):
uid=26(postgres) gid=26(postgres) groups=26(postgres) context=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
```

The `id` output shows UID 26, GID 26, and group `postgres` (the trailing
`context=` is the SELinux label, which you can ignore). This is the account
the whole module has been leading toward. Now exit back to `ec2-user`:

```bash
exit
```

> **DBA Context - You Now Speak Permissions:** "Permission denied" is no longer
> a mystery. You can read ownership and permission bits. You can reason about
> who you are versus who owns a file. You can become the right user. And you can
> set the exact ownership and permissions PostgreSQL demands. That fluency is
> what makes a DBA effective on any Linux server, in any datacenter.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Read the `postgres` entry from `/etc/passwd` and identify it as a system account by its low UID
- [ ] Explain why the `postgres` user has no interactive human login
- [ ] Become the postgres user with `sudo su - postgres` and confirm with `whoami` and `pwd`
- [ ] Explain why the dash in `su - postgres` is required for `psql` to be found
- [ ] Give at least two reasons PostgreSQL refuses to run as root
- [ ] State the required ownership of the data directory (`postgres:postgres`)
- [ ] State the required permission on the data directory (`700`) and read `drwx------`
- [ ] Recite the fix for a data directory with wrong ownership and permissions
- [ ] List the golden three-item checklist for a PostgreSQL startup failure
- [ ] Explain how least privilege limits the blast radius of a database compromise
