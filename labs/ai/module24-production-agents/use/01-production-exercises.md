# Use 01: Production Agent Exercises

Module 24 - Production Agent Systems
Audience: DBAs with no Python background
Prerequisite: Module 18 (multi-agent basics), Python3 installed on Mac

---

## How to read this guide

Every Python line is explained. Where a DBA analogy helps, it is used. All scripts run
as standalone heredoc blocks - paste the entire block into your terminal and press Enter.

---

## Exercise 1: Build an MCP Server with 3 PostgreSQL Diagnostic Tools

### What you are building

An MCP server that exposes three PostgreSQL diagnostic tools: a lock inspector, a
checkpoint monitor, and a WAL generation tracker. Any MCP-compatible AI client can
connect and call these tools.

**DBA analogy:** You are creating three stored procedures and registering them in a
catalog so that authorized clients can discover and call them.

### Code

On your **Mac terminal**, create the MCP server file:

```bash
vi /tmp/exercise_mcp_server.py
```

Paste this content:

```python
from fastmcp import FastMCP
import json
import datetime

mcp = FastMCP(name="PostgreSQL Diagnostics Lab")


@mcp.tool()
def inspect_locks(database: str) -> str:
    """Inspect current lock activity in a database.
    Returns blocking and waiting queries with lock types.
    Use when investigating lock contention or deadlocks."""

    # In production: SELECT * FROM pg_locks JOIN pg_stat_activity ...
    simulated = {
        "production": {
            "total_locks": 47,
            "blocking_pids": [14523],
            "waiting_pids": [14801, 15002, 15100],
            "lock_types": {"RowExclusiveLock": 30, "AccessShareLock": 12, "ExclusiveLock": 5},
            "longest_wait_seconds": 45.2
        },
        "staging": {
            "total_locks": 8,
            "blocking_pids": [],
            "waiting_pids": [],
            "lock_types": {"AccessShareLock": 8},
            "longest_wait_seconds": 0
        }
    }
    data = simulated.get(database, {"total_locks": 0, "blocking_pids": [], "waiting_pids": [], "lock_types": {}, "longest_wait_seconds": 0})
    data["database"] = database
    data["status"] = "CRITICAL" if data["longest_wait_seconds"] > 30 else "WARNING" if data["longest_wait_seconds"] > 10 else "OK"
    data["checked_at"] = datetime.datetime.now().isoformat()
    return json.dumps(data, indent=2)


@mcp.tool()
def check_checkpoints() -> str:
    """Check checkpoint frequency and duration.
    Returns checkpoint stats from pg_stat_checkpointer.
    Use when investigating I/O spikes or WAL buildup."""

    # In production: SELECT * FROM pg_stat_checkpointer;
    data = {
        "checkpoints_timed": 142,
        "checkpoints_requested": 18,
        "checkpoint_write_time_ms": 45200,
        "checkpoint_sync_time_ms": 1200,
        "buffers_written": 89000,
        "avg_checkpoint_interval_seconds": 290,
        "status": "WARNING" if 18 > 10 else "OK",
        "note": "18 requested checkpoints suggest max_wal_size may be too small",
        "checked_at": datetime.datetime.now().isoformat()
    }
    return json.dumps(data, indent=2)


@mcp.tool()
def check_wal_generation(hours: int) -> str:
    """Check WAL generation rate over the specified number of hours.
    Returns WAL bytes generated and rate per hour.
    Use when planning archive storage or diagnosing replication lag."""

    # In production: SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') ...
    wal_per_hour_mb = 450
    total_mb = wal_per_hour_mb * hours
    data = {
        "period_hours": hours,
        "total_wal_generated_mb": total_mb,
        "avg_wal_per_hour_mb": wal_per_hour_mb,
        "avg_wal_per_minute_mb": round(wal_per_hour_mb / 60, 1),
        "estimated_daily_gb": round((wal_per_hour_mb * 24) / 1024, 1),
        "status": "WARNING" if wal_per_hour_mb > 400 else "OK",
        "checked_at": datetime.datetime.now().isoformat()
    }
    return json.dumps(data, indent=2)


if __name__ == "__main__":
    mcp.run()
```

Save and close vi (`:wq`).

Now test the tools directly on your **Mac terminal**:

```bash
python3 << 'PYEOF'
import sys
sys.path.insert(0, "/tmp")
from exercise_mcp_server import inspect_locks, check_checkpoints, check_wal_generation

print("=== MCP SERVER TOOL TESTS ===\n")

print("--- inspect_locks('production') ---")
print(inspect_locks(database="production"))

print("\n--- check_checkpoints() ---")
print(check_checkpoints())

print("\n--- check_wal_generation(24) ---")
print(check_wal_generation(hours=24))

print("\nAll 3 tools working. Server ready for MCP clients.")

PYEOF
```

Expected output (yours will differ):
```
=== MCP SERVER TOOL TESTS ===

--- inspect_locks('production') ---
{
  "total_locks": 47,
  "blocking_pids": [14523],
  "waiting_pids": [14801, 15002, 15100],
  "lock_types": {"RowExclusiveLock": 30, "AccessShareLock": 12, "ExclusiveLock": 5},
  "longest_wait_seconds": 45.2,
  "database": "production",
  "status": "CRITICAL",
  ...
}

--- check_checkpoints() ---
{
  "checkpoints_timed": 142,
  "checkpoints_requested": 18,
  ...
  "status": "WARNING"
}

--- check_wal_generation(24) ---
{
  "period_hours": 24,
  "total_wal_generated_mb": 10800,
  ...
  "estimated_daily_gb": 10.5
}

All 3 tools working. Server ready for MCP clients.
```

---

## Exercise 2: Create a Slack Notification Function for Agent Alerts

### What you are building

A reusable Slack notification function that formats DBA alerts with severity-based
formatting, structured fields, and actionable recommendations.

**DBA analogy:** You are building a `pg_notify()` wrapper that formats the payload
as a rich Slack message instead of plain text.

### Code

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import urllib.request
import json
import datetime


def notify_slack(webhook_url: str, alert: dict) -> dict:
    """
    Send a formatted DBA alert to Slack.

    Parameters:
        webhook_url - Slack incoming webhook URL
        alert       - dict with keys: severity, database, metric, value, diagnosis, action

    Returns:
        dict with success status and details
    """
    severity = alert.get("severity", "UNKNOWN")
    emoji_map = {"CRITICAL": ":rotating_light:", "WARNING": ":warning:", "OK": ":white_check_mark:"}
    emoji = emoji_map.get(severity, ":question:")

    payload = {
        "text": f"{emoji} [{severity}] {alert.get('database', 'unknown')}: {alert.get('metric', '')}",
        "blocks": [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": f"{emoji} [{severity}] Database Alert"}
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Database:*\n{alert.get('database', 'N/A')}"},
                    {"type": "mrkdwn", "text": f"*Metric:*\n{alert.get('metric', 'N/A')} = {alert.get('value', 'N/A')}"},
                    {"type": "mrkdwn", "text": f"*Severity:*\n{severity}"},
                    {"type": "mrkdwn", "text": f"*Time:*\n{datetime.datetime.now().strftime('%H:%M:%S')}"}
                ]
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": f"*Diagnosis:*\n{alert.get('diagnosis', 'No diagnosis available')}"}
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": f"*Recommended Action:*\n```{alert.get('action', 'No action specified')}```"}
            }
        ]
    }

    req = urllib.request.Request(
        url=webhook_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {"success": True, "status_code": response.status}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ---------------------------------------------------------
# TEST WITH MULTIPLE ALERT TYPES
# ---------------------------------------------------------

print("=== SLACK NOTIFICATION TEST ===\n")

test_alerts = [
    {
        "severity": "CRITICAL",
        "database": "production",
        "metric": "active_connections",
        "value": "199/200",
        "diagnosis": "reporting_app holding 142 idle connections without pooling",
        "action": "pg_terminate_backend(pid) for idle > 10 min\nDeploy PgBouncer"
    },
    {
        "severity": "WARNING",
        "database": "analytics",
        "metric": "disk_usage_percent",
        "value": "82%",
        "diagnosis": "Large unvacuumed tables consuming excess space",
        "action": "VACUUM FULL public.event_log;\nArchive data older than 90 days"
    },
    {
        "severity": "OK",
        "database": "staging",
        "metric": "replication_lag",
        "value": "0.3s",
        "diagnosis": "All replicas healthy and caught up",
        "action": "No action needed"
    }
]

for alert in test_alerts:
    result = notify_slack("https://httpbin.org/post", alert)
    status = "SENT" if result["success"] else "FAILED"
    print(f"  [{alert['severity']}] {alert['database']}: {alert['metric']} = {alert['value']} -> {status}")

print("\nAll notifications sent to httpbin.org (test endpoint).")
print("Replace URL with your Slack webhook for real notifications.")

PYEOF
```

Expected output (yours will differ):
```
=== SLACK NOTIFICATION TEST ===

  [CRITICAL] production: active_connections = 199/200 -> SENT
  [WARNING] analytics: disk_usage_percent = 82% -> SENT
  [OK] staging: replication_lag = 0.3s -> SENT

All notifications sent to httpbin.org (test endpoint).
Replace URL with your Slack webhook for real notifications.
```

---

## Exercise 3: Implement a Feedback Loop

### What you are building

A feedback loop that stores DBA corrections, retrieves them when similar alerts
appear, and tracks accuracy improvement over time.

**DBA analogy:** You are building a `pg_stat_statements` equivalent for your agent
that tracks not just performance, but correctness. When the DBA says "wrong," the
agent remembers and uses that correction next time.

### Code

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import datetime


class FeedbackLoop:
    """
    Stores DBA corrections and retrieves them for similar alerts.
    DBA analogy: a correction_log table with full-text search.
    """

    def __init__(self):
        self.feedback = []
        self.accuracy_log = []

    def store_feedback(self, alert_text: str, agent_answer: str,
                       dba_rating: str, dba_correction: str = ""):
        record = {
            "id": len(self.feedback) + 1,
            "alert_text": alert_text,
            "keywords": set(alert_text.lower().replace(",", " ").replace("=", " ").split()),
            "agent_answer": agent_answer,
            "dba_rating": dba_rating,
            "dba_correction": dba_correction,
            "timestamp": datetime.datetime.now().isoformat()
        }
        self.feedback.append(record)
        self.accuracy_log.append(dba_rating)
        return record["id"]

    def retrieve_corrections(self, alert_text: str) -> list:
        """Find past corrections for similar alerts using keyword overlap."""
        alert_keywords = set(alert_text.lower().replace(",", " ").replace("=", " ").split())
        matches = []
        for fb in self.feedback:
            if fb["dba_rating"] in ("wrong", "partial"):
                overlap = len(alert_keywords & fb["keywords"])
                if overlap >= 2:
                    matches.append({"correction": fb["dba_correction"], "score": overlap})
        matches.sort(key=lambda x: x["score"], reverse=True)
        return matches

    def get_accuracy(self) -> float:
        if not self.accuracy_log:
            return 0.0
        correct = self.accuracy_log.count("correct")
        partial = self.accuracy_log.count("partial") * 0.5
        return round((correct + partial) / len(self.accuracy_log) * 100, 1)


# ---------------------------------------------------------
# SIMULATE THE FEEDBACK LOOP
# ---------------------------------------------------------

loop = FeedbackLoop()

print("=== FEEDBACK LOOP EXERCISE ===\n")

# Round 1: Agent gets replication lag wrong
print("Round 1: Agent misdiagnoses replication lag")
print("  Agent says: 'Network issue causing lag'")
print("  DBA says: 'Wrong - it is a long-running transaction holding the slot'")
loop.store_feedback(
    "replication_lag_seconds=400, replay_lsn stuck",
    "Network issue causing lag",
    "wrong",
    "Long-running transaction holding replication slot. "
    "Find the oldest idle-in-transaction session and terminate it."
)
print(f"  Accuracy: {loop.get_accuracy()}%")

# Round 2: Similar alert - agent should find the past correction
print("\nRound 2: Similar replication lag alert")
corrections = loop.retrieve_corrections("replication_lag_seconds=250, replay_lsn not moving")
if corrections:
    print(f"  Found {len(corrections)} past correction(s)")
    print(f"  Using: {corrections[0]['correction'][:60]}...")
    print("  Agent now says: 'Based on past feedback - check for blocking transaction'")
    loop.store_feedback(
        "replication_lag_seconds=250, replay_lsn not moving",
        "Blocking transaction - per past DBA feedback",
        "correct"
    )
else:
    print("  No past corrections found")
print(f"  Accuracy: {loop.get_accuracy()}%")

# Round 3: New type - agent gets it right
print("\nRound 3: Connection exhaustion alert (new type)")
loop.store_feedback(
    "active_connections=198, max_connections=200",
    "Connection pool exhaustion - deploy PgBouncer",
    "correct"
)
print(f"  Agent got it correct. Accuracy: {loop.get_accuracy()}%")

# Round 4: Bloat alert - partially correct
print("\nRound 4: Table bloat alert")
loop.store_feedback(
    "dead_tuples=9000000, autovacuum_count=0, table=orders",
    "Run VACUUM ANALYZE on orders table",
    "partial",
    "Need pg_repack not VACUUM ANALYZE for this level of bloat. Also check autovacuum settings."
)
print(f"  Partial credit. Accuracy: {loop.get_accuracy()}%")

# Summary
print(f"\n--- Feedback Loop Summary ---")
print(f"  Total alerts: {len(loop.accuracy_log)}")
print(f"  Correct: {loop.accuracy_log.count('correct')}")
print(f"  Partial: {loop.accuracy_log.count('partial')}")
print(f"  Wrong:   {loop.accuracy_log.count('wrong')}")
print(f"  Final accuracy: {loop.get_accuracy()}%")
print(f"  Stored corrections: {sum(1 for f in loop.feedback if f['dba_rating'] in ('wrong', 'partial'))}")

PYEOF
```

Expected output (yours will differ):
```
=== FEEDBACK LOOP EXERCISE ===

Round 1: Agent misdiagnoses replication lag
  Agent says: 'Network issue causing lag'
  DBA says: 'Wrong - it is a long-running transaction holding the slot'
  Accuracy: 0.0%

Round 2: Similar replication lag alert
  Found 1 past correction(s)
  Using: Long-running transaction holding replication slot. Find the ...
  Agent now says: 'Based on past feedback - check for blocking transaction'
  Accuracy: 50.0%

Round 3: Connection exhaustion alert (new type)
  Agent got it correct. Accuracy: 66.7%

Round 4: Table bloat alert
  Partial credit. Accuracy: 62.5%

--- Feedback Loop Summary ---
  Total alerts: 4
  Correct: 2
  Partial: 1
  Wrong:   1
  Final accuracy: 62.5%
  Stored corrections: 2
```

---

## Exercise 4: Add Observability Logging to an Existing Agent

### What you are building

A logging decorator that wraps any agent tool function and automatically records
timing, token usage (simulated), and errors. You will apply it to three existing
functions and generate a performance report.

**DBA analogy:** You are adding `log_min_duration_statement` and `pg_stat_statements`
tracking to your agent's tool calls.

### Code

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import json
import datetime

# ---------------------------------------------------------
# OBSERVABILITY DECORATOR
# ---------------------------------------------------------

metrics = []

def observe(func):
    """
    Decorator that logs timing, success/failure, and simulated token usage
    for every function call. Appends a record to the metrics list.

    DBA analogy: like auto_explain logging every query with its execution time.
    """
    def wrapper(*args, **kwargs):
        start = time.time()
        success = True
        error_msg = None
        result = None

        try:
            result = func(*args, **kwargs)
        except Exception as e:
            success = False
            error_msg = str(e)
            raise
        finally:
            elapsed_ms = round((time.time() - start) * 1000, 2)
            record = {
                "function": func.__name__,
                "args": str(args)[:50],
                "duration_ms": elapsed_ms,
                "success": success,
                "error": error_msg,
                "tokens_estimate": len(str(args)) + len(str(result or "")),
                "timestamp": datetime.datetime.now().isoformat()
            }
            metrics.append(record)

        return result
    return wrapper


# ---------------------------------------------------------
# AGENT TOOLS WITH OBSERVABILITY
# ---------------------------------------------------------

@observe
def classify_alert(alert_text: str) -> str:
    time.sleep(0.03)
    if "connection" in alert_text.lower():
        return "CRITICAL"
    elif "lag" in alert_text.lower():
        return "WARNING"
    return "OK"

@observe
def diagnose_alert(alert_text: str) -> str:
    time.sleep(0.05)
    if "fail" in alert_text.lower():
        raise RuntimeError("Cannot diagnose: data source unavailable")
    return f"Root cause analysis for: {alert_text[:30]}"

@observe
def send_notification(channel: str, message: str) -> str:
    time.sleep(0.02)
    return f"Sent to {channel}: {message[:30]}"


# ---------------------------------------------------------
# RUN MULTIPLE OPERATIONS
# ---------------------------------------------------------

print("=== OBSERVABILITY EXERCISE ===\n")
print("Running agent operations...\n")

# Normal operations
classify_alert("active_connections=199, max=200")
diagnose_alert("active_connections=199, max=200")
send_notification("#dba-alerts", "CRITICAL: connection exhaustion on production")

classify_alert("replication_lag=5s")
diagnose_alert("replication_lag=5s")
send_notification("#dba-alerts", "WARNING: replication lag on standby-2")

classify_alert("cpu_percent=35")

# This one will fail
try:
    diagnose_alert("fail: data source timeout")
except RuntimeError:
    pass

classify_alert("disk_usage=92%")
send_notification("#dba-alerts", "OK: daily health check passed")

# ---------------------------------------------------------
# PERFORMANCE REPORT
# ---------------------------------------------------------

print(f"{'Function':<20} {'Duration':<12} {'Success':<10} {'Tokens':<8}")
print("-" * 55)
for m in metrics:
    status = "OK" if m["success"] else "ERROR"
    print(f"{m['function']:<20} {m['duration_ms']:<12} {status:<10} {m['tokens_estimate']:<8}")

# Summary
total = len(metrics)
errors = sum(1 for m in metrics if not m["success"])
avg_ms = round(sum(m["duration_ms"] for m in metrics) / total, 1)
total_tokens = sum(m["tokens_estimate"] for m in metrics)

print(f"\n--- Summary ---")
print(f"  Total calls:   {total}")
print(f"  Errors:        {errors} ({errors/total*100:.0f}%)")
print(f"  Avg latency:   {avg_ms}ms")
print(f"  Total tokens:  {total_tokens}")

PYEOF
```

Expected output (yours will differ):
```
=== OBSERVABILITY EXERCISE ===

Running agent operations...

Function             Duration     Success    Tokens
-------------------------------------------------------
classify_alert       31.5         OK         56
diagnose_alert       52.3         OK         78
send_notification    21.1         OK         85
classify_alert       30.8         OK         38
diagnose_alert       51.7         OK         60
send_notification    20.5         OK         72
classify_alert       30.2         OK         28
diagnose_alert       50.9         ERROR      0
classify_alert       31.0         OK         30
send_notification    20.8         OK         64

--- Summary ---
  Total calls:   10
  Errors:        1 (10%)
  Avg latency:   34.1ms
  Total tokens:  511
```

---

## Exercise 5: Build a Complete Alert-to-Resolution Pipeline

### What you are building

A full pipeline: receive alert -> diagnose -> check past feedback -> recommend ->
notify -> log everything. This combines all four BUILD guides into one working system.

**DBA analogy:** This is the complete on-call workflow encoded as code: alert fires,
DBA diagnoses, DBA checks past incidents, DBA communicates, DBA logs everything.

### Code

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
import datetime
import urllib.request

# ---------------------------------------------------------
# COMPONENTS (simplified from BUILD guides)
# ---------------------------------------------------------

# Logging
log_entries = []
def log(level, action, details, duration_ms=None):
    entry = {"ts": datetime.datetime.now().isoformat()[:19], "level": level,
             "action": action, "details": details, "ms": duration_ms}
    log_entries.append(entry)

# Feedback database
feedback_db = [
    {"keywords": ["replication", "lag", "replay_lsn"],
     "correction": "Check for long-running transactions holding replication slots before blaming network"},
    {"keywords": ["dead_tuples", "bloat", "autovacuum"],
     "correction": "Use pg_repack for >20% bloat. Check autovacuum settings on the table."},
]

def check_feedback(alert_text):
    text = alert_text.lower()
    for fb in feedback_db:
        matches = sum(1 for kw in fb["keywords"] if kw in text)
        if matches >= 2:
            return fb["correction"]
    return None

# Diagnosis
def diagnose(alert):
    start = time.time()
    text = alert["metric"].lower()

    # Check feedback first
    past = check_feedback(f"{alert['metric']} {alert.get('extra', '')}")

    if past:
        result = {"severity": "CRITICAL", "diagnosis": f"[Feedback] {past}",
                  "source": "feedback"}
    elif "connection" in text and alert["value"] > 180:
        result = {"severity": "CRITICAL", "diagnosis": "Connection pool near exhaustion",
                  "source": "rules"}
    elif "lag" in text and alert["value"] > 60:
        result = {"severity": "WARNING", "diagnosis": "Replication lag elevated",
                  "source": "rules"}
    else:
        result = {"severity": "OK", "diagnosis": "Within normal range", "source": "rules"}

    elapsed = round((time.time() - start) * 1000, 2)
    log("INFO", "diagnose", {"metric": alert["metric"], "severity": result["severity"]}, elapsed)
    return result

# Notification
def notify(severity, database, summary):
    start = time.time()
    payload = {"text": f"[{severity}] {database}: {summary}"}
    try:
        req = urllib.request.Request(
            "https://httpbin.org/post",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        response = urllib.request.urlopen(req, timeout=10)
        elapsed = round((time.time() - start) * 1000, 2)
        log("INFO", "notify", {"service": "slack", "status": "sent"}, elapsed)
        return True
    except Exception as e:
        elapsed = round((time.time() - start) * 1000, 2)
        log("ERROR", "notify", {"service": "slack", "error": str(e)}, elapsed)
        return False

# ---------------------------------------------------------
# PIPELINE ORCHESTRATOR
# ---------------------------------------------------------

def process_alert(alert):
    """Full pipeline: diagnose -> check feedback -> recommend -> notify -> log."""
    database = alert["database"]
    metric = alert["metric"]
    value = alert["value"]
    extra = alert.get("extra", "")

    print(f"\n{'=' * 55}")
    print(f"ALERT: {metric} = {value} on {database}")
    print(f"{'=' * 55}")

    # Step 1: Diagnose
    start = time.time()
    result = diagnose(alert)
    print(f"  [1] Diagnosis: [{result['severity']}] {result['diagnosis']}")
    print(f"      Source: {result['source']}")

    # Step 2: Notify
    notify_result = notify(result["severity"], database,
                           f"{metric}={value}: {result['diagnosis']}")
    print(f"  [2] Notification: {'sent' if notify_result else 'FAILED'}")

    # Step 3: Log completion
    total_ms = round((time.time() - start) * 1000, 2)
    log("INFO", "pipeline_complete", {
        "alert": f"{metric}={value}",
        "severity": result["severity"],
        "source": result["source"]
    }, total_ms)
    print(f"  [3] Logged. Total time: {total_ms}ms")

    return result


# ---------------------------------------------------------
# RUN THE PIPELINE
# ---------------------------------------------------------

print("COMPLETE ALERT-TO-RESOLUTION PIPELINE")
print("=" * 55)

alerts = [
    {"database": "production", "metric": "active_connections", "value": 195, "extra": ""},
    {"database": "production", "metric": "replication_lag_seconds", "value": 300,
     "extra": "replay_lsn stuck"},
    {"database": "analytics", "metric": "dead_tuples", "value": 9500000,
     "extra": "bloat autovacuum_count=0"},
    {"database": "staging", "metric": "cpu_percent", "value": 42, "extra": ""},
]

for alert in alerts:
    process_alert(alert)

# ---------------------------------------------------------
# PIPELINE REPORT
# ---------------------------------------------------------

print(f"\n{'=' * 55}")
print("PIPELINE REPORT")
print(f"{'=' * 55}")

print(f"\n  Log entries: {len(log_entries)}")
print(f"\n  {'Action':<20} {'Level':<8} {'Duration':<10} {'Details'}")
print(f"  {'-' * 65}")
for entry in log_entries:
    detail_str = str(entry["details"])[:40]
    ms_str = f"{entry['ms']}ms" if entry['ms'] else "N/A"
    print(f"  {entry['action']:<20} {entry['level']:<8} {ms_str:<10} {detail_str}")

errors = sum(1 for e in log_entries if e["level"] == "ERROR")
total_time = sum(e["ms"] for e in log_entries if e["ms"])
print(f"\n  Total pipeline time: {total_time:.0f}ms")
print(f"  Errors: {errors}")
print(f"  Alerts processed: {len(alerts)}")

PYEOF
```

Expected output (yours will differ):
```
COMPLETE ALERT-TO-RESOLUTION PIPELINE
=======================================================

=======================================================
ALERT: active_connections = 195 on production
=======================================================
  [1] Diagnosis: [CRITICAL] Connection pool near exhaustion
      Source: rules
  [2] Notification: sent
  [3] Logged. Total time: 250ms

=======================================================
ALERT: replication_lag_seconds = 300 on production
=======================================================
  [1] Diagnosis: [CRITICAL] [Feedback] Check for long-running transactions...
      Source: feedback
  [2] Notification: sent
  [3] Logged. Total time: 240ms

=======================================================
ALERT: dead_tuples = 9500000 on analytics
=======================================================
  [1] Diagnosis: [CRITICAL] [Feedback] Use pg_repack for >20% bloat...
      Source: feedback
  [2] Notification: sent
  [3] Logged. Total time: 235ms

=======================================================
ALERT: cpu_percent = 42 on staging
=======================================================
  [1] Diagnosis: [OK] Within normal range
      Source: rules
  [2] Notification: sent
  [3] Logged. Total time: 230ms

=======================================================
PIPELINE REPORT
=======================================================

  Log entries: 12
  ...
  Total pipeline time: 955ms
  Errors: 0
  Alerts processed: 4
```

---

## Summary

| Exercise | Pattern | DBA Analogy |
|----------|---------|-------------|
| 1 | MCP server with diagnostic tools | Stored procedures in a tool catalog |
| 2 | Slack notification function | `pg_notify()` with rich formatting |
| 3 | Feedback loop with retrieval | `pg_stat_statements` for correctness tracking |
| 4 | Observability decorator | `auto_explain` + `log_min_duration_statement` |
| 5 | Complete alert-to-resolution pipeline | Full on-call DBA workflow as code |

Next: Module 24 Survive labs - what happens when APIs fail or feedback gets poisoned.
