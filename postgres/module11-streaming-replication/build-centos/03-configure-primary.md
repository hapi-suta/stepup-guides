# Build 03: Configure the Primary (CentOS Stream 9)

Configure NODE1 as the streaming replication primary.

All steps run on NODE1 only unless noted.

---

## Connect to NODE1

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@[NODE1_IP]
```

---

## 1. Edit postgresql.conf

The main PostgreSQL configuration file lives inside the data directory on CentOS Stream 9.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open the config file:

```bash
vi /var/lib/pgsql/16/data/postgresql.conf
```

In vi, you can search for a parameter by typing `/` followed by the parameter name and pressing Enter. For example, `/listen_addresses` will jump to that line. Press `n` to find the next match.

Find each of the following parameters and set them (remove the `#` comment symbol if the line is commented out, then change the value). If a parameter does not exist in the file, add it at the end.

Set or uncomment these parameters:

```
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
wal_log_hints = on
wal_keep_size = 1GB
archive_mode = on
archive_command = 'test ! -f /var/lib/pgsql/16/archive/%f && cp %p /var/lib/pgsql/16/archive/%f'
archive_timeout = 60
```

The `archive_command` line broken down:
- `test ! -f /var/lib/pgsql/16/archive/%f` - checks that the file does NOT already exist in the archive (prevents overwriting)
- `&&` - only runs the next command if the test passes
- `cp %p /var/lib/pgsql/16/archive/%f` - copies the WAL segment to the archive directory
- `%p` is replaced by PostgreSQL with the full path to the WAL file
- `%f` is replaced with just the filename

Save and quit vi: press `Esc`, then type `:wq`, then press Enter.

Exit back to ec2-user:

```bash
exit
```

> **Concept - wal_level = replica**: This is the minimum WAL level that supports streaming replication. It adds enough information to the WAL for a standby to replay it. The default in PG 16 is already `replica`, but always set it explicitly so your config is self-documenting.

> **Concept - max_wal_senders**: Each streaming standby uses one WAL sender process. Set this to at least the number of standbys you plan to run, plus a few spare for pg_basebackup and monitoring tools.

> **Concept - wal_log_hints = on**: This logs full-page images of hint-bit-only changes to WAL. Without it, `pg_rewind` cannot safely rewind a diverged node because some page modifications would be invisible in the WAL. Always enable this if you plan to use `pg_rewind` after a failover (and you should).

> **Concept - wal_keep_size**: Keeps this much WAL on the primary even if no standby has consumed it yet. A safety net for slow standbys. In production, use replication slots instead (which we set up in step 4).

---

## 2. Create the archive directory

WAL segments will be copied here by the `archive_command`. The directory must exist and be owned by the `postgres` user before PostgreSQL can archive anything.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the directory. The `-p` flag creates any needed parent directories and does not error if the directory already exists:

```bash
mkdir -p /var/lib/pgsql/16/archive
```

Verify the directory was created with correct ownership:

```bash
ls -la /var/lib/pgsql/16/
```

Expected output (yours will differ):

```
total 4
drwx------. 4 postgres postgres  51 May 15 14:05 .
drwxr-xr-x. 4 root     root      31 May 15 13:58 ..
drwx------. 2 postgres postgres   6 May 15 14:05 archive
drwx------. 19 postgres postgres 4096 May 15 14:00 data
```

The `archive` directory appears, owned by `postgres`.

Exit back to ec2-user:

```bash
exit
```

---

## 3. Create a replication role

The standby will authenticate to the primary using a dedicated database role. This role needs only the `REPLICATION` and `LOGIN` privileges - nothing else.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the role:

```bash
psql <<SQL
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass_2026';
SQL
```

Verify the role was created with the `rolreplication` flag set to true:

```bash
psql -c "SELECT rolname, rolreplication FROM pg_roles WHERE rolname = 'replicator';"
```

Expected output:

```
  rolname   | rolreplication
------------+----------------
 replicator | t
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Least privilege for replication**: The `replicator` role has only REPLICATION and LOGIN. It cannot read tables, modify data, or create objects. Never use a superuser for replication. If the replication credentials are ever leaked, the attacker cannot access your data.

---

## 4. Create a replication slot

A physical replication slot ensures the primary keeps WAL segments until the standby has consumed them. Without a slot, the primary can recycle WAL that the standby still needs, causing the standby to fall behind irreparably.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the slot:

```bash
psql -c "SELECT pg_create_physical_replication_slot('standby_slot');"
```

Expected output:

```
  pg_create_physical_replication_slot
--------------------------------------
 (standby_slot,)
(1 row)
```

Verify it appears in the catalog. It should show `active = f` because the standby has not connected yet:

```bash
psql -c "SELECT slot_name, active FROM pg_replication_slots;"
```

Expected output:

```
  slot_name   | active
--------------+--------
 standby_slot | f
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Replication slots prevent WAL recycling**: Without a slot, the primary can delete WAL that a lagging standby still needs. With a slot, the primary retains WAL until the standby confirms it has consumed it. The tradeoff: if a standby goes down for days, the slot prevents WAL cleanup and the primary's disk fills. Monitor `pg_replication_slots.active` and drop abandoned slots.

---

## 5. Configure pg_hba.conf for replication

`pg_hba.conf` controls which users can connect, from where, and using what authentication method. You need to add a rule that lets the `replicator` role connect from NODE2 using the replication protocol.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open pg_hba.conf:

```bash
vi /var/lib/pgsql/16/data/pg_hba.conf
```

In vi, press `G` to jump to the last line of the file. Then press `o` to open a new line below and enter insert mode.

Add this line (replace `[NODE2_IP]` with your NODE2's actual IP address):

```
# Replication connections from standby
host    replication     replicator      [NODE2_IP]/32       scram-sha-256
```

The columns in this line:
- `host` - TCP connection (not Unix socket)
- `replication` - this is a special keyword, not a database name. It grants access to the replication protocol
- `replicator` - the role we just created
- `[NODE2_IP]/32` - only this specific IP can connect (`/32` means exactly that IP, no range)
- `scram-sha-256` - authentication method (password, hashed)

Press `Esc`, then type `:wq`, then press Enter to save and quit.

Exit back to ec2-user:

```bash
exit
```

> **Concept - pg_hba.conf for replication**: The `replication` keyword in the database column is special. It allows the role to connect via the replication protocol (used by pg_basebackup and WAL streaming). Without this line, the standby cannot connect even if the role has REPLICATION privilege.

---

## 6. Restart PostgreSQL to apply changes

The changes to `postgresql.conf` and `pg_hba.conf` require a full restart to take effect (not just a reload, because `wal_level` and `max_wal_senders` require a restart):

```bash
sudo systemctl restart postgresql-16
```

Verify the service came back up:

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
* postgresql-16.service - PostgreSQL 16 Database Server
     Active: active (running) since ...
```

Now verify the key settings took effect. Switch to the postgres user:

```bash
sudo -iu postgres
```

Check WAL level:

```bash
psql -c "SHOW wal_level;"
```

Expected output:

```
 wal_level
-----------
 replica
(1 row)
```

Check max_wal_senders:

```bash
psql -c "SHOW max_wal_senders;"
```

Expected output:

```
 max_wal_senders
-----------------
 10
(1 row)
```

Check archive_mode:

```bash
psql -c "SHOW archive_mode;"
```

Expected output:

```
 archive_mode
--------------
 on
(1 row)
```

Check wal_log_hints:

```bash
psql -c "SHOW wal_log_hints;"
```

Expected output:

```
 wal_log_hints
---------------
 on
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

---

## 7. Create a test database with sample data

This data will replicate to the standby. You will use it to verify replication is working in guides 04 and 05.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the database and insert 10,000 rows:

```bash
psql <<SQL
CREATE DATABASE labdb;
\c labdb
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    department TEXT NOT NULL,
    hired_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO employees (name, department)
SELECT 'employee_' || g,
       (ARRAY['engineering','sales','support','ops'])[1 + (g % 4)]
FROM generate_series(1, 10000) g;
SQL
```

`generate_series(1, 10000)` produces 10,000 integers, one per row. The array lookup cycles through the 4 department names.

Verify the row count:

```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected output:

```
 count
-------
 10000
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

---

## 8. Test that NODE2 can reach NODE1 on port 5432

Run on NODE2.

Connect to NODE2 in your second terminal:

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@[NODE2_IP]
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Try to connect to the primary using the replication user:

```bash
psql -h pg-primary -U replicator -d postgres -c "SELECT 1;"
```

When prompted for the password, enter:

```
replicator_pass_2026
```

Expected output:

```
 ?column?
----------
        1
(1 row)
```

If this fails, check:
1. That `[NODE2_IP]` in pg_hba.conf matches this server's actual IP
2. That the hostname `pg-primary` resolves (check `/etc/hosts`)
3. That the AWS security group allows port 5432 from NODE2

Exit back to ec2-user:

```bash
exit
```

---

## Checkpoint

NODE1 (primary) has:
- [x] `wal_level = replica`, `max_wal_senders = 10`, `archive_mode = on`, `wal_log_hints = on`
- [x] Archive directory created at `/var/lib/pgsql/16/archive`
- [x] `replicator` role with REPLICATION privilege and password set
- [x] Physical replication slot `standby_slot` created
- [x] `pg_hba.conf` allows replication from NODE2's IP
- [x] `postgresql-16` restarted and running with new config
- [x] `labdb` database with 10,000 rows in `employees` table
- [x] NODE2 can connect to primary on port 5432 as `replicator`

Proceed to `04-configure-standby.md`.
