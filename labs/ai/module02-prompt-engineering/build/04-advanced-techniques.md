# Build 04: Advanced Techniques

Prompt templates, ReAct pattern, streaming responses, and building a reusable prompt library. These are the patterns used in production AI systems.

---

## Step 1. Prompt templates

Hardcoded prompts don't scale. Templates let you reuse the same prompt structure with different inputs - like parameterized SQL queries.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

# A reusable template
def analyze_query(query: str, context: str = "") -> str:
    """Analyze a SQL query and return optimization suggestions."""
    system = """You are a PostgreSQL query optimizer. Respond in this format:
COMPLEXITY: simple | moderate | complex
ISSUES: bullet list of problems (or "none")
SUGGESTION: one concrete improvement
Keep your response under 100 words."""

    user_msg = f"Analyze this query:\n```sql\n{query}\n```"
    if context:
        user_msg += f"\n\nContext: {context}"

    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": user_msg}]
    )
    return msg.content[0].text

# Use the template with different inputs
queries = [
    ("SELECT * FROM users WHERE id = 42", "users table has 1M rows"),
    ("SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at", "orders table has 50M rows, no index on status"),
    ("SELECT u.name, COUNT(*) FROM users u JOIN orders o ON u.id = o.user_id GROUP BY u.name", ""),
]

for query, ctx in queries:
    print(f"Query: {query[:60]}...")
    print(analyze_query(query, ctx))
    print("-" * 60)
PYEOF
```

Expected output (yours will differ):
```
Query: SELECT * FROM users WHERE id = 42...
COMPLEXITY: simple
ISSUES: none (primary key lookup is optimal)
SUGGESTION: Replace SELECT * with specific columns to reduce I/O.
------------------------------------------------------------
Query: SELECT * FROM orders WHERE status = 'pending' ORDER BY cr...
COMPLEXITY: moderate
ISSUES:
- No index on status column, causing sequential scan on 50M rows
- SELECT * fetches all columns
- ORDER BY without matching index requires in-memory sort
SUGGESTION: CREATE INDEX idx_orders_status_created ON orders(status, created_at DESC);
------------------------------------------------------------
Query: SELECT u.name, COUNT(*) FROM users u JOIN orders o ON u.i...
COMPLEXITY: moderate
ISSUES:
- Full scan of both tables for the JOIN and GROUP BY
SUGGESTION: Ensure index exists on orders(user_id) for the join lookup.
------------------------------------------------------------
```

This is how production AI features work:
- The template (function) encapsulates the prompt engineering
- Different inputs go through the same proven prompt
- Your application code calls the function, not raw API calls
- Easy to test, version, and improve

---

## Step 2. The ReAct pattern (Reason + Act)

ReAct makes the model think before acting. Instead of just answering, it follows a loop: **Thought -> Action -> Observation -> Thought -> ...**

This is the foundation of AI Agents (Module 04). Here's a simplified version:

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

system = """You are a database troubleshooting agent. When given a problem, work through it using the ReAct pattern:

THOUGHT: What do I think is happening? What should I check?
ACTION: What specific command or query would I run?
OBSERVATION: (The user will provide the result)
THOUGHT: Based on the result, what do I now think?
ACTION: What next command?
... repeat until you have a diagnosis.

When you are confident in the root cause, end with:
DIAGNOSIS: [the root cause]
FIX: [the specific command to fix it]

Always explain your reasoning. Never guess without evidence."""

messages = [
    {"role": "user", "content": "Users are reporting that the application is very slow and some requests are timing out. Help me investigate."}
]

# Turn 1: Agent reasons and suggests first action
msg1 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    temperature=0,
    system=system,
    messages=messages
)
print("=== Agent Turn 1 ===")
print(msg1.content[0].text)
print()

# Simulate providing the observation
messages.append({"role": "assistant", "content": msg1.content[0].text})
messages.append({"role": "user", "content": """OBSERVATION: Here's what pg_stat_activity shows:
- 285 connections total
- 240 in state 'idle in transaction'
- 30 in state 'active'
- 15 in state 'idle'
- Longest running query: 2 hours 15 minutes
- max_connections is set to 300"""})

# Turn 2: Agent analyzes and suggests next action
msg2 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    temperature=0,
    system=system,
    messages=messages
)
print("=== Agent Turn 2 ===")
print(msg2.content[0].text)
print()

# Simulate providing more data
messages.append({"role": "assistant", "content": msg2.content[0].text})
messages.append({"role": "user", "content": """OBSERVATION: The 240 idle-in-transaction connections:
- 238 come from application 'web-api' (same app)
- Most have been idle for 10-45 minutes
- The 2-hour query is: SELECT * FROM reports JOIN transactions ON ... (a large analytics query)
- idle_in_transaction_session_timeout is set to 0 (disabled)"""})

# Turn 3: Agent should now have enough to diagnose
msg3 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=400,
    temperature=0,
    system=system,
    messages=messages
)
print("=== Agent Turn 3 ===")
print(msg3.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
=== Agent Turn 1 ===
THOUGHT: Slow application + timeouts could be: database overloaded,
connection exhaustion, lock contention, or long-running queries
blocking others. I need to see what the database is doing right now.

ACTION: Run this on the primary:
SELECT state, COUNT(*) FROM pg_stat_activity GROUP BY state;
Also check: SELECT * FROM pg_stat_activity WHERE state != 'idle'
ORDER BY query_start;

=== Agent Turn 2 ===
THOUGHT: This is concerning. 240 out of 285 connections are "idle in
transaction" - that's 84% of connections doing nothing but holding
locks. Only 15 slots remain before max_connections (300). New
requests are timing out because they can't get a connection.

The 2-hour query might be holding locks that are blocking others,
but the bigger issue is the 240 leaked connections.

ACTION: Let me see who owns these idle-in-transaction connections:
SELECT application_name, COUNT(*), MAX(NOW() - state_change) as max_idle_time
FROM pg_stat_activity
WHERE state = 'idle in transaction'
GROUP BY application_name;

Also check: SHOW idle_in_transaction_session_timeout;

=== Agent Turn 3 ===
THOUGHT: Now I have the full picture. The 'web-api' application is
opening transactions and never committing or rolling them back. 238
connections are stuck. The timeout is disabled so they'll sit forever.
This is a classic connection leak in the application code.

DIAGNOSIS: The web-api application has a transaction/connection leak.
It opens database transactions but doesn't close them (missing COMMIT
or ROLLBACK, likely in an error handling path). With
idle_in_transaction_session_timeout disabled, these connections
accumulate until max_connections is nearly exhausted, causing new
requests to time out.

FIX:
1. Immediate: SET idle_in_transaction_session_timeout = '5min';
   (kills leaked transactions after 5 minutes)
2. Immediate: SELECT pg_terminate_backend(pid) FROM pg_stat_activity
   WHERE state = 'idle in transaction'
   AND state_change < NOW() - INTERVAL '10 minutes';
3. Application fix: find the missing connection.close() or
   transaction commit in the web-api error handling code
4. Permanent: Add to postgresql.conf:
   idle_in_transaction_session_timeout = 300000
```

This is exactly how real troubleshooting works:
1. Don't guess - gather evidence first
2. Each observation narrows the diagnosis
3. The fix addresses both the symptom (kill leaked connections) and the root cause (application code + timeout setting)

This ReAct pattern becomes the core of AI Agents in Module 04.

---

## Step 3. Streaming responses

For long responses, streaming shows output as it's generated - like watching a query execute instead of waiting for the full result.

```bash
python3 << 'PYEOF'
import anthropic
import sys

client = anthropic.Anthropic()

print("Streaming response:")
print("-" * 40)

with client.messages.stream(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    temperature=0,
    messages=[{"role": "user", "content": "List 5 PostgreSQL performance tuning parameters with brief explanations."}]
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)

print()
print("-" * 40)
print("Stream complete.")
PYEOF
```

Expected output (appears word by word):
```
Streaming response:
----------------------------------------
1. **shared_buffers** - Amount of memory PostgreSQL uses for
caching data pages. Set to 25% of system RAM as a starting
point...
(text appears progressively, not all at once)
----------------------------------------
Stream complete.
```

- `client.messages.stream()` returns a context manager
- `stream.text_stream` yields text chunks as they're generated
- `flush=True` ensures each chunk displays immediately
- Use streaming for: chatbots, long responses, any user-facing feature where waiting 10+ seconds feels broken

---

## Step 4. Build a prompt library

In production, you don't write prompts inline. You build a library of tested, versioned prompts.

```bash
cat > /tmp/prompt_library.py << 'PYEOF'
"""
Prompt Library - Reusable prompt templates for database operations.
Each prompt is tested and versioned.
"""
import anthropic
import json
from typing import Optional

client = anthropic.Anthropic()


def call_claude(system: str, user_msg: str, max_tokens: int = 300, temperature: float = 0) -> str:
    """Base function for all Claude API calls."""
    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=max_tokens,
        temperature=temperature,
        system=system,
        messages=[{"role": "user", "content": user_msg}]
    )
    return msg.content[0].text


def classify_alert(alert_text: str) -> dict:
    """Classify a database alert by severity and category."""
    system = """Classify the database alert. Respond with JSON only:
{"severity": "critical|high|medium|low", "category": "performance|replication|storage|security|connectivity", "action_needed": true|false, "summary": "one sentence"}"""

    result = call_claude(system, alert_text, max_tokens=150)
    return json.loads(result)


def explain_query(sql: str, audience: str = "junior") -> str:
    """Explain a SQL query for a specific audience level."""
    audiences = {
        "junior": "Explain like they've only written basic SELECT queries. No jargon.",
        "mid": "Explain assuming they understand joins, indexes, and execution plans.",
        "senior": "Focus on performance implications, edge cases, and production risks."
    }
    system = f"You are a SQL educator. {audiences.get(audience, audiences['junior'])} Keep it under 100 words."
    return call_claude(system, f"Explain this query:\n```sql\n{sql}\n```")


def generate_runbook_step(task: str, server: str, user: str) -> str:
    """Generate a single runbook step in SUTA Labs format."""
    system = """Generate a runbook step following these rules:
- State the server and user before the command
- One command per code block
- Explain what the command does (1-2 sentences)
- Show expected output (3-5 lines)
- Use vi for file editing, never nano
Format: markdown with code blocks."""

    return call_claude(system, f"Task: {task}\nServer: {server}\nUser: {user}", max_tokens=300)


# === Test the library ===
if __name__ == "__main__":
    print("=== Alert Classification ===")
    result = classify_alert("PostgreSQL primary: WAL directory at 95% capacity, growing 2GB/hour")
    print(json.dumps(result, indent=2))
    print()

    print("=== Query Explanation (junior) ===")
    print(explain_query("SELECT pid, state, query FROM pg_stat_activity WHERE state = 'active'", "junior"))
    print()

    print("=== Query Explanation (senior) ===")
    print(explain_query("SELECT pid, state, query FROM pg_stat_activity WHERE state = 'active'", "senior"))
    print()

    print("=== Runbook Step ===")
    print(generate_runbook_step("Check replication lag", "pg-standby", "postgres"))
PYEOF
echo "Prompt library saved to /tmp/prompt_library.py"
echo "Run with: python3 /tmp/prompt_library.py"
```

Expected output when run (yours will differ):
```
=== Alert Classification ===
{
  "severity": "high",
  "category": "storage",
  "action_needed": true,
  "summary": "WAL directory nearing capacity with active growth requires immediate cleanup or archiving."
}

=== Query Explanation (junior) ===
This query looks at all the connections to your database and shows
only the ones that are currently running a query. It shows three
things for each: the process ID (like a job number), whether it's
active, and what query it's running.

=== Query Explanation (senior) ===
Queries pg_stat_activity for active backends. Note: this only shows
the current query text - if a backend just finished a query, it shows
the last one executed. For lock investigation, join with pg_locks.
Consider adding wait_event and wait_event_type columns for blocked
session analysis.

=== Runbook Step ===
On **pg-standby**, as **postgres**:

Check the current replication lag:
```sql
SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()
  THEN 0
  ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())
END AS lag_seconds;
```
This compares the last WAL position received from the primary with
the last position replayed locally. If they match, lag is 0.
```

This prompt library pattern:
- Encapsulates prompt engineering in reusable functions
- Each function has a clear input/output contract
- Easy to test, version, and swap models
- Your application code stays clean

---

## What You Learned

| Technique | What It Does | Production Use |
|-----------|-------------|----------------|
| Prompt templates | Reusable functions with variable inputs | Every AI feature |
| ReAct pattern | Think -> Act -> Observe loop | Troubleshooting agents, investigation tools |
| Streaming | Show output progressively | Chat UIs, long responses |
| Prompt library | Versioned, tested prompt collection | Enterprise AI applications |
