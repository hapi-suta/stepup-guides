# Use Exercise 01 - Measure Bloat Deliberately

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 20-25 minutes

---

## Goal

Create table bloat deliberately using an UPDATE loop, measure it using `pg_stat_user_tables` and `pgstattuple`, then fix it with VACUUM.

---

## Setup

Log in to NODE1, switch to postgres, and connect to stepup_store.

```bash
ssh -i ~/student.pem ec2-user@<NODE1_IP>
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Task 1 - Create the exercise table

```sql
CREATE TABLE bloat_exercise (
  id    serial PRIMARY KEY,
  data  text,
  score integer
);
```

```sql
INSERT INTO bloat_exercise (data, score)
SELECT 'record_' || i, (random() * 100)::int
FROM generate_series(1, 5000) AS i;
```

---

## Task 2 - Record the baseline size

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       pg_size_pretty(pg_total_relation_size('bloat_exercise')) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'bloat_exercise';
```

Write down the `total_size` value. You will compare it after creating bloat.

---

## Task 3 - Run an UPDATE loop without VACUUM

Run this UPDATE 5 times to create dead tuples. Each UPDATE creates 5,000 new dead tuples.

```sql
UPDATE bloat_exercise SET score = score + 1;
```

```sql
UPDATE bloat_exercise SET score = score + 1;
```

```sql
UPDATE bloat_exercise SET score = score + 1;
```

```sql
UPDATE bloat_exercise SET score = score + 1;
```

```sql
UPDATE bloat_exercise SET score = score + 1;
```

---

## Task 4 - Measure dead tuples with pg_stat_user_tables

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       pg_size_pretty(pg_total_relation_size('bloat_exercise')) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'bloat_exercise';
```

You should see roughly 25,000 dead tuples (5 updates x 5,000 rows) and the dead ratio near 80-83%.

**Question:** Why is the total_size much larger than the data you actually have?

---

## Task 5 - Measure bloat precisely with pgstattuple

`pgstattuple` does a full scan of the heap - it takes longer but gives exact numbers.

```sql
SELECT table_len,
       tuple_count,
       round(tuple_percent::numeric, 2) AS live_pct,
       dead_tuple_count,
       round(dead_tuple_percent::numeric, 2) AS dead_pct,
       round(free_percent::numeric, 2) AS free_pct
FROM pgstattuple('bloat_exercise');
```

Record all three percentages. The dead_pct should be high because VACUUM has not run yet.

---

## Task 6 - Run VACUUM and re-measure

```sql
VACUUM bloat_exercise;
```

```sql
SELECT table_len,
       tuple_count,
       round(tuple_percent::numeric, 2) AS live_pct,
       dead_tuple_count,
       round(dead_tuple_percent::numeric, 2) AS dead_pct,
       round(free_percent::numeric, 2) AS free_pct
FROM pgstattuple('bloat_exercise');
```

**Question:** What happened to dead_pct? What happened to free_pct? Did table_len change?

---

## Task 7 - Check if the file shrank

```sql
SELECT pg_size_pretty(pg_relation_size('bloat_exercise')) AS heap_size;
```

Compare this to the size you noted in Task 2. The heap size should be the same or larger - VACUUM does not shrink the file.

---

## Task 8 - Run VACUUM FULL to reclaim OS space

```sql
VACUUM FULL bloat_exercise;
```

```sql
SELECT pg_size_pretty(pg_relation_size('bloat_exercise')) AS heap_size;
```

**Question:** How much space was physically returned? Is the new size close to what you expected based on 5,000 rows?

---

## Task 9 - Check the Pulse dashboard

Open `http://<NODE1_IP>:8080` and navigate to the MVCC/Vacuum panel. Confirm `bloat_exercise` is no longer showing in the top bloated tables list.

---

## Cleanup

```sql
DROP TABLE bloat_exercise;
```

```sql
\q
```

```bash
exit
```

```bash
exit
```

---

## Key Takeaways

- Each UPDATE to a row creates one dead tuple - 5 updates x 5,000 rows = 25,000 dead tuples
- `pg_stat_user_tables` gives fast estimates; `pgstattuple` gives exact numbers (requires a full scan)
- VACUUM clears dead tuples and marks space free for reuse - the file does not shrink
- VACUUM FULL rewrites the table and returns space to the OS - but requires an exclusive lock
- Always check the Pulse MVCC panel after running VACUUM to confirm dead tuples dropped
