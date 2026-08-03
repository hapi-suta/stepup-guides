# Build 03: Multi-Model Fallback

Running your entire DBA agent on a single model is like running your database on a single server with no replicas. When that model goes down - or gets too expensive, or too slow - your agent stops working. This guide teaches you to build multi-model routing and fallback chains.

---

## Step 1. Understand multi-model architecture

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Multi-Model Architecture
=========================

DBA Analogy: Primary + Standby + Read Replicas

  Your production PostgreSQL setup:
  - Primary: handles writes (the authoritative source)
  - Standby: hot standby for failover (same data, ready to promote)
  - Read replicas: handle read queries (offload SELECT traffic)

  A multi-model agent setup:
  - Primary model: handles complex tasks (Claude Opus - the "primary")
  - Fast model: handles simple tasks (Claude Haiku - the "read replica")
  - Fallback model: takes over if primary is down (GPT-4 - the "standby")

Why use multiple models?

  1. COST: Haiku costs ~1/50th of Opus per token
     - Alert classification doesn't need Opus
     - Simple stats lookups don't need Opus
     - Only complex root cause analysis needs the big model

  2. SPEED: Haiku responds in ~200ms, Opus in ~2-5 seconds
     - For real-time monitoring, latency matters
     - Classify 100 alerts/minute with Haiku, not Opus

  3. RELIABILITY: If Anthropic API is down, fall back to OpenAI
     - Like cascading replication: primary -> sync standby -> async standby
     - Never have a single point of failure

  4. CONSENSUS: Ask two models the same question, compare
     - Like comparing EXPLAIN plans from primary vs replica
     - If they disagree, escalate to a human
""")
PYEOF
```

---

## Step 2. Build model routing by task complexity

Route simple tasks to fast/cheap models, complex tasks to powerful models.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time

print("=" * 60)
print("MODEL ROUTING: Send tasks to the right model")
print("=" * 60)

class ModelRouter:
    """
    Route tasks to the appropriate model based on complexity.

    DBA analogy: Query routing in a read/write split.
    - SELECT goes to the read replica (fast, cheap)
    - INSERT/UPDATE goes to the primary (authoritative)
    - Complex analytics go to the dedicated analytics replica

    Same idea with AI models:
    - Classification -> Haiku (fast, cheap)
    - Diagnosis -> Sonnet (balanced)
    - Remediation planning -> Opus (thorough)
    """

    # Model configs: (name, cost_per_1k_input, cost_per_1k_output, avg_latency_ms)
    MODELS = {
        "haiku": {
            "name": "claude-3-5-haiku-20241022",
            "cost_per_1k_input": 0.001,
            "cost_per_1k_output": 0.005,
            "avg_latency_ms": 200,
            "capability": "fast_simple",
        },
        "sonnet": {
            "name": "claude-sonnet-4-20250514",
            "cost_per_1k_input": 0.003,
            "cost_per_1k_output": 0.015,
            "avg_latency_ms": 1000,
            "capability": "balanced",
        },
        "opus": {
            "name": "claude-opus-4-20250514",
            "cost_per_1k_input": 0.015,
            "cost_per_1k_output": 0.075,
            "avg_latency_ms": 3000,
            "capability": "thorough",
        },
    }

    # Task -> model mapping (like application routing rules)
    ROUTING_RULES = {
        "classify_alert": "haiku",      # Simple: is it performance, storage, or replication?
        "check_stats": "haiku",         # Simple: read a metric value
        "summarize_log": "haiku",       # Simple: extract key lines
        "diagnose_issue": "sonnet",     # Medium: correlate multiple signals
        "explain_query": "sonnet",      # Medium: analyze a query plan
        "root_cause": "opus",           # Complex: multi-step reasoning
        "remediation_plan": "opus",     # Complex: generate safe fix steps
        "incident_report": "opus",      # Complex: comprehensive write-up
    }

    @classmethod
    def route(cls, task_type):
        """
        Determine which model should handle this task.
        Returns (model_key, model_config, reason).
        """
        model_key = cls.ROUTING_RULES.get(task_type)

        if model_key is None:
            # Unknown task -> default to Sonnet (balanced)
            return "sonnet", cls.MODELS["sonnet"], "Unknown task type, defaulting to balanced model"

        model = cls.MODELS[model_key]
        return model_key, model, f"Task '{task_type}' routed to {model_key}"

    @classmethod
    def estimate_cost(cls, model_key, input_tokens, output_tokens):
        """
        Estimate cost for a request.
        Returns cost in dollars.
        """
        model = cls.MODELS[model_key]
        input_cost = (input_tokens / 1000) * model["cost_per_1k_input"]
        output_cost = (output_tokens / 1000) * model["cost_per_1k_output"]
        return round(input_cost + output_cost, 6)


# -----------------------------------------------------------------------
# TEST IT: Simulate routing for a typical incident
# -----------------------------------------------------------------------

incident_tasks = [
    # Step 1: Classify the incoming alert (fast, cheap)
    {"task": "classify_alert", "input_tokens": 200, "output_tokens": 50,
     "description": "Alert: CPU at 95% on pg-primary-01"},

    # Step 2: Check relevant stats (fast, cheap)
    {"task": "check_stats", "input_tokens": 150, "output_tokens": 100,
     "description": "Fetch pg_stat_activity and pg_stat_user_tables"},

    # Step 3: Diagnose the issue (medium complexity)
    {"task": "diagnose_issue", "input_tokens": 2000, "output_tokens": 500,
     "description": "Correlate CPU spike with active queries and table stats"},

    # Step 4: Analyze the slow query (medium complexity)
    {"task": "explain_query", "input_tokens": 1500, "output_tokens": 800,
     "description": "EXPLAIN ANALYZE output for the suspect query"},

    # Step 5: Find root cause (complex)
    {"task": "root_cause", "input_tokens": 5000, "output_tokens": 1500,
     "description": "Determine why this query suddenly became slow"},

    # Step 6: Plan the fix (complex)
    {"task": "remediation_plan", "input_tokens": 3000, "output_tokens": 2000,
     "description": "Generate step-by-step fix with rollback plan"},
]

total_cost = 0.0
print()
print(f"{'Step':<5} {'Task':<20} {'Model':<8} {'Latency':>8} {'Cost':>10}")
print("-" * 55)

for i, task in enumerate(incident_tasks, 1):
    model_key, model, reason = ModelRouter.route(task["task"])
    cost = ModelRouter.estimate_cost(model_key, task["input_tokens"], task["output_tokens"])
    total_cost += cost

    print(f"{i:<5} {task['task']:<20} {model_key:<8} {model['avg_latency_ms']:>6}ms ${cost:>8.5f}")

print("-" * 55)
print(f"{'':>33} Total: ${total_cost:.5f}")

# Compare with "everything on Opus"
opus_cost = sum(
    ModelRouter.estimate_cost("opus", t["input_tokens"], t["output_tokens"])
    for t in incident_tasks
)
print(f"\n  If everything ran on Opus: ${opus_cost:.5f}")
print(f"  Savings from routing:     {(1 - total_cost/opus_cost):.0%}")
PYEOF
```

Expected output (yours will differ):
```
Step  Task                 Model    Latency       Cost
-------------------------------------------------------
1     classify_alert       haiku      200ms $ 0.00045
2     check_stats          haiku      200ms $ 0.00065
3     diagnose_issue       sonnet    1000ms $ 0.01350
4     explain_query        sonnet    1000ms $ 0.01650
5     root_cause           opus      3000ms $ 0.18750
6     remediation_plan     opus      3000ms $ 0.19500
-------------------------------------------------------
                                 Total: $0.41360

  If everything ran on Opus: $0.54900
  Savings from routing:     25%
```

The cheap tasks (classify, check stats) cost almost nothing on Haiku. The expensive work (root cause, remediation) runs on Opus where quality matters. Routing saves money and reduces latency for simple operations.

---

## Step 3. Build a fallback chain

When a model is unavailable, fall back to the next one - like cascading replication failover.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import random

print("=" * 60)
print("FALLBACK CHAIN: Cascading model failover")
print("=" * 60)

class ModelFallbackChain:
    """
    Try models in order until one succeeds.

    DBA analogy: Cascading replication failover.

      pg-primary (sync) -> pg-standby-1 (async) -> pg-standby-2 (async)

      If primary is down:
        1. Try sync standby
        2. If that's down, try async standby
        3. If ALL are down, return error

    Same pattern for models:
      Claude Opus -> Claude Sonnet -> GPT-4 -> Error
    """

    def __init__(self):
        # Ordered list of models to try (primary first, then fallbacks)
        self.chain = [
            {"name": "Claude Opus", "provider": "anthropic", "model": "claude-opus-4-20250514"},
            {"name": "Claude Sonnet", "provider": "anthropic", "model": "claude-sonnet-4-20250514"},
            {"name": "GPT-4", "provider": "openai", "model": "gpt-4"},
            {"name": "GPT-4o-mini", "provider": "openai", "model": "gpt-4o-mini"},
        ]

        # Track which models are "healthy" (simulated)
        # In production, this would be based on actual API health checks
        self.model_health = {m["name"]: True for m in self.chain}
        self.attempt_log = []

    def set_model_health(self, model_name, is_healthy):
        """Simulate a model going up or down."""
        self.model_health[model_name] = is_healthy

    def call_model(self, model, prompt):
        """
        Simulate calling a model API.
        In real code, this would be an HTTP request to the API.
        """
        # Simulate health check
        if not self.model_health.get(model["name"], False):
            raise ConnectionError(f"{model['name']} is unavailable (API down)")

        # Simulate random failures (10% chance)
        if random.random() < 0.1:
            raise TimeoutError(f"{model['name']} timed out after 30s")

        # Simulate success
        return {
            "model_used": model["name"],
            "response": f"[{model['name']}] Analysis: {prompt[:50]}...",
            "tokens_used": random.randint(200, 1500),
        }

    def execute(self, prompt):
        """
        Try each model in the chain until one succeeds.
        Returns (success, result_or_error, attempts).
        """
        attempts = []

        for model in self.chain:
            attempt = {
                "model": model["name"],
                "timestamp": time.strftime("%H:%M:%S"),
            }

            try:
                result = self.call_model(model, prompt)
                attempt["status"] = "success"
                attempt["tokens"] = result["tokens_used"]
                attempts.append(attempt)
                self.attempt_log.extend(attempts)
                return True, result, attempts

            except (ConnectionError, TimeoutError) as e:
                attempt["status"] = "failed"
                attempt["error"] = str(e)
                attempts.append(attempt)
                # Continue to next model in chain

        # All models failed
        self.attempt_log.extend(attempts)
        return False, "All models in fallback chain failed", attempts


# -----------------------------------------------------------------------
# TEST IT
# -----------------------------------------------------------------------
random.seed(42)  # For reproducible output
chain = ModelFallbackChain()

print("\n--- Scenario 1: Primary works ---")
success, result, attempts = chain.execute("CPU at 95% on pg-primary")
for a in attempts:
    print(f"  {a['model']}: {a['status']}")
if success:
    print(f"  Result: {result['response'][:60]}")

print("\n--- Scenario 2: Anthropic is down ---")
chain.set_model_health("Claude Opus", False)
chain.set_model_health("Claude Sonnet", False)
random.seed(99)  # Avoid random timeout on GPT-4

success, result, attempts = chain.execute("Replication lag at 30s")
for a in attempts:
    status = a['status']
    extra = f" - {a.get('error', '')}" if status == "failed" else ""
    print(f"  {a['model']}: {status}{extra}")
if success:
    print(f"  Result: {result['response'][:60]}")
    print(f"  Fell back from Claude to {result['model_used']}")

print("\n--- Scenario 3: All models down ---")
chain.set_model_health("Claude Opus", False)
chain.set_model_health("Claude Sonnet", False)
chain.set_model_health("GPT-4", False)
chain.set_model_health("GPT-4o-mini", False)

success, result, attempts = chain.execute("Database is completely down")
for a in attempts:
    print(f"  {a['model']}: {a['status']} - {a.get('error', '')}")
if not success:
    print(f"  CRITICAL: {result}")
    print(f"  Action: Page the on-call DBA immediately")

# Restore health for next scenario
chain.set_model_health("Claude Opus", True)
chain.set_model_health("Claude Sonnet", True)
chain.set_model_health("GPT-4", True)
chain.set_model_health("GPT-4o-mini", True)
PYEOF
```

Expected output (yours will differ):
```
--- Scenario 1: Primary works ---
  Claude Opus: success
  Result: [Claude Opus] Analysis: CPU at 95% on pg-primary...

--- Scenario 2: Anthropic is down ---
  Claude Opus: failed - Claude Opus is unavailable (API down)
  Claude Sonnet: failed - Claude Sonnet is unavailable (API down)
  GPT-4: success
  Result: [GPT-4] Analysis: Replication lag at 30s...
  Fell back from Claude to GPT-4

--- Scenario 3: All models down ---
  Claude Opus: failed - Claude Opus is unavailable (API down)
  Claude Sonnet: failed - Claude Sonnet is unavailable (API down)
  GPT-4: failed - GPT-4 is unavailable (API down)
  GPT-4o-mini: failed - GPT-4o-mini is unavailable (API down)
  CRITICAL: All models in fallback chain failed
  Action: Page the on-call DBA immediately
```

---

## Step 4. Cost tracking per alert

Track how much each alert costs to process - like tracking query costs with `pg_stat_statements`.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

print("=" * 60)
print("COST TRACKING: pg_stat_statements for AI spending")
print("=" * 60)

class CostTracker:
    """
    Track token usage and cost per alert, per model, per hour.

    DBA analogy: pg_stat_statements tracks:
    - total_exec_time per query
    - calls per query
    - rows per query

    This tracker tracks:
    - total_cost per alert type
    - calls per model
    - tokens per request
    """

    # Pricing (dollars per 1000 tokens)
    PRICING = {
        "haiku":  {"input": 0.001, "output": 0.005},
        "sonnet": {"input": 0.003, "output": 0.015},
        "opus":   {"input": 0.015, "output": 0.075},
        "gpt-4":  {"input": 0.010, "output": 0.030},
    }

    def __init__(self):
        self.records = []
        self.by_model = {}
        self.by_alert_type = {}

    def record(self, alert_type, model, input_tokens, output_tokens):
        """Record a single model call."""
        pricing = self.PRICING.get(model, {"input": 0.01, "output": 0.03})
        cost = (
            (input_tokens / 1000) * pricing["input"] +
            (output_tokens / 1000) * pricing["output"]
        )

        entry = {
            "alert_type": alert_type,
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cost": cost,
        }
        self.records.append(entry)

        # Aggregate by model
        if model not in self.by_model:
            self.by_model[model] = {"calls": 0, "total_cost": 0, "total_tokens": 0}
        self.by_model[model]["calls"] += 1
        self.by_model[model]["total_cost"] += cost
        self.by_model[model]["total_tokens"] += input_tokens + output_tokens

        # Aggregate by alert type
        if alert_type not in self.by_alert_type:
            self.by_alert_type[alert_type] = {"calls": 0, "total_cost": 0}
        self.by_alert_type[alert_type]["calls"] += 1
        self.by_alert_type[alert_type]["total_cost"] += cost

        return cost

    def report(self):
        """Generate a cost report - like pg_stat_statements output."""
        total_cost = sum(r["cost"] for r in self.records)
        total_calls = len(self.records)

        print(f"\n{'=' * 55}")
        print(f"COST REPORT (like pg_stat_statements for AI)")
        print(f"{'=' * 55}")
        print(f"Total calls: {total_calls}")
        print(f"Total cost:  ${total_cost:.4f}")
        print(f"Avg cost/call: ${total_cost/max(total_calls,1):.5f}")

        print(f"\n--- By Model (like per-query stats) ---")
        print(f"{'Model':<10} {'Calls':>6} {'Tokens':>10} {'Cost':>10} {'Avg':>10}")
        for model, stats in sorted(self.by_model.items()):
            avg = stats["total_cost"] / max(stats["calls"], 1)
            print(f"{model:<10} {stats['calls']:>6} {stats['total_tokens']:>10} "
                  f"${stats['total_cost']:>9.4f} ${avg:>9.5f}")

        print(f"\n--- By Alert Type ---")
        print(f"{'Alert Type':<20} {'Calls':>6} {'Cost':>10} {'Avg':>10}")
        for atype, stats in sorted(self.by_alert_type.items(),
                                    key=lambda x: x[1]["total_cost"], reverse=True):
            avg = stats["total_cost"] / max(stats["calls"], 1)
            print(f"{atype:<20} {stats['calls']:>6} "
                  f"${stats['total_cost']:>9.4f} ${avg:>9.5f}")


# -----------------------------------------------------------------------
# SIMULATE a day of alerts
# -----------------------------------------------------------------------
tracker = CostTracker()

# Simulate processing 50 alerts over a day
alerts = [
    # High volume, simple classification (Haiku)
    *[("cpu_high", "haiku", 200, 50)] * 15,
    *[("disk_warning", "haiku", 150, 40)] * 10,
    *[("connection_spike", "haiku", 180, 45)] * 8,

    # Medium volume, diagnosis needed (Sonnet)
    *[("replication_lag", "sonnet", 1500, 400)] * 5,
    *[("slow_query", "sonnet", 2000, 600)] * 4,

    # Low volume, complex analysis (Opus)
    *[("cascading_failure", "opus", 5000, 2000)] * 2,
    *[("data_corruption", "opus", 8000, 3000)] * 1,

    # Fallback to GPT-4 (Anthropic was down)
    *[("cpu_high", "gpt-4", 200, 50)] * 3,
    *[("slow_query", "gpt-4", 2000, 600)] * 2,
]

for alert_type, model, inp, out in alerts:
    tracker.record(alert_type, model, inp, out)

tracker.report()

# Monthly projection
daily_cost = sum(r["cost"] for r in tracker.records)
print(f"\n--- Projections ---")
print(f"  Daily cost:   ${daily_cost:.4f}")
print(f"  Monthly cost: ${daily_cost * 30:.2f}")
print(f"  Yearly cost:  ${daily_cost * 365:.2f}")
PYEOF
```

Expected output (yours will differ):
```
=======================================================
COST REPORT (like pg_stat_statements for AI)
=======================================================
Total calls: 50
Total cost:  $1.0075
Avg cost/call: $0.02015

--- By Model (like per-query stats) ---
Model      Calls     Tokens       Cost        Avg
gpt-4          5       5950 $  0.0865 $  0.01730
haiku         33       7450 $  0.0135 $  0.00041
opus           3      25000 $  0.7950 $  0.26500
sonnet         9      19900 $  0.1125 $  0.01250

--- By Alert Type ---
Alert Type            Calls       Cost        Avg
cascading_failure          2 $  0.4500 $  0.22500
data_corruption            1 $  0.3450 $  0.34500
slow_query                 6 $  0.1360 $  0.02267
replication_lag            5 $  0.0525 $  0.01050
...

--- Projections ---
  Daily cost:   $1.0075
  Monthly cost: $30.22
  Yearly cost:  $367.73
```

Notice: 3 Opus calls (6% of volume) account for nearly half the cost. This is why routing matters - you only use the expensive model when the task demands it.

---

## Step 5. Model consensus for critical decisions

For high-stakes decisions, ask two models and compare. If they disagree, escalate to a human.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random

print("=" * 60)
print("MODEL CONSENSUS: Two models, one decision")
print("=" * 60)

class ModelConsensus:
    """
    Ask multiple models the same question, compare answers.

    DBA analogy: Comparing query plans between primary and replica.
    If EXPLAIN on the primary shows a sequential scan but the replica
    shows an index scan, something is wrong with statistics.

    Same idea: if Claude says "restart replication" but GPT says
    "increase wal_keep_size", you need a human to decide.
    """

    SEVERITY_RANK = {"low": 1, "medium": 2, "high": 3, "critical": 4}

    @classmethod
    def simulate_model_response(cls, model_name, alert, seed):
        """
        Simulate a model analyzing an alert.
        In production, this calls the actual API.
        """
        random.seed(seed + hash(model_name))
        severities = ["low", "medium", "high", "critical"]
        actions = ["monitor", "investigate", "escalate", "remediate"]

        return {
            "model": model_name,
            "severity": random.choice(severities),
            "action": random.choice(actions),
            "confidence": round(random.uniform(0.4, 0.95), 2),
            "diagnosis": f"[{model_name}] Analysis of: {alert[:40]}",
        }

    @classmethod
    def check_consensus(cls, responses):
        """
        Compare responses from multiple models.
        Returns (consensus_reached, agreement_details, recommendation).
        """
        severities = [r["severity"] for r in responses]
        actions = [r["action"] for r in responses]

        # Check severity agreement
        severity_agree = len(set(severities)) == 1
        # Allow adjacent severity (high vs critical is close enough)
        severity_close = abs(
            cls.SEVERITY_RANK.get(severities[0], 0) -
            cls.SEVERITY_RANK.get(severities[1], 0)
        ) <= 1

        # Check action agreement
        action_agree = len(set(actions)) == 1

        # Consensus rules
        if severity_agree and action_agree:
            consensus = "STRONG"
            recommendation = f"Both models agree: {severities[0]} / {actions[0]}"
        elif severity_close and action_agree:
            consensus = "MODERATE"
            recommendation = f"Models close on severity, agree on action: {actions[0]}"
        elif severity_agree:
            consensus = "PARTIAL"
            recommendation = f"Agree on severity ({severities[0]}) but not action"
        else:
            consensus = "NONE"
            recommendation = "Models disagree - escalate to human DBA"

        # Use highest confidence response as primary recommendation
        best = max(responses, key=lambda r: r["confidence"])

        return {
            "consensus": consensus,
            "recommendation": recommendation,
            "severity_agree": severity_agree,
            "action_agree": action_agree,
            "best_response": best,
            "all_responses": responses,
        }


# -----------------------------------------------------------------------
# TEST IT
# -----------------------------------------------------------------------

alerts = [
    "CPU at 98% on pg-primary-01, 500 active connections",
    "Replication lag at 45 seconds on pg-replica-02",
    "Disk at 65% on pg-archive-01, growing 2% per day",
    "OOM killer terminated postmaster on pg-analytics",
]

print()
for i, alert in enumerate(alerts):
    # Get responses from two models
    resp_claude = ModelConsensus.simulate_model_response("Claude", alert, seed=i*100)
    resp_gpt = ModelConsensus.simulate_model_response("GPT-4", alert, seed=i*100)

    result = ModelConsensus.check_consensus([resp_claude, resp_gpt])

    print(f"Alert: {alert[:55]}")
    print(f"  Claude: severity={resp_claude['severity']}, action={resp_claude['action']}, "
          f"conf={resp_claude['confidence']}")
    print(f"  GPT-4:  severity={resp_gpt['severity']}, action={resp_gpt['action']}, "
          f"conf={resp_gpt['confidence']}")
    print(f"  Consensus: [{result['consensus']}] {result['recommendation']}")
    if result["consensus"] == "NONE":
        print(f"  >>> HUMAN REVIEW REQUIRED <<<")
    print()
PYEOF
```

Expected output (yours will differ):
```
Alert: CPU at 98% on pg-primary-01, 500 active connections
  Claude: severity=high, action=investigate, conf=0.82
  GPT-4:  severity=critical, action=investigate, conf=0.71
  Consensus: [MODERATE] Models close on severity, agree on action: investigate

Alert: Replication lag at 45 seconds on pg-replica-02
  Claude: severity=medium, action=remediate, conf=0.55
  GPT-4:  severity=critical, action=monitor, conf=0.88
  Consensus: [NONE] Models disagree - escalate to human DBA
  >>> HUMAN REVIEW REQUIRED <<<

Alert: Disk at 65% on pg-archive-01, growing 2% per day
  Claude: severity=low, action=monitor, conf=0.91
  GPT-4:  severity=low, action=monitor, conf=0.67
  Consensus: [STRONG] Both models agree: low / monitor
...
```

When models disagree on a critical decision (like replication lag remediation), the system correctly escalates to a human. You never want two models giving conflicting advice for the same database issue.

---

## What You Learned

| Concept | DBA Analogy | What You Built |
|---------|-------------|----------------|
| Model routing | Read/write split with replicas | `ModelRouter` class |
| Fallback chain | Cascading replication failover | `ModelFallbackChain` class |
| Cost tracking | pg_stat_statements for AI | `CostTracker` class |
| Model consensus | Comparing query plans | `ModelConsensus` class |
| Cost optimization | Connection pooling | Route by complexity |

Next: [Build 04 - Permission Systems](04-permission-systems.md)
