# Build 03 - Prepare the Subscriber

Set up the second server so it is ready to receive the published data.

**Nodes:**
- **pg-suta-labs-1** - the publisher (source of changes)
- **pg-suta-labs-2** - the subscriber (receives changes)

---

## Prepare the Subscriber Node

Now we switch to pg-suta-labs-2 (the subscriber). Open a new terminal or SSH into pg-suta-labs-2.

On **pg-suta-labs-2**, as **ec2-user**:

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@pg-suta-labs-2
```

**Important**: Before we can set up logical replication, the subscriber must be an independent, standalone PostgreSQL server - NOT a physical streaming replica. If pg-suta-labs-2 is currently a streaming replica of pg-suta-labs-1, you need to promote it first.

Switch to the postgres user.

```bash
sudo su - postgres
```

Check if this node is a standby (in recovery).

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

If the result is `t` (true), this is a streaming replica. You must promote it to make it standalone.

```bash
/usr/pgsql-16/bin/pg_ctl promote -D /var/lib/pgsql/16/data
```

Expected output (yours will differ):
```
waiting for server to promote.... done
server promoted
```

Verify it is now standalone.

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

Exit back to ec2-user.

```bash
exit
```

---

## Change wal_level to logical on the Subscriber

On **pg-suta-labs-2**, as **ec2-user**:

This is best practice - it allows the subscriber to act as a publisher later if needed.

Switch to root.

```bash
sudo su -
```

Open postgresql.conf.

```bash
vi /var/lib/pgsql/16/data/postgresql.conf
```

Find the wal_level line (type `/wal_level` in vi) and change it to:

```
wal_level = logical
```

Save and exit vi (Esc, then `:wq`).

Exit back to ec2-user.

```bash
exit
```

Restart PostgreSQL.

```bash
sudo systemctl restart postgresql-16
```

Verify it is running.

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):
```
   Active: active (running) since Sun 2026-06-01 ...
   ...
```

---

## Create the Table Structure on the Subscriber

On **pg-suta-labs-2**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Logical replication does NOT replicate DDL (schema changes). The table must already exist on the subscriber with the same column structure.

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

**If the table already exists** (because pg-suta-labs-2 was a physical replica and had a copy of everything), drop it first so we start clean.

```sql
DROP TABLE IF EXISTS products;
```

Create the products table with the exact same structure as the publisher.

```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    created_at TIMESTAMP DEFAULT now()
);
```

Expected output (yours will differ):
```
CREATE TABLE
```

Verify it is empty.

```sql
SELECT count(*) FROM products;
```

Expected output (yours will differ):
```
 count
-------
     0
(1 row)
```

The table is empty. The subscription will copy the initial data automatically.

---
