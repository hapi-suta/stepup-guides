# Build 02: Advanced Crews

You built a basic crew in Build 01. Now you'll learn patterns that make crews production-ready: task dependencies, delegation, custom tools, callbacks, and full incident response pipelines.

## DBA Analogy: Advanced Runbooks

| Basic Crew | Advanced Crew |
|-----------|--------------|
| Linear runbook (step 1, 2, 3) | Dynamic runbook with branching and delegation |
| Each person works alone | Agents can ask other agents for help |
| No tools besides their brain | Agents have access to psql, logs, metrics |
| No logging | Every action is logged with timestamps |
| Like a simple SQL script | Like a stored procedure with error handling and dynamic SQL |

---

## Step 1. Task dependencies with context

In Build 01, tasks ran in order and the output of each task was automatically passed to the next. But you can be explicit about which tasks feed into which using `context`.

**DBA analogy:** This is like a CTE chain where each CTE references specific previous CTEs, not just the one before it.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Create agents
triage = Agent(
    role='Triage Lead',
    goal='Classify database alerts by severity and type',
    backstory='Senior DBA who triages alerts instantly.',
    verbose=True
)

perf_dba = Agent(
    role='Performance DBA',
    goal='Diagnose slow query and performance issues',
    backstory='Expert in EXPLAIN plans, indexes, and pg_stat_statements.',
    verbose=True
)

remediation = Agent(
    role='Remediation DBA',
    goal='Create safe, tested remediation plans',
    backstory='Expert in making changes safely with rollback plans.',
    verbose=True
)

# Task 1: Triage
task_triage = Task(
    description='''Triage this alert:
    ALERT: Query on pg-analytics taking 340 seconds.
    Table: orders (450M rows). No index on customer_id.
    CPU: 88%. Active connections: 180/200.
    Classify severity and type.''',
    expected_output='Severity (P1-P4), category, and summary.',
    agent=triage
)

# Task 2: Diagnose - depends on triage output
task_diagnose = Task(
    description='''Given the triage report, diagnose the root cause.
    Analyze the query pattern, missing indexes, table statistics,
    and connection pool pressure.''',
    expected_output='Root cause analysis with specific findings.',
    agent=perf_dba,
    context=[task_triage]    # explicitly depends on triage output
)

# Task 3: Fix - depends on BOTH triage and diagnosis
task_fix = Task(
    description='''Create a remediation plan based on the triage severity
    and diagnosis findings. Include: exact SQL commands, rollback plan,
    verification steps, and estimated time to fix.''',
    expected_output='Step-by-step remediation with commands and rollback plan.',
    agent=remediation,
    context=[task_triage, task_diagnose]    # gets output from BOTH previous tasks
)

crew = Crew(
    agents=[triage, perf_dba, remediation],
    tasks=[task_triage, task_diagnose, task_fix],
    process=Process.sequential,
    verbose=True
)

print('Task dependency chain:')
print(f'  task_triage -> task_diagnose (context: triage)')
print(f'  task_triage + task_diagnose -> task_fix (context: triage, diagnose)')
print()
print('Kicking off...')
result = crew.kickoff()
print()
print('REMEDIATION PLAN:')
print(result)
"
```

Expected output (yours will differ):
```
Task dependency chain:
  task_triage -> task_diagnose (context: triage)
  task_triage + task_diagnose -> task_fix (context: triage, diagnose)

Kicking off...
 [INFO]: Working Agent: Triage Lead
 ...
 [INFO]: Working Agent: Performance DBA
 ...
 [INFO]: Working Agent: Remediation DBA
 ...

REMEDIATION PLAN:
## Remediation Plan - P1 Performance Issue

1. Immediate: Create index
   CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
...
```

The `context` parameter is the key here. Without it, each task only sees the output of the task immediately before it. With `context=[task_triage, task_diagnose]`, the remediation agent sees both the severity classification AND the detailed diagnosis.

---

## Step 2. Delegation between agents

When you set `allow_delegation=True`, an agent can say "I need help from another agent" and pass work to them. This is like a DBA saying "this is a replication issue, let me hand it to our replication specialist."

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Manager agent that CAN delegate
manager = Agent(
    role='DBA Team Lead',
    goal='Coordinate incident response and delegate to specialists',
    backstory='''You lead a team of specialist DBAs. You assess incoming
    incidents and delegate investigation to the right specialist.
    You do NOT investigate yourself - you coordinate.''',
    allow_delegation=True,    # can hand tasks to other agents
    verbose=True
)

# Specialists that do the actual work
perf_dba = Agent(
    role='Performance DBA',
    goal='Diagnose and fix performance issues',
    backstory='Expert in query plans, indexes, vacuum, and connection pools.',
    allow_delegation=False,    # does their own work, no delegation
    verbose=True
)

repl_dba = Agent(
    role='Replication DBA',
    goal='Diagnose and fix replication issues',
    backstory='Expert in streaming replication, WAL, and failover.',
    allow_delegation=False,
    verbose=True
)

investigate_task = Task(
    description='''A P1 alert came in: primary database pg-main has 200 blocked
    queries behind a single long-running transaction. The transaction has been
    open for 45 minutes. Active connections: 195/200.

    Investigate and provide remediation steps.''',
    expected_output='Investigation findings and remediation steps with exact commands.',
    agent=manager    # manager receives it, but may delegate
)

crew = Crew(
    agents=[manager, perf_dba, repl_dba],
    tasks=[investigate_task],
    process=Process.sequential,
    verbose=True
)

print('Manager has allow_delegation=True')
print('Manager may delegate to Performance DBA or Replication DBA')
print()
result = crew.kickoff()
print(result)
"
```

Expected output (yours will differ):
```
Manager has allow_delegation=True
Manager may delegate to Performance DBA or Replication DBA

 [INFO]: Working Agent: DBA Team Lead
 [INFO]: Starting Task: A P1 alert came in...

 [INFO]: DBA Team Lead delegated task to Performance DBA
 ...
```

The manager agent will decide which specialist is most appropriate. Since this is a blocking query issue (performance), it should delegate to the Performance DBA. The LLM makes this decision based on each agent's role and backstory.

---

## Step 3. Custom tools for agents

Tools give agents the ability to DO things - not just think about them. CrewAI uses the `@tool` decorator to create tools that agents can call.

**DBA analogy:** Without tools, an agent is a DBA who can think about the problem but has no `psql` terminal. With tools, they can actually run queries.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.tools import tool

# Create a custom tool - like giving an agent access to psql
@tool('Check PostgreSQL Connections')
def check_connections(database_name: str) -> str:
    '''Check active connections for a PostgreSQL database.
    Returns connection count and status breakdown.'''
    # In production, this would run an actual query via psycopg2
    # For this demo, we simulate the response
    simulated_data = {
        'pg-primary': {'active': 145, 'idle': 30, 'idle_in_transaction': 15, 'max': 200},
        'pg-analytics': {'active': 45, 'idle': 100, 'idle_in_transaction': 5, 'max': 200},
        'pg-replica-1': {'active': 80, 'idle': 50, 'idle_in_transaction': 2, 'max': 200},
    }
    data = simulated_data.get(database_name, {'active': 0, 'idle': 0, 'idle_in_transaction': 0, 'max': 200})
    total = data['active'] + data['idle'] + data['idle_in_transaction']
    utilization = (total / data['max']) * 100
    return f'''Connection Report for {database_name}:
  Active: {data['active']}
  Idle: {data['idle']}
  Idle in Transaction: {data['idle_in_transaction']}
  Total: {total}/{data['max']} ({utilization:.0f}% utilized)
  Status: {\"CRITICAL\" if utilization > 90 else \"WARNING\" if utilization > 75 else \"OK\"}'''

@tool('Check Replication Lag')
def check_replication_lag(replica_name: str) -> str:
    '''Check replication lag for a specific replica.
    Returns lag in seconds and bytes.'''
    simulated_lag = {
        'pg-replica-1': {'seconds': 2, 'bytes': 1048576},
        'pg-replica-2': {'seconds': 45, 'bytes': 52428800},
    }
    lag = simulated_lag.get(replica_name, {'seconds': 0, 'bytes': 0})
    status = 'CRITICAL' if lag['seconds'] > 30 else 'WARNING' if lag['seconds'] > 10 else 'OK'
    return f'''Replication Lag for {replica_name}:
  Time lag: {lag['seconds']} seconds
  Byte lag: {lag['bytes']:,} bytes
  Status: {status}'''

# Create an agent WITH tools
dba_agent = Agent(
    role='On-Call DBA',
    goal='Investigate database alerts using available diagnostic tools',
    backstory='Experienced DBA with access to monitoring tools. Always checks metrics before making recommendations.',
    tools=[check_connections, check_replication_lag],    # agent can use these
    verbose=True
)

task = Task(
    description='''Check the health of pg-primary and pg-replica-2.
    Report on connection utilization and replication lag.
    Provide recommendations based on the findings.''',
    expected_output='Health report with connection stats, replication lag, and recommendations.',
    agent=dba_agent
)

crew = Crew(agents=[dba_agent], tasks=[task], process=Process.sequential, verbose=True)

print('Agent tools:')
for t in dba_agent.tools:
    print(f'  - {t.name}')
print()
result = crew.kickoff()
print(result)
"
```

Expected output (yours will differ):
```
Agent tools:
  - Check PostgreSQL Connections
  - Check Replication Lag

 [INFO]: Working Agent: On-Call DBA
 [INFO]: Starting Task: Check the health of...
 [INFO]: Using tool: Check PostgreSQL Connections
 [INFO]: Tool input: {"database_name": "pg-primary"}
 [INFO]: Tool output: Connection Report for pg-primary:
   Active: 145 ...
 [INFO]: Using tool: Check Replication Lag
 [INFO]: Tool input: {"replica_name": "pg-replica-2"}
 [INFO]: Tool output: Replication Lag for pg-replica-2:
   Time lag: 45 seconds ...

HEALTH REPORT:
...
```

The agent DECIDES which tools to call and what arguments to pass. You don't tell it "call check_connections with pg-primary" - the agent reads the task description and figures that out on its own.

---

## Step 4. Build a DBA tool library

In production, you'd build a library of tools your agents can use. Here's a more complete set:

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai.tools import tool

# Tool 1: Query executor (simulated)
@tool('Execute SQL Query')
def execute_query(query: str, database: str) -> str:
    '''Execute a read-only SQL query against a PostgreSQL database.
    Only SELECT queries are allowed for safety.'''
    if not query.strip().upper().startswith('SELECT'):
        return 'ERROR: Only SELECT queries are allowed. This tool is read-only.'
    # In production: psycopg2 connection and execution
    return f'[SIMULATED] Executed on {database}: {query}'

# Tool 2: Log analyzer
@tool('Analyze PostgreSQL Logs')
def analyze_logs(server: str, minutes: int) -> str:
    '''Analyze PostgreSQL logs from the last N minutes.
    Returns error counts, slow query counts, and notable patterns.'''
    # In production: parse actual log files or query pg_stat_statements
    return f'''Log Analysis for {server} (last {minutes} minutes):
  Errors: 3 (2x \"could not serialize access\", 1x \"deadlock detected\")
  Slow queries (>1s): 12
  Most frequent slow query: SELECT * FROM orders WHERE customer_id = \$1 (no index)
  Connection resets: 0
  Checkpoint warnings: 1 (checkpoint completing too frequently)'''

# Tool 3: Metrics collector
@tool('Collect Server Metrics')
def collect_metrics(server: str) -> str:
    '''Collect current server metrics: CPU, memory, disk, connections.'''
    return f'''Server Metrics for {server}:
  CPU: 78% (user: 65%, system: 13%)
  Memory: 82% (shared_buffers: 8GB, effective_cache: 24GB)
  Disk /pgdata: 73% used (450GB/620GB)
  WAL rate: 120MB/min
  Transactions/sec: 4,500
  Cache hit ratio: 99.2%'''

# Tool 4: Configuration checker
@tool('Check PostgreSQL Configuration')
def check_config(server: str, parameter: str) -> str:
    '''Check the current value of a PostgreSQL configuration parameter.'''
    configs = {
        'shared_buffers': '8GB',
        'effective_cache_size': '24GB',
        'work_mem': '256MB',
        'max_connections': '200',
        'wal_level': 'replica',
        'max_wal_senders': '10',
    }
    value = configs.get(parameter, 'parameter not found')
    return f'{server}: {parameter} = {value}'

print('DBA Tool Library:')
tools = [execute_query, analyze_logs, collect_metrics, check_config]
for t in tools:
    desc = t.description.split('\n')[0][:60] if t.description else 'No description'
    print(f'  {t.name}: {desc}...')
print()
print(f'Total tools: {len(tools)}')
print()
print('These tools can be assigned to any agent:')
print('  agent = Agent(role=..., tools=[execute_query, analyze_logs])')
"
```

Expected output (yours will differ):
```
DBA Tool Library:
  Execute SQL Query: Execute a read-only SQL query against a PostgreSQL datab...
  Analyze PostgreSQL Logs: Analyze PostgreSQL logs from the last N minutes.
...
  Total tools: 4

These tools can be assigned to any agent:
  agent = Agent(role=..., tools=[execute_query, analyze_logs])
```

**Key safety pattern:** Notice that `execute_query` only allows SELECT queries. When giving AI agents tools that interact with real databases, always enforce read-only access. This is like creating a PostgreSQL role with `GRANT SELECT` only.

---

## Step 5. Callbacks for logging

Callbacks let you hook into the crew's lifecycle - log when tasks start and finish, track timing, send notifications.

**DBA analogy:** Callbacks are like PostgreSQL event triggers or `log_statement` - they fire automatically when something happens.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from datetime import datetime

# Track timing
start_times: dict[str, datetime] = {}

def on_task_start(task_output):
    '''Called when a task begins.'''
    now = datetime.now().strftime('%H:%M:%S')
    print(f'  [{now}] TASK STARTED')

def on_task_complete(task_output):
    '''Called when a task finishes.'''
    now = datetime.now().strftime('%H:%M:%S')
    # task_output.raw contains the agent's response text
    output_preview = str(task_output.raw)[:100] if task_output.raw else 'no output'
    print(f'  [{now}] TASK COMPLETED - Output: {output_preview}...')

agent = Agent(
    role='Health Check DBA',
    goal='Perform database health checks',
    backstory='Runs routine health checks across the fleet.',
    verbose=False    # quiet mode - let callbacks do the logging
)

task1 = Task(
    description='Check if pg-primary has any long-running queries over 5 minutes.',
    expected_output='List of long-running queries or confirmation that none exist.',
    agent=agent,
    callback=on_task_complete    # fires when this task finishes
)

task2 = Task(
    description='Check replication lag across all replicas.',
    expected_output='Replication lag report for each replica.',
    agent=agent,
    callback=on_task_complete
)

crew = Crew(
    agents=[agent],
    tasks=[task1, task2],
    process=Process.sequential,
    verbose=False    # quiet crew - callbacks handle logging
)

print('Running health check crew with callbacks...')
print()
result = crew.kickoff()
print()
print('Crew complete.')
"
```

Expected output (yours will differ):
```
Running health check crew with callbacks...

  [10:15:32] TASK COMPLETED - Output: No long-running queries found on pg-primary...
  [10:15:35] TASK COMPLETED - Output: Replication lag report: pg-replica-1: 2s...

Crew complete.
```

---

## Step 6. Full incident response crew

Putting it all together - a crew that handles a complete incident from triage to post-mortem:

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.tools import tool

# --- Tools ---
@tool('Get Alert Details')
def get_alert(alert_id: str) -> str:
    '''Fetch full details for a database alert by ID.'''
    return '''Alert #DB-4521:
  Severity: P1 (auto-escalated)
  Source: pg-primary-1
  Message: 200 blocked queries, oldest waiting 12 minutes
  Triggered: 2026-06-15 09:45:00
  Metrics at trigger time:
    Active connections: 198/200
    CPU: 92%
    Longest transaction: 45 minutes (pid 12847)
    Lock waits: 200
    Deadlocks last hour: 0'''

@tool('Run Diagnostic Query')
def run_diagnostic(query_name: str) -> str:
    '''Run a pre-defined diagnostic query. Available: blocking_tree, long_transactions, lock_waits, table_bloat.'''
    results = {
        'blocking_tree': '''Blocking Tree:
  PID 12847 (idle in transaction, 45 min) BLOCKS:
    PID 13001 (UPDATE orders, waiting 12 min)
    PID 13002 (UPDATE orders, waiting 11 min)
    ... (198 more blocked PIDs)
  Query: BEGIN; SELECT * FROM orders WHERE id = 99; (no COMMIT)
  Application: analytics-etl-job
  Client: 10.0.1.50''',
        'long_transactions': '''Long Transactions:
  PID 12847 | 45 min | idle in transaction | analytics-etl-job | BEGIN; SELECT...''',
    }
    return results.get(query_name, f'Unknown diagnostic: {query_name}')

# --- Agents ---
triage = Agent(
    role='Incident Triage Lead',
    goal='Quickly assess the incident and create an initial assessment',
    backstory='First responder for all database incidents. Calm under pressure.',
    tools=[get_alert],
    verbose=True
)

investigator = Agent(
    role='Incident Investigator',
    goal='Find the root cause using diagnostic tools',
    backstory='Deep PostgreSQL internals expert. Finds root causes fast.',
    tools=[run_diagnostic],
    verbose=True
)

fixer = Agent(
    role='Remediation Engineer',
    goal='Execute safe fixes with rollback plans',
    backstory='Expert at making changes under pressure without making things worse.',
    verbose=True
)

postmortem = Agent(
    role='Post-Incident Analyst',
    goal='Write clear post-mortems that prevent recurrence',
    backstory='Writes blameless post-mortems focused on systemic improvements.',
    verbose=True
)

# --- Tasks ---
task_triage = Task(
    description='Fetch and assess alert #DB-4521. Determine severity, blast radius, and immediate risk.',
    expected_output='Initial assessment with severity, blast radius, and escalation decision.',
    agent=triage
)

task_investigate = Task(
    description='Run diagnostics to find the root cause. Check blocking tree and long transactions.',
    expected_output='Root cause analysis with specific PIDs, queries, and applications involved.',
    agent=investigator,
    context=[task_triage]
)

task_fix = Task(
    description='''Create a remediation plan based on the investigation.
    Include: immediate action (terminate the blocking query), verification steps,
    and preventive measures (statement timeout, idle-in-transaction timeout).''',
    expected_output='Step-by-step remediation with exact commands and rollback plan.',
    agent=fixer,
    context=[task_triage, task_investigate]
)

task_postmortem = Task(
    description='''Write a post-mortem report covering:
    1. Timeline of events
    2. Root cause
    3. Impact (how many queries blocked, for how long)
    4. What we did to fix it
    5. Action items to prevent recurrence''',
    expected_output='Blameless post-mortem document.',
    agent=postmortem,
    context=[task_triage, task_investigate, task_fix]
)

# --- Crew ---
incident_crew = Crew(
    agents=[triage, investigator, fixer, postmortem],
    tasks=[task_triage, task_investigate, task_fix, task_postmortem],
    process=Process.sequential,
    verbose=True
)

print('Incident Response Crew')
print('=' * 40)
print('Pipeline: Triage -> Investigate -> Fix -> Post-Mortem')
print()
for i, task in enumerate(incident_crew.tasks, 1):
    deps = [t.agent.role for t in (task.context if isinstance(task.context, list) else [])]
    dep_str = f' (needs: {', '.join(deps)})' if deps else ''
    print(f'  {i}. [{task.agent.role}]{dep_str}')
print()
print('Kicking off...')
print()
result = incident_crew.kickoff()
print()
print('POST-MORTEM:')
print(result)
"
```

Expected output (yours will differ):
```
Incident Response Crew
========================================
Pipeline: Triage -> Investigate -> Fix -> Post-Mortem

  1. [Incident Triage Lead]
  2. [Incident Investigator] (needs: Incident Triage Lead)
  3. [Remediation Engineer] (needs: Incident Triage Lead, Incident Investigator)
  4. [Post-Incident Analyst] (needs: Incident Triage Lead, Incident Investigator, Remediation Engineer)

Kicking off...

 [INFO]: Working Agent: Incident Triage Lead
 ...
 [INFO]: Working Agent: Incident Investigator
 ...
 [INFO]: Working Agent: Remediation Engineer
 ...
 [INFO]: Working Agent: Post-Incident Analyst
 ...

POST-MORTEM:
## Post-Incident Report - Alert #DB-4521

### Timeline
- 09:00 - analytics-etl-job started a transaction
- 09:45 - Alert triggered: 200 blocked queries
...
```

---

## What You Built

In this guide you learned:
- **Task dependencies** with `context` - directing information flow like CTEs
- **Delegation** with `allow_delegation` - letting agents hand off work
- **Custom tools** with `@tool` - giving agents the ability to query databases
- **Callbacks** - logging and monitoring crew execution
- **Full incident pipeline** - triage, investigate, fix, post-mortem as a crew

**DBA translation:** You went from a simple sequential runbook to a full incident response system where specialists have access to diagnostic tools, work flows through defined dependencies, and the output is a complete post-mortem document.

## Next Steps

In Build 03, you'll add memory to your crews - so agents remember past incidents and learn over time. Instead of treating every alert as brand new, your crew will say "this looks like the outage we had last week."
