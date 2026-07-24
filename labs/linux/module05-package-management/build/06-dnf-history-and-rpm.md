# Build 06: dnf history and rpm

In this guide you will learn a few key tools. You will review everything `dnf`
has done with `dnf history`. You will undo an action with `dnf history undo`.
And you will use the lower-level `rpm` tool three ways: to list installed
packages (`rpm -qa`), to find which package owns a file (`rpm -qf`), and to list
the files a package installed (`rpm -ql`).

As a DBA, these are the tools you use to track changes and undo a bad install.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first as **ec2-user**.

---

## Step 0 - dnf vs rpm

`rpm` is the low-level tool. It installs and tracks each package file. `dnf`
sits on top of `rpm`. It adds repos, works out dependencies, and downloads
packages for you.

Use `dnf` to install and update. It does the heavy lifting. Use `rpm` to ask
exact questions about what is already installed. `rpm` never touches the network
and never works out dependencies. Both tools read the same package database, so
they always agree on what is installed.

---

## 1. dnf history - Review every transaction

Every time `dnf` installs, updates, or removes something, it saves a record. Each
record is a numbered transaction. `dnf history` shows that log. It only reads,
so it does not need `sudo`.

On **your lab server**, as **ec2-user**:

```bash
dnf history
```

```
Expected output (yours will differ):
ID     | Command line              | Date and time    | Action(s)   | Altered
-------------------------------------------------------------------------------
    6  | install -y postgresql16-. | 2026-07-08 15:02 | Install     |    3
    5  | -qy module disable postg. | 2026-07-08 15:00 | Disabled    |    1
    4  | install -y dnf-plugins-c. | 2026-07-08 14:55 | Install     |    2
    3  | install git               | 2026-07-08 14:40 | Install     |   10
    2  | install htop              | 2026-07-08 14:30 | Install     |    1
    1  |                           | 2026-07-08 14:10 | Install     |  428 EE
-------------------------------------------------------------------------------
```

- `ID` - the transaction number (used to inspect or undo it)
- `Command line` - the command you ran (truncated)
- `Action(s)` - Install, Upgrade, Remove, etc.
- `Altered` - how many packages that transaction changed

Transaction `1` with a big number is the original OS installation.

### Look inside one transaction

Pass a transaction ID to see exactly what it changed:

```bash
dnf history info 3
```

```
Expected output (yours will differ):
Transaction ID : 3
Begin time     : Wed 08 Jul 2026 02:40:00 PM UTC
Command Line   : install git
...
Packages Altered:
    Install git-2.43.5-1.el9.x86_64                @appstream
    Install git-core-2.43.5-1.el9.x86_64           @appstream
    Install perl-Git-2.43.5-1.el9.noarch           @appstream
...
```

> **DBA Context - The Change Audit:** When a server starts acting strange, one
> of the first questions is "what changed recently?". `dnf history` answers it.
> It shows who installed or updated what, and when. On a production database
> host, this log is often the fastest way to go from "it broke this afternoon"
> to "someone updated openssl at 2pm".

---

## 2. dnf history undo - Roll back a transaction

If a transaction caused a problem, you can undo it. `dnf history undo` reverses
one transaction. It removes what was installed. It reinstalls what was removed.
It changes the system, so it needs `sudo`.

Suppose transaction `2` installed `htop` and you want to reverse just that:

```bash
sudo dnf history undo 2
```

- `history undo 2` - reverse transaction number 2

```
Expected output (yours will differ):
Undoing transaction 2, from Wed 08 Jul 2026 02:30:00 PM UTC
    Install htop-3.2.1-1.el9.x86_64 @epel
Dependencies resolved.
========================================================================
 Package    Architecture   Version         Repository       Size
========================================================================
Removing:
 htop       x86_64         3.2.1-1.el9     @epel           384 k
...
Is this ok [y/N]:
```

Read the summary first. It shows that undoing an install means removing the
package. Type `y` to confirm, or `N` to cancel.

There is also `dnf history rollback ID`. This undoes everything back to a given
point, meaning all transactions after that ID. So use `undo` for a single
transaction. Use `rollback` to return the whole system to an earlier state.

> **DBA Context - Undo Is Not Magic:** `history undo` reverses package changes.
> But it does NOT restore data or config files you edited by hand. Say an update
> rewrote `postgresql.conf`. Undoing the package will not bring back your custom
> settings. So always back up your config and data before a risky change. Undo
> is a safety net for packages, not for everything.

---

## 3. rpm -qa - List all installed packages

`rpm -qa` lists every installed package. The `-q` means "query" (ask a
question). The `-a` means "all". It reads the local package database right away.

```bash
rpm -qa | head -10
```

```
Expected output (yours will differ):
setup-2.13.7-1.el9.noarch
filesystem-3.16-2.el9.x86_64
basesystem-11-13.el9.noarch
bash-5.1.8-9.el9.x86_64
glibc-2.34-100.el9.x86_64
...
```

Filter for PostgreSQL packages:

```bash
rpm -qa | grep postgresql
```

```
Expected output (yours will differ):
postgresql16-libs-16.4-1PGDG.rhel9.x86_64
postgresql16-16.4-1PGDG.rhel9.x86_64
postgresql16-server-16.4-1PGDG.rhel9.x86_64
```

Notice that `rpm -qa` prints the full version, including the `PGDG` build tag.
This is a fast way to confirm exactly what is installed. And it needs no
network.

---

## 4. rpm -qf - Which package owns a file?

`rpm -qf` (query file) tells you which installed package a file belongs to.
Think of it as the "already installed" version of `dnf provides`.

Find which package owns the `psql` binary path:

```bash
rpm -qf /usr/pgsql-16/bin/psql
```

- `-qf` - query which package owns this file

```
Expected output (yours will differ):
postgresql16-16.4-1PGDG.rhel9.x86_64
```

Find which package owns a system file:

```bash
rpm -qf /etc/hosts
```

```
Expected output (yours will differ):
setup-2.13.7-1.el9.noarch
```

> **DBA Context - Tracing a Mystery File:** Say you find a strange config file
> or program and wonder where it came from. `rpm -qf` names the package that put
> it there. If no package owns the file, `rpm` says "not owned by any package".
> That tells you a person or a script made it, not the package manager. This
> difference matters during a security review.

---

## 5. rpm -ql - List a package's files

`rpm -ql` (query list) lists every file a package installed. Use it to find
where a package put its programs, config files, and docs.

List the files installed by `postgresql16-server`:

```bash
rpm -ql postgresql16-server | head -15
```

- `-ql` - query and list the files of a package

```
Expected output (yours will differ):
/usr/pgsql-16/bin/initdb
/usr/pgsql-16/bin/pg_basebackup
/usr/pgsql-16/bin/pg_ctl
/usr/pgsql-16/bin/postgres
/usr/pgsql-16/lib/...
/usr/pgsql-16/share/pg_hba.conf.sample
...
```

This confirms exactly where PostgreSQL 16 put its programs. It is the
version-based `/usr/pgsql-16/bin/` path you saw in Build 05.

Find just the config-sample files a package ships:

```bash
rpm -ql postgresql16-server | grep conf
```

```
Expected output (yours will differ):
/usr/pgsql-16/share/pg_hba.conf.sample
/usr/pgsql-16/share/pg_ident.conf.sample
/usr/pgsql-16/share/postgresql.conf.sample
```

> **DBA Context - Finding Where a Package Put Things:** New to a server and need
> to know where PostgreSQL's programs or sample configs live?
> `rpm -ql postgresql16-server` lists every file it owns. This beats guessing.
> It is far safer than assuming a standard path, especially when a box has
> several major versions installed side by side.

---

## 6. Practice exercises

### View the most recent dnf transactions

```bash
dnf history
```

### Inspect what your PostgreSQL install transaction changed

```bash
dnf history info 6
```

(Use the ID that matches your `postgresql16-server` install.)

### Count how many packages are installed

```bash
rpm -qa | wc -l
```

```
Expected output (yours will differ):
441
```

### Find which package owns the sshd config

```bash
rpm -qf /etc/ssh/sshd_config
```

```
Expected output (yours will differ):
openssh-server-8.7p1-38.el9.x86_64
```

### List the binaries the postgresql16 client package installed

```bash
rpm -ql postgresql16 | grep bin
```

```
Expected output (yours will differ):
/usr/pgsql-16/bin/psql
/usr/pgsql-16/bin/pg_dump
/usr/pgsql-16/bin/pg_restore
...
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain the difference between `dnf` (high-level, network) and `rpm` (low-level, local)
- [ ] Use `dnf history` to list past transactions
- [ ] Use `dnf history info ID` to inspect what one transaction changed
- [ ] Use `sudo dnf history undo ID` to reverse a transaction
- [ ] Explain that undo reverses packages but NOT hand-edited config or data
- [ ] Use `rpm -qa` to list installed packages and filter with `grep`
- [ ] Use `rpm -qf FILE` to find which package owns a file
- [ ] Use `rpm -ql PACKAGE` to list all files a package installed

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
