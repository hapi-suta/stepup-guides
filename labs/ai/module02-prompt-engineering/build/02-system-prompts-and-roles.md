# Build 02: System Prompts and Roles

The system prompt is the most powerful lever in prompt engineering. It tells the model WHO it is, WHAT it knows, and HOW it should respond. Without a system prompt, you're talking to a generic assistant. With one, you're talking to a specialist.

---

## Step 1. No system prompt vs with system prompt

Let's see the difference side by side.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

question = "My database is slow. What should I do?"

# WITHOUT system prompt
msg1 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=200,
    temperature=0,
    messages=[{"role": "user", "content": question}]
)
print("=== WITHOUT system prompt ===")
print(msg1.content[0].text)
print()

# WITH system prompt
msg2 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=200,
    temperature=0,
    system="You are a PostgreSQL DBA with 15 years of production experience managing databases across AWS, Heroku, and on-prem. You give precise, actionable advice. You always ask clarifying questions before making recommendations. You never suggest solutions without understanding the environment first.",
    messages=[{"role": "user", "content": question}]
)
print("=== WITH system prompt ===")
print(msg2.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
=== WITHOUT system prompt ===
Here are some general steps to troubleshoot a slow database:
1. Check your queries for missing indexes
2. Look at your server resources
3. Consider caching...
(generic, surface-level advice)

=== WITH system prompt ===
Before I can help, I need to understand your environment:

1. Which PostgreSQL version are you running?
2. What's slow - specific queries, overall throughput, or connection time?
3. What does pg_stat_activity show right now?
4. When did this start - gradually or suddenly?
5. Any recent changes (config, schema, traffic)?

The troubleshooting path is completely different depending on whether
this is a missing index, lock contention, vacuum bloat, or
infrastructure issue.
(specific, asks before answering, sounds like a real DBA)
```

The system prompt transformed a generic assistant into a DBA who thinks like you do - asking questions before jumping to conclusions.

---

## Step 2. Constrain the output format

System prompts can enforce output rules - format, length, style.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

system = """You are a database incident responder.

Rules:
- Always respond in this exact format:
  SEVERITY: [P1/P2/P3/P4]
  IMPACT: [one sentence]
  IMMEDIATE ACTION: [one command or step]
  ROOT CAUSE INVESTIGATION: [what to check next]
- Never write more than 4 lines
- Never say "it depends" - commit to a severity level
- If information is missing, state what you need"""

msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=200,
    temperature=0,
    system=system,
    messages=[{"role": "user", "content": "Replication lag just jumped to 5 minutes on our primary production database"}]
)
print(msg.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
SEVERITY: P2
IMPACT: Standby is 5 minutes behind primary, reads may serve stale data.
IMMEDIATE ACTION: Run `SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) FROM pg_stat_replication;` on primary to confirm lag.
ROOT CAUSE INVESTIGATION: Check for long-running transactions, heavy write load, WAL sender bottleneck, or network latency between primary and standby.
```

The model followed the exact format you specified. This is how you build reliable AI features - constrain the output so your code can parse it.

---

## Step 3. Multi-turn conversations

Real conversations have back-and-forth. The `messages` list holds the full conversation history.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

system = "You are a PostgreSQL tuning advisor. Be concise. Ask one clarifying question at a time."

messages = [
    {"role": "user", "content": "My SELECT queries are slow."}
]

# Turn 1
msg1 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=150,
    temperature=0,
    system=system,
    messages=messages
)
print(f"Turn 1 - Assistant: {msg1.content[0].text}")
print()

# Add assistant response to history, then add user follow-up
messages.append({"role": "assistant", "content": msg1.content[0].text})
messages.append({"role": "user", "content": "PostgreSQL 16, the query joins 3 tables and scans about 2 million rows. Takes 12 seconds."})

# Turn 2
msg2 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=150,
    temperature=0,
    system=system,
    messages=messages
)
print(f"Turn 2 - Assistant: {msg2.content[0].text}")
print()

# Add and continue
messages.append({"role": "assistant", "content": msg2.content[0].text})
messages.append({"role": "user", "content": "Here's the EXPLAIN ANALYZE output: Seq Scan on orders, rows=1800000, actual time=8500ms"})

# Turn 3
msg3 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=200,
    temperature=0,
    system=system,
    messages=messages
)
print(f"Turn 3 - Assistant: {msg3.content[0].text}")
PYEOF
```

Expected output (yours will differ):
```
Turn 1 - Assistant: What PostgreSQL version are you running, and how
many rows does the query typically scan?

Turn 2 - Assistant: Can you share the EXPLAIN ANALYZE output for the
slowest query? That will show whether it's doing sequential scans,
nested loops, or something else.

Turn 3 - Assistant: That Seq Scan on 1.8M rows is your bottleneck.
Create an index on the column(s) used in your WHERE clause and JOIN
conditions for the orders table. Something like:
CREATE INDEX CONCURRENTLY idx_orders_... ON orders (...);
Then re-run EXPLAIN ANALYZE to confirm it uses an Index Scan.
```

Key pattern:
- Each turn, you send the FULL conversation history (all previous messages)
- The assistant's response gets appended with `role: "assistant"`
- The user's next message gets appended with `role: "user"`
- Claude remembers everything in the conversation - but only because YOU sent it back. The API is stateless.

---

## Step 4. Persona stacking (multiple roles)

You can give the model multiple personas or perspectives in one system prompt.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

system = """You provide database advice from three perspectives:

[DBA]: Production operations perspective - stability, monitoring, backups
[DEV]: Application developer perspective - query patterns, ORMs, connection pooling
[SRE]: Infrastructure perspective - scaling, failover, resource utilization

For each question, give a brief response from all three perspectives.
Format each perspective on its own line starting with the role tag."""

msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    temperature=0,
    system=system,
    messages=[{"role": "user", "content": "Should we add a read replica?"}]
)
print(msg.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
[DBA]: Yes, if your primary is over 60% CPU from read queries. Set up
streaming replication, configure pg_hba.conf for the replica, and ensure
WAL archiving is working first. Monitor replication lag daily.

[DEV]: Route read-heavy queries (reports, dashboards, search) to the
replica using your connection pooler or ORM's read/write splitting.
Keep all writes on primary. Watch for stale reads during lag.

[SRE]: Before adding a replica, check if connection pooling (pgBouncer)
or query optimization could solve the load issue cheaper. A replica
doubles your infrastructure cost and adds a failure mode to monitor.
```

This technique is useful for:
- Getting diverse perspectives on architecture decisions
- Building review tools that catch different types of issues
- Creating training materials that show multiple viewpoints

---

## Step 5. System prompt as a guardrail

System prompts can restrict what the model will and won't do. This is critical for production AI features.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

system = """You are a read-only database query assistant.

STRICT RULES:
1. You may ONLY help with SELECT queries
2. You must REFUSE any INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or CREATE commands
3. If the user asks you to modify data, respond with: "I can only help with read queries. For data modifications, please contact your DBA."
4. You must NEVER generate DDL or DML that modifies data, even if the user insists
5. If a SELECT query could be expensive (full table scan on large table), warn the user"""

# Test: Try to get it to write a DELETE
msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=150,
    temperature=0,
    system=system,
    messages=[{"role": "user", "content": "Write me a query to delete all inactive users older than 90 days"}]
)
print("User: Write me a query to delete all inactive users older than 90 days")
print(f"Assistant: {msg.content[0].text}")
print()

# Test: A legitimate SELECT
msg2 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=150,
    temperature=0,
    system=system,
    messages=[{"role": "user", "content": "Show me how to find inactive users older than 90 days"}]
)
print("User: Show me how to find inactive users older than 90 days")
print(f"Assistant: {msg2.content[0].text}")
PYEOF
```

Expected output (yours will differ):
```
User: Write me a query to delete all inactive users older than 90 days
Assistant: I can only help with read queries. For data modifications,
please contact your DBA.

User: Show me how to find inactive users older than 90 days
Assistant: SELECT id, username, last_login
FROM users
WHERE last_login < NOW() - INTERVAL '90 days'
  AND is_active = false
ORDER BY last_login;
```

The model refused the DELETE but helped with the SELECT. This is how you build safe AI features - the system prompt acts as a policy layer. But note: system prompts are NOT security. A determined user can sometimes bypass them (that's Module 15 - AI Security).

---

## What You Learned

| Concept | What It Does | Production Use |
|---------|-------------|----------------|
| System prompt | Sets persona, rules, constraints | Every AI feature needs one |
| Format constraints | Forces structured output | Parseable responses for your code |
| Multi-turn conversations | Maintains context across messages | Chatbots, interactive tools |
| Persona stacking | Multiple perspectives in one prompt | Review tools, decision support |
| Guardrail prompts | Restricts model behavior | Safety for user-facing features |
