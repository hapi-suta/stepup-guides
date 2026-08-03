# SURVIVE 04 - FDW Connection Broken

**Difficulty:** Intermediate
**Estimated time:** 20 minutes

---

## The Situation

Your application team reports that cross-database reports stopped working at 11 PM last night. The errors in the application logs say:

```
ERROR: could not connect to server "remote_data_server"
DETAIL: could not translate host name "nonexistent-rds-endpoint.invalid.us-east-1.rds.amazonaws.com" to address: Name or service not known
```

All queries that touch `remote_source.*` tables are failing.

---

## What You Know

- The foreign data wrapper `postgres_fdw` is installed on the local database
- There is a foreign server named `remote_data_server`
- Queries that use `remote_source.source_data` are failing
- Something about the remote server's endpoint changed

---

## Your Goal

- Find out what changed with the foreign server connection
- Determine the correct endpoint for the remote server
- Update the foreign server configuration
- Verify all cross-database queries work again

---

## Step 1 - Diagnose the Problem

**Connect to the database:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d [DBNAME]
```

**Look at the foreign server configuration:**

```sql
SELECT srvname, srvoptions
FROM pg_foreign_server;
```

Expected output:
```
       srvname       |                              srvoptions
---------------------+----------------------------------------------------------------------
 remote_data_server  | {host=nonexistent-rds-endpoint.invalid.us-east-1.rds.amazonaws.com,
                     |  port=5432,dbname=postgres}
(1 row)
```

The host is wrong. It points to a nonexistent hostname.

**Try to query the foreign table to confirm the error:**

```sql
SELECT COUNT(*) FROM remote_source.source_data;
```

Expected error:
```
ERROR:  could not connect to server "remote_data_server"
DETAIL:  could not translate host name "nonexistent-rds-endpoint...." to address:
         Name or service not known
```

**Check user mappings:**

```sql
SELECT umuser::regrole, umoptions
FROM pg_user_mappings
WHERE srvid = (SELECT oid FROM pg_foreign_server WHERE srvname = 'remote_data_server');
```

The user mapping itself may be fine - just the server host is wrong.

---

## Step 2 - Find the Correct Endpoint

The remote server's endpoint has changed. You need to find the current correct endpoint.

**Check your AWS CLI for available RDS instances:**

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address,Status:DBInstanceStatus}' \
  --output table \
  --region [YOUR-REGION]
```

Expected output:
```
------------------------------------------------------------------------------------
|                          DescribeDBInstances                                     |
+----------------------------+--------------------------------------+---------------+
|            ID              |             Endpoint                 |    Status     |
+----------------------------+--------------------------------------+---------------+
|  my-postgres-instance      |  my-postgres.abc123.us-east-1...    |  available    |
|  my-remote-instance        |  my-remote.def456.us-east-1...      |  available    |
+----------------------------+--------------------------------------+---------------+
```

Identify which instance is the "remote" one that the foreign server should point to.

**If the remote and local are the same instance** (self-referential FDW in this lab), the correct host is your primary RDS endpoint.

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

---

## Step 3 - Update the Foreign Server

Once you have the correct endpoint, update the foreign server.

```sql
ALTER SERVER remote_data_server
OPTIONS (SET host '[CORRECT-ENDPOINT]');
```

Replace `[CORRECT-ENDPOINT]` with the actual RDS hostname.

**Verify the change:**

```sql
SELECT srvname, srvoptions
FROM pg_foreign_server
WHERE srvname = 'remote_data_server';
```

Expected output:
```
       srvname       |                     srvoptions
---------------------+----------------------------------------------
 remote_data_server  | {host=my-postgres.abc123.us-east-1.rds...,
                     |  port=5432,dbname=postgres}
(1 row)
```

---

## Step 4 - Test the Connection

```sql
-- Test basic connectivity
SELECT COUNT(*) FROM remote_source.source_data;
```

Expected output:
```
 count
-------
   100
(1 row)
```

**Run a more complete test:**

```sql
SELECT id, name, value
FROM remote_source.source_data
ORDER BY id
LIMIT 5;
```

Expected output (yours will differ):
```
 id |    name    |       value
----+------------+--------------------
  1 | record_1   |  423.5812...
  2 | record_2   |  891.2347...
  3 | record_3   |   67.4521...
  4 | record_4   |  234.9871...
  5 | record_5   |  756.3412...
(5 rows)
```

---

## Step 5 - Investigate How This Happened

Check the RDS events log for the remote instance to understand why the endpoint changed:

```bash
aws rds describe-events \
  --source-identifier [REMOTE-INSTANCE-ID] \
  --source-type db-instance \
  --duration 1440 \
  --query 'Events[*].{Time:Date,Message:Message}' \
  --output table \
  --region [YOUR-REGION]
```

Common causes of FDW endpoint changes:
- **Instance restore:** Restoring from a snapshot creates a new instance with a different endpoint
- **Rename:** Renaming the RDS instance changes its endpoint
- **Multi-AZ failover:** In Aurora, the cluster endpoint stays the same, but direct instance endpoints can change
- **Security group change:** The connection attempt fails at network level (different error message)

---

## Step 6 - Add Monitoring and Resilience

**Create a connectivity check function:**

```sql
CREATE OR REPLACE FUNCTION check_fdw_connectivity()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  result text;
BEGIN
  BEGIN
    SELECT COUNT(*)::text INTO result
    FROM remote_source.source_data
    LIMIT 1;
    RETURN 'OK: ' || result || ' rows accessible';
  EXCEPTION WHEN OTHERS THEN
    RETURN 'FAILED: ' || SQLERRM;
  END;
END;
$$;
```

**Test it:**

```sql
SELECT check_fdw_connectivity();
```

Expected output:
```
   check_fdw_connectivity
------------------------------
 OK: 1 rows accessible
(1 row)
```

**Set up a regular connectivity check:** This function can be called from your monitoring system (pgBadger, custom scripts, CloudWatch) to detect FDW connectivity issues before they reach users.

---

## Step 7 - Document the Correct Configuration

Create an internal runbook entry with the correct FDW configuration:

```sql
-- Record the current working configuration
COMMENT ON SERVER remote_data_server IS
  'Foreign server for remote data queries. Correct endpoint: [CORRECT-ENDPOINT]. Last verified: [DATE]. Owner: [TEAM NAME].';
```

This comment survives schema dumps and is visible in psql with `\des+`.

---

## Root Cause and Prevention

**Root cause:** The foreign server's `host` option was changed to an invalid hostname. This can happen when:
- A remote RDS instance is renamed or recreated
- Someone manually edited the foreign server configuration incorrectly
- An endpoint was rotated as part of a disaster recovery test

**Prevention:**

1. **Use Aurora cluster endpoints instead of instance endpoints** where possible. The cluster endpoint stays stable across failovers and renames.

2. **Tag your foreign server with the expected endpoint** using `COMMENT ON SERVER`. When the endpoint changes, you have a record of what it should be.

3. **Add FDW connectivity to your monitoring checks.** A nightly check that runs `check_fdw_connectivity()` catches problems before production queries fail.

4. **Use pgaudit to log DDL changes.** `ALTER SERVER` is a DDL statement. If pgaudit is logging DDL, you will see exactly when and who changed the foreign server.

5. **Document all FDW connections in your infrastructure runbook** - source instance, target instance, database, user, and purpose.

---

## Run validate.sh to confirm your fix is complete.
