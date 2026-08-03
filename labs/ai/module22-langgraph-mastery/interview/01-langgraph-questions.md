# Interview 01: LangGraph Mastery

Five interview questions covering LangGraph architecture, state management, human-in-the-loop, workflow design, and framework comparison.

---

## Question 1: LangGraph's state graph model

**Interviewer asks:**
"Explain LangGraph's state graph model. How does it differ from a simple agent loop that calls tools in sequence?"

**What they're testing:** Do you understand WHY graphs matter, not just how to use them?

**Strong answer:**

```
A simple agent loop is: prompt -> think -> act -> observe -> repeat.
It's a single linear path. The agent decides everything on each step.

LangGraph's state graph is fundamentally different:

1. EXPLICIT CONTROL FLOW
   Instead of the LLM deciding what to do next on every step,
   the graph defines the possible paths upfront. A conditional
   edge routes based on state, not LLM judgment. This is more
   predictable and auditable.

2. TYPED STATE
   State is a TypedDict - a schema with explicit types.
   Every node reads and writes to this shared state.
   Like a workflow table in a database: the schema is fixed,
   each step updates specific columns.

3. CHECKPOINTING
   After each node, state is saved to a checkpoint store.
   If the process crashes, you resume from the last node,
   not from the beginning. A simple loop loses everything
   on crash.

4. CONDITIONAL ROUTING
   Different inputs take different paths through the graph.
   A P1 alert goes to escalation. A P4 goes to backlog.
   In a simple loop, this routing is buried in LLM prompts
   and hard to test.

5. PARALLEL EXECUTION
   Fan out to multiple nodes simultaneously, then fan in.
   A simple loop is sequential by nature.

6. HUMAN-IN-THE-LOOP
   The graph can pause at specific nodes, save state,
   and wait for human input. A simple loop can't do this
   without significant custom code.

The key insight: a simple loop is good for open-ended
exploration. A graph is better when you know the workflow
and need reliability, auditability, and recoverability.

For production database operations, you want a graph -
the same way you want a defined incident response process
instead of "figure it out as you go."
```

**DBA parallel:** A simple loop is like an ad-hoc psql session - you type commands as you think of them. A state graph is like a defined runbook - steps are predetermined, branching is explicit, progress is tracked, and you can resume if interrupted.

---

## Question 2: Checkpointing in production

**Interviewer asks:**
"How does LangGraph checkpointing work, and why is it critical for production agent systems? What happens without it?"

**What they're testing:** Do you understand persistence, crash recovery, and production reliability?

**Strong answer:**

```
LangGraph checkpointing saves the entire graph state after
each node executes. It's the agent equivalent of PostgreSQL's
WAL + checkpoint system.

HOW IT WORKS:
  1. Node A runs and returns state updates
  2. Updates are merged into the full state
  3. State is serialized and written to the checkpoint store
  4. Node B runs (repeat)

If the process crashes after step 3, on restart:
  - Load the last checkpoint
  - Resume from the next node (B)
  - Nodes A's work is NOT repeated

CHECKPOINT STORES:
  - MemorySaver: in-memory, lost on crash (dev only)
  - SqliteSaver: local file, survives restart
  - PostgresSaver: production-grade, uses YOUR database

Thread-based isolation:
  Each thread_id is like a database connection - its own
  state, its own checkpoint history. Thread "incident-001"
  and "incident-002" are completely separate.

WITHOUT CHECKPOINTING:
  - 10-step diagnostic workflow crashes at step 7
  - All 7 steps of work are lost
  - Must restart from step 1
  - If this involved API calls or database checks,
    you're repeating expensive operations
  - For human-in-the-loop: the human's approval is lost,
    they have to approve again

For production agents managing databases, checkpointing
is non-negotiable. You can't have an agent lose 30 minutes
of diagnostic work because of a process restart.

I'd use PostgresSaver in production because:
  1. The state lives in a durable database
  2. I can query checkpoint history with SQL
  3. I get my existing backup/HA for free
  4. I can debug agent behavior by inspecting rows
```

**DBA parallel:** Asking "why checkpointing?" for an agent is like asking "why WAL?" for a database. Without WAL, every crash loses committed transactions. Without checkpointing, every crash loses agent progress. Production systems need both.

---

## Question 3: Human-in-the-loop implementation

**Interviewer asks:**
"When would you use human-in-the-loop in an agent system, and how do you implement it in LangGraph? Give a concrete example."

**What they're testing:** Can you design safe agent systems that know when to defer to humans?

**Strong answer:**

```
WHEN TO USE IT:
  Any time the agent's proposed action could cause harm
  if it's wrong. The cost of asking a human is low.
  The cost of executing a bad action is high.

Examples:
  - Agent proposes VACUUM FULL (locks table for 30 min)
  - Agent proposes pg_terminate_backend (kills a query)
  - Agent proposes ALTER SYSTEM SET (changes config)
  - Agent proposes any DDL in production

When NOT to use it:
  - Read-only diagnostic queries (SELECT, EXPLAIN)
  - Low-risk operations (ANALYZE, regular VACUUM)
  - High-frequency, low-impact actions

HOW TO IMPLEMENT:

  graph = builder.compile(
      checkpointer=checkpointer,
      interrupt_before=["execute_action"],
  )

  Step 1: Agent runs up to the interrupt point.
          It classifies, diagnoses, and proposes an action.
          Graph saves checkpoint and STOPS.

  Step 2: Human reviews the proposal.
          They see: "Agent proposes: VACUUM FULL orders;"
          They can:
            - APPROVE: graph.invoke(None, config)
            - MODIFY: graph.update_state(config, {new_action})
                      then graph.invoke(None, config)
            - REJECT: don't resume (or route to cancel node)

  Step 3: After approval, agent executes and verifies.

For multi-step remediations, I'd interrupt before EACH
dangerous step. The DBA approves step-by-step, not all
at once. If step 2 causes unexpected results, they can
abort before step 3.

I'd also add time-boxed approval for P1 alerts:
  - Wait 5 minutes for DBA response
  - If no response, escalate to manager
  - If still no response, execute a SAFE DEFAULT
    (never VACUUM FULL, only non-destructive actions)

The key principle: the agent does the analysis work
(the boring part). The human makes the final decision
(the important part).
```

**DBA parallel:** This is the same as a change management process. The DBA proposes a maintenance window change. The CAB reviews. If approved, execute. If rejected, revise. You'd never auto-execute ALTER SYSTEM SET without review.

---

## Question 4: Design a LangGraph workflow for incident response

**Interviewer asks:**
"Design a LangGraph workflow for automated database incident response. Walk me through the nodes, edges, state, and how you'd handle different alert types."

**What they're testing:** Can you architect a real system, not just use the framework?

**Strong answer:**

```
STATE DESIGN:
  class IncidentState(TypedDict):
      alert_text: str
      alert_source: str           # prometheus, datadog, etc.
      metrics: dict               # cpu, disk, connections
      category: str               # replication, storage, etc.
      severity: str               # P1-P4
      confidence: float           # classification confidence
      diagnostic_findings: Annotated[list, operator.add]
      proposed_actions: list
      risk_level: str             # LOW, MEDIUM, HIGH
      execution_status: str
      audit_log: Annotated[list, operator.add]

GRAPH ARCHITECTURE:

  ingest -> classify -> route
                          |
            P1: escalate_and_diagnose -> propose -> [approve] -> execute -> verify
            P2/P3: diagnose -> propose -> [approve if HIGH risk] -> execute -> verify
            P4: log_to_backlog -> END

KEY DESIGN DECISIONS:

  1. CLASSIFICATION NODE
     Keyword matching + metric thresholds for reliability.
     Don't rely solely on LLM - use rules for safety-critical routing.
     LLM can enhance but rules must override.

  2. METRIC FLOOR SAFETY
     Regardless of text classification, certain metrics force P1:
       cpu > 95%, disk > 95%, replication_lag > 300s
     This prevents misclassification of critical alerts.

  3. CATEGORY-SPECIFIC SUBGRAPHS
     Each category (replication, storage, performance) has its own
     diagnostic subgraph with specialized checks.
     Replication subgraph: check_wal, check_slots, check_network
     Storage subgraph: check_bloat, check_autovacuum, check_disk

  4. PARALLEL DIAGNOSTICS
     Fan out to run multiple diagnostic checks simultaneously.
     Don't check connections, then replication, then disk serially.
     Run all three in parallel and merge results.

  5. RISK-BASED APPROVAL
     LOW risk: auto-execute (SELECT, ANALYZE)
     MEDIUM risk: require DBA approval
     HIGH risk: require DBA approval + confirmation

  6. CHECKPOINTING WITH POSTGRESQL
     Use PostgresSaver - agent state lives in the same database
     it's monitoring. If the agent process crashes mid-diagnosis,
     it resumes from the last completed node.

  7. AUDIT LOG
     Every node appends to audit_log (Annotated[list, operator.add]).
     This is the compliance trail. Who classified what, when,
     what action was proposed, who approved it.

SCALING:
  For 10+ databases, use map-reduce:
    - MAP: run health checks on all databases in parallel
    - REDUCE: merge findings, sort by severity
    - ROUTE: process each alert through the pipeline
```

**DBA parallel:** This is exactly how you'd design a production monitoring and incident response system - but instead of a Confluence runbook that humans follow, it's an executable graph that agents follow with human checkpoints at critical decision points.

---

## Question 5: LangGraph vs CrewAI

**Interviewer asks:**
"Compare LangGraph to CrewAI. When would you choose each? What are the tradeoffs?"

**What they're testing:** Do you understand the design philosophy differences, not just feature lists?

**Strong answer:**

```
FUNDAMENTAL DIFFERENCE:
  LangGraph = workflow-first (define the process, agents follow it)
  CrewAI = agent-first (define the agents, they figure out the process)

LANGGRAPH:
  - Core concept: state graph with explicit nodes and edges
  - Control flow is DEFINED by the developer
  - State is a typed dictionary with reducers
  - Built-in checkpointing and human-in-the-loop
  - Deterministic routing (same input = same path)
  - Best analogy: a flowchart/runbook

CREWAI:
  - Core concept: team of agents with roles and goals
  - Control flow is EMERGENT from agent collaboration
  - State is shared through agent messages
  - Less control over execution order
  - Non-deterministic (agents decide how to collaborate)
  - Best analogy: a team of specialists

WHEN I'D CHOOSE LANGGRAPH:
  - Database incident response (defined steps, need reliability)
  - Compliance-sensitive workflows (need audit trail)
  - Production systems (need checkpointing, crash recovery)
  - Workflows with human approval gates
  - When I need to guarantee specific paths are followed
  - Complex conditional routing based on data

WHEN I'D CHOOSE CREWAI:
  - Exploratory research tasks (agents brainstorm together)
  - Content creation (writer + editor + reviewer)
  - Quick prototyping of multi-agent systems
  - Tasks where agent "creativity" is more important than
    deterministic execution

FOR DATABASE OPERATIONS, I'D CHOOSE LANGGRAPH:
  When I'm managing 15,000 databases, I need:
    - Predictable routing (P1 ALWAYS goes to escalation)
    - Checkpointing (resume after crashes)
    - Human-in-the-loop (DBA approves dangerous operations)
    - Audit trail (who approved what, when)
    - Testable paths (I can test every routing branch)

  CrewAI's emergent behavior is a liability here.
  I don't want my database management agent to get
  "creative" with how it handles a P1 disk-full alert.

THE TRADEOFF:
  LangGraph requires more upfront design (you define every path).
  CrewAI requires less design but gives you less control.

  For production database operations: more control is better.
  For creative tasks: more flexibility is better.
```

**DBA parallel:** LangGraph is like a stored procedure with explicit control flow. CrewAI is like giving three DBAs a problem and letting them figure out who does what. For production incidents, you want the stored procedure. For brainstorming database architecture, you might want the team.
