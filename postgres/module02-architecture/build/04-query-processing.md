# Build 04: Query Processing Pipeline

**Lab 2.4 - How PostgreSQL Processes a SQL Query**
**Duration:** 45 minutes
**Node:** NODE1 only
**Prerequisites:** PostgreSQL 16 running on NODE1. Lab 2.3 completed.

In this lab you will trace a SQL query through all five stages of PostgreSQL's query processing pipeline. You will learn where syntax errors are caught, how views are expanded, and how to read an execution plan. This lab focuses on understanding the pipeline - performance tuning and optimization are covered separately in Module 12.

---

## 1. The 5 Stages Overview

Before you type any commands, take a minute to understand the full journey a SQL query takes inside PostgreSQL. Every single query passes through these five stages in order:

| Stage | Name | What It Does |
|---|---|---|
| 1 | **Parser** | Checks SQL syntax. Catches typos and grammar mistakes. |
| 2 | **Analyzer** | Resolves table and column names. Confirms they actually exist. Determines data types. |
| 3 | **Rewriter** | Expands views and applies rewrite rules. Transforms the query tree. |
| 4 | **Planner** | Decides HOW to execute the query - which scan method, which join strategy, what order. |
| 5 | **Executor** | Actually runs the plan and returns results. |

A query can fail at any stage. A typo fails at the Parser. A missing table fails at the Analyzer. But if the query makes it through all five stages, you get your results.

> **Concept: Pipeline, not monolith.**
> PostgreSQL does not just "run your query." It passes the SQL text through five distinct processing stages. Each stage has one job and hands its output to the next stage. This modular design is what makes PostgreSQL extensible - you can add custom data types, operators, and even rewrite rules without touching the executor.

---

## 2. Stage 1: The Parser

**Run on NODE1 (pg-primary):**

The parser is the first thing that touches your SQL. It reads the raw text and checks whether the syntax is valid SQL. It does NOT check whether tables or columns exist - that comes later.

Log in to NODE1 as `ec2-user`, then switch to root.

```bash
sudo su -
```

**You are now root.**

Switch to the postgres user.

```bash
su - postgres
```

**You are now the postgres user.**

Connect to `labdb`. We connect to `labdb` because that's where the pgbench tables were created in the backup-pitr lab.

```bash
psql -d labdb
```

Run an intentionally broken SQL statement. The word `SELECT` is misspelled as `SELCT`.

```sql
SELCT * FROM pgbench_accounts;
```

Expected output:

```
ERROR:  syntax error at or near "SELCT"
LINE 1: SELCT * FROM pgbench_accounts;
        ^
```

The parser rejected this immediately. It does not recognize `SELCT` as a valid SQL keyword. Notice that the error message points to the exact location of the problem with a caret (`^`).

Now run a query with correct syntax but a table that does not exist.

```sql
SELECT * FROM this_table_does_not_exist;
```

Expected output:

```
ERROR:  relation "this_table_does_not_exist" does not exist
LINE 1: SELECT * FROM this_table_does_not_exist;
                      ^
```

This looks similar, but it is a completely different error from a completely different stage. The parser was fine with the syntax - `SELECT * FROM tablename` is valid SQL. The error came from the analyzer (Stage 2), which tried to look up `this_table_does_not_exist` in the system catalog and could not find it.

> **Concept: Syntax vs semantics.**
> The parser only cares about syntax - is the SQL grammatically correct? The analyzer cares about semantics - do the objects you referenced actually exist? When you see "syntax error," the parser caught it. When you see "relation does not exist" or "column does not exist," the analyzer caught it. Knowing which stage produced an error helps you fix it faster.

---

## 3. Stage 2: The Analyzer

**Run on NODE1 (pg-primary):**

**You are still the postgres user, connected to psql.**

The analyzer takes the parse tree from Stage 1 and resolves every name in it. It looks up table names, column names, function names, and data types in the system catalog (`pg_catalog`). If anything is missing or ambiguous, it raises an error.

Run a query that references a column that does not exist on the `pgbench_accounts` table.

```sql
SELECT nonexistent_column FROM pgbench_accounts;
```

Expected output:

```
ERROR:  column "nonexistent_column" does not exist
LINE 1: SELECT nonexistent_column FROM pgbench_accounts;
               ^
```

The analyzer resolved the table `pgbench_accounts` successfully - it exists. But when it looked for `nonexistent_column` in that table's column list, it could not find it.

Now check which columns actually exist on that table. The `\d` command describes a table's structure.

```sql
\d pgbench_accounts
```

Expected output (yours will differ - sizes vary):

```
              Table "public.pgbench_accounts"
  Column  |     Type      | Collation | Nullable | Default
----------+---------------+-----------+----------+---------
 aid      | integer       |           | not null |
 bid      | integer       |           |          |
 abalance | integer       |           |          |
 filler   | character(84) |           |          |
```

The analyzer checks every column reference against this exact list. If your column name is not here, the query fails at Stage 2.

> **Concept: The system catalog is the source of truth.**
> The analyzer does not guess. It queries PostgreSQL's internal system catalog tables (`pg_class`, `pg_attribute`, `pg_type`, etc.) to verify that every object in your SQL actually exists. This is why DDL changes (like adding a column) take effect immediately for subsequent queries - the catalog is updated first, and the analyzer reads the catalog fresh each time.

---

## 4. Stage 3: The Rewriter

**Run on NODE1 (pg-primary):**

**You are still the postgres user, connected to psql.**

The rewriter transforms the query tree before the planner sees it. Its most common job is expanding views. When you query a view, the rewriter replaces the view reference with the view's underlying SQL definition.

Create a simple view that filters `pgbench_accounts` for rows with a positive balance.

```sql
CREATE VIEW large_accounts AS SELECT * FROM pgbench_accounts WHERE abalance > 0;
```

Expected output:

```
CREATE VIEW
```

Now use `EXPLAIN` to see how PostgreSQL plans to execute a query against this view. The `EXPLAIN` command shows the execution plan without actually running the query.

```sql
EXPLAIN SELECT * FROM large_accounts;
```

Expected output (yours will differ - cost numbers, row estimates, and plan shape vary based on data size):

```
                             QUERY PLAN
---------------------------------------------------------------------
 Seq Scan on pgbench_accounts  (cost=0.00..7.88 rows=1 width=97)
   Filter: (abalance > 0)
(2 rows)
```

> **Note:** If your table is large, you may see `Parallel Seq Scan` and `Gather` nodes instead of a simple `Seq Scan`. This is fine - the key point is that the view `large_accounts` was expanded to show `pgbench_accounts` with the `Filter: (abalance > 0)` condition. The rewriter replaced the view with its underlying query before the planner ever saw it.

Look carefully at the output. There is no mention of `large_accounts` anywhere in the plan. Instead, PostgreSQL shows a scan on `pgbench_accounts` with a `Filter: (abalance > 0)`. The rewriter replaced the view with its underlying query before the planner ever saw it.

> **Concept: Views are not stored results.**
> A view does not store any data. It stores a SQL definition. Every time you query a view, the rewriter expands it into the underlying query, and the planner optimizes the expanded version. This means a view never makes a query faster or slower on its own - it is purely a convenience layer. If you want stored results, you need a materialized view (different concept entirely).

---

## 5. Stage 4: The Planner

**Run on NODE1 (pg-primary):**

**You are still the postgres user, connected to psql.**

The planner is where PostgreSQL decides HOW to execute your query. It considers multiple strategies - different scan methods, join orders, and access paths - and picks the one with the lowest estimated cost. The planner uses table statistics (row counts, value distributions) to make these estimates.

Run `EXPLAIN` on a query that fetches a single row by primary key.

```sql
EXPLAIN SELECT * FROM pgbench_accounts WHERE aid = 1;
```

Expected output (yours will differ - cost numbers, row estimates, and scan type depend on table size):

```
                                          QUERY PLAN
-----------------------------------------------------------------------------------------------
 Index Scan using pgbench_accounts_pkey on pgbench_accounts  (cost=0.29..8.30 rows=1 width=97)
   Index Cond: (aid = 1)
(2 rows)
```

The planner chose an `Index Scan` because it knows there is a primary key index on `aid` and you are looking for exactly one row. It would be wasteful to read the entire table for a single row.

Here is what the cost numbers mean:
- `cost=0.29..8.30` - the first number (`0.29`) is the startup cost (work before the first row is returned). The second number (`8.30`) is the total estimated cost to return all rows. These numbers are in arbitrary units - they are useful for comparing plans, not for predicting wall-clock time.
- `rows=1` - the planner estimates this query will return 1 row.
- `width=97` - each row is estimated to be 97 bytes wide.

Now run a different query that aggregates the entire table.

```sql
EXPLAIN SELECT count(*) FROM pgbench_accounts;
```

Expected output (yours will differ - cost numbers, row estimates, and plan shape vary based on data size):

```
                                              QUERY PLAN
------------------------------------------------------------------------------------------------------
 Aggregate  (cost=6.50..6.51 rows=1 width=8)
   ->  Seq Scan on pgbench_accounts  (cost=0.00..5.00 rows=100 width=0)
(2 rows)
```

> **Note:** If your table is large, PostgreSQL may choose a `Parallel Seq Scan` instead of a regular `Seq Scan`. This is normal - the planner uses parallel workers when it estimates the table is big enough to benefit from them.

The planner chose a completely different strategy. It needs to count every row, so it uses a `Seq Scan` (sequential scan - read every page in the table) followed by an `Aggregate` node that computes the count. Notice the arrow (`->`) that shows the Aggregate node feeds from the Seq Scan node.

Remember: `EXPLAIN` without `ANALYZE` only shows the plan. It does NOT run the query. The row counts and costs are estimates based on statistics, not actual measurements.

> **Concept: The planner is a cost-based optimizer.**
> PostgreSQL does not use a fixed set of rules to choose a plan. It calculates the estimated cost of multiple possible plans and picks the cheapest one. The cost estimates depend on table statistics - row counts, data distribution, and correlation. If these statistics are stale, the planner can choose a bad plan. The `ANALYZE` command (not to be confused with `EXPLAIN ANALYZE`) refreshes these statistics.

---

## 6. Stage 5: The Executor

**Run on NODE1 (pg-primary):**

**You are still the postgres user, connected to psql.**

The executor takes the plan from Stage 4 and actually runs it. To see what the executor does, use `EXPLAIN ANALYZE`. This runs the query for real and adds actual timing and row count information to the plan output.

```sql
EXPLAIN ANALYZE SELECT * FROM pgbench_accounts WHERE aid = 1;
```

Expected output (yours will differ - cost numbers, timing, and row counts vary based on data size):

```
                                                          QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------
 Index Scan using pgbench_accounts_pkey on pgbench_accounts  (cost=0.29..8.30 rows=1 width=97) (actual time=0.015..0.016 rows=1 loops=1)
   Index Cond: (aid = 1)
 Planning Time: 0.085 ms
 Execution Time: 0.035 ms
(4 rows)
```

`EXPLAIN ANALYZE` adds three important pieces of information:

- `actual time=0.015..0.016` - the real time in milliseconds. First number is time to return the first row. Second is time to return all rows.
- `rows=1` (after "actual") - the actual number of rows returned. Compare this to the estimated `rows=1` before it. If these numbers are very different, the planner's statistics are stale.
- `loops=1` - how many times this node was executed. For a simple query this is 1, but inside a nested loop join it can be much higher.

The two timing lines at the bottom are also important:
- `Planning Time` - how long Stage 4 (the planner) took.
- `Execution Time` - how long Stage 5 (the executor) took.
- The total query time is both combined.

---

## 7. Reading an EXPLAIN Output

**Run on NODE1 (pg-primary):**

**You are still the postgres user, connected to psql.**

Now let's read a more complex plan - a join between two tables. This is where the bottom-up reading rule becomes essential.

```sql
EXPLAIN ANALYZE SELECT a.aid, b.bid
FROM pgbench_accounts a
JOIN pgbench_branches b ON a.bid = b.bid
WHERE a.abalance > 0;
```

Expected output (yours will differ - plan shape, costs, timing, row counts, and join strategy all vary based on data size):

```
                                                          QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------
 Hash Join  (cost=1.02..9.50 rows=1 width=8) (actual time=0.030..0.095 rows=0 loops=1)
   Hash Cond: (a.bid = b.bid)
   ->  Seq Scan on pgbench_accounts a  (cost=0.00..7.88 rows=1 width=8) (actual time=0.090..0.090 rows=0 loops=1)
         Filter: (abalance > 0)
         Rows Removed by Filter: 100
   ->  Hash  (cost=1.01..1.01 rows=1 width=4) (actual time=0.010..0.011 rows=1 loops=1)
         Buckets: 1024  Batches: 1  Memory Usage: 9kB
         ->  Seq Scan on pgbench_branches b  (cost=0.00..1.01 rows=1 width=4) (actual time=0.005..0.006 rows=1 loops=1)
 Planning Time: 0.200 ms
 Execution Time: 0.120 ms
(10 rows)
```

> **Note:** This query may take a minute or longer if your `pgbench_accounts` table is large. This is expected - the planner is scanning the entire table. If your table is large, PostgreSQL may choose a `Parallel Seq Scan` instead of a regular `Seq Scan`. This is normal - the planner uses parallel workers when it estimates the table is big enough to benefit from them.

Read this plan from the bottom up, starting with the most indented nodes:

1. **Seq Scan on pgbench_branches b** - the executor reads every row in `pgbench_branches`. This is the innermost node on the right side.
2. **Hash** - the executor builds a hash table from those branch rows. This makes the join lookup fast.
3. **Seq Scan on pgbench_accounts a** with **Filter** - the executor reads every row in `pgbench_accounts` and throws away rows where `abalance` is not greater than 0. The `Rows Removed by Filter` line tells you how many rows were discarded.
4. **Hash Join** - for each remaining account row, the executor looks up `a.bid` in the hash table built from branches. Matching pairs are returned.

The general rule: read the plan from the most indented (deepest) nodes outward and upward. The deepest nodes execute first and feed their results to their parent nodes.

> **Concept: Plans are trees, read bottom-up.**
> An EXPLAIN output is a tree of plan nodes. Each node is an operation (scan, join, sort, aggregate). Child nodes feed rows to their parent. The deepest, most indented node starts first. When reading a plan, always start at the bottom and work your way up to the top node - that top node produces the final result.

---

## 8. Clean Up

**Run on NODE1 (pg-primary):**

**You are still the postgres user, connected to psql.**

Drop the view you created earlier.

```sql
DROP VIEW large_accounts;
```

Expected output:

```
DROP VIEW
```

Exit psql.

```sql
\q
```

Exit back to root.

```bash
exit
```

**You are now root.**

Exit back to ec2-user.

```bash
exit
```

**You are now ec2-user.**

---

## Checkpoint

You have completed Lab 2.4. Verify you can do the following:

- [x] Name the 5 stages of query processing in order (Parser, Analyzer, Rewriter, Planner, Executor)
- [x] Distinguish a parser error (syntax error) from an analyzer error (relation/column does not exist)
- [x] Understand how the rewriter expands views into queries on base tables
- [x] Use `EXPLAIN` to see a query plan without running the query
- [x] Use `EXPLAIN ANALYZE` to see actual execution times and row counts
- [x] Read an `EXPLAIN` output - cost, estimated rows, actual rows, actual time
- [x] Read a multi-node plan from the bottom up

---

You have completed the Architecture Deep Dive module. You now understand how PostgreSQL works internally - its processes, memory, storage, and query processing. These fundamentals will support everything you learn from here forward.
