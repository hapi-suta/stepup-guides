# Build 01: Searching for and Inspecting Packages

In this guide you will learn four things. How to search for software. How to
read a package's details before you install it. How to list what is already
installed. And how to find which package provides a certain file or command.
As a DBA, this is how you check that a package exists, see its version, and
decide what to install before you touch the system.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first as **ec2-user**.

---

## Step 0 - What is dnf?

`dnf` is the package manager on CentOS Stream 9. A package manager installs,
updates, and removes software for you. It also handles the other packages your
software needs to run. You do not download files from a website by hand.
Instead, you tell `dnf` what you want. It then fetches everything from a
trusted software store called a repository.

As a DBA, you will use `dnf` a lot. You will use it to install PostgreSQL, add
its official repository, pull in monitoring tools, and keep the system patched.
But before you install anything, you first search and inspect. That is what
this guide covers.

Searching and inspecting do not change the system. So these commands do not
need `sudo`.

One-time setup: some example packages in this module (like `htop`) live in the
EPEL repository, which is not enabled on a fresh CentOS box. Enable it once now
so the examples below work. This is the only command in this guide that changes
the system, so it uses `sudo`:

```bash
sudo dnf install -y epel-release
```

```
Expected output (yours will differ):
Installed:
  epel-next-release-9-7.el9.noarch          epel-release-9-7.el9.noarch

Complete!
```

---

## 1. dnf search - Find a package by keyword

Use `dnf search` when you know roughly what you want but not the exact name.
It looks through package names and short descriptions for your keyword.

On **your lab server**, as **ec2-user**:

```bash
dnf search htop
```

- `dnf` - the package manager command
- `search` - the sub-command that looks for matching packages
- `htop` - the keyword to search for

```
Expected output (yours will differ):
Last metadata expiration check: 0:00:21 ago on Wed 08 Jul 2026 07:21:29 PM UTC.
========================== Name Exactly Matched: htop ==========================
htop.x86_64 : Interactive process viewer
```

The first line mentions "metadata expiration." That just means `dnf` is using
its saved list of available packages. That is normal.

Now search with a broader keyword to see more matches:

```bash
dnf search postgresql
```

```
Expected output (yours will differ):
====================== Name & Summary Matched: postgresql ======================
postgresql.x86_64 : PostgreSQL client programs
postgresql-contrib.x86_64 : Extension modules distributed with PostgreSQL
postgresql-server.x86_64 : The programs needed to create and run a PostgreSQL server
postgresql-upgrade.x86_64 : Support for upgrading from the previous major release of PostgreSQL
...
```

> **DBA Context - Search Before You Install:** Searching first tells you two
> things. Whether a package exists in your repositories, and what its exact
> name is. Package names are precise. `postgresql` is the client, but
> `postgresql-server` is the actual database server. Installing the wrong one
> is a common beginner mistake.

---

## 2. dnf info - Read the details before installing

`dnf info` shows everything about a package. Its version, size, license,
repository, and a full description. Always read this before you install
something you are unsure about.

```bash
dnf info htop
```

```
Expected output (yours will differ):
Available Packages
Name         : htop
Version      : 3.3.0
Release      : 1.el9
Architecture : x86_64
Size         : 198 k
Source       : htop-3.3.0-1.el9.src.rpm
Repository   : epel
Summary      : Interactive process viewer
License      : GPLv2+
Description  : htop is an interactive text-mode process viewer for Linux, similar to
             : top(1).
```

Here are the key fields to read:

- `Version` - which version you would get
- `Repository` - which repo it comes from (or `@System` if already installed)
- `Size` - the download size
- `Description` - what the package actually does

Now check the base OS package for PostgreSQL:

```bash
dnf info postgresql-server
```

```
Expected output (yours will differ):
Available Packages
Name         : postgresql-server
Version      : 13.23
Release      : 3.el9
Architecture : x86_64
Repository   : appstream
Summary      : The programs needed to create and run a PostgreSQL server
...
```

Notice the version is `13`. The version that ships with the OS is often old. In
a later guide you will add the official PostgreSQL repository. That gets you a
current version like 16.

---

## 3. dnf list installed - See what is already on the box

`dnf list installed` shows every package that is installed right now. On its
own it prints hundreds of lines. So you usually filter it with a keyword.

First, list everything. Pipe it through `head` so it does not flood your
terminal:

```bash
dnf list installed | head -10
```

- `|` - a pipe, sends the output of `dnf` into the next command
- `head -10` - shows only the first 10 lines

```
Expected output (yours will differ):
Installed Packages
NetworkManager.x86_64          1:1.54.4-2.el9    @anaconda
NetworkManager-libnm.x86_64    1:1.54.4-2.el9    @anaconda
NetworkManager-tui.x86_64      1:1.54.4-2.el9    @anaconda
acl.x86_64                     2.3.1-4.el9       @anaconda
...
```

Now list only installed packages whose name matches a keyword:

```bash
dnf list installed "openssl*"
```

The `openssl*` uses a wildcard. It matches `openssl`, `openssl-libs`, and so
on. Put quotes around it so the shell does not expand the `*` itself.

```
Expected output (yours will differ):
Installed Packages
openssl.x86_64                 1:3.5.7-1.el9     @anaconda
openssl-fips-provider.x86_64   1:3.5.7-1.el9     @anaconda
openssl-libs.x86_64            1:3.5.7-1.el9     @anaconda
```

The `@anaconda` at the end tells you where each package came from. `@anaconda`
means it was installed when the OS was first set up. Other packages may show a
repo name like `@appstream` or `@baseos` instead.

> **DBA Context - Auditing Installed Software:** When you inherit a server, one
> of the first things you do is find out what is on it.
> `dnf list installed | grep -i postgres` tells you at once whether
> PostgreSQL is present and which version. This matters during audits and when
> planning upgrades.

---

## 4. dnf provides - Which package owns a file or command?

Sometimes you know a command exists but not which package installs it. Or a
script fails because a file is missing. `dnf provides` answers one question:
"which package would give me this file or command?"

Find out which package provides the `psql` command:

```bash
dnf provides psql
```

```
Expected output (yours will differ):
postgresql-13.16-1.el9.x86_64 : PostgreSQL client programs
Repo        : appstream
Matched from:
Filename    : /usr/bin/psql
...
```

This tells you `psql` comes from the `postgresql` package. If it is not
installed, you now know exactly what to install.

Now find which package owns a specific file path:

```bash
dnf provides /etc/hosts
```

The path must be a real file path. This helps when a config file is missing
and you need to know which package to reinstall.

```
Expected output (yours will differ):
setup-2.13.7-6.el9.noarch : A set of system configuration and setup files
Repo        : baseos
Matched from:
Filename    : /etc/hosts
...
```

You can also use a wildcard to find which package provides any file under a
directory:

```bash
dnf provides "*/pg_hba.conf"
```

```
Expected output (yours will differ):
postgresql-server.x86_64 : The programs needed to create and run a PostgreSQL server
Repo        : appstream
Matched from:
Filename    : /usr/share/pgsql/pg_hba.conf.sample
...
```

> **DBA Context - Missing Command Recovery:** A runbook says to run
> `pg_basebackup`. But the server replies `command not found`. You use
> `dnf provides pg_basebackup` to find the package
> (`postgresql-server` or `postgresqlNN-server`), then install it. This turns a
> confusing error into a one-line fix.

---

## 5. Practice exercises

### Search for a text editor

```bash
dnf search vim
```

```
Expected output (yours will differ):
====================== Name Exactly Matched: vim =======================
vim-enhanced.x86_64 : A version of the VIM editor which includes recent enhancements
vim-common.x86_64 : The common files needed by any version of the VIM editor
...
```

### Check how big the git package is before installing

```bash
dnf info git
```

Look at the `Size` field in the output.

### Find out if wget is installed

```bash
dnf list installed "wget"
```

If it prints an "Error: No matching Packages to list" message, it is not
installed yet.

### Find which package provides the ifconfig command

```bash
dnf provides ifconfig
```

```
Expected output (yours will differ):
net-tools-2.0-0.65.20160912git.el9.x86_64 : Basic networking tools
Repo        : appstream
Matched from:
Filename    : /usr/sbin/ifconfig
...
```

This tells you `ifconfig` lives in the `net-tools` package.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Use `dnf search KEYWORD` to find packages by keyword
- [ ] Use `dnf info PACKAGE` to read a package's version, repo, and description
- [ ] Explain the difference between `postgresql` and `postgresql-server`
- [ ] Use `dnf list installed` and filter it with a keyword
- [ ] Read the `@repository` marker to see where an installed package came from
- [ ] Use `dnf provides COMMAND` to find which package owns a command
- [ ] Use `dnf provides /path/to/file` to find which package owns a file
- [ ] Explain why searching and inspecting do not need `sudo`

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
