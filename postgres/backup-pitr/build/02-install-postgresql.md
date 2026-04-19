# Build 02: Install PostgreSQL and Create Sample Databases

Install PostgreSQL 16 on NODE1 (full server) and the client tools on NODE2
(backup server). Then create multiple sample databases including a 5GB dataset
that exercises real-world backup scenarios.

---

## 1. Add the PGDG repository (BOTH nodes)

The PGDG (PostgreSQL Global Development Group) repository gives you the latest PostgreSQL packages. CentOS Stream 9 ships with an older version, so we add this repo to get version 16.

Install the repository RPM:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

Disable the built-in PostgreSQL module so it doesn't conflict with the PGDG packages:

```bash
sudo dnf -qy module disable postgresql
```

Expected: repository added, built-in PostgreSQL module disabled.

```
Expected output (yours will differ):
pgdg-redhat-repo-latest.noarch.rpm          12 kB/s |  13 kB     00:01
...
Installed:
  pgdg-redhat-repo-42.0-...
Complete!
```

## 2. Install PostgreSQL 16 on NODE1

On NODE1 only - install the server and contrib packages. `contrib` includes extra utilities like `pgbench` that we'll use later:

```bash
sudo dnf install -y postgresql16-server postgresql16-contrib
```

```
Expected output (yours will differ):
Dependencies resolved.
...
Installed:
  postgresql16-server-16.13-...  postgresql16-contrib-16.13-...  postgresql16-libs-16.13-...
Complete!
```

Do NOT run `postgresql-16-setup --initdb` yet - we will use initdb manually
with custom paths.

## 3. Initialize the data directory with custom paths

Switch to the postgres user. The `-iu` flags give you a full login shell as that user:

```bash
sudo -iu postgres
```

Run initdb to create the database cluster. We specify custom locations for the data files and WAL (write-ahead log) files:

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data \
  --waldir=/opt/pgsql/wal \
  --encoding=UTF8 --locale=en_US.UTF-8
```

(`-D` = where to put the data files, `--waldir` = separate location for WAL files, `--encoding` = character encoding for the cluster)

Expected: `Success. You can now start the database server` message.

```
Expected output (yours will differ):
The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.
...
fixing permissions on existing directory /opt/pgsql/data ... ok
creating subdirectories ... ok
selecting dynamic shared memory implementation ... posix
...
Success. You can now start the database server using:
    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data -l logfile start
```

This creates:
- Data files in `/opt/pgsql/data`
- WAL files in `/opt/pgsql/wal` (with a symlink at `/opt/pgsql/data/pg_wal` pointing there)

Verify the data directory was created:

```bash
ls -la /opt/pgsql/data/
```

Verify the WAL directory was created:

```bash
ls -la /opt/pgsql/wal/
```

Verify the symlink. This should show `pg_wal` pointing to `/opt/pgsql/wal`:

```bash
ls -la /opt/pgsql/data/pg_wal
```

Exit back to ec2-user:

```bash
exit
```

## 4. Configure postgresql.conf for custom paths

Edit the main configuration file. You can use `vim` or any text editor:

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open the configuration file:

```bash
vim /opt/pgsql/data/postgresql.conf
```

Find and set these parameters (some may be commented out with `#` - uncomment them and set the values):

```
# Custom paths
data_directory = '/opt/pgsql/data'
log_directory = '/opt/pgsql/log'
logging_collector = on
log_filename = 'postgresql-%Y-%m-%d.log'

# Accept remote connections
listen_addresses = '*'
```

Save and exit vim.

Exit back to ec2-user:

```bash
exit
```

## 5. Add PostgreSQL tools to the postgres user's PATH

By default, CentOS does not add `/usr/pgsql-16/bin` to the `postgres` user's PATH. This means you would need to type the full path (like `/usr/pgsql-16/bin/psql`) every time. Let's fix that so you can just type `psql`, `pg_dump`, etc.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Add the PostgreSQL bin directory to the `.bash_profile`:

```bash
echo "export PATH=/usr/pgsql-16/bin:\$PATH" >> ~/.bash_profile
```

Also set PGDATA so tools know where the data directory is:

```bash
echo "export PGDATA=/opt/pgsql/data" >> ~/.bash_profile
```

Exit back to ec2-user:

```bash
exit
```

Verify the PATH is set. Switch to postgres again (this reloads `.bash_profile`):

```bash
sudo -iu postgres
```

Check where psql lives:

```bash
which psql
```

Expected: `/usr/pgsql-16/bin/psql`.

```
Expected output:
/usr/pgsql-16/bin/psql
```

Exit back to ec2-user:

```bash
exit
```

From this point on, when you switch to the postgres user, you can use `psql`, `pg_dump`, `pg_restore`, etc. without typing the full path.

## 6. Override systemd to use custom PGDATA

The default systemd unit for postgresql-16 expects `/var/lib/pgsql/16/data`.
We need to override it to point to our custom path.

Open the systemd override editor:

```bash
sudo systemctl edit postgresql-16
```

Add these lines in the editor (between the comment markers):

```
[Service]
Environment=PGDATA=/opt/pgsql/data
```

Save and exit.

Reload systemd so it picks up the override:

```bash
sudo systemctl daemon-reload
```

Enable PostgreSQL to start automatically on boot:

```bash
sudo systemctl enable postgresql-16
```

Start PostgreSQL:

```bash
sudo systemctl start postgresql-16
```

Verify PostgreSQL is running. Switch to the postgres user:

```bash
sudo -iu postgres
```

Check the version:

```bash
psql -c "SELECT version();"
```

Expected: output contains `PostgreSQL 16`.

```
Expected output (yours will differ):
                                                  version
------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.13 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.5.0 20240719 (Red Hat 11.5.0-2), 64-bit
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

Check the systemd service status:

```bash
sudo systemctl status postgresql-16
```

Expected: `active (running)`.

```
Expected output (yours will differ):
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; ...)
    Drop-In: /etc/systemd/system/postgresql-16.service.d
             └─override.conf
     Active: active (running) since Sat 2026-04-19 01:05:00 UTC; ...
   Main PID: 12345 (postmaster)
...
```

Verify the custom paths are active. Switch to postgres:

```bash
sudo -iu postgres
```

```bash
psql -c "SHOW data_directory;"
```

Expected: `/opt/pgsql/data`.

```
Expected output:
  data_directory
-----------------
 /opt/pgsql/data
(1 row)
```

```bash
psql -c "SHOW log_directory;"
```

Expected: `/opt/pgsql/log`.

```
Expected output:
 log_directory
---------------
 /opt/pgsql/log
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

## 7. Install PostgreSQL client on NODE2

On NODE2 only - we need the client tools (psql, pg_dump, pg_restore) but not
the full server:

```bash
sudo dnf install -y postgresql16
```

Set up the PATH for the postgres user on NODE2 as well. Switch to the postgres user:

```bash
sudo -iu postgres
```

Add the PostgreSQL bin directory to the `.bash_profile`:

```bash
echo "export PATH=/usr/pgsql-16/bin:\$PATH" >> ~/.bash_profile
```

Exit back to ec2-user:

```bash
exit
```

Verify the client tools are available. Switch to postgres:

```bash
sudo -iu postgres
```

Check psql:

```bash
psql --version
```

Check pg_dump:

```bash
pg_dump --version
```

Check pg_restore:

```bash
pg_restore --version
```

Expected: all report version 16.

```
Expected output:
psql (PostgreSQL) 16.13
pg_dump (PostgreSQL) 16.13
pg_restore (PostgreSQL) 16.13
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Client-only install**: The backup server does not need a running
> PostgreSQL instance for logical backups and WAL storage. Installing only the
> client package keeps the attack surface small. We will start a temporary PG
> instance on NODE2 later during the PITR exercise.

## 8. Configure NODE1 to accept remote connections

Back on NODE1, edit `pg_hba.conf` to allow NODE2 to connect. This file controls who can connect to PostgreSQL:

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open the client authentication file:

```bash
vim /opt/pgsql/data/pg_hba.conf
```

Add this line at the end (replace `[NODE2_IP]` with your actual IP):

```
# Allow backup server to connect
host    all             postgres        [NODE2_IP]/32       scram-sha-256
```

(`host` = TCP connection, `all` = any database, `postgres` = the user, `/32` = exact IP match, `scram-sha-256` = password authentication method)

Save and exit vim.

Exit back to ec2-user:

```bash
exit
```

Set a password for the postgres role. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "ALTER ROLE postgres PASSWORD 'backup_lab_2026';"
```

Exit back to ec2-user:

```bash
exit
```

Restart PostgreSQL so the pg_hba.conf changes take effect:

```bash
sudo systemctl restart postgresql-16
```

Verify from NODE2. SSH into NODE2 and test the connection:

```bash
PGPASSWORD=backup_lab_2026 /usr/pgsql-16/bin/psql -h pg-primary -U postgres -c "SELECT 1;"
```

Expected: returns `1`.

```
Expected output:
 ?column?
----------
        1
(1 row)
```

## 9. Create the labdb database with 5GB of pgbench data

This is the primary lab database with enough data to make backup and restore
times realistic. Run these on NODE1.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the database:

```bash
createdb labdb
```

Initialize pgbench data with scale factor 330. Each scale factor creates roughly 16MB of data, so 330 gives you approximately 5GB. This will take a few minutes:

```bash
pgbench -i -s 330 labdb
```

(`-i` = initialize, `-s 330` = scale factor of 330)

This creates four tables: `pgbench_accounts` (33M rows), `pgbench_branches`, `pgbench_tellers`, and `pgbench_history`.

Verify the row count:

```bash
psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"
```

Expected: `33000000` (33 million rows).

```
Expected output:
  count
----------
 33000000
(1 row)
```

Check the database size:

```bash
psql -c "SELECT pg_size_pretty(pg_database_size('labdb'));"
```

Expected: approximately 5 GB.

```
Expected output (yours will differ):
 pg_size_pretty
----------------
 5001 MB
(1 row)
```

Stay logged in as postgres for the next steps.

> **Concept - Realistic data volume**: A 5GB database forces you to think about
> backup duration, compression ratios, and network transfer times. Small test
> databases hide problems that surface in production - like a pg_dump that takes
> 45 minutes instead of 5 seconds, or a pg_basebackup that fills your backup
> disk. Practice with realistic sizes.

## 10. Create the appdb database

A realistic schema with foreign keys, indexes, and variety - exercises pg_dump's
handling of dependencies. Still as the postgres user:

Create the database:

```bash
createdb appdb
```

Create tables and insert sample data:

```bash
psql appdb -c "
CREATE TABLE employees(id serial PRIMARY KEY, name text, department text, hired_at timestamptz DEFAULT now());
CREATE TABLE departments(id serial PRIMARY KEY, name text UNIQUE, budget numeric);
INSERT INTO employees(name, department) SELECT 'emp_' || g, (ARRAY['engineering','sales','marketing','hr','finance'])[1 + (g % 5)] FROM generate_series(1, 100000) g;
INSERT INTO departments(name, budget) VALUES ('engineering', 5000000), ('sales', 3000000), ('marketing', 2000000), ('hr', 1500000), ('finance', 4000000);
"
```

Verify the data:

```bash
psql -d appdb -c "
SELECT 'employees' AS tbl, count(*) FROM employees
UNION ALL
SELECT 'departments', count(*) FROM departments;
"
```

Expected:
```
     tbl      | count
--------------+--------
 employees    | 100000
 departments  |      5
```

> **Concept - Why multiple databases?**: Each database exercises different backup
> behaviors. labdb tests large-volume backup performance. appdb tests dependency
> handling (tables with relationships). blobdb tests binary data encoding. A
> realistic cluster always has multiple databases with different characteristics.

## 11. Create the blobdb database

A table with binary data - tests backup handling of large objects and bytea columns.
Still as the postgres user:

Create the database:

```bash
createdb blobdb
```

Create a table with binary data and insert 1000 rows:

```bash
psql blobdb -c "
CREATE TABLE documents(id serial PRIMARY KEY, title text, content bytea, created_at timestamptz DEFAULT now());
INSERT INTO documents(title, content) SELECT 'doc_' || g, decode(repeat(md5(g::text), 64), 'hex') FROM generate_series(1, 1000) g;
"
```

Verify:

```bash
psql -d blobdb -c "SELECT count(*), pg_size_pretty(sum(length(content))) AS total_size FROM documents;"
```

Expected: 1000 rows with total size in megabytes.

```
Expected output (yours will differ):
 count | total_size
-------+------------
  1000 | 2048 kB
(1 row)
```

> **Concept - Binary data in backups**: bytea columns are encoded as hex in plain
> SQL dumps, making them much larger than the original binary data. Custom and
> directory formats handle binary data more efficiently with compression. If your
> database uses large objects (lo_*), pg_dump needs the --blobs flag (default in
> PG 16). Understanding how binary data affects backup size is critical for
> capacity planning.

## 12. Verify all databases

List all databases:

```bash
psql -c "\l"
```

Expected: you see `labdb`, `appdb`, and `blobdb` in the list alongside the
default `postgres` and `template0`/`template1`.

Check the size of each lab database:

```bash
psql -c "
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datname IN ('labdb','appdb','blobdb')
ORDER BY datname;
"
```

Expected: labdb is approximately 5GB, appdb and blobdb are much smaller.

```
Expected output (yours will differ):
 datname | size
---------+---------
 appdb   | 22 MB
 blobdb  | 10 MB
 labdb   | 5001 MB
(3 rows)
```

Exit back to ec2-user:

```bash
exit
```

---

## Checkpoint

- [x] PostgreSQL 16 installed on NODE1
- [x] initdb run with custom --waldir=/opt/pgsql/wal
- [x] postgresql.conf configured for /opt/pgsql/log
- [x] systemd override set for PGDATA=/opt/pgsql/data
- [x] PATH configured for postgres user on both nodes
- [x] PostgreSQL 16 running on NODE1 with custom paths
- [x] postgresql16 client tools installed on NODE2
- [x] NODE1 accepts connections from NODE2
- [x] labdb exists with ~5GB pgbench data (33M rows)
- [x] appdb exists with employees (100K rows) and departments (5 rows)
- [x] blobdb exists with 1000 binary data rows
- [x] All databases visible in `\l`

Proceed to `03-logical-backups.md`.
