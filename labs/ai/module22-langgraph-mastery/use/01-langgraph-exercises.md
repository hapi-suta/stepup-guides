# Use 01: LangGraph Exercises

Apply everything from Builds 01-04. Each exercise builds on the previous one.

---

## Exercise 1: Build a 3-node alert processing graph

Build a graph with 3 nodes: classify, diagnose, recommend. The graph takes a raw database alert and returns an actionable recommendation.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 1: 3-Node Alert Processing Graph
#
# Build this pipeline:
#   classify -> diagnose -> recommend -> END
#
# Requirements:
#   - classify: identify category from keywords
#   - diagnose: suggest diagnostic query based on category
#   - recommend: suggest remediation action
#
# Test with at least 3 different alert types.
# ============================================================

from typing import TypedDict
from langgraph.graph import StateGraph, END

class AlertState(TypedDict):
    alert_text: str
    category: str
    diagnostic_query: str
    recommendation: str

def classify(state: AlertState) -> dict:
    text = state["alert_text"].lower()

    # TODO: Add more categories and keywords
    if "replication" in text or "lag" in text or "standby" in text:
        return {"category": "replication"}
    elif "disk" in text or "space" in text or "full" in text:
        return {"category": "storage"}
    elif "cpu" in text or "slow" in text or "query" in text:
        return {"category": "performance"}
    elif "connection" in text or "refused" in text:
        return {"category": "connectivity"}
    elif "backup" in text or "archive" in text:
        return {"category": "backup"}
    return {"category": "unknown"}

def diagnose(state: AlertState) -> dict:
    queries = {
        "replication": "SELECT client_addr, state, replay_lag FROM pg_stat_replication;",
        "storage": "SELECT relname, n_dead_tup, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 5;",
        "performance": "SELECT pid, duration, query FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC LIMIT 10;",
        "connectivity": "SELECT count(*), state FROM pg_stat_activity GROUP BY state;",
        "backup": "SELECT * FROM pg_stat_archiver;",
    }
    query = queries.get(state["category"], "SELECT * FROM pg_stat_activity;")
    return {"diagnostic_query": query}

def recommend(state: AlertState) -> dict:
    actions = {
        "replication": "Check network latency. If lag > 60s, increase wal_keep_size. Verify standby I/O performance.",
        "storage": "Run VACUUM on bloated tables. Check autovacuum settings. Consider partitioning large tables.",
        "performance": "EXPLAIN ANALYZE the slow query. Check for missing indexes. Review pg_stat_statements.",
        "connectivity": "Check pgbouncer pool utilization. Kill idle_in_transaction sessions. Review app pool config.",
        "backup": "Check archive_command. Verify backup target disk space. Test pg_basebackup manually.",
    }
    rec = actions.get(state["category"], "Gather more context with pg_stat_activity.")
    return {"recommendation": rec}

# Build the graph
builder = StateGraph(AlertState)
builder.add_node("classify", classify)
builder.add_node("diagnose", diagnose)
builder.add_node("recommend", recommend)
builder.set_entry_point("classify")
builder.add_edge("classify", "diagnose")
builder.add_edge("diagnose", "recommend")
builder.add_edge("recommend", END)
graph = builder.compile()

# Test
print("Exercise 1: 3-Node Alert Processing Graph")
print("=" * 55)

test_alerts = [
    "Replication lag 60s on standby-2 and increasing",
    "Disk space at 94% on /pgdata - pg-analytics",
    "Slow queries detected - p99 latency over 10 seconds",
    "Connection refused from app server - pool exhausted",
    "WAL archive failing - last success 2 hours ago",
]

for alert in test_alerts:
    result = graph.invoke({
        "alert_text": alert,
        "category": "",
        "diagnostic_query": "",
        "recommendation": "",
    })
    print(f"\nAlert: {alert}")
    print(f"  Category:    {result['category']}")
    print(f"  Query:       {result['diagnostic_query'][:60]}...")
    print(f"  Action:      {result['recommendation'][:60]}...")

print(f"""
Check your work:
  [x] 3 nodes: classify, diagnose, recommend
  [x] Edges: classify -> diagnose -> recommend -> END
  [x] Each alert correctly categorized
  [x] Diagnostic query matches category
  [x] Recommendation is actionable
""")
PYEOF
```

---

## Exercise 2: Add checkpointing with SQLite

Take Exercise 1's graph and add SQLite checkpointing. Process multiple alerts on the same thread, then "restart" and verify state was preserved.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 2: SQLite Checkpointing
#
# Add persistent checkpointing to the alert processing graph.
# Process 3 alerts, "restart" the process, verify state survived.
#
# Requirements:
#   - Use SqliteSaver with /tmp/exercise2_checkpoints.db
#   - Process 3 alerts on thread "exercise-2-thread"
#   - After processing, verify checkpoint history
#   - Simulate a restart and recover the state
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
import operator
import os

DB_PATH = "/tmp/exercise2_checkpoints.db"
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

class AlertState(TypedDict):
    alert_text: str
    category: str
    recommendation: str
    alerts_processed: Annotated[list, operator.add]

def classify_and_recommend(state: AlertState) -> dict:
    text = state["alert_text"].lower()
    if "replication" in text or "lag" in text:
        category, rec = "replication", "Check pg_stat_replication"
    elif "disk" in text or "space" in text:
        category, rec = "storage", "Run VACUUM on bloated tables"
    elif "cpu" in text or "slow" in text:
        category, rec = "performance", "Find slow queries with pg_stat_statements"
    else:
        category, rec = "general", "Check pg_stat_activity"

    return {
        "category": category,
        "recommendation": rec,
        "alerts_processed": [f"{category}: {state['alert_text'][:40]}"],
    }

builder = StateGraph(AlertState)
builder.add_node("process", classify_and_recommend)
builder.set_entry_point("process")
builder.add_edge("process", END)

# Session 1: Process alerts
print("Exercise 2: SQLite Checkpointing")
print("=" * 55)

with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "exercise-2-thread"}}

    print("\nSession 1: Processing 3 alerts")
    print("-" * 45)
    for alert in [
        "Replication lag 30s on standby-1",
        "Disk usage 91% on /pgdata",
        "CPU spike - slow queries on pg-primary",
    ]:
        result = graph.invoke({
            "alert_text": alert,
            "category": "", "recommendation": "",
            "alerts_processed": [],
        }, config=config)
        print(f"  Processed: {alert[:45]}...")

    print(f"\n  Total alerts in history: {len(result['alerts_processed'])}")

    # Show checkpoint history
    states = list(graph.get_state_history(config))
    print(f"  Checkpoints saved: {len(states)}")

print(f"\nFile saved: {DB_PATH} ({os.path.getsize(DB_PATH)} bytes)")

# Session 2: Recover after "restart"
print(f"\nSession 2: Recovery after restart")
print("-" * 45)

with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
    config = {"configurable": {"thread_id": "exercise-2-thread"}}

    recovered = graph.get_state(config)
    alerts = recovered.values.get("alerts_processed", [])
    print(f"  Recovered {len(alerts)} alerts from checkpoint:")
    for a in alerts:
        print(f"    - {a}")

print(f"""
Check your work:
  [x] SqliteSaver persists to disk
  [x] 3 alerts processed on same thread
  [x] Alert history accumulated via reducer
  [x] State survived simulated restart
  [x] Checkpoint history available
""")

os.remove(DB_PATH)
PYEOF
```

---

## Exercise 3: Human-in-the-loop approval flow

Build a graph that detects a dangerous operation, proposes it, pauses for DBA approval, then executes.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 3: Human-in-the-Loop Approval
#
# Build a remediation graph that:
#   1. Detects the issue
#   2. Proposes a fix with risk assessment
#   3. PAUSES for DBA approval
#   4. Executes the approved fix
#   5. Verifies the result
#
# Test with:
#   - A dangerous operation (VACUUM FULL) -> must pause
#   - A safe operation (ANALYZE) -> can auto-execute
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class ApprovalState(TypedDict):
    alert: str
    proposed_action: str
    risk: str
    requires_approval: bool
    execution_result: str
    verification: str
    log: Annotated[list, operator.add]

def detect_and_propose(state: ApprovalState) -> dict:
    text = state["alert"].lower()

    if "bloat" in text or "dead tuples" in text:
        action = "VACUUM FULL public.orders;"
        risk = "HIGH"
    elif "statistics" in text or "stale" in text:
        action = "ANALYZE public.orders;"
        risk = "LOW"
    elif "blocking" in text or "locked" in text:
        action = "SELECT pg_terminate_backend(12345);"
        risk = "MEDIUM"
    else:
        action = "SELECT * FROM pg_stat_activity;"
        risk = "LOW"

    needs_approval = risk in ("MEDIUM", "HIGH")
    print(f"  [detect]  Action: {action}")
    print(f"            Risk: {risk}, Needs approval: {needs_approval}")
    return {
        "proposed_action": action,
        "risk": risk,
        "requires_approval": needs_approval,
        "log": [f"Proposed: {action} (risk={risk})"],
    }

def execute(state: ApprovalState) -> dict:
    action = state["proposed_action"]
    print(f"  [EXECUTE] {action}")
    return {
        "execution_result": f"Success: {action}",
        "log": [f"Executed: {action}"],
    }

def verify(state: ApprovalState) -> dict:
    print(f"  [verify]  Checking results...")
    return {
        "verification": "PASSED - operation completed successfully",
        "log": ["Verification: PASSED"],
    }

builder = StateGraph(ApprovalState)
builder.add_node("detect_and_propose", detect_and_propose)
builder.add_node("execute", execute)
builder.add_node("verify", verify)

builder.set_entry_point("detect_and_propose")
builder.add_edge("detect_and_propose", "execute")
builder.add_edge("execute", "verify")
builder.add_edge("verify", END)

checkpointer = MemorySaver()
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute"],
)

print("Exercise 3: Human-in-the-Loop Approval")
print("=" * 55)

# Scenario A: Dangerous operation - needs approval
print("\n--- Scenario A: VACUUM FULL (high risk) ---")
config_a = {"configurable": {"thread_id": "approval-dangerous"}}

graph.invoke({
    "alert": "Table orders: 5M dead tuples, 40% bloat",
    "proposed_action": "", "risk": "",
    "requires_approval": False, "execution_result": "",
    "verification": "", "log": [],
}, config=config_a)

state = graph.get_state(config_a)
print(f"\n  PAUSED at: {state.next}")
print(f"  Proposed: {state.values['proposed_action']}")
print(f"  Risk: {state.values['risk']}")

# DBA approves
print(f"  DBA says: APPROVED")
result = graph.invoke(None, config=config_a)
print(f"\n  Result: {result['execution_result']}")
print(f"  Verification: {result['verification']}")

# Scenario B: Safe operation - would normally auto-execute
# but our graph always interrupts (simplified demo)
print(f"\n--- Scenario B: ANALYZE (low risk) ---")
config_b = {"configurable": {"thread_id": "approval-safe"}}

graph.invoke({
    "alert": "Stale statistics on orders table",
    "proposed_action": "", "risk": "",
    "requires_approval": False, "execution_result": "",
    "verification": "", "log": [],
}, config=config_b)

state = graph.get_state(config_b)
print(f"\n  Risk: {state.values['risk']}")
print(f"  Note: Low risk - could auto-execute in production")
# Auto-approve for low risk
result = graph.invoke(None, config=config_b)
print(f"  Result: {result['execution_result']}")

# Show audit log
print(f"\n--- Audit Log (Scenario A) ---")
final = graph.get_state(config_a)
for entry in final.values.get("log", []):
    print(f"  {entry}")

print(f"""
Check your work:
  [x] Graph pauses before execute node
  [x] DBA can review proposed action and risk level
  [x] Graph resumes after approval
  [x] Verification step confirms success
  [x] Full audit log tracks every step
""")
PYEOF
```

---

## Exercise 4: Replication diagnostic subgraph

Create a subgraph that performs detailed replication diagnostics, then embed it in a parent alert processing graph.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 4: Replication Diagnostic Subgraph
#
# Build a subgraph with 4 diagnostic checks:
#   1. WAL sender status
#   2. Replication slot health
#   3. Network latency
#   4. Standby I/O performance
#
# Embed it in a parent graph that routes to this subgraph
# when the alert category is "replication".
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator

# ---- Subgraph: Replication Diagnostics ----

class ReplState(TypedDict):
    alert: str
    checks: Annotated[list, operator.add]
    root_cause: str

def check_wal_sender(state: ReplState) -> dict:
    result = "WAL sender: active, sent_lsn=0/5A000060, write_lsn=0/5A000060"
    print(f"    [wal_sender] {result}")
    return {"checks": [result]}

def check_repl_slots(state: ReplState) -> dict:
    result = "Replication slots: standby_2_slot active, 45MB retained WAL"
    print(f"    [repl_slots] {result}")
    return {"checks": [result]}

def check_network(state: ReplState) -> dict:
    result = "Network: primary->standby-2 latency 1.8ms, bandwidth 920Mbps"
    print(f"    [network]    {result}")
    return {"checks": [result]}

def check_standby_io(state: ReplState) -> dict:
    result = "Standby I/O: iowait 55%, disk utilization 92% - BOTTLENECK"
    print(f"    [standby_io] {result}")
    return {"checks": [result]}

def determine_root_cause(state: ReplState) -> dict:
    checks = state.get("checks", [])
    # Simple heuristic: look for BOTTLENECK
    if any("BOTTLENECK" in c for c in checks):
        cause = "Standby disk I/O bottleneck causing replay lag"
    elif any("latency" in c and "high" in c.lower() for c in checks):
        cause = "Network latency between primary and standby"
    else:
        cause = "No clear bottleneck found - monitor for trends"
    print(f"    [root_cause] {cause}")
    return {"root_cause": cause}

# Build subgraph
sub_builder = StateGraph(ReplState)
sub_builder.add_node("wal_sender", check_wal_sender)
sub_builder.add_node("repl_slots", check_repl_slots)
sub_builder.add_node("network", check_network)
sub_builder.add_node("standby_io", check_standby_io)
sub_builder.add_node("root_cause", determine_root_cause)

sub_builder.set_entry_point("wal_sender")
sub_builder.add_edge("wal_sender", "repl_slots")
sub_builder.add_edge("repl_slots", "network")
sub_builder.add_edge("network", "standby_io")
sub_builder.add_edge("standby_io", "root_cause")
sub_builder.add_edge("root_cause", END)

repl_subgraph = sub_builder.compile()

# ---- Parent Graph ----

class AlertState(TypedDict):
    alert: str
    category: str
    diagnosis: str
    recommendation: str

def classify(state: AlertState) -> dict:
    text = state["alert"].lower()
    if "replication" in text or "lag" in text:
        cat = "replication"
    elif "disk" in text:
        cat = "storage"
    else:
        cat = "general"
    print(f"  [classify] {cat}")
    return {"category": cat}

def diagnose_replication(state: AlertState) -> dict:
    print(f"  [diagnose] Running replication subgraph...")
    sub_result = repl_subgraph.invoke({
        "alert": state["alert"],
        "checks": [],
        "root_cause": "",
    })
    return {"diagnosis": sub_result["root_cause"]}

def diagnose_other(state: AlertState) -> dict:
    print(f"  [diagnose] Generic: check pg_stat_activity")
    return {"diagnosis": "Run generic diagnostic queries"}

def recommend(state: AlertState) -> dict:
    diag = state["diagnosis"]
    if "I/O bottleneck" in diag:
        rec = "Upgrade standby to NVMe storage. Short-term: reduce checkpoint_completion_target."
    elif "Network" in diag:
        rec = "Check network switches. Consider dedicated replication network."
    else:
        rec = "Monitor trends and investigate further."
    print(f"  [recommend] {rec[:60]}...")
    return {"recommendation": rec}

def route(state: AlertState) -> str:
    return "diagnose_replication" if state["category"] == "replication" else "diagnose_other"

parent_builder = StateGraph(AlertState)
parent_builder.add_node("classify", classify)
parent_builder.add_node("diagnose_replication", diagnose_replication)
parent_builder.add_node("diagnose_other", diagnose_other)
parent_builder.add_node("recommend", recommend)

parent_builder.set_entry_point("classify")
parent_builder.add_conditional_edges("classify", route, {
    "diagnose_replication": "diagnose_replication",
    "diagnose_other": "diagnose_other",
})
parent_builder.add_edge("diagnose_replication", "recommend")
parent_builder.add_edge("diagnose_other", "recommend")
parent_builder.add_edge("recommend", END)

parent_graph = parent_builder.compile()

print("Exercise 4: Replication Diagnostic Subgraph")
print("=" * 55)

# Test: replication alert routes to subgraph
print("\nTest 1: Replication alert (uses subgraph)")
print("-" * 45)
result = parent_graph.invoke({
    "alert": "Replication lag 45s on standby-2",
    "category": "", "diagnosis": "", "recommendation": "",
})
print(f"\n  Diagnosis:      {result['diagnosis']}")
print(f"  Recommendation: {result['recommendation'][:60]}...")

# Test: non-replication alert skips subgraph
print(f"\nTest 2: Storage alert (skips subgraph)")
print("-" * 45)
result = parent_graph.invoke({
    "alert": "Disk 92% on /pgdata",
    "category": "", "diagnosis": "", "recommendation": "",
})
print(f"\n  Diagnosis:      {result['diagnosis']}")
print(f"  Recommendation: {result['recommendation']}")

print(f"""
Check your work:
  [x] Subgraph has 5 nodes (4 checks + root cause)
  [x] Parent graph routes replication alerts to subgraph
  [x] Non-replication alerts skip the subgraph
  [x] Subgraph findings flow back to parent
  [x] Parent generates recommendation based on subgraph diagnosis
""")
PYEOF
```

---

## Exercise 5: Parallel diagnostics graph

Build a graph that runs connection, replication, and disk checks simultaneously, then merges results.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 5: Parallel Diagnostics
#
# Build a fan-out / fan-in graph:
#   triage -> [check_connections, check_replication, check_disk] -> merge -> report
#
# All 3 checks run in parallel.
# The merge node waits for all 3 and combines results.
# The report node generates a summary with severity.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator
import time

class ParallelState(TypedDict):
    alert: str
    findings: Annotated[list, operator.add]
    severity: str
    report: str

def triage(state: ParallelState) -> dict:
    print(f"  [triage] Starting parallel diagnostics...")
    return {"findings": ["triage: alert acknowledged"]}

def check_connections(state: ParallelState) -> dict:
    time.sleep(0.05)
    result = "Connections: 420/500 active (84%)"
    status = "WARNING" if 420 > 400 else "OK"
    print(f"  [connections] {result} [{status}]")
    return {"findings": [f"connections:{status}:{result}"]}

def check_replication(state: ParallelState) -> dict:
    time.sleep(0.05)
    result = "Replication: lag 8s on standby-1, 45s on standby-2"
    status = "WARNING"
    print(f"  [replication] {result} [{status}]")
    return {"findings": [f"replication:{status}:{result}"]}

def check_disk(state: ParallelState) -> dict:
    time.sleep(0.05)
    result = "Disk: /pgdata 72%, /wal 45%, /backup 88%"
    status = "OK"
    print(f"  [disk] {result} [{status}]")
    return {"findings": [f"disk:{status}:{result}"]}

def merge_findings(state: ParallelState) -> dict:
    findings = state.get("findings", [])
    statuses = []
    for f in findings:
        if ":" in f:
            parts = f.split(":", 2)
            if len(parts) >= 2:
                statuses.append(parts[1])

    if "CRITICAL" in statuses:
        severity = "P1"
    elif "WARNING" in statuses:
        severity = "P2"
    else:
        severity = "P4"

    print(f"  [merge] {len(findings)} findings -> severity {severity}")
    return {"severity": severity}

def generate_report(state: ParallelState) -> dict:
    findings = state.get("findings", [])
    severity = state["severity"]

    report_lines = [f"Health Report - Severity: {severity}"]
    report_lines.append(f"Checks completed: {len(findings)}")
    for f in findings:
        if ":" in f:
            parts = f.split(":", 2)
            if len(parts) == 3:
                check, status, detail = parts
                report_lines.append(f"  [{status:8s}] {check}: {detail}")

    report = "\n".join(report_lines)
    print(f"  [report] Generated")
    return {"report": report}

builder = StateGraph(ParallelState)
builder.add_node("triage", triage)
builder.add_node("check_connections", check_connections)
builder.add_node("check_replication", check_replication)
builder.add_node("check_disk", check_disk)
builder.add_node("merge", merge_findings)
builder.add_node("report", generate_report)

builder.set_entry_point("triage")

# Fan out: triage -> 3 parallel checks
builder.add_edge("triage", "check_connections")
builder.add_edge("triage", "check_replication")
builder.add_edge("triage", "check_disk")

# Fan in: all checks -> merge
builder.add_edge("check_connections", "merge")
builder.add_edge("check_replication", "merge")
builder.add_edge("check_disk", "merge")

builder.add_edge("merge", "report")
builder.add_edge("report", END)

graph = builder.compile()

print("Exercise 5: Parallel Diagnostics Graph")
print("=" * 55)

start = time.time()
result = graph.invoke({
    "alert": "General health check on pg-primary cluster",
    "findings": [],
    "severity": "",
    "report": "",
})
elapsed = time.time() - start

print(f"\n{result['report']}")
print(f"\nTotal time: {elapsed:.2f}s")

# Visualize
print(f"\nGraph structure:")
print(graph.get_graph().draw_mermaid())

print(f"""
Check your work:
  [x] 3 checks run in parallel (fan-out)
  [x] Merge node waits for all 3 (fan-in)
  [x] Severity calculated from combined findings
  [x] Report includes all check results
  [x] Mermaid diagram shows parallel structure
""")
PYEOF
```

---

## Summary

| Exercise | Pattern | Key Concept |
|----------|---------|-------------|
| 1 | Sequential graph | Nodes, edges, state flow |
| 2 | Checkpointing | SqliteSaver, thread persistence |
| 3 | Human-in-the-loop | interrupt_before, update_state |
| 4 | Subgraphs | Modular diagnostic workflows |
| 5 | Parallel execution | Fan-out/fan-in, reducers |

All 5 exercises use DBA-relevant scenarios: alert classification, diagnostic queries, remediation approval, replication diagnosis, and fleet health checks.
