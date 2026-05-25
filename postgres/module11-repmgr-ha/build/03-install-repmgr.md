# Build 03: Install repmgr (CentOS Stream 9)

Install repmgr on all four nodes and create the repmgr extension on the primary.

---

## 1. Install repmgr on ALL FOUR servers

```bash
sudo dnf install -y repmgr_16
```

This installs the repmgr package from the PGDG repository. The `_16` suffix means it is built for PostgreSQL 16.

Expected output (yours will differ):
```
Complete!
```

Verify:

```bash
/usr/pgsql-16/bin/repmgr --version
```

Expected output (yours will differ):
```
repmgr 5.4.1
```

> **Important**: On CentOS, the repmgr binary is at `/usr/pgsql-16/bin/repmgr`, not
> just `repmgr`. The PGDG packages install binaries under `/usr/pgsql-16/bin/`.

Add the PostgreSQL 16 bin directory to the postgres user's PATH so you can run `repmgr` without the full path:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
vi ~/.bash_profile
```

Add this line at the bottom:

```
export PATH=/usr/pgsql-16/bin:$PATH
```

Save and exit vi (`:wq`).

Also add the same line to `.bashrc` - this is needed for non-login SSH commands
(repmgr crosscheck SSHes between nodes and runs repmgr remotely):

```bash
vi ~/.bashrc
```

Add this line at the bottom:

```
export PATH=/usr/pgsql-16/bin:$PATH
```

Save and exit vi (`:wq`).

Reload the profile:

```bash
source ~/.bash_profile
```

Verify:

```bash
repmgr --version
```

Expected: `repmgr 5.4.x` - now accessible without the full path.

```bash
exit
```

**You are now back to ec2-user.**

> **Concept - What is repmgr**: repmgr is a suite of open-source tools for
> managing PostgreSQL replication and failover. It wraps native streaming
> replication with a metadata layer (stored in a dedicated database) and
> provides commands for cloning standbys, registering nodes, performing
> switchovers, and - through the repmgrd daemon - automatic failover.

## 2. Enable shared_preload_libraries (ALL FOUR servers)

Now that repmgr is installed, configure PostgreSQL to load it at startup:

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -c "ALTER SYSTEM SET shared_preload_libraries = 'repmgr';"
```

Expected output (yours will differ):
```
ALTER SYSTEM
```

```bash
exit
```

**You are now back to ec2-user.**

Restart PostgreSQL to load the library:

```bash
sudo systemctl restart postgresql-16
```

Verify:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -c "SHOW shared_preload_libraries;"
```

Expected: `repmgr`.

```bash
exit
```

**You are now back to ec2-user.**

> **Concept - shared_preload_libraries = 'repmgr'**: The repmgr extension
> includes a background worker (repmgrd) that monitors cluster health and
> triggers automatic failover. To load background workers, the library must
> be preloaded at server start. Without this setting, the repmgrd daemon
> cannot start. We set it here - after installing repmgr - because PostgreSQL
> will refuse to start if the library file does not exist.

## 3. Create the repmgr user and database (NODE1 only)

On NODE1 (primary):

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
createuser -s repmgr
```

The `-s` flag makes the new user a superuser. repmgr needs superuser privileges to create extensions, modify replication settings, and execute pg_rewind.

```bash
createdb repmgr -O repmgr
```

The `-O` flag sets the owner of the new database to `repmgr`.

Verify:

```bash
psql -c "SELECT rolname, rolsuper FROM pg_roles WHERE rolname = 'repmgr';"
```

Expected output (yours will differ):
```
 rolname | rolsuper
---------+----------
 repmgr  | t
(1 row)
```

```bash
psql -c "SELECT datname FROM pg_database WHERE datname = 'repmgr';"
```

Expected output (yours will differ):
```
 datname
---------
 repmgr
(1 row)
```

```bash
exit
```

**You are now back to ec2-user.**

> **Concept - Why repmgr needs a superuser**: repmgr performs operations that
> require elevated privileges: creating extensions, modifying replication
> settings, promoting standbys, and executing pg_rewind. In production, you
> can use a non-superuser with specific grants, but superuser simplifies the
> lab setup.

## 4. Install the repmgr extension (NODE1 only)

On NODE1:

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -d repmgr -c "CREATE EXTENSION repmgr;"
```

Expected output (yours will differ):
```
CREATE EXTENSION
```

Verify:

```bash
psql -d repmgr -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'repmgr';"
```

Expected output (yours will differ):
```
 extname | extversion
---------+------------
 repmgr  | 5.4
(1 row)
```

```bash
exit
```

**You are now back to ec2-user.**

> **Concept - The repmgr extension**: This creates the `repmgr` schema in the
> repmgr database. It contains tables like `repmgr.nodes` (cluster membership),
> `repmgr.events` (event log), and `repmgr.monitoring_history` (health metrics).
> When you clone standbys later, the repmgr database replicates to them
> automatically through streaming replication.

## 5. Configure pg_hba.conf for repmgr (NODE1 only for now)

On NODE1, edit `/var/lib/pgsql/16/data/pg_hba.conf` and add repmgr access rules.

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
vi /var/lib/pgsql/16/data/pg_hba.conf
```

Add these lines **BEFORE** the default `local all all peer` line (substitute your actual private IPs for the placeholders).

> **Important**: pg_hba.conf is first-match-wins. If you add these after
> `local all all peer`, the peer rule matches first and repmgr connections
> will fail with "Peer authentication failed". The repmgr rules must come first.

```
# repmgr connections
local   repmgr        repmgr                              trust
host    repmgr        repmgr        [NODE1_IP]/32         trust
host    repmgr        repmgr        [NODE2_IP]/32         trust
host    repmgr        repmgr        [NODE3_IP]/32         trust
host    repmgr        repmgr        [NODE4_IP]/32         trust

# replication connections
local   replication   repmgr                              trust
host    replication   repmgr        [NODE1_IP]/32         trust
host    replication   repmgr        [NODE2_IP]/32         trust
host    replication   repmgr        [NODE3_IP]/32         trust
host    replication   repmgr        [NODE4_IP]/32         trust
```

Save and exit vi (`:wq`).

Reload PostgreSQL to apply the new pg_hba.conf rules:

```bash
psql -c "SELECT pg_reload_conf();"
```

Expected output (yours will differ):
```
 pg_reload_conf
----------------
 t
(1 row)
```

```bash
exit
```

**You are now back to ec2-user.**

> **Concept - Trust auth for repmgr**: We use `trust` authentication for the
> repmgr user because repmgrd and repmgr CLI tools need to connect without
> password prompts. In production, you would use `.pgpass` files with
> scram-sha-256 or certificate-based auth. For this lab, trust is acceptable
> because the firewall limits access to cluster nodes.

## 6. Test repmgr connectivity from NODE1

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -d repmgr -U repmgr -c "SELECT 1;"
```

Expected: returns `1` without a password prompt.

```bash
exit
```

**You are now back to ec2-user.**

---

## Checkpoint

All four servers have:
- [x] repmgr installed (`repmgr_16` package)
- [x] `/usr/pgsql-16/bin/` added to postgres user's PATH
- [x] `shared_preload_libraries = 'repmgr'` set and PostgreSQL restarted

NODE1 (primary) additionally has:
- [x] `repmgr` superuser role created
- [x] `repmgr` database created, owned by repmgr
- [x] `repmgr` extension installed in the repmgr database
- [x] pg_hba.conf allows repmgr and replication connections from all nodes
- [x] `repmgr` user can connect without password

Proceed to `04-configure-primary.md`.
