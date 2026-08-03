# Build 03: Human in the Loop

Agents propose, DBAs approve. Build approval workflows where the agent pauses and waits for human input before executing dangerous operations.

---

## Step 1. Why agents need human approval

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# WHY AGENTS NEED HUMAN APPROVAL
#
# DBA analogy: You wouldn't let a junior DBA run
# DROP TABLE in production without review. Same for agents.
#
# Some operations are too dangerous to auto-execute:
#   - VACUUM FULL (locks the table for the entire duration)
#   - pg_terminate_backend (kills a running query)
#   - ALTER TABLE (might lock for minutes on large tables)
#   - Any DDL in production
#
# The pattern: Agent PROPOSES an action.
# Human REVIEWS and APPROVES (or rejects).
# Only then does the agent EXECUTE.
#
# This is the same as a pull request workflow:
#   Developer proposes changes -> Reviewer approves -> Merge
# Or a change management process:
#   DBA proposes maintenance -> CAB approves -> Execute
# ============================================================

print("Why Agents Need Human Approval")
print("=" * 55)

scenarios = [
    {
        "alert": "Table 'orders' has 5M dead tuples, 40% bloat",
        "agent_proposes": "VACUUM FULL orders;",
        "risk": "HIGH - VACUUM FULL takes an ACCESS EXCLUSIVE lock. "
                "The orders table will be COMPLETELY LOCKED for 10-30 minutes. "
                "No reads, no writes. If this is peak hours, you just killed the app.",
        "needs_approval": True,
    },
    {
        "alert": "Query running for 4 hours, blocking 12 other sessions",
        "agent_proposes": "SELECT pg_terminate_backend(12345);",
        "risk": "MEDIUM - Killing the query rolls back all its work. "
                "If it's a critical ETL job, you lose 4 hours of processing. "
                "If it's a runaway ad-hoc query, killing it is the right call.",
        "needs_approval": True,
    },
    {
        "alert": "Replication lag is 45 seconds on standby-2",
        "agent_proposes": "SELECT * FROM pg_stat_replication;",
        "risk": "NONE - This is a read-only diagnostic query. "
                "No data changes, no locks, no side effects.",
        "needs_approval": False,
    },
]

for s in scenarios:
    print(f"\nAlert: {s['alert']}")
    print(f"Agent proposes: {s['agent_proposes']}")
    print(f"Risk: {s['risk']}")
    approval = "YES - require DBA approval" if s["needs_approval"] else "NO - auto-execute (safe)"
    print(f"Needs approval: {approval}")
    print("-" * 55)

print(f"""
Rule of thumb:
  READ operations  -> auto-execute (SELECT, EXPLAIN)
  WRITE operations -> require approval (UPDATE, DELETE, DDL)
  LOCK operations  -> require approval (VACUUM FULL, REINDEX)
  KILL operations  -> require approval (pg_terminate_backend)

This is defense in depth:
  The agent is smart, but not infallible.
  A human checkpoint catches mistakes before they cause damage.
""")
PYEOF
```

---

## Step 2. Interrupt points - pausing the graph

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# INTERRUPT POINTS
#
# LangGraph can pause execution BEFORE or AFTER a node.
# The graph saves its state (checkpoint) and stops.
# When the human approves, you resume from that checkpoint.
#
# DBA analogy: A two-phase commit (2PC).
#   Phase 1: PREPARE TRANSACTION - work is done but not committed
#   Phase 2: COMMIT PREPARED - human says "go ahead"
#   Or: ROLLBACK PREPARED - human says "abort"
#
# In LangGraph:
#   interrupt_before=["execute"] means:
#     "Do all the work up to the execute node.
#      Then STOP and wait for approval.
#      When approved, run execute."
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class RemediationState(TypedDict):
    alert: str
    diagnosis: str
    proposed_action: str
    approval_status: str
    execution_result: str
    log: Annotated[list, operator.add]

def diagnose(state: RemediationState) -> dict:
    alert = state["alert"]
    if "bloat" in alert.lower() or "dead tuples" in alert.lower():
        diagnosis = "Table bloat detected. Dead tuples consuming significant space."
        action = "VACUUM FULL orders; -- WARNING: ACCESS EXCLUSIVE lock"
    elif "long-running" in alert.lower() or "blocking" in alert.lower():
        diagnosis = "Long-running query blocking other sessions."
        action = "SELECT pg_terminate_backend(12345); -- Kills query PID 12345"
    else:
        diagnosis = "General performance issue detected."
        action = "EXPLAIN ANALYZE <slow_query>; -- Safe diagnostic"

    print(f"  [diagnose] {diagnosis}")
    print(f"  [propose]  {action}")
    return {
        "diagnosis": diagnosis,
        "proposed_action": action,
        "log": [f"Diagnosed: {diagnosis}"],
    }

def execute_action(state: RemediationState) -> dict:
    """This node only runs AFTER human approval."""
    action = state["proposed_action"]
    print(f"  [EXECUTE] Running: {action}")
    return {
        "execution_result": f"Executed successfully: {action}",
        "log": [f"Executed: {action}"],
    }

builder = StateGraph(RemediationState)
builder.add_node("diagnose", diagnose)
builder.add_node("execute", execute_action)
builder.set_entry_point("diagnose")
builder.add_edge("diagnose", "execute")
builder.add_edge("execute", END)

checkpointer = MemorySaver()

# interrupt_before=["execute"] means:
# The graph will STOP before running the execute node.
# It saves the checkpoint and waits.
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute"],
)

config = {"configurable": {"thread_id": "remediation-001"}}

print("Interrupt Points - Pausing Before Execution")
print("=" * 55)

# Phase 1: Run up to the interrupt point
print("\nPhase 1: Agent diagnoses and proposes action")
print("-" * 45)
result = graph.invoke({
    "alert": "Table orders has 5M dead tuples and 40% bloat",
    "diagnosis": "",
    "proposed_action": "",
    "approval_status": "",
    "execution_result": "",
    "log": [],
}, config=config)

# Graph is now PAUSED before "execute"
state = graph.get_state(config)
print(f"\n  Graph status: PAUSED (waiting for approval)")
print(f"  Next node:    {state.next}")
print(f"  Proposed:     {state.values['proposed_action']}")

# Phase 2: Simulate DBA approval
# In a real system, this would be a Slack button, web UI, or CLI prompt
print(f"\nPhase 2: DBA reviews and approves")
print("-" * 45)
print(f"  DBA sees: {state.values['proposed_action']}")
print(f"  DBA says: APPROVED")

# Update state with approval and resume
graph.update_state(
    config,
    {"approval_status": "APPROVED"},
)

# Resume execution from the interrupt point
print(f"\nPhase 3: Agent executes approved action")
print("-" * 45)
result = graph.invoke(None, config=config)

print(f"\n  Execution result: {result['execution_result']}")
print(f"\n  Full log:")
for entry in result["log"]:
    print(f"    - {entry}")

print(f"""
The 3-phase pattern:
  1. Agent runs diagnosis and proposes action (auto)
  2. Graph PAUSES - human reviews the proposal
  3. Human approves - graph RESUMES and executes

This is your production safety net.
The agent does the analysis work.
The DBA makes the final call.

DBA parallel: PREPARE TRANSACTION -> review -> COMMIT or ROLLBACK.
""")
PYEOF
```

Expected output (yours will differ):

```
Interrupt Points - Pausing Before Execution
=======================================================

Phase 1: Agent diagnoses and proposes action
---------------------------------------------
  [diagnose] Table bloat detected. Dead tuples consuming significant space.
  [propose]  VACUUM FULL orders; -- WARNING: ACCESS EXCLUSIVE lock

  Graph status: PAUSED (waiting for approval)
  Next node:    ('execute',)
  Proposed:     VACUUM FULL orders; -- WARNING: ACCESS EXCLUSIVE lock

Phase 2: DBA reviews and approves
---------------------------------------------
  DBA sees: VACUUM FULL orders; -- WARNING: ACCESS EXCLUSIVE lock
  DBA says: APPROVED

Phase 3: Agent executes approved action
---------------------------------------------
  [EXECUTE] Running: VACUUM FULL orders; -- WARNING: ACCESS EXCLUSIVE lock

  Execution result: Executed successfully: VACUUM FULL orders; ...
```

---

## Step 3. DBA can reject and modify the plan

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# REJECT AND MODIFY
#
# The DBA doesn't just approve/reject.
# They can MODIFY the agent's proposed action.
#
# Example: Agent proposes VACUUM FULL during peak hours.
# DBA says: "No, use regular VACUUM instead. And do it
# after midnight."
#
# DBA analogy: Code review.
#   Developer submits PR. Reviewer says "change this line."
#   Developer updates. Reviewer approves. Merge.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class PlanState(TypedDict):
    alert: str
    proposed_action: str
    dba_decision: str
    execution_result: str
    log: Annotated[list, operator.add]

def propose(state: PlanState) -> dict:
    print(f"  [propose] VACUUM FULL orders;")
    return {
        "proposed_action": "VACUUM FULL orders;",
        "log": ["Agent proposed: VACUUM FULL orders;"],
    }

def execute(state: PlanState) -> dict:
    action = state["proposed_action"]
    print(f"  [execute] Running: {action}")
    return {
        "execution_result": f"Done: {action}",
        "log": [f"Executed: {action}"],
    }

builder = StateGraph(PlanState)
builder.add_node("propose", propose)
builder.add_node("execute", execute)
builder.set_entry_point("propose")
builder.add_edge("propose", "execute")
builder.add_edge("execute", END)

checkpointer = MemorySaver()
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute"],
)

print("Reject and Modify the Agent's Plan")
print("=" * 55)

# Scenario 1: DBA REJECTS and modifies
print("\nScenario 1: DBA modifies the plan")
print("-" * 45)

config1 = {"configurable": {"thread_id": "plan-001"}}

graph.invoke({
    "alert": "Table bloat on orders table",
    "proposed_action": "",
    "dba_decision": "",
    "execution_result": "",
    "log": [],
}, config=config1)

# Graph is paused. DBA reviews.
state = graph.get_state(config1)
print(f"  Agent proposed: {state.values['proposed_action']}")
print(f"  DBA says: 'No VACUUM FULL during business hours.'")
print(f"            'Use regular VACUUM instead.'")

# DBA modifies the proposed action
graph.update_state(
    config1,
    {
        "proposed_action": "VACUUM orders;",  # Changed from VACUUM FULL
        "dba_decision": "MODIFIED: Use regular VACUUM, not VACUUM FULL",
    },
)

# Resume with the modified plan
result = graph.invoke(None, config=config1)

print(f"\n  Executed: {result['execution_result']}")
print(f"  Log:")
for entry in result["log"]:
    print(f"    - {entry}")

# Scenario 2: DBA APPROVES as-is
print(f"\nScenario 2: DBA approves as-is (after hours)")
print("-" * 45)

config2 = {"configurable": {"thread_id": "plan-002"}}

graph.invoke({
    "alert": "Table bloat on orders table (after hours maintenance)",
    "proposed_action": "",
    "dba_decision": "",
    "execution_result": "",
    "log": [],
}, config=config2)

state = graph.get_state(config2)
print(f"  Agent proposed: {state.values['proposed_action']}")
print(f"  DBA says: 'Approved. It's after hours, VACUUM FULL is fine.'")

graph.update_state(config2, {"dba_decision": "APPROVED"})
result = graph.invoke(None, config=config2)

print(f"  Executed: {result['execution_result']}")

print(f"""
Three possible DBA decisions:
  1. APPROVE  - run the action as proposed
  2. MODIFY   - change the action, then run it
  3. REJECT   - cancel the workflow entirely

update_state() lets the DBA change ANY field in the state.
They can rewrite the proposed_action, add notes, or
change the severity - anything the agent got wrong.

DBA parallel: this is your change advisory board (CAB).
The agent submits the change request.
The DBA reviews, modifies if needed, and approves.
""")
PYEOF
```

Expected output (yours will differ):

```
Reject and Modify the Agent's Plan
=======================================================

Scenario 1: DBA modifies the plan
---------------------------------------------
  [propose] VACUUM FULL orders;
  Agent proposed: VACUUM FULL orders;
  DBA says: 'No VACUUM FULL during business hours.'
            'Use regular VACUUM instead.'
  [execute] Running: VACUUM orders;

  Executed: Done: VACUUM orders;
```

---

## Step 4. Multi-step approval workflow

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# MULTI-STEP APPROVAL
#
# For complex remediations with multiple steps,
# the DBA approves EACH step individually.
#
# DBA analogy: A maintenance plan with 5 steps.
# You don't approve the whole thing at once.
# You approve step 1, verify it worked, then approve step 2.
#
# Example:
#   Step 1: Kill the blocking query    -> approve
#   Step 2: VACUUM the bloated table   -> approve
#   Step 3: REINDEX the fragmented idx -> approve
#   Step 4: Update table statistics    -> approve
#   Step 5: Verify query performance   -> auto (safe)
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class MultiStepState(TypedDict):
    alert: str
    current_step: str
    steps_completed: Annotated[list, operator.add]
    steps_remaining: list
    result: str

def plan_steps(state: MultiStepState) -> dict:
    """Create a multi-step remediation plan."""
    steps = [
        "Step 1: pg_terminate_backend(12345) -- kill blocking query",
        "Step 2: VACUUM orders -- reclaim dead tuples",
        "Step 3: REINDEX INDEX idx_orders_customer_id -- fix fragmentation",
        "Step 4: ANALYZE orders -- update table statistics",
    ]
    print(f"  [plan] Created {len(steps)}-step remediation plan:")
    for step in steps:
        print(f"         {step}")
    return {
        "steps_remaining": steps,
        "current_step": steps[0],
    }

def execute_step(state: MultiStepState) -> dict:
    """Execute the current step."""
    step = state["current_step"]
    print(f"  [EXECUTE] {step}")
    remaining = state["steps_remaining"][1:]  # Remove completed step
    return {
        "steps_completed": [step],
        "steps_remaining": remaining,
        "current_step": remaining[0] if remaining else "ALL DONE",
        "result": f"Completed: {step}",
    }

def check_if_done(state: MultiStepState) -> str:
    """Route: more steps or done?"""
    if state["steps_remaining"]:
        return "execute_step"
    return END

builder = StateGraph(MultiStepState)
builder.add_node("plan_steps", plan_steps)
builder.add_node("execute_step", execute_step)

builder.set_entry_point("plan_steps")
builder.add_edge("plan_steps", "execute_step")

# After execution, check if more steps remain
builder.add_conditional_edges(
    "execute_step",
    check_if_done,
    {
        "execute_step": "execute_step",
        END: END,
    }
)

checkpointer = MemorySaver()
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute_step"],  # Pause before EACH execution
)

config = {"configurable": {"thread_id": "multistep-001"}}

print("Multi-Step Approval Workflow")
print("=" * 55)

# Start the plan
print("\nPhase 0: Create the plan")
print("-" * 45)
graph.invoke({
    "alert": "Orders table: blocking query + bloat + fragmented index",
    "current_step": "",
    "steps_completed": [],
    "steps_remaining": [],
    "result": "",
}, config=config)

# Now approve each step one at a time
step_num = 0
while True:
    state = graph.get_state(config)

    # Check if graph has more nodes to run
    if not state.next:
        print(f"\nAll steps completed!")
        break

    step_num += 1
    current = state.values.get("current_step", "unknown")
    print(f"\nStep {step_num}: Awaiting approval")
    print("-" * 45)
    print(f"  Proposed: {current}")
    print(f"  DBA says: APPROVED")

    # Resume (approve by continuing)
    graph.invoke(None, config=config)

# Final summary
final_state = graph.get_state(config)
print(f"\nFinal Summary:")
print(f"  Steps completed:")
for step in final_state.values.get("steps_completed", []):
    print(f"    [done] {step}")

print(f"""
Each step required separate approval.
The DBA could reject or modify any individual step.
The graph paused before each dangerous operation.

This is how you handle complex maintenance:
  1. Agent builds the plan
  2. DBA approves step-by-step
  3. Each step is checkpointed
  4. If something goes wrong at step 3,
     you don't re-run steps 1 and 2
""")
PYEOF
```

Expected output (yours will differ):

```
Multi-Step Approval Workflow
=======================================================

Phase 0: Create the plan
---------------------------------------------
  [plan] Created 4-step remediation plan:
         Step 1: pg_terminate_backend(12345) -- kill blocking query
         Step 2: VACUUM orders -- reclaim dead tuples
         ...

Step 1: Awaiting approval
---------------------------------------------
  Proposed: Step 1: pg_terminate_backend(12345) -- kill blocking query
  DBA says: APPROVED
  [EXECUTE] Step 1: pg_terminate_backend(12345) -- kill blocking query
...
```

---

## Step 5. Complete DBA remediation agent

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# COMPLETE DBA REMEDIATION AGENT
#
# Puts it all together:
#   1. Detect the issue
#   2. Diagnose root cause
#   3. Propose fix (with risk level)
#   4. Wait for DBA approval
#   5. Execute the fix
#   6. Verify the fix worked
#
# Two scenarios:
#   A) Bloated table -> propose VACUUM FULL -> approve -> execute
#   B) Long-running query -> propose pg_terminate_backend -> approve
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator

class RemediationState(TypedDict):
    alert: str
    category: str
    diagnosis: str
    proposed_action: str
    risk_level: str
    approval: str
    execution_result: str
    verification: str
    log: Annotated[list, operator.add]

def detect_and_classify(state: RemediationState) -> dict:
    text = state["alert"].lower()
    if "bloat" in text or "dead tuples" in text or "vacuum" in text:
        cat = "table_bloat"
    elif "long-running" in text or "blocking" in text or "lock" in text:
        cat = "blocking_query"
    elif "replication" in text or "lag" in text:
        cat = "replication_lag"
    elif "disk" in text or "full" in text:
        cat = "disk_pressure"
    else:
        cat = "general"

    print(f"  [detect]    Category: {cat}")
    return {"category": cat, "log": [f"Classified as: {cat}"]}

def diagnose_issue(state: RemediationState) -> dict:
    diag_map = {
        "table_bloat": "High dead tuple count from frequent updates without adequate autovacuum. Table size inflated 40%+. Consider VACUUM FULL for immediate relief or tune autovacuum for prevention.",
        "blocking_query": "Long-running query holding locks that block other transactions. 12+ sessions waiting. The blocking query has been running 4+ hours.",
        "replication_lag": "Standby falling behind. WAL apply rate slower than WAL generation rate. Network or I/O bottleneck suspected.",
        "disk_pressure": "Disk usage approaching critical. Largest tables have significant dead tuple overhead.",
    }
    diagnosis = diag_map.get(state["category"], "Requires manual investigation.")
    print(f"  [diagnose]  {diagnosis[:60]}...")
    return {"diagnosis": diagnosis, "log": [f"Diagnosis: {diagnosis[:50]}..."]}

def propose_fix(state: RemediationState) -> dict:
    fix_map = {
        "table_bloat": {
            "action": "VACUUM FULL public.orders;",
            "risk": "HIGH - ACCESS EXCLUSIVE lock for duration. Table unavailable for reads/writes.",
        },
        "blocking_query": {
            "action": "SELECT pg_terminate_backend(12345);",
            "risk": "MEDIUM - Query will be killed and rolled back. 4 hours of work lost.",
        },
        "replication_lag": {
            "action": "ALTER SYSTEM SET wal_keep_size = '2GB'; SELECT pg_reload_conf();",
            "risk": "LOW - Config change, no downtime. Increases disk usage for WAL.",
        },
        "disk_pressure": {
            "action": "VACUUM public.orders; VACUUM public.order_items;",
            "risk": "LOW - Regular VACUUM, no exclusive locks. May take 10-20 minutes.",
        },
    }
    fix = fix_map.get(state["category"], {"action": "Manual investigation needed", "risk": "UNKNOWN"})
    print(f"  [propose]   Action: {fix['action']}")
    print(f"              Risk:   {fix['risk'][:50]}...")
    return {
        "proposed_action": fix["action"],
        "risk_level": fix["risk"],
        "log": [f"Proposed: {fix['action']}"],
    }

def execute_fix(state: RemediationState) -> dict:
    action = state["proposed_action"]
    print(f"  [EXECUTE]   Running: {action}")
    # In production, this would actually run the SQL
    return {
        "execution_result": f"Successfully executed: {action}",
        "log": [f"Executed: {action}"],
    }

def verify_fix(state: RemediationState) -> dict:
    cat = state["category"]
    verify_map = {
        "table_bloat": "VERIFIED: Dead tuples reduced from 5M to 0. Table size reduced 40%.",
        "blocking_query": "VERIFIED: Blocking query terminated. 12 waiting sessions unblocked.",
        "replication_lag": "VERIFIED: wal_keep_size set to 2GB. Monitoring lag for next hour.",
        "disk_pressure": "VERIFIED: Disk usage dropped from 92% to 78%. Autovacuum running normally.",
    }
    verification = verify_map.get(cat, "Manual verification needed.")
    print(f"  [verify]    {verification}")
    return {"verification": verification, "log": [f"Verified: {verification}"]}

builder = StateGraph(RemediationState)
builder.add_node("detect", detect_and_classify)
builder.add_node("diagnose", diagnose_issue)
builder.add_node("propose", propose_fix)
builder.add_node("execute", execute_fix)
builder.add_node("verify", verify_fix)

builder.set_entry_point("detect")
builder.add_edge("detect", "diagnose")
builder.add_edge("diagnose", "propose")
builder.add_edge("propose", "execute")  # Interrupt happens here
builder.add_edge("execute", "verify")
builder.add_edge("verify", END)

checkpointer = MemorySaver()
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute"],  # Pause before dangerous operation
)

print("Complete DBA Remediation Agent")
print("=" * 55)

# Scenario A: Table bloat
print("\n--- Scenario A: Table Bloat ---")
config_a = {"configurable": {"thread_id": "remediation-bloat"}}

graph.invoke({
    "alert": "Table orders: 5M dead tuples, 40% bloat detected",
    "category": "", "diagnosis": "", "proposed_action": "",
    "risk_level": "", "approval": "", "execution_result": "",
    "verification": "", "log": [],
}, config=config_a)

state = graph.get_state(config_a)
print(f"\n  PAUSED - Awaiting DBA approval")
print(f"  Proposed: {state.values['proposed_action']}")
print(f"  Risk:     {state.values['risk_level'][:50]}...")
print(f"  DBA decision: APPROVED (it's maintenance window)")

# Resume
graph.invoke(None, config=config_a)

# Scenario B: Blocking query
print("\n--- Scenario B: Blocking Query ---")
config_b = {"configurable": {"thread_id": "remediation-block"}}

graph.invoke({
    "alert": "Long-running query PID 12345 blocking 12 sessions for 4 hours",
    "category": "", "diagnosis": "", "proposed_action": "",
    "risk_level": "", "approval": "", "execution_result": "",
    "verification": "", "log": [],
}, config=config_b)

state = graph.get_state(config_b)
print(f"\n  PAUSED - Awaiting DBA approval")
print(f"  Proposed: {state.values['proposed_action']}")
print(f"  Risk:     {state.values['risk_level'][:50]}...")
print(f"  DBA decision: APPROVED (12 blocked sessions is too many)")

graph.invoke(None, config=config_b)

# Show full log for scenario A
print(f"\n--- Full Audit Log (Scenario A) ---")
final = graph.get_state(config_a)
for entry in final.values.get("log", []):
    print(f"  {entry}")

print(f"""
The complete human-in-the-loop pattern:
  1. detect -> diagnose -> propose (automatic)
  2. PAUSE for approval (human reviews)
  3. execute -> verify (after approval)

Every action is logged. Every approval is recorded.
This is your audit trail - same as pg_audit_log
but for agent actions.
""")
PYEOF
```

Expected output (yours will differ):

```
Complete DBA Remediation Agent
=======================================================

--- Scenario A: Table Bloat ---
  [detect]    Category: table_bloat
  [diagnose]  High dead tuple count from frequent updates without adequa...
  [propose]   Action: VACUUM FULL public.orders;
              Risk:   HIGH - ACCESS EXCLUSIVE lock for duration. Table u...

  PAUSED - Awaiting DBA approval
  Proposed: VACUUM FULL public.orders;
  ...
  [EXECUTE]   Running: VACUUM FULL public.orders;
  [verify]    VERIFIED: Dead tuples reduced from 5M to 0. ...
```

---

## Step 6. Time-boxed approval with escalation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# TIME-BOXED APPROVAL
#
# What if the DBA doesn't respond in time?
# For P1 alerts, you can't wait forever.
#
# Pattern:
#   - Wait up to 5 minutes for DBA approval
#   - If no response, auto-escalate to manager
#   - If still no response, execute safe default action
#
# DBA analogy: PagerDuty escalation policy.
#   Level 1: On-call DBA (5 min timeout)
#   Level 2: DBA manager (10 min timeout)
#   Level 3: Auto-execute safe remediation
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
import operator
import time

class EscalationState(TypedDict):
    alert: str
    severity: str
    proposed_action: str
    safe_default_action: str
    approval_timeout_seconds: int
    escalation_level: int
    final_action: str
    log: Annotated[list, operator.add]

def assess_alert(state: EscalationState) -> dict:
    """Assess the alert and set approval timeout based on severity."""
    severity = state.get("severity", "P3")

    timeout_map = {
        "P1": 300,   # 5 minutes
        "P2": 600,   # 10 minutes
        "P3": 1800,  # 30 minutes
        "P4": 86400, # 24 hours
    }

    safe_defaults = {
        "P1": "CHECKPOINT; -- Safe: forces a checkpoint, no locks, buys time",
        "P2": "SELECT pg_reload_conf(); -- Safe: reload config, no restart",
        "P3": "ANALYZE; -- Safe: update statistics only",
        "P4": "-- No action: logged for review",
    }

    timeout = timeout_map.get(severity, 1800)
    safe_action = safe_defaults.get(severity, "-- No action")

    print(f"  [assess] Severity: {severity}")
    print(f"           Timeout:  {timeout}s before escalation")
    print(f"           Safe default: {safe_action}")
    return {
        "approval_timeout_seconds": timeout,
        "safe_default_action": safe_action,
        "proposed_action": "VACUUM FULL orders; -- Full remediation",
        "escalation_level": 0,
        "log": [f"Alert assessed: {severity}, timeout {timeout}s"],
    }

def simulate_approval_flow(state: EscalationState) -> dict:
    """Simulate the escalation timeline."""
    timeout = state["approval_timeout_seconds"]
    severity = state["severity"]

    print(f"\n  Escalation Timeline (simulated):")
    print(f"  {'='*45}")

    # Simulate: for P1, DBA doesn't respond, escalate
    if severity == "P1":
        print(f"  T+0s:    Alert sent to on-call DBA")
        print(f"  T+{timeout}s:  No response. ESCALATING to DBA manager.")
        print(f"  T+{timeout*2}s: No response. AUTO-EXECUTING safe default.")
        final_action = state["safe_default_action"]
        level = 3
    elif severity == "P2":
        print(f"  T+0s:    Alert sent to on-call DBA")
        print(f"  T+120s:  DBA responds: APPROVED")
        final_action = state["proposed_action"]
        level = 1
    else:
        print(f"  T+0s:    Alert sent to on-call DBA")
        print(f"  T+45s:   DBA responds: APPROVED")
        final_action = state["proposed_action"]
        level = 1

    return {
        "final_action": final_action,
        "escalation_level": level,
        "log": [f"Escalation level: {level}, action: {final_action}"],
    }

def execute_final(state: EscalationState) -> dict:
    action = state["final_action"]
    level = state["escalation_level"]
    level_names = {0: "none", 1: "DBA approved", 2: "Manager approved", 3: "Auto-executed (safe default)"}
    print(f"\n  [EXECUTE] {action}")
    print(f"  [level]   {level_names.get(level, 'unknown')}")
    return {"log": [f"Final execution: {action} (level {level})"]}

builder = StateGraph(EscalationState)
builder.add_node("assess", assess_alert)
builder.add_node("approval_flow", simulate_approval_flow)
builder.add_node("execute", execute_final)
builder.set_entry_point("assess")
builder.add_edge("assess", "approval_flow")
builder.add_edge("approval_flow", "execute")
builder.add_edge("execute", END)

graph = builder.compile()

print("Time-Boxed Approval with Escalation")
print("=" * 55)

# P1 alert - DBA doesn't respond, auto-executes safe default
print("\n--- P1: No Response -> Auto-Escalate ---")
result = graph.invoke({
    "alert": "Primary database unresponsive",
    "severity": "P1",
    "proposed_action": "", "safe_default_action": "",
    "approval_timeout_seconds": 0, "escalation_level": 0,
    "final_action": "", "log": [],
})

print(f"\n  Final action: {result['final_action']}")

# P3 alert - DBA responds in time
print(f"\n{'='*55}")
print("\n--- P3: DBA Responds -> Execute Proposed Fix ---")
result = graph.invoke({
    "alert": "Slow queries on pg-analytics",
    "severity": "P3",
    "proposed_action": "", "safe_default_action": "",
    "approval_timeout_seconds": 0, "escalation_level": 0,
    "final_action": "", "log": [],
})

print(f"\n  Final action: {result['final_action']}")

print(f"""
Escalation policy:
  P1: 5 min -> escalate -> 5 min -> auto-execute SAFE default
  P2: 10 min -> escalate -> 10 min -> auto-execute SAFE default
  P3: 30 min timeout
  P4: 24 hour timeout

The safe default is always a NON-DESTRUCTIVE action:
  CHECKPOINT, ANALYZE, pg_reload_conf, or log-only.
  Never VACUUM FULL, never pg_terminate_backend.

The key insight: time-boxed approval with safe defaults
means P1 alerts ALWAYS get some response, even if the
DBA is unavailable.
""")
PYEOF
```

Expected output (yours will differ):

```
Time-Boxed Approval with Escalation
=======================================================

--- P1: No Response -> Auto-Escalate ---
  [assess] Severity: P1
           Timeout:  300s before escalation
           Safe default: CHECKPOINT; -- Safe: forces a checkpoint...

  Escalation Timeline (simulated):
  =============================================
  T+0s:    Alert sent to on-call DBA
  T+300s:  No response. ESCALATING to DBA manager.
  T+600s:  No response. AUTO-EXECUTING safe default.
  ...
```

---

## What you learned

| Concept | DBA Analogy | LangGraph |
|---------|------------|-----------|
| Interrupt before | PREPARE TRANSACTION | `interrupt_before=["node"]` |
| Resume after approval | COMMIT PREPARED | `graph.invoke(None, config)` |
| Reject/modify | Code review changes | `graph.update_state()` |
| Multi-step approval | Maintenance plan steps | Interrupt before each step |
| Time-boxed approval | PagerDuty escalation | Timeout + safe default |
| Audit log | pg_audit | Annotated[list, operator.add] log |

Next: [Build 04 - Advanced LangGraph](04-advanced-langgraph.md) - subgraphs, parallel execution, and production patterns.
