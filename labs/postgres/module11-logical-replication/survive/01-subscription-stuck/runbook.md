# Survive: Subscription Stuck in Initializing State (8 min)

## The Scenario

You created a subscription, but the data never arrives. The subscription seems stuck and the table on the subscriber stays empty.

---

## Step 1: Check the Subscription Status

On **pg-suta-labs-2**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Check the subscription relation state. This shows the sync status for each table in the subscription.

```sql
SELECT srsubid, srrelid, srsubstate, srsublsn
FROM pg_subscription_rel;
```

Expected output (yours will differ):
```
 srsubid | srrelid | srsubstate | srsublsn
---------+---------+------------+----------
   16421 |   16400 | i          |
(1 row)
```

The `srsubstate` column tells you the state:
- `i` = initializing (copying initial data) - **stuck here**
- `d` = data copy in progress
- `s` = synchronized (waiting for streaming to start)
- `r` = ready (streaming live changes) - **this is the healthy state**

If the state is `i` and it has been more than a few minutes, something is wrong.

---

## Step 2: Check the Subscriber Logs

The PostgreSQL logs will tell you exactly why the sync failed. Exit psql first.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

On **pg-suta-labs-2**, as **ec2-user**:

Check the most recent log file. PostgreSQL on CentOS Stream 9 logs to /var/lib/pgsql/16/data/log/.

```bash
sudo ls -lt /var/lib/pgsql/16/data/log/ | head -3
```

This lists log files sorted by most recent first. The `-l` flag shows details, `-t` sorts by time.

Expected output (yours will differ):
```
total 48
-rw------- 1 postgres postgres 12345 Jun  1 15:30 postgresql-Sun.log
...
```

Read the most recent log file. Replace the filename with the one you see.

```bash
sudo tail -50 /var/lib/pgsql/16/data/log/postgresql-Sun.log
```

The `tail -50` command shows the last 50 lines of the file.

Look for error messages like these:

**Error: Missing primary key**
```
ERROR:  logical replication target relation "public.products" is missing a PRIMARY KEY
```

**Error: Connection refused**
```
ERROR:  could not connect to the publisher: connection to server at "pg-suta-labs-1" (172.31.x.x), port 5432 failed: Connection refused
```

**Error: Authentication failed**
```
FATAL:  password authentication failed for user "replicator"
```

---

## Step 3: Diagnose the Root Cause

### Cause A: Table has no PRIMARY KEY

This is the most common cause. Logical replication needs a way to identify individual rows for UPDATE and DELETE operations. Without a PRIMARY KEY, the subscriber cannot match rows.

On **pg-suta-labs-1**, as **ec2-user**:

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@pg-suta-labs-1
```

Switch to the postgres user.

```bash
sudo su - postgres
```

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Check if the table has a primary key.

```sql
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'products'::regclass AND contype = 'p';
```

Expected output if PK exists:
```
    conname     | contype
----------------+---------
 products_pkey  | p
(1 row)
```

If no rows are returned, the table has no primary key.

**Fix**: Add a primary key to the table on BOTH publisher and subscriber.

On the publisher (still as **postgres** on **pg-suta-labs-1**):

```sql
ALTER TABLE products ADD PRIMARY KEY (id);
```

On the subscriber, open a separate terminal.

On **pg-suta-labs-2**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

```sql
ALTER TABLE products ADD PRIMARY KEY (id);
```

### Cause B: Replication slot does not exist on the publisher

Still as **postgres** on **pg-suta-labs-1** in the psql session on labdb, check the publisher for the replication slot.

```sql
SELECT slot_name, slot_type, active
FROM pg_replication_slots
WHERE slot_name = 'products_sub';
```

Expected output (yours will differ):
```
  slot_name   | slot_type | active
--------------+-----------+--------
 products_sub | logical   | t
(1 row)
```

If no rows are returned, the slot was dropped or never created. You need to drop and recreate the subscription.

### Cause C: pg_hba.conf blocks the connection

Still as **postgres** on **pg-suta-labs-1**, exit psql and check pg_hba.conf.

```sql
\q
```

```bash
cat /var/lib/pgsql/16/data/pg_hba.conf | grep replicator
```

Expected output (yours will differ):
```
host    replication     replicator      172.31.0.0/16           md5
host    all             replicator      172.31.0.0/16           md5
```

If the replicator user is not listed, add a line and reload PostgreSQL.

Exit back to ec2-user.

```bash
exit
```

---

## Step 4: Fix by Dropping and Recreating the Subscription

If the subscription is stuck and cannot recover, the cleanest fix is to drop it and start over.

On **pg-suta-labs-2**, as **ec2-user**, switch to postgres and connect to labdb.

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Drop the stuck subscription.

```sql
DROP SUBSCRIPTION products_sub;
```

Expected output (yours will differ):
```
NOTICE:  dropped replication slot "products_sub" on publisher
DROP SUBSCRIPTION
```

If the drop hangs because it cannot reach the publisher to clean up the slot, use:

```sql
ALTER SUBSCRIPTION products_sub DISABLE;
ALTER SUBSCRIPTION products_sub SET (slot_name = NONE);
DROP SUBSCRIPTION products_sub;
```

This disconnects the subscription from the slot first, then drops it. You will need to manually drop the orphaned slot on the publisher afterward.

Switch to your **publisher terminal** (pg-suta-labs-1). As **ec2-user**, reconnect if needed:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Drop the orphaned replication slot:

```sql
SELECT pg_drop_replication_slot('products_sub');
```

Switch back to the **subscriber terminal** (pg-suta-labs-2). Still as **postgres** on labdb.

Now recreate the subscription. Since the tables already have data, use `copy_data = false` to skip the initial copy (which would fail with duplicate key errors).

```sql
CREATE SUBSCRIPTION products_sub
    CONNECTION 'host=pg-suta-labs-1 port=5432 dbname=labdb user=replicator password=StrongPass123'
    PUBLICATION products_pub
    WITH (copy_data = false);
```

Expected output (yours will differ):
```
NOTICE:  created replication slot "products_sub" on publisher
CREATE SUBSCRIPTION
```

Verify the sync state is progressing.

```sql
SELECT srsubstate FROM pg_subscription_rel;
```

Wait a moment and run it again. You should see it move from `i` to `d` to `r`.

Expected output (yours will differ):
```
 srsubstate
------------
 r
(1 row)
```

The `r` state means the table is synchronized and streaming live changes. The fix worked.

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

---

## Quick Reference: Subscription States

| State | Meaning | Action |
|-------|---------|--------|
| `i` | Initializing | Wait a moment. If stuck, check logs. |
| `d` | Data copy in progress | Large table. Wait for it to finish. |
| `s` | Synced, waiting for streaming | Almost done. Should move to `r` soon. |
| `r` | Ready, streaming live changes | Healthy. No action needed. |
