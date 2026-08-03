# Concepts: AI Agents & MCP

## What Is an AI Agent?

An AI agent is an AI that DOES things, not just TALKS about things.

Regular AI: "You should check pg_stat_replication for replication lag."
Agent AI: *checks pg_stat_replication itself, reads the result, decides lag is too high, checks what's causing it, and reports back with findings*

The difference: agents have **tools** (functions they can call) and an **agent loop** (a cycle of thinking, acting, and observing results).

## You Already Built One

SutaClaw is an AI agent. When a student says "check my servers", SutaClaw:
1. Thinks: "I need to identify this student and check their server status"
2. Acts: runs `phone-lookup.sh`, then `preflight-check.sh`
3. Observes: reads the script output
4. Thinks: "Servers are running but replication is lagging"
5. Acts: runs a diagnostic query
6. Reports back with findings

That's the agent loop. This module teaches you the formal patterns behind what you've already built intuitively.

## The Agent Loop

Every agent follows the same cycle:

```
USER INPUT: "Why is my database slow?"
         |
         v
   +----------+
   |  THINK   |  "I should check server metrics first"
   +----------+
         |
         v
   +----------+
   |   ACT    |  Calls get_server_metrics("pg-primary")
   +----------+
         |
         v
   +----------+
   | OBSERVE  |  CPU: 95%, connections: 290/300
   +----------+
         |
         v
   +----------+
   |  THINK   |  "CPU is maxed. Let me check what queries are running"
   +----------+
         |
         v
   +----------+
   |   ACT    |  Calls run_sql_query("SELECT * FROM pg_stat_activity WHERE state='active'")
   +----------+
         |
         v
   +----------+
   | OBSERVE  |  250 active queries, most are "SELECT * FROM orders WHERE..."
   +----------+
         |
         v
   +----------+
   |  THINK   |  "250 queries hitting orders table. Missing index. I have enough info."
   +----------+
         |
         v
   FINAL ANSWER: "The orders table is missing an index on the
   column used in your WHERE clause. 250 queries are doing
   full table scans, maxing out CPU at 95%."
```

The agent keeps looping until it has enough information to answer, or hits a maximum number of steps.

## What Are Tools?

Tools are functions the agent can call. Each tool has:
- A **name**: `check_replication_lag`
- A **description**: "Check replication lag between primary and standby"
- An **input schema**: what parameters it accepts (server name, query, etc.)
- An **implementation**: the actual code that runs

You define the tools. Claude decides WHEN and HOW to use them based on the user's question.

## What Is MCP?

MCP (Model Context Protocol) is a standard way to give AI agents access to tools. Instead of hardcoding tool definitions in every script, MCP lets you build a **server** that exposes tools, and any MCP-compatible **client** (Claude Desktop, Claude Code, your own app) can use them.

Think of it like a REST API but for AI tools:
- **MCP Server:** Exposes tools (your code that does things)
- **MCP Client:** Connects to servers and makes tools available to the AI
- **Transport:** How they communicate (stdio for local, SSE for remote)

```
Your MCP Server              Claude (MCP Client)
+-----------------+          +------------------+
| check_pg_status |  <--->   | "Use these tools |
| get_table_bloat |  stdin/  |  to answer the   |
| run_sql_query   |  stdout  |  user's question" |
+-----------------+          +------------------+
```

## Why MCP Matters

Without MCP, every AI app defines tools differently. With MCP:
- Build a tool server once, use it everywhere (Claude Desktop, Claude Code, your own apps)
- Tools are discoverable - the client can ask "what tools do you have?"
- Standard protocol - like HTTP for web, MCP for AI tools
- 110M monthly downloads - faster adoption than React

## Tool Use vs MCP

| | Tool Use (Direct) | MCP |
|---|-------------------|-----|
| Where tools are defined | In your API call | In a separate server |
| Reusability | One script at a time | Any MCP client can use them |
| Discovery | You list tools manually | Client auto-discovers tools |
| Best for | Quick scripts, prototypes | Production, shared tooling |

Start with direct tool use (simpler). Move to MCP when you want to share tools across apps.

## Key Concepts

### Function Calling
Claude doesn't execute code. When it wants to use a tool, it returns a structured request: "call `check_replication_lag` with `server='pg-primary'`". YOUR code executes the function and sends the result back to Claude. Claude reads the result and decides what to do next.

### Tool Choice
Claude decides which tool to use based on:
- The tool's name and description
- The user's question
- Previous observations in the conversation
- You can force a specific tool or let Claude choose

### Max Steps
Agents can loop forever if you're not careful. Always set a maximum number of tool calls (typically 5-10). If the agent hasn't answered by then, it should summarize what it found and admit what's still unknown.

### Safety
Agents can DO things. A tool that runs SQL could run DELETE. A tool that executes shell commands could run `rm -rf`. Always:
- Make tools read-only by default
- Require explicit confirmation for destructive actions
- Sandbox tool execution
- Log every tool call

## What You'll Build

In this module:
1. Direct tool use with Claude's API (Build 01)
2. A complete agent loop that investigates database problems (Build 02)
3. An MCP server that exposes DBA tools to any MCP client (Build 03)

## Prerequisites

- Anthropic API key
- Python with anthropic SDK and mcp package
- PostgreSQL 17 running (for live tool demos)
