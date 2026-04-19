# Module 04 - Creating and Managing Instances
## Guide 01: Create Your First Cluster with initdb

**Objective:** Understand what `initdb` does by examining an existing cluster's fingerprint with `pg_controldata`, then create a brand-new test cluster from scratch with custom options, start it, and tear it down.

**Time:** 25-30 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 running on port 5432 with PGDATA at `/opt/pgsql/data`
- PostgreSQL 15 running on port 5433 with PGDATA at `/opt/pgsql/data15`

---

## 1. Examine the Existing PG16 Cluster

Every PostgreSQL cluster has a fingerprint - a set of decisions that were locked in when `initdb` first created it. The `pg_controldata` command reads this fingerprint from the control file inside PGDATA.

Log in to your server as `ec2-user`:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the `postgres` user. This user owns the data directory and runs all cluster commands:

```bash
sudo -iu postgres
```

Run `pg_controldata` against the PG16 data directory. This reads the `global/pg_control` file and displays every cluster-level setting:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data
```

Expected output (yours will differ):

```
pg_control version number:            1300
Catalog version number:               202307071
Database system identifier:           7629952116069622029
Database cluster state:               in production
...
Data page checksum version:           0
...
```

The output is long. Here are the fields that matter most:

| Field | What It Tells You |
|-------|-------------------|
| `Database system identifier` | A unique 64-bit number assigned when `initdb` runs. No two clusters in the world share this number. Replication uses it to verify primary and replica belong together. |
| `Database cluster state` | Current state: `in production`, `shut down`, `in recovery`, etc. |
| `Data page checksum version` | `0` means checksums are OFF. `1` means checksums are ON. This cannot be changed after `initdb` without `pg_checksums`. |
| `WAL block size` | Size of each WAL record block (always 8192 bytes). |
| `Bytes per WAL segment` | Size of each WAL file. Default is 16 MB (16777216 bytes). |
| `Maximum length of identifiers` | Max length for table/column names (default 64 bytes, set at compile time). |

> **Concept: What is a system identifier?**
> The system identifier is a unique number generated from the timestamp and process ID when `initdb` runs. It acts like a cluster's DNA - streaming replication checks this number to make sure a replica was cloned from the right primary. If the identifiers don't match, replication refuses to start. You will see this in Module 11 when you set up streaming replication.

Now filter for just the checksum and WAL segment information. The `grep` command searches for lines matching a pattern:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep -E "checksum|WAL segment"
```

Expected output:

```
Bytes per WAL segment:                16777216
Data page checksum version:           0
```

Note: Checksum version `0` means this cluster was created **without** `--data-checksums`. You will create a new cluster with checksums enabled shortly and see the difference.

Exit the postgres session:

```bash
exit
```

---

## 2. Check Available Locales

Before creating a new cluster, you need to know which locales are installed on the operating system. The locale controls how PostgreSQL sorts text, formats dates, and handles uppercase/lowercase conversions.

As `ec2-user`, list the available English (US) locales. The `locale -a` command shows every locale installed on the system, and we filter for `en_US`:

```bash
locale -a | grep en_US
```

Expected output:

```
en_US
en_US.iso88591
en_US.iso885915
en_US.utf8
```

The one you want is `en_US.utf8` (CentOS displays it this way, but PostgreSQL accepts `en_US.UTF-8` as well - they refer to the same locale).

> **Concept: Why does the locale matter at initdb time?**
> The locale you choose at `initdb` becomes the default for every database in the cluster. It affects `ORDER BY` on text columns, `LIKE` pattern matching performance, and how `upper()`/`lower()` work with accented characters. Changing it later requires re-creating the cluster. For most English-language systems, `en_US.UTF-8` is the right choice. For maximum sort performance with no locale features, some DBAs use `C` or `C.UTF-8`.

---

## 3. Create a Fresh Test Cluster

Now you will create a brand-new cluster from scratch, just like the PG16 cluster was originally created. This lets you see every decision `initdb` makes.

Switch to root to create the data directory:

```bash
sudo su -
```

Create the directory for the test cluster:

```bash
mkdir /opt/pgsql/data-test
```

Set ownership to the `postgres` user. PostgreSQL refuses to run if the data directory is owned by anyone else:

```bash
chown postgres:postgres /opt/pgsql/data-test
```

Set permissions to 700. PostgreSQL requires the data directory to be readable only by the owner - it will refuse to start if other users can read it:

```bash
chmod 700 /opt/pgsql/data-test
```

Exit the root session:

```bash
exit
```

Switch to the `postgres` user to run `initdb`:

```bash
sudo -iu postgres
```

Run `initdb` to create the cluster. Each flag controls a specific decision:

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data-test --data-checksums --locale=en_US.UTF-8 --encoding=UTF8 --wal-segsize=16
```

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.

The database cluster will be initialized with locale "en_US.UTF-8".
The default database encoding has accordingly been set to "UTF8".
The default text search configuration will be set to "english".

Data page checksums are enabled.

...
Success. You can now start the database server using:

    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data-test -l logfile start
```

Here is what each flag does:

| Flag | Purpose |
|------|---------|
| `-D /opt/pgsql/data-test` | The directory where the cluster's files will be created (PGDATA). |
| `--data-checksums` | Enables page-level checksums to detect silent data corruption on disk. |
| `--locale=en_US.UTF-8` | Sets the default locale for sorting, formatting, and case conversion. |
| `--encoding=UTF8` | Sets the default character encoding for all databases. |
| `--wal-segsize=16` | Sets WAL segment file size to 16 MB (this is the default, shown here for explicitness). |

> **Concept: Data checksums - should you always enable them?**
> Yes. Data checksums add a small CRC-32C checksum to every 8 KB data page. When PostgreSQL reads a page from disk, it verifies the checksum. If the page was corrupted by faulty storage, a failing disk, or a misbehaving filesystem, PostgreSQL detects it immediately instead of silently returning wrong data. The CPU overhead is negligible on modern hardware (under 1%). Every production cluster should have checksums enabled.

> **Concept: initdb is a one-time operation**
> Once `initdb` has created a cluster, you cannot re-run it on the same directory. Options like `--data-checksums`, `--locale`, and `--wal-segsize` are permanently baked into the cluster. To change them, you must dump your data, destroy the cluster, run `initdb` with new options, and reload the data. Plan these choices carefully before production.

Verify the files that `initdb` created. The `ls` command lists the contents of the new data directory:

```bash
ls /opt/pgsql/data-test/
```

Expected output:

```
base          pg_commit_ts  pg_logical    pg_replslot   pg_stat      pg_twophase  postgresql.auto.conf
global        pg_dynshmem   pg_multixact  pg_serial     pg_stat_tmp  PG_VERSION   postgresql.conf
log           pg_hba.conf   pg_notify     pg_snapshots  pg_subtrans  pg_wal       pg_ident.conf
pg_xact       pg_tblspc
```

Exit the postgres session:

```bash
exit
```

---

## 4. Compare pg_controldata Between Clusters

Now compare the fingerprints of the existing PG16 cluster and your new test cluster. This shows that each cluster is completely independent.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Check the system identifier for the PG16 cluster:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7490123456789012345
```

Check the system identifier for the test cluster:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data-test | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7495678901234567890
```

The numbers are different. Each cluster got its own unique identifier when `initdb` ran.

Now compare the checksum settings:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "checksum"
```

Expected output:

```
Data page checksum version:           0
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data-test | grep "checksum"
```

Expected output:

```
Data page checksum version:           1
```

The PG16 main cluster has checksums **OFF** (version 0) because it was created without `--data-checksums`. Your test cluster has checksums **ON** (version 1) because you used `--data-checksums` in the `initdb` command above. This difference is permanent - you cannot enable checksums on an existing cluster without stopping it and running `pg_checksums --enable`.

Compare WAL segment size:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "Bytes per WAL segment"
```

Expected output:

```
Bytes per WAL segment:                16777216
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data-test | grep "Bytes per WAL segment"
```

Expected output:

```
Bytes per WAL segment:                16777216
```

Both use 16 MB WAL segments (16777216 bytes). Some high-throughput systems use `--wal-segsize=64` to reduce the number of WAL files that get created, but 16 MB is the standard default.

> **Concept: pg_controldata as a cluster fingerprint**
> Think of `pg_controldata` as an X-ray of your cluster. It tells you everything that was decided at creation time and the current state of the cluster. When you inherit a database from another team, `pg_controldata` is the first command to run - it tells you whether checksums are on, what locale was chosen, and whether the cluster shut down cleanly.

Exit the postgres session:

```bash
exit
```

---

## 5. Configure and Start the Test Cluster

The new cluster exists on disk but is not running yet. You need to set a unique port (so it doesn't conflict with PG16 on 5432 or PG15 on 5433) and then start it.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Open the test cluster's `postgresql.conf` to change the port. Use `vi` to edit the file:

```bash
vi /opt/pgsql/data-test/postgresql.conf
```

Find the `#port = 5432` line (you can search with `/port` in vi). Change it to:

```
port = 5435
```

Save and exit vi (`:wq`).

Start the test cluster using `pg_ctl`. The `-D` flag specifies the data directory and `-l` specifies the log file:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-test -l /opt/pgsql/log/pg-test.log
```

Expected output:

```
waiting for server to start.... done
server started
```

Verify the cluster is running with `pg_isready`. The `-p` flag specifies which port to check:

```bash
/usr/pgsql-16/bin/pg_isready -p 5435
```

Expected output:

```
/run/postgresql:5435 - accepting connections
```

Connect to the test cluster and check the version:

```bash
psql -p 5435 -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                  version
-------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x ..., 64-bit
(1 row)
```

Verify your PG16 main cluster is still running independently:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

Both clusters are running side by side on the same server. They share nothing - different data directories, different ports, different system identifiers.

Exit the postgres session:

```bash
exit
```

---

## 6. Tear Down the Test Cluster

The test cluster served its purpose. Always clean up test clusters to avoid port conflicts and wasted disk space.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Stop the test cluster. The `-D` flag tells `pg_ctl` which cluster to stop:

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-test
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Verify it is stopped:

```bash
/usr/pgsql-16/bin/pg_isready -p 5435
```

Expected output:

```
/run/postgresql:5435 - no response
```

Exit the postgres session:

```bash
exit
```

Switch to root to remove the data directory:

```bash
sudo su -
```

Remove the test data directory. The `-rf` flags mean recursive and force (no confirmation prompts):

```bash
rm -rf /opt/pgsql/data-test
```

Verify it is gone:

```bash
ls /opt/pgsql/data-test
```

Expected output:

```
ls: cannot access '/opt/pgsql/data-test': No such file or directory
```

Exit the root session:

```bash
exit
```

---

## Checkpoint

You have completed Guide 01. Verify you understand the following:

- [ ] You can use `pg_controldata` to read a cluster's fingerprint (system identifier, checksum status, WAL segment size)
- [ ] You know that the system identifier is unique per cluster and used by replication to verify primary/replica pairing
- [ ] You can check available locales with `locale -a` before running `initdb`
- [ ] You can create a new cluster with `initdb -D <path> --data-checksums --locale=en_US.UTF-8 --encoding=UTF8`
- [ ] You understand that `initdb` decisions (checksums, locale, WAL segment size) are permanent
- [ ] You can start a cluster on a custom port with `pg_ctl start -D <path> -l <logfile>`
- [ ] You can verify a cluster is running with `/usr/pgsql-16/bin/pg_isready -p <port>`

---

Proceed to **Guide 02 - PostgreSQL Configuration Mastery**
