# Module 03 - Guide 02: Multi-Version Installation

In production, you will often need multiple PostgreSQL versions running on the same server. Common reasons include testing upgrades before committing, running different applications on different versions, or preparing for a major-version migration.

In this guide, you will install PostgreSQL 15 alongside your existing PostgreSQL 16 - without touching your PG16 cluster.

**Prerequisites:**
- CentOS Stream 9 with PostgreSQL 16 installed and running on port 5432
- PG16 binary path: `/usr/pgsql-16/bin/`
- PG16 data directory: `/opt/pgsql/data`
- Root or sudo access

---

## 1. Install PostgreSQL 15 Packages

The PGDG repository you used for PG16 already contains packages for older versions. You just need to install the PG15 packages.

Install the PostgreSQL 15 server and client packages:

```bash
sudo dnf install -y postgresql15-server postgresql15
```

This installs two packages:
- `postgresql15-server` - the database server, initdb, and pg_ctl utilities
- `postgresql15` - the psql client and other command-line tools

**Expected output (last few lines):**
```
Installed:
  postgresql15-15.x.x-1PGDG.rhel9.x86_64
  postgresql15-server-15.x.x-1PGDG.rhel9.x86_64

Complete!
```

Verify both packages installed correctly:

```bash
rpm -q postgresql15-server postgresql15
```

The `rpm -q` command queries the RPM database to confirm a package is installed. It prints the full package name and version.

**Expected output:**
```
postgresql15-server-15.x.x-1PGDG.rhel9.x86_64
postgresql15-15.x.x-1PGDG.rhel9.x86_64
```

Confirm the PG15 binaries landed in their own directory:

```bash
ls /usr/pgsql-15/bin/postgres
```

**Expected output:**
```
/usr/pgsql-15/bin/postgres
```

> **Concept: Side-by-Side Binaries**
>
> PGDG packages install each major version into its own directory tree under `/usr/pgsql-{version}/`. This means PG15 binaries live in `/usr/pgsql-15/bin/` and PG16 binaries live in `/usr/pgsql-16/bin/`. They never collide, and you can have as many versions installed as you want.

---

## 2. Create the PG15 Data Directory

Each PostgreSQL cluster needs its own data directory. Your PG16 cluster uses `/opt/pgsql/data`. You will create a separate directory for PG15.

Create the data directory for PG15:

```bash
sudo mkdir -p /opt/pgsql/data15
```

The `-p` flag tells `mkdir` to create parent directories if they do not exist and to not error if the directory already exists.

Set ownership to the `postgres` OS user:

```bash
sudo chown postgres:postgres /opt/pgsql/data15
```

The `chown` command changes the owner and group. PostgreSQL refuses to start if the data directory is not owned by the user running the server.

Set permissions to 700 (owner-only access):

```bash
sudo chmod 700 /opt/pgsql/data15
```

The `chmod 700` command gives read, write, and execute permissions to the owner only. PostgreSQL requires this - it will refuse to start if the data directory is accessible to other users.

Verify the directory looks correct:

```bash
ls -ld /opt/pgsql/data15
```

**Expected output:**
```
drwx------. 2 postgres postgres 6 Apr 18 10:00 /opt/pgsql/data15
```

Confirm `drwx------` (700 permissions) and `postgres postgres` (correct ownership).

---

## 3. Initialize the PG15 Cluster

Initializing a cluster creates the system catalogs, default configuration files, and the directory structure PostgreSQL needs to run.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Run `initdb` using the PG15 binary and point it at the new data directory:

```bash
/usr/pgsql-15/bin/initdb -D /opt/pgsql/data15
```

The `-D` flag specifies the data directory where the new cluster will live. You must use the full path to the PG15 `initdb` binary - if you just type `initdb`, your shell might pick up the PG16 version from your PATH.

**Expected output (key lines):**
```
The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.

The database cluster will be initialized with locale "en_US.UTF-8".
The default database encoding has accordingly been set to "UTF8".
The default text search configuration will be set to "english".

Data page checksums are disabled.

...

Success. You can now start the database server using:

    /usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l logfile start
```

> **Concept: What initdb Actually Creates**
>
> When you run `initdb`, PostgreSQL creates the entire directory structure a cluster needs to run: the `base/` directory for table data, `pg_wal/` for write-ahead logs, `pg_xact/` for transaction status, and the configuration files `postgresql.conf`, `pg_hba.conf`, and `pg_ident.conf`. Every cluster - regardless of version - follows this same layout.

Exit back to your regular user:

```bash
exit
```

---

## 4. Configure PG15 to Use a Different Port

By default, PostgreSQL listens on port 5432. Your PG16 cluster already uses that port, so PG15 must use a different one. You will set it to port 5433.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Open the PG15 configuration file:

```bash
vi /opt/pgsql/data15/postgresql.conf
```

Find the line that reads:

```
#port = 5432
```

Change it to (remove the `#` and change the value):

```
port = 5433
```

While you are in the file, also find:

```
#listen_addresses = 'localhost'
```

Change it to:

```
listen_addresses = 'localhost'
```

The `port` setting tells PostgreSQL which TCP port to listen on. The `listen_addresses` setting controls which network interfaces accept connections. Setting it to `localhost` means only local connections are allowed - safe for a lab environment.

Save and exit vi (`:wq`).

> **Concept: Port Separation**
>
> Every PostgreSQL cluster on the same server must use a unique port. The convention is to increment by one for each additional cluster: 5432, 5433, 5434, and so on. When connecting with `psql`, you specify the port with `-p 5433` to reach the right cluster.

Verify your change took effect:

```bash
grep -n "^port" /opt/pgsql/data15/postgresql.conf
```

The `grep -n` command searches for lines starting with `port` and shows the line number. The `^` means "start of line" so it skips commented lines.

**Expected output:**
```
64:port = 5433
```

The line number may differ, but you should see `port = 5433` without a leading `#`.

Exit back to your regular user:

```bash
exit
```

---

## 5. Create and Configure the PG15 Systemd Service

CentOS uses systemd to manage services. The PGDG packages install a systemd unit file for PG15, but it points to the default data directory. You need to edit it to point to `/opt/pgsql/data15`.

Open the full unit file for editing:

```bash
sudo systemctl edit --full postgresql-15
```

The `--full` flag opens the complete unit file for editing rather than creating a drop-in override. This gives you full control over every setting.

Find the line that sets the `Environment` variable for PGDATA. It will look something like:

```
Environment=PGDATA=/var/lib/pgsql/15/data/
```

Change it to:

```
Environment=PGDATA=/opt/pgsql/data15/
```

Also find the `Description` line and update it so you can tell the services apart:

```
Description=PostgreSQL 15 database server (port 5433)
```

Save and exit vi (`:wq`).

> **Concept: systemctl edit --full vs. Drop-in Overrides**
>
> Running `systemctl edit --full <service>` copies the vendor unit file into `/etc/systemd/system/` and opens it for editing. This file takes priority over the package-installed version in `/usr/lib/systemd/system/`. If the package is updated, your custom file is preserved - but you will not automatically get any new settings from the updated package unit. For most PostgreSQL setups, this trade-off is fine because you want stable, predictable configuration.

Reload systemd so it picks up the changes:

```bash
sudo systemctl daemon-reload
```

The `daemon-reload` command tells systemd to re-read all unit files. You must run this every time you modify a unit file, or systemd will keep using the old version in memory.

---

## 6. Start PG15 and Verify Both Versions Running

Now start the PG15 service:

```bash
sudo systemctl start postgresql-15
```

Check that PG15 started without errors:

```bash
sudo systemctl status postgresql-15
```

**Expected output (key lines):**
```
  postgresql-15.service - PostgreSQL 15 database server (port 5433)
     Loaded: loaded (/etc/systemd/system/postgresql-15.service; ...)
     Active: active (running) since ...
```

Confirm `Active: active (running)`. If it says `failed`, check the logs with `sudo journalctl -u postgresql-15 --no-pager -n 20`.

Now verify both clusters are accepting connections. Check PG16 on port 5432:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

The `pg_isready` command checks whether a PostgreSQL server is accepting connections. The `-p` flag specifies the port to check. We use the full path because `pg_isready` is not in ec2-user's PATH by default.

**Expected output:**
```
/var/run/postgresql:5432 - accepting connections
```

Check PG15 on port 5433:

```bash
/usr/pgsql-15/bin/pg_isready -p 5433
```

**Expected output:**
```
/var/run/postgresql:5433 - accepting connections
```

> **Concept: pg_isready for Health Checks**
>
> `pg_isready` is a lightweight connection check that does not require authentication. It returns exit code 0 if the server is accepting connections. This makes it ideal for scripting, monitoring, and systemd health checks. In production, you will often see it in load balancer health probes.

Now connect to each cluster and confirm the version. Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to PG16 on port 5432:

```bash
psql -p 5432 -c "SELECT version();"
```

The `-p` flag tells psql which port to connect to. The `-c` flag runs a single SQL command and exits.

**Expected output:**
```
                                                version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

Connect to PG15 on port 5433:

```bash
psql -p 5433 -c "SELECT version();"
```

**Expected output:**
```
                                                version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 15.x.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

Exit back to your regular user:

```bash
exit
```

Enable PG15 to start automatically on boot:

```bash
sudo systemctl enable postgresql-15
```

The `enable` command creates a symlink so systemd starts this service automatically when the server boots. Without this, you would have to manually start PG15 after every reboot.

**Expected output:**
```
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-15.service -> /etc/systemd/system/postgresql-15.service.
```

---

## 7. Compare the Two Installations

You now have two fully independent PostgreSQL clusters on the same server. Here is a side-by-side comparison:

| Setting         | PostgreSQL 16               | PostgreSQL 15               |
|-----------------|-----------------------------|-----------------------------|
| Binary path     | `/usr/pgsql-16/bin/`        | `/usr/pgsql-15/bin/`        |
| Data directory  | `/opt/pgsql/data`           | `/opt/pgsql/data15`         |
| Config file     | `/opt/pgsql/data/postgresql.conf` | `/opt/pgsql/data15/postgresql.conf` |
| Port            | 5432                        | 5433                        |
| Systemd service | `postgresql-16`             | `postgresql-15`             |
| Connect with    | `psql -p 5432`              | `psql -p 5433`              |

> **Concept: Independent Clusters**
>
> Each PostgreSQL cluster is completely independent. They have their own data directories, configuration files, WAL streams, users, and databases. Stopping PG15 has zero effect on PG16, and vice versa. They share only the operating system and hardware resources (CPU, memory, disk I/O). In production, you would typically give each cluster its own dedicated storage to avoid I/O contention.

You can verify both services are running and enabled with one command:

```bash
sudo systemctl list-units --type=service --state=running | grep postgresql
```

This filters the systemd service list to show only running services, then filters for `postgresql` in the name.

**Expected output:**
```
  postgresql-15.service   loaded active running   PostgreSQL 15 database server (port 5433)
  postgresql-16.service   loaded active running   PostgreSQL 16 database server
```

---

## Checkpoint

Before moving on, confirm everything is in place:

- [ ] PG15 packages installed (`rpm -q postgresql15-server postgresql15`)
- [ ] PG15 binaries exist at `/usr/pgsql-15/bin/`
- [ ] PG15 data directory exists at `/opt/pgsql/data15` with `postgres:postgres` ownership and `700` permissions
- [ ] PG15 cluster initialized (check for `postgresql.conf` inside `/opt/pgsql/data15/`)
- [ ] PG15 configured on port 5433 (`grep "^port" /opt/pgsql/data15/postgresql.conf`)
- [ ] PG15 systemd service edited with correct PGDATA (`systemctl cat postgresql-15`)
- [ ] PG16 still running on port 5432 (`/usr/pgsql-16/bin/pg_isready -p 5432`)
- [ ] PG15 running on port 5433 (`/usr/pgsql-15/bin/pg_isready -p 5433`)
- [ ] `SELECT version()` returns PG16 on port 5432 and PG15 on port 5433
- [ ] PG15 enabled for auto-start on boot (`systemctl is-enabled postgresql-15`)

If any check fails, go back to the relevant section and re-do those steps before continuing.

---

**Proceed to Guide 03 - Building from Source**
