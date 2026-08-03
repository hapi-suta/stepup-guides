# Module 10 - Use Exercise 04: Operations Runbook

**Objective:** Write a complete operations runbook for the Aurora stack. Cover the 8 most common incidents an on-call engineer will face, with step-by-step triage, diagnosis, and resolution procedures.
**Time:** 40 minutes
**Level:** Senior / Staff

---

## Context

You are handing this Aurora stack to an operations team. The on-call engineer may not have built the stack and may not be a PostgreSQL expert. The runbook must be clear enough for someone at 3 AM with limited context to follow successfully.

---

## Exercise

Write a complete operations runbook covering the following 8 incidents. For each incident, include:
- **Detection:** How the incident is discovered (alarm, user report, monitoring)
- **Impact:** What is affected (reads, writes, all access)
- **Triage:** First 5 minutes - determine severity
- **Diagnosis:** Commands to identify root cause
- **Resolution:** Step-by-step fix
- **Escalation:** When to escalate and to whom
- **Post-incident:** What to document

<details>
<summary>Incident 1: High CPU Utilization (click to expand)</summary>

### Detection
CloudWatch alarm `devops-lab-aurora-cpu-high` triggers (CPU > 80% for 5 minutes).

### Impact
Query performance degrades. Response times increase. Application may time out.

### Triage (first 5 minutes)

**Step 1:** Check current CPU:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-w1 \
  --start-time $(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 60 \
  --statistics Average,Maximum \
  --output table
```

**Step 2:** Check if this is writer, reader, or both:

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table
```

### Diagnosis

**Step 3:** Open Performance Insights in the AWS Console. Navigate to RDS > Performance Insights > select the affected instance. Look at the "Database load" chart:
- If load is dominated by CPU waits: a query is consuming all CPU
- If load shows lock waits: blocking, not CPU

**Step 4:** Find the top CPU-consuming queries:

```sql
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

**Step 5:** Check for long-running queries:

```sql
SELECT pid, usename, state, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE state = 'active' AND query NOT LIKE '%pg_stat%'
ORDER BY duration DESC;
```

### Resolution

- If a single runaway query: terminate it with `SELECT pg_terminate_backend(PID);`
- If a new deployment introduced an expensive query: roll back the deployment
- If organic growth: scale up the instance class or optimize the query

### Escalation

Escalate to the DBA team if CPU remains above 90% for more than 15 minutes after initial triage.

</details>

<details>
<summary>Incident 2: Connection Exhaustion (click to expand)</summary>

### Detection
CloudWatch alarm `devops-lab-aurora-connections-high` triggers. Application reports "too many connections" errors.

### Impact
New connections are rejected. Application returns 500 errors.

### Triage (first 5 minutes)

**Step 1:** Check current connection count:

```sql
SELECT count(*) FROM pg_stat_activity;
```

**Step 2:** Check max_connections:

```sql
SHOW max_connections;
```

**Step 3:** Find connection sources:

```sql
SELECT usename, client_addr, state, count(*)
FROM pg_stat_activity
GROUP BY usename, client_addr, state
ORDER BY count DESC;
```

### Diagnosis

**Step 4:** Check for idle connections (connection pool leak):

```sql
SELECT usename, state, count(*)
FROM pg_stat_activity
GROUP BY usename, state
ORDER BY count DESC;
```

If `idle` connections dominate, the application is not returning connections to the pool.

**Step 5:** Check for idle-in-transaction (holding locks):

```sql
SELECT pid, usename, state, now() - state_change AS idle_duration
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_duration DESC;
```

### Resolution

- Terminate idle-in-transaction sessions older than 5 minutes:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND state_change < now() - interval '5 minutes';
```

- Long-term: deploy RDS Proxy or PgBouncer for connection pooling
- Verify `idle_in_transaction_session_timeout` is set in the parameter group

### Escalation

Escalate to the application team if connections are from a specific service (they need to fix their connection pool settings).

</details>

<details>
<summary>Incident 3: Replica Lag Spike (click to expand)</summary>

### Detection
CloudWatch alarm `devops-lab-aurora-replica-lag-high` triggers (lag > 30 seconds).

### Impact
Read queries on the reader endpoint return stale data.

### Triage (first 5 minutes)

**Step 1:** Check current replica lag:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-r1 \
  --start-time $(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 60 \
  --statistics Maximum \
  --output table
```

**Step 2:** Check writer CPU and I/O:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-w1 \
  --start-time $(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 60 \
  --statistics Average \
  --output table
```

### Diagnosis

Common causes:
- Heavy write load on the writer overwhelming replication
- Long-running query on the reader blocking replay
- Reader instance undersized compared to writer

**Step 3:** Check for long-running queries on the reader:

Connect to the reader endpoint and run:

```sql
SELECT pid, usename, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

### Resolution

- If a long reader query is blocking replay: terminate it
- If heavy write load: this is normal behavior, lag will recover when writes decrease
- If consistent lag: scale up the reader instance class

### Escalation

Escalate to the DBA team if lag exceeds 60 seconds for more than 15 minutes.

</details>

<details>
<summary>Incident 4: Failover Event (click to expand)</summary>

### Detection
RDS event notification: "Completed failover." Application reports brief connection errors.

### Impact
30-60 seconds of write unavailability during failover. Reads may also be briefly affected.

### Triage (first 5 minutes)

**Step 1:** Confirm the failover:

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 30 \
  --query 'Events[*].[Date,Message]' --output table
```

**Step 2:** Identify the new writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].[DBInstanceIdentifier,IsClusterWriter]' --output table
```

### Diagnosis

**Step 3:** Determine the cause:
- Planned: maintenance window, manual failover
- Unplanned: instance crash, AZ issue, storage failure

Check instance events:

```bash
aws rds describe-events \
  --source-type db-instance \
  --duration 30 \
  --query 'Events[?contains(Message, `failover`) || contains(Message, `reboot`)].[SourceIdentifier,Date,Message]' --output table
```

### Resolution

- Verify the cluster endpoint resolves to the new writer
- Verify the application reconnected (check application logs)
- Verify all alarms returned to OK

**No manual action needed for planned failovers.** Aurora handles promotion automatically.

### Post-incident

Document: failover time, cause, duration of impact, whether application retry logic worked correctly.

</details>

<details>
<summary>Incident 5: Storage Growth Alert (click to expand)</summary>

### Detection
Custom alarm for VolumeBytesUsed crossing a threshold, or manual capacity review.

### Triage

**Step 1:** Check current storage:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 86400 \
  --statistics Maximum \
  --output table
```

### Diagnosis

**Step 2:** Find the largest tables:

```sql
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 20;
```

**Step 3:** Check for table bloat:

```sql
SELECT schemaname, tablename, n_dead_tup, n_live_tup,
  round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC;
```

### Resolution

- If bloat: check autovacuum is running, consider manual VACUUM on large tables
- If legitimate growth: verify storage cost estimate, consider archiving old data
- Aurora auto-scales storage - no action needed for allocation

</details>

<details>
<summary>Incident 6: Deadlock Detected (click to expand)</summary>

### Detection
CloudWatch alarm `devops-lab-aurora-deadlocks` triggers. Log metric filter matched "deadlock detected."

### Triage

**Step 1:** Check PostgreSQL logs for the deadlock detail:

```bash
aws logs filter-log-events \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-pattern "deadlock detected" \
  --start-time $(date -u -v-1H +%s000) \
  --limit 5 \
  --query 'events[*].message' --output text
```

### Diagnosis

The deadlock log message includes which processes were involved and which locks they held. Look for:
- Which tables are involved
- Which queries caused the deadlock
- Whether this is a recurring pattern or a one-time event

### Resolution

- A single deadlock: no action needed, PostgreSQL automatically resolved it by killing one transaction
- Recurring deadlocks: review application code for transaction ordering issues
- Fix: ensure all transactions access tables in the same order

### Escalation

Escalate to the application team with the deadlock detail log. They need to fix the transaction ordering.

</details>

<details>
<summary>Incident 7: Authentication Failures (click to expand)</summary>

### Detection
CloudWatch alarm `devops-lab-aurora-auth-failures` triggers (5+ failures in 5 minutes).

### Triage

**Step 1:** Check the logs:

```bash
aws logs filter-log-events \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-pattern "authentication failed" \
  --start-time $(date -u -v-1H +%s000) \
  --limit 10 \
  --query 'events[*].message' --output text
```

### Diagnosis

Look for:
- Which user is failing (application user or admin?)
- Which source IP is attempting authentication
- Whether it is a legitimate application misconfiguration or a brute-force attack

### Resolution

- If application misconfiguration: check Secrets Manager for the current password, update the application config
- If brute-force attempt: tighten the security group rules, consider blocking the source IP
- If password expired: reset the password in Secrets Manager

### Escalation

If the source IP is unknown and attempts are increasing, escalate to the security team immediately as a potential intrusion attempt.

</details>

<details>
<summary>Incident 8: Backup Failure (click to expand)</summary>

### Detection
RDS event: backup failed. Or manual check reveals missing automated snapshots.

### Triage

**Step 1:** Check recent backup events:

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 1440 \
  --query 'Events[?contains(Message, `backup`)].[Date,Message]' --output table
```

**Step 2:** Check the latest automated snapshot:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type automated \
  --query 'DBClusterSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]' --output table
```

### Diagnosis

Common causes:
- Storage issue preventing snapshot
- Insufficient IAM permissions (rare)
- Cluster in a state that prevents backup (modifying, failing-over)

### Resolution

- Take a manual snapshot to verify backup capability:

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-snapshot-identifier manual-backup-verification-$(date +%Y%m%d)
```

- If manual snapshot fails, check RDS events for error details
- If automated backups are not being created, verify backup retention period > 0

### Escalation

Escalate to the DBA team immediately. A cluster without backups is a data loss risk.

</details>

---

## Deliverable

Write the complete runbook in a format your team uses (Confluence, Notion, markdown in a git repo). Include:

1. **Table of contents** - Quick navigation to each incident
2. **Contact list** - DBA team, application team, security team contacts
3. **Severity definitions** - P1 (all users affected), P2 (degraded), P3 (minor), P4 (cosmetic)
4. **Incident templates** - For each of the 8 incidents above
5. **General procedures** - How to connect to the database, where to find credentials, how to access CloudWatch

---

## Summary

An operations runbook is a living document. Update it after every incident with lessons learned. The best runbooks are written by the people who built the system and refined by the people who operate it.
