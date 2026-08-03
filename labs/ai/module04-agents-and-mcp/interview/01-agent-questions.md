# Interview 01: AI Agents & MCP Questions

Five questions you might get in an interview about AI agents, tool use, and MCP.

---

## Question 1: Design an Agent for Database Incident Response

**Question:** You're building an AI agent that responds to PagerDuty alerts for PostgreSQL incidents. Walk me through how you'd design it - what tools would it have, how would the agent loop work, and what safety controls would you put in place?

**Strong answer should include:**

**Tools (5-8 specific ones):**
- `get_alert_details(alert_id)` - Pull the alert from PagerDuty
- `get_server_metrics(host)` - CPU, memory, disk, connections
- `run_readonly_query(query, host)` - SELECT-only SQL execution
- `check_replication_status(host)` - Lag, state, slot status
- `get_recent_changes(hours=24)` - Recent deploys, config changes
- `check_logs(host, pattern, minutes=30)` - Search pg_log
- `escalate_to_human(summary, severity)` - Page the on-call DBA
- `post_to_slack(channel, message)` - Update the incident channel

**Agent loop design:**
1. Start: Parse alert, identify severity and affected host
2. Gather: Check metrics, replication, connections (parallel calls)
3. Investigate: Based on findings, drill into specific areas
4. Diagnose: Correlate data, identify root cause
5. Act: For read-only actions, proceed. For writes, escalate to human
6. Report: Post summary to Slack with findings and recommendations

**Safety controls:**
- Read-only database access (SELECT only, no DDL/DML)
- Max 10 steps per incident (prevent runaway investigation)
- Token budget of 50K per incident
- Time limit of 2 minutes per investigation
- Human-in-the-loop for any destructive action (kill process, failover)
- Audit log of every tool call with timestamp and result
- Escalate to human if confidence is below threshold

**Red flags in a weak answer:** No safety controls, agent can run arbitrary SQL, no escalation path, no step limit.

---

## Question 2: Tool Use vs MCP - When Would You Use Each?

**Question:** Your team wants to add AI capabilities to your database monitoring platform. Explain the difference between direct tool use (function calling) and MCP, and recommend which approach for this use case.

**Strong answer should include:**

**Direct tool use:**
- Tools defined inline in each API call
- Best for: single scripts, prototypes, one-off automations
- Simpler to set up (no server process)
- Tools are tightly coupled to the application

**MCP:**
- Tools published as a standalone server
- Any MCP client can discover and use the tools
- Best for: shared tooling, team-wide use, production systems
- Supports multiple transports (stdio for local, SSE for remote)

**Recommendation for monitoring platform:**
MCP - because:
1. Multiple consumers: Claude Desktop for DBAs, web dashboard for managers, CLI for automation
2. Tool discovery: new tools added to the server are automatically available to all clients
3. Separation of concerns: tool implementation lives in one place, not duplicated across apps
4. Team collaboration: one engineer maintains the MCP server, everyone benefits

**Architecture:**
```
MCP Server (dba-tools)          Clients
+------------------+       +-- Claude Desktop (DBAs)
| check_replication|       +-- Web dashboard (managers)
| run_query        | <---> +-- CLI tool (automation)
| get_metrics      |       +-- Incident bot (PagerDuty)
| check_bloat      |       +-- Custom scripts
+------------------+
```

Start with direct tool use in a prototype. Migrate to MCP when you have multiple consumers or team adoption.

---

## Question 3: How Do You Prevent an Agent from Causing Damage?

**Question:** An AI agent has access to tools that can query your production database. How do you prevent it from running destructive queries or consuming too many resources?

**Strong answer should include 4 layers:**

**Layer 1 - Application code:**
- Allowlist approach: only permit SELECT, SHOW, EXPLAIN, WITH
- Reject multi-statement queries (block semicolons in the middle)
- Block dangerous functions (dblink_exec, pg_read_file, COPY)
- Input validation before any tool execution

**Layer 2 - Database permissions:**
- Dedicated read-only role: `GRANT SELECT ON ALL TABLES`
- No GRANT for INSERT, UPDATE, DELETE, TRUNCATE, CREATE, DROP
- Apply to future tables: `ALTER DEFAULT PRIVILEGES`

**Layer 3 - Resource limits:**
- `statement_timeout = '30s'` on the agent's role
- `work_mem = '64MB'` to prevent memory-heavy queries
- Connection pooler limiting agent to 5 connections max
- Rate limiting: max 100 queries per minute

**Layer 4 - Operational controls:**
- Audit log of every query the agent runs
- Alert if agent runs > N queries in a time window
- Kill switch: disable agent access without touching app code
- Human approval required for anything not in the safe list

**Why blocklists fail:**
```sql
-- Blocklist blocks "DROP TABLE"
-- But this bypasses it:
SELECT 1; DROP TABLE users; --
-- Starts with SELECT, passes the check, PostgreSQL runs both
```

**Red flags:** Only mentions one layer. Says "just block DELETE." No database-level permissions.

---

## Question 4: Explain the Agent Loop Pattern

**Question:** What is the agent loop, and how does it differ from a single API call to Claude? Walk me through a concrete example.

**Strong answer:**

**Single API call:** User asks question -> Claude answers. One round trip. Claude can only use its training data.

**Agent loop:** User asks question -> Claude thinks -> calls a tool -> reads result -> thinks again -> calls another tool -> reads result -> provides final answer. Multiple round trips. Claude uses real data.

**Concrete example - "Why is my database slow?":**

```
Step 1 (Think): "I should check server metrics first"
Step 1 (Act):   get_server_metrics("pg-primary")
Step 1 (Observe): CPU 92%, connections 285/300

Step 2 (Think): "CPU is high, connections near limit. Let me check what's running"
Step 2 (Act):   run_sql_query("SELECT * FROM pg_stat_activity WHERE state='active'")
Step 2 (Observe): 240 idle-in-transaction sessions, 1 VACUUM running

Step 3 (Think): "Connection leak. Let me check table health too"
Step 3 (Act):   run_sql_query("SELECT * FROM pg_stat_user_tables WHERE n_dead_tup > 1M")
Step 3 (Observe): orders table has 12.5M dead tuples

Final: "Three issues found: connection leak (240 idle-in-transaction),
        table bloat (12.5M dead tuples on orders), high CPU from
        sequential scans on the bloated table. Here are the fix commands..."
```

**Key components:**
1. **Messages array:** accumulates the full conversation (user -> assistant -> tool_result -> assistant -> ...)
2. **stop_reason:** `tool_use` means keep looping, `end_turn` means done
3. **Max steps:** safety limit (typically 5-10) to prevent infinite loops
4. **Tool results:** sent back as `tool_result` messages with matching `tool_use_id`

**Without the loop:** Claude would say "you should check pg_stat_activity" but wouldn't actually check it.

---

## Question 5: Design an MCP Server for Your Team

**Question:** Your DBA team wants a shared set of AI-powered database tools. Design an MCP server - what tools would you expose, what safety controls, and how would you deploy it?

**Strong answer should include:**

**Tools (organized by category):**

*Health checks:*
- `pg_isready(host, port)` - connection check
- `get_cluster_status()` - primary/standby roles and lag
- `check_connections(host)` - connection counts by state

*Query analysis:*
- `get_slow_queries(min_duration_ms, limit)` - from pg_stat_statements
- `explain_query(query, host)` - run EXPLAIN ANALYZE (read-only)
- `get_blocking_queries(host)` - find lock waiters

*Table health:*
- `check_bloat(table, schema)` - dead tuples and last vacuum
- `check_index_usage(table)` - unused indexes
- `get_table_sizes(top_n)` - largest tables

*Operational:*
- `search_logs(pattern, minutes)` - grep pg_log
- `check_backup_status()` - last backup time and size
- `get_replication_slots()` - slot status and lag

**Safety controls:**
- All tools are read-only (SELECT, SHOW, EXPLAIN only)
- Read-only database role with statement_timeout
- Rate limiting per client
- Audit logging to a separate table
- No shell command execution

**Deployment:**
- SSE transport for remote access (team-wide)
- HTTPS with authentication (API key or mTLS)
- Run as a systemd service on a jump host
- Health check endpoint for monitoring
- Config in environment variables (no hardcoded credentials)

**Claude Desktop config for the team:**
```json
{
  "mcpServers": {
    "dba-tools": {
      "url": "https://dba-mcp.internal.company.com/sse",
      "headers": {
        "Authorization": "Bearer ${DBA_MCP_TOKEN}"
      }
    }
  }
}
```

**Red flags:** Tools that can run arbitrary shell commands. No authentication. Hardcoded database credentials. No rate limiting.
