#!/bin/bash
# ============================================================
# VALIDATE: Confirm the conditional edge routing bug is fixed
#
# Checks:
#   1. P1 alerts route to "escalate"
#   2. P2/P3 alerts route to "standard"
#   3. P4 alerts route to "low_priority"
#   4. Integer severity raises TypeError (not silently passes)
#   5. All 3 routes are reachable
# ============================================================

echo "============================================"
echo "VALIDATING: Conditional Edge Wrong Route Fix"
echo "============================================"
echo ""

python3 << 'PYEOF'
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator

passed = 0
failed = 0

def check(name, condition):
    global passed, failed
    if condition:
        print(f"  PASS: {name}")
        passed += 1
    else:
        print(f"  FAIL: {name}")
        failed += 1

# ---- The FIXED functions ----

class AlertState(TypedDict):
    alert_text: str
    severity: str
    category: str
    route_taken: str
    response_time: str

def classify_fixed(state: AlertState) -> dict:
    text = state["alert_text"].lower()
    if "replication" in text or "lag" in text:
        category = "replication"
    elif "disk" in text or "full" in text:
        category = "storage"
    else:
        category = "general"

    if any(kw in text for kw in ["down", "crash", "data loss", "98%", "critical"]):
        severity = "P1"
    elif any(kw in text for kw in ["high", "increasing", "lag"]):
        severity = "P2"
    else:
        severity = "P4"

    assert isinstance(severity, str), f"severity must be str, got {type(severity).__name__}"
    return {"category": category, "severity": severity}

def route_fixed(state: AlertState) -> str:
    severity = state["severity"]
    if not isinstance(severity, str):
        raise TypeError(f"severity must be str, got {type(severity).__name__}")
    if severity == "P1":
        return "escalate"
    elif severity in ("P2", "P3"):
        return "standard"
    return "low_priority"

def escalate(state: AlertState) -> dict:
    return {"route_taken": "escalate", "response_time": "< 1 minute"}

def standard(state: AlertState) -> dict:
    return {"route_taken": "standard", "response_time": "5-15 minutes"}

def low_priority(state: AlertState) -> dict:
    return {"route_taken": "low_priority", "response_time": "24+ hours"}

# Build the fixed graph
builder = StateGraph(AlertState)
builder.add_node("classify", classify_fixed)
builder.add_node("escalate", escalate)
builder.add_node("standard", standard)
builder.add_node("low_priority", low_priority)
builder.set_entry_point("classify")
builder.add_conditional_edges("classify", route_fixed, {
    "escalate": "escalate",
    "standard": "standard",
    "low_priority": "low_priority",
})
builder.add_edge("escalate", END)
builder.add_edge("standard", END)
builder.add_edge("low_priority", END)
graph = builder.compile()

# ---- Test 1: P1 alerts route to escalate ----

print("Test 1: P1 alerts route to escalate")
print("-" * 45)

p1_alerts = [
    "PRIMARY DATABASE IS DOWN - data loss possible",
    "Disk at 98% CRITICAL on pg-primary",
]

for alert in p1_alerts:
    result = graph.invoke({
        "alert_text": alert, "severity": "", "category": "",
        "route_taken": "", "response_time": "",
    })
    check(f"'{alert[:35]}...' -> escalate", result["route_taken"] == "escalate")

# ---- Test 2: P2 alerts route to standard ----

print(f"\nTest 2: P2 alerts route to standard")
print("-" * 45)

p2_alerts = [
    "Replication lag increasing on standby-2",
]

for alert in p2_alerts:
    result = graph.invoke({
        "alert_text": alert, "severity": "", "category": "",
        "route_taken": "", "response_time": "",
    })
    check(f"'{alert[:35]}...' -> standard", result["route_taken"] == "standard")

# ---- Test 3: P4 alerts route to low_priority ----

print(f"\nTest 3: P4 alerts route to low_priority")
print("-" * 45)

p4_alerts = [
    "Routine checkpoint completed successfully",
]

for alert in p4_alerts:
    result = graph.invoke({
        "alert_text": alert, "severity": "", "category": "",
        "route_taken": "", "response_time": "",
    })
    check(f"'{alert[:35]}...' -> low_priority", result["route_taken"] == "low_priority")

# ---- Test 4: Type safety ----

print(f"\nTest 4: Integer severity raises TypeError")
print("-" * 45)

for bad_val in [1, 2, 4]:
    try:
        route_fixed({"severity": bad_val, "alert_text": "", "category": "", "route_taken": "", "response_time": ""})
        check(f"severity={bad_val} raises TypeError", False)
    except TypeError:
        check(f"severity={bad_val} raises TypeError", True)

# ---- Test 5: All routes reachable ----

print(f"\nTest 5: All routes reachable")
print("-" * 45)

routes_hit = set()
for sev in ["P1", "P2", "P4"]:
    route = route_fixed({"severity": sev, "alert_text": "", "category": "", "route_taken": "", "response_time": ""})
    routes_hit.add(route)

check("All 3 routes reachable", routes_hit == {"escalate", "standard", "low_priority"})

# ---- Summary ----

print(f"\n{'=' * 45}")
print(f"Results: {passed} passed, {failed} failed")
if failed == 0:
    print("ALL CHECKS PASSED - routing fix verified")
else:
    print(f"WARNING: {failed} check(s) failed - review the fix")
print(f"{'=' * 45}")
PYEOF
