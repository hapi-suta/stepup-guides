# Concepts: Agent Safety & Guardrails

## What Is This Module?

You've built AI agents that can classify alerts, diagnose issues, and recommend fixes. Now you need to make them safe for production. An AI agent with database access is like a DBA with superuser privileges - powerful, but one mistake and you lose data.

This module teaches you to build the guardrails that prevent agents from doing damage, even when they receive malicious input, have bugs in their logic, or make bad decisions.

## The DBA Parallel

Every safety concept in this module has a direct PostgreSQL equivalent:

| Agent Safety Concept | PostgreSQL Equivalent | Purpose |
|---------------------|----------------------|---------|
| Input validation | Parameterized queries | Prevent injection attacks |
| Output filtering | Column-level GRANT | Control what data escapes |
| SQL safety checker | pg_hba.conf + GRANT | Control what can be executed |
| Rate limiting | connection limits, PgBouncer | Prevent resource exhaustion |
| Token budgets | statement_timeout | Cap cost per operation |
| Permission tiers | ROLE hierarchy | Least privilege access |
| Approval workflows | Four-eyes principle for DDL | Human oversight for risky actions |
| Audit logging | log_statement = 'all' | Record every decision |
| Multi-model fallback | Streaming replication failover | Redundancy and reliability |
| Model consensus | Comparing EXPLAIN plans | Cross-validation of decisions |
| Blast radius control | Schema-level isolation | Limit damage scope |

## Threat Model for AI Agents

When you give an AI agent access to a database, you create attack surfaces that don't exist in traditional automation:

### 1. Prompt Injection (The SQL Injection of AI)

An attacker embeds instructions in data that the agent processes. If the agent treats data as instructions, the attacker controls the agent.

**Attack vectors:**
- Malicious text in alert messages
- Crafted log entries that contain instructions
- Database records with embedded prompts
- Configuration values that double as instructions

**Defense:** Treat ALL external input as data, never as instructions. Validate before processing. Use separate agents for classification (reads data) and remediation (takes actions).

### 2. Over-Privileged Agents

An agent with more permissions than it needs is a liability. If compromised (via prompt injection or bugs), the blast radius is maximum.

**Attack vectors:**
- Agent with SUPERUSER running a simple monitoring check
- Read-only agent that also has EXECUTE on pg_terminate_backend
- Agent with access to all databases when it only needs one

**Defense:** Principle of least privilege. Create separate agents with separate roles. Monitor agent uses SELECT only. Ops agent gets specific EXECUTE grants. Admin agent requires human approval.

### 3. Model Hallucination Leading to Wrong Actions

AI models can generate confident but wrong recommendations. A model that says "run VACUUM FULL on the 500GB table during peak hours" sounds authoritative but will cause an outage.

**Defense:** Confidence scoring with evidence requirements. Safety checklists before execution. Require multiple signals before taking action. Never auto-execute remediation without validation.

### 4. Cost and Resource Exhaustion

An agent in a loop, or processing a massive input, can burn through API tokens or overwhelm your database with queries.

**Attack vectors:**
- Alert storm triggers thousands of API calls
- Agent retries indefinitely on a failing query
- Large log dump sent as a single prompt (costs $5+ per request)

**Defense:** Rate limiting. Token budgets per request and per hour. Circuit breakers that stop after N failures. Input size limits.

### 5. Data Leakage via Agent Output

The agent reads pg_hba.conf, .env files, connection strings, and query results. If it includes that data in its response (Slack message, log, API response), you have a data breach.

**Attack vectors:**
- Agent summarizes a config file including passwords
- Agent includes connection strings in diagnostic reports
- Agent logs query results containing PII

**Defense:** Output filtering with regex patterns for credentials, IPs, emails. Structured output schemas that only allow defined fields. Credential detection before any output is emitted.

## Input Validation Strategies

### Pattern-Based Detection

Check input text against known injection patterns. Fast, deterministic, and catches common attacks. Cannot catch novel attacks or obfuscated injections.

### Schema Validation

Define exact types, ranges, and allowed values for every tool input. Like CHECK constraints on agent inputs. Catches type mismatches and out-of-range values.

### Allowlists vs Denylists

- **Allowlist (recommended):** Define exactly what IS allowed. Everything else is blocked. Like PostgreSQL's default-deny permission model.
- **Denylist (supplement):** Define what is NOT allowed. Everything else passes. Like a blocklist of dangerous SQL patterns.

Best practice: Use allowlists as the primary defense, denylists as a supplementary layer.

## Output Filtering Strategies

### Credential Detection

Regex patterns that catch:
- Connection strings (postgresql://user:pass@host)
- Password fields (password = 'value')
- API keys (sk-xxx, AKIA-xxx)
- Internal IP addresses (10.x.x.x, 192.168.x.x)
- Email addresses (PII)
- SSH private keys
- JWT tokens

### Structured Output Enforcement

Force agent responses into a defined schema with:
- Required fields (like NOT NULL)
- Allowed values (like CHECK constraints)
- Maximum lengths (like VARCHAR(n))
- Type validation (like column data types)

### Confidence Scoring

Every recommendation includes a confidence score:
- 85-99%: HIGH - act on it
- 60-84%: MEDIUM - investigate first
- 40-59%: LOW - needs more data
- Below 40%: VERY LOW - treat as a guess

Confidence is based on evidence: metric data, log matches, historical patterns, multiple signals, recent changes.

## Multi-Model Strategies

### Model Routing

Route tasks by complexity:
- **Simple tasks** (classification, stats lookup): Fast/cheap model (Haiku)
- **Medium tasks** (diagnosis, query analysis): Balanced model (Sonnet)
- **Complex tasks** (root cause, remediation planning): Powerful model (Opus)

This saves 50-80% on API costs compared to using Opus for everything.

### Fallback Chains

Try models in order until one succeeds:
1. Primary model (Claude Opus)
2. Secondary model (Claude Sonnet)
3. Tertiary model (GPT-4)
4. Emergency: page the on-call DBA

Like cascading replication: primary -> sync standby -> async standby.

### Model Consensus

For critical decisions, ask two models the same question:
- If they agree: proceed with high confidence
- If they disagree: escalate to human
- If one fails: use the other's answer with reduced confidence

## Permission Models

### Tiered Access

| Tier | Agent Role | Approval | Example Actions |
|------|-----------|----------|-----------------|
| 1 | Monitor | None (auto) | Check stats, read logs, send alerts |
| 2 | Operator | Notify DBA | Kill queries, VACUUM, adjust params |
| 3 | Administrator | Require approval | Failover, DROP, ALTER SYSTEM |

### Blast Radius Control

Limit what each agent can affect:
- **Server scope:** Agent X can only access pg-primary-01 and pg-replica-01
- **Database scope:** Agent Y can only access the "analytics" database
- **Schema scope:** Agent Z can only read from "public" schema
- **Time scope:** Agent W can only act during maintenance windows

## Audit Requirements

Every agent action must be logged with:

1. **Timestamp** - when it happened
2. **Agent ID** - which agent acted
3. **Action** - what was attempted
4. **Target** - which server/database/table
5. **Parameters** - what inputs were provided
6. **Result** - success, denied, blocked, or error
7. **Approval** - who approved (if applicable)
8. **Evidence** - what data led to the decision

This is non-negotiable. Without an audit trail, you cannot investigate incidents, prove compliance, or improve the system.

## OWASP Top 10 for LLM Agents (Applied to DBA Agents)

| # | Risk | DBA Agent Example | Mitigation |
|---|------|-------------------|------------|
| 1 | Prompt Injection | Alert text contains "DROP DATABASE" | Input validation, separation of data/instructions |
| 2 | Insecure Output | Agent leaks connection strings | Output filtering, credential detection |
| 3 | Training Data Poisoning | Bad examples teach agent wrong fixes | Curated training data, validation |
| 4 | Model Denial of Service | Sending 50KB alert text | Input size limits, token budgets |
| 5 | Supply Chain | Compromised model API | Fallback chains, model verification |
| 6 | Sensitive Info Disclosure | Agent reveals server architecture | Output schema enforcement |
| 7 | Insecure Plugin Design | Agent tool with no input validation | Schema validation on every tool |
| 8 | Excessive Agency | Agent with SUPERUSER access | Tiered permissions, least privilege |
| 9 | Overreliance | Blindly trusting agent recommendations | Confidence scoring, human review |
| 10 | Model Theft | Exposing system prompts | Prompt injection defense, access control |

## Key Principle: Defense in Depth

No single guardrail is sufficient. Stack multiple layers:

```
                     Alert Input
                         |
                   [Input Sanitizer]     <- Block injection
                         |
                   [Schema Validator]    <- Validate types/ranges
                         |
                   [Rate Limiter]        <- Prevent floods
                         |
                   [Permission Check]    <- Verify authorization
                         |
                   [SQL Safety Check]    <- Block dangerous SQL
                         |
                   [Approval Workflow]   <- Human oversight
                         |
                   [Execute Action]
                         |
                   [Output Filter]       <- Strip credentials
                         |
                   [Schema Enforcer]     <- Force response format
                         |
                   [Audit Logger]        <- Record everything
                         |
                    Safe Response
```

If any single layer fails (bug, bypass, misconfiguration), the other layers still protect you. This is exactly how PostgreSQL security works - pg_hba.conf, GRANT/REVOKE, row-level security, and logging are all independent layers.

## Prerequisites

- Python basics (functions, classes, dictionaries, regex)
- Module 15 (AI Security) - prompt injection concepts
- Module 18 (Multi-Agent Systems) - agent architecture
- Understanding of PostgreSQL security (roles, grants, pg_hba.conf)
