# Survive 01: Agent Deadlock

## The Scenario

Two agents wait on each other's output. Agent A (Diagnosis) needs Agent B's
(Classifier) category label before it can run root-cause analysis. Agent B needs
Agent A's enriched metric summary before it can classify. Neither can proceed.
The entire pipeline freezes for 45 minutes until an outer timeout kills both.
Three P1 alerts go unprocessed. The on-call DBA gets no notification.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'

# This script simulates the deadlock scenario so you can see exactly what happened.
# No real API calls are made - we simulate the waiting behavior with flags.

# threading lets us run two functions at the same time
# Think of it like two parallel database sessions running simultaneously
import threading

# time lets us pause execution - like pg_sleep() in PostgreSQL
import time

print("=" * 60)
print("SCENARIO: Agent Deadlock")
print("=" * 60)

print("""
Your multi-agent alert pipeline:

  Monitor -> [Classifier <-> Diagnosis] -> Remediation

The deadlock:
  Classifier : "I need the enriched metric summary before I can classify."
  Diagnosis  : "I need the category label before I can enrich the metric."

  Both wait. Neither proceeds.

Timeline:
  09:00  Alert fires: high connection count on pg-primary
  09:00  Orchestrator starts Classifier and Diagnosis in parallel
  09:00  Classifier sends request to Diagnosis - then waits
  09:00  Diagnosis sends request to Classifier - then waits
  09:01  Both agents blocked, holding their thread locks
  09:15  Alert queue starts backing up (30 unprocessed alerts)
  09:30  Monitoring dashboard shows 0 alerts processed in 30 min
  09:45  Outer pipeline timeout fires - kills both agents
         45 minutes of alerts lost. 3 P1 alerts missed.
         On-call DBA receives no page.

Root cause: CIRCULAR DEPENDENCY
  Classifier depends on Diagnosis
  Diagnosis  depends on Classifier
  A -> B -> A  (cycle - same as a foreign key loop in DDL)
""")

# -----------------------------------------------------------------------
# DEMONSTRATE THE DEADLOCK
# -----------------------------------------------------------------------
# We use two threading.Event objects as "locks"
# An Event starts in the "not set" state (blocked)
# .wait() pauses until the Event is set - like waiting for a row lock to release

# classifier_done is set when Classifier finishes
# diagnosis_done is set when Diagnosis finishes
classifier_done = threading.Event()
diagnosis_done  = threading.Event()

# This flag lets us break the simulation after a timeout
deadlock_detected = threading.Event()


def classifier_agent():
    """
    Classifier is waiting for Diagnosis to finish before it can run.
    In production this was an API call with no timeout.
    """
    print("  [Classifier] Started. Waiting for Diagnosis output...")
    # .wait(timeout=5) waits up to 5 seconds for the event to be set
    # In the real incident this was wait() with NO timeout - it waited forever
    got_it = diagnosis_done.wait(timeout=5)
    if not got_it:
        print("  [Classifier] Still waiting for Diagnosis... (no timeout set)")
        deadlock_detected.set()
    else:
        print("  [Classifier] Got Diagnosis output. Classifying...")
        classifier_done.set()


def diagnosis_agent():
    """
    Diagnosis is waiting for Classifier to finish before it can run.
    In production this was also an API call with no timeout.
    """
    print("  [Diagnosis]  Started. Waiting for Classifier output...")
    got_it = classifier_done.wait(timeout=5)
    if not got_it:
        print("  [Diagnosis]  Still waiting for Classifier... (no timeout set)")
        deadlock_detected.set()
    else:
        print("  [Diagnosis]  Got Classifier output. Diagnosing...")
        diagnosis_done.set()


print("Starting both agents simultaneously...")
print()

# threading.Thread creates a background task
# target= is the function to run
# .start() launches it without blocking the main program
t1 = threading.Thread(target=classifier_agent)
t2 = threading.Thread(target=diagnosis_agent)

t1.start()
t2.start()

# .join() waits for the thread to finish before continuing
# timeout=8 means "wait at most 8 seconds, then give up"
t1.join(timeout=8)
t2.join(timeout=8)

print()
if deadlock_detected.is_set():
    print("DEADLOCK CONFIRMED: Both agents are waiting on each other.")
    print("In the real incident, this lasted 45 minutes before the outer")
    print("timeout killed both agents and triggered a pipeline restart.")
else:
    print("No deadlock detected.")

PYEOF
```

### Expected output (yours will differ):

```
============================================================
SCENARIO: Agent Deadlock
============================================================

[scenario text printed here]

Starting both agents simultaneously...

  [Classifier] Started. Waiting for Diagnosis output...
  [Diagnosis]  Started. Waiting for Classifier output...
  [Classifier] Still waiting for Diagnosis... (no timeout set)
  [Diagnosis]  Still waiting for Classifier... (no timeout set)

DEADLOCK CONFIRMED: Both agents are waiting on each other.
In the real incident, this lasted 45 minutes before the outer
timeout killed both agents and triggered a pipeline restart.
```

---

## Investigate

On your **Mac terminal**, find the circular dependency:

```bash
python3 << 'PYEOF'

# This script shows how to detect a circular dependency using a depth-first search.
# DBA analogy: this is the same algorithm PostgreSQL uses internally to detect
# deadlocks between session lock graphs.

print("Investigation: Finding the Circular Dependency")
print("=" * 55)

print("""
How the cycle was introduced:

BEFORE (working - linear pipeline):
  Monitor -> Classifier -> Diagnosis -> Remediation
  Classifier ran first. It produced a category label.
  Diagnosis consumed that label to decide which metrics to analyze.

AFTER the feature change (broken - cycle):
  A developer added "metric enrichment" to the Classifier.
  The Classifier now wanted Diagnosis to pre-analyze raw metrics
  before the Classifier ran, so it could classify more accurately.
  But Diagnosis still needed Classifier's category to run.
  Result: A waits for B, B waits for A.

This is identical to the deadlock PostgreSQL detects between sessions:
  Session A holds lock on table_orders, wants lock on table_payments
  Session B holds lock on table_payments, wants lock on table_orders
  PostgreSQL kills one session and logs: "deadlock detected"
  Our agents had no equivalent protection.
""")

# -----------------------------------------------------------------------
# DEPENDENCY GRAPH
# -----------------------------------------------------------------------
# We represent the pipeline as a dict where each key is an agent
# and the value is the list of agents it must wait for before running.
# This is a directed graph - the same data structure as a foreign key graph.

dependencies = {
    "monitor":     [],                              # no dependencies - runs first
    "classifier":  ["diagnosis"],                   # BUG: now depends on diagnosis
    "diagnosis":   ["classifier"],                  # depends on classifier (original)
    "remediation": ["classifier", "diagnosis"],     # downstream - needs both
}

print("Dependency graph (who each agent waits for):")
for agent, deps in dependencies.items():
    # ljust pads the string to 14 characters so the columns line up
    dep_str = deps if deps else ["(none)"]
    print(f"  {agent.ljust(14)} <- waits for: {dep_str}")


# -----------------------------------------------------------------------
# CYCLE DETECTION (depth-first search)
# -----------------------------------------------------------------------
# A depth-first search walks the graph node by node.
# If we ever arrive at a node we are already visiting in this path,
# we have found a cycle - a circular dependency.
# DBA analogy: imagine tracing FK relationships. If you follow the chain
# and arrive back at the table you started from, you have a circular reference.

# Type hints (: dict, -> list) tell you what the function expects and returns.
# graph: dict means "graph should be a dictionary"
# -> list means "this function returns a list"
# They don't change how the code runs - they're just labels for readability.
# DBA analogy: like column data types. They document what goes where.
def find_cycle(graph: dict) -> list:
    """
    Walk the dependency graph and return the first cycle found.
    Returns an empty list if no cycle exists.
    """
    # visited = nodes we have fully explored and confirmed cycle-free
    # in_path = nodes on the current exploration trail
    visited = set()
    in_path = set()

    def dfs(node: str, path: list) -> list:
        # If this node is already on our current path, we have found a cycle
        if node in in_path:
            # Return the cycle path including the repeated node at the end
            return path + [node]

        # If we have already fully explored this node, skip it
        if node in visited:
            return []

        # Mark this node as currently being explored
        in_path.add(node)
        path.append(node)

        # Recurse into each dependency
        for dep in graph.get(node, []):
            result = dfs(dep, path[:])   # path[:] creates a copy of the list
            if result:
                return result            # cycle found - bubble it up

        # Done exploring this node - remove from current path, mark fully visited
        in_path.discard(node)
        visited.add(node)
        return []

    # Try starting the search from each node in the graph
    for start_node in graph:
        cycle = dfs(start_node, [])
        if cycle:
            return cycle

    return []


cycle = find_cycle(dependencies)

print()
if cycle:
    # " -> ".join(cycle) turns ["classifier", "diagnosis", "classifier"] into
    # "classifier -> diagnosis -> classifier"
    print(f"CYCLE DETECTED: {' -> '.join(cycle)}")
    print()
    print("This means:")
    print("  classifier cannot run until diagnosis runs")
    print("  diagnosis cannot run until classifier runs")
    print("  Neither can ever run. Deadlock.")
else:
    print("No cycle found.")

PYEOF
```

### Expected output (yours will differ):

```
Investigation: Finding the Circular Dependency
=======================================================

[explanation text printed here]

Dependency graph (who each agent waits for):
  monitor        <- waits for: ['(none)']
  classifier     <- waits for: ['diagnosis']
  diagnosis      <- waits for: ['classifier']
  remediation    <- waits for: ['classifier', 'diagnosis']

CYCLE DETECTED: classifier -> diagnosis -> classifier

This means:
  classifier cannot run until diagnosis runs
  diagnosis cannot run until classifier runs
  Neither can ever run. Deadlock.
```

---

## The Fix

Three changes prevent this from ever happening again.

### Fix 1: Validate the dependency graph at startup

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 1: Run the cycle-detection check BEFORE starting the pipeline.
# If a cycle is found, refuse to start and print the offending path.
# DBA analogy: like PostgreSQL refusing to start if postgresql.conf has invalid values.

print("Fix 1: Startup Dependency Validation")
print("=" * 50)


def validate_pipeline(dependencies: dict) -> tuple:
    """
    Check the dependency graph for cycles before the pipeline starts.
    Returns (is_valid, cycle_path).
    If is_valid is False, cycle_path shows which agents form the loop.
    """
    visited = set()
    in_path = set()

    def dfs(node, path):
        if node in in_path:
            return path + [node]
        if node in visited:
            return []
        in_path.add(node)
        path.append(node)
        for dep in dependencies.get(node, []):
            result = dfs(dep, path[:])
            if result:
                return result
        in_path.discard(node)
        visited.add(node)
        return []

    for node in dependencies:
        cycle = dfs(node, [])
        if cycle:
            # Return False (not valid) and the cycle path
            return False, cycle

    # No cycle found - safe to start
    return True, []


def start_pipeline(dependencies: dict):
    """
    Validate before starting. Refuse if invalid.
    """
    is_valid, cycle = validate_pipeline(dependencies)

    if not is_valid:
        # This is the equivalent of PostgreSQL logging FATAL and refusing to start
        print(f"  PIPELINE REFUSED TO START")
        print(f"  Circular dependency detected: {' -> '.join(cycle)}")
        print(f"  Fix the dependency graph before restarting.")
        return

    print(f"  Dependency graph is valid. Pipeline starting.")


# Test with the broken config (the bug)
broken = {
    "monitor":     [],
    "classifier":  ["diagnosis"],    # bug - creates cycle
    "diagnosis":   ["classifier"],
    "remediation": ["classifier", "diagnosis"],
}

print("\nBroken config (with cycle):")
start_pipeline(broken)

# Test with the fixed config (linear pipeline)
fixed = {
    "monitor":     [],
    "classifier":  [],               # runs independently - no deps
    "diagnosis":   ["classifier"],   # uses classifier output
    "remediation": ["classifier", "diagnosis"],
}

print("\nFixed config (linear pipeline):")
start_pipeline(fixed)

PYEOF
```

### Expected output (yours will differ):

```
Fix 1: Startup Dependency Validation
==================================================

Broken config (with cycle):
  PIPELINE REFUSED TO START
  Circular dependency detected: classifier -> diagnosis -> classifier
  Fix the dependency graph before restarting.

Fixed config (linear pipeline):
  Dependency graph is valid. Pipeline starting.
```

### Fix 2: Add timeouts to every inter-agent call

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 2: Every call one agent makes to another must have a timeout.
# If the answer does not arrive in time, use a safe fallback value and continue.
# DBA analogy: like statement_timeout in PostgreSQL.
#   SET statement_timeout = '30s';
#   Any query that runs longer than 30 seconds is automatically cancelled.
# The pipeline keeps moving; no agent can block everything indefinitely.

import threading
import time

print("Fix 2: Inter-Agent Call Timeouts")
print("=" * 50)


def call_agent_with_timeout(agent_fn, args: tuple, timeout_seconds: int, fallback):
    """
    Call agent_fn(*args). If it does not return within timeout_seconds,
    return the fallback value instead.

    agent_fn     - the function to call (the agent)
    args         - the arguments to pass to it (as a tuple)
    timeout_seconds - how long to wait before giving up
    fallback     - the value to use if the agent times out
    """
    # result is a list with one slot - we use a list so the inner function can write to it
    # Python does not let a nested function assign to a plain variable in the outer scope,
    # but it can mutate (change the contents of) a list - this is a common Python pattern
    result = [None]
    exception = [None]

    def run():
        try:
            # Call the agent function with its arguments and store the result
            result[0] = agent_fn(*args)
        except Exception as e:
            exception[0] = e

    # Run the agent in a background thread so we can time it
    thread = threading.Thread(target=run)
    thread.start()

    # Wait up to timeout_seconds for the thread to finish
    thread.join(timeout=timeout_seconds)

    if thread.is_alive():
        # The thread is still running - it has exceeded the timeout
        print(f"  TIMEOUT: agent did not respond within {timeout_seconds}s. Using fallback.")
        return fallback

    if exception[0]:
        print(f"  ERROR in agent: {exception[0]}. Using fallback.")
        return fallback

    return result[0]


# -----------------------------------------------------------------------
# SIMULATED AGENTS
# -----------------------------------------------------------------------

def fast_classifier(metric: str) -> str:
    """Responds quickly - simulates a healthy agent."""
    time.sleep(0.5)    # 0.5 seconds - within the 5-second timeout
    return "CRITICAL"


def slow_diagnosis(metric: str) -> str:
    """Responds too slowly - simulates a hung agent."""
    time.sleep(10)     # 10 seconds - will exceed the 5-second timeout
    return "high_connections"


# -----------------------------------------------------------------------
# RUN THE CALLS WITH TIMEOUT PROTECTION
# -----------------------------------------------------------------------

metric = "active_connections=199, max_connections=200"

print(f"\nMetric: {metric}")
print()

# Call the fast agent - should succeed
print("Calling classifier agent (fast)...")
severity = call_agent_with_timeout(
    agent_fn=fast_classifier,
    args=(metric,),
    timeout_seconds=5,
    fallback="WARNING"    # safe default if timeout
)
print(f"  Classifier result: {severity}")

print()

# Call the slow agent - should timeout and use fallback
print("Calling diagnosis agent (slow - will timeout)...")
root_cause = call_agent_with_timeout(
    agent_fn=slow_diagnosis,
    args=(metric,),
    timeout_seconds=5,
    fallback="unknown - timed out"    # safe default if timeout
)
print(f"  Diagnosis result: {root_cause}")

print()
print("Pipeline continued despite the slow agent.")
print("The fallback value was used so downstream agents could keep running.")

PYEOF
```

### Expected output (yours will differ):

```
Fix 2: Inter-Agent Call Timeouts
==================================================

Metric: active_connections=199, max_connections=200

Calling classifier agent (fast)...
  Classifier result: CRITICAL

Calling diagnosis agent (slow - will timeout)...
  TIMEOUT: agent did not respond within 5s. Using fallback.
  Diagnosis result: unknown - timed out

Pipeline continued despite the slow agent.
The fallback value was used so downstream agents could keep running.
```

### Fix 3: Redesign the pipeline as a strict linear sequence

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 3: Remove the circular dependency by fixing the pipeline order.
# The Classifier no longer waits for Diagnosis.
# The Classifier runs first on raw metrics alone, produces a category,
# and then Diagnosis runs next using that category.
# Data flows in one direction only: forward.
# DBA analogy: like resolving a circular FK reference by introducing an intermediate table
# that breaks the cycle into two one-directional references.

print("Fix 3: Linear Pipeline (No Cycles)")
print("=" * 50)

print("""
BEFORE (broken - cycle):
  Monitor -> Classifier <-> Diagnosis -> Remediation
             (each waits on the other)

AFTER (fixed - linear):
  Monitor -> Classifier -> Diagnosis -> Remediation
  (each stage runs only after the previous one finishes)

The key change:
  Classifier was updated to work WITHOUT the enriched metric summary.
  It classifies based on the raw metric text alone.
  This is slightly less accurate but eliminates the deadlock entirely.
  Diagnosis then refines the analysis using the Classifier's category.

Design rule: in a multi-agent pipeline, dependencies must always
point forward. If you draw arrows showing which agent waits for which,
those arrows must never form a loop.
""")

# Represent the corrected pipeline as an ordered list of stages
# Each stage runs only after the previous one is done
pipeline_stages = [
    {"name": "monitor",     "depends_on": []},
    {"name": "classifier",  "depends_on": ["monitor"]},
    {"name": "diagnosis",   "depends_on": ["classifier"]},
    {"name": "remediation", "depends_on": ["classifier", "diagnosis"]},
]

print("Corrected pipeline execution order:")
print()

# Iterate through stages in order and simulate running each one
for stage in pipeline_stages:
    name = stage["name"]
    deps = stage["depends_on"]

    if not deps:
        print(f"  [{name.upper()}] Running (no dependencies)")
    else:
        # ", ".join(deps) turns ["classifier", "diagnosis"] into "classifier, diagnosis"
        print(f"  [{name.upper()}] Running (after: {', '.join(deps)})")

print()
print("All stages completed. No deadlock possible.")
print("Data flowed forward only: monitor -> classifier -> diagnosis -> remediation")

PYEOF
```

### Expected output (yours will differ):

```
Fix 3: Linear Pipeline (No Cycles)
==================================================

[explanation text printed here]

Corrected pipeline execution order:

  [MONITOR] Running (no dependencies)
  [CLASSIFIER] Running (after: monitor)
  [DIAGNOSIS] Running (after: classifier)
  [REMEDIATION] Running (after: classifier, diagnosis)

All stages completed. No deadlock possible.
Data flowed forward only: monitor -> classifier -> diagnosis -> remediation
```

---

## What You Learned

| Problem | Why It Caused the Incident | Fix |
|---------|---------------------------|-----|
| Circular dependency between agents | Both agents waited forever - neither could start | Validate the dependency graph at startup; refuse to run if a cycle is found |
| No timeout on inter-agent calls | One blocked agent froze the entire pipeline for 45 minutes | Set a timeout on every agent call; use a safe fallback value if it expires |
| No dependency validation at deploy time | The cycle was invisible until the pipeline ran in production | Check the dependency graph in CI/CD before every deployment |
| Parallel agents with mutual dependencies | Running agents at the same time is safe only when they are independent | Agents that share data must run in sequence, not in parallel |
| No deadlock monitoring | 45 minutes passed before anyone noticed | Alert when any agent has been waiting more than 30 seconds |
