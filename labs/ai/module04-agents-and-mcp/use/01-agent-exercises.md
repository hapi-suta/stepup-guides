# USE 01: Agent & MCP Exercises

Practice what you built. Each exercise builds on Build 01-03.

---

## Exercise 1: Add a New Tool (Build 01 extension)

Add a `check_index_usage` tool to the tool definitions from Build 01.

**Requirements:**
- Name: `check_index_usage`
- Description: Returns index usage stats for a given table
- Parameters: `table_name` (required string), `schema` (optional string, default "public")
- Simulated output: return index name, scan count, and size

**Steps:**
1. Copy the tool definition pattern from Build 01
2. Write the JSON schema with both parameters
3. Implement the simulated function
4. Test it by calling `execute_tool("check_index_usage", {"table_name": "orders"})`

**Expected behavior:**
```
check_index_usage({'table_name': 'orders'}):
  {
    "indexes": [
      {"name": "orders_pkey", "scans": 45000, "size": "12 MB"},
      {"name": "idx_orders_status", "scans": 3, "size": "8 MB"}
    ]
  }
```

**Hint:** The low scan count on `idx_orders_status` suggests it might be unused. A real DBA agent would flag this.

---

## Exercise 2: Extend the Agent Loop (Build 02 extension)

Modify the agent from Build 02 to handle a NEW scenario: disk space alerts.

**Requirements:**
1. Add a `check_disk_usage` tool that returns disk usage per mount point
2. Add a `check_wal_growth` tool that returns WAL file count and total size
3. Simulated data should show `/opt/pgsql/data` at 91% and WAL directory growing fast
4. Run the agent with: "We got a disk space alert on the primary. Investigate."

**Simulated tool data:**
```python
def check_disk_usage(server):
    return json.dumps({
        "mounts": [
            {"mount": "/", "used_pct": 45, "size": "50G"},
            {"mount": "/opt/pgsql/data", "used_pct": 91, "size": "200G"},
            {"mount": "/opt/pgsql/wal", "used_pct": 78, "size": "50G"},
        ]
    })

def check_wal_growth(server):
    return json.dumps({
        "wal_files": 1247,
        "total_size_gb": 19.8,
        "oldest_wal": "00000001000000000000004A",
        "replication_slot_active": False,
        "replication_slot_name": "standby_slot"
    })
```

**Expected agent behavior:**
- Step 1: Check server metrics (high CPU/connections)
- Step 2: Check disk usage (sees 91% on data mount)
- Step 3: Check WAL growth (finds inactive replication slot holding WAL)
- Final: Diagnose inactive replication slot as root cause, recommend dropping or reactivating it

---

## Exercise 3: Add a Resource to Your MCP Server (Build 03 extension)

MCP servers can expose **resources** (read-only data) in addition to tools. Add a resource to the DBA MCP server.

**Requirements:**
1. Add a `pg_config` resource that returns the current PostgreSQL configuration
2. Use the `@mcp.resource()` decorator
3. The resource should query `pg_settings` for key parameters

**Starter code:**
```python
@mcp.resource("config://postgresql")
def pg_config() -> str:
    """Current PostgreSQL configuration (key settings)."""
    query = """
    SELECT name, setting, unit, short_desc
    FROM pg_settings
    WHERE name IN (
        'max_connections', 'shared_buffers', 'work_mem',
        'maintenance_work_mem', 'effective_cache_size',
        'wal_level', 'max_wal_senders', 'hot_standby'
    )
    ORDER BY name;
    """
    return run_readonly_query(query)
```

**Test it:**
```python
from dba_mcp_server import pg_config
print(pg_config())
```

**Expected output (yours will differ):**
```
max_connections,100,,Sets the maximum number of concurrent connections.
shared_buffers,16384,8kB,Sets the number of shared memory buffers...
work_mem,4096,kB,Sets the maximum memory to be used for query workspaces.
...
```

---

## Exercise 4: Build a Multi-Server Agent

Build an agent that monitors BOTH primary and standby servers and compares them.

**Requirements:**
1. Use the tools from Build 02 (get_server_metrics, check_replication_lag, run_sql_query)
2. System prompt should instruct Claude to always check BOTH servers
3. Ask: "Give me a full health report on our PostgreSQL cluster."
4. Claude should use parallel tool calls to check both servers at once

**Key pattern:**
```python
# Claude should request these in parallel (one response, multiple tool_use blocks):
# get_server_metrics(server="pg-primary")
# get_server_metrics(server="pg-standby")
# check_replication_lag(server="pg-standby")
```

**Expected behavior:**
- Claude requests 2-3 tools in the first step (parallel)
- Follows up with 1-2 more specific queries
- Produces a comparison report with both servers side by side
- Flags any discrepancies (e.g., standby lag, CPU difference)

---

## Exercise 5: End-to-End - Build and Connect a Custom MCP Server

Build a complete MCP server for a different domain: **log analysis**.

**Requirements:**
1. Create `log_analyzer_mcp.py` with these tools:
   - `search_logs(pattern, last_minutes=60)` - Search PostgreSQL logs for a pattern
   - `count_errors(last_minutes=60)` - Count error types in recent logs
   - `get_slow_queries(min_duration_ms=1000)` - Find queries slower than threshold
   - `get_log_summary()` - Overview of log activity (errors, warnings, connections)

2. Each tool should read from a simulated log file or return simulated data

3. Add safety: block any tool call that tries to modify or delete log files

4. Test all tools locally (import and call directly)

5. Configure for Claude Desktop (write the JSON config)

**Starter structure:**
```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("log-analyzer", instructions="""
You analyze PostgreSQL logs to find errors, slow queries,
and connection issues. Always check the log summary first,
then drill into specific areas.
""")

@mcp.tool()
def search_logs(pattern: str, last_minutes: int = 60) -> str:
    """Search PostgreSQL logs for a pattern in recent entries."""
    # Your implementation here
    pass

# Add remaining tools...

if __name__ == "__main__":
    mcp.run()
```

**Deliverable:** A working MCP server that you can connect to Claude Desktop and ask "What errors happened in the last hour?"

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Tool definition + JSON schema | Beginner |
| 2 | Agent loop + multi-tool investigation | Intermediate |
| 3 | MCP resources (new concept) | Intermediate |
| 4 | Parallel tool calls + comparison logic | Intermediate |
| 5 | Full MCP server from scratch | Advanced |
