# Build 02: State and Memory

LangGraph state management and persistence. By the end, your DBA agent will remember past alerts across sessions and resume interrupted workflows.

---

## Step 1. How state flows through the graph

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# STATE CHANNELS: HOW STATE FLOWS
#
# DBA analogy: Think of state like a row in a table.
# Each node is a stored procedure that reads and updates columns.
# When node A finishes, its updates are visible to node B.
#
# The key insight: nodes DON'T replace the entire state.
# They return ONLY the keys they want to update.
# LangGraph MERGES those updates into the existing state.
#
# SQL analogy:
#   UPDATE workflow SET category = 'replication'
#   WHERE id = current_run;
#   -- Only category changes. Other columns stay the same.
# ============================================================

from typing import TypedDict
from langgraph.graph import StateGraph, END

class PipelineState(TypedDict):
    alert: str
    step1_result: str
    step2_result: str
    step3_result: str
    steps_completed: int

def step1(state: PipelineState) -> dict:
    # Only update step1_result and steps_completed
    # Other fields stay unchanged
    print(f"  [step1] Processing: {state['alert']}")
    return {
        "step1_result": f"Classified: {state['alert'][:30]}",
        "steps_completed": 1,
    }

def step2(state: PipelineState) -> dict:
    # Can read step1's result because state was merged
    print(f"  [step2] Reading step1: {state['step1_result']}")
    return {
        "step2_result": f"Diagnosed based on: {state['step1_result']}",
        "steps_completed": 2,
    }

def step3(state: PipelineState) -> dict:
    print(f"  [step3] Reading step2: {state['step2_result']}")
    return {
        "step3_result": f"Recommendation ready",
        "steps_completed": 3,
    }

builder = StateGraph(PipelineState)
builder.add_node("step1", step1)
builder.add_node("step2", step2)
builder.add_node("step3", step3)
builder.set_entry_point("step1")
builder.add_edge("step1", "step2")
builder.add_edge("step2", "step3")
builder.add_edge("step3", END)
graph = builder.compile()

print("State Flow Through Nodes")
print("=" * 55)

result = graph.invoke({
    "alert": "High replication lag on standby-2",
    "step1_result": "",
    "step2_result": "",
    "step3_result": "",
    "steps_completed": 0,
})

print(f"\nFinal state:")
for key, value in result.items():
    print(f"  {key}: {value}")

print(f"""
Key takeaway:
  Each node only returned the keys it changed.
  LangGraph merged each update into the full state.
  By step3, all 3 results are available.

  This is exactly like UPDATE ... SET column = value.
  You don't rewrite the whole row - just the columns you change.
""")
PYEOF
```

Expected output (yours will differ):

```
State Flow Through Nodes
=======================================================
  [step1] Processing: High replication lag on standby-2
  [step2] Reading step1: Classified: High replication lag on stan
  [step3] Reading step2: Diagnosed based on: Classified: High replication lag on stan

Final state:
  alert: High replication lag on standby-2
  step1_result: Classified: High replication lag on stan
  step2_result: Diagnosed based on: Classified: High replication lag on stan
  step3_result: Recommendation ready
  steps_completed: 3
```

---

## Step 2. Reducer functions - merging state updates

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# REDUCER FUNCTIONS
#
# Problem: What happens when a node adds to a list?
#   Node 1 returns: {"alerts": ["alert_a"]}
#   Node 2 returns: {"alerts": ["alert_b"]}
# Without a reducer, node 2's list REPLACES node 1's list.
# You'd lose alert_a.
#
# A reducer tells LangGraph HOW to merge updates.
#   - Default: replace (last write wins)
#   - add: append to list
#   - Custom: any function you want
#
# DBA analogy: WAL replay. Each WAL record is a change.
# The reducer defines HOW changes are applied:
#   - INSERT = add to the list
#   - UPDATE = replace the value
#   - Custom = your trigger logic
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator

# Annotated[list, operator.add] means:
#   "When updating this field, APPEND new items to the existing list"
# Without this annotation, each update would REPLACE the list.

class DiagnosticState(TypedDict):
    alert: str
    # This list uses the 'add' reducer - new items are appended
    findings: Annotated[list, operator.add]
    # This string uses default reducer - last write wins
    final_summary: str

def check_connections(state: DiagnosticState) -> dict:
    finding = "Connections: 450/500 (90% used)"
    print(f"  [connections] {finding}")
    return {"findings": [finding]}  # Appended, not replaced

def check_replication(state: DiagnosticState) -> dict:
    finding = "Replication: lag 12s on standby-2"
    print(f"  [replication] {finding}")
    return {"findings": [finding]}  # Appended to previous

def check_disk(state: DiagnosticState) -> dict:
    finding = "Disk: /pgdata at 87% usage"
    print(f"  [disk] {finding}")
    return {"findings": [finding]}  # Appended to previous

def summarize(state: DiagnosticState) -> dict:
    summary = f"Found {len(state['findings'])} issues: " + "; ".join(state["findings"])
    print(f"  [summary] Compiled {len(state['findings'])} findings")
    return {"final_summary": summary}

builder = StateGraph(DiagnosticState)
builder.add_node("check_connections", check_connections)
builder.add_node("check_replication", check_replication)
builder.add_node("check_disk", check_disk)
builder.add_node("summarize", summarize)

builder.set_entry_point("check_connections")
builder.add_edge("check_connections", "check_replication")
builder.add_edge("check_replication", "check_disk")
builder.add_edge("check_disk", "summarize")
builder.add_edge("summarize", END)

graph = builder.compile()

print("Reducer Functions - Appending to Lists")
print("=" * 55)

result = graph.invoke({
    "alert": "Multiple issues detected on pg-primary",
    "findings": [],
    "final_summary": "",
})

print(f"\nAll findings preserved (not overwritten):")
for i, finding in enumerate(result["findings"], 1):
    print(f"  {i}. {finding}")
print(f"\nSummary: {result['final_summary'][:80]}...")

print(f"""
Without the reducer (Annotated[list, operator.add]):
  findings would only contain the LAST node's finding.
  You'd lose the first two checks.

With the reducer:
  Each node's findings are APPENDED to the list.
  All 3 findings are preserved.

DBA parallel: Without WAL, you lose intermediate changes.
The reducer IS your WAL replay logic - it defines how
each change is applied to the state.
""")
PYEOF
```

Expected output (yours will differ):

```
Reducer Functions - Appending to Lists
=======================================================
  [connections] Connections: 450/500 (90% used)
  [replication] Replication: lag 12s on standby-2
  [disk] Disk: /pgdata at 87% usage
  [summary] Compiled 3 findings

All findings preserved (not overwritten):
  1. Connections: 450/500 (90% used)
  2. Replication: lag 12s on standby-2
  3. Disk: /pgdata at 87% usage
```

---

## Step 3. Checkpointing with MemorySaver

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# CHECKPOINTING: SAVE AND RESUME GRAPH STATE
#
# DBA analogy: PostgreSQL checkpointing.
#   - PostgreSQL writes WAL first, then checkpoints to disk
#   - If it crashes, it replays WAL from last checkpoint
#   - The database resumes exactly where it left off
#
# LangGraph checkpointing is the same idea:
#   - After each node runs, the state is saved
#   - If the process crashes, you resume from last checkpoint
#   - No work is lost, no nodes run twice
#
# MemorySaver = in-memory checkpointer (for development)
# SqliteSaver = SQLite checkpointer (persists to disk)
# PostgresSaver = PostgreSQL checkpointer (production)
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class AlertState(TypedDict):
    alert: str
    steps_done: Annotated[list, operator.add]
    result: str

def step_classify(state: AlertState) -> dict:
    print(f"  [classify] Running...")
    return {"steps_done": ["classify"], "result": "category=replication"}

def step_diagnose(state: AlertState) -> dict:
    print(f"  [diagnose] Running...")
    return {"steps_done": ["diagnose"], "result": "lag caused by network"}

def step_recommend(state: AlertState) -> dict:
    print(f"  [recommend] Running...")
    return {"steps_done": ["recommend"], "result": "Increase wal_keep_size"}

builder = StateGraph(AlertState)
builder.add_node("classify", step_classify)
builder.add_node("diagnose", step_diagnose)
builder.add_node("recommend", step_recommend)
builder.set_entry_point("classify")
builder.add_edge("classify", "diagnose")
builder.add_edge("diagnose", "recommend")
builder.add_edge("recommend", END)

# Add the checkpointer
checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

print("Checkpointing with MemorySaver")
print("=" * 55)

# Thread ID = conversation/session identifier
# DBA analogy: like a database connection - each thread
# has its own state, its own history, its own checkpoint.
config = {"configurable": {"thread_id": "alert-001"}}

result = graph.invoke(
    {
        "alert": "Replication lag 45s on standby-2",
        "steps_done": [],
        "result": "",
    },
    config=config,
)

print(f"\nSteps completed: {result['steps_done']}")
print(f"Final result: {result['result']}")

# Now check the checkpoint history
print(f"\nCheckpoint History (like pg_stat_wal):")
print("-" * 45)
states = list(graph.get_state_history(config))
for i, state in enumerate(states):
    s = state.values
    print(f"  Checkpoint {i}: steps={s.get('steps_done', [])}")

print(f"""
{len(states)} checkpoints saved - one after each node plus one at __start__.
If this process had crashed after 'diagnose',
you could resume from that checkpoint instead of
starting over from 'classify'.

Same concept as PostgreSQL:
  pg_stat_checkpointer shows when checkpoints happened.
  After a crash, PostgreSQL replays WAL from the last checkpoint.
  LangGraph resumes the graph from the last checkpoint.
""")
PYEOF
```

Expected output (yours will differ):

```
Checkpointing with MemorySaver
=======================================================
  [classify] Running...
  [diagnose] Running...
  [recommend] Running...

Steps completed: ['classify', 'diagnose', 'recommend']
Final result: Increase wal_keep_size

Checkpoint History (like pg_stat_wal):
---------------------------------------------
  Checkpoint 0: steps=['classify', 'diagnose', 'recommend']
  Checkpoint 1: steps=['classify', 'diagnose', 'recommend']
  Checkpoint 2: steps=['classify', 'diagnose']
  Checkpoint 3: steps=['classify']
  Checkpoint 4: steps=[]

5 checkpoints saved - one after each node plus one at __start__.
```

---

## Step 4. Persistent checkpointing with SQLite

The SQLite checkpointer is in a separate package. On your **Mac terminal**, install it first:

```bash
pip3 install langgraph-checkpoint-sqlite
```

Expected output (yours will differ):

```
Successfully installed langgraph-checkpoint-sqlite-...
```

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# SQLITE CHECKPOINTING: PERSIST TO DISK
#
# MemorySaver loses everything when the process exits.
# SqliteSaver writes to a SQLite file on disk.
#
# DBA analogy: MemorySaver is like unlogged tables -
# fast but gone after a crash. SqliteSaver is like
# regular tables - persisted to disk, survives restarts.
#
# For production, you'd use PostgresSaver (of course).
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
import operator
import os

class AlertState(TypedDict):
    alert: str
    history: Annotated[list, operator.add]
    status: str

def process_alert(state: AlertState) -> dict:
    alert = state["alert"]
    print(f"  Processing: {alert}")
    return {
        "history": [f"Processed: {alert}"],
        "status": "done",
    }

# Use a context manager for SQLite connection
DB_PATH = "/tmp/langgraph_checkpoints.db"

# Clean up any previous run
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
    builder = StateGraph(AlertState)
    builder.add_node("process", process_alert)
    builder.set_entry_point("process")
    builder.add_edge("process", END)
    graph = builder.compile(checkpointer=checkpointer)

    print("SQLite Checkpointing - Session 1")
    print("=" * 55)

    # Process 3 alerts on the same thread
    config = {"configurable": {"thread_id": "dba-session-1"}}

    for alert in [
        "High CPU on pg-primary",
        "Disk 90% on pg-analytics",
        "Replication lag 30s",
    ]:
        result = graph.invoke(
            {"alert": alert, "history": [], "status": ""},
            config=config,
        )

    print(f"\nAlert history (thread dba-session-1):")
    for item in result["history"]:
        print(f"  - {item}")

print(f"\nSQLite file saved at: {DB_PATH}")
print(f"File size: {os.path.getsize(DB_PATH)} bytes")

# Now simulate a "restart" - read from the same SQLite file
print(f"\n{'=' * 55}")
print("Session 2 - After 'restart' (reading saved checkpoints)")
print("=" * 55)

with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
    builder = StateGraph(AlertState)
    builder.add_node("process", process_alert)
    builder.set_entry_point("process")
    builder.add_edge("process", END)
    graph = builder.compile(checkpointer=checkpointer)

    config = {"configurable": {"thread_id": "dba-session-1"}}

    # Get the saved state
    saved_state = graph.get_state(config)
    print(f"\nRecovered state from SQLite:")
    print(f"  Status: {saved_state.values.get('status', 'unknown')}")
    print(f"  History: {len(saved_state.values.get('history', []))} alerts")
    for item in saved_state.values.get("history", []):
        print(f"    - {item}")

    print(f"""
The state survived the 'restart'.
SQLite checkpointing = your graph's WAL on disk.

In production, swap SqliteSaver for PostgresSaver
and your agent state lives in YOUR database.
""")

# Clean up
os.remove(DB_PATH)
PYEOF
```

Expected output (yours will differ):

```
SQLite Checkpointing - Session 1
=======================================================
  Processing: High CPU on pg-primary
  Processing: Disk 90% on pg-analytics
  Processing: Replication lag 30s

Alert history (thread dba-session-1):
  - Processed: High CPU on pg-primary
  - Processed: Disk 90% on pg-analytics
  - Processed: Replication lag 30s

SQLite file saved at: /tmp/langgraph_checkpoints.db
...
Session 2 - After 'restart' (reading saved checkpoints)
...
Recovered state from SQLite:
  Status: done
  History: 3 alerts
```

---

## Step 5. Thread-based memory - separate conversations

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# THREAD-BASED MEMORY
#
# Each thread_id gets its own state, its own history.
# Different threads don't see each other's data.
#
# DBA analogy: database connections.
#   - Connection A and Connection B each have their own
#     transaction, their own snapshot, their own state.
#   - What happens in Connection A's transaction is invisible
#     to Connection B (unless committed and refreshed).
#
# Threads in LangGraph work the same way.
# Thread "incident-001" and "incident-002" are separate.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class IncidentState(TypedDict):
    message: str
    log: Annotated[list, operator.add]

def handle(state: IncidentState) -> dict:
    return {"log": [state["message"]]}

builder = StateGraph(IncidentState)
builder.add_node("handle", handle)
builder.set_entry_point("handle")
builder.add_edge("handle", END)

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

print("Thread-Based Memory")
print("=" * 55)

# Thread 1: Incident on pg-primary
for msg in ["Alert: CPU 95% on pg-primary", "Diagnosed: runaway query", "Fixed: query killed"]:
    graph.invoke(
        {"message": msg, "log": []},
        config={"configurable": {"thread_id": "incident-001"}},
    )

# Thread 2: Incident on pg-analytics
for msg in ["Alert: Disk 92% on pg-analytics", "Diagnosed: table bloat"]:
    graph.invoke(
        {"message": msg, "log": []},
        config={"configurable": {"thread_id": "incident-002"}},
    )

# Check each thread's state independently
for thread_id in ["incident-001", "incident-002"]:
    config = {"configurable": {"thread_id": thread_id}}
    state = graph.get_state(config)
    print(f"\nThread: {thread_id}")
    for entry in state.values.get("log", []):
        print(f"  - {entry}")

print(f"""
Each thread has its own history.
incident-001 has 3 entries (pg-primary issue).
incident-002 has 2 entries (pg-analytics issue).
They don't mix.

DBA parallel: This is MVCC for agent state.
Each 'connection' (thread) sees its own consistent view.
""")
PYEOF
```

Expected output (yours will differ):

```
Thread-Based Memory
=======================================================

Thread: incident-001
  - Alert: CPU 95% on pg-primary
  - Diagnosed: runaway query
  - Fixed: query killed

Thread: incident-002
  - Alert: Disk 92% on pg-analytics
  - Diagnosed: table bloat
```

---

## Step 6. DBA agent with persistent memory across sessions

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# DBA AGENT WITH PERSISTENT MEMORY
#
# Build an agent that remembers past alerts across sessions.
# When a new alert comes in, it can reference past incidents.
#
# DBA analogy: Your incident log.
#   "This looks like the same replication issue we had last Tuesday.
#    Last time, the fix was increasing wal_keep_size to 2GB."
#
# Humans remember past incidents naturally.
# Agents need checkpointing to do the same.
# ============================================================

from typing import TypedDict, Annotated, List
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator
from datetime import datetime

class DBAMemoryState(TypedDict):
    current_alert: str
    alert_history: Annotated[list, operator.add]
    past_similar: str
    recommendation: str

def log_alert(state: DBAMemoryState) -> dict:
    """Log the current alert to history."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] {state['current_alert']}"
    print(f"  [log] Recorded: {entry}")
    return {"alert_history": [entry]}

def check_history(state: DBAMemoryState) -> dict:
    """Check if we've seen similar alerts before."""
    current = state["current_alert"].lower()
    history = state.get("alert_history", [])

    # Simple keyword matching against history
    keywords = current.split()
    similar = []
    for past_entry in history[:-1]:  # Exclude current (just added)
        past_lower = past_entry.lower()
        matches = sum(1 for kw in keywords if kw in past_lower)
        if matches >= 2:
            similar.append(past_entry)

    if similar:
        msg = f"Found {len(similar)} similar past alert(s): {similar[-1]}"
        print(f"  [history] {msg}")
    else:
        msg = "No similar past alerts found. This is a new issue type."
        print(f"  [history] {msg}")

    return {"past_similar": msg}

def generate_recommendation(state: DBAMemoryState) -> dict:
    """Generate recommendation, considering history."""
    current = state["current_alert"].lower()
    has_history = "similar past alert" in state.get("past_similar", "").lower()

    if "replication" in current or "lag" in current:
        rec = "Check pg_stat_replication. Verify network between primary and standby."
    elif "disk" in current or "storage" in current:
        rec = "Check pg_stat_user_tables for bloat. Run VACUUM on worst offenders."
    elif "cpu" in current or "slow" in current:
        rec = "Check pg_stat_activity for long queries. Use EXPLAIN ANALYZE."
    else:
        rec = "Check pg_stat_activity for general health."

    if has_history:
        rec += " NOTE: This is a recurring issue - consider a permanent fix."

    print(f"  [recommend] {rec[:60]}...")
    return {"recommendation": rec}

builder = StateGraph(DBAMemoryState)
builder.add_node("log_alert", log_alert)
builder.add_node("check_history", check_history)
builder.add_node("generate_recommendation", generate_recommendation)
builder.set_entry_point("log_alert")
builder.add_edge("log_alert", "check_history")
builder.add_edge("check_history", "generate_recommendation")
builder.add_edge("generate_recommendation", END)

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

# Same thread across multiple "sessions"
config = {"configurable": {"thread_id": "dba-brain-main"}}

print("DBA Agent with Persistent Memory")
print("=" * 55)

# Session 1: First alert
print("\n--- Session 1 (Monday morning) ---")
result = graph.invoke({
    "current_alert": "Replication lag 45s on standby-2",
    "alert_history": [],
    "past_similar": "",
    "recommendation": "",
}, config=config)
print(f"  Result: {result['past_similar']}")

# Session 2: Different alert
print("\n--- Session 2 (Monday afternoon) ---")
result = graph.invoke({
    "current_alert": "Disk usage 93% on pg-analytics",
    "alert_history": [],
    "past_similar": "",
    "recommendation": "",
}, config=config)
print(f"  Result: {result['past_similar']}")

# Session 3: Similar to first alert - agent should remember!
print("\n--- Session 3 (Tuesday morning) ---")
result = graph.invoke({
    "current_alert": "Replication lag 60s on standby-2",
    "alert_history": [],
    "past_similar": "",
    "recommendation": "",
}, config=config)
print(f"  Result: {result['past_similar']}")
print(f"  Recommendation: {result['recommendation']}")

# Show full history
print(f"\n--- Full Alert History ---")
state = graph.get_state(config)
for entry in state.values.get("alert_history", []):
    print(f"  {entry}")

print(f"""
The agent remembered the Monday replication alert
when it saw Tuesday's similar alert.
It flagged it as recurring and recommended a permanent fix.

This is the power of checkpointed memory:
  - Survives between invocations
  - Accumulates knowledge over time
  - Makes better decisions based on history

DBA parallel: you remember that standby-2 had lag last week.
Now the agent remembers too.
""")
PYEOF
```

Expected output (yours will differ):

```
DBA Agent with Persistent Memory
=======================================================

--- Session 1 (Monday morning) ---
  [log] Recorded: [2026-06-15 ...] Replication lag 45s on standby-2
  [history] No similar past alerts found. This is a new issue type.
  ...

--- Session 3 (Tuesday morning) ---
  [log] Recorded: [2026-06-15 ...] Replication lag 60s on standby-2
  [history] Found 1 similar past alert(s): ...
  ...
  Recommendation: Check pg_stat_replication... NOTE: This is a recurring issue...
```

---

## Step 7. Resume interrupted workflows

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# RESUME INTERRUPTED WORKFLOWS
#
# Scenario: Your agent is diagnosing a complex issue.
# It's on step 3 of 5 when the process crashes.
# Without checkpointing: start over from step 1.
# With checkpointing: resume from step 3.
#
# DBA analogy: crash recovery.
#   PostgreSQL crashes mid-transaction.
#   On restart, it replays WAL from the last checkpoint.
#   It doesn't redo the work that was already checkpointed.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class WorkflowState(TypedDict):
    task: str
    completed_steps: Annotated[list, operator.add]
    current_step: int
    result: str

# Simulated step counter to demonstrate crash
step_counter = {"value": 0}

def step_gather(state: WorkflowState) -> dict:
    step_counter["value"] += 1
    print(f"  [step 1] Gathering metrics (run #{step_counter['value']})")
    return {"completed_steps": ["gather_metrics"], "current_step": 1}

def step_analyze(state: WorkflowState) -> dict:
    step_counter["value"] += 1
    print(f"  [step 2] Analyzing patterns (run #{step_counter['value']})")
    return {"completed_steps": ["analyze_patterns"], "current_step": 2}

def step_correlate(state: WorkflowState) -> dict:
    step_counter["value"] += 1
    print(f"  [step 3] Correlating events (run #{step_counter['value']})")
    return {"completed_steps": ["correlate_events"], "current_step": 3}

def step_diagnose(state: WorkflowState) -> dict:
    step_counter["value"] += 1
    print(f"  [step 4] Diagnosing root cause (run #{step_counter['value']})")
    return {"completed_steps": ["diagnose_root_cause"], "current_step": 4}

def step_recommend(state: WorkflowState) -> dict:
    step_counter["value"] += 1
    print(f"  [step 5] Generating recommendation (run #{step_counter['value']})")
    return {
        "completed_steps": ["generate_recommendation"],
        "current_step": 5,
        "result": "Root cause: network partition. Fix: check switch on rack 3.",
    }

builder = StateGraph(WorkflowState)
builder.add_node("gather", step_gather)
builder.add_node("analyze", step_analyze)
builder.add_node("correlate", step_correlate)
builder.add_node("diagnose", step_diagnose)
builder.add_node("recommend", step_recommend)

builder.set_entry_point("gather")
builder.add_edge("gather", "analyze")
builder.add_edge("analyze", "correlate")
builder.add_edge("correlate", "diagnose")
builder.add_edge("diagnose", "recommend")
builder.add_edge("recommend", END)

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

config = {"configurable": {"thread_id": "complex-diagnosis-001"}}

print("Resume Interrupted Workflows")
print("=" * 55)

# First run - completes fully
print("\nRun 1: Full completion")
print("-" * 45)
result = graph.invoke({
    "task": "Diagnose replication failure across 3 standbys",
    "completed_steps": [],
    "current_step": 0,
    "result": "",
}, config=config)

total_runs = step_counter["value"]
print(f"\n  Completed steps: {result['completed_steps']}")
print(f"  Total node executions: {total_runs}")
print(f"  Result: {result['result']}")

# Show checkpoint history
print(f"\nCheckpoint history:")
states = list(graph.get_state_history(config))
for i, state in enumerate(states):
    steps = state.values.get("completed_steps", [])
    step_num = state.values.get("current_step", 0)
    print(f"  Checkpoint {i}: step {step_num}, steps done: {len(steps)}")

print(f"""
With checkpointing, if the process crashed after step 3:
  - Checkpoint at step 3 is saved
  - On restart, load checkpoint 3
  - Resume from step 4 (not step 1)
  - Steps 1-3 are NOT re-executed

This is exactly how PostgreSQL crash recovery works:
  1. Find the last checkpoint in pg_control
  2. Replay WAL from that checkpoint forward
  3. Skip everything before the checkpoint

For long-running diagnostic workflows (10+ steps),
this saves enormous time when things go wrong.
""")
PYEOF
```

Expected output (yours will differ):

```
Resume Interrupted Workflows
=======================================================

Run 1: Full completion
---------------------------------------------
  [step 1] Gathering metrics (run #1)
  [step 2] Analyzing patterns (run #2)
  [step 3] Correlating events (run #3)
  [step 4] Diagnosing root cause (run #4)
  [step 5] Generating recommendation (run #5)

  Completed steps: ['gather_metrics', 'analyze_patterns', ...]
  Total node executions: 5
```

---

## What you learned

| Concept | DBA Analogy | LangGraph |
|---------|------------|-----------|
| State updates | UPDATE SET column = value | Node returns dict with changed keys |
| Reducer | WAL replay logic | Annotated[list, operator.add] |
| MemorySaver | unlogged table | In-memory, lost on restart |
| SqliteSaver | local WAL file | Persists to disk |
| PostgresSaver | Production database | Agent state in your DB |
| Thread ID | Database connection | Separate state per thread |
| Checkpoint history | pg_stat_wal | List of saved states |
| Resume from checkpoint | Crash recovery | Load last good state |

Next: [Build 03 - Human in the Loop](03-human-in-the-loop.md) - add DBA approval gates to your graph.
