# USE: Prompt Engineering Exercises

Work through these exercises in order. Each one builds a real, useful prompt. Test them by running the code - the API will give you immediate feedback on whether your prompt works.

---

## Exercise 1: The Alert Triage System

**Task:** Build a prompt that takes raw monitoring alerts and outputs a structured triage report. The system should:

1. Classify severity (P1-P4)
2. Identify which team should handle it (DBA, SRE, App Dev, Security)
3. Suggest the first diagnostic command to run
4. Output as JSON

Test it with these alerts:
- "CRITICAL: Primary database connection refused on port 5432"
- "WARNING: Disk usage on /pgdata reached 80%"
- "INFO: Nightly backup completed in 45 minutes (usual: 20 minutes)"

<details>
<summary>Hint</summary>

- Put the classification rules and JSON schema in the system prompt
- Use few-shot examples to calibrate severity levels (e.g., connection refused = P1, disk 80% = P3)
- The tricky one is the backup alert - it says INFO but the duration is 2x normal. A good prompt catches this.
</details>

<details>
<summary>Solution</summary>

```python
import anthropic
import json

client = anthropic.Anthropic()

system = """You are a database alert triage system. Classify alerts and output JSON only.

Severity guide:
- P1: Service down, data loss risk, security breach
- P2: Degraded performance, replication broken, near capacity
- P3: Approaching limits, unusual patterns, needs attention this shift
- P4: Informational, optimization opportunity, can wait

IMPORTANT: Look beyond the alert level. An INFO alert with abnormal values should be escalated.

Output format:
{
  "severity": "P1|P2|P3|P4",
  "team": "DBA|SRE|AppDev|Security",
  "alert_text": "original alert",
  "analysis": "what this actually means (one sentence)",
  "first_command": "diagnostic command to run",
  "escalate": true|false
}"""

alerts = [
    "CRITICAL: Primary database connection refused on port 5432",
    "WARNING: Disk usage on /pgdata reached 80%",
    "INFO: Nightly backup completed in 45 minutes (usual: 20 minutes)",
]

for alert in alerts:
    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": alert}]
    )
    result = json.loads(msg.content[0].text)
    print(f"[{result['severity']}] {result['team']}: {result['analysis']}")
    print(f"  Run: {result['first_command']}")
    print()
```

The backup alert should be classified as P3 (not P4) because 2x normal duration indicates a problem - table bloat, I/O contention, or data growth.
</details>

---

## Exercise 2: The Query Explainer (Multi-Audience)

**Task:** Build a function that explains any SQL query at three audience levels:
- **Beginner:** Assumes they know what a table is but nothing about joins or indexes
- **Intermediate:** Knows SQL basics, wants to understand performance implications
- **Expert:** Wants edge cases, lock behavior, and production risks

Test with: `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND state_change < NOW() - INTERVAL '10 minutes';`

The beginner explanation should be reassuring ("this safely cleans up..."). The expert explanation should include warnings about open transactions and uncommitted data.

<details>
<summary>Hint</summary>

- Use the audience level in the system prompt to change tone, depth, and vocabulary
- For beginners: avoid terms like "backend", "pid", "state machine"
- For experts: mention transaction isolation, lock release, and application-side effects
- Keep each explanation under 100 words
</details>

<details>
<summary>Solution</summary>

```python
import anthropic

client = anthropic.Anthropic()

audiences = {
    "beginner": """Explain SQL queries for someone who knows what tables and rows are, but nothing about database internals.
Use simple analogies. Never use terms like 'backend', 'pid', 'WAL', or 'lock'.
If the query could be dangerous, explain the risk in simple terms.
Under 80 words.""",

    "intermediate": """Explain SQL queries for someone who knows SELECT/JOIN/WHERE and basic indexes.
Focus on what the query does and its performance characteristics.
Mention if it needs special permissions.
Under 80 words.""",

    "expert": """Explain SQL queries for a senior DBA.
Focus on: lock behavior, transaction safety, side effects, edge cases.
Mention what could go wrong in production.
Under 80 words.""",
}

query = """SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND state_change < NOW() - INTERVAL '10 minutes';"""

for level, system in audiences.items():
    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=150,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": f"Explain:\n```sql\n{query}\n```"}]
    )
    print(f"=== {level.upper()} ===")
    print(msg.content[0].text)
    print()
```
</details>

---

## Exercise 3: Chain-of-Thought Root Cause Analysis

**Task:** Build a prompt that takes a set of database symptoms and produces a root cause analysis using chain-of-thought. The prompt should:

1. List each symptom and what it tells us individually
2. Find connections between symptoms
3. Identify the root cause (not just the loudest symptom)
4. Provide a fix with specific commands

Test with these symptoms:
```
- Autovacuum not running on any table for 6 hours
- Table bloat on 'orders' grew from 15% to 65% in the last 6 hours
- Query performance degraded 4x across all SELECT queries
- Two long-running ALTER TABLE operations started 6 hours ago
- pg_stat_user_tables shows 0 vacuum operations since 6 hours ago
- autovacuum_max_workers = 3 (default)
```

The root cause is NOT "autovacuum is broken." Think deeper.

<details>
<summary>Hint</summary>

- The ALTER TABLE operations started exactly when vacuum stopped
- ALTER TABLE takes an ACCESS EXCLUSIVE lock on the table
- Autovacuum cannot vacuum a table that has a conflicting lock
- But wait - the ALTER is on some tables, yet vacuum stopped on ALL tables. Why?
- With only 3 autovacuum workers, if they're all waiting on locks, no other tables get vacuumed
</details>

<details>
<summary>Solution</summary>

```python
import anthropic

client = anthropic.Anthropic()

system = """You are a PostgreSQL root cause analyst.

When given symptoms, analyze using this exact chain-of-thought process:

STEP 1 - INDIVIDUAL SYMPTOMS: What does each symptom tell us in isolation?
STEP 2 - TIMELINE: What happened first? Build a sequence of events.
STEP 3 - CONNECTIONS: How do symptoms relate to each other causally?
STEP 4 - ROOT CAUSE: What single event triggered the cascade? (Never name a symptom as the root cause - find what CAUSED the symptom)
STEP 5 - FIX: Immediate action + permanent prevention

Be specific. Include exact PostgreSQL commands."""

symptoms = """
- Autovacuum not running on any table for 6 hours
- Table bloat on 'orders' grew from 15% to 65% in the last 6 hours
- Query performance degraded 4x across all SELECT queries
- Two long-running ALTER TABLE operations started 6 hours ago
- pg_stat_user_tables shows 0 vacuum operations since 6 hours ago
- autovacuum_max_workers = 3 (default)
"""

msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=600,
    temperature=0,
    system=system,
    messages=[{"role": "user", "content": f"Analyze these symptoms:\n{symptoms}"}]
)
print(msg.content[0].text)
```

The root cause is: two ALTER TABLE operations took ACCESS EXCLUSIVE locks, causing autovacuum workers to queue behind them. With only 3 workers, all workers are stuck waiting, and no other tables can be vacuumed either. The fix: cancel the ALTER TABLE operations (or wait), increase autovacuum_max_workers, and consider using CREATE INDEX CONCURRENTLY instead of ALTER TABLE when possible.
</details>

---

## Exercise 4: The Conversation Bot

**Task:** Build an interactive troubleshooting bot that:

1. Starts by asking what problem the user is experiencing
2. Asks ONE focused follow-up question at a time (never multiple)
3. After 3-4 turns of investigation, provides a diagnosis
4. Uses the ReAct pattern (THOUGHT/ACTION/OBSERVATION)

Make it work in a real terminal loop where you type responses.

```python
# Skeleton to start from:
import anthropic

client = anthropic.Anthropic()
system = "..." # Your system prompt here
messages = []

print("DBA Troubleshooter (type 'quit' to exit)")
print("=" * 50)

while True:
    user_input = input("\nYou: ")
    if user_input.lower() == 'quit':
        break

    messages.append({"role": "user", "content": user_input})

    # Your API call here
    # ...

    # Print response
    # Append assistant message to history
```

<details>
<summary>Hint</summary>

- The system prompt should enforce: "Ask exactly ONE question. Never give a diagnosis until you've asked at least 3 questions."
- Track turn count - after turn 4, add to the user message: "You've gathered enough information. Provide your diagnosis now."
- Use ReAct format so the user can see the model's reasoning
</details>

---

## Exercise 5: Prompt Optimization Challenge

**Task:** You have a working but expensive prompt that costs ~$0.05 per call. Optimize it to cost under $0.01 per call while maintaining quality.

Here's the expensive version:

```python
system = """You are an expert PostgreSQL database administrator with over 20 years
of experience managing large-scale production databases across multiple cloud
providers including AWS, GCP, and Azure. You have deep expertise in query
optimization, replication topologies, backup strategies, disaster recovery,
connection pooling with pgBouncer, high availability with Patroni and repmgr,
and performance monitoring using pg_stat_statements, pg_stat_activity, and
various monitoring tools like Grafana and Prometheus. You always provide
detailed, actionable advice with specific PostgreSQL commands and configuration
parameters. You explain your reasoning thoroughly and consider edge cases. You
format your responses clearly with headers and bullet points. You always mention
potential risks and how to mitigate them. When discussing configuration changes,
you always mention the need for testing in staging first and whether a restart
or reload is required."""
```

Constraints:
- Must still give accurate DBA advice
- Must still provide specific commands
- Must mention if changes need restart vs reload
- Reduce the system prompt to under 50 words
- Use max_tokens wisely

<details>
<summary>Hint</summary>

- Most of that system prompt is telling the model things it already knows
- Claude already knows PostgreSQL deeply - you don't need to list your resume
- Focus on the output CONSTRAINTS, not the model's "background"
- A 50-word system prompt with the right constraints outperforms a 200-word biography
- Reduce max_tokens to the minimum needed (200 instead of 1000)
</details>
