# Build 01: CrewAI Fundamentals

CrewAI lets you build teams of AI agents that collaborate to solve problems. Think of it this way: instead of one LLM doing everything, you assemble a crew of specialists - just like building an on-call DBA team where each person has a specialty (replication, performance tuning, security).

This guide walks you through installing CrewAI, creating agents, defining tasks, and assembling your first crew.

## DBA Analogy: Why Crews?

| Single LLM Call | CrewAI Crew |
|----------------|-------------|
| One DBA handles everything | Specialized team: triage, performance, replication |
| Gets overwhelmed on complex issues | Each agent focuses on what they know best |
| Like one `psql` session doing all the work | Like a runbook with assigned owners per step |
| No handoffs | Output of one step feeds the next |
| `SELECT * FROM problems` - one query does it all | `WITH triage AS (...), diagnosis AS (...), fix AS (...)` - CTEs chain together |

---

## Step 1. Install CrewAI

CrewAI requires Python 3.10+ and pip. On your **Mac terminal**, run:

```bash
pip3 install crewai crewai-tools
```

Expected output (yours will differ):
```
Successfully installed crewai-0.x.x crewai-tools-0.x.x ...
```

Verify the install:

```bash
python3 -c "
import crewai
print(f'CrewAI version: {crewai.__version__}')
print('Install successful')
"
```

Expected output (yours will differ):
```
CrewAI version: 0.x.x
Install successful
```

---

## Step 2. Configure your API key

CrewAI agents use an LLM (like OpenAI's GPT or Anthropic's Claude) under the hood. You need an API key.

**For OpenAI:**

```bash
export OPENAI_API_KEY="your-key-here"
```

**For Anthropic (Claude):**

```bash
export ANTHROPIC_API_KEY="your-key-here"
```

To make this permanent, add it to your shell profile. On your **Mac terminal**:

```bash
vi ~/.zshrc
```

Add one of these lines at the bottom:

```
export OPENAI_API_KEY="your-key-here"
export ANTHROPIC_API_KEY="your-key-here"
```

Save and reload:

```bash
source ~/.zshrc
```

**DBA analogy:** This is like setting `PGPASSWORD` or putting credentials in `~/.pgpass` - the tool needs authentication to talk to the backend service.

---

## Step 3. Understand the three building blocks

CrewAI has three core concepts. Every crew you build uses them:

| CrewAI Concept | What It Is | DBA Analogy |
|---------------|------------|-------------|
| **Agent** | A specialist with a role, goal, and backstory | A DBA team member with a specialty (the replication expert, the performance tuner) |
| **Task** | A specific piece of work assigned to an agent | A ticket or runbook step: "Investigate the slow query on pg-primary" |
| **Crew** | A team of agents working through tasks | The on-call rotation - the team assembled to handle an incident |

The relationship is simple:
- You define **Agents** (who does the work)
- You define **Tasks** (what work needs to be done)
- You assemble a **Crew** (agents + tasks + process order)
- You `kick off` the crew and it runs

This is like writing a runbook:
1. Define roles (who is responsible for each step)
2. Define steps (what each person does)
3. Execute the runbook (run it in order)

---

## Step 4. Create your first Agent

An Agent needs three things:
- `role` - their job title (like "Senior Performance DBA")
- `goal` - what they're trying to accomplish (like "Find the root cause of slow queries")
- `backstory` - context about their expertise (like "10 years of PostgreSQL tuning experience")

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent

# Create a DBA triage specialist
triage_agent = Agent(
    role='Database Triage Lead',
    goal='Quickly assess incoming database alerts and determine severity and category',
    backstory='''You are a senior DBA with 15 years of experience. You have seen
    every type of database alert - replication lag, high CPU, connection storms,
    disk space warnings, long-running queries. You can look at an alert and
    immediately know which specialist should handle it and how urgent it is.
    You categorize alerts as: performance, replication, storage, security, or connectivity.''',
    verbose=True    # prints what the agent is thinking
)

print(f'Agent created: {triage_agent.role}')
print(f'Goal: {triage_agent.goal}')
"
```

Expected output (yours will differ):
```
Agent created: Database Triage Lead
Goal: Quickly assess incoming database alerts and determine severity and category
```

- `role` tells the LLM "you are this person" - it shapes how the agent thinks
- `goal` keeps the agent focused - like a KPI for a team member
- `backstory` gives the LLM context about what this agent knows
- `verbose=True` shows you the agent's reasoning (like `SET log_statement = 'all'`)

---

## Step 5. Create a Task

A Task defines what an agent should do. It needs:
- `description` - the actual work (like a Jira ticket description)
- `expected_output` - what a good result looks like
- `agent` - who does this task

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task

triage_agent = Agent(
    role='Database Triage Lead',
    goal='Assess database alerts and determine severity and category',
    backstory='Senior DBA with 15 years of experience triaging database incidents.',
    verbose=True
)

# Create a task - like a Jira ticket
triage_task = Task(
    description='''Analyze this database alert and provide a triage assessment:

    ALERT: pg-primary-1 replication lag is 45 seconds and climbing.
    Current WAL position: 0/5A000000
    Replica WAL position: 0/58000000
    Network latency between primary and replica: 2ms (normal)
    Replica CPU: 95%
    Replica disk I/O wait: 60%

    Provide: severity (P1-P4), category, likely root cause, and recommended
    next steps.''',
    expected_output='''A structured triage report with:
    - Severity level (P1 critical, P2 high, P3 medium, P4 low)
    - Category (performance, replication, storage, security, connectivity)
    - Likely root cause analysis
    - Recommended immediate actions
    - Which specialist should handle this next''',
    agent=triage_agent
)

print(f'Task created for agent: {triage_task.agent.role}')
print(f'Description preview: {triage_task.description[:80]}...')
"
```

Expected output (yours will differ):
```
Task created for agent: Database Triage Lead
Description preview: Analyze this database alert and provide a triage assessment:

    ALERT: pg-primar...
```

**DBA analogy:** A Task is like a row in your incident tracking system:
- `description` = the ticket body
- `expected_output` = the Definition of Done
- `agent` = the assignee

---

## Step 6. Assemble a Crew

A Crew combines agents and tasks into a working team. The key parameter is `process` - how the crew executes:

| Process Mode | How It Works | DBA Analogy |
|-------------|-------------|-------------|
| `Process.sequential` | Tasks run one after another, output chains forward | A runbook - step 1 then step 2 then step 3 |
| `Process.hierarchical` | A manager agent delegates tasks to workers | Lead DBA assigns work: "you check replication, you check performance" |

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Define three specialist agents
triage_lead = Agent(
    role='Database Triage Lead',
    goal='Assess incoming alerts and route to the right specialist',
    backstory='Senior DBA who has triaged thousands of database incidents. Can identify the category and severity of any alert in seconds.',
    verbose=True
)

perf_specialist = Agent(
    role='Performance Specialist',
    goal='Diagnose and resolve database performance issues',
    backstory='Expert in PostgreSQL query optimization, indexing strategy, vacuum tuning, and connection pooling. Has optimized databases handling 100K TPS.',
    verbose=True
)

repl_specialist = Agent(
    role='Replication Specialist',
    goal='Diagnose and resolve replication issues',
    backstory='Expert in PostgreSQL streaming replication, logical replication, WAL management, and failover procedures. Has managed replication across 50+ clusters.',
    verbose=True
)

# Define tasks in sequence
triage_task = Task(
    description='''Analyze this alert and determine severity and category:

    ALERT: pg-primary-1 replication lag is 45 seconds and climbing.
    Replica CPU: 95%. Replica disk I/O wait: 60%.
    Network latency: 2ms (normal).

    Classify the alert and recommend which specialist should investigate.''',
    expected_output='Severity level, category, and which specialist should handle this.',
    agent=triage_lead
)

investigate_task = Task(
    description='''Based on the triage assessment, investigate the root cause.
    Consider: WAL generation rate, replay speed, disk throughput, and
    competing workloads on the replica. Provide a detailed diagnosis.''',
    expected_output='Root cause analysis with specific technical details.',
    agent=repl_specialist
)

remediate_task = Task(
    description='''Based on the investigation findings, provide specific
    remediation steps. Include exact PostgreSQL commands to run,
    configuration changes to make, and verification steps.''',
    expected_output='Step-by-step remediation plan with exact commands.',
    agent=repl_specialist
)

# Assemble the crew
dba_crew = Crew(
    agents=[triage_lead, perf_specialist, repl_specialist],
    tasks=[triage_task, investigate_task, remediate_task],
    process=Process.sequential,    # runbook order: triage -> investigate -> fix
    verbose=True
)

print('Crew assembled!')
print(f'Agents: {len(dba_crew.agents)}')
print(f'Tasks: {len(dba_crew.tasks)}')
print(f'Process: {dba_crew.process}')
print()
print('Agent roles:')
for agent in dba_crew.agents:
    print(f'  - {agent.role}')
print()
print('Task sequence:')
for i, task in enumerate(dba_crew.tasks, 1):
    print(f'  {i}. {task.agent.role}: {task.description[:60]}...')
"
```

Expected output (yours will differ):
```
Crew assembled!
Agents: 3
Tasks: 3
Process: Process.sequential

Agent roles:
  - Database Triage Lead
  - Performance Specialist
  - Replication Specialist

Task sequence:
  1. Database Triage Lead: Analyze this alert and determine severity and category:...
  2. Replication Specialist: Based on the triage assessment, investigate the root ...
  3. Replication Specialist: Based on the investigation findings, provide specific...
```

---

## Step 7. Kick off the Crew

This is where the magic happens. When you call `crew.kickoff()`, CrewAI:
1. Runs task 1 (triage) and gets the output
2. Passes that output as context to task 2 (investigate)
3. Passes that output as context to task 3 (remediate)

Each agent calls the LLM with its role, goal, backstory, and the task description. The LLM generates a response, which becomes the task output.

**This step costs API credits.** Each agent makes at least one LLM call. A 3-agent crew typically uses 3-5 API calls.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

triage_lead = Agent(
    role='Database Triage Lead',
    goal='Assess incoming alerts and route to the right specialist',
    backstory='Senior DBA who has triaged thousands of database incidents.',
    verbose=True
)

repl_specialist = Agent(
    role='Replication Specialist',
    goal='Diagnose and resolve replication issues',
    backstory='Expert in PostgreSQL streaming replication, WAL management, and failover. Has managed 50+ clusters.',
    verbose=True
)

triage_task = Task(
    description='''Analyze this alert:
    ALERT: pg-primary-1 replication lag is 45 seconds and climbing.
    Replica CPU: 95%. Replica disk I/O wait: 60%. Network: 2ms (normal).
    Classify severity (P1-P4) and category.''',
    expected_output='Severity, category, and recommended specialist.',
    agent=triage_lead
)

fix_task = Task(
    description='''Based on the triage, provide the exact PostgreSQL commands
    to diagnose and fix this replication lag issue. Include commands to check
    WAL sender/receiver status, replay lag, and any configuration changes.''',
    expected_output='Step-by-step fix with exact psql commands.',
    agent=repl_specialist
)

crew = Crew(
    agents=[triage_lead, repl_specialist],
    tasks=[triage_task, fix_task],
    process=Process.sequential,
    verbose=True
)

print('Kicking off the DBA crew...')
print('=' * 50)
result = crew.kickoff()
print()
print('=' * 50)
print('FINAL RESULT:')
print('=' * 50)
print(result)
"
```

Expected output (yours will differ):
```
Kicking off the DBA crew...
==================================================
 [2026-06-15 10:00:00][INFO]: Working Agent: Database Triage Lead
 [2026-06-15 10:00:00][INFO]: Starting Task: Analyze this alert...

... (agent reasoning and LLM calls) ...

 [2026-06-15 10:00:05][INFO]: Working Agent: Replication Specialist
 [2026-06-15 10:00:05][INFO]: Starting Task: Based on the triage...

... (agent reasoning and LLM calls) ...

==================================================
FINAL RESULT:
==================================================
## Replication Lag Remediation Plan

1. Check WAL sender status:
   SELECT * FROM pg_stat_replication;

2. Check replay lag on replica:
   SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;
...
```

The exact output depends on the LLM. The key thing: each agent produced structured output and the second agent used the first agent's output as context.

---

## Step 8. Use Anthropic Claude instead of OpenAI

By default, CrewAI uses OpenAI. To use Claude:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process, LLM

# Configure Claude as the LLM
claude_llm = LLM(
    model='anthropic/claude-sonnet-4-20250514',
    api_key='your-anthropic-key-here'    # or use ANTHROPIC_API_KEY env var
)

agent = Agent(
    role='PostgreSQL Expert',
    goal='Answer database questions accurately',
    backstory='Senior PostgreSQL DBA with deep internals knowledge.',
    llm=claude_llm,
    verbose=True
)

task = Task(
    description='Explain what happens during a PostgreSQL checkpoint in 3 sentences.',
    expected_output='A clear, concise explanation of PostgreSQL checkpoints.',
    agent=agent
)

crew = Crew(agents=[agent], tasks=[task], process=Process.sequential, verbose=True)
result = crew.kickoff()
print(result)
"
```

You can also set the LLM via environment variable:

```bash
export CREWAI_LLM_PROVIDER="anthropic"
export ANTHROPIC_API_KEY="your-key"
```

---

## What You Built

In this guide you:
- Installed CrewAI and configured API access
- Created Agents with roles, goals, and backstories (your DBA team members)
- Defined Tasks with descriptions and expected outputs (your runbook steps)
- Assembled a Crew with sequential process (your incident response runbook)
- Kicked off the crew and saw agents collaborate on a replication lag alert

**DBA translation:** You went from "one DBA doing everything" to "a team of specialists working a runbook together." The triage lead classifies the alert, then the replication specialist investigates and provides exact commands to fix it.

## Next Steps

In Build 02, you'll learn advanced patterns: task dependencies, delegation between agents, and building custom PostgreSQL tools that agents can use to actually query your databases.
