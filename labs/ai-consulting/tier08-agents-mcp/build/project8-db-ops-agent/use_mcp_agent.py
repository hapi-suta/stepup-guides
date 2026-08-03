"""USE exercise 1: run the agent with two of its tools served OVER MCP.

Instead of calling the Python tool functions directly, this driver routes
get_db_health and search_runbooks through the local MCP server (mcp/mcp_server.py)
via the MCP client (mcp/mcp_client.py). Same agent, same harness - the two read
tools now come across the MCP protocol. Mock model, stdlib only, no API key.

Run:  python3 use_mcp_agent.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp"))

import agent  # noqa: E402
from mcp_client import MCPClient  # noqa: E402


def _always_approve(name, tool_input):
    print(f"[auto-approve] approving action '{name}'")
    return True


def main() -> None:
    client = MCPClient()
    try:
        offered = [t["name"] for t in client.list_tools()]
        print(f"MCP server offers: {offered}")

        # Point the agent's two read tools at the MCP server.
        agent.TOOLS["get_db_health"] = lambda instance: client.call_tool("get_db_health", {"instance": instance})
        agent.TOOLS["search_runbooks"] = lambda query: client.call_tool("search_runbooks", {"query": query})

        agent.reset_audit()
        result = agent.run("Check the health of pg-prod-1 and write an incident report.",
                           approver=_always_approve)

        print("\n===== AGENT (tools over MCP) RESULT =====")
        print(f"stopped because: {result['stopped']}   tool calls: {result['tool_calls']}")
        print("----- final answer -----")
        print(result["answer"])
    finally:
        client.close()


if __name__ == "__main__":
    main()
