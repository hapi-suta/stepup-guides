# LangGraph Mastery - Concepts

Everything you need to understand LangGraph, from graph theory basics to production patterns.

---

## Graph Theory Basics

A graph is a set of **nodes** connected by **edges**.

```
Node A --edge--> Node B --edge--> Node C
```

In LangGraph:
- **Node** = a Python function that reads state and returns updates
- **Edge** = a connection that controls which node runs next
- **State** = a dictionary that flows through every node
- **Conditional edge** = an edge that chooses the next node based on state

**DBA parallel:**

| Graph Concept | DBA Equivalent |
|--------------|----------------|
| Node | A stored procedure |
| Edge | Control flow (CALL next_procedure) |
| State | A row in a workflow table |
| Conditional edge | CASE WHEN in SQL |
| Entry point | First step in a runbook |
| END | Incident resolved, ticket closed |

---

## LangGraph Architecture

LangGraph is built on three core ideas:

### 1. State is a TypedDict

```python
class AlertState(TypedDict):
    alert_text: str
    category: str
    severity: str
    recommendation: str
```

This is your "workflow table schema." Every node reads from and writes to this state.

### 2. Nodes are functions

```python
def classify(state: AlertState) -> dict:
    # Read state, do work, return updates
    return {"category": "replication"}
```

Nodes return ONLY the keys they want to update. LangGraph merges the updates into the full state. This is like `UPDATE ... SET column = value` - you don't rewrite the whole row.

### 3. The graph controls execution order

```python
builder = StateGraph(AlertState)
builder.add_node("classify", classify)
builder.add_node("diagnose", diagnose)
builder.add_edge("classify", "diagnose")
```

The graph defines which node runs after which. You can have:
- **Sequential edges**: A -> B -> C
- **Conditional edges**: A -> B if P1, A -> C if P4
- **Parallel edges**: A -> [B, C, D] (fan out)
- **Convergent edges**: [B, C, D] -> E (fan in)

---

## State Management

### Default behavior: last write wins

When a node returns `{"severity": "P1"}`, it overwrites whatever was in `severity` before. This is the default for all scalar fields (str, int, bool).

### Reducers: accumulate instead of overwrite

For list fields, you usually want to APPEND, not REPLACE:

```python
from typing import Annotated
import operator

class State(TypedDict):
    findings: Annotated[list, operator.add]  # append, don't replace
```

With `Annotated[list, operator.add]`, each node's list is appended to the existing list. Without it, each node's list replaces the previous one.

**DBA parallel:** Reducers are like WAL replay logic. Each node's changes are a WAL record. The reducer defines how to apply them:
- Default (replace) = UPDATE SET column = new_value
- Add (append) = INSERT INTO log_table

---

## Checkpointing

Checkpointing saves the graph state after each node runs.

### Why it matters

Without checkpointing:
- Process crashes at step 3 of 5 -> start over from step 1
- Lose all intermediate results

With checkpointing:
- Process crashes at step 3 of 5 -> resume from step 3
- All intermediate results preserved

### Checkpointer options

| Checkpointer | Storage | Persistence | Use Case |
|--------------|---------|-------------|----------|
| MemorySaver | RAM | Lost on exit | Development, testing |
| SqliteSaver | SQLite file | Survives restart | Single-server deployment |
| PostgresSaver | PostgreSQL | Full durability | Production (the DBA's choice) |

**DBA parallel:** Checkpointing IS your WAL + checkpoint system.
- MemorySaver = unlogged table (fast, lost on crash)
- SqliteSaver = local WAL file on disk
- PostgresSaver = synchronous replication (full durability)

### Thread-based isolation

Each `thread_id` gets its own state, like a separate database connection:

```python
config = {"configurable": {"thread_id": "incident-001"}}
```

Thread "incident-001" and "incident-002" have completely separate state. This is MVCC for agent state.

---

## Human-in-the-Loop Patterns

### The core pattern

```python
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute"],  # Pause here
)
```

The graph runs up to the `execute` node, saves a checkpoint, and stops. A human reviews the proposed action, then resumes:

```python
graph.invoke(None, config=config)  # Resume from checkpoint
```

### Modify before resuming

The human can change the agent's plan:

```python
graph.update_state(config, {"proposed_action": "VACUUM orders;"})
```

### When to use human-in-the-loop

| Operation | Risk Level | Approval |
|-----------|-----------|----------|
| SELECT queries | None | Auto-execute |
| EXPLAIN ANALYZE | None | Auto-execute |
| VACUUM (regular) | Low | Auto-execute |
| ALTER SYSTEM SET | Medium | Require approval |
| pg_terminate_backend | Medium | Require approval |
| VACUUM FULL | High | Require approval |
| DROP TABLE | Critical | Require approval + confirmation |

**DBA parallel:** This is your change advisory board (CAB) process, automated. The agent submits the change request. The DBA approves, modifies, or rejects.

---

## Subgraphs

A subgraph is a compiled graph used as a node inside a parent graph.

```
Parent Graph:
  classify -> [replication_subgraph] -> recommend

Replication Subgraph (runs internally):
  check_wal -> check_network -> check_standby -> summarize
```

**Benefits:**
- **Reuse:** the replication subgraph can be used in multiple parent graphs
- **Test:** test the subgraph independently
- **Maintain:** change subgraph internals without touching the parent

**DBA parallel:** Stored procedures calling other stored procedures. `diagnose_replication()` internally calls `check_wal_sender()`, `check_network()`, `check_standby_io()`. The caller just gets the final diagnosis.

---

## Streaming

Instead of waiting for the entire graph to finish, stream results as each node completes.

Two modes:
- `stream()` - get node-level updates (what changed)
- `stream(stream_mode="values")` - get full state snapshots

**DBA parallel:** `tail -f postgresql.log` vs `cat postgresql.log`. Streaming lets you watch the agent think in real-time.

---

## Error Handling Patterns

### Retry

Wrap flaky operations in a retry loop:

```python
def check_with_retry(state):
    for attempt in range(3):
        try:
            result = run_check()
            return {"finding": result}
        except TimeoutError:
            if attempt == 2:
                return {"finding": "UNAVAILABLE (cached data)"}
```

### Fallback

If a check fails after all retries, use a safe default instead of crashing:

```python
except Exception:
    return {"finding": "Check failed - using cached data"}
```

### Skip and continue

Mark the failed check and continue the pipeline:

```python
return {"findings": ["check_x: FAILED"], "errors": ["check_x timed out"]}
```

**DBA parallel:** Your monitoring script retries on psql timeout, uses cached data if all retries fail, and never crashes the entire monitoring loop because one of 10 checks failed.

---

## Comparison to Other Frameworks

| Feature | LangGraph | CrewAI | AutoGen |
|---------|-----------|--------|---------|
| Graph-based | Yes (core concept) | No (agent teams) | No (conversation) |
| State management | TypedDict + reducers | Agent memory | Chat history |
| Checkpointing | Built-in | Not built-in | Not built-in |
| Human-in-the-loop | Built-in (interrupt) | Limited | Limited |
| Parallel execution | Fan-out/fan-in | Parallel tasks | Async agents |
| Subgraphs | Yes | Sub-teams | Nested groups |
| Streaming | Yes | Limited | Yes |
| Visualization | Mermaid export | No | No |
| Best for | Complex workflows | Team-based tasks | Conversational AI |

### When to choose LangGraph

- Complex workflows with conditional routing
- Workflows that need to be paused and resumed
- Production systems that need checkpointing
- Workflows that need human approval gates
- Parallel execution with merge steps

### When to choose CrewAI

- Simple agent teams with defined roles
- Quick prototyping of multi-agent systems
- Tasks where agent "personality" matters
- Less complex routing requirements

---

## Production Checklist

Before deploying a LangGraph pipeline to production:

- [ ] **Checkpointing:** PostgresSaver configured (not MemorySaver)
- [ ] **Error handling:** Every node has try/except with fallbacks
- [ ] **Retry logic:** Flaky operations retry 3 times
- [ ] **Human-in-the-loop:** Dangerous operations require approval
- [ ] **Type safety:** TypedDict state with explicit types
- [ ] **Routing tests:** Every conditional edge path tested
- [ ] **Visualization:** Graph exported as Mermaid for documentation
- [ ] **Streaming:** Real-time output for monitoring dashboards
- [ ] **Audit log:** Every node logs its actions to state
- [ ] **Timeout:** Nodes have maximum execution time
- [ ] **Monitoring:** Track node execution time, error rate, routing distribution

**DBA parallel:** This is the same checklist as deploying a PostgreSQL cluster:
- [ ] Replication configured (not standalone)
- [ ] Backups scheduled and tested
- [ ] Monitoring and alerting active
- [ ] pg_hba.conf reviewed
- [ ] Connection pooling configured
- [ ] Runbooks documented
