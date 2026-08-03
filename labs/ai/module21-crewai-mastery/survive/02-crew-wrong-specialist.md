# SURVIVE 02: The Wrong Specialist

## Scenario

You built a triage crew that routes database alerts to specialists. It worked great in testing. In production, you notice something alarming: the triage agent consistently routes alerts to the WRONG specialist.

- Performance issues (slow queries, high CPU) go to the Replication Specialist
- Replication issues (lag, WAL problems) go to the Security Specialist
- Storage issues (disk full, bloat) go to the Performance Specialist

The crew produces confident-sounding but completely wrong recommendations. A replication specialist told someone to "add an index" to fix replication lag. A security specialist recommended "increasing max_wal_senders" to fix a slow query.

**DBA analogy:** This is like having your monitoring system send Nagios alerts to the wrong PagerDuty escalation policy. The disk alerts page the network team, the network alerts page the DBA team. Everyone gets paged, nobody gets the right alert.

---

## The Broken Code

On your **Mac terminal**, examine the buggy crew:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# The triage agent has a vague, unhelpful backstory
triage = Agent(
    role='Alert Router',
    goal='Route alerts to agents',
    backstory='You route alerts to other agents.',    # BUG: too vague
    verbose=True
)

# BUG: Agent roles and backstories are generic and overlapping
specialist_a = Agent(
    role='Database Agent A',                          # BUG: generic role
    goal='Handle database issues',                     # BUG: generic goal
    backstory='You are a database specialist.',         # BUG: generic backstory
    verbose=True
)

specialist_b = Agent(
    role='Database Agent B',                          # BUG: generic role
    goal='Handle database issues',                     # BUG: same generic goal
    backstory='You are a database specialist.',         # BUG: same generic backstory
    verbose=True
)

specialist_c = Agent(
    role='Database Agent C',                          # BUG: generic role
    goal='Handle database issues',                     # BUG: same generic goal
    backstory='You are a database specialist.',         # BUG: same generic backstory
    verbose=True
)

# Three alerts to test routing
alerts = [
    'pg-primary: Top query doing seq scan on 500M row table. 45 second query time. No index on customer_id.',
    'pg-replica-2: Replication lag is 90 seconds. WAL receiver not keeping up. Replica disk I/O at 95%.',
    'pg-primary: /pgdata disk 98% full. pg_wal directory is 200GB. archive_command failing.',
]

for i, alert in enumerate(alerts, 1):
    # BUG: Task does not specify which specialist to use
    # The triage agent has to guess, and with generic agent names it guesses wrong
    task_triage = Task(
        description=f'Route this alert to the right specialist: {alert}',
        expected_output='Route decision.',
        agent=triage
    )

    task_handle = Task(
        description=f'Handle this alert: {alert}',
        expected_output='Resolution plan.',
        agent=specialist_a    # BUG: always goes to Agent A regardless of type
    )

    print(f'Alert {i}: {alert[:60]}...')
    print(f'  Routed to: {task_handle.agent.role}')
    print(f'  Problem: Agent A handles everything, regardless of alert type')
    print()

print('ROOT CAUSE: All specialists have identical roles/goals/backstories.')
print('The triage agent cannot distinguish between them.')
print('And the task always hardcodes agent=specialist_a.')
"
```

Expected output:
```
Alert 1: pg-primary: Top query doing seq scan on 500M row table. 45 s...
  Routed to: Database Agent A
  Problem: Agent A handles everything, regardless of alert type

Alert 2: pg-replica-2: Replication lag is 90 seconds. WAL receiver no...
  Routed to: Database Agent A
  Problem: Agent A handles everything, regardless of alert type

Alert 3: pg-primary: /pgdata disk 98% full. pg_wal directory is 200GB...
  Routed to: Database Agent A
  Problem: Agent A handles everything, regardless of alert type

ROOT CAUSE: All specialists have identical roles/goals/backstories.
The triage agent cannot distinguish between them.
And the task always hardcodes agent=specialist_a.
```

---

## Your Mission

Fix the crew so that:
1. The triage agent correctly classifies each alert
2. Each alert is routed to the appropriate specialist
3. Each specialist produces domain-specific recommendations (not generic advice)

**Rules:**
- You must use 3 specialist agents (performance, replication, storage)
- The triage agent must classify the alert before the specialist handles it
- The output for each alert must include domain-specific commands (not generic "check the database" advice)

---

## Diagnostic Steps

```bash
python3 -c "
print('Wrong Specialist Diagnosis')
print('=' * 40)
print()
print('Bug 1: Generic agent identities')
print('  All three specialists have role=\"Database Agent X\"')
print('  All have the same goal and backstory')
print('  The LLM cannot tell them apart')
print()
print('Bug 2: No routing logic')
print('  task_handle always uses specialist_a')
print('  The triage result is never used to pick an agent')
print()
print('Bug 3: Triage agent has no classification criteria')
print('  Backstory is just \"You route alerts to other agents\"')
print('  No categories, no routing rules, no examples')
print()
print('DBA analogy: This is like having three identical PagerDuty')
print('escalation policies with the same name and same team members.')
print('All alerts go to the first one alphabetically.')
print()
print('Fix needed:')
print('  1. Give each specialist a unique, descriptive role + backstory')
print('  2. Give the triage agent clear classification rules')
print('  3. Build routing logic that maps triage output to the right agent')
"
```

---

## Validation

After your fix, verify:

1. Performance alert -> Performance DBA (recommends CREATE INDEX, EXPLAIN, etc.)
2. Replication alert -> Replication DBA (recommends checking pg_stat_replication, WAL receiver, etc.)
3. Storage alert -> Storage DBA (recommends pg_wal cleanup, VACUUM, archive_command fix, etc.)

```bash
python3 -c "
print('Validation checklist:')
print()
print('Alert 1 (slow query, seq scan):')
print('  [ ] Routed to Performance DBA')
print('  [ ] Mentions CREATE INDEX or EXPLAIN')
print('  [ ] Does NOT mention replication or WAL')
print()
print('Alert 2 (replication lag):')
print('  [ ] Routed to Replication DBA')
print('  [ ] Mentions pg_stat_replication or WAL receiver')
print('  [ ] Does NOT mention indexing')
print()
print('Alert 3 (disk full, WAL bloat):')
print('  [ ] Routed to Storage DBA')
print('  [ ] Mentions archive_command or pg_wal cleanup')
print('  [ ] Does NOT mention query optimization')
"
```

---

<details>
<summary>Runbook (hints, not answers)</summary>

**Fix 1: Give agents distinct identities.**
Each specialist needs a unique `role`, `goal`, and `backstory` that clearly defines their domain. The LLM uses these to decide which agent is appropriate.

Example for Performance DBA:
- role: "Performance DBA"
- goal: "Diagnose and fix query performance issues"
- backstory: "Expert in EXPLAIN plans, indexes, sequential scans, query optimization, and pg_stat_statements"

**Fix 2: Give the triage agent classification rules.**
The triage agent's backstory should include explicit routing rules:
- "If the alert mentions slow queries, missing indexes, high CPU -> Performance"
- "If the alert mentions replication lag, WAL, replica -> Replication"
- "If the alert mentions disk, storage, bloat, archive -> Storage"

**Fix 3: Build a routing function.**
Instead of hardcoding `agent=specialist_a`, create a function:
```python
def route_alert(alert_text):
    keywords = {
        'performance': ['slow', 'query', 'index', 'scan', 'cpu'],
        'replication': ['replica', 'replication', 'lag', 'wal receiver'],
        'storage': ['disk', 'storage', 'bloat', 'archive', 'pg_wal'],
    }
    # Match keywords and return the right agent
```

**Fix 4: Or use separate tasks per specialist.**
Create 3 separate crews (one per alert type) instead of trying to route dynamically. This is the simplest fix and the most reliable. Like having separate runbooks for each incident type.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# FIX 1: Distinct, descriptive agent identities
triage = Agent(
    role='Alert Triage Lead',
    goal='Classify database alerts into categories: performance, replication, or storage',
    backstory='''You are an expert at rapid alert classification. Your routing rules:
    - Keywords: slow query, index, seq scan, CPU, EXPLAIN -> PERFORMANCE
    - Keywords: replication, lag, WAL receiver, replica, streaming -> REPLICATION
    - Keywords: disk, storage, bloat, archive, pg_wal, space -> STORAGE
    You ALWAYS classify into exactly one category.''',
    verbose=True
)

perf_dba = Agent(
    role='Performance DBA',
    goal='Diagnose and fix query performance issues with specific SQL commands',
    backstory='''Expert in PostgreSQL query optimization. Your toolkit:
    EXPLAIN ANALYZE, CREATE INDEX CONCURRENTLY, pg_stat_statements,
    pg_stat_user_tables, auto_explain. You fix slow queries and sequential scans.''',
    verbose=True
)

repl_dba = Agent(
    role='Replication DBA',
    goal='Diagnose and fix replication issues with specific commands',
    backstory='''Expert in PostgreSQL streaming replication. Your toolkit:
    pg_stat_replication, pg_stat_wal_receiver, pg_wal_lsn_diff(),
    pg_last_xact_replay_timestamp(). You fix lag and WAL issues.''',
    verbose=True
)

storage_dba = Agent(
    role='Storage DBA',
    goal='Diagnose and fix disk and storage issues with specific commands',
    backstory='''Expert in PostgreSQL storage management. Your toolkit:
    pg_total_relation_size(), VACUUM FULL, pg_wal directory management,
    archive_command troubleshooting, tablespace management. You fix disk issues.''',
    verbose=True
)

# FIX 2: Routing function based on keywords
def get_specialist(alert_text: str) -> Agent:
    alert_lower = alert_text.lower()
    if any(kw in alert_lower for kw in ['replication', 'replica', 'lag', 'wal receiver']):
        return repl_dba
    elif any(kw in alert_lower for kw in ['disk', 'storage', 'bloat', 'archive', 'pg_wal']):
        return storage_dba
    else:
        return perf_dba    # default to performance

alerts = [
    'pg-primary: Top query doing seq scan on 500M row table. 45 second query time. No index on customer_id.',
    'pg-replica-2: Replication lag is 90 seconds. WAL receiver not keeping up. Replica disk I/O at 95%.',
    'pg-primary: /pgdata disk 98% full. pg_wal directory is 200GB. archive_command failing.',
]

for i, alert in enumerate(alerts, 1):
    print(f'\\n{\"=\" * 50}')
    print(f'ALERT {i}: {alert[:70]}...')
    print(f'{\"=\" * 50}')

    # FIX 3: Triage classifies, then route to correct specialist
    specialist = get_specialist(alert)
    print(f'Routed to: {specialist.role}')

    task_triage = Task(
        description=f'Classify this alert: {alert}',
        expected_output='Category (performance/replication/storage) and severity.',
        agent=triage
    )

    task_handle = Task(
        description=f'''Handle this alert using your domain expertise: {alert}
        Provide specific PostgreSQL commands for diagnosis and remediation.''',
        expected_output='Domain-specific diagnosis and remediation with exact commands.',
        agent=specialist,    # FIXED: routed to the right specialist
        context=[task_triage]
    )

    crew = Crew(
        agents=[triage, specialist],
        tasks=[task_triage, task_handle],
        process=Process.sequential,
        verbose=True
    )

    result = crew.kickoff()
    print(f'\\nRESULT from {specialist.role}:')
    print(str(result)[:300])
    print()
"
```
</details>
