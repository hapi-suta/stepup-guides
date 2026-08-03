# Build 01: LangGraph Fundamentals

Build your first LangGraph workflow from scratch. By the end, you'll have a working DBA alert processing graph that classifies, routes, diagnoses, and recommends.

---

## Step 1. Install LangGraph

On your **Mac terminal**, run:

```bash
pip3 install langgraph langchain-anthropic langchain-openai langchain-core
```

Expected output (yours will differ):

```
Successfully installed langgraph-0.x.x langchain-anthropic-0.x.x ...
```

Verify the install:

```bash
python3 -c "from importlib.metadata import version; print(f'LangGraph version: {version(\"langgraph\")}')"
```

Expected output (yours will differ):

```
LangGraph version: 1.x.x
```

---

## Step 2. What is a state graph?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# WHAT IS A STATE GRAPH?
#
# DBA analogy: Think of your incident response flowchart.
#
#   Alert fires
#     -> Classify (is it replication? storage? performance?)
#     -> Route (P1 goes to immediate, P4 goes to backlog)
#     -> Diagnose (check pg_stat_activity, pg_stat_replication)
#     -> Recommend (VACUUM? kill query? add standby?)
#
# Each step is a NODE (a function that reads and updates state).
# Each arrow is an EDGE (a connection between nodes).
# The entire flowchart is a STATE GRAPH.
#
# In SQL terms:
#   - State = the current row in a workflow table
#   - Node  = a stored procedure that updates that row
#   - Edge  = a foreign key pointing to the next procedure
#   - Conditional edge = a CASE WHEN that picks the next step
# ============================================================

print("State Graph = Your Incident Response Flowchart")
print("=" * 55)

print("""
PostgreSQL Incident Response        LangGraph Equivalent
---------------------------------   ----------------------
Alert fires                         graph.invoke(initial_state)
Classify the alert                  Node: classify_alert()
Route by severity                   Conditional Edge: route()
Diagnose root cause                 Node: diagnose()
Recommend fix                       Node: recommend()
Done - ticket closed                END node

The STATE is a dictionary that flows through every node.
Each node reads the state, does work, and returns updates.
The graph controls which node runs next.

Why not just call functions in sequence?
  - Conditional routing (different paths for different alerts)
  - Checkpointing (resume if the process crashes mid-way)
  - Human-in-the-loop (pause and wait for DBA approval)
  - Parallel execution (check 10 databases at once)
  - Visualization (see the flowchart as a diagram)

Regular function calls can't do any of that cleanly.
A graph gives you all of it for free.
""")
PYEOF
```

---

## Step 3. Build your first StateGraph

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# YOUR FIRST STATEGRAPH
#
# We'll build the simplest possible graph:
#   start -> greet -> END
#
# DBA analogy: a one-step runbook.
#   "When you get a disk alert, check df -h. Done."
# ============================================================

from typing import TypedDict
from langgraph.graph import StateGraph, END

# Step 1: Define the state.
# TypedDict = a dictionary with specific keys and types.
# DBA analogy: this is the schema for your workflow table.
#   CREATE TABLE workflow_state (
#       message TEXT,
#       processed BOOLEAN DEFAULT FALSE
#   );

class SimpleState(TypedDict):
    message: str
    processed: bool

# Step 2: Define a node.
# A node is just a function that takes state and returns updates.
# DBA analogy: a stored procedure that reads a row and updates it.

def greet(state: SimpleState) -> dict:
    """Take the message and mark it as processed."""
    msg = state["message"]
    print(f"  Node 'greet' received: {msg}")
    return {"message": f"Processed: {msg}", "processed": True}

# Step 3: Build the graph.
# DBA analogy: defining the workflow steps and their order.

graph_builder = StateGraph(SimpleState)

# Add the node
graph_builder.add_node("greet", greet)

# Set the entry point (which node runs first)
graph_builder.set_entry_point("greet")

# Add edge from greet to END
graph_builder.add_edge("greet", END)

# Compile the graph (like preparing a query plan)
graph = graph_builder.compile()

# Step 4: Run it!
print("Running the simplest possible graph")
print("=" * 45)

result = graph.invoke({
    "message": "High CPU on pg-primary",
    "processed": False,
})

print(f"\n  Final state:")
print(f"    message:   {result['message']}")
print(f"    processed: {result['processed']}")
print(f"\nThe graph ran one node and reached END.")
PYEOF
```

Expected output (yours will differ):

```
Running the simplest possible graph
=============================================
  Node 'greet' received: High CPU on pg-primary

  Final state:
    message:   Processed: High CPU on pg-primary
    processed: True

The graph ran one node and reached END.
```

---

## Step 4. Multi-node graph with edges

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# MULTI-NODE GRAPH
#
# Three nodes in sequence:
#   classify -> diagnose -> recommend -> END
#
# DBA analogy: a 3-step runbook.
#   1. Classify the alert (replication? storage? performance?)
#   2. Diagnose (check relevant pg_stat views)
#   3. Recommend (what command to run)
# ============================================================

from typing import TypedDict, Optional
from langgraph.graph import StateGraph, END

class AlertState(TypedDict):
    alert_text: str
    category: str
    diagnosis: str
    recommendation: str

def classify(state: AlertState) -> dict:
    """Classify the alert based on keywords."""
    text = state["alert_text"].lower()

    if any(kw in text for kw in ["replication", "lag", "standby", "wal"]):
        category = "replication"
    elif any(kw in text for kw in ["disk", "storage", "space", "full"]):
        category = "storage"
    elif any(kw in text for kw in ["cpu", "slow", "timeout", "latency"]):
        category = "performance"
    elif any(kw in text for kw in ["connection", "refused", "pool"]):
        category = "connectivity"
    else:
        category = "unknown"

    print(f"  [classify] '{state['alert_text']}' -> {category}")
    return {"category": category}

def diagnose(state: AlertState) -> dict:
    """Suggest diagnostic queries based on category."""
    diagnostics = {
        "replication": "SELECT * FROM pg_stat_replication; SELECT pg_wal_lsn_diff(sent_lsn, replay_lsn) FROM pg_stat_replication;",
        "storage": "SELECT pg_size_pretty(pg_database_size(current_database())); SELECT * FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 5;",
        "performance": "SELECT * FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC LIMIT 10;",
        "connectivity": "SELECT count(*) FROM pg_stat_activity; SHOW max_connections;",
        "unknown": "SELECT * FROM pg_stat_activity; -- start with general activity check",
    }
    diag = diagnostics.get(state["category"], diagnostics["unknown"])
    print(f"  [diagnose] category={state['category']} -> query selected")
    return {"diagnosis": diag}

def recommend(state: AlertState) -> dict:
    """Recommend action based on category and diagnosis."""
    actions = {
        "replication": "Check network latency between primary and standby. If lag > 30s, consider increasing wal_keep_size or checking standby I/O.",
        "storage": "Run VACUUM FULL on top bloated tables. Check pg_stat_user_tables.n_dead_tup. Consider adding autovacuum_vacuum_scale_factor tuning.",
        "performance": "Identify the slow query with pg_stat_statements. Check for missing indexes with EXPLAIN ANALYZE.",
        "connectivity": "Check pgbouncer pool utilization. Increase max_connections if needed (but prefer connection pooling).",
        "unknown": "Gather more context. Check pg_stat_activity and system metrics (CPU, disk, memory).",
    }
    action = actions.get(state["category"], actions["unknown"])
    print(f"  [recommend] action generated for {state['category']}")
    return {"recommendation": action}

# Build the graph
builder = StateGraph(AlertState)

# Add nodes
builder.add_node("classify", classify)
builder.add_node("diagnose", diagnose)
builder.add_node("recommend", recommend)

# Add edges: classify -> diagnose -> recommend -> END
builder.set_entry_point("classify")
builder.add_edge("classify", "diagnose")
builder.add_edge("diagnose", "recommend")
builder.add_edge("recommend", END)

# Compile
graph = builder.compile()

# Run with test alerts
print("Multi-Node Alert Processing Graph")
print("=" * 55)

test_alerts = [
    "Replication lag on pg-standby-2 is 45 seconds and growing",
    "Disk usage at 94% on pg-analytics /pgdata",
    "CPU spike to 98% - queries timing out on pg-primary",
    "Connection refused from app server - pool exhausted",
]

for alert in test_alerts:
    print(f"\nAlert: {alert}")
    print("-" * 55)
    result = graph.invoke({
        "alert_text": alert,
        "category": "",
        "diagnosis": "",
        "recommendation": "",
    })
    print(f"  [result] Recommendation: {result['recommendation'][:80]}...")
PYEOF
```

Expected output (yours will differ):

```
Multi-Node Alert Processing Graph
=======================================================

Alert: Replication lag on pg-standby-2 is 45 seconds and growing
-------------------------------------------------------
  [classify] 'Replication lag on pg-standby-2 is 45 seconds and growing' -> replication
  [diagnose] category=replication -> query selected
  [recommend] action generated for replication
  [result] Recommendation: Check network latency between primary and standby. If lag > 30s, co...
```

---

## Step 5. Conditional edges - routing based on state

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# CONDITIONAL EDGES
#
# Not all alerts follow the same path.
# P1 alerts need immediate escalation.
# P4 alerts go to the backlog.
#
# DBA analogy: CASE WHEN in a SQL query.
#   CASE
#     WHEN severity = 'P1' THEN escalate()
#     WHEN severity = 'P4' THEN log_and_wait()
#     ELSE standard_response()
#   END
#
# In LangGraph, a conditional edge is a function that
# returns the NAME of the next node to run.
# ============================================================

from typing import TypedDict
from langgraph.graph import StateGraph, END

class AlertState(TypedDict):
    alert_text: str
    severity: str
    category: str
    response: str

def classify_and_score(state: AlertState) -> dict:
    """Classify alert and assign severity."""
    text = state["alert_text"].lower()

    # Simple keyword classification
    if "replication" in text or "lag" in text:
        category = "replication"
    elif "disk" in text or "full" in text:
        category = "storage"
    elif "cpu" in text or "slow" in text:
        category = "performance"
    else:
        category = "general"

    # Score severity based on urgency keywords
    if any(kw in text for kw in ["down", "crash", "data loss", "corruption"]):
        severity = "P1"
    elif any(kw in text for kw in ["95%", "98%", "99%", "lag 60", "timeout"]):
        severity = "P2"
    elif any(kw in text for kw in ["lag", "slow", "high"]):
        severity = "P3"
    else:
        severity = "P4"

    print(f"  [classify] category={category}, severity={severity}")
    return {"category": category, "severity": severity}

def escalate(state: AlertState) -> dict:
    """P1: immediate escalation - page the on-call DBA."""
    print(f"  [ESCALATE] P1 ALERT - paging on-call DBA immediately!")
    return {"response": f"ESCALATED: P1 {state['category']} alert. On-call DBA paged. Incident channel opened."}

def standard_response(state: AlertState) -> dict:
    """P2/P3: standard diagnostic response."""
    print(f"  [standard] Running standard diagnostics for {state['category']}")
    return {"response": f"DIAGNOSED: {state['category']} issue. Running automated checks. DBA notified via Slack."}

def log_to_backlog(state: AlertState) -> dict:
    """P4: low priority - just log it."""
    print(f"  [backlog] Low priority - logging for review")
    return {"response": f"LOGGED: P4 {state['category']} alert added to backlog for next business day review."}

# The routing function: returns the NAME of the next node
def route_by_severity(state: AlertState) -> str:
    """Route to different nodes based on severity.

    DBA analogy: this is your CASE WHEN statement.
    It reads the state and returns which 'stored procedure' to call next.
    """
    severity = state["severity"]
    if severity == "P1":
        return "escalate"
    elif severity in ("P2", "P3"):
        return "standard_response"
    else:
        return "log_to_backlog"

# Build the graph
builder = StateGraph(AlertState)

builder.add_node("classify_and_score", classify_and_score)
builder.add_node("escalate", escalate)
builder.add_node("standard_response", standard_response)
builder.add_node("log_to_backlog", log_to_backlog)

builder.set_entry_point("classify_and_score")

# Conditional edge: after classify, route based on severity
builder.add_conditional_edges(
    "classify_and_score",       # source node
    route_by_severity,          # routing function
    {                           # mapping: return value -> node name
        "escalate": "escalate",
        "standard_response": "standard_response",
        "log_to_backlog": "log_to_backlog",
    }
)

# All response nodes go to END
builder.add_edge("escalate", END)
builder.add_edge("standard_response", END)
builder.add_edge("log_to_backlog", END)

graph = builder.compile()

print("Conditional Routing Graph")
print("=" * 55)

test_alerts = [
    "Primary database is DOWN - possible data loss",
    "Disk usage at 98% on pg-analytics /pgdata",
    "Replication lag increasing on standby-3",
    "Routine checkpoint completed successfully",
]

for alert in test_alerts:
    print(f"\nAlert: {alert}")
    print("-" * 55)
    result = graph.invoke({
        "alert_text": alert,
        "severity": "",
        "category": "",
        "response": "",
    })
    print(f"  -> {result['response']}")
PYEOF
```

Expected output (yours will differ):

```
Conditional Routing Graph
=======================================================

Alert: Primary database is DOWN - possible data loss
-------------------------------------------------------
  [classify] category=general, severity=P1
  [ESCALATE] P1 ALERT - paging on-call DBA immediately!
  -> ESCALATED: P1 general alert. On-call DBA paged. Incident channel opened.

Alert: Disk usage at 98% on pg-analytics /pgdata
-------------------------------------------------------
  [classify] category=storage, severity=P2
  [standard] Running standard diagnostics for storage
  -> DIAGNOSED: storage issue. Running automated checks. DBA notified via Slack.
```

---

## Step 6. Complete DBA alert processing graph

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# COMPLETE DBA ALERT PROCESSING GRAPH
#
# Full pipeline: classify -> route -> diagnose -> recommend -> END
#
# DBA analogy: Your complete incident response playbook,
# encoded as a graph that can be checkpointed, visualized,
# and extended with human-in-the-loop approvals.
# ============================================================

from typing import TypedDict, List
from langgraph.graph import StateGraph, END

class DBAAlertState(TypedDict):
    alert_text: str
    metrics: dict
    category: str
    severity: str
    diagnosis: str
    queries_to_run: List[str]
    recommendation: str
    escalated: bool

def classify_alert(state: DBAAlertState) -> dict:
    text = state["alert_text"].lower()
    keywords = {
        "replication": ["replication", "lag", "standby", "wal", "streaming"],
        "storage": ["disk", "storage", "space", "full", "tablespace", "bloat"],
        "performance": ["cpu", "slow", "timeout", "latency", "load", "query"],
        "connectivity": ["connection", "refused", "pool", "pgbouncer", "max_connections"],
        "backup": ["backup", "archive", "pitr", "restore", "basebackup"],
        "security": ["permission", "denied", "auth", "login", "unauthorized"],
    }

    scores = {}
    for cat, kws in keywords.items():
        scores[cat] = sum(1 for kw in kws if kw in text)

    category = max(scores, key=scores.get) if max(scores.values()) > 0 else "unknown"
    print(f"  [1. classify] -> {category}")
    return {"category": category}

def score_severity(state: DBAAlertState) -> dict:
    text = state["alert_text"].lower()
    metrics = state.get("metrics", {})

    # Start at P3, escalate based on signals
    score = 3
    if any(kw in text for kw in ["down", "crash", "data loss", "corruption", "failover"]):
        score = 1
    elif any(kw in text for kw in ["95%", "98%", "99%", "critical", "emergency"]):
        score = 1
    elif any(kw in text for kw in ["high", "increasing", "degraded"]):
        score = 2

    # Metric overrides - critical thresholds force P1
    cpu = metrics.get("cpu_percent", 0)
    disk = metrics.get("disk_percent", 0)
    lag = metrics.get("replication_lag_seconds", 0)

    if cpu > 95 or disk > 95 or lag > 300:
        score = 1

    severity = f"P{score}"
    print(f"  [2. score]    -> {severity}")
    return {"severity": severity}

def route_alert(state: DBAAlertState) -> str:
    if state["severity"] == "P1":
        return "escalate_and_diagnose"
    else:
        return "diagnose"

def escalate_and_diagnose(state: DBAAlertState) -> dict:
    print(f"  [3. ESCALATE] P1 -> paging on-call, opening incident channel")
    cat = state["category"]
    diag_map = {
        "replication": "WAL sender disconnected or standby I/O bottleneck. Check pg_stat_replication and network.",
        "storage": "Disk critically full. Immediate risk of database shutdown. Check pg_stat_user_tables for bloat.",
        "performance": "Query or CPU crisis. Check pg_stat_activity for long-running queries and locks.",
        "connectivity": "Connection pool exhausted or PostgreSQL refusing connections. Check max_connections.",
        "backup": "Backup failure risks data loss. Check WAL archiving and backup job logs.",
        "security": "Unauthorized access attempt. Check pg_hba.conf and auth logs immediately.",
    }
    diagnosis = diag_map.get(cat, "Unknown issue. Start with pg_stat_activity.")
    return {"diagnosis": diagnosis, "escalated": True}

def diagnose(state: DBAAlertState) -> dict:
    cat = state["category"]
    diag_map = {
        "replication": "Replication lag detected. Likely causes: network latency, standby I/O, or WAL sender backlog.",
        "storage": "Storage pressure. Likely causes: table bloat, dead tuples, or unmanaged temp files.",
        "performance": "Performance degradation. Likely causes: missing index, lock contention, or resource starvation.",
        "connectivity": "Connection issues. Likely causes: pool exhaustion, firewall, or max_connections reached.",
        "backup": "Backup issue. Likely causes: disk space on backup target, network timeout, or archive_command failure.",
        "security": "Security event. Likely causes: pg_hba.conf mismatch, expired credentials, or brute force attempt.",
    }
    diagnosis = diag_map.get(cat, "Unknown category. Investigate manually.")
    print(f"  [3. diagnose] -> {diagnosis[:60]}...")
    return {"diagnosis": diagnosis, "escalated": False}

def recommend_queries(state: DBAAlertState) -> dict:
    cat = state["category"]
    query_map = {
        "replication": [
            "SELECT client_addr, state, sent_lsn, replay_lsn, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;",
            "SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes FROM pg_replication_slots;",
        ],
        "storage": [
            "SELECT schemaname, relname, n_dead_tup, pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;",
            "SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;",
        ],
        "performance": [
            "SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;",
            "SELECT query, calls, mean_exec_time, total_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;",
        ],
        "connectivity": [
            "SELECT count(*), state FROM pg_stat_activity GROUP BY state;",
            "SHOW max_connections;",
        ],
        "backup": [
            "SELECT * FROM pg_stat_archiver;",
            "SELECT pg_walfile_name(pg_current_wal_lsn());",
        ],
        "security": [
            "SELECT usename, client_addr, backend_start, state FROM pg_stat_activity ORDER BY backend_start DESC LIMIT 20;",
            "SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL;",
        ],
    }
    queries = query_map.get(cat, ["SELECT * FROM pg_stat_activity;"])
    print(f"  [4. queries]  -> {len(queries)} diagnostic queries")
    return {"queries_to_run": queries}

def generate_recommendation(state: DBAAlertState) -> dict:
    cat = state["category"]
    sev = state["severity"]
    escalated = state.get("escalated", False)

    rec_map = {
        "replication": "Check network between primary/standby. If lag > 60s, consider increasing wal_keep_size. Monitor pg_stat_replication continuously.",
        "storage": "Run VACUUM on top bloated tables. If disk > 90%, identify and truncate/drop unused tables. Add autovacuum tuning.",
        "performance": "EXPLAIN ANALYZE the slow query. Add missing indexes. Check for lock contention with pg_locks.",
        "connectivity": "Increase pgbouncer pool_size or max_connections. Check for connection leaks in application code.",
        "backup": "Check archive_command status. Verify backup target has disk space. Re-run failed backup manually.",
        "security": "Review pg_hba.conf for the source IP. Check if credentials were compromised. Enable log_connections.",
    }

    rec = rec_map.get(cat, "Investigate manually.")
    if escalated:
        rec = f"[ESCALATED - ON-CALL PAGED] {rec}"

    print(f"  [5. recommend] -> done")
    return {"recommendation": rec}

# Build the complete graph
builder = StateGraph(DBAAlertState)

# Add all nodes
builder.add_node("classify_alert", classify_alert)
builder.add_node("score_severity", score_severity)
builder.add_node("escalate_and_diagnose", escalate_and_diagnose)
builder.add_node("diagnose", diagnose)
builder.add_node("recommend_queries", recommend_queries)
builder.add_node("generate_recommendation", generate_recommendation)

# Wire the edges
builder.set_entry_point("classify_alert")
builder.add_edge("classify_alert", "score_severity")

# Conditional routing after severity scoring
builder.add_conditional_edges(
    "score_severity",
    route_alert,
    {
        "escalate_and_diagnose": "escalate_and_diagnose",
        "diagnose": "diagnose",
    }
)

# Both diagnosis paths lead to query recommendation
builder.add_edge("escalate_and_diagnose", "recommend_queries")
builder.add_edge("diagnose", "recommend_queries")
builder.add_edge("recommend_queries", "generate_recommendation")
builder.add_edge("generate_recommendation", END)

graph = builder.compile()

# Run the complete pipeline
print("Complete DBA Alert Processing Graph")
print("=" * 55)

test_cases = [
    {
        "alert_text": "Primary database is DOWN - replication failover initiated",
        "metrics": {"cpu_percent": 0, "disk_percent": 45, "replication_lag_seconds": 0},
    },
    {
        "alert_text": "Disk usage at 92% on pg-analytics /pgdata - increasing steadily",
        "metrics": {"cpu_percent": 30, "disk_percent": 92, "replication_lag_seconds": 2},
    },
    {
        "alert_text": "Slow queries detected on pg-primary - p99 latency 5s",
        "metrics": {"cpu_percent": 78, "disk_percent": 60, "replication_lag_seconds": 1},
    },
]

for tc in test_cases:
    print(f"\nAlert: {tc['alert_text']}")
    print(f"Metrics: {tc['metrics']}")
    print("-" * 55)
    result = graph.invoke({
        "alert_text": tc["alert_text"],
        "metrics": tc["metrics"],
        "category": "",
        "severity": "",
        "diagnosis": "",
        "queries_to_run": [],
        "recommendation": "",
        "escalated": False,
    })
    print(f"\n  Category:       {result['category']}")
    print(f"  Severity:       {result['severity']}")
    print(f"  Escalated:      {result['escalated']}")
    print(f"  Diagnosis:      {result['diagnosis'][:70]}...")
    print(f"  Queries:        {len(result['queries_to_run'])} diagnostic queries ready")
    print(f"  Recommendation: {result['recommendation'][:70]}...")
PYEOF
```

Expected output (yours will differ):

```
Complete DBA Alert Processing Graph
=======================================================

Alert: Primary database is DOWN - replication failover initiated
Metrics: {'cpu_percent': 0, 'disk_percent': 45, 'replication_lag_seconds': 0}
-------------------------------------------------------
  [1. classify] -> replication
  [2. score]    -> P1
  [3. ESCALATE] P1 -> paging on-call, opening incident channel
  [4. queries]  -> 2 diagnostic queries
  [5. recommend] -> done

  Category:       replication
  Severity:       P1
  Escalated:      True
  ...
```

---

## Step 7. Visualize the graph

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# VISUALIZE THE GRAPH
#
# LangGraph can export your graph as a Mermaid diagram.
# Mermaid is a text-based diagram format that GitHub,
# Notion, and many tools can render.
#
# DBA analogy: EXPLAIN shows you the query plan.
# get_graph().draw_mermaid() shows you the workflow plan.
# ============================================================

from typing import TypedDict, List
from langgraph.graph import StateGraph, END

class AlertState(TypedDict):
    alert_text: str
    severity: str
    category: str
    response: str

def classify(state: AlertState) -> dict:
    return {"category": "performance"}

def escalate(state: AlertState) -> dict:
    return {"response": "ESCALATED"}

def standard(state: AlertState) -> dict:
    return {"response": "standard response"}

def backlog(state: AlertState) -> dict:
    return {"response": "logged"}

def route(state: AlertState) -> str:
    s = state["severity"]
    if s == "P1":
        return "escalate"
    elif s in ("P2", "P3"):
        return "standard"
    return "backlog"

builder = StateGraph(AlertState)
builder.add_node("classify", classify)
builder.add_node("escalate", escalate)
builder.add_node("standard", standard)
builder.add_node("backlog", backlog)
builder.set_entry_point("classify")
builder.add_conditional_edges("classify", route, {
    "escalate": "escalate",
    "standard": "standard",
    "backlog": "backlog",
})
builder.add_edge("escalate", END)
builder.add_edge("standard", END)
builder.add_edge("backlog", END)
graph = builder.compile()

# Get the Mermaid diagram
mermaid = graph.get_graph().draw_mermaid()

print("Graph Visualization (Mermaid format)")
print("=" * 55)
print()
print(mermaid)
print()
print("Paste this into https://mermaid.live to see the diagram,")
print("or put it in a ```mermaid code block in GitHub/Notion.")
print()
print("This is like EXPLAIN for your workflow -")
print("you can see the flow before running it.")
PYEOF
```

Note: The exact Mermaid syntax may differ between LangGraph versions (e.g., `%%{init: ...}%%` header vs. YAML front matter), but the graph structure should match - you should see `__start__` connecting to `classify`, which conditionally routes to `escalate`, `standard`, or `backlog`, each connecting to `__end__`.

Expected output (yours will differ):

```
Graph Visualization (Mermaid format)
=======================================================

---
title: LangGraph
---
graph TD;
	__start__([<p>__start__</p>])
	classify(classify)
	escalate(escalate)
	standard(standard)
	backlog(backlog)
	__end__([<p>__end__</p>])
	__start__ --> classify;
	classify -.-> escalate;
	classify -.-> standard;
	classify -.-> backlog;
	escalate --> __end__;
	standard --> __end__;
	backlog --> __end__;
```

---

## What you learned

| Concept | DBA Analogy | LangGraph |
|---------|------------|-----------|
| State | Workflow table row | TypedDict passed through nodes |
| Node | Stored procedure | Function that transforms state |
| Edge | Foreign key to next step | Connection between nodes |
| Conditional edge | CASE WHEN routing | Function that returns next node name |
| Entry point | First step in runbook | `set_entry_point()` |
| END | Ticket closed | `END` sentinel |
| Compile | Prepare query plan | `builder.compile()` |
| Visualize | EXPLAIN | `get_graph().draw_mermaid()` |

Next: [Build 02 - State and Memory](02-state-and-memory.md) - add checkpointing so your graph can survive restarts.
