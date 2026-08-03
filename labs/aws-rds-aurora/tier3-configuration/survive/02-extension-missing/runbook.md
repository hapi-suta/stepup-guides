# SURVIVE 02 - Extension Missing

**Difficulty:** Intermediate
**Estimated time:** 20 minutes

---

## The Situation

Your application monitoring system sends an alert at 2 AM:

```
ERROR: relation "pg_stat_statements" does not exist
ERROR: Failed to call refresh_query_log()
ALERT: Query monitoring dashboard is offline
```

Developers also report that a view used by the ops dashboard is broken.

---

## What You Know

- The error references `pg_stat_statements` not existing
- The monitoring dashboard stopped working 30 minutes ago
- No application code was deployed in the last 24 hours
- Someone had database access during a weekend maintenance window

---

## Your Goal

- Identify which extension is missing
- Reinstall it correctly
- Restore all dependent objects (view, procedure)
- Verify the application monitoring is working again

---

## Step 1 - Diagnose

**Connect to the database:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d [DBNAME]
```

**Check which extensions are installed:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

**Check if pg_stat_statements is available but not installed:**

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

If `installed_version` is null but `default_version` has a value, the extension is available but was dropped.

**Try querying the broken view:**

```sql
SELECT * FROM app_slow_queries LIMIT 1;
```

Expected error:
```
ERROR:  relation "pg_stat_statements" does not exist
LINE 5: FROM pg_stat_statements
```

**Find broken views:**

```sql
SELECT schemaname, viewname, definition
FROM pg_views
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY viewname;
```

Look for any view that references `pg_stat_statements`.

**Check the shared_preload_libraries setting:**

```sql
SHOW shared_preload_libraries;
```

If `pg_stat_statements` is still in `shared_preload_libraries`, you just need to recreate the extension. If it is missing from there too, you need a parameter change and reboot first.

---

## Step 2 - Verify the Module Is Still Loaded

The `shared_preload_libraries` parameter may still have `pg_stat_statements`. If so, the module is loaded but the extension objects were dropped from the database catalog.

```sql
SHOW shared_preload_libraries;
```

Expected output:
```
    shared_preload_libraries
-----------------------------
 pg_stat_statements,pgaudit
(1 row)
```

If `pg_stat_statements` is in the output, the module is loaded. You just need to recreate the extension.

If it is NOT in the output, you need to:
1. Add it back to `shared_preload_libraries` in the parameter group
2. Reboot the instance
3. Then proceed with step 3

---

## Step 3 - Recreate the Extension

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

**Verify:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

Expected output:
```
        name        | installed_version
--------------------+-------------------
 pg_stat_statements | 1.10
(1 row)
```

---

## Step 4 - Check and Restore Dependent Objects

When an extension is dropped with `CASCADE`, all objects that depended on it (views, functions) are dropped too.

**Check if the view still exists:**

```sql
SELECT viewname FROM pg_views WHERE viewname = 'app_slow_queries';
```

If the view is missing, recreate it:

```sql
CREATE OR REPLACE VIEW app_slow_queries AS
SELECT
  LEFT(query, 200) AS query_text,
  calls,
  round(mean_exec_time::numeric, 2) AS avg_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 50;
```

**Check if the procedure still exists:**

```sql
SELECT proname FROM pg_proc WHERE proname = 'refresh_query_log';
```

If missing, recreate it:

```sql
CREATE OR REPLACE PROCEDURE refresh_query_log()
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO app_query_log (query_text, avg_ms)
  SELECT query_text, avg_ms
  FROM app_slow_queries
  WHERE avg_ms > 100;
END;
$$;
```

---

## Step 5 - Test the Fix

**Test the view:**

```sql
SELECT COUNT(*) FROM app_slow_queries;
```

Expected output:
```
 count
-------
     0
(1 row)
```

Zero rows is fine - pg_stat_statements was just recreated so it has no data yet. The important thing is that there is no error.

**Test the procedure:**

```sql
CALL refresh_query_log();
```

Expected output:
```
CALL
```

No error means the procedure ran successfully.

**Generate some query activity and verify tracking works:**

```sql
-- Run some queries to populate pg_stat_statements
SELECT count(*) FROM pg_catalog.pg_class;
SELECT version();
SELECT now();

-- Check that pg_stat_statements is tracking them
SELECT query, calls FROM pg_stat_statements ORDER BY calls DESC LIMIT 5;
```

---

## Step 6 - Prevent Recurrence

**Add a safeguard check to your monitoring:**

```sql
-- Create an alert table for missing extensions
CREATE TABLE IF NOT EXISTS extension_health_log (
  checked_at timestamptz DEFAULT now(),
  extension_name text,
  status text
);

-- Create a function to check extension health
CREATE OR REPLACE FUNCTION check_required_extensions()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  required_extensions text[] := ARRAY['pg_stat_statements', 'pgaudit'];
  ext text;
  installed boolean;
BEGIN
  FOREACH ext IN ARRAY required_extensions
  LOOP
    SELECT (installed_version IS NOT NULL)
    INTO installed
    FROM pg_available_extensions
    WHERE name = ext;

    INSERT INTO extension_health_log (extension_name, status)
    VALUES (ext, CASE WHEN installed THEN 'OK' ELSE 'MISSING' END);

    IF NOT installed THEN
      RAISE WARNING 'CRITICAL: Extension % is not installed', ext;
    END IF;
  END LOOP;
END;
$$;
```

**Revoke DROP privilege to prevent future drops:**

```sql
-- Revoke the ability to drop extensions from non-superusers
-- (only superusers or extension owners can drop by default,
--  but make sure your app user doesn't have SUPERUSER)
SELECT rolname, rolsuper
FROM pg_roles
WHERE rolname = '[YOUR-APP-USERNAME]';
```

If your application user has `rolsuper = true`, that is too much privilege. Revoke it.

---

## Root Cause and Prevention

**Root cause:** Someone with superuser access ran `DROP EXTENSION pg_stat_statements CASCADE` during the maintenance window. The `CASCADE` option automatically dropped all objects that depended on the extension (the view and procedure) without warning.

**Prevention measures:**

1. **Use separate credentials** for maintenance vs application work. Maintenance credentials should be temporary.

2. **Enable pgaudit DDL logging.** A `DROP EXTENSION` statement would have appeared in audit logs, identifying who did it and when.

3. **Never run `DROP EXTENSION CASCADE`** in production without understanding what objects will be dropped. Always run `DROP EXTENSION [name]` without CASCADE first - it will fail if there are dependencies, which is your warning.

4. **Check `\dx` before any extension drop** to see what's installed.

5. **Script your extension recreations** and store them in version control. Recovery is fast if you have the scripts ready.

---

## Run validate.sh to confirm your fix is complete.
