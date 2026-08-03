# Interview 01: Agentic AI Foundations

Five interview questions covering AI agents, async Python, safety, SDK differences, and agent architecture.

---

## Question 1: Chatbot vs AI agent

**Interviewer asks:**
"Explain the difference between a chatbot and an AI agent. When would you use each for database operations?"

**What they're testing:** Do you understand the fundamental distinction? Can you apply it to real DBA work?

**Strong answer:**

```
A chatbot is reactive - it answers questions when asked.
An AI agent is proactive - it observes, decides, and acts autonomously.

Key differences:

  Chatbot:
    - Stateless (each message is independent)
    - No tools (just generates text)
    - Waits for user input
    - Example: "What's the replication lag?" -> "2.3 seconds"

  Agent:
    - Stateful (remembers context and previous actions)
    - Has tools (can call functions, run queries, make API calls)
    - Runs autonomously on a schedule or trigger
    - Example: polls pg_stat_activity every 30s, detects a
      connection spike, investigates the cause, alerts the DBA
      with a diagnosis

When to use each for database operations:

  Chatbot: ad-hoc DBA queries
    - "Explain this EXPLAIN ANALYZE output"
    - "What index should I create for this query?"
    - "Is this pg_hba.conf entry correct?"

  Agent: continuous operations
    - Monitor fleet health 24/7
    - Detect and investigate anomalies
    - Triage alerts (classify, prioritize, route)
    - Capacity planning (trend analysis over time)

The agent loop is: observe -> think -> act -> remember.
A chatbot only does the "think" part when prompted.

DBA parallel: a chatbot is like psql (you type, it responds).
An agent is like pg_cron + monitoring + automated runbooks
(it runs continuously and takes action).
```

**DBA parallel:** Think of it as the difference between running ad-hoc queries in psql (chatbot) versus having a comprehensive monitoring system with automated responses (agent). Both are valuable, but they serve different purposes.

---

## Question 2: Async vs sync for database monitoring

**Interviewer asks:**
"When would you use async vs sync Python for database monitoring? What are the tradeoffs?"

**What they're testing:** Do you understand when async provides real benefits? Can you avoid over-engineering?

**Strong answer:**

```
Use async when you're I/O-bound - waiting for external responses.
Use sync when you're CPU-bound or the code is simple.

When async wins (I/O-bound):
  - Checking health of 100+ database servers concurrently
  - Making multiple API calls (LLM, monitoring endpoints)
  - Polling pg_stat_activity across a fleet
  - Fetching metrics from Prometheus for multiple targets

  Example: checking 100 servers
    Sync:  100 servers * 200ms each = 20 seconds
    Async: 100 servers concurrently = ~200ms
    That's a 100x speedup.

When sync is fine:
  - Monitoring a single database
  - CPU-heavy work (parsing large log files, training models)
  - Simple scripts that run once and exit
  - When the code complexity isn't worth the speedup

Tradeoffs:
  - Async code is harder to debug (stack traces are confusing)
  - Async requires all libraries to be async-compatible
  - Async has a learning curve (coroutines, event loop, gather)
  - Async bugs (like the thundering herd) can be devastating

  Rule of thumb: if you're checking fewer than 5 servers,
  sync is fine. If you're checking 10+, async is worth it.

The critical mistake with async: unbounded concurrency.
asyncio.gather() with 500 database connections will exhaust
max_connections. Always use a semaphore or connection pool
to limit concurrent connections.

  # WRONG - opens 500 connections at once
  await asyncio.gather(*[check(db) for db in all_500_dbs])

  # RIGHT - max 20 concurrent
  sem = asyncio.Semaphore(20)
  async def limited(db):
      async with sem:
          return await check(db)
  await asyncio.gather(*[limited(db) for db in all_500_dbs])
```

**DBA parallel:** Async is like PostgreSQL's async commit - you trade a small complexity increase for a massive performance gain on I/O-heavy workloads. Sync is like synchronous replication - simpler, safer, but slower when you have many targets.

---

## Question 3: Preventing dangerous AI agent actions

**Interviewer asks:**
"How do you prevent an AI agent from executing dangerous SQL on a production database? Walk me through your safety architecture."

**What they're testing:** Do you think about safety at multiple layers? Can you design defense-in-depth?

**Strong answer:**

```
Five layers of defense, from outermost to innermost:

Layer 1: Read-only database role
  CREATE ROLE agent_monitor LOGIN PASSWORD '...';
  GRANT CONNECT ON DATABASE prod TO agent_monitor;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_monitor;
  ALTER ROLE agent_monitor CONNECTION LIMIT 20;

  Even if every other layer fails, the database itself
  rejects writes. This is your last line of defense.

Layer 2: SQL allowlist (application layer)
  Only allow specific SQL statement types:
    ALLOWED = {"SELECT", "EXPLAIN", "SHOW"}
    BLOCKED = {"DROP", "DELETE", "TRUNCATE", "ALTER", "INSERT", "UPDATE"}

  Parse the first keyword of any SQL before execution.
  Reject anything not on the allowlist.

Layer 3: LLM output sanitization
  Never execute LLM-generated SQL directly.
  Extract SQL from the response, validate it against
  the allowlist, check for injection patterns (semicolons,
  comments with DROP, etc.).

  LLMs hallucinate. They will confidently suggest
  "DROP TABLE audit_log" as a disk space fix.

Layer 4: Human-in-the-loop for write operations
  If the agent determines a write action is needed:
    - Queue the recommendation for human review
    - Show what it WOULD do (dry run)
    - Wait for explicit approval
    - Log who approved it

  No autonomous write operations on production. Ever.

Layer 5: Audit logging
  Log every action with:
    - Timestamp
    - What was executed
    - Why (LLM reasoning)
    - Result
    - Who approved it (for writes)

  DBA parallel: like pgaudit. Every action is recorded.

The key principle: defense in depth.
Any single layer can have bugs. Multiple layers mean
an attacker (or hallucinating LLM) must defeat ALL of them.

In PostgreSQL terms:
  Layer 1 = pg_hba.conf + GRANT (network + permissions)
  Layer 2 = application input validation
  Layer 3 = parameterized queries (prevent injection)
  Layer 4 = change management process
  Layer 5 = pgaudit extension
```

---

## Question 4: OpenAI vs Anthropic tool calling

**Interviewer asks:**
"Compare OpenAI and Anthropic tool calling. When would you pick each for a DBA agent?"

**What they're testing:** Practical SDK knowledge. Can you make informed vendor decisions?

**Strong answer:**

```
Both support tool calling (function calling), but the APIs differ:

API Differences:

  Tool Definition:
    OpenAI:    {"type": "function", "function": {"name": ..., "parameters": ...}}
    Anthropic: {"name": ..., "input_schema": ...}
    (Anthropic is flatter, OpenAI is nested)

  Tool Call Detection:
    OpenAI:    response.choices[0].message.tool_calls (list)
    Anthropic: response.stop_reason == "tool_use" + content blocks

  Tool Result Return:
    OpenAI:    {"role": "tool", "tool_call_id": ..., "content": ...}
    Anthropic: {"role": "user", "content": [{"type": "tool_result", ...}]}
    (Anthropic puts tool results in user messages, not a special role)

When to pick each:

  OpenAI (gpt-4o-mini / gpt-4o):
    - High-volume routine monitoring (cheapest per call)
    - Simple tool chains (1-2 tools per interaction)
    - Speed-critical applications (generally faster responses)
    - When you need structured output (JSON mode is mature)
    - Cost-sensitive: gpt-4o-mini at $0.15/$0.60 per 1M tokens

  Anthropic (Claude Sonnet / Opus):
    - Complex diagnostic reasoning (extended thinking)
    - Multi-step tool chains (3+ tools with conditional logic)
    - Safety-critical agents (Claude is better at refusing bad actions)
    - When you need to see the reasoning (extended thinking)
    - When instructions need to be followed precisely

  Production pattern:
    Use BOTH. Route by complexity:
      Simple checks -> gpt-4o-mini (cheap, fast)
      Complex diagnosis -> Claude Sonnet (better reasoning)
      Safety-critical -> Claude (better at saying "no")

  The tool FUNCTIONS are identical between SDKs.
  Only the schema format and message flow differ.
  Write your tools once, wrap them for both APIs.

DBA parallel: like choosing between pg_dump and pg_basebackup.
Both back up your database, but one is better for logical
backups (point-in-time flexibility) and the other for physical
backups (speed, simplicity). Know both, pick per situation.
```

---

## Question 5: Design an autonomous DBA agent architecture

**Interviewer asks:**
"Design an autonomous DBA agent that monitors a fleet of 100 PostgreSQL databases. What components do you need, and how do they interact?"

**What they're testing:** Systems thinking. Can you design a complete, production-grade agent?

**Strong answer:**

```
Architecture with 7 components:

1. ASYNC MONITOR (data collection)
   - Polls all 100 databases every 30 seconds
   - Uses asyncio with Semaphore(20) to limit concurrency
   - Uses connection pooling (asyncpg.create_pool, max=20)
   - Collects: pg_stat_activity, pg_stat_replication,
     pg_stat_statements, disk usage, connection counts
   - Pure Python, no LLM cost

2. ANOMALY DETECTOR (threshold engine)
   - Evaluates poll results against configurable thresholds
   - Connection usage > 80%, replication lag > 5s, etc.
   - Fast, deterministic, no LLM needed
   - Outputs: list of anomalies with severity and context

3. LLM ANALYST (the brain)
   - Only called when anomalies are detected (cost control)
   - Receives anomaly context + recent history
   - Decides which tools to call for investigation
   - Uses Claude Sonnet for complex reasoning
   - Uses gpt-4o-mini for simple routing decisions

4. TOOL REGISTRY (available actions)
   - Read tools: check_replication_lag, get_active_queries,
     get_lock_chains, get_table_bloat, check_index_usage
   - Write tools: kill_query, reload_config (require approval)
   - Each tool has: function, schema, safety classification

5. SAFETY LAYER (guardrails)
   - Read-only database roles (GRANT SELECT only)
   - SQL allowlist (only SELECT, EXPLAIN, SHOW)
   - Semaphore for write operations (max 3 per cycle)
   - Human-in-the-loop for destructive actions
   - Rate limiting on LLM calls (max 10/minute)

6. MEMORY & STATE (persistence)
   - Conversation history (last N interactions)
   - Action log (what was done and why)
   - Known issues tracker (deduplication)
   - State file (survives restarts, like pg_control)
   - Metrics over time (trend detection)

7. NOTIFICATION SYSTEM (output)
   - Slack/PagerDuty for critical alerts
   - Email digest for daily summaries
   - Dashboard for real-time status
   - Audit log for compliance

Data flow:
  Monitor -> Detector -> [anomalies?] -> LLM -> Tools -> Logger
                                     -> [no anomalies] -> sleep 30s

Cost management:
  - Anomaly detection is free (pure Python)
  - LLM called only for anomalies (~5-10 calls/hour)
  - gpt-4o-mini for routing (~$0.001/call)
  - Claude Sonnet for diagnosis (~$0.01/call)
  - Estimated: $5-20/day for 100 databases

Scaling:
  - Horizontal: run multiple agent instances, each monitoring
    a subset of databases (shard by datacenter)
  - Vertical: increase semaphore/pool size for more concurrency
  - Cost: add caching for repeated anomalies (don't re-analyze)

The key insight: the LLM is the most expensive component,
so you minimize its usage. Pure Python handles 95% of the
work (polling, thresholds). The LLM only gets involved for
the 5% that requires reasoning.

DBA parallel: this is your monitoring stack reimagined.
  Monitor = Prometheus node_exporter + postgres_exporter
  Detector = Alertmanager rules
  LLM = The senior DBA's brain
  Tools = Your psql toolkit
  Safety = pg_hba.conf + role permissions
  Memory = Incident management system (PagerDuty/Jira)
  Notifications = Slack + PagerDuty
```

**DBA parallel:** The best agent architecture mirrors what a well-run DBA team already does - continuous monitoring, threshold-based alerting, expert investigation when needed, strict change management, and complete audit trails. The AI agent automates the investigation and triage steps, not the decision to make production changes.
