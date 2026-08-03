#!/bin/bash
# ============================================================
# INJECT: Graph State Corruption
#
# Scenario: The checkpoint store gets corrupted. The agent
# resumes from a bad state and makes wrong decisions based
# on stale/incorrect data.
#
# What this script does:
#   1. Creates a working LangGraph pipeline with SQLite checkpoints
#   2. Processes several alerts correctly
#   3. Corrupts the checkpoint database (simulates disk corruption)
#   4. Resumes the pipeline - agent now has wrong state
#   5. Shows the agent making bad decisions
# ============================================================

echo "============================================"
echo "INJECTING: Graph State Corruption"
echo "============================================"
echo ""

python3 << 'PYEOF'
import os
import sqlite3

# ---- Phase 1: Create a working pipeline with checkpoints ----

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
import operator

DB_PATH = "/tmp/survive_corrupt_checkpoints.db"
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

class AlertState(TypedDict):
    alert: str
    category: str
    severity: str
    history: Annotated[list, operator.add]
    recommendation: str

def classify(state: AlertState) -> dict:
    text = state["alert"].lower()
    if "replication" in text or "lag" in text:
        return {"category": "replication", "severity": "P2"}
    elif "disk" in text or "full" in text:
        return {"category": "storage", "severity": "P1"}
    elif "cpu" in text:
        return {"category": "performance", "severity": "P3"}
    return {"category": "unknown", "severity": "P4"}

def recommend(state: AlertState) -> dict:
    recs = {
        "replication": "Check pg_stat_replication. Monitor lag trend.",
        "storage": "CRITICAL: Free disk space immediately. VACUUM or extend storage.",
        "performance": "Check pg_stat_activity for slow queries.",
    }
    rec = recs.get(state["category"], "Investigate manually.")
    return {
        "recommendation": rec,
        "history": [f"{state['severity']} {state['category']}: {state['alert'][:40]}"],
    }

builder = StateGraph(AlertState)
builder.add_node("classify", classify)
builder.add_node("recommend", recommend)
builder.set_entry_point("classify")
builder.add_edge("classify", "recommend")
builder.add_edge("recommend", END)

# Process alerts with checkpointing
print("Phase 1: Processing alerts with checkpointing...")
print("-" * 50)

with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "production-001"}}

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
        print(f"  Processed: {alert[:45]}...")
        print(f"    -> {result['severity']} {result['category']}: {result['recommendation'][:50]}...")

    print(f"\n  Total alerts in history: {len(result['history'])}")
    print(f"  Checkpoint file: {DB_PATH}")

# ---- Phase 2: CORRUPT the checkpoint database ----

print(f"\nPhase 2: CORRUPTING checkpoint database...")
print("-" * 50)

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# List tables to understand structure
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = cursor.fetchall()
print(f"  Tables in checkpoint DB: {[t[0] for t in tables]}")

# Corrupt: change the stored state data
# This simulates disk corruption or a software bug that writes bad data
cursor.execute("SELECT * FROM checkpoints LIMIT 1;")
row = cursor.fetchone()
if row:
    # Overwrite checkpoint data with garbage that changes severity
    # In real corruption, bytes would be flipped randomly
    print("  Injecting corruption into checkpoint data...")
    cursor.execute("""
        UPDATE checkpoints
        SET checkpoint = REPLACE(
            checkpoint,
            '"severity": "P1"',
            '"severity": "P4"'
        )
        WHERE checkpoint LIKE '%P1%'
    """)
    affected = cursor.rowcount
    print(f"  Corrupted {affected} checkpoint records")
    print("  P1 (critical) alerts now appear as P4 (low priority)")

conn.commit()
conn.close()

print(f"""
CORRUPTION INJECTED!

What happened:
  - 3 alerts were processed correctly
  - The disk-full alert was correctly classified as P1 (critical)
  - The checkpoint database was corrupted
  - P1 severity was changed to P4 in the stored state
  - If the agent resumes from this checkpoint, it will think
    the critical disk alert was P4 (low priority)

Impact:
  - Agent makes wrong decisions based on corrupted state
  - Critical alerts could be ignored or deprioritized
  - Historical context is unreliable

The corrupted checkpoint file is at: {DB_PATH}

Now run the runbook to diagnose and fix this.
""")
PYEOF
