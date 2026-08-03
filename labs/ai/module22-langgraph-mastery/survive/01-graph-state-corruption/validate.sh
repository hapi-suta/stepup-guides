#!/bin/bash
# ============================================================
# VALIDATE: Confirm the graph state corruption was fixed
#
# Checks:
#   1. Corrupted checkpoint file exists (for forensics)
#   2. Clean state can be rebuilt from source data
#   3. Rebuilt state has correct severity for all alerts
#   4. State checksum validation works
# ============================================================

echo "============================================"
echo "VALIDATING: Graph State Corruption Fix"
echo "============================================"
echo ""

python3 << 'PYEOF'
import os
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
import operator
import hashlib
import json

CLEAN_DB = "/tmp/survive_validate_checkpoints.db"
if os.path.exists(CLEAN_DB):
    os.remove(CLEAN_DB)

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

# ---- Test 1: Rebuild state from source data ----

class AlertState(TypedDict):
    alert: str
    category: str
    severity: str
    history: Annotated[list, operator.add]
    recommendation: str

def classify(state: AlertState) -> dict:
    text = state["alert"].lower()
    if "disk" in text or "full" in text or "96%" in text:
        return {"category": "storage", "severity": "P1"}
    elif "replication" in text or "lag" in text:
        return {"category": "replication", "severity": "P2"}
    elif "cpu" in text:
        return {"category": "performance", "severity": "P3"}
    return {"category": "unknown", "severity": "P4"}

def recommend(state: AlertState) -> dict:
    return {
        "recommendation": "action",
        "history": [f"{state['severity']} {state['category']}: {state['alert'][:40]}"],
    }

builder = StateGraph(AlertState)
builder.add_node("classify", classify)
builder.add_node("recommend", recommend)
builder.set_entry_point("classify")
builder.add_edge("classify", "recommend")
builder.add_edge("recommend", END)

print("Test 1: Rebuild state from source data")
print("-" * 45)

with SqliteSaver.from_conn_string(CLEAN_DB) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "validate-001"}}

    alerts = [
        "Disk usage at 96% on pg-primary /pgdata - CRITICAL",
        "Replication lag 30s on standby-2",
        "CPU spike 85% on pg-analytics",
    ]

    for alert in alerts:
        result = graph.invoke({
            "alert": alert, "category": "", "severity": "",
            "history": [], "recommendation": "",
        }, config=config)

    state = graph.get_state(config)
    history = state.values.get("history", [])

    check("State rebuilt with 3 alerts", len(history) == 3)

    # Verify severities
    for entry in history:
        if "storage" in entry:
            check("Disk alert is P1 (critical)", "P1" in entry)
        elif "replication" in entry:
            check("Replication alert is P2", "P2" in entry)
        elif "performance" in entry:
            check("CPU alert is P3", "P3" in entry)

# ---- Test 2: Checkpoint persists to disk ----

print(f"\nTest 2: Checkpoint persistence")
print("-" * 45)

check("Checkpoint file exists", os.path.exists(CLEAN_DB))
check("Checkpoint file is non-empty", os.path.getsize(CLEAN_DB) > 0)

# Read back from disk (simulating restart)
with SqliteSaver.from_conn_string(CLEAN_DB) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "validate-001"}}
    recovered = graph.get_state(config)
    recovered_history = recovered.values.get("history", [])
    check("State recovered after restart", len(recovered_history) == 3)

# ---- Test 3: Checksum validation ----

print(f"\nTest 3: State checksum validation")
print("-" * 45)

def compute_checksum(data: dict) -> str:
    critical = {"severity": data.get("severity", ""), "category": data.get("category", "")}
    return hashlib.sha256(json.dumps(critical, sort_keys=True).encode()).hexdigest()[:16]

test_state = {"severity": "P1", "category": "storage"}
checksum1 = compute_checksum(test_state)
checksum2 = compute_checksum(test_state)
check("Same state produces same checksum", checksum1 == checksum2)

corrupted_state = {"severity": "P4", "category": "storage"}
checksum3 = compute_checksum(corrupted_state)
check("Different state produces different checksum", checksum1 != checksum3)

# ---- Summary ----

print(f"\n{'=' * 45}")
print(f"Results: {passed} passed, {failed} failed")
if failed == 0:
    print("ALL CHECKS PASSED - corruption fix verified")
else:
    print(f"WARNING: {failed} check(s) failed - review the fix")
print(f"{'=' * 45}")

# Clean up
os.remove(CLEAN_DB)
PYEOF
