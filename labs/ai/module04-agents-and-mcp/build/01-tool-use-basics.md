# Build 01: Tool Use Basics

Tool use (function calling) lets Claude call your functions. You define what tools are available. Claude decides when to use them. Your code executes them and returns the result.

---

## Step 1. Define tools

Tools are defined as JSON schemas. Each tool has a name, description, and input schema.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

# Define tools the agent can use
tools = [
    {
        "name": "check_replication_lag",
        "description": "Check the replication lag in seconds between primary and standby PostgreSQL servers.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {
                    "type": "string",
                    "description": "The server to check: 'pg-primary' or 'pg-standby'"
                }
            },
            "required": ["server"]
        }
    },
    {
        "name": "run_sql_query",
        "description": "Execute a read-only SQL query on PostgreSQL and return results as JSON.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The SQL SELECT query to execute"
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "get_server_metrics",
        "description": "Get current CPU, memory, disk, and connection metrics for a database server.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {
                    "type": "string",
                    "description": "Server hostname: 'pg-primary' or 'pg-standby'"
                }
            },
            "required": ["server"]
        }
    }
]

print("Defined tools:")
for t in tools:
    params = t["input_schema"]["properties"]
    print(f"  {t['name']}")
    print(f"    Description: {t['description'][:70]}...")
    print(f"    Parameters: {', '.join(params.keys())}")
print(f"\nTool count: {len(tools)}")
PYEOF
```

Expected output:
```
Defined tools:
  check_replication_lag
    Description: Check the replication lag in seconds between primary and standby ...
    Parameters: server
  run_sql_query
    Description: Execute a read-only SQL query on PostgreSQL and return results as...
    Parameters: query
  get_server_metrics
    Description: Get current CPU, memory, disk, and connection metrics for a datab...
    Parameters: server

Tool count: 3
```

Key points:
- `name`: How Claude refers to the tool. Use clear, descriptive names.
- `description`: Tells Claude WHEN to use this tool. Be specific - "Check replication lag" is better than "Database tool".
- `input_schema`: JSON Schema defining what parameters the tool accepts. Claude generates these values.
- `required`: Which parameters must be provided.

---

## Step 2. Implement the tools

Tools are just Python functions. In production, these would SSH into servers, run queries, or call APIs. For learning, we'll simulate them.

```bash
python3 << 'PYEOF'
import json

# Tool implementations (simulated - in production these hit real servers)
def check_replication_lag(server):
    data = {
        "pg-primary": {"lag_seconds": 0, "role": "primary", "connected_standbys": 1},
        "pg-standby": {"lag_seconds": 45, "role": "standby", "replay_lag": "00:00:45", "state": "streaming"},
    }
    result = data.get(server, {"error": f"Unknown server: {server}"})
    return json.dumps(result)

def run_sql_query(query):
    if "pg_stat_replication" in query.lower():
        return json.dumps({"rows": [
            {"client_addr": "10.0.1.5", "state": "streaming",
             "sent_lsn": "0/5000000", "replay_lsn": "0/4F00000",
             "replay_lag": "00:00:45"}
        ]})
    elif "pg_stat_activity" in query.lower():
        return json.dumps({"rows": [
            {"pid": 1234, "state": "idle in transaction", "query": "SELECT * FROM orders", "wait_event": "ClientRead", "duration_minutes": 15},
            {"pid": 1235, "state": "active", "query": "VACUUM ANALYZE users", "wait_event": None, "duration_minutes": 2},
            {"pid": 1236, "state": "idle in transaction", "query": "UPDATE inventory SET ...", "wait_event": "ClientRead", "duration_minutes": 42},
        ], "total_connections": 285, "max_connections": 300})
    return json.dumps({"rows": [], "message": "Query executed, 0 rows returned"})

def get_server_metrics(server):
    return json.dumps({
        "server": server, "cpu_percent": 92.5, "memory_percent": 68.3,
        "disk_percent": 45.1, "active_connections": 285, "max_connections": 300,
        "uptime_hours": 720,
    })

# Tool registry - maps names to functions
TOOL_REGISTRY = {
    "check_replication_lag": check_replication_lag,
    "run_sql_query": run_sql_query,
    "get_server_metrics": get_server_metrics,
}

def execute_tool(name, arguments):
    """Execute a tool by name. Returns JSON string."""
    if name not in TOOL_REGISTRY:
        return json.dumps({"error": f"Unknown tool: {name}"})
    try:
        # ** (double-star) unpacks a dictionary into named arguments.
        # If arguments = {"server": "pg-1"}, then **arguments becomes: server="pg-1"
        # DBA analogy: like expanding a JSONB object into function parameters.
        return TOOL_REGISTRY[name](**arguments)
    except Exception as e:
        return json.dumps({"error": f"Tool failed: {str(e)}"})

# Test all tools
print("=== Testing Tools ===")
for name, args in [
    ("check_replication_lag", {"server": "pg-standby"}),
    ("run_sql_query", {"query": "SELECT * FROM pg_stat_activity WHERE state != 'idle'"}),
    ("get_server_metrics", {"server": "pg-primary"}),
]:
    result = execute_tool(name, args)
    parsed = json.loads(result)
    print(f"\n{name}({args}):")
    print(f"  {json.dumps(parsed, indent=2)[:200]}...")
PYEOF
```

Expected output:
```
=== Testing Tools ===

check_replication_lag({'server': 'pg-standby'}):
  {
    "lag_seconds": 45,
    "role": "standby",
    "replay_lag": "00:00:45",
    "state": "streaming"
  }...

run_sql_query({'query': 'SELECT * FROM pg_stat_activity...'}):
  {
    "rows": [
      {"pid": 1234, "state": "idle in transaction"...}
    ...

get_server_metrics({'server': 'pg-primary'}):
  {
    "server": "pg-primary",
    "cpu_percent": 92.5,
    ...
```

---

## Step 3. Send tools to Claude (API call)

Now connect tools to Claude. When you pass tools in the API call, Claude can choose to call them.

```bash
python3 << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

# Tool definitions (same as Step 1)
tools = [
    {
        "name": "check_replication_lag",
        "description": "Check the replication lag in seconds between primary and standby PostgreSQL servers.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {"type": "string", "description": "Server: 'pg-primary' or 'pg-standby'"}
            },
            "required": ["server"]
        }
    },
    {
        "name": "get_server_metrics",
        "description": "Get current CPU, memory, disk, and connection metrics for a database server.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {"type": "string", "description": "Server hostname"}
            },
            "required": ["server"]
        }
    }
]

# Ask Claude a question with tools available
response = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    tools=tools,
    messages=[{"role": "user", "content": "Is the standby server healthy? Check its replication status."}]
)

# Claude's response will contain a tool_use block
print("Stop reason:", response.stop_reason)
print()

for block in response.content:
    if block.type == "text":
        print(f"Text: {block.text}")
    elif block.type == "tool_use":
        print(f"Tool call: {block.name}")
        print(f"  Arguments: {json.dumps(block.input)}")
        print(f"  Tool use ID: {block.id}")
PYEOF
```

Expected output (yours will differ):
```
Stop reason: tool_use

Tool call: check_replication_lag
  Arguments: {"server": "pg-standby"}
  Tool use ID: toolu_abc123...
```

Key insight: Claude didn't answer the question. Instead, `stop_reason: tool_use` tells you Claude wants to call a tool first. It chose `check_replication_lag` with `server: "pg-standby"` because that's what the user asked about.

YOUR code now needs to:
1. Execute the tool
2. Send the result back to Claude
3. Claude reads the result and responds

---

## Step 4. Complete the tool use cycle

This is the full pattern: send tools -> Claude requests a tool call -> you execute it -> send result back -> Claude answers.

```bash
python3 << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

# Tool definitions
tools = [
    {
        "name": "check_replication_lag",
        "description": "Check replication lag between primary and standby PostgreSQL servers.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {"type": "string", "description": "Server: 'pg-primary' or 'pg-standby'"}
            },
            "required": ["server"]
        }
    },
    {
        "name": "get_server_metrics",
        "description": "Get current CPU, memory, disk, and connection metrics.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {"type": "string", "description": "Server hostname"}
            },
            "required": ["server"]
        }
    }
]

# Tool implementations
def check_replication_lag(server):
    data = {
        "pg-primary": {"lag_seconds": 0, "role": "primary"},
        "pg-standby": {"lag_seconds": 45, "role": "standby", "state": "streaming"},
    }
    return json.dumps(data.get(server, {"error": f"Unknown: {server}"}))

def get_server_metrics(server):
    return json.dumps({"server": server, "cpu_percent": 92.5, "memory_percent": 68.3,
                       "active_connections": 285, "max_connections": 300})

TOOL_REGISTRY = {
    "check_replication_lag": check_replication_lag,
    "get_server_metrics": get_server_metrics,
}

# Step 1: Initial request
messages = [{"role": "user", "content": "Is the standby server healthy?"}]

print("User: Is the standby server healthy?")
print("=" * 50)

response = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=300,
    tools=tools,
    messages=messages,
)

# Step 2: Process tool calls
if response.stop_reason == "tool_use":
    # Add Claude's response (with tool_use block) to message history
    messages.append({"role": "assistant", "content": response.content})

    # Find and execute each tool call
    for block in response.content:
        if block.type == "tool_use":
            print(f"\nClaude calls: {block.name}({json.dumps(block.input)})")

            # Execute the tool
            result = TOOL_REGISTRY[block.name](**block.input)
            print(f"Tool result: {result}")

            # Add tool result to messages
            messages.append({
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    }
                ],
            })

    # Step 3: Send tool results back to Claude for final answer
    final = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=300,
        tools=tools,
        messages=messages,
    )

    print(f"\nClaude's answer:")
    for block in final.content:
        if block.type == "text":
            print(block.text)
else:
    # Claude answered without using tools
    for block in response.content:
        if block.type == "text":
            print(block.text)
PYEOF
```

Expected output (yours will differ):
```
User: Is the standby server healthy?
==================================================

Claude calls: check_replication_lag({"server": "pg-standby"})
Tool result: {"lag_seconds": 45, "role": "standby", "state": "streaming"}

Claude's answer:
The standby server is functional but showing elevated replication lag:

- **Status:** Streaming (connected and receiving WAL)
- **Replication lag:** 45 seconds

While the server is operational (streaming state is healthy), a 45-second
lag is worth investigating. Common causes include heavy write load on the
primary, I/O bottlenecks on the standby, or network latency. I'd recommend
checking the primary's write rate and the standby's I/O wait metrics.
```

This is the complete tool use cycle:
1. You send the question + tool definitions
2. Claude returns `stop_reason: tool_use` with the tool it wants to call
3. Your code executes the tool and captures the result
4. You send the result back as a `tool_result` message
5. Claude reads the result and generates a final answer

---

## What You Learned

| Concept | What It Does | Production Use |
|---------|-------------|----------------|
| Tool definitions | Tell Claude what functions are available | Every agent needs tools |
| `stop_reason: tool_use` | Claude wants to call a function | Your code's cue to execute |
| `tool_use_id` | Links a tool call to its result | Required when returning results |
| Tool registry | Maps tool names to implementations | Clean, extensible tool dispatch |
| Tool result message | Sends execution results back to Claude | Completes the think-act-observe cycle |
