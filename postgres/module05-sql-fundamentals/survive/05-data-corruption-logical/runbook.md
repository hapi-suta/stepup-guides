# Scenario 05 - Logical Data Corruption

**Severity:** HIGH
**Expected Recovery Time:** 15-20 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Data integrity errors detected.
The nightly reconciliation job is reporting mismatched employee-department
records. Some employees reference departments that do not exist. Duplicate
email addresses found in the employees table.
```

---

## Key Concepts for Revision

- **Foreign key constraints** - A foreign key ensures that a value in the child table (e.g., `employees.dept_id`) always matches a value in the parent table (e.g., `departments.dept_id`). If someone disables triggers and inserts bad data, the FK still exists as metadata but was not enforced during the insert. The orphaned rows silently break application joins and reports.

- **Trigger disabling** - `ALTER TABLE ... DISABLE TRIGGER ALL` turns off all triggers including the internal triggers that enforce foreign keys and unique constraints. This is sometimes done during bulk loads for performance but is dangerous if the data is not validated afterward.

- **Finding orphaned records** - A LEFT JOIN from child to parent where the parent side is NULL reveals orphaned rows. Alternatively, `NOT IN` or `NOT EXISTS` subqueries work. LEFT JOIN is usually the clearest to read.

- **Validating constraints after repair** - After fixing the data, use `ALTER TABLE ... VALIDATE CONSTRAINT` to have PostgreSQL re-check every row against the constraint. If any row still violates the FK, this command fails with an error showing the bad row.

- **Duplicate detection** - Use `GROUP BY` with `HAVING COUNT(*) > 1` to find columns that should be unique but have duplicates. The `ctid` system column (physical row location) can help distinguish duplicates when all visible columns are the same.

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

### Step 2 - Check the current state of the tables

Look at all employees:

```sql
SELECT emp_id, emp_name, dept_id, email FROM employees ORDER BY emp_id;
```

Expected output (yours will differ):

```
 emp_id |     emp_name      | dept_id |        email
--------+-------------------+---------+---------------------
      1 | Alice Chen        |       1 | alice@company.com
      2 | Bob Martinez      |       2 | bob@company.com
      3 | Carol Davis       |       1 | carol@company.com
      4 | Dave Kim          |       3 | dave@company.com
      5 | Eve Johnson       |       4 | eve@company.com
      6 | Ghost Worker 1    |      99 | ghost1@company.com
      7 | Ghost Worker 2    |      88 | ghost2@company.com
      8 | Ghost Worker 3    |      77 | ghost3@company.com
      9 | Alice Chen Copy   |       1 | alice@company.com
(9 rows)
```

Rows 6-8 reference departments 99, 88, 77 which do not exist. Row 9 duplicates the email from row 1.

### Step 3 - Find orphaned records (employees with no matching department)

```sql
SELECT e.emp_id, e.emp_name, e.dept_id
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_id IS NULL;
```

Expected output (yours will differ):

```
 emp_id |    emp_name    | dept_id
--------+----------------+---------
      6 | Ghost Worker 1 |      99
      7 | Ghost Worker 2 |      88
      8 | Ghost Worker 3 |      77
(3 rows)
```

The LEFT JOIN returns NULL on the departments side for any employee whose `dept_id` does not match a real department. Those are the orphans.

### Step 4 - Find duplicate emails

```sql
SELECT email, COUNT(*) AS cnt
FROM employees
GROUP BY email
HAVING COUNT(*) > 1;
```

Expected output (yours will differ):

```
       email       | cnt
-------------------+-----
 alice@company.com |   2
(1 row)
```

See which rows share the duplicate:

```sql
SELECT emp_id, emp_name, email, hire_date
FROM employees
WHERE email = 'alice@company.com'
ORDER BY emp_id;
```

Expected output (yours will differ):

```
 emp_id |     emp_name     |       email       | hire_date
--------+------------------+-------------------+------------
      1 | Alice Chen       | alice@company.com | 2023-01-15
      9 | Alice Chen Copy  | alice@company.com | 2024-04-01
(2 rows)
```

Row 1 is the original. Row 9 is the bad duplicate.

---

## Resolution

### Step 1 - Delete orphaned records

Remove employees that reference non-existent departments:

```sql
DELETE FROM employees
WHERE dept_id NOT IN (SELECT dept_id FROM departments);
```

Expected output:

```
DELETE 3
```

Three orphaned rows removed.

### Step 2 - Delete duplicate email records

Keep the original row (lowest `emp_id`) and delete the duplicate:

```sql
DELETE FROM employees
WHERE emp_id IN (
  SELECT emp_id FROM (
    SELECT emp_id, ROW_NUMBER() OVER (PARTITION BY email ORDER BY emp_id) AS rn
    FROM employees
  ) dupes
  WHERE rn > 1
);
```

Expected output:

```
DELETE 1
```

One duplicate removed.

### Step 3 - Verify the data is clean

Check for any remaining orphans:

```sql
SELECT e.emp_id, e.emp_name, e.dept_id
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_id IS NULL;
```

Expected output:

```
 emp_id | emp_name | dept_id
--------+----------+---------
(0 rows)
```

Check for any remaining duplicate emails:

```sql
SELECT email, COUNT(*) FROM employees GROUP BY email HAVING COUNT(*) > 1;
```

Expected output:

```
 email | count
-------+-------
(0 rows)
```

### Step 4 - Validate the foreign key constraint

Ask PostgreSQL to re-check every row against the FK:

```sql
ALTER TABLE employees VALIDATE CONSTRAINT employees_dept_id_fkey;
```

Expected output:

```
ALTER TABLE
```

If any row still violated the FK, this command would fail with an error. `ALTER TABLE` means all rows passed.

### Step 5 - Confirm triggers are enabled

```sql
SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgrelid = 'employees'::regclass;
```

The `tgenabled` column should show `O` (origin - the default enabled state) for all triggers. If any show `D` (disabled), re-enable them:

```sql
ALTER TABLE employees ENABLE TRIGGER ALL;
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

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- Both tables exist
- No orphaned employee records
- No duplicate emails
- FK constraint is valid and enforced
- Triggers are enabled

---

## Interview Discussion Points

1. **How can logical corruption happen even with constraints in place?** - Constraints can be bypassed by disabling triggers (`ALTER TABLE ... DISABLE TRIGGER ALL`), using session_replication_role = 'replica', or loading data via COPY with `--no-triggers` in some restore scenarios. Bulk ETL pipelines sometimes disable triggers for speed and forget to re-validate afterward.

2. **What is the difference between NOT VALID and VALIDATE CONSTRAINT?** - When you add a new FK with `NOT VALID`, PostgreSQL only checks new inserts going forward - it does not scan existing rows. Later, `ALTER TABLE ... VALIDATE CONSTRAINT` does a full scan. This two-step approach avoids locking the table for a long time on large tables. You get immediate protection for new data while deferring the expensive scan.

3. **How do you find orphaned records at scale across many tables?** - Query `pg_constraint` to get all FK relationships, then programmatically generate LEFT JOIN queries for each one. Tools like `pg_validate_constraints` automate this. For large databases, sample-based approaches (checking a random 1% of rows per table) can detect corruption faster than full scans.

4. **What is the risk of DELETE vs UPDATE for fixing orphans?** - DELETE removes the orphaned rows permanently. If those rows contain real business data that was accidentally assigned wrong dept_ids, you lose the data. A safer approach is to first move orphans to a staging table (`INSERT INTO employees_orphans SELECT ... ; DELETE ...`), fix them there, then merge back. Always take a logical backup (pg_dump) before bulk deletes.

5. **How would you prevent this in the future?** - Never disable triggers in production without a validation step afterward. Use a CI check that runs `ALTER TABLE ... VALIDATE CONSTRAINT` for every FK after any bulk load. Add application-level checks for referential integrity in addition to database constraints. Monitor the count of `NOT VALID` constraints via `pg_constraint WHERE convalidated = false`.
