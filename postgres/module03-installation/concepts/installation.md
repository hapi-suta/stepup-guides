# Installing PostgreSQL

## Why This Module Matters

Installing PostgreSQL sounds simple. Download it, install it, done. But there are
decisions baked into the installation that will affect you for the life of that cluster -
which version, which packages, where data lives, who owns what, and how connections are
authenticated. Getting these wrong means broken connections, permission errors, and
configuration that fights you every time you try to change something.

This doc walks you through the logic behind each step so the lab commands make sense
instead of feeling like cargo-culted magic.

---

## Where to Get PostgreSQL

You have three realistic options.

**1. PGDG repository (recommended)**

PGDG stands for PostgreSQL Global Development Group - the upstream PostgreSQL project.
They maintain their own package repositories for RHEL, Debian, Ubuntu, and other distros.
This is almost always the right choice.

**2. OS distribution packages**

Every major Linux distro ships PostgreSQL in its default repo (e.g., `dnf install postgresql-server`
on RHEL/CentOS). The problem is these versions lag behind. CentOS Stream 9's default repo
ships PostgreSQL 13 while upstream is at 17. If you need a specific version or a recent
one, use PGDG.

**3. Compile from source**

For custom builds, specific compile-time options, or platforms without packages. This is
not a day-one skill and not what we cover here.

For this course, we use the PGDG repo on CentOS Stream 9.

---

## Why PGDG Matters

The PGDG repo gives you two things that the OS repo does not:

**Multiple versions side by side.** The PGDG repo packages each major version separately.
You can have PostgreSQL 14, 15, and 16 all installed on the same server. The binaries
live in `/usr/pgsql-16/bin/`, `/usr/pgsql-15/bin/`, etc. They do not conflict.

**Current versions.** PGDG tracks upstream releases closely. You get bug fixes and
security patches as they come out, not six months later after distro packaging.

To add the PGDG repo on CentOS Stream 9:

```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql
```

The second command disables the built-in OS module so PGDG packages take precedence.

---

## Package Naming

PGDG packages follow a consistent naming pattern: `postgresql{version}-{component}`.

| Package | What it contains |
|---|---|
| `postgresql16-server` | The server binary (postgres), initdb, pg_ctl |
| `postgresql16-contrib` | Extra utilities and extensions (pg_stat_statements, pgcrypto...) |
| `postgresql16-devel` | Headers and libraries for building extensions |
| `postgresql16-libs` | The libpq client library |
| `postgresql16` | The client tools (psql, pg_dump, pg_restore) |

For a basic server install you need at minimum `postgresql16-server` and
`postgresql16-contrib`. Install them both.

---

## initdb - Creating the Cluster

Installing the packages does not create a database. It just installs the software.
You create the actual database cluster by running `initdb`.

`initdb` does the following:

- Creates the PGDATA directory structure (`base/`, `global/`, `pg_wal/`, etc.)
- Writes the system catalog tables (`pg_class`, `pg_database`, etc.)
- Creates the three default databases: `postgres`, `template0`, `template1`
- Writes a default `postgresql.conf` and `pg_hba.conf`
- Records the cluster's locale and encoding (these cannot be changed later without re-initdb)

```bash
sudo -u postgres /usr/pgsql-16/bin/initdb -D /opt/pgsql/data
```

Or call initdb directly:

```bash
su - postgres
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data
```

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.

The database cluster will be initialized with locale "en_US.UTF-8".
...
Success. You can now start the database server using:

    pg_ctl -D /opt/pgsql/data -l logfile start
```

---

## PGDATA Ownership

The PGDATA directory and everything inside it must be owned by the `postgres` OS user.
The PostgreSQL server process runs as `postgres` and needs read/write access to all
those files. If anything is owned by root or another user, the server will refuse to
start.

The correct permissions are `700` on the PGDATA directory itself (no group or world
access - PostgreSQL enforces this and will not start if the permissions are wrong).

```bash
ls -ld /opt/pgsql/data
# Should show: drwx------ postgres postgres ...
```

---

## systemd Service Management

On CentOS Stream 9 with PGDG packages, the service name is `postgresql-16`.

```bash
# Enable the service to start on boot
systemctl enable postgresql-16

# Start the service
systemctl start postgresql-16

# Check status
systemctl status postgresql-16

# Stop the service
systemctl stop postgresql-16

# Restart after config changes
systemctl restart postgresql-16

# Reload config without full restart (safe for most postgresql.conf changes)
systemctl reload postgresql-16
```

`systemctl reload` sends a SIGHUP to postmaster which re-reads postgresql.conf. This
works for most settings. A few settings (like `shared_buffers` and `max_connections`)
require a full restart because they affect shared memory allocation.

---

## postgresql.conf - The Main Config File

Located at `$PGDATA/postgresql.conf`. This is where you tune the server. The file ships
with almost everything commented out - commented-out lines use the compiled-in defaults.

Key settings to know for a basic server:

```
listen_addresses = 'localhost'   # or '*' to listen on all interfaces
port = 5432                      # default port
max_connections = 100            # maximum concurrent connections
shared_buffers = 128MB           # start here, tune upward (25% of RAM is common)
```

**listen_addresses** - Controls which network interfaces PostgreSQL listens on.
`localhost` means only local connections (Unix socket + 127.0.0.1). `'*'` means all
interfaces. If you cannot connect remotely, this is often why.

**max_connections** - Each connection consumes shared memory (for lock tables, etc.)
and a backend process. Set it to what you actually need, not arbitrarily high.

After changing postgresql.conf, check which settings require a restart vs a reload:

```sql
SELECT name, context FROM pg_settings WHERE name IN ('shared_buffers', 'max_connections', 'listen_addresses');
-- context = 'postmaster' means restart required
-- context = 'sighup' means reload is enough
```

---

## pg_hba.conf - The Gatekeeper

`pg_hba.conf` controls who can connect to what and how they authenticate. It stands for
Host-Based Authentication. Every connection attempt is matched against the rules in this
file top-to-bottom. The first matching rule wins.

```
# TYPE   DATABASE   USER       ADDRESS          METHOD
local    all        all                         peer
host     all        all        127.0.0.1/32     scram-sha-256
host     all        all        ::1/128          scram-sha-256
host     all        all        10.0.0.0/8       scram-sha-256
```

**TYPE** - `local` is a Unix socket connection. `host` is TCP (plain or SSL).
`hostssl` forces SSL.

**DATABASE** - Which database this rule applies to. `all` matches every database.

**USER** - Which PostgreSQL role this rule applies to. `all` matches every user.

**ADDRESS** - The client IP range (CIDR notation). Only applies to `host` rules.

**METHOD** - How to authenticate:

| Method | What it means |
|---|---|
| `trust` | No password required. Anyone matching the rule is let in. Use only on tightly controlled local connections. |
| `peer` | For local (Unix socket) connections only. The OS username must match the PostgreSQL username. |
| `md5` | Password required, hashed with MD5. Works but weaker than scram. |
| `scram-sha-256` | Password required, uses SCRAM-SHA-256. Use this for all new setups. |
| `reject` | Always deny. Useful for blocking specific users or IPs explicitly. |

If a connection is refused and you are sure the user and password are correct, check
pg_hba.conf first. No rule matching your connection = rejected.

After editing pg_hba.conf, reload is sufficient (no restart needed):

```bash
systemctl reload postgresql-16
```

---

## The conf.d Pattern

PostgreSQL supports splitting configuration across multiple files using `include_dir`.
Instead of one giant postgresql.conf, you can organize settings into separate files.

In postgresql.conf:

```
include_dir = 'conf.d'
```

Then create `/opt/pgsql/data/conf.d/` and put files like `memory.conf`,
`connections.conf`, `logging.conf` in there. PostgreSQL reads them in alphabetical order.
Later files override earlier ones. The main postgresql.conf is read last of all (or
first, depending on where the include_dir directive sits) - put the include_dir line at
the top so conf.d files can override defaults, or at the bottom to have conf.d override
everything.

This is useful for managed environments where you want to separate tuning from base
configuration, or when using configuration management tools like Ansible.

---

## Common First-Time Mistakes

**Cannot connect remotely, getting "connection refused"**

PostgreSQL is only listening on localhost. Set `listen_addresses = '*'` in
postgresql.conf and restart.

**Connection refused even after setting listen_addresses**

Check that the firewall allows port 5432. On CentOS: `firewall-cmd --add-port=5432/tcp --permanent && firewall-cmd --reload`.

**"password authentication failed" even with correct password**

pg_hba.conf has no rule matching your client IP, or has a `trust` rule that ignores
the password but the app is sending one and getting confused. Check `pg_hba.conf`.

**"FATAL: data directory has wrong ownership"**

The PGDATA directory is not owned by the `postgres` OS user. Fix with:
`chown -R postgres:postgres /opt/pgsql/data`

**"FATAL: could not create lock file" or "already running"**

A stale postmaster.pid file from a previous crash. If PostgreSQL is definitely not
running, remove the file: `rm /opt/pgsql/data/postmaster.pid` and try again.

**initdb fails with locale error**

The locale specified is not installed on the OS. Install it or use `--locale=C` for
a byte-order locale that always works.

---

## What to Watch For in the Lab

In this module you will install PostgreSQL from PGDG, run initdb, start the service,
and make your first connections. Pay attention to:

- The exact package names and which ones you actually need
- What initdb creates - list the PGDATA directory before and after
- The first connection as the `postgres` user via `peer` auth (no password needed)
- What happens when you try to connect remotely before changing listen_addresses
- Reading pg_hba.conf and tracing which rule matches your connection

Ask yourself: if this server crashed and I had to rebuild it, what decisions made
during installation would I need to make again the same way?
