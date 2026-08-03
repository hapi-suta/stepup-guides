# Concepts: SQL for AI and Analytics

**Read this before you touch the keyboard.** You are a DBA - you know SQL for running databases. This document is about a different use of SQL: preparing and profiling data so it can feed a model or an analytics pipeline. Same language, different job. The examples run against the `support_tickets` table from Project 1 (`labdb`, user `labuser`).

The core idea: **models are only as good as the data you feed them.** Most of the work in AI is not the model - it is finding missing values, duplicates, and outliers, then shaping the data into features. SQL is where that work starts, right at the source, before a single row leaves the database.

Recall the table:

```sql
CREATE TABLE support_tickets (
    id          SERIAL PRIMARY KEY,
    subject     TEXT NOT NULL,
    body        TEXT,
    category    TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);
```

---

## 1. Data profiling: know your data before you use it

**Profiling** means measuring the shape of your data: how many rows, how many distinct values, how much is missing, what the ranges are. You do this first, always, before modeling or reporting.

```sql
-- row count, distinct categories, min/max dates
SELECT
    count(*)                          AS total_rows,
    count(DISTINCT category)          AS distinct_categories,
    min(created_at)                   AS earliest,
    max(created_at)                   AS latest
FROM support_tickets;
```

`count(*)` counts all rows. `count(DISTINCT category)` counts unique non-null categories. Profiling answers "do I even have enough data, and is it what I think it is?" before you waste time on it.

---

## 2. Missing values

Missing data (`NULL`) breaks models and skews counts. Find it first, then decide: fill it, drop it, or flag it.

```sql
-- how many rows are missing each field
SELECT
    count(*) FILTER (WHERE category IS NULL) AS missing_category,
    count(*) FILTER (WHERE body IS NULL)     AS missing_body,
    count(*) FILTER (WHERE subject IS NULL OR trim(subject) = '') AS blank_subject
FROM support_tickets;
```

- `IS NULL` tests for missing values - never `= NULL`, which always evaluates to `NULL` (unknown), so it matches nothing in SQL's three-valued logic.
- `count(*) FILTER (WHERE ...)` counts only rows matching the condition - a clean way to get several conditional counts in one pass. `FILTER` on aggregates is standard SQL, supported in Postgres (see: PostgreSQL docs, SELECT / aggregate expressions).
- `trim(subject) = ''` catches "empty but not null" - a string of spaces. Real data has both. This mirrors `app.py` skipping blank subjects.

---

## 3. Duplicates

Duplicate rows double-count and bias a model toward whatever is repeated. Find them by grouping on the columns that define "the same record".

```sql
-- subjects that appear more than once
SELECT subject, count(*) AS n
FROM support_tickets
GROUP BY subject
HAVING count(*) > 1
ORDER BY n DESC;
```

- `GROUP BY subject` collapses rows with the same subject into one group.
- `HAVING count(*) > 1` keeps only groups with more than one row - `HAVING` filters groups, `WHERE` filters rows before grouping.
- To dedupe keeping the newest, `ROW_NUMBER()` (see window functions below) is the standard tool.

---

## 4. Outliers

An **outlier** is a value far outside the normal range - a body of 50,000 characters, a `created_at` in the year 2099. Outliers are either bad data to clean or rare signal to keep - you must look, not assume.

```sql
-- unusually long ticket bodies
SELECT id, subject, length(body) AS body_len
FROM support_tickets
WHERE body IS NOT NULL
ORDER BY body_len DESC
LIMIT 5;
```

`length(body)` gives character count. Ordering descending and taking the top few surfaces the extremes. For numeric columns, compare against the average and standard deviation, or use percentiles (`percentile_cont`) to define "far from normal".

---

## 5. Aggregations

Aggregations collapse many rows into summary numbers - the heart of analytics. This is the SQL version of Project 1's `/summary`.

```sql
SELECT category, count(*) AS n
FROM support_tickets
GROUP BY category
ORDER BY n DESC;
```

Common aggregate functions: `count()`, `sum()`, `avg()`, `min()`, `max()`. `GROUP BY` defines the buckets; every non-aggregated column in the SELECT must appear in the `GROUP BY` (Postgres relaxes this only when the other columns are functionally dependent on a grouped primary key; treat the strict rule as your default). Doing this count in SQL instead of Python pushes the work to the database, which is far faster over large tables - a key optimization instinct for a DBA moving into AI.

---

## 6. Window functions

A **window function** computes across a set of rows **related to the current row** without collapsing them - unlike `GROUP BY`, you keep every row and add a computed column. This is the single most valuable analytical SQL skill, and a guaranteed interview question.

```sql
-- rank tickets within each category by recency, and show a running count
SELECT
    id, subject, category, created_at,
    row_number() OVER (PARTITION BY category ORDER BY created_at DESC) AS recency_rank,
    count(*)     OVER (PARTITION BY category)                         AS category_size
FROM support_tickets;
```

- `OVER (...)` turns an ordinary function into a window function; the rows keep their separate identities instead of collapsing into one output row (see: PostgreSQL docs, Window Functions).
- `PARTITION BY category` = "restart the calculation for each category" (like `GROUP BY`, but rows are kept).
- `ORDER BY created_at DESC` orders rows inside each partition.
- `row_number()` numbers rows 1, 2, 3... within the partition - the standard dedupe and "top-N-per-group" tool.

Other window functions: `rank()` / `dense_rank()` (ranking with ties), `lag()` / `lead()` (previous/next row - essential for time-series deltas), `sum() OVER (...)` (running totals). Use a window function whenever you need a per-row value that depends on other rows: rank, running total, "compared to the group average", "change since last event".

---

## 7. Sampling

For large tables you often want a representative subset - for a quick look, for a test set, or to fit in memory.

```sql
-- a random 20% sample
SELECT * FROM support_tickets TABLESAMPLE BERNOULLI (20);

-- 5 random rows
SELECT * FROM support_tickets ORDER BY random() LIMIT 5;
```

`TABLESAMPLE BERNOULLI (20)` returns approximately 20% of rows by testing each row independently; the faster `TABLESAMPLE SYSTEM (20)` samples whole disk blocks (less statistically even). Add `REPEATABLE (seed)` for a reproducible sample (see: PostgreSQL docs, SELECT / TABLESAMPLE). `ORDER BY random() LIMIT n` is simpler and fine for small tables (but scans the whole table). When you build train/test splits, prefer a deterministic method (hash of the id) so the split is reproducible.

---

## 8. Feature preparation

A **feature** is a single input column a model reads. Feature prep is turning raw columns into clean, numeric, model-ready ones. Much of it is plain SQL.

```sql
SELECT
    id,
    lower(trim(subject))                          AS subject_clean,   -- normalize text
    coalesce(category, 'uncategorized')           AS category_filled, -- fill missing
    length(coalesce(body, ''))                    AS body_len,        -- derived numeric feature
    (category IS NULL)::int                        AS was_uncategorized, -- boolean -> 0/1
    extract(hour FROM created_at)                 AS created_hour     -- time feature
FROM support_tickets;
```

- `lower(trim(...))` - normalize text so "Login " and "login" are the same feature.
- `coalesce(x, default)` - replace `NULL` with a default; the SQL twin of Python's `x or default`.
- `::int` - cast; `(condition)::int` turns a boolean into 0/1, which is how models want it.
- `extract(hour FROM ...)` - pull a numeric part out of a timestamp for a time feature.

This is exactly the cleaning `app.py` does in Python, done in SQL instead. Doing it in SQL is often faster and keeps the logic next to the data.

---

## 9. Time-series queries

Support tickets, logs, and metrics are time series. The core move is bucketing by a time period and counting.

```sql
-- tickets per day
SELECT
    date_trunc('day', created_at) AS day,
    count(*)                      AS tickets
FROM support_tickets
GROUP BY day
ORDER BY day;
```

- `date_trunc('day', ts)` rounds a timestamp down to the start of the day (also `'hour'`, `'week'`, `'month'`) - the standard bucketing tool.
- Combine with `lag()` to compute day-over-day change: `count(*) - lag(count(*)) OVER (ORDER BY day)`.
- Watch time zones: `created_at` is `TIMESTAMPTZ`, so it stores an absolute instant; bucketing happens in the session time zone unless you convert with `AT TIME ZONE`.

---

## 10. JSON and array processing

Modern data (API payloads, event logs, LLM outputs) is often JSON. Postgres can query inside `JSONB` columns directly, so you do not have to unpack everything in Python first.

```sql
-- given a JSONB column 'meta' like {"source": "email", "tags": ["urgent","vip"]}
SELECT
    meta ->> 'source'                    AS source,        -- ->> gets a text value
    jsonb_array_length(meta -> 'tags')   AS tag_count,     -- -> keeps it as JSON
    tag
FROM tickets_json,
     jsonb_array_elements_text(meta -> 'tags') AS tag      -- expand array to rows
WHERE meta ->> 'source' = 'email';
```

- `->` returns `json`/`jsonb`; `->>` returns `text`. Use `->>` when you want a plain value to compare or display (see: PostgreSQL docs, JSON Functions and Operators).
- `jsonb_array_elements_text(...)` expands a JSON array into one row per element (as `text`) - the JSON equivalent of unpivoting. `jsonb_array_length(...)` returns the element count as an integer.
- Postgres native array columns have their own operators (`unnest()`, `= ANY(...)`, `array_agg()`).

You do not have a JSON column in `support_tickets`, but you will hit this constantly with AI data, so the syntax is here as reference.

---

## 11. Analytical views

A **view** is a saved query you can select from like a table. It packages your cleaning and profiling logic in one named place so every consumer sees the same clean data.

```sql
CREATE OR REPLACE VIEW v_ticket_profile AS
SELECT
    id,
    lower(trim(subject))                AS subject_clean,
    coalesce(category, 'uncategorized') AS category_filled,
    length(coalesce(body, ''))          AS body_len,
    date_trunc('day', created_at)       AS day
FROM support_tickets
WHERE subject IS NOT NULL AND trim(subject) <> '';

SELECT category_filled, count(*) FROM v_ticket_profile GROUP BY category_filled;
```

`CREATE OR REPLACE VIEW` defines it; it stores the query, not the data, so it is always current. Views are how you give a data scientist a clean, consistent surface without copying data or making them re-derive your cleaning rules. A **materialized view** stores the results and must be refreshed - use it when the query is expensive and slightly stale data is acceptable.

---

## 12. Data-quality queries

Pull the individual profiling checks together into a single **data-quality report** - a set of named metrics you can run on a schedule and alert on. This is the SQL you turn into a repeatable job.

```sql
SELECT 'total_rows'       AS metric, count(*)::text AS value FROM support_tickets
UNION ALL
SELECT 'missing_category', count(*)::text FROM support_tickets WHERE category IS NULL
UNION ALL
SELECT 'blank_subject',    count(*)::text FROM support_tickets WHERE subject IS NULL OR trim(subject) = ''
UNION ALL
SELECT 'duplicate_subjects', count(*)::text FROM (
    SELECT subject FROM support_tickets GROUP BY subject HAVING count(*) > 1
) d;
```

`UNION ALL` stacks the results into one metric/value table. Run it before every model refresh; if `blank_subject` or `duplicate_subjects` jumps, you catch bad data before it poisons the model. You build exactly this report, and export it, in the USE `03-sql-data-quality.md` exercise.

---

## Vocabulary recap

- **profiling** - measuring the shape of your data before using it.
- **missing values / `IS NULL` / `FILTER`** - finding and counting nulls and blanks.
- **duplicates / `GROUP BY` + `HAVING`** - finding repeated records.
- **outliers** - values far outside the normal range; clean or keep, but look first.
- **aggregation / `count`/`sum`/`avg` / `GROUP BY`** - collapsing rows into summaries.
- **window function / `OVER` / `PARTITION BY` / `row_number` / `lag`** - per-row calculations across related rows; keeps every row.
- **sampling / `TABLESAMPLE`** - a representative subset for speed or splits.
- **feature / `coalesce` / cast `::` / `extract`** - turning raw columns into model-ready inputs.
- **time-series / `date_trunc`** - bucketing by time period.
- **JSON / `->` vs `->>` / `jsonb_array_elements`** - querying inside JSONB.
- **view / materialized view** - a saved query as a clean, reusable surface.
- **data-quality query / `UNION ALL`** - a repeatable, alertable set of quality metrics.

Next: [04-apis.md](04-apis.md) - how programs talk to each other over HTTP.

---

## References

- PostgreSQL docs, Window Functions (tutorial): https://www.postgresql.org/docs/current/tutorial-window.html
- PostgreSQL docs, Window Functions (function list - `row_number`, `rank`, `dense_rank`, `lag`, `lead`): https://www.postgresql.org/docs/current/functions-window.html
- PostgreSQL docs, SELECT (TABLESAMPLE, GROUP BY, HAVING): https://www.postgresql.org/docs/current/sql-select.html
- PostgreSQL docs, Aggregate expressions (FILTER clause): https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES
- PostgreSQL docs, JSON Functions and Operators (`->`, `->>`, `jsonb_array_elements_text`, `jsonb_array_length`): https://www.postgresql.org/docs/current/functions-json.html
- PostgreSQL docs, Date/Time Functions (`date_trunc`, `extract`, `AT TIME ZONE`): https://www.postgresql.org/docs/current/functions-datetime.html
- PostgreSQL docs, CREATE VIEW / CREATE MATERIALIZED VIEW: https://www.postgresql.org/docs/current/sql-createview.html
