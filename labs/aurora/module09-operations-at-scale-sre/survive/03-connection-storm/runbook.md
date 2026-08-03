# Runbook: Connection Storm (Reconnect Flood)

**Severity:** Critical
**Last Updated:** 2026-06-09
**Owner:** DBA Team

---

## Symptoms

- CloudWatch alarm: DatabaseConnections exceeds 80% of max_connections
- Application errors: "too many connections" or "connection refused"
- CPU spike from connection overhead
- Write latency degradation
- Multiple application pods reconnecting simultaneously

---

## Impact

- New connections are refused once max_connections is reached
- Existing queries slow down due to CPU overhead from connection management
- If idle-in-transaction sessions accumulate, they can block VACUUM and cause bloat
- Read replicas may also be impacted if applications connect to readers

---

## Immediate Actions (first 5 minutes)

### Step 1: Assess Connection State

Connect to the writer endpoint and check the connection breakdown:

```sql
SELECT
    state,
    count(*) AS count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY count DESC;
```

### Step 2: Identify Top Connection Sources

```sql
-- By user
SELECT usename, count(*) AS count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY usename
ORDER BY count DESC;

-- By client address
SELECT client_addr, count(*) AS count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND client_addr IS NOT NULL
GROUP BY client_addr
ORDER BY count DESC;

-- By database
SELECT datname, count(*) AS count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY datname
ORDER BY count DESC;
```

### Step 3: Check Connection Utilization

```sql
SELECT
    count(*) AS current_connections,
    current_setting('max_connections')::int AS max_connections,
    round(count(*)::numeric / current_setting('max_connections')::int * 100, 1)
        AS utilization_pct
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

---

## Diagnosis

### Check for Idle-in-Transaction Sessions

```sql
SELECT
    pid,
    usename,
    datname,
    client_addr,
    state,
    left(query, 100) AS query,
    round(extract(epoch FROM now() - state_change)::numeric, 0) AS idle_seconds
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND backend_type = 'client backend'
ORDER BY state_change ASC;
```

### Check for the Storm Source

If one user or one client address has an abnormal number of connections, that is the storm source.

```sql
-- Find users with more than 20 connections
SELECT usename, count(*) AS count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY usename
HAVING count(*) > 20
ORDER BY count DESC;
```

---

## Remediation

### Fix 1: Terminate Idle-in-Transaction Sessions (> 5 minutes)

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND extract(epoch FROM now() - state_change) > 300
  AND backend_type = 'client backend'
  AND pid != pg_backend_pid();
```

### Fix 2: Terminate Storm User Connections

If you identify a specific user causing the storm:

```sql
-- Replace 'storm-user' with the actual username
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = 'storm-user'
  AND backend_type = 'client backend'
  AND pid != pg_backend_pid();
```

### Fix 3: Revoke Connect Privilege (if user should not connect)

```sql
-- Prevent the user from reconnecting
REVOKE CONNECT ON DATABASE postgres FROM "storm-user";

-- Or drop the user entirely (after terminating all connections)
DROP ROLE IF EXISTS "storm-user";
```

### Fix 4: Set Connection Limits

Prevent future storms by setting per-user connection limits:

```sql
-- Limit application users to a reasonable number
ALTER ROLE app_user CONNECTION LIMIT 100;

-- Check current limits
SELECT rolname, rolconnlimit
FROM pg_roles
WHERE rolconnlimit != -1;
```

---

## Verification

After terminating storm connections:

```sql
-- Check connections are back to baseline
SELECT
    count(*) AS current_connections,
    current_setting('max_connections')::int AS max_connections,
    round(count(*)::numeric / current_setting('max_connections')::int * 100, 1)
        AS utilization_pct
FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- Verify no idle-in-transaction sessions remain
SELECT count(*) FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND extract(epoch FROM now() - state_change) > 300;

-- Verify storm user is removed
SELECT rolname FROM pg_roles WHERE rolname LIKE '%storm%';
```

Run `validate.sh` to confirm all checks pass.

---

## Prevention

1. Deploy RDS Proxy or PgBouncer as a connection pooler
2. Set `idle_in_transaction_session_timeout` to 300000 (5 minutes)
3. Set per-role connection limits for application users
4. Add CloudWatch alarm for connection rate-of-change (> 50% increase in 5 minutes)
5. Implement exponential backoff with jitter in application reconnection logic
6. Add Lambda automation to auto-terminate idle-in-transaction sessions

---

## Escalation

- If connections reach 95% of max_connections: escalate to engineering lead
- If terminating sessions causes application failures: coordinate with application team
- If connection storm is caused by a security incident (unauthorized user): escalate to security team
