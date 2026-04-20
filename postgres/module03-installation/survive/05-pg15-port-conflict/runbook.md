# Runbook 05: PG15 Port Conflict

## Scenario

A junior DBA changed the PostgreSQL 15 port configuration. Now PG15 refuses to start, while PG16 continues running on port 5432. Diagnose the port conflict and restore PG15 to service on its correct port (5433).

---

## Layer 1: Fix Path

### Step 1 - Check which PostgreSQL instances are running

```bash
sudo systemctl status postgresql-16
```

Expected output:
```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

```bash
sudo systemctl status postgresql-15
```

Expected output:
```
● postgresql-15.service - PostgreSQL 15 database server
     Active: failed (Result: exit-code) since ...
```

> **Concept: Multi-version coexistence** - PostgreSQL supports running multiple major versions side-by-side on the same server. Each version has its own binaries, data directory, and systemd service. They MUST listen on different ports to avoid conflicts.

### Step 2 - Check the PG15 logs for the failure reason

```bash
sudo journalctl -xeu postgresql-15 --no-pager | tail -30
```

`-x` adds explanatory help text. `-e` jumps to the end of the log. `-u` filters to this service. `--no-pager` prints to the terminal.

Expected output (key line):
```
FATAL:  could not bind IPv4 address "0.0.0.0": Address already in use
HINT:  Is another postmaster already running on port 5432? If not, wait a few seconds and retry.
```

### Step 3 - Check what is already listening on port 5432

```bash
sudo ss -tlnp | grep 5432
```

`-t` shows TCP sockets. `-l` shows only listening sockets. `-n` shows port numbers instead of names. `-p` shows which process owns each socket.

Expected output:
```
LISTEN  0  244  0.0.0.0:5432  0.0.0.0:*  users:(("postmaster",pid=XXXX,fd=X))
```

This confirms PG16 already owns port 5432.

> **Concept: Port binding** - Only one process can bind to a given TCP port at a time. When PG15 tries to start on port 5432, the OS rejects the bind() call because PG16 already holds that port. The "Address already in use" error is a socket-level failure, not a PostgreSQL-specific one.

### Step 4 - Check what port PG15 is configured to use

```bash
sudo -iu postgres
```

```bash
grep -E '^port' /opt/pgsql/data15/postgresql.conf
```

Expected output:
```
port = 5432
```

This is the problem - PG15 is set to the same port as PG16.

```bash
exit
```

### Step 5 - Fix the port back to 5433

```bash
sudo -iu postgres
```

```bash
vi /opt/pgsql/data15/postgresql.conf
```

Find the line:
```
port = 5432
```

Change it to:
```
port = 5433
```

Save and exit (`:wq`).

```bash
exit
```

### Step 6 - Start PG15

```bash
sudo systemctl start postgresql-15
```

```bash
sudo systemctl status postgresql-15
```

Expected output:
```
● postgresql-15.service - PostgreSQL 15 database server
     Active: active (running) since ...
```

### Step 7 - Verify both instances respond

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:
```
/var/run/postgresql:5432 - accepting connections
```

```bash
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output:
```
/var/run/postgresql:5433 - accepting connections
```

```bash
exit
```

> **Concept: pg_isready** - This lightweight utility checks whether a PostgreSQL server is accepting connections on a given port. It does not require authentication and returns exit code 0 on success - making it ideal for health checks and scripts.

---

## Layer 2: Revision Concepts

### Why different ports?

When you run multiple PostgreSQL versions on the same host, each instance needs its own:
- **Port** - unique TCP port (e.g., 5432 for PG16, 5433 for PG15)
- **Data directory** - separate PGDATA path
- **Service name** - separate systemd unit
- **Binary path** - version-specific binaries in /usr/pgsql-NN/bin

If any of these overlap, one instance will fail to start or corrupt the other's data.

### How the OS handles port conflicts

1. PG16 starts first and calls `bind(0.0.0.0:5432)` - OS grants it
2. PG15 starts and calls `bind(0.0.0.0:5432)` - OS returns EADDRINUSE
3. PostgreSQL translates this to `FATAL: could not bind IPv4 address`
4. The postmaster exits, systemd marks the unit as failed

### Diagnostic tools for port issues

| Tool | Purpose |
|------|---------|
| `ss -tlnp` | Show listening TCP sockets with process info |
| `pg_isready -p PORT` | Test if PostgreSQL accepts connections on a port |
| `lsof -i :5432` | Show which process holds a specific port |
| `journalctl -xeu SERVICE` | Read systemd journal for a specific service |

> **Concept: ss vs netstat** - The `ss` command (socket statistics) is the modern replacement for `netstat` on CentOS/RHEL systems. The flags `-tlnp` mean: TCP sockets (-t), listening only (-l), numeric ports (-n), show process info (-p). Always use `ss` on modern systems - `netstat` may not even be installed.

### What if you need two instances on the same port?

You can't - not on the same IP address. Options:
- Use different ports (standard approach)
- Bind each instance to a different IP address using the `listen_addresses` parameter
- Use different hosts entirely

> **Concept: listen_addresses vs port** - The `listen_addresses` parameter controls which IP addresses PostgreSQL binds to, while `port` controls the TCP port. Two instances CAN share a port only if they bind to different IP addresses (e.g., one on 127.0.0.1 and one on the server's public IP). In practice, using different ports is simpler and less error-prone.

---

## Layer 3: Interview Discussion Points

1. **How do you set up multi-version PostgreSQL on one server?** - Install each version from PGDG repo (each goes to /usr/pgsql-NN), create separate data directories, assign unique ports, create separate systemd units. The PGDG packages handle most of this automatically.

2. **A service fails to start after a config change - what's your first move?** - Check `systemctl status SERVICE` for the exit code, then `journalctl -xeu SERVICE` for the actual error message. PostgreSQL logs to both the journal and its own log directory.

3. **How would you prevent port conflicts in a CI/CD or automation context?** - Validate the port is free before starting (`ss -tlnp | grep PORT`), use configuration management (Ansible) to enforce port assignments, add pre-start checks in a systemd ExecStartPre directive.

4. **What's the difference between "connection refused" and "address already in use"?** - "Address already in use" happens at start time (server side) - the port is taken. "Connection refused" happens at connect time (client side) - no server is listening. Different failure points, different diagnostics.

5. **How do you manage configuration drift across PostgreSQL instances?** - Use version-controlled postgresql.conf templates, deploy with Ansible or similar tooling, use `ALTER SYSTEM` sparingly (it creates postgresql.auto.conf which can override your managed config), audit with `pg_settings` view.
