# USE 03 - Wait Event Analysis Exercise

**Time:** 45 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 02 complete (Performance Insights enabled). psql access.

---

## Objective

Generate specific wait event patterns, identify them in Performance Insights, and apply the correct fix for each. By the end you will be able to read a PI dashboard and map each dominant wait event to a specific action.

---

## Exercise Tasks

### Task 1 - Generate IO:DataFileRead Wait Events

Create a table and force cache misses by scanning a table larger than shared_buffers can hold:

```sql
CREATE TABLE IF NOT EXISTS io_test (
    id BIGSERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    payload BYTEA DEFAULT gen_random_bytes(200)
);

INSERT INTO io_test (data)
SELECT md5(random()::TEXT) FROM generate_series(1, 2000000);

ANALYZE io_test;
```

Now run a sequential scan that will miss the cache:

```sql
SELECT count(*) FROM io_test WHERE data LIKE 'ab%';
```

Run it 10 times:

```sql
DO $$ BEGIN FOR i IN 1..10 LOOP
    PERFORM count(*) FROM io_test WHERE data LIKE 'ab%';
END LOOP; END $$;
```

Open Performance Insights and look at the DB Load chart. You should see `IO:DataFileRead` as the dominant wait event.

<details>
<summary>What does this mean and how to fix it?</summary>

**Meaning:** The database is reading data pages from Aurora storage because they are not in shared_buffers.

**Fix options (in order of preference):**
1. Add an index on the filter column to avoid full table scans
2. Increase instance size (more RAM = larger shared_buffers)
3. Use Aurora Optimized Reads (NVMe tiered cache) on compatible instances
4. If the query is analytical, route it to a reader instance

For this case:
```sql
CREATE INDEX CONCURRENTLY idx_io_test_data ON io_test(data text_pattern_ops);
```
</details>

### Task 2 - Generate Lock:relation Wait Events

Open two separate psql sessions.

**Session 1:**

```sql
BEGIN;
LOCK TABLE io_test IN ACCESS EXCLUSIVE MODE;
-- Do NOT commit yet. Leave this session open.
```

**Session 2:**

```sql
-- This will block, waiting for the lock from Session 1
SELECT count(*) FROM io_test;
```

Session 2 will hang. Open Performance Insights and look for `Lock:relation` in the wait events.

<details>
<summary>What does this mean and how to fix it?</summary>

**Meaning:** A session is waiting to acquire a table-level lock that another session holds.

**Diagnosis:**
```sql
SELECT pid, mode, granted, relation::regclass
FROM pg_locks
WHERE NOT granted;
```

**Fix:**
1. Find the blocking session
2. Determine if it is safe to terminate
3. Terminate it: `SELECT pg_terminate_backend([pid]);`
4. Prevent future occurrences: avoid `LOCK TABLE`, use `CONCURRENTLY` for DDL
</details>

Go back to Session 1 and release the lock:

```sql
ROLLBACK;
```

### Task 3 - Generate IO:BufFileRead Wait Events

Force a sort to spill to disk:

```sql
SET work_mem = '1MB';
```

```sql
SELECT id, data
FROM io_test
ORDER BY data
LIMIT 1000;
```

Run it 10 times and check PI for `IO:BufFileRead` and `IO:BufFileWrite`.

<details>
<summary>What does this mean and how to fix it?</summary>

**Meaning:** The sort/hash operation exceeded work_mem and spilled to temporary files on disk.

**Fix:**
```sql
SET work_mem = '64MB';
-- Re-run the query
RESET work_mem;
```

For a permanent fix, increase work_mem in the parameter group (carefully - it multiplies per session per operation).
</details>

```sql
RESET work_mem;
```

### Task 4 - Generate CPU Wait Events

Run a computation-heavy query with no I/O bottleneck:

```sql
SELECT count(DISTINCT md5(data || id::text))
FROM io_test
WHERE id < 500000;
```

Run it 5 times. In PI, you should see `CPU` as the dominant category (no specific wait event - the session is actively computing).

<details>
<summary>What does this mean and how to fix it?</summary>

**Meaning:** Sessions are actively using CPU for computation - not waiting on anything.

**Diagnosis:** Check Top SQL in PI to find which query is responsible. Then use EXPLAIN ANALYZE to see if there are unnecessary sequential scans or missing indexes.

**Fix options:**
1. Add indexes to reduce the amount of data scanned
2. Rewrite the query to avoid expensive operations (like DISTINCT on a hash)
3. Scale up the instance (more vCPUs)
4. Route analytical queries to a reader instance
</details>

### Task 5 - Build a Wait Event Diagnosis Cheat Sheet

Fill out this table based on what you observed:

| Wait Event | Category | You Observed It When | Fix Applied | Result |
|------------|----------|---------------------|-------------|--------|
| IO:DataFileRead | IO | ___ | ___ | ___ |
| Lock:relation | Lock | ___ | ___ | ___ |
| IO:BufFileRead | IO | ___ | ___ | ___ |
| CPU | CPU | ___ | ___ | ___ |

---

## Cleanup

```sql
DROP TABLE IF EXISTS io_test CASCADE;
```
