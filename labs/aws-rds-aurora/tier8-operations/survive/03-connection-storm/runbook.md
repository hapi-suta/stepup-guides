# Runbook: Connection Storm - Application Bug Causing Connection Explosion

**Severity:** Critical
**Scenario:** max_connections exceeded. Application requests failing with "too many clients already."

---

## Symptoms

- CloudWatch alarm: `DatabaseConnections` at or above `max_connections`
- Application errors: `FATAL: sorry, too many clients already`
- `remaining connection slots are reserved for non-replication superuser connections` (when even superuser slots are exhausted)
- High application error rate, correlated with a recent deployment or traffic spike

---

## Immediate Actions (first 5 minutes)

1. Connect using the superuser account. PostgreSQL reserves slots for superusers even when max_connections is exceeded.

```bash
psql \
  --host=[RDS-ENDPOINT] \
  --port=5432 \
  --username=[MASTER-USER] \
  --dbname=postgres
```

2. Confirm connection exhaustion:

```sql
SELECT count(*) AS total_connections,
       current_setting('max_connections') AS max_connections
FROM pg_stat_activity;
```

3. Get the breakdown by state:

```sql
SELECT state, count(*) AS connection_count
FROM pg_stat_activity
GROUP BY state
ORDER BY connection_count DESC;
```

4. Post to incident channel: "Connection storm on [INSTANCE]. Actively investigating. ETA for first update: 5 minutes."

---

## Diagnosis

### Identify the connection source

```sql
SELECT application_name, state, count(*) AS count
FROM pg_stat_activity
GROUP BY application_name, state
ORDER BY count DESC;
```

The application_name and state breakdown reveals whether connections are:
- Coming from one application (application bug or pool misconfiguration)
- All idle-in-transaction (application not committing transactions)
- All idle (application holding connections open without using them)
- All active (genuine traffic spike)

### Find long-lived problematic connections

```sql
-- Idle-in-transaction sessions (most common storm cause)
SELECT pid, now() - xact_start AS duration, application_name, state, left(query, 80) AS query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY duration DESC
LIMIT 20;
```

```sql
-- All long-running connections
SELECT pid, now() - backend_start AS session_duration, state, application_name
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY session_duration DESC
LIMIT 20;
```

### Check for a recent configuration change

Was max_connections recently reduced? Check the parameter group:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --query 'Parameters[?ParameterName==`max_connections`]' \
  --region [REGION]
```

Also check RDS events for recent reboots or parameter group changes:

```bash
aws rds describe-events \
  --source-identifier [INSTANCE-ID] \
  --source-type db-instance \
  --duration 240 \
  --region [REGION]
```

---

## Remediation

### Option 1: Terminate idle-in-transaction connections (no downtime, immediate)

This is the first action if idle-in-transaction connections are the cause:

```sql
-- Show what you will terminate before doing it
SELECT count(*) FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND now() - xact_start > interval '5 minutes';

-- Terminate sessions idle-in-transaction for more than 5 minutes
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND now() - xact_start > interval '5 minutes'
AND pid <> pg_backend_pid();
```

After termination, check if connections drop to a healthy level:

```sql
SELECT count(*), current_setting('max_connections') AS max_connections
FROM pg_stat_activity;
```

### Option 2: Terminate idle connections (if idle connections are the problem)

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND now() - state_change > interval '10 minutes'
AND pid <> pg_backend_pid();
```

### Option 3: Increase max_connections (requires database restart)

Only do this if options 1 and 2 do not free enough slots. This causes brief downtime.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot \
  --region [REGION]

aws rds reboot-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --region [REGION]
```

Communicate the restart time to the application team before executing.

---

## Verification

After terminating problematic connections:

```sql
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
```

Connection count should be well below max_connections. Application error rate should drop as the application pool recovers and new connections can be established.

---

## Prevention

1. **Set `idle_in_transaction_session_timeout`:** Automatically terminates sessions that have been idle in a transaction for too long.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters ParameterName=idle_in_transaction_session_timeout,ParameterValue=300000,ApplyMethod=immediate \
  --region [REGION]
```

`300000` ms = 5 minutes. Any session idle in a transaction for 5 minutes is automatically terminated.

2. **Set `statement_timeout`:** Prevents any single statement from running indefinitely.

3. **Deploy PgBouncer or RDS Proxy:** This is the systemic fix. Connection poolers multiplex application connections so the database never sees more than its configured maximum.

4. **Alert at 70% of max_connections:** The current alert at 100% is too late. Alert when connections reach 70% of max so you have time to investigate before the outage.

5. **Restore max_connections to the correct value:** If the storm was caused by a misconfigured max_connections setting, restore it.

---

## Escalation

If connections continue to climb after terminating idle sessions, the root cause is a connection leak in the application - connections are being opened but never closed. This requires the application team to:
- Review connection pool configuration
- Check for unclosed connection objects in the code
- Deploy an application fix (this is a code-level issue, not a database issue)
