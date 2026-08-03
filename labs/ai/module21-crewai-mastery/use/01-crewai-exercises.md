# USE: CrewAI Mastery Exercises

Work through these exercises in order. Each builds on skills from the Build guides. Try to solve them before looking at the hints or solutions.

---

## Exercise 1: Health Report Crew

**Task:** Build a 2-agent crew where Agent 1 generates a database health report and Agent 2 reviews it for accuracy and completeness.

Requirements:
- Agent 1: "Health Check DBA" - checks connections, replication, disk, and CPU
- Agent 2: "Report Reviewer" - reviews the report for missing items, inaccuracies, and formatting
- Sequential process
- The reviewer should receive the health checker's output as context

Your alert:
```
Server: pg-primary-1
Connections: 180/200 (90%)
Replication lag: 12 seconds
Disk /pgdata: 88% full
CPU: 72%
Cache hit ratio: 94.1%
```

Expected output: A reviewed health report with the reviewer's comments and a final grade (PASS/NEEDS-WORK/FAIL).

<details>
<summary>Hint</summary>

Create two agents, two tasks. The second task should have `context=[first_task]` so the reviewer sees the health report. The reviewer's backstory should emphasize attention to detail and standards compliance.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

checker = Agent(
    role='Health Check DBA',
    goal='Generate comprehensive database health reports',
    backstory='Methodical DBA who checks every metric and documents findings clearly.',
    verbose=True
)

reviewer = Agent(
    role='Report Reviewer',
    goal='Review health reports for accuracy, completeness, and actionability',
    backstory='''Senior DBA who reviews team reports. Checks for: missing metrics,
    incorrect severity assessments, missing recommendations, and formatting issues.
    Grades reports as PASS, NEEDS-WORK, or FAIL.''',
    verbose=True
)

check_task = Task(
    description='''Generate a health report for pg-primary-1 with these metrics:
    Connections: 180/200 (90%)
    Replication lag: 12 seconds
    Disk /pgdata: 88% full
    CPU: 72%
    Cache hit ratio: 94.1%

    For each metric, provide: current value, threshold, status (OK/WARNING/CRITICAL),
    and recommended action if needed.''',
    expected_output='Structured health report with status and recommendations per metric.',
    agent=checker
)

review_task = Task(
    description='''Review the health report for completeness and accuracy.
    Check: Are all metrics covered? Are severity levels correct?
    Are recommendations actionable? Is anything missing?
    Grade the report as PASS, NEEDS-WORK, or FAIL with specific feedback.''',
    expected_output='Review with grade (PASS/NEEDS-WORK/FAIL) and specific feedback.',
    agent=reviewer,
    context=[check_task]
)

crew = Crew(
    agents=[checker, reviewer],
    tasks=[check_task, review_task],
    process=Process.sequential,
    verbose=True
)

result = crew.kickoff()
print()
print('REVIEWED REPORT:')
print(result)
"
```
</details>

---

## Exercise 2: Custom PostgreSQL Query Tool

**Task:** Create a custom tool that simulates running PostgreSQL queries and give it to a CrewAI agent. The agent should use the tool to investigate a slow query alert.

Requirements:
- Create a `@tool` called "Run PostgreSQL Query" that accepts a query string
- The tool should return simulated results for these queries:
  - `pg_stat_activity` - returns 5 rows showing active queries
  - `pg_stat_statements` - returns top 3 slow queries
  - `pg_locks` - returns 2 lock conflicts
- Build an agent with this tool and task it with investigating: "Multiple users reporting slow response times on the orders service"

<details>
<summary>Hint</summary>

Use `if 'pg_stat_activity' in query.lower()` to match queries and return appropriate simulated data. The agent will figure out which queries to run based on the task description.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.tools import tool

@tool('Run PostgreSQL Query')
def run_pg_query(query: str) -> str:
    '''Run a read-only query against PostgreSQL. Returns results as text.'''
    q = query.lower()
    if 'pg_stat_activity' in q:
        return '''pid  | state              | duration  | query
-----+--------------------+-----------+------------------------------------------
1234 | active             | 00:05:23  | SELECT * FROM orders WHERE customer_id = 99
1235 | active             | 00:03:11  | UPDATE inventory SET qty = qty - 1 WHERE id = 5
1236 | idle in transaction| 00:45:00  | BEGIN; SELECT * FROM users WHERE id = 1
1237 | active             | 00:00:02  | SELECT count(*) FROM orders
1238 | active             | 00:02:45  | SELECT o.*, c.name FROM orders o JOIN customers c...'''
    elif 'pg_stat_statements' in q:
        return '''query                                    | calls | mean_ms | total_ms
-----------------------------------------+-------+---------+---------
SELECT * FROM orders WHERE customer_id=$ | 45000 | 340.2   | 15309000
UPDATE inventory SET qty = qty - 1 WHERE | 12000 | 125.8   |  1509600
SELECT o.*, c.name FROM orders o JOIN cu | 8000  | 89.3    |   714400'''
    elif 'pg_locks' in q:
        return '''pid  | locktype | mode          | granted | waiting_pid
-----+----------+---------------+---------+------------
1236 | relation | AccessExclusive| t       | 1234
1236 | relation | AccessExclusive| t       | 1235'''
    else:
        return f'Query executed: {query} (0 rows returned)'

agent = Agent(
    role='Performance DBA',
    goal='Investigate slow query reports using diagnostic queries',
    backstory='Expert at using pg_stat_activity, pg_stat_statements, and pg_locks to find performance issues.',
    tools=[run_pg_query],
    verbose=True
)

task = Task(
    description='''Users report slow response times on the orders service.
    Use your PostgreSQL query tools to investigate:
    1. Check active queries (pg_stat_activity)
    2. Check slow query patterns (pg_stat_statements)
    3. Check for lock conflicts (pg_locks)
    Provide a root cause analysis and remediation plan.''',
    expected_output='Investigation findings with root cause and fix.',
    agent=agent
)

crew = Crew(agents=[agent], tasks=[task], process=Process.sequential, verbose=True)
result = crew.kickoff()
print()
print('INVESTIGATION:')
print(result)
"
```
</details>

---

## Exercise 3: Hierarchical Crew with Manager

**Task:** Build a crew with `Process.hierarchical` where a manager agent delegates to three specialists based on the alert type.

Requirements:
- Manager: "DBA Team Lead" with `allow_delegation=True`
- Specialist 1: "Performance DBA"
- Specialist 2: "Replication DBA"
- Specialist 3: "Storage DBA"
- Give the manager an alert that involves BOTH performance AND storage: "pg-primary has 95% disk usage AND the top query is doing sequential scans on a 500M row table"
- The manager should delegate to the right specialists

<details>
<summary>Hint</summary>

With `Process.hierarchical`, CrewAI automatically creates an internal manager. Set the task's agent to the manager, and the manager will delegate to the specialist whose role and backstory best matches the problem. For a multi-domain problem, you may need multiple tasks.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

manager = Agent(
    role='DBA Team Lead',
    goal='Coordinate incident response by delegating to the right specialists',
    backstory='''You lead a team of 3 specialist DBAs. You NEVER investigate
    yourself - you assess the alert and delegate to the right person.
    For multi-domain issues, you delegate to multiple specialists.''',
    allow_delegation=True,
    verbose=True
)

perf_dba = Agent(
    role='Performance DBA',
    goal='Diagnose and fix query performance issues',
    backstory='Expert in EXPLAIN plans, indexes, sequential scans, and query optimization.',
    verbose=True
)

repl_dba = Agent(
    role='Replication DBA',
    goal='Diagnose and fix replication issues',
    backstory='Expert in streaming replication, WAL, and failover procedures.',
    verbose=True
)

storage_dba = Agent(
    role='Storage DBA',
    goal='Diagnose and fix storage and disk issues',
    backstory='Expert in tablespace management, VACUUM, bloat, WAL retention, and disk capacity planning.',
    verbose=True
)

task_storage = Task(
    description='''pg-primary disk usage is at 95%. Investigate what is consuming
    disk space and provide a remediation plan to free space immediately
    and prevent recurrence.''',
    expected_output='Disk space analysis and remediation plan.',
    agent=manager
)

task_perf = Task(
    description='''The top query on pg-primary is doing sequential scans on a
    500M row table (orders). It runs 45,000 times per day with a mean
    execution time of 340ms. Diagnose and provide an optimization plan.''',
    expected_output='Query optimization plan with specific index recommendations.',
    agent=manager,
    context=[task_storage]
)

crew = Crew(
    agents=[manager, perf_dba, repl_dba, storage_dba],
    tasks=[task_storage, task_perf],
    process=Process.hierarchical,
    manager_agent=manager,
    verbose=True
)

print('Hierarchical crew: Manager delegates to specialists')
print()
result = crew.kickoff()
print()
print('RESULT:')
print(result)
"
```
</details>

---

## Exercise 4: Crew with Memory

**Task:** Build a crew that remembers past incidents. Run it twice with similar alerts and verify the second run references the first.

Requirements:
- Enable `memory=True` on the crew
- First run: alert about connection pool exhaustion on pg-primary
- Second run: alert about connection pool exhaustion on pg-analytics
- The agent on the second run should reference the first incident

<details>
<summary>Hint</summary>

Set `memory=True` on the Crew. The first run stores its results. On the second run, the agent's backstory should mention checking for past similar incidents. CrewAI's long-term memory will surface the first run's results.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

def run_incident(alert_text: str, run_number: int) -> str:
    agent = Agent(
        role='Incident Responder',
        goal='Resolve database incidents using past experience',
        backstory='''Experienced DBA who always checks for similar past incidents
        before investigating. References past solutions when a pattern matches.''',
        verbose=True
    )
    task = Task(
        description=f'''Run #{run_number} - Respond to: {alert_text}
        First, check if you have seen a similar incident before.
        Then provide your investigation and remediation plan.''',
        expected_output='Response referencing any past similar incidents.',
        agent=agent
    )
    crew = Crew(
        agents=[agent],
        tasks=[task],
        process=Process.sequential,
        memory=True,
        verbose=True
    )
    result = crew.kickoff()
    return str(result)

# Run 1
print('=== RUN 1: Connection exhaustion on pg-primary ===')
print()
r1 = run_incident(
    'pg-primary connection pool exhausted. 200/200 connections. '
    'Root cause: ETL job not releasing connections. Fix: killed idle connections, '
    'added PgBouncer with pool_size=50.',
    run_number=1
)
print()
print(f'Run 1 result: {r1[:200]}...')
print()

# Run 2 - similar alert, different server
print('=== RUN 2: Connection exhaustion on pg-analytics ===')
print()
r2 = run_incident(
    'pg-analytics connection pool exhausted. 500/500 connections. '
    'Multiple reporting queries are holding idle connections.',
    run_number=2
)
print()
print(f'Run 2 result: {r2[:200]}...')
print()
print('Check: does Run 2 reference the pg-primary incident from Run 1?')
"
```
</details>

---

## Exercise 5: Multi-Alert Incident Response Crew

**Task:** Build a crew that can handle 3 different alert types and route each to the correct specialist.

Requirements:
- Create a triage agent that classifies alerts
- Create 3 specialist agents (performance, replication, storage)
- Process these 3 alerts sequentially through the crew:
  1. "pg-replica-2 replication lag is 60 seconds"
  2. "pg-primary disk /pgdata is 97% full"
  3. "Query on orders table taking 45 seconds, sequential scan on 500M rows"
- Each alert should be triaged and then handled by the correct specialist
- Output a summary of all 3 resolutions

<details>
<summary>Hint</summary>

Create a function that builds a 2-task crew (triage + specialist) for each alert. The triage task classifies the alert, and based on the `context`, the specialist task handles it. Run the function 3 times with different alerts and collect results.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Define specialists once
triage = Agent(
    role='Triage Lead',
    goal='Classify alerts and route to the correct specialist',
    backstory='Instantly recognizes alert types: performance, replication, storage.',
    verbose=True
)

perf = Agent(
    role='Performance DBA',
    goal='Fix query performance issues',
    backstory='Expert in EXPLAIN, indexes, and query optimization.',
    verbose=True
)

repl = Agent(
    role='Replication DBA',
    goal='Fix replication issues',
    backstory='Expert in streaming replication, WAL, and lag troubleshooting.',
    verbose=True
)

storage = Agent(
    role='Storage DBA',
    goal='Fix disk and storage issues',
    backstory='Expert in bloat, vacuum, WAL retention, and capacity planning.',
    verbose=True
)

alerts = [
    'pg-replica-2 replication lag is 60 seconds. Replica CPU: 40%. Network: normal.',
    'pg-primary disk /pgdata is 97% full. WAL archiving backlog: 500 files.',
    'Query on orders table taking 45 seconds. Sequential scan on 500M rows. No index on customer_id.',
]

all_results = []

for i, alert in enumerate(alerts, 1):
    print(f'\\n{\"=\" * 50}')
    print(f'ALERT {i}: {alert[:60]}...')
    print(f'{\"=\" * 50}')

    task_triage = Task(
        description=f'Triage this alert: {alert}. Classify as performance, replication, or storage.',
        expected_output='Category and severity.',
        agent=triage
    )

    # Use all specialists - the triage context helps the right one respond appropriately
    task_fix = Task(
        description=f'''Based on the triage, provide specific remediation steps
        for this alert: {alert}
        Include exact PostgreSQL commands.''',
        expected_output='Remediation steps with exact commands.',
        agent=repl if 'replication' in alert.lower() else storage if 'disk' in alert.lower() else perf,
        context=[task_triage]
    )

    crew = Crew(
        agents=[triage, perf, repl, storage],
        tasks=[task_triage, task_fix],
        process=Process.sequential,
        verbose=True
    )

    result = crew.kickoff()
    all_results.append({'alert': alert, 'resolution': str(result)})

# Summary
print(f'\\n{\"=\" * 50}')
print('SUMMARY: All Alerts Resolved')
print(f'{\"=\" * 50}')
for i, r in enumerate(all_results, 1):
    print(f'\\nAlert {i}: {r[\"alert\"][:60]}...')
    print(f'Resolution: {str(r[\"resolution\"])[:150]}...')
"
```
</details>
