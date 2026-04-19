# Scenario 07 - Listen Address Wrong

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start. Service is DOWN.
A team member changed the listen address to accommodate
a new network configuration, but PostgreSQL will not
bind to the address.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **listen_addresses parameter** - Controls which IP addresses PostgreSQL listens on for TCP/IP connections. Common values: `'localhost'` (local only), `'*'` (all interfaces), `'0.0.0.0'` (all IPv4 interfaces), or a specific IP like `'192.168.1.10'`. If you set it to an IP that does not exist on any network interface, PostgreSQL cannot bind a socket and refuses to start with a FATAL error.

- **Socket binding** - When PostgreSQL starts, it calls the OS `bind()` system call to attach to each address in `listen_addresses` on the configured port. The OS checks whether the requested IP exists on a local interface. If it does not, `bind()` returns `EADDRNOTAVAIL` (address not available), and PostgreSQL logs a FATAL error and shuts down. This is an OS-level check - PostgreSQL has no way around it.

- **postgresql.auto.conf and startup failures** - When PostgreSQL fails to start due to a config error, you cannot use SQL commands (like `ALTER SYSTEM RESET`) to fix it because there is no running server to connect to. You must edit the config file on disk. For ALTER SYSTEM changes, that file is `postgresql.auto.conf`. This is one of the most important things to know: if ALTER SYSTEM breaks startup, the only fix is a direct file edit.

- **journalctl for systemd services** - On systemd-based systems (CentOS, RHEL, Ubuntu), PostgreSQL startup errors appear in both the PostgreSQL log files and the systemd journal. `journalctl -u postgresql-16 --no-pager -n 30` shows the most recent log entries for the service. This is often faster than finding and tailing the PG log file.

- **Local socket vs TCP connections** - PostgreSQL can accept connections via Unix domain sockets (local) and TCP/IP. Even if `listen_addresses` is wrong, Unix socket connections (using `psql` without `-h`) would work - if the server were running. But since a bad `listen_addresses` prevents startup entirely, both connection methods fail.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
 postgresql-16.service - PostgreSQL 16 database server
   Loaded: loaded (...)
   Active: failed (Result: exit-code) since ...
...
```

The service shows "failed" status.

### Step 2 - Check the journal for the bind error

```bash
sudo journalctl -u postgresql-16 --no-pager -n 30
```

Expected output (yours will differ):

```
... LOG:  starting PostgreSQL 16...
... FATAL:  could not create any TCP/IP sockets
... LOG:  database system is shut down
```

### Step 3 - Check PostgreSQL log files for more detail

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
FATAL:  could not create any TCP/IP sockets
LOG:  database system is shut down
```

The error tells you PostgreSQL tried to bind to a TCP address and failed. The next question: which address?

### Step 4 - Check postgresql.auto.conf for listen_addresses

Since the server is down, you cannot query `pg_settings`. Check the config files directly.

```bash
sudo grep listen_addresses /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):

```
listen_addresses = '10.0.0.99'
```

There it is. `10.0.0.99` does not exist on any local network interface.

### Step 5 - Confirm the IP does not exist on this server

```bash
ip addr show | grep "10.0.0.99"
```

Expected output (yours will differ):

```
(no output - the IP does not exist)
```

No output means the IP is not assigned to any interface. PostgreSQL cannot bind to it.

---

## Resolution

### Step 1 - Remove the bad listen_addresses from auto.conf

Since PostgreSQL is down, you cannot use `ALTER SYSTEM RESET`. Edit the file directly.

```bash
sudo -iu postgres
```

```bash
vi /opt/pgsql/data/postgresql.auto.conf
```

Find the line:

```
listen_addresses = '10.0.0.99'
```

Delete this entire line. Save and exit.

```bash
exit
```

### Step 2 - Verify the fix

```bash
sudo grep listen_addresses /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):

```
(no output)
```

No output means the override is gone. PostgreSQL will fall back to the value in `postgresql.conf`.

### Step 3 - Check what listen_addresses will be used

```bash
sudo grep listen_addresses /opt/pgsql/data/postgresql.conf
```

Expected output (yours will differ):

```
listen_addresses = 'localhost'
```

The base config has `localhost`, which is correct.

### Step 4 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

### Step 5 - Verify it started

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
 postgresql-16.service - PostgreSQL 16 database server
   Active: active (running) since ...
```

### Step 6 - Verify it accepts connections

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT 1;"
```

Expected output (yours will differ):

```
 ?column?
----------
        1
(1 row)
```

### Step 7 - Confirm listen_addresses is correct

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SHOW listen_addresses;"
```

Expected output (yours will differ):

```
 listen_addresses
------------------
 localhost
(1 row)
```

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- PostgreSQL accepts connections on port 5432
- listen_addresses is not 10.0.0.99
- postgresql.auto.conf does not contain listen_addresses override
- psql connection succeeds

---

## Interview Discussion Points

1. **What happens if listen_addresses contains an IP that does not exist on the server?** - PostgreSQL calls `bind()` on each address during startup. If the OS cannot bind to an IP (because it is not assigned to any local interface), the `bind()` call fails with `EADDRNOTAVAIL`. If PostgreSQL cannot bind to ANY address in the list, it logs a FATAL error and shuts down. If the list contains multiple addresses and only some fail, PostgreSQL will start with warnings for the failed ones but still listen on the successful ones.

2. **How do you fix a configuration error when PostgreSQL will not start?** - You must edit the configuration file directly on disk. If the error was introduced via `ALTER SYSTEM`, edit `postgresql.auto.conf`. If it was in `postgresql.conf` or `conf.d/`, edit that file. You cannot use SQL commands because there is no running server. After editing, start the service with `systemctl start`. This is why having OS-level access to the database server is critical for DBAs.

3. **What is the difference between listen_addresses = 'localhost' and listen_addresses = '*'?** - `'localhost'` binds only to `127.0.0.1` (and `::1` for IPv6), meaning only connections from the same machine are possible. `'*'` binds to all available network interfaces, accepting connections from any IP. In production, `'*'` is common because applications connect over the network, but you must pair it with proper `pg_hba.conf` rules and firewall settings. Never use `'*'` without also restricting access at the HBA and network level.

4. **Can you change listen_addresses without a restart?** - No. `listen_addresses` has context `postmaster`, meaning it can only be changed with a full server restart. This is because binding to network addresses happens once during postmaster startup. A reload (`pg_ctl reload`) will NOT rebind to new addresses. This makes listen_addresses changes a planned-downtime event in production.

5. **What diagnostic tools do you use for PostgreSQL startup failures?** - In order: (1) `systemctl status postgresql-16` for quick pass/fail, (2) `journalctl -u postgresql-16` for systemd-captured output, (3) PostgreSQL's own log files (here `/opt/pgsql/log/postgresql-*.log`) for FATAL messages with full detail. Also `pg_ctl -D /opt/pgsql/data start` run manually (as postgres user) can give more immediate error output than systemd does. For network binding issues specifically, `ss -tlnp | grep 5432` confirms which addresses the server is actually listening on after a successful start.
