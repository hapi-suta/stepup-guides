# Build 04: Permission Systems

A DBA agent that can do everything is like a database user with SUPERUSER. One mistake and it drops a table, reloads config, or terminates every connection. This guide teaches you to build role-based permissions, approval workflows, and audit logging for agents - the same way you manage access in PostgreSQL.

---

## Step 1. Understand agent permissions

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Agent Permissions: Principle of Least Privilege
================================================

DBA Analogy: PostgreSQL roles and privileges.

  -- Monitoring user: read-only
  CREATE ROLE monitor_agent LOGIN;
  GRANT CONNECT ON DATABASE production TO monitor_agent;
  GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO monitor_agent;

  -- Operations user: can manage sessions
  CREATE ROLE ops_agent LOGIN;
  GRANT monitor_agent TO ops_agent;  -- inherits read access
  GRANT EXECUTE ON FUNCTION pg_cancel_backend TO ops_agent;

  -- Admin user: full control (dangerous!)
  CREATE ROLE admin_agent LOGIN SUPERUSER;

Agent permission tiers work the same way:

  Tier 1 (Auto) - Like the monitoring role:
    - Check pg_stat views
    - Read logs
    - Send alerts
    -> No human approval needed

  Tier 2 (Notify) - Like the operations role:
    - Kill long-running queries
    - Run VACUUM
    - Adjust session parameters
    -> Notifies DBA, acts if no objection in 5 minutes

  Tier 3 (Approve) - Like the admin role:
    - Failover to standby
    - DROP objects
    - ALTER SYSTEM
    -> Requires explicit DBA approval before executing

Why not just give the agent full access?

  Same reason you don't give every application SUPERUSER:
  1. A bug becomes a disaster (agent runs DROP instead of SELECT)
  2. A prompt injection becomes a breach (attacker controls a powerful agent)
  3. No audit trail of who approved what
  4. No blast radius control (one mistake affects everything)
""")
PYEOF
```

---

## Step 2. Build role-based agent permissions

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

print("=" * 60)
print("ROLE-BASED AGENT PERMISSIONS")
print("=" * 60)

class AgentPermissionSystem:
    """
    Role-based access control for agent actions.

    DBA analogy: This IS PostgreSQL's GRANT/REVOKE system,
    but applied to agent tool calls instead of SQL statements.

    CREATE ROLE tier1_agent;  -- read-only
    CREATE ROLE tier2_agent;  -- operational
    CREATE ROLE tier3_agent;  -- administrative

    GRANT SELECT ON pg_stat_activity TO tier1_agent;
    GRANT EXECUTE ON pg_cancel_backend TO tier2_agent;
    -- tier3_agent can ALTER SYSTEM (but only with approval)
    """

    # Define which actions belong to which tier
    TIERS = {
        1: {
            "name": "Auto (Read-Only)",
            "approval": "none",
            "actions": [
                "check_stats",          # SELECT from pg_stat views
                "read_logs",            # Read PostgreSQL log files
                "send_alert",           # Send notification to Slack/PagerDuty
                "check_replication",    # Check replication status
                "check_disk_space",     # Check filesystem usage
                "explain_query",        # Run EXPLAIN (not EXPLAIN ANALYZE)
                "list_connections",     # List active connections
                "check_locks",         # Check pg_locks
            ],
        },
        2: {
            "name": "Notify (Operational)",
            "approval": "notify",
            "actions": [
                "cancel_query",         # pg_cancel_backend (graceful)
                "terminate_connection", # pg_terminate_backend (forced)
                "run_vacuum",          # VACUUM (not FULL)
                "run_analyze",         # ANALYZE
                "set_parameter",       # SET for session params only
                "create_index",        # CREATE INDEX CONCURRENTLY
                "refresh_stats",       # pg_stat_reset
            ],
        },
        3: {
            "name": "Approve (Administrative)",
            "approval": "explicit",
            "actions": [
                "failover",            # Promote standby to primary
                "drop_object",         # DROP TABLE/INDEX/etc.
                "alter_system",        # ALTER SYSTEM SET
                "reload_config",       # pg_reload_conf
                "restart_server",      # systemctl restart postgresql
                "modify_hba",         # Edit pg_hba.conf
                "create_role",        # CREATE ROLE
                "backup_database",    # pg_basebackup / pg_dump
            ],
        },
    }

    def __init__(self, agent_role):
        """
        Initialize with an agent role (tier level).
        Like: SET ROLE tier1_agent;
        """
        self.role = agent_role
        self.max_tier = agent_role  # Agent can access this tier and below
        self.pending_approvals = []

    def get_tier_for_action(self, action):
        """Look up which tier an action belongs to."""
        for tier_num, tier_info in self.TIERS.items():
            if action in tier_info["actions"]:
                return tier_num, tier_info
        return None, None

    def check_permission(self, action):
        """
        Check if the agent can perform an action.
        Returns (allowed, tier, approval_needed, reason).
        """
        tier_num, tier_info = self.get_tier_for_action(action)

        if tier_num is None:
            return False, None, None, f"Unknown action: {action} (no GRANT exists)"

        if tier_num > self.max_tier:
            return False, tier_num, None, (
                f"Action '{action}' requires tier {tier_num} ({tier_info['name']}), "
                f"but agent has tier {self.max_tier} access"
            )

        return True, tier_num, tier_info["approval"], (
            f"Action '{action}' is tier {tier_num} ({tier_info['name']})"
        )


# -----------------------------------------------------------------------
# TEST: Three agents with different roles
# -----------------------------------------------------------------------

# Create three agents with different permission levels
read_only_agent = AgentPermissionSystem(agent_role=1)   # Like a monitoring user
ops_agent = AgentPermissionSystem(agent_role=2)         # Like an ops user
admin_agent = AgentPermissionSystem(agent_role=3)       # Like a DBA

test_actions = [
    "check_stats",
    "send_alert",
    "cancel_query",
    "run_vacuum",
    "failover",
    "alter_system",
    "drop_object",
]

print()
agents = [
    ("Read-Only (Tier 1)", read_only_agent),
    ("Ops (Tier 2)", ops_agent),
    ("Admin (Tier 3)", admin_agent),
]

# Print header
print(f"{'Action':<22}", end="")
for name, _ in agents:
    print(f"{name:<22}", end="")
print()
print("-" * 88)

for action in test_actions:
    print(f"{action:<22}", end="")
    for name, agent in agents:
        allowed, tier, approval, reason = agent.check_permission(action)
        if allowed and approval == "none":
            status = "AUTO"
        elif allowed and approval == "notify":
            status = "NOTIFY"
        elif allowed and approval == "explicit":
            status = "APPROVE"
        else:
            status = "DENIED"
        print(f"{status:<22}", end="")
    print()

print()
print("AUTO    = Execute immediately, no approval needed")
print("NOTIFY  = Execute but notify the DBA")
print("APPROVE = Requires explicit DBA approval")
print("DENIED  = Agent lacks permission for this action")
PYEOF
```

Expected output (yours will differ):
```
Action                Read-Only (Tier 1)    Ops (Tier 2)          Admin (Tier 3)
----------------------------------------------------------------------------------------
check_stats           AUTO                  AUTO                  AUTO
send_alert            AUTO                  AUTO                  AUTO
cancel_query          DENIED                NOTIFY                NOTIFY
run_vacuum            DENIED                NOTIFY                NOTIFY
failover              DENIED                DENIED                APPROVE
alter_system          DENIED                DENIED                APPROVE
drop_object           DENIED                DENIED                APPROVE

AUTO    = Execute immediately, no approval needed
NOTIFY  = Execute but notify the DBA
APPROVE = Requires explicit DBA approval
DENIED  = Agent lacks permission for this action
```

The Read-Only agent can only check stats and send alerts. The Ops agent can also kill queries and vacuum. Only the Admin agent can failover or drop objects - and even then, it needs explicit approval.

---

## Step 3. Build the approval workflow

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import json

print("=" * 60)
print("APPROVAL WORKFLOW: Two-DBA rule for dangerous operations")
print("=" * 60)

class ApprovalWorkflow:
    """
    Manage approval requests for high-risk agent actions.

    DBA analogy: The "four eyes" principle.
    In many shops, a second DBA must approve before you:
    - Run a failover
    - DROP a production table
    - ALTER SYSTEM

    This workflow enforces the same rule for agents.
    """

    def __init__(self):
        self.pending = {}
        self.completed = {}
        self.next_id = 1

    def request_approval(self, action, details, requested_by):
        """
        Create an approval request.
        Returns a request ID that the approver uses to approve/deny.
        """
        request_id = f"APR-{self.next_id:04d}"
        self.next_id += 1

        self.pending[request_id] = {
            "id": request_id,
            "action": action,
            "details": details,
            "requested_by": requested_by,
            "requested_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "status": "pending",
            "expires_at": "10 minutes from request",
        }

        return request_id

    def approve(self, request_id, approved_by, reason=""):
        """Approve a pending request."""
        if request_id not in self.pending:
            return False, f"Request {request_id} not found"

        request = self.pending.pop(request_id)
        request["status"] = "approved"
        request["approved_by"] = approved_by
        request["approved_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
        request["approval_reason"] = reason
        self.completed[request_id] = request
        return True, f"Request {request_id} approved by {approved_by}"

    def deny(self, request_id, denied_by, reason=""):
        """Deny a pending request."""
        if request_id not in self.pending:
            return False, f"Request {request_id} not found"

        request = self.pending.pop(request_id)
        request["status"] = "denied"
        request["denied_by"] = denied_by
        request["denied_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
        request["denial_reason"] = reason
        self.completed[request_id] = request
        return True, f"Request {request_id} denied by {denied_by}"

    def is_approved(self, request_id):
        """Check if a request was approved."""
        if request_id in self.completed:
            return self.completed[request_id]["status"] == "approved"
        return False


# -----------------------------------------------------------------------
# SIMULATION: Agent wants to perform dangerous operations
# -----------------------------------------------------------------------
workflow = ApprovalWorkflow()

print()
print("--- Agent requests to failover pg-primary ---")
req1 = workflow.request_approval(
    action="failover",
    details={
        "source": "pg-primary-01",
        "target": "pg-standby-01",
        "reason": "Primary is unresponsive for >5 minutes",
        "impact": "30 seconds of downtime during promotion",
    },
    requested_by="dba-agent-admin"
)
print(f"  Request created: {req1}")
print(f"  Waiting for DBA approval...")

# DBA approves
success, msg = workflow.approve(req1, approved_by="happy.afopezi", reason="Confirmed primary is down")
print(f"  {msg}")
print(f"  Agent can now execute failover: {workflow.is_approved(req1)}")

print()
print("--- Agent requests to DROP TABLE ---")
req2 = workflow.request_approval(
    action="drop_object",
    details={
        "object": "TABLE temp_migration_data",
        "database": "production",
        "reason": "Migration completed, temp table no longer needed",
        "row_count": 5000000,
    },
    requested_by="dba-agent-admin"
)
print(f"  Request created: {req2}")

# DBA denies
success, msg = workflow.deny(req2, denied_by="happy.afopezi", reason="Keep for 7 days post-migration")
print(f"  {msg}")
print(f"  Agent can execute DROP: {workflow.is_approved(req2)}")

print()
print("--- Agent requests ALTER SYSTEM ---")
req3 = workflow.request_approval(
    action="alter_system",
    details={
        "parameter": "shared_buffers",
        "current_value": "4GB",
        "new_value": "8GB",
        "reason": "Buffer hit ratio dropped to 85%",
        "requires_restart": True,
    },
    requested_by="dba-agent-admin"
)
print(f"  Request created: {req3}")

# Still pending - no approval yet
print(f"  Status: pending (no DBA has responded yet)")
print(f"  Agent can execute: {workflow.is_approved(req3)}")

print()
print("--- Completed Requests (Audit Trail) ---")
for req_id, req in workflow.completed.items():
    print(f"  {req_id}: {req['action']} -> {req['status']}")
    print(f"    Requested by: {req['requested_by']} at {req['requested_at']}")
    if req['status'] == 'approved':
        print(f"    Approved by:  {req['approved_by']} - {req['approval_reason']}")
    else:
        print(f"    Denied by:    {req['denied_by']} - {req['denial_reason']}")
    print()

print("--- Pending Requests ---")
for req_id, req in workflow.pending.items():
    print(f"  {req_id}: {req['action']} -> WAITING FOR APPROVAL")
    print(f"    Details: {json.dumps(req['details'])[:70]}...")
PYEOF
```

Expected output (yours will differ):
```
--- Agent requests to failover pg-primary ---
  Request created: APR-0001
  Waiting for DBA approval...
  Request APR-0001 approved by happy.afopezi
  Agent can now execute failover: True

--- Agent requests to DROP TABLE ---
  Request created: APR-0002
  Request APR-0002 denied by happy.afopezi
  Agent can execute DROP: False

--- Agent requests ALTER SYSTEM ---
  Request created: APR-0003
  Status: pending (no DBA has responded yet)
  Agent can execute: False

--- Completed Requests (Audit Trail) ---
  APR-0001: failover -> approved
    Requested by: dba-agent-admin at 2026-06-15 10:00:00
    Approved by:  happy.afopezi - Confirmed primary is down

  APR-0002: drop_object -> denied
    Requested by: dba-agent-admin at 2026-06-15 10:00:00
    Denied by:    happy.afopezi - Keep for 7 days post-migration

--- Pending Requests ---
  APR-0003: alter_system -> WAITING FOR APPROVAL
    Details: {"parameter": "shared_buffers", "current_value": "4GB", "new_v...
```

---

## Step 4. Build comprehensive audit logging

Every action the agent takes must be logged. This is your `log_statement = 'all'` for the agent.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import json
import os

print("=" * 60)
print("AUDIT LOGGING: log_statement = 'all' for agents")
print("=" * 60)

class AgentAuditLog:
    """
    Log every tool call, decision, and action.

    DBA analogy: PostgreSQL's logging system.
    - log_statement = 'all'         -> log every query
    - log_connections = on          -> log every connection
    - log_disconnections = on       -> log every disconnect
    - log_duration = on             -> log how long each query took

    This audit log does the same for agent operations.
    """

    def __init__(self, log_file="/tmp/agent_audit.log"):
        self.log_file = log_file
        self.entries = []

    def log(self, event_type, agent_id, action, details, result="pending"):
        """
        Log an event. Every field maps to something you'd see
        in PostgreSQL logs.
        """
        entry = {
            # When (like log_line_prefix %t)
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            # What type of event
            "event_type": event_type,
            # Which agent (like %u - user in PG logs)
            "agent_id": agent_id,
            # What action (like the SQL statement)
            "action": action,
            # Context (like %d database, %a application_name)
            "details": details,
            # Outcome
            "result": result,
        }
        self.entries.append(entry)

        # Write to file (append mode, like PG log files)
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

        return entry

    def query(self, agent_id=None, event_type=None, action=None):
        """
        Query the audit log - like querying csvlog.

        SELECT * FROM pg_log WHERE user_name = 'agent' AND command_tag = 'SELECT';
        """
        results = self.entries
        if agent_id:
            results = [e for e in results if e["agent_id"] == agent_id]
        if event_type:
            results = [e for e in results if e["event_type"] == event_type]
        if action:
            results = [e for e in results if e["action"] == action]
        return results

    def summary(self):
        """
        Generate a summary - like pg_stat_statements but for agents.
        """
        by_type = {}
        by_agent = {}
        by_action = {}

        for entry in self.entries:
            et = entry["event_type"]
            by_type[et] = by_type.get(et, 0) + 1

            aid = entry["agent_id"]
            by_agent[aid] = by_agent.get(aid, 0) + 1

            act = entry["action"]
            by_action[act] = by_action.get(act, 0) + 1

        return {"by_type": by_type, "by_agent": by_agent, "by_action": by_action}


# -----------------------------------------------------------------------
# SIMULATION: Full incident with audit trail
# -----------------------------------------------------------------------

# Clean up any previous log file
if os.path.exists("/tmp/agent_audit.log"):
    os.remove("/tmp/agent_audit.log")

audit = AgentAuditLog()

print("\n--- Simulating an incident response ---\n")

# Tier 1 agent detects the problem
audit.log("alert_received", "tier1-monitor", "check_stats",
          {"server": "pg-primary-01", "metric": "cpu_percent", "value": 97})
print("  [Tier 1] Detected CPU at 97% on pg-primary-01")

audit.log("tool_call", "tier1-monitor", "check_stats",
          {"server": "pg-primary-01", "query": "pg_stat_activity"})
print("  [Tier 1] Checked pg_stat_activity: 847 active connections")

audit.log("tool_call", "tier1-monitor", "send_alert",
          {"channel": "slack", "severity": "high", "message": "CPU spike on pg-primary"})
print("  [Tier 1] Sent alert to Slack")

# Tier 2 agent takes action
audit.log("tool_call", "tier2-ops", "cancel_query",
          {"server": "pg-primary-01", "pid": 12345, "reason": "runaway query, 45 min"},
          result="success")
print("  [Tier 2] Cancelled long-running query (pid 12345)")

audit.log("tool_call", "tier2-ops", "run_vacuum",
          {"server": "pg-primary-01", "table": "orders", "type": "standard"},
          result="success")
print("  [Tier 2] Ran VACUUM on orders table")

# Tier 3 agent needs approval
audit.log("approval_requested", "tier3-admin", "alter_system",
          {"parameter": "work_mem", "old": "4MB", "new": "64MB"},
          result="pending")
print("  [Tier 3] Requested approval to change work_mem")

audit.log("approval_granted", "tier3-admin", "alter_system",
          {"parameter": "work_mem", "approved_by": "happy.afopezi"},
          result="approved")
print("  [Tier 3] Approval granted by happy.afopezi")

audit.log("tool_call", "tier3-admin", "alter_system",
          {"parameter": "work_mem", "value": "64MB"},
          result="success")
print("  [Tier 3] Changed work_mem to 64MB")

audit.log("tool_call", "tier3-admin", "reload_config",
          {"server": "pg-primary-01"},
          result="success")
print("  [Tier 3] Reloaded configuration")

# Blocked action
audit.log("permission_denied", "tier2-ops", "failover",
          {"reason": "Tier 2 agent cannot perform failover (requires Tier 3)"},
          result="blocked")
print("  [Tier 2] BLOCKED: Attempted failover without permission")

# -----------------------------------------------------------------------
# AUDIT REPORT
# -----------------------------------------------------------------------
print("\n" + "=" * 60)
print("AUDIT REPORT")
print("=" * 60)

summary = audit.summary()

print("\nEvents by type:")
for event_type, count in sorted(summary["by_type"].items()):
    print(f"  {event_type:<25} {count}")

print("\nEvents by agent:")
for agent, count in sorted(summary["by_agent"].items()):
    print(f"  {agent:<25} {count}")

print("\nEvents by action:")
for action, count in sorted(summary["by_action"].items()):
    print(f"  {action:<25} {count}")

# Query the log for blocked events
print("\nBlocked/Denied events:")
denied = audit.query(event_type="permission_denied")
for entry in denied:
    print(f"  {entry['timestamp']} | {entry['agent_id']} tried '{entry['action']}'")
    print(f"    Reason: {entry['details'].get('reason', 'N/A')}")

print(f"\nAudit log written to: /tmp/agent_audit.log")
print(f"Total entries: {len(audit.entries)}")
PYEOF
```

Expected output (yours will differ):
```
--- Simulating an incident response ---

  [Tier 1] Detected CPU at 97% on pg-primary-01
  [Tier 1] Checked pg_stat_activity: 847 active connections
  [Tier 1] Sent alert to Slack
  [Tier 2] Cancelled long-running query (pid 12345)
  [Tier 2] Ran VACUUM on orders table
  [Tier 3] Requested approval to change work_mem
  [Tier 3] Approval granted by happy.afopezi
  [Tier 3] Changed work_mem to 64MB
  [Tier 3] Reloaded configuration
  [Tier 2] BLOCKED: Attempted failover without permission

============================================================
AUDIT REPORT
============================================================

Events by type:
  alert_received            1
  approval_granted          1
  approval_requested        1
  permission_denied         1
  tool_call                 6

Events by agent:
  tier1-monitor             3
  tier2-ops                 3
  tier3-admin               4

Events by action:
  alter_system              3
  cancel_query              1
  check_stats               2
  failover                  1
  reload_config             1
  run_vacuum                1
  send_alert                1

Blocked/Denied events:
  2026-06-15 10:00:00 | tier2-ops tried 'failover'
    Reason: Tier 2 agent cannot perform failover (requires Tier 3)

Audit log written to: /tmp/agent_audit.log
Total entries: 10
```

---

## Step 5. Complete tiered DBA agent system

Let's wire permissions, approval workflow, and audit logging together into a complete system.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import json
import os

print("=" * 60)
print("COMPLETE TIERED DBA AGENT SYSTEM")
print("=" * 60)

# -----------------------------------------------------------------------
# TIER DEFINITIONS
# -----------------------------------------------------------------------
TIER_CONFIG = {
    1: {
        "name": "Monitor",
        "approval": "none",
        "actions": {"check_stats", "read_logs", "send_alert", "check_replication",
                    "explain_query", "list_connections", "check_locks"},
    },
    2: {
        "name": "Operator",
        "approval": "notify",
        "actions": {"cancel_query", "terminate_connection", "run_vacuum",
                    "run_analyze", "set_parameter", "create_index"},
    },
    3: {
        "name": "Administrator",
        "approval": "explicit",
        "actions": {"failover", "drop_object", "alter_system",
                    "reload_config", "restart_server", "modify_hba"},
    },
}

class TieredDBAAgent:
    """
    A DBA agent with tiered permissions, approval workflow,
    and full audit trail.

    This is the entire security stack for a DBA agent:
    - Permissions (GRANT/REVOKE)
    - Approval workflow (four-eyes principle)
    - Audit logging (log_statement = 'all')
    - Blast radius control (limit to specific servers)
    """

    def __init__(self, agent_id, tier_level, allowed_servers=None):
        self.agent_id = agent_id
        self.tier_level = tier_level
        self.allowed_servers = allowed_servers  # None = all servers
        self.audit_log = []
        self.pending_approvals = {}
        self.approval_counter = 0

    def _audit(self, event, action, details, result="success"):
        entry = {
            "ts": time.strftime("%H:%M:%S"),
            "agent": self.agent_id,
            "event": event,
            "action": action,
            "details": str(details)[:100],
            "result": result,
        }
        self.audit_log.append(entry)
        return entry

    def _get_tier_for_action(self, action):
        for tier_num, config in TIER_CONFIG.items():
            if action in config["actions"]:
                return tier_num, config
        return None, None

    def execute(self, action, server, params=None):
        """
        Attempt to execute an action. Checks:
        1. Does the agent have permission? (tier check)
        2. Is the server in scope? (blast radius)
        3. Is approval needed? (workflow)
        """
        if params is None:
            params = {}

        # Check blast radius (server scope)
        if self.allowed_servers and server not in self.allowed_servers:
            self._audit("blast_radius_blocked", action,
                       f"Server {server} not in allowed list", "blocked")
            return {
                "status": "blocked",
                "reason": f"Agent {self.agent_id} is not allowed to access {server}",
            }

        # Check tier permission
        required_tier, tier_config = self._get_tier_for_action(action)

        if required_tier is None:
            self._audit("unknown_action", action, params, "blocked")
            return {"status": "blocked", "reason": f"Unknown action: {action}"}

        if required_tier > self.tier_level:
            self._audit("permission_denied", action,
                       f"Needs tier {required_tier}, has tier {self.tier_level}", "blocked")
            return {
                "status": "blocked",
                "reason": (f"Action '{action}' requires {tier_config['name']} "
                          f"(tier {required_tier}), agent has tier {self.tier_level}"),
            }

        # Check approval requirement
        approval = TIER_CONFIG[required_tier]["approval"]

        if approval == "none":
            # Tier 1: Execute immediately
            self._audit("auto_executed", action, f"{server}: {params}")
            return {"status": "executed", "approval": "none",
                    "message": f"[AUTO] {action} on {server}"}

        elif approval == "notify":
            # Tier 2: Execute and notify
            self._audit("executed_with_notify", action, f"{server}: {params}")
            return {"status": "executed", "approval": "notified",
                    "message": f"[NOTIFY] {action} on {server} - DBA notified"}

        elif approval == "explicit":
            # Tier 3: Create approval request, don't execute yet
            self.approval_counter += 1
            req_id = f"REQ-{self.approval_counter:03d}"
            self.pending_approvals[req_id] = {
                "action": action, "server": server, "params": params
            }
            self._audit("approval_requested", action, f"{server}: {params}", "pending")
            return {"status": "pending", "approval_id": req_id,
                    "message": f"[APPROVE] {action} on {server} - waiting for DBA approval"}

    def approve_and_execute(self, req_id, approver):
        """DBA approves a pending request, then we execute."""
        if req_id not in self.pending_approvals:
            return {"status": "error", "reason": f"No pending request {req_id}"}

        request = self.pending_approvals.pop(req_id)
        self._audit("approved_and_executed", request["action"],
                   f"Approved by {approver}: {request['server']}")
        return {
            "status": "executed",
            "message": f"[EXECUTED] {request['action']} on {request['server']} "
                       f"(approved by {approver})",
        }


# -----------------------------------------------------------------------
# SIMULATION
# -----------------------------------------------------------------------

# Create agents with different tiers and blast radii
monitor = TieredDBAAgent("monitor-bot", tier_level=1)
operator = TieredDBAAgent("ops-bot", tier_level=2,
                          allowed_servers=["pg-primary-01", "pg-replica-01"])
admin = TieredDBAAgent("admin-bot", tier_level=3)

print("\n--- Monitor Agent (Tier 1, all servers) ---")
actions = [
    ("check_stats", "pg-primary-01", {"metric": "cpu"}),
    ("send_alert", "pg-primary-01", {"channel": "slack"}),
    ("cancel_query", "pg-primary-01", {"pid": 12345}),  # Should be denied
]
for action, server, params in actions:
    result = monitor.execute(action, server, params)
    print(f"  {action}: {result['status']} - {result['message'] if 'message' in result else result['reason']}")

print("\n--- Operator Agent (Tier 2, restricted servers) ---")
actions = [
    ("check_stats", "pg-primary-01", {}),                  # Tier 1, allowed server
    ("cancel_query", "pg-primary-01", {"pid": 12345}),     # Tier 2, allowed server
    ("cancel_query", "pg-analytics-01", {"pid": 99999}),   # Tier 2, BLOCKED server
    ("failover", "pg-primary-01", {}),                      # Tier 3, denied
]
for action, server, params in actions:
    result = operator.execute(action, server, params)
    status = result['status']
    msg = result.get('message', result.get('reason', ''))
    print(f"  {action} on {server}: {status}")
    print(f"    {msg}")

print("\n--- Admin Agent (Tier 3, all servers) ---")
actions = [
    ("check_stats", "pg-primary-01", {}),
    ("cancel_query", "pg-primary-01", {"pid": 12345}),
    ("failover", "pg-primary-01", {"target": "pg-standby-01"}),
    ("alter_system", "pg-primary-01", {"param": "shared_buffers", "value": "8GB"}),
]
for action, server, params in actions:
    result = admin.execute(action, server, params)
    status = result['status']
    msg = result.get('message', result.get('reason', ''))
    print(f"  {action}: {status}")
    print(f"    {msg}")

# Approve the pending requests
print("\n--- DBA Approves Pending Requests ---")
for req_id in list(admin.pending_approvals.keys()):
    result = admin.approve_and_execute(req_id, approver="happy.afopezi")
    print(f"  {result['message']}")

# Print audit trail
print("\n--- Complete Audit Trail ---")
all_logs = monitor.audit_log + operator.audit_log + admin.audit_log
for entry in all_logs:
    print(f"  {entry['ts']} | {entry['agent']:<12} | {entry['event']:<25} | "
          f"{entry['action']:<20} | {entry['result']}")
PYEOF
```

Expected output (yours will differ):
```
--- Monitor Agent (Tier 1, all servers) ---
  check_stats: executed - [AUTO] check_stats on pg-primary-01
  send_alert: executed - [AUTO] send_alert on pg-primary-01
  cancel_query: blocked - Action 'cancel_query' requires Operator (tier 2), agent has tier 1

--- Operator Agent (Tier 2, restricted servers) ---
  check_stats on pg-primary-01: executed
    [AUTO] check_stats on pg-primary-01
  cancel_query on pg-primary-01: executed
    [NOTIFY] cancel_query on pg-primary-01 - DBA notified
  cancel_query on pg-analytics-01: blocked
    Agent ops-bot is not allowed to access pg-analytics-01
  failover on pg-primary-01: blocked
    Action 'failover' requires Administrator (tier 3), agent has tier 2

--- Admin Agent (Tier 3, all servers) ---
  check_stats: executed
    [AUTO] check_stats on pg-primary-01
  cancel_query: executed
    [NOTIFY] cancel_query on pg-primary-01 - DBA notified
  failover: pending
    [APPROVE] failover on pg-primary-01 - waiting for DBA approval
  alter_system: pending
    [APPROVE] alter_system on pg-primary-01 - waiting for DBA approval

--- DBA Approves Pending Requests ---
  [EXECUTED] failover on pg-primary-01 (approved by happy.afopezi)
  [EXECUTED] alter_system on pg-primary-01 (approved by happy.afopezi)

--- Complete Audit Trail ---
  10:00:00 | monitor-bot  | auto_executed             | check_stats          | success
  10:00:00 | monitor-bot  | auto_executed             | send_alert           | success
  10:00:00 | monitor-bot  | permission_denied         | cancel_query         | blocked
  10:00:00 | ops-bot      | auto_executed             | check_stats          | success
  10:00:00 | ops-bot      | executed_with_notify      | cancel_query         | success
  10:00:00 | ops-bot      | blast_radius_blocked      | cancel_query         | blocked
  10:00:00 | ops-bot      | permission_denied         | failover             | blocked
  ...
```

---

## What You Learned

| Concept | DBA Analogy | What You Built |
|---------|-------------|----------------|
| Tier-based permissions | PostgreSQL GRANT/REVOKE | 3-tier action classification |
| Approval workflow | Four-eyes principle for DDL | Request/approve/deny system |
| Audit logging | log_statement = 'all' | Complete event trail |
| Blast radius control | Host-based access (pg_hba.conf) | Server allowlists per agent |
| Principle of least privilege | Minimal role grants | Agents only get what they need |

This completes the Build section. Proceed to [USE Exercises](../use/01-safety-exercises.md) to practice everything you learned.
