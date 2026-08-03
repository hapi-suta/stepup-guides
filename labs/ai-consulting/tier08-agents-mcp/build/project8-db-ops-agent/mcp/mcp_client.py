"""A minimal MCP-style client (stdlib only). Launches mcp_server.py as a local
subprocess and talks to it over stdio - the LOCAL transport from Concepts 8.4.

Use it two ways:
  1. As a library: MCPClient().list_tools() / .call_tool(name, input)
  2. From the CLI:  python3 mcp/mcp_client.py           (demo: list + call)

The agent can use this client to make its tools available OVER MCP instead of
calling the Python functions directly. Same request/execute boundary - the
client asks, the server runs the tool. See USE for wiring it into the agent.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys


class MCPClient:
    def __init__(self, server_path: str = None):
        if server_path is None:
            server_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp_server.py")
        # Launch the server as a subprocess (local stdio transport).
        self.proc = subprocess.Popen(
            [sys.executable, server_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
        )
        self._id = 0

    def _rpc(self, method: str, params: dict = None) -> dict:
        self._id += 1
        req = {"id": self._id, "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("MCP server closed the connection unexpectedly")
        resp = json.loads(line)
        if "error" in resp and resp["error"] is not None:
            raise RuntimeError(f"MCP server error: {resp['error']}")
        return resp["result"]

    def list_tools(self) -> list:
        return self._rpc("list_tools")["tools"]

    def call_tool(self, name: str, tool_input: dict) -> dict:
        return self._rpc("call_tool", {"name": name, "input": tool_input})

    def close(self) -> None:
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:  # noqa: BLE001
            self.proc.kill()


if __name__ == "__main__":
    client = MCPClient()
    try:
        tools = client.list_tools()
        print("Tools offered by the MCP server:")
        for t in tools:
            print(f"  - {t['name']}: {t['description'][:60]}...")
        print("\nCalling get_db_health(instance='pg-prod-1') over MCP:")
        result = client.call_tool("get_db_health", {"instance": "pg-prod-1"})
        print("  ", json.dumps(result))
    finally:
        client.close()
