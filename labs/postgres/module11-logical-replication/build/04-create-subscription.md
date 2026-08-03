# Build 04 - Create the Subscription

Connect the subscriber to the publisher so replication begins.

**Nodes:**
- **pg-suta-labs-1** - the publisher (source of changes)
- **pg-suta-labs-2** - the subscriber (receives changes)

---

## Create a Subscription

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

This is where the magic happens. The subscription tells the subscriber to connect to the publisher, pull the initial data, and then keep listening for new changes.

First, clean up any stale subscription metadata that may have been copied when pg-suta-labs-2 was a physical replica:

```sql
DROP SUBSCRIPTION IF EXISTS products_sub;
```

Now create the subscription:

```sql
CREATE SUBSCRIPTION products_sub
    CONNECTION 'host=pg-suta-labs-1 port=5432 dbname=labdb user=replicator password=StrongPass123'
    PUBLICATION products_pub;
```

- `products_sub` - the name we are giving this subscription.
- `host=pg-suta-labs-1` - the publisher's hostname (from /etc/hosts).
- `user=replicator` - the replication user that already exists on the publisher.
- `PUBLICATION products_pub` - the name of the publication we created on the publisher.

Expected output (yours will differ):
```
NOTICE:  created replication slot "products_sub" on publisher
CREATE SUBSCRIPTION
```

The NOTICE tells you that PostgreSQL automatically created a replication slot on the publisher. This slot ensures the publisher retains WAL until the subscriber has consumed it.

---

## Verify the Subscription

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

Check the subscription exists.

```sql
SELECT subname, subenabled, subconninfo, subpublications
FROM pg_subscription;
```

Expected output (yours will differ):
```
   subname    | subenabled |                              subconninfo                               | subpublications
--------------+------------+------------------------------------------------------------------------+-----------------
 products_sub | t          | host=pg-suta-labs-1 port=5432 dbname=labdb user=replicator password=... | {products_pub}
(1 row)
```

- `subenabled = t` means the subscription is active.

---
