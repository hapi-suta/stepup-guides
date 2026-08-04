# Exercise 06: Cross-Platform Cluster Management

PostgreSQL runs on many operating systems. The commands you learned in this module are CentOS/RHEL-specific. In production, you will encounter Ubuntu/Debian servers just as often. This exercise teaches you the Debian tools so you are not lost when you SSH into an Ubuntu box.

**Duration:** 20 min
**Server:** Reference exercise (read and compare). Hands-on practice on the Ubuntu server when available.

---

## 1. The Two Worlds

CentOS/RHEL and Ubuntu/Debian handle PostgreSQL cluster management very differently. CentOS gives you raw tools (`initdb`, `pg_ctl`, manual systemd units). Ubuntu wraps everything in a higher-level toolkit called `postgresql-common`.

| Concept | CentOS/RHEL (this lab) | Ubuntu/Debian |
|---------|----------------------|---------------|
| Package manager | `dnf` / `yum` | `apt` |
| PG repository | PGDG Yum repo | PGDG Apt repo |
| Install command | `dnf install postgresql16-server` | `apt install postgresql-16` |
| Auto-init on install | No (you run `initdb` manually) | Yes (`pg_createcluster` runs automatically) |
| Config location | `/opt/pgsql/data/postgresql.conf` (or `/opt/pgsql/data/`) | `/etc/postgresql/16/main/postgresql.conf` |
| Data directory | You choose (we use `/opt/pgsql/data`) | `/var/lib/postgresql/16/main/` |
| Service name | `postgresql-16` | `postgresql@16-main` |
| systemd unit | One unit per version | One unit per version-cluster pair |

> **Concept: Why the difference?** - CentOS follows upstream PostgreSQL conventions closely. Ubuntu's `postgresql-common` package adds a management layer that handles multiple clusters per version automatically. Neither is "better" - CentOS gives you more control, Ubuntu gives you more convenience. A senior DBA must know both.

---

## 2. The Ubuntu Cluster Tools

Ubuntu provides four commands that have no CentOS equivalent:

### pg_lsclusters - List all clusters

```bash
pg_lsclusters
```

Expected output on Ubuntu:
```
Ver Cluster Port Status Owner    Data directory                  Log file
16  main    5432 online postgres /var/lib/postgresql/16/main      /var/log/postgresql/postgresql-16-main.log
15  main    5433 online postgres /var/lib/postgresql/15/main      /var/log/postgresql/postgresql-15-main.log
```

This single command shows every cluster on the server - version, name, port, status, and paths. On CentOS, you would need to check each systemd service individually.

**CentOS equivalent (manual):**

```bash
sudo systemctl list-units 'postgresql*' --type=service --all
```

Expected output (yours will differ):
```
  UNIT                     LOAD   ACTIVE SUB     DESCRIPTION
  postgresql-16.service    loaded active running PostgreSQL 16 database server
...
```

Then for each service, check its PGDATA, port, and status separately.

### pg_createcluster - Create a new cluster

```bash
sudo pg_createcluster 16 test --port=5435
```

This creates a new PostgreSQL 16 cluster named "test" listening on port 5435. It does everything that takes 5-6 steps on CentOS:
1. Creates the data directory at `/var/lib/postgresql/16/test/`
2. Runs `initdb` with the system locale
3. Sets the port in `postgresql.conf`
4. Creates a systemd service unit (`postgresql@16-test`)
5. Configures log rotation

**CentOS equivalent (manual):**

```bash
sudo mkdir -p /opt/pgsql/data-test
```

```bash
sudo chown postgres:postgres /opt/pgsql/data-test
```

```bash
sudo chmod 700 /opt/pgsql/data-test
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data-test
```

```bash
exit
```

Then manually edit `postgresql.conf` for the port, create a systemd unit file, and run `daemon-reload`.

### pg_dropcluster - Remove a cluster

```bash
sudo pg_dropcluster 16 test --stop
```

This stops the cluster and then removes the data directory, the systemd unit, and the log file in one command. The `--stop` flag stops the cluster before removing it.

**CentOS equivalent (manual):**

```bash
sudo systemctl stop postgresql-16-test
```

```bash
sudo systemctl disable postgresql-16-test
```

```bash
sudo rm /etc/systemd/system/postgresql-16-test.service
```

```bash
sudo systemctl daemon-reload
```

```bash
sudo rm -rf /opt/pgsql/data-test
```

### pg_ctlcluster - Start/stop/restart a specific cluster

```bash
sudo pg_ctlcluster 16 main start
```

```bash
sudo pg_ctlcluster 16 test stop
```

```bash
sudo pg_ctlcluster 16 main reload
```

**CentOS equivalent:**

```bash
sudo systemctl start postgresql-16
```

```bash
sudo systemctl stop postgresql-16-test
```

```bash
sudo systemctl reload postgresql-16
```

The CentOS version is similar here - `pg_ctlcluster` is mostly a convenience wrapper around `systemctl` on modern Ubuntu.

---

## 3. Config File Location Differences

This is the most confusing difference for DBAs who switch between platforms.

### CentOS/RHEL

Config files live inside the data directory (or wherever PGDATA points):

```
/opt/pgsql/data/
  postgresql.conf
  postgresql.auto.conf
  pg_hba.conf
  pg_ident.conf
  conf.d/            (if you created it)
```

### Ubuntu/Debian

Config files are separated from the data directory:

```
/etc/postgresql/16/main/       <-- Config files (editable)
  postgresql.conf
  pg_hba.conf
  pg_ident.conf
  conf.d/                      <-- Already exists by default!

/var/lib/postgresql/16/main/   <-- Data directory (PGDATA)
  base/
  global/
  pg_wal/
  postgresql.auto.conf         <-- Only auto.conf stays in PGDATA
```

> **Concept: Config separation on Debian** - Ubuntu separates config from data so that sysadmins can back up `/etc/` (config) and `/var/lib/` (data) independently. It also means you can `apt upgrade postgresql-16` without worrying about config files being overwritten - they live in `/etc/`, not in the package-managed directory. The `conf.d/` directory exists by default on Ubuntu, with an `include_dir` already in `postgresql.conf`.

### How to find the active config on any platform

No matter which OS you are on, this query always works:

```sql
SHOW config_file;
```

Expected output (CentOS):
```
         config_file
------------------------------
 /opt/pgsql/data/postgresql.conf
(1 row)
```

Expected output (Ubuntu):
```
              config_file
---------------------------------------
 /etc/postgresql/16/main/postgresql.conf
(1 row)
```

This works regardless of OS because PostgreSQL itself knows where its config was loaded from.

Also useful:

```sql
SHOW data_directory;
```

```sql
SHOW hba_file;
```

These queries eliminate guesswork on any platform.

---

## 4. Package Naming Differences

| Purpose | CentOS/RHEL | Ubuntu/Debian |
|---------|-------------|---------------|
| Server | `postgresql16-server` | `postgresql-16` |
| Client | `postgresql16` | `postgresql-client-16` |
| Contrib extensions | `postgresql16-contrib` | `postgresql-16-contrib` (note the `-16-` not `16`) |
| Dev headers | `postgresql16-devel` | `postgresql-server-dev-16` |
| Common tools | (none) | `postgresql-common` |

Notice the naming pattern: CentOS uses `postgresql16` (no dash before version). Ubuntu uses `postgresql-16` (dash before version).

---

## 5. Service Management Comparison

### Check if PostgreSQL is running

**CentOS:**
```bash
sudo systemctl status postgresql-16
```

**Ubuntu:**
```bash
sudo systemctl status postgresql@16-main
```

The service name follows the `postgresql@version-cluster` pattern, so a cluster named "main" on version 16 becomes `postgresql@16-main`.

Or the Ubuntu shortcut:
```bash
pg_lsclusters
```

### Enable auto-start on boot

**CentOS:**
```bash
sudo systemctl enable postgresql-16
```

This registers the service to start automatically when the server boots.

**Ubuntu:**
```bash
sudo systemctl enable postgresql@16-main
```

Ubuntu auto-enables on `apt install`, so you rarely need this command.

### Check logs

**CentOS:**
```bash
sudo tail -50 /opt/pgsql/log/postgresql-*.log
```

Or:
```bash
sudo journalctl -u postgresql-16 --no-pager -n 50
```

`-u` filters by systemd unit name. `--no-pager` prints directly to terminal. `-n 50` shows only the last 50 lines.

**Ubuntu:**
```bash
sudo tail -50 /var/log/postgresql/postgresql-16-main.log
```

> **Concept: Log location** - CentOS logs wherever `log_directory` points (we configured `/opt/pgsql/log/`). Ubuntu defaults to `/var/log/postgresql/` with automatic log rotation via `logrotate`. Both use `journalctl` for systemd logs, but the primary PostgreSQL log file location differs.

---

## 6. Quick Reference Card

Print this and keep it nearby when switching between platforms:

| Task | CentOS/RHEL | Ubuntu/Debian |
|------|-------------|---------------|
| Install PG16 | `dnf install postgresql16-server` | `apt install postgresql-16` |
| Init cluster | `initdb -D /path` | `pg_createcluster 16 name` (or automatic) |
| List clusters | `systemctl list-units 'postgresql*'` | `pg_lsclusters` |
| Start | `systemctl start postgresql-16` | `pg_ctlcluster 16 main start` |
| Stop | `systemctl stop postgresql-16` | `pg_ctlcluster 16 main stop` |
| Reload | `systemctl reload postgresql-16` | `pg_ctlcluster 16 main reload` |
| Status | `systemctl status postgresql-16` | `pg_lsclusters` |
| Drop cluster | Manual (stop + rm) | `pg_dropcluster 16 name --stop` |
| Config file | `/opt/pgsql/data/postgresql.conf` | `/etc/postgresql/16/main/postgresql.conf` |
| Data dir | `/opt/pgsql/data/` | `/var/lib/postgresql/16/main/` |
| Log file | `/opt/pgsql/log/` | `/var/log/postgresql/` |
| DB user | `sudo -iu postgres` | `sudo -iu postgres` |
| Find config | `SHOW config_file;` | `SHOW config_file;` |

---

## Checkpoint

After reviewing this exercise, you should be able to answer:

- [ ] What does `pg_lsclusters` do and why doesn't CentOS have it?
- [ ] How does `pg_createcluster` compare to manually running `initdb` + systemd setup?
- [ ] Where are config files stored on Ubuntu vs CentOS?
- [ ] Why does Ubuntu separate config from data?
- [ ] What query works on ANY platform to find the active config file?
- [ ] What is the Ubuntu service name pattern? (`postgresql@version-cluster`)

---

**You have completed all USE exercises for Module 04.**
