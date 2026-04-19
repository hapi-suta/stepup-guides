# Use 05: Major Version Upgrade Planning

Plan a major version upgrade from PostgreSQL 16 to PostgreSQL 17. This exercise covers the full planning cycle: pre-upgrade checklist, test on replica, rollback plan, and communication templates.

---

## Instructions

1. Work through each section in order
2. Fill in the planning templates
3. This is a planning exercise - do NOT execute the upgrade
4. The plan should be detailed enough that another DBA could follow it

---

## 1. Pre-Upgrade Research

### 1.1 Read the release notes

Before planning any major upgrade, read the full release notes for the target version.

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT version();"
```

Record your current version: ____

Check the PostgreSQL 17 release notes at: `https://www.postgresql.org/docs/17/release-17.html`

Answer these questions:

1. Are there any incompatible changes that affect your application?
   - Answer: ____

2. Are there any removed features you depend on?
   - Answer: ____

3. Are there new features that benefit your workload?
   - Answer: ____

4. Are there any changes to default settings?
   - Answer: ____

### 1.2 Check extension compatibility

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Record:

| Extension | Current Version | Available in PG17? |
|-----------|----------------|-------------------|
| | | |

Verify each extension has a PG17-compatible version available in the PGDG repository.

```bash
exit
```

### 1.3 Check for deprecated features

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT * FROM pg_stat_user_tables WHERE schemaname = 'pg_catalog';"
```

Check if your application uses any deprecated SQL syntax, system catalogs, or functions.

Common items to check:
- `string_agg` without ORDER BY (behavior may change)
- `json` vs `jsonb` usage
- `oid` column references
- Custom C extensions or shared libraries

```bash
exit
```

---

## 2. Pre-Upgrade Checklist

Fill in each item:

### Infrastructure

- [ ] Target version packages available for our OS (CentOS Stream 9)?
- [ ] All extensions have PG17-compatible versions?
- [ ] Sufficient disk space for two PostgreSQL installations during upgrade?
- [ ] Maintenance window scheduled (date/time): ____
- [ ] Maintenance window duration: ____
- [ ] Rollback window: within ____ hours of start

### Backups

- [ ] Full backup taken immediately before upgrade: ____
- [ ] Backup verified (test restore): ____
- [ ] WAL archiving verified: ____
- [ ] PITR recovery tested: ____

### Application

- [ ] Application team notified: ____
- [ ] Read-only mode available for application: ____
- [ ] Application tested against PG17 in staging: ____
- [ ] Connection strings documented: ____
- [ ] ORM/driver PG17 compatibility verified: ____

### Monitoring

- [ ] Alert silencing planned for maintenance window: ____
- [ ] Post-upgrade health check script prepared: ____
- [ ] Rollback alert trigger defined: ____

---

## 3. Upgrade Methods Comparison

### 3.1 pg_upgrade (in-place)

**Pros**:
- Fastest method
- No data export/import needed
- Hard links minimize disk usage

**Cons**:
- Requires downtime
- Old cluster cannot run after upgrade (unless using --copy)
- Statistics are reset

**Best for**: Small to medium databases, short maintenance windows.

### 3.2 Logical replication

**Pros**:
- Near-zero downtime
- Old cluster stays available during migration
- Can upgrade schema selectively

**Cons**:
- Complex setup
- DDL changes during migration are tricky
- Large initial data sync
- Sequences need manual sync

**Best for**: Large databases where downtime must be minimal.

### 3.3 pg_dump / pg_restore

**Pros**:
- Simplest method
- Works across any version gap
- Full schema and data export

**Cons**:
- Slowest method
- Requires 2x disk space
- Long downtime proportional to database size

**Best for**: Small databases or when other methods are not feasible.

### Your choice

Based on your database size and downtime tolerance:

- Database size: ____
- Acceptable downtime: ____
- Chosen method: ____
- Reason: ____

---

## 4. Test Upgrade on Replica

### 4.1 Prepare the test environment

The safest way to test a major upgrade is on a copy of your data. Use the standby server.

Step-by-step plan:

1. Stop replication to the standby
2. Promote the standby to an independent server
3. Install PG17 on the standby
4. Run pg_upgrade on the standby
5. Run application test suite against the upgraded standby
6. Record results

### 4.2 pg_upgrade dry run commands

These are the commands you would run (do NOT execute them now):

On the test server, after installing PG17:

```
# Dry run (check only, no changes)
/usr/pgsql-17/bin/pg_upgrade \
    --old-datadir=/opt/pgsql/data \
    --new-datadir=/opt/pgsql/data17 \
    --old-bindir=/usr/pgsql-16/bin \
    --new-bindir=/usr/pgsql-17/bin \
    --check
```

- `--check` - Only checks compatibility. Does not modify anything.
- `--old-datadir` - Path to the existing PG16 data directory.
- `--new-datadir` - Path for the new PG17 data directory.

If the check passes:

```
/usr/pgsql-17/bin/pg_upgrade \
    --old-datadir=/opt/pgsql/data \
    --new-datadir=/opt/pgsql/data17 \
    --old-bindir=/usr/pgsql-16/bin \
    --new-bindir=/usr/pgsql-17/bin \
    --link
```

- `--link` - Uses hard links instead of copying files. Much faster, but the old cluster is unusable after.

### 4.3 Post-upgrade steps

After pg_upgrade completes:

```
# Update statistics (critical for query performance)
/usr/pgsql-17/bin/vacuumdb --all --analyze-in-stages

# Check for any issues
/usr/pgsql-17/bin/psql -c "SELECT datname, age(datfrozenxid) FROM pg_database;"

# Run the delete_old_cluster.sh script (only after verifying everything works)
./delete_old_cluster.sh
```

### 4.4 Test checklist

Run these tests on the upgraded test server:

- [ ] All tables accessible: `SELECT count(*) FROM app.customers;`
- [ ] All indexes exist: `SELECT count(*) FROM pg_indexes WHERE schemaname = 'app';`
- [ ] Extensions loaded: `SELECT extname, extversion FROM pg_extension;`
- [ ] Application queries work: [run your test suite]
- [ ] Replication can be set up from new version
- [ ] Backup tools work with new version
- [ ] Monitoring works with new version
- [ ] No unexpected query plan changes

---

## 5. Rollback Plan

### 5.1 Before the upgrade

Take these actions before starting:

1. Take a full pgBackRest backup

```
pgbackrest --stanza=prod --type=full backup
```

2. Record the current WAL position

```
psql -c "SELECT pg_current_wal_lsn();"
```

3. Export the role definitions

```
pg_dumpall --roles-only > /opt/pgsql/backup/roles-pre-upgrade.sql
```

4. Save the current postgresql.conf and pg_hba.conf

```
cp /opt/pgsql/data/postgresql.conf /opt/pgsql/backup/postgresql.conf.pre-upgrade
cp /opt/pgsql/data/pg_hba.conf /opt/pgsql/backup/pg_hba.conf.pre-upgrade
```

### 5.2 Rollback steps (if upgrade fails)

If using pg_upgrade with --copy (not --link):

1. Stop PG17
2. Restore PG16 binaries
3. Start PG16 with the original data directory
4. Verify application connectivity

If using pg_upgrade with --link:

1. Stop PG17
2. Restore from the pre-upgrade pgBackRest backup
3. Start PG16
4. Verify application connectivity

If using logical replication:

1. Stop writes to PG17
2. Point application back to PG16 (which was never stopped)
3. Verify application connectivity
4. Clean up PG17 instance

### 5.3 Rollback decision criteria

Trigger a rollback if any of these occur:

- [ ] pg_upgrade --check fails on critical errors
- [ ] Application test suite fails on upgraded instance
- [ ] Query performance degrades by more than 20%
- [ ] Any data integrity issue detected
- [ ] Upgrade exceeds the maintenance window

---

## 6. Communication Templates

### 6.1 Pre-upgrade announcement

```
Subject: [PLANNED] PostgreSQL Major Version Upgrade - [DATE]

Team,

We are upgrading PostgreSQL from version 16 to version 17 during the
following maintenance window:

  Date: [DATE]
  Time: [START TIME] - [END TIME] UTC
  Expected downtime: [DURATION]

What to expect:
- The database will be unavailable during the upgrade
- Applications should be placed in maintenance mode before [START TIME]
- We will send an all-clear when the upgrade is complete

Rollback plan:
- If the upgrade fails, we will restore from backup
- Maximum rollback time: [TIME]

If you have concerns, please respond to this email by [DATE - 3 days].

Regards,
[YOUR NAME]
Database Administration
```

### 6.2 Upgrade start notification

```
Subject: [IN PROGRESS] PostgreSQL Upgrade Starting Now

Team,

The PostgreSQL upgrade is starting now.

  Start time: [TIME] UTC
  Expected completion: [TIME] UTC

The database is now offline. Please do not attempt connections.

We will notify you when the upgrade is complete.

Regards,
[YOUR NAME]
```

### 6.3 Upgrade complete notification

```
Subject: [COMPLETE] PostgreSQL Upgrade Successful

Team,

The PostgreSQL upgrade is complete.

  Completion time: [TIME] UTC
  New version: PostgreSQL 17.x
  Downtime: [ACTUAL DURATION]

The database is back online. Applications can resume normal operations.

Post-upgrade monitoring is active. If you notice any issues, please
report them immediately to [CONTACT].

Regards,
[YOUR NAME]
```

### 6.4 Rollback notification

```
Subject: [ROLLBACK] PostgreSQL Upgrade Rolled Back

Team,

The PostgreSQL upgrade has been rolled back to the previous version.

  Rollback reason: [REASON]
  Current version: PostgreSQL 16.x
  Downtime: [ACTUAL DURATION]

The database is back online on the previous version. No data was lost.

We will schedule a follow-up to address the upgrade issues and plan
a new attempt.

Regards,
[YOUR NAME]
```
