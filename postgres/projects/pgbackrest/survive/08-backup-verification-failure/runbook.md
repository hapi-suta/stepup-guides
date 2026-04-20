# Scenario 08 - Backup Verification Failure

**Severity:** MEDIUM
**Expected Recovery Time:** 10-15 minutes
**Single Server**

---

## Alert

```
MEDIUM: Automated backup verification failed.
pgbackrest check and stanza-check both returning errors.
```

---

## Symptoms

- `pgbackrest check` returns errors
- `pgbackrest info` shows no backups or errors
- Monitoring alerts for backup health failures
- WAL archiving may be silently failing

---

## Impact

- No new backups can be taken until configuration is fixed
- WAL archiving is broken - WAL files will accumulate
- If a disaster occurs now, recovery depends on whatever backups existed before the misconfiguration
- Extended misconfiguration means the WAL gap grows - PITR window shrinks

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **pgbackrest check** - Validates that the pgBackRest configuration is correct, the stanza exists, PostgreSQL is accessible, and WAL archiving is functional. It performs an end-to-end test by pushing a WAL file. This is your primary tool for verifying backup health.
- **pgbackrest info** - Shows backup inventory: backup labels, sizes, timestamps, WAL ranges, and retention status. If the repo path is wrong, it either shows no backups or errors out.
- **pgbackrest.conf** - The main configuration file at `/etc/pgbackrest.conf`. Contains stanza definitions, repo paths, PostgreSQL paths, and retention settings. A misconfigured path means pgBackRest cannot find its backup repository.
- **archive_command stanza mismatch** - The `--stanza` parameter in archive_command must exactly match the stanza name defined in pgbackrest.conf. If they differ, archive-push fails because it cannot find the stanza configuration.
- **Defense in depth** - Use multiple verification methods: `pgbackrest check` (end-to-end), `pgbackrest info` (backup inventory), and `pg_stat_archiver` (PostgreSQL-side archiving status). Any one of these can catch problems the others miss.

---

## Layer 1 - Quick Fix

### Step 1 - Run pgbackrest check

Start by running the standard health check to see the error.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00  ERROR: [055]: repo1: raised from local-1 shim protocol:
            unable to load info file '/tmp/pgbackrest-decoy/backup/main/backup.info'
            ...
```

The error shows pgBackRest is looking for backups in `/tmp/pgbackrest-decoy` instead of the correct repo path. This is a configuration problem.

### Step 2 - Run pgbackrest info

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: error (missing stanza path)
    cipher: none
```

No backups are visible because pgBackRest is looking in the wrong directory.

> **Concept: pgbackrest info as a diagnostic tool** - When `info` shows "missing stanza path" but you know backups exist, the most likely cause is a wrong `repo1-path` in the config. The stanza path is `{repo1-path}/backup/{stanza-name}/`. If either the repo path or stanza name is wrong, pgBackRest cannot find its metadata files.

### Step 3 - Check the configuration file

```bash
cat /etc/pgbackrest.conf
```

Expected output (yours will differ):

```
[global]
repo1-path=/tmp/pgbackrest-decoy
repo1-retention-full=2
process-max=2
log-level-console=info
log-level-file=detail

[main]
pg1-path=/opt/pgsql/data
pg1-port=5432
```

The `repo1-path` is set to `/tmp/pgbackrest-decoy` instead of `/opt/pgsql/backup/pgbackrest`. That is the first problem.

### Step 4 - Check archive_command

```bash
exit
```

```bash
sudo -i -u postgres
```

The `-p 5432` flag tells psql to connect on port 5432 (the default PostgreSQL port).

```bash
/usr/pgsql-16/bin/psql -p 5432
```

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
 archive_command
------------------------------------------------------
 pgbackrest --stanza=wrong_stanza archive-push %p
```

The archive_command references `wrong_stanza` instead of `main`. That is the second problem.

> **Concept: Multiple failure modes** - This scenario has two independent misconfigurations: the repo path in pgbackrest.conf and the stanza name in archive_command. Fixing only one will not fully resolve the issue. Always check all related configuration when troubleshooting.

### Step 5 - Exit psql and postgres user

```
\q
```

```bash
exit
```

### Step 6 - Fix repo1-path in pgbackrest.conf

Edit the configuration file to set the correct repo path.

```bash
sudo vi /etc/pgbackrest.conf
```

Find this line:

```
repo1-path=/tmp/pgbackrest-decoy
```

Change it to:

```
repo1-path=/opt/pgsql/backup/pgbackrest
```

Save and exit (`:wq`).

Verify the change.

```bash
grep repo1-path /etc/pgbackrest.conf
```

Expected output (yours will differ):

```
repo1-path=/opt/pgsql/backup/pgbackrest
```

### Step 7 - Verify pgbackrest can see backups now

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000020

        full backup: 20260420-100000F
            timestamp start/stop: ...
            database size: 850MB
            ...
```

Backups are visible again. The repo path is fixed.

```bash
exit
```

### Step 8 - Fix archive_command

```bash
sudo -i -u postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432
```

```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';
```

Expected output (yours will differ):

```
ALTER SYSTEM
```

### Step 9 - Reload PostgreSQL configuration

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
```

### Step 10 - Verify archive_command is correct

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
 archive_command
-------------------------------------------------------
 pgbackrest --stanza=main archive-push %p
```

### Step 11 - Exit psql and postgres user

```
\q
```

```bash
exit
```

### Step 12 - Run pgbackrest check

Now run the full end-to-end check.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00   INFO: check repo1 configuration (primary)
P00   INFO: check repo1 (standby)
P00   INFO: check command end: completed successfully
```

> **Concept: pgbackrest check is end-to-end** - The `check` command does more than verify the config file. It connects to PostgreSQL, verifies the stanza exists, checks that archive_command is configured, and performs a test WAL archive push. If check passes, the entire backup pipeline is working.

### Step 13 - Force a WAL switch to confirm archiving works

Open psql.

```bash
/usr/pgsql-16/bin/psql -p 5432
```

Run this query.

```sql
SELECT pg_switch_wal();
```

Expected output (yours will differ):

```
 pg_switch_wal
----------------
 0/22000100
```

Wait a few seconds, then verify.

```sql
SELECT last_archived_wal, failed_count, last_archived_time FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 last_archived_wal        | failed_count | last_archived_time
--------------------------+--------------+-------------------------
 000000010000000000000022 |            5 | 2026-04-20 10:45:00+00
```

The `last_archived_time` should be very recent (within the last minute). The `failed_count` may be non-zero from earlier failures - that is fine as long as archiving is working now.

Exit psql.

```
\q
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

Expected output (yours will differ):

```
[PASS] pgbackrest check passes
[PASS] pgbackrest info shows valid backups
[PASS] repo1-path is correct in config
[PASS] archive_command is correct (contains pgbackrest with correct stanza)
[PASS] Recent successful WAL archive
Result: ALL CHECKS PASSED
```

---

## Layer 2 - Concepts

### Configuration Validation Workflow

When pgBackRest is misbehaving, follow this diagnostic flow:

1. **pgbackrest check** - End-to-end test. If it fails, you know something is broken.
2. **pgbackrest info** - Can pgBackRest see its backups? If not, the repo path or stanza config is wrong.
3. **cat pgbackrest.conf** - Read the actual config. Check repo1-path, stanza name, pg1-path.
4. **SHOW archive_command** - Does it match the stanza in pgbackrest.conf?
5. **pg_stat_archiver** - Is PostgreSQL able to archive WAL files?
6. **pgBackRest logs** - Check `/var/log/pgbackrest/` for detailed error messages.

### Common Misconfiguration Patterns

| Symptom | Likely Cause |
|---------|-------------|
| "missing stanza path" | Wrong repo1-path in config |
| "stanza not found" | Stanza name mismatch (config vs command) |
| "unable to find pg_control" | Wrong pg1-path in config |
| Archive failing but check passes | archive_command stanza != config stanza |
| Check fails but info works | archive_command problem (not repo problem) |

### Monitoring pgBackRest Health

Production monitoring should check:

- `pgbackrest check` exit code (run via cron every 15 minutes)
- `pgbackrest info` - backup age (alert if last backup > 25 hours)
- `pg_stat_archiver.failed_count` - alert if increasing
- Time since `last_archived_time` - alert if > 5 minutes
- pgBackRest log files for ERROR entries
- Backup repo disk usage

> **Concept: Configuration drift** - In production, config files can be changed by automated tools (Ansible, Puppet), manual edits, or package updates. Always version-control pgbackrest.conf and use a config management tool to enforce the correct state. After any system update, run `pgbackrest check` to verify nothing was changed.

> **Concept: archive_command vs pgbackrest.conf** - These are two separate configuration systems. archive_command is a PostgreSQL parameter (set in postgresql.conf or via ALTER SYSTEM). pgbackrest.conf is pgBackRest's own config. They must agree on the stanza name. Changing one without the other is a common source of failures.

---

## Layer 3 - Interview Discussion Points

1. **How would you automate pgBackRest health monitoring?** - Run `pgbackrest --stanza=main check` via cron every 15 minutes - alert on non-zero exit code. Parse `pgbackrest info --output=json` to check backup age - alert if the last backup is older than your schedule plus a buffer. Monitor `pg_stat_archiver` via a metrics collector (pg_exporter for Prometheus, or custom script). Check pgBackRest log files for ERROR lines. Set up disk space alerts on the backup repository.

2. **What is the difference between pgbackrest check and pgbackrest stanza-check?** - `stanza-check` is a lighter check that verifies the stanza configuration, repo accessibility, and PostgreSQL connectivity. It does not test WAL archiving. `check` does everything `stanza-check` does plus verifies that archive_command is configured and performs a test WAL archive. Use `check` for comprehensive validation. Use `stanza-check` when you only need to verify the repo and connectivity.

3. **Someone changed pgbackrest.conf on a Friday evening and left for the weekend. Monday morning, backups have not run for 3 days. How do you triage?** - (a) Check the pgBackRest log files in `/var/log/pgbackrest/` for the first error after the config change. (b) Diff the current config against version control (or the backup of the config in the repo). (c) Run `pgbackrest check` to identify the current failure. (d) Fix the config and run a manual backup immediately. (e) Check if WAL archiving was also broken - if so, verify the WAL chain is intact. (f) Take a full backup to reset the chain if WAL gaps exist.

4. **Why should the backup repository be on separate storage from PGDATA?** - If PGDATA and the backup repo share a disk and the disk fails, you lose both the database and the backups. Separate storage ensures that a single hardware failure does not cause unrecoverable data loss. Options: separate physical disk, NFS mount, cloud object storage (S3/GCS via pgBackRest's native S3 support), or a remote pgBackRest repository host.

5. **How do you handle pgBackRest configuration in a multi-node replication setup?** - Each node needs pgbackrest.conf with the same stanza name and repo path. For a local repo, the primary takes backups and standbys are configured as pg2, pg3, etc. For a remote repo (dedicated backup server), all nodes push WAL to the same repo. After a failover, the new primary must be able to take backups - verify that pgbackrest.conf on the new primary has the correct pg1-path and that the repo is accessible. Use `pgbackrest check` on all nodes after any topology change.
