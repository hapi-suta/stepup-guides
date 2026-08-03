# Survive 02: Rogue Agent

## The Scenario

The remediation agent starts auto-executing medium-risk actions without approval.
A config file was copied from staging to production by mistake. The config set the
agent's safety level to `auto_execute_all` instead of `recommend_only`. The agent
did exactly what it was configured to do - in the wrong environment. It killed 12
active queries in 30 seconds. Three critical reports that were mid-generation are
gone. Two ETL jobs that had been running for hours must be restarted from scratch.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'

# This script simulates what the rogue agent did.
# We use a Python list as a mock "pg_stat_activity" table.
# The agent iterates the list and kills anything above its threshold.

# datetime lets us generate timestamps - like PostgreSQL's NOW()
from datetime import datetime, timedelta

print("=" * 60)
print("SCENARIO: Rogue Remediation Agent")
print("=" * 60)

print("""
Your multi-agent system runs in production with this config:

  remediation_agent:
    mode: recommend_only      <- correct for production
    min_query_duration_sec: 1800

On Tuesday, DevOps updates the staging config for load testing:

  remediation_agent:
    mode: auto_execute_all    <- OK for staging, NEVER for production
    min_query_duration_sec: 300

On Wednesday, DevOps runs this command to copy a different setting:
  cp staging/agent_config.yaml production/agent_config.yaml

The safety mode was in the same file as the other setting.
The agent restarts with the new production config.
Nobody notices until Thursday morning.
""")

# -----------------------------------------------------------------------
# MOCK pg_stat_activity
# -----------------------------------------------------------------------
# Each dict represents one row from pg_stat_activity.
# Keys match the real PostgreSQL column names so this looks familiar.

now = datetime.now()

pg_stat_activity = [
    # (pid, application_name, state, query_start, query_preview)
    {"pid": 12341, "application_name": "annual_finance_report",  "state": "active", "query_start": now - timedelta(minutes=62),  "query": "SELECT * FROM finance.gl_entries WHERE fiscal_year = 2025..."},
    {"pid": 12342, "application_name": "etl_nightly_load",       "state": "active", "query_start": now - timedelta(hours=3, minutes=14), "query": "INSERT INTO dw.fact_sales SELECT ..."},
    {"pid": 12343, "application_name": "quarterly_audit_report", "state": "active", "query_start": now - timedelta(minutes=55),  "query": "SELECT * FROM audit.transactions JOIN ..."},
    {"pid": 12344, "application_name": "psql",                   "state": "idle",   "query_start": now - timedelta(minutes=2),   "query": "SELECT 1"},
    {"pid": 12345, "application_name": "etl_customer_sync",      "state": "active", "query_start": now - timedelta(hours=2),     "query": "UPDATE customers SET last_seen = ..."},
    {"pid": 12346, "application_name": "pgbouncer",              "state": "active", "query_start": now - timedelta(seconds=5),   "query": "BEGIN"},
    {"pid": 12347, "application_name": "annual_hr_report",       "state": "active", "query_start": now - timedelta(minutes=47),  "query": "SELECT * FROM hr.headcount_history ..."},
    {"pid": 12348, "application_name": "psql",                   "state": "idle",   "query_start": now - timedelta(minutes=1),   "query": "SELECT version()"},
]

# -----------------------------------------------------------------------
# ROGUE AGENT BEHAVIOR
# -----------------------------------------------------------------------
# In auto_execute_all mode, the agent kills any query running longer than
# min_query_duration_sec - without checking the application name,
# without asking for approval, and without any rate limiting.

class RemediationAgent:
    def __init__(self, mode: str, min_duration_sec: int):
        # Store the config values - no safety validation at this point (that is the bug)
        self.mode             = mode
        self.min_duration_sec = min_duration_sec
        self.kill_log         = []

    def _duration_seconds(self, query_start) -> float:
        # Calculate how long the query has been running
        # Same as: EXTRACT(EPOCH FROM NOW() - query_start)
        return (datetime.now() - query_start).total_seconds()

    def process(self, stat_activity: list):
        killed = []

        for row in stat_activity:
            # Skip idle sessions - nothing to kill
            if row["state"] == "idle":
                continue

            duration = self._duration_seconds(row["query_start"])

            # In auto_execute_all mode, any long-running query is terminated
            if self.mode == "auto_execute_all" and duration > self.min_duration_sec:
                killed.append({
                    "pid":              row["pid"],
                    "application":      row["application_name"],
                    "running_for_sec":  int(duration),
                    "killed_at":        datetime.now().isoformat(),
                    "action":           f"SELECT pg_terminate_backend({row['pid']})"
                })

            elif self.mode == "recommend_only":
                # Safe mode - only log, never touch
                if duration > self.min_duration_sec:
                    print(f"  RECOMMEND: review pid {row['pid']} ({row['application_name']}, "
                          f"{int(duration)}s)")

        return killed


# -----------------------------------------------------------------------
# RUN IN THE WRONG MODE
# -----------------------------------------------------------------------

print("Agent starting with PRODUCTION config (accidentally set to auto_execute_all)...")
print()

rogue_agent = RemediationAgent(mode="auto_execute_all", min_duration_sec=300)
kills = rogue_agent.process(pg_stat_activity)

print("Action log (what the agent did in 30 seconds):")
print("-" * 60)

for k in kills:
    mins = k["running_for_sec"] // 60
    print(f"  [{k['killed_at'][11:19]}] KILLED pid {k['pid']} - {k['application']}")
    print(f"    Had been running for {mins} minutes")
    print(f"    Executed: {k['action']}")
    print()

print(f"Total queries killed: {len(kills)}")

print("""
Impact:
  - annual_finance_report  : 62-minute query lost. Regeneration: ~3 hours.
  - quarterly_audit_report : 55-minute query lost. Regeneration: ~2 hours.
  - annual_hr_report       : 47-minute query lost. Regeneration: ~1.5 hours.
  - etl_nightly_load       : 3-hour ETL job killed. Restart + reprocess: ~6 hours.
  - etl_customer_sync      : 2-hour ETL job killed. Restart + reprocess: ~4 hours.

  Total lost work: approximately 16.5 engineer-hours of processing time.
  Trust in the AI remediation system: severely damaged.
  Board finance report delayed by one business day.
""")

PYEOF
```

### Expected output (yours will differ):

```
============================================================
SCENARIO: Rogue Remediation Agent
============================================================

[scenario text printed here]

Agent starting with PRODUCTION config (accidentally set to auto_execute_all)...

Action log (what the agent did in 30 seconds):
------------------------------------------------------------
  [08:15:03] KILLED pid 12341 - annual_finance_report
    Had been running for 62 minutes
    Executed: SELECT pg_terminate_backend(12341)

  [08:15:03] KILLED pid 12342 - etl_nightly_load
    Had been running for 194 minutes
    Executed: SELECT pg_terminate_backend(12342)
...

Total queries killed: 5

[impact text printed here]
```

---

## Investigate

On your **Mac terminal**, trace how the wrong config reached production:

```bash
python3 << 'PYEOF'

# This script models the config validation that SHOULD have been in place.
# It shows what each check would have caught - and at what point in the deployment.

print("Investigation: How the Rogue Config Reached Production")
print("=" * 60)

print("""
Config drift timeline:

  Tuesday 14:00
    DevOps sets staging config: mode=auto_execute_all
    Reason: load testing needs the agent to act, not just recommend
    Staging config file: /configs/staging/agent_config.yaml

  Wednesday 09:30
    DevOps needs to update max_connections_threshold in production config
    Command run:
      cp /configs/staging/agent_config.yaml /configs/production/agent_config.yaml
    Reason: "I'll just copy the file and edit the one value I need"
    The mode value was in the same file. It was overwritten silently.

  Wednesday 09:32
    Production agent restarts (automated restart on config change)
    Agent does NOT validate its own config on startup
    Agent does NOT log its mode on startup
    No alert fired. No human noticed.

  Thursday 08:15
    Agent processes a large alert batch
    Kills 5 long-running queries in 8 seconds
    On-call DBA sees terminated sessions in pg_log
    Root cause traced to config file 12 minutes later

Contributing factors:
  1. Safety mode and other settings were in the same config file
     (should be in a separate, access-controlled safety config)
  2. Agent did not validate its own config on startup
  3. Agent did not log its operating mode on startup
  4. No alert on safety-mode changes in production
  5. No diff review before a config file was deployed
  6. No CI/CD check for dangerous mode in production configs
""")

# -----------------------------------------------------------------------
# SHOW WHAT PROPER VALIDATION WOULD HAVE CAUGHT
# -----------------------------------------------------------------------
# We define a validation function and run it against both configs.
# This is what the agent should call before it does anything else.

def validate_agent_config(config: dict, environment: str) -> tuple:
    """
    Validate agent configuration for the target environment.
    Returns (is_safe, list_of_issues).

    config       - the loaded config dict
    environment  - "production", "staging", or "development"
    """
    issues = []

    mode = config.get("mode", "recommend_only")

    # Rule 1: auto_execute_all is never allowed in production
    # This is the critical check that would have blocked the incident
    if mode == "auto_execute_all" and environment == "production":
        issues.append({
            "severity": "CRITICAL",
            "check":    "safety_mode_production_block",
            "message":  f"mode='{mode}' is not permitted in production",
            "required": "mode must be 'recommend_only' or 'auto_low_risk' in production",
        })

    # Rule 2: auto_low_risk in production requires an approval_webhook to be set
    if mode == "auto_low_risk" and environment == "production":
        if not config.get("approval_webhook"):
            issues.append({
                "severity": "WARNING",
                "check":    "approval_webhook_missing",
                "message":  "auto_low_risk mode in production requires an approval_webhook",
                "required": "set approval_webhook to a valid endpoint",
            })

    # Rule 3: the config must declare its intended environment
    # This catches the "copied from staging" pattern
    if config.get("intended_environment") and config["intended_environment"] != environment:
        issues.append({
            "severity": "CRITICAL",
            "check":    "environment_mismatch",
            "message":  f"config says intended_environment='{config['intended_environment']}' "
                        f"but we are running in '{environment}'",
            "required": "config file must match the target environment",
        })

    # Return True (safe) only if there are no CRITICAL issues
    is_safe = not any(i["severity"] == "CRITICAL" for i in issues)
    return is_safe, issues


# -----------------------------------------------------------------------
# TEST BOTH CONFIGS
# -----------------------------------------------------------------------

staging_config = {
    "mode":                    "auto_execute_all",
    "min_query_duration_sec":  300,
    "intended_environment":    "staging",     # correctly labeled
}

# This is the config that was copied to production - it still says staging
copied_to_production = {
    "mode":                    "auto_execute_all",
    "min_query_duration_sec":  300,
    "intended_environment":    "staging",     # wrong - was not updated
}

correct_production_config = {
    "mode":                    "recommend_only",
    "min_query_duration_sec":  1800,
    "intended_environment":    "production",
    "approval_webhook":        None,          # recommend_only does not need a webhook
}

configs_to_test = [
    ("Staging config in staging",               staging_config,            "staging"),
    ("Staging config accidentally in production", copied_to_production,    "production"),
    ("Correct production config",               correct_production_config, "production"),
]

print("Config validation results:")
print()

for label, config, env in configs_to_test:
    is_safe, issues = validate_agent_config(config, env)
    status = "SAFE - agent may start" if is_safe else "BLOCKED - agent refuses to start"
    print(f"  [{status}]")
    print(f"  Scenario : {label}")
    print(f"  Mode     : {config['mode']}, Environment: {env}")
    if issues:
        for issue in issues:
            print(f"  [{issue['severity']}] {issue['check']}: {issue['message']}")
    print()

PYEOF
```

### Expected output (yours will differ):

```
Investigation: How the Rogue Config Reached Production
============================================================

[timeline text printed here]

Config validation results:

  [SAFE - agent may start]
  Scenario : Staging config in staging
  Mode     : auto_execute_all, Environment: staging

  [BLOCKED - agent refuses to start]
  Scenario : Staging config accidentally in production
  Mode     : auto_execute_all, Environment: production
  [CRITICAL] safety_mode_production_block: mode='auto_execute_all' is not permitted in production
  [CRITICAL] environment_mismatch: config says intended_environment='staging' but we are running in 'production'

  [SAFE - agent may start]
  Scenario : Correct production config
  Mode     : recommend_only, Environment: production
```

---

## The Fix

Four changes. Implement all of them. They are not optional.

### Fix 1: Safety validation on agent startup

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 1: The agent validates its own config before it does anything else.
# If the config is unsafe for the environment, the agent raises an error and exits.
# DBA analogy: like PostgreSQL checking that data_directory is writable before starting.
# If a required condition is not met, the process refuses to come up.

print("Fix 1: Safety Validation on Agent Startup")
print("=" * 50)


class SafeRemediationAgent:
    """
    Remediation agent that validates its own config before starting.
    An unsafe config causes __init__ to raise a ValueError,
    which stops the agent before it can take any action.
    """

    # This dict defines which modes are allowed per environment
    # It is a class-level constant - think of it as a CHECK constraint
    ALLOWED_MODES = {
        "production":  ["recommend_only", "auto_low_risk"],
        "staging":     ["recommend_only", "auto_low_risk", "auto_execute_all"],
        "development": ["recommend_only", "auto_low_risk", "auto_execute_all"],
    }

    def __init__(self, config: dict, environment: str):
        self.environment = environment
        self.mode        = config.get("mode", "recommend_only")

        # Run safety checks immediately - before storing any other state
        # If this raises, the object is never fully constructed
        self._validate_or_raise(config)

        # Only reaches here if validation passed
        self.min_duration_sec = config.get("min_query_duration_sec", 1800)
        print(f"  Agent started. mode={self.mode}, env={self.environment}")

    def _validate_or_raise(self, config: dict):
        """
        Check all safety rules. Raise ValueError if any CRITICAL rule fails.
        This is called ONCE at startup - the agent never runs with a bad config.
        """
        allowed = self.ALLOWED_MODES.get(self.environment, ["recommend_only"])

        if self.mode not in allowed:
            raise ValueError(
                f"SAFETY BLOCK: mode='{self.mode}' is not allowed in "
                f"'{self.environment}'. Allowed modes: {allowed}"
            )

        intended = config.get("intended_environment")
        if intended and intended != self.environment:
            raise ValueError(
                f"SAFETY BLOCK: config intended_environment='{intended}' "
                f"but agent is running in '{self.environment}'. "
                f"This config was not written for this environment."
            )

        print(f"  Config validation passed. mode={self.mode}, env={self.environment}")


# -----------------------------------------------------------------------
# TEST: try to start in three different scenarios
# -----------------------------------------------------------------------

# try/except: run code that MIGHT fail, and handle the failure gracefully.
#   try: runs the code inside
#   except ValueError as e: if that specific error happens, catch it
#   "as e" saves the error message in a variable called e
# DBA analogy: like BEGIN ... EXCEPTION WHEN ... in PL/pgSQL.
# Without try/except, the error would crash the entire program.
# With it, we catch the error and handle it (print a message, continue).
print("\nScenario 1: Safe config in production")
try:
    agent = SafeRemediationAgent(
        config={"mode": "recommend_only", "intended_environment": "production"},
        environment="production"
    )
except ValueError as e:
    print(f"  BLOCKED: {e}")

print("\nScenario 2: Staging config copied to production (the actual incident)")
try:
    agent = SafeRemediationAgent(
        config={"mode": "auto_execute_all", "intended_environment": "staging"},
        environment="production"
    )
except ValueError as e:
    print(f"  BLOCKED: {e}")

print("\nScenario 3: auto_execute_all in staging (legitimate)")
try:
    agent = SafeRemediationAgent(
        config={"mode": "auto_execute_all", "intended_environment": "staging"},
        environment="staging"
    )
except ValueError as e:
    print(f"  BLOCKED: {e}")

PYEOF
```

### Expected output (yours will differ):

```
Fix 1: Safety Validation on Agent Startup
==================================================

Scenario 1: Safe config in production
  Config validation passed. mode=recommend_only, env=production
  Agent started. mode=recommend_only, env=production

Scenario 2: Staging config copied to production (the actual incident)
  BLOCKED: SAFETY BLOCK: mode='auto_execute_all' is not allowed in 'production'.
  Allowed modes: ['recommend_only', 'auto_low_risk']

Scenario 3: auto_execute_all in staging (legitimate)
  Config validation passed. mode=auto_execute_all, env=staging
  Agent started. mode=auto_execute_all, env=staging
```

### Fix 2: Action approval workflow for medium and high-risk actions

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 2: Any action that is not low-risk must go through an approval step
# before it is executed. In a real system, this sends a Slack message or
# PagerDuty alert and waits for a DBA to click "Approve" or "Reject".
# Here we simulate the approval with a simple function.
# DBA analogy: like a two-person authorization rule for DROP TABLE in production.
# One person writes the command; a second person must confirm before it runs.

from datetime import datetime

print("Fix 2: Action Approval Workflow")
print("=" * 50)


def request_approval(action: str, risk: str, context: str) -> bool:
    """
    In production: send an approval request via Slack/PagerDuty and wait.
    Here: simulate the DBA's decision based on risk level.

    Returns True (approved) or False (rejected).
    """
    print(f"  APPROVAL REQUEST")
    print(f"    Action  : {action}")
    print(f"    Risk    : {risk}")
    print(f"    Context : {context}")

    # Simulate: low risk is auto-approved, medium/high needs manual review
    if risk == "low":
        print(f"    Decision: AUTO-APPROVED (low risk)")
        return True
    else:
        # In production this would block until a DBA responds
        # For this simulation, we reject medium/high risk automatically
        print(f"    Decision: QUEUED FOR HUMAN REVIEW (risk={risk})")
        print(f"    The action will not execute until a DBA approves it.")
        return False


class ApprovalGatedAgent:
    """
    Remediation agent that gates medium and high-risk actions behind an approval step.
    """

    def __init__(self, environment: str):
        self.environment = environment

    def execute_or_request(self, action: str, risk: str, context: str):
        """
        Low risk  : execute immediately (safe to auto-run)
        Medium    : request approval, execute only if approved
        High      : request approval, execute only if approved
        """
        if risk == "low":
            approved = request_approval(action, risk, context)
        else:
            approved = request_approval(action, risk, context)

        if approved:
            print(f"    Executing: {action}")
            # In production: run the actual query here
        else:
            print(f"    Not executed. Waiting for DBA response.")
        print()


# -----------------------------------------------------------------------
# TEST THE APPROVAL WORKFLOW
# -----------------------------------------------------------------------

agent = ApprovalGatedAgent(environment="production")

candidate_actions = [
    {
        "action":  "SELECT pg_reload_conf()",
        "risk":    "low",
        "context": "Reload config to pick up autovacuum setting change"
    },
    {
        "action":  "SELECT pg_terminate_backend(12341)",
        "risk":    "medium",
        "context": "annual_finance_report has been running 62 minutes, may be blocking"
    },
    {
        "action":  "ALTER TABLE orders SET (autovacuum_enabled = true)",
        "risk":    "medium",
        "context": "autovacuum disabled on orders table, dead tuples at 8.5M"
    },
]

print()
for item in candidate_actions:
    agent.execute_or_request(item["action"], item["risk"], item["context"])

PYEOF
```

### Expected output (yours will differ):

```
Fix 2: Action Approval Workflow
==================================================

  APPROVAL REQUEST
    Action  : SELECT pg_reload_conf()
    Risk    : low
    Context : Reload config to pick up autovacuum setting change
    Decision: AUTO-APPROVED (low risk)
    Executing: SELECT pg_reload_conf()

  APPROVAL REQUEST
    Action  : SELECT pg_terminate_backend(12341)
    Risk    : medium
    Context : annual_finance_report has been running 62 minutes, may be blocking
    Decision: QUEUED FOR HUMAN REVIEW (risk=medium)
    The action will not execute until a DBA approves it.
    Not executed. Waiting for DBA response.
...
```

### Fix 3: Kill switch that any DBA can trigger immediately

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 3: A global emergency stop that any DBA can activate.
# When the kill switch is thrown:
#   - All agents immediately stop executing actions
#   - All agents switch to recommend_only mode
#   - The kill switch state is persisted (survives agent restarts)
#   - Re-enabling requires explicit action by a senior DBA
# DBA analogy: like pg_ctl stop -m fast - an immediate, clean shutdown
# that does not wait for transactions to finish.

import threading
import time

print("Fix 3: Emergency Kill Switch")
print("=" * 50)


class KillSwitch:
    """
    A shared object that any component can check before taking action.
    When engaged, all agents immediately stop executing.
    """

    def __init__(self):
        # threading.Event is thread-safe - safe to read/write from multiple agents at once
        # .is_set() returns True if the kill switch is active
        self._engaged = threading.Event()
        self._engaged_by = None
        self._engaged_at = None

    def engage(self, triggered_by: str):
        """Activate the kill switch. Any DBA can call this."""
        self._engaged.set()
        self._engaged_by = triggered_by
        self._engaged_at = time.strftime("%Y-%m-%dT%H:%M:%S")
        print(f"  KILL SWITCH ENGAGED by {triggered_by} at {self._engaged_at}")
        print(f"  All agents are now in recommend_only mode.")

    def clear(self, cleared_by: str):
        """Deactivate the kill switch. Only senior DBAs should call this."""
        self._engaged.clear()
        print(f"  KILL SWITCH CLEARED by {cleared_by}")

    # @property makes this method act like a variable.
    # Instead of calling kill_switch.is_active(), you use kill_switch.is_active
    # (no parentheses). It's just a shortcut for cleaner code.
    # "-> bool" is a type hint: tells readers this returns True or False.
    # DBA analogy: like a VIEW - looks like a table, but runs a query behind the scenes.
    @property
    def is_active(self) -> bool:
        """Returns True if the kill switch is currently engaged."""
        return self._engaged.is_set()

    def status(self) -> str:
        if self.is_active:
            return f"ENGAGED (by {self._engaged_by} at {self._engaged_at})"
        return "CLEAR"


class KillSwitchAwareAgent:
    """
    An agent that checks the kill switch before every action.
    If the switch is active, it records the recommended action but does not execute it.
    """

    def __init__(self, name: str, kill_switch: KillSwitch):
        self.name        = name
        self.kill_switch = kill_switch

    def take_action(self, action: str, risk: str):
        # Check the kill switch BEFORE doing anything
        if self.kill_switch.is_active:
            print(f"  [{self.name}] KILL SWITCH ACTIVE - action blocked: {action}")
            return

        print(f"  [{self.name}] Executing [{risk}]: {action}")


# -----------------------------------------------------------------------
# SIMULATE: kill switch being used during an incident
# -----------------------------------------------------------------------

print()
switch = KillSwitch()
agent  = KillSwitchAwareAgent("RemediationAgent", switch)

print("Before kill switch:")
print(f"  Kill switch status: {switch.status()}")
agent.take_action("SELECT pg_reload_conf()", "low")
agent.take_action("SELECT pg_terminate_backend(12341)", "medium")

print()
print("DBA engages the kill switch after noticing rogue behavior:")
switch.engage(triggered_by="hapopezi")

print()
print("After kill switch:")
print(f"  Kill switch status: {switch.status()}")
agent.take_action("SELECT pg_reload_conf()", "low")
agent.take_action("SELECT pg_terminate_backend(12342)", "medium")

print()
print("Senior DBA investigates, fixes the config, clears the switch:")
switch.clear(cleared_by="hapopezi (verified config corrected)")

print()
print(f"Kill switch status after clear: {switch.status()}")
agent.take_action("SELECT pg_reload_conf()", "low")

PYEOF
```

### Expected output (yours will differ):

```
Fix 3: Emergency Kill Switch
==================================================

Before kill switch:
  Kill switch status: CLEAR
  [RemediationAgent] Executing [low]: SELECT pg_reload_conf()
  [RemediationAgent] Executing [medium]: SELECT pg_terminate_backend(12341)

DBA engages the kill switch after noticing rogue behavior:
  KILL SWITCH ENGAGED by hapopezi at 2026-06-09T14:30:00
  All agents are now in recommend_only mode.

After kill switch:
  Kill switch status: ENGAGED (by hapopezi at 2026-06-09T14:30:00)
  [RemediationAgent] KILL SWITCH ACTIVE - action blocked: SELECT pg_reload_conf()
  [RemediationAgent] KILL SWITCH ACTIVE - action blocked: SELECT pg_terminate_backend(12342)

Senior DBA investigates, fixes the config, clears the switch:
  KILL SWITCH CLEARED by hapopezi (verified config corrected)

Kill switch status after clear: CLEAR
  [RemediationAgent] Executing [low]: SELECT pg_reload_conf()
```

---

## What You Learned

| Problem | Why It Caused the Incident | Fix |
|---------|---------------------------|-----|
| Safety mode in the same file as other settings | A routine config copy silently overwrote the safety mode | Keep safety mode in a separate, access-controlled config file |
| No startup config validation | Agent started in `auto_execute_all` mode in production without any warning | Agent validates its own config on startup; refuses to run if the mode is not permitted |
| No approval workflow for medium-risk actions | Agent killed long-running queries without asking anyone | All medium and high-risk actions must be approved by a DBA before execution |
| No kill switch | 12 queries were killed before anyone could stop the agent | Any DBA can engage a kill switch that immediately blocks all agent actions |
| No alert on safety-mode changes in production | Nobody was notified when the config changed | Alert fires any time the safety mode changes on a production agent |
| No environment label in config files | Config intended for staging ran in production without detection | Every config file must declare its `intended_environment`; a mismatch blocks startup |
