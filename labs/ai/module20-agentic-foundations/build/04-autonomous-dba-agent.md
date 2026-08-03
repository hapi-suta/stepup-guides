# Build 04: Autonomous DBA Agent

This is the capstone of Module 20. You'll combine async Python, an LLM SDK, and DBA tools into a fully autonomous agent that monitors PostgreSQL, detects anomalies, decides what to do, and logs its reasoning.

---

## Step 1. Agent architecture overview

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# AUTONOMOUS DBA AGENT - ARCHITECTURE
#
# This agent runs continuously, like a DBA on-call:
#   1. Polls pg_stat_activity every 30 seconds
#   2. Detects anomalies (connection spikes, long queries, locks)
#   3. Sends anomalies to Claude for analysis
#   4. Claude decides what tools to call
#   5. Agent executes tools and logs everything
#   6. Repeats
#
# DBA analogy: this IS the automated version of your on-call
# rotation. The agent does what you do at 3 AM:
# check, think, act, document.
# ============================================================

print("Autonomous DBA Agent - Architecture")
print("=" * 55)

print("""
Components:

  +---------------------------+
  |     Monitor Loop          |  Polls every 30s (async)
  |  (asyncio event loop)     |
  +---------------------------+
              |
              v
  +---------------------------+
  |   Anomaly Detector        |  Threshold-based detection
  |  (no LLM needed)          |  Fast, cheap, always-on
  +---------------------------+
              |
              v (only if anomalies found)
  +---------------------------+
  |   LLM Analyst             |  Claude analyzes anomalies
  |  (Anthropic SDK)          |  Decides what to investigate
  +---------------------------+
              |
              v
  +---------------------------+
  |   Tool Executor           |  Runs DBA tools
  |  (with safety layer)      |  Read-only by default
  +---------------------------+
              |
              v
  +---------------------------+
  |   Action Logger           |  Logs every decision
  |  (JSON file + console)    |  Full audit trail
  +---------------------------+

Safety Rules:
  1. Read-only by default (check, query, inspect)
  2. Write operations require confirmation (kill query, change config)
  3. NEVER execute raw SQL from the LLM
  4. Log every action with timestamp, reasoning, and result
  5. Rate limit LLM calls (max 1 per anomaly batch)

Cost Management:
  - Anomaly detection is pure Python (free)
  - LLM only called when anomalies are found
  - Use claude-sonnet-4-20250514 (good reasoning, moderate cost)
  - Cap thinking tokens at 5000
""")
PYEOF
```

Expected output:
```
Autonomous DBA Agent - Architecture
=======================================================

Components:

  +---------------------------+
  |     Monitor Loop          |  Polls every 30s (async)
  |  (asyncio event loop)     |
  +---------------------------+
...
```

---

## Step 2. Build the agent - save to file

This agent is too large for a heredoc. Create it as a file.

On your **Mac terminal**, run:

```bash
vi /tmp/dba_agent.py
```

Paste this content:

```python
#!/usr/bin/env python3
"""
Autonomous DBA Agent
Monitors PostgreSQL, detects anomalies, and takes action.

Usage: python3 /tmp/dba_agent.py
  - Runs 5 monitoring cycles (configurable)
  - Saves state to /tmp/dba_agent_state.json
  - Logs all actions to console

DBA analogy: this is your automated on-call DBA.
It watches pg_stat_activity, detects problems, and either
alerts you or investigates autonomously.
"""

import asyncio
import json
import random
import time
from datetime import datetime


# ============================================================
# CONFIGURATION
# ============================================================

CONFIG = {
    "poll_interval_seconds": 5,      # How often to poll (5s for demo, 30s in production)
    "max_cycles": 5,                 # How many cycles to run (set to 0 for infinite)
    "state_file": "/tmp/dba_agent_state.json",
    "log_file": "/tmp/dba_agent_log.json",
    "llm_enabled": False,            # Set to True if you have ANTHROPIC_API_KEY
}

# Monitored servers
SERVERS = {
    "pg-primary": {"host": "10.0.1.10", "port": 5432, "role": "primary", "max_conn": 200},
    "pg-replica-1": {"host": "10.0.1.11", "port": 5432, "role": "replica", "max_conn": 200},
    "pg-replica-2": {"host": "10.0.1.12", "port": 5432, "role": "replica", "max_conn": 200},
}

# Anomaly thresholds
THRESHOLDS = {
    "connection_percent": 80,
    "long_query_seconds": 300,
    "idle_in_transaction_seconds": 60,
    "replication_lag_seconds": 5,
    "waiting_on_locks": 5,
}


# ============================================================
# DBA TOOLS (same tools the agent can call)
# ============================================================

def check_replication_lag(server_name: str) -> dict:
    """Check replication lag on a replica."""
    lag = random.uniform(0, 10.0)
    return {
        "server": server_name,
        "replication_lag_seconds": round(lag, 2),
        "status": "critical" if lag > 5 else "warning" if lag > 2 else "healthy",
    }


def get_active_queries(server_name: str, min_duration_seconds: float = 0) -> dict:
    """Get active queries from pg_stat_activity."""
    all_queries = [
        {"pid": 12345, "duration_seconds": 125.3, "state": "active",
         "query": "SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at",
         "wait_event": None},
        {"pid": 12346, "duration_seconds": 0.5, "state": "active",
         "query": "UPDATE inventory SET qty = qty - 1 WHERE id = 42",
         "wait_event": None},
        {"pid": 12347, "duration_seconds": 450.0, "state": "idle in transaction",
         "query": "BEGIN; SELECT * FROM accounts WHERE balance > 10000",
         "wait_event": "ClientRead"},
        {"pid": 12348, "duration_seconds": 45.2, "state": "active",
         "query": "CREATE INDEX CONCURRENTLY idx_orders_date ON orders(created_at)",
         "wait_event": None},
        {"pid": 12349, "duration_seconds": 600.0, "state": "active",
         "query": "VACUUM ANALYZE large_events_table",
         "wait_event": "IO:DataFileRead"},
    ]
    filtered = [q for q in all_queries if q["duration_seconds"] >= min_duration_seconds]
    return {"server": server_name, "total": len(filtered), "queries": filtered}


def kill_query(server_name: str, pid: int, reason: str) -> dict:
    """Terminate a backend process. WRITE OPERATION - requires confirmation."""
    return {
        "server": server_name, "pid": pid, "action": "terminated",
        "reason": reason, "success": True,
        "warning": "This is a write operation - logged for audit.",
    }


def get_lock_chains(server_name: str) -> dict:
    """Get lock wait chains (who is blocking whom)."""
    chains = [
        {"blocker_pid": 12345, "blocker_query": "UPDATE accounts SET ...",
         "blocked_pid": 12350, "blocked_query": "UPDATE accounts SET ...",
         "lock_type": "RowExclusiveLock", "wait_seconds": 45},
    ]
    # Randomly add more lock chains for demo variety
    if random.random() > 0.5:
        chains.append({
            "blocker_pid": 12345, "blocker_query": "UPDATE accounts SET ...",
            "blocked_pid": 12351, "blocked_query": "SELECT * FROM accounts ...",
            "lock_type": "AccessShareLock", "wait_seconds": 30,
        })
    return {"server": server_name, "lock_chains": chains, "total_blocked": len(chains)}


TOOL_FUNCTIONS = {
    "check_replication_lag": check_replication_lag,
    "get_active_queries": get_active_queries,
    "kill_query": kill_query,
    "get_lock_chains": get_lock_chains,
}

# Safety classification
READ_ONLY_TOOLS = {"check_replication_lag", "get_active_queries", "get_lock_chains"}
WRITE_TOOLS = {"kill_query"}


# ============================================================
# ANOMALY DETECTOR (no LLM needed - pure Python)
# ============================================================

async def poll_server(server_name: str, config: dict) -> dict:
    """Simulate polling a server's pg_stat_activity."""
    await asyncio.sleep(random.uniform(0.05, 0.15))

    connections = random.randint(10, int(config["max_conn"] * 0.95))
    replication_lag = random.uniform(0, 8.0) if config["role"] == "replica" else 0.0
    long_queries = random.randint(0, 4)
    idle_in_tx = random.randint(0, 3)
    waiting_locks = random.randint(0, 8)

    return {
        "server": server_name,
        "role": config["role"],
        "connections": connections,
        "max_connections": config["max_conn"],
        "connection_percent": round(connections / config["max_conn"] * 100, 1),
        "replication_lag_seconds": round(replication_lag, 2),
        "long_running_queries": long_queries,
        "idle_in_transaction": idle_in_tx,
        "waiting_on_locks": waiting_locks,
    }


def detect_anomalies(poll_result: dict) -> list:
    """Check poll results against thresholds. Pure Python, no LLM."""
    anomalies = []

    if poll_result["connection_percent"] > THRESHOLDS["connection_percent"]:
        severity = "critical" if poll_result["connection_percent"] > 90 else "warning"
        anomalies.append({
            "type": "HIGH_CONNECTIONS",
            "severity": severity,
            "server": poll_result["server"],
            "value": poll_result["connection_percent"],
            "threshold": THRESHOLDS["connection_percent"],
            "message": (f"{poll_result['connection_percent']}% connections used "
                        f"({poll_result['connections']}/{poll_result['max_connections']})"),
        })

    if (poll_result["role"] == "replica" and
            poll_result["replication_lag_seconds"] > THRESHOLDS["replication_lag_seconds"]):
        anomalies.append({
            "type": "REPLICATION_LAG",
            "severity": "critical" if poll_result["replication_lag_seconds"] > 10 else "warning",
            "server": poll_result["server"],
            "value": poll_result["replication_lag_seconds"],
            "threshold": THRESHOLDS["replication_lag_seconds"],
            "message": f"Replication lag: {poll_result['replication_lag_seconds']}s",
        })

    if poll_result["idle_in_transaction"] > 0:
        anomalies.append({
            "type": "IDLE_IN_TRANSACTION",
            "severity": "warning",
            "server": poll_result["server"],
            "value": poll_result["idle_in_transaction"],
            "message": f"{poll_result['idle_in_transaction']} sessions idle in transaction",
        })

    if poll_result["waiting_on_locks"] > THRESHOLDS["waiting_on_locks"]:
        anomalies.append({
            "type": "LOCK_CONTENTION",
            "severity": "critical",
            "server": poll_result["server"],
            "value": poll_result["waiting_on_locks"],
            "threshold": THRESHOLDS["waiting_on_locks"],
            "message": f"{poll_result['waiting_on_locks']} queries waiting on locks",
        })

    return anomalies


# ============================================================
# LLM ANALYST (calls Claude when anomalies are found)
# ============================================================

def analyze_with_llm_simulated(anomalies: list) -> dict:
    """
    Simulate LLM analysis when no API key is available.
    In production, this calls Claude with the anomaly data.
    """
    # Group by type
    types = set(a["type"] for a in anomalies)
    servers = set(a["server"] for a in anomalies)
    critical_count = sum(1 for a in anomalies if a["severity"] == "critical")

    recommendations = []
    tools_to_call = []

    if "HIGH_CONNECTIONS" in types:
        recommendations.append("Investigate connection sources - check for connection leaks")
        tools_to_call.append({"name": "get_active_queries", "args": {"server_name": list(servers)[0], "min_duration_seconds": 0}})

    if "REPLICATION_LAG" in types:
        recommendations.append("Check WAL sender/receiver and network between primary and replica")
        for s in servers:
            if "replica" in s:
                tools_to_call.append({"name": "check_replication_lag", "args": {"server_name": s}})

    if "LOCK_CONTENTION" in types:
        recommendations.append("Identify blocking queries and consider terminating long holders")
        tools_to_call.append({"name": "get_lock_chains", "args": {"server_name": list(servers)[0]}})

    if "IDLE_IN_TRANSACTION" in types:
        recommendations.append("Find idle-in-transaction sessions - likely application bug or abandoned connection")
        tools_to_call.append({"name": "get_active_queries", "args": {"server_name": list(servers)[0], "min_duration_seconds": 60}})

    return {
        "analysis": f"Detected {len(anomalies)} anomalies across {len(servers)} server(s). {critical_count} critical.",
        "recommendations": recommendations,
        "tools_to_call": tools_to_call,
        "urgency": "high" if critical_count > 0 else "medium",
    }


async def analyze_with_llm_real(anomalies: list) -> dict:
    """
    Real LLM analysis using Anthropic Claude.
    Uncomment and use when ANTHROPIC_API_KEY is set.
    """
    try:
        import anthropic
        client = anthropic.Anthropic()

        anomaly_text = json.dumps(anomalies, indent=2)

        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=500,
            system=(
                "You are an autonomous PostgreSQL DBA agent. Analyze the anomalies "
                "and respond with JSON: "
                '{"analysis": "...", "recommendations": [...], '
                '"tools_to_call": [{"name": "tool_name", "args": {...}}], '
                '"urgency": "low|medium|high|critical"}'
                "\nAvailable tools: check_replication_lag, get_active_queries, "
                "get_lock_chains, kill_query. "
                "Only recommend kill_query for clearly problematic queries."
            ),
            messages=[{"role": "user", "content": f"Anomalies detected:\n{anomaly_text}"}],
        )

        return json.loads(response.content[0].text)
    except Exception as e:
        print(f"  LLM call failed: {e}")
        return analyze_with_llm_simulated(anomalies)


# ============================================================
# SAFETY LAYER
# ============================================================

class SafetyLayer:
    """
    Safety layer for agent actions.

    Rules:
      1. Read-only tools: always allowed
      2. Write tools: require confirmation (simulated as auto-approve in demo)
      3. Raw SQL: NEVER executed
      4. Rate limiting: max 3 write actions per cycle

    DBA analogy: like pg_hba.conf + role permissions.
    The agent has a role with limited permissions.
    """

    def __init__(self):
        self.write_actions_this_cycle = 0
        self.max_writes_per_cycle = 3
        self.blocked_actions = []

    def check_permission(self, tool_name: str, args: dict) -> tuple:
        """Returns (allowed: bool, reason: str)."""

        if tool_name in READ_ONLY_TOOLS:
            return True, "Read-only tool - always allowed"

        if tool_name in WRITE_TOOLS:
            if self.write_actions_this_cycle >= self.max_writes_per_cycle:
                self.blocked_actions.append({"tool": tool_name, "args": args,
                                             "reason": "Rate limit exceeded"})
                return False, f"Rate limit: max {self.max_writes_per_cycle} write actions per cycle"

            self.write_actions_this_cycle += 1
            return True, f"Write tool approved ({self.write_actions_this_cycle}/{self.max_writes_per_cycle})"

        return False, f"Unknown tool: {tool_name}"

    def reset_cycle(self):
        self.write_actions_this_cycle = 0


# ============================================================
# ACTION LOGGER
# ============================================================

class ActionLogger:
    """
    Log every agent action with full context.

    DBA analogy: like an audit log (pgaudit).
    Every action is recorded with who did it, when, why, and what happened.
    """

    def __init__(self):
        self.entries = []

    def log(self, action_type: str, details: dict):
        entry = {
            "timestamp": datetime.now().isoformat(),
            "action_type": action_type,
            **details,
        }
        self.entries.append(entry)

        # Console output
        severity = details.get("severity", "info")
        marker = {"critical": "!!!", "warning": " ! ", "info": "   "}.get(severity, "   ")
        print(f"  [{marker}] {action_type}: {details.get('message', json.dumps(details)[:80])}")

    def save(self, filepath: str):
        with open(filepath, "w") as f:
            json.dump(self.entries, f, indent=2)


# ============================================================
# AGENT STATE (persistence across restarts)
# ============================================================

class AgentState:
    """
    Persistent state that survives agent restarts.

    DBA analogy: like pg_control. The database reads this on
    startup to know where it left off.
    """

    def __init__(self, state_file: str):
        self.state_file = state_file
        self.data = {
            "cycles_completed": 0,
            "total_anomalies_detected": 0,
            "total_actions_taken": 0,
            "last_cycle_time": None,
            "known_issues": [],  # Issues already seen (dedup)
        }
        self._load()

    def _load(self):
        try:
            with open(self.state_file, "r") as f:
                self.data = json.load(f)
            print(f"  Loaded state from {self.state_file}")
            print(f"  Previous cycles: {self.data['cycles_completed']}")
        except FileNotFoundError:
            print(f"  No previous state found - starting fresh")

    def save(self):
        with open(self.state_file, "w") as f:
            json.dump(self.data, f, indent=2)

    def update(self, anomalies_count: int, actions_count: int):
        self.data["cycles_completed"] += 1
        self.data["total_anomalies_detected"] += anomalies_count
        self.data["total_actions_taken"] += actions_count
        self.data["last_cycle_time"] = datetime.now().isoformat()
        self.save()


# ============================================================
# THE AGENT (puts it all together)
# ============================================================

class AutonomousDBAAgent:
    """
    The autonomous DBA agent.

    Combines: async polling + anomaly detection + LLM analysis
              + tool execution + safety + logging + state.
    """

    def __init__(self):
        self.safety = SafetyLayer()
        self.logger = ActionLogger()
        self.state = AgentState(CONFIG["state_file"])

    async def poll_all_servers(self) -> list:
        """Poll all servers concurrently."""
        tasks = [
            poll_server(name, config)
            for name, config in SERVERS.items()
        ]
        return await asyncio.gather(*tasks, return_exceptions=True)

    async def run_cycle(self, cycle_num: int):
        """Run one monitoring cycle."""
        print(f"\n{'='*60}")
        print(f"  CYCLE {cycle_num} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"{'='*60}")

        # Step 1: Poll all servers
        self.logger.log("POLL_START", {"message": f"Polling {len(SERVERS)} servers", "severity": "info"})
        poll_results = await self.poll_all_servers()

        # Display poll results
        for result in poll_results:
            if isinstance(result, Exception):
                self.logger.log("POLL_ERROR", {"message": str(result), "severity": "critical"})
                continue

            conns = f"{result['connections']}/{result['max_connections']}"
            lag = f"lag={result['replication_lag_seconds']:.1f}s" if result["role"] == "replica" else ""
            print(f"    {result['server']:<18} conns={conns:<10} {lag}")

        # Step 2: Detect anomalies (pure Python, no LLM)
        all_anomalies = []
        for result in poll_results:
            if isinstance(result, Exception):
                continue
            anomalies = detect_anomalies(result)
            all_anomalies.extend(anomalies)

        if not all_anomalies:
            self.logger.log("NO_ANOMALIES", {"message": "All servers healthy", "severity": "info"})
            self.state.update(0, 0)
            return

        # Log anomalies
        for a in all_anomalies:
            self.logger.log("ANOMALY", {
                "message": f"[{a['server']}] {a['message']}",
                "severity": a["severity"],
                "type": a["type"],
            })

        # Step 3: LLM analysis (only when anomalies found)
        self.logger.log("LLM_ANALYSIS", {"message": f"Analyzing {len(all_anomalies)} anomalies", "severity": "info"})

        if CONFIG["llm_enabled"]:
            analysis = await analyze_with_llm_real(all_anomalies)
        else:
            analysis = analyze_with_llm_simulated(all_anomalies)

        print(f"\n    LLM Analysis: {analysis['analysis']}")
        print(f"    Urgency: {analysis['urgency']}")
        for rec in analysis.get("recommendations", []):
            print(f"    - {rec}")

        # Step 4: Execute recommended tools (with safety checks)
        actions_taken = 0
        for tool_call in analysis.get("tools_to_call", []):
            tool_name = tool_call["name"]
            args = tool_call["args"]

            # Safety check
            allowed, reason = self.safety.check_permission(tool_name, args)
            if not allowed:
                self.logger.log("BLOCKED", {
                    "message": f"{tool_name} blocked: {reason}",
                    "severity": "warning",
                })
                continue

            # Execute tool
            func = TOOL_FUNCTIONS.get(tool_name)
            if func:
                result = func(**args)
                self.logger.log("TOOL_EXECUTED", {
                    "message": f"{tool_name}({json.dumps(args)}) -> {json.dumps(result)[:80]}",
                    "severity": "info",
                })
                actions_taken += 1

        # Step 5: Update state
        self.safety.reset_cycle()
        self.state.update(len(all_anomalies), actions_taken)

    async def run(self):
        """Run the agent for configured number of cycles."""
        max_cycles = CONFIG["max_cycles"]
        interval = CONFIG["poll_interval_seconds"]

        print(f"\nAutonomous DBA Agent Starting")
        print(f"  Servers: {list(SERVERS.keys())}")
        print(f"  Poll interval: {interval}s")
        print(f"  Max cycles: {max_cycles} (0 = infinite)")
        print(f"  LLM enabled: {CONFIG['llm_enabled']}")
        print(f"  State file: {CONFIG['state_file']}")

        cycle = 1
        try:
            while max_cycles == 0 or cycle <= max_cycles:
                await self.run_cycle(cycle)
                cycle += 1
                if max_cycles == 0 or cycle <= max_cycles:
                    await asyncio.sleep(interval)

        except KeyboardInterrupt:
            print("\n\n  Agent stopped by user (Ctrl+C)")

        # Final report
        print(f"\n{'='*60}")
        print(f"  AGENT SHUTDOWN")
        print(f"{'='*60}")
        print(f"  Cycles completed: {self.state.data['cycles_completed']}")
        print(f"  Total anomalies: {self.state.data['total_anomalies_detected']}")
        print(f"  Total actions: {self.state.data['total_actions_taken']}")
        print(f"  State saved to: {CONFIG['state_file']}")

        # Save logs
        self.logger.save(CONFIG["log_file"])
        print(f"  Logs saved to: {CONFIG['log_file']}")

        self.state.save()


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    agent = AutonomousDBAAgent()
    asyncio.run(agent.run())
```

Save and exit vi (`:wq`).

---

## Step 3. Run the agent

On your **Mac terminal**, run:

```bash
python3 /tmp/dba_agent.py
```

Expected output (yours will differ):
```
  No previous state found - starting fresh

Autonomous DBA Agent Starting
  Servers: ['pg-primary', 'pg-replica-1', 'pg-replica-2']
  Poll interval: 5s
  Max cycles: 5 (0 = infinite)
  LLM enabled: False
  State file: /tmp/dba_agent_state.json

============================================================
  CYCLE 1 - 2026-06-15 14:30:00
============================================================
  [   ] POLL_START: Polling 3 servers
    pg-primary         conns=87/200
    pg-replica-1       conns=156/200    lag=3.2s
    pg-replica-2       conns=45/200     lag=1.1s
  [   ] NO_ANOMALIES: All servers healthy

============================================================
  CYCLE 2 - 2026-06-15 14:30:05
============================================================
  [   ] POLL_START: Polling 3 servers
    pg-primary         conns=178/200
    pg-replica-1       conns=42/200     lag=6.8s
    pg-replica-2       conns=90/200     lag=0.5s
  [ ! ] ANOMALY: [pg-primary] 89.0% connections used (178/200)
  [!!!] ANOMALY: [pg-replica-1] Replication lag: 6.8s
  [   ] LLM_ANALYSIS: Analyzing 2 anomalies

    LLM Analysis: Detected 2 anomalies across 2 server(s). 1 critical.
    Urgency: high
    - Investigate connection sources - check for connection leaks
    - Check WAL sender/receiver and network between primary and replica
  [   ] TOOL_EXECUTED: get_active_queries({"server_name": "pg-primary"...
  [   ] TOOL_EXECUTED: check_replication_lag({"server_name": "pg-replica...
...

============================================================
  AGENT SHUTDOWN
============================================================
  Cycles completed: 5
  Total anomalies: 11
  Total actions: 8
  State saved to: /tmp/dba_agent_state.json
  Logs saved to: /tmp/dba_agent_log.json
```

---

## Step 4. Inspect the agent's state and logs

On your **Mac terminal**, check the saved state:

```bash
python3 << 'PYEOF'
import json

print("Agent State")
print("=" * 50)

# Load and display state
with open("/tmp/dba_agent_state.json") as f:
    state = json.load(f)
print(json.dumps(state, indent=2))

print(f"\nAgent Log (last 5 entries)")
print("=" * 50)

with open("/tmp/dba_agent_log.json") as f:
    log = json.load(f)

for entry in log[-5:]:
    print(f"  [{entry['timestamp'][:19]}] {entry['action_type']}: {entry.get('message', '')[:70]}")

print(f"\nTotal log entries: {len(log)}")

# Summarize by type
from collections import Counter
type_counts = Counter(e["action_type"] for e in log)
print("\nActions by type:")
for action_type, count in type_counts.most_common():
    print(f"  {action_type:<20} {count}")
PYEOF
```

Expected output (yours will differ):
```
Agent State
==================================================
{
  "cycles_completed": 5,
  "total_anomalies_detected": 11,
  "total_actions_taken": 8,
  "last_cycle_time": "2026-06-15T14:30:25.123456",
  "known_issues": []
}

Agent Log (last 5 entries)
==================================================
  [2026-06-15T14:30:2] ANOMALY: [pg-replica-1] Replication lag: 7.2s
  [2026-06-15T14:30:2] LLM_ANALYSIS: Analyzing 3 anomalies
  [2026-06-15T14:30:2] TOOL_EXECUTED: check_replication_lag({"server_name": "pg-...
  [2026-06-15T14:30:2] TOOL_EXECUTED: get_lock_chains({"server_name": "pg-primary...
  [2026-06-15T14:30:2] TOOL_EXECUTED: get_active_queries({"server_name": "pg-prim...

Total log entries: 34

Actions by type:
  POLL_START           5
  ANOMALY              11
  TOOL_EXECUTED        8
  LLM_ANALYSIS         4
  NO_ANOMALIES         1
  BLOCKED              0
```

---

## Step 5. Enable real LLM analysis (optional)

If you have an Anthropic API key set, you can enable real LLM analysis.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import os

# Check if API key is available
key = os.environ.get("ANTHROPIC_API_KEY", "")
if key:
    print("ANTHROPIC_API_KEY is set - you can enable LLM analysis!")
    print()
    print("To enable, edit /tmp/dba_agent.py and change:")
    print('  "llm_enabled": False')
    print("to:")
    print('  "llm_enabled": True')
    print()
    print("Then run: python3 /tmp/dba_agent.py")
    print()
    print("The agent will call Claude for each batch of anomalies.")
    print("Cost: ~$0.005-0.02 per cycle (depending on anomalies).")
    print("For 5 cycles: ~$0.02-0.10 total.")
else:
    print("ANTHROPIC_API_KEY not set.")
    print("The agent runs fine without it using simulated analysis.")
    print("Set the key in ~/.zshrc to enable real LLM analysis.")
PYEOF
```

---

## Step 6. Restart and resume from saved state

On your **Mac terminal**, run the agent again:

```bash
python3 /tmp/dba_agent.py
```

Expected output (yours will differ):
```
  Loaded state from /tmp/dba_agent_state.json
  Previous cycles: 5

Autonomous DBA Agent Starting
  Servers: ['pg-primary', 'pg-replica-1', 'pg-replica-2']
  ...

============================================================
  CYCLE 1 - 2026-06-15 14:35:00
============================================================
...

============================================================
  AGENT SHUTDOWN
============================================================
  Cycles completed: 10
  Total anomalies: 23
  Total actions: 17
...
```

The agent resumed from where it left off. The cycle count accumulated across restarts.

---

## What You Learned

| Component | What It Does | DBA Analogy |
|-----------|-------------|-------------|
| Monitor loop | Async polling of all servers | cron job running health checks |
| Anomaly detector | Threshold-based detection (no LLM) | Nagios/Zabbix alert rules |
| LLM analyst | Analyzes anomalies and recommends actions | Senior DBA reviewing alerts |
| Tool executor | Runs DBA tools based on LLM recommendations | DBA executing investigation steps |
| Safety layer | Read-only by default, rate-limited writes | pg_hba.conf + role permissions |
| Action logger | Full audit trail of every decision | pgaudit extension |
| Agent state | Persistent state across restarts | pg_control file |
| Graceful shutdown | Save state on Ctrl+C | Checkpoint on shutdown |
