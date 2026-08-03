# Runbook: Conditional Edge Wrong Route

P1 alerts are routed to the low-priority path. Critical alerts get delayed 24+ hours instead of immediate escalation. The on-call DBA is never paged.

---

## Symptoms

- No P1 escalations happening despite critical alerts firing
- All alerts routed to "low_priority" regardless of severity
- On-call DBA never receives pages
- Monitoring dashboard shows 0 escalations in the last 24 hours

---

## Step 1. Reproduce and identify the bug

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# DIAGNOSE: Why are all alerts going to low_priority?
#
# Strategy: trace the routing function with debug output.
# Check what type severity is and what the comparison does.
#
# DBA analogy: EXPLAIN ANALYZE to see where the query plan
# goes wrong. We're doing the same for the routing logic.
# ============================================================

print("Diagnosis: Tracing the Routing Bug")
print("=" * 55)

# Simulate what the classify function returns
severity_from_classify = 1  # integer
print(f"classify() returned severity = {severity_from_classify}")
print(f"Type: {type(severity_from_classify).__name__}")

# Simulate what route_by_severity compares against
print(f"\nroute_by_severity() comparisons:")
print(f"  severity == 'P1' -> {severity_from_classify == 'P1'}")
print(f"  severity == 'P2' -> {severity_from_classify == 'P2'}")
print(f"  else             -> True (this always runs)")

print(f"""
ROOT CAUSE FOUND:
  classify() returns: severity = 1           (integer)
  route_by_severity() checks: severity == "P1"  (string)

  1 == "P1" is False in Python.
  Python does NOT raise an error for this comparison.
  It just returns False silently.

  This is a TYPE MISMATCH bug.

DBA analogy:
  SELECT * FROM alerts WHERE severity = 'P1';
  But the column is INTEGER, storing 1, 2, 3, 4.
  In PostgreSQL, this would FAIL or implicitly cast.
  In Python, it silently returns False. Much worse.
""")
PYEOF
```

---

## Step 2. Fix the routing function

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# FIX: Two approaches to fix the type mismatch
#
# Option A: Fix classify() to return strings ("P1", "P2")
# Option B: Fix route_by_severity() to compare integers
#
# Best practice: Option A + type validation
#
# DBA analogy: fix the data type at the source.
#   ALTER TABLE alerts ALTER COLUMN severity TYPE text;
#   Don't hack the WHERE clause - fix the column type.
# ============================================================

from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
import operator

class AlertState(TypedDict):
    alert_text: str
    severity: str       # FIXED: explicitly typed as str
    category: str
    route_taken: str
    response: str
    response_time: str
    log: Annotated[list, operator.add]

def classify_fixed(state: AlertState) -> dict:
    """FIXED: Returns severity as string, not integer."""
    text = state["alert_text"].lower()

    if "replication" in text or "lag" in text:
        category = "replication"
    elif "disk" in text or "full" in text:
        category = "storage"
    elif "cpu" in text or "slow" in text:
        category = "performance"
    else:
        category = "general"

    # FIXED: Return string "P1", not integer 1
    if any(kw in text for kw in ["down", "crash", "data loss", "100%", "corruption"]):
        severity = "P1"
    elif any(kw in text for kw in ["95%", "98%", "critical"]):
        severity = "P1"
    elif any(kw in text for kw in ["high", "increasing", "lag"]):
        severity = "P2"
    else:
        severity = "P4"

    # ADDED: Type validation - catch this bug early
    assert isinstance(severity, str) and severity.startswith("P"), \
        f"Bug: severity must be a string like 'P1', got {type(severity).__name__}: {severity}"

    print(f"  [classify] category={category}, severity={severity} (type: {type(severity).__name__})")
    return {"category": category, "severity": severity}

def route_by_severity_fixed(state: AlertState) -> str:
    """FIXED: Added type check and logging."""
    severity = state["severity"]

    # ADDED: Defensive type check
    if not isinstance(severity, str):
        print(f"  [WARN] severity is {type(severity).__name__}, expected str. Converting.")
        severity = f"P{severity}"

    if severity == "P1":
        return "escalate"
    elif severity in ("P2", "P3"):
        return "standard"
    else:
        return "low_priority"

def escalate(state: AlertState) -> dict:
    print(f"  [ESCALATE] P1 CRITICAL - paging DBA immediately!")
    return {
        "route_taken": "escalate",
        "response": "ESCALATED: On-call DBA paged.",
        "response_time": "< 1 minute",
        "log": ["ESCALATED"],
    }

def standard(state: AlertState) -> dict:
    print(f"  [standard] Running diagnostics")
    return {
        "route_taken": "standard",
        "response": "STANDARD: Diagnostics running.",
        "response_time": "5-15 minutes",
        "log": ["STANDARD"],
    }

def low_priority(state: AlertState) -> dict:
    print(f"  [low_priority] Logging for review")
    return {
        "route_taken": "low_priority",
        "response": "LOGGED: Next business day.",
        "response_time": "24+ hours",
        "log": ["LOW PRIORITY"],
    }

builder = StateGraph(AlertState)
builder.add_node("classify", classify_fixed)
builder.add_node("escalate", escalate)
builder.add_node("standard", standard)
builder.add_node("low_priority", low_priority)

builder.set_entry_point("classify")
builder.add_conditional_edges(
    "classify",
    route_by_severity_fixed,
    {
        "escalate": "escalate",
        "standard": "standard",
        "low_priority": "low_priority",
    }
)
builder.add_edge("escalate", END)
builder.add_edge("standard", END)
builder.add_edge("low_priority", END)

graph = builder.compile()

print("FIXED Conditional Edge Routing")
print("=" * 55)

test_alerts = [
    ("PRIMARY DATABASE IS DOWN - possible data loss!!", "escalate"),
    ("Disk usage at 98% CRITICAL on pg-primary", "escalate"),
    ("Replication lag increasing on standby-2", "standard"),
    ("Routine checkpoint completed", "low_priority"),
]

all_correct = True
for alert, expected_route in test_alerts:
    print(f"\nAlert: {alert}")
    print("-" * 55)
    result = graph.invoke({
        "alert_text": alert,
        "severity": "", "category": "", "route_taken": "",
        "response": "", "response_time": "", "log": [],
    })

    actual = result["route_taken"]
    match = "PASS" if actual == expected_route else "FAIL"
    if actual != expected_route:
        all_correct = False
    print(f"  Route: {actual} (expected: {expected_route}) [{match}]")
    print(f"  Response time: {result['response_time']}")

print(f"\n{'=' * 55}")
if all_correct:
    print("ALL ROUTING TESTS PASSED")
else:
    print("SOME ROUTING TESTS FAILED - review the fix")
print(f"{'=' * 55}")
PYEOF
```

Expected output (yours will differ):

```
FIXED Conditional Edge Routing
=======================================================

Alert: PRIMARY DATABASE IS DOWN - possible data loss!!
-------------------------------------------------------
  [classify] category=general, severity=P1 (type: str)
  [ESCALATE] P1 CRITICAL - paging DBA immediately!
  Route: escalate (expected: escalate) [PASS]
  Response time: < 1 minute
...
ALL ROUTING TESTS PASSED
```

---

## Step 3. Add routing tests to prevent regressions

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# PREVENTION: Add routing tests
#
# Test every routing path with known inputs.
# Run these tests before every deployment.
#
# DBA analogy: before applying a pg_hba.conf change,
# test that the right users can connect and the wrong
# ones are rejected. Don't find out in production.
# ============================================================

print("Routing Test Suite")
print("=" * 55)

def route_by_severity(severity: str) -> str:
    """The routing function under test."""
    if not isinstance(severity, str):
        raise TypeError(f"severity must be str, got {type(severity).__name__}: {severity}")
    if severity == "P1":
        return "escalate"
    elif severity in ("P2", "P3"):
        return "standard"
    else:
        return "low_priority"

# Test cases: (input, expected_output)
test_cases = [
    # Normal cases
    ("P1", "escalate"),
    ("P2", "standard"),
    ("P3", "standard"),
    ("P4", "low_priority"),

    # Edge cases
    ("P0", "low_priority"),   # Unknown severity -> low priority
    ("P5", "low_priority"),   # Unknown severity -> low priority
]

passed = 0
failed = 0

print("\nTest 1: Correct type (string) routing")
print("-" * 45)
for severity, expected in test_cases:
    actual = route_by_severity(severity)
    status = "PASS" if actual == expected else "FAIL"
    if actual == expected:
        passed += 1
    else:
        failed += 1
    print(f"  [{status}] severity='{severity}' -> {actual} (expected {expected})")

# Test 2: Wrong type should raise TypeError
print(f"\nTest 2: Wrong type detection")
print("-" * 45)
wrong_types = [1, 2, 3, 4, None, True, 1.0]
for bad_input in wrong_types:
    try:
        route_by_severity(bad_input)
        print(f"  [FAIL] severity={bad_input} ({type(bad_input).__name__}) - no error raised")
        failed += 1
    except TypeError as e:
        print(f"  [PASS] severity={bad_input} ({type(bad_input).__name__}) - TypeError raised")
        passed += 1

# Test 3: Routing coverage - every path is reachable
print(f"\nTest 3: All routes are reachable")
print("-" * 45)
routes_hit = set()
for severity in ["P1", "P2", "P3", "P4"]:
    route = route_by_severity(severity)
    routes_hit.add(route)

expected_routes = {"escalate", "standard", "low_priority"}
all_reachable = routes_hit == expected_routes
status = "PASS" if all_reachable else "FAIL"
if all_reachable:
    passed += 1
else:
    failed += 1
print(f"  [{status}] Routes hit: {routes_hit}")
print(f"         Expected:   {expected_routes}")

print(f"\n{'=' * 55}")
print(f"Results: {passed} passed, {failed} failed")
if failed == 0:
    print("ALL ROUTING TESTS PASSED")
else:
    print(f"WARNING: {failed} test(s) failed")
print(f"{'=' * 55}")

print(f"""
Prevention checklist:
  1. TYPE HINTS: Use str for severity in TypedDict, not object
  2. ASSERTIONS: assert isinstance(severity, str) in classify()
  3. DEFENSIVE: Convert types in route function if wrong
  4. TESTS: Test every routing path with known inputs
  5. COVERAGE: Verify all routes are reachable
  6. CI/CD: Run routing tests before every deployment

DBA parallel:
  Before changing pg_hba.conf:
    - Test that postgres can still connect
    - Test that app users can still connect
    - Test that unauthorized users are rejected
    - Only then reload
  Same discipline for routing logic.
""")
PYEOF
```

---

## Key Takeaways

| Bug Pattern | DBA Parallel | Prevention |
|-------------|-------------|------------|
| Type mismatch (int vs str) | Wrong column type in WHERE | Type hints + assertions |
| Silent comparison failure | Implicit type cast | Explicit type checking |
| All routes go to default | WHERE clause matches no rows | Test every routing path |
| No error raised | Query returns empty silently | Raise TypeError on bad input |
| Untested routing logic | Untested pg_hba.conf | Route coverage tests |
