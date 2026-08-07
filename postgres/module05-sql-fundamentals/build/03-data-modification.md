# Module 05 - SQL Fundamentals
## Guide 03: Data Modification - INSERT, UPDATE, DELETE, UPSERT

**Objective:** Write INSERT, UPDATE, and DELETE statements. Use the RETURNING clause to capture changed data. Learn UPSERT with ON CONFLICT. Use CTEs for multi-step data operations.

**Time:** 35-40 minutes

**Prerequisites:**
- Guides 01 and 02 complete
- PostgreSQL 16 running, connected to `stepup_store`

---

## 1. Connect and Create a Test Table

Log in to your server:

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

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

Create a test table for modification exercises. Using a separate table protects the live Pulse data from accidental changes:

```sql
CREATE TABLE IF NOT EXISTS test_inventory (
  item_id     SERIAL PRIMARY KEY,
  sku         VARCHAR(50) UNIQUE NOT NULL,
  description TEXT,
  quantity    INTEGER NOT NULL DEFAULT 0,
  unit_cost   NUMERIC(10,2),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Verify it was created:

```sql
\d test_inventory
```

Expected output:

```
                                          Table "public.test_inventory"
   Column    |           Type           | Nullable |                     Default
-------------+--------------------------+----------+--------------------------------------------------
 item_id     | integer                  | not null | nextval('test_inventory_item_id_seq'::regclass)
 sku         | character varying(50)    | not null |
 description | text                     |          |
 quantity    | integer                  | not null | 0
 unit_cost   | numeric(10,2)            |          |
 updated_at  | timestamp with time zone | not null | now()
```

Note there is no `category` column on this table - it is a simple standalone inventory table, unrelated to the `products.category` column you used in earlier guides.

> **Concept: SERIAL and sequences**
> `SERIAL` is shorthand for creating an integer column with a sequence that auto-increments. PostgreSQL actually creates a sequence object named `tablename_columnname_seq` and sets the column default to `nextval('sequence_name')`. `BIGSERIAL` uses a `BIGINT` column. The modern equivalent is `GENERATED ALWAYS AS IDENTITY` which follows the SQL standard.

---

## 2. INSERT - Single Row

Insert one row into the test table. Specify column names explicitly to avoid order-dependency on the schema:

```sql
INSERT INTO test_inventory (sku, description, quantity, unit_cost)
VALUES ('SKU-001', 'DBA Toolkit Pro spare license', 50, 4.99);
```

Expected output:

```
INSERT 0 1
```

`INSERT 0 1` means 0 rows were copied from another table (the OID) and 1 row was inserted.

Verify the insert:

```sql
SELECT * FROM test_inventory;
```

Expected output:

```
 item_id |   sku   |          description           | quantity | unit_cost |          updated_at
---------+---------+--------------------------------+----------+-----------+-------------------------------
       1 | SKU-001 | DBA Toolkit Pro spare license  |       50 |      4.99 | 2026-08-07 02:06:10.066289+00
(1 row)
```

Insert a row without specifying the optional `description` column. It will be NULL:

```sql
INSERT INTO test_inventory (sku, quantity, unit_cost)
VALUES ('SKU-002', 100, 2.49);
```

---

## 3. INSERT - Multiple Rows

Insert several rows in a single statement. This is more efficient than multiple single-row inserts because it requires only one round-trip to the server:

```sql
INSERT INTO test_inventory (sku, description, quantity, unit_cost)
VALUES
  ('SKU-003', 'Backup Solution add-on', 30, 7.99),
  ('SKU-004', 'Migration Tool add-on', 200, 1.25),
  ('SKU-005', 'Monitoring Dashboard add-on', 75, 3.50);
```

Expected output:

```
INSERT 0 3
```

Verify all rows exist:

```sql
SELECT item_id, sku, quantity FROM test_inventory ORDER BY item_id;
```

Expected output:

```
 item_id |   sku   | quantity
---------+---------+----------
       1 | SKU-001 |       50
       2 | SKU-002 |      100
       3 | SKU-003 |       30
       4 | SKU-004 |      200
       5 | SKU-005 |       75
(5 rows)
```

---

## 4. INSERT with SELECT

Copy rows from one table into another using INSERT ... SELECT. This inserts into `test_inventory` based on a query against `products`:

```sql
INSERT INTO test_inventory (sku, description, quantity, unit_cost)
SELECT
  'PROD-' || product_id,
  name,
  stock,
  price * 0.4
FROM products
WHERE category = 'Software';
```

Expected output:

```
INSERT 0 10
```

The `Software` category has 10 products, so 10 rows are inserted. Verify:

```sql
SELECT item_id, sku, description, quantity, unit_cost FROM test_inventory WHERE sku LIKE 'PROD-%' ORDER BY item_id;
```

Expected output:

```
 item_id |   sku   |     description      | quantity | unit_cost
---------+---------+----------------------+----------+-----------
       6 | PROD-2  | DBA Toolkit Pro      |       50 |     80.00
       7 | PROD-3  | Database Monitor     |       75 |     36.00
       8 | PROD-5  | Backup Solution      |       30 |     60.00
       9 | PROD-7  | Performance Tuner    |       60 |     52.00
      10 | PROD-8  | Migration Tool       |       40 |     72.00
      11 | PROD-9  | Monitoring Dashboard |       80 |     40.00
      12 | PROD-12 | Cloud DB Manager     |       25 |    100.00
      13 | PROD-13 | Replication Toolkit  |       35 |     64.00
      14 | PROD-14 | Security Scanner     |       45 |     88.00
      15 | PROD-15 | Data Recovery Pro    |       20 |     76.00
(10 rows)
```

The `||` operator concatenates strings in PostgreSQL. `stock` is copied as-is into `quantity`. `price * 0.4` calculates a 40% cost estimate from the sale price.

> **Concept: INSERT ... SELECT vs COPY**
> `INSERT ... SELECT` is flexible - you can transform, filter, and compute values during the copy. `COPY` (the bulk loader) is much faster for large datasets because it bypasses the expression evaluation path and streams raw data. For millions of rows, use `COPY`. For thousands of rows with transformation, use `INSERT ... SELECT`.

---

## 5. RETURNING Clause

`RETURNING` makes INSERT, UPDATE, and DELETE return the affected rows. This eliminates the need for a second SELECT to fetch the new values.

Insert a row and immediately see the generated `item_id` and `updated_at`:

```sql
INSERT INTO test_inventory (sku, description, quantity, unit_cost)
VALUES ('SKU-RETURN-TEST', 'Test item for RETURNING', 10, 1.00)
RETURNING item_id, sku, updated_at;
```

Expected output (yours will differ - `item_id` and the timestamp depend on how many rows you inserted above):

```
 item_id |       sku        |          updated_at
---------+------------------+-------------------------------
      16 | SKU-RETURN-TEST  | 2026-08-07 02:06:10.071877+00
(1 row)
```

Without `RETURNING`, you would need to run a separate `SELECT` after the insert to find out the assigned `item_id`. This is especially useful when the application needs the auto-generated ID to insert related rows immediately after.

---

## 6. UPDATE

Update rows in the table. Always use a WHERE clause with UPDATE - without one, every row in the table changes.

Increase the quantity of SKU-001 by 25:

```sql
UPDATE test_inventory
SET quantity = quantity + 25
WHERE sku = 'SKU-001';
```

Expected output:

```
UPDATE 1
```

The number after `UPDATE` is the count of rows changed.

Update multiple columns at once for SKU-002:

```sql
UPDATE test_inventory
SET quantity = 150,
    description = 'DBA Toolkit Pro spare license - updated',
    updated_at = now()
WHERE sku = 'SKU-002';
```

Verify:

```sql
SELECT sku, description, quantity, updated_at FROM test_inventory WHERE sku = 'SKU-002';
```

Expected output:

```
   sku   |               description               | quantity |          updated_at
---------+-----------------------------------------+----------+-------------------------------
 SKU-002 | DBA Toolkit Pro spare license - updated |      150 | 2026-08-07 02:06:10.074277+00
(1 row)
```

Update with RETURNING to confirm what changed in one statement. Add a 10% cost increase to SKU-001 and SKU-002:

```sql
UPDATE test_inventory
SET unit_cost = unit_cost * 1.10
WHERE sku IN ('SKU-001', 'SKU-002')
RETURNING sku, unit_cost AS new_cost;
```

Expected output:

```
   sku   | new_cost
---------+----------
 SKU-001 |     5.49
 SKU-002 |     2.74
(2 rows)
```

> **Concept: UPDATE without WHERE is dangerous**
> `UPDATE test_inventory SET quantity = 0;` with no WHERE clause sets quantity to 0 on every row. PostgreSQL will execute it without warning. Always run a SELECT with the same WHERE clause first to confirm you are targeting the right rows. In production, many teams run updates inside a transaction, check the rowcount with `GET DIAGNOSTICS`, and ROLLBACK if the count looks wrong.

---

## 7. DELETE

Delete a specific row. Always use WHERE with DELETE - without it, the entire table is emptied:

```sql
DELETE FROM test_inventory WHERE sku = 'SKU-RETURN-TEST';
```

Expected output:

```
DELETE 1
```

Delete with RETURNING to log what was removed:

```sql
DELETE FROM test_inventory
WHERE quantity > 150
RETURNING sku, description, quantity;
```

Expected output:

```
   sku   |      description      | quantity
---------+-----------------------+----------
 SKU-004 | Migration Tool add-on |      200
(1 row)
```

> **Concept: DELETE vs TRUNCATE**
> `DELETE FROM table` removes rows one at a time, fires row-level triggers, and can be rolled back. It is slower on large tables because PostgreSQL marks each row as dead rather than dropping the data immediately. `TRUNCATE TABLE` removes all rows by dropping and recreating the table's data pages - it is nearly instant. TRUNCATE cannot be used with a WHERE clause and requires an ACCESS EXCLUSIVE lock.

---

## 8. UPSERT with ON CONFLICT

UPSERT inserts a row if it does not exist, or updates it if it does. PostgreSQL implements this with `ON CONFLICT`.

Try to insert SKU-001 which already exists. Without ON CONFLICT, this fails with a unique constraint violation:

```sql
INSERT INTO test_inventory (sku, description, quantity, unit_cost)
VALUES ('SKU-001', 'DBA Toolkit Pro spare license', 50, 4.99)
ON CONFLICT (sku) DO NOTHING;
```

Expected output:

```
INSERT 0 0
```

`DO NOTHING` silently ignores the conflict. The existing row is unchanged.

Now insert or update - if SKU-001 exists, add to its quantity:

```sql
INSERT INTO test_inventory (sku, description, quantity, unit_cost)
VALUES ('SKU-001', 'DBA Toolkit Pro spare license', 25, 4.99)
ON CONFLICT (sku)
DO UPDATE SET
  quantity = test_inventory.quantity + EXCLUDED.quantity,
  updated_at = now();
```

Expected output:

```
INSERT 0 1
```

`EXCLUDED` is a special table reference that holds the values from the row that was attempted but conflicted. `test_inventory.quantity + EXCLUDED.quantity` adds the incoming 25 to the existing quantity.

Verify:

```sql
SELECT sku, quantity FROM test_inventory WHERE sku = 'SKU-001';
```

Expected output:

```
   sku   | quantity
---------+----------
 SKU-001 |      100
(1 row)
```

SKU-001 started at 50, gained 25 in Section 6 (`quantity = quantity + 25`), then gained another 25 here (100 total).

> **Concept: UPSERT atomicity**
> The entire INSERT ... ON CONFLICT is atomic. There is no race condition between checking for existence and inserting/updating. If two sessions run UPSERT simultaneously with the same SKU, PostgreSQL serializes them - one wins the insert, the other triggers the conflict branch. This is much safer than an application-level "check then insert" pattern.

---

## 9. CTEs with Data Modification

A Common Table Expression (CTE) with `WITH` can feed data into INSERT, UPDATE, or DELETE statements. This enables multi-step operations in a single statement.

Identify low-stock items (quantity below 40) and log them to a hypothetical reorder table in one step. First create the reorder_log table:

```sql
CREATE TABLE IF NOT EXISTS reorder_log (
  log_id     SERIAL PRIMARY KEY,
  sku        VARCHAR(50),
  quantity   INTEGER,
  logged_at  TIMESTAMPTZ DEFAULT now()
);
```

Check which items currently have quantity below 40:

```sql
SELECT sku, quantity FROM test_inventory WHERE quantity < 40 ORDER BY sku;
```

Expected output:

```
   sku   | quantity
---------+----------
 PROD-12 |       25
 PROD-13 |       35
 PROD-15 |       20
 PROD-5  |       30
 SKU-003 |       30
(5 rows)
```

Now use a CTE to find low-stock items and insert them into the log:

```sql
WITH low_stock AS (
  SELECT sku, quantity
  FROM test_inventory
  WHERE quantity < 40
)
INSERT INTO reorder_log (sku, quantity)
SELECT sku, quantity FROM low_stock;
```

Expected output:

```
INSERT 0 5
```

Verify the log:

```sql
SELECT * FROM reorder_log ORDER BY log_id;
```

Expected output (yours will differ in the `logged_at` timestamp):

```
 log_id |   sku   | quantity |           logged_at
--------+---------+----------+-------------------------------
      1 | SKU-003 |       30 | 2026-08-07 02:06:10.085966+00
      2 | PROD-5  |       30 | 2026-08-07 02:06:10.085966+00
      3 | PROD-12 |       25 | 2026-08-07 02:06:10.085966+00
      4 | PROD-13 |       35 | 2026-08-07 02:06:10.085966+00
      5 | PROD-15 |       20 | 2026-08-07 02:06:10.085966+00
(5 rows)
```

Use a CTE to update in stages - first identify items to update, then update them. Add 100 units to every item that is still below 40:

```sql
WITH items_to_restock AS (
  SELECT item_id FROM test_inventory WHERE quantity < 40
)
UPDATE test_inventory
SET quantity = quantity + 100
WHERE item_id IN (SELECT item_id FROM items_to_restock)
RETURNING sku, quantity AS new_quantity;
```

Expected output:

```
   sku   | new_quantity
---------+--------------
 SKU-003 |          130
 PROD-5  |          130
 PROD-12 |          125
 PROD-13 |          135
 PROD-15 |          120
(5 rows)
```

> **Concept: CTE visibility in data-modifying queries**
> In PostgreSQL, data-modifying CTEs (WITH clauses containing INSERT/UPDATE/DELETE) execute with snapshot isolation relative to the main query. Changes made in one CTE branch are not visible to other branches in the same statement. This prevents unexpected cascading effects when you chain multiple modifications together in one statement.

---

## 10. Cleanup

Remove the test tables created in this guide:

```sql
DROP TABLE IF EXISTS reorder_log;
```

```sql
DROP TABLE IF EXISTS test_inventory;
```

Exit psql:

```sql
\q
```

Exit the postgres user:

```bash
exit
```

---

## Summary

| Statement | Purpose |
|-----------|---------|
| `INSERT INTO ... VALUES` | Add one or more rows |
| `INSERT INTO ... SELECT` | Copy rows from a query result |
| `RETURNING` | Return affected rows from INSERT/UPDATE/DELETE |
| `UPDATE ... SET ... WHERE` | Modify existing rows |
| `DELETE FROM ... WHERE` | Remove rows |
| `ON CONFLICT DO NOTHING` | Skip conflicting inserts |
| `ON CONFLICT DO UPDATE` | Upsert - insert or update on conflict |
| `WITH ... INSERT/UPDATE` | CTE-driven multi-step operations |

**Next:** Guide 04 covers transactions and isolation levels.
