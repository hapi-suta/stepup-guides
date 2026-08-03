# Build 03: Building an MCP Server

MCP (Model Context Protocol) lets you build a tool server once and use it from any MCP client - Claude Desktop, Claude Code, or your own apps. Instead of defining tools in every script, you publish them as a service.

---

## Step 1. Install the MCP SDK

On your **Mac terminal**, run:

```bash
pip3 install mcp
```

Expected output (yours will differ):
```
Successfully installed mcp-1.27.2 ...
```

---

## Step 2. Build a DBA tools MCP server

This server exposes PostgreSQL monitoring tools that any MCP client can use.

```bash
cat > ~/Projects/AItech/labs/ai/module04-agents-and-mcp/build/dba_mcp_server.py << 'PYEOF'
"""
DBA Tools MCP Server
Exposes PostgreSQL monitoring and management tools via MCP.

Run: python3 dba_mcp_server.py
Test: Use with Claude Desktop or any MCP client.
"""
from mcp.server.fastmcp import FastMCP
import json
import subprocess

# Create the MCP server
mcp = FastMCP("dba-tools", instructions="""
You have access to PostgreSQL DBA tools. Use them to investigate
database health, check replication, analyze queries, and monitor
server metrics. Always gather data before making recommendations.
""")


# @mcp.tool() is a "decorator" - it wraps the function below it.
# The @ symbol means "register this function as an MCP tool."
# DBA analogy: like creating a trigger. The decorator is the trigger
# definition, the function is the trigger body.
# Without the @, it's just a regular function. With @, it becomes a tool.
@mcp.tool()
def pg_isready(host: str = "localhost", port: int = 5432) -> str:
    """Check if a PostgreSQL server is accepting connections.

    Args:
        host: Server hostname or IP
        port: PostgreSQL port number
    """
    try:
        result = subprocess.run(
            ["/opt/homebrew/opt/postgresql@17/bin/pg_isready", "-h", host, "-p", str(port)],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() or result.stderr.strip()
    except Exception as e:
        return f"Error: {str(e)}"


@mcp.tool()
def run_readonly_query(query: str, database: str = "postgres") -> str:
    """Execute a read-only SQL query on PostgreSQL and return results.
    Only SELECT queries are allowed. INSERT, UPDATE, DELETE, DROP are blocked.

    Args:
        query: SQL SELECT query to execute
        database: Database name to connect to
    """
    # Safety check
    normalized = query.strip().upper()
    blocked = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE", "GRANT"]
    for keyword in blocked:
        if keyword in normalized and not normalized.startswith("SELECT"):
            return json.dumps({"error": f"Blocked: {keyword} queries not allowed. Read-only access only."})

    try:
        result = subprocess.run(
            ["/opt/homebrew/opt/postgresql@17/bin/psql", "-d", database, "-h", "/tmp",
             "-c", query, "-t", "-A", "--pset=format=csv"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return json.dumps({"error": result.stderr.strip()})
        return result.stdout.strip() or "Query returned no results"
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def check_active_queries(min_duration_seconds: int = 0) -> str:
    """List active queries running on PostgreSQL, optionally filtered by minimum duration.

    Args:
        min_duration_seconds: Only show queries running longer than this many seconds (0 for all)
    """
    query = f"""
    SELECT pid, state, usename,
           EXTRACT(EPOCH FROM (now() - query_start))::int AS duration_seconds,
           LEFT(query, 100) AS query_preview
    FROM pg_stat_activity
    WHERE state != 'idle'
      AND pid != pg_backend_pid()
      AND EXTRACT(EPOCH FROM (now() - query_start)) > {min_duration_seconds}
    ORDER BY query_start;
    """
    return run_readonly_query(query)


@mcp.tool()
def check_table_bloat(table_name: str, schema: str = "public") -> str:
    """Check estimated bloat percentage for a table.

    Args:
        table_name: Name of the table to check
        schema: Schema name (default: public)
    """
    query = f"""
    SELECT
        schemaname, relname,
        n_live_tup, n_dead_tup,
        CASE WHEN n_live_tup > 0
             THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
             ELSE 0 END AS dead_pct,
        last_autovacuum,
        last_autoanalyze
    FROM pg_stat_user_tables
    WHERE relname = '{table_name}' AND schemaname = '{schema}';
    """
    return run_readonly_query(query)


@mcp.tool()
def check_connections() -> str:
    """Get current connection counts grouped by state."""
    query = """
    SELECT state, count(*) as count
    FROM pg_stat_activity
    GROUP BY state
    ORDER BY count DESC;
    """
    return run_readonly_query(query)


@mcp.tool()
def check_database_size(database: str = "postgres") -> str:
    """Get the size of a database in human-readable format.

    Args:
        database: Database name to check
    """
    query = f"SELECT pg_size_pretty(pg_database_size('{database}')) AS size;"
    return run_readonly_query(query)


if __name__ == "__main__":
    print("Starting DBA Tools MCP Server...")
    print("Tools available:")
    for name in ["pg_isready", "run_readonly_query", "check_active_queries",
                 "check_table_bloat", "check_connections", "check_database_size"]:
        print(f"  - {name}")
    print()
    print("Connect from Claude Desktop or any MCP client using stdio transport.")
    mcp.run()
PYEOF
echo "MCP server saved to: ~/Projects/AItech/labs/ai/module04-agents-and-mcp/build/dba_mcp_server.py"
```

---

## Step 3. Test the MCP server tools locally

Before connecting to an MCP client, verify each tool works:

```bash
python3 << 'PYEOF'
# Import the tools directly and test them
import sys
sys.path.insert(0, "/Users/hafopezi/Projects/AItech/labs/ai/module04-agents-and-mcp/build")

# Test pg_isready
from dba_mcp_server import pg_isready, run_readonly_query, check_connections, check_database_size

print("=== pg_isready ===")
print(pg_isready())
print()

print("=== check_connections ===")
print(check_connections())
print()

print("=== check_database_size ===")
print(check_database_size())
print()

print("=== run_readonly_query (safe) ===")
print(run_readonly_query("SELECT count(*) FROM pg_stat_activity;"))
print()

print("=== run_readonly_query (blocked) ===")
print(run_readonly_query("DROP TABLE users;"))
PYEOF
```

Expected output (yours will differ):
```
=== pg_isready ===
/tmp:5432 - accepting connections

=== check_connections ===
idle,3
active,1
...

=== check_database_size ===
7 MB

=== run_readonly_query (safe) ===
4

=== run_readonly_query (blocked) ===
{"error": "Blocked: DROP queries not allowed. Read-only access only."}
```

Key things to notice:
- `pg_isready` talks to the real PostgreSQL on your Mac
- `check_connections` runs a real query against pg_stat_activity
- The `DROP TABLE` attempt is blocked by the safety check
- All tools produce usable output

---

## Step 4. Connect to Claude Desktop (optional)

If you have Claude Desktop installed, you can add this MCP server to it.

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "dba-tools": {
      "command": "python3",
      "args": ["/Users/hafopezi/Projects/AItech/labs/ai/module04-agents-and-mcp/build/dba_mcp_server.py"]
    }
  }
}
```

Restart Claude Desktop. You'll see the DBA tools available in the conversation.

---

## Step 5. Understand the MCP architecture

```bash
python3 << 'PYEOF'
print("""
MCP Architecture:

                 Your MCP Server                   MCP Client (Claude)
              +-------------------+              +-------------------+
              |  pg_isready       |    stdio     | "What tools are   |
User  <--->   |  run_readonly_sql |  <-------->  |  available?"      |
              |  check_bloat      |   JSON-RPC   | "Call pg_isready"  |
              |  check_connections|              | "Here's the result"|
              +-------------------+              +-------------------+

Transport options:
  stdio  - Local process. Server runs as a subprocess of the client.
           Best for: Claude Desktop, local development.

  SSE    - Server Sent Events over HTTP. Server runs as a web service.
           Best for: Remote servers, shared team access.

Protocol:
  1. Client connects and asks: "What tools do you have?"
  2. Server responds with tool definitions (name, description, schema)
  3. Client (Claude) decides to call a tool
  4. Server executes the tool and returns results
  5. Repeat until the conversation ends

Key benefit: Build once, use everywhere.
  - Same server works with Claude Desktop, Claude Code, your own apps
  - Tools are discoverable (clients don't need to know in advance)
  - Standard protocol (like HTTP for web apps)
""")

# Show how many MCP servers are in the ecosystem
print("MCP adoption (2026):")
print("  - 110M monthly downloads (faster than React)")
print("  - Supported by: Anthropic, OpenAI, Google, Microsoft")
print("  - Standard for: AI tool integration")
PYEOF
```

---

## What You Learned

| Concept | What It Does | Production Use |
|---------|-------------|----------------|
| FastMCP | Simple Python framework for MCP servers | Build tool servers fast |
| `@mcp.tool()` | Decorator that registers a function as MCP tool | Each function becomes an available tool |
| Safety checks | Block dangerous queries before execution | Prevent destructive actions |
| stdio transport | Local communication between client and server | Claude Desktop, development |
| SSE transport | HTTP-based remote communication | Production, shared servers |
| Tool discovery | Client auto-discovers available tools | No hardcoded tool lists |
