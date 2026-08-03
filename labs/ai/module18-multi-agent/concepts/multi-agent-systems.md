# Module 18 - Multi-Agent Systems: Core Concepts

## What Are Multi-Agent Systems?

A multi-agent system is a group of AI agents that each handle a specific job, then pass results to each other to solve a bigger problem together.

**DBA analogy:** Think of your DBA team. You would not want one generalist DBA responsible for monitoring, capacity planning, query tuning, incident response, and reporting all at once. You split the work across specialists. Multi-agent AI works the same way - each agent is a specialist with a defined scope.

A single agent trying to do everything becomes:
- Slow (more context to process)
- Error-prone (instructions conflict)
- Hard to debug (where did it go wrong?)

A team of focused agents is faster, more accurate, and easier to maintain.

---

## Agent Architecture: Role, Tools, Memory

Every agent in a multi-agent system has three core components:

| Component | What It Means | DBA Analogy |
|-----------|--------------|-------------|
| **Role** | The agent's job description and instructions | A database role - defines what this agent IS responsible for |
| **Tools** | Functions the agent can call (APIs, scripts, queries) | GRANT statements - defines what the agent is ALLOWED to do |
| **Memory** | Context the agent carries across steps | A session variable or temp table - scratch space for the current task |

**DBA analogy for roles and tools:**

```
-- In PostgreSQL, you scope access by role:
CREATE ROLE monitor_agent;
GRANT SELECT ON pg_stat_activity TO monitor_agent;
GRANT SELECT ON pg_stat_bgwriter TO monitor_agent;
-- monitor_agent can READ metrics, nothing else

CREATE ROLE remediation_agent;
GRANT EXECUTE ON FUNCTION terminate_idle_connections() TO remediation_agent;
-- remediation_agent can ACT, but only within its scope
```

Same idea in multi-agent AI: each agent is granted only the tools it needs. An agent that reads metrics should not also have the ability to restart a server.

---

## Communication Patterns

How agents hand off work to each other follows recognizable patterns.

### Sequential (Pipeline)

Each agent finishes, then passes output to the next.

```
Monitor Agent -> Classifier Agent -> Diagnostics Agent -> Remediation Agent
```

**DBA analogy:** ETL pipeline. Extract finishes before Transform starts. Transform finishes before Load starts. Each stage depends on the previous one completing correctly.

- Use when: each step depends on the output of the last
- Risk: one slow or failed agent blocks the whole pipeline

---

### Parallel

Multiple agents work at the same time on different parts of the same problem.

```
                  -> Disk I/O Agent    \
Alert arrives ->  -> Memory Agent      -> Aggregator Agent -> Report
                  -> Connection Agent  /
```

**DBA analogy:** Running `EXPLAIN ANALYZE` while simultaneously checking `pg_stat_activity` and `pg_stat_bgwriter`. You gather all metrics at once rather than one at a time, then correlate them.

- Use when: tasks are independent and do not need each other's output to start
- Benefit: faster total wall-clock time

---

### Hierarchical (Orchestrator + Specialists)

An orchestrator agent receives the problem, decides which specialist agents to call, collects their responses, and produces a final answer.

```
                          -> Monitor Agent
Orchestrator (receives alert) -> Diagnostics Agent -> synthesizes -> Final recommendation
                          -> Reporting Agent
```

**DBA analogy:** A DBA team lead who triages an incident. The lead does not personally check every metric - they direct the on-call DBA to pull slow query logs, direct the storage admin to check disk, and direct the app team to check connection pools. The lead synthesizes all findings into the incident summary.

- Use when: the problem requires coordinating multiple specialists
- The orchestrator needs to be good at task decomposition, not just execution

---

## Agent Types for Database Management

A practical multi-agent setup for database operations would include:

| Agent | Job | Tools It Uses |
|-------|-----|---------------|
| **Monitor Agent** | Continuously watches metrics - connections, replication lag, disk, CPU, lock waits | Query pg_stat_* views, Prometheus API, CloudWatch |
| **Classifier Agent** | Reads an alert and categorizes it - performance, availability, replication, security | Pattern matching, alert history lookup |
| **Diagnostics Agent** | Given a category, finds the root cause - which query, which table, which session | EXPLAIN, pg_stat_activity, pg_locks, log parsing |
| **Remediation Agent** | Recommends or executes a fix - kill a query, add an index, resize a connection pool | pg_terminate_backend(), DDL scripts, runbook lookup |
| **Reporting Agent** | Writes the incident summary, trend reports, or capacity projections | Templating, historical data queries, formatting |

These agents can be wired together in any of the patterns above. A common real-world flow:

```
Monitor -> Classifier -> Diagnostics -> Remediation
                                     -> Reporting (runs in parallel with Remediation)
```

---

## Coordination Challenges

Multi-agent systems introduce problems you do not have with a single agent.

| Challenge | What Happens | DBA Analogy |
|-----------|-------------|-------------|
| **Conflicting recommendations** | Agent A says kill the long-running query; Agent B says it is a critical batch job - do not touch it | Two DBAs with different context giving opposite advice on the same session |
| **Resource contention** | Multiple agents querying the same heavy system views at the same time hammers the monitored database | Running 10 concurrent EXPLAIN ANALYZE on a prod primary during peak traffic |
| **Communication overhead** | Passing large result sets between agents slows everything down | Passing a 10MB slow query log through three pipeline stages instead of summarizing early |
| **Agent failure handling** | One agent crashes mid-pipeline - does the rest of the pipeline keep going or halt? | A step in your ETL fails silently and the load stage runs on incomplete data |

**How to handle these:**
- Define clear agent boundaries so their recommendations do not overlap
- Rate-limit how often monitoring agents hit production databases
- Pass summaries between agents, not raw data dumps
- Build explicit error handling - if an agent fails, the orchestrator must know and decide whether to retry, skip, or abort

---

## Single Agent vs. Multi-Agent: When to Use Each

| Situation | Use | Reason |
|-----------|-----|--------|
| Simple, one-step task | Single agent | Less overhead, easier to debug |
| Task requires 2-3 sequential steps | Single agent with tools | Chain-of-thought handles this fine |
| Task has parallel independent sub-tasks | Multi-agent | Saves time, each agent stays focused |
| Problem needs specialists with different tools | Multi-agent | Clean separation of concerns |
| Long-running autonomous monitoring | Multi-agent | Agents can run independently and escalate |
| You need auditability per step | Multi-agent | Each agent's input/output is logged separately |

**Rule of thumb:** If you can write a single clear system prompt that covers the whole task without it becoming 2,000 words of conflicting instructions, use a single agent. If you are writing "unless X, but if Y, however when Z" - split it into agents.

---

## Key Takeaways

- Multi-agent = team of specialists, not one overloaded generalist
- Each agent has a role (what it does), tools (what it can access), and memory (what it knows right now)
- Communication patterns - sequential, parallel, hierarchical - map directly to patterns DBAs already use in ETL, incident response, and team org structures
- The main risks are conflicting outputs, resource contention, and silent failures - all solvable with clear boundaries and explicit error handling
- Start with a single agent and split into multi-agent only when complexity demands it
