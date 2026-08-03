# Runbook: Graph State Corruption

The checkpoint store is corrupted. The agent resumes from bad state and makes wrong decisions.

---

## Symptoms

- Agent classifies previously-critical alerts as low priority
- Recommendations don't match the actual alert severity
- Historical context in state contains incorrect data
- DBA notices the agent "forgot" a P1 alert or demoted it

---

## Step 1. Detect the corruption

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# DETECT: Is the checkpoint state corrupt?
#
# DBA analogy: pg_checksums detects data corruption.
# We need the same concept for agent state.
#
# Strategy:
#   1. Load the checkpoint
#   2. Run consistency checks on the state
#   3. Compare severity in state vs. what the alert text suggests
# ============================================================

import os
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
import operator

DB_PATH = "/tmp/survive_corrupt_checkpoints.db"

class AlertState(TypedDict):
    alert: str
    category: str
    severity: str
    history: Annotated[list, operator.add]
    recommendation: str

def dummy(state: AlertState) -> dict:
    return {}

builder = StateGraph(AlertState)
builder.add_node("dummy", dummy)
builder.set_entry_point("dummy")
builder.add_edge("dummy", END)

with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "production-001"}}

    state = graph.get_state(config)

    print("Checkpoint State Inspection")
    print("=" * 55)
    print(f"\nCurrent state values:")
    for key, value in state.values.items():
        if isinstance(value, list):
            print(f"  {key}: [{len(value)} items]")
            for item in value:
                print(f"    - {item}")
        else:
            print(f"  {key}: {value}")

    # Consistency check: look for mismatches
    print(f"\nConsistency Checks:")
    print("-" * 45)

    history = state.values.get("history", [])
    issues_found = 0

    for entry in history:
        # Each entry looks like "P2 replication: Replication lag 30s..."
        parts = entry.split(" ", 2)
        if len(parts) >= 2:
            stored_severity = parts[0]
            alert_text = parts[-1] if len(parts) > 2 else ""

            # Check: does the severity match the alert content?
            text_lower = alert_text.lower()
            expected_severity = "P4"  # default

            if any(kw in text_lower for kw in ["critical", "down", "crash", "96%", "98%", "99%"]):
                expected_severity = "P1"
            elif any(kw in text_lower for kw in ["lag", "high", "spike"]):
                expected_severity = "P2"

            if stored_severity != expected_severity:
                print(f"  MISMATCH: stored={stored_severity}, expected={expected_severity}")
                print(f"            entry: {entry}")
                issues_found += 1
            else:
                print(f"  OK:       {stored_severity} matches for: {entry[:40]}...")

    if issues_found > 0:
        print(f"\n  CORRUPTION DETECTED: {issues_found} severity mismatch(es)")
        print(f"  Agent state is unreliable. Do NOT resume from this checkpoint.")
    else:
        print(f"\n  All checks passed. State appears consistent.")

PYEOF
```

Expected output (yours will differ):

```
Checkpoint State Inspection
=======================================================
...
Consistency Checks:
---------------------------------------------
  MISMATCH: stored=P4, expected=P1
            entry: P4 storage: Disk usage at 96% on pg-primary /pgda
  ...
  CORRUPTION DETECTED: 1 severity mismatch(es)
```

---

## Step 2. Understand the impact

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("Impact Assessment")
print("=" * 55)

print("""
What went wrong:
  The checkpoint database was corrupted.
  P1 (critical) severity was changed to P4 (low priority).

  If the agent resumes from this state:
    - It thinks the disk-full alert was P4 (routine)
    - It won't escalate or page the on-call DBA
    - The disk fills to 100% and PostgreSQL shuts down
    - Data loss is possible if WAL can't be written

This is the same as WAL corruption in PostgreSQL:
  - Corrupted WAL -> wrong data on recovery
  - Corrupted checkpoint -> wrong agent decisions on resume

DBA parallel:
  pg_checksums catches data page corruption.
  We need checksum-like validation for agent state.
""")
PYEOF
```

---

## Step 3. Fix - rebuild state from source data

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# FIX: Rebuild the agent state from source data
#
# Strategy: re-process the original alerts through the pipeline.
# Don't trust the corrupted checkpoint - rebuild from scratch.
#
# DBA analogy: pg_resetwal + replay.
#   When WAL is corrupted, you restore from backup and replay.
#   Same idea: throw away corrupt state, rebuild from source.
# ============================================================

import os
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
import operator

# Step 1: Delete the corrupted checkpoint
CORRUPT_DB = "/tmp/survive_corrupt_checkpoints.db"
CLEAN_DB = "/tmp/survive_clean_checkpoints.db"

if os.path.exists(CLEAN_DB):
    os.remove(CLEAN_DB)

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
    elif "disk" in text or "full" in text or "96%" in text:
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

# Rebuild state from original alerts
print("Rebuilding State from Source Data")
print("=" * 55)

# These are the original alerts (from your alert source/queue)
original_alerts = [
    "Disk usage at 96% on pg-primary /pgdata - CRITICAL",
    "Replication lag 30s on standby-2",
    "CPU spike 85% on pg-analytics",
]

with SqliteSaver.from_conn_string(CLEAN_DB) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "production-001"}}

    for alert in original_alerts:
        result = graph.invoke({
            "alert": alert, "category": "", "severity": "",
            "history": [], "recommendation": "",
        }, config=config)
        print(f"  Reprocessed: {result['severity']} {result['category']}: {alert[:40]}...")

    print(f"\nRebuilt state:")
    state = graph.get_state(config)
    for entry in state.values.get("history", []):
        print(f"  {entry}")

    # Verify the disk alert is correctly P1
    print(f"\nVerification:")
    for entry in state.values.get("history", []):
        if "storage" in entry:
            if "P1" in entry:
                print(f"  PASS: Storage alert is correctly P1 (critical)")
            else:
                print(f"  FAIL: Storage alert severity is wrong")

print(f"""
State rebuilt successfully from source data.
Corrupted checkpoint replaced with clean checkpoint.

Clean checkpoint: {CLEAN_DB}
Corrupted (keep for forensics): {CORRUPT_DB}
""")

# Clean up
os.remove(CLEAN_DB)
PYEOF
```

---

## Step 4. Prevent future corruption

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# PREVENTION: Add state validation to your pipeline
#
# Strategy: validate state after loading from checkpoint.
# If validation fails, refuse to resume and alert the DBA.
#
# DBA analogy: data_checksums in postgresql.conf.
#   PostgreSQL validates checksums on every page read.
#   If a page is corrupt, it refuses to serve it.
#   Same pattern for agent state.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator
import hashlib
import json

class ValidatedState(TypedDict):
    alert: str
    category: str
    severity: str
    history: Annotated[list, operator.add]
    recommendation: str
    state_checksum: str  # NEW: checksum for integrity

def compute_checksum(state_values: dict) -> str:
    """Compute a checksum over critical state fields."""
    critical_fields = {
        "category": state_values.get("category", ""),
        "severity": state_values.get("severity", ""),
        "history": state_values.get("history", []),
    }
    data = json.dumps(critical_fields, sort_keys=True)
    return hashlib.sha256(data.encode()).hexdigest()[:16]

def classify_with_checksum(state: ValidatedState) -> dict:
    text = state["alert"].lower()
    if "disk" in text or "96%" in text:
        cat, sev = "storage", "P1"
    elif "replication" in text or "lag" in text:
        cat, sev = "replication", "P2"
    else:
        cat, sev = "general", "P4"

    # Compute checksum after classification
    new_state = {"category": cat, "severity": sev, "history": state.get("history", [])}
    checksum = compute_checksum({**state, **new_state})

    return {"category": cat, "severity": sev, "state_checksum": checksum}

def validate_state(state: ValidatedState) -> dict:
    """Validate state integrity before acting on it."""
    expected = compute_checksum(state)
    actual = state.get("state_checksum", "none")

    if actual == "none":
        print(f"  [validate] WARNING: No checksum found (first run)")
        return {"history": ["validation: no checksum (ok for first run)"]}
    elif expected != actual:
        print(f"  [validate] CORRUPTION DETECTED!")
        print(f"             Expected: {expected}")
        print(f"             Got:      {actual}")
        print(f"             REFUSING to continue. Alert DBA.")
        # In production: raise an exception or route to error handler
        return {"history": ["CORRUPTION DETECTED - state invalid"]}
    else:
        print(f"  [validate] Checksum valid: {actual}")
        return {"history": ["validation: checksum OK"]}

builder = StateGraph(ValidatedState)
builder.add_node("classify", classify_with_checksum)
builder.add_node("validate", validate_state)
builder.set_entry_point("classify")
builder.add_edge("classify", "validate")
builder.add_edge("validate", END)

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

print("Prevention: State Checksums")
print("=" * 55)

config = {"configurable": {"thread_id": "validated-001"}}

# Normal operation: checksum matches
print("\nTest 1: Normal operation (checksum matches)")
print("-" * 45)
result = graph.invoke({
    "alert": "Disk 96% on pg-primary", "category": "", "severity": "",
    "history": [], "recommendation": "", "state_checksum": "",
}, config=config)

# Simulate corruption: tamper with state
print(f"\nTest 2: After corruption (checksum mismatch)")
print("-" * 45)
graph.update_state(config, {"severity": "P4"})  # Corrupt severity
result = graph.invoke(None, config=config) if graph.get_state(config).next else None

# Show the validation
state = graph.get_state(config)
print(f"\n  Stored severity: {state.values.get('severity', '?')}")
print(f"  Checksum: {state.values.get('state_checksum', '?')}")

print(f"""
Prevention strategies:
  1. STATE CHECKSUMS: hash critical fields after each update.
     On resume, recompute and compare. Refuse if mismatch.

  2. BACKUP CHECKPOINTS: keep the last N good checkpoints.
     If current is corrupt, roll back to a known-good one.
     (Same as pg_basebackup + WAL for point-in-time recovery.)

  3. STATE VALIDATION: before acting on loaded state,
     run consistency checks (severity matches alert text, etc.)

  4. DUAL-WRITE: write checkpoints to both SQLite and PostgreSQL.
     If one is corrupt, recover from the other.
     (Same as synchronous replication for zero data loss.)

DBA parallel:
  data_checksums = on         -> detect page corruption
  wal_level = replica         -> recover from WAL
  synchronous_commit = on     -> no data loss on crash
  Same principles for agent state.
""")
PYEOF
```

---

## Key Takeaways

| Risk | DBA Parallel | Prevention |
|------|-------------|------------|
| Corrupted checkpoint | Corrupted data page | Checksums on state |
| Resume from bad state | Recovery from corrupt WAL | Validate before resume |
| Lost critical severity | Lost transaction | Dual-write checkpoints |
| Stale historical context | Stale statistics | Rebuild from source data |
