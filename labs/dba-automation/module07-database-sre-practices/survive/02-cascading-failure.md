# SURVIVE 02: The Cascading Failure

**Module 07: Database SRE Practices**
**Difficulty: Hard**
**Estimated Time: 45 minutes**

---

## The Scenario

It is 10:15 AM on a Monday. Here is what happened in the last 15 minutes:

1. **10:00** - A marketing email blast drives 5x normal traffic to the application
2. **10:02** - PgBouncer's connection pool fills up. New connections start queuing.
3. **10:04** - Application instances start getting connection timeouts. They implement retry logic: if a request fails, retry 3 times with 1-second backoff.
4. **10:06** - The retries triple the request volume. PgBouncer's queue grows from 50 to 500 waiting connections.
5. **10:08** - Application health checks start failing because they also need database connections. The load balancer marks app instances as unhealthy and removes them.
6. **10:10** - Fewer app instances means surviving instances get MORE traffic. They also start failing.
7. **10:12** - Downstream services (inventory, notifications, analytics) that depend on the payment API start timing out. Their retry logic kicks in too.
8. **10:15** - You are paged. The entire platform is down. Every service is retrying, creating a thundering herd. Even if the database recovers, the retry storm will immediately overwhelm it again.

This is a **cascading failure** - one component failing causes dependent components to fail, which amplifies the original failure.

---

## The Architecture

```
Users -> Load Balancer -> App Instances (x10) -> PgBouncer -> PostgreSQL
                              |
                    +----+----+----+----+
                    |         |         |
              Inventory  Notifications  Analytics
              Service    Service        Service
```

### Current Configuration

| Component | Setting | Value |
|-----------|---------|-------|
| PgBouncer | max_client_conn | 200 |
| PgBouncer | default_pool_size | 20 |
| PgBouncer | reserve_pool_size | 5 |
| PgBouncer | query_wait_timeout | 120s |
| PostgreSQL | max_connections | 100 |
| Application | connection timeout | 30s |
| Application | retry count | 3 |
| Application | retry backoff | 1s fixed |

---

## Your Mission

1. **Break the cascade** - stop the bleeding RIGHT NOW
2. **Restore service** - bring the platform back up
3. **Implement safeguards** - prevent this from happening again

---

## Part 1: Break the Cascade (First 5 Minutes)

The immediate priority is stopping the thundering herd of retries. Every second you wait, the retry volume grows.

### Step 1: Reduce the Retry Storm

**On the application side (if you have access):**

The fastest fix is to tell the load balancer to return a static error page instead of routing to the application:

```
# If using AWS ALB - return fixed response
# This stops ALL traffic from reaching the application and database
```

If you cannot control the load balancer, ask the application team to deploy a feature flag that disables retry logic immediately.

### Step 2: Clear PgBouncer's Queue

**On the PgBouncer server, as ec2-user:**

```bash
sudo su - postgres
psql -p 6432 -U postgres pgbouncer
```

```sql
-- Check the current state
SHOW POOLS;
```

Expected output (yours will differ):
```
 database  |   user    | cl_active | cl_waiting | sv_active | sv_idle | sv_used | sv_login | maxwait
-----------+-----------+-----------+------------+-----------+---------+---------+----------+---------
 myapp     | app_user  |        20 |        487 |        20 |       0 |       0 |        0 |     180
```

487 clients are waiting. The pool is fully saturated.

```sql
-- Kill all client connections to clear the queue
-- This is aggressive but necessary to break the cascade
KILL myapp;

-- Verify the queue is cleared
SHOW POOLS;
```

```sql
\q
```

```bash
exit
```

### Step 3: Verify PostgreSQL is Healthy

**On the PostgreSQL primary, as postgres:**

```bash
sudo su - postgres
psql
```

```sql
-- Check if PostgreSQL itself is overloaded
SELECT
    count(*) AS total_conn,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn
FROM pg_stat_activity;

-- Kill any long-running queries that might be stuck
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
  AND pid != pg_backend_pid();

-- Check for lock contention
SELECT count(*) FROM pg_locks WHERE NOT granted;
```

```sql
\q
```

```bash
exit
```

---

## Part 2: Controlled Restart

You cannot just open the floodgates. If you allow all traffic back immediately, the retry storm will crash everything again. You need a controlled restart.

### Step 4: Reduce PgBouncer's Client Limit Temporarily

**On the PgBouncer server, as ec2-user:**

```bash
sudo vi /etc/pgbouncer/pgbouncer.ini
```

Temporarily set:

```ini
# Reduce client connections to prevent immediate re-flood
max_client_conn = 50        # Was 200 - temporarily limit
query_wait_timeout = 5      # Was 120 - fail fast instead of queuing
```

```bash
sudo systemctl reload pgbouncer
```

### Step 5: Re-enable Traffic Gradually

1. Allow the load balancer to route to 2 of 10 app instances (20% traffic)
2. Monitor for 5 minutes
3. If stable, increase to 5 instances (50%)
4. If stable, increase to all 10 instances

Monitor PgBouncer during each step:

```sql
-- Connect to PgBouncer admin
psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"
```

Watch for `cl_waiting` - if it starts growing, you are re-flooding.

### Step 6: Restore Full Configuration

Once all traffic is flowing without queue buildup:

```bash
sudo vi /etc/pgbouncer/pgbouncer.ini
```

Restore (but with improvements):

```ini
max_client_conn = 500       # Increase from original 200
default_pool_size = 40      # Increase from 20
reserve_pool_size = 10      # Increase from 5
query_wait_timeout = 10     # Decrease from 120 - fail fast
```

```bash
sudo systemctl reload pgbouncer
```

---

## Part 3: Implement Safeguards

### Safeguard 1: Circuit Breaker Pattern

A circuit breaker stops retries when a service is clearly down. Instead of retrying 3 times on every request (amplifying failure), the circuit breaker "opens" after detecting failures and returns errors immediately.

```
Circuit Breaker States:
  CLOSED  -> Requests flow normally
  OPEN    -> All requests fail immediately (no retries, no database hit)
  HALF-OPEN -> Let one request through to test if service recovered
```

**Application-side implementation (conceptual):**

```python
# Pseudo-code for circuit breaker
class CircuitBreaker:
    def __init__(self, failure_threshold=5, reset_timeout=30):
        self.failure_count = 0
        self.failure_threshold = failure_threshold
        self.reset_timeout = reset_timeout
        self.state = "CLOSED"
        self.last_failure_time = None

    def call(self, func):
        if self.state == "OPEN":
            if time_since(self.last_failure_time) > self.reset_timeout:
                self.state = "HALF_OPEN"
            else:
                raise CircuitOpenError("Service unavailable - circuit breaker open")

        try:
            result = func()
            if self.state == "HALF_OPEN":
                self.state = "CLOSED"
                self.failure_count = 0
            return result
        except Exception:
            self.failure_count += 1
            self.last_failure_time = now()
            if self.failure_count >= self.failure_threshold:
                self.state = "OPEN"
            raise
```

**DBA recommendation to the application team:** Implement a circuit breaker for database connections. After 5 consecutive failures, stop trying for 30 seconds. This prevents the retry storm.

### Safeguard 2: Exponential Backoff with Jitter

The current retry logic uses fixed 1-second backoff. This means all retries hit at the same time (thundering herd).

**Better approach:**

```
Retry 1: wait random(0, 2) seconds
Retry 2: wait random(0, 4) seconds
Retry 3: wait random(0, 8) seconds
```

The random jitter spreads retries over time instead of concentrating them.

### Safeguard 3: Separate Health Check Pool

Application health checks should NOT compete with user traffic for database connections. Create a separate PgBouncer pool for health checks:

```ini
# In pgbouncer.ini
[databases]
myapp = host=pg-primary port=5432 dbname=myapp pool_size=40
healthcheck = host=pg-primary port=5432 dbname=myapp pool_size=2
```

The application's health check endpoint uses the `healthcheck` database entry, which has its own dedicated 2-connection pool. Even if the main pool is exhausted, health checks still work.

### Safeguard 4: Connection Limits per Client

PgBouncer does not natively limit connections per application. But you can use PostgreSQL's `ALTER ROLE ... CONNECTION LIMIT`:

```sql
-- Limit app_user to 80 connections (leave headroom for admin)
ALTER ROLE app_user CONNECTION LIMIT 80;

-- monitoring user gets a reserved pool
ALTER ROLE monitoring CONNECTION LIMIT 5;
```

### Safeguard 5: Query Wait Timeout

The original `query_wait_timeout = 120s` meant clients waited 2 minutes in the queue before timing out. During a cascade, this keeps connections alive far too long.

```ini
# Fail fast: if no pool connection available in 10 seconds, return error
query_wait_timeout = 10
```

This is counterintuitive - shorter timeouts seem worse. But during a cascade, fast failure is better than slow failure because it prevents queue buildup.

### Safeguard 6: Load Shedding

Configure the application to reject requests when database latency exceeds a threshold:

```
If database_response_time > 2 seconds:
    Return HTTP 503 (Service Unavailable) with Retry-After header
    Do NOT retry internally
```

This protects the database by reducing load when it is struggling, allowing it to recover.

---

## Part 4: Post-Incident Configuration

```bash
vi ~/dba-labs/sre-practice/survive-budget/cascade-fix-config.md
```

```markdown
# Configuration Changes After Cascading Failure

## PgBouncer (pgbouncer.ini)

| Setting | Before | After | Reason |
|---------|--------|-------|--------|
| max_client_conn | 200 | 500 | Handle traffic spikes |
| default_pool_size | 20 | 40 | More concurrent queries |
| reserve_pool_size | 5 | 10 | Buffer for spikes |
| query_wait_timeout | 120 | 10 | Fail fast, prevent queue buildup |
| server_connect_timeout | 15 | 5 | Detect backend failure faster |

## PostgreSQL

| Setting | Before | After | Reason |
|---------|--------|-------|--------|
| max_connections | 100 | 150 | Accommodate larger PgBouncer pool |
| idle_in_transaction_session_timeout | (none) | 5min | Kill leaked transactions |
| statement_timeout | (none) | 60s | Prevent runaway queries |

## Application (recommendations)

| Change | Description |
|--------|-------------|
| Circuit breaker | Open after 5 failures, reset after 30s |
| Exponential backoff with jitter | Replace fixed 1s retry |
| Separate health check connection | Do not compete with user traffic |
| Load shedding at 2s latency | Return 503 instead of queuing |
| Retry budget | Max 10% of requests can be retries |
```

---

## Validation Checklist

- [ ] PgBouncer queue cleared (cl_waiting = 0)
- [ ] PostgreSQL has no stuck queries or lock contention
- [ ] Traffic re-enabled gradually (not all at once)
- [ ] PgBouncer config updated with fail-fast timeouts
- [ ] Application team notified about circuit breaker recommendation
- [ ] Health check separated from main connection pool
- [ ] Monitoring added for PgBouncer queue depth
- [ ] Post-incident config changes documented

---

## Lessons Learned

1. **Retries amplify failures.** Without circuit breakers, retry logic turns a partial failure into a total outage. 10 clients retrying 3 times each = 30x the original load.
2. **Fail fast, not slow.** Short timeouts (query_wait_timeout = 10s) are better during cascades than long queues (120s). Fast failure lets the system recover.
3. **Separate health check connections from user traffic.** If health checks compete for the same pool, the load balancer removes "unhealthy" instances, making things worse.
4. **Gradual restart prevents re-flooding.** After clearing the queue, bring traffic back at 20% -> 50% -> 100%, not all at once.
5. **Connection pools need headroom.** If your normal traffic uses 80% of the pool, a 2x spike overflows. Size pools for peak, not average.
6. **Cascades are system problems, not component problems.** The database was fine. PgBouncer was fine. The application was fine. It was the interaction between them under stress that failed.
