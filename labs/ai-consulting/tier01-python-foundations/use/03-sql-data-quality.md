# USE: SQL Data-Quality Report

**Goal:** before any data feeds a model or a dashboard, you profile it and check its quality. You will write data-quality SQL against the real `support_tickets` table, build a single report query, and export it to a file - a repeatable artifact you could run on a schedule and alert on. This turns the SQL concepts into a deliverable.

**Where you are:** the lab server, as **ec2-user**. PostgreSQL `labdb` (user `labuser`, password `labpass`) with the `support_tickets` table from BUILD.

**What you will practice:** profiling, missing values, duplicates, aggregations, window functions, and exporting results - the material from [03-sql-for-ai-and-analytics.md](03-sql-for-ai-and-analytics.md).

---

## Step 1: Confirm the table is there and add one messy row

You will add a duplicate and a blank-subject row so the quality checks have something to catch. First, open a database session.

On your **lab server**, as **ec2-user**:

```bash
cd ~/project1
```

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb
```

`psql` opens an interactive SQL prompt. You will see `labdb=>`. Confirm the row count:

```sql
SELECT count(*) FROM support_tickets;
```

Expected output (yours will differ):

```
 count
-------
    10
(1 row)
```

Now insert a duplicate subject and a blank-subject row on purpose:

```sql
INSERT INTO support_tickets (subject, body, category) VALUES
    ('Refund status?', 'Duplicate on purpose', NULL),
    ('   ',            'Blank subject on purpose', NULL);
```

Expected output:

```
INSERT 0 2
```

Leave the `psql` prompt open for the next steps.

---

## Step 2: Profile the data

Get the shape of the table in one query.

At the `labdb=>` prompt:

```sql
SELECT
    count(*)                 AS total_rows,
    count(DISTINCT category) AS distinct_categories,
    min(created_at)          AS earliest,
    max(created_at)          AS latest
FROM support_tickets;
```

Expected output (yours will differ):

```
 total_rows | distinct_categories |          earliest          |           latest
------------+---------------------+----------------------------+----------------------------
         12 |                   5 | 2026-07-25 14:10:02.11+00   | 2026-07-25 14:31:44.87+00
(1 row)
```

12 rows now, 5 distinct non-null categories. This is the baseline before you check quality.

---

## Step 3: Count missing and blank values

Find the data problems: missing categories, missing bodies, and blank subjects.

At the `labdb=>` prompt:

```sql
SELECT
    count(*) FILTER (WHERE category IS NULL)                       AS missing_category,
    count(*) FILTER (WHERE body IS NULL)                           AS missing_body,
    count(*) FILTER (WHERE subject IS NULL OR trim(subject) = '')  AS blank_subject
FROM support_tickets;
```

`count(*) FILTER (WHERE ...)` counts only rows meeting each condition, all in one pass. `trim(subject) = ''` catches the all-spaces row.

Expected output (yours will differ):

```
 missing_category | missing_body | blank_subject
------------------+--------------+---------------
                3 |            0 |             1
(1 row)
```

Three tickets have no category (the model would need the keyword rules for these), and one has a blank subject that must be excluded.

---

## Step 4: Find duplicates with a window function

Instead of just counting duplicates, use `row_number()` to see which specific rows are repeats - the standard dedupe pattern.

At the `labdb=>` prompt:

```sql
SELECT id, subject,
       row_number() OVER (PARTITION BY lower(trim(subject)) ORDER BY id) AS dup_rank
FROM support_tickets
WHERE subject IS NOT NULL AND trim(subject) <> ''
ORDER BY subject, dup_rank;
```

`PARTITION BY lower(trim(subject))` groups rows with the same normalized subject; `row_number()` numbers them 1, 2, 3 inside each group. Any row with `dup_rank > 1` is a duplicate you would drop.

Expected output (yours will differ, truncated):

```
 id |    subject     | dup_rank
----+----------------+----------
  6 | App crashes... |        1
  ...
  5 | Refund status? |        1
 11 | Refund status? |        2
  ...
```

`Refund status?` appears with `dup_rank = 2` - that is the duplicate you inserted, correctly identified.

---

## Step 5: Aggregate - the category distribution

The analytics summary: tickets per category, treating missing categories honestly.

At the `labdb=>` prompt:

```sql
SELECT coalesce(category, 'uncategorized') AS category, count(*) AS n
FROM support_tickets
WHERE subject IS NOT NULL AND trim(subject) <> ''
GROUP BY coalesce(category, 'uncategorized')
ORDER BY n DESC, category;
```

`coalesce(category, 'uncategorized')` fills nulls with a label; the `WHERE` excludes the blank-subject row so it does not inflate the counts.

Expected output (yours will differ):

```
    category    | n
----------------+---
 billing        | 3
 uncategorized  | 3
 auth           | 2
 bug            | 2
 feature        | 1
 performance    | 1
(6 rows)
```

---

## Step 6: Build a single data-quality report query

Combine the key metrics into one metric/value result with `UNION ALL`. This is the artifact you would schedule and alert on.

At the `labdb=>` prompt:

```sql
SELECT 'total_rows' AS metric, count(*)::text AS value FROM support_tickets
UNION ALL
SELECT 'missing_category', count(*)::text FROM support_tickets WHERE category IS NULL
UNION ALL
SELECT 'blank_subject', count(*)::text FROM support_tickets
    WHERE subject IS NULL OR trim(subject) = ''
UNION ALL
SELECT 'duplicate_subjects', count(*)::text FROM (
    SELECT lower(trim(subject)) AS s
    FROM support_tickets
    WHERE subject IS NOT NULL AND trim(subject) <> ''
    GROUP BY lower(trim(subject)) HAVING count(*) > 1
) d;
```

`::text` casts each count to text so the columns line up under one type. `UNION ALL` stacks the rows.

Expected output (yours will differ):

```
       metric        | value
---------------------+-------
 total_rows          | 12
 missing_category    | 3
 blank_subject       | 1
 duplicate_subjects  | 1
(4 rows)
```

That is a data-quality report: four named metrics you can watch over time. Exit the prompt:

```sql
\q
```

`\q` quits `psql` and returns you to the shell as ec2-user.

---

## Step 7: Export the report to a file

Now run the same report non-interactively and save it as a shareable artifact. You do this from the shell, not inside psql.

Still on the **lab server**, as **ec2-user**, create the report SQL with `vi`:

```bash
vi data_quality_report.sql
```

Press `i`, type the following, then `Esc` and `:wq`:

```sql
SELECT 'total_rows' AS metric, count(*)::text AS value FROM support_tickets
UNION ALL
SELECT 'missing_category', count(*)::text FROM support_tickets WHERE category IS NULL
UNION ALL
SELECT 'blank_subject', count(*)::text FROM support_tickets
    WHERE subject IS NULL OR trim(subject) = ''
UNION ALL
SELECT 'duplicate_subjects', count(*)::text FROM (
    SELECT lower(trim(subject)) AS s
    FROM support_tickets
    WHERE subject IS NOT NULL AND trim(subject) <> ''
    GROUP BY lower(trim(subject)) HAVING count(*) > 1
) d;
```

Run it and write clean CSV output to a file:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb \
  --csv -f data_quality_report.sql -o data_quality_report.csv
```

`--csv` makes psql emit comma-separated output. `-f` runs the file, `-o` writes results to `data_quality_report.csv`.

View the exported report:

```bash
cat data_quality_report.csv
```

Expected output (yours will differ):

```
metric,value
total_rows,12
missing_category,3
blank_subject,1
duplicate_subjects,1
```

You now have a portable data-quality profile you could email, commit, or feed into a monitoring job.

---

## Step 8: Clean up the messy rows (optional)

Remove the two rows you added so the table is back to the BUILD baseline.

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb \
  -c "DELETE FROM support_tickets WHERE body IN ('Duplicate on purpose','Blank subject on purpose');"
```

`-c` runs a single SQL statement.

Expected output:

```
DELETE 2
```

---

## What you just did

- **Profiled** a real table: row count, distinct values, date range.
- **Quantified missing values** in one pass with `count(*) FILTER (WHERE ...)`.
- **Found specific duplicates** with a `row_number()` window function partitioned on the normalized subject.
- **Aggregated** the category distribution, filling nulls with `coalesce`.
- **Assembled a one-shot data-quality report** with `UNION ALL` and **exported it to CSV** as a repeatable, shareable artifact.

This is the unglamorous but essential work that stands between raw data and a trustworthy model. In real AI projects you run reports like this on a schedule and alert when `blank_subject` or `duplicate_subjects` spikes - catching bad data before it reaches the model.
