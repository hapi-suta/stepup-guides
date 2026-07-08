# Packages and Repositories - Concepts Reference

This is your reference for how software works on CentOS Stream 9. It covers how
software is packaged, shared, and managed. Read it alongside the BUILD guides.
Come back to it any time you need to look something up. As a DBA, this is how you
get PostgreSQL onto a server.

---

## 1. What is a Package?

A package is one file that holds a piece of software plus everything needed to
install it. That includes the program's files, where each file goes on disk, its
version number, and a list of other packages it needs to run. Those needed
packages are called its dependencies.

On CentOS, packages use the **RPM** format (Red Hat Package Manager). The files
end in `.rpm`. Here is what a package name looks like:

```
postgresql16-server-16.4-1PGDG.rhel9.x86_64.rpm
```

| Part | Meaning |
|------|---------|
| `postgresql16-server` | Package name |
| `16.4` | Software version |
| `1PGDG.rhel9` | Package release / build (who built it, for which OS) |
| `x86_64` | Architecture (64-bit Intel/AMD); `noarch` means any architecture |
| `.rpm` | The package file format |

---

## 2. rpm vs dnf - Two Layers of the Same System

You have two tools for managing packages. They work together as a team.

| Tool | Level | What it does | Uses the network? | Resolves dependencies? |
|------|-------|--------------|-------------------|------------------------|
| `rpm` | Low-level | Installs, removes, and queries individual `.rpm` files; tracks what is installed in a local database | No | No |
| `dnf` | High-level | Downloads packages from repositories, resolves dependencies, then hands the actual install to `rpm` | Yes | Yes |

Here is the key idea: **`dnf` sits on top of `rpm`.** When you run `dnf install`,
`dnf` works out what to download and in what order. It fetches the `.rpm` files
from repositories. Then `rpm` does the real work of putting the files in place.
Both tools read the same package database, so they always agree on what is
installed.

### When to use which

- Use **`dnf`** to install, update, and remove software. It does the hard work:
  repos, downloads, and dependencies.
- Use **`rpm`** to ask quick, read-only questions about what is already
  installed. It is fast and never touches the network.

| Task | Command |
|------|---------|
| Install PostgreSQL | `sudo dnf install postgresql16-server` |
| List all installed packages | `rpm -qa` |
| Which package owns this file? | `rpm -qf /usr/pgsql-16/bin/psql` |
| What files did this package install? | `rpm -ql postgresql16-server` |
| Which package provides this command (installed or not)? | `dnf provides psql` |

> `yum` was the older high-level tool. On CentOS Stream 9, `yum` is just another
> name for `dnf` - they are the same program now. You will still see `yum` in
> older docs and in the directory name `/etc/yum.repos.d/`.

---

## 3. Repositories

A **repository** (or repo) is a server on the internet that holds a collection
of packages. It also holds **metadata**, which is an index that describes every
package: its name, version, and dependencies. `dnf` downloads this metadata and
saves a copy on your server. It then uses that copy to decide what to install and
where to get it.

### Repos that ship with CentOS Stream 9

| Repo id | Contents |
|---------|----------|
| `baseos` | The core operating system packages |
| `appstream` | Applications and runtimes (includes the OS's own PostgreSQL) |
| `extras-common` | Additional CentOS-maintained packages |

### Repos a DBA commonly adds

| Repo | Why |
|------|-----|
| **PGDG** (PostgreSQL Global Development Group) | The official PostgreSQL repo, with every supported major version (16, 15, 14, ...). The OS version is usually old. |
| **EPEL** (Extra Packages for Enterprise Linux) | Community extras like `htop`, monitoring tools, and utilities not in the base repos. |

### Where repos are defined

Each repo is described by a plain-text `.repo` file in `/etc/yum.repos.d/`. A
repo section looks like this:

```
[pgdg16]
name=PostgreSQL 16 for RHEL / Rocky / AlmaLinux 9 - x86_64
baseurl=https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-9-x86_64
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
```

| Field | Meaning |
|-------|---------|
| `[pgdg16]` | The repo id |
| `name` | Human-readable description |
| `baseurl` | The web address the packages are downloaded from |
| `enabled` | `1` = use this repo, `0` = ignore it |
| `gpgcheck` | `1` = verify package signatures before installing |
| `gpgkey` | Location of the key used to verify signatures |

Adding a repo (like PGDG) just means dropping a new `.repo` file into this
directory. That is exactly what the PGDG "repo RPM" does for you.

---

## 4. Dependency Resolution

Almost no software runs on its own. A program needs shared libraries, runtimes,
and helper tools. These are its **dependencies**. `dnf`'s most useful job is
**dependency resolution**. Before it changes anything, `dnf` reads what your
package needs. Then it reads what those needs need, all the way down. Finally it
builds a full plan called a **transaction**.

The transaction is what `dnf` shows you before it asks `Is this ok [y/N]`:

```
Installing:
 postgresql16-server    (the package you asked for)
Installing dependencies:
 postgresql16           (the client, required by the server)
 postgresql16-libs      (shared libraries, required by both)
```

Sometimes `dnf` cannot meet a requirement, because a needed package is missing
from every enabled repo. When that happens, it **stops and changes nothing**.
This "all or nothing" rule is a safety feature. You never end up with a
half-installed program.

Removal works the same way, but in reverse. If you remove a package, `dnf` also
removes anything that only depended on it. This is why you must read the
`Removing:` list carefully. A careless removal can spread and take out packages
you still needed.

---

## 5. Transactions and History

Every install, update, or removal is saved as a numbered **transaction** in a
local history database.

- `dnf history` - lists past transactions with an ID, the command, the date, and how many packages changed
- `dnf history info ID` - shows exactly what one transaction changed
- `dnf history undo ID` - reverses a single transaction
- `dnf history rollback ID` - undoes everything back to a given point

**Important limit:** `history undo` reverses *package* changes only. It does NOT
restore data files or config files you edited by hand. Say an update overwrote
`postgresql.conf`. Undoing the package will not bring back your custom settings.
So always back up config and data before a risky change. History is a safety net
for packages, not for everything.

---

## 6. Package Signatures and Security (GPG)

Trusted repos add a cryptographic **signature** to every package. When
`gpgcheck=1`, `dnf` checks that a package's signature matches a trusted key
before it installs. This proves two things:

1. The package really came from the vendor it claims to.
2. It was not tampered with in transit.

Never turn off `gpgcheck` on a database server. It is a core defense against
installing a bad or fake package. The first time you use a new repo, `dnf`
imports its GPG key and asks you to confirm you trust it.

---

## 7. The -y Flag and Production Discipline

The `-y` flag answers "yes" to `dnf`'s confirmation prompt for you. The command
then runs without stopping to ask.

- **Safe:** in tested automation scripts, and for well-known, low-risk installs
  (like adding the trusted PGDG repo RPM).
- **Dangerous:** on a live production database host you are working on by hand.

On production, always run install, update, and remove commands WITHOUT `-y`.
Read the transaction summary. Confirm nothing critical is being removed or
replaced. Only then type `y`. A rushed `dnf ... -y` can quietly remove a shared
library or trigger a surprise reboot. That is a classic cause of database
outages.

---

## 8. Updates, Upgrades, and Patching

| Command | What it does |
|---------|--------------|
| `dnf check-update` | Lists available updates without installing (read-only, no sudo) |
| `dnf update` / `dnf upgrade` | Installs newer versions of installed packages (same command on modern dnf) |
| `dnf update --security` | Installs only updates that fix security advisories |
| `dnf update PACKAGE` | Updates a single named package and its dependencies |

Patching matters because a database server is a high-value target. Attackers
look for unpatched flaws in the kernel, OpenSSL, or PostgreSQL. Those flaws can
be exploited or cause crashes. The DBA routine is simple: check what would
change, take a backup, schedule a maintenance window, apply the updates, and
reboot if a kernel or core-library update needs it. The `needs-restarting -r`
command tells you whether a reboot is needed. Many teams apply full updates
monthly, but apply critical security updates as soon as they land.

---

## 9. AppStream Modules

CentOS Stream 9 groups some software into **modules** that pin a specific version
"stream". PostgreSQL is one of them. A DBA usually wants the current PGDG version,
not the OS one. So the standard setup **disables** the built-in PostgreSQL module.
That stops it from hiding or clashing with the PGDG packages:

```
sudo dnf -qy module disable postgresql
```

Skip this step and you get the single most common cause of a broken PGDG
install. `dnf` gets confused about which `postgresql` package should win.

---

## 10. DBA Relevance Summary

Package management is how the database gets onto the box and stays healthy:

- **Install** PostgreSQL and its tools from the right repo at the right version.
- **Add the PGDG repo** to get a current, supported major version instead of the old OS default.
- **Resolve dependencies** automatically so PostgreSQL gets the exact libraries it needs.
- **Patch** the system to close security holes, on a schedule that respects database availability.
- **Audit** with `dnf history` and `rpm -qa` to answer "what changed?" and "what is installed?".
- **Recover** with `dnf provides` / `rpm -qf` when a command or file is missing, and `dnf history undo` when a change goes wrong.

Every one of these is a task you will perform on real database servers.
