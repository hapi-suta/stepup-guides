# PostgreSQL Upgrades

## Why This Module Matters

PostgreSQL releases a new major version every year and minor patches every quarter.
Staying current means access to performance improvements, security fixes, and new
features. Falling behind means accumulating technical debt and eventually facing an
unsupported version. Understanding how to upgrade safely - and how to roll back when
things go wrong - is a core DBA skill.

---

## Version Numbering

### Major Versions (16 -> 17)

Major versions change the first number: 15, 16, 17. They can include:
- New features
- Changes to system catalog format
- Incompatible changes to data storage
- Deprecated features removed

You cannot simply replace binaries for a major upgrade. The on-disk data format may
have changed. You need a migration tool (pg_upgrade or logical replication).

Major versions are supported for 5 years from release.

### Minor Versions (16.1 -> 16.2)

Minor versions change the second number: 16.1, 16.2, 16.3. They include only:
- Security fixes
- Bug fixes
- No new features
- No breaking changes

Minor upgrades are binary-compatible. Stop the server, replace binaries, start it.
The data directory format does not change between minor versions.

```
PostgreSQL Version Timeline:

16.0 --> 16.1 --> 16.2 --> 16.3    (minor: safe, just replace binaries)
 |
 |  (major: requires migration)
 v
17.0 --> 17.1 --> 17.2             (minor: safe, just replace binaries)
```

---

## Minor Upgrades

Minor upgrades are straightforward and should be done regularly - ideally within
a few weeks of each release.

### The Process

```bash
# 1. Read the release notes (always!)
#    https://www.postgresql.org/docs/release/

# 2. Stop PostgreSQL
sudo systemctl stop postgresql

# 3. Install the new minor version (replaces binaries)
# On RHEL/CentOS:
sudo dnf update postgresql16-server postgresql16

# On Debian/Ubuntu:
sudo apt update
sudo apt install postgresql-16

# 4. Start PostgreSQL
sudo systemctl start postgresql

# 5. Verify
psql -c "SELECT version();"
```

No data migration needed. No ANALYZE needed. The data directory is untouched.

### When to Upgrade

- Security fixes: immediately (schedule within days)
- Bug fixes: within a maintenance window in the next 2-4 weeks
- Never skip minor versions for months - the fixes accumulate and the risk of
  hitting a known bug increases

---

## pg_upgrade

The primary tool for major version upgrades. It migrates the data directory from
one major version to the next without doing a full dump/restore.

### How It Works

pg_upgrade operates in two modes:

**Copy mode (default)** - copies all data files from old to new cluster.

```
Old cluster (PG 16)          New cluster (PG 17)
  data/base/16384/   --copy-->  data/base/16384/
```

Safe but slow for large databases (copies every byte).

**Link mode (--link)** - creates hard links instead of copying.

```
Old cluster (PG 16)          New cluster (PG 17)
  data/base/16384/   --link-->  data/base/16384/
                     (same physical file on disk)
```

Fast (seconds instead of hours) but the old cluster becomes unusable after the
new cluster starts. You cannot roll back by starting the old cluster.

### The pg_upgrade Process

```
+------------------+        +------------------+
| Old cluster      |        | New cluster      |
| PG 16 (stopped)  |        | PG 17 (stopped)  |
| /data/16/        |        | /data/17/        |
+------------------+        +------------------+
         |                           |
         +---------> pg_upgrade <----+
                     (migrates catalog,
                      copies/links data files)
                          |
                          v
                  +------------------+
                  | New cluster      |
                  | PG 17 (ready)    |
                  | /data/17/        |
                  +------------------+
```

### Running pg_upgrade

```bash
# 1. Install the new PostgreSQL version alongside the old one
sudo dnf install postgresql17-server

# 2. Switch to the postgres user
sudo -iu postgres

# 3. Initialize a new data directory
/usr/pgsql-17/bin/initdb -D /var/lib/pgsql/17/data

# 4. Exit back to ec2-user
exit

# 5. Stop both clusters
sudo systemctl stop postgresql-16
# (new cluster shouldn't be running yet)

# 6. Switch to the postgres user
sudo -iu postgres

# 7. Run the upgrade check first
/usr/pgsql-17/bin/pg_upgrade \
    --old-datadir /var/lib/pgsql/16/data \
    --new-datadir /var/lib/pgsql/17/data \
    --old-bindir /usr/pgsql-16/bin \
    --new-bindir /usr/pgsql-17/bin \
    --check

# 8. If check passes, run the actual upgrade
/usr/pgsql-17/bin/pg_upgrade \
    --old-datadir /var/lib/pgsql/16/data \
    --new-datadir /var/lib/pgsql/17/data \
    --old-bindir /usr/pgsql-16/bin \
    --new-bindir /usr/pgsql-17/bin \
    --link

# 9. Exit back to ec2-user
exit

# 6. Start the new cluster
sudo systemctl start postgresql-17
```

### What pg_upgrade Does Internally

1. Connects to both clusters and verifies compatibility
2. Dumps the schema (DDL) from the old cluster
3. Restores the schema into the new cluster
4. Copies or links the data files
5. Rebuilds the system catalogs for the new version
6. Generates scripts for post-upgrade tasks

### What pg_upgrade Does NOT Do

- It does not upgrade extensions (you do that after)
- It does not update statistics (you run ANALYZE after)
- It does not rebuild indexes (you may want to REINDEX after for hash indexes)
- It does not migrate pg_hba.conf or postgresql.conf (copy manually)

---

## Logical Replication Upgrade Method

For databases that cannot tolerate downtime, logical replication provides a
zero-downtime upgrade path.

### How It Works

```
+------------------+    logical replication    +------------------+
| Old cluster      |  ----------------------> | New cluster      |
| PG 16 (running)  |    (real-time data sync) | PG 17 (running)  |
| Primary          |                          | Replica           |
+------------------+                          +------------------+
        |                                              |
   Application                                    Application
   (reads/writes)                                 (reads only, initially)

                    --- cutover ---

   Application stops writing to old
   Application starts writing to new
   Old cluster decommissioned
```

### Steps

1. Set up the new version cluster
2. Create the schema on the new cluster (pg_dump --schema-only)
3. Create a publication on the old cluster
4. Create a subscription on the new cluster
5. Wait for initial data sync to complete
6. Wait for replication lag to reach zero
7. Stop writes to old cluster
8. Verify all data is synced
9. Point application to new cluster
10. Drop subscription, decommission old cluster

### Advantages

- Zero downtime (application switches in seconds)
- You can test the new cluster while it's replicating
- You can roll back by pointing the application back to the old cluster

### Limitations

- DDL is not replicated (schema changes during migration need manual handling)
- Sequences are not replicated (must be manually synced at cutover)
- Large objects are not replicated
- More complex to set up and monitor than pg_upgrade

---

## Pre-Upgrade Checklist

### 1. Read the Release Notes

Every major version has a "Migration" section documenting breaking changes. Read it
completely. Common issues:
- Removed configuration parameters
- Changed default values
- Deprecated SQL syntax now removed
- Changes to authentication defaults

### 2. Check Extensions

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

Verify every extension is available for the new version. Third-party extensions
(PostGIS, pg_partman, pgvector) may lag behind new PostgreSQL releases. This is the
most common blocker.

### 3. Check Custom Types and Operators

If you have custom types, operators, or C-language functions, they must be recompiled
against the new version's headers.

### 4. Check Deprecated Features

```sql
-- PG 16+: check for deprecated features
-- Example: old-style typecasting, implicit casts
```

Each version's release notes list what's deprecated. Search for your usage patterns.

### 5. Check Data Types

Some major versions change internal storage for certain types. pg_upgrade handles
this, but you should be aware of it.

### 6. Test the Application

Run your application test suite against the new version. Set up a copy of production
on the new version and run integration tests.

### 7. Check Replication Compatibility

If you use streaming replication, all replicas must be upgraded after the primary.
Physical replicas cannot connect to a primary running a different major version.

### 8. Backup

Take a full backup before any upgrade. This is your safety net.

```bash
pg_dumpall -U postgres > pre_upgrade_backup.sql
# or use pg_basebackup for a physical backup
```

---

## Post-Upgrade Tasks

### 1. Run ANALYZE

pg_upgrade does not copy optimizer statistics. The planner will use default estimates
until you run ANALYZE.

```bash
# pg_upgrade generates this script
./analyze_new_cluster.sh

# Or manually:
vacuumdb --all --analyze-in-stages -U postgres
```

`--analyze-in-stages` does three passes with increasing sample sizes, giving the
planner usable (if imprecise) statistics quickly.

### 2. Update Extensions

```sql
ALTER EXTENSION postgis UPDATE;
ALTER EXTENSION pg_stat_statements UPDATE;
-- Repeat for each extension
```

### 3. Check and Reindex Hash Indexes

Before PostgreSQL 10, hash indexes were not crash-safe. If upgrading from PG 9.x,
reindex all hash indexes:

```sql
REINDEX INDEX my_hash_index;
```

For PG 10+ to newer versions, this is generally not needed.

### 4. Update Configuration Files

pg_upgrade does not migrate postgresql.conf or pg_hba.conf. Copy your customized
settings to the new cluster's config files, but review each parameter:

- Some parameters may have been renamed
- Some defaults may have changed
- New parameters may be available

### 5. Delete Old Cluster

pg_upgrade generates a `delete_old_cluster.sh` script. Run it after you've confirmed
the new cluster is stable:

```bash
# Wait a few days to be sure, then:
./delete_old_cluster.sh
```

---

## Rollback Strategies

### pg_upgrade Copy Mode Rollback

The old data directory is intact. Simply start the old cluster:

```bash
sudo systemctl start postgresql-16
```

Point your application back to the old cluster.

### pg_upgrade Link Mode Rollback

The old data directory is no longer usable (files are now owned by the new cluster).
Your rollback options:
- Restore from the backup you took before the upgrade
- You did take a backup, right?

This is why link mode is faster but riskier. Use it only when you have a verified
backup and are confident in the upgrade.

### Logical Replication Rollback

Simply point the application back to the old cluster. The old cluster was running
the whole time and has all the data (it was the source of truth until cutover).

This is the safest rollback path, which is why logical replication is preferred
for mission-critical systems.

---

## Common Upgrade Failures

### 1. Extension Not Available

```
could not open extension control file "/usr/pgsql-17/share/extension/postgis.control"
```

The extension is not installed for the new version. Install it before running pg_upgrade.

### 2. Incompatible Locale

```
lc_collate values for database "mydb" do not match
```

The new cluster was initialized with a different locale. Reinitialize with matching
locale settings or use `--locale` with initdb.

### 3. Tablespace Path Issues

pg_upgrade expects tablespace directories to exist at the same paths. If your
tablespaces moved, create symlinks or update the paths.

### 4. Custom loadable Libraries

```
could not load library "/usr/pgsql-16/lib/my_custom.so"
```

Custom shared libraries must be compiled for the new version and placed in the
new lib directory.

### 5. Insufficient Disk Space (Copy Mode)

Copy mode needs enough free space for a complete copy of the data directory.
Check free space before starting:

```bash
du -sh /var/lib/pgsql/16/data
df -h /var/lib/pgsql/
```

### 6. Old Cluster Not Cleanly Shut Down

pg_upgrade requires the old cluster to be stopped cleanly (not crashed). If it
wasn't clean:

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/16/data start
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/16/data stop -m fast
```

---

## Planning a Production Upgrade

### Timeline

```
Week 1-2: Research
  - Read release notes for every version between current and target
  - Inventory extensions and verify availability
  - Identify application compatibility concerns

Week 3-4: Test Environment
  - Restore production backup to test server
  - Perform upgrade on test server
  - Run full application test suite against upgraded test server
  - Measure upgrade duration

Week 5-6: Staging
  - Upgrade staging environment
  - Run staging for 1-2 weeks under real-ish traffic
  - Validate monitoring, alerting, and backups work

Week 7-8: Production
  - Schedule maintenance window (for pg_upgrade) or cutover window (for logical replication)
  - Take full backup
  - Perform upgrade
  - Run post-upgrade tasks
  - Monitor intensively for 48 hours
  - Keep old cluster available for 1 week (rollback safety net)

Week 9-10: Cleanup
  - Remove old binaries and data directories
  - Update documentation and runbooks
  - Close the upgrade ticket
```

### Skip-Version Upgrades

pg_upgrade supports upgrading from any supported version to any newer version
(e.g., PG 12 directly to PG 17). You do not need to upgrade through each
intermediate version.

However, read the release notes for EVERY intermediate version. Breaking changes
accumulate.

### Upgrade Frequency

- **Minor versions**: quarterly, within weeks of release
- **Major versions**: annually or every 2 years at most
- **Never**: let your version reach end-of-life without a plan

Current support timeline:
- Each major version is supported for 5 years
- After that, no more security patches

Running an unsupported version means known vulnerabilities with no fixes.

---

## Key Takeaways

1. Minor upgrades are simple binary replacements - do them promptly for security fixes
2. Major upgrades require pg_upgrade (faster, some downtime) or logical replication (zero downtime, more complex)
3. pg_upgrade link mode is fast but destroys the old cluster - always have a backup
4. Always run --check before the actual pg_upgrade
5. Post-upgrade: run ANALYZE immediately, update extensions, review config files
6. Extensions are the most common upgrade blocker - verify availability early
7. Test the upgrade on a copy of production before touching the real thing
8. Keep the old cluster available for rollback for at least a week after upgrading
