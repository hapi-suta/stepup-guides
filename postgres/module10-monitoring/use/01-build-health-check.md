# Use Exercise 01 - Build a Health Check Script

Write a bash script that checks 5 vital signs and exits with the appropriate exit code so it can be used in automated monitoring.

**Run on:** NODE1

---

## Your Mission

A health check script is the simplest form of monitoring: run it, get a pass or fail, and act on the result. Many monitoring systems (nagios, AWS CloudWatch custom checks, cron alerting) rely on scripts that return:

- Exit code `0` = healthy
- Exit code `1` = warning
- Exit code `2` = critical

Your script must check these 5 vital signs:

1. PostgreSQL is accepting connections
2. Connection count is below 80% of `max_connections`
3. Cache hit ratio is above 95%
4. No queries have been running longer than 10 minutes
5. No sessions are in `idle in transaction` state for more than 5 minutes

---

## Instructions

SSH into NODE1 and switch to the postgres user.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

```
sudo -iu postgres
```

Create your script at `/opt/pgsql/health_check.sh`.

```
vi /opt/pgsql/health_check.sh
```

Your script must:

- Use `/usr/pgsql-16/bin/psql -p 5432 -d stepup_store` to query PostgreSQL
- Print a status line for each check (PASS / WARN / CRIT)
- Exit with code `2` if any check is CRITICAL
- Exit with code `1` if any check is WARNING (and none are critical)
- Exit with code `0` if all checks pass
- Print a final summary line showing how many checks passed

---

## Reference

Use these queries as the basis for each check. You built most of these in Guide 05.

**Check 1 - pg_isready:**

```
/usr/pgsql-16/bin/pg_isready -p 5432
```

**Check 2 - Connection percentage:**

```sql
SELECT round(count(*) * 100.0 / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections'), 1)
FROM pg_stat_activity;
```

**Check 3 - Cache hit ratio:**

```sql
SELECT round(blks_hit * 100.0 / nullif(blks_hit + blks_read, 0), 2)
FROM pg_stat_database WHERE datname = 'stepup_store';
```

**Check 4 - Queries over 10 minutes:**

```sql
SELECT count(*) FROM pg_stat_activity
WHERE state != 'idle'
  AND query_start IS NOT NULL
  AND now() - query_start > interval '10 minutes';
```

**Check 5 - Idle-in-transaction over 5 minutes:**

```sql
SELECT count(*) FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '5 minutes';
```

---

## Test Your Script

Make it executable.

```
chmod +x /opt/pgsql/health_check.sh
```

Run it.

```
/opt/pgsql/health_check.sh
```

Expected output (yours will differ):

```
[PASS] PostgreSQL is accepting connections
[PASS] Connection count: 5.0% of max
[PASS] Cache hit ratio: 99.86%
[PASS] Long-running queries: 0 over 10 minutes
[PASS] Idle-in-transaction: 0 over 5 minutes

Summary: 5/5 checks passed
```

Check the exit code.

```
echo $?
```

Expected output (when all pass):

```
0
```

---

## Trigger a Warning

To verify your WARNING exit code works, temporarily lower the threshold for long-running queries to 0 seconds in your script (any running query will trigger it), run the script while a query is executing, then restore the threshold.

---

## Checkpoint

- [ ] Script checks all 5 vital signs
- [ ] Prints PASS / WARN / CRIT per check
- [ ] Exits with code 2 for critical, 1 for warning, 0 for all pass
- [ ] Prints a summary count at the end

---

Proceed to: [Use Exercise 02 - Slow Query Investigation](./02-slow-query-investigation.md)
