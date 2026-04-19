# Scenario 07 - Sequence Exhausted

**Severity:** CRITICAL
**Expected Recovery Time:** 10-15 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application error - cannot create new tickets.
INSERT into tickets table is failing with:
ERROR: integer out of range
The support ticket system is completely down.
```

---

## Key Concepts for Revision

- **SERIAL vs BIGSERIAL** - `SERIAL` creates an `integer` column (4 bytes, max 2,147,483,647). `BIGSERIAL` creates a `bigint` column (8 bytes, max 9,223,372,036,854,775,807). For any table expected to grow indefinitely, always use `BIGSERIAL`. Once a `SERIAL` column hits the integer max, all INSERTs fail.

- **Sequences** - A sequence is a database object that generates incrementing numbers. `SERIAL` columns are backed by a sequence named `tablename_columnname_seq`. The sequence tracks its current value, increment, min, and max. When `last_value` equals `max_value`, the next `nextval()` call fails.

- **setval and currval** - `setval('seq_name', value)` sets the current position of a sequence. `currval('seq_name')` returns the last value generated in the current session. `SELECT last_value FROM seq_name` shows the current value without advancing it.

- **ALTER TABLE ... ALTER COLUMN TYPE** - Changing a column from `integer` to `bigint` requires a full table rewrite in PostgreSQL. On large tables this can take a long time and holds an ACCESS EXCLUSIVE lock. For emergencies, this is the correct fix. For large production tables, consider the two-step approach: add a new bigint column, backfill, then swap.

- **Sequence max_value** - Every sequence has a `max_value`. For integer-backed sequences, it is 2,147,483,647 by default. For bigint-backed sequences, it is 9,223,372,036,854,775,807. You can check this with `SELECT * FROM pg_sequences`.

---

## Diagnostic Steps

### Step 1 - Connect to the server

Log in to the server:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open psql:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Reproduce the error

Try to insert a new ticket:

```sql
INSERT INTO tickets (subject) VALUES ('Test ticket');
```

Expected output:

```
ERROR:  integer out of range
```

The sequence is returning a value larger than what an `integer` column can hold.

### Step 3 - Check the sequence current value

```sql
SELECT last_value, max_value, data_type
FROM pg_sequences
WHERE sequencename = 'tickets_ticket_id_seq';
```

Expected output (yours will differ):

```
 last_value  |  max_value  | data_type
-------------+-------------+-----------
  2147483647 | 2147483647  | integer
(1 row)
```

The `last_value` has reached `max_value`. There are no more integer values available.

### Step 4 - Check the column type

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'tickets' AND column_name = 'ticket_id';
```

Expected output:

```
 column_name | data_type
-------------+-----------
 ticket_id   | integer
(1 row)
```

The column is `integer` (max 2,147,483,647). It needs to be `bigint` (max 9.2 quintillion).

### Step 5 - Check how many rows actually exist

```sql
SELECT COUNT(*) FROM tickets;
```

Expected output (yours will differ):

```
 count
-------
     7
(1 row)
```

Only a handful of rows exist. The sequence was advanced far past the actual data - someone may have run a `setval()` by mistake, or the sequence naturally grew over years of inserts and deletes.

---

## Resolution

### Step 1 - Change the column type to bigint

Alter the primary key column from integer to bigint:

```sql
ALTER TABLE tickets ALTER COLUMN ticket_id TYPE bigint;
```

Expected output:

```
ALTER TABLE
```

This rewrites the table. On a table with only a few rows, it completes instantly. On a large table, this would take longer and lock the table.

### Step 2 - Change the sequence to bigint

Alter the sequence to use bigint so its max value increases:

```sql
ALTER SEQUENCE tickets_ticket_id_seq AS bigint;
```

Expected output:

```
ALTER SEQUENCE
```

### Step 3 - Verify the sequence now has room

```sql
SELECT last_value, max_value, data_type
FROM pg_sequences
WHERE sequencename = 'tickets_ticket_id_seq';
```

Expected output (yours will differ):

```
 last_value  |      max_value       | data_type
-------------+----------------------+-----------
  2147483647 | 9223372036854775807  | bigint
(1 row)
```

The max_value is now 9.2 quintillion. Plenty of room.

### Step 4 - Test that inserts work again

```sql
INSERT INTO tickets (subject) VALUES ('Recovery test ticket') RETURNING ticket_id, subject;
```

Expected output (yours will differ):

```
 ticket_id  |       subject
------------+---------------------
 2147483648 | Recovery test ticket
(1 row)
```

The insert succeeded with a ticket_id beyond the old integer max.

### Step 5 - Optionally reset the sequence to a sane value

If the sequence was artificially advanced and you want to reclaim the gap:

```sql
SELECT MAX(ticket_id) FROM tickets;
```

If the max is much lower than the sequence value, you can reset it:

```sql
SELECT setval('tickets_ticket_id_seq', (SELECT MAX(ticket_id) FROM tickets));
```

This is optional. The bigint conversion already fixed the immediate problem.

Exit psql:

```sql
\q
```

Exit the postgres user:

```bash
exit
```

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- tickets table exists
- ticket_id column is bigint
- Sequence is bigint with room remaining
- INSERT succeeds

---

## Interview Discussion Points

1. **How do you monitor for sequence exhaustion before it becomes an outage?** - Query `pg_sequences` and compare `last_value` to `max_value`. Calculate percent used: `last_value::float / max_value * 100`. Alert when any sequence exceeds 50% of its max. Tools like `pgbouncer_fdw` or custom monitoring scripts can automate this check on a schedule.

2. **What is the impact of ALTER COLUMN TYPE on a large table?** - PostgreSQL rewrites the entire table, which requires an ACCESS EXCLUSIVE lock for the duration. On a 100GB table, this could take hours. During that time, all reads and writes are blocked. For large tables, the safer approach is: add a new bigint column, backfill in batches, create a new index, swap the columns, and drop the old one.

3. **Why not just reset the sequence to 1?** - If existing rows have high IDs, resetting to 1 would eventually generate a value that conflicts with an existing primary key, causing a unique constraint violation. You must either reset to `MAX(id) + 1` or change the column type to bigint. Changing the type is the permanent fix.

4. **Should you always use BIGSERIAL instead of SERIAL?** - For new tables, yes. The storage overhead is 4 bytes per row (8 vs 4), which is negligible compared to the cost of an emergency column type migration. The PostgreSQL community recommends `bigint` with `GENERATED ALWAYS AS IDENTITY` over `SERIAL` for new schemas.

5. **What is the difference between SERIAL and IDENTITY columns?** - `SERIAL` is a PostgreSQL shorthand that creates a sequence and sets a default. `GENERATED ALWAYS AS IDENTITY` is the SQL standard approach. IDENTITY columns are tighter - they prevent manual value insertion by default (you must say `OVERRIDING SYSTEM VALUE`). They also show up more clearly in `information_schema`. For new schemas, use IDENTITY.
