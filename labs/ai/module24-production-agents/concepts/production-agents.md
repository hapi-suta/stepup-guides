# Module 24 - Production Agent Systems: Core Concepts

## What Are Production Agent Systems?

A production agent system is an AI agent that runs continuously in a real environment, processing alerts, calling external APIs, learning from feedback, and being monitored for health. It is the difference between a one-off Python script and a PostgreSQL server running 24/7.

**DBA analogy:** Think of the difference between running a manual `pg_dump` command and having a fully automated backup system with scheduling, monitoring, alerting, and retention policies. Building an agent is easy. Running it in production - reliably, safely, affordably - is the hard part.

---

## MCP (Model Context Protocol)

### What Is MCP?

MCP is an open standard protocol that lets AI models discover and call tools on external systems. It defines how a client (the AI) asks "what tools do you have?" and how a server responds with a structured list of callable functions.

**DBA analogy:** MCP is to AI tools what the PostgreSQL wire protocol is to database clients. Any client that speaks the wire protocol - psql, pgAdmin, DBeaver, Python/psycopg - can connect to any PostgreSQL server. MCP does the same thing: any AI client that speaks MCP can connect to any MCP server.

### MCP Architecture

| Component | Role | DBA Analogy |
|-----------|------|-------------|
| **MCP Server** | Exposes tools with names, descriptions, and parameter schemas | PostgreSQL server exposing stored procedures |
| **MCP Client** | Discovers and calls tools | psql client running `\df` then calling functions |
| **Transport** | Communication channel (stdio, HTTP, SSE) | PostgreSQL wire protocol over TCP |
| **Tool** | A callable function with typed parameters | A stored procedure with defined parameters |

### MCP Flow

```
1. Server starts, registers tools
2. Client connects: "What tools do you have?"
3. Server responds: [check_connections(db), get_slow_queries(ms), ...]
4. Client decides to call: check_connections("production")
5. Server executes the function, returns the result
6. Client uses the result to inform its response
```

This is the same discover-then-call pattern that `\df` + `SELECT function_name()` follows in psql.

---

## API Integration Patterns

### Why Agents Need APIs

An agent that can diagnose but cannot communicate is like a monitoring system with alerting disabled. The agent must:
- **Notify:** Post to Slack, page via PagerDuty, send email
- **Record:** Create Jira tickets, update status pages
- **Query:** Fetch metrics from CloudWatch, Prometheus, or monitoring APIs
- **Act:** Call webhooks, trigger runbooks, create tickets

**DBA analogy:** Your existing monitoring stack already does this. Nagios sends emails. PagerDuty pages. Grafana dashboards query Prometheus. The agent replaces the static threshold logic with intelligent diagnosis, but uses the same notification channels.

### Integration Architecture

```
Agent Pipeline:
  Alert arrives
    |
    v
  [Diagnose] - classify severity, find root cause
    |
    v
  [Route by severity]
    |
    +-- P1/P2: PagerDuty + Slack + Jira
    +-- P3:    Slack + Jira
    +-- P4:    Slack only
    +-- OK:    Log only
```

### Resilient API Calls

Every external API call must handle failure:

| Pattern | What It Does | DBA Analogy |
|---------|-------------|-------------|
| **Retry with backoff** | Try again after 1s, 2s, 4s | Backup script retrying after temp failure |
| **Fallback chain** | PagerDuty -> Slack -> email -> local file | Streaming replication with multiple standbys |
| **Circuit breaker** | After 3 failures, skip service for 30s | PgBouncer marking a backend as down |
| **Timeout** | Cancel after 10s if no response | `statement_timeout` in PostgreSQL |
| **Idempotency key** | Prevent duplicate notifications | Using a dedup key so the same alert is not paged twice |

---

## Feedback Loop Design

### Why Feedback Matters

An agent that never learns from corrections will repeat the same mistakes. Feedback loops let the agent adapt based on DBA expertise.

**DBA analogy:** PostgreSQL's autovacuum is a feedback loop. It processes a table, measures the result (dead tuples remaining), and adjusts its behavior next time (vacuum more or less aggressively). Your agent should work the same way.

### Feedback Loop Cycle

```
1. Alert arrives
2. Agent diagnoses and recommends
3. DBA rates: correct / wrong / partial
4. If wrong/partial: DBA provides the correct answer
5. Correction is stored with alert context
6. Next similar alert: agent retrieves past corrections
7. Agent delivers improved diagnosis
8. Accuracy tracked over time
```

### Feedback Quality Controls

Uncontrolled feedback is dangerous. A single wrong correction can poison the agent's behavior for an entire alert category.

| Control | Purpose | DBA Analogy |
|---------|---------|-------------|
| **Reviewer expertise weighting** | Senior DBA feedback counts more | `GRANT` levels - superuser vs regular user |
| **Consensus requirement** | Multiple reviewers must agree | Patroni quorum - 2-of-3 for failover |
| **Per-category accuracy tracking** | Detect poisoning in specific categories | Cache hit ratio per table, not just overall |
| **Feedback rollback** | Remove bad corrections and restore accuracy | PITR - roll back to a known-good state |
| **Feedback expiration** | Old corrections auto-expire | WAL retention policy - old data gets cleaned up |

---

## Agent Observability

### What to Monitor

| Metric | What It Tells You | DBA Analogy |
|--------|------------------|-------------|
| **Response time (avg, p95)** | Is the agent slow? | `mean_exec_time` in `pg_stat_statements` |
| **Error rate** | Is the agent failing? | `xact_rollback` in `pg_stat_database` |
| **Token usage** | How much is each alert costing? | `shared_blks_read` per query |
| **Tool call count** | Which tools are used most? | `calls` in `pg_stat_statements` |
| **Accuracy** | Is the agent getting smarter or dumber? | Cache hit ratio trending up or down |
| **Cost per alert** | Is the agent cost-effective? | I/O cost per query in `EXPLAIN` |
| **Queue depth** | Are alerts backing up? | `pg_stat_activity` active query count |

### Structured Logging

Every agent decision must be logged as a structured record (JSON) with:
- Timestamp
- Agent name
- Action taken
- Tool called
- Duration
- Input summary
- Output summary
- Success/failure

**DBA analogy:** This is the PostgreSQL CSV log format. Each field is a column. You can `COPY` the log into a table and query it with SQL.

### Anomaly Detection

Monitor for sudden changes in agent behavior:

| Anomaly | What It Means | Alert When |
|---------|--------------|------------|
| Token spike | Context window growing, prompt injection, or runaway loop | Recent avg > 3x historical avg |
| Latency spike | Model endpoint slow, or tool calls hanging | p95 > 2x normal |
| Error rate spike | Downstream API down, or model returning errors | Error rate > 20% in 5-minute window |
| Accuracy drop | Bad feedback, model degradation, or new alert patterns | Category accuracy < 70% |
| Cost spike | More alerts, more complex alerts, or model upgrade | Daily cost > 2x previous week avg |

---

## Deployment Strategies

### Development to Production

| Stage | Purpose | DBA Analogy |
|-------|---------|-------------|
| **Local testing** | Run against simulated data | Running queries on a dev database |
| **Shadow mode** | Agent processes real alerts but doesn't notify - human reviews output | Read-only standby - receives real data, no writes |
| **Canary deployment** | Agent handles 5% of alerts, rest go to existing system | Blue/green deployment with traffic splitting |
| **Full production** | Agent handles all alerts with human override available | Primary database accepting all traffic |

### Scaling Agents

| Pattern | When to Use | DBA Analogy |
|---------|------------|-------------|
| **Single agent** | < 100 alerts/day | Single PostgreSQL instance |
| **Worker pool** | 100-1000 alerts/day, independent processing | Connection pooling with multiple backends |
| **Specialized agents** | Different alert types need different expertise | Partitioned tables with per-partition indexes |
| **Async processing** | High volume, alerts can tolerate seconds of delay | Asynchronous replication - eventual consistency |

### Cost Optimization

| Technique | Savings | DBA Analogy |
|-----------|---------|-------------|
| **Model tiering** | Use cheap model for classification, expensive for diagnosis | Using a read replica for reporting queries |
| **Caching** | Cache repeated diagnoses for the same alert pattern | `pg_stat_statements` query plan caching |
| **Early exit** | Skip diagnosis for obvious OK alerts | Short-circuit evaluation in WHERE clauses |
| **Batch processing** | Group similar alerts and diagnose once | Batch INSERT vs row-by-row INSERT |
| **Token budgets** | Set per-alert token limits | `work_mem` limits per query |

---

## Key Takeaways

- MCP standardizes how AI tools are exposed and called - learn it once, use it everywhere
- Every external API call must have retry, fallback, timeout, and error handling
- Feedback loops make agents smarter, but uncontrolled feedback can poison them
- Agent observability is as important as database observability - you need pg_stat views for your agents
- Start in shadow mode, deploy gradually, monitor everything
- Cost optimization matters at scale - tier your models and cache repeated work
