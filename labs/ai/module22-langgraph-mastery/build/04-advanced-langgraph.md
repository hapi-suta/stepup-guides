# Build 04: Advanced LangGraph Patterns

Subgraphs, parallel execution, map-reduce, streaming, dynamic graphs, and error handling. Build a production DBA monitoring pipeline.

---

## Step 1. Subgraphs - graphs within graphs

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# SUBGRAPHS: GRAPHS WITHIN GRAPHS
#
# DBA analogy: Stored procedures that call other stored procedures.
#   - diagnose_replication() calls check_wal_sender(),
#     check_network_latency(), and check_standby_io()
#   - Each sub-procedure is its own unit with its own logic
#   - The parent procedure orchestrates them
#
# In LangGraph:
#   - A subgraph is a compiled graph used as a node
#   - The parent graph calls the subgraph
#   - The subgraph has its own nodes, edges, and state
#   - Clean separation of concerns
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator

# ---------- SUBGRAPH: Replication Diagnostics ----------

class ReplDiagState(TypedDict):
    alert: str
    wal_status: str
    network_status: str
    standby_status: str
    repl_diagnosis: str

def check_wal_sender(state: ReplDiagState) -> dict:
    status = "WAL sender active, sent_lsn ahead of replay_lsn by 45MB"
    print(f"    [sub:wal]     {status}")
    return {"wal_status": status}

def check_network(state: ReplDiagState) -> dict:
    status = "Network latency 2.3ms (normal), bandwidth 850Mbps (ok)"
    print(f"    [sub:network] {status}")
    return {"network_status": status}

def check_standby(state: ReplDiagState) -> dict:
    status = "Standby I/O wait at 45% - disk bottleneck on standby"
    print(f"    [sub:standby] {status}")
    return {"standby_status": status}

def summarize_repl(state: ReplDiagState) -> dict:
    diagnosis = (
        f"WAL: {state['wal_status'][:30]}... | "
        f"Network: OK | "
        f"Standby: I/O bottleneck detected"
    )
    print(f"    [sub:summary] {diagnosis[:60]}...")
    return {"repl_diagnosis": diagnosis}

# Build the subgraph
repl_builder = StateGraph(ReplDiagState)
repl_builder.add_node("check_wal", check_wal_sender)
repl_builder.add_node("check_network", check_network)
repl_builder.add_node("check_standby", check_standby)
repl_builder.add_node("summarize", summarize_repl)

repl_builder.set_entry_point("check_wal")
repl_builder.add_edge("check_wal", "check_network")
repl_builder.add_edge("check_network", "check_standby")
repl_builder.add_edge("check_standby", "summarize")
repl_builder.add_edge("summarize", END)

repl_subgraph = repl_builder.compile()

# ---------- PARENT GRAPH ----------

class ParentState(TypedDict):
    alert: str
    category: str
    diagnosis: str
    recommendation: str

def classify(state: ParentState) -> dict:
    text = state["alert"].lower()
    if "replication" in text or "lag" in text:
        cat = "replication"
    elif "disk" in text:
        cat = "storage"
    else:
        cat = "general"
    print(f"  [classify] {cat}")
    return {"category": cat}

def diagnose_replication(state: ParentState) -> dict:
    """Call the replication subgraph."""
    print(f"  [diagnose] Running replication subgraph...")
    # Run the subgraph with its own state
    sub_result = repl_subgraph.invoke({
        "alert": state["alert"],
        "wal_status": "", "network_status": "",
        "standby_status": "", "repl_diagnosis": "",
    })
    return {"diagnosis": sub_result["repl_diagnosis"]}

def diagnose_general(state: ParentState) -> dict:
    print(f"  [diagnose] General: check pg_stat_activity")
    return {"diagnosis": "General issue - check pg_stat_activity and system metrics"}

def recommend(state: ParentState) -> dict:
    diag = state["diagnosis"]
    if "I/O bottleneck" in diag:
        rec = "Upgrade standby disk to SSD or NVMe. Short-term: reduce checkpoint_completion_target."
    else:
        rec = "Investigate further with diagnostic queries."
    print(f"  [recommend] {rec[:60]}...")
    return {"recommendation": rec}

def route_diagnosis(state: ParentState) -> str:
    if state["category"] == "replication":
        return "diagnose_replication"
    return "diagnose_general"

parent_builder = StateGraph(ParentState)
parent_builder.add_node("classify", classify)
parent_builder.add_node("diagnose_replication", diagnose_replication)
parent_builder.add_node("diagnose_general", diagnose_general)
parent_builder.add_node("recommend", recommend)

parent_builder.set_entry_point("classify")
parent_builder.add_conditional_edges("classify", route_diagnosis, {
    "diagnose_replication": "diagnose_replication",
    "diagnose_general": "diagnose_general",
})
parent_builder.add_edge("diagnose_replication", "recommend")
parent_builder.add_edge("diagnose_general", "recommend")
parent_builder.add_edge("recommend", END)

parent_graph = parent_builder.compile()

print("Subgraphs - Replication Diagnostic Subgraph")
print("=" * 55)

result = parent_graph.invoke({
    "alert": "Replication lag 45s on standby-2",
    "category": "", "diagnosis": "", "recommendation": "",
})

print(f"\nFinal result:")
print(f"  Category:       {result['category']}")
print(f"  Diagnosis:      {result['diagnosis'][:70]}...")
print(f"  Recommendation: {result['recommendation'][:70]}...")

print(f"""
The parent graph called the replication subgraph.
The subgraph ran 4 nodes internally.
The parent only saw the final diagnosis.

DBA parallel: diagnose_replication() is a stored procedure
that internally calls check_wal_sender(), check_network(),
and check_standby(). The caller doesn't need to know
the internal steps - just the result.

Benefits:
  - Reuse: the replication subgraph can be used in multiple parents
  - Test: test the subgraph independently
  - Maintain: change subgraph internals without touching the parent
""")
PYEOF
```

Expected output (yours will differ):

```
Subgraphs - Replication Diagnostic Subgraph
=======================================================
  [classify] replication
  [diagnose] Running replication subgraph...
    [sub:wal]     WAL sender active, sent_lsn ahead of replay_lsn by 45MB
    [sub:network] Network latency 2.3ms (normal), bandwidth 850Mbps (ok)
    [sub:standby] Standby I/O wait at 45% - disk bottleneck on standby
    [sub:summary] WAL: WAL sender active, sent_lsn a... ...
  [recommend] Upgrade standby disk to SSD or NVMe. Short-term: reduce ...
```

---

## Step 2. Parallel node execution

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# PARALLEL NODE EXECUTION
#
# Run multiple diagnostic checks at the same time.
# Don't wait for check_connections to finish before
# starting check_replication.
#
# DBA analogy: When diagnosing a sick database, you don't:
#   1. Check connections (wait 5s)
#   2. Then check replication (wait 5s)
#   3. Then check disk (wait 5s)
#   Total: 15 seconds
#
# You open 3 terminal tabs and run them all at once.
#   All 3 checks run simultaneously.
#   Total: 5 seconds (longest check).
#
# In LangGraph, you can fan out to parallel nodes
# by adding multiple edges from one source node.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator
import time

class DiagState(TypedDict):
    alert: str
    findings: Annotated[list, operator.add]
    summary: str

def triage(state: DiagState) -> dict:
    print(f"  [triage] Alert received, starting parallel checks...")
    return {"findings": ["Triage: alert acknowledged"]}

def check_connections(state: DiagState) -> dict:
    # Simulate work
    start = time.time()
    time.sleep(0.1)  # Simulates a 100ms query
    elapsed = time.time() - start
    finding = f"Connections: 380/500 active ({elapsed:.1f}s)"
    print(f"  [connections] {finding}")
    return {"findings": [finding]}

def check_replication(state: DiagState) -> dict:
    start = time.time()
    time.sleep(0.1)
    elapsed = time.time() - start
    finding = f"Replication: lag 12s on standby-2 ({elapsed:.1f}s)"
    print(f"  [replication] {finding}")
    return {"findings": [finding]}

def check_disk(state: DiagState) -> dict:
    start = time.time()
    time.sleep(0.1)
    elapsed = time.time() - start
    finding = f"Disk: /pgdata at 87% ({elapsed:.1f}s)"
    print(f"  [disk] {finding}")
    return {"findings": [finding]}

def merge_findings(state: DiagState) -> dict:
    count = len(state["findings"])
    summary = f"Completed {count} checks. " + " | ".join(state["findings"][-3:])
    print(f"  [merge] {count} findings merged")
    return {"summary": summary}

builder = StateGraph(DiagState)
builder.add_node("triage", triage)
builder.add_node("check_connections", check_connections)
builder.add_node("check_replication", check_replication)
builder.add_node("check_disk", check_disk)
builder.add_node("merge", merge_findings)

builder.set_entry_point("triage")

# Fan out: triage -> 3 parallel checks
# Each edge from triage goes to a different check node
builder.add_edge("triage", "check_connections")
builder.add_edge("triage", "check_replication")
builder.add_edge("triage", "check_disk")

# Fan in: all 3 checks -> merge
builder.add_edge("check_connections", "merge")
builder.add_edge("check_replication", "merge")
builder.add_edge("check_disk", "merge")
builder.add_edge("merge", END)

graph = builder.compile()

print("Parallel Node Execution")
print("=" * 55)

start = time.time()
result = graph.invoke({
    "alert": "General health check on pg-primary",
    "findings": [],
    "summary": "",
})
elapsed = time.time() - start

print(f"\n  Findings: {len(result['findings'])}")
for f in result["findings"]:
    print(f"    - {f}")
print(f"\n  Total time: {elapsed:.2f}s")
print(f"  (Sequential would be ~0.3s+. Parallel can overlap.)")

print(f"""
Fan-out / fan-in pattern:
  triage -> [connections, replication, disk] -> merge

All 3 checks can run concurrently.
The merge node waits for ALL checks to complete.
Findings are accumulated via the 'add' reducer.

DBA parallel: running 3 psql sessions in parallel tabs
vs running 3 queries one at a time in a single session.
""")
PYEOF
```

Expected output (yours will differ):

```
Parallel Node Execution
=======================================================
  [triage] Alert received, starting parallel checks...
  [connections] Connections: 380/500 active (0.1s)
  [replication] Replication: lag 12s on standby-2 (0.1s)
  [disk] Disk: /pgdata at 87% (0.1s)
  [merge] 4 findings merged
```

---

## Step 3. Map-reduce pattern

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# MAP-REDUCE PATTERN
#
# Check 10 databases in parallel, merge results.
#
# DBA analogy: You manage 10 databases.
#   MAP:    Run the same health check on all 10
#   REDUCE: Merge results into a single report
#
# SQL analogy:
#   MAP    = SELECT health_check(db) FROM databases
#   REDUCE = GROUP BY status, COUNT(*)
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator

class MapReduceState(TypedDict):
    databases: list
    results: Annotated[list, operator.add]
    summary: str

def distribute_checks(state: MapReduceState) -> dict:
    """Map phase: check each database."""
    results = []
    for db in state["databases"]:
        # Simulate health check per database
        import random
        random.seed(sum(ord(c) for c in db))
        cpu = random.randint(10, 99)
        conns = random.randint(10, 500)
        disk = random.randint(40, 98)
        lag = random.randint(0, 120) if "standby" in db else 0

        status = "HEALTHY"
        issues = []
        if cpu > 90:
            status = "WARNING"
            issues.append(f"CPU {cpu}%")
        if disk > 90:
            status = "CRITICAL"
            issues.append(f"Disk {disk}%")
        if lag > 60:
            status = "WARNING"
            issues.append(f"Lag {lag}s")
        if conns > 450:
            status = "WARNING"
            issues.append(f"Conns {conns}/500")

        result = {
            "database": db,
            "status": status,
            "cpu": cpu,
            "connections": conns,
            "disk": disk,
            "replication_lag": lag,
            "issues": issues,
        }
        results.append(result)
        icon = "X" if status == "CRITICAL" else ("!" if status == "WARNING" else " ")
        print(f"  [{icon}] {db:30s} {status:10s} CPU={cpu}% Disk={disk}% Conns={conns}")

    return {"results": results}

def reduce_results(state: MapReduceState) -> dict:
    """Reduce phase: merge into summary."""
    results = state["results"]
    total = len(results)
    critical = sum(1 for r in results if r["status"] == "CRITICAL")
    warning = sum(1 for r in results if r["status"] == "WARNING")
    healthy = sum(1 for r in results if r["status"] == "HEALTHY")

    # Find worst offenders
    worst = [r for r in results if r["status"] in ("CRITICAL", "WARNING")]
    worst_summary = "; ".join(
        f"{r['database']}: {', '.join(r['issues'])}"
        for r in worst
    )

    summary = (
        f"Fleet health: {total} databases checked. "
        f"{critical} critical, {warning} warning, {healthy} healthy. "
        f"Issues: {worst_summary if worst_summary else 'none'}"
    )
    print(f"\n  [reduce] {summary[:80]}...")
    return {"summary": summary}

builder = StateGraph(MapReduceState)
builder.add_node("map_checks", distribute_checks)
builder.add_node("reduce_results", reduce_results)
builder.set_entry_point("map_checks")
builder.add_edge("map_checks", "reduce_results")
builder.add_edge("reduce_results", END)

graph = builder.compile()

print("Map-Reduce: Fleet Health Check")
print("=" * 55)

databases = [
    "pg-primary-us-east",
    "pg-standby-us-east-1",
    "pg-standby-us-east-2",
    "pg-primary-us-west",
    "pg-standby-us-west-1",
    "pg-analytics-us-east",
    "pg-reporting-eu-west",
    "pg-staging",
    "pg-dev",
    "pg-ci-test",
]

result = graph.invoke({
    "databases": databases,
    "results": [],
    "summary": "",
})

print(f"\nFleet Summary:")
print(f"  {result['summary']}")

print(f"""
Map-Reduce for database fleet management:
  MAP:    Run the same check on every database
  REDUCE: Aggregate into a single fleet report

This scales to hundreds of databases.
In production, the MAP phase would make real
psql connections to each database in parallel.
""")
PYEOF
```

Note: Exact health check numbers depend on your Python version since the random number generator may produce different sequences. The structure and format will match, but specific CPU/Disk/Connection values and status counts may vary.

Expected output (yours will differ):

```
Map-Reduce: Fleet Health Check
=======================================================
  [ ] pg-primary-us-east                HEALTHY    CPU=...% Disk=...% Conns=...
  ...
  (10 database entries with HEALTHY, WARNING, or CRITICAL status)

Fleet Summary:
  Fleet health: 10 databases checked. X critical, Y warning, Z healthy. ...
```

---

## Step 4. Streaming agent output

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# STREAMING
#
# Instead of waiting for the entire graph to finish,
# stream results as each node completes.
#
# DBA analogy: tail -f vs cat.
#   cat pg_log/postgresql.log       -> wait for file to be read
#   tail -f pg_log/postgresql.log   -> see lines as they appear
#
# Streaming lets the DBA see:
#   "Classifying... done. Diagnosing... done. Recommending..."
# Instead of waiting 30 seconds and seeing everything at once.
# ============================================================

from typing import TypedDict
from langgraph.graph import StateGraph, END
import time

class StreamState(TypedDict):
    alert: str
    stage: str
    result: str

def classify(state: StreamState) -> dict:
    time.sleep(0.2)  # Simulate work
    return {"stage": "classified", "result": "category=replication"}

def diagnose(state: StreamState) -> dict:
    time.sleep(0.3)
    return {"stage": "diagnosed", "result": "lag caused by I/O on standby"}

def recommend(state: StreamState) -> dict:
    time.sleep(0.2)
    return {"stage": "recommended", "result": "upgrade standby disk to NVMe"}

builder = StateGraph(StreamState)
builder.add_node("classify", classify)
builder.add_node("diagnose", diagnose)
builder.add_node("recommend", recommend)
builder.set_entry_point("classify")
builder.add_edge("classify", "diagnose")
builder.add_edge("diagnose", "recommend")
builder.add_edge("recommend", END)
graph = builder.compile()

print("Streaming Agent Output")
print("=" * 55)

print("\nMethod 1: stream() - get updates after each node")
print("-" * 45)

start = time.time()
for event in graph.stream({
    "alert": "Replication lag on standby-2",
    "stage": "",
    "result": "",
}):
    elapsed = time.time() - start
    # event is a dict with the node name as key
    for node_name, node_output in event.items():
        stage = node_output.get("stage", "")
        result = node_output.get("result", "")
        print(f"  [{elapsed:.1f}s] Node '{node_name}' -> stage={stage}, result={result}")

print(f"\nMethod 2: stream(stream_mode='values') - get full state")
print("-" * 45)

start = time.time()
for state_snapshot in graph.stream(
    {"alert": "Disk 95% on pg-analytics", "stage": "", "result": ""},
    stream_mode="values",
):
    elapsed = time.time() - start
    print(f"  [{elapsed:.1f}s] stage={state_snapshot.get('stage', 'init'):15s} result={state_snapshot.get('result', 'pending')}")

print(f"""
Two stream modes:
  stream()                    -> node-level updates (what changed)
  stream(stream_mode='values') -> full state snapshots

For a DBA dashboard, stream_mode='values' is ideal.
You can show a real-time status bar:
  [Classifying...] -> [Diagnosing...] -> [Recommending...] -> [Done]

DBA parallel: this is tail -f for your agent's thought process.
""")
PYEOF
```

Expected output (yours will differ):

```
Streaming Agent Output
=======================================================

Method 1: stream() - get updates after each node
---------------------------------------------
  [0.2s] Node 'classify' -> stage=classified, result=category=replication
  [0.5s] Node 'diagnose' -> stage=diagnosed, result=lag caused by I/O on standby
  [0.7s] Node 'recommend' -> stage=recommended, result=upgrade standby disk to NVMe
```

---

## Step 5. Error handling - retry and fallback

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ERROR HANDLING: RETRY AND FALLBACK
#
# Nodes can fail. LangGraph needs to handle this gracefully.
#
# DBA analogy: your monitoring script retries on timeout.
#   - psql times out on check 1: retry 3 times
#   - If all retries fail: use cached data (fallback)
#   - Never crash the entire pipeline for one failed check
#
# Patterns:
#   1. Retry: try the node again (transient errors)
#   2. Fallback: use a safe default (persistent errors)
#   3. Skip: mark as failed, continue the pipeline
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator
import random

class RobustState(TypedDict):
    alert: str
    findings: Annotated[list, operator.add]
    errors: Annotated[list, operator.add]
    summary: str

# Simulate flaky checks
attempt_counter: dict = {}

def check_with_retry(name: str, success_rate: float, result_on_success: str):
    """Create a check function with retry logic built in."""
    def check_fn(state: RobustState) -> dict:
        max_retries = 3
        attempt_counter.setdefault(name, 0)

        for attempt in range(1, max_retries + 1):
            attempt_counter[name] += 1
            # Simulate random failures
            if random.random() < success_rate or attempt == max_retries:
                if attempt > 1:
                    print(f"  [{name}] Succeeded on attempt {attempt}")
                else:
                    print(f"  [{name}] {result_on_success}")
                return {"findings": [f"{name}: {result_on_success}"]}
            else:
                print(f"  [{name}] Attempt {attempt} failed - retrying...")

        # All retries exhausted - fallback
        fallback = f"{name}: UNAVAILABLE (used cached data)"
        print(f"  [{name}] All retries failed - using fallback")
        return {
            "findings": [fallback],
            "errors": [f"{name} failed after {max_retries} attempts"],
        }
    return check_fn

def safe_check(name: str, check_func):
    """Wrap a check in try/except for unexpected errors."""
    def wrapper(state: RobustState) -> dict:
        try:
            return check_func(state)
        except Exception as e:
            error_msg = f"{name}: ERROR - {str(e)}"
            print(f"  [{name}] Unexpected error: {e}")
            return {
                "findings": [f"{name}: FAILED (skipped)"],
                "errors": [error_msg],
            }
    return wrapper

def summarize(state: RobustState) -> dict:
    findings = state.get("findings", [])
    errors = state.get("errors", [])

    summary_parts = [f"{len(findings)} checks completed"]
    if errors:
        summary_parts.append(f"{len(errors)} errors")
    summary = ". ".join(summary_parts)

    print(f"\n  [summary] {summary}")
    return {"summary": summary}

# Set seed for reproducibility
random.seed(42)

builder = StateGraph(RobustState)

builder.add_node("check_cpu", safe_check("cpu",
    check_with_retry("cpu", 0.9, "CPU 65% (normal)")))
builder.add_node("check_disk", safe_check("disk",
    check_with_retry("disk", 0.5, "Disk 87% (warning)")))
builder.add_node("check_repl", safe_check("repl",
    check_with_retry("repl", 0.8, "Replication lag 3s (ok)")))
builder.add_node("summarize", summarize)

builder.set_entry_point("check_cpu")
builder.add_edge("check_cpu", "check_disk")
builder.add_edge("check_disk", "check_repl")
builder.add_edge("check_repl", "summarize")
builder.add_edge("summarize", END)

graph = builder.compile()

print("Error Handling - Retry and Fallback")
print("=" * 55)

result = graph.invoke({
    "alert": "Routine health check",
    "findings": [],
    "errors": [],
    "summary": "",
})

print(f"\nFindings:")
for f in result["findings"]:
    print(f"  - {f}")

if result.get("errors"):
    print(f"\nErrors:")
    for e in result["errors"]:
        print(f"  - {e}")

print(f"\nSummary: {result['summary']}")

print(f"""
Error handling strategy:
  1. RETRY:    Transient failures get 3 attempts
  2. FALLBACK: Use cached/default data after retries exhaust
  3. WRAP:     try/except catches unexpected errors
  4. CONTINUE: Pipeline continues even if one check fails

DBA parallel: your monitoring doesn't crash because
one of 10 database checks timed out. It logs the error,
uses cached data, and continues checking the other 9.

Never let one bad node take down the whole pipeline.
""")
PYEOF
```

Note: Exact retry behavior depends on your Python version since `random.seed(42)` produces different sequences on Python 3.13 vs older versions. The pattern will be the same - some checks succeed immediately, others may retry - but which checks retry may differ.

Expected output (yours will differ):

```
Error Handling - Retry and Fallback
=======================================================
  [cpu] CPU 65% (normal)
  [disk] ...
  [repl] ...

  [summary] 3 checks completed
```

---

## Step 6. Production DBA monitoring pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# PRODUCTION DBA MONITORING PIPELINE
#
# The complete system:
#   1. Receive alerts from multiple sources
#   2. Classify in parallel
#   3. Route to specialist subgraphs
#   4. Run diagnostics concurrently
#   5. Merge findings
#   6. Propose remediation with risk level
#   7. Execute after approval (simulated)
#
# This is the culmination of everything in this module.
# ============================================================

from typing import TypedDict, Annotated, List
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator
from datetime import datetime

class PipelineState(TypedDict):
    # Input
    alert_text: str
    alert_source: str
    metrics: dict
    timestamp: str

    # Classification
    category: str
    severity: str
    confidence: float

    # Diagnostics
    diagnostic_findings: Annotated[list, operator.add]

    # Remediation
    proposed_actions: list
    risk_level: str
    requires_approval: bool

    # Execution
    execution_status: str

    # Audit
    audit_log: Annotated[list, operator.add]

def ingest_alert(state: PipelineState) -> dict:
    """Step 1: Ingest and normalize the alert."""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"  [1. ingest] Alert from {state['alert_source']} at {ts}")
    return {
        "timestamp": ts,
        "audit_log": [f"[{ts}] Alert ingested from {state['alert_source']}"],
    }

def classify_alert(state: PipelineState) -> dict:
    """Step 2: Classify the alert."""
    text = state["alert_text"].lower()
    metrics = state.get("metrics", {})

    # Keyword-based classification
    categories = {
        "replication": ["replication", "lag", "standby", "wal", "streaming"],
        "storage": ["disk", "storage", "space", "full", "bloat"],
        "performance": ["cpu", "slow", "timeout", "latency", "query"],
        "connectivity": ["connection", "refused", "pool", "max_connections"],
        "backup": ["backup", "archive", "pitr", "restore"],
    }

    scores = {}
    for cat, keywords in categories.items():
        scores[cat] = sum(1 for kw in keywords if kw in text)

    best_cat = max(scores, key=scores.get)
    best_score = scores[best_cat]
    confidence = min(1.0, best_score / 3.0) if best_score > 0 else 0.1

    # Severity from metrics
    cpu = metrics.get("cpu_percent", 0)
    disk = metrics.get("disk_percent", 0)
    lag = metrics.get("replication_lag_seconds", 0)

    if cpu > 95 or disk > 95 or lag > 300 or "down" in text or "crash" in text:
        severity = "P1"
    elif cpu > 80 or disk > 85 or lag > 60:
        severity = "P2"
    elif any(kw in text for kw in ["high", "increasing"]):
        severity = "P3"
    else:
        severity = "P4"

    print(f"  [2. classify] {best_cat} ({severity}, confidence={confidence:.1f})")
    return {
        "category": best_cat,
        "severity": severity,
        "confidence": confidence,
        "audit_log": [f"Classified: {best_cat} {severity} (conf={confidence:.1f})"],
    }

def run_diagnostics(state: PipelineState) -> dict:
    """Step 3: Run diagnostic checks based on category."""
    cat = state["category"]

    diagnostic_map = {
        "replication": [
            "pg_stat_replication: 2 standbys active, replay_lag 45s on standby-2",
            "pg_stat_wal_receiver: standby-2 last_msg 50s ago",
            "Network: latency primary<->standby-2 = 2.1ms (normal)",
            "Standby-2 I/O: iowait 42%, disk util 89% (bottleneck)",
        ],
        "storage": [
            "pg_stat_user_tables: orders has 5.2M dead tuples",
            "Database size: 450GB, table orders: 120GB (45GB bloat)",
            "Disk usage: /pgdata 92%, /wal 67%",
            "Autovacuum: last vacuum on orders was 3 days ago",
        ],
        "performance": [
            "pg_stat_activity: 3 queries running > 60s",
            "pg_stat_statements: top query avg 12s (was 0.5s last week)",
            "CPU usage: 89% user, 8% iowait",
            "pg_locks: 2 blocked sessions waiting on AccessExclusiveLock",
        ],
        "connectivity": [
            "pg_stat_activity: 490/500 connections used",
            "Connection breakdown: 300 idle, 150 idle_in_transaction, 40 active",
            "pgbouncer: pool exhausted, 25 clients in queue",
        ],
        "backup": [
            "pg_stat_archiver: last_archived_wal 2 hours ago",
            "archive_command: last failure 90 minutes ago",
            "Backup target: /backup at 95% disk usage",
        ],
    }

    findings = diagnostic_map.get(cat, ["No specific diagnostics for this category"])
    for f in findings:
        print(f"  [3. diag] {f[:65]}...")

    return {
        "diagnostic_findings": findings,
        "audit_log": [f"Diagnostics: {len(findings)} checks completed"],
    }

def propose_remediation(state: PipelineState) -> dict:
    """Step 4: Propose remediation actions with risk assessment."""
    cat = state["category"]
    severity = state["severity"]

    remediation_map = {
        "replication": {
            "actions": [
                "Verify standby-2 disk I/O with iostat",
                "Consider migrating standby-2 to faster storage",
                "Short-term: increase wal_keep_size to 4GB",
                "Monitor: set alert for lag > 30s",
            ],
            "risk": "LOW" if severity != "P1" else "MEDIUM",
        },
        "storage": {
            "actions": [
                "VACUUM orders (regular, no lock)",
                "If insufficient: VACUUM FULL orders (ACCESS EXCLUSIVE lock)",
                "Tune autovacuum: autovacuum_vacuum_scale_factor = 0.05",
                "Long-term: partition the orders table by date",
            ],
            "risk": "MEDIUM",
        },
        "performance": {
            "actions": [
                "EXPLAIN ANALYZE the top slow query",
                "Add missing index if full table scan detected",
                "pg_terminate_backend for 60min+ blocking queries",
                "Set statement_timeout = '5min' for ad-hoc sessions",
            ],
            "risk": "HIGH" if "terminate" in str(state.get("diagnostic_findings", [])) else "MEDIUM",
        },
        "connectivity": {
            "actions": [
                "Kill idle_in_transaction sessions > 30 min old",
                "Increase pgbouncer default_pool_size",
                "Review application connection pool settings",
                "Set idle_in_transaction_session_timeout = '10min'",
            ],
            "risk": "MEDIUM",
        },
        "backup": {
            "actions": [
                "Check archive_command for errors",
                "Free space on backup target",
                "Manually trigger pg_basebackup test",
                "Set up WAL archiving monitoring alert",
            ],
            "risk": "LOW",
        },
    }

    remed = remediation_map.get(cat, {"actions": ["Manual investigation"], "risk": "UNKNOWN"})
    requires_approval = remed["risk"] in ("MEDIUM", "HIGH")

    print(f"  [4. propose] {len(remed['actions'])} actions, risk={remed['risk']}")
    for i, action in enumerate(remed["actions"], 1):
        print(f"     {i}. {action}")

    return {
        "proposed_actions": remed["actions"],
        "risk_level": remed["risk"],
        "requires_approval": requires_approval,
        "audit_log": [f"Proposed {len(remed['actions'])} actions, risk={remed['risk']}"],
    }

def execute_or_wait(state: PipelineState) -> dict:
    """Step 5: Execute (if auto-approved) or wait for DBA."""
    if state["requires_approval"]:
        status = f"AWAITING_APPROVAL (risk={state['risk_level']})"
        print(f"  [5. execute] {status}")
        print(f"               DBA must approve before execution")
    else:
        status = "AUTO_EXECUTED (low risk actions)"
        print(f"  [5. execute] {status}")

    return {
        "execution_status": status,
        "audit_log": [f"Status: {status}"],
    }

# Build the pipeline
builder = StateGraph(PipelineState)
builder.add_node("ingest", ingest_alert)
builder.add_node("classify", classify_alert)
builder.add_node("diagnose", run_diagnostics)
builder.add_node("propose", propose_remediation)
builder.add_node("execute", execute_or_wait)

builder.set_entry_point("ingest")
builder.add_edge("ingest", "classify")
builder.add_edge("classify", "diagnose")
builder.add_edge("diagnose", "propose")
builder.add_edge("propose", "execute")
builder.add_edge("execute", END)

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer)

# Visualize
print("Production DBA Monitoring Pipeline")
print("=" * 55)
print("\nGraph structure:")
print(graph.get_graph().draw_mermaid())
print()

# Test with multiple alert scenarios
test_alerts = [
    {
        "alert_text": "Replication lag 45s on standby-2 and increasing",
        "alert_source": "prometheus",
        "metrics": {"cpu_percent": 45, "disk_percent": 70, "replication_lag_seconds": 45},
    },
    {
        "alert_text": "Disk usage critical on pg-analytics /pgdata at 95%",
        "alert_source": "datadog",
        "metrics": {"cpu_percent": 30, "disk_percent": 95, "replication_lag_seconds": 1},
    },
    {
        "alert_text": "CPU spike 92% - slow queries detected on pg-primary",
        "alert_source": "pagerduty",
        "metrics": {"cpu_percent": 92, "disk_percent": 60, "replication_lag_seconds": 2},
    },
]

for i, alert in enumerate(test_alerts, 1):
    config = {"configurable": {"thread_id": f"pipeline-{i:03d}"}}
    print(f"\n{'='*55}")
    print(f"Alert {i}: {alert['alert_text'][:50]}...")
    print(f"Source: {alert['alert_source']}")
    print(f"Metrics: {alert['metrics']}")
    print("-" * 55)

    result = graph.invoke({
        **alert,
        "timestamp": "",
        "category": "",
        "severity": "",
        "confidence": 0.0,
        "diagnostic_findings": [],
        "proposed_actions": [],
        "risk_level": "",
        "requires_approval": False,
        "execution_status": "",
        "audit_log": [],
    }, config=config)

    print(f"\n  Result:")
    print(f"    Category:    {result['category']}")
    print(f"    Severity:    {result['severity']}")
    print(f"    Risk:        {result['risk_level']}")
    print(f"    Status:      {result['execution_status']}")
    print(f"    Audit trail: {len(result['audit_log'])} entries")

print(f"""

{'='*55}
PRODUCTION PIPELINE SUMMARY
{'='*55}

5-stage pipeline:
  1. INGEST:    Normalize alert from any source
  2. CLASSIFY:  Category + severity + confidence
  3. DIAGNOSE:  Run category-specific checks
  4. PROPOSE:   Remediation with risk assessment
  5. EXECUTE:   Auto-execute (low risk) or await approval

Production features:
  - Checkpointing:    Resume if pipeline crashes
  - Audit log:        Every step recorded (compliance)
  - Risk assessment:  Auto vs. manual execution
  - Multi-source:     Prometheus, Datadog, PagerDuty, etc.
  - Thread isolation:  Each alert is a separate thread

This is a real production pattern. Add LLM calls to the
classify and diagnose nodes, connect to real databases in
the diagnostic checks, and you have dbaBrain.
""")
PYEOF
```

Expected output (yours will differ):

```
Production DBA Monitoring Pipeline
=======================================================

Graph structure:
(Mermaid diagram - exact syntax varies by LangGraph version)
...

Alert 1: Replication lag 45s on standby-2 and increasing...
Source: prometheus
...
  [1. ingest] Alert from prometheus at 2026-06-15 ...
  [2. classify] replication (P3, confidence=1.0)
  [3. diag] pg_stat_replication: 2 standbys active...
  [4. propose] 4 actions, risk=LOW
  [5. execute] AUTO_EXECUTED (low risk actions)
```

---

## What you learned

| Pattern | DBA Analogy | LangGraph |
|---------|------------|-----------|
| Subgraph | Stored procedure calling sub-procedures | Compiled graph used as a node |
| Parallel nodes | Multiple psql sessions in parallel tabs | Fan-out edges from one node |
| Map-reduce | Check 10 DBs, merge into fleet report | Map function + reduce merger |
| Streaming | tail -f for agent thoughts | `graph.stream()` |
| Retry | Retry psql on timeout | Loop in node with counter |
| Fallback | Use cached data on failure | Default return in except |
| Production pipeline | Complete incident response | All patterns combined |

This completes the Build track. Continue to [Use exercises](../use/01-langgraph-exercises.md) to practice these patterns.
