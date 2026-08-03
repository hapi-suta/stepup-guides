# Survive 02: Agent Runs Dangerous SQL

## The Scenario

A bug in the permission system allows the remediation agent to skip the approval check for Tier 3 actions. The agent receives an alert about low buffer hit ratio and decides to "fix" it by running `ALTER SYSTEM SET shared_buffers = '1MB'` (destroying performance). While investigating a "cleanup" task, it also runs `TRUNCATE` on a table it misidentified as temporary.

The permission bug: someone changed `required_tier > self.tier_level` to `required_tier >= self.tier_level` during a refactor. A single-character typo promoted Tier 2 actions to run without approval, and Tier 3 actions to run with just a notification.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
import time

print("=" * 60)
print("SCENARIO: Agent Executes Dangerous SQL")
print("=" * 60)

print("""
Timeline:
  Monday 14:00 - Developer refactors permission check
  Monday 14:05 - Code review missed the one-character bug
  Monday 14:30 - Deploy to production
  Tuesday 03:00 - Agent detects low buffer cache hit ratio (82%)
  Tuesday 03:01 - Agent decides to reduce shared_buffers to "test"
  Tuesday 03:02 - Agent runs ALTER SYSTEM SET shared_buffers = '1MB'
  Tuesday 03:03 - Agent reloads config (pg_reload_conf)
  Tuesday 03:10 - Buffer cache hit ratio drops to 15%
  Tuesday 03:11 - Every query now hits disk. Response times 50x slower.
  Tuesday 03:15 - Agent sees "large temp table" and runs TRUNCATE
  Tuesday 03:16 - The "temp table" was actually audit_log (5 years of data)
  Tuesday 06:00 - On-call DBA wakes up to 847 alerts
""")

# -----------------------------------------------------------------------
# THE BUGGY PERMISSION SYSTEM
# -----------------------------------------------------------------------
class BuggyPermissionSystem:
    """
    This permission system has a one-character bug.
    """

    TIER_ACTIONS = {
        1: {"check_stats", "read_logs", "send_alert"},
        2: {"cancel_query", "run_vacuum", "set_parameter"},
        3: {"alter_system", "drop_object", "failover", "truncate_table",
            "reload_config"},
    }

    def __init__(self, agent_tier):
        self.agent_tier = agent_tier

    def check_permission(self, action):
        for tier, actions in self.TIER_ACTIONS.items():
            if action in actions:
                # BUG: should be > but is >=
                # This means tier 3 actions pass for tier 3 agents
                # WITHOUT requiring approval
                if tier >= self.agent_tier:   # <-- THE BUG: should be >
                    return True, "auto"        # <-- Should return "approve" for tier 3
                return True, "auto"
        return False, "denied"


class BuggyAgent:
    """Agent using the buggy permission system."""

    def __init__(self):
        self.perms = BuggyPermissionSystem(agent_tier=3)
        self.actions_taken = []

    def execute(self, action, params):
        allowed, approval_type = self.perms.check_permission(action)
        if allowed:
            # Bug: approval_type is always "auto" due to the permission bug
            self.actions_taken.append({
                "action": action,
                "params": params,
                "approval": approval_type,
                "timestamp": time.strftime("%H:%M:%S"),
            })
            return True, f"Executed {action} (approval: {approval_type})"
        return False, f"Denied: {action}"


# -----------------------------------------------------------------------
# SIMULATE THE DISASTER
# -----------------------------------------------------------------------
agent = BuggyAgent()

print("--- The Bug in Action ---\n")

# Agent's "diagnosis" of low buffer hit ratio
print("Agent reasoning: 'Buffer cache hit ratio is 82%. Normally 99%.'")
print("Agent reasoning: 'shared_buffers might be misconfigured.'")
print("Agent reasoning: 'Let me reduce it to test if that helps.'")
print("(This reasoning is WRONG - reducing shared_buffers makes it WORSE)")
print()

steps = [
    ("check_stats", {"query": "SHOW shared_buffers", "result": "4GB"}),
    ("alter_system", {"sql": "ALTER SYSTEM SET shared_buffers = '1MB'"}),
    ("reload_config", {"sql": "SELECT pg_reload_conf()"}),
    ("check_stats", {"query": "SHOW shared_buffers", "result": "1MB"}),
    ("truncate_table", {"sql": "TRUNCATE audit_log", "reason": "Identified as temp table"}),
]

for action, params in steps:
    success, msg = agent.execute(action, params)
    if action in ("alter_system", "reload_config", "truncate_table"):
        print(f"  DANGER >>> {msg}")
        print(f"            SQL: {params.get('sql', 'N/A')}")
    else:
        print(f"  {msg}")

print(f"\n--- Damage Assessment ---")
print(f"  shared_buffers changed: 4GB -> 1MB (99.97% reduction)")
print(f"  Buffer cache hit ratio: 99% -> 15%")
print(f"  Query response time: 5ms -> 250ms (50x slower)")
print(f"  audit_log table: 5 years of data GONE (150M rows)")
print(f"  Recovery time: 4+ hours (restore from backup)")

print(f"\n--- Root Cause ---")
print(f"  The permission check uses >= instead of >")
print(f"  This means ALL actions at the agent's tier level")
print(f"  execute automatically without approval.")
print(f"  Tier 3 actions (alter_system, truncate) ran as 'auto'")
print(f"  instead of requiring explicit DBA approval.")
PYEOF
```

Expected output (yours will differ):
```
--- The Bug in Action ---

Agent reasoning: 'Buffer cache hit ratio is 82%. Normally 99%.'
Agent reasoning: 'shared_buffers might be misconfigured.'
Agent reasoning: 'Let me reduce it to test if that helps.'
(This reasoning is WRONG - reducing shared_buffers makes it WORSE)

  Executed check_stats (approval: auto)
  DANGER >>> Executed alter_system (approval: auto)
            SQL: ALTER SYSTEM SET shared_buffers = '1MB'
  DANGER >>> Executed reload_config (approval: auto)
            SQL: SELECT pg_reload_conf()
  Executed check_stats (approval: auto)
  DANGER >>> Executed truncate_table (approval: auto)
            SQL: TRUNCATE audit_log

--- Damage Assessment ---
  shared_buffers changed: 4GB -> 1MB (99.97% reduction)
  Buffer cache hit ratio: 99% -> 15%
  Query response time: 5ms -> 250ms (50x slower)
  audit_log table: 5 years of data GONE (150M rows)
  Recovery time: 4+ hours (restore from backup)

--- Root Cause ---
  The permission check uses >= instead of >
  This means ALL actions at the agent's tier level
  execute automatically without approval.
  Tier 3 actions (alter_system, truncate) ran as 'auto'
  instead of requiring explicit DBA approval.
```

---

## Your Mission

Fix the permission system so that:

1. Tier 3 actions ALWAYS require explicit approval (never auto-execute)
2. The SQL safety checker blocks `ALTER SYSTEM` and `TRUNCATE` independently of permissions
3. Parameter changes have sanity checks (shared_buffers can never be set below 128MB)
4. A confirmation step validates the change BEFORE and AFTER execution

---

## The Fix

On your **Mac terminal**, run the hardened version:

```bash
python3 << 'PYEOF'
import re
import time

print("=" * 60)
print("FIX: Hardened Permission System with Defense in Depth")
print("=" * 60)

# -----------------------------------------------------------------------
# Layer 1: Fixed Permission System
# -----------------------------------------------------------------------
class FixedPermissionSystem:
    """
    Permission system with the bug fixed AND additional safeguards.
    """

    TIER_ACTIONS = {
        1: {"check_stats", "read_logs", "send_alert"},
        2: {"cancel_query", "run_vacuum", "set_parameter"},
        3: {"alter_system", "drop_object", "failover", "truncate_table",
            "reload_config"},
    }

    TIER_APPROVAL = {
        1: "auto",       # Execute immediately
        2: "notify",     # Execute and notify DBA
        3: "approve",    # Require DBA approval FIRST
    }

    def __init__(self, agent_tier):
        self.agent_tier = agent_tier

    def check_permission(self, action):
        for tier, actions in self.TIER_ACTIONS.items():
            if action in actions:
                # FIXED: Use > (not >=) to check if agent has sufficient tier
                if tier > self.agent_tier:
                    return False, "denied"
                # Return the CORRECT approval type for the action's tier
                approval = self.TIER_APPROVAL[tier]
                return True, approval
        return False, "unknown_action"


# -----------------------------------------------------------------------
# Layer 2: SQL Safety Checker (independent of permissions)
# -----------------------------------------------------------------------
class SQLSafetyChecker:
    """Even if permissions pass, dangerous SQL is blocked."""

    BLOCKED_PATTERNS = [
        (r"\bALTER\s+SYSTEM\b", "ALTER SYSTEM blocked"),
        (r"\bTRUNCATE\b", "TRUNCATE blocked"),
        (r"\bDROP\s+(TABLE|DATABASE)\b", "DROP blocked"),
    ]

    @classmethod
    def check(cls, sql):
        for pattern, reason in cls.BLOCKED_PATTERNS:
            if re.search(pattern, sql, re.IGNORECASE):
                return False, reason
        return True, "SQL is safe"


# -----------------------------------------------------------------------
# Layer 3: Parameter Sanity Checker
# -----------------------------------------------------------------------
class ParameterSanityChecker:
    """
    Validate PostgreSQL parameter values before applying them.

    DBA analogy: This is like CHECK constraints on postgresql.conf.
    PostgreSQL already does some of this (e.g., shared_buffers
    minimum is 128kB), but the agent needs additional guardrails.
    """

    PARAMETER_RULES = {
        "shared_buffers": {
            "min": "128MB",
            "min_bytes": 128 * 1024 * 1024,
            "max": "64GB",
            "max_bytes": 64 * 1024 * 1024 * 1024,
            "requires_restart": True,
        },
        "work_mem": {
            "min": "1MB",
            "min_bytes": 1 * 1024 * 1024,
            "max": "2GB",
            "max_bytes": 2 * 1024 * 1024 * 1024,
            "requires_restart": False,
        },
        "maintenance_work_mem": {
            "min": "16MB",
            "min_bytes": 16 * 1024 * 1024,
            "max": "4GB",
            "max_bytes": 4 * 1024 * 1024 * 1024,
            "requires_restart": False,
        },
    }

    @classmethod
    def parse_size(cls, value_str):
        """Parse PostgreSQL size string to bytes."""
        value_str = value_str.strip().upper()
        multipliers = {"KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
        for suffix, mult in multipliers.items():
            if value_str.endswith(suffix):
                return int(value_str[:-len(suffix)]) * mult
        return int(value_str)  # Assume bytes if no suffix

    @classmethod
    def validate(cls, param_name, new_value):
        if param_name not in cls.PARAMETER_RULES:
            return False, f"Unknown parameter: {param_name}"

        rules = cls.PARAMETER_RULES[param_name]
        try:
            new_bytes = cls.parse_size(new_value)
        except ValueError:
            return False, f"Invalid value format: {new_value}"

        if new_bytes < rules["min_bytes"]:
            return False, (f"{param_name} = {new_value} is below minimum "
                          f"({rules['min']}). This would destroy performance.")
        if new_bytes > rules["max_bytes"]:
            return False, (f"{param_name} = {new_value} exceeds maximum "
                          f"({rules['max']}). Server would crash on restart.")

        warnings = []
        if rules.get("requires_restart"):
            warnings.append("Requires server restart to take effect")

        return True, f"Value {new_value} is within safe range. " + "; ".join(warnings)


# -----------------------------------------------------------------------
# Layer 4: Hardened Agent
# -----------------------------------------------------------------------
class HardenedAgent:
    def __init__(self):
        self.perms = FixedPermissionSystem(agent_tier=3)
        self.audit_log = []

    def _audit(self, action, result, detail):
        self.audit_log.append({
            "ts": time.strftime("%H:%M:%S"),
            "action": action,
            "result": result,
            "detail": str(detail)[:80],
        })

    def execute(self, action, params):
        """
        Multi-layer validation:
        1. Permission check (is the agent allowed?)
        2. SQL safety check (is the SQL dangerous?)
        3. Parameter sanity check (are the values reasonable?)
        4. Approval check (does this need human approval?)
        """

        # Layer 1: Permission check
        allowed, approval_type = self.perms.check_permission(action)
        if not allowed:
            self._audit(action, "denied", "Permission denied")
            return False, f"DENIED: No permission for {action}"

        # Layer 2: SQL safety check
        sql = params.get("sql", "")
        if sql:
            sql_safe, sql_reason = SQLSafetyChecker.check(sql)
            if not sql_safe:
                self._audit(action, "sql_blocked", sql_reason)
                return False, f"SQL BLOCKED: {sql_reason} | SQL: {sql}"

        # Layer 3: Parameter sanity check
        if action == "alter_system" and "param" in params:
            param_safe, param_reason = ParameterSanityChecker.validate(
                params["param"], params.get("value", "")
            )
            if not param_safe:
                self._audit(action, "param_blocked", param_reason)
                return False, f"PARAM BLOCKED: {param_reason}"

        # Layer 4: Approval check
        if approval_type == "approve":
            self._audit(action, "needs_approval", f"Waiting for DBA approval")
            return False, f"NEEDS APPROVAL: {action} requires explicit DBA approval before execution"

        if approval_type == "notify":
            self._audit(action, "executed_notify", params)
            return True, f"EXECUTED (DBA notified): {action}"

        self._audit(action, "executed_auto", params)
        return True, f"EXECUTED (auto): {action}"


# -----------------------------------------------------------------------
# TEST THE FIX with the same attack scenario
# -----------------------------------------------------------------------
agent = HardenedAgent()

print("\n--- Replay the Disaster with Hardened Agent ---\n")

# Same steps the buggy agent took
steps = [
    ("check_stats", {"query": "SHOW shared_buffers"}),
    ("alter_system", {
        "sql": "ALTER SYSTEM SET shared_buffers = '1MB'",
        "param": "shared_buffers",
        "value": "1MB"
    }),
    ("reload_config", {"sql": "SELECT pg_reload_conf()"}),
    ("truncate_table", {"sql": "TRUNCATE audit_log"}),
]

for action, params in steps:
    success, msg = agent.execute(action, params)
    status = "OK " if success else "BLOCKED"
    print(f"  [{status}] {msg}")

# Test that REASONABLE changes also need approval
print("\n--- Even reasonable Tier 3 changes need approval ---")
reasonable_steps = [
    ("alter_system", {
        "param": "shared_buffers",
        "value": "8GB",
    }),
    ("alter_system", {
        "param": "work_mem",
        "value": "64MB",
    }),
]

for action, params in reasonable_steps:
    success, msg = agent.execute(action, params)
    print(f"  {msg}")

print(f"\n--- Audit Trail ---")
for entry in agent.audit_log:
    print(f"  {entry['ts']} | {entry['action']:<18} | {entry['result']:<18} | {entry['detail'][:40]}")

# Count results
blocked = sum(1 for e in agent.audit_log if "blocked" in e["result"] or "denied" in e["result"])
needs_approval = sum(1 for e in agent.audit_log if e["result"] == "needs_approval")
auto_ok = sum(1 for e in agent.audit_log if "executed" in e["result"])

print(f"\n--- Summary ---")
print(f"  Actions blocked by safety checks: {blocked}")
print(f"  Actions requiring approval: {needs_approval}")
print(f"  Actions auto-executed (Tier 1 only): {auto_ok}")

if blocked >= 2 and needs_approval >= 2:
    print(f"\n  PASS: Dangerous actions blocked, approval enforced!")
else:
    print(f"\n  FAIL: Some dangerous actions got through")
PYEOF
```

Expected output (yours will differ):
```
--- Replay the Disaster with Hardened Agent ---

  [OK ] EXECUTED (auto): check_stats
  [BLOCKED] SQL BLOCKED: ALTER SYSTEM blocked | SQL: ALTER SYSTEM SET shared_buffers = '1MB'
  [BLOCKED] NEEDS APPROVAL: reload_config requires explicit DBA approval before execution
  [BLOCKED] SQL BLOCKED: TRUNCATE blocked | SQL: TRUNCATE audit_log

--- Even reasonable Tier 3 changes need approval ---
  NEEDS APPROVAL: alter_system requires explicit DBA approval before execution
  NEEDS APPROVAL: alter_system requires explicit DBA approval before execution

--- Audit Trail ---
  10:00:00 | check_stats        | executed_auto      | {'query': 'SHOW shared_buffers'}
  10:00:00 | alter_system       | sql_blocked        | ALTER SYSTEM blocked
  10:00:00 | reload_config      | needs_approval     | Waiting for DBA approval
  10:00:00 | truncate_table     | sql_blocked        | TRUNCATE blocked
  10:00:00 | alter_system       | needs_approval     | Waiting for DBA approval
  10:00:00 | alter_system       | needs_approval     | Waiting for DBA approval

--- Summary ---
  Actions blocked by safety checks: 2
  Actions requiring approval: 3
  Actions auto-executed (Tier 1 only): 1

  PASS: Dangerous actions blocked, approval enforced!
```

---

## Validation

On your **Mac terminal**, run the validation:

```bash
python3 << 'PYEOF'
import re

print("Validation: Defense in Depth Check")
print("=" * 50)

# Layer 1: Permission bug is fixed
class FixedPerms:
    TIERS = {1: {"check_stats"}, 2: {"cancel_query"}, 3: {"alter_system", "failover"}}
    APPROVAL = {1: "auto", 2: "notify", 3: "approve"}

    def check(self, agent_tier, action):
        for tier, actions in self.TIERS.items():
            if action in actions:
                if tier > agent_tier:
                    return "denied"
                return self.APPROVAL[tier]
        return "denied"

perms = FixedPerms()
tests = [
    (3, "check_stats", "auto"),
    (3, "cancel_query", "notify"),
    (3, "alter_system", "approve"),    # MUST be "approve", not "auto"
    (2, "alter_system", "denied"),
    (1, "cancel_query", "denied"),
]

print("\nLayer 1: Permission checks")
l1_pass = True
for tier, action, expected in tests:
    result = perms.check(tier, action)
    ok = result == expected
    if not ok:
        l1_pass = False
    print(f"  Tier {tier} + {action}: {result} (expected {expected}) {'PASS' if ok else 'FAIL'}")

# Layer 2: SQL safety
print("\nLayer 2: SQL safety checks")
blocked_sqls = [
    "ALTER SYSTEM SET shared_buffers = '1MB'",
    "TRUNCATE audit_log",
    "DROP TABLE customers",
]
safe_sqls = [
    "SELECT * FROM pg_stat_activity",
    "SHOW shared_buffers",
]

l2_pass = True
for sql in blocked_sqls:
    blocked = bool(re.search(r"\b(ALTER\s+SYSTEM|TRUNCATE|DROP\s+(TABLE|DATABASE))\b", sql, re.IGNORECASE))
    if not blocked:
        l2_pass = False
    print(f"  {sql[:40]:40s} -> {'BLOCKED' if blocked else 'ALLOWED'} {'PASS' if blocked else 'FAIL'}")

for sql in safe_sqls:
    blocked = bool(re.search(r"\b(ALTER\s+SYSTEM|TRUNCATE|DROP\s+(TABLE|DATABASE))\b", sql, re.IGNORECASE))
    if blocked:
        l2_pass = False
    print(f"  {sql[:40]:40s} -> {'BLOCKED' if blocked else 'ALLOWED'} {'PASS' if not blocked else 'FAIL'}")

# Layer 3: Parameter sanity
print("\nLayer 3: Parameter sanity checks")
l3_pass = True
param_tests = [
    ("shared_buffers", "1MB", False),      # Below minimum
    ("shared_buffers", "128MB", True),     # At minimum
    ("shared_buffers", "8GB", True),       # Normal
    ("shared_buffers", "100GB", False),    # Above maximum
]

for param, value, should_pass in param_tests:
    value_str = value.upper()
    multipliers = {"KB": 1024, "MB": 1024**2, "GB": 1024**3}
    val_bytes = 0
    for suffix, mult in multipliers.items():
        if value_str.endswith(suffix):
            val_bytes = int(value_str[:-len(suffix)]) * mult
            break
    min_bytes = 128 * 1024 * 1024
    max_bytes = 64 * 1024 * 1024 * 1024
    is_safe = min_bytes <= val_bytes <= max_bytes
    ok = is_safe == should_pass
    if not ok:
        l3_pass = False
    print(f"  {param} = {value:>6s} -> {'SAFE' if is_safe else 'BLOCKED':7s} {'PASS' if ok else 'FAIL'}")

print(f"\n{'=' * 50}")
all_pass = l1_pass and l2_pass and l3_pass
print(f"Overall: {'ALL LAYERS PASS' if all_pass else 'SOME LAYERS FAILED'}")
PYEOF
```

Expected output:
```
Validation: Defense in Depth Check
==================================================

Layer 1: Permission checks
  Tier 3 + check_stats: auto (expected auto) PASS
  Tier 3 + cancel_query: notify (expected notify) PASS
  Tier 3 + alter_system: approve (expected approve) PASS
  Tier 2 + alter_system: denied (expected denied) PASS
  Tier 1 + cancel_query: denied (expected denied) PASS

Layer 2: SQL safety checks
  ALTER SYSTEM SET shared_buffers = '1MB'    -> BLOCKED PASS
  TRUNCATE audit_log                         -> BLOCKED PASS
  DROP TABLE customers                       -> BLOCKED PASS
  SELECT * FROM pg_stat_activity             -> ALLOWED PASS
  SHOW shared_buffers                        -> ALLOWED PASS

Layer 3: Parameter sanity checks
  shared_buffers =    1MB -> BLOCKED PASS
  shared_buffers =  128MB -> SAFE    PASS
  shared_buffers =    8GB -> SAFE    PASS
  shared_buffers =  100GB -> BLOCKED PASS

==================================================
Overall: ALL LAYERS PASS
```

---

## Key Takeaways

1. **One-character bugs can be catastrophic.** `>=` vs `>` is the difference between "ask the DBA" and "destroy the database."
2. **Defense in depth.** Never rely on a single check. Layer permissions + SQL validation + parameter sanity.
3. **Test your permission system.** Write explicit tests that verify Tier 3 actions ALWAYS require approval.
4. **Parameter guardrails.** Agents should never be able to set `shared_buffers = 1MB` or `max_connections = 1`.
5. **Audit everything.** When the disaster happens, the audit trail tells you exactly what went wrong.

DBA analogy: This is why PostgreSQL has multiple layers of security - `pg_hba.conf` for connections, `GRANT/REVOKE` for permissions, `row_security` for data access, and `log_statement` for auditing. No single layer is sufficient. Your agent needs the same defense in depth.
