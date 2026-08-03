# Build 02: The Agent Loop

Build 01 handled a single tool call. Real agents make MULTIPLE tool calls in a loop - think, act, observe, think again - until they have enough information to answer. This is the core pattern behind every AI agent.

---

## Step 1. Build the agent loop

The loop keeps running until Claude either gives a final answer (`stop_reason: end_turn`) or hits the maximum number of steps.

On your **Mac terminal**, save this script:

```bash
cat > /tmp/dba_agent.py << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

# --- Tool Definitions ---
TOOLS = [
    {
        "name": "check_replication_lag",
        "description": "Check replication lag for a PostgreSQL server. Returns lag in seconds, role, and state.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {"type": "string", "description": "Server: 'pg-primary' or 'pg-standby'"}
            },
            "required": ["server"]
        }
    },
    {
        "name": "run_sql_query",
        "description": "Execute a read-only SQL query on PostgreSQL. Returns rows as JSON.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "SQL SELECT query to execute"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "get_server_metrics",
        "description": "Get current CPU, memory, disk, and connection count for a server.",
        "input_schema": {
            "type": "object",
            "properties": {
                "server": {"type": "string", "description": "Server: 'pg-primary' or 'pg-standby'"}
            },
            "required": ["server"]
        }
    },
]

# --- Tool Implementations (simulated) ---
def check_replication_lag(server):
    data = {
        "pg-primary": {"lag_seconds": 0, "role": "primary", "standbys_connected": 1},
        "pg-standby": {"lag_seconds": 45, "role": "standby", "state": "streaming", "replay_lag": "00:00:45"},
    }
    return json.dumps(data.get(server, {"error": f"Unknown server: {server}"}))

def run_sql_query(query):
    q = query.lower()
    if "pg_stat_replication" in q:
        return json.dumps({"rows": [
            {"client_addr": "10.0.1.5", "state": "streaming", "replay_lag": "00:00:45", "sent_lsn": "0/5000000", "replay_lsn": "0/4F00000"}
        ]})
    elif "pg_stat_activity" in q:
        return json.dumps({"rows": [
            {"pid": 1234, "state": "idle in transaction", "query": "SELECT * FROM orders WHERE status='pending'", "duration": "00:42:00"},
            {"pid": 1235, "state": "idle in transaction", "query": "UPDATE inventory SET qty=qty-1", "duration": "00:38:00"},
            {"pid": 1236, "state": "active", "query": "VACUUM ANALYZE orders", "duration": "00:05:00"},
        ], "total_connections": 285, "max_connections": 300, "idle_in_transaction": 240})
    elif "pg_locks" in q:
        return json.dumps({"rows": [
            {"blocked_pid": 1300, "blocking_pid": 1234, "blocked_query": "ALTER TABLE orders ADD COLUMN...", "lock_type": "AccessExclusiveLock"}
        ]})
    elif "pg_stat_user_tables" in q or "n_dead_tup" in q:
        return json.dumps({"rows": [
            {"relname": "orders", "n_dead_tup": 12500000, "last_autovacuum": "3 days ago", "seq_scan": 45000, "idx_scan": 1200}
        ]})
    return json.dumps({"rows": [], "note": "Query returned no results"})

def get_server_metrics(server):
    return json.dumps({
        "server": server, "cpu_percent": 92.5, "memory_percent": 68.3,
        "disk_percent": 45.1, "active_connections": 285, "max_connections": 300,
        "wal_directory_percent": 78.0
    })

TOOL_REGISTRY = {
    "check_replication_lag": check_replication_lag,
    "run_sql_query": run_sql_query,
    "get_server_metrics": get_server_metrics,
}

# --- The Agent Loop ---
def run_agent(user_question, max_steps=8):
    """Run the agent loop: think -> act -> observe -> repeat until done."""

    system = """You are a PostgreSQL DBA agent. You investigate database problems by using your tools to gather information before making recommendations.

Rules:
1. ALWAYS use tools to gather data before diagnosing. Never guess.
2. Check server metrics first to get an overview.
3. Then drill into specific areas based on what looks abnormal.
4. After gathering enough data (usually 2-4 tool calls), provide your diagnosis.
5. Include specific remediation commands in your final answer.
6. If something looks critical, say so clearly."""

    messages = [{"role": "user", "content": user_question}]

    print(f"User: {user_question}")
    print("=" * 60)

    for step in range(max_steps):
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=500,
            system=system,
            tools=TOOLS,
            messages=messages,
        )

        # Check if Claude wants to use tools or is done
        if response.stop_reason == "end_turn":
            # Claude is done - print final answer
            print(f"\n--- Final Answer (after {step} tool calls) ---")
            for block in response.content:
                if block.type == "text":
                    print(block.text)
            return

        if response.stop_reason == "tool_use":
            # Add Claude's response to history
            messages.append({"role": "assistant", "content": response.content})

            # Execute each tool call
            tool_results = []
            for block in response.content:
                if block.type == "text" and block.text:
                    print(f"\n[Step {step+1}] Thinking: {block.text[:150]}...")
                elif block.type == "tool_use":
                    print(f"[Step {step+1}] Action: {block.name}({json.dumps(block.input)[:80]})")
                    result = TOOL_REGISTRY[block.name](**block.input)
                    print(f"[Step {step+1}] Result: {result[:120]}...")
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })

            # Send all tool results back
            messages.append({"role": "user", "content": tool_results})

    print(f"\n[Agent hit max steps ({max_steps}). Forcing final answer.]")


# --- Run it ---
if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
    else:
        question = "The application is running very slowly and some requests are timing out. Investigate the database."

    run_agent(question)
PYEOF
echo "Agent saved to /tmp/dba_agent.py"
echo "Run: python3 /tmp/dba_agent.py"
echo "Or: python3 /tmp/dba_agent.py 'your question here'"
```

Expected output when run (yours will differ):
```
User: The application is running very slowly and some requests are timing out.
============================================================

[Step 1] Action: get_server_metrics({"server": "pg-primary"})
[Step 1] Result: {"server": "pg-primary", "cpu_percent": 92.5, "memory_percent": 68.3...

[Step 2] Thinking: CPU is at 92.5% and connections are at 285/300...
[Step 2] Action: run_sql_query({"query": "SELECT state, count(*) FROM pg_stat_activity GROUP BY state"})
[Step 2] Result: {"rows": [{"pid": 1234, "state": "idle in transaction"...

[Step 3] Action: run_sql_query({"query": "SELECT * FROM pg_stat_user_tables WHERE n_dead_tup > 1000000"})
[Step 3] Result: {"rows": [{"relname": "orders", "n_dead_tup": 12500000...

--- Final Answer (after 3 tool calls) ---

**Critical Issues Found:**

1. **Connection exhaustion** (285/300 connections used)
   - 240 connections are "idle in transaction" - these are leaked
   - Application is not closing transactions properly

2. **Severe table bloat** on `orders` table
   - 12.5 million dead tuples
   - Last autovacuum: 3 days ago
   - 45,000 sequential scans vs only 1,200 index scans

3. **High CPU** (92.5%) caused by sequential scans on bloated table

**Immediate Actions:**

```sql
-- Kill idle-in-transaction sessions older than 10 minutes
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND state_change < NOW() - INTERVAL '10 minutes';

-- Set timeout to prevent future leaks
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
SELECT pg_reload_conf();

-- Vacuum the bloated table
VACUUM ANALYZE orders;
```
```

The agent:
1. Started with metrics (Step 1) - found high CPU and near-full connections
2. Investigated connections (Step 2) - found 240 idle-in-transaction
3. Checked table health (Step 3) - found massive bloat
4. Synthesized everything into a diagnosis with specific commands

---

## Step 2. Add safety controls

Agents can be dangerous. Let's add guardrails.

```bash
python3 << 'PYEOF'
import json

# A dangerous tool registry (what NOT to do)
def run_shell_command(command):
    """DANGEROUS: Executes any shell command."""
    import subprocess
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    return result.stdout + result.stderr

# A SAFE tool registry
SAFE_COMMANDS = {
    "pg_isready": "pg_isready",
    "check_disk": "df -h /opt/pgsql/data",
    "check_connections": "psql -c 'SELECT count(*) FROM pg_stat_activity;'",
}

def run_approved_command(command_name):
    """SAFE: Only runs pre-approved commands."""
    if command_name not in SAFE_COMMANDS:
        return json.dumps({
            "error": f"Command '{command_name}' not in approved list",
            "approved_commands": list(SAFE_COMMANDS.keys())
        })
    # In production, you'd actually run it
    return json.dumps({"command": command_name, "output": f"[simulated output for {command_name}]"})

# Demonstrate the difference
print("=== DANGEROUS approach ===")
print("run_shell_command('rm -rf /') -> executes anything!")
print("If Claude decides to run a destructive command, it's game over.")
print()

print("=== SAFE approach ===")
print("run_approved_command('pg_isready') -> runs from approved list only")
result = run_approved_command("pg_isready")
print(f"  Result: {result}")

result = run_approved_command("rm -rf /")
print(f"  Blocked: {result}")
print()

print("=== Safety Rules ===")
print("1. Allowlist over blocklist (define what's OK, not what's bad)")
print("2. Read-only by default (SELECT yes, DELETE no)")
print("3. Confirmation for destructive actions")
print("4. Log every tool call")
print("5. Max steps limit (prevent infinite loops)")
PYEOF
```

Expected output:
```
=== DANGEROUS approach ===
run_shell_command('rm -rf /') -> executes anything!
If Claude decides to run a destructive command, it's game over.

=== SAFE approach ===
run_approved_command('pg_isready') -> runs from approved list only
  Result: {"command": "pg_isready", "output": "[simulated output for pg_isready]"}
  Blocked: {"error": "Command 'rm -rf /' not in approved list", "approved_commands": ["pg_isready", "check_disk", "check_connections"]}

=== Safety Rules ===
1. Allowlist over blocklist (define what's OK, not what's bad)
2. Read-only by default (SELECT yes, DELETE no)
3. Confirmation for destructive actions
4. Log every tool call
5. Max steps limit (prevent infinite loops)
```

---

## Step 3. Multi-tool parallel calls

Claude can request multiple tools in a single response when it needs independent data from multiple sources.

```bash
python3 << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

tools = [
    {
        "name": "get_server_metrics",
        "description": "Get CPU, memory, disk metrics for a server.",
        "input_schema": {
            "type": "object",
            "properties": {"server": {"type": "string"}},
            "required": ["server"]
        }
    },
    {
        "name": "check_replication_lag",
        "description": "Check replication lag for a server.",
        "input_schema": {
            "type": "object",
            "properties": {"server": {"type": "string"}},
            "required": ["server"]
        }
    },
]

def get_server_metrics(server):
    metrics = {
        "pg-primary": {"cpu": 45, "memory": 62, "connections": 150},
        "pg-standby": {"cpu": 25, "memory": 40, "connections": 50},
    }
    return json.dumps(metrics.get(server, {}))

def check_replication_lag(server):
    data = {"pg-standby": {"lag_seconds": 2, "state": "streaming"}}
    return json.dumps(data.get(server, {"lag_seconds": 0}))

REGISTRY = {"get_server_metrics": get_server_metrics, "check_replication_lag": check_replication_lag}

# Ask about BOTH servers - Claude should request both at once
messages = [{"role": "user", "content": "Give me a health check on both the primary and standby servers."}]

response = client.messages.create(
    model="claude-sonnet-4-20250514", max_tokens=400, tools=tools, messages=messages,
)

# Count how many tool calls in one response
tool_calls = [b for b in response.content if b.type == "tool_use"]
print(f"Claude requested {len(tool_calls)} tool calls in one response:")
for tc in tool_calls:
    print(f"  {tc.name}({json.dumps(tc.input)})")

# Execute all and send results back
messages.append({"role": "assistant", "content": response.content})
results = []
for tc in tool_calls:
    result = REGISTRY[tc.name](**tc.input)
    print(f"  -> {result[:80]}")
    results.append({"type": "tool_result", "tool_use_id": tc.id, "content": result})

messages.append({"role": "user", "content": results})

final = client.messages.create(
    model="claude-sonnet-4-20250514", max_tokens=400, tools=tools, messages=messages,
)

print(f"\nFinal answer:")
for b in final.content:
    if b.type == "text":
        print(b.text)
PYEOF
```

Expected output (yours will differ):
```
Claude requested 2 tool calls in one response:
  get_server_metrics({"server": "pg-primary"})
  get_server_metrics({"server": "pg-standby"})
  -> {"cpu": 45, "memory": 62, "connections": 150}
  -> {"cpu": 25, "memory": 40, "connections": 50}

Final answer:
Both servers look healthy:
- **Primary:** CPU 45%, Memory 62%, 150 connections - all within normal range
- **Standby:** CPU 25%, Memory 40%, 50 connections - healthy with low utilization
```

Claude requested BOTH server metrics simultaneously because they're independent. This is more efficient than sequential calls.

---

## What You Learned

| Concept | What It Does | Why It Matters |
|---------|-------------|---------------|
| Agent loop | Think -> Act -> Observe -> Repeat | Core pattern for all agents |
| Max steps | Limits how many tool calls before stopping | Prevents infinite loops and runaway costs |
| Safety controls | Allowlist, read-only default, logging | Agents can DO things - safety is critical |
| Parallel tool calls | Multiple independent tools in one step | Faster investigation (2 calls in 1 round trip) |
| Simulated tools | Fake tool results for testing | Develop and test without real infrastructure |
