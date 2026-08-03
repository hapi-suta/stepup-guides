#!/bin/bash
# ============================================================
# INJECT: Conditional Edge Wrong Route
#
# Scenario: A conditional edge function has a bug that routes
# P1 alerts to the low-priority path. Critical alerts get
# delayed recommendations instead of immediate escalation.
#
# What this script does:
#   1. Creates a routing graph with a BUGGY conditional edge
#   2. Processes several alerts including P1 critical alerts
#   3. Shows that P1 alerts are incorrectly routed to low-priority
#   4. Demonstrates the impact: critical alerts get delayed
# ============================================================

echo "============================================"
echo "INJECTING: Conditional Edge Wrong Route"
echo "============================================"
echo ""

python3 << 'PYEOF'

# ============================================================
# THE BUG: A typo in the routing function.
#
# The developer wrote:
#   if severity == "P1":      <- checks the string "P1"
#       return "escalate"
#
# But the classify function returns severity as an integer:
#   severity = 1              <- integer, not string "P1"
#
# So severity == "P1" is ALWAYS False.
# 1 == "P1" is False in Python.
# All alerts go to the low-priority path.
#
# DBA analogy: a WHERE clause that never matches.
#   SELECT * FROM alerts WHERE severity = 'P1'
#   But the column stores integers: severity = 1
#   No rows returned. Critical alerts are invisible.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class AlertState(TypedDict):
    alert_text: str
    severity: object    # BUG: should be str, but classify returns int
    category: str
    route_taken: str
    response: str
    response_time: str
    log: Annotated[list, operator.add]

def classify(state: AlertState) -> dict:
    """Classify alert and assign severity."""
    text = state["alert_text"].lower()

    if "replication" in text or "lag" in text:
        category = "replication"
    elif "disk" in text or "full" in text:
        category = "storage"
    elif "cpu" in text or "slow" in text:
        category = "performance"
    else:
        category = "general"

    # BUG: Returns severity as INTEGER (1, 2, 3, 4)
    # The routing function compares against STRING ("P1", "P2")
    if any(kw in text for kw in ["down", "crash", "data loss", "100%", "corruption"]):
        severity = 1    # BUG: should be "P1"
    elif any(kw in text for kw in ["95%", "98%", "critical"]):
        severity = 1    # BUG: should be "P1"
    elif any(kw in text for kw in ["high", "increasing", "lag"]):
        severity = 2    # BUG: should be "P2"
    else:
        severity = 4    # BUG: should be "P4"

    print(f"  [classify] category={category}, severity={severity} (type: {type(severity).__name__})")
    return {"category": category, "severity": severity}

def route_by_severity(state: AlertState) -> str:
    """Route based on severity.

    BUG: Compares integer severity against string literals.
    severity=1 never equals "P1", so ALL alerts go to low_priority.
    """
    severity = state["severity"]
    if severity == "P1":        # BUG: 1 == "P1" is False
        return "escalate"
    elif severity == "P2":      # BUG: 2 == "P2" is False
        return "standard"
    else:
        return "low_priority"   # ALL alerts end up here

def escalate(state: AlertState) -> dict:
    print(f"  [ESCALATE] P1 CRITICAL - paging DBA immediately!")
    return {
        "route_taken": "escalate",
        "response": "ESCALATED: On-call DBA paged. Incident channel opened.",
        "response_time": "< 1 minute",
        "log": ["ESCALATED: immediate response"],
    }

def standard(state: AlertState) -> dict:
    print(f"  [standard] P2/P3 - running diagnostics")
    return {
        "route_taken": "standard",
        "response": "STANDARD: Diagnostics running. DBA notified via Slack.",
        "response_time": "5-15 minutes",
        "log": ["STANDARD: normal response"],
    }

def low_priority(state: AlertState) -> dict:
    print(f"  [low_priority] P4 - logging for next business day")
    return {
        "route_taken": "low_priority",
        "response": "LOGGED: Added to backlog for next business day review.",
        "response_time": "24+ hours",
        "log": ["LOW PRIORITY: delayed response"],
    }

# Build the BUGGY graph
builder = StateGraph(AlertState)
builder.add_node("classify", classify)
builder.add_node("escalate", escalate)
builder.add_node("standard", standard)
builder.add_node("low_priority", low_priority)

builder.set_entry_point("classify")
builder.add_conditional_edges(
    "classify",
    route_by_severity,
    {
        "escalate": "escalate",
        "standard": "standard",
        "low_priority": "low_priority",
    }
)
builder.add_edge("escalate", END)
builder.add_edge("standard", END)
builder.add_edge("low_priority", END)

graph = builder.compile()

print("BUGGY Conditional Edge Routing")
print("=" * 55)

test_alerts = [
    "PRIMARY DATABASE IS DOWN - possible data loss!!",
    "Disk usage at 98% CRITICAL on pg-primary /pgdata",
    "Replication lag increasing on standby-2",
    "Routine checkpoint completed",
]

results = []
for alert in test_alerts:
    print(f"\nAlert: {alert}")
    print("-" * 55)
    result = graph.invoke({
        "alert_text": alert,
        "severity": None, "category": "", "route_taken": "",
        "response": "", "response_time": "", "log": [],
    })
    results.append(result)
    print(f"  Route:    {result['route_taken']}")
    print(f"  Response: {result['response_time']}")

# Summary
print(f"\n{'=' * 55}")
print("IMPACT SUMMARY")
print("=" * 55)

p1_alerts = [r for r in results if "DOWN" in r.get("log", [""])[0] or True]
escalated = sum(1 for r in results if r["route_taken"] == "escalate")
low_pri = sum(1 for r in results if r["route_taken"] == "low_priority")

print(f"""
All {len(results)} alerts were routed to: low_priority
Escalated: {escalated} (should be 2)
Low priority: {low_pri} (should be 1)

THE BUG:
  classify() returns severity as INTEGER: 1, 2, 3, 4
  route_by_severity() compares against STRING: "P1", "P2"
  1 == "P1" is False in Python
  All alerts fall through to the else branch (low_priority)

IMPACT:
  - Database is DOWN: response time 24+ hours (should be < 1 min)
  - Disk at 98%: response time 24+ hours (should be < 1 min)
  - Every P1 alert is silently deprioritized
  - The DBA is never paged
  - Data loss is likely

This is a TYPE MISMATCH bug - one of the most common
and hardest to catch because Python doesn't error out.
1 == "P1" just returns False silently.

Now run the runbook to diagnose and fix this.
""")
PYEOF
