# Build 04: Agent Observability

## Why Agent Observability Matters

You would never run a PostgreSQL database in production without `pg_stat_activity`, `pg_stat_statements`, and log monitoring. Your agents need the same treatment. Without observability, you cannot tell if the agent is slow, expensive, inaccurate, or broken.

**DBA analogy:** Agent observability is `pg_stat_*` views for your AI system. Just as you monitor connections, query performance, cache hit ratios, and replication lag, you need to monitor agent response times, tool call counts, token usage, error rates, and accuracy.

```
PostgreSQL observability:
  pg_stat_activity    - what is running right now
  pg_stat_statements  - historical query performance
  pg_stat_bgwriter    - background process health
  postgresql.log      - detailed event log

Agent observability:
  Active requests      - what is the agent processing right now
  Request history      - historical performance per alert type
  Tool call metrics    - which tools are called most, which are slowest
  Agent log            - every decision with full context
```

---

## Step 1: Structured Logging

### The Concept

Every agent decision must be logged with enough context to reconstruct what happened. This is not `print()` debugging - it is structured logging that can be queried and analyzed.

**DBA analogy:** This is the difference between `log_statement = 'all'` (noisy, hard to parse) and `pg_stat_statements` (structured, queryable). We want the `pg_stat_statements` version for our agent.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a structured logging system for agent operations.
#   Every decision is logged as a JSON record with full context.
#   Logs can be queried, filtered, and analyzed.
# ---------------------------------------------------------

import json
import datetime
import time

# ---------------------------------------------------------
# STRUCTURED LOGGER
# ---------------------------------------------------------

class AgentLogger:
    """
    Structured logging for agent operations.

    Every log entry is a JSON dict with standardized fields.
    This makes logs queryable - you can filter by level, agent,
    tool, or time range.

    DBA analogy: like the PostgreSQL CSV log format.
    Each field is a column. You can COPY the log into a table
    and query it with SQL.
    """

    def __init__(self, log_file: str = "/tmp/agent_log.jsonl"):
        self.log_file = log_file
        self.entries = []

    def log(self, level: str, agent: str, action: str,
            details: dict = None, duration_ms: float = None):
        """
        Write a structured log entry.

        Parameters:
            level       - INFO, WARNING, ERROR (like PostgreSQL log_min_messages)
            agent       - which agent produced this entry
            action      - what happened (tool_call, diagnosis, notification, etc.)
            details     - additional context as a dict
            duration_ms - how long the action took in milliseconds
        """
        entry = {
            "timestamp": datetime.datetime.now().isoformat(),
            "level": level,
            "agent": agent,
            "action": action,
            "duration_ms": duration_ms,
            "details": details or {}
        }

        self.entries.append(entry)

        # Also write to file (append mode)
        # "a" means append - each entry gets one line
        # JSONL format = one JSON object per line (like CSV but for JSON)
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def query(self, level: str = None, agent: str = None,
              action: str = None, limit: int = 10) -> list:
        """
        Query the log entries with filters.

        DBA analogy: SELECT * FROM agent_log
                     WHERE level = 'ERROR'
                       AND agent = 'DiagnosisAgent'
                     ORDER BY timestamp DESC
                     LIMIT 10;
        """
        results = self.entries

        if level:
            results = [e for e in results if e["level"] == level]
        if agent:
            results = [e for e in results if e["agent"] == agent]
        if action:
            results = [e for e in results if e["action"] == action]

        # Return most recent first - like ORDER BY timestamp DESC
        return list(reversed(results[-limit:]))


# ---------------------------------------------------------
# TOOL CALL DECORATOR WITH LOGGING
# ---------------------------------------------------------

def logged_tool(logger: AgentLogger, agent_name: str):
    """
    A decorator factory that wraps a tool function with timing and logging.

    Decorators in Python wrap a function with extra behavior.
    Think of it like a PostgreSQL trigger: the trigger fires before/after
    the function executes and records what happened.

    Usage:
        @logged_tool(logger, "MonitorAgent")
        def check_connections(database):
            ...

    Every call to check_connections will now be automatically:
    - Timed (start to finish, in milliseconds)
    - Logged with the input parameters and output
    - Recorded as ERROR if an exception occurs
    """

    # "outer" receives the function being decorated
    def outer(func):
        # "wrapper" replaces the original function
        # *args and **kwargs capture any arguments passed to the function
        # *args = positional args, **kwargs = keyword args
        def wrapper(*args, **kwargs):
            start = time.time()

            try:
                # Call the actual tool function
                result = func(*args, **kwargs)

                # Calculate elapsed time in milliseconds
                elapsed = round((time.time() - start) * 1000, 2)

                # Log success
                logger.log(
                    level="INFO",
                    agent=agent_name,
                    action="tool_call",
                    details={
                        "tool": func.__name__,
                        "args": str(args),
                        "kwargs": str(kwargs),
                        "result_length": len(str(result)),
                        "status": "success"
                    },
                    duration_ms=elapsed
                )

                return result

            except Exception as e:
                elapsed = round((time.time() - start) * 1000, 2)

                # Log failure
                logger.log(
                    level="ERROR",
                    agent=agent_name,
                    action="tool_call",
                    details={
                        "tool": func.__name__,
                        "args": str(args),
                        "kwargs": str(kwargs),
                        "error": str(e),
                        "status": "failed"
                    },
                    duration_ms=elapsed
                )

                # Re-raise the exception so the caller knows it failed
                raise

        return wrapper
    return outer


# ---------------------------------------------------------
# AGENT WITH LOGGED TOOLS
# ---------------------------------------------------------

logger = AgentLogger(log_file="/tmp/agent_log.jsonl")

# Decorate tool functions with logging
# Each call will be automatically timed and recorded

@logged_tool(logger, "MonitorAgent")
def check_connections(database: str) -> str:
    """Simulates checking database connections."""
    time.sleep(0.05)  # simulate 50ms of work
    if database == "broken":
        raise ConnectionError("Cannot connect to database: broken")
    return f"connections: 187/200 on {database}"


@logged_tool(logger, "MonitorAgent")
def check_replication(primary: str) -> str:
    """Simulates checking replication lag."""
    time.sleep(0.08)  # simulate 80ms of work
    return f"lag: 2.1s on standby-1, 0.3s on standby-2"


@logged_tool(logger, "DiagnosisAgent")
def diagnose_alert(alert_text: str) -> str:
    """Simulates diagnosing an alert."""
    time.sleep(0.12)  # simulate 120ms of work
    return f"Root cause: connection pool exhaustion from reporting_app"


# ---------------------------------------------------------
# SIMULATE AGENT OPERATIONS
# ---------------------------------------------------------

print("=" * 60)
print("STRUCTURED LOGGING DEMO")
print("=" * 60)

# Run several tool calls
print("\nRunning tool calls...")

check_connections("production")
check_connections("staging")
check_replication("pg-primary")
diagnose_alert("active_connections=199, max=200")

# Try a failing call
try:
    check_connections("broken")
except ConnectionError:
    print("  (caught expected error for 'broken' database)")

# Run a few more
check_connections("production")
check_replication("pg-primary")

# ---------------------------------------------------------
# QUERY THE LOGS
# ---------------------------------------------------------

print(f"\n{'=' * 60}")
print("LOG QUERIES")
print(f"{'=' * 60}")

# All entries
print(f"\nTotal log entries: {len(logger.entries)}")

# Query errors only
errors = logger.query(level="ERROR")
print(f"\nERROR entries (like: SELECT * FROM agent_log WHERE level = 'ERROR'):")
for entry in errors:
    print(f"  [{entry['timestamp'][:19]}] {entry['agent']} - "
          f"{entry['details'].get('tool', '')} - {entry['details'].get('error', '')}")

# Query by agent
monitor_logs = logger.query(agent="MonitorAgent")
print(f"\nMonitorAgent entries (last 5):")
for entry in monitor_logs[:5]:
    d = entry["details"]
    print(f"  [{entry['timestamp'][:19]}] {d.get('tool', '')} "
          f"({entry['duration_ms']}ms) - {d.get('status', '')}")

# Show the raw log file
print(f"\nLog file written to: /tmp/agent_log.jsonl")
print("First 3 lines:")
with open("/tmp/agent_log.jsonl", "r") as f:
    for i, line in enumerate(f):
        if i >= 3:
            break
        # Parse and re-format for readability
        record = json.loads(line)
        print(f"  {record['level']:<7} {record['agent']:<15} "
              f"{record['details'].get('tool', ''):<20} {record.get('duration_ms', '')}ms")

EOF
```

Expected output (yours will differ):
```
============================================================
STRUCTURED LOGGING DEMO
============================================================

Running tool calls...
  (caught expected error for 'broken' database)

============================================================
LOG QUERIES
============================================================

Total log entries: 7

ERROR entries (like: SELECT * FROM agent_log WHERE level = 'ERROR'):
  [2026-06-15T14:30:00] MonitorAgent - check_connections - Cannot connect to database: broken

MonitorAgent entries (last 5):
  [2026-06-15T14:30:00] check_connections (52.1ms) - success
  [2026-06-15T14:30:00] check_connections (51.3ms) - success
  [2026-06-15T14:30:00] check_replication (81.4ms) - success
  [2026-06-15T14:30:00] check_connections (50.8ms) - failed
  [2026-06-15T14:30:00] check_connections (51.0ms) - success

Log file written to: /tmp/agent_log.jsonl
First 3 lines:
  INFO    MonitorAgent    check_connections    52.1ms
  INFO    MonitorAgent    check_connections    51.3ms
  INFO    MonitorAgent    check_replication    81.4ms
```

---

## Step 2: Token Usage and Cost Tracking

### The Concept

Every LLM call costs money. In production, you need to know exactly how much each alert costs to process so you can optimize and budget.

**DBA analogy:** This is like tracking `shared_blks_read` and `shared_blks_hit` in `pg_stat_statements`. You measure I/O cost per query to find the expensive ones and optimize them. Token tracking is I/O cost accounting for AI.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a token usage and cost tracker for agent operations.
#   Tracks tokens consumed per tool call, per alert, and per day.
#   Calculates cost based on model pricing.
# ---------------------------------------------------------

import json
import datetime

# ---------------------------------------------------------
# TOKEN TRACKER
# ---------------------------------------------------------

class TokenTracker:
    """
    Tracks token usage and calculates cost.

    DBA analogy: like pg_stat_statements tracking shared_blks_read per query.
    Each record stores how many tokens (blocks) were consumed.
    You can query totals by agent, tool, or time period.
    """

    # Pricing per 1M tokens (as of mid-2026)
    # These are approximate - check current pricing for your model
    PRICING = {
        "gpt-4o-mini": {"input": 0.15, "output": 0.60},
        "gpt-4o":      {"input": 2.50, "output": 10.00},
        "claude-sonnet": {"input": 3.00, "output": 15.00},
    }

    def __init__(self):
        self.records = []

    def record_usage(self, agent: str, tool: str, model: str,
                     input_tokens: int, output_tokens: int,
                     alert_id: str = None):
        """
        Record token usage for one LLM call.

        DBA analogy: INSERT INTO token_usage (agent, tool, model, tokens_in, tokens_out, ...)
        """
        pricing = self.PRICING.get(model, {"input": 0, "output": 0})

        # Calculate cost: tokens / 1_000_000 * price_per_million
        # 1_000_000 is Python's way of writing 1000000 with underscores for readability
        input_cost = (input_tokens / 1_000_000) * pricing["input"]
        output_cost = (output_tokens / 1_000_000) * pricing["output"]
        total_cost = round(input_cost + output_cost, 6)

        record = {
            "timestamp": datetime.datetime.now().isoformat(),
            "agent": agent,
            "tool": tool,
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "cost_usd": total_cost,
            "alert_id": alert_id
        }

        self.records.append(record)
        return record

    def get_summary(self) -> dict:
        """
        Overall usage summary.

        DBA analogy: SELECT sum(calls), sum(total_time), sum(shared_blks_read)
                     FROM pg_stat_statements;
        """
        if not self.records:
            return {"total_records": 0}

        total_input = sum(r["input_tokens"] for r in self.records)
        total_output = sum(r["output_tokens"] for r in self.records)
        total_cost = sum(r["cost_usd"] for r in self.records)

        return {
            "total_calls": len(self.records),
            "total_input_tokens": total_input,
            "total_output_tokens": total_output,
            "total_tokens": total_input + total_output,
            "total_cost_usd": round(total_cost, 4),
            "avg_tokens_per_call": round((total_input + total_output) / len(self.records)),
            "avg_cost_per_call": round(total_cost / len(self.records), 6)
        }

    def get_cost_by_agent(self) -> dict:
        """
        Cost breakdown by agent.

        DBA analogy: SELECT usename, sum(total_time), count(*)
                     FROM pg_stat_statements
                     JOIN pg_roles ON userid = oid
                     GROUP BY usename ORDER BY sum(total_time) DESC;
        """
        agents = {}
        for r in self.records:
            agent = r["agent"]
            if agent not in agents:
                agents[agent] = {"calls": 0, "tokens": 0, "cost": 0.0}
            agents[agent]["calls"] += 1
            agents[agent]["tokens"] += r["total_tokens"]
            agents[agent]["cost"] += r["cost_usd"]

        # Round the costs
        for agent in agents:
            agents[agent]["cost"] = round(agents[agent]["cost"], 6)

        return agents

    def get_cost_by_alert(self) -> dict:
        """
        Cost breakdown by alert ID.
        Shows how much each alert costs to process.

        DBA analogy: SELECT queryid, sum(total_time)
                     FROM pg_stat_statements
                     GROUP BY queryid ORDER BY sum(total_time) DESC;
        """
        alerts = {}
        for r in self.records:
            aid = r.get("alert_id", "unknown")
            if aid not in alerts:
                alerts[aid] = {"calls": 0, "tokens": 0, "cost": 0.0}
            alerts[aid]["calls"] += 1
            alerts[aid]["tokens"] += r["total_tokens"]
            alerts[aid]["cost"] += r["cost_usd"]

        for aid in alerts:
            alerts[aid]["cost"] = round(alerts[aid]["cost"], 6)

        return alerts


# ---------------------------------------------------------
# SIMULATE PROCESSING SEVERAL ALERTS
# ---------------------------------------------------------

tracker = TokenTracker()

print("=" * 60)
print("TOKEN USAGE AND COST TRACKING")
print("=" * 60)

# Alert 1: Connection exhaustion - processed by 3 agents
print("\nProcessing Alert-001: Connection exhaustion")
tracker.record_usage("ClassifierAgent", "classify", "gpt-4o-mini",
                     input_tokens=450, output_tokens=15, alert_id="ALERT-001")
tracker.record_usage("DiagnosisAgent", "diagnose", "gpt-4o-mini",
                     input_tokens=820, output_tokens=180, alert_id="ALERT-001")
tracker.record_usage("RemediationAgent", "recommend", "gpt-4o-mini",
                     input_tokens=950, output_tokens=250, alert_id="ALERT-001")

# Alert 2: Replication lag - more complex, uses a larger model
print("Processing Alert-002: Replication lag")
tracker.record_usage("ClassifierAgent", "classify", "gpt-4o-mini",
                     input_tokens=380, output_tokens=12, alert_id="ALERT-002")
tracker.record_usage("DiagnosisAgent", "diagnose", "gpt-4o",
                     input_tokens=1200, output_tokens=350, alert_id="ALERT-002")
tracker.record_usage("RemediationAgent", "recommend", "gpt-4o",
                     input_tokens=1500, output_tokens=400, alert_id="ALERT-002")

# Alert 3: Simple OK alert - only classifier runs
print("Processing Alert-003: Normal metrics (OK)")
tracker.record_usage("ClassifierAgent", "classify", "gpt-4o-mini",
                     input_tokens=300, output_tokens=8, alert_id="ALERT-003")

# ---------------------------------------------------------
# DISPLAY COST REPORTS
# ---------------------------------------------------------

print(f"\n{'=' * 60}")
print("COST REPORTS")
print(f"{'=' * 60}")

# Overall summary
summary = tracker.get_summary()
print(f"\n--- Overall Summary ---")
print(f"  Total LLM calls:     {summary['total_calls']}")
print(f"  Total tokens:        {summary['total_tokens']:,}")
print(f"  Total cost:          ${summary['total_cost_usd']:.4f}")
print(f"  Avg tokens/call:     {summary['avg_tokens_per_call']:,}")
print(f"  Avg cost/call:       ${summary['avg_cost_per_call']:.6f}")

# Cost by agent
print(f"\n--- Cost by Agent ---")
print(f"  {'Agent':<22} {'Calls':<8} {'Tokens':<10} {'Cost'}")
print(f"  {'-' * 50}")
by_agent = tracker.get_cost_by_agent()
for agent, data in sorted(by_agent.items(), key=lambda x: x[1]["cost"], reverse=True):
    print(f"  {agent:<22} {data['calls']:<8} {data['tokens']:<10} ${data['cost']:.6f}")

# Cost by alert
print(f"\n--- Cost by Alert ---")
print(f"  {'Alert':<15} {'Calls':<8} {'Tokens':<10} {'Cost'}")
print(f"  {'-' * 45}")
by_alert = tracker.get_cost_by_alert()
for aid, data in sorted(by_alert.items(), key=lambda x: x[1]["cost"], reverse=True):
    print(f"  {aid:<15} {data['calls']:<8} {data['tokens']:<10} ${data['cost']:.6f}")

# Projections
if summary['total_calls'] > 0:
    alerts_per_day = 100
    calls_per_alert = summary['total_calls'] / 3  # 3 alerts processed
    daily_cost = alerts_per_day * calls_per_alert * summary['avg_cost_per_call']
    monthly_cost = daily_cost * 30

    print(f"\n--- Cost Projection (at {alerts_per_day} alerts/day) ---")
    print(f"  Daily cost:   ${daily_cost:.2f}")
    print(f"  Monthly cost: ${monthly_cost:.2f}")

EOF
```

Expected output (yours will differ):
```
============================================================
TOKEN USAGE AND COST TRACKING
============================================================

Processing Alert-001: Connection exhaustion
Processing Alert-002: Replication lag
Processing Alert-003: Normal metrics (OK)

============================================================
COST REPORTS
============================================================

--- Overall Summary ---
  Total LLM calls:     7
  Total tokens:        6,815
  Total cost:          $0.0150
  Avg tokens/call:     974
  Avg cost/call:       $0.002138

--- Cost by Agent ---
  Agent                  Calls    Tokens     Cost
  --------------------------------------------------
  RemediationAgent       2        3,100      $0.009475
  DiagnosisAgent         2        2,550      $0.005150
  ClassifierAgent        3        1,165      $0.000340

--- Cost by Alert ---
  Alert           Calls    Tokens     Cost
  ---------------------------------------------
  ALERT-002       3        3,842      $0.014314
  ALERT-001       3        2,665      $0.000601
  ALERT-003       1        308        $0.000046

--- Cost Projection (at 100 alerts/day) ---
  Daily cost:   $0.50
  Monthly cost: $14.97
```

---

## Step 3: Error Rate and Health Monitoring

### The Concept

Track error rates to detect when the agent is unhealthy. A sudden spike in errors means something is wrong - a downstream API is down, a model is rate-limited, or a tool is broken.

**DBA analogy:** This is like monitoring `pg_stat_database.xact_rollback`. A sudden spike in rollbacks tells you something is wrong with the application or the database. Same idea for agent errors.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a health monitoring system that tracks error rates,
#   response times, and detects anomalies in agent behavior.
# ---------------------------------------------------------

import datetime
import json
import statistics

# ---------------------------------------------------------
# HEALTH MONITOR
# ---------------------------------------------------------

class AgentHealthMonitor:
    """
    Monitors agent health metrics and alerts on anomalies.

    DBA analogy: like a combination of pg_stat_database and
    a threshold-based monitoring system (Nagios/Zabbix).
    Tracks error rates, response times, and fires alerts
    when metrics exceed thresholds.
    """

    def __init__(self, error_rate_threshold: float = 0.2,
                 latency_threshold_ms: float = 5000,
                 token_spike_multiplier: float = 3.0):
        """
        Parameters:
            error_rate_threshold   - alert if error rate exceeds this (0.2 = 20%)
            latency_threshold_ms   - alert if avg latency exceeds this
            token_spike_multiplier - alert if token usage is N times the average
        """
        self.error_rate_threshold = error_rate_threshold
        self.latency_threshold_ms = latency_threshold_ms
        self.token_spike_multiplier = token_spike_multiplier

        # Metrics storage - like pg_stat_* views
        self.requests = []
        self.alerts_fired = []

    def record_request(self, agent: str, success: bool,
                       duration_ms: float, tokens_used: int):
        """Record one agent request and check for anomalies."""
        record = {
            "timestamp": datetime.datetime.now().isoformat(),
            "agent": agent,
            "success": success,
            "duration_ms": duration_ms,
            "tokens_used": tokens_used
        }
        self.requests.append(record)

        # Check for anomalies after every 5 requests
        if len(self.requests) % 5 == 0:
            self._check_health()

    def _check_health(self):
        """
        Check all health metrics and fire alerts if needed.

        DBA analogy: like a cron job that runs:
          SELECT count(*) FILTER (WHERE NOT success) * 100.0 / count(*)
          FROM agent_requests
          WHERE timestamp > now() - interval '5 minutes';
        """
        # Use the last 20 requests as our window
        window = self.requests[-20:]

        if len(window) < 5:
            return

        # Check 1: Error rate
        total = len(window)
        errors = sum(1 for r in window if not r["success"])
        error_rate = errors / total

        if error_rate > self.error_rate_threshold:
            self._fire_alert(
                "HIGH_ERROR_RATE",
                f"Error rate is {error_rate:.0%} ({errors}/{total}). "
                f"Threshold: {self.error_rate_threshold:.0%}."
            )

        # Check 2: Latency
        durations = [r["duration_ms"] for r in window]
        avg_latency = statistics.mean(durations)

        if avg_latency > self.latency_threshold_ms:
            self._fire_alert(
                "HIGH_LATENCY",
                f"Avg latency is {avg_latency:.0f}ms. "
                f"Threshold: {self.latency_threshold_ms}ms."
            )

        # Check 3: Token spike
        all_tokens = [r["tokens_used"] for r in self.requests]
        if len(all_tokens) > 10:
            # Compare recent average to historical average
            historical_avg = statistics.mean(all_tokens[:-5])
            recent_avg = statistics.mean(all_tokens[-5:])

            if historical_avg > 0 and recent_avg > historical_avg * self.token_spike_multiplier:
                self._fire_alert(
                    "TOKEN_SPIKE",
                    f"Recent token avg ({recent_avg:.0f}) is "
                    f"{recent_avg/historical_avg:.1f}x the historical avg "
                    f"({historical_avg:.0f}). Threshold: {self.token_spike_multiplier}x."
                )

    def _fire_alert(self, alert_type: str, message: str):
        """Record a health alert."""
        alert = {
            "timestamp": datetime.datetime.now().isoformat(),
            "type": alert_type,
            "message": message
        }
        self.alerts_fired.append(alert)

    def get_dashboard(self) -> dict:
        """
        Generate a health dashboard summary.

        DBA analogy: like a Grafana dashboard showing key PostgreSQL metrics.
        """
        if not self.requests:
            return {"status": "NO_DATA"}

        total = len(self.requests)
        errors = sum(1 for r in self.requests if not r["success"])
        durations = [r["duration_ms"] for r in self.requests]
        tokens = [r["tokens_used"] for r in self.requests]

        return {
            "total_requests": total,
            "error_count": errors,
            "error_rate": f"{(errors/total)*100:.1f}%",
            "avg_latency_ms": round(statistics.mean(durations), 1),
            "p95_latency_ms": round(sorted(durations)[int(total * 0.95)], 1) if total > 1 else durations[0],
            "max_latency_ms": round(max(durations), 1),
            "total_tokens": sum(tokens),
            "avg_tokens_per_request": round(statistics.mean(tokens)),
            "health_alerts": len(self.alerts_fired),
            "status": "DEGRADED" if self.alerts_fired else "HEALTHY"
        }


# ---------------------------------------------------------
# SIMULATE AGENT OPERATIONS WITH HEALTH MONITORING
# ---------------------------------------------------------

monitor = AgentHealthMonitor(
    error_rate_threshold=0.2,
    latency_threshold_ms=3000,
    token_spike_multiplier=3.0
)

print("=" * 60)
print("AGENT HEALTH MONITORING")
print("=" * 60)

# Phase 1: Normal operations
print("\nPhase 1: Normal operations (healthy)")
for i in range(10):
    monitor.record_request("DiagnosisAgent", success=True,
                           duration_ms=200 + (i * 30), tokens_used=500 + (i * 20))

# Phase 2: Latency spike (something is slow)
print("Phase 2: Latency spike (model endpoint slow)")
for i in range(5):
    monitor.record_request("DiagnosisAgent", success=True,
                           duration_ms=4000 + (i * 500), tokens_used=600)

# Phase 3: Error spike (API failures)
print("Phase 3: Error spike (PagerDuty API down)")
for i in range(5):
    success = i % 3 != 0  # 2 out of 5 will fail
    monitor.record_request("NotificationAgent", success=success,
                           duration_ms=500, tokens_used=100)

# Phase 4: Token spike (prompt injection or runaway context)
print("Phase 4: Token spike (context window growing)")
for i in range(5):
    monitor.record_request("DiagnosisAgent", success=True,
                           duration_ms=1500, tokens_used=5000 + (i * 2000))

# ---------------------------------------------------------
# DISPLAY DASHBOARD
# ---------------------------------------------------------

print(f"\n{'=' * 60}")
print("AGENT HEALTH DASHBOARD")
print(f"{'=' * 60}")

dashboard = monitor.get_dashboard()
for key, value in dashboard.items():
    label = key.replace("_", " ").title()
    print(f"  {label:<25} {value}")

# Show health alerts
if monitor.alerts_fired:
    print(f"\n{'=' * 60}")
    print("HEALTH ALERTS")
    print(f"{'=' * 60}")
    for alert in monitor.alerts_fired:
        print(f"\n  [{alert['type']}] {alert['timestamp'][:19]}")
        print(f"  {alert['message']}")

EOF
```

Expected output (yours will differ):
```
============================================================
AGENT HEALTH MONITORING
============================================================

Phase 1: Normal operations (healthy)
Phase 2: Latency spike (model endpoint slow)
Phase 3: Error spike (PagerDuty API down)
Phase 4: Token spike (context window growing)

============================================================
AGENT HEALTH DASHBOARD
============================================================
  Total Requests            25
  Error Count               2
  Error Rate                8.0%
  Avg Latency Ms            1534
  P95 Latency Ms            5500
  Max Latency Ms            6000
  Total Tokens              54400
  Avg Tokens Per Request    2176
  Health Alerts             1
  Status                    DEGRADED

============================================================
HEALTH ALERTS
============================================================

  [TOKEN_SPIKE] 2026-06-15T19:11:12
  Recent token avg (9000) is 19.1x the historical avg (470). Threshold: 3.0x.
```

**Why only TOKEN_SPIKE fires:** Health checks run every 5 requests. By the time Phase 2's latency spike is checked, the 20-request window includes enough normal requests to keep the average below 3000ms. Similarly, Phase 3 has only 2 errors in the 20-request window (10%), below the 20% threshold. Only the Phase 4 token spike is dramatic enough - the recent average (9000) is 19x the historical average (470). This mirrors real PostgreSQL monitoring: a brief spike gets smoothed out by the window, but a sustained anomaly triggers an alert.

---

## Step 4: Complete Observability Dashboard

### The Concept

Combine all metrics into a single CSV-based dashboard that shows the key health indicators at a glance.

**DBA analogy:** This is your agent's equivalent of `pg_stat_database` - one view that gives you the overall health picture.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Generates a CSV-based observability dashboard for the agent.
#   Combines: alerts processed, avg response time, accuracy,
#   cost, and health status into one report.
# ---------------------------------------------------------

import csv
import datetime
import json
import os

# ---------------------------------------------------------
# DASHBOARD DATA (aggregated from the systems built in Steps 1-3)
# ---------------------------------------------------------

# Simulated daily metrics - in production these come from the logger,
# token tracker, and health monitor
daily_metrics = [
    {"date": "2026-06-09", "alerts_processed": 142, "avg_response_ms": 1250,
     "accuracy_pct": 72.0, "total_tokens": 185000, "cost_usd": 1.85,
     "errors": 8, "p95_latency_ms": 3200, "health_alerts": 2},
    {"date": "2026-06-10", "alerts_processed": 158, "avg_response_ms": 1180,
     "accuracy_pct": 78.5, "total_tokens": 198000, "cost_usd": 1.98,
     "errors": 5, "p95_latency_ms": 2800, "health_alerts": 1},
    {"date": "2026-06-11", "alerts_processed": 135, "avg_response_ms": 1320,
     "accuracy_pct": 81.0, "total_tokens": 175000, "cost_usd": 1.75,
     "errors": 4, "p95_latency_ms": 3500, "health_alerts": 1},
    {"date": "2026-06-12", "alerts_processed": 163, "avg_response_ms": 980,
     "accuracy_pct": 85.0, "total_tokens": 201000, "cost_usd": 2.01,
     "errors": 3, "p95_latency_ms": 2100, "health_alerts": 0},
    {"date": "2026-06-13", "alerts_processed": 171, "avg_response_ms": 920,
     "accuracy_pct": 88.0, "total_tokens": 210000, "cost_usd": 2.10,
     "errors": 2, "p95_latency_ms": 1900, "health_alerts": 0},
    {"date": "2026-06-14", "alerts_processed": 155, "avg_response_ms": 1050,
     "accuracy_pct": 91.0, "total_tokens": 192000, "cost_usd": 1.92,
     "errors": 1, "p95_latency_ms": 2200, "health_alerts": 0},
    {"date": "2026-06-15", "alerts_processed": 148, "avg_response_ms": 1100,
     "accuracy_pct": 92.5, "total_tokens": 188000, "cost_usd": 1.88,
     "errors": 1, "p95_latency_ms": 2400, "health_alerts": 0},
]


# ---------------------------------------------------------
# WRITE CSV DASHBOARD
# ---------------------------------------------------------

csv_path = "/tmp/agent_dashboard.csv"

# csv.DictWriter writes a list of dicts as a CSV file
# fieldnames defines the column order - like a CREATE TABLE with column ordering
with open(csv_path, "w", newline="") as f:
    fieldnames = ["date", "alerts_processed", "avg_response_ms", "accuracy_pct",
                  "total_tokens", "cost_usd", "errors", "p95_latency_ms", "health_alerts"]
    writer = csv.DictWriter(f, fieldnames=fieldnames)

    # Write the header row - like the column names in a psql \x display
    writer.writeheader()

    # Write each day's metrics - like INSERT INTO dashboard VALUES (...)
    for row in daily_metrics:
        writer.writerow(row)

print("=" * 60)
print("AGENT OBSERVABILITY DASHBOARD")
print("=" * 60)

# ---------------------------------------------------------
# DISPLAY THE DASHBOARD
# ---------------------------------------------------------

print(f"\n{'Date':<12} {'Alerts':<8} {'Avg ms':<9} {'Acc%':<7} "
      f"{'Tokens':<10} {'Cost':<8} {'Errs':<6} {'P95 ms':<9} {'Hlth'}")
print("-" * 78)

for row in daily_metrics:
    print(f"{row['date']:<12} {row['alerts_processed']:<8} "
          f"{row['avg_response_ms']:<9} {row['accuracy_pct']:<7} "
          f"{row['total_tokens']:<10} ${row['cost_usd']:<7} "
          f"{row['errors']:<6} {row['p95_latency_ms']:<9} "
          f"{row['health_alerts']}")

# ---------------------------------------------------------
# WEEKLY SUMMARY
# ---------------------------------------------------------

total_alerts = sum(r["alerts_processed"] for r in daily_metrics)
total_cost = sum(r["cost_usd"] for r in daily_metrics)
total_errors = sum(r["errors"] for r in daily_metrics)
avg_accuracy = sum(r["accuracy_pct"] for r in daily_metrics) / len(daily_metrics)
avg_latency = sum(r["avg_response_ms"] for r in daily_metrics) / len(daily_metrics)

print(f"\n{'=' * 60}")
print("WEEKLY SUMMARY")
print(f"{'=' * 60}")
print(f"  Total alerts processed: {total_alerts}")
print(f"  Total cost:             ${total_cost:.2f}")
print(f"  Cost per alert:         ${total_cost/total_alerts:.4f}")
print(f"  Avg accuracy:           {avg_accuracy:.1f}%")
print(f"  Avg latency:            {avg_latency:.0f}ms")
print(f"  Total errors:           {total_errors}")
print(f"  Error rate:             {total_errors/total_alerts*100:.1f}%")

# Trend analysis
print(f"\n  Accuracy trend:")
print(f"    Day 1: {daily_metrics[0]['accuracy_pct']}%")
print(f"    Day 7: {daily_metrics[-1]['accuracy_pct']}%")
improvement = daily_metrics[-1]['accuracy_pct'] - daily_metrics[0]['accuracy_pct']
print(f"    Change: +{improvement} percentage points")

print(f"\n  Error trend:")
print(f"    Day 1: {daily_metrics[0]['errors']} errors")
print(f"    Day 7: {daily_metrics[-1]['errors']} errors")

print(f"\nDashboard CSV saved to: {csv_path}")
print("You can open this in Excel or import into PostgreSQL:")
print(f"  COPY agent_dashboard FROM '{csv_path}' CSV HEADER;")

EOF
```

Expected output (yours will differ):
```
============================================================
AGENT OBSERVABILITY DASHBOARD
============================================================

Date         Alerts   Avg ms    Acc%    Tokens     Cost     Errs   P95 ms    Hlth
------------------------------------------------------------------------------
2026-06-09   142      1250      72.0    185000     $1.85    8      3200      2
2026-06-10   158      1180      78.5    198000     $1.98    5      2800      1
2026-06-11   135      1320      81.0    175000     $1.75    4      3500      1
2026-06-12   163      980       85.0    201000     $2.01    3      2100      0
2026-06-13   171      920       88.0    210000     $2.10    2      1900      0
2026-06-14   155      1050      91.0    192000     $1.92    1      2200      0
2026-06-15   148      1100      92.5    188000     $1.88    1      2400      0

============================================================
WEEKLY SUMMARY
============================================================
  Total alerts processed: 1072
  Total cost:             $13.49
  Cost per alert:         $0.0126
  Avg accuracy:           84.0%
  Avg latency:            1114ms
  Total errors:           24
  Error rate:             2.2%

  Accuracy trend:
    Day 1: 72.0%
    Day 7: 92.5%
    Change: +20.5 percentage points

  Error trend:
    Day 1: 8 errors
    Day 7: 1 errors

Dashboard CSV saved to: /tmp/agent_dashboard.csv
You can open this in Excel or import into PostgreSQL:
  COPY agent_dashboard FROM '/tmp/agent_dashboard.csv' CSV HEADER;
```

---

## What You Learned

| Concept | Python Implementation | DBA Analogy |
|---|---|---|
| Structured logging | JSON entries with standardized fields | PostgreSQL CSV log format |
| Log decorator | `@logged_tool()` wraps functions with timing | `log_statement = 'all'` + `log_duration = on` |
| Token tracking | Record input/output tokens per call | `shared_blks_read/hit` in `pg_stat_statements` |
| Cost calculation | Tokens / 1M * price per million | I/O cost estimation in `EXPLAIN` |
| Error rate monitoring | Count failures / total in a sliding window | `xact_rollback / xact_commit` in `pg_stat_database` |
| Latency tracking | p95 and avg response time | `mean_exec_time` in `pg_stat_statements` |
| Anomaly detection | Compare recent metrics to historical baseline | Alert on query time regression after a deploy |
| CSV dashboard | Daily metrics exported for analysis | `COPY agent_dashboard FROM ... CSV HEADER` |

**Next:** Use exercises to practice building production agent components end-to-end.
