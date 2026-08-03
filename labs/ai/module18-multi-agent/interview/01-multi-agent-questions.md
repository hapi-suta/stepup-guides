# Interview 01: Multi-Agent System Questions

---

## Question 1: What are multi-agent systems and when would you use them?

**What they're asking:** Do you understand when multiple agents are better than one?

**Answer:**

A multi-agent system is multiple AI agents, each with a specialized role, working together on a task. Instead of one model doing everything, you have specialists that communicate.

When to use multi-agent over single agent:
- **Complex workflows:** Alert triage needs monitoring, classification, diagnosis, and remediation - four distinct skills
- **Specialization:** A classifier agent can be optimized for accuracy while a remediation agent is optimized for safety
- **Scalability:** You can run 10 classifier agents in parallel but only 1 remediation agent (for safety)
- **Independent updates:** You can retrain the classifier without touching the diagnostics agent

When NOT to use multi-agent:
- Simple tasks (text classification alone doesn't need multiple agents)
- Low latency requirements (agent communication adds overhead)
- Small teams (more agents = more things to maintain)

**DBA parallel:** A single DBA can handle a small environment. But a 15,000-database operation needs specialists: one for performance tuning, one for replication, one for security, one for backup. Same databases, specialized roles. Multi-agent AI is the same organizational pattern.

---

## Question 2: Explain the orchestrator pattern for multi-agent systems.

**What they're asking:** Can you design agent coordination?

**Answer:**

The orchestrator pattern has one master agent that delegates to specialists:

```
Alert arrives
    |
[Orchestrator] - "This is a storage alert, high severity"
    |
    +---> [Classifier Agent] - "Category: storage, confidence 92%"
    +---> [Diagnostics Agent] - "Root cause: WAL archiving failed"
    +---> [Remediation Agent] - "Recommend: fix archive_command"
    |
[Orchestrator] - combines results, generates final response
```

The orchestrator's responsibilities:
1. **Route:** Decide which agents to involve based on the alert
2. **Coordinate:** Pass context between agents (classifier result to diagnostics)
3. **Aggregate:** Combine results into a unified response
4. **Conflict resolution:** If classifier says "storage" but diagnostics says "performance," decide which to trust
5. **Timeout management:** If an agent takes too long, skip it and use defaults

The orchestrator does NOT do the actual analysis - it manages the workflow.

**DBA parallel:** Like PgBouncer. It doesn't execute queries itself - it routes connections to the right backend, manages the pool, and handles failures. The orchestrator is PgBouncer for AI agents.

---

## Question 3: How do you handle agent failures in production?

**What they're asking:** Can you build a resilient multi-agent system?

**Answer:**

Three failure handling strategies:

**1. Circuit breaker**
If an agent fails 3 times in a row, mark it as "down" and stop sending tasks. After a cooldown (5 minutes), try one test task. If it succeeds, re-enable.

```
Agent healthy -> 3 failures -> Circuit OPEN (no tasks sent)
                               -> 5 min cooldown
                               -> Try one task
                               -> Success? Circuit CLOSED (resume)
                               -> Fail? Stay OPEN, reset cooldown
```

**2. Graceful degradation**
When a specialist agent is down, fall back to simpler alternatives:
- Diagnostics agent down -> use keyword-based root cause rules
- Classifier agent down -> use threshold-based classification from metrics only
- Remediation agent down -> classify and alert, but don't recommend actions

The system is less capable but still functional.

**3. Agent redundancy**
Run multiple instances of critical agents. If one fails, others handle the load. The orchestrator keeps a registry of healthy agents and routes accordingly.

**DBA parallel:** Same as database high availability.
- Circuit breaker = PgBouncer health checks (mark backend down after failures)
- Graceful degradation = read-only mode when primary is down
- Redundancy = streaming replication (multiple standbys)

---

## Question 4: How do you prevent a rogue agent from taking dangerous actions?

**What they're asking:** Can you build safe multi-agent systems?

**Answer:**

Four safety layers:

**1. Agent permissions (least privilege)**
Each agent has an explicit list of allowed actions:
- Monitor agent: can read metrics (no writes)
- Classifier agent: can classify (no actions)
- Diagnostics agent: can run read-only SQL (no modifications)
- Remediation agent: can recommend actions (execution requires approval)

No agent has permissions beyond its role.

**2. Action approval workflow**
Even the remediation agent can't execute medium/high-risk actions alone:
- Low risk (read-only query): auto-execute
- Medium risk (kill idle connection): execute + notify
- High risk (failover): require human approval
- Critical (DROP TABLE): blocked entirely

**3. Startup safety validation**
When an agent starts, it validates its own configuration:
- Check: are my safety levels correct?
- Check: do I have the right permissions?
- Check: is my action catalog correct?
If any check fails, the agent refuses to start.

**4. Kill switch**
A global emergency stop that:
- Immediately halts all agent actions
- Switches to human-only mode
- Logs the reason for activation
- Requires manual re-enablement

**DBA parallel:** Same as database security.
- Agent permissions = GRANT/REVOKE per role
- Action approval = transaction confirmation for DDL
- Startup validation = pg_hba.conf checks on startup
- Kill switch = pg_ctl stop -m immediate

---

## Question 5: Design a multi-agent system for database monitoring.

**What they're asking:** Can you architect a complete system?

**Answer:**

Five agents for database monitoring:

**Agent 1: Monitor**
- Role: collect metrics and detect changes
- Tools: read pg_stat views, read Prometheus, read logs
- Output: metric snapshots with change flags
- Runs: continuously (every 30 seconds)

**Agent 2: Classifier**
- Role: categorize alerts by type and severity
- Tools: text analysis, metric thresholds, multi-modal fusion
- Input: alert text + metrics from Monitor
- Output: category + confidence + severity + priority

**Agent 3: Diagnostics**
- Role: find root cause
- Tools: knowledge base lookup, context engine (recent alerts), read-only SQL
- Input: classified alert from Classifier
- Output: likely root cause + evidence + diagnostic queries

**Agent 4: Remediation**
- Role: recommend and execute fixes
- Tools: action catalog, runbook generator, (limited) SQL execution
- Input: diagnosis from Diagnostics
- Output: remediation plan with risk-rated steps
- Safety: only auto-executes low-risk actions

**Agent 5: Reporter**
- Role: generate summaries and track patterns
- Tools: pattern detection, trend analysis, report generation
- Input: all resolved incidents
- Output: daily summary, weekly trends, capacity predictions

**Orchestrator:**
- Routes alerts through the pipeline: Monitor -> Classifier -> Diagnostics -> Remediation
- Runs Reporter asynchronously (doesn't block the alert pipeline)
- Handles agent failures with circuit breakers
- Aggregates results for the DBA dashboard

**DBA parallel:** This is the same team structure you'd build for a large database operation:
- Junior DBA monitors dashboards (Monitor agent)
- Mid-level DBA triages alerts (Classifier agent)
- Senior DBA diagnoses root causes (Diagnostics agent)
- Principal DBA approves and executes fixes (Remediation agent)
- Manager generates reports (Reporter agent)
- Lead DBA coordinates everyone (Orchestrator)
