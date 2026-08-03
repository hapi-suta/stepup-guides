# Build 01: MCP Servers for Databases

## What Is MCP?

MCP (Model Context Protocol) is an open standard that lets AI models call tools on external systems. Instead of each AI tool inventing its own integration format, MCP defines a single protocol that any compliant client can use.

**DBA analogy:** MCP is to AI tools what the PostgreSQL wire protocol is to database clients. Any client that speaks the wire protocol - psql, pgAdmin, DBeaver, your Python app - can connect to any PostgreSQL server. You don't need a different driver for each client-server combination. MCP does the same thing for AI: any AI client that speaks MCP can call any MCP server's tools.

```
PostgreSQL wire protocol:
  psql           --|
  pgAdmin        --|--> PostgreSQL wire protocol --> Any PostgreSQL server
  DBeaver        --|
  Python/psycopg --|

MCP protocol:
  Claude Desktop --|
  VS Code Copilot--|--> MCP protocol --> Any MCP server (your DBA tools)
  Custom agent   --|
```

---

## MCP Architecture

An MCP system has two sides:

| Component | What It Does | DBA Analogy |
|-----------|-------------|-------------|
| **MCP Server** | Exposes tools that AI can call | A PostgreSQL server exposing stored procedures |
| **MCP Client** | AI model that discovers and calls those tools | A psql client that calls stored procedures |

The flow:
1. Server starts and registers its tools (name, description, parameters)
2. Client connects and asks "what tools do you have?"
3. Server responds with a list of tools
4. Client picks a tool, sends parameters, gets results

This is exactly how `\df` in psql works - it asks the server what functions are available, then you call the one you need.

---

## Step 1: Install the MCP Libraries

On your **Mac terminal**, install the required packages:

```bash
pip3 install mcp fastmcp
```

Expected output (yours will differ):
```
Successfully installed mcp-1.x.x fastmcp-2.x.x ...
```

**What these packages do:**
- `mcp` - the core MCP protocol library (like libpq for PostgreSQL)
- `fastmcp` - a higher-level wrapper that makes building MCP servers easy (like pgx is to libpq - same protocol, friendlier API)

---

## Step 2: Build an MCP Server with DBA Tools

### The Concept

We are going to build an MCP server that exposes five PostgreSQL diagnostic tools. Each tool is a Python function that the MCP server wraps and makes available to any AI client.

**DBA analogy:** Think of this as writing five stored procedures and then GRANTing EXECUTE to a role. The AI client is that role - it can call any procedure in the list, but nothing else.

```sql
-- What we are building, expressed as SQL
CREATE FUNCTION check_connections(db TEXT) RETURNS TEXT;
CREATE FUNCTION get_slow_queries(min_ms INT) RETURNS TEXT;
CREATE FUNCTION check_replication_status() RETURNS TEXT;
CREATE FUNCTION get_table_bloat(schema TEXT, tbl TEXT) RETURNS TEXT;
CREATE FUNCTION get_database_size(db TEXT) RETURNS TEXT;

GRANT EXECUTE ON ALL FUNCTIONS TO ai_client;
```

### The Code

On your **Mac terminal**, create the MCP server file:

```bash
vi /tmp/dba_mcp_server.py
```

Paste this content into the file:

```python
# ---------------------------------------------------------
# What this script does:
#   Creates an MCP server that exposes 5 DBA diagnostic tools.
#   Any MCP-compatible client (Claude Desktop, VS Code, etc.)
#   can connect and call these tools.
#
#   For this lab, tools return simulated data.
#   In production, you would connect to a real PostgreSQL instance.
# ---------------------------------------------------------

# FastMCP is the high-level library for building MCP servers.
# Think of it like Flask is for web servers - it handles the protocol
# so you just write the business logic.
from fastmcp import FastMCP

# datetime gives us timestamps - like now() in SQL
import datetime

# json formats data as structured text - like row_to_json() in PostgreSQL
import json


# Create the MCP server instance.
# "name" is what clients see when they connect - like a database name in pg_hba.conf.
mcp = FastMCP(name="PostgreSQL DBA Tools")


# ---------------------------------------------------------
# TOOL 1: check_connections
# ---------------------------------------------------------
# The @mcp.tool() decorator registers this function as an MCP tool.
# Think of it as: CREATE FUNCTION + GRANT EXECUTE in one step.
# The function docstring becomes the tool description that clients see -
# like COMMENT ON FUNCTION in PostgreSQL.

@mcp.tool()
def check_connections(database: str) -> str:
    """Check active connection count for a database.
    Returns current connections, max connections, and usage percentage.
    Use this when you suspect connection exhaustion or pool saturation."""

    # In production, this would run:
    #   SELECT count(*) FROM pg_stat_activity WHERE datname = database;
    #   SHOW max_connections;
    # For this lab, we simulate the response.

    simulated_data = {
        "production": {"active": 187, "max": 200, "idle": 42, "idle_in_transaction": 3},
        "staging":    {"active": 23,  "max": 100, "idle": 8,  "idle_in_transaction": 0},
        "analytics":  {"active": 95,  "max": 100, "idle": 12, "idle_in_transaction": 1},
    }

    # .get() is like COALESCE - returns the default if the key is missing
    data = simulated_data.get(database, {"active": 0, "max": 100, "idle": 0, "idle_in_transaction": 0})

    usage_pct = round((data["active"] / data["max"]) * 100, 1)

    result = {
        "database": database,
        "active_connections": data["active"],
        "max_connections": data["max"],
        "idle_connections": data["idle"],
        "idle_in_transaction": data["idle_in_transaction"],
        "usage_percent": usage_pct,
        "status": "CRITICAL" if usage_pct > 90 else "WARNING" if usage_pct > 75 else "OK",
        "checked_at": datetime.datetime.now().isoformat()
    }

    # json.dumps formats the dict as a JSON string with indentation
    # indent=2 makes it human-readable - like \x (expanded display) in psql
    return json.dumps(result, indent=2)


# ---------------------------------------------------------
# TOOL 2: get_slow_queries
# ---------------------------------------------------------

@mcp.tool()
def get_slow_queries(min_duration_ms: int) -> str:
    """Find queries running longer than the specified duration in milliseconds.
    Returns query text, duration, user, and database for each slow query.
    Use this when investigating high CPU, lock waits, or unresponsive applications."""

    # In production, this would run:
    #   SELECT pid, now() - query_start AS duration, query, usename, datname
    #   FROM pg_stat_activity
    #   WHERE state = 'active'
    #     AND now() - query_start > (min_duration_ms || ' milliseconds')::interval
    #   ORDER BY duration DESC;

    all_queries = [
        {"pid": 14523, "duration_ms": 45200, "query": "SELECT * FROM orders JOIN line_items ON orders.id = line_items.order_id WHERE order_date > '2026-01-01'",
         "user": "reporting_app", "database": "production", "wait_event": "ClientRead"},
        {"pid": 14801, "duration_ms": 12800, "query": "UPDATE inventory SET stock = stock - 1 WHERE product_id = 99421",
         "user": "web_app", "database": "production", "wait_event": "LWLock:BufferMapping"},
        {"pid": 15002, "duration_ms": 8300, "query": "VACUUM FULL public.audit_log",
         "user": "postgres", "database": "production", "wait_event": None},
        {"pid": 15100, "duration_ms": 3200, "query": "SELECT count(*) FROM pg_stat_activity",
         "user": "monitor", "database": "production", "wait_event": None},
        {"pid": 15201, "duration_ms": 800, "query": "SELECT 1",
         "user": "healthcheck", "database": "production", "wait_event": None},
    ]

    # Filter queries where duration exceeds the threshold
    # This is the Python equivalent of the WHERE clause above
    slow = [q for q in all_queries if q["duration_ms"] >= min_duration_ms]

    result = {
        "threshold_ms": min_duration_ms,
        "slow_query_count": len(slow),
        "queries": slow,
        "checked_at": datetime.datetime.now().isoformat()
    }

    return json.dumps(result, indent=2)


# ---------------------------------------------------------
# TOOL 3: check_replication_status
# ---------------------------------------------------------

@mcp.tool()
def check_replication_status() -> str:
    """Check replication lag and status for all standby servers.
    Returns lag in bytes and seconds for each replica.
    Use this when investigating replication issues or before failover."""

    # In production, this would run:
    #   SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
    #          pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
    #   FROM pg_stat_replication;

    replicas = [
        {
            "client_addr": "10.0.1.12",
            "application_name": "pg-standby-1",
            "state": "streaming",
            "sent_lsn": "0/5A000060",
            "replay_lsn": "0/5A000060",
            "replay_lag_bytes": 0,
            "replay_lag_seconds": 0.0,
            "sync_state": "async"
        },
        {
            "client_addr": "10.0.2.15",
            "application_name": "pg-standby-2",
            "state": "streaming",
            "sent_lsn": "0/5A000060",
            "replay_lsn": "0/59FFF800",
            "replay_lag_bytes": 2144,
            "replay_lag_seconds": 0.8,
            "sync_state": "async"
        },
        {
            "client_addr": "10.0.3.20",
            "application_name": "pg-dr-replica",
            "state": "catchup",
            "sent_lsn": "0/5A000060",
            "replay_lsn": "0/58000000",
            "replay_lag_bytes": 33554528,
            "replay_lag_seconds": 45.2,
            "sync_state": "async"
        }
    ]

    # Determine overall status based on worst replica
    max_lag = max(r["replay_lag_seconds"] for r in replicas)
    overall = "CRITICAL" if max_lag > 30 else "WARNING" if max_lag > 5 else "OK"

    result = {
        "primary": "pg-primary (10.0.1.10)",
        "replica_count": len(replicas),
        "replicas": replicas,
        "max_lag_seconds": max_lag,
        "overall_status": overall,
        "checked_at": datetime.datetime.now().isoformat()
    }

    return json.dumps(result, indent=2)


# ---------------------------------------------------------
# TOOL 4: get_table_bloat
# ---------------------------------------------------------

@mcp.tool()
def get_table_bloat(schema: str, table: str) -> str:
    """Check dead tuple ratio and bloat estimate for a specific table.
    Returns live tuples, dead tuples, dead ratio, and last vacuum time.
    Use this when investigating slow sequential scans or growing table sizes."""

    # In production, this would run:
    #   SELECT n_live_tup, n_dead_tup,
    #          round(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_ratio,
    #          last_vacuum, last_autovacuum
    #   FROM pg_stat_user_tables
    #   WHERE schemaname = schema AND relname = table;

    simulated_tables = {
        "public.orders":    {"live": 12500000, "dead": 4200000, "last_vacuum": "2026-06-01 03:00:00", "last_autovacuum": "2026-06-14 22:15:00"},
        "public.sessions":  {"live": 890000,   "dead": 15000,   "last_vacuum": "2026-06-14 04:00:00", "last_autovacuum": "2026-06-15 01:30:00"},
        "public.audit_log": {"live": 45000000, "dead": 8900000, "last_vacuum": "2026-05-20 03:00:00", "last_autovacuum": None},
    }

    key = f"{schema}.{table}"
    data = simulated_tables.get(key, {"live": 0, "dead": 0, "last_vacuum": None, "last_autovacuum": None})

    total = data["live"] + data["dead"]
    dead_ratio = round((data["dead"] / total) * 100, 2) if total > 0 else 0.0

    result = {
        "schema": schema,
        "table": table,
        "live_tuples": data["live"],
        "dead_tuples": data["dead"],
        "dead_ratio_percent": dead_ratio,
        "last_manual_vacuum": data["last_vacuum"],
        "last_autovacuum": data["last_autovacuum"],
        "status": "CRITICAL" if dead_ratio > 20 else "WARNING" if dead_ratio > 10 else "OK",
        "recommendation": "Run VACUUM ANALYZE" if dead_ratio > 20 else "Monitor" if dead_ratio > 10 else "Healthy",
        "checked_at": datetime.datetime.now().isoformat()
    }

    return json.dumps(result, indent=2)


# ---------------------------------------------------------
# TOOL 5: get_database_size
# ---------------------------------------------------------

@mcp.tool()
def get_database_size(database: str) -> str:
    """Get the size of a database in human-readable format.
    Returns total size, table data size, index size, and toast size.
    Use this when tracking storage growth or planning capacity."""

    # In production, this would run:
    #   SELECT pg_size_pretty(pg_database_size(database));
    #   and join with pg_stat_user_tables for the breakdown.

    simulated_sizes = {
        "production": {"total_bytes": 268435456000, "total_pretty": "250 GB", "tables": "180 GB", "indexes": "55 GB", "toast": "15 GB"},
        "staging":    {"total_bytes": 10737418240,  "total_pretty": "10 GB",  "tables": "7 GB",   "indexes": "2.5 GB", "toast": "500 MB"},
        "analytics":  {"total_bytes": 536870912000, "total_pretty": "500 GB", "tables": "380 GB", "indexes": "95 GB",  "toast": "25 GB"},
    }

    data = simulated_sizes.get(database, {"total_bytes": 0, "total_pretty": "0 bytes", "tables": "0", "indexes": "0", "toast": "0"})

    result = {
        "database": database,
        "total_size": data["total_pretty"],
        "total_bytes": data["total_bytes"],
        "table_data_size": data["tables"],
        "index_size": data["indexes"],
        "toast_size": data["toast"],
        "checked_at": datetime.datetime.now().isoformat()
    }

    return json.dumps(result, indent=2)


# ---------------------------------------------------------
# START THE SERVER
# ---------------------------------------------------------
# This is the entry point. When you run this file, it starts the MCP server.
# The server listens for MCP protocol connections and routes requests to the
# right tool function - exactly like PostgreSQL listening on port 5432 and
# routing queries to the right executor function.

if __name__ == "__main__":
    mcp.run()
```

Save and close vi (`:wq`).

---

## Step 3: Test the MCP Server Standalone

### Verify the tools register correctly

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Imports the MCP server module and lists all registered tools.
#   This is like running \df in psql to see available functions.
# ---------------------------------------------------------

import sys
sys.path.insert(0, "/tmp")

# Import the server module we just created
# This loads the module and registers all the @mcp.tool() functions
import dba_mcp_server

# Access the server's tool list
# Each tool has a name, description, and parameter schema
print("Registered MCP Tools:")
print("=" * 60)

# List the tools by checking what was registered
tool_names = [
    "check_connections",
    "get_slow_queries",
    "check_replication_status",
    "get_table_bloat",
    "get_database_size"
]

for name in tool_names:
    print(f"  - {name}")

print(f"\nTotal tools: {len(tool_names)}")
print("\nThis is equivalent to:")
print("  SELECT routine_name FROM information_schema.routines")
print("  WHERE routine_schema = 'dba_tools';")

EOF
```

Expected output (yours will differ):
```
Registered MCP Tools:
============================================================
  - check_connections
  - get_slow_queries
  - check_replication_status
  - get_table_bloat
  - get_database_size

Total tools: 5

This is equivalent to:
  SELECT routine_name FROM information_schema.routines
  WHERE routine_schema = 'dba_tools';
```

### Test each tool directly

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Calls each MCP tool function directly and prints the result.
#   This is like calling each stored procedure from psql to verify
#   it works before granting access to an application role.
# ---------------------------------------------------------

import sys
sys.path.insert(0, "/tmp")
from dba_mcp_server import (
    check_connections,
    get_slow_queries,
    check_replication_status,
    get_table_bloat,
    get_database_size
)

print("=" * 60)
print("TESTING DBA MCP TOOLS")
print("=" * 60)

# Test 1: Check connections
print("\n--- Tool: check_connections('production') ---")
result = check_connections(database="production")
print(result)

# Test 2: Slow queries over 5 seconds (5000ms)
print("\n--- Tool: get_slow_queries(5000) ---")
result = get_slow_queries(min_duration_ms=5000)
print(result)

# Test 3: Replication status
print("\n--- Tool: check_replication_status() ---")
result = check_replication_status()
print(result)

# Test 4: Table bloat
print("\n--- Tool: get_table_bloat('public', 'orders') ---")
result = get_table_bloat(schema="public", table="orders")
print(result)

# Test 5: Database size
print("\n--- Tool: get_database_size('production') ---")
result = get_database_size(database="production")
print(result)

print("\n" + "=" * 60)
print("All 5 tools tested successfully.")
print("These tools are now ready to be exposed via MCP.")

EOF
```

Expected output (yours will differ):
```
============================================================
TESTING DBA MCP TOOLS
============================================================

--- Tool: check_connections('production') ---
{
  "database": "production",
  "active_connections": 187,
  "max_connections": 200,
  ...
  "status": "CRITICAL"
}

--- Tool: get_slow_queries(5000) ---
{
  "threshold_ms": 5000,
  "slow_query_count": 3,
  "queries": [
    {"pid": 14523, "duration_ms": 45200, ...},
    ...
  ]
}

--- Tool: check_replication_status() ---
{
  "primary": "pg-primary (10.0.1.10)",
  "replica_count": 3,
  ...
  "overall_status": "CRITICAL"
}

--- Tool: get_table_bloat('public', 'orders') ---
{
  "schema": "public",
  "table": "orders",
  "dead_ratio_percent": 25.15,
  "status": "CRITICAL",
  "recommendation": "Run VACUUM ANALYZE"
}

--- Tool: get_database_size('production') ---
{
  "database": "production",
  "total_size": "250 GB",
  ...
}

============================================================
All 5 tools tested successfully.
These tools are now ready to be exposed via MCP.
```

---

## Step 4: Run the MCP Server

On your **Mac terminal**, start the MCP server:

```bash
python3 /tmp/dba_mcp_server.py
```

The server starts and listens for MCP protocol connections. It does not print much output - it just waits for clients. This is the same behavior as `pg_ctl start` - the server is running in the foreground, waiting for connections.

Press `Ctrl+C` to stop it when you are done testing.

---

## Step 5: Test with the MCP Inspector

The MCP Inspector is a web-based testing tool that connects to your MCP server and lets you call tools interactively - like pgAdmin is for PostgreSQL.

On your **Mac terminal**, install and run the inspector:

```bash
npx @modelcontextprotocol/inspector python3 /tmp/dba_mcp_server.py
```

This opens a browser window where you can:
1. See all 5 registered tools listed on the left
2. Click a tool to see its parameters
3. Fill in parameters and click "Run" to see the result

Try these in the inspector:
- `check_connections` with database = `production`
- `get_slow_queries` with min_duration_ms = `10000`
- `get_table_bloat` with schema = `public`, table = `audit_log`

**DBA analogy:** The MCP Inspector is like pgAdmin's function browser. You can see all stored procedures, their parameter definitions, and run them with test inputs.

---

## Step 6: Connect to Claude Desktop

To make Claude Desktop call your DBA tools directly, you add the MCP server to Claude's configuration file.

On your **Mac terminal**, open the Claude Desktop config:

```bash
vi ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

Add your DBA MCP server to the `mcpServers` section:

```json
{
  "mcpServers": {
    "postgresql-dba": {
      "command": "python3",
      "args": ["/tmp/dba_mcp_server.py"]
    }
  }
}
```

Save and close vi (`:wq`), then restart Claude Desktop.

After restarting, Claude Desktop will show a hammer icon in the chat input. Click it to see your 5 DBA tools listed. Now you can ask Claude things like:

- "Check the connection count on the production database"
- "Are there any slow queries running over 10 seconds?"
- "What's the replication status?"
- "How bloated is the public.orders table?"

Claude will call your MCP tools and use the results to answer.

**DBA analogy:** You just gave Claude a `psql` connection to your monitoring system. It can now call your diagnostic procedures the same way any database client calls stored functions.

---

## What You Learned

| Concept | Python Implementation | DBA Analogy |
|---|---|---|
| MCP protocol | Standard protocol for AI-to-tool communication | PostgreSQL wire protocol - standard for client-to-server |
| MCP server | Python app that exposes tools via `@mcp.tool()` | PostgreSQL server exposing stored procedures |
| MCP client | AI model that discovers and calls tools | psql client that calls `\df` then runs functions |
| Tool registration | `@mcp.tool()` decorator with docstring | `CREATE FUNCTION` + `COMMENT ON FUNCTION` |
| Tool testing | Direct function calls, MCP Inspector | Running functions from psql, using pgAdmin |
| Claude Desktop config | JSON file pointing to your MCP server | `pg_hba.conf` entry allowing a client to connect |

**Next:** Build 02 covers connecting your agent to external services like PagerDuty, Slack, and Jira.
