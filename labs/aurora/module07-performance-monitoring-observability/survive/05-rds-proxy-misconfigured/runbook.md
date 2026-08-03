# Runbook: RDS Proxy Misconfigured (Connection Pinning)

**Scenario:** RDS Proxy is deployed but most connections are pinned, meaning they cannot be multiplexed. The proxy is not providing its expected benefit. Connection count is as high as without a proxy.

**Time limit:** 20 minutes
**Severity:** P2 - Reduced connection efficiency, risk of exhaustion

---

## Symptoms

- RDS Proxy CloudWatch metric `DatabaseConnectionsCurrentlySessionPinned` is high
- Connection count on the database is much higher than expected with a proxy
- Applications experience connection timeouts despite proxy being deployed
- Proxy is not multiplexing connections as expected

---

## Step 1 - Identify Pinned Sessions

Find sessions that have session-level state (which causes pinning):

```sql
SELECT
    pid,
    usename,
    application_name,
    state,
    left(query, 80) AS last_query
FROM pg_stat_activity
WHERE application_name LIKE 'pinned_session%'
ORDER BY application_name;
```

---

## Step 2 - Identify Pinning Causes

**Check for SET commands (search_path, work_mem, etc.):**

Sessions that use SET commands get pinned because the proxy cannot share their connection with other clients that have different settings.

```sql
SELECT
    pid,
    application_name,
    left(query, 100) AS query
FROM pg_stat_activity
WHERE application_name LIKE 'pinned_session%'
  AND query LIKE '%SET%';
```

**Check for temporary tables:**

```sql
SELECT
    pid,
    application_name
FROM pg_stat_activity
WHERE application_name LIKE 'pinned_session%';
```

Temp tables are per-session objects. A connection with temp tables cannot be shared.

**Check for advisory locks:**

```sql
SELECT
    l.pid,
    a.application_name,
    l.classid,
    l.objid,
    l.granted
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.locktype = 'advisory';
```

---

## Step 3 - Categorize Pinning Causes

| Pinning Cause | Sessions | Fix |
|---------------|---------|-----|
| SET commands | ___ | Move to parameter group |
| Temp tables | ___ | Use regular tables or CTEs |
| Advisory locks | ___ | Use transaction-level locks |
| Prepared statements | ___ | Use driver-level settings |
| LISTEN/NOTIFY | ___ | Use separate non-proxy connection |

---

## Step 4 - Kill Pinned Sessions (Immediate Mitigation)

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name LIKE 'pinned_session%'
  AND pid != pg_backend_pid();
```

---

## Step 5 - Fix SET Commands

Instead of using SET in application code:

```sql
-- BAD (causes pinning):
SET search_path = public, app_schema;
SET work_mem = '64MB';
```

Move these to the parameter group or role-level defaults:

```sql
-- GOOD (no pinning):
ALTER ROLE app_user SET search_path = 'public, app_schema';
ALTER ROLE app_user SET work_mem = '64MB';
```

Or use the RDS Proxy initialization query (set in the proxy configuration):
- Go to RDS Console > Proxies > Your Proxy > Modify
- Add initialization query: `SET search_path = public, app_schema`

---

## Step 6 - Fix Temporary Tables

Replace temporary tables with:

**Option A: CTEs (Common Table Expressions):**
```sql
-- BAD (causes pinning):
CREATE TEMP TABLE results AS SELECT ...;

-- GOOD (no pinning):
WITH results AS (SELECT ...) SELECT * FROM results;
```

**Option B: Regular tables with session tracking:**
```sql
-- BAD (causes pinning):
CREATE TEMP TABLE session_cache (id INT);

-- GOOD (no pinning):
CREATE TABLE IF NOT EXISTS session_cache (session_id TEXT, id INT);
-- Use a unique session identifier to isolate data
```

---

## Step 7 - Fix Advisory Locks

Replace session-level advisory locks with transaction-level ones:

```sql
-- BAD (causes pinning - lock held for entire session):
SELECT pg_advisory_lock(123);

-- GOOD (no pinning - lock released at end of transaction):
SELECT pg_advisory_xact_lock(123);
```

---

## Step 8 - Verify Fix

After applying the fixes and terminating pinned sessions:

```sql
-- Check for remaining pinned sessions
SELECT count(*) FROM pg_stat_activity
WHERE application_name LIKE 'pinned_session%';

-- Check for remaining advisory locks
SELECT count(*) FROM pg_locks WHERE locktype = 'advisory';

-- Check connection count is reasonable
SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';
```

---

## Prevention

1. **Audit application code** for SET commands, temp tables, and advisory locks before deploying RDS Proxy
2. **Use role-level defaults** (`ALTER ROLE ... SET`) instead of session-level SET
3. **Use transaction-level advisory locks** (`pg_advisory_xact_lock`) instead of session-level
4. **Monitor the `DatabaseConnectionsCurrentlySessionPinned` CloudWatch metric** for RDS Proxy
5. **Set up an alarm** when pinned connections exceed 30% of total proxy connections

---

## Post-Incident Check

```sql
-- No more pinned sessions
SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'pinned_%';

-- No stale advisory locks
SELECT count(*) FROM pg_locks WHERE locktype = 'advisory';

-- Connection count back to normal
SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count(*) DESC;
```
