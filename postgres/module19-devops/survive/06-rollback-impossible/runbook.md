# SURVIVE 06: Rollback Impossible - Runbook

## Symptom

The application team ran a migration that dropped the `loyalty_points` column from the `customers` table. The column contained customer loyalty point balances. No pre-migration backup was taken.

---

## Step 1: Confirm the Damage

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to the database.

```bash
psql -d rollback_chaos
```

Check the current table structure.

```sql
\d customers
```

The `loyalty_points` column should be missing.

Check the migration history.

```sql
SELECT * FROM schema_migrations ORDER BY version;
```

Exit psql.

```sql
\q
```

---

## Step 2: Find Available Data Sources

In a real incident, you would check these sources in order:

1. **pg_dump backup** - Most recent nightly backup
2. **WAL archives** - Point-in-time recovery to just before the migration
3. **Application logs** - May contain loyalty point values
4. **Replica database** - If replication is lagged, the column might still exist there

In this lab, we have a backup file at `/tmp/loyalty_points_backup.txt`.

Check the backup file.

```bash
cat /tmp/loyalty_points_backup.txt
```

Expected output (yours will differ):
```
1500
890
2300
450
3100
```

These values correspond to customers ordered by ID.

---

## Step 3: Add the Column Back

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
psql -d rollback_chaos
```

Add the column back with a default of 0.

```sql
ALTER TABLE customers ADD COLUMN loyalty_points INTEGER DEFAULT 0;
```

---

## Step 4: Restore the Data

We need to map each line in the backup to the correct customer ID.

First, check the customer IDs.

```sql
SELECT id, name FROM customers ORDER BY id;
```

Update each customer with their loyalty points. Since the backup file has values in ID order, we can use a temporary table.

```sql
CREATE TEMP TABLE loyalty_restore (
    row_num SERIAL,
    points INTEGER
);
```

Exit psql to load the data.

```sql
\q
```

Load the backup data into the temp table.

```bash
psql -d rollback_chaos -c "\COPY loyalty_restore(points) FROM '/tmp/loyalty_points_backup.txt'"
```

Connect again.

```bash
psql -d rollback_chaos
```

Map the restored data back to customers. We match by row number to customer ID order.

```sql
WITH ranked_customers AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM customers
)
UPDATE customers c
SET loyalty_points = lr.points
FROM ranked_customers rc
JOIN loyalty_restore lr ON rc.rn = lr.row_num
WHERE c.id = rc.id;
```

Verify the restoration.

```sql
SELECT id, name, loyalty_points FROM customers ORDER BY id;
```

Expected output:
```
 id |     name      | loyalty_points
----+---------------+----------------
  1 | Alice Johnson |           1500
  2 | Bob Smith     |            890
  3 | Charlie Brown |           2300
  4 | Diana Prince  |            450
  5 | Eve Wilson    |           3100
```

---

## Step 5: Add Protection

Add a NOT NULL constraint to prevent accidental data loss.

```sql
ALTER TABLE customers ALTER COLUMN loyalty_points SET NOT NULL;
```

Add a CHECK constraint.

```sql
ALTER TABLE customers ADD CONSTRAINT chk_loyalty_nonneg CHECK (loyalty_points >= 0);
```

---

## Step 6: Update Migration Tracking

Record the fix as a new migration.

```sql
INSERT INTO schema_migrations VALUES (3, 'restore_loyalty_points_column', NOW());
```

Exit psql.

```sql
\q
```

Exit the postgres user.

```bash
exit
```

---

## Prevention

1. **Never DROP COLUMN in a migration without a backup** - Always pg_dump the table first
2. **Use the expand/contract pattern** - Instead of dropping a column:
   - Phase 1 (expand): Add new column, start writing to both
   - Phase 2 (migrate): Backfill data
   - Phase 3 (contract): Remove old column after verifying nothing reads it
3. **Migration safety checks** - CI should flag any DROP COLUMN as requiring manual approval
4. **Pre-migration backups** - Automate pg_dump of affected tables before every migration
5. **Soft delete columns** - Instead of DROP, rename to `_deprecated_loyalty_points` and remove later

---

## Discussion Points

- In real production, PITR (Point-In-Time Recovery) to a moment before the migration is the most reliable way to recover dropped data
- If you have a standby that has not replicated the change yet, you can query the column directly from the replica
- pg_dump with `--column-inserts` creates INSERT statements that include column names, making selective restore easier
- The expand/contract pattern is standard at companies like GitHub and Stripe for zero-downtime migrations
