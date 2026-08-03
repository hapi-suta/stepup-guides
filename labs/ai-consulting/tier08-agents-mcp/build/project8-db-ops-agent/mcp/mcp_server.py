"""A minimal MCP-style tool server over stdio (stdlib only, no pip installs).

This mirrors how a real MCP server works, kept deliberately small so it runs
on the lab box with no network and no dependencies:

  - The CLIENT launches this file as a subprocess (LOCAL / stdio transport).
  - It talks JSON-RPC-style messages over stdin/stdout, one JSON object per line.
  - It exposes two of the agent's read-only tools: get_db_health, search_runbooks.

This is NOT the official MCP SDK - it is a faithful teaching stand-in that uses
the same host/client/server + transport ideas from Concepts 8.4, so you can see
the protocol end to end without installing anything or needing a key.

Protocol (one JSON object per line):
  request : {"id": 1, "method": "list_tools"}
  request : {"id": 2, "method": "call_tool", "params": {"name": "...", "input": {...}}}
  response: {"id": 1, "result": {...}}
  response: {"id": 2, "error": "..."}          (on failure)
"""

from __future__ import annotations

import json
import os
import sys

# Import the SAME tool functions and schemas the agent already uses, so the MCP
# server is a thin wrapper - no duplicated tool logic.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import agent  # noqa: E402

# Only expose these read-only tools over MCP (allowlist at the server boundary).
EXPOSED = {
    "get_db_health": agent.tool_get_db_health,
    "search_runbooks": agent.tool_search_runbooks,
}
EXPOSED_SCHEMAS = [s for s in agent.TOOL_SCHEMAS if s["name"] in EXPOSED]


def handle(req: dict) -> dict:
    rid = req.get("id")
    method = req.get("method")
    try:
        if method == "list_tools":
            return {"id": rid, "result": {"tools": EXPOSED_SCHEMAS}}
        if method == "call_tool":
            name = req["params"]["name"]
            tool_input = req["params"].get("input", {})
            if name not in EXPOSED:
                return {"id": rid, "error": f"tool '{name}' is not exposed by this server"}
            result = EXPOSED[name](**tool_input)
            return {"id": rid, "result": result}
        return {"id": rid, "error": f"unknown method '{method}'"}
    except Exception as exc:  # noqa: BLE001 - report tool errors to the client, don't crash the server
        return {"id": rid, "error": str(exc)}


def main() -> None:
    # Read one JSON request per line, write one JSON response per line.
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            sys.stdout.write(json.dumps({"id": None, "error": "invalid JSON"}) + "\n")
            sys.stdout.flush()
            continue
        resp = handle(req)
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
