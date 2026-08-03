# Build 05: Production Frameworks - LangGraph, CrewAI, and OpenAI Swarm

## What You Will Build

You already built multi-agent systems from scratch in BUILD 01-04. Now you will see how production frameworks implement the same patterns you coded by hand. You will build the same DBA alert triage system three ways - with LangGraph, CrewAI, and OpenAI Swarm - and compare them to your hand-built version.

By the end of this guide you will know which framework to pick for which job, and you will recognize every pattern because you already built them yourself.

---

## Before You Start

You need:
- Python 3 installed (`python3 --version`)
- An Anthropic or OpenAI API key (frameworks vary)
- BUILD 01-04 completed (you must understand the patterns before using shortcuts)

---

## Step 1: Why Frameworks Exist

You built an orchestrator, message passing, failure handling, and circuit breakers by hand. That works. But in production:

- You repeat the same boilerplate across projects
- State management gets complex (what if agents need to pause, resume, or retry?)
- You need persistence (save agent state to a database so it survives restarts)
- You need observability (trace which agent did what, when, and why)

**DBA Analogy:** You can manage replication by writing shell scripts that check `pg_stat_replication`, run `pg_promote`, and update `pg_hba.conf`. Or you can use Patroni, which handles all of that with a tested, battle-hardened state machine. Same logic - Patroni is the "framework" for HA, just like LangGraph is a framework for agents.

| What You Built | Framework Equivalent |
|---|---|
| Agent loop (BUILD 01-02) | LangGraph nodes + edges |
| Message passing (BUILD 02) | CrewAI task delegation |
| Orchestrator pattern (BUILD 03) | LangGraph conditional routing |
| Failure handling (BUILD 04) | LangGraph retry policies, CrewAI error handling |
| Circuit breaker (BUILD 04) | Built-in timeout/fallback in all frameworks |

---

## Step 2: LangGraph - State Machines for Agents

LangGraph (by LangChain) models agent workflows as **graphs**. Each step is a node. Edges connect nodes. Conditional edges let the graph branch based on state.

**DBA Analogy:** Think of a LangGraph as a flowchart for incident response. "Check if it is a replication issue -> yes -> check lag -> lag > 30s -> page on-call. No -> check connections -> connections > 80% -> investigate connection leaks." Each box is a node, each arrow is an edge.

### Install LangGraph

```bash
pip3 install langgraph langchain-anthropic
```

### Build a DBA Alert Router with LangGraph

This is the same alert triage system from BUILD 03, but using LangGraph's state graph instead of your hand-rolled orchestrator.

```bash
python3 -c "
import os
os.environ.setdefault('ANTHROPIC_API_KEY', 'your-key-here')

from langgraph.graph import StateGraph, END
from typing import TypedDict

# State is a typed dictionary - like a row moving through a pipeline
class AlertState(TypedDict):
    alert_text: str
    category: str
    severity: str
    recommendation: str

# Node 1: Classify the alert
def classify_alert(state: AlertState) -> AlertState:
    text = state['alert_text'].lower()
    if 'replication' in text or 'lag' in text:
        state['category'] = 'replication'
    elif 'connection' in text or 'max_connections' in text:
        state['category'] = 'connection'
    elif 'cpu' in text or 'memory' in text or 'disk' in text:
        state['category'] = 'resource'
    elif 'lock' in text or 'deadlock' in text:
        state['category'] = 'locking'
    else:
        state['category'] = 'unknown'
    return state

# Node 2: Assess severity
def assess_severity(state: AlertState) -> AlertState:
    text = state['alert_text'].lower()
    if 'critical' in text or 'down' in text or 'crash' in text:
        state['severity'] = 'P1'
    elif 'high' in text or 'degraded' in text:
        state['severity'] = 'P2'
    elif 'warning' in text or 'elevated' in text:
        state['severity'] = 'P3'
    else:
        state['severity'] = 'P4'
    return state

# Node 3: Generate recommendation based on category
def recommend_action(state: AlertState) -> AlertState:
    recommendations = {
        'replication': 'Check pg_stat_replication, verify WAL sender, check network between primary and standby',
        'connection': 'Check pg_stat_activity for idle-in-transaction, review pgbouncer pool size, check application connection leaks',
        'resource': 'Check top/htop for CPU, free -h for memory, df -h for disk. Review pg_stat_bgwriter for I/O pressure',
        'locking': 'Run pg_blocking_pids() to find blockers, check pg_stat_activity for long transactions, consider pg_terminate_backend()',
        'unknown': 'Gather more context. Check PostgreSQL logs, application logs, and system metrics',
    }
    state['recommendation'] = recommendations.get(state['category'], 'Escalate to senior DBA')
    return state

# Conditional edge: route P1 alerts differently
def should_escalate(state: AlertState) -> str:
    if state['severity'] == 'P1':
        return 'escalate'
    return 'standard'

# Node 4: Escalation path (also generates recommendation since it skips the recommend node)
def escalate(state: AlertState) -> AlertState:
    state = recommend_action(state)
    state['recommendation'] = 'ESCALATE IMMEDIATELY: ' + state['recommendation'] + ' | Page on-call DBA and notify incident channel'
    return state

# Build the graph
graph = StateGraph(AlertState)

# Add nodes (like adding steps to your incident runbook)
graph.add_node('classify', classify_alert)
graph.add_node('severity', assess_severity)
graph.add_node('recommend', recommend_action)
graph.add_node('escalate', escalate)

# Add edges (the flow between steps)
graph.set_entry_point('classify')
graph.add_edge('classify', 'severity')

# Conditional edge: P1 goes to escalate, others go to recommend
graph.add_conditional_edges('severity', should_escalate, {
    'escalate': 'escalate',
    'standard': 'recommend',
})
graph.add_edge('recommend', END)
graph.add_edge('escalate', END)

# Compile and run
app = graph.compile()

# Test with alerts
alerts = [
    'WARNING: Replication lag on standby-2 is 45 seconds and rising',
    'CRITICAL: Primary database is down, all connections refused',
    'High CPU usage on pg-prod-3, queries are slow',
]

for alert in alerts:
    result = app.invoke({'alert_text': alert, 'category': '', 'severity': '', 'recommendation': ''})
    print(f'Alert: {alert[:60]}...')
    print(f'  Category: {result[\"category\"]}')
    print(f'  Severity: {result[\"severity\"]}')
    print(f'  Action: {result[\"recommendation\"][:80]}...')
    print()
"
```

Expected output (yours will differ):

```
Alert: WARNING: Replication lag on standby-2 is 45 seconds and ...
  Category: replication
  Severity: P3
  Action: Check pg_stat_replication, verify WAL sender, check network between primary a...

Alert: CRITICAL: Primary database is down, all connections refus...
  Category: connection
  Severity: P1
  Action: ESCALATE IMMEDIATELY: Check pg_stat_activity for idle-in-transaction, review ...

Alert: High CPU usage on pg-prod-3, queries are slow...
  Category: resource
  Severity: P2
  Action: Check top/htop for CPU, free -h for memory, df -h for disk. Review pg_stat_b...
```

### What LangGraph Gives You Over Hand-Built

| Feature | Your Hand-Built Code | LangGraph |
|---|---|---|
| State passing | You pass dicts between functions manually | TypedDict with automatic state threading |
| Conditional routing | if/elif chains | `add_conditional_edges` with named routes |
| Visualization | None | `graph.get_graph().draw_mermaid()` for diagrams |
| Persistence | You build it yourself | Built-in checkpointing to SQLite/Postgres |
| Streaming | Manual | Built-in token streaming |
| Human-in-the-loop | Manual input() calls | Built-in interrupt/resume points |

---

## Step 3: CrewAI - Role-Based Agent Teams

CrewAI thinks about agents as **people with roles on a team**. Each agent has a role, a goal, and a backstory. They work on tasks and collaborate.

**DBA Analogy:** CrewAI is like staffing an on-call team. You have a "Performance DBA" agent, a "Replication DBA" agent, and a "Security DBA" agent. Each has a job description (role) and a mission (goal). The crew lead (process) decides who works on what.

### Install CrewAI

```bash
pip3 install crewai crewai-tools
```

### Build a DBA Crew

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Define specialist agents - like building your DBA team
performance_dba = Agent(
    role='Performance DBA',
    goal='Analyze database performance issues and recommend tuning actions',
    backstory='Senior DBA with 15 years of PostgreSQL tuning experience. Expert in pg_stat_statements, EXPLAIN plans, and index optimization.',
    verbose=True,
    allow_delegation=False,
)

replication_dba = Agent(
    role='Replication DBA',
    goal='Monitor and troubleshoot PostgreSQL replication issues',
    backstory='Specialist in streaming replication, logical replication, and failover. Manages 50+ replica clusters.',
    verbose=True,
    allow_delegation=False,
)

triage_lead = Agent(
    role='Triage Lead',
    goal='Receive alerts, determine category and severity, and assign to the right specialist',
    backstory='Lead DBA who runs the on-call rotation. Reads every alert and decides who handles it.',
    verbose=True,
    allow_delegation=True,
)

# Define tasks - like creating tickets
classify_task = Task(
    description='Classify this alert and determine severity: \"WARNING: Replication lag on standby-2 reached 45 seconds. WAL sender on primary shows streaming state but apply delay is growing.\"',
    expected_output='A JSON with category (replication/performance/connection/storage) and severity (P1-P4)',
    agent=triage_lead,
)

investigate_task = Task(
    description='Based on the triage classification, investigate the root cause of the replication lag alert and provide step-by-step remediation commands.',
    expected_output='Step-by-step runbook with actual PostgreSQL commands to diagnose and fix the issue',
    agent=replication_dba,
)

# Create the crew - like assembling your incident team
crew = Crew(
    agents=[triage_lead, replication_dba, performance_dba],
    tasks=[classify_task, investigate_task],
    process=Process.sequential,  # Tasks run in order (like your orchestrator)
    verbose=True,
)

# Note: Running crew.kickoff() requires an LLM API key configured.
# CrewAI defaults to OpenAI. To use Anthropic:
# export OPENAI_API_KEY='your-key' OR configure CrewAI for Anthropic.
#
# For now, we show the structure. Uncomment to run:
# result = crew.kickoff()
# print(result)

print('Crew assembled:')
for agent in crew.agents:
    print(f'  Role: {agent.role}')
    print(f'  Goal: {agent.goal}')
    print()
print(f'Tasks: {len(crew.tasks)}')
print(f'Process: {crew.process}')
print('Ready to kick off (needs LLM API key)')
"
```

Expected output:

```
Crew assembled:
  Role: Performance DBA
  Goal: Analyze database performance issues and recommend tuning actions

  Role: Replication DBA
  Goal: Monitor and troubleshoot PostgreSQL replication issues

  Role: Triage Lead
  Goal: Receive alerts, determine category and severity, and assign to the right specialist

Tasks: 2
Process: sequential
Ready to kick off (needs LLM API key)
```

### CrewAI vs Your Hand-Built Code

| Feature | Your Hand-Built Code | CrewAI |
|---|---|---|
| Agent definition | Python class with methods | `Agent(role=, goal=, backstory=)` |
| Task assignment | Manual routing logic | `Task(agent=specific_agent)` |
| Execution order | You manage the loop | `Process.sequential` or `Process.hierarchical` |
| Delegation | You code it | `allow_delegation=True` lets agents hand off work |
| Memory | You build dict-based memory | Built-in short-term and long-term memory |

---

## Step 4: OpenAI Swarm - Lightweight Agent Handoffs

OpenAI Swarm is the simplest framework. Agents are just functions. They can hand off to other agents by returning a handoff instruction. No state machines, no crew roles - just function calls and handoffs.

**DBA Analogy:** Swarm is like a phone tree. You call the helpdesk (Agent A). They say "this is a replication issue, let me transfer you" and hand off to the replication specialist (Agent B). Agent B handles it directly.

### Install Swarm

```bash
pip3 install openai
```

Swarm is part of the OpenAI cookbook/experimental repo. The pattern is simple enough to show inline:

```bash
python3 -c "
# Swarm pattern: agents are functions that can hand off to other agents
# This is the simplest multi-agent pattern - no framework needed

class Agent:
    def __init__(self, name, instructions, functions=None):
        self.name = name
        self.instructions = instructions
        self.functions = functions or []

class Handoff:
    def __init__(self, agent):
        self.agent = agent

# Define specialist agents
def diagnose_replication(alert):
    return f'Replication diagnosis: Check pg_stat_replication on primary. Run: SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;'

def diagnose_performance(alert):
    return f'Performance diagnosis: Check pg_stat_statements. Run: SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;'

def diagnose_connection(alert):
    return f'Connection diagnosis: Check pg_stat_activity. Run: SELECT state, count(*) FROM pg_stat_activity GROUP BY state;'

replication_agent = Agent('Replication DBA', 'Handle replication alerts', [diagnose_replication])
performance_agent = Agent('Performance DBA', 'Handle performance alerts', [diagnose_performance])
connection_agent = Agent('Connection DBA', 'Handle connection alerts', [diagnose_connection])

# Triage agent decides who to hand off to
def triage(alert_text):
    text = alert_text.lower()
    if 'replication' in text or 'lag' in text or 'standby' in text:
        return Handoff(replication_agent)
    elif 'slow' in text or 'cpu' in text or 'performance' in text:
        return Handoff(performance_agent)
    elif 'connection' in text or 'refused' in text or 'max_connections' in text:
        return Handoff(connection_agent)
    else:
        return 'Unknown alert type - escalate to senior DBA'

triage_agent = Agent('Triage Lead', 'Route alerts to specialists', [triage])

# Simple Swarm runner
def run_swarm(agent, alert_text):
    print(f'[{agent.name}] Received: {alert_text[:60]}...')

    # Triage first
    result = agent.functions[0](alert_text)

    # If it is a handoff, follow it
    if isinstance(result, Handoff):
        specialist = result.agent
        print(f'[{agent.name}] Handing off to {specialist.name}')
        diagnosis = specialist.functions[0](alert_text)
        print(f'[{specialist.name}] {diagnosis}')
        return diagnosis
    else:
        print(f'[{agent.name}] {result}')
        return result

# Test
alerts = [
    'WARNING: Replication lag on standby-2 is 45 seconds',
    'CRITICAL: Slow queries detected, CPU at 95%',
    'ERROR: max_connections reached, new connections refused',
]

for alert in alerts:
    run_swarm(triage_agent, alert)
    print()
"
```

Expected output:

```
[Triage Lead] Received: WARNING: Replication lag on standby-2 is 45 seconds...
[Triage Lead] Handing off to Replication DBA
[Replication DBA] Replication diagnosis: Check pg_stat_replication on primary. Run: SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;

[Triage Lead] Received: CRITICAL: Slow queries detected, CPU at 95%...
[Triage Lead] Handing off to Performance DBA
[Performance DBA] Performance diagnosis: Check pg_stat_statements. Run: SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;

[Triage Lead] Received: ERROR: max_connections reached, new connections refused...
[Triage Lead] Handing off to Connection DBA
[Connection DBA] Connection diagnosis: Check pg_stat_activity. Run: SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
```

---

## Step 5: Framework Comparison - Which One to Pick

| Criteria | LangGraph | CrewAI | Swarm | Hand-Built |
|---|---|---|---|---|
| **Complexity** | Medium - state graphs | Medium - role-based | Low - just functions | Depends on you |
| **Best for** | Complex workflows with branching, loops, human-in-the-loop | Team-based collaboration, autonomous research | Simple handoff chains | Learning, full control |
| **State management** | Built-in checkpointing | Agent memory | Minimal (conversation only) | You build it |
| **Persistence** | SQLite, Postgres, Redis | Built-in memory | None | You build it |
| **LLM support** | Any (via LangChain) | OpenAI default, configurable | OpenAI only | Any |
| **Debugging** | Graph visualization, LangSmith tracing | Verbose logging | Print statements | Your logging |
| **Production ready** | Yes - used at scale | Yes - growing adoption | Experimental | If you test it |
| **Learning curve** | Moderate (graph concepts) | Low (intuitive roles) | Very low | High (build everything) |

### Decision Guide for DBAs

**Pick LangGraph when:**
- Your workflow has complex branching (different paths for different alert types)
- You need human-in-the-loop (DBA approval before running remediation)
- You need to pause and resume agent work (save state to PostgreSQL)
- You want to visualize the workflow as a diagram

**Pick CrewAI when:**
- You think of the problem as "a team working together"
- Each agent has a clear role and specialty
- You want agents to delegate work to each other autonomously
- You are building something like "a DBA team that handles incidents 24/7"

**Pick Swarm when:**
- Your workflow is a simple chain of handoffs
- You want the lightest possible approach
- You are prototyping and want to move fast
- Your agents do not need memory or persistence

**Pick hand-built when:**
- You need to understand exactly what is happening (learning)
- Your workflow is simple enough that a framework adds overhead
- You have unusual requirements frameworks do not cover
- You want zero dependencies

---

## Step 6: From Frameworks Back to Fundamentals

Every framework implements the same patterns you built in BUILD 01-04:

| Your Code (BUILD 01-04) | LangGraph | CrewAI | Swarm |
|---|---|---|---|
| Agent class with `run()` | Node function | `Agent()` with role/goal | Function |
| Message dict passing | `TypedDict` state | Task output chaining | Return values |
| if/elif routing | `add_conditional_edges` | `Process.hierarchical` | Handoff class |
| try/except with fallback | Retry policies | Error handling config | try/except |
| Circuit breaker | Timeout + fallback node | Task timeout | Manual |
| Orchestrator function | Entry point + graph edges | `Crew(process=)` | Runner function |

The frameworks save you time in production. But knowing the fundamentals means you can debug any framework, switch between them, and build custom solutions when no framework fits.

---

## What You Learned

| Concept | What It Means |
|---|---|
| LangGraph | State machine for agent workflows - nodes, edges, conditional routing |
| CrewAI | Role-based agent teams - agents with jobs, tasks, and collaboration |
| Swarm | Lightweight handoff pattern - functions that transfer to other functions |
| When to use each | Complex branching = LangGraph, team collaboration = CrewAI, simple chains = Swarm |
| Frameworks vs hand-built | Frameworks are Patroni; hand-built is shell scripts. Same logic, different packaging |
