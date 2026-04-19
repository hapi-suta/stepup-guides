# Exercise 01: initdb Detective

**Duration:** 20 minutes
**Objective:** Use `pg_controldata` to inspect the internals of existing PostgreSQL clusters and understand what `initdb` configured at creation time.

**Prerequisites:** PG16 running on port 5432 (`/opt/pgsql/data`), PG15 running on port 5433. Single node.

---

## Background

Every PostgreSQL cluster stores metadata about how it was created. The `pg_controldata` command reads this metadata directly from the data directory - no running server required. This is your forensics tool for understanding a cluster's birth certificate.

---

## Question 1: Are data checksums enabled?

Data checksums protect against silent data corruption on disk. When enabled, PostgreSQL calculates a checksum for every data page and verifies it on read.

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

Run `pg_controldata` against the PG16 cluster and look for the checksum field.

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep -i checksum
```

Expected output (yours will differ):

```
Data page checksum version:           1
```

Now check the PG15 cluster.

```bash
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep -i checksum
```

Expected output (yours will differ):

```
Data page checksum version:           0
```

Exit back to ec2-user.

```bash
exit
```

### Answer

- A checksum version of `1` means checksums are **enabled**. This was set during `initdb --data-checksums` (or `-k`).
- A checksum version of `0` means checksums are **disabled**. Once a cluster is created without checksums, you cannot enable them without `pg_checksums --enable` (requires the server to be stopped).

---

## Question 2: What locale was used?

The locale determines how text is sorted and compared. It is baked in at `initdb` time and cannot be changed afterward without recreating the cluster.

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check the locale settings for the PG16 cluster.

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "LC_"
```

Expected output (yours will differ):

```
LC_COLLATE:                           en_US.UTF-8
LC_CTYPE:                             en_US.UTF-8
```

Now check PG15.

```bash
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep "LC_"
```

Expected output (yours will differ):

```
LC_COLLATE:                           en_US.UTF-8
LC_CTYPE:                             en_US.UTF-8
```

Exit back to ec2-user.

```bash
exit
```

### Answer

- `LC_COLLATE` controls string sort order (e.g., does "a" come before "B"?).
- `LC_CTYPE` controls character classification (e.g., what counts as a letter, digit, or whitespace).
- Both are typically `en_US.UTF-8` on US-based servers. These were set by the `--locale` flag (or system default) during `initdb`.

---

## Question 3: What is the WAL segment size?

WAL (Write-Ahead Log) segments are fixed-size files that store transaction log data. The default size is 16 MB, but this can be changed at `initdb` time.

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "Bytes per WAL segment"
```

Expected output (yours will differ):

```
Bytes per WAL segment:                16777216
```

Exit back to ec2-user.

```bash
exit
```

### Answer

16,777,216 bytes = 16 MB. This is the default and is appropriate for most workloads. High-throughput systems sometimes use 64 MB or 256 MB segments to reduce the number of WAL files that need to be managed. This value is set once at `initdb` time with `--wal-segsize` and cannot be changed afterward.

---

## Question 4: What is the system identifier?

Every PostgreSQL cluster has a unique 64-bit system identifier. This number is generated at `initdb` time and never changes. It prevents you from accidentally mixing WAL files or backups between clusters.

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7496032148219837451
```

Now check PG15.

```bash
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7496032291405628190
```

Exit back to ec2-user.

```bash
exit
```

### Answer

The two numbers are different - every cluster gets a unique identifier, even on the same server. This identifier is critical for streaming replication: a standby will refuse to connect to a primary with a different system identifier. It is also embedded in every WAL file and backup, preventing accidental cross-cluster restoration.

---

## Question 5: What catalog version? How does it relate to the PG version?

The catalog version number tells you which internal schema format the cluster uses. It changes between major PostgreSQL versions.

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "Catalog version"
```

Expected output (yours will differ):

```
Catalog version number:               202307071
```

Now check PG15.

```bash
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep "Catalog version"
```

Expected output (yours will differ):

```
Catalog version number:               202209061
```

Exit back to ec2-user.

```bash
exit
```

### Answer

- PG16 uses catalog version `202307071` (July 7, 2023 format).
- PG15 uses catalog version `202209061` (September 6, 2022 format).

The catalog version encodes the date when the internal system catalog format was finalized for that major version. Different catalog versions mean the clusters store system metadata differently - this is why you cannot use `pg_upgrade` across incompatible catalog versions and why you cannot point a PG16 binary at a PG15 data directory.

---

## Question 6: When was the last checkpoint? What timeline?

Checkpoints are points where PostgreSQL flushes all dirty data to disk. The timeline tracks the cluster's history (it increments after recovery from backup or promotion of a standby).

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep -E "Latest checkpoint|TimeLineID"
```

Expected output (yours will differ):

```
Latest checkpoint location:           0/15A2C60
Latest checkpoint's REDO location:    0/15A2C28
Latest checkpoint's TimeLineID:       1
Latest checkpoint's PrevTimeLineID:   1
```

Exit back to ec2-user.

```bash
exit
```

### Answer

- **Latest checkpoint location** is the WAL position where the last checkpoint completed. PostgreSQL needs this to know where to start recovery from if it crashes.
- **TimeLineID = 1** means this cluster has never been recovered from a backup or promoted from standby. Each time one of those events happens, the timeline increments (2, 3, etc.). In streaming replication and PITR scenarios, timelines prevent WAL from different "histories" from getting mixed up.

---

## Summary

`pg_controldata` is a read-only forensics tool. It works even when the server is stopped. In production, you will use it to:

- Verify checksums are enabled before deploying
- Confirm system identifiers match between primary and standby
- Check the timeline after a failover
- Investigate why a cluster will not start (corrupted control file)
