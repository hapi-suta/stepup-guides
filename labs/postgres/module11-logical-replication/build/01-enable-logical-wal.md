# Build 01 - Enable Logical WAL on the Publisher

First we make the publisher write enough detail to its write-ahead log for logical replication, then confirm it took effect.

**Nodes:**
- **pg-suta-labs-1** - the publisher (source of changes)
- **pg-suta-labs-2** - the subscriber (receives changes)

---

## Identify the Current Primary

On **pg-suta-labs-1**, as **ec2-user**:

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@pg-suta-labs-1
```

Switch to the postgres user.

```bash
sudo su - postgres
```

Check if this node is the primary (not in recovery).

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

The result should be `f` (false), meaning this is the primary. If it returns `t`, then pg-suta-labs-2 is your actual primary - swap the node names in all steps below.

Exit back to ec2-user.

```bash
exit
```

---

## Check the Current wal_level on the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Query the current wal_level setting.

```bash
/usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

Expected output (yours will differ):
```
 wal_level
-----------
 replica
(1 row)
```

The value is `replica`. Logical replication requires `logical`. We need to change this and restart PostgreSQL.

Exit back to ec2-user.

```bash
exit
```

---

## Change wal_level to logical on the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to root. We need root to edit the PostgreSQL configuration file.

```bash
sudo su -
```

Open postgresql.conf in vi.

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the wal_level line. In vi, type `/wal_level` and press Enter to search for it.

Change the line to:

```
wal_level = logical
```

If the line is commented out (starts with `#`), remove the `#` and set the value.

Save and exit vi by pressing Esc, then typing `:wq` and pressing Enter.

Exit back to ec2-user.

```bash
exit
```

---

## Restart PostgreSQL on the Publisher

On **pg-suta-labs-1**, as **ec2-user**:

Changing wal_level requires a full restart (reload is not enough).

```bash
sudo systemctl restart postgresql-16
```

Verify PostgreSQL is running.

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):
```
   Active: active (running) since Sun 2026-06-01 ...
   ...
```

Confirm the status shows `active (running)`.

---

## Verify wal_level Is Now logical

On **pg-suta-labs-1**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Check the wal_level.

```bash
/usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

Expected output (yours will differ):
```
 wal_level
-----------
 logical
(1 row)
```

The value should now be `logical`. If it still shows `replica`, go back to the step where you changed wal_level to logical and make sure you edited the correct file and saved it.

---
