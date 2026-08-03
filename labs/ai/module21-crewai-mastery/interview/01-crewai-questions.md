# Interview: CrewAI Mastery

These questions test whether you understand multi-agent orchestration patterns, not just CrewAI syntax. Interviewers want to know you can design agent systems that work reliably in production - the same way they'd test whether a DBA can design a replication topology, not just run `pg_basebackup`.

---

## Question 1: Agent/Task/Crew Model

**Q: Explain CrewAI's Agent/Task/Crew model. When would you use it instead of a single LLM call?**

**Model Answer:**

CrewAI has three building blocks. An **Agent** is a specialist with a role, goal, and backstory - like a DBA team member. A **Task** is a specific piece of work assigned to an agent - like a Jira ticket. A **Crew** is a team of agents working through tasks in a defined process - like an on-call team executing a runbook.

You'd use CrewAI instead of a single LLM call when:

1. **The problem requires multiple domains of expertise.** A database incident might need a triage expert, a performance specialist, and someone to write the post-mortem. One LLM call trying to do all three produces shallow results in each area.

2. **The workflow has distinct phases.** Triage, investigation, remediation, and communication are different steps. Each benefits from a focused agent with a specific role.

3. **You need structured output flow.** Task outputs feed into subsequent tasks via `context`. This ensures each step builds on the previous one, like a CTE chain in SQL.

You would NOT use CrewAI for simple, single-domain tasks. Classifying an alert as P1-P4? One LLM call is enough. Adding 3 agents and 4 tasks would be over-engineering - like creating a 5-table schema for data that fits in one table.

**Key points to hit:**
- Agent = specialist identity (role/goal/backstory)
- Task = work item with expected output
- Crew = orchestration layer
- Use multi-agent when problem spans multiple domains or phases
- Don't use it for simple, single-step tasks

---

## Question 2: Sequential vs Hierarchical

**Q: What's the difference between Sequential and Hierarchical process in CrewAI? When would you choose each?**

**Model Answer:**

**Sequential** runs tasks in order. Task 1 finishes, its output feeds Task 2, then Task 3. Every task has a pre-assigned agent. This is like a runbook: Step 1 (triage lead classifies), Step 2 (specialist investigates), Step 3 (engineer remediates).

**Hierarchical** has a manager agent that receives tasks and decides which specialist to delegate to. The manager reads the task, evaluates which agent's role and backstory best matches, and delegates. This is like a war room where the lead DBA listens to the symptoms and assigns work dynamically.

When to use **Sequential:**
- You know the workflow upfront (triage -> investigate -> fix)
- Each step has a clear owner
- The order matters
- You want predictable cost (fixed number of agents and tasks)
- Example: Standard incident response, scheduled health checks

When to use **Hierarchical:**
- You don't know which specialist should handle the work until runtime
- The alert could be any category (performance, replication, storage)
- You want the manager to make routing decisions
- You're willing to pay for an extra agent (the manager) for better routing
- Example: General alert intake, multi-domain triage

The trade-off is control vs flexibility. Sequential gives you control - you know exactly what runs when. Hierarchical gives you flexibility - the manager decides at runtime. In my experience, sequential handles 80% of use cases. Use hierarchical only when routing logic is genuinely complex.

**DBA analogy:** Sequential = playbook with assigned roles. Hierarchical = war room with a coordinator.

**Key points to hit:**
- Sequential: fixed order, pre-assigned agents, predictable
- Hierarchical: manager delegates, dynamic routing, flexible
- Sequential for known workflows, hierarchical for dynamic routing
- Sequential is cheaper (no manager overhead)

---

## Question 3: Memory in Production

**Q: How does CrewAI memory work and why is it important for production agents?**

**Model Answer:**

CrewAI has four memory types:

1. **Short-term memory** operates within a single crew run. As agents execute tasks and use tools, results are stored so later agents in the same run can reference them. This prevents redundant work and contradictions. DBA analogy: your working memory during an incident - you remember you already checked pg_stat_activity.

2. **Long-term memory** persists across runs in a local database. When a crew finishes, its results are stored. On the next run, agents can retrieve similar past results. DBA analogy: your team's incident wiki - "we saw this same replication lag pattern on June 3rd."

3. **Entity memory** stores facts about specific entities - servers, databases, applications. As agents encounter information ("pg-primary has 200 max_connections"), it's stored and retrieved when that entity appears again. DBA analogy: your mental model of each server in your fleet.

4. **Knowledge sources** are documents loaded at startup - runbooks, documentation, past post-mortems. Agents can search these during task execution. DBA analogy: Confluence wiki with your runbooks.

Why it matters for production:

Without memory, every crew run starts from zero. The agent treats "replication lag on pg-primary" the same whether it's the first time or the 50th time. With memory, the agent says "this matches 3 past incidents, all caused by the analytics ETL job. The fix is statement_timeout on the analytics role."

This directly reduces mean time to resolution (MTTR). In our incident database, crews with memory resolve recurring issues 40-60% faster because they skip the investigation phase for known patterns.

The risk: stale memory. If your infrastructure changes (pg-primary gets upgraded from 200 to 500 max_connections), entity memory still says 200. You need a process to invalidate or update stale facts - like cache invalidation in any system.

**Key points to hit:**
- Four types: short-term, long-term, entity, knowledge sources
- Short-term = within a run, long-term = across runs
- Production benefit: faster resolution of recurring issues
- Risk: stale memory needs invalidation strategy
- DBA analogy for each type

---

## Question 4: Testing CrewAI

**Q: How would you test a CrewAI crew before deploying to production?**

**Model Answer:**

I'd use a three-layer testing strategy, similar to how you'd test database migrations:

**Layer 1: Unit tests (agent configuration)**
- Verify each agent has the correct role, goal, and backstory
- Verify tools are attached to the right agents
- Verify task dependencies (`context`) are wired correctly
- These tests are free - no API calls required
- DBA analogy: checking your migration script syntax before running it

**Layer 2: Integration tests (crew execution)**
- Run the crew against known alerts with known correct answers
- Build a test suite: 10-15 alerts covering every category (performance, replication, storage)
- For each alert, define what "correct" looks like: right severity, right specialist, right commands
- Check that the output contains expected keywords (e.g., "CREATE INDEX" for a missing index alert)
- These tests cost API credits, so run them on a schedule (nightly) not on every code change
- DBA analogy: running your migration on a staging database

**Layer 3: Chaos tests (SURVIVE scenarios)**
- What happens when a tool fails? (API timeout, database unreachable)
- What happens when agents try to delegate in loops?
- What happens with ambiguous alerts that could be multiple categories?
- What happens when the LLM returns unexpected output?
- DBA analogy: running `kill -9 postgres` on a replica to test failover

**Practical approach:**
```python
# Golden test: alert with known correct answer
test_alert = "pg-primary seq scan on 500M row orders table, no index on customer_id"
expected_keywords = ["CREATE INDEX", "customer_id", "CONCURRENTLY"]

result = crew.kickoff(inputs={"alert": test_alert})
for keyword in expected_keywords:
    assert keyword.lower() in str(result).lower(), f"Missing: {keyword}"
```

I'd also track cost per test run. If integration tests cost $2/run and you run them daily, that's $60/month - worth it for confidence, but you should budget for it.

**Key points to hit:**
- Three layers: unit (free), integration (costs API), chaos (edge cases)
- Golden tests: known alerts with known correct answers
- Keyword checking for output validation
- Cost awareness for test runs
- Chaos testing for failure modes

---

## Question 5: Design Exercise

**Q: Design a CrewAI-based database incident response system. Walk me through the agents, tasks, tools, memory strategy, and deployment architecture.**

**Model Answer:**

I'd design a 4-stage incident response system:

**Stage 1: Triage Crew**
- Agent: Triage Lead
- Tools: `get_alert_details()`, `get_server_metadata()`
- Task: Classify alert (P1-P4, category), check past incidents
- Output: Triage report with severity, category, and past similar incidents

**Stage 2: Investigation Crew**
- Agent: Domain specialist (routed by triage category)
- Tools: `run_diagnostic_query()`, `check_metrics()`, `analyze_logs()`
- Task: Find root cause using diagnostic tools
- Output: Root cause analysis with evidence

**Stage 3: Remediation Crew**
- Agent: Remediation Engineer
- Tools: `create_jira_ticket()`, `send_slack_message()`, `page_oncall()`
- Task: Create remediation plan AND communicate to stakeholders
- Output: Step-by-step fix with commands, Jira ticket, Slack notification

**Stage 4: Post-mortem Crew**
- Agent: Post-mortem Analyst
- Tools: `write_document()`, `update_runbook()`
- Task: Write blameless post-mortem, update runbooks for next time
- Output: Post-mortem document with action items

**Memory strategy:**
- Long-term memory: store every resolved incident for pattern matching
- Entity memory: store facts about each server (role, capacity, quirks)
- Knowledge sources: load all runbooks, past post-mortems, architecture docs
- Memory invalidation: weekly job to prune entity facts older than 90 days or after infrastructure changes

**Deployment:**
```
PagerDuty webhook
     |
     v
API Gateway (rate limiting, auth)
     |
     v
CrewAI Flow (Triage -> Investigate -> Remediate -> PostMortem)
     |
     +---> Slack (real-time updates)
     +---> Jira (ticket creation)
     +---> Memory DB (incident storage)
     +---> Metrics (cost tracking, latency)
```

**Safety rails:**
- All database tools are read-only (SELECT only)
- Remediation steps are RECOMMENDED, not auto-executed
- A human approves before any write action runs
- Cost budget: $5/incident max, alert if exceeded
- Timeout: 5 minutes per crew stage, 15 minutes total

**Cost estimate:**
- 4 stages, ~2-3 API calls each = 8-12 calls per incident
- At GPT-4o rates: ~$0.10-0.20 per incident
- At 100 incidents/month: ~$10-20/month
- This is a fraction of the DBA salary hours saved

**What I'd build first:**
Stage 1 (triage) only. Get that working reliably for 2 weeks. Then add Stage 2. Then 3 and 4. Like building a database system - get the core right, then add features.

**Key points to hit:**
- Clear stage separation with specific agents per stage
- Read-only tools with human approval for writes
- Memory strategy for learning from past incidents
- Cost budgeting and safety rails
- Incremental deployment (don't build all 4 stages at once)
- Practical cost estimate showing ROI
