# Runbook 08 - pgBackRest Stanza Misconfigured

**Severity:** Critical - All backup and restore operations are broken
**Time to resolve:** 10-15 minutes

---

## Fix Path

### Step 1: Confirm pgBackRest is broken

SSH to [NODE1] and run a stanza check:

```bash
sudo -u postgres pgbackrest --stanza=main check
```

Expected: Error - stanza "main" not found or invalid pg1-path.

```bash
sudo -u postgres pgbackrest --stanza=main info
```

Expected: Error about missing or invalid stanza.

### Step 2: Examine the current configuration

```bash
sudo cat /etc/pgbackrest.conf
```

Look for these common misconfigurations:
- Wrong stanza name (e.g., `[wrong-stanza]` instead of `[main]`)
- Wrong pg1-path (does not match actual PostgreSQL data directory)
- Wrong pg1-port
- Missing required options

> **Concept - pgBackRest Stanza**: A stanza is a named configuration block that maps to a specific PostgreSQL cluster. The stanza name must match what was used during `pgbackrest stanza-create`. The pg1-path must point to the actual data directory.

### Step 3: Determine the correct settings

Check the actual PostgreSQL data directory:

```sql
SHOW data_directory;
```

Expected: `/opt/pgsql/data`

Check the port:

```sql
SHOW port;
```

Expected: `5432`

Check what stanza name the existing repo uses:

```bash
sudo ls /opt/pgsql/backup/pgbackrest/backup/
```

The directory name there is the stanza name (e.g., `main`).

### Step 4: Fix the configuration

Edit `/etc/pgbackrest.conf` with the correct settings:

```bash
sudo nano /etc/pgbackrest.conf
```

The corrected config should look like:

```ini
[main]
pg1-path=/opt/pgsql/data
pg1-port=5432

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
log-level-console=info
log-level-file=detail
```

Key fixes:
- Stanza name matches the repo directory name (`main`)
- pg1-path matches SHOW data_directory output (`/opt/pgsql/data`)
- pg1-port matches SHOW port output

> **Concept - Configuration Validation**: Always validate config changes by running `pgbackrest --stanza=main check` after editing. A config that looks correct syntactically can still fail if values do not match the actual PostgreSQL setup.

### Step 5: Check if stanza needs recreation

If the stanza name was changed, you may need to verify the stanza:

```bash
sudo -u postgres pgbackrest --stanza=main stanza-create
```

This is safe to run even if the stanza already exists - it will verify and update as needed.

### Step 6: Verify the fix

```bash
sudo -u postgres pgbackrest --stanza=main check
```

Expected: "check command end: completed successfully"

```bash
sudo -u postgres pgbackrest --stanza=main info
```

Expected: Shows valid backup information with stanza name "main".

### Step 7: Verify a backup can be taken

```bash
sudo -u postgres pgbackrest --stanza=main --type=diff backup
```

This confirms the entire backup pipeline is working end-to-end.

### Step 8: Verify archiving works

```sql
SELECT pg_switch_wal();
```

Wait a few seconds, then:

```bash
sudo -u postgres pgbackrest --stanza=main check
```

---

## Key Concepts for Revision

- **pgBackRest stanza** is the unit of configuration that ties a pgBackRest repo to a PostgreSQL cluster. The stanza name, pg1-path, and pg1-port must all be consistent.
- **stanza-create** initializes the repo structure for a stanza. It creates the directory layout and initial metadata. It is idempotent - safe to re-run.
- **pgbackrest check** validates the entire chain: config file, PostgreSQL connectivity, archive_command, and WAL archiving. It is the single best command for verifying pgBackRest health.
- **pg1-path** must exactly match PostgreSQL's data_directory. Even a trailing slash difference can cause failures.
- **Configuration file locations**: pgBackRest checks /etc/pgbackrest.conf by default. You can override with --config flag or PGBACKREST_CONFIG environment variable.
- **archive_command integration**: The archive_command in postgresql.conf must reference the same stanza name used in pgbackrest.conf. A mismatch breaks archiving silently.
- **Multi-stanza setups**: A single pgbackrest.conf can contain multiple stanzas for different PostgreSQL clusters. Each stanza has its own pg1-path and backup schedule.

---

## Interview Discussion Points

1. **Configuration management**: How do you manage pgBackRest configuration in production? Do you use configuration management tools (Ansible, Puppet) to prevent config drift?

2. **Config validation**: What pre-checks do you run after any config change to pgbackrest.conf? How do you prevent a bad config from reaching production?

3. **Stanza naming conventions**: How do you name stanzas in a multi-cluster environment? What naming scheme avoids confusion? (e.g., hostname-based, application-based, port-based)

4. **archive_command consistency**: The archive_command references `--stanza=main` but someone renames the stanza in pgbackrest.conf. What happens? How do you detect this?

5. **Disaster recovery documentation**: Where do you document the pgBackRest configuration for each cluster? If a DBA is restoring at 3 AM, can they find the correct settings?

6. **Configuration backup**: Do you back up /etc/pgbackrest.conf itself? Where? How do you ensure the config backup is up to date?

7. **Testing config changes**: How do you test pgBackRest configuration changes without affecting production backups? Can you use --dry-run or a test stanza?
