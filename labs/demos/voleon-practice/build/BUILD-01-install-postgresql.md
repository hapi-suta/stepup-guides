# Build Guide 01: Install and Configure PostgreSQL 17

| | |
|---|---|
| **Time** | 30 minutes |
| **Server** | pg-primary (3.90.199.62) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn
- How to connect to a remote Linux server via SSH
- How to install PostgreSQL 17 from the official PGDG repository
- How to initialize a database cluster
- How to configure PostgreSQL for replication readiness
- How to start and enable the PostgreSQL service

## Prerequisites
- SSH key at `~/.ssh/id_ed25519` with access to pg-primary
- A terminal on your local machine (Mac: Terminal or iTerm2, Windows: PowerShell or PuTTY)
- Basic familiarity with Linux commands (helpful but not required)

---

## Step 1: Connect to pg-primary via SSH

Open your terminal on your local machine and run:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

The `-i` flag tells SSH which private key file to use for authentication. `ec2-user` is the default admin user on this CentOS instance.

Expected output (yours will differ):
```
The authenticity of host '3.90.199.62 (3.90.199.62)' can't be established.
ED25519 key fingerprint is SHA256:abc123...
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '3.90.199.62' (ED25519) to the list of known hosts.
[ec2-user@pg-primary ~]$
```

Type `yes` when prompted about the host fingerprint. You will only see this prompt the first time.

---

## Step 2: Update System Packages

On **pg-primary**, as **ec2-user**:

```bash
sudo dnf update -y
```

`dnf` is the package manager on CentOS Stream 9. The `update` subcommand downloads and installs all available package updates. The `-y` flag automatically answers "yes" to all prompts so you do not need to confirm each update.

This may take a few minutes depending on how many updates are available.

Expected output (yours will differ):
```
CentOS Stream 9 - BaseOS                        12 MB/s |  11 MB     00:00
CentOS Stream 9 - AppStream                     18 MB/s |  19 MB     00:01
...
Complete!
```

---

## Step 3: Install the PGDG Repository

On **pg-primary**, as **ec2-user**:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

This installs the PostgreSQL Global Development Group (PGDG) repository definition file. Without this, `dnf` would only be able to install the older version of PostgreSQL that ships with CentOS, not the latest PostgreSQL 17. The URL points directly to a `.rpm` package hosted on the official PostgreSQL servers.

Expected output (yours will differ):
```
pgdg-redhat-repo-latest.noarch.rpm              134 kB/s |  10 kB     00:00
Dependencies resolved.
...
Installed:
  pgdg-redhat-repo-42.0-38PGDG.noarch
Complete!
```

---

## Step 4: Disable the Built-in PostgreSQL Module

On **pg-primary**, as **ec2-user**:

```bash
sudo dnf -qy module disable postgresql
```

CentOS Stream 9 ships with a built-in "AppStream module" for an older version of PostgreSQL. If this module is not disabled, it can conflict with the PGDG packages we want to install. The `-q` flag suppresses extra output, and `-y` automatically confirms the action.

Expected output (yours will differ):
```
[ec2-user@pg-primary ~]$
```

No output means it ran successfully.

---

## Step 5: Install PostgreSQL 17 Server and Contrib

On **pg-primary**, as **ec2-user**:

```bash
sudo dnf install -y postgresql17-server postgresql17-contrib
```

`postgresql17-server` is the core PostgreSQL 17 server package. `postgresql17-contrib` is a collection of additional utility modules and extensions (such as `pg_stat_statements`) that are not included in the base package but are very commonly used.

Expected output (yours will differ):
```
Dependencies resolved.
...
Installing:
 postgresql17           x86_64  17.x-1PGDG.rhel9  pgdg17  ...
 postgresql17-contrib   x86_64  17.x-1PGDG.rhel9  pgdg17  ...
 postgresql17-libs      x86_64  17.x-1PGDG.rhel9  pgdg17  ...
...
Complete!
```

---

## Step 6: Initialize the Database Cluster

On **pg-primary**, as **ec2-user**:

```bash
sudo /usr/pgsql-17/bin/postgresql-17-setup initdb
```

`initdb` creates the initial directory structure and system catalog files that PostgreSQL needs before it can start. This only needs to be done once. It sets up `/var/lib/pgsql/17/data/` as the data directory. We call it through the full path `/usr/pgsql-17/bin/` because the PGDG binaries live there, separate from any system PostgreSQL.

Expected output (yours will differ):
```
Initializing database ... OK
```

---

## Step 7: Configure postgresql.conf

The main configuration file is at `/var/lib/pgsql/17/data/postgresql.conf`. You will edit it using `vi`.

On **pg-primary**, as **ec2-user**:

```bash
sudo vi /var/lib/pgsql/17/data/postgresql.conf
```

`vi` is a terminal-based text editor. The file will open and you will see the default configuration with many commented-out lines (lines starting with `#`).

You need to find and update (or add) each setting listed below. For each one, use the search feature in `vi`:

- Press `/` to open the search prompt
- Type the setting name (e.g., `listen_addresses`) and press `Enter`
- Press `n` to jump to the next match if needed
- Press `i` to enter insert mode so you can edit
- Make your change
- Press `Esc` to exit insert mode

When you have made all changes, save and quit:

- Press `Esc`
- Type `:wq` and press `Enter`

Set or update each of the following lines. If the line exists and is commented out (starts with `#`), remove the `#` and update the value. If the line does not exist, you can add it at the bottom of the file.

```
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = '512MB'
effective_cache_size = '1536MB'
maintenance_work_mem = '128MB'
wal_level = 'replica'
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = '256MB'
hot_standby = on
archive_mode = on
archive_command = '/bin/true'
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%a.log'
log_statement = 'ddl'
log_min_duration_statement = 1000
shared_preload_libraries = 'pg_stat_statements'
password_encryption = 'scram-sha-256'
```

What these settings mean:

- `listen_addresses = '*'` - Accept connections on all network interfaces, not just localhost.
- `port = 5432` - The TCP port PostgreSQL listens on (5432 is the standard default).
- `max_connections = 200` - Maximum number of simultaneous client connections.
- `shared_buffers = '512MB'` - Memory allocated to PostgreSQL for caching data pages; a key performance setting.
- `effective_cache_size = '1536MB'` - Tells the query planner how much total memory is available for disk caching (OS + PostgreSQL combined).
- `maintenance_work_mem = '128MB'` - Memory used for maintenance operations like VACUUM, CREATE INDEX, and REINDEX.
- `wal_level = 'replica'` - Sets the level of information written to WAL; `replica` is required for streaming replication.
- `max_wal_senders = 10` - Maximum number of concurrent connections from standby servers or replication tools.
- `max_replication_slots = 10` - Maximum number of replication slots (used by standbys and logical replication consumers).
- `wal_keep_size = '256MB'` - Minimum amount of WAL to keep on disk so standbys that fall behind can catch up.
- `hot_standby = on` - Allows read queries on a standby server while it is applying WAL from the primary.
- `archive_mode = on` - Enables WAL archiving (required for point-in-time recovery setups).
- `archive_command = '/bin/true'` - Placeholder archive command; `true` always succeeds without doing anything, which is fine for this lab.
- `log_destination = 'stderr'` - Sends log output to standard error, which `logging_collector` then captures.
- `logging_collector = on` - Enables the background process that captures log output to files.
- `log_directory = 'log'` - Subdirectory under the data directory where log files are written.
- `log_filename = 'postgresql-%a.log'` - Log file name pattern; `%a` is the abbreviated weekday name, so you get one file per day of the week.
- `log_statement = 'ddl'` - Logs all DDL statements (CREATE, ALTER, DROP) for auditing.
- `log_min_duration_statement = 1000` - Logs any query that takes longer than 1000 milliseconds (1 second) so you can identify slow queries.
- `shared_preload_libraries = 'pg_stat_statements'` - Loads the `pg_stat_statements` extension at startup, which tracks query performance statistics.
- `password_encryption = 'scram-sha-256'` - Uses the stronger SCRAM-SHA-256 method for storing and verifying passwords.

---

## Step 8: Configure pg_hba.conf

`pg_hba.conf` controls who is allowed to connect to PostgreSQL and how they authenticate. It is at `/var/lib/pgsql/17/data/pg_hba.conf`.

You will replace the default contents entirely with a clean, known-good configuration.

On **pg-primary**, as **ec2-user**:

```bash
sudo vi /var/lib/pgsql/17/data/pg_hba.conf
```

First, delete all existing content:

- Press `Esc` to make sure you are in normal mode
- Type `gg` to jump to the first line
- Type `dG` to delete from the first line to the last line (this clears the entire file)

Now press `i` to enter insert mode and type the following exactly:

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Allow the postgres OS user to connect locally without a password
local   all             postgres                                peer

# Allow all other local connections using password (scram-sha-256)
local   all             all                                     scram-sha-256

# Allow all remote connections using password (scram-sha-256)
host    all             all             0.0.0.0/0               scram-sha-256

# Allow replication connections from any host (password still required)
host    replication     replicator      0.0.0.0/0               scram-sha-256
```

What each line means:

- `local all postgres peer` - The `postgres` OS user can connect to any database over a local Unix socket using "peer" authentication (no password needed; the OS identity is trusted).
- `local all all scram-sha-256` - All other local connections require a password, verified using SCRAM-SHA-256.
- `host all all 0.0.0.0/0 scram-sha-256` - TCP connections from any IP address are allowed but require a SCRAM-SHA-256 password. This covers application servers and your workstation.
- `host replication replicator 0.0.0.0/0 scram-sha-256` - Any host can attempt a replication connection as the `replicator` user, but the SCRAM-SHA-256 password is still required.

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

---

## Step 9: Start and Enable PostgreSQL

On **pg-primary**, as **ec2-user**:

Start the service:

```bash
sudo systemctl start postgresql-17
```

`systemctl start` launches the service right now. The service name `postgresql-17` matches the package you installed.

Enable the service so it starts automatically on every server reboot:

```bash
sudo systemctl enable postgresql-17
```

`systemctl enable` creates the systemd links that cause the service to start at boot. Without this, PostgreSQL would not restart after a reboot.

Expected output (yours will differ):
```
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-17.service
  -> /usr/lib/systemd/system/postgresql-17.service.
```

---

## Step 10: Verify PostgreSQL is Running

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl status postgresql-17
```

This shows the current state of the service, including whether it is active, how long it has been running, and the most recent log lines.

Expected output (yours will differ):
```
* postgresql-17.service - PostgreSQL 17 Database Server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled; ...)
     Active: active (running) since Sun 2026-06-15 14:23:11 UTC; 5s ago
    Process: 12345 ExecStartPre=... (code=exited, status=0/SUCCESS)
   Main PID: 12350 (postmaster)
      Tasks: 7 (limit: 4680)
...
```

Look for `Active: active (running)`. If you see `failed` or `inactive`, check Step 7 and Step 8 for typos in your config files.

---

## Step 11: Connect and Verify the Version

Now switch to the `postgres` operating system user to run `psql`:

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

`sudo su - postgres` switches your session to the `postgres` OS user. The `-` means a login shell, which loads the correct environment variables for that user. This is needed because `pg_hba.conf` uses `peer` authentication for the `postgres` user over local sockets - it checks that the OS user matches the database user.

You should now see a prompt like:

```
-bash-5.1$
```

Now connect to PostgreSQL:

```bash
psql
```

`psql` is the PostgreSQL interactive terminal. Because you are already the `postgres` OS user, it connects as the `postgres` database superuser automatically via peer authentication.

Expected output (yours will differ):
```
psql (17.x)
Type "help" for help.

postgres=#
```

Verify the version:

```sql
SELECT version();
```

Expected output (yours will differ):
```
                         version
----------------------------------------------------------
 PostgreSQL 17.x on x86_64-pc-linux-gnu, compiled by gcc...
(1 row)
```

Check that your settings from Step 7 are active:

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW shared_preload_libraries;
```

Expected output (yours will differ):
```
 wal_level
-----------
 replica
(1 row)

 max_wal_senders
-----------------
 10
(1 row)

 shared_preload_libraries
--------------------------
 pg_stat_statements
(1 row)
```

Exit psql:

```sql
\q
```

Exit the postgres user session:

```bash
exit
```

You are now back as `ec2-user`.

---

## Summary

You have:
- Installed PostgreSQL 17 from the official PGDG repository
- Initialized the data directory
- Configured `postgresql.conf` for replication readiness and observability
- Set up `pg_hba.conf` with secure, explicit access rules
- Started and enabled the service
- Verified the installation

The server is now ready for the next build guide where you will create the `quantdb` database and schema.
