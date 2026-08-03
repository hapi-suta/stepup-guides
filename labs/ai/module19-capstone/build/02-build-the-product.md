# Build 02: Build the Product

Assemble all components into a working product. This combines code from Modules 5-18 into one integrated system.

---

## Step 1. The complete classifier

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import math
import json
import time
import hashlib
from datetime import datetime
# Counter counts items: Counter(["a","b","a"]) -> {"a": 2, "b": 1}
# defaultdict auto-creates missing keys instead of crashing.
# DBA analogy: Counter = GROUP BY + COUNT. defaultdict = INSERT ON CONFLICT DO UPDATE.
from collections import Counter, defaultdict

# ============================================================
# dbaBrain ALERT CLASSIFIER - COMPLETE PRODUCT
# This is the entire classification engine in one file.
# Every component comes from a previous module.
# ============================================================

print("dbaBrain Alert Classifier - Complete Build")
print("=" * 55)

# --- Component 1: Feature Extraction (Module 5-8, 16) ---

class FeatureExtractor:
    """Extract features from text and metrics (Module 5-8, 16)."""

    def __init__(self):
        self.keywords = {
            "performance": ["cpu", "slow", "latency", "query", "lock", "wait", "vacuum", "bloat"],
            "storage": ["disk", "space", "full", "tablespace", "wal", "archive"],
            "replication": ["replication", "lag", "standby", "replica", "failover"],
            "security": ["login", "password", "ssl", "auth", "denied", "pg_hba"],
            "connectivity": ["connection", "timeout", "refused", "pool", "pgbouncer"],
            "backup": ["backup", "restore", "pitr", "basebackup", "pg_dump"],
        }
        self.metric_ranges = {
            "cpu_percent": (0, 100),
            "memory_percent": (0, 100),
            "disk_percent": (0, 100),
            "connections": (0, 500),
            "replication_lag_seconds": (0, 3600),
        }

    def extract(self, text, metrics=None):
        """
        Convert raw text and metrics into numbers the classifier can use.
        This is the same approach from Module 16 - keyword counting for text,
        min-max normalization for metrics.
        """
        text_lower = text.lower()    # lowercase so "CPU" matches "cpu"
        features = {}

        # Text keyword features: count matching keywords per category
        # sum(1 for kw in kws if kw in text_lower) = count matches
        # DBA analogy: SELECT COUNT(*) FROM keywords WHERE keyword IN (alert_words)
        for cat, kws in self.keywords.items():
            matches = sum(1 for kw in kws if kw in text_lower)
            features[f"text_{cat}"] = matches    # e.g. "text_performance": 3

        # Metric features: normalize each metric to 0-1 range
        # (metrics or {}) means: use metrics if provided, empty dict if None
        # .get(name) returns the value or None if the metric isn't present
        for name, (min_v, max_v) in self.metric_ranges.items():
            val = (metrics or {}).get(name)       # like COALESCE - safe lookup
            if val is not None:
                # Min-max scaling: (value - min) / (max - min)
                # max(0, min(1, ...)) clips the result to 0-1 range
                scaled = max(0, min(1, (val - min_v) / (max_v - min_v)))
                features[f"metric_{name}"] = round(scaled, 4)
                features[f"missing_{name}"] = 0   # metric was present
            else:
                features[f"metric_{name}"] = 0.0
                features[f"missing_{name}"] = 1   # metric was missing

        return features


# --- Component 2: Classifier (Module 9-10, 16) ---

class AlertClassifier:
    """Multi-modal alert classifier (Modules 9-10, 16)."""

    def __init__(self):
        self.text_rules = {
            "performance": ["cpu", "slow", "latency", "query", "lock", "vacuum"],
            "storage": ["disk", "space", "full", "wal", "archive", "tablespace"],
            "replication": ["replication", "lag", "standby", "replica", "failover"],
            "security": ["login", "password", "ssl", "auth", "denied"],
            "connectivity": ["connection", "timeout", "refused", "pool"],
            "backup": ["backup", "restore", "pitr", "basebackup"],
        }
        self.metric_rules = [
            ("cpu_percent", 85, "performance"),
            ("disk_percent", 85, "storage"),
            ("replication_lag_seconds", 30, "replication"),
            ("connections", 400, "connectivity"),
        ]

    def classify(self, text, metrics=None):
        """
        Classify an alert using late fusion (Module 16).
        Text and metrics each vote separately, then we combine.
        """
        # --- Text classification ---
        # Count keyword matches per category (same as Module 16)
        text_lower = text.lower()
        text_scores = {}                     # category -> confidence score
        for cat, kws in self.text_rules.items():
            score = sum(1 for kw in kws if kw in text_lower)  # count matches
            if score > 0:
                # Convert match count to confidence (1 match=0.62, 2=0.74, etc.)
                text_scores[cat] = min(0.5 + score * 0.12, 0.85)

        # --- Metric classification ---
        # Check if any metric exceeds its threshold
        metric_scores = {}                   # category -> confidence score
        for name, thresh, cat in self.metric_rules:
            # (metrics or {}).get(name) = safe lookup, returns None if missing
            val = (metrics or {}).get(name)
            if val is not None and val >= thresh:
                # How far above threshold? (0.0 = at threshold, 1.0 = double)
                severity = min((val - thresh) / thresh, 1.0)
                metric_scores[cat] = min(0.5 + severity * 0.35, 0.9)

        # --- Late fusion: combine text and metric votes ---
        # set() removes duplicates - get all categories from both models
        all_cats = set(list(text_scores.keys()) + list(metric_scores.keys()))
        combined = {}
        for cat in all_cats:
            tc = text_scores.get(cat, 0)     # text confidence (0 if no text match)
            mc = metric_scores.get(cat, 0)   # metric confidence (0 if no metric match)
            if tc > 0 and mc > 0:
                # Both agree: average + agreement bonus (Module 16 late fusion)
                combined[cat] = min((tc + mc) / 2 + 0.08, 0.95)
            elif tc > 0:
                combined[cat] = tc * 0.85    # text only: slight penalty
            else:
                combined[cat] = mc * 0.85    # metrics only: slight penalty

        if not combined:
            return "unknown", 0.1, []        # nothing matched at all

        # Pick category with highest combined score
        best = max(combined, key=combined.get)
        evidence = []
        if best in text_scores:
            evidence.append(f"text_keywords_matched")
        if best in metric_scores:
            evidence.append(f"metric_threshold_exceeded")

        return best, round(combined[best], 3), evidence


# --- Component 3: Severity Scorer (Module 17) ---

class SeverityScorer:
    """Score severity and assign priority (Module 17)."""

    def __init__(self):
        self.critical_thresholds = {
            "cpu_percent": 95, "disk_percent": 95,
            "replication_lag_seconds": 600, "connections": 480,
        }
        self.env_weights = {"production": 1.5, "staging": 1.0, "development": 0.5}

    def score(self, metrics, environment="production"):
        metric_score = 0
        has_critical = False

        for name, thresh in self.critical_thresholds.items():
            val = (metrics or {}).get(name)
            if val is not None and val >= thresh:
                has_critical = True
                metric_score = max(metric_score, 90)
            elif val is not None and val >= thresh * 0.85:
                metric_score = max(metric_score, 70)

        env_weight = self.env_weights.get(environment, 1.0)
        final = min(metric_score * env_weight, 100)

        if has_critical and environment == "production":
            final = max(final, 80)

        if final >= 80: priority = "P1"
        elif final >= 60: priority = "P2"
        elif final >= 30: priority = "P3"
        else: priority = "P4"

        return round(final), priority, has_critical


# --- Component 4: Diagnostics (Module 17) ---

class DiagnosticsEngine:
    """Root cause analysis (Module 17)."""

    def __init__(self):
        self.causes = {
            "performance": [
                ("Long-running query", ["query", "slow", "pid"]),
                ("Autovacuum on large table", ["vacuum", "autovacuum"]),
                ("Lock contention", ["lock", "blocked", "wait"]),
            ],
            "storage": [
                ("WAL archiving failed", ["wal", "archive"]),
                ("Table bloat", ["bloat", "dead tuples", "full"]),
            ],
            "replication": [
                ("Network issue to standby", ["replication", "lag"]),
            ],
            "connectivity": [
                ("Connection leak", ["connection", "too many", "pool"]),
            ],
        }

    def diagnose(self, text, category):
        text_lower = text.lower()
        candidates = self.causes.get(category, [])

        for cause, keywords in candidates:
            # any() returns True if ANY item in the list is True.
            # "any keyword found in the text?" - if yes, this is the cause.
            # DBA analogy: like WHERE keyword = ANY(ARRAY['lock','blocked','wait'])
            if any(kw in text_lower for kw in keywords):
                return cause

        return f"General {category} issue - investigate manually"


# --- Component 5: Output Filter (Module 15) ---

class OutputFilter:
    """Security output filtering (Module 15)."""

    def __init__(self):
        self.valid_categories = [
            "performance", "storage", "replication",
            "security", "connectivity", "backup", "unknown",
        ]
        # Regex patterns to find and replace sensitive data.
        # r'\b\d{1,3}...\b' matches IP addresses like 192.168.1.1
        # r'\bpg-\w+...\b' matches server names like pg-primary-1
        # Each tuple is (pattern_to_find, replacement_text).
        self.redact_patterns = [
            (r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP_REDACTED]'),
            (r'\bpg-\w+[-\w]*\b', '[SERVER_REDACTED]'),
        ]

    def filter(self, response):
        if response.get("category") not in self.valid_categories:
            response["category"] = "unknown"
        response["confidence"] = max(0, min(1, response.get("confidence", 0)))

        # Redact sensitive info from explanation
        explanation = response.get("explanation", "")
        for pattern, replacement in self.redact_patterns:
            explanation = re.sub(pattern, replacement, explanation)
        response["explanation"] = explanation

        return response


# --- Component 6: Audit Logger (Module 14-15) ---

class AuditLogger:
    """Log all predictions for audit (Modules 14-15)."""

    def __init__(self):
        self.log = []

    def record(self, request_id, request, response, duration_ms):
        self.log.append({
            "request_id": request_id,
            "timestamp": datetime.now().isoformat(),
            "input_text": request.get("text", "")[:100],
            "has_metrics": bool(request.get("metrics")),
            "category": response.get("category"),
            "confidence": response.get("confidence"),
            "priority": response.get("priority"),
            "duration_ms": round(duration_ms, 2),
        })


# === ASSEMBLE THE PRODUCT ===

class DBaBrainClassifier:
    """
    The complete dbaBrain Alert Classifier.

    Assembles all components into one product.
    Every component comes from a previous module.
    """

    def __init__(self, environment="production"):
        self.extractor = FeatureExtractor()
        self.classifier = AlertClassifier()
        self.scorer = SeverityScorer()
        self.diagnostics = DiagnosticsEngine()
        self.output_filter = OutputFilter()
        self.audit = AuditLogger()
        self.environment = environment

    def classify(self, text, metrics=None):
        """Full classification pipeline."""
        start = time.time()                 # record start time for latency tracking
        # Generate a unique request ID (like a transaction ID in PostgreSQL).
        # hashlib.md5() creates a hash, .hexdigest() converts to text,
        # [:8] takes the first 8 characters. Just a short unique identifier.
        request_id = hashlib.md5(f"{time.time()}".encode()).hexdigest()[:8]

        # Step 1: Extract features
        features = self.extractor.extract(text, metrics)

        # Step 2: Classify
        category, confidence, evidence = self.classifier.classify(text, metrics)

        # Step 3: Score severity
        severity, priority, is_critical = self.scorer.score(metrics, self.environment)

        # Step 4: Diagnose
        root_cause = self.diagnostics.diagnose(text, category)

        # Step 5: Build response
        response = {
            "request_id": request_id,
            "category": category,
            "confidence": confidence,
            "severity_score": severity,
            "priority": priority,
            "is_critical": is_critical,
            "root_cause": root_cause,
            "evidence": evidence,
            "environment": self.environment,
            "explanation": f"{category} alert: {root_cause}",
        }

        # Step 6: Filter output
        response = self.output_filter.filter(response)

        # Step 7: Audit log
        duration = (time.time() - start) * 1000
        self.audit.record(request_id, {"text": text, "metrics": metrics}, response, duration)

        response["latency_ms"] = round(duration, 2)
        return response


# === TEST THE PRODUCT ===

brain = DBaBrainClassifier(environment="production")

test_alerts = [
    {"text": "CPU at 96% on pg-primary-prod-3, long running query PID 12345",
     "metrics": {"cpu_percent": 96, "memory_percent": 60}},
    {"text": "Disk at 98% on /pgdata, WAL files accumulating",
     "metrics": {"disk_percent": 98}},
    {"text": "Replication lag 500 seconds on standby-2",
     "metrics": {"replication_lag_seconds": 500}},
    {"text": "Too many connections: 490 of 500",
     "metrics": {"connections": 490}},
    {"text": "Something happened on the server",
     "metrics": {"cpu_percent": 40}},
    {"text": "Backup failed on pg-backup-server",
     "metrics": {}},
]

print("\ndbaBrain Classification Results:")
print("-" * 70)

for alert in test_alerts:
    result = brain.classify(alert["text"], alert.get("metrics"))

    print(f"\n  Alert: '{alert['text'][:55]}...'")
    print(f"  Result: {result['category']} ({result['confidence']:.0%}) "
          f"| Severity: {result['severity_score']} ({result['priority']}) "
          f"| {result['latency_ms']:.1f}ms")
    print(f"  Root cause: {result['root_cause']}")

# Show audit log summary
print(f"\nAudit Log: {len(brain.audit.log)} entries")
avg_latency = sum(e["duration_ms"] for e in brain.audit.log) / len(brain.audit.log)
print(f"Average latency: {avg_latency:.1f}ms")

PYEOF
```

---

## Step 2. The API server

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

# ============================================================
# API SERVER DESIGN
# Wrapping the classifier in a REST API (Module 13).
# We show the structure here - FastAPI code from Module 13.
# ============================================================

print("API Server Design")
print("=" * 50)

# Request schema (Pydantic from Module 13)
request_schema = {
    "text": {"type": "string", "required": True, "max_length": 5000},
    "metrics": {"type": "object", "required": False},
    "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"], "required": False},
    "environment": {"type": "string", "default": "production"},
}

# Response schema
response_schema = {
    "request_id": "string (unique ID)",
    "category": "string (one of 6 categories + unknown)",
    "confidence": "float (0.0 to 1.0)",
    "severity_score": "int (0 to 100)",
    "priority": "string (P1-P4)",
    "root_cause": "string (suggested root cause)",
    "evidence": "list (what supported this classification)",
    "latency_ms": "float (processing time)",
}

# API endpoints
endpoints = [
    {
        "method": "POST",
        "path": "/classify",
        "description": "Classify a single alert",
        "request": "AlertRequest (text + optional metrics)",
        "response": "ClassificationResult",
    },
    {
        "method": "POST",
        "path": "/classify/batch",
        "description": "Classify multiple alerts",
        "request": "List[AlertRequest] (max 50)",
        "response": "List[ClassificationResult]",
    },
    {
        "method": "POST",
        "path": "/feedback",
        "description": "Submit DBA correction",
        "request": "FeedbackRequest (request_id + correct_category)",
        "response": "FeedbackAck",
    },
    {
        "method": "GET",
        "path": "/health",
        "description": "Health check",
        "request": "None",
        "response": "HealthStatus (status, model_version, uptime)",
    },
    {
        "method": "GET",
        "path": "/metrics",
        "description": "Accuracy and performance metrics",
        "request": "None",
        "response": "MetricsReport (accuracy per category, latency stats)",
    },
]

print("\nAPI Endpoints:")
print("-" * 55)
for ep in endpoints:
    print(f"  {ep['method']:<6s} {ep['path']:<20s} {ep['description']}")

print(f"\nRequest Schema:")
for field, info in request_schema.items():
    req = "required" if info.get("required") else "optional"
    print(f"  {field:<15s} {info['type']:<10s} {req}")

print(f"\nResponse Schema:")
for field, desc in response_schema.items():
    print(f"  {field:<20s} {desc}")

print("""
FastAPI code structure (from Module 13):

  app = FastAPI(title="dbaBrain Alert Classifier")

  @app.post("/classify")
  async def classify(request: AlertRequest) -> ClassificationResult:
      result = brain.classify(request.text, request.metrics)
      return ClassificationResult(**result)

  @app.post("/feedback")
  async def feedback(request: FeedbackRequest) -> FeedbackAck:
      store.record_feedback(request.request_id, request.correct_category)
      return FeedbackAck(status="received")

  @app.get("/health")
  async def health() -> HealthStatus:
      return HealthStatus(status="healthy", model_version="1.0")
""")
PYEOF
```

---

## Step 3. Monitoring setup

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from collections import defaultdict, Counter
from datetime import datetime, timedelta
import random

random.seed(42)

# ============================================================
# MONITORING SETUP
# Track everything the product does (Module 14).
# Without monitoring, you're flying blind.
# ============================================================

print("Monitoring Setup")
print("=" * 50)

class ProductMonitor:
    """
    Monitor all aspects of the classification product.

    Tracks:
    1. Accuracy per category (from DBA feedback)
    2. Prediction latency (p50, p95, p99)
    3. Request volume (per minute)
    4. Error rate
    5. Confidence distribution
    """

    def __init__(self):
        self.predictions = []
        self.feedback = []
        self.errors = []
        self.latencies = []

    def record_prediction(self, category, confidence, latency_ms):
        self.predictions.append({
            "category": category,
            "confidence": confidence,
            "latency_ms": latency_ms,
            "timestamp": datetime.now(),
        })
        self.latencies.append(latency_ms)

    def record_feedback(self, predicted, actual):
        self.feedback.append({
            "predicted": predicted,
            "actual": actual,
            "correct": predicted == actual,
        })

    def record_error(self, error_type, message):
        self.errors.append({
            "type": error_type,
            "message": message,
            "timestamp": datetime.now(),
        })

    def get_dashboard(self):
        """Generate monitoring dashboard."""
        dashboard = {}

        # Accuracy
        if self.feedback:
            correct = sum(1 for f in self.feedback if f["correct"])
            dashboard["accuracy"] = {
                "overall": round(correct / len(self.feedback) * 100, 1),
                "total_feedback": len(self.feedback),
            }

            # Per-category
            cat_stats = defaultdict(lambda: {"correct": 0, "total": 0})
            for f in self.feedback:
                cat_stats[f["actual"]]["total"] += 1
                if f["correct"]:
                    cat_stats[f["actual"]]["correct"] += 1

            dashboard["per_category"] = {}
            for cat, stats in cat_stats.items():
                acc = stats["correct"] / stats["total"] * 100 if stats["total"] > 0 else 0
                dashboard["per_category"][cat] = round(acc, 1)

        # Latency
        if self.latencies:
            sorted_lat = sorted(self.latencies)
            n = len(sorted_lat)
            dashboard["latency"] = {
                "p50": round(sorted_lat[int(n * 0.5)], 1),
                "p95": round(sorted_lat[int(n * 0.95)], 1),
                "p99": round(sorted_lat[min(int(n * 0.99), n-1)], 1),
                "total_requests": n,
            }

        # Category distribution
        if self.predictions:
            cat_dist = Counter(p["category"] for p in self.predictions)
            dashboard["category_distribution"] = dict(cat_dist.most_common())

        # Error rate
        total = len(self.predictions)
        dashboard["error_rate"] = round(len(self.errors) / max(total, 1) * 100, 2)

        return dashboard


# Simulate production traffic
monitor = ProductMonitor()

categories = ["performance", "storage", "replication", "connectivity", "security", "backup"]

# Simulate 500 predictions
for _ in range(500):
    cat = random.choice(categories)
    conf = random.uniform(0.5, 0.95)
    latency = random.gauss(15, 5)  # mean=15ms, std=5ms
    monitor.record_prediction(cat, conf, max(latency, 1))

# Simulate 200 feedback entries (90% accuracy)
for _ in range(200):
    actual = random.choice(categories)
    predicted = actual if random.random() < 0.90 else random.choice(categories)
    monitor.record_feedback(predicted, actual)

# Simulate some errors
for _ in range(5):
    monitor.record_error("timeout", "Request timed out after 10s")

# Display dashboard
dashboard = monitor.get_dashboard()

print(f"\nProduction Dashboard:")
print("-" * 55)

if "accuracy" in dashboard:
    print(f"  Overall accuracy: {dashboard['accuracy']['overall']}% "
          f"({dashboard['accuracy']['total_feedback']} reviews)")

    if "per_category" in dashboard:
        print(f"\n  Per-category accuracy:")
        for cat, acc in sorted(dashboard['per_category'].items()):
            bar = "#" * int(acc / 5)
            flag = " <- BELOW 80%" if acc < 80 else ""
            print(f"    {cat:<15s} {acc:>5.1f}% {bar}{flag}")

if "latency" in dashboard:
    lat = dashboard["latency"]
    print(f"\n  Latency: p50={lat['p50']}ms, p95={lat['p95']}ms, p99={lat['p99']}ms")
    print(f"  Total requests: {lat['total_requests']}")

print(f"  Error rate: {dashboard['error_rate']}%")

if "category_distribution" in dashboard:
    print(f"\n  Category distribution:")
    for cat, count in dashboard['category_distribution'].items():
        print(f"    {cat:<15s} {count:>4d}")

print("""
What to alert on:
  - Overall accuracy drops below 85%
  - Any category drops below 75%
  - p95 latency exceeds 500ms
  - Error rate exceeds 1%
  - Prediction volume drops to 0 (pipeline is dead)
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Product assembly | Combine all components | Building the cluster from components |
| Complete classifier | End-to-end classification pipeline | Full query execution pipeline |
| API design | REST endpoints for the product | PgBouncer frontend |
| Monitoring dashboard | Track accuracy, latency, errors | pg_stat_statements + Grafana |
| Production metrics | p50/p95/p99 latency, per-category accuracy | Query performance percentiles |
