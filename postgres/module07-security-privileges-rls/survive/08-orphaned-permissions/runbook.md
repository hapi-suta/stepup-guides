# Scenario 08 - Orphaned Permissions

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Queries against analytics_events and
analytics_metrics are failing with permission errors.
The analytics_admin role was dropped last week.
These tables appear to have no valid owner.
```

---

## Key Concepts for Revision

- **Every object has an owner** - In PostgreSQL, every table, view, function, and sequence has an owner stored as an OID in `pg_class.relowner`. If the role corresponding to that OID is dropped, the object becomes orphaned - the OID points to nothing.

- **REASSIGN OWNED BY before dropping roles** - Always run `REASSIGN OWNED BY rolename TO new_owner` before dropping a role. This transfers all objects owned by the role to a new owner. Follow with `DROP OWNED BY rolename` to remove any remaining privileges, then `DROP ROLE rolename`.

- **Orphaned objects cause permission errors** - When an object's owner OID does not map to any existing role, PostgreSQL cannot resolve ownership checks. This can cause unexpected permission denied errors and makes the object unmanageable.

- **pg_class.relowner links to pg_roles.oid** - To find orphaned objects, join `pg_class` with `pg_roles` on `relowner = oid` and look for rows where the join fails (no matching role).

---

## Diagnostic Steps

### Step 1 - Confirm the error

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT * FROM analytics_events LIMIT 1;
```

This may return data (since you are the superuser) or may show an error. The issue is that the table has no valid owner.

### Step 2 - Find objects with invalid owners

```sql
SELECT c.relname, c.relkind, c.relowner,
       r.rolname AS owner_name
FROM pg_class c
LEFT JOIN pg_roles r ON r.oid = c.relowner
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND c.relkind IN ('r', 'S', 'v')
  AND r.oid IS NULL;
```

Expected output (yours will differ):

```
      relname       | relkind | relowner | owner_name
--------------------+---------+----------+------------
 analytics_events   | r       |    99999 |
 analytics_metrics  | r       |    99999 |
(2 rows)
```

The `owner_name` is NULL because the OID 99999 does not correspond to any existing role. These are orphaned objects.

### Step 3 - Check sequences too

```sql
SELECT c.relname, c.relkind, c.relowner
FROM pg_class c
LEFT JOIN pg_roles r ON r.oid = c.relowner
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND c.relkind = 'S'
  AND r.oid IS NULL;
```

Check if any sequences are also orphaned.

---

## Resolution

### Step 1 - Reassign ownership of orphaned tables to postgres

```sql
ALTER TABLE analytics_events OWNER TO postgres;
```

Expected output:

```
ALTER TABLE
```

```sql
ALTER TABLE analytics_metrics OWNER TO postgres;
```

Expected output:

```
ALTER TABLE
```

### Step 2 - Reassign any orphaned sequences

Check for orphaned sequences related to these tables.

```sql
SELECT c.relname, c.relowner
FROM pg_class c
LEFT JOIN pg_roles r ON r.oid = c.relowner
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND c.relkind = 'S'
  AND r.oid IS NULL;
```

If any appear, reassign them. For example:

```sql
ALTER SEQUENCE analytics_events_id_seq OWNER TO postgres;
```

```sql
ALTER SEQUENCE analytics_metrics_id_seq OWNER TO postgres;
```

### Step 3 - Verify no orphaned objects remain

```sql
SELECT c.relname, c.relkind, c.relowner
FROM pg_class c
LEFT JOIN pg_roles r ON r.oid = c.relowner
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND c.relkind IN ('r', 'S', 'v')
  AND r.oid IS NULL;
```

Expected output:

```
 relname | relkind | relowner
---------+---------+----------
(0 rows)
```

No more orphaned objects.

### Step 4 - Grant access to app_user

```sql
GRANT SELECT, INSERT, UPDATE ON analytics_events TO app_user;
```

Expected output:

```
GRANT
```

```sql
GRANT SELECT, INSERT, UPDATE ON analytics_metrics TO app_user;
```

Expected output:

```
GRANT
```

```sql
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;
```

Expected output:

```
GRANT
```

### Step 5 - Verify access works

```sql
SET ROLE app_user;
```

```sql
SELECT count(*) FROM analytics_events;
```

Expected output (yours will differ):

```
 count
-------
     1
(1 row)
```

```sql
RESET ROLE;
```

### Step 6 - Exit

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- No orphaned objects with invalid owners
- analytics_events has a valid owner
- analytics_metrics has a valid owner
- app_user can query both tables

---

## Interview Discussion Points

1. **What is the correct procedure for dropping a role that owns objects?** - Three steps in order: (1) `REASSIGN OWNED BY rolename TO new_owner` - transfers all objects to a new owner. (2) `DROP OWNED BY rolename` - removes any remaining privileges, default privileges, and memberships. (3) `DROP ROLE rolename` - removes the role itself. Skipping step 1 leaves orphaned objects. Skipping step 2 leaves the role with dependencies that prevent dropping.

2. **What happens if you try to DROP ROLE without REASSIGN OWNED first?** - PostgreSQL raises an error: `ERROR: role "rolename" cannot be dropped because some objects depend on it`. It lists the dependent objects. This is a safety mechanism. However, if the OID mapping is manually corrupted (or objects were created in a restored dump), orphaned objects can exist without this safety catching them.

3. **How would you find all objects owned by a specific role before dropping it?** - Use `SELECT * FROM pg_catalog.pg_shdepend WHERE refobjid = (SELECT oid FROM pg_roles WHERE rolname = 'rolename')`. This shows all shared dependencies. Alternatively, `\dt rolename.*` in psql shows tables, and `SELECT * FROM pg_proc WHERE proowner = (SELECT oid FROM pg_roles WHERE rolname = 'rolename')` shows functions.

4. **Should you reassign ownership to postgres or to another application role?** - Reassign to a dedicated admin or application role, not `postgres`. Having the `postgres` superuser own application tables blurs the boundary between system and application objects. Create a role like `app_admin` that owns application objects and grant admin privileges as needed.

5. **How do you prevent orphaned objects in an automated deployment pipeline?** - Include a pre-drop check in your deployment scripts: `SELECT count(*) FROM pg_shdepend WHERE refobjid = (SELECT oid FROM pg_roles WHERE rolname = $1)`. If the count is greater than zero, run REASSIGN OWNED and DROP OWNED before DROP ROLE. Make this a standard step in your role lifecycle management.
