# Logical Replication - Concepts (15 min)

## What Is Logical Replication?

Logical replication copies data changes at the **table level** instead of copying raw disk blocks. PostgreSQL reads the WAL (Write-Ahead Log), **decodes** the changes back into SQL-like operations (INSERT, UPDATE, DELETE), and sends those decoded changes to another server that applies them independently.

This is different from physical (streaming) replication, which copies the entire cluster byte-for-byte.

Think of it this way:
- **Physical replication** = photocopying every page of a book (exact clone)
- **Logical replication** = reading the book out loud so someone else can write down just the chapters they care about

---

## The Publication / Subscription Model

Logical replication uses a **publisher-subscriber** pattern:

1. The **publisher** (source) creates a **publication** - a set of tables whose changes it will broadcast.
2. The **subscriber** (target) creates a **subscription** - a connection to the publisher that receives and applies those changes.

One publisher can have many subscribers. One subscriber can subscribe to many publishers.

```
 Publisher (pg-suta-labs-1)              Subscriber (pg-suta-labs-2)
+-----------------------+          +-----------------------+
| labdb                 |          | labdb                 |
|                       |          |                       |
| products table -------+-- WAL --+-> products table      |
| (publication)         | decoded  |   (subscription)      |
+-----------------------+          +-----------------------+
```

---

## Physical vs Logical Replication

| Feature                  | Physical (Streaming)         | Logical                          |
|--------------------------|------------------------------|----------------------------------|
| **What it copies**       | Entire cluster (all DBs)     | Selected tables in one database  |
| **Granularity**          | Cluster-level                | Table-level (can filter rows/cols)|
| **Cross-version**        | No - must be same PG version | Yes - different PG versions OK   |
| **DDL replication**      | Yes (automatic)              | No - must apply DDL manually     |
| **Subscriber writable?** | No (read-only standby)       | Yes - subscriber is read-write   |
| **Conflict handling**    | No conflicts possible        | Conflicts possible (must handle) |
| **Sequence sync**        | Yes (automatic)              | No - sequences not replicated    |
| **Use case**             | HA / disaster recovery       | Upgrades, partial replication    |

---

## How It Works Under the Hood

1. **Publisher** writes changes to WAL (same as always).
2. A **logical decoding plugin** (pgoutput) reads the WAL and converts raw bytes into logical change records: "INSERT into products values (1, 'Widget', 9.99)".
3. A **replication slot** on the publisher tracks how far the subscriber has consumed. WAL is retained until the subscriber confirms it.
4. The **walsender** process on the publisher streams decoded changes over the network.
5. A **logical replication worker** on the subscriber receives the changes and applies them using standard SQL operations.

---

## Key Use Cases

**1. Cross-version upgrades**
Replicate from PostgreSQL 15 to PostgreSQL 16. Once caught up, cut over. Zero-downtime upgrade.

**2. Selective table replication**
Only replicate the 3 tables your reporting server needs, not all 200 tables.

**3. Data consolidation**
Multiple source databases publish to one central subscriber (data warehouse pattern).

**4. Blue-green deployments**
Set up a new environment, replicate data to it, test, then switch traffic.

---

## Limitations You Must Know

1. **No DDL replication** - If you ALTER TABLE on the publisher, you must manually run the same ALTER TABLE on the subscriber. Logical rep only moves data, not schema changes.

2. **Sequences are NOT synced** - The subscriber's sequences stay at their initial value (usually 1). You must manually set them before cutover.

3. **Tables need a PRIMARY KEY** - For UPDATE and DELETE to work, the subscriber must identify which row to change. Without a PK (or REPLICA IDENTITY), updates and deletes will fail.

4. **Large objects not replicated** - BLOBs stored via the large object API are not replicated.

5. **TRUNCATE is replicated** - Be careful. A TRUNCATE on the publisher will TRUNCATE on the subscriber too.

6. **Conflicts must be handled manually** - If the same row exists on both sides with different data, the subscriber will stop and log an error. You must resolve it.

---

## Key Terms

| Term                       | Definition                                                                 |
|----------------------------|---------------------------------------------------------------------------|
| **Publication**            | A named set of tables on the publisher whose changes are broadcast        |
| **Subscription**           | A connection on the subscriber that receives and applies changes          |
| **Logical replication slot** | A bookmark on the publisher tracking what the subscriber has consumed   |
| **Logical decoding**       | The process of converting WAL bytes into logical change records           |
| **Origin**                 | Tracks where a change came from, prevents replication loops               |
| **REPLICA IDENTITY**       | Tells PostgreSQL how to identify rows for UPDATE/DELETE (default: PK)     |
| **pgoutput**               | The built-in logical decoding output plugin used by logical replication   |

---

## Quick Check - Can You Answer These?

1. Can you replicate just one table from a database with 50 tables?
2. If you add a new column on the publisher, does the subscriber get it automatically?
3. What happens if a table has no primary key and you try to UPDATE a row?
4. Can you run INSERT statements directly on the subscriber?
5. After logical replication, will the subscriber's sequences be up to date?

**Answers**: 1) Yes. 2) No - you must add the column manually. 3) The subscriber will error out. 4) Yes - the subscriber is read-write. 5) No - you must sync sequences manually.
