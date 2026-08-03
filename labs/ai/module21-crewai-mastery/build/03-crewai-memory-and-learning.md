# Build 03: CrewAI Memory and Learning

Imagine a DBA team where every incident is treated as brand new - nobody remembers that the same replication lag happened last Tuesday, was caused by a long-running analytics query, and was fixed by killing PID 12847. That team wastes time re-investigating known problems.

CrewAI memory fixes this. Agents can remember past incidents, build knowledge about your specific infrastructure, and learn from experience - just like a real DBA team does.

## DBA Analogy: Memory Types

| CrewAI Memory Type | DBA Equivalent |
|-------------------|----------------|
| **Short-term memory** | Your working memory during an incident - "I just checked pg_stat_activity and saw 200 blocked queries" |
| **Long-term memory** | Your incident log / runbook wiki - "Last time we saw this, the fix was X" |
| **Entity memory** | Your mental model of infrastructure - "pg-primary has 200 max connections, pg-analytics always spikes at 2am" |
| **Knowledge sources** | Runbooks, documentation, past post-mortems - reference material agents can search |

---

## Step 1. Short-term memory (within a single run)

Short-term memory is enabled by default. Within a single crew run, agents remember what they've already done and what other agents have output. This prevents agents from repeating themselves or contradicting each other.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Two agents that need to build on each other's work
checker = Agent(
    role='Health Checker',
    goal='Check database health and report findings',
    backstory='Methodical DBA who checks things in order and remembers what was already checked.',
    verbose=True
)

reporter = Agent(
    role='Report Writer',
    goal='Write a summary report based on all findings',
    backstory='Technical writer who synthesizes findings into clear reports.',
    verbose=True
)

task_check_conns = Task(
    description='Check connection utilization for pg-primary. It has 200 max connections, currently 185 active.',
    expected_output='Connection health assessment.',
    agent=checker
)

task_check_repl = Task(
    description='Check replication lag for pg-replica-1. Current lag is 3 seconds.',
    expected_output='Replication health assessment.',
    agent=checker
)

task_report = Task(
    description='Write a combined health report based on ALL previous findings. Include both connection and replication checks.',
    expected_output='Combined health report with all findings and overall status.',
    agent=reporter,
    context=[task_check_conns, task_check_repl]
)

crew = Crew(
    agents=[checker, reporter],
    tasks=[task_check_conns, task_check_repl, task_report],
    process=Process.sequential,
    memory=True,    # enable memory (short-term is always on, this also enables long-term)
    verbose=True
)

print('Memory enabled: short-term memory active within this run')
print('The reporter agent will see BOTH check results via context + memory')
print()
result = crew.kickoff()
print()
print('REPORT:')
print(result)
"
```

Expected output (yours will differ):
```
Memory enabled: short-term memory active within this run
The reporter agent will see BOTH check results via context + memory

 [INFO]: Working Agent: Health Checker
 [INFO]: Starting Task: Check connection utilization...
 ...
 [INFO]: Working Agent: Health Checker
 [INFO]: Starting Task: Check replication lag...
 ...
 [INFO]: Working Agent: Report Writer
 [INFO]: Starting Task: Write a combined health report...
 ...

REPORT:
## Database Health Report

### Connection Utilization - pg-primary
- Active: 185/200 (92.5%)
- Status: WARNING - approaching max connections
...

### Replication - pg-replica-1
- Lag: 3 seconds
- Status: OK
...
```

Short-term memory is like your working memory during an incident. The reporter agent "remembers" everything the checker found because it's stored in the crew's short-term memory for this run.

---

## Step 2. Long-term memory (persists across runs)

Long-term memory lets agents learn from past crew executions. When enabled, CrewAI stores task results in a local database. On the next run, agents can retrieve relevant past results.

**DBA analogy:** This is your team's incident wiki. When a new alert comes in, you search past incidents for similar patterns. "Oh, we saw this replication lag pattern on June 3rd - it was caused by a vacuum on the replica."

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
import os

# CrewAI stores long-term memory in a local SQLite database
# Default location: ./crewai_memory/ in your working directory

agent = Agent(
    role='Incident Responder',
    goal='Respond to database incidents using past experience',
    backstory='''Experienced DBA who learns from every incident.
    Always checks if a similar incident happened before and references
    past solutions when relevant.''',
    verbose=True
)

task = Task(
    description='''Respond to this alert:
    ALERT: pg-primary replication lag jumped to 30 seconds.
    Replica CPU is at 95%.

    Check your memory for similar past incidents before investigating.
    If you remember a similar incident, reference it.''',
    expected_output='Incident response plan, referencing past incidents if any.',
    agent=agent
)

crew = Crew(
    agents=[agent],
    tasks=[task],
    process=Process.sequential,
    memory=True,              # enables all memory types
    verbose=True
)

print('Long-term memory: ENABLED')
print('Memory storage: ./crewai_memory/ (SQLite)')
print()
print('Run 1: First time seeing this alert type')
print('The agent has no past incidents to reference yet.')
print()
result = crew.kickoff()
print()
print('RESPONSE:')
print(result)
print()
print('This response is now stored in long-term memory.')
print('Next time you run this crew with a similar alert,')
print('the agent will find this incident in memory and reference it.')
"
```

Expected output (yours will differ):
```
Long-term memory: ENABLED
Memory storage: ./crewai_memory/ (SQLite)

Run 1: First time seeing this alert type
The agent has no past incidents to reference yet.

 [INFO]: Working Agent: Incident Responder
 ...

RESPONSE:
## Incident Response - Replication Lag

No similar past incidents found in memory.

### Investigation Plan:
1. Check pg_stat_replication on primary...
...

This response is now stored in long-term memory.
Next time you run this crew with a similar alert,
the agent will find this incident in memory and reference it.
```

Now run it again with a similar alert and the agent will reference the first run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

agent = Agent(
    role='Incident Responder',
    goal='Respond to database incidents using past experience',
    backstory='''Experienced DBA who learns from every incident.
    Always checks if a similar incident happened before and references
    past solutions when relevant.''',
    verbose=True
)

task = Task(
    description='''Respond to this alert:
    ALERT: pg-analytics replication lag is 25 seconds.
    Replica CPU at 90%, disk I/O wait at 40%.

    Check your memory for similar past incidents.''',
    expected_output='Incident response referencing past similar incidents.',
    agent=agent
)

crew = Crew(
    agents=[agent],
    tasks=[task],
    process=Process.sequential,
    memory=True,
    verbose=True
)

print('Run 2: Similar alert - agent should reference past incident')
print()
result = crew.kickoff()
print()
print('RESPONSE:')
print(result)
"
```

Expected output (yours will differ):
```
Run 2: Similar alert - agent should reference past incident

 [INFO]: Working Agent: Incident Responder
 ...

RESPONSE:
## Incident Response - Replication Lag on pg-analytics

This is similar to a recent incident on pg-primary where replication lag
reached 30 seconds with high replica CPU. In that case, the root cause was...
...
```

The agent found the past incident in long-term memory and used it to inform its response. This is exactly how an experienced DBA team works - they build institutional knowledge over time.

---

## Step 3. Entity memory

Entity memory stores facts about specific entities - servers, databases, tables, applications. As agents encounter information about these entities, they remember it.

**DBA analogy:** This is the mental model every experienced DBA has. "pg-primary has 200 max_connections, runs on r6g.4xlarge, hosts the orders and users tables. The analytics ETL job runs at 2am and causes replication lag."

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Agent that builds entity knowledge over time
dba = Agent(
    role='Fleet DBA',
    goal='Monitor and maintain the entire database fleet',
    backstory='''You manage 15 PostgreSQL clusters. You remember specifics
    about each server: its role, capacity, quirks, and history.
    When checking a server, you recall what you know about it.''',
    verbose=True
)

# First run: teach the agent about your infrastructure
task_learn = Task(
    description='''Record these facts about the database fleet:

    pg-primary-1: Primary server, r6g.4xlarge, 200 max_connections,
    hosts orders+users+inventory tables. Peak hours: 9am-5pm EST.

    pg-analytics-1: Analytics replica, r6g.8xlarge, 500 max_connections,
    receives streaming replication from pg-primary-1.
    ETL job runs daily at 2am, causes temporary lag spikes.

    pg-replica-1: Read replica for web traffic, r6g.2xlarge,
    100 max_connections. Serves dashboard queries.

    Summarize what you know about each server.''',
    expected_output='Summary of known facts about each database server.',
    agent=dba
)

crew = Crew(
    agents=[dba],
    tasks=[task_learn],
    process=Process.sequential,
    memory=True,              # entity memory stores these facts
    verbose=True
)

print('Teaching the agent about your infrastructure...')
print('Entity memory will store facts about each server.')
print()
result = crew.kickoff()
print()
print('FLEET KNOWLEDGE:')
print(result)
"
```

Expected output (yours will differ):
```
Teaching the agent about your infrastructure...
Entity memory will store facts about each server.

 [INFO]: Working Agent: Fleet DBA
 ...

FLEET KNOWLEDGE:
## Database Fleet Summary

### pg-primary-1
- Role: Primary
- Instance: r6g.4xlarge
- Max connections: 200
- Tables: orders, users, inventory
- Peak hours: 9am-5pm EST
...
```

On subsequent runs, when the agent encounters "pg-primary-1" in an alert, entity memory retrieves everything it knows about that server - its role, capacity, peak hours, and past incidents.

---

## Step 4. Knowledge sources

Knowledge sources let you feed agents with reference material - runbooks, documentation, past incident reports. Instead of putting everything in the backstory (which has token limits), you give agents searchable documents.

**DBA analogy:** This is the difference between a DBA who "just knows things" and a DBA who has a well-organized Confluence wiki they can search. The wiki DBA is more reliable because they reference actual documentation.

On your **Mac terminal**, create a knowledge file first:

```bash
mkdir -p /tmp/dba_knowledge
```

```bash
cat > /tmp/dba_knowledge/replication_runbook.txt << 'EOF'
RUNBOOK: Replication Lag Troubleshooting

STEP 1: Check current lag
  SQL: SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       (sent_lsn - replay_lsn) AS byte_lag
       FROM pg_stat_replication;

STEP 2: Check replica apply rate
  SQL: SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;

STEP 3: Common causes
  - Replica CPU maxed out (check for competing workloads)
  - Replica disk I/O saturated (check iostat)
  - Large transaction on primary generating massive WAL
  - Network issue between primary and replica
  - recovery_min_apply_delay is set (intentional delay)

STEP 4: Quick fixes
  - Kill competing queries on replica: SELECT pg_terminate_backend(pid)
  - Increase max_parallel_workers_per_gather on replica
  - If caused by vacuum: wait for it to finish or reduce vacuum cost limit

STEP 5: Escalation
  - If lag exceeds 5 minutes: page the replication specialist
  - If lag exceeds 15 minutes: consider promoting another replica
  - If all replicas are lagging: investigate primary WAL generation rate
EOF
```

Now use it as a knowledge source:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.knowledge.source.text_file_knowledge_source import TextFileKnowledgeSource

# Load runbook as a knowledge source
# CrewAI looks for knowledge files relative to a 'knowledge/' directory.
# Create it in the current working directory:
import os
os.makedirs('knowledge', exist_ok=True)

# Copy the runbook to the knowledge directory
import shutil
shutil.copy('/tmp/dba_knowledge/replication_runbook.txt', 'knowledge/replication_runbook.txt')

repl_knowledge = TextFileKnowledgeSource(
    file_paths=['replication_runbook.txt']
)

agent = Agent(
    role='On-Call DBA',
    goal='Respond to alerts using documented runbooks',
    backstory='Follows runbooks precisely. Always references documentation before acting.',
    verbose=True
)

task = Task(
    description='''Alert: pg-replica-2 replication lag is 8 minutes and climbing.
    Use the replication runbook to respond. Follow the documented steps exactly.''',
    expected_output='Step-by-step response following the runbook, with specific SQL commands.',
    agent=agent
)

crew = Crew(
    agents=[agent],
    tasks=[task],
    process=Process.sequential,
    memory=True,
    knowledge_sources=[repl_knowledge],    # make runbook available to all agents
    verbose=True
)

print('Knowledge source loaded: replication_runbook.txt')
print('The agent can search this document when responding.')
print()
result = crew.kickoff()
print()
print('RESPONSE:')
print(result)
"
```

Expected output (yours will differ):
```
Knowledge source loaded: replication_runbook.txt
The agent can search this document when responding.

 [INFO]: Working Agent: On-Call DBA
 [INFO]: Starting Task: Alert: pg-replica-2...
 ...

RESPONSE:
Following the Replication Lag Troubleshooting runbook:

Step 1: Check current lag
  Running: SELECT client_addr, state, sent_lsn, ...
  FROM pg_stat_replication;

Step 2: Check replica apply rate
  Running: SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;
...

Step 5: Escalation
  Lag exceeds 5 minutes - paging replication specialist.
```

The agent found the runbook via knowledge sources and followed it step by step, including the escalation rule (lag > 5 minutes = page specialist).

---

## Step 5. Build a crew that learns from resolved incidents

This is the full pattern: a crew that handles incidents AND stores what it learned for future use.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
import json
import os

# --- Simulated incident database ---
INCIDENT_DB = '/tmp/dba_incidents.json'

def load_past_incidents() -> str:
    '''Load resolved incidents from our incident database.'''
    if not os.path.exists(INCIDENT_DB):
        return 'No past incidents recorded.'
    with open(INCIDENT_DB, 'r') as f:
        incidents = json.load(f)
    if not incidents:
        return 'No past incidents recorded.'
    summary = 'Past Resolved Incidents:\\n'
    for inc in incidents[-5:]:    # last 5 incidents
        summary += f\"\"\"
  [{inc['date']}] {inc['alert']}
    Root cause: {inc['root_cause']}
    Fix: {inc['fix']}
    Time to resolve: {inc['ttr']}
\"\"\"
    return summary

def save_incident(alert: str, root_cause: str, fix: str, ttr: str) -> None:
    '''Save a resolved incident for future reference.'''
    incidents = []
    if os.path.exists(INCIDENT_DB):
        with open(INCIDENT_DB, 'r') as f:
            incidents = json.load(f)
    incidents.append({
        'date': '2026-06-15',
        'alert': alert,
        'root_cause': root_cause,
        'fix': fix,
        'ttr': ttr,
    })
    with open(INCIDENT_DB, 'w') as f:
        json.dump(incidents, f, indent=2)

# Seed with some past incidents
save_incident(
    alert='pg-primary replication lag 30s',
    root_cause='Long-running analytics query on replica consuming all CPU',
    fix='pg_terminate_backend() on the analytics query, then set statement_timeout=300000 for analytics role',
    ttr='8 minutes'
)
save_incident(
    alert='pg-analytics connection pool exhausted',
    root_cause='ETL job opening 150 connections without pooling',
    fix='Added PgBouncer in front of analytics DB, set pool_size=50',
    ttr='25 minutes'
)

# Load past incidents for the agent's context
past = load_past_incidents()

# --- Agents ---
responder = Agent(
    role='Incident Responder',
    goal='Resolve database incidents quickly by leveraging past experience',
    backstory=f'''Experienced DBA who always checks past incidents before
    investigating. You have access to the team incident database.

    PAST INCIDENTS:
    {past}''',
    verbose=True
)

# --- Task ---
task = Task(
    description='''New Alert: pg-replica-3 replication lag is 45 seconds.
    Replica CPU: 98%. A long-running query from the analytics role is
    consuming all resources on the replica.

    1. Check past incidents for similar patterns
    2. If you find a match, reference it
    3. Provide your response plan
    4. Note what you learned for next time''',
    expected_output='Incident response referencing past incidents, with resolution steps.',
    agent=responder
)

crew = Crew(
    agents=[responder],
    tasks=[task],
    process=Process.sequential,
    memory=True,
    verbose=True
)

print('Past incidents loaded into agent backstory:')
print(past)
print()
print('New alert: replication lag on pg-replica-3')
print()
result = crew.kickoff()

# Save this incident too
save_incident(
    alert='pg-replica-3 replication lag 45s',
    root_cause='Long-running analytics query on replica (same pattern as June 15)',
    fix='pg_terminate_backend(), added statement_timeout for analytics role on replica-3',
    ttr='5 minutes (faster because we recognized the pattern)'
)

print()
print('RESPONSE:')
print(result)
print()
print('Incident saved to database. Next run will see 3 past incidents.')
"
```

Expected output (yours will differ):
```
Past incidents loaded into agent backstory:

  [2026-06-15] pg-primary replication lag 30s
    Root cause: Long-running analytics query on replica consuming all CPU
    Fix: pg_terminate_backend() on the analytics query, then set statement_timeout...
    Time to resolve: 8 minutes

  [2026-06-15] pg-analytics connection pool exhausted
    Root cause: ETL job opening 150 connections without pooling
    Fix: Added PgBouncer in front of analytics DB...
    Time to resolve: 25 minutes

New alert: replication lag on pg-replica-3

 [INFO]: Working Agent: Incident Responder
 ...

RESPONSE:
## Incident Response - pg-replica-3 Replication Lag

### Pattern Match Found
This matches a previous incident (pg-primary replication lag 30s) where a
long-running analytics query consumed all replica CPU. That incident was
resolved in 8 minutes using pg_terminate_backend().

### Resolution Plan (based on past experience):
1. Identify the analytics query: SELECT pid, query, state, now() - query_start ...
2. Terminate it: SELECT pg_terminate_backend(<pid>);
3. Prevent recurrence: ALTER ROLE analytics SET statement_timeout = '300000';
...

Incident saved to database. Next run will see 3 past incidents.
```

Notice the time-to-resolve improved from 8 minutes to 5 minutes because the agent recognized the pattern. This is exactly how real DBA teams get faster over time - institutional knowledge.

---

## Step 6. Memory architecture summary

Here's how all the memory types work together:

```
                    CrewAI Memory Architecture
                    ========================

  Short-term Memory          Long-term Memory         Entity Memory
  (within one run)           (across runs)            (facts about things)
  +-----------------+       +------------------+      +------------------+
  | Task 1 output   |       | Run 1 results    |      | pg-primary:      |
  | Task 2 output   |       | Run 2 results    |      |   200 max_conn   |
  | Agent reasoning |       | Run 3 results    |      |   r6g.4xlarge    |
  | Tool results    |       | ...              |      | pg-replica-1:    |
  +-----------------+       +------------------+      |   100 max_conn   |
        |                          |                  +------------------+
        |                          |                         |
        +----------+---------------+-------------------------+
                   |
           +-------v--------+
           |  Knowledge     |
           |  Sources       |
           |  (runbooks,    |
           |   docs, past   |
           |   post-mortems)|
           +----------------+
```

**DBA analogy for the full stack:**

| Memory Type | DBA Equivalent | PostgreSQL Equivalent |
|------------|---------------|----------------------|
| Short-term | Working memory during an incident | `work_mem` - temporary per-query storage |
| Long-term | Team incident wiki / knowledge base | `pg_stat_statements` - persists across restarts |
| Entity | Mental model of your infrastructure | `pg_catalog` - metadata about your objects |
| Knowledge sources | Runbooks on Confluence | `pg_description` - documentation attached to objects |

---

## What You Built

In this guide you:
- Enabled **short-term memory** so agents share information within a run
- Used **long-term memory** so agents learn from past executions
- Built **entity memory** to store facts about specific servers and databases
- Connected **knowledge sources** so agents reference your runbooks
- Created a crew that **recognizes patterns** from past incidents and responds faster

**DBA translation:** You turned your AI crew from a team of strangers who start fresh every shift into a team that has institutional memory, knows your infrastructure, follows your runbooks, and gets faster at resolving recurring issues.

## Next Steps

In Build 04, you'll take this to production: error handling, rate limiting, cost control, testing strategies, and integration with external systems like Slack and PagerDuty.
