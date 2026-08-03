# Interview 01: Production Agent System Questions

---

## Question 1: What is MCP and how does it standardize tool access for AI agents?

**What they're asking:** Do you understand the protocol that connects AI to external tools?

**Answer:**

MCP (Model Context Protocol) is an open standard that defines how AI models discover and call tools on external systems. Instead of each AI tool building its own custom integration, MCP provides a single protocol that any compliant client and server can use.

The architecture has three parts:
- **MCP Server** - exposes tools with names, descriptions, and typed parameters
- **MCP Client** - the AI model that connects, discovers tools, and calls them
- **Transport** - the communication channel (stdio for local, HTTP/SSE for remote)

The flow:
1. Server starts and registers tools (e.g., `check_connections(database)`, `get_slow_queries(min_ms)`)
2. Client connects and asks "what tools do you have?"
3. Server responds with a structured list including parameter schemas
4. Client picks a tool, sends parameters, gets results
5. Client uses results to inform its response

Why this matters for production:
- **Standardization** - build your DBA tools once, use them with Claude, VS Code Copilot, or any MCP client
- **Discoverability** - the AI can see what tools are available without hardcoding
- **Type safety** - parameters have types and descriptions, reducing errors
- **Separation of concerns** - the MCP server handles database access, the AI handles reasoning

**DBA parallel:** MCP is to AI tools what the PostgreSQL wire protocol is to database clients. Any client that speaks the wire protocol (psql, pgAdmin, DBeaver, psycopg) can connect to any PostgreSQL server. You don't write a new driver for each combination. MCP does the same for AI - build your tool server once, any MCP client can use it.

---

## Question 2: How would you integrate a DBA agent with PagerDuty, Slack, and Jira?

**What they're asking:** Can you build resilient external service integrations?

**Answer:**

The integration follows a severity-based routing pattern:

```
Alert arrives -> Agent diagnoses -> Route by severity:
  P1 (CRITICAL): PagerDuty + Slack + Jira
  P2 (WARNING):  Slack + Jira
  P3 (INFO):     Slack only
  OK:            Log only
```

**PagerDuty integration:**
- Use the Events API v2 (POST to `/v2/enqueue`)
- Include a `dedup_key` so the same alert doesn't create duplicate incidents
- Set severity, source, component, and custom_details with the diagnosis
- Support both `trigger` and `resolve` actions so the agent can auto-resolve

**Slack integration:**
- Use incoming webhooks (POST to the webhook URL with JSON)
- Format messages using Block Kit for structured display
- Include: severity emoji, database name, diagnosis, recommended action
- Use different channels for different severity levels (#dba-critical vs #dba-info)

**Jira integration:**
- Use REST API v3 (POST to `/rest/api/3/issue`)
- Map severity to Jira priority (P1 = Highest, P2 = High, etc.)
- Include structured description: database, diagnosis, recommendation, runbook link
- Add labels for filtering: `dba-agent`, `auto-created`, severity level

**Critical design patterns for all integrations:**
1. **Retry with exponential backoff** - try 3 times with 1s, 2s, 4s delays
2. **Fallback chain** - if PagerDuty is down, fall back to Slack, then email, then local file
3. **Circuit breaker** - after 3 consecutive failures, skip the service for 30s
4. **Timeout** - every API call has a 10s timeout, never wait indefinitely
5. **Idempotency** - use dedup keys so retries don't create duplicates

**DBA parallel:** This is exactly how a production monitoring stack works today. Nagios sends emails, PagerDuty pages, Grafana dashboards update. The agent replaces the static threshold logic ("connections > 180 = page") with intelligent diagnosis ("connections are high because reporting_app is leaking - here's the fix"). Same notification channels, smarter content.

---

## Question 3: Design a feedback loop that improves agent accuracy over time.

**What they're asking:** Can you build a learning system with quality controls?

**Answer:**

The feedback loop has five stages:

**Stage 1: Collection**
After each diagnosis, the DBA rates it:
- `correct` - agent got it right (reinforce the pattern)
- `wrong` - agent was wrong, DBA provides the real answer (store correction)
- `partial` - agent was close but missed something (store refinement)

**Stage 2: Storage**
Each feedback record stores:
- Original alert text and keywords
- Agent's classification and diagnosis
- DBA rating and correction
- Reviewer name and expertise level
- Timestamp

**Stage 3: Retrieval**
When a new alert arrives, the agent searches past feedback for similar alerts using keyword overlap (simple) or vector similarity (advanced). If a past correction exists, the agent uses it instead of its default rules.

**Stage 4: Quality controls** (critical for safety)
- **Reviewer weighting** - senior DBA corrections count 3x more than junior ones
- **Consensus requirement** - corrections need 2+ reviewers to agree before being accepted
- **Per-category accuracy tracking** - monitor accuracy for each alert type separately
- **Rollback capability** - if accuracy drops for a category, roll back recent corrections
- **Expiration** - old corrections auto-expire after 90 days unless refreshed

**Stage 5: Measurement**
Track accuracy over time windows (weekly) and per category:
- Overall accuracy trend (should go up)
- Per-category accuracy (catch poisoning early)
- Feedback volume (are DBAs actually providing feedback?)
- Correction-to-acceptance ratio (how often is the agent wrong?)

**DBA parallel:** This is PostgreSQL's autovacuum feedback loop applied to AI. Autovacuum processes a table, measures the result (dead tuples remaining), and adjusts next time. The quality controls are like `pg_hba.conf` (who can provide feedback), quorum for Patroni failover (consensus), per-table stats (per-category tracking), and PITR (rollback).

---

## Question 4: What metrics would you track for a production DBA agent?

**What they're asking:** Can you build proper observability for AI systems?

**Answer:**

Six metric categories, each with a PostgreSQL analogy:

**1. Performance metrics**
- Average response time per alert (like `mean_exec_time` in `pg_stat_statements`)
- p95 latency (like `max_exec_time` for capacity planning)
- Tool call count and duration (like `calls` and `total_exec_time` per function)
- Queue depth - alerts waiting to be processed (like active queries in `pg_stat_activity`)

**2. Accuracy metrics**
- Overall accuracy percentage (like cache hit ratio)
- Per-category accuracy (like per-table cache hit ratio)
- Accuracy trend over time (is the agent improving or degrading?)
- Feedback-augmented vs rule-based accuracy comparison

**3. Cost metrics**
- Token usage per alert (like `shared_blks_read` per query)
- Cost per alert in dollars (like I/O cost in `EXPLAIN`)
- Cost by agent (which agent is most expensive?)
- Cost by alert type (which alerts cost most to process?)
- Monthly cost projection at current volume

**4. Error metrics**
- Error rate (like `xact_rollback / (xact_commit + xact_rollback)`)
- Errors by type (API failure, timeout, model error, tool error)
- Error trend (spike detection)
- Mean time to recovery after errors

**5. Health metrics**
- Circuit breaker states for each external service
- Notification delivery success rate per channel
- Agent uptime and restart count
- Memory and CPU usage of the agent process

**6. Business metrics**
- Alerts processed per day/hour
- Mean time from alert to notification (how fast does the DBA get paged?)
- Mean time from alert to resolution (end-to-end effectiveness)
- False positive rate (how often does the agent page for nothing?)

**Anomaly detection thresholds:**
- Token usage > 3x historical average = possible prompt injection or runaway context
- Error rate > 20% in 5 minutes = downstream service failure
- Latency > 2x normal = model endpoint degradation
- Category accuracy < 70% = possible feedback poisoning

**DBA parallel:** This is `pg_stat_database` + `pg_stat_statements` + `pg_stat_bgwriter` for your agent. You already monitor these for PostgreSQL - the agent needs the same level of visibility. If you would not run a production database without `pg_stat_statements`, you should not run a production agent without equivalent observability.

---

## Question 5: How would you deploy and scale an agent system that handles 1000 alerts/day?

**What they're asking:** Can you architect a production-grade agent system?

**Answer:**

**Deployment stages:**

1. **Shadow mode (week 1-2)** - Agent processes real alerts in parallel with the existing system. Agent output is logged but not acted on. A human reviews every diagnosis for accuracy.

2. **Canary (week 3-4)** - Agent handles 10% of alerts (every 10th alert). Existing system handles the other 90%. Compare accuracy and response time.

3. **Gradual rollout (week 5-8)** - Increase to 25%, 50%, 75%, 100% over four weeks. Roll back if accuracy drops below 85% at any stage.

4. **Full production** - Agent handles all alerts. Human override always available. One-click kill switch to revert to manual mode.

**Architecture for 1000 alerts/day:**

```
Ingest Layer:
  Webhook receiver -> Message queue (Redis or SQS)
  Rate: ~42 alerts/hour, ~0.7/minute

Processing Layer:
  Worker pool: 3-5 agent workers pulling from the queue
  Each worker processes alerts independently
  Circuit breakers on all external APIs
  Token budget per alert: 2000 tokens max

Notification Layer:
  PagerDuty, Slack, Jira with fallback chains
  Dedup by alert fingerprint (prevent duplicate pages)
  Rate limiting: max 10 pages/hour (prevent alert storms)

Feedback Layer:
  Web UI for DBA ratings
  Consensus pipeline for corrections
  Per-category accuracy dashboard

Observability Layer:
  Structured JSON logs -> log aggregator
  Metrics -> time-series database (Prometheus)
  Dashboard -> Grafana with alert rules
```

**Cost estimate at 1000 alerts/day:**

| Component | Cost |
|-----------|------|
| Classification (gpt-4o-mini, ~400 tokens/alert) | $0.06/day |
| Diagnosis (gpt-4o-mini, ~1000 tokens/alert, P1/P2 only, ~200/day) | $0.12/day |
| Remediation (gpt-4o-mini, ~1200 tokens/alert, CRITICAL only, ~50/day) | $0.04/day |
| **Total model cost** | **~$0.22/day ($6.60/month)** |

For complex diagnostics requiring a larger model (gpt-4o or Claude Sonnet), budget 10x more per call but only use it for P1 alerts.

**Scaling strategies:**
- **Model tiering** - cheap model for classification, expensive model only for P1 diagnosis
- **Caching** - if the same alert pattern appeared in the last hour, reuse the cached diagnosis
- **Early exit** - if all metrics are within normal range, skip diagnosis entirely
- **Batch dedup** - if 50 "high connections" alerts arrive in 5 minutes, diagnose once and apply to all

**DBA parallel:** This is the same architecture as a production database deployment.
- Shadow mode = read-only standby receiving real WAL
- Canary = traffic splitting with PgBouncer
- Worker pool = connection pooling with multiple backends
- Circuit breakers = PgBouncer health checks
- Kill switch = `pg_ctl stop -m immediate`
- Cost optimization = using read replicas for reporting instead of hitting the primary
