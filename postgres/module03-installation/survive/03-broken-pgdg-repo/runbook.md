# Scenario 03 - Broken PGDG Repository

**Severity:** MEDIUM
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Package installation failing on the database server.
The team needs to install postgresql16-contrib but dnf reports
'Failed to download metadata' errors.
PostgreSQL is still running - this is a packaging issue.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **PGDG (PostgreSQL Global Development Group) repository** - The official package repository for PostgreSQL on RHEL/CentOS/Rocky. It provides RPM packages for all supported PG versions. The repo file lives at `/etc/yum.repos.d/pgdg-redhat-all.repo` and contains baseurl entries pointing to `https://download.postgresql.org/pub/repos/yum/`.

- **dnf repolist** - Shows all enabled repositories and their status. If a repo is misconfigured (bad URL, expired GPG key, network issue), it may not appear or will show an error. This is the first command to run when package operations fail.

- **dnf clean all** - Removes all cached metadata and packages from `/var/cache/dnf/`. After fixing a repo file, you must clean the cache so dnf re-downloads metadata from the corrected URL. Without this, dnf may continue using stale cached data.

- **Repo file structure** - Each `.repo` file contains sections like `[pgdg16]` with `name=`, `baseurl=`, `enabled=`, and `gpgcheck=` directives. The `baseurl` must point to a valid URL containing the `repodata/` directory. A typo in the URL causes all package operations for that repo to fail.

- **Why this matters for DBAs** - You cannot install extensions, upgrade minor versions, or install debugging tools if the repo is broken. In an emergency (e.g., you need `pg_stat_statements` or `pg_repack`), a broken repo turns a 2-minute fix into a much longer outage.

---

## Diagnostic Steps

### Step 1 - Try the failing command to see the error

```bash
sudo dnf info postgresql16-contrib
```

Expected output includes errors like:

```
Failed to download metadata for repo 'pgdg16'
Error: Failed to download metadata for repo 'pgdg16': Cannot download repomd.xml
```

### Step 2 - Check which repos are available

```bash
sudo dnf repolist
```

If `pgdg16` is missing from the list or shows an error, the repo configuration is broken.

### Step 3 - Examine the repo file

```bash
sudo cat /etc/yum.repos.d/pgdg-redhat-all.repo
```

Look at the `baseurl` lines. Look for anything that seems wrong - typos, incorrect paths, unreachable domains.

### Step 4 - Identify the problem

```bash
sudo grep baseurl /etc/yum.repos.d/pgdg-redhat-all.repo | head -5
```

Expected output shows something like:

```
baseurl=https://download.postgresql.org/pub/repos/BROKEN/...
```

The URL contains `BROKEN` instead of `yum`. This is why dnf cannot download metadata.

### Step 5 - Confirm PG is still running

```bash
sudo systemctl status postgresql-16
```

PostgreSQL itself is not affected - this is purely a package manager issue.

---

## Resolution

### Step 1 - Fix the baseurl in the repo file

Replace the broken URL with the correct one:

```bash
sudo sed -i 's|/pub/repos/BROKEN|/pub/repos/yum|g' /etc/yum.repos.d/pgdg-redhat-all.repo
```

### Step 2 - Verify the fix

```bash
sudo grep baseurl /etc/yum.repos.d/pgdg-redhat-all.repo | head -3
```

Expected output:

```
baseurl=https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-$releasever-$basearch
...
```

### Step 3 - Clean the dnf cache

```bash
sudo dnf clean all
```

### Step 4 - Test that the repo works

```bash
sudo dnf repolist
```

Expected output includes a line like:

```
pgdg16           PostgreSQL 16 for RHEL / Rocky / AlmaLinux 9 - x86_64
```

### Step 5 - Confirm packages are queryable

```bash
sudo dnf info postgresql16-contrib
```

Expected output shows package details (name, version, repository, size).

### Step 6 - Clean up the backup file

```bash
sudo rm -f /etc/yum.repos.d/pgdg-redhat-all.repo.chaos-bak
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- pgdg16 appears in dnf repolist
- dnf can query postgresql16 packages
- PGDG repo has valid baseurl
- Backup repo file cleaned up

---

## Interview Discussion Points

1. **How do you install the PGDG repository on a fresh CentOS/RHEL server?** - Install the repo RPM: `sudo dnf install -y https://download.postgresql.org/pub/repos/yum/repopackages/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm`. This drops the repo file into `/etc/yum.repos.d/`. Then disable the built-in PostgreSQL module with `sudo dnf -qy module disable postgresql` to avoid conflicts with the distro's older version.

2. **What is the difference between PGDG packages and distro packages?** - Distro packages (AppStream) are maintained by Red Hat/CentOS and are often one or two major versions behind. PGDG packages are maintained by the PostgreSQL community, track the latest releases, and install to version-specific directories (`/usr/pgsql-16/`). PGDG packages are the standard for production use. Never mix the two.

3. **How would you fix this if you did not have internet access?** - Download the RPM packages on a machine with internet access, transfer them via SCP, and install with `dnf localinstall`. Alternatively, set up a local mirror using `reposync` and point the repo file to a local or NFS path. Air-gapped environments should have a local RPM repository as part of their infrastructure.

4. **What does `dnf clean all` actually remove?** - It removes cached package files (`/var/cache/dnf/*/packages/`), repository metadata (`repodata/`), and other cached data. It does not remove installed packages or modify repo configuration files. After cleaning, the next `dnf` command re-downloads metadata from the configured URLs.

5. **How would you handle this on a system using dnf modules?** - On RHEL 8+/CentOS Stream 9, PostgreSQL is also available via dnf modules (`dnf module list postgresql`). If the PGDG repo is broken but you need PG urgently, you could temporarily enable the AppStream module. However, the module version is typically older. The correct fix is always to restore the PGDG repo. Run `dnf module disable postgresql` to ensure the AppStream module does not conflict with PGDG packages.
