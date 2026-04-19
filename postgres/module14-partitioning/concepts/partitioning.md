# Partitioning in PostgreSQL

## What Is Partitioning?

Partitioning splits a single large table into smaller physical pieces called **partitions**. Each partition holds a subset of the data, but queries against the parent table transparently access all partitions. PostgreSQL has supported **declarative partitioning** since version 10, with significant improvements in each major release through 16.

### Why Partition?

- **Query performance** - the planner skips partitions that can't contain matching rows (partition pruning)
- **Maintenance efficiency** - VACUUM, ANALYZE, and REINDEX operate on smaller chunks
- **Bulk data management** - drop an entire partition instead of DELETE + VACUUM
- **Parallel scans** - each partition can be scanned by a separate worker

### When NOT to Partition

- Tables under ~10 million rows rarely benefit
- Queries that don't filter on the partition key scan all partitions (worse than a single table)
- Too many partitions (hundreds+) cause planning overhead
- If your workload is OLTP with point lookups, a good index on a single table is usually faster

---

## Partition Strategies

PostgreSQL supports three strategies. You choose one when creating the partitioned table and cannot change it later.

### Range Partitioning

Splits data by a continuous range of values. Most common for time-series data.

```
                    orders
         ┌────────────┼────────────┐
    orders_2024   orders_2025   orders_2026
    (< 2025-01)   (< 2026-01)   (< 2027-01)
```

```sql
CREATE TABLE orders (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    created_at  timestamptz NOT NULL,
    total       numeric
) PARTITION BY RANGE (created_at);

CREATE TABLE orders_2025_q1 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');
```

Key points:
- FROM is inclusive, TO is exclusive
- Ranges must not overlap
- Gaps between ranges are allowed (inserts into gaps fail unless a default partition exists)

### List Partitioning

Splits data by discrete values. Good for categories, regions, or status codes.

```sql
CREATE TABLE tickets (
    id      bigint GENERATED ALWAYS AS IDENTITY,
    region  text NOT NULL,
    subject text
) PARTITION BY LIST (region);

CREATE TABLE tickets_us PARTITION OF tickets FOR VALUES IN ('us-east', 'us-west');
CREATE TABLE tickets_eu PARTITION OF tickets FOR VALUES IN ('eu-west', 'eu-central');
```

### Hash Partitioning

Distributes data evenly across N partitions using a hash function. Useful when there's no natural range or list, but you want even distribution for parallel processing.

```sql
CREATE TABLE sessions (
    id      uuid PRIMARY KEY,
    data    jsonb
) PARTITION BY HASH (id);

CREATE TABLE sessions_0 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sessions_1 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE sessions_2 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE sessions_3 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```

---

## Partition Pruning

Partition pruning is the optimization that makes partitioning worthwhile. The planner examines WHERE clauses and eliminates partitions that cannot contain matching rows.

```sql
-- Only scans orders_2025_q1 (other partitions pruned)
SELECT * FROM orders WHERE created_at = '2025-02-15';
```

### Static vs Dynamic Pruning

- **Static pruning** - happens at plan time when the value is a constant
- **Dynamic pruning** - happens at execution time when the value comes from a parameter or subquery (PG 11+)

### When Pruning Fails

Pruning requires that the WHERE clause references the partition key directly:

```sql
-- Pruning works
WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01'

-- Pruning FAILS (function wraps the partition key)
WHERE date_trunc('month', created_at) = '2025-01-01'

-- Pruning FAILS (expression on the partition key)
WHERE created_at + interval '1 day' > '2025-01-01'
```

Check with EXPLAIN:

```
Append (cost=...)
  -> Seq Scan on orders_2025_q1  <-- only one partition = pruning worked
```

If you see all partitions listed, pruning is not happening.

The GUC `enable_partition_pruning` controls this (default: on). If set to off, all partitions are always scanned.

---

## Constraints and Indexes

### Unique Constraints

A unique constraint on a partitioned table **must include the partition key**:

```sql
-- This FAILS
ALTER TABLE orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id);

-- This WORKS
ALTER TABLE orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id, created_at);
```

Why? PostgreSQL enforces uniqueness per partition. Without the partition key in the constraint, it can't guarantee global uniqueness efficiently.

### Foreign Keys

As of PostgreSQL 15+, partitioned tables can be referenced by foreign keys. Earlier versions required workarounds.

```sql
-- PG 15+: works
CREATE TABLE order_items (
    id       bigint,
    order_id bigint,
    FOREIGN KEY (order_id, order_created_at) REFERENCES orders (id, created_at)
);
```

### Indexes

Indexes defined on the parent are automatically created on each partition:

```sql
CREATE INDEX ON orders (total);
-- Creates orders_2025_q1_total_idx, orders_2025_q2_total_idx, etc.
```

Each partition gets its own physical index. There is no single global index across all partitions.

**Partial indexes** work per partition. **Expression indexes** work per partition.

---

## Managing Partitions

### Adding New Partitions

```sql
CREATE TABLE orders_2025_q2 PARTITION OF orders
    FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');
```

This takes a brief ACCESS EXCLUSIVE lock on the parent, but the partition is empty so it's fast.

### The Default Partition

A default partition catches rows that don't match any defined partition:

```sql
CREATE TABLE orders_default PARTITION OF orders DEFAULT;
```

Without a default partition, inserting a row that doesn't match any range/list causes an error. With a default partition, it silently lands there - which can hide problems if you forget to create new partitions.

**Best practice**: Create a default partition, but monitor its size. If rows are landing there, you're missing a partition definition.

### Detaching Partitions

```sql
-- Blocks writes briefly
ALTER TABLE orders DETACH PARTITION orders_2024_q1;

-- Non-blocking (PG 14+) - two-phase
ALTER TABLE orders DETACH PARTITION orders_2024_q1 CONCURRENTLY;
```

Once detached, the partition becomes a standalone table. You can archive it, drop it, or move it to another tablespace.

### Attaching Partitions

```sql
ALTER TABLE orders ATTACH PARTITION orders_new
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
```

PostgreSQL validates that all existing rows in the table match the partition constraint. For large tables, this scan can be slow. To avoid it:

1. Add a CHECK constraint matching the partition bounds before attaching
2. PostgreSQL skips validation if the CHECK constraint already guarantees the data fits

```sql
ALTER TABLE orders_new ADD CONSTRAINT chk
    CHECK (created_at >= '2026-01-01' AND created_at < '2026-04-01');
-- Now ATTACH skips the full scan
ALTER TABLE orders ATTACH PARTITION orders_new
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
```

---

## Sub-Partitioning

Partitions can themselves be partitioned:

```
                    orders
            (RANGE by created_at)
         ┌──────────┼──────────┐
    orders_2025   orders_2026   ...
    (LIST by region)
      ┌─────┼─────┐
    us     eu    asia
```

```sql
CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01')
    PARTITION BY LIST (region);

CREATE TABLE orders_2025_us PARTITION OF orders_2025
    FOR VALUES IN ('us');
```

Use sub-partitioning sparingly. Two levels is usually the maximum before planning overhead outweighs benefits.

---

## Maintenance on Partitioned Tables

### VACUUM and ANALYZE

Run against the parent table - PostgreSQL processes each partition:

```sql
VACUUM ANALYZE orders;
```

Or target individual partitions:

```sql
VACUUM ANALYZE orders_2025_q1;
```

Autovacuum treats each partition as a separate table, so thresholds apply per partition. This is generally good - small partitions get vacuumed more frequently.

### Bulk Deletes

Instead of:
```sql
DELETE FROM orders WHERE created_at < '2024-01-01';  -- slow, generates WAL, leaves dead tuples
```

Do:
```sql
ALTER TABLE orders DETACH PARTITION orders_2023;
DROP TABLE orders_2023;  -- instant, no dead tuples
```

This is one of the biggest operational wins from partitioning.

---

## Common Pitfalls

### 1. Too Many Partitions

Every partition adds overhead to query planning. At ~100+ partitions, you may notice slower plan times. At 1000+, it can become severe.

**Solution**: Use wider ranges (monthly instead of daily), or consolidate old partitions.

### 2. Missing Default Partition

Without a default partition, inserts fail if no partition matches. Automated systems can break overnight when a new month starts and no partition exists.

**Solution**: Always create a default partition. Monitor it. Automate partition creation ahead of time.

### 3. Queries Not Using the Partition Key

If most queries don't filter on the partition key, every query scans every partition. This is worse than having a single table.

**Solution**: Choose a partition key that aligns with your most common query patterns.

### 4. Cross-Partition Joins

Joining two partitioned tables on different keys scans all partition combinations. PostgreSQL 12+ has partition-wise joins that help when both tables are partitioned by the same key.

### 5. Global Index Workarounds

PostgreSQL doesn't have global indexes. If you need to look up by a column that's not the partition key, you need to either:
- Add that column to the partition key (often impractical)
- Maintain a separate lookup table
- Accept that the query will scan index on every partition

---

## Monitoring Partitioned Tables

Key queries for DBA daily checks:

```sql
-- Count rows per partition
SELECT
    c.relname AS partition,
    pg_stat_get_live_tuples(c.oid) AS live_tuples
FROM pg_inherits i
JOIN pg_class c ON i.inhrelid = c.oid
WHERE i.inhparent = 'orders'::regclass
ORDER BY c.relname;
```

```sql
-- Size per partition
SELECT
    c.relname AS partition,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_inherits i
JOIN pg_class c ON i.inhrelid = c.oid
WHERE i.inhparent = 'orders'::regclass
ORDER BY pg_total_relation_size(c.oid) DESC;
```

```sql
-- Check for rows in default partition (should be near zero)
SELECT count(*) FROM orders_default;
```

```sql
-- Verify partition pruning with EXPLAIN
EXPLAIN (COSTS OFF)
SELECT * FROM orders WHERE created_at = '2025-03-15';
```

---

## Version History

| Version | Feature |
|---------|---------|
| PG 10 | Declarative partitioning (range, list) |
| PG 11 | Hash partitioning, default partitions, dynamic pruning, index on parent |
| PG 12 | Foreign keys to partitioned tables, partition-wise joins improved |
| PG 13 | Before-row triggers on partitioned tables |
| PG 14 | DETACH CONCURRENTLY, REINDEX CONCURRENTLY on partitioned indexes |
| PG 15 | Foreign keys referencing partitioned tables |
| PG 16 | MERGE support for partitioned tables, improved pruning |

---

## Key Takeaways

1. Partition when tables exceed ~10M rows AND queries filter on the partition key
2. Range partitioning on timestamps is the most common and well-tested pattern
3. Always create a default partition and monitor it
4. Unique constraints must include the partition key
5. Keep partition count under ~100 unless you've benchmarked planning overhead
6. Use DETACH + DROP instead of DELETE for bulk removal
7. Automate future partition creation - don't rely on manual creation
8. Check EXPLAIN output to confirm partition pruning is working
