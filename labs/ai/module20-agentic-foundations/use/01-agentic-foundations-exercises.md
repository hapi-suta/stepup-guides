# Use 01: Agentic AI Foundations - Exercises

Apply what you learned about async Python, tool calling, and autonomous agents. Each exercise builds a working DBA automation tool.

---

## Exercise 1: Async disk space checker

Build an async function that checks disk space on multiple mount points concurrently.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 1: Async Disk Space Checker
#
# Check 6 mount points concurrently. Report which ones are
# above 80% usage. This is the most common DBA monitoring task.
#
# Skills: asyncio.gather(), async def, return_exceptions
# ============================================================

import asyncio
import random

print("Exercise 1: Async Disk Space Checker")
print("=" * 55)

# Simulated mount points (in production, use shutil.disk_usage or os.statvfs)
MOUNT_POINTS = {
    "/pgdata": {"total_gb": 500, "label": "PostgreSQL data"},
    "/pgwal": {"total_gb": 100, "label": "WAL files"},
    "/pglog": {"total_gb": 50, "label": "PostgreSQL logs"},
    "/backup": {"total_gb": 2000, "label": "Backup storage"},
    "/tmp": {"total_gb": 20, "label": "Temporary files"},
    "/": {"total_gb": 100, "label": "Root filesystem"},
}

async def check_disk_space(mount_point, config):
    """
    Check disk space on a single mount point.

    YOUR TASK: This function should:
    1. Simulate a check (await asyncio.sleep for 0.1-0.3s)
    2. Generate a random used_percent (30-98%)
    3. Return a dict with: mount, label, total_gb, used_percent, status
    4. Status should be:
       - "critical" if used_percent > 90
       - "warning" if used_percent > 80
       - "healthy" otherwise
    """
    # Simulate I/O delay
    await asyncio.sleep(random.uniform(0.1, 0.3))

    used_percent = round(random.uniform(30, 98), 1)
    used_gb = round(config["total_gb"] * used_percent / 100, 1)
    free_gb = round(config["total_gb"] - used_gb, 1)

    if used_percent > 90:
        status = "critical"
    elif used_percent > 80:
        status = "warning"
    else:
        status = "healthy"

    return {
        "mount": mount_point,
        "label": config["label"],
        "total_gb": config["total_gb"],
        "used_gb": used_gb,
        "free_gb": free_gb,
        "used_percent": used_percent,
        "status": status,
    }

async def check_all_disks():
    """Check all mount points concurrently."""
    import time
    start = time.time()

    tasks = [
        check_disk_space(mount, config)
        for mount, config in MOUNT_POINTS.items()
    ]

    results = await asyncio.gather(*tasks, return_exceptions=True)
    elapsed = time.time() - start

    # Display results
    print(f"\nDisk Space Report ({elapsed:.2f}s for {len(results)} mount points)")
    print(f"{'Mount':<12} {'Label':<20} {'Used':<10} {'Free':<10} {'Status'}")
    print("-" * 65)

    alerts = []
    for r in sorted(results, key=lambda x: x["used_percent"] if isinstance(x, dict) else 0, reverse=True):
        if isinstance(r, Exception):
            print(f"  ERROR: {r}")
            continue

        marker = "!!!" if r["status"] == "critical" else " ! " if r["status"] == "warning" else "   "
        print(f"{marker}{r['mount']:<10} {r['label']:<20} {r['used_percent']:>5.1f}%{'':<4} {r['free_gb']:>7.1f}GB  {r['status']}")

        if r["status"] in ("critical", "warning"):
            alerts.append(r)

    if alerts:
        print(f"\n  ALERTS: {len(alerts)} mount point(s) need attention!")
        for a in alerts:
            print(f"    [{a['status'].upper()}] {a['mount']} ({a['label']}): {a['used_percent']}% used, {a['free_gb']}GB free")
    else:
        print(f"\n  All mount points healthy.")

asyncio.run(check_all_disks())

print("""
Key patterns used:
  - asyncio.gather() for concurrent checks
  - return_exceptions=True for fault tolerance
  - Threshold-based alerting (80%/90%)
  - Sorted output (worst first)
""")
PYEOF
```

Expected output (yours will differ):
```
Exercise 1: Async Disk Space Checker
=======================================================

Disk Space Report (0.28s for 6 mount points)
Mount        Label                Used       Free       Status
-----------------------------------------------------------------
!!!/pglog     PostgreSQL logs      94.2%       2.9GB  critical
 ! /pgwal     WAL files            85.3%      14.7GB  warning
   /pgdata    PostgreSQL data      67.8%     161.0GB  healthy
   /backup    Backup storage       52.1%     958.0GB  healthy
   /tmp       Temporary files      45.6%      10.9GB  healthy
   /          Root filesystem      38.2%      61.8GB  healthy

  ALERTS: 2 mount point(s) need attention!
    [CRITICAL] /pglog (PostgreSQL logs): 94.2% used, 2.9GB free
    [WARNING] /pgwal (WAL files): 85.3% used, 14.7GB free
...
```

---

## Exercise 2: OpenAI tool-calling agent with 3 DBA tools

Build an agent that uses OpenAI's API with three custom database tools.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 2: OpenAI Tool-Calling Agent
#
# Build an agent with 3 tools:
#   1. check_connections - shows connection count and max
#   2. check_slow_queries - finds queries over N seconds
#   3. suggest_index - analyzes a query and suggests indexes
#
# The agent should investigate a user's question using
# the tools and provide a final recommendation.
# ============================================================

import openai
import json
import random

print("Exercise 2: OpenAI Tool-Calling Agent")
print("=" * 55)

client = openai.OpenAI()

# ---- Tool 1: Check connections ----
def check_connections(server_name):
    used = random.randint(50, 195)
    return {
        "server": server_name,
        "connections_used": used,
        "connections_max": 200,
        "percent_used": round(used / 200 * 100, 1),
        "idle_in_transaction": random.randint(0, 15),
        "idle": random.randint(10, 50),
        "active": random.randint(5, 30),
    }

# ---- Tool 2: Check slow queries ----
def check_slow_queries(server_name, min_seconds=30):
    queries = [
        {"pid": 11001, "duration_seconds": 340, "state": "active",
         "query": "SELECT o.id, o.total, c.name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.created_at BETWEEN '2025-01-01' AND '2025-12-31' ORDER BY o.total DESC"},
        {"pid": 11002, "duration_seconds": 120, "state": "active",
         "query": "UPDATE products SET last_viewed = NOW() WHERE category_id IN (SELECT id FROM categories WHERE active = true)"},
        {"pid": 11003, "duration_seconds": 60, "state": "active",
         "query": "DELETE FROM session_logs WHERE created_at < NOW() - INTERVAL '90 days'"},
    ]
    return {
        "server": server_name,
        "queries": [q for q in queries if q["duration_seconds"] >= min_seconds],
    }

# ---- Tool 3: Suggest index ----
def suggest_index(query_text):
    """Analyze a query and suggest indexes (rule-based)."""
    suggestions = []
    query_lower = query_text.lower()

    if "where" in query_lower:
        # Extract table and column from WHERE clause (simplified)
        if "created_at" in query_lower:
            suggestions.append("CREATE INDEX idx_created_at ON <table>(created_at)")
        if "category_id" in query_lower:
            suggestions.append("CREATE INDEX idx_category_id ON <table>(category_id)")
        if "customer_id" in query_lower:
            suggestions.append("CREATE INDEX idx_customer_id ON <table>(customer_id)")
        if "active" in query_lower:
            suggestions.append("CREATE INDEX idx_active ON <table>(active) WHERE active = true")

    if "order by" in query_lower:
        suggestions.append("Consider an index on the ORDER BY column for sort elimination")

    if "join" in query_lower:
        suggestions.append("Ensure join columns have indexes on both sides")

    return {
        "query": query_text[:100] + ("..." if len(query_text) > 100 else ""),
        "suggestions": suggestions if suggestions else ["No obvious index suggestions - run EXPLAIN ANALYZE for details"],
    }

TOOL_FUNCTIONS = {
    "check_connections": check_connections,
    "check_slow_queries": check_slow_queries,
    "suggest_index": suggest_index,
}

TOOLS = [
    {"type": "function", "function": {
        "name": "check_connections",
        "description": "Check connection usage on a PostgreSQL server. Shows used, max, idle, active counts.",
        "parameters": {"type": "object", "properties": {
            "server_name": {"type": "string", "description": "Server name"}
        }, "required": ["server_name"]}}},
    {"type": "function", "function": {
        "name": "check_slow_queries",
        "description": "Find queries running longer than min_seconds on a server.",
        "parameters": {"type": "object", "properties": {
            "server_name": {"type": "string", "description": "Server name"},
            "min_seconds": {"type": "integer", "description": "Minimum query duration in seconds. Default 30."}
        }, "required": ["server_name"]}}},
    {"type": "function", "function": {
        "name": "suggest_index",
        "description": "Analyze a SQL query and suggest indexes that could improve performance.",
        "parameters": {"type": "object", "properties": {
            "query_text": {"type": "string", "description": "The SQL query to analyze"}
        }, "required": ["query_text"]}}},
]

def run_agent(question):
    """Run the OpenAI agent loop."""
    print(f"\nQuestion: {question}")
    print("-" * 55)

    messages = [
        {"role": "system", "content": (
            "You are a PostgreSQL performance tuning expert. Use your tools "
            "to investigate issues. Check connections and slow queries first, "
            "then suggest indexes if you find slow queries. Be concise."
        )},
        {"role": "user", "content": question},
    ]

    for iteration in range(5):
        response = client.chat.completions.create(
            model="gpt-4o-mini", messages=messages, tools=TOOLS, tool_choice="auto",
        )
        msg = response.choices[0].message

        if msg.tool_calls:
            messages.append(msg)
            for tc in msg.tool_calls:
                name = tc.function.name
                args = json.loads(tc.function.arguments)
                print(f"  Tool: {name}({json.dumps(args)[:60]})")
                func = TOOL_FUNCTIONS.get(name)
                result = func(**args) if func else {"error": "unknown tool"}
                messages.append({"role": "tool", "tool_call_id": tc.id, "content": json.dumps(result)})
        else:
            print(f"\n  Agent: {msg.content}")
            return msg.content

    return "Max iterations reached."

# Run the agent
run_agent("pg-primary seems slow. Can you check what's going on and suggest any fixes?")

print("""
This agent follows the full investigation pattern:
  1. Check connections (is the server overloaded?)
  2. Find slow queries (what's taking long?)
  3. Suggest indexes (how to fix the slow queries?)

Each step feeds into the next. The LLM decides which
tools to call based on what it finds.
""")
PYEOF
```

Expected output (yours will differ):
```
Exercise 2: OpenAI Tool-Calling Agent
=======================================================

Question: pg-primary seems slow. Can you check what's going on and suggest any fixes?
-------------------------------------------------------
  Tool: check_connections({"server_name": "pg-primary"})
  Tool: check_slow_queries({"server_name": "pg-primary"})
  Tool: suggest_index({"query_text": "SELECT o.id, o.total, c.name FR...

  Agent: Here's what I found on pg-primary:

  **Connections:** 167/200 (83.5%) - getting high. 12 idle-in-transaction sessions need investigating.

  **Slow Queries:** 3 queries running over 30 seconds...
...
```

---

## Exercise 3: Same agent with Anthropic

Build the same agent from Exercise 2, but using Anthropic's Claude. Compare response quality.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 3: Anthropic Tool-Calling Agent (same tools)
#
# Same 3 tools as Exercise 2, but using Claude's API.
# After running both, compare response quality and style.
# ============================================================

import anthropic
import json
import random

print("Exercise 3: Anthropic Tool-Calling Agent")
print("=" * 55)

client = anthropic.Anthropic()

# Same tool functions as Exercise 2
def check_connections(server_name):
    used = random.randint(50, 195)
    return {"server": server_name, "connections_used": used, "connections_max": 200,
            "percent_used": round(used / 200 * 100, 1),
            "idle_in_transaction": random.randint(0, 15),
            "idle": random.randint(10, 50), "active": random.randint(5, 30)}

def check_slow_queries(server_name, min_seconds=30):
    queries = [
        {"pid": 11001, "duration_seconds": 340, "state": "active",
         "query": "SELECT o.id, o.total, c.name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.created_at BETWEEN '2025-01-01' AND '2025-12-31' ORDER BY o.total DESC"},
        {"pid": 11002, "duration_seconds": 120, "state": "active",
         "query": "UPDATE products SET last_viewed = NOW() WHERE category_id IN (SELECT id FROM categories WHERE active = true)"},
    ]
    return {"server": server_name, "queries": [q for q in queries if q["duration_seconds"] >= min_seconds]}

def suggest_index(query_text):
    suggestions = []
    q = query_text.lower()
    if "created_at" in q: suggestions.append("CREATE INDEX idx_created_at ON <table>(created_at)")
    if "customer_id" in q: suggestions.append("CREATE INDEX idx_customer_id ON <table>(customer_id)")
    if "category_id" in q: suggestions.append("CREATE INDEX idx_category_id ON <table>(category_id)")
    if "join" in q: suggestions.append("Ensure join columns are indexed on both sides")
    return {"query": query_text[:80] + "...", "suggestions": suggestions or ["Run EXPLAIN ANALYZE for details"]}

TOOL_FUNCTIONS = {"check_connections": check_connections, "check_slow_queries": check_slow_queries, "suggest_index": suggest_index}

TOOLS = [
    {"name": "check_connections",
     "description": "Check connection usage on a PostgreSQL server.",
     "input_schema": {"type": "object", "properties": {"server_name": {"type": "string", "description": "Server name"}}, "required": ["server_name"]}},
    {"name": "check_slow_queries",
     "description": "Find queries running longer than min_seconds.",
     "input_schema": {"type": "object", "properties": {"server_name": {"type": "string", "description": "Server"}, "min_seconds": {"type": "integer", "description": "Min seconds. Default 30."}}, "required": ["server_name"]}},
    {"name": "suggest_index",
     "description": "Analyze SQL and suggest indexes.",
     "input_schema": {"type": "object", "properties": {"query_text": {"type": "string", "description": "SQL query to analyze"}}, "required": ["query_text"]}},
]

def run_agent(question):
    print(f"\nQuestion: {question}")
    print("-" * 55)

    messages = [{"role": "user", "content": question}]
    system = ("You are a PostgreSQL performance tuning expert. Use tools to investigate. "
              "Check connections and slow queries, then suggest indexes. Be concise.")

    for iteration in range(5):
        response = client.messages.create(
            model="claude-sonnet-4-20250514", max_tokens=1024,
            system=system, tools=TOOLS, messages=messages,
        )

        if response.stop_reason == "tool_use":
            tool_blocks = [b for b in response.content if b.type == "tool_use"]
            messages.append({"role": "assistant", "content": response.content})

            results = []
            for block in tool_blocks:
                func = TOOL_FUNCTIONS.get(block.name)
                args = block.input
                print(f"  Tool: {block.name}({json.dumps(args)[:60]})")
                result = func(**args) if func else {"error": "unknown"}
                results.append({"type": "tool_result", "tool_use_id": block.id, "content": json.dumps(result)})

            messages.append({"role": "user", "content": results})

        elif response.stop_reason == "end_turn":
            text = "\n".join(b.text for b in response.content if hasattr(b, "text"))
            print(f"\n  Agent: {text}")
            return text

    return "Max iterations."

run_agent("pg-primary seems slow. Can you check what's going on and suggest any fixes?")

print("""
Compare this output with Exercise 2 (OpenAI).
Notice the differences in:
  - Investigation approach (which tools called first)
  - Response style (technical depth, formatting)
  - Actionability (specific vs general recommendations)

Both agents solve the same problem. The choice between
them depends on your priorities: cost, speed, reasoning
depth, and safety behavior.
""")
PYEOF
```

Expected output (yours will differ):
```
Exercise 3: Anthropic Tool-Calling Agent
=======================================================

Question: pg-primary seems slow. Can you check what's going on and suggest any fixes?
-------------------------------------------------------
  Tool: check_connections({"server_name": "pg-primary"})
  Tool: check_slow_queries({"server_name": "pg-primary"})
  Tool: suggest_index({"query_text": "SELECT o.id, o.total, c.name FR...

  Agent: Here's the situation on pg-primary:

  **Connection Load:** 172/200 (86%) - elevated. You have 8 idle-in-transaction sessions that should be investigated...
...
```

---

## Exercise 4: EXPLAIN ANALYZE explainer agent

Build an agent that takes EXPLAIN ANALYZE output and explains it in plain English.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 4: EXPLAIN ANALYZE Explainer
#
# Feed real EXPLAIN ANALYZE output to an LLM and get
# a plain-English explanation of what PostgreSQL is doing
# and what could be improved.
#
# No tools needed - just smart prompting.
# ============================================================

import openai
import json

print("Exercise 4: EXPLAIN ANALYZE Explainer")
print("=" * 55)

client = openai.OpenAI()

# A realistic EXPLAIN ANALYZE output
explain_output = """
Nested Loop Left Join  (cost=1.14..28456.78 rows=500 width=180) (actual time=0.089..4523.456 rows=49823 loops=1)
  ->  Seq Scan on orders o  (cost=0.00..18334.00 rows=500 width=100) (actual time=0.045..2105.234 rows=49823 loops=1)
        Filter: ((created_at >= '2025-01-01'::date) AND (created_at <= '2025-12-31'::date) AND (status = 'pending'::text))
        Rows Removed by Filter: 950177
  ->  Index Scan using customers_pkey on customers c  (cost=1.14..20.24 rows=1 width=80) (actual time=0.048..0.048 rows=1 loops=49823)
        Index Cond: (id = o.customer_id)
Planning Time: 0.234 ms
Execution Time: 4531.567 ms
"""

print(f"\nEXPLAIN ANALYZE output:")
print(f"{'.'*55}")
print(explain_output)
print(f"{'.'*55}")

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "system", "content": (
            "You are a PostgreSQL performance expert explaining EXPLAIN ANALYZE "
            "output to a DBA. For each node in the plan:\n"
            "1. Explain what PostgreSQL is doing in plain English\n"
            "2. Point out any problems (seq scans, bad estimates, slow nodes)\n"
            "3. Suggest specific improvements (indexes, query rewrites)\n"
            "4. Show the recommended index CREATE statement if applicable\n"
            "Be concise but thorough. Use bullet points."
        )},
        {"role": "user", "content": f"Explain this query plan:\n\n{explain_output}"},
    ],
    max_tokens=600,
)

print(f"\nPlain-English Explanation:")
print(f"{'-'*55}")
print(response.choices[0].message.content)

print(f"""
This is a powerful pattern for DBA agents:
  - Feed EXPLAIN ANALYZE output to an LLM
  - Get plain-English explanation + improvement suggestions
  - No tools needed - just a well-crafted prompt

In production, combine this with tools:
  1. get_active_queries() finds slow queries
  2. Run EXPLAIN ANALYZE on the slow query
  3. Feed output to LLM for analysis
  4. LLM suggests an index
  5. DBA reviews and creates the index
""")
PYEOF
```

Expected output (yours will differ):
```
Exercise 4: EXPLAIN ANALYZE Explainer
=======================================================

EXPLAIN ANALYZE output:
.......................................................
Nested Loop Left Join  (cost=1.14..28456.78 rows=500...
...
.......................................................

Plain-English Explanation:
-------------------------------------------------------
- **Sequential Scan on orders**: PostgreSQL is scanning the ENTIRE orders table (1 million rows) and filtering by date range and status. It estimated 500 rows but actually found 49,823. This is the bottleneck - 2.1 seconds just for this scan.

- **Problem**: No index on orders.created_at or orders.status. PostgreSQL must read every row to find matches.

- **Fix**: Create a composite index:
  ```sql
  CREATE INDEX idx_orders_date_status ON orders(created_at, status);
  ```
...
```

---

## Exercise 5: Async pg_stat_statements monitor

Build an async agent that monitors pg_stat_statements and alerts on new slow queries.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 5: Async pg_stat_statements Monitor
#
# Monitor pg_stat_statements across multiple databases.
# Track query patterns over time and alert when:
#   - A new slow query appears (not seen before)
#   - An existing query gets significantly slower
#   - Total query load increases
#
# DBA analogy: like a continuous pg_stat_statements audit.
# You track which queries are running, how long they take,
# and alert when something changes.
# ============================================================

import asyncio
import random
import time
from datetime import datetime

print("Exercise 5: Async pg_stat_statements Monitor")
print("=" * 55)

# Simulated pg_stat_statements data
QUERY_TEMPLATES = [
    {"queryid": 1001, "query": "SELECT * FROM orders WHERE customer_id = $1",
     "base_mean_ms": 5.0, "base_calls": 10000},
    {"queryid": 1002, "query": "INSERT INTO audit_log (event, data) VALUES ($1, $2)",
     "base_mean_ms": 2.0, "base_calls": 50000},
    {"queryid": 1003, "query": "UPDATE inventory SET quantity = quantity - $1 WHERE product_id = $2",
     "base_mean_ms": 8.0, "base_calls": 5000},
    {"queryid": 1004, "query": "SELECT c.name, COUNT(o.id) FROM customers c JOIN orders o ON c.id = o.customer_id GROUP BY c.name",
     "base_mean_ms": 150.0, "base_calls": 200},
    {"queryid": 1005, "query": "DELETE FROM session_tokens WHERE expires_at < NOW()",
     "base_mean_ms": 25.0, "base_calls": 1000},
]

# New query that appears mid-monitoring (simulating a deployment)
NEW_SLOW_QUERY = {
    "queryid": 9999,
    "query": "SELECT * FROM orders o JOIN products p ON o.product_id = p.id WHERE p.category = $1 ORDER BY o.created_at",
    "base_mean_ms": 500.0,
    "base_calls": 100,
}

class PgStatStatementsTracker:
    """
    Track pg_stat_statements over time.
    Detect new queries and performance changes.
    """

    def __init__(self):
        self.known_queries = {}  # queryid -> last known stats
        self.alerts = []

    async def poll_database(self, db_name, cycle):
        """Simulate polling pg_stat_statements."""
        await asyncio.sleep(random.uniform(0.05, 0.15))

        stats = []
        for template in QUERY_TEMPLATES:
            # Add some variance
            mean_ms = template["base_mean_ms"] * random.uniform(0.8, 1.5)
            calls = template["base_calls"] + random.randint(-100, 500)
            stats.append({
                "queryid": template["queryid"],
                "query": template["query"][:80],
                "calls": calls,
                "mean_exec_time_ms": round(mean_ms, 2),
                "total_exec_time_ms": round(mean_ms * calls, 2),
            })

        # After cycle 2, introduce the new slow query
        if cycle >= 3:
            mean_ms = NEW_SLOW_QUERY["base_mean_ms"] * random.uniform(0.9, 1.3)
            stats.append({
                "queryid": NEW_SLOW_QUERY["queryid"],
                "query": NEW_SLOW_QUERY["query"][:80],
                "calls": NEW_SLOW_QUERY["base_calls"] * (cycle - 2),
                "mean_exec_time_ms": round(mean_ms, 2),
                "total_exec_time_ms": round(mean_ms * NEW_SLOW_QUERY["base_calls"] * (cycle - 2), 2),
            })

        return {"database": db_name, "stats": stats}

    def analyze_changes(self, poll_result):
        """Compare current stats with previous snapshot."""
        db = poll_result["database"]
        cycle_alerts = []

        for stat in poll_result["stats"]:
            qid = stat["queryid"]
            key = f"{db}:{qid}"

            if key not in self.known_queries:
                # New query detected
                if stat["mean_exec_time_ms"] > 100:
                    cycle_alerts.append({
                        "type": "NEW_SLOW_QUERY",
                        "severity": "warning",
                        "database": db,
                        "queryid": qid,
                        "query": stat["query"],
                        "mean_ms": stat["mean_exec_time_ms"],
                        "message": f"New slow query detected: {stat['query'][:50]}... (avg {stat['mean_exec_time_ms']:.1f}ms)",
                    })
                self.known_queries[key] = stat
            else:
                # Known query - check for performance regression
                prev = self.known_queries[key]
                if stat["mean_exec_time_ms"] > prev["mean_exec_time_ms"] * 2:
                    cycle_alerts.append({
                        "type": "QUERY_REGRESSION",
                        "severity": "warning",
                        "database": db,
                        "queryid": qid,
                        "query": stat["query"],
                        "prev_ms": prev["mean_exec_time_ms"],
                        "curr_ms": stat["mean_exec_time_ms"],
                        "message": f"Query regression: {stat['query'][:40]}... ({prev['mean_exec_time_ms']:.1f}ms -> {stat['mean_exec_time_ms']:.1f}ms)",
                    })
                self.known_queries[key] = stat

        self.alerts.extend(cycle_alerts)
        return cycle_alerts

async def run_monitor(cycles=5, interval=1):
    """Run the pg_stat_statements monitor."""
    tracker = PgStatStatementsTracker()
    databases = ["prod-primary", "prod-analytics"]

    print(f"\nMonitoring pg_stat_statements on {databases}")
    print(f"Cycles: {cycles}, Interval: {interval}s\n")

    for cycle in range(1, cycles + 1):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] Cycle {cycle}")

        # Poll all databases concurrently
        tasks = [tracker.poll_database(db, cycle) for db in databases]
        results = await asyncio.gather(*tasks)

        # Analyze changes
        cycle_alerts = []
        for result in results:
            alerts = tracker.analyze_changes(result)
            cycle_alerts.extend(alerts)

            # Show top queries by total time
            top = sorted(result["stats"], key=lambda x: x["total_exec_time_ms"], reverse=True)[:3]
            print(f"  {result['database']}: {len(result['stats'])} queries tracked")
            for q in top:
                print(f"    qid={q['queryid']}  avg={q['mean_exec_time_ms']:>8.1f}ms  calls={q['calls']:>6}  {q['query'][:40]}...")

        if cycle_alerts:
            print(f"\n  ** ALERTS ({len(cycle_alerts)}) **")
            for a in cycle_alerts:
                print(f"  [{a['severity'].upper()}] {a['message']}")
        else:
            print(f"  No new alerts")

        print()
        if cycle < cycles:
            await asyncio.sleep(interval)

    # Final summary
    print(f"{'='*55}")
    print(f"Monitoring Summary")
    print(f"  Cycles: {cycles}")
    print(f"  Queries tracked: {len(tracker.known_queries)}")
    print(f"  Total alerts: {len(tracker.alerts)}")
    for a in tracker.alerts:
        print(f"  [{a['type']}] {a['message']}")

asyncio.run(run_monitor(cycles=5, interval=0.5))

print("""
This exercise combines:
  - Async polling (concurrent database checks)
  - State tracking (remembering previous snapshots)
  - Change detection (new queries, regressions)
  - Alert generation (actionable notifications)

In production, you'd connect this to a real LLM to:
  - Analyze WHY a new query appeared (deployment? new feature?)
  - Suggest indexes for slow queries
  - Correlate with other anomalies (connection spikes, lock waits)
""")
PYEOF
```

Expected output (yours will differ):
```
Exercise 5: Async pg_stat_statements Monitor
=======================================================

Monitoring pg_stat_statements on ['prod-primary', 'prod-analytics']
Cycles: 5, Interval: 1s

[14:30:00] Cycle 1
  prod-primary: 5 queries tracked
    qid=1002  avg=     2.3ms  calls= 50234  INSERT INTO audit_log (event, data)...
    qid=1004  avg=   178.2ms  calls=   198  SELECT c.name, COUNT(o.id) FROM cust...
    qid=1005  avg=    28.1ms  calls=  1023  DELETE FROM session_tokens WHERE expi...
  prod-analytics: 5 queries tracked
    ...
  No new alerts

[14:30:01] Cycle 3
  prod-primary: 6 queries tracked
    ...
  prod-analytics: 6 queries tracked
    ...

  ** ALERTS (2) **
  [WARNING] New slow query detected: SELECT * FROM orders o JOIN products p ON o.... (avg 523.4ms)
  [WARNING] New slow query detected: SELECT * FROM orders o JOIN products p ON o.... (avg 487.1ms)
...
```

---

## Summary

| Exercise | Skills Practiced | DBA Application |
|----------|-----------------|-----------------|
| 1. Async disk checker | asyncio.gather, thresholds | Fleet disk monitoring |
| 2. OpenAI agent | Tool calling, agent loop | AI-powered DBA assistant |
| 3. Anthropic agent | SDK comparison, tool_use | Multi-vendor flexibility |
| 4. EXPLAIN explainer | LLM prompting | Query plan analysis |
| 5. pg_stat_statements | Async monitoring, state tracking | Continuous query audit |
