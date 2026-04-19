# SQL Fundamentals - Concepts Reference

Quick reference covering the mental models behind Module 05. Read this alongside the build guides.

---

## SQL Execution Order

SQL is declarative - you describe what you want, not how to get it. The database engine decides the execution order. Understanding the logical order prevents confusing errors.

```
1. FROM           - identify and join the source tables
2. WHERE          - filter rows before grouping
3. GROUP BY       - group rows for aggregation
4. HAVING         - filter groups after aggregation
5. SELECT         - compute output columns and expressions
6. DISTINCT       - remove duplicates (if specified)
7. ORDER BY       - sort the result
8. LIMIT / OFFSET - trim the final result
```

**Why this matters:**

- You cannot use a SELECT alias in WHERE: `WHERE revenue > 1000` fails if `revenue` is defined in SELECT - WHERE runs first.
- You can use a SELECT alias in ORDER BY: `ORDER BY revenue DESC` works - ORDER BY runs after SELECT.
- You cannot use a window function in WHERE: window functions are computed in the SELECT phase.
- COUNT(*) in HAVING works: HAVING runs after GROUP BY where the aggregation already happened.

---

## Join Types - Visual Guide

Given two tables:

```
customers                     orders
-----------                   ------------------
id | name                     id | customer_id
1  | Alice                    1  | 1
2  | Bob                      2  | 1
3  | Carol                    3  | 99  (orphan)
```

**INNER JOIN** - Only rows with matches on both sides:

```
Result: Alice+order1, Alice+order2
Bob and Carol excluded (no orders), order3 excluded (no customer)
```

**LEFT JOIN** (customers LEFT JOIN orders) - All customers, matched orders or NULL:

```
Result: Alice+order1, Alice+order2, Bob+NULL, Carol+NULL
order3 excluded (no matching customer in the left table)
```

**RIGHT JOIN** (customers RIGHT JOIN orders) - All orders, matched customers or NULL:

```
Result: Alice+order1, Alice+order2, NULL+order3
Bob and Carol excluded (no orders to match against)
```

**FULL OUTER JOIN** - All rows from both sides, NULLs where no match:

```
Result: Alice+order1, Alice+order2, Bob+NULL, Carol+NULL, NULL+order3
```

**CROSS JOIN** - Every combination (Cartesian product):

```
3 customers x 3 orders = 9 rows
```

**The "missing rows" pattern (anti-join):**

Find customers with no orders:

```sql
SELECT c.name
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;
```

---

## Transaction Isolation Levels

PostgreSQL uses Multi-Version Concurrency Control (MVCC). Readers never block writers and writers never block readers. Instead, each transaction sees a snapshot of the database at a point in time.

### Anomalies Defined

**Dirty read:** Session A reads data that Session B has modified but not committed. If B rolls back, A read data that never existed.

**Non-repeatable read:** Session A reads row X, Session B updates and commits row X, Session A reads row X again and sees different data.

**Phantom read:** Session A queries "all rows where amount > 100", Session B inserts a new row with amount = 200 and commits, Session A runs the same query and sees a new row that was not there before.

**Serialization anomaly:** Two transactions produce a combined result that could not occur if they ran sequentially in any order.

### Isolation Level Behavior in PostgreSQL

| Level | What changes between reads | Use case |
|-------|---------------------------|---------|
| READ COMMITTED (default) | See any committed data at the moment of each statement | General OLTP |
| REPEATABLE READ | See only data committed before your first statement | Financial reporting, consistent aggregations |
| SERIALIZABLE | Full SSI - detects and aborts conflicting patterns | Accounting, anything requiring strict correctness |

PostgreSQL does not implement READ UNCOMMITTED - it treats it as READ COMMITTED.

### Key Behaviors

At **READ COMMITTED**: each statement gets a fresh snapshot. Two SELECT statements in the same transaction can return different rows if another session commits between them.

At **REPEATABLE READ**: the transaction snapshot is taken at the first statement. All reads see the same data for the duration of the transaction. Writers on the same row cause a serialization error rather than silently overwriting.

At **SERIALIZABLE**: PostgreSQL tracks read-write dependencies between transactions. If it detects a dependency cycle that would produce non-serializable results, it aborts one transaction with `ERROR: could not serialize access due to read/write dependencies`. Applications must retry.

---

## Reading EXPLAIN Output

```
QUERY PLAN
---------------------------------------------------------------
 Sort  (cost=45.00..46.50 rows=600 width=40)
       (actual time=12.000..12.200 rows=580 loops=1)
   Sort Key: total_amount DESC
   Sort Method: quicksort  Memory: 56kB
   ->  Hash Join  (cost=8.00..18.00 rows=600 width=40)
                  (actual time=0.500..4.000 rows=580 loops=1)
         Hash Cond: (o.customer_id = c.customer_id)
         ->  Seq Scan on orders o  (cost=0.00..8.00 rows=600 width=30)
               Filter: (total_amount > 100)
               Rows Removed by Filter: 300
         ->  Hash  (cost=3.50..3.50 rows=50 width=20)
               Buckets: 1024  Batches: 1  Memory Usage: 11kB
               ->  Seq Scan on customers c  (cost=0.00..3.50 rows=50 width=20)
```

**Reading the tree:** The plan is a tree. The leaf nodes (Seq Scan) execute first. Their output feeds up to the parent node (Hash, Sort, etc.). Read from the most-indented (deepest) level up.

**cost=start..total:** `start` is the cost to return the first row. `total` is the cost for all rows. These are in arbitrary "cost units" (one sequential page read = 1.0). They are useful for comparing plan alternatives, not for predicting wall-clock time.

**rows=N:** Estimated rows returned by this node. Compare to `actual ... rows=N` to see if estimates are accurate.

**actual time=start..end:** Milliseconds. `start` is time to first row. `end` is time for all rows. This is real wall-clock time from EXPLAIN ANALYZE.

**loops=N:** How many times this node executed. If `loops=5`, multiply the timing by 5 to get total time for that node.

**Rows Removed by Filter:** How many rows were read but discarded by the filter. Large numbers here indicate an index would help.

### Node Types

| Node | What It Does | When You See It |
|------|-------------|----------------|
| Seq Scan | Read every row sequentially | No usable index, or small table |
| Index Scan | Follow index to fetch rows | Selective predicate with an index |
| Index Only Scan | Get data from index without touching the table | Query only uses indexed columns |
| Bitmap Index Scan | Build a bitmap of matching row locations, then fetch | Multiple conditions, OR clauses |
| Hash Join | Build hash table from smaller table, probe with larger | Equi-joins between large tables |
| Nested Loop | For each outer row, scan inner | Small inner table or indexed lookup |
| Merge Join | Sort both sides and merge | Pre-sorted data or sorted index scans |
| Sort | Sort rows | ORDER BY without a supporting index |
| Hash Agg | Group with a hash table | GROUP BY |
| Limit | Stop after N rows | LIMIT clause |

---

## Index Types and When to Use Each

### B-Tree (default)

Created by: `CREATE INDEX idx ON table (column);`

Supports: `=`, `<`, `>`, `<=`, `>=`, `BETWEEN`, `IN`, `LIKE 'prefix%'`, `ORDER BY`, `DISTINCT`, `MIN/MAX`

Use for: Most equality and range queries on any data type. The default choice.

Does NOT support: `LIKE '%suffix'`, full-text search, containment of complex types.

### GIN (Generalized Inverted Index)

Created by: `CREATE INDEX idx ON table USING GIN (column);`

Supports: Array containment (`@>`, `&&`), JSONB containment (`@>`) and key existence (`?`), full-text search (`@@`), trigram matching with `pg_trgm` extension.

Use for: JSONB columns you query with `@>` or `?`. Array columns. Full-text search columns.

Tradeoff: Slower to write than B-Tree (needs to index each element). Much faster than Seq Scan for containment queries.

### GiST (Generalized Search Tree)

Created by: `CREATE INDEX idx ON table USING GIST (column);`

Supports: Geometric types, range types, full-text search (`tsvector`), IP addresses with `inet_ops`.

Use for: PostGIS geometry columns, range columns, IP range queries.

### Hash

Created by: `CREATE INDEX idx ON table USING HASH (column);`

Supports: Only `=` (equality).

Use for: Equality-only lookups where B-Tree overhead is measurable. Rarely needed - B-Tree handles equality fine.

### BRIN (Block Range INdex)

Created by: `CREATE INDEX idx ON table USING BRIN (column);`

Supports: `=`, range queries on naturally ordered data.

Use for: Very large append-only tables where values are physically ordered (e.g., timestamps in a logs table). Extremely small index size. Not suitable for randomly ordered data.

### Partial Index

Created by: `CREATE INDEX idx ON table (column) WHERE condition;`

Use for: When you only ever query a specific subset of rows. Example: `WHERE status = 'active'` when 90% of rows are archived. The index is small and fast because it only covers active rows.

### Composite Index

Created by: `CREATE INDEX idx ON table (col1, col2);`

Column order matters:
- The index can be used for queries filtering on `col1` alone, or on `col1 + col2`.
- It cannot be used for queries filtering on `col2` alone (unless the planner can use it with a special scan).
- Put the highest-selectivity column (most unique values) first.

### Index on Expression

Created by: `CREATE INDEX idx ON table (LOWER(email));`

Use for: Queries that always apply a function in the WHERE clause (`WHERE LOWER(email) = ...`). The index stores the pre-computed function result.
