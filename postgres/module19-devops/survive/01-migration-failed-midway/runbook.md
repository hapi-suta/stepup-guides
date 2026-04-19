# SURVIVE 01: Migration Failed Midway - Runbook

## Symptom

The application team reports that migration V2 failed partway through. Some DDL changes were applied but the data migration did not complete. The schema is in an inconsistent state.

---

## Step 1: Assess the Damage

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to the database.

```bash
psql -d migrate_chaos
```

Check the migration tracking table to see what happened.

```sql
SELECT version, description, success, applied_at FROM schema_migrations ORDER BY version;
```

List all tables to see what exists.

```sql
\dt
```

Check the employees table structure.

```sql
\d employees
```

Check the departments table.

```sql
\d departments
```

```sql
SELECT count(*) FROM departments;
```

The departments table exists (DDL succeeded) but is empty (DML failed). The `department_id` column exists on employees but has no data.

---

## Step 2: Decide Your Fix Strategy

You have two options:

**Option A: Roll back V2 entirely** - Remove all V2 changes and re-run from scratch.
**Option B: Complete V2 manually** - Finish the data migration that failed.

Option B is usually better because it preserves work that was already done.

---

## Step 3: Complete the Failed Migration (Option B)

Populate the departments table from existing employee data.

```sql
INSERT INTO departments (name, budget)
SELECT DISTINCT department, 100000.00
FROM employees
WHERE department IS NOT NULL
ON CONFLICT (name) DO NOTHING;
```

Verify departments were created.

```sql
SELECT * FROM departments;
```

Update employees with the correct department_id values.

```sql
UPDATE employees
SET department_id = d.id
FROM departments d
WHERE employees.department = d.name;
```

Verify the update worked.

```sql
SELECT e.name, e.department, e.department_id, d.name AS dept_name
FROM employees e
LEFT JOIN departments d ON e.department_id = d.id;
```

---

## Step 4: Add the Foreign Key Constraint

Now that the data is consistent, add the constraint that was supposed to be part of V2.

```sql
ALTER TABLE employees
ADD CONSTRAINT fk_employees_department
FOREIGN KEY (department_id) REFERENCES departments(id);
```

---

## Step 5: Update the Migration Tracking

Mark V2 as successful now that we have completed it.

```sql
UPDATE schema_migrations SET success = true WHERE version = 2;
```

Verify.

```sql
SELECT version, description, success FROM schema_migrations ORDER BY version;
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

1. Wrap migrations in transactions when possible - DDL in PostgreSQL is transactional
2. Use `BEGIN; ... COMMIT;` in migration files
3. Always test migrations against a copy of production data before running them live
4. Use Flyway or Liquibase which handle transaction wrapping automatically
5. Keep DDL and DML in separate migration files so partial failure is cleaner

---

## Discussion Points

- Why did the DDL succeed but the DML fail? Common causes: data type mismatch, constraint violation, out of disk space, connection timeout
- What if Option B was not possible? You would need to DROP the departments table and department_id column, then re-run V2 from scratch
- How do transactions help? In PostgreSQL, even DDL is transactional. If the entire migration is in a single transaction, a DML failure rolls back the DDL too
