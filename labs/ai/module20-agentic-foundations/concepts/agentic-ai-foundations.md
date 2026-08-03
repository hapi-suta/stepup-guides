# Agentic AI Foundations & Async Python - Concepts

You've built classifiers, pipelines, multi-agent systems, and shipped a product. Now it's time to build real AI agents - autonomous programs that observe, think, and act in a loop. And to make them fast, you need async Python.

---

## What "Agentic AI" Really Means

A chatbot answers questions. An agent takes actions.

| Chatbot | Agent |
|---------|-------|
| You ask, it answers | It observes, decides, acts |
| Stateless (each message is independent) | Stateful (remembers what it did) |
| No tools | Has tools (functions it can call) |
| Waits for you | Runs autonomously |
| Like `psql` (you type queries, it responds) | Like `pg_cron` + monitoring (runs on its own, takes action) |

**DBA analogy:** A chatbot is like running `psql` - you ask questions, it answers. An agent is like a combination of `pg_cron`, `pg_stat_activity` monitoring, and automated runbooks - it watches the database, detects problems, decides what to do, and acts.

An AI agent has three core capabilities:
1. **Observe** - gather information (read pg_stat_activity, check disk space, query metrics)
2. **Think** - analyze what it sees (is this a problem? what's the root cause? what should I do?)
3. **Act** - take action (alert the DBA, kill a query, add an index, scale resources)

---

## The Agent Loop

Every agent runs the same fundamental loop:

```
while True:
    observation = observe()      # What's happening?
    thought = think(observation) # What should I do?
    action = act(thought)        # Do it
    memory.append(action)        # Remember what I did
```

**DBA analogy:** This is exactly how an experienced DBA monitors a database:

```
while on_call:
    check pg_stat_activity        # observe
    "hmm, 50 blocked queries"     # think
    find and kill blocking query   # act
    write incident note            # remember
```

The difference with AI agents: the "think" step uses an LLM (like GPT-4 or Claude) instead of a human brain. The LLM decides which tools to call and what arguments to pass.

---

## Async Programming Mental Model

### Why Async Matters

Imagine you're a DBA checking 10 database servers. Synchronous approach:

```
Check server 1 (wait 2 seconds for response)
Check server 2 (wait 2 seconds for response)
Check server 3 (wait 2 seconds for response)
...
Check server 10 (wait 2 seconds for response)
Total: 20 seconds
```

Async approach:

```
Send check to all 10 servers at once
Wait for all responses
Total: ~2 seconds
```

**DBA analogy: async commit.** In PostgreSQL, synchronous commit waits for WAL to flush to disk before confirming the transaction. Async commit confirms immediately and lets the WAL flush happen in the background. You trade a tiny risk for massive speed improvement.

```
-- Synchronous: wait for WAL flush (safe but slow)
SET synchronous_commit = on;

-- Asynchronous: don't wait (fast but tiny data loss risk)
SET synchronous_commit = off;
```

Async Python works the same way - don't block waiting for I/O. Start the operation, do other work, come back when it's ready.

### The Event Loop

The event loop is the core of async Python. It manages all your concurrent tasks, deciding which one runs when.

**DBA analogy: pg_stat_activity.** PostgreSQL's backend process manager is like an event loop. It manages hundreds of concurrent connections, switching between them as needed:

```sql
-- PostgreSQL manages many concurrent connections
SELECT pid, state, query FROM pg_stat_activity;

 pid  | state  | query
------+--------+---------------------------
 1234 | active | SELECT * FROM orders...
 1235 | idle   | (waiting for next query)
 1236 | active | UPDATE inventory...
 1237 | idle in transaction | (waiting)
```

The event loop does the same thing for your Python code - it tracks which tasks are waiting for I/O, which are ready to run, and switches between them efficiently.

---

## Coroutines vs Threads vs Processes

Python has three ways to do concurrent work. Each maps to a PostgreSQL concept:

| Python | PostgreSQL Analogy | When to Use |
|--------|-------------------|-------------|
| **Coroutines** (async/await) | Connection pooling via PgBouncer - one process handles many connections by switching between them | I/O-bound work (HTTP calls, database queries, file reads) |
| **Threads** (threading) | PostgreSQL backend processes - separate threads sharing the same memory | I/O-bound work with libraries that don't support async |
| **Processes** (multiprocessing) | Separate PostgreSQL instances on different ports - full isolation | CPU-bound work (data crunching, model training) |

### Why Coroutines Win for Agents

AI agents are almost entirely I/O-bound:
- Calling LLM APIs (network I/O) - waiting 1-5 seconds per call
- Querying databases (network I/O) - waiting 10-500ms per query
- Reading files (disk I/O) - waiting 1-10ms per read
- Calling monitoring APIs (network I/O) - waiting 100-2000ms per call

The actual computation (parsing responses, making decisions) takes microseconds. You spend 99% of the time waiting for I/O. Coroutines let you do other work during that wait.

**DBA analogy:** PgBouncer handles 10,000 connections with a single process because most connections are idle - waiting for the application to send the next query. Similarly, async Python handles thousands of concurrent API calls because most are idle - waiting for the response to come back.

---

## OpenAI vs Anthropic SDK Differences

Both OpenAI and Anthropic offer tool calling (function calling), but the patterns differ:

### OpenAI Flow
```
1. You send: messages + tool definitions
2. Model responds: "I want to call tool X with args Y"
   (response has tool_calls array)
3. You execute: tool X with args Y, get result
4. You send: tool result as a "tool" role message
5. Model responds: final answer using the tool result
```

### Anthropic Flow
```
1. You send: messages + tool definitions
2. Model responds: content blocks including tool_use blocks
   (response has content array with type: "tool_use")
3. You send: tool_result content block in a "user" message
4. Model responds: final answer using the tool result
```

Key differences:

| Aspect | OpenAI | Anthropic |
|--------|--------|-----------|
| Tool definition | `functions` or `tools` parameter | `tools` parameter |
| Tool call in response | `tool_calls` array on message | `tool_use` content block |
| Tool result format | Separate message with `role: "tool"` | `tool_result` content block in `role: "user"` |
| Multiple tools | Can call multiple tools in one response | Can call multiple tools in one response |
| Streaming | `stream=True` with SSE events | `stream=True` with SSE events |
| Thinking/reasoning | Not built-in (use system prompt) | `extended_thinking` parameter |

**DBA analogy:** Think of it like the difference between `pg_dump` and `pg_basebackup`. Both back up your database, but the flags, workflow, and output format are different. You need to know both because production environments use both.

---

## When to Use Async

Use async when your agent does I/O-bound work. That's most DBA automation tasks:

**Good for async (I/O-bound):**
- Checking health of multiple database servers
- Polling pg_stat_activity across a fleet
- Making LLM API calls
- Fetching metrics from Prometheus/Grafana
- Running queries against multiple databases
- Downloading WAL files from archive storage

**Not worth async (CPU-bound):**
- Training a machine learning model
- Parsing a 10GB log file locally
- Compressing backup files
- Computing checksums

**Rule of thumb:** If you're waiting for something external (network, disk, API), use async. If you're crunching data locally, use multiprocessing.

---

## The Agent Architecture

A production DBA agent has these components:

```
+------------------+
|   Agent Loop     |  <-- The brain: observe-think-act
+------------------+
        |
+------------------+
|   LLM Client     |  <-- OpenAI or Anthropic SDK (async)
+------------------+
        |
+------------------+
|   Tool Registry   |  <-- Available tools the agent can call
+------------------+
        |
+-------+----------+----------+----------+
|       |          |          |          |
| check | get      | kill     | analyze  |
| health| queries  | query    | explain  |
+-------+----------+----------+----------+
        |
+------------------+
|   Memory / State  |  <-- What it's seen and done
+------------------+
        |
+------------------+
|   Safety Layer    |  <-- Read-only by default, confirm writes
+------------------+
```

**DBA analogy:** This is like your monitoring stack:
- Agent Loop = your on-call brain
- LLM Client = your experience and knowledge
- Tool Registry = your toolkit (psql, pg_top, pg_stat_statements)
- Memory = your incident log
- Safety Layer = your change management process (no production changes without approval)

---

## What You'll Build in This Module

| BUILD | What | Skills |
|-------|------|--------|
| 01 | Async Python for Agents | async/await, asyncio.gather(), aiohttp, async context managers |
| 02 | OpenAI Agent SDK | Chat completions, tool calling, agent loop, structured outputs |
| 03 | Anthropic Agent SDK | Messages API, tool_use, extended thinking, SDK comparison |
| 04 | Autonomous DBA Agent | Full agent combining async + SDK + tools + safety + memory |

By the end, you'll have a working autonomous DBA agent that monitors PostgreSQL, detects anomalies, decides what to do, and logs its reasoning - all running asynchronously for maximum performance.
