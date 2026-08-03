# Build 03: Orchestrator Pattern

## What You Will Build

A master "orchestrator" agent that receives a database alert, decides which specialist agents need to handle it, sends tasks to them in parallel, and then combines all their responses into a single unified recommendation.

By the end of this guide you will understand how multi-agent systems divide and conquer complex problems - the same way a lead DBA delegates to team members.

---

## Before You Start

You need:
- Python 3 installed (`python3 --version`)
- The `anthropic` Python package (`pip3 install anthropic`)
- An Anthropic API key exported in your terminal:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

---

## Step 1: The Orchestrator Agent

### What is an orchestrator?

In a multi-agent system, the **orchestrator** is the agent that:
1. Receives the original problem (a database alert, a user request, etc.)
2. Reads it and decides which specialists are needed
3. Hands off specific sub-tasks to those specialists
4. Waits for all specialists to finish
5. Combines their answers into one final response

**DBA analogy:** Think of a lead DBA who receives a production incident page at 2 AM. The lead does not try to fix everything alone. Instead, the lead looks at the alert, calls the storage engineer about disk usage, calls the application team about connection counts, and calls the performance team about slow queries. Then the lead reads all three call-back reports and writes the final incident summary. The lead DBA is the orchestrator.

### Why not just use one agent?

One agent can handle one task at a time. If your alert has three different dimensions (performance, storage, security), one agent must work through them sequentially. An orchestrator sends those three tasks to three specialists who work in parallel - the same way a DBA lead delegates instead of doing everything alone.

### Run this script

Every line is explained below the script. Run it in your Mac terminal:

```bash
python3 << 'PYEOF'
import anthropic   # This imports the Anthropic SDK - like loading a library of tools
import json        # This imports JSON handling - we use JSON to pass structured data between agents

# Initialize the Anthropic client
# Think of this like opening a database connection - you create it once and reuse it
client = anthropic.Anthropic()

# This is our orchestrator function
# It takes a raw alert string and returns a routing plan
# DBA analogy: this is like a triage function - "what kind of problem IS this?"
def orchestrator_analyze(alert: str) -> dict:
    """
    The orchestrator reads the alert and decides which specialist agents are needed.
    Returns a JSON plan describing the task for each specialist.
    """

    # We give the orchestrator a very specific job: ONLY decide routing, not fix the problem
    # DBA analogy: the lead DBA's first job is to assess and delegate, not to start typing commands
    system_prompt = """You are an orchestrator agent for a DBA team.
Your ONLY job is to read a database alert and output a JSON routing plan.
Do NOT try to diagnose the problem. Just decide which specialists are needed.

Available specialists:
- performance_agent: handles slow queries, CPU, index issues, lock waits
- storage_agent: handles disk usage, tablespace, bloat, WAL accumulation
- connection_agent: handles connection counts, connection pooling, idle connections
- security_agent: handles failed logins, privilege changes, unusual access patterns

Output ONLY valid JSON in this exact format:
{
  "severity": "critical|high|medium|low",
  "specialists_needed": ["agent_name1", "agent_name2"],
  "task_for_each_specialist": {
    "agent_name1": "specific question or task for this specialist",
    "agent_name2": "specific question or task for this specialist"
  },
  "reason": "one sentence explaining why these specialists were chosen"
}"""

    # We call the Claude API - this is like executing a SQL query
    # model: which Claude version to use
    # max_tokens: maximum length of the response (like a result set size limit)
    # messages: the conversation - "user" is us sending the alert
    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=500,
        system=system_prompt,
        messages=[
            {"role": "user", "content": f"Alert received: {alert}"}
        ]
    )

    # response.content is a list - we take the first item and get its text
    # This is like: SELECT text FROM response WHERE position = 0
    raw_text = response.content[0].text

    # Parse the JSON string into a Python dictionary
    # A Python dictionary is like a row in a table: key-value pairs
    # json.loads() converts a JSON string into a dict - like deserializing a result
    routing_plan = json.loads(raw_text)
    return routing_plan


# --- TEST IT ---
# Simulate a real-world alert that has multiple dimensions
test_alert = """
ALERT: pg-primary-01
- CPU: 94% for last 15 minutes
- Active connections: 487 of 500 max
- Disk /var/lib/pgsql: 89% full
- 3 queries running > 10 minutes
"""

print("=== ORCHESTRATOR ANALYSIS ===")
print(f"Input alert:\n{test_alert}")

# Call the orchestrator
plan = orchestrator_analyze(test_alert)

# Pretty-print the routing plan with 2-space indentation
# json.dumps() converts a dict back to a formatted JSON string - like SELECT ... FOR OUTPUT
print("\nRouting plan produced by orchestrator:")
print(json.dumps(plan, indent=2))

print(f"\nSeverity: {plan['severity']}")
print(f"Specialists needed: {', '.join(plan['specialists_needed'])}")
print(f"Reason: {plan['reason']}")
PYEOF
```

### What to expect

```
Expected output (yours will differ):
=== ORCHESTRATOR ANALYSIS ===
Input alert:
  ALERT: pg-primary-01
  - CPU: 94% for last 15 minutes
  ...

Routing plan produced by orchestrator:
{
  "severity": "critical",
  "specialists_needed": ["performance_agent", "connection_agent", "storage_agent"],
  "task_for_each_specialist": {
    "performance_agent": "Investigate CPU at 94% and 3 long-running queries...",
    ...
  },
  "reason": "Alert shows simultaneous CPU, connection, and disk pressure..."
}
```

---

## Step 2: Task Routing

### What is task routing?

Routing means taking the orchestrator's plan and actually sending the right task to the right specialist agent.

**DBA analogy:** Think of PgBouncer. PgBouncer sits in front of your PostgreSQL instances and routes each incoming query to the right backend pool. A transaction from the billing service goes to the billing pool. A read-only analytics query goes to the replica pool. PgBouncer does not process the query itself - it just routes it. Your task router does exactly the same thing: it reads the routing plan and dispatches tasks to the right agents without doing the work itself.

**Priority handling:** Not all tasks are equal. If the disk is at 99%, the storage agent should run first. If connections are at 95% of max, the connection agent fires before the performance agent. The orchestrator sets the severity; the router decides the execution order.

### Run this script

```bash
python3 << 'PYEOF'
import anthropic
import json
import concurrent.futures   # This module runs multiple functions at the same time (parallel execution)
                            # DBA analogy: like parallel query workers - multiple tasks run simultaneously

client = anthropic.Anthropic()


# Each specialist agent is a function that takes a task description and returns a diagnosis
# DBA analogy: each function is like a stored procedure written by a specialist
# You call it with parameters, it returns a result set

def performance_agent(task: str) -> dict:
    """Specialist for CPU, slow queries, locks, indexes."""
    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=400,
        system="""You are a PostgreSQL performance specialist.
Respond ONLY with valid JSON:
{
  "agent": "performance_agent",
  "findings": "what you found",
  "root_cause": "most likely cause",
  "immediate_actions": ["action1", "action2"],
  "severity_score": 1-10
}""",
        messages=[{"role": "user", "content": task}]
    )
    return json.loads(response.content[0].text)


def storage_agent(task: str) -> dict:
    """Specialist for disk, tablespace, bloat, WAL."""
    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=400,
        system="""You are a PostgreSQL storage specialist.
Respond ONLY with valid JSON:
{
  "agent": "storage_agent",
  "findings": "what you found",
  "root_cause": "most likely cause",
  "immediate_actions": ["action1", "action2"],
  "severity_score": 1-10
}""",
        messages=[{"role": "user", "content": task}]
    )
    return json.loads(response.content[0].text)


def connection_agent(task: str) -> dict:
    """Specialist for connection counts, pooling, idle connections."""
    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=400,
        system="""You are a PostgreSQL connection management specialist.
Respond ONLY with valid JSON:
{
  "agent": "connection_agent",
  "findings": "what you found",
  "root_cause": "most likely cause",
  "immediate_actions": ["action1", "action2"],
  "severity_score": 1-10
}""",
        messages=[{"role": "user", "content": task}]
    )
    return json.loads(response.content[0].text)


def security_agent(task: str) -> dict:
    """Specialist for failed logins, privilege changes, unusual access."""
    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=400,
        system="""You are a PostgreSQL security specialist.
Respond ONLY with valid JSON:
{
  "agent": "security_agent",
  "findings": "what you found",
  "root_cause": "most likely cause",
  "immediate_actions": ["action1", "action2"],
  "severity_score": 1-10
}""",
        messages=[{"role": "user", "content": task}]
    )
    return json.loads(response.content[0].text)


# This dictionary maps agent names (strings) to their functions
# DBA analogy: like a routing table - destination name maps to the actual backend
# When you say "send to performance_agent", Python looks up this dict and calls the right function
AGENT_REGISTRY = {
    "performance_agent": performance_agent,
    "storage_agent":     storage_agent,
    "connection_agent":  connection_agent,
    "security_agent":    security_agent,
}


def route_tasks(routing_plan: dict) -> list:
    """
    Takes the orchestrator's routing plan and dispatches tasks to the right agents.
    Runs agents in parallel when severity is critical or high.
    Returns a list of results from all agents.
    """

    specialists  = routing_plan["specialists_needed"]        # list of agent names
    task_map     = routing_plan["task_for_each_specialist"]  # dict: agent_name -> task string
    severity     = routing_plan["severity"]

    print(f"\nRouting {len(specialists)} task(s) at severity={severity}")

    results = []

    # For critical/high severity, run all agents IN PARALLEL
    # concurrent.futures.ThreadPoolExecutor creates a pool of worker threads
    # DBA analogy: like parallel_workers in PostgreSQL - multiple threads process simultaneously
    # max_workers=4 means up to 4 agents can run at the same time
    if severity in ("critical", "high"):
        print("Severity is critical/high - running agents IN PARALLEL")

        # ThreadPoolExecutor is a context manager (the "with" block)
        # It automatically cleans up threads when the block finishes
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:

            # Submit each agent task to the thread pool
            # executor.submit(function, argument) schedules the function to run
            # It returns a "future" - a promise that the result will be available later
            # DBA analogy: like issuing multiple async queries - you submit them all, then collect results
            future_to_agent = {}
            for agent_name in specialists:
                if agent_name in AGENT_REGISTRY:
                    agent_func = AGENT_REGISTRY[agent_name]   # look up the function
                    task_text  = task_map[agent_name]         # look up the task
                    future = executor.submit(agent_func, task_text)   # submit to thread pool
                    future_to_agent[future] = agent_name      # remember which future belongs to which agent
                    print(f"  Dispatched: {agent_name}")

            # Now collect results as they complete
            # concurrent.futures.as_completed() returns futures in the order they finish
            # DBA analogy: like collecting query results as each parallel worker finishes
            for future in concurrent.futures.as_completed(future_to_agent):
                agent_name = future_to_agent[future]
                result = future.result()   # .result() blocks until this specific future is done
                results.append(result)
                print(f"  Completed: {agent_name} (severity_score={result.get('severity_score')})")

    # For medium/low severity, run agents SEQUENTIALLY (save API costs)
    # DBA analogy: like running EXPLAIN ANALYZE one query at a time on a low-priority issue
    else:
        print("Severity is medium/low - running agents SEQUENTIALLY")
        for agent_name in specialists:
            if agent_name in AGENT_REGISTRY:
                agent_func = AGENT_REGISTRY[agent_name]
                task_text  = task_map[agent_name]
                print(f"  Running: {agent_name}")
                result = agent_func(task_text)   # call the function directly, wait for result
                results.append(result)
                print(f"  Done: {agent_name} (severity_score={result.get('severity_score')})")

    return results


# --- TEST IT ---
# We'll use a hardcoded routing plan so this step runs independently
# In production, this plan would come from the orchestrator_analyze() function in Step 1
sample_routing_plan = {
    "severity": "critical",
    "specialists_needed": ["performance_agent", "connection_agent", "storage_agent"],
    "task_for_each_specialist": {
        "performance_agent": "CPU is at 94% and there are 3 queries running over 10 minutes. What is likely causing this and what should be done immediately?",
        "connection_agent":  "Connections are at 487 of 500 max. What is causing this and what should be done immediately?",
        "storage_agent":     "Disk /var/lib/pgsql is at 89% full. What is causing this and what should be done immediately?"
    },
    "reason": "Multiple simultaneous critical conditions requiring parallel specialist response."
}

print("=== TASK ROUTING ===")
agent_results = route_tasks(sample_routing_plan)

print(f"\nReceived {len(agent_results)} specialist report(s):")
for r in agent_results:
    print(f"  - {r['agent']}: score={r['severity_score']}, root_cause={r['root_cause'][:60]}...")
PYEOF
```

### What to expect

```
Expected output (yours will differ):
=== TASK ROUTING ===
Routing 3 task(s) at severity=critical
Severity is critical/high - running agents IN PARALLEL
  Dispatched: performance_agent
  Dispatched: connection_agent
  Dispatched: storage_agent
  Completed: connection_agent (severity_score=9)
  Completed: storage_agent (severity_score=7)
  Completed: performance_agent (severity_score=9)

Received 3 specialist report(s):
  - connection_agent: score=9, root_cause=Connection leak or missing pooler...
  - storage_agent: score=7, root_cause=WAL accumulation from long-running txn...
  - performance_agent: score=9, root_cause=Long-running transactions blocking...
```

Notice the agents do NOT complete in the order they were dispatched. That is correct - they run in parallel and finish when they are done, just like parallel query workers.

---

## Step 3: Result Aggregation

### What is result aggregation?

After all specialist agents return their reports, the orchestrator must:
1. Read all reports together
2. Resolve conflicts (agent A says the root cause is one thing, agent B says something else)
3. Sort by priority
4. Produce one unified response that a DBA can act on immediately

**DBA analogy:** You have three monitoring tools - pgBadger, check_postgres, and Datadog. Each one flags different things. None of them knows what the others found. Your job as a DBA is to read all three dashboards, correlate the findings, decide what is actually the root cause, and write a single incident report. The aggregator agent does exactly this.

**Conflict resolution:** Two agents might disagree. The performance agent says "the root cause is a missing index." The connection agent says "the root cause is a connection leak." The aggregator reads both, looks at the severity scores, and determines the real root cause - which might be that the missing index caused slow queries, which caused connections to pile up waiting. Correlation is the aggregator's job.

### Run this script

```bash
python3 << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()


def aggregate_results(agent_results: list, original_alert: str) -> dict:
    """
    Takes all specialist reports and combines them into one unified DBA action plan.
    Resolves conflicts and sorts actions by priority.
    """

    # Sort results by severity_score descending before sending to aggregator
    # This helps the aggregator see the most critical findings first
    # sorted() returns a new sorted list - it does not modify the original
    # key=lambda r: r["severity_score"] tells sorted() what value to sort by
    # reverse=True means highest score first (descending order)
    # DBA analogy: like ORDER BY severity_score DESC
    sorted_results = sorted(
        agent_results,
        key=lambda r: r["severity_score"],
        reverse=True
    )

    # Build a single string that contains all specialist reports
    # We will pass this entire string to the aggregator agent
    # DBA analogy: like concatenating result sets from multiple queries into one text block
    reports_text = ""
    for i, result in enumerate(sorted_results, start=1):
        # f-string formatting - like string_agg() in PostgreSQL
        # {variable} inside f"..." gets replaced with the variable's value
        reports_text += f"""
--- Specialist Report {i}: {result['agent']} (severity_score: {result['severity_score']}) ---
Findings:         {result['findings']}
Root cause:       {result['root_cause']}
Immediate actions: {', '.join(result['immediate_actions'])}
"""

    # The aggregator agent gets the original alert AND all specialist reports
    # Its job is to synthesize, not to re-diagnose
    system_prompt = """You are a senior DBA lead synthesizing specialist reports into one unified incident response.

Your job:
1. Read all specialist reports
2. Identify the TRUE root cause (multiple agents may have found symptoms of the same root cause)
3. Resolve any conflicts between specialists - explain why one finding takes priority
4. Produce a single ordered action plan (most critical first)
5. Estimate total recovery time

Respond ONLY with valid JSON:
{
  "incident_summary": "2-3 sentence summary of what is happening",
  "true_root_cause": "the single most likely root cause tying all findings together",
  "conflict_resolution": "if agents disagreed, explain which finding takes priority and why",
  "ordered_action_plan": [
    {"priority": 1, "action": "...", "owner": "DBA|AppTeam|Both", "estimated_minutes": 5},
    {"priority": 2, "action": "...", "owner": "DBA|AppTeam|Both", "estimated_minutes": 10}
  ],
  "estimated_total_recovery_minutes": 30,
  "follow_up_required": ["post-incident action 1", "post-incident action 2"]
}"""

    # We send both the original alert and all specialist reports to the aggregator
    # This gives it full context - original problem + all specialist findings
    user_message = f"""Original alert:
{original_alert}

Specialist reports:
{reports_text}

Please synthesize these into a unified incident response."""

    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=800,
        system=system_prompt,
        messages=[{"role": "user", "content": user_message}]
    )

    unified_report = json.loads(response.content[0].text)
    return unified_report


def print_incident_report(report: dict):
    """Formats and prints the unified report in a readable way."""

    # Separator lines for readability
    print("\n" + "="*60)
    print("UNIFIED INCIDENT REPORT")
    print("="*60)

    print(f"\nSUMMARY:\n{report['incident_summary']}")
    print(f"\nTRUE ROOT CAUSE:\n{report['true_root_cause']}")

    # Only print conflict resolution if agents actually disagreed
    # "if report['conflict_resolution']" checks if the string is non-empty
    if report["conflict_resolution"]:
        print(f"\nCONFLICT RESOLUTION:\n{report['conflict_resolution']}")

    print("\nORDERED ACTION PLAN:")
    # Iterate over the list of action dicts, printing each one
    for action in report["ordered_action_plan"]:
        print(f"  [{action['priority']}] ({action['owner']}, ~{action['estimated_minutes']}m) {action['action']}")

    print(f"\nEstimated total recovery time: {report['estimated_total_recovery_minutes']} minutes")

    print("\nFOLLOW-UP REQUIRED:")
    for item in report["follow_up_required"]:
        print(f"  - {item}")

    print("="*60)


# --- TEST IT ---
# Simulated specialist results (as if they came from Step 2's route_tasks())
# In a full pipeline, these would come directly from route_tasks()
sample_agent_results = [
    {
        "agent": "performance_agent",
        "findings": "Three queries running over 10 minutes, all waiting on RowExclusiveLock. CPU spiking due to lock contention retry loops.",
        "root_cause": "Long-running transaction holding locks, preventing other queries from completing.",
        "immediate_actions": ["SELECT pg_cancel_backend(pid) for blocking query", "Identify and fix the transaction that is not committing"],
        "severity_score": 9
    },
    {
        "agent": "connection_agent",
        "findings": "487 of 500 connections active. 320 of them are idle-in-transaction, waiting on the same lock.",
        "root_cause": "Connection buildup caused by queries blocked waiting for the long-running transaction to release locks.",
        "immediate_actions": ["Terminate idle-in-transaction connections older than 5 minutes", "Deploy PgBouncer if not already in use"],
        "severity_score": 9
    },
    {
        "agent": "storage_agent",
        "findings": "Disk at 89%. WAL directory has grown 40GB in last hour. Dead tuples accumulating because autovacuum cannot run due to long transaction.",
        "root_cause": "Long-running transaction preventing autovacuum and WAL recycling, causing disk to fill.",
        "immediate_actions": ["Monitor disk every 5 minutes", "Terminate long-running transaction to unblock WAL recycling"],
        "severity_score": 7
    }
]

original_alert = """
ALERT: pg-primary-01
- CPU: 94% for last 15 minutes
- Active connections: 487 of 500 max
- Disk /var/lib/pgsql: 89% full
- 3 queries running > 10 minutes
"""

print("=== RESULT AGGREGATION ===")
print("Feeding specialist reports to aggregator agent...")

unified = aggregate_results(sample_agent_results, original_alert)
print_incident_report(unified)
PYEOF
```

### What to expect

```
Expected output (yours will differ):
============================================================
UNIFIED INCIDENT REPORT
============================================================

SUMMARY:
A long-running uncommitted transaction on pg-primary-01 is the
single root cause driving CPU spike, connection exhaustion, and
disk fill simultaneously...

TRUE ROOT CAUSE:
An uncommitted transaction is holding RowExclusiveLock, causing
query pile-up (CPU), connection exhaustion, and blocking WAL
recycling (disk)...

ORDERED ACTION PLAN:
  [1] (DBA, ~2m) Run SELECT pid, query, now()-query_start AS duration ...
  [2] (DBA, ~1m) SELECT pg_cancel_backend(pid) for the blocking PID
  [3] (DBA, ~5m) Terminate idle-in-transaction connections > 5min
  ...

Estimated total recovery time: 20 minutes
```

Notice how the aggregator identified that all three specialists found symptoms of the SAME root cause - one long-running transaction. That correlation is exactly what a senior DBA does when reading three separate monitoring tool dashboards.

---

## Putting It All Together

The three steps above are a complete orchestrator pipeline:

```
Alert arrives
    |
    v
[Orchestrator] -- analyzes alert --> routing plan
    |
    v
[Router] -- dispatches tasks --> [performance_agent]
         |                    -> [storage_agent]     (parallel)
         |                    -> [connection_agent]
    |
    v
[Aggregator] -- synthesizes all results --> unified incident report
    |
    v
DBA receives one clear action plan
```

This is the pattern used by production AI systems like database copilots and AIOps platforms. You now understand how it works from the inside.

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---|---|---|
| Orchestrator agent | Reads a problem and decides which specialists are needed | Lead DBA assessing an incident and delegating to team members |
| Task routing | Sends the right task to the right specialist agent | PgBouncer routing queries to the right backend pool |
| Parallel execution | Runs multiple agents at the same time | PostgreSQL parallel query workers |
| Sequential execution | Runs agents one at a time for lower-priority work | Single-process query for a low-priority job |
| AGENT_REGISTRY dict | Maps agent names to their functions | A routing table: destination name maps to backend |
| Result aggregation | Combines all specialist reports into one unified response | Reading pgBadger, Datadog, and check_postgres together and writing one incident report |
| Conflict resolution | Determines which finding takes priority when agents disagree | Senior DBA correlating conflicting alerts across tools |
| Severity scoring | Lets the aggregator sort findings by importance | ORDER BY severity DESC in an alerting query |
| concurrent.futures | Python module for parallel execution | parallel_workers setting in PostgreSQL |
| json.loads / json.dumps | Convert between JSON strings and Python dicts | Deserializing and serializing structured result data |
