"""USE exercise 2 helper: summarize audit.log into a human-readable report.

Reads the JSON-lines audit trail the agent writes and prints a tidy summary:
what the goal was, how many tool calls, which actions were approved or denied,
and whether any limit stopped the run. This is the "sample audit log" deliverable.

Run:  python3 audit_report.py            (reads ./audit.log)
      python3 audit_report.py path.log   (reads a specific file)
"""

from __future__ import annotations

import json
import sys


def main(path: str = "audit.log") -> None:
    try:
        with open(path, encoding="utf-8") as fh:
            records = [json.loads(line) for line in fh if line.strip()]
    except FileNotFoundError:
        print(f"No audit log at {path} - run the agent first.")
        sys.exit(1)

    tool_calls = [r for r in records if r["event"] == "tool_call"]
    approved = [r for r in records if r["event"] == "action_approved"]
    denied = [r for r in records if r["event"] == "action_denied"]
    refused = [r for r in records if r["event"] == "tool_refused_unknown"]
    stops = [r for r in records if r["event"] in ("stop", "final")]

    print("===== AUDIT REPORT =====")
    start = next((r for r in records if r["event"] == "run_start"), None)
    if start:
        print(f"goal:            {start.get('goal')}")
        print(f"limits:          max_tool_calls={start.get('max_tool_calls')} max_tokens={start.get('max_tokens')}")
    print(f"tool calls:      {len(tool_calls)}")
    for r in tool_calls:
        status = "ok" if r.get("ok") else f"ERROR ({r.get('error')})"
        print(f"  - {r['name']:16} {status}")
    print(f"actions approved: {len(approved)}")
    print(f"actions denied:   {len(denied)}")
    print(f"unknown tools refused: {len(refused)}")
    if stops:
        last = stops[-1]
        reason = last.get("reason") or last.get("event")
        print(f"run ended:       {reason}")
    print("========================")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "audit.log")
