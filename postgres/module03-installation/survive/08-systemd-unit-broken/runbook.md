# Runbook 08: Systemd Unit Broken

## Scenario

PostgreSQL 16 failed to start after a routine maintenance window. An on-call engineer made a systemd configuration change, but now the service won't come up. Nobody touched postgresql.conf or the data directory directly. Diagnose the systemd-level issue and restore PostgreSQL to service.

---

## Layer 1: Fix Path

### Step 1 - Check the service status

```bash
sudo systemctl status postgresql-16
```

Expected output:
```
● postgresql-16.service - PostgreSQL 16 database server
     Active: failed (Result: exit-code) since ...
     Process: XXXX ExecStartPre=/usr/pgsql-16/bin/postgresql-16-check-db-dir ${PGDATA} (code=exited, status=1/FAILURE)
```

The key clue is the ExecStartPre failure - it runs before PostgreSQL even tries to start.

> **Concept: ExecStartPre** - Systemd runs ExecStartPre commands before the main ExecStart. For PostgreSQL, this is `postgresql-16-check-db-dir` which verifies the PGDATA directory exists and contains a valid cluster. If this check fails, PostgreSQL never attempts to start. The exit status=1 tells you the pre-check failed, not PostgreSQL itself.

### Step 2 - Check the journal for details

```bash
sudo journalctl -xeu postgresql-16 --no-pager | tail -20
```

`-x` adds explanatory help text. `-e` jumps to the end of the log. `-u` filters to this service. `--no-pager` prints to the terminal.

Expected output (key lines):
```
postgresql-16-check-db-dir[XXXX]: "/opt/pgsql/data-WRONG" is missing or empty.
postgresql-16-check-db-dir[XXXX]: Use "/usr/pgsql-16/bin/postgresql-16-setup --initdb" to initialize the database cluster.
systemd[1]: postgresql-16.service: Control process exited, code=exited, status=1/FAILURE
```

The path `/opt/pgsql/data-WRONG` is clearly not right. But where is it coming from?

### Step 3 - Inspect the full systemd unit configuration

```bash
sudo systemctl cat postgresql-16
```

Expected output:
```
# /usr/lib/systemd/system/postgresql-16.service
[Unit]
Description=PostgreSQL 16 database server
...
[Service]
...
Environment=PGDATA=/opt/pgsql/data
...

# /etc/systemd/system/postgresql-16.service.d/override.conf
[Service]
Environment=PGDATA=/opt/pgsql/data-WRONG
```

The bottom section shows a systemd override file that replaces the PGDATA environment variable with a wrong path.

> **Concept: systemctl cat** - This command shows the complete, merged unit file configuration including any drop-in overrides. It's the first tool to use when a service behaves unexpectedly. The output shows both the original unit file (from `/usr/lib/systemd/system/`) and any overrides (from `/etc/systemd/system/`). Overrides take precedence.

### Step 4 - Examine the override file

```bash
sudo cat /etc/systemd/system/postgresql-16.service.d/override.conf
```

Expected output:
```
[Service]
Environment=PGDATA=/opt/pgsql/data-WRONG
```

This is the problem. The override sets PGDATA to a non-existent path.

> **Concept: Systemd drop-in overrides** - Files in `/etc/systemd/system/<service>.service.d/*.conf` override settings from the main unit file in `/usr/lib/systemd/system/`. This is the proper way to customize a service without editing the vendor unit file (which gets overwritten on package upgrades). The `systemctl edit` command creates these files safely. But a bad override can break the service entirely.

### Step 5 - Fix the override with the correct PGDATA path

The base unit file (from the RPM package) defaults to `/opt/pgsql/data/`. This lab uses `/opt/pgsql/data`, so we need a correct override - not no override.

```bash
sudo vi /etc/systemd/system/postgresql-16.service.d/override.conf
```

Change:
```
Environment=PGDATA=/opt/pgsql/data-WRONG
```

To:
```
Environment=PGDATA=/opt/pgsql/data
```

Save and exit (`:wq`).

### Step 6 - Reload systemd to pick up the change

```bash
sudo systemctl daemon-reload
```

This is critical. Systemd caches unit file configurations. If you don't reload, it will still use the old (broken) configuration.

> **Concept: systemctl daemon-reload** - Systemd reads unit files once and caches them. Any change to unit files or overrides requires `daemon-reload` to take effect. Forgetting this step is a common mistake - you remove the bad file but the service still fails because systemd is using the cached version. Always run `daemon-reload` after modifying unit files.

### Step 7 - Verify the configuration is correct now

```bash
sudo systemctl cat postgresql-16
```

Expected output (override section shows correct path):
```
# /usr/lib/systemd/system/postgresql-16.service
[Unit]
Description=PostgreSQL 16 database server
...
[Service]
...
Environment=PGDATA=/opt/pgsql/data/
...

# /etc/systemd/system/postgresql-16.service.d/override.conf
[Service]
Environment=PGDATA=/opt/pgsql/data
```

The override section now correctly points to `/opt/pgsql/data`, which takes precedence over the RPM default.

### Step 8 - Reset failed state and start PostgreSQL

If systemd hit a restart rate limit, reset it first:

```bash
sudo systemctl reset-failed postgresql-16
```

```bash
sudo systemctl start postgresql-16
```

```bash
sudo systemctl status postgresql-16
```

Expected output:
```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

### Step 9 - Verify PostgreSQL is healthy

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

```sql
SHOW data_directory;
```

Expected output:
```
  data_directory
-----------------
 /opt/pgsql/data
(1 row)
```

```sql
SELECT count(*) FROM pg_stat_activity;
```

Expected output:
```
 count
-------
     X
(1 row)
```

```sql
\q
```

```bash
exit
```

### Alternative fix: systemctl edit

Instead of manually editing the override file, you can use:

```bash
sudo systemctl edit postgresql-16
```

This opens the override file in your editor and automatically runs `daemon-reload` when you save. It's the safest way to modify systemd overrides.

> **Warning about systemctl revert** - Do NOT use `systemctl revert postgresql-16` here. It removes ALL overrides, which would reset PGDATA back to the RPM default `/opt/pgsql/data/`. Since this lab uses a custom data directory at `/opt/pgsql/data`, removing the override would break PostgreSQL.

---

## Layer 2: Revision Concepts

### Systemd unit file hierarchy

Systemd loads unit files from multiple locations with a priority order:

| Priority | Path | Purpose |
|----------|------|---------|
| Highest | `/etc/systemd/system/` | Local admin overrides |
| Medium | `/run/systemd/system/` | Runtime-generated units |
| Lowest | `/usr/lib/systemd/system/` | Vendor-installed defaults |

Drop-in overrides (`*.service.d/*.conf`) merge with the base unit file. A file in `/etc/` with the same name as one in `/usr/lib/` completely replaces it.

### How PGDATA flows through systemd

1. The unit file sets `Environment=PGDATA=/opt/pgsql/data`
2. `ExecStartPre` runs `postgresql-16-check-db-dir ${PGDATA}` - checks the directory exists
3. `ExecStart` runs `postmaster -D ${PGDATA}` - starts the server
4. If PGDATA is wrong, ExecStartPre catches it before PostgreSQL even tries to start

### Key systemd debugging commands

| Command | Purpose |
|---------|---------|
| `systemctl status SERVICE` | Quick status, exit codes, recent log lines |
| `journalctl -xeu SERVICE` | Full journal for the service with explanations |
| `systemctl cat SERVICE` | Complete merged configuration with overrides |
| `systemctl show SERVICE` | All properties (Environment, ExecStart, etc.) |
| `systemctl edit SERVICE` | Safely create/edit an override file |
| `systemctl revert SERVICE` | Remove all local overrides |
| `systemd-analyze verify SERVICE` | Check unit file syntax |

### Safe override workflow

When you need to customize a PostgreSQL systemd unit, use `systemctl edit` instead of manually creating files:

```bash
sudo systemctl edit postgresql-16
```

This opens an editor and automatically:
- Creates the override directory
- Names the file correctly (override.conf)
- Runs daemon-reload when you save
- Validates syntax

### Common override use cases for PostgreSQL

```ini
# Increase open file limit
[Service]
LimitNOFILE=65536

# Set custom PGDATA (legitimate use)
[Service]
Environment=PGDATA=/data/pgdata

# Increase OOM kill protection
[Service]
OOMScoreAdjust=-1000

# Add a pre-start backup script
[Service]
ExecStartPre=/usr/local/bin/pg-backup-check.sh
```

> **Concept: Environment directive behavior** - When you set `Environment=PGDATA=/new/path` in an override, it does NOT append to the existing environment. It replaces the PGDATA variable entirely. If the original unit sets `Environment=PGDATA=/opt/pgsql/data` and your override sets `Environment=PGDATA=/wrong/path`, the override wins. This is why a single bad override can completely break the service.

---

## Layer 3: Interview Discussion Points

1. **The service won't start but nobody touched postgresql.conf - where do you look?** - Check systemd first: `systemctl status` for the error, `journalctl -xeu` for details, `systemctl cat` for the full configuration including overrides. Many PostgreSQL startup issues are at the systemd layer, not the PostgreSQL layer. Also check file permissions, disk space, and whether someone changed the systemd environment.

2. **What's the difference between editing the unit file and using an override?** - Never edit `/usr/lib/systemd/system/postgresql-16.service` directly. Package upgrades will overwrite it. Always use `systemctl edit` to create a drop-in override in `/etc/systemd/system/`. Overrides survive package upgrades and are clearly visible as local changes.

3. **How would you audit systemd changes in a production environment?** - Monitor the `/etc/systemd/system/` directory with file integrity tools (AIDE, Tripwire). Use configuration management (Ansible) to enforce expected overrides. Log all `systemctl edit` and `systemctl daemon-reload` commands via auditd. Review `systemctl cat` output during incident post-mortems.

4. **A colleague wants to change PGDATA to a new mount point. Walk through the safe process.** - Stop PostgreSQL, copy or move data to the new path (`rsync -av`), verify ownership (postgres:postgres) and permissions (700), use `systemctl edit postgresql-16` to set the new Environment=PGDATA, run `daemon-reload`, start the service, verify with `SHOW data_directory`. Test a restart cycle to confirm it survives reboot.

5. **What does ExecStartPre do and why is it important?** - It runs validation checks before the main service starts. For PostgreSQL, it verifies the PGDATA directory exists and is initialized. This prevents PostgreSQL from starting with a missing or corrupt data directory, which could lead to data loss. If ExecStartPre fails, ExecStart never runs - this is a safety gate. You can add custom ExecStartPre commands for pre-start health checks.
