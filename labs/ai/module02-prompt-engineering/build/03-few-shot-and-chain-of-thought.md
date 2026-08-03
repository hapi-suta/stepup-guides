# Build 03: Few-Shot and Chain-of-Thought

Two techniques that dramatically improve output quality: showing examples (few-shot) and forcing step-by-step reasoning (chain-of-thought).

---

## Step 1. Zero-shot vs few-shot

**Zero-shot** = no examples, just the task. "Classify this query as fast or slow."
**Few-shot** = give examples first, then the task. "Here are 3 examples... now classify this one."

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

# ZERO-SHOT: just ask
msg1 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=100,
    temperature=0,
    messages=[{"role": "user", "content": "Classify this database alert: 'WAL archive directory is 92% full'"}]
)
print("=== ZERO-SHOT ===")
print(msg1.content[0].text)
print()

# FEW-SHOT: give examples first
msg2 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=100,
    temperature=0,
    messages=[{"role": "user", "content": """Classify database alerts into: CRITICAL, WARNING, or INFO.

Examples:
- "Primary server is unreachable" -> CRITICAL
- "Replication lag is 45 seconds" -> WARNING
- "Daily backup completed successfully" -> INFO
- "Connection pool at 85% capacity" -> WARNING
- "Disk space at 98% on data volume" -> CRITICAL

Now classify: "WAL archive directory is 92% full"
"""}]
)
print("=== FEW-SHOT ===")
print(msg2.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
=== ZERO-SHOT ===
This alert indicates that the Write-Ahead Log (WAL) archive
directory is running low on disk space. This could be a
warning or critical issue depending on...
(rambling, unsure classification)

=== FEW-SHOT ===
WARNING

92% disk usage is high but not yet at the critical 98%
threshold shown in the examples. Immediate action should be
taken to archive or clean old WAL files before it hits 98%.
```

The few-shot version:
- Picked up the classification format from examples (single word first)
- Calibrated its thresholds from the patterns (92% < 98% example = WARNING not CRITICAL)
- Gave a concise, structured response

**Rule:** When you need consistent output format, always give examples.

---

## Step 2. Few-shot with user/assistant turns

For even stronger few-shot, put examples in the conversation as actual message turns. This is the most reliable way to teach the model a pattern.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

system = "You are a SQL query explainer for junior DBAs. Explain what the query does in plain English, then rate its efficiency as GOOD, OKAY, or BAD."

messages = [
    # Example 1
    {"role": "user", "content": "EXPLAIN: SELECT * FROM users WHERE id = 42;"},
    {"role": "assistant", "content": "WHAT: Fetches all columns for the user with ID 42.\nEFFICIENCY: GOOD - primary key lookup, uses index, returns 1 row."},

    # Example 2
    {"role": "user", "content": "EXPLAIN: SELECT * FROM orders WHERE created_at > '2026-01-01';"},
    {"role": "assistant", "content": "WHAT: Fetches all columns from orders created after January 1, 2026.\nEFFICIENCY: OKAY - date range scan, needs index on created_at. Could be slow on large tables without it."},

    # Example 3
    {"role": "user", "content": "EXPLAIN: SELECT * FROM logs;"},
    {"role": "assistant", "content": "WHAT: Fetches every column and every row from the logs table.\nEFFICIENCY: BAD - full table scan with no filter. On a large logs table this will be extremely slow and use excessive memory."},

    # Now the real question
    {"role": "user", "content": "EXPLAIN: SELECT u.name, COUNT(o.id) FROM users u LEFT JOIN orders o ON u.id = o.user_id GROUP BY u.name HAVING COUNT(o.id) > 10 ORDER BY COUNT(o.id) DESC;"},
]

msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=200,
    temperature=0,
    system=system,
    messages=messages
)
print(msg.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
WHAT: Finds users who have placed more than 10 orders, shows their
name and order count, sorted from most orders to least.
EFFICIENCY: OKAY - the LEFT JOIN and GROUP BY require scanning both
tables. Needs indexes on users.id (primary key) and orders.user_id
(foreign key). The HAVING filter happens after aggregation, so all
rows are processed first.
```

The model perfectly matched the format (WHAT/EFFICIENCY) and the rating style from the examples. It didn't need to be told the format - it learned it from the conversation turns.

---

## Step 3. Chain-of-thought prompting

Chain-of-thought (CoT) forces the model to reason through a problem step by step before giving an answer. It dramatically improves accuracy on complex tasks.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

scenario = """
A PostgreSQL database has these symptoms:
- CPU usage: 95%
- Active connections: 450 (max_connections = 500)
- pg_stat_activity shows 380 queries in "idle in transaction" state
- Replication lag: increasing (was 2s, now 45s)
- Autovacuum workers: 0 running (usually 3)
- Table bloat on "orders" table: 60%

What is the root cause and what should we do first?
"""

# WITHOUT chain-of-thought
msg1 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    temperature=0,
    messages=[{"role": "user", "content": scenario}]
)
print("=== WITHOUT CoT ===")
print(msg1.content[0].text[:300])
print("...")
print()

# WITH chain-of-thought
msg2 = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=500,
    temperature=0,
    messages=[{"role": "user", "content": scenario + """

Think through this step by step:
1. What does each symptom tell us individually?
2. How do the symptoms connect to each other?
3. What is the root cause (not just a symptom)?
4. What is the single most important action to take FIRST?
"""}]
)
print("=== WITH CoT ===")
print(msg2.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
=== WITHOUT CoT ===
The main issues are high CPU, too many idle connections, and
replication lag. You should kill the idle transactions and
tune your connection pooler...
(jumps to solution, misses the root cause chain)

=== WITH CoT ===
Step 1 - Individual symptoms:
- 95% CPU: something is consuming compute heavily
- 450/500 connections: nearly exhausted
- 380 "idle in transaction": connections are held open without doing work
- Replication lag increasing: WAL apply can't keep up
- 0 autovacuum workers: can't launch because no connections available
- 60% table bloat: vacuum hasn't been running (confirms above)

Step 2 - Connection:
380 idle-in-transaction connections are hogging 76% of all connection
slots. This leaves almost no room for autovacuum workers (which need
connections too). Without vacuum, table bloat grows. With 60% bloat,
every query scans 2.5x more data than needed -> high CPU. The CPU
load slows down WAL replay -> replication lag increases.

Step 3 - Root cause:
The root cause is the 380 idle-in-transaction sessions. Everything
else is a downstream effect: no vacuum slots -> bloat -> high CPU
-> replication lag.

Step 4 - First action:
Terminate the idle-in-transaction sessions:
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND state_change < NOW() - INTERVAL '5 minutes';

Then immediately: set idle_in_transaction_session_timeout = '5min'
to prevent recurrence.
```

The CoT version:
- Analyzed each symptom individually (didn't just react to the scariest one)
- Found the causal chain (idle txns -> no vacuum slots -> bloat -> CPU -> lag)
- Identified the ROOT cause, not just a symptom
- Gave a precise first action

**When to use CoT:** Any time the task requires reasoning across multiple pieces of information. Debugging, architecture decisions, root cause analysis.

---

## Step 4. Structured output (JSON)

For production AI features, you need the response in a format your code can parse - not free text.

```bash
python3 << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

system = """You are a database health analyzer. You MUST respond with valid JSON only - no text before or after the JSON.

Output schema:
{
  "overall_status": "healthy" | "degraded" | "critical",
  "issues": [
    {
      "component": "string",
      "severity": "low" | "medium" | "high" | "critical",
      "description": "string",
      "action": "string"
    }
  ],
  "score": 0-100
}"""

metrics = """
CPU: 78%
Memory: 85%
Disk: 45%
Connections: 180/200
Replication lag: 800ms
Longest running query: 45 minutes
Dead tuples: 12 million
Last vacuum on orders table: 3 days ago
"""

msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=500,
    temperature=0,
    system=system,
    messages=[{"role": "user", "content": f"Analyze these database metrics:\n{metrics}"}]
)

response_text = msg.content[0].text
print("Raw response:")
print(response_text)
print()

# Parse the JSON
try:
    data = json.loads(response_text)
    print(f"Status: {data['overall_status']}")
    print(f"Health score: {data['score']}/100")
    print(f"Issues found: {len(data['issues'])}")
    for issue in data['issues']:
        print(f"  [{issue['severity'].upper()}] {issue['component']}: {issue['description']}")
except json.JSONDecodeError as e:
    print(f"Failed to parse JSON: {e}")
PYEOF
```

Expected output (yours will differ):
```
Raw response:
{
  "overall_status": "degraded",
  "issues": [
    {
      "component": "connections",
      "severity": "high",
      "description": "Connection pool at 90% capacity (180/200)",
      "action": "Investigate connection leaks, consider pgBouncer"
    },
    {
      "component": "vacuum",
      "severity": "high",
      "description": "12M dead tuples, last vacuum 3 days ago on orders",
      "action": "Run VACUUM ANALYZE orders immediately"
    },
    {
      "component": "queries",
      "severity": "medium",
      "description": "Query running for 45 minutes",
      "action": "Investigate with pg_stat_activity, consider terminating"
    },
    {
      "component": "replication",
      "severity": "low",
      "description": "800ms replication lag is within acceptable range",
      "action": "Monitor but no immediate action needed"
    }
  ],
  "score": 55
}

Status: degraded
Health score: 55/100
Issues found: 4
  [HIGH] connections: Connection pool at 90% capacity (180/200)
  [HIGH] vacuum: 12M dead tuples, last vacuum 3 days ago on orders
  [MEDIUM] queries: Query running for 45 minutes
  [LOW] replication: 800ms replication lag is within acceptable range
```

This is the pattern behind every AI-powered feature:
1. System prompt defines the JSON schema
2. User message provides the data
3. Response is valid JSON your code can parse
4. Your code takes action based on the structured data

This is exactly how dbaBrain's Sage engine will work - take metrics, produce structured recommendations.

---

## Step 5. Combining techniques

Real-world prompts combine multiple techniques. Here's a production-grade example.

```bash
python3 << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

system = """You are a database query optimizer.

Your task: analyze SQL queries and suggest improvements.

Rules:
1. Think step by step (explain your reasoning)
2. Output your final recommendation as JSON
3. Rate improvement impact as: minor (< 2x), moderate (2-10x), major (> 10x)

Output format (after your reasoning):
```json
{
  "original_query": "the input query",
  "issues": ["list of problems found"],
  "optimized_query": "the improved query",
  "expected_improvement": "minor | moderate | major",
  "reasoning": "one sentence explaining why"
}
```"""

# Few-shot example as conversation turn
messages = [
    {"role": "user", "content": "Optimize: SELECT * FROM users WHERE email LIKE '%@gmail.com'"},
    {"role": "assistant", "content": """Let me analyze this step by step:

1. `SELECT *` fetches all columns - wasteful if we only need a few
2. `LIKE '%@gmail.com'` has a leading wildcard - cannot use a standard B-tree index
3. This will always do a sequential scan regardless of indexes

Options: use a functional index on the domain part, or reverse the string matching.

```json
{
  "original_query": "SELECT * FROM users WHERE email LIKE '%@gmail.com'",
  "issues": ["SELECT * fetches unnecessary columns", "Leading wildcard prevents index usage", "Forces sequential scan"],
  "optimized_query": "SELECT id, name, email FROM users WHERE email_domain = 'gmail.com'",
  "expected_improvement": "major",
  "reasoning": "Adding a generated column email_domain with an index eliminates the sequential scan entirely"
}
```"""},
    # Real query to optimize
    {"role": "user", "content": "Optimize: SELECT o.*, u.name FROM orders o, users u WHERE o.user_id = u.id AND o.created_at > '2026-01-01' ORDER BY o.created_at DESC LIMIT 100"},
]

msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=500,
    temperature=0,
    system=system,
    messages=messages
)
print(msg.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
Let me analyze this step by step:

1. Implicit join syntax (FROM orders o, users u WHERE) - works but
   explicit JOIN is clearer and less error-prone
2. SELECT o.* - fetches all order columns when we may only need a few
3. Missing index: the ORDER BY + WHERE combo needs a composite index
   on (created_at DESC) to avoid a sort operation
4. The LIMIT 100 with ORDER BY means PostgreSQL might sort millions
   of rows just to return 100

```json
{
  "original_query": "SELECT o.*, u.name FROM orders o, users u WHERE o.user_id = u.id AND o.created_at > '2026-01-01' ORDER BY o.created_at DESC LIMIT 100",
  "issues": ["Implicit join syntax", "SELECT o.* fetches unnecessary columns", "Missing composite index on created_at for ORDER BY + filter", "Potential sort of entire result set for LIMIT"],
  "optimized_query": "SELECT o.id, o.total, o.status, o.created_at, u.name FROM orders o JOIN users u ON o.user_id = u.id WHERE o.created_at > '2026-01-01' ORDER BY o.created_at DESC LIMIT 100",
  "expected_improvement": "moderate",
  "reasoning": "Explicit join, selective columns, and a composite index on orders(created_at DESC) enables an index-only backward scan for the top 100 rows"
}
```
```

This prompt combined:
- System prompt (role + rules + output format)
- Few-shot (one example in conversation turns)
- Chain-of-thought ("think step by step")
- Structured output (JSON block)

---

## What You Learned

| Technique | When to Use | Impact |
|-----------|------------|--------|
| Zero-shot | Simple tasks the model already knows | Baseline |
| Few-shot (in prompt) | Need consistent format, quick setup | High - calibrates output |
| Few-shot (in turns) | Need very reliable format matching | Highest - model mimics exactly |
| Chain-of-thought | Complex reasoning, multi-step problems | Major accuracy improvement |
| Structured output (JSON) | Code needs to parse the response | Required for production |
| Combined techniques | Real-world production prompts | Best results |
