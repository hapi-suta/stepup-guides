# Build 05: Installing PostgreSQL from the Official Repo

In this guide you will do a real DBA setup. You will add the official
PostgreSQL repo, called PGDG. You will install its repo package. You will turn
off the built-in PostgreSQL module that CentOS ships with. Then you will install
`postgresql16-server`.

This is how you get an up-to-date PostgreSQL onto a real server, instead of the
old version that comes with the operating system.

**Time estimate:** 50 minutes

All steps run on your lab server. Connect with SSH first as **ec2-user**.

---

## Step 0 - Why not just dnf install postgresql-server?

In Build 01 you saw that the OS repos offer `postgresql-server` version 13.
That is fine for testing. But in production, DBAs almost always want a current,
fully supported version like 16. The PostgreSQL project runs its own repo for
this. It is called the PGDG repo, short for PostgreSQL Global Development Group.
It carries every supported version.

The setup has three parts:

1. Add the PGDG repo (install a small "repo package")
2. Turn off the built-in CentOS `postgresql` module so it does not clash
3. Install `postgresql16-server` from PGDG

Follow the steps in order. Doing them out of order is the most common reason
this setup fails.

---

## 1. Add the PGDG repository

The PGDG repo comes as a small RPM package. When you install it, it drops the
`.repo` file into `/etc/yum.repos.d/` for you. You install it straight from a
web address (a URL).

On **your lab server**, as **ec2-user**:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

- `sudo dnf install` - install a package
- `-y` - this is a safe, well-known repo RPM, so auto-confirm is acceptable here
- the URL - `dnf` downloads the RPM straight from the PostgreSQL project

```
Expected output (yours will differ):
pgdg-redhat-repo-latest.noarch.rpm              45 kB/s |  12 kB     00:00
Dependencies resolved.
========================================================================
 Package               Architecture  Version       Repository    Size
========================================================================
Installing:
 pgdg-redhat-repo      noarch        42.0-49PGDG    @commandline  12 k
...
Installed:
  pgdg-redhat-repo-42.0-49PGDG.noarch

Complete!
```

Confirm the new repo file appeared:

```bash
ls /etc/yum.repos.d/ | grep pgdg
```

```
Expected output (yours will differ):
pgdg-redhat-all.repo
```

Confirm the PGDG repos are now known to `dnf`:

```bash
dnf repolist | grep pgdg
```

```
Expected output (yours will differ):
pgdg-common      PostgreSQL common RPMs for RHEL / Rocky / AlmaLinux 9 - x86_64
pgdg16           PostgreSQL 16 for RHEL / Rocky / AlmaLinux 9 - x86_64
pgdg15           PostgreSQL 15 for RHEL / Rocky / AlmaLinux 9 - x86_64
...
```

---

## 2. Disable the built-in PostgreSQL module

CentOS Stream 9 ships its own PostgreSQL as an "AppStream module". If you leave
it turned on, it can hide or clash with the PGDG packages. So you turn it off.
That way `dnf` uses the PGDG version with no trouble.

```bash
sudo dnf -qy module disable postgresql
```

- `module disable postgresql` - turn off the built-in PostgreSQL module stream
- `-q` - quiet mode (less output)
- `-y` - auto-confirm

```
Expected output (yours will differ):
Importing GPG key 0x08B40D20:
 Userid     : "PostgreSQL RPM Repository ..."
 ...
```

This command is quiet by design. If it returns to the prompt with no error, it
worked.

> **Concept - AppStream Modules:** CentOS groups some software into "modules".
> A module locks you to one version. PostgreSQL is one of these. You want the
> PGDG version, not the OS one. So you turn off the module. That way the two do
> not fight over which `postgresql` package wins. Skipping this step is the top
> cause of a broken PGDG install.

---

## 3. Install postgresql16-server

Now install the PostgreSQL 16 server package. Notice that the version number is
part of the package name: `postgresql16-server`.

```bash
sudo dnf install -y postgresql16-server
```

- `postgresql16-server` - the PostgreSQL 16 server from the PGDG repo

```
Expected output (yours will differ):
Dependencies resolved.
========================================================================
 Package                Architecture  Version         Repository   Size
========================================================================
Installing:
 postgresql16-server    x86_64        16.4-1PGDG.rhel9  pgdg16     5.7 M
Installing dependencies:
 postgresql16           x86_64        16.4-1PGDG.rhel9  pgdg16     1.6 M
 postgresql16-libs      x86_64        16.4-1PGDG.rhel9  pgdg16     287 k
...
Installed:
  postgresql16-server-16.4-1PGDG.rhel9.x86_64
  postgresql16-16.4-1PGDG.rhel9.x86_64
  postgresql16-libs-16.4-1PGDG.rhel9.x86_64

Complete!
```

Notice that `dnf` also pulled in two other packages on its own: `postgresql16`
(the client) and `postgresql16-libs` (shared libraries). These are
dependencies. That is the same automatic dependency handling you learned in
Build 02.

---

## 4. Confirm the install and version

The PGDG packages put their programs under a version-based path:
`/usr/pgsql-16/bin/`. This path is not on your PATH by default, so you have to
type it in full. Let's confirm the files are there and check the version.

Check the server binary exists:

```bash
ls /usr/pgsql-16/bin/
```

```
Expected output (yours will differ):
initdb   pg_basebackup  pg_ctl  pg_dump  postgres  psql  ...
```

Check the version:

```bash
/usr/pgsql-16/bin/postgres --version
```

```
Expected output (yours will differ):
postgres (PostgreSQL) 16.4
```

You now have PostgreSQL 16 installed. Setting up the data directory and starting
the service come later, in the PostgreSQL installation module. Here we focused
on the package side: getting PostgreSQL onto the box.

> **DBA Context - Versioned Paths:** PGDG installs into `/usr/pgsql-16/bin/`.
> Version 15 goes into `/usr/pgsql-15/bin/`, and so on. It does this on purpose.
> It lets you keep more than one major version on a box at the same time, which
> helps during an upgrade. This is why runbooks use full paths like
> `/usr/pgsql-16/bin/pg_ctl`. They do not assume `pg_ctl` is on your PATH.

---

## 5. Verify it came from the right repo

Let's make sure the installed package really came from PGDG, and not from the OS
repo:

```bash
dnf list installed "postgresql16*"
```

```
Expected output (yours will differ):
Installed Packages
postgresql16.x86_64            16.4-1PGDG.rhel9    @pgdg16
postgresql16-libs.x86_64       16.4-1PGDG.rhel9    @pgdg16
postgresql16-server.x86_64     16.4-1PGDG.rhel9    @pgdg16
```

The `@pgdg16` tag on each line shows these came from the PostgreSQL 16 repo. The
version also ends in `PGDG`. That is exactly what you want.

---

## 6. Practice exercises

### Confirm the pgdg16 repo is enabled

```bash
dnf repolist | grep pgdg16
```

```
Expected output (yours will differ):
pgdg16      PostgreSQL 16 for RHEL / Rocky / AlmaLinux 9 - x86_64
```

### See which client tools PGDG installed

```bash
ls /usr/pgsql-16/bin/ | grep pg_
```

```
Expected output (yours will differ):
pg_basebackup
pg_config
pg_ctl
pg_dump
pg_dumpall
pg_restore
...
```

### Check the psql client version

```bash
/usr/pgsql-16/bin/psql --version
```

```
Expected output (yours will differ):
psql (PostgreSQL) 16.4
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain why DBAs add the PGDG repo instead of using the OS PostgreSQL package
- [ ] Add the PGDG repo by installing the repo RPM from its URL
- [ ] Confirm the new `.repo` file appeared and the pgdg repos show in `dnf repolist`
- [ ] Disable the built-in PostgreSQL AppStream module and explain why
- [ ] Install `postgresql16-server` and see its dependencies pulled in automatically
- [ ] Locate the versioned binary path `/usr/pgsql-16/bin/`
- [ ] Check the installed version with `/usr/pgsql-16/bin/postgres --version`
- [ ] Confirm the packages came from `@pgdg16` with `dnf list installed`

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
