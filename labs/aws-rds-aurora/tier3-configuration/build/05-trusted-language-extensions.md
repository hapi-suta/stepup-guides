# BUILD 05 - Trusted Language Extensions (TLE)

**Time:** 30 minutes
**Goal:** Enable pg_tle, create a simple custom extension, and manage its lifecycle.

---

## Prerequisites

- RDS PostgreSQL 16 instance with your custom parameter group from BUILD 01
- psql access to the instance
- AWS CLI configured

---

## What Is TLE and Why Does It Exist?

Standard PostgreSQL extensions can be written in C. A C extension can do anything - allocate memory, open files, crash the server. AWS cannot allow arbitrary C code to run on managed RDS instances.

Trusted Language Extensions (pg_tle) solves this. It lets you write custom extensions in safe, sandboxed languages:
- SQL
- PL/pgSQL
- PL/Perl (when enabled)
- PL/v8 (JavaScript, when enabled)

These languages cannot crash the server or access the OS. AWS allows them on RDS.

> **Concept:** TLE is like the difference between a plugin that runs in your browser's JavaScript sandbox vs a desktop app that has full OS access. The sandbox is safe to allow from untrusted code.

**When would you use TLE?**
- You have organization-specific SQL utilities you want packaged as an extension
- You want to distribute helper functions across many databases in a controlled way
- You need a custom data validation function that isn't in core PostgreSQL
- You want version-controlled, installable business logic

---

## Part 1 - Enable pg_tle

pg_tle requires preloading at startup.

### Step 1 - Add to shared_preload_libraries

### Console

1. Go to the **RDS** console at [https://console.aws.amazon.com/rds](https://console.aws.amazon.com/rds).
2. In the left sidebar, click **Parameter groups**.
3. Click the name of your parameter group (e.g., **tier3-custom-pg16**).
4. Click the **Edit** button in the top-right corner of the page.
5. In the search bar, type `shared_preload_libraries` and press Enter.
6. Click the value field for `shared_preload_libraries`. You will see the libraries already loaded (e.g., `pg_stat_statements,pgaudit`).
7. Add `,pg_tle` to the end of the existing value. The full value should look like: `pg_stat_statements,pgaudit,pg_tle`.

   > **Important:** Include all existing libraries. Omitting a library removes it from the list.

8. Click **Save changes** at the top-right corner.

You should see a green banner confirming the parameter group was updated.

---

### CLI

Check what's currently in shared_preload_libraries first:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name tier3-custom-pg16 \
  --query 'Parameters[?ParameterName==`shared_preload_libraries`].ParameterValue' \
  --output text
```

Expected output (yours will differ):
```
pg_stat_statements,pgaudit
```

Now add pg_tle to the existing list:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements\,pgaudit\,pg_tle,ApplyMethod=pending-reboot"
```

> **Important:** Include all existing libraries when you update `shared_preload_libraries`. Omitting a library removes it from the list.

### Step 2 - Reboot the Instance

### Console

1. In the left sidebar, click **Databases**.
2. Click your instance name (e.g., **tier3-postgres**) to open its detail page.
3. Click the **Actions** button in the top-right corner.
4. Click **Reboot** from the dropdown menu.
5. A confirmation dialog appears. Leave **Reboot with failover** unchecked (this is a single instance). Click **Confirm**.

You will see the instance status change to **Rebooting**. Wait until the status returns to **Available** - this usually takes 1-3 minutes. Refresh the page to check the current status.

---

### CLI

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

Wait for the instance to become available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

### Step 3 - Create the pg_tle Extension

Connect to psql and create the extension:

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_tle;
```

**Verify pg_tle is installed:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'pg_tle';
```

Expected output (yours will differ):
```
  name  | installed_version
--------+-------------------
 pg_tle | 1.4.0
(1 row)
```

**Check what pg_tle functions are now available:**

```sql
\df pgtle.*
```

Expected output (yours will differ):
```
                                     List of functions
 Schema |           Name           | Result data type |    Argument data types
--------+--------------------------+------------------+----------------------------------
 pgtle  | available_extensions     | SETOF record     |
 pgtle  | extension_owner_uid      | oid              | extname text
 pgtle  | install_element          | void             | ...
 pgtle  | install_extension        | boolean          | ...
 pgtle  | install_extension_version_sql | void        | ...
 pgtle  | set_default_version      | boolean          | ...
 pgtle  | uninstall_extension      | boolean          | ...
 pgtle  | uninstall_extension_version | boolean       | ...
 ...
(12 rows)
```

---

## Part 2 - Create a Simple TLE Extension

You will create an extension called `company_utils` that provides common utility functions for a fictional company.

### Step 1 - Write the Extension SQL

This extension will provide:
- `company_utils.mask_email(email text)` - masks an email for display (e.g., `j***@example.com`)
- `company_utils.is_strong_password(pw text)` - checks if a password meets basic strength rules

```sql
SELECT pgtle.install_extension(
  'company_utils',          -- extension name
  '1.0',                    -- version
  'Company utility functions for [COMPANY]',  -- description
  $install$
    -- Function 1: Mask an email address for display
    CREATE OR REPLACE FUNCTION company_utils.mask_email(email text)
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE STRICT
    AS $$
    DECLARE
      parts text[];
      local_part text;
      domain_part text;
      masked text;
    BEGIN
      parts := string_to_array(email, '@');
      IF array_length(parts, 1) != 2 THEN
        RETURN '***@***.***';
      END IF;
      local_part := parts[1];
      domain_part := parts[2];
      IF length(local_part) <= 1 THEN
        masked := local_part || '***';
      ELSE
        masked := left(local_part, 1) || repeat('*', 3);
      END IF;
      RETURN masked || '@' || domain_part;
    END;
    $$;

    -- Function 2: Check password strength
    CREATE OR REPLACE FUNCTION company_utils.is_strong_password(pw text)
    RETURNS boolean
    LANGUAGE plpgsql
    IMMUTABLE STRICT
    AS $$
    BEGIN
      -- Must be at least 12 characters
      IF length(pw) < 12 THEN RETURN false; END IF;
      -- Must contain at least one digit
      IF pw !~ '[0-9]' THEN RETURN false; END IF;
      -- Must contain at least one uppercase letter
      IF pw !~ '[A-Z]' THEN RETURN false; END IF;
      -- Must contain at least one special character
      IF pw !~ '[^a-zA-Z0-9]' THEN RETURN false; END IF;
      RETURN true;
    END;
    $$;
  $install$
);
```

**Verify the extension was registered in pg_tle:**

```sql
SELECT *
FROM pgtle.available_extensions()
WHERE name = 'company_utils';
```

Expected output (yours will differ):
```
     name      | default_version |             comment
---------------+-----------------+----------------------------------
 company_utils | 1.0             | Company utility functions for...
(1 row)
```

### Step 2 - Activate the Extension in Your Database

Installing the extension with `pgtle.install_extension` just registers it. You still need to run `CREATE EXTENSION` to activate it in a specific database.

TLE functions reference the schema by the same name as the extension, so create it first:

```sql
CREATE SCHEMA IF NOT EXISTS company_utils;
```

```sql
CREATE EXTENSION IF NOT EXISTS company_utils;
```

**Verify it is now active:**

```sql
\dx company_utils
```

Expected output (yours will differ):
```
                         List of installed extensions
     Name      | Version |   Schema    |           Description
---------------+---------+-------------+---------------------------------
 company_utils | 1.0     | public      | Company utility functions for...
(1 row)
```

---

## Part 3 - Use the TLE Extension

**Test the mask_email function:**

```sql
SELECT company_utils.mask_email('john.smith@example.com') AS masked;
```

Expected output (yours will differ):
```
    masked
----------------
 j***@example.com
(1 row)
```

**Test the is_strong_password function:**

```sql
SELECT
  company_utils.is_strong_password('weak') AS weak_password,
  company_utils.is_strong_password('MyStr0ng!Password') AS strong_password;
```

Expected output (yours will differ):
```
 weak_password | strong_password
---------------+-----------------
 f             | t
(1 row)
```

**Use it in a real query:**

```sql
-- Create a test users table
CREATE TABLE test_users (
  id    serial PRIMARY KEY,
  email text NOT NULL
);

INSERT INTO test_users (email) VALUES
  ('alice@example.com'),
  ('bob@company.org'),
  ('charlie@gmail.com');

-- Query with masked emails
SELECT id, company_utils.mask_email(email) AS displayed_email
FROM test_users;
```

Expected output (yours will differ):
```
 id |  displayed_email
----+------------------
  1 | a***@example.com
  2 | b***@company.org
  3 | c***@gmail.com
(3 rows)
```

---

## Part 4 - Add a New Version

You can install a new version of a TLE extension without removing the old one. Users on older versions keep working until they upgrade.

```sql
SELECT pgtle.install_extension_version_sql(
  'company_utils',    -- extension name
  '1.1',              -- new version
  $update_sql$
    -- New in 1.1: truncate_text function
    CREATE OR REPLACE FUNCTION company_utils.truncate_text(
      input_text text,
      max_length integer DEFAULT 100
    )
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE STRICT
    AS $$
    BEGIN
      IF length(input_text) <= max_length THEN
        RETURN input_text;
      END IF;
      RETURN left(input_text, max_length - 3) || '...';
    END;
    $$;
  $update_sql$
);
```

**Set 1.1 as the new default version:**

```sql
SELECT pgtle.set_default_version('company_utils', '1.1');
```

**Register the upgrade path from 1.0 to 1.1 so ALTER EXTENSION UPDATE works:**

```sql
SELECT pgtle.install_update_path(
  'company_utils',
  '1.0',
  '1.1',
  $update_path$
    CREATE OR REPLACE FUNCTION company_utils.truncate_text(
      input_text text,
      max_length integer DEFAULT 100
    )
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE STRICT
    AS $$
    BEGIN
      IF length(input_text) <= max_length THEN
        RETURN input_text;
      END IF;
      RETURN left(input_text, max_length - 3) || '...';
    END;
    $$;
  $update_path$
);
```

**Upgrade the extension in your database:**

```sql
ALTER EXTENSION company_utils UPDATE TO '1.1';
```

**Verify the upgrade:**

```sql
\dx company_utils
```

Expected output (yours will differ):
```
                         List of installed extensions
     Name      | Version |   Schema    |           Description
---------------+---------+-------------+---------------------------------
 company_utils | 1.1     | public      | Company utility functions for...
(1 row)
```

**Test the new function:**

```sql
SELECT company_utils.truncate_text('This is a very long text that needs to be shortened for display purposes', 30);
```

Expected output (yours will differ):
```
          truncate_text
---------------------------------
 This is a very long text th...
(1 row)
```

---

## Part 5 - Manage TLE Lifecycle

### List All Installed TLE Extensions

```sql
SELECT name, default_version
FROM pgtle.available_extensions();
```

### Deactivate in a Database (Without Uninstalling)

```sql
DROP EXTENSION company_utils;
```

This removes the extension from the current database but keeps it registered in pg_tle. Other databases can still use it.

### Fully Uninstall a TLE Extension

To remove all versions and the registration:

```sql
SELECT pgtle.uninstall_extension('company_utils');
```

To remove only a specific version:

```sql
SELECT pgtle.uninstall_extension_version('company_utils', '1.0');
```

---

## Summary

| Step | Command |
|---|---|
| Enable TLE | Add `pg_tle` to `shared_preload_libraries`, reboot, `CREATE EXTENSION pg_tle` |
| Register extension | `SELECT pgtle.install_extension(...)` |
| Activate in database | `CREATE EXTENSION [name]` |
| Add new version | `SELECT pgtle.install_extension_version_sql(...)` |
| Set default version | `SELECT pgtle.set_default_version(...)` |
| Upgrade in database | `ALTER EXTENSION [name] UPDATE TO '1.1'` |
| Deactivate in database | `DROP EXTENSION [name]` |
| Fully uninstall | `SELECT pgtle.uninstall_extension(...)` |

---

## Cleanup

```sql
DROP EXTENSION IF EXISTS company_utils;
SELECT pgtle.uninstall_extension('company_utils');
DROP TABLE IF EXISTS test_users;
```

---

## Next Steps

- [BUILD 06 - Foreign Data Wrappers](06-foreign-data-wrappers.md)
