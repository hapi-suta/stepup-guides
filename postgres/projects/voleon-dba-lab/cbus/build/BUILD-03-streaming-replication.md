# Build Guide 03: Setup Streaming Replication

| | |
|---|---|
| **Time** | 45 minutes |
| **Servers** | pg-primary (3.90.199.62), pg-replica (3.91.32.84) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- What streaming replication is and why it matters
- How to install PostgreSQL 17 on the replica without initializing it
- How to create a replication slot on the primary
- How to take a base backup using pg_basebackup
- How to verify replication is running in both directions
- How to test that changes on the primary appear on the replica

## Prerequisites

- BUILD-01 complete: PostgreSQL 17 installed and running on pg-primary
- BUILD-02 complete: The `replicator` role exists on pg-primary with REPLICATION privileges
- You can SSH into both servers

---

## Step 1: Understand Streaming Replication

Before you touch a single command, spend 2 minutes reading this. It will make everything else make sense.

PostgreSQL streaming replication works like this:

1. The **primary** server accepts all writes. Every change is written to the WAL (Write-Ahead Log) - a sequential log of every database operation.
2. The **replica** connects to the primary over the network and streams those WAL records in real time.
3. The replica applies those WAL records to its own copy of the data, staying in sync.

The replica is in **read-only mode** (called "recovery mode"). You can run SELECT queries on it, but you cannot INSERT, UPDATE, or DELETE - those go to the primary.

A **replication slot** ensures the primary does not delete WAL files that the replica still needs. Without a slot, if the replica falls behind, the primary might clean up WAL files the replica has not read yet, and replication breaks.

The `-R` flag in pg_basebackup writes a `standby.signal` file in the data directory. When PostgreSQL sees that file at startup, it knows to boot in standby (replica) mode instead of primary mode.

---

## Step 2: Install PostgreSQL 17 on pg-replica

You need PostgreSQL 17 binaries on pg-replica so you have the pg_basebackup tool and the postgres service. Do NOT run `postgresql-17-setup initdb` - that would create an empty data directory. We want pg_basebackup to create the data directory by copying it from the primary.

SSH into pg-replica first.

On your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

Now you are on **pg-replica** as **ec2-user**. Add the PostgreSQL YUM repository. This tells dnf where to download PostgreSQL packages from.

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

```
Expected output (yours will differ):
Last metadata expiration check: ...
pgdg-redhat-repo-latest.noarch.rpm    27 kB/s |  11 kB     00:00
...
Complete!
```

Disable the default CentOS Stream PostgreSQL module. CentOS Stream 9 ships with an older PostgreSQL - this command prevents it from interfering with the version we want.

```bash
sudo dnf -qy module disable postgresql
```

Install the PostgreSQL 17 server and contrib packages. `postgresql17-server` gives you the postgres daemon and data tools. `postgresql17-contrib` adds extra modules used in production environments.

```bash
sudo dnf install -y postgresql17-server postgresql17-contrib
```

```
Expected output (yours will differ):
Last metadata expiration check: ...
Installed:
  postgresql17-17.x...
  postgresql17-server-17.x...
  postgresql17-contrib-17.x...
Complete!
```

Confirm the binary exists. This also tells us pg_basebackup is available.

```bash
/usr/pgsql-17/bin/postgres --version
```

```
Expected output (yours will differ):
postgres (PostgreSQL) 17.x
```

Do NOT run `initdb` or `postgresql-17-setup initdb`. The base backup will create the data directory. If you run initdb here, you will have to delete the data directory before the next step.

---

## Step 3: Verify the Replicator Role on pg-primary

The `replicator` role was created in BUILD-02. Before going further, confirm it exists and has the right attributes.

Open a second terminal. SSH into pg-primary.

On your local machine (new terminal window):

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user** - switch to the postgres user:

```bash
sudo su - postgres
```

Now you are on **pg-primary** as **postgres**. Connect to the database:

```bash
psql
```

Check the replicator role:

```sql
\du replicator
```

```
Expected output (yours will differ):
                   List of roles
  Role name  |       Attributes
-------------+-------------------------------
 replicator  | Replication
```

You should see `Replication` in the Attributes column. If the role is missing, run:

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_voleon_2026';
```

Exit psql but stay as postgres - you need it for the next step:

```sql
\q
```

---

## Step 4: Verify pg_hba.conf Allows Replication from the Private Network

The `pg_hba.conf` file controls who can connect to PostgreSQL and how. The replica needs to connect using the `replication` pseudo-database entry.

On **pg-primary**, as **postgres**. Check the replication entry:

```bash
grep replication /var/lib/pgsql/17/data/pg_hba.conf
```

```
Expected output (yours will differ):
host    replication     replicator      172.31.0.0/16           scram-sha-256
```

You need a line that looks like the above - `replication` in the database column, `replicator` as the user, covering the `172.31.0.0/16` private subnet (both servers are in that subnet).

If that line is missing, open the file:

```bash
vi /var/lib/pgsql/17/data/pg_hba.conf
```

Add this line near the bottom, after the existing host entries:

```
host    replication     replicator      172.31.0.0/16           scram-sha-256
```

Save and exit vi: press `Esc`, then type `:wq` and press Enter.

If you made a change, reload PostgreSQL as ec2-user (do NOT use pg_ctl reload as postgres for service-managed instances - use systemctl):

First exit the postgres shell:

```bash
exit
```

Now you are back as **ec2-user** on **pg-primary**. Reload:

```bash
sudo systemctl reload postgresql-17
```

If you did not need to make changes, stay as postgres for the next step. If you did make changes, switch back:

```bash
sudo su - postgres
```

---

## Step 5: Create a Replication Slot on pg-primary

A replication slot is a bookmark that tells the primary "do not throw away WAL files until this replica has read them." Without a slot, if your replica is offline for a few hours and the primary recycles its WAL files, replication breaks permanently when the replica comes back.

On **pg-primary**, as **postgres** - connect to psql:

```bash
psql
```

Create the replication slot:

```sql
SELECT * FROM pg_create_physical_replication_slot('replica_slot');
```

```
Expected output (yours will differ):
   slot_name   | lsn
---------------+-----
 replica_slot  |
(1 row)
```

Verify the slot exists:

```sql
SELECT slot_name, slot_type, active FROM pg_replication_slots;
```

```
Expected output (yours will differ):
   slot_name   | slot_type | active
---------------+-----------+--------
 replica_slot  | physical  | f
(1 row)
```

`active` is `f` (false) because the replica is not connected yet. It will flip to `t` after the replica starts.

Exit psql:

```sql
\q
```

Exit the postgres shell:

```bash
exit
```

---

## Step 6: Take the Base Backup on pg-replica

The base backup is a full physical copy of the primary's data directory. pg_basebackup copies every file over the network and puts it in the replica's data directory. The `-R` flag also writes the connection details so PostgreSQL knows how to stream WAL after startup.

Switch to your **pg-replica terminal**. You should still be on pg-replica as ec2-user.

Switch to the postgres user:

```bash
sudo su - postgres
```

Now you are on **pg-replica**, as **postgres**. Run the base backup. Read the flag explanations below before running this - it will prompt for a password.

```bash
/usr/pgsql-17/bin/pg_basebackup -h 172.31.19.86 -U replicator -D /var/lib/pgsql/17/data -Fp -Xs -P -R -S replica_slot
```

When prompted, enter the replicator password:

```
Password: repl_voleon_2026
```

Flag explanation:

- `-h 172.31.19.86` - connect to pg-primary using its private IP (faster and more reliable than the public IP inside AWS)
- `-U replicator` - use the replicator role (which has REPLICATION privilege)
- `-D /var/lib/pgsql/17/data` - write the base backup into this directory (the standard PostgreSQL data directory path)
- `-Fp` - "format plain" - copy files as-is, not as a tar archive
- `-Xs` - "WAL method stream" - stream WAL changes happening during the backup so the backup is consistent when it finishes
- `-P` - show a progress indicator as files are copied
- `-R` - write a `standby.signal` file and add `primary_conninfo` to `postgresql.auto.conf` so the replica knows where to connect
- `-S replica_slot` - tell the replica to use the `replica_slot` replication slot we created on the primary

```
Expected output (yours will differ):
28528/28528 kB (100%), 1/1 tablespace
```

The backup is complete when you see 100%. It may take a minute depending on how much data is on the primary.

---

## Step 7: Verify standby.signal and postgresql.auto.conf

After pg_basebackup finishes, confirm the two key files were written correctly. These files are what tell PostgreSQL to boot in standby mode.

On **pg-replica**, still as **postgres**:

Check that standby.signal exists:

```bash
ls -la /var/lib/pgsql/17/data/standby.signal
```

```
Expected output (yours will differ):
-rw------- 1 postgres postgres 0 Jun 15 14:23 /var/lib/pgsql/17/data/standby.signal
```

The file is empty (0 bytes) - that is normal. Its presence is all that matters. PostgreSQL sees this file at startup and knows to enter standby mode.

Check the auto.conf for the primary connection info:

```bash
cat /var/lib/pgsql/17/data/postgresql.auto.conf
```

```
Expected output (yours will differ):
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
primary_conninfo = 'user=replicator password=repl_voleon_2026 host=172.31.19.86 port=5432 sslmode=prefer sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'
primary_slot_name = 'replica_slot'
```

You should see `primary_conninfo` pointing to `172.31.19.86` (the primary's private IP) and `primary_slot_name = 'replica_slot'`.

Exit the postgres shell:

```bash
exit
```

---

## Step 8: Start PostgreSQL on pg-replica

Now start the PostgreSQL service on the replica. Because `standby.signal` exists, it will boot in standby mode and begin streaming WAL from the primary.

On **pg-replica**, as **ec2-user**:

Start the service:

```bash
sudo systemctl start postgresql-17
```

Enable it so it starts automatically on reboot:

```bash
sudo systemctl enable postgresql-17
```

```
Expected output (yours will differ):
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-17.service ...
```

Check that the service started successfully:

```bash
sudo systemctl status postgresql-17
```

```
Expected output (yours will differ):
* postgresql-17.service - PostgreSQL 17 Database Server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled; ...)
     Active: active (running) since ...
...
```

You want `Active: active (running)`. If it shows `failed`, check the logs:

```bash
sudo journalctl -u postgresql-17 -n 30
```

---

## Step 9: Verify Replication is Running

Now check both sides to confirm replication is active.

### Check the primary side

Switch to your **pg-primary terminal**. On **pg-primary**, as **ec2-user** - switch to postgres:

```bash
sudo su - postgres
```

Connect to psql:

```bash
psql
```

Query the replication status. This view shows all replicas currently streaming from this primary:

```sql
SELECT client_addr, state, sent_lsn, write_lsn, replay_lsn FROM pg_stat_replication;
```

```
Expected output (yours will differ):
  client_addr  |   state   | sent_lsn  | write_lsn | replay_lsn
---------------+-----------+-----------+-----------+------------
 172.31.22.69  | streaming | 0/5000060 | 0/5000060 | 0/5000060
(1 row)
```

- `client_addr` - the replica's private IP (172.31.22.69)
- `state` - should be `streaming` (not `startup` or `catchup`)
- `sent_lsn`, `write_lsn`, `replay_lsn` - Log Sequence Numbers showing how far WAL has been sent, written, and applied. When they match, there is zero lag.

Check the replication slot is now active:

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

```
Expected output (yours will differ):
   slot_name   | active
---------------+--------
 replica_slot  | t
(1 row)
```

`active` is now `t` (true) - the replica is connected and using the slot.

Exit psql but stay as postgres for the next step:

```sql
\q
```

### Check the replica side

Switch to your **pg-replica terminal**. On **pg-replica**, as **ec2-user** - switch to postgres:

```bash
sudo su - postgres
```

Connect to psql:

```bash
psql
```

Confirm this server is in recovery (standby) mode:

```sql
SELECT pg_is_in_recovery();
```

```
Expected output (yours will differ):
 pg_is_in_recovery
-------------------
 t
(1 row)
```

`t` means true - this server is a standby. If you see `f`, something is wrong (standby.signal may be missing).

Check the WAL receiver status. This shows the replica's perspective of the streaming connection:

```sql
SELECT * FROM pg_stat_wal_receiver;
```

```
Expected output (yours will differ):
-[ RECORD 1 ]---------+------------------------------------------------------
pid                   | 12345
status                | streaming
receive_start_lsn     | 0/5000000
receive_start_tli     | 1
written_lsn           | 0/5000060
flushed_lsn           | 0/5000060
received_tli          | 1
last_msg_send_time    | 2026-06-15 14:25:01.123+00
last_msg_receipt_time | 2026-06-15 14:25:01.098+00
...
```

`status` should be `streaming`. The `last_msg_send_time` and `last_msg_receipt_time` timestamps should be recent (within the last few seconds).

Exit psql:

```sql
\q
```

---

## Step 10: Test Replication End-to-End

Create a table on the primary and verify it appears on the replica. This is the real proof that replication is working.

On **pg-primary**, as **postgres** (you should already be in this shell):

```bash
psql
```

Create a test table and insert some rows:

```sql
CREATE TABLE replication_test (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO replication_test (message) VALUES
    ('Row 1 from primary'),
    ('Row 2 from primary'),
    ('Row 3 from primary');

SELECT * FROM replication_test;
```

```
Expected output (yours will differ):
 id |       message        |          created_at
----+----------------------+-------------------------------
  1 | Row 1 from primary   | 2026-06-15 14:26:10.123+00
  2 | Row 2 from primary   | 2026-06-15 14:26:10.124+00
  3 | Row 3 from primary   | 2026-06-15 14:26:10.125+00
(3 rows)
```

Exit psql:

```sql
\q
```

Now switch to your **pg-replica terminal**. On **pg-replica**, as **postgres**:

```bash
psql
```

Query the same table:

```sql
SELECT * FROM replication_test;
```

```
Expected output (yours will differ):
 id |       message        |          created_at
----+----------------------+-------------------------------
  1 | Row 1 from primary   | 2026-06-15 14:26:10.123+00
  2 | Row 2 from primary   | 2026-06-15 14:26:10.124+00
  3 | Row 3 from primary   | 2026-06-15 14:26:10.125+00
(3 rows)
```

The rows appear on the replica - replication is confirmed working.

Try inserting on the replica to confirm it is read-only:

```sql
INSERT INTO replication_test (message) VALUES ('This should fail');
```

```
Expected output (yours will differ):
ERROR:  cannot execute INSERT in a read-only transaction
```

That error is expected and correct. Standbys do not accept writes.

Exit psql:

```sql
\q
```

---

## Step 11: Check Replication Lag

Replication lag is the time difference between when a change is committed on the primary and when it is applied on the replica. In a healthy setup with a local network, this should be under 1 millisecond.

On **pg-primary**, as **postgres**:

```bash
psql
```

Check the replication lag in seconds:

```sql
SELECT
    client_addr,
    state,
    EXTRACT(EPOCH FROM write_lag) AS write_lag_seconds,
    EXTRACT(EPOCH FROM flush_lag) AS flush_lag_seconds,
    EXTRACT(EPOCH FROM replay_lag) AS replay_lag_seconds
FROM pg_stat_replication;
```

```
Expected output (yours will differ):
  client_addr  |   state   | write_lag_seconds | flush_lag_seconds | replay_lag_seconds
---------------+-----------+-------------------+-------------------+--------------------
 172.31.22.69  | streaming |                   |                   |
(1 row)
```

NULL values for lag columns mean lag is so small it is unmeasurable - this is ideal. You would see non-NULL values if the replica was under heavy load or had network issues.

Exit psql and exit the postgres shell:

```sql
\q
```

```bash
exit
```

---

## Summary

Streaming replication is now set up. Here is what you built:

- pg-replica has PostgreSQL 17 installed (binaries only, no initdb)
- pg-primary has a replication slot named `replica_slot`
- pg-replica has a full base backup of the primary's data directory
- pg-replica starts in standby mode (standby.signal present)
- WAL is streaming continuously from primary to replica
- Changes on the primary appear on the replica in near real time

In the next guide (BUILD-04), you will set up pgBackRest with simulated Ceph storage for point-in-time recovery.
