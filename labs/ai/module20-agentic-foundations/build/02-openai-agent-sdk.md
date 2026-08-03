# Build 02: OpenAI Agent SDK

You know async Python. Now you'll use it to build an AI agent with OpenAI's SDK. The agent will have tools - Python functions it can call to check databases, analyze queries, and recommend actions.

---

## Step 1. Install and configure the OpenAI SDK

On your **Mac terminal**, install the SDK:

```bash
pip3 install openai
```

Set your API key as an environment variable. Open your shell profile:

```bash
vi ~/.zshrc
```

Add this line (replace with your actual key):

```
export OPENAI_API_KEY="sk-your-key-here"
```

Save and reload:

```bash
source ~/.zshrc
```

Verify it's set:

```bash
echo $OPENAI_API_KEY | head -c 10
```

Expected output:
```
sk-your-ke
```

Now test the SDK:

```bash
python3 << 'PYEOF'
import openai
import os

client = openai.OpenAI()

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Say 'OpenAI SDK working' and nothing else."}],
    max_tokens=20,
)

print(response.choices[0].message.content)
print(f"Model: {response.model}")
print(f"Tokens used: {response.usage.total_tokens}")
PYEOF
```

Expected output:
```
OpenAI SDK working
Model: gpt-4o-mini
Tokens used: 28
```

---

## Step 2. Define tools as Python functions

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# DEFINING TOOLS FOR AN AI AGENT
#
# Tools are Python functions the agent can call.
# You define them with a JSON schema so the LLM knows
# what each tool does and what arguments it expects.
#
# DBA analogy: tools are like stored procedures.
# The agent knows the function signature (name, params, return type)
# and can call them when needed.
# ============================================================

import json
import random

print("Defining DBA Agent Tools")
print("=" * 50)

# ---- Tool 1: Check replication lag ----

def check_replication_lag(server_name):
    """
    Check replication lag on a replica server.
    In production, this would run:
      SELECT EXTRACT(EPOCH FROM replay_lag)
      FROM pg_stat_replication WHERE application_name = ...;
    """
    # Simulated results
    lag_seconds = random.uniform(0, 10.0)
    return {
        "server": server_name,
        "replication_lag_seconds": round(lag_seconds, 2),
        "status": "critical" if lag_seconds > 5 else "warning" if lag_seconds > 2 else "healthy",
        "wal_position": "0/1A000060",
        "replay_position": "0/19FFE0A0",
    }

# ---- Tool 2: Get active queries ----

def get_active_queries(server_name, min_duration_seconds=0):
    """
    Get active queries from pg_stat_activity.
    In production, this would run:
      SELECT pid, state, query, now() - query_start as duration
      FROM pg_stat_activity
      WHERE state = 'active' AND now() - query_start > interval '...'
    """
    queries = [
        {"pid": 12345, "state": "active", "duration_seconds": 125.3,
         "query": "SELECT o.*, c.name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.created_at > '2026-01-01'"},
        {"pid": 12346, "state": "active", "duration_seconds": 0.5,
         "query": "UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 42"},
        {"pid": 12347, "state": "idle in transaction", "duration_seconds": 300.0,
         "query": "BEGIN; SELECT * FROM accounts WHERE balance > 10000"},
        {"pid": 12348, "state": "active", "duration_seconds": 45.2,
         "query": "CREATE INDEX CONCURRENTLY idx_orders_date ON orders(created_at)"},
    ]
    filtered = [q for q in queries if q["duration_seconds"] >= min_duration_seconds]
    return {
        "server": server_name,
        "total_active": len(filtered),
        "queries": filtered,
    }

# ---- Tool 3: Kill a query ----

def kill_query(server_name, pid, reason):
    """
    Kill a query by PID.
    In production: SELECT pg_terminate_backend(pid);
    """
    return {
        "server": server_name,
        "pid": pid,
        "action": "terminated",
        "reason": reason,
        "success": True,
        "message": f"Process {pid} terminated on {server_name}",
    }

# ---- Tool definitions for OpenAI ----
# These JSON schemas tell the LLM what tools are available

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "check_replication_lag",
            "description": "Check replication lag on a PostgreSQL replica server. Returns lag in seconds, WAL positions, and health status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "server_name": {
                        "type": "string",
                        "description": "The name of the replica server (e.g., 'pg-replica-1')",
                    },
                },
                "required": ["server_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_active_queries",
            "description": "Get active queries from pg_stat_activity on a server. Can filter by minimum duration.",
            "parameters": {
                "type": "object",
                "properties": {
                    "server_name": {
                        "type": "string",
                        "description": "The server to check",
                    },
                    "min_duration_seconds": {
                        "type": "number",
                        "description": "Only return queries running longer than this many seconds. Default 0.",
                    },
                },
                "required": ["server_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "kill_query",
            "description": "Terminate a PostgreSQL backend process by PID. USE WITH CAUTION - only for queries confirmed to be problematic.",
            "parameters": {
                "type": "object",
                "properties": {
                    "server_name": {
                        "type": "string",
                        "description": "The server where the query is running",
                    },
                    "pid": {
                        "type": "integer",
                        "description": "The process ID to terminate",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Reason for terminating the query (for audit log)",
                    },
                },
                "required": ["server_name", "pid", "reason"],
            },
        },
    },
]

# Map function names to actual functions
TOOL_FUNCTIONS = {
    "check_replication_lag": check_replication_lag,
    "get_active_queries": get_active_queries,
    "kill_query": kill_query,
}

print("\nRegistered Tools:")
for tool in TOOLS:
    func = tool["function"]
    params = list(func["parameters"]["properties"].keys())
    print(f"  {func['name']}({', '.join(params)})")
    print(f"    {func['description'][:70]}...")

# Test the tools directly
print("\nDirect tool test:")
result = check_replication_lag("pg-replica-1")
print(f"  check_replication_lag('pg-replica-1') = {json.dumps(result, indent=4)}")

print("""
Tool definitions have 3 parts:
  1. name - the function name the LLM will call
  2. description - what it does (LLM reads this to decide when to use it)
  3. parameters - JSON Schema of the arguments

DBA analogy: this is like CREATE FUNCTION in PostgreSQL.
You define the name, parameters, and what it returns.
The LLM is like an application that knows which functions
are available and calls them when needed.
""")
PYEOF
```

Expected output (yours will differ):
```
Defining DBA Agent Tools
==================================================

Registered Tools:
  check_replication_lag(server_name)
    Check replication lag on a PostgreSQL replica server. Returns lag in ...
  get_active_queries(server_name, min_duration_seconds)
    Get active queries from pg_stat_activity on a server. Can filter by ...
  kill_query(server_name, pid, reason)
    Terminate a PostgreSQL backend process by PID. USE WITH CAUTION - on...

Direct tool test:
  check_replication_lag('pg-replica-1') = {
      "server": "pg-replica-1",
      "replication_lag_seconds": 3.42,
      "status": "warning",
...
```

---

## Step 3. The agent loop - tool calling with OpenAI

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# THE AGENT LOOP
#
# This is the core pattern for every OpenAI agent:
#   1. Send message + tools to LLM
#   2. LLM responds with tool calls (or final answer)
#   3. Execute the tool calls
#   4. Send tool results back to LLM
#   5. LLM responds with final answer (or more tool calls)
#   6. Repeat until LLM gives a final answer (no tool calls)
#
# DBA analogy: like a junior DBA asking a senior DBA for help.
# Junior: "Server is slow."
# Senior: "Check pg_stat_activity." (tool call)
# Junior: runs query, shows results
# Senior: "Kill PID 12345, it's a runaway query." (tool call)
# Junior: kills it, reports back
# Senior: "Done. The table scan was caused by a missing index."
# ============================================================

import openai
import json
import random

print("OpenAI Agent Loop - DBA Assistant")
print("=" * 50)

client = openai.OpenAI()

# ---- DBA Tools (same as Step 2) ----

def check_replication_lag(server_name):
    lag = random.uniform(0, 10.0)
    return {
        "server": server_name,
        "replication_lag_seconds": round(lag, 2),
        "status": "critical" if lag > 5 else "warning" if lag > 2 else "healthy",
    }

def get_active_queries(server_name, min_duration_seconds=0):
    queries = [
        {"pid": 12345, "duration_seconds": 125.3,
         "query": "SELECT * FROM orders WHERE created_at > '2026-01-01' AND status = 'pending'",
         "state": "active"},
        {"pid": 12347, "duration_seconds": 300.0,
         "query": "BEGIN; SELECT * FROM accounts WHERE balance > 10000",
         "state": "idle in transaction"},
    ]
    return {
        "server": server_name,
        "total_active": len([q for q in queries if q["duration_seconds"] >= min_duration_seconds]),
        "queries": [q for q in queries if q["duration_seconds"] >= min_duration_seconds],
    }

def kill_query(server_name, pid, reason):
    return {
        "server": server_name,
        "pid": pid,
        "action": "terminated",
        "reason": reason,
        "success": True,
    }

TOOL_FUNCTIONS = {
    "check_replication_lag": check_replication_lag,
    "get_active_queries": get_active_queries,
    "kill_query": kill_query,
}

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "check_replication_lag",
            "description": "Check replication lag on a PostgreSQL replica. Returns lag in seconds and health status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "server_name": {"type": "string", "description": "Replica server name"},
                },
                "required": ["server_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_active_queries",
            "description": "Get active queries from pg_stat_activity. Filter by minimum duration.",
            "parameters": {
                "type": "object",
                "properties": {
                    "server_name": {"type": "string", "description": "Server to check"},
                    "min_duration_seconds": {"type": "number", "description": "Min query duration filter. Default 0."},
                },
                "required": ["server_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "kill_query",
            "description": "Terminate a backend process by PID. Only use for confirmed problematic queries.",
            "parameters": {
                "type": "object",
                "properties": {
                    "server_name": {"type": "string", "description": "Server name"},
                    "pid": {"type": "integer", "description": "Process ID to kill"},
                    "reason": {"type": "string", "description": "Reason for termination"},
                },
                "required": ["server_name", "pid", "reason"],
            },
        },
    },
]

# ---- The Agent Loop ----

def execute_tool(tool_name, arguments):
    """Execute a tool call and return the result."""
    func = TOOL_FUNCTIONS.get(tool_name)
    if not func:
        return {"error": f"Unknown tool: {tool_name}"}
    try:
        result = func(**arguments)
        return result
    except Exception as e:
        return {"error": f"Tool execution failed: {str(e)}"}

def run_agent(user_message):
    """
    Run the agent loop.

    Flow:
      1. Send user message + tool definitions
      2. If LLM wants to call tools, execute them
      3. Send results back, repeat until LLM gives final answer
    """
    print(f"\nUser: {user_message}")
    print("-" * 50)

    messages = [
        {
            "role": "system",
            "content": (
                "You are a PostgreSQL DBA assistant. You have tools to check "
                "database health, query activity, and manage processes. "
                "Always investigate before taking action. Be concise."
            ),
        },
        {"role": "user", "content": user_message},
    ]

    # Agent loop - keep going until LLM gives final answer
    max_iterations = 5  # Safety limit
    for iteration in range(max_iterations):
        print(f"\n  [Loop iteration {iteration + 1}]")

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=TOOLS,
            tool_choice="auto",  # LLM decides whether to call tools
        )

        message = response.choices[0].message

        # Check if LLM wants to call tools
        if message.tool_calls:
            print(f"  LLM wants to call {len(message.tool_calls)} tool(s):")

            # Add the assistant's message (with tool calls) to history
            messages.append(message)

            # Execute each tool call
            for tool_call in message.tool_calls:
                func_name = tool_call.function.name
                arguments = json.loads(tool_call.function.arguments)
                print(f"    -> {func_name}({json.dumps(arguments)})")

                # Execute the tool
                result = execute_tool(func_name, arguments)
                print(f"    <- {json.dumps(result)}")

                # Add tool result to message history
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "content": json.dumps(result),
                })
        else:
            # No tool calls - LLM gave a final answer
            print(f"\n  Agent: {message.content}")
            print(f"\n  [Completed in {iteration + 1} iteration(s)]")
            print(f"  [Tokens: {response.usage.total_tokens}]")
            return message.content

    print("  [Hit max iterations - stopping]")
    return "Agent reached maximum iterations without a final answer."

# ---- Run the agent ----

# Scenario 1: Check replication health
run_agent("Check the replication lag on pg-replica-1. Is it healthy?")

# Scenario 2: Find and handle slow queries
run_agent("There are reports of slow queries on pg-primary. Find any queries running longer than 60 seconds and tell me what to do.")

print("""
The agent loop pattern:
  1. User sends a message
  2. LLM receives message + tool definitions
  3. LLM decides: call a tool OR give a final answer
  4. If tool call: execute it, send result back, go to step 3
  5. If final answer: return it to the user

This loop can run for multiple iterations. The LLM might:
  - Call one tool, then another based on the first result
  - Call multiple tools at once
  - Give an answer immediately without any tools

DBA analogy: like an escalation path.
  Check pg_stat_activity -> find slow query -> investigate ->
  decide to kill or wait -> report back.
  Each step depends on the previous one.
""")
PYEOF
```

Expected output (yours will differ):
```
OpenAI Agent Loop - DBA Assistant
==================================================

User: Check the replication lag on pg-replica-1. Is it healthy?
--------------------------------------------------

  [Loop iteration 1]
  LLM wants to call 1 tool(s):
    -> check_replication_lag({"server_name": "pg-replica-1"})
    <- {"server": "pg-replica-1", "replication_lag_seconds": 3.42, "status": "warning"}

  [Loop iteration 2]

  Agent: The replication lag on pg-replica-1 is 3.42 seconds with a "warning" status. This is elevated but not critical. I'd recommend monitoring it closely - if it continues to climb above 5 seconds, you should investigate the replica's I/O and network.

  [Completed in 2 iteration(s)]
  [Tokens: 245]
...
```

---

## Step 4. Structured outputs for reliable parsing

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# STRUCTURED OUTPUTS (JSON MODE)
#
# When your agent needs to return structured data (not prose),
# use JSON mode or response_format to get reliable parsing.
#
# DBA analogy: like using COPY with CSV format instead of
# \pset format. You get predictable, parseable output.
# ============================================================

import openai
import json

print("Structured Outputs - JSON Mode")
print("=" * 50)

client = openai.OpenAI()

# ---- JSON Mode ----

print("\n1. JSON Mode (guaranteed valid JSON):")

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {
            "role": "system",
            "content": (
                "You are a PostgreSQL diagnostic tool. Always respond with "
                "JSON containing: category (performance|storage|replication|"
                "connectivity|security|backup), severity (P1-P4), "
                "root_cause (string), and recommended_actions (list of strings)."
            ),
        },
        {
            "role": "user",
            "content": "Alert: pg-replica-2 replication lag is 45 seconds and climbing. WAL receiver process restarted 3 times in the last hour.",
        },
    ],
    response_format={"type": "json_object"},
    max_tokens=300,
)

result = json.loads(response.choices[0].message.content)
print(f"  Parsed JSON:")
print(f"  {json.dumps(result, indent=4)}")

# ---- Using structured output for agent decisions ----

print("\n2. Agent decision as structured output:")

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {
            "role": "system",
            "content": (
                "You are an autonomous DBA agent deciding what to do next. "
                "Respond with JSON: "
                '{"action": "investigate|alert|remediate|ignore", '
                '"tool_to_call": "tool name or null", '
                '"arguments": {}, '
                '"reasoning": "why this action"}'
            ),
        },
        {
            "role": "user",
            "content": "Observation: pg-primary has 195/200 connections used (97.5%). 15 connections are idle in transaction for over 10 minutes.",
        },
    ],
    response_format={"type": "json_object"},
    max_tokens=200,
)

decision = json.loads(response.choices[0].message.content)
print(f"  Agent decision:")
print(f"  {json.dumps(decision, indent=4)}")

print("""
Why structured outputs matter for agents:
  - Agents need to PARSE LLM responses to take action
  - Free-text responses are hard to parse reliably
  - JSON mode guarantees valid JSON output
  - You define the schema, the LLM fills in the values

DBA analogy: like the difference between:
  psql -c "SELECT * FROM pg_stat_activity"  (human-readable)
  psql -t -A -F',' -c "SELECT ..."          (machine-parseable CSV)
Both have the same data. The second is reliable to parse.
""")
PYEOF
```

Expected output (yours will differ):
```
Structured Outputs - JSON Mode
==================================================

1. JSON Mode (guaranteed valid JSON):
  Parsed JSON:
  {
      "category": "replication",
      "severity": "P1",
      "root_cause": "WAL receiver instability causing growing replication lag",
      "recommended_actions": [
          "Check network connectivity between primary and replica",
          "Review pg_stat_replication on primary for send/write/flush lag",
          "Check replica disk I/O and available space",
          "Consider restarting the WAL receiver if lag continues"
      ]
  }
...
```

---

## Step 5. Streaming responses

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# STREAMING RESPONSES
#
# For long agent responses, streaming shows output in real-time
# instead of waiting for the entire response to complete.
#
# DBA analogy: like \watch in psql. You see results as they
# come in, not after the entire query batch finishes.
# ============================================================

import openai

print("Streaming Responses")
print("=" * 50)

client = openai.OpenAI()

print("\n1. Non-streaming (wait for full response):")
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "system", "content": "You are a PostgreSQL DBA. Be concise."},
        {"role": "user", "content": "Explain 3 things to check when replication lag increases. Keep it short."},
    ],
    max_tokens=200,
)
print(f"  {response.choices[0].message.content}")

print(f"\n2. Streaming (see tokens as they arrive):")
print("  ", end="", flush=True)

stream = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "system", "content": "You are a PostgreSQL DBA. Be concise."},
        {"role": "user", "content": "What are 3 common causes of connection exhaustion?"},
    ],
    max_tokens=200,
    stream=True,  # Enable streaming
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)

print()  # New line after streaming

print("""
When to use streaming:
  - Agent is explaining a complex diagnosis (long response)
  - User is watching agent work in real-time
  - You want to show progress during long agent chains

When NOT to use streaming:
  - Agent is making tool calls (you need the full response to parse)
  - Response will be parsed as JSON (wait for complete JSON)
  - Backend processing (no human watching)
""")
PYEOF
```

Expected output (yours will differ):
```
Streaming Responses
==================================================

1. Non-streaming (wait for full response):
  1. Network: Check bandwidth and latency between primary and replica...
  2. Disk I/O: Verify the replica can write WAL fast enough...
  3. Heavy writes: Large transactions on primary generate more WAL...

2. Streaming (see tokens as they arrive):
  1. Connection pool misconfiguration - applications opening connections but not closing them...
  2. Idle in transaction - sessions holding connections while doing nothing...
  3. Missing connection pooler - no PgBouncer or pgpool to manage connection reuse...
...
```

---

## Step 6. Cost tracking and token management

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# COST TRACKING AND TOKEN MANAGEMENT
#
# Every API call costs money. A DBA agent that runs 24/7
# can rack up serious costs if you're not tracking.
#
# DBA analogy: like monitoring pg_stat_statements for
# expensive queries. You track calls, duration, and cost
# so you can optimize.
# ============================================================

import openai
import json

print("Cost Tracking and Token Management")
print("=" * 50)

client = openai.OpenAI()

# ---- Token cost tracking ----

class CostTracker:
    """
    Track API costs across agent sessions.

    DBA analogy: like pg_stat_statements tracking query costs.
    You see total calls, tokens, and estimated cost.
    """

    # Pricing per 1M tokens (as of mid-2026, check current pricing)
    PRICING = {
        "gpt-4o-mini": {"input": 0.15, "output": 0.60},
        "gpt-4o": {"input": 2.50, "output": 10.00},
        "gpt-4.1-mini": {"input": 0.40, "output": 1.60},
        "gpt-4.1": {"input": 2.00, "output": 8.00},
    }

    def __init__(self):
        self.calls = []
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.total_cost_usd = 0.0

    def track(self, response):
        """Track a single API response."""
        model = response.model
        usage = response.usage

        # Calculate cost
        pricing = self.PRICING.get(model, {"input": 5.0, "output": 15.0})
        input_cost = (usage.prompt_tokens / 1_000_000) * pricing["input"]
        output_cost = (usage.completion_tokens / 1_000_000) * pricing["output"]
        total_cost = input_cost + output_cost

        self.calls.append({
            "model": model,
            "input_tokens": usage.prompt_tokens,
            "output_tokens": usage.completion_tokens,
            "cost_usd": total_cost,
        })

        self.total_input_tokens += usage.prompt_tokens
        self.total_output_tokens += usage.completion_tokens
        self.total_cost_usd += total_cost

        return total_cost

    def report(self):
        """Print a cost report."""
        print(f"\n  Cost Report ({len(self.calls)} API calls)")
        print(f"  {'-' * 50}")
        print(f"  Total input tokens:  {self.total_input_tokens:,}")
        print(f"  Total output tokens: {self.total_output_tokens:,}")
        print(f"  Total tokens:        {self.total_input_tokens + self.total_output_tokens:,}")
        print(f"  Estimated cost:      ${self.total_cost_usd:.6f}")
        print(f"  {'-' * 50}")

        # Project daily/monthly costs
        if self.calls:
            avg_cost = self.total_cost_usd / len(self.calls)
            print(f"  Avg cost per call:   ${avg_cost:.6f}")
            print(f"  If 100 calls/day:    ${avg_cost * 100:.4f}/day")
            print(f"  If 100 calls/day:    ${avg_cost * 100 * 30:.2f}/month")

    def per_call_breakdown(self):
        """Show each call's cost."""
        for i, call in enumerate(self.calls):
            print(f"  Call {i+1}: {call['model']} - "
                  f"in={call['input_tokens']}, out={call['output_tokens']}, "
                  f"cost=${call['cost_usd']:.6f}")


# ---- Demo: track costs across multiple calls ----

tracker = CostTracker()

print("\nMaking 3 agent calls and tracking costs...\n")

scenarios = [
    "Check if pg-replica-1 replication lag is acceptable.",
    "There are slow queries on pg-primary. What should I investigate?",
    "A connection spike hit pg-analytics. What are the likely causes?",
]

for scenario in scenarios:
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are a PostgreSQL DBA. Be concise (2-3 sentences)."},
            {"role": "user", "content": scenario},
        ],
        max_tokens=100,
    )
    cost = tracker.track(response)
    print(f"  Q: {scenario[:60]}...")
    print(f"  A: {response.choices[0].message.content[:80]}...")
    print(f"  Cost: ${cost:.6f}")
    print()

tracker.per_call_breakdown()
tracker.report()

print("""
Cost management tips for DBA agents:
  1. Use gpt-4o-mini for routine checks (10-20x cheaper than gpt-4o)
  2. Reserve gpt-4o for complex diagnostics
  3. Set max_tokens to limit response length
  4. Cache common queries (don't ask the same thing twice)
  5. Batch related checks into single prompts
  6. Monitor daily spend with alerts (like monitoring disk space)

DBA parallel: like pg_stat_statements tracking query costs.
  - total_calls = calls (number of times executed)
  - total_tokens = rows (total rows processed)
  - total_cost = total_exec_time (cumulative resource usage)
  - avg_cost_per_call = mean_exec_time (average per call)
""")
PYEOF
```

Expected output (yours will differ):
```
Cost Tracking and Token Management
==================================================

Making 3 agent calls and tracking costs...

  Q: Check if pg-replica-1 replication lag is acceptable....
  A: Replication lag acceptability depends on your RPO. Generally, under 1 second ...
  Cost: $0.000045

  Q: There are slow queries on pg-primary. What should I investigate?...
  A: Start with pg_stat_activity to find active queries sorted by duration...
  Cost: $0.000052

  Q: A connection spike hit pg-analytics. What are the likely causes?...
  A: Common causes: application deployment without connection pooling, a batch job...
  Cost: $0.000048

  Call 1: gpt-4o-mini - in=38, out=52, cost=$0.000045
  Call 2: gpt-4o-mini - in=40, out=61, cost=$0.000052
  Call 3: gpt-4o-mini - in=39, out=55, cost=$0.000048

  Cost Report (3 API calls)
  --------------------------------------------------
  Total input tokens:  117
  Total output tokens: 168
  Total tokens:        285
  Estimated cost:      $0.000145
...
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Tool definitions | JSON schemas describing functions the LLM can call | CREATE FUNCTION signatures |
| `tool_calls` in response | LLM requesting to execute specific tools | Application calling stored procedures |
| Agent loop | Iterative send-execute-respond cycle | Investigation escalation path |
| `role: "tool"` messages | Sending tool results back to the LLM | Returning query results to the application |
| JSON mode | Guaranteed structured output | COPY CSV format vs psql display |
| Streaming | Real-time token delivery | `\watch` in psql |
| Cost tracking | Monitor API spend per call | pg_stat_statements cost tracking |
