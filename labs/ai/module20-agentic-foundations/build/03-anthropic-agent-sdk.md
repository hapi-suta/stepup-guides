# Build 03: Anthropic Agent SDK

Now you'll build the same DBA agent using Anthropic's Claude SDK. The tools are the same, but the API pattern is different. By the end, you'll know both SDKs and when to pick each one.

---

## Step 1. Install and configure the Anthropic SDK

On your **Mac terminal**, install the SDK:

```bash
pip3 install anthropic
```

Set your API key. Open your shell profile:

```bash
vi ~/.zshrc
```

Add this line (replace with your actual key):

```
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

Save and reload:

```bash
source ~/.zshrc
```

Verify it's set:

```bash
echo $ANTHROPIC_API_KEY | head -c 12
```

Expected output:
```
sk-ant-your-
```

Test the SDK:

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

response = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=50,
    messages=[{"role": "user", "content": "Say 'Anthropic SDK working' and nothing else."}],
)

print(response.content[0].text)
print(f"Model: {response.model}")
print(f"Input tokens: {response.usage.input_tokens}")
print(f"Output tokens: {response.usage.output_tokens}")
PYEOF
```

Expected output:
```
Anthropic SDK working
Model: claude-sonnet-4-20250514
Input tokens: 18
Output tokens: 7
```

---

## Step 2. Define tools with JSON schema

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ANTHROPIC TOOL DEFINITIONS
#
# Same DBA tools as BUILD 02, but Anthropic uses a different
# schema format. The tools are defined with 'input_schema'
# instead of 'parameters'.
#
# DBA analogy: same stored procedures, different client library.
# pg_dump and pg_basebackup both back up data but with
# different flags and output formats.
# ============================================================

import json
import random

print("Anthropic Tool Definitions")
print("=" * 50)

# ---- Same DBA tools ----

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
         "query": "SELECT * FROM orders WHERE created_at > '2026-01-01'",
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
        "server": server_name, "pid": pid,
        "action": "terminated", "reason": reason, "success": True,
    }

TOOL_FUNCTIONS = {
    "check_replication_lag": check_replication_lag,
    "get_active_queries": get_active_queries,
    "kill_query": kill_query,
}

# ---- Anthropic tool schema ----
# Key difference: Anthropic uses 'input_schema' (not 'parameters')
# and the tool is a flat dict (not nested under 'function')

TOOLS = [
    {
        "name": "check_replication_lag",
        "description": "Check replication lag on a PostgreSQL replica. Returns lag in seconds and health status.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server_name": {
                    "type": "string",
                    "description": "The replica server name (e.g., 'pg-replica-1')",
                },
            },
            "required": ["server_name"],
        },
    },
    {
        "name": "get_active_queries",
        "description": "Get active queries from pg_stat_activity on a server. Filter by minimum duration.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server_name": {
                    "type": "string",
                    "description": "Server to check",
                },
                "min_duration_seconds": {
                    "type": "number",
                    "description": "Only return queries running longer than this. Default 0.",
                },
            },
            "required": ["server_name"],
        },
    },
    {
        "name": "kill_query",
        "description": "Terminate a backend process by PID. Only for confirmed problematic queries.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server_name": {"type": "string", "description": "Server name"},
                "pid": {"type": "integer", "description": "Process ID to terminate"},
                "reason": {"type": "string", "description": "Reason for termination (audit log)"},
            },
            "required": ["server_name", "pid", "reason"],
        },
    },
]

# ---- Compare OpenAI vs Anthropic tool format ----

print("\nOpenAI format:")
print('  {"type": "function", "function": {"name": "...", "parameters": {...}}}')

print("\nAnthropic format:")
print('  {"name": "...", "input_schema": {...}}')

print("\nKey differences:")
print("  1. Anthropic: flat dict. OpenAI: nested under 'function'")
print("  2. Anthropic: 'input_schema'. OpenAI: 'parameters'")
print("  3. Both use JSON Schema for parameter definitions")

print("\nRegistered Anthropic tools:")
for tool in TOOLS:
    params = list(tool["input_schema"]["properties"].keys())
    print(f"  {tool['name']}({', '.join(params)})")

print("""
The actual tool FUNCTIONS are identical between SDKs.
Only the SCHEMA FORMAT differs. Your check_replication_lag()
function works the same way regardless of which SDK calls it.

DBA analogy: like pg_dump vs pg_basebackup. The underlying
data (your tools) is the same. The interface (how you define
and call them) is different.
""")
PYEOF
```

Expected output (yours will differ):
```
Anthropic Tool Definitions
==================================================

OpenAI format:
  {"type": "function", "function": {"name": "...", "parameters": {...}}}

Anthropic format:
  {"name": "...", "input_schema": {...}}

Key differences:
  1. Anthropic: flat dict. OpenAI: nested under 'function'
  2. Anthropic: 'input_schema'. OpenAI: 'parameters'
  3. Both use JSON Schema for parameter definitions

Registered Anthropic tools:
  check_replication_lag(server_name)
  get_active_queries(server_name, min_duration_seconds)
  kill_query(server_name, pid, reason)
...
```

---

## Step 3. Tool use flow with Anthropic

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ANTHROPIC TOOL USE FLOW
#
# Anthropic's tool use has a different message flow than OpenAI:
#
# OpenAI:
#   user msg -> assistant msg (with tool_calls) -> tool msg -> assistant msg
#
# Anthropic:
#   user msg -> assistant msg (with tool_use blocks)
#   -> user msg (with tool_result blocks) -> assistant msg
#
# Key difference: in Anthropic, tool results go in a "user" message
# with content blocks. In OpenAI, they go in a "tool" role message.
# ============================================================

import anthropic
import json
import random

print("Anthropic Tool Use Flow - DBA Agent")
print("=" * 50)

client = anthropic.Anthropic()

# ---- DBA tools (same functions) ----

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
         "query": "SELECT * FROM orders WHERE created_at > '2026-01-01'",
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
        "server": server_name, "pid": pid,
        "action": "terminated", "reason": reason, "success": True,
    }

TOOL_FUNCTIONS = {
    "check_replication_lag": check_replication_lag,
    "get_active_queries": get_active_queries,
    "kill_query": kill_query,
}

TOOLS = [
    {
        "name": "check_replication_lag",
        "description": "Check replication lag on a PostgreSQL replica. Returns lag in seconds and health status.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server_name": {"type": "string", "description": "Replica server name"},
            },
            "required": ["server_name"],
        },
    },
    {
        "name": "get_active_queries",
        "description": "Get active queries from pg_stat_activity. Filter by minimum duration.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server_name": {"type": "string", "description": "Server to check"},
                "min_duration_seconds": {"type": "number", "description": "Min duration filter. Default 0."},
            },
            "required": ["server_name"],
        },
    },
    {
        "name": "kill_query",
        "description": "Terminate a backend process by PID. Only for confirmed problematic queries.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server_name": {"type": "string", "description": "Server name"},
                "pid": {"type": "integer", "description": "Process ID to terminate"},
                "reason": {"type": "string", "description": "Reason for termination"},
            },
            "required": ["server_name", "pid", "reason"],
        },
    },
]

# ---- The Anthropic Agent Loop ----

def run_agent(user_message):
    """
    Run the Anthropic agent loop.

    Key difference from OpenAI:
      - Tool results go in a "user" message with tool_result content blocks
      - Response has content blocks (text + tool_use), not a single message
      - stop_reason tells you if the model wants to use tools
    """
    print(f"\nUser: {user_message}")
    print("-" * 50)

    messages = [{"role": "user", "content": user_message}]

    system_prompt = (
        "You are a PostgreSQL DBA assistant. You have tools to check "
        "database health, query activity, and manage processes. "
        "Always investigate before taking action. Be concise."
    )

    max_iterations = 5
    for iteration in range(max_iterations):
        print(f"\n  [Loop iteration {iteration + 1}]")

        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            system=system_prompt,
            tools=TOOLS,
            messages=messages,
        )

        # Check stop reason
        # "tool_use" = model wants to call tools
        # "end_turn" = model gave a final answer
        print(f"  Stop reason: {response.stop_reason}")

        if response.stop_reason == "tool_use":
            # Extract tool use blocks from response content
            tool_use_blocks = [
                block for block in response.content
                if block.type == "tool_use"
            ]

            print(f"  Claude wants to call {len(tool_use_blocks)} tool(s):")

            # Add assistant's response to message history
            messages.append({"role": "assistant", "content": response.content})

            # Execute each tool and build tool_result blocks
            tool_results = []
            for block in tool_use_blocks:
                func_name = block.name
                arguments = block.input
                tool_id = block.id

                print(f"    -> {func_name}({json.dumps(arguments)})")

                # Execute the tool
                func = TOOL_FUNCTIONS.get(func_name)
                if func:
                    try:
                        result = func(**arguments)
                    except Exception as e:
                        result = {"error": str(e)}
                else:
                    result = {"error": f"Unknown tool: {func_name}"}

                print(f"    <- {json.dumps(result)}")

                # Build tool_result content block
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": json.dumps(result),
                })

            # Send tool results back as a "user" message
            # THIS IS THE KEY DIFFERENCE FROM OPENAI
            # OpenAI: role="tool", Anthropic: role="user" with tool_result blocks
            messages.append({"role": "user", "content": tool_results})

        elif response.stop_reason == "end_turn":
            # Final answer - extract text blocks
            text_blocks = [
                block.text for block in response.content
                if hasattr(block, "text")
            ]
            answer = "\n".join(text_blocks)
            print(f"\n  Agent: {answer}")
            print(f"\n  [Completed in {iteration + 1} iteration(s)]")
            print(f"  [Tokens: in={response.usage.input_tokens}, out={response.usage.output_tokens}]")
            return answer

    print("  [Hit max iterations]")
    return "Agent reached maximum iterations."

# ---- Run the agent ----

run_agent("Check the replication lag on pg-replica-1. Is it healthy?")

run_agent("Find any slow queries on pg-primary running longer than 60 seconds. What should I do about them?")

print("""
Anthropic tool use flow (compared to OpenAI):

  Step 1: Send user message + tools
    OpenAI:    messages=[...], tools=[...]
    Anthropic: messages=[...], tools=[...], system="..."

  Step 2: Model responds with tool calls
    OpenAI:    response.choices[0].message.tool_calls = [...]
    Anthropic: response.content = [TextBlock(...), ToolUseBlock(...)]
               response.stop_reason = "tool_use"

  Step 3: Send tool results back
    OpenAI:    {"role": "tool", "tool_call_id": "...", "content": "..."}
    Anthropic: {"role": "user", "content": [{"type": "tool_result", ...}]}

  Step 4: Model gives final answer
    OpenAI:    response.choices[0].message.content
    Anthropic: response.content = [TextBlock("...")]
               response.stop_reason = "end_turn"
""")
PYEOF
```

Expected output (yours will differ):
```
Anthropic Tool Use Flow - DBA Agent
==================================================

User: Check the replication lag on pg-replica-1. Is it healthy?
--------------------------------------------------

  [Loop iteration 1]
  Stop reason: tool_use
  Claude wants to call 1 tool(s):
    -> check_replication_lag({"server_name": "pg-replica-1"})
    <- {"server": "pg-replica-1", "replication_lag_seconds": 2.34, "status": "warning"}

  [Loop iteration 2]
  Stop reason: end_turn

  Agent: The replication lag on pg-replica-1 is 2.34 seconds, which puts it in "warning" status. While not critical, this is above the ideal sub-second range. I'd recommend monitoring it - if it continues climbing past 5 seconds, investigate network throughput and disk I/O on the replica.

  [Completed in 2 iteration(s)]
  [Tokens: in=412, out=78]
...
```

---

## Step 4. Extended thinking for complex diagnostics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXTENDED THINKING
#
# Anthropic's Claude has an "extended thinking" mode where
# the model shows its reasoning process before answering.
# This is useful for complex database diagnostics where
# you want to see HOW the agent reached its conclusion.
#
# DBA analogy: like EXPLAIN ANALYZE for AI reasoning.
# You see the "query plan" (thinking) before the "result".
# ============================================================

import anthropic
import json

print("Extended Thinking - Complex Database Diagnostics")
print("=" * 50)

client = anthropic.Anthropic()

# Complex diagnostic scenario
scenario = """
Production incident on pg-primary-1:
- Connection count: 195/200 (97.5%)
- 12 connections are "idle in transaction" for 15+ minutes
- Replication lag on pg-replica-1: 45 seconds and climbing
- Disk usage: 92% on /pgdata
- autovacuum is running on 4 large tables simultaneously
- Application team reports intermittent 5-second query timeouts
- This started 30 minutes ago after a deployment

What is the most likely root cause, and what should I do first?
"""

print(f"\nScenario: {scenario[:100]}...")
print("-" * 50)

response = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=16000,
    thinking={
        "type": "enabled",
        "budget_tokens": 10000,  # Max tokens for thinking
    },
    messages=[
        {
            "role": "user",
            "content": f"You are a senior PostgreSQL DBA with 15 years of experience. Analyze this production incident:\n\n{scenario}",
        },
    ],
)

# Process response content blocks
for block in response.content:
    if block.type == "thinking":
        print(f"\n  [THINKING - Claude's reasoning process]")
        print(f"  {'.' * 50}")
        # Show first 800 chars of thinking to keep output manageable
        thinking_text = block.thinking
        if len(thinking_text) > 800:
            print(f"  {thinking_text[:800]}...")
            print(f"  [... {len(thinking_text)} total chars of reasoning]")
        else:
            print(f"  {thinking_text}")
        print(f"  {'.' * 50}")

    elif block.type == "text":
        print(f"\n  [ANSWER]")
        print(f"  {block.text}")

print(f"\n  Tokens: in={response.usage.input_tokens}, out={response.usage.output_tokens}")

print("""
Extended thinking is valuable when:
  - Diagnosing complex production incidents (multiple interacting symptoms)
  - The agent needs to reason through cause-and-effect chains
  - You want to audit WHY the agent recommended a specific action
  - Training junior DBAs (show the reasoning, not just the answer)

Cost note: thinking tokens count toward output tokens.
Use budget_tokens to cap thinking cost.

DBA analogy: EXPLAIN ANALYZE shows you HOW PostgreSQL executed
a query (which indexes, which join methods, actual row counts).
Extended thinking shows you HOW Claude analyzed the problem
(which symptoms it connected, what it ruled out, why it
prioritized certain actions).
""")
PYEOF
```

Expected output (yours will differ):
```
Extended Thinking - Complex Database Diagnostics
==================================================

Scenario: Production incident on pg-primary-1:
- Connection count: 195/200 (97.5%)
- 12 connecti...
--------------------------------------------------

  [THINKING - Claude's reasoning process]
  ..................................................
  Let me analyze this incident systematically. The key symptoms are:
  1. Near connection exhaustion (195/200)
  2. 12 idle in transaction connections (holding locks)
  3. Growing replication lag (45s - suggests heavy write load)
  4. High disk usage (92%)
  5. 4 concurrent autovacuums (competing for I/O)
  6. Started after a deployment

  The deployment correlation is strong. Let me think about what
  a deployment could cause...
  [... 2341 total chars of reasoning]
  ..................................................

  [ANSWER]
  Root cause analysis: The deployment likely introduced a connection
  leak or changed transaction handling, causing connections to stay
  open in "idle in transaction" state...
...
```

---

## Step 5. Side-by-side comparison - OpenAI vs Anthropic

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# SIDE-BY-SIDE COMPARISON
#
# Same DBA question, both SDKs, compared on:
# speed, response quality, token usage, and cost.
# ============================================================

import openai
import anthropic
import json
import time

print("OpenAI vs Anthropic - Side by Side Comparison")
print("=" * 55)

openai_client = openai.OpenAI()
anthropic_client = anthropic.Anthropic()

# The same DBA question for both
question = (
    "A PostgreSQL primary server has 190/200 connections used. "
    "pg_stat_activity shows 30 connections in 'idle in transaction' state, "
    "some for over 10 minutes. The application team says they deployed "
    "a new microservice 20 minutes ago. "
    "What's the most likely cause and what should I do first?"
)

system_prompt = (
    "You are a senior PostgreSQL DBA. Diagnose the issue and "
    "recommend specific actions. Be concise (3-5 sentences max)."
)

# ---- OpenAI ----

print(f"\n{'='*55}")
print("OpenAI (gpt-4o-mini)")
print(f"{'='*55}")

start = time.time()
openai_response = openai_client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": question},
    ],
    max_tokens=300,
)
openai_time = time.time() - start

openai_answer = openai_response.choices[0].message.content
openai_in = openai_response.usage.prompt_tokens
openai_out = openai_response.usage.completion_tokens

print(f"  Time: {openai_time:.2f}s")
print(f"  Tokens: in={openai_in}, out={openai_out}")
print(f"  Cost: ~${(openai_in * 0.15 + openai_out * 0.60) / 1_000_000:.6f}")
print(f"  Answer:\n  {openai_answer}")

# ---- Anthropic ----

print(f"\n{'='*55}")
print("Anthropic (claude-sonnet-4-20250514)")
print(f"{'='*55}")

start = time.time()
anthropic_response = anthropic_client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    system=system_prompt,
    messages=[{"role": "user", "content": question}],
)
anthropic_time = time.time() - start

anthropic_answer = anthropic_response.content[0].text
anthropic_in = anthropic_response.usage.input_tokens
anthropic_out = anthropic_response.usage.output_tokens

print(f"  Time: {anthropic_time:.2f}s")
print(f"  Tokens: in={anthropic_in}, out={anthropic_out}")
print(f"  Cost: ~${(anthropic_in * 3.0 + anthropic_out * 15.0) / 1_000_000:.6f}")
print(f"  Answer:\n  {anthropic_answer}")

# ---- Comparison ----

print(f"\n{'='*55}")
print("Comparison Summary")
print(f"{'='*55}")
print(f"  {'Metric':<25} {'OpenAI':<20} {'Anthropic':<20}")
print(f"  {'-'*65}")
print(f"  {'Response time':<25} {openai_time:.2f}s{'':<15} {anthropic_time:.2f}s")
print(f"  {'Input tokens':<25} {openai_in:<20} {anthropic_in:<20}")
print(f"  {'Output tokens':<25} {openai_out:<20} {anthropic_out:<20}")

faster = "OpenAI" if openai_time < anthropic_time else "Anthropic"
print(f"\n  Faster: {faster}")

print("""
When to use each:

  OpenAI (gpt-4o-mini / gpt-4o):
    + Fastest response times for simple queries
    + Cheapest for high-volume routine checks
    + Good structured output support
    + Large ecosystem of fine-tuned models
    Best for: routine monitoring, high-volume checks, cost-sensitive

  Anthropic (Claude Sonnet / Opus):
    + Extended thinking for complex reasoning
    + Strong at following detailed instructions
    + Excellent at multi-step tool use chains
    + Better at refusing dangerous actions (safety)
    Best for: complex diagnostics, safety-critical agents, detailed analysis

  Production pattern: use gpt-4o-mini for routine checks (cheap, fast)
  and Claude for complex diagnostics (better reasoning). Route based
  on complexity.

DBA analogy: like choosing between pg_stat_statements (lightweight,
always-on monitoring) and auto_explain with ANALYZE (detailed but
more expensive). Use the right tool for the right job.
""")
PYEOF
```

Expected output (yours will differ):
```
OpenAI vs Anthropic - Side by Side Comparison
=======================================================

=======================================================
OpenAI (gpt-4o-mini)
=======================================================
  Time: 1.23s
  Tokens: in=98, out=142
  Cost: ~$0.000100
  Answer:
  The most likely cause is the new microservice deployment introduced a connection leak - it's opening database connections but not closing them properly...

=======================================================
Anthropic (claude-sonnet-4-20250514)
=======================================================
  Time: 2.15s
  Tokens: in=102, out=158
  Cost: ~$0.002676
  Answer:
  The idle-in-transaction connections correlating with the deployment 20 minutes ago strongly suggests the new microservice has a connection handling bug...

=======================================================
Comparison Summary
=======================================================
  Metric                    OpenAI               Anthropic
  -----------------------------------------------------------------
  Response time             1.23s                2.15s
  Input tokens              98                   102
  Output tokens             142                  158

  Faster: OpenAI
...
```

---

## Step 6. Building a complete Anthropic DBA agent

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# COMPLETE ANTHROPIC DBA AGENT
#
# Full agent with tools, memory, and multi-turn conversation.
# This mirrors BUILD 02's OpenAI agent but with Anthropic's SDK.
# ============================================================

import anthropic
import json
import random

print("Complete Anthropic DBA Agent")
print("=" * 50)

client = anthropic.Anthropic()

# ---- DBA Tools ----

def check_replication_lag(server_name):
    lag = random.uniform(0, 10.0)
    return {"server": server_name, "replication_lag_seconds": round(lag, 2),
            "status": "critical" if lag > 5 else "warning" if lag > 2 else "healthy"}

def get_active_queries(server_name, min_duration_seconds=0):
    queries = [
        {"pid": 12345, "duration_seconds": 125.3, "state": "active",
         "query": "SELECT * FROM orders WHERE status = 'pending'"},
        {"pid": 12347, "duration_seconds": 300.0, "state": "idle in transaction",
         "query": "BEGIN; SELECT * FROM accounts"},
        {"pid": 12348, "duration_seconds": 45.2, "state": "active",
         "query": "CREATE INDEX CONCURRENTLY idx_orders_date ON orders(created_at)"},
    ]
    return {"server": server_name,
            "total_active": len([q for q in queries if q["duration_seconds"] >= min_duration_seconds]),
            "queries": [q for q in queries if q["duration_seconds"] >= min_duration_seconds]}

def kill_query(server_name, pid, reason):
    return {"server": server_name, "pid": pid, "action": "terminated",
            "reason": reason, "success": True}

def get_server_metrics(server_name):
    """Get overall server metrics."""
    return {
        "server": server_name,
        "cpu_percent": round(random.uniform(10, 95), 1),
        "memory_percent": round(random.uniform(40, 90), 1),
        "disk_percent": round(random.uniform(30, 95), 1),
        "connections_used": random.randint(20, 195),
        "connections_max": 200,
        "uptime_hours": random.randint(24, 8760),
    }

TOOL_FUNCTIONS = {
    "check_replication_lag": check_replication_lag,
    "get_active_queries": get_active_queries,
    "kill_query": kill_query,
    "get_server_metrics": get_server_metrics,
}

TOOLS = [
    {"name": "check_replication_lag",
     "description": "Check replication lag on a PostgreSQL replica.",
     "input_schema": {"type": "object",
                      "properties": {"server_name": {"type": "string", "description": "Replica server name"}},
                      "required": ["server_name"]}},
    {"name": "get_active_queries",
     "description": "Get active queries from pg_stat_activity. Filter by min duration.",
     "input_schema": {"type": "object",
                      "properties": {"server_name": {"type": "string", "description": "Server to check"},
                                     "min_duration_seconds": {"type": "number", "description": "Min duration filter"}},
                      "required": ["server_name"]}},
    {"name": "kill_query",
     "description": "Terminate a backend by PID. Only for confirmed problematic queries.",
     "input_schema": {"type": "object",
                      "properties": {"server_name": {"type": "string", "description": "Server"},
                                     "pid": {"type": "integer", "description": "PID to terminate"},
                                     "reason": {"type": "string", "description": "Reason for termination"}},
                      "required": ["server_name", "pid", "reason"]}},
    {"name": "get_server_metrics",
     "description": "Get CPU, memory, disk, and connection metrics for a server.",
     "input_schema": {"type": "object",
                      "properties": {"server_name": {"type": "string", "description": "Server to check"}},
                      "required": ["server_name"]}},
]

# ---- Agent with memory ----

class DBAAgent:
    """
    DBA agent with conversation memory and action log.

    DBA analogy: like a DBA who keeps an incident log.
    Every check, every action, every decision is recorded.
    """

    def __init__(self):
        self.messages = []
        self.action_log = []
        self.total_input_tokens = 0
        self.total_output_tokens = 0

    def chat(self, user_message):
        """Send a message and get a response (with tool use)."""
        print(f"\nUser: {user_message}")
        print("-" * 50)

        self.messages.append({"role": "user", "content": user_message})

        max_iterations = 5
        for iteration in range(max_iterations):
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=1024,
                system=(
                    "You are an expert PostgreSQL DBA assistant. Use your tools to "
                    "investigate issues. Always check metrics before recommending actions. "
                    "Be concise. Explain your reasoning."
                ),
                tools=TOOLS,
                messages=self.messages,
            )

            self.total_input_tokens += response.usage.input_tokens
            self.total_output_tokens += response.usage.output_tokens

            if response.stop_reason == "tool_use":
                tool_blocks = [b for b in response.content if b.type == "tool_use"]
                text_blocks = [b for b in response.content if hasattr(b, "text")]

                # Show any thinking text before tool calls
                for tb in text_blocks:
                    if tb.text.strip():
                        print(f"  Thinking: {tb.text[:100]}...")

                self.messages.append({"role": "assistant", "content": response.content})

                tool_results = []
                for block in tool_blocks:
                    func = TOOL_FUNCTIONS.get(block.name)
                    args = block.input
                    print(f"  Tool: {block.name}({json.dumps(args)})")

                    if func:
                        result = func(**args)
                    else:
                        result = {"error": f"Unknown tool: {block.name}"}

                    print(f"    -> {json.dumps(result, indent=2)[:150]}")

                    self.action_log.append({
                        "tool": block.name,
                        "args": args,
                        "result": result,
                    })

                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(result),
                    })

                self.messages.append({"role": "user", "content": tool_results})

            elif response.stop_reason == "end_turn":
                text = "\n".join(
                    b.text for b in response.content if hasattr(b, "text")
                )
                print(f"\n  Agent: {text}")
                self.messages.append({"role": "assistant", "content": response.content})
                return text

        return "Max iterations reached."

    def show_stats(self):
        print(f"\n  Session Stats:")
        print(f"    Messages: {len(self.messages)}")
        print(f"    Tool calls: {len(self.action_log)}")
        print(f"    Input tokens: {self.total_input_tokens}")
        print(f"    Output tokens: {self.total_output_tokens}")


# ---- Run a multi-turn conversation ----

agent = DBAAgent()

# Turn 1: General health check
agent.chat("How's pg-primary doing? Check its overall metrics.")

# Turn 2: Follow-up based on previous response (agent remembers)
agent.chat("Check pg-replica-1's replication lag too.")

# Turn 3: Investigation
agent.chat("Are there any long-running queries on pg-primary? Show me anything over 60 seconds.")

agent.show_stats()

print("""
This agent maintains conversation history (memory).
Each new message includes ALL previous messages, so Claude
knows what it already checked and what the context is.

DBA analogy: like an incident thread in Slack.
Each message builds on the previous ones. The DBA
remembers what they already checked and connects
new information to previous findings.
""")
PYEOF
```

Expected output (yours will differ):
```
Complete Anthropic DBA Agent
==================================================

User: How's pg-primary doing? Check its overall metrics.
--------------------------------------------------
  Tool: get_server_metrics({"server_name": "pg-primary"})
    -> {"server": "pg-primary", "cpu_percent": 67.3, "memory_percent": 72.1, ...}

  Agent: pg-primary metrics look acceptable but worth watching. CPU is at 67.3% and memory at 72.1%, both within normal range. Disk is at 58.2% - plenty of room. You have 142/200 connections in use (71%), which is getting up there but not critical yet.

User: Check pg-replica-1's replication lag too.
--------------------------------------------------
  Tool: check_replication_lag({"server_name": "pg-replica-1"})
    -> {"server": "pg-replica-1", "replication_lag_seconds": 1.87, "status": "healthy"}

  Agent: pg-replica-1 lag is 1.87 seconds - healthy range. Combined with pg-primary's metrics, your cluster looks stable right now.
...
```

---

## What You Learned

| Concept | OpenAI | Anthropic |
|---------|--------|-----------|
| SDK install | `pip3 install openai` | `pip3 install anthropic` |
| Client | `openai.OpenAI()` | `anthropic.Anthropic()` |
| API call | `client.chat.completions.create()` | `client.messages.create()` |
| System prompt | `{"role": "system", ...}` in messages | `system="..."` parameter |
| Tool schema key | `parameters` | `input_schema` |
| Tool call detection | `message.tool_calls` list | `response.stop_reason == "tool_use"` |
| Tool result message | `role: "tool"` | `role: "user"` with `tool_result` blocks |
| Final answer | `message.content` (string) | `response.content` (list of blocks) |
| Thinking/reasoning | Use system prompt instructions | `thinking={"type": "enabled"}` |
| Token tracking | `response.usage.total_tokens` | `response.usage.input_tokens` + `.output_tokens` |
