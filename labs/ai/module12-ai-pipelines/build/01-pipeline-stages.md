# Build 01: Building Pipeline Stages

A pipeline is only as good as its individual stages. Each stage should validate its inputs, do one thing well, and produce clean outputs. This guide builds reusable pipeline stages.

---

## Step 1. The anatomy of a pipeline stage

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime

# A pipeline stage follows this pattern:
# 1. Accept input
# 2. Validate input
# 3. Process
# 4. Return output (or error)

# @dataclass is a decorator that auto-generates setup code for a class.
# Without it, you'd write __init__(self, ...) manually for every field.
# With it, Python creates __init__ for you from the field definitions.
# DBA analogy: like CREATE TABLE with columns - you define the fields,
# PostgreSQL handles the storage details automatically.
#
# field(default_factory=lambda: []) means "default value is an empty list."
# lambda: [] is a tiny function that creates a new empty list each time.
# DBA analogy: like DEFAULT '[]'::jsonb on a column.
@dataclass
class PipelineResult:
    """Result from a pipeline stage."""
    success: bool                        # did the stage succeed?
    data: object = None                  # output data (if success)
    error: Optional[str] = None          # error message (if failure)
    stage: str = ""                      # which stage produced this
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    # default_factory runs the lambda to set default value
    # dataclass auto-generates __init__, __repr__, etc.

# Example: a validation stage
def validate_alert(alert: dict) -> PipelineResult:
    """Validate an incoming alert has required fields."""
    required_fields = ["message", "severity", "source", "timestamp"]

    # Check for missing fields
    missing = [f for f in required_fields if f not in alert]
    # List comprehension: collect field names not in the alert
    if missing:
        return PipelineResult(
            success=False,
            error=f"Missing fields: {missing}",
            stage="validate"
        )

    # Check for empty message
    if not alert["message"].strip():
        # .strip() removes whitespace; empty string is falsy
        return PipelineResult(
            success=False,
            error="Empty message",
            stage="validate"
        )

    # Check severity is valid
    valid_severities = ["low", "medium", "high", "critical"]
    if alert["severity"] not in valid_severities:
        return PipelineResult(
            success=False,
            error=f"Invalid severity: {alert['severity']}. Must be one of {valid_severities}",
            stage="validate"
        )

    return PipelineResult(success=True, data=alert, stage="validate")

# Test it
print("Pipeline Stage: Validation")
print("=" * 50)

test_alerts = [
    {"message": "CPU at 95%", "severity": "high", "source": "prometheus", "timestamp": "2024-01-15T10:00:00"},
    {"message": "Disk full", "severity": "critical", "source": "nagios"},  # missing timestamp
    {"message": "", "severity": "low", "source": "grafana", "timestamp": "2024-01-15T10:00:00"},  # empty message
    {"message": "SSL expired", "severity": "urgent", "source": "custom", "timestamp": "2024-01-15T10:00:00"},  # invalid severity
]

for alert in test_alerts:
    result = validate_alert(alert)
    status = "PASS" if result.success else "FAIL"
    detail = alert.get("message", "?")[:30] if result.success else result.error
    print(f"  [{status}] {detail}")
PYEOF
```

Expected output:

```
Pipeline Stage: Validation
==================================================
  [PASS] CPU at 95%
  [FAIL] Missing fields: ['timestamp']
  [FAIL] Empty message
  [FAIL] Invalid severity: urgent. Must be one of ['low', 'medium', 'high', 'critical']
```

---

## Step 2. Build the core stages

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from dataclasses import dataclass, field
from typing import Optional
from datetime import datetime

@dataclass
class PipelineResult:
    success: bool
    data: object = None
    error: Optional[str] = None
    stage: str = ""
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())

# Stage 1: Ingest
def ingest_alerts(raw_data: list) -> PipelineResult:
    """Parse raw alert data into structured format."""
    # try/except handles errors gracefully instead of crashing.
    # Code inside "try" runs normally. If it fails, "except" catches the error.
    # "except Exception as e" catches any error and stores it in variable "e".
    # DBA analogy: like BEGIN ... EXCEPTION WHEN others THEN ... END in PL/pgSQL.
    try:
        alerts = []
        for item in raw_data:
            if isinstance(item, dict):
                alerts.append(item)
            elif isinstance(item, str):
                # Parse simple string format: "severity|source|message"
                parts = item.split("|")
                if len(parts) == 3:
                    alerts.append({
                        "severity": parts[0].strip(),
                        "source": parts[1].strip(),
                        "message": parts[2].strip(),
                        "timestamp": datetime.now().isoformat()
                    })
        return PipelineResult(success=True, data=alerts, stage="ingest")
    except Exception as e:
        return PipelineResult(success=False, error=str(e), stage="ingest")

# Stage 2: Validate
def validate_alerts(alerts: list) -> PipelineResult:
    """Validate alerts, separate valid from invalid."""
    valid = []
    invalid = []
    for alert in alerts:
        if all(k in alert for k in ["message", "severity", "source"]):
            # all() returns True if every element is True
            if alert["message"].strip() and alert["severity"] in ["low", "medium", "high", "critical"]:
                valid.append(alert)
            else:
                invalid.append({"alert": alert, "reason": "invalid field values"})
        else:
            invalid.append({"alert": alert, "reason": "missing fields"})

    return PipelineResult(
        success=True,
        data={"valid": valid, "invalid": invalid},
        stage="validate"
    )

# Stage 3: Transform (preprocessing)
def transform_alerts(alerts: list) -> PipelineResult:
    """Normalize and enrich alert data."""
    transformed = []
    for alert in alerts:
        # **alert "spreads" all key-value pairs from the alert dict into this new dict.
        # Then we add extra fields after it. The result is a copy of alert PLUS new fields.
        # DBA analogy: like SELECT *, lower(message) AS message_lower FROM alerts
        transformed.append({
            **alert,  # spread all existing fields
            "message_lower": alert["message"].lower(),
            # lowercase for consistent processing
            "message_length": len(alert["message"]),
            "severity_score": {"low": 1, "medium": 2, "high": 3, "critical": 4}[alert["severity"]],
            # Map severity to numeric score
        })
    return PipelineResult(success=True, data=transformed, stage="transform")

# Stage 4: Classify (model inference)
def classify_alerts(alerts: list) -> PipelineResult:
    """Classify alerts into categories using keyword matching (production would use a model)."""
    categories = {
        "performance": ["cpu", "slow", "query", "latency", "timeout", "connection"],
        "storage": ["disk", "space", "full", "wal", "bloat", "storage"],
        "replication": ["replication", "standby", "lag", "wal sender", "primary"],
        "security": ["login", "unauthorized", "ssl", "password", "access", "denied"],
    }

    classified = []
    for alert in alerts:
        msg = alert["message_lower"]
        scores = {}
        for cat, keywords in categories.items():
            scores[cat] = sum(1 for kw in keywords if kw in msg)
            # Count how many keywords match

        if max(scores.values()) > 0:
            category = max(scores, key=scores.get)
            # max with key= finds the key with the highest value
            confidence = min(1.0, max(scores.values()) / 3)
        else:
            category = "unknown"
            confidence = 0.0

        classified.append({
            **alert,
            "category": category,
            "confidence": confidence,
        })

    return PipelineResult(success=True, data=classified, stage="classify")

# Test the stages
print("Pipeline Stages Test")
print("=" * 60)

# Raw input
raw = [
    "critical|prometheus|CPU usage exceeded 95% on pg-primary",
    "high|grafana|Replication lag reached 120 seconds",
    "medium|nagios|Disk usage at 87% on /pgdata",
    "low|custom|SSL certificate expires in 30 days",
    {"message": "Connection pool exhausted", "severity": "high", "source": "app"},
]

# Run each stage
r1 = ingest_alerts(raw)
print(f"[{r1.stage:>10s}] {len(r1.data)} alerts ingested")

r2 = validate_alerts(r1.data)
valid = r2.data["valid"]
invalid = r2.data["invalid"]
print(f"[{r2.stage:>10s}] {len(valid)} valid, {len(invalid)} invalid")

r3 = transform_alerts(valid)
print(f"[{r3.stage:>10s}] {len(r3.data)} alerts transformed")

r4 = classify_alerts(r3.data)
print(f"[{r4.stage:>10s}] {len(r4.data)} alerts classified")

print()
print("Results:")
for alert in r4.data:
    print(f"  [{alert['severity']:>8s}] [{alert['category']:>13s}] "
          f"({alert['confidence']:.0%}) {alert['message'][:45]}")
PYEOF
```

Expected output (yours will differ):

```
Pipeline Stages Test
============================================================
[    ingest] 5 alerts ingested
[  validate] 5 valid, 0 invalid
[ transform] 5 alerts transformed
[  classify] 5 alerts classified

Results:
  [critical] [  performance] (67%) CPU usage exceeded 95% on pg-primary
  [    high] [  replication] (67%) Replication lag reached 120 seconds
  [  medium] [      storage] (67%) Disk usage at 87% on /pgdata
  [     low] [     security] (33%) SSL certificate expires in 30 days
  [    high] [  performance] (33%) Connection pool exhausted
```

---

## Step 3. Chain stages into a pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from dataclasses import dataclass, field
from typing import Optional, Callable, List
from datetime import datetime
import time

@dataclass
class PipelineResult:
    success: bool
    data: object = None
    error: Optional[str] = None
    stage: str = ""
    duration_ms: float = 0

class Pipeline:
    """Chain multiple stages together."""

    def __init__(self, name: str):
        self.name = name
        self.stages: List[tuple] = []
        # List of (stage_name, function) tuples

    def add_stage(self, name: str, func: Callable):
        """Add a processing stage to the pipeline."""
        self.stages.append((name, func))
        return self
        # return self enables method chaining: pipeline.add_stage(...).add_stage(...)

    def run(self, initial_data):
        """Execute all stages in sequence."""
        print(f"\nPipeline: {self.name}")
        print("=" * 50)

        data = initial_data
        results = []

        for stage_name, func in self.stages:
            start = time.time()
            try:
                result = func(data)
                duration = (time.time() - start) * 1000

                if not result.success:
                    print(f"  [{stage_name:>12s}] FAILED: {result.error}")
                    return results  # stop pipeline on failure

                # Extract data for next stage
                if isinstance(result.data, dict) and "valid" in result.data:
                    data = result.data["valid"]  # validation stage outputs valid/invalid
                else:
                    data = result.data

                result.duration_ms = duration
                results.append(result)
                print(f"  [{stage_name:>12s}] OK ({duration:.1f}ms) "
                      f"- {len(data) if isinstance(data, list) else 1} items")

            except Exception as e:
                print(f"  [{stage_name:>12s}] ERROR: {e}")
                return results

        print(f"\nPipeline completed: {len(results)}/{len(self.stages)} stages")
        total_ms = sum(r.duration_ms for r in results)
        print(f"Total time: {total_ms:.1f}ms")

        return results

# Define stages (reusing from Step 2, simplified)
def ingest(raw):
    alerts = []
    for item in raw:
        if isinstance(item, str):
            parts = item.split("|")
            if len(parts) == 3:
                alerts.append({"severity": parts[0].strip(), "source": parts[1].strip(),
                               "message": parts[2].strip(), "timestamp": datetime.now().isoformat()})
        elif isinstance(item, dict):
            alerts.append(item)
    return PipelineResult(success=True, data=alerts, stage="ingest")

def validate(alerts):
    valid = [a for a in alerts if a.get("message", "").strip() and
             a.get("severity") in ["low", "medium", "high", "critical"]]
    invalid = [a for a in alerts if a not in valid]
    return PipelineResult(success=True, data={"valid": valid, "invalid": invalid}, stage="validate")

def transform(alerts):
    for a in alerts:
        a["message_lower"] = a["message"].lower()
        a["severity_score"] = {"low": 1, "medium": 2, "high": 3, "critical": 4}.get(a["severity"], 0)
    return PipelineResult(success=True, data=alerts, stage="transform")

def classify(alerts):
    cats = {"performance": ["cpu", "slow", "query", "latency"],
            "storage": ["disk", "space", "full", "wal"],
            "replication": ["replication", "standby", "lag"],
            "security": ["login", "ssl", "password", "unauthorized"]}
    for a in alerts:
        msg = a["message_lower"]
        # This line does a LOT. Let's break it down:
        # For each category (c) and its keywords (kws) in the dictionary:
        #   count how many keywords appear in the message
        #   store as {category: count}
        # It's like running this SQL for each category:
        #   SELECT category, COUNT(*) FROM keywords WHERE keyword IN (message_words)
        # The result is a dict like {"performance": 3, "storage": 1, "replication": 0}
        scores = {c: sum(1 for k in kws if k in msg) for c, kws in cats.items()}
        a["category"] = max(scores, key=scores.get) if max(scores.values()) > 0 else "unknown"
    return PipelineResult(success=True, data=alerts, stage="classify")

def store(alerts):
    # In production, this would write to a database
    print(f"    -> Would store {len(alerts)} classified alerts to database")
    return PipelineResult(success=True, data=alerts, stage="store")

# Build and run the pipeline
pipeline = Pipeline("Alert Classification")
pipeline.add_stage("ingest", ingest)
pipeline.add_stage("validate", validate)
pipeline.add_stage("transform", transform)
pipeline.add_stage("classify", classify)
pipeline.add_stage("store", store)

raw_alerts = [
    "critical|prometheus|CPU usage exceeded 95% on pg-primary",
    "high|grafana|Replication lag reached 120 seconds on standby",
    "medium|nagios|Disk space at 92% on /pgdata volume",
    "low|custom|SSL certificate expires in 7 days",
    "high|app|Slow query detected: sequential scan on orders table",
]

results = pipeline.run(raw_alerts)

# Show final output
if results:
    final = results[-1].data
    print(f"\nClassified alerts:")
    for a in final:
        print(f"  [{a['severity']:>8s}] [{a['category']:>13s}] {a['message'][:50]}")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Pipeline stage | One step: validate, transform, classify | One step in an ETL job |
| PipelineResult | Standard output format with success/error | Function return with error handling |
| Stage chaining | Output of one stage feeds into the next | Query plan execution order |
| Validation stage | Reject bad data before processing | CHECK constraints on INSERT |
| Pipeline class | Orchestrates stage execution | pgAgent job chain |
