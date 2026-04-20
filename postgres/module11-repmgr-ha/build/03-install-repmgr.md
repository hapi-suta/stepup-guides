# Build 03: Install repmgr

Install repmgr 5.4 on all four nodes and create the repmgr extension on the primary.

---

## 1. Install repmgr on ALL FOUR servers

```bash
apt install -y postgresql-16-repmgr
```

Verify:
```bash
repmgr --version
```

Expected: `repmgr 5.4.x`.

> **Concept - What is repmgr**: repmgr is a suite of open-source tools for
> managing PostgreSQL replication and failover. It wraps native streaming
> replication with a metadata layer (stored in a dedicated database) and
> provides commands for cloning standbys, registering nodes, performing
> switchovers, and - through the repmgrd daemon - automatic failover.

## 2. Create the repmgr user and database (NODE1 only)

On NODE1 (primary):

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
createuser -s repmgr
```

The `-s` flag makes the new user a superuser.

```bash
createdb repmgr -O repmgr
```

The `-O` flag sets the owner of the new database.

Verify:

```bash
psql -c "SELECT rolname, rolsuper FROM pg_roles WHERE rolname = 'repmgr';"
```

```bash
psql -c "SELECT datname FROM pg_database WHERE datname = 'repmgr';"
```

```bash
exit
```

**You are now back to root.**

Expected: `repmgr | t` and `repmgr` database exists.

> **Concept - Why repmgr needs a superuser**: repmgr performs operations that
> require elevated privileges: creating extensions, modifying replication
> settings, promoting standbys, and executing pg_rewind. In production, you
> can use a non-superuser with specific grants, but superuser simplifies the
> lab setup.

## 3. Install the repmgr extension (NODE1 only)

On NODE1:

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -d repmgr -c "CREATE EXTENSION repmgr;"
```

Verify:

```bash
psql -d repmgr -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'repmgr';"
```

```bash
exit
```

**You are now back to root.**

Expected: `repmgr | 5.4`.

> **Concept - The repmgr extension**: This creates the `repmgr` schema in the
> repmgr database. It contains tables like `repmgr.nodes` (cluster membership),
> `repmgr.events` (event log), and `repmgr.monitoring_history` (health metrics).
> When you clone standbys later, the repmgr database replicates to them
> automatically through streaming replication.

## 4. Configure pg_hba.conf for repmgr (NODE1 only for now)

On NODE1, edit `/etc/postgresql/16/main/pg_hba.conf` and add these lines
BEFORE any restrictive rules:

```bash
cat >> /etc/postgresql/16/main/pg_hba.conf <<EOF

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
EOF
```

Reload:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -c "SELECT pg_reload_conf();"
```

```bash
exit
```

**You are now back to root.**

> **Concept - Trust auth for repmgr**: We use `trust` authentication for the
> repmgr user because repmgrd and repmgr CLI tools need to connect without
> password prompts. In production, you would use `.pgpass` files with
> scram-sha-256 or certificate-based auth. For this lab, trust is acceptable
> because the firewall limits access to cluster nodes.

## 5. Test repmgr connectivity from NODE1

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

**You are now back to root.**

---

## Checkpoint

All four servers have:
- [x] repmgr 5.4 installed (`postgresql-16-repmgr` package)

NODE1 (primary) additionally has:
- [x] `repmgr` superuser role created
- [x] `repmgr` database created, owned by repmgr
- [x] `repmgr` extension installed in the repmgr database
- [x] pg_hba.conf allows repmgr and replication connections from all nodes
- [x] `repmgr` user can connect without password

Proceed to `04-configure-primary.md`.
