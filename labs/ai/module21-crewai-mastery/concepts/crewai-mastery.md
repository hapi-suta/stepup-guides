# Concepts: CrewAI Mastery

## What Is CrewAI?

CrewAI is a framework for building teams of AI agents that collaborate to solve problems. Instead of one LLM doing everything, you assemble specialists - each with a defined role, goal, and set of tools - and orchestrate them through tasks.

**DBA analogy:** CrewAI is to AI agents what an on-call roster is to a DBA team. You don't have one person handle every incident. You have a triage lead, a performance specialist, a replication expert, and a storage engineer. Each knows their domain deeply. CrewAI lets you build the same structure with AI agents.

---

## Core Architecture

```
                    CrewAI Architecture
                    ===================

  +------------------+     +------------------+
  |  Agent           |     |  Agent           |
  |  - role          |     |  - role          |
  |  - goal          |     |  - goal          |
  |  - backstory     |     |  - backstory     |
  |  - tools[]       |     |  - tools[]       |
  |  - llm           |     |  - llm           |
  +--------+---------+     +--------+---------+
           |                         |
           v                         v
  +------------------+     +------------------+
  |  Task            |     |  Task            |
  |  - description   |     |  - description   |
  |  - expected_output|    |  - expected_output|
  |  - agent         |     |  - agent         |
  |  - context[]     |     |  - context[]     |
  |  - callback      |     |  - callback      |
  +--------+---------+     +--------+---------+
           |                         |
           +----------+--------------+
                      |
                      v
             +------------------+
             |  Crew            |
             |  - agents[]      |
             |  - tasks[]       |
             |  - process       |
             |  - memory        |
             |  - verbose       |
             +--------+---------+
                      |
                      v
               crew.kickoff()
                      |
                      v
                  Result
```

---

## Agent Lifecycle

When an agent receives a task, it goes through this loop:

```
1. Read the task description
2. Consider role, goal, backstory
3. Check available tools
4. Think: "What should I do?"
5. Decide: use a tool OR write a response OR delegate
6. If tool: call tool, get result, go back to step 4
7. If response: return the task output
8. If delegate: pass to another agent
```

**DBA analogy:** This is exactly how a DBA works an incident:

```
1. Read the alert (PagerDuty notification)
2. Remember who you are (performance specialist)
3. Check your tools (psql, top, iostat, pg_stat_activity)
4. Think: "What should I check first?"
5. Decide: run a diagnostic query OR write findings OR escalate
6. If query: run it, read results, think again
7. If findings: write the report
8. If escalate: hand off to another team member
```

---

## The Three Building Blocks

### Agent

An Agent is a specialist with an identity. The identity shapes how the LLM responds.

| Agent Property | What It Does | DBA Analogy |
|---------------|-------------|-------------|
| `role` | Job title - shapes the persona | "Senior Performance DBA" on your badge |
| `goal` | What success looks like | Your KPI: "reduce P99 query latency below 200ms" |
| `backstory` | Experience and context | Your resume: "10 years, 50+ clusters, expert in partitioning" |
| `tools` | Functions the agent can call | Your toolkit: psql, pgBadger, pg_stat_statements |
| `llm` | Which AI model to use | Your brain - some agents need a senior brain (GPT-4), others a junior one (GPT-4o-mini) |
| `allow_delegation` | Can hand off to other agents | Whether you can escalate to a colleague |
| `max_iter` | Maximum thinking loops | How long before you stop investigating and report what you have |
| `verbose` | Show reasoning | Like SET log_min_messages = DEBUG1 |

### Task

A Task is a specific piece of work assigned to an agent.

| Task Property | What It Does | DBA Analogy |
|--------------|-------------|-------------|
| `description` | The actual work to do | Jira ticket body |
| `expected_output` | What a good result looks like | Definition of Done on the ticket |
| `agent` | Who does this task | Assignee |
| `context` | Other tasks whose output feeds in | "See ticket DBA-1233 for background" |
| `callback` | Function to call when done | Slack notification on ticket completion |

### Crew

A Crew is the team assembled to work through tasks.

| Crew Property | What It Does | DBA Analogy |
|--------------|-------------|-------------|
| `agents` | List of specialists | Your on-call roster |
| `tasks` | List of work items | Your incident runbook steps |
| `process` | How tasks execute | Runbook type: sequential or delegated |
| `memory` | Remember past runs | Team wiki / incident database |
| `verbose` | Show all agent reasoning | Debug logging |

---

## Process Modes

### Sequential Process

Tasks run one after another. Output of task N is available to task N+1.

```
Task 1 (Triage) --> Task 2 (Investigate) --> Task 3 (Fix)
     |                    |                      |
  Triage Lead        Perf DBA               Remediation DBA
```

**When to use:** Most incident response workflows. When each step depends on the previous one. Like a runbook.

**DBA analogy:** A standard incident runbook:
1. Triage the alert (severity + category)
2. Investigate the root cause (diagnostic queries)
3. Fix the issue (remediation steps)

### Hierarchical Process

A manager agent receives all tasks and delegates to workers.

```
                Manager Agent
               /      |       \
         Perf DBA  Repl DBA  Storage DBA
```

**When to use:** When you don't know in advance which specialist should handle the work. The manager decides at runtime.

**DBA analogy:** Lead DBA on a war room call. They listen to the symptoms and say "Performance team, check the query plans. Replication team, check the lag. Storage team, check disk space."

---

## Memory Types

| Memory Type | Scope | What It Stores | DBA Analogy |
|------------|-------|---------------|-------------|
| **Short-term** | Within one crew run | Agent outputs, tool results | Working memory during an incident |
| **Long-term** | Across crew runs | Past task results | Team incident wiki |
| **Entity** | Across crew runs | Facts about specific things | Your mental model of each server |
| **Knowledge sources** | Loaded at startup | Documents, runbooks, past reports | Confluence documentation |

### How memory flows

```
Run 1: Agent handles replication lag on pg-primary
  -> Short-term: agent remembers its own steps within this run
  -> Long-term: final result stored for future runs
  -> Entity: facts about pg-primary stored (200 max_conn, r6g.4xlarge)

Run 2: Similar alert on pg-analytics
  -> Long-term: agent finds "similar to Run 1 - replication lag on pg-primary"
  -> Entity: agent knows pg-analytics is different (500 max_conn, r6g.8xlarge)
  -> Agent response: "This is similar to the incident on pg-primary. Same fix should work."
```

---

## Tool Integration

Tools give agents the ability to DO things. Without tools, agents can only think and write.

```
Agent WITHOUT tools:
  "I recommend checking pg_stat_replication..."
  (suggests what to do, but can't actually do it)

Agent WITH tools:
  *calls check_replication() tool*
  "I checked pg_stat_replication and found lag of 45 seconds.
   The WAL receiver is 50MB behind. Here's the fix..."
  (actually runs the check, then recommends based on real data)
```

### Tool safety hierarchy

| Safety Level | What's Allowed | DBA Analogy |
|-------------|---------------|-------------|
| Read-only tools | SELECT queries, log reading, metric collection | GRANT SELECT role |
| Controlled write | Kill queries, change GUCs, vacuum | GRANT EXECUTE on specific functions |
| Full access | DDL, DROP, configuration changes | superuser (NEVER in production AI agents) |

**Rule:** Start with read-only tools. Add write capabilities one at a time, with human approval gates.

---

## Deployment Patterns

### Pattern 1: Alert-triggered crew

```
PagerDuty alert --> webhook --> CrewAI crew --> Slack response
```

The crew runs when an alert fires. It triages, investigates, and posts findings to Slack. A human decides whether to act on the recommendations.

### Pattern 2: Scheduled crew

```
Cron job (daily) --> CrewAI crew --> Health report --> Email
```

The crew runs on a schedule. It generates health reports, capacity forecasts, or compliance audits.

### Pattern 3: Pipeline crew (Flow)

```
Alert --> Triage Crew --> Investigate Crew --> Fix Crew --> PostMortem Crew
```

Multiple crews chained together. Each crew's output feeds the next. If any stage fails, the pipeline stops and alerts the human.

---

## Comparison to Other Frameworks

| Feature | CrewAI | LangGraph | AutoGen | Raw LLM Calls |
|---------|--------|-----------|---------|---------------|
| Multi-agent | Yes (core feature) | Yes (graph-based) | Yes (conversation) | Manual |
| Task dependencies | Built-in context | Manual edge definitions | Manual | Manual |
| Memory | Built-in (4 types) | Manual (checkpointer) | Manual | Manual |
| Tools | @tool decorator | @tool decorator | Function definitions | Function calling |
| Process modes | Sequential + Hierarchical | Custom graphs | Round-robin + custom | N/A |
| Learning curve | Low | Medium | Medium | N/A |
| Best for | Team-based workflows | Complex state machines | Agent conversations | Simple tasks |

**When to choose CrewAI:**
- You think in terms of "team of specialists working a runbook"
- Your workflow is sequential or delegated (not a complex graph)
- You want built-in memory without building it yourself
- Your team is familiar with the concept of roles, tasks, and crews

**When NOT to choose CrewAI:**
- You need complex branching logic (use LangGraph)
- You need agents to have extended conversations with each other (use AutoGen)
- You need sub-10ms latency (use direct API calls with caching)
- Your task is simple enough for a single LLM call (don't over-engineer)

---

## Key Design Principles

1. **Specificity over generality.** Agents with specific roles ("Replication DBA with 10 years experience in WAL management") perform better than generic ones ("Database specialist"). Just like hiring - you want the expert, not the generalist.

2. **Explicit over implicit.** Use `context` to explicitly wire task dependencies. Don't rely on agents figuring out the flow. Like a runbook - spell out every step and dependency.

3. **Read-only first.** Start with read-only tools. Add write capabilities gradually. Like giving a new DBA SELECT access before superuser.

4. **Test like production.** Run your crew against known alerts with known answers. If the crew's response doesn't match the expected fix, debug the agent roles and backstories.

5. **Cost is proportional to agents.** More agents = more API calls = more cost. Start with 2 agents and add only when quality gaps appear. Like database indexes - add when needed.

---

## Prerequisites for This Module

- Python 3.10+
- `pip3 install crewai crewai-tools`
- An API key (OpenAI or Anthropic)
- Completion of Module 20 (Agentic AI Foundations) is recommended but not required
