# Build 03: Model Versioning

Models change over time - you retrain with more data, try different architectures, fix bugs. Model versioning tracks what model is running, lets you switch between versions, and enables A/B testing.

---

## Step 1. Model registry

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import os
import time
from datetime import datetime
from pathlib import Path

print("""
Model Registry: Track all model versions in one place.

Think of it like a database migration system:
  - Each version has metadata (when, why, accuracy)
  - You can roll forward or roll back
  - You always know what's running in production

DBA analogy:
  - pg_dump versions: db_backup_2024-01-01.sql, db_backup_2024-01-15.sql
  - Migration files: 001_create_tables.sql, 002_add_indexes.sql
  - You track which version is deployed and can roll back if needed
""")

class ModelRegistry:
    """Track model versions."""

    def __init__(self, registry_dir="/tmp/model_registry"):
        self.registry_dir = Path(registry_dir)
        self.registry_dir.mkdir(parents=True, exist_ok=True)
        # parents=True creates parent directories if needed
        # exist_ok=True doesn't error if directory already exists
        self.registry_file = self.registry_dir / "registry.json"
        self.models = self._load()

    def _load(self):
        """Load registry from disk."""
        if self.registry_file.exists():
            with open(self.registry_file) as f:
                return json.load(f)
        return {"models": {}, "active": None}

    def _save(self):
        """Save registry to disk."""
        with open(self.registry_file, "w") as f:
            json.dump(self.models, f, indent=2)

    def register(self, name, version, metadata):
        """Register a new model version."""
        key = f"{name}:{version}"
        self.models["models"][key] = {
            "name": name,
            "version": version,
            "registered_at": datetime.now().isoformat(),
            **metadata,
        }
        self._save()
        return key

    def set_active(self, name, version):
        """Set which version is active (serving traffic)."""
        key = f"{name}:{version}"
        if key not in self.models["models"]:
            raise ValueError(f"Model {key} not found in registry")
        self.models["active"] = key
        self._save()

    def get_active(self):
        """Get the currently active model."""
        key = self.models.get("active")
        if key:
            return self.models["models"][key]
        return None

    def list_versions(self, name=None):
        """List all registered model versions."""
        versions = []
        for key, meta in self.models["models"].items():
            if name is None or meta["name"] == name:
                is_active = key == self.models.get("active")
                versions.append({**meta, "is_active": is_active})
        return versions

    def rollback(self, name):
        """Roll back to the previous version."""
        versions = [v for v in self.list_versions(name) if not v["is_active"]]
        if not versions:
            raise ValueError("No previous version to roll back to")
        # Sort by registration time, get the most recent non-active
        versions.sort(key=lambda v: v["registered_at"], reverse=True)
        prev = versions[0]
        self.set_active(prev["name"], prev["version"])
        return prev

# Demo
registry = ModelRegistry()

# Register model versions
registry.register("alert_classifier", "v1", {
    "type": "keyword-rules",
    "accuracy": 0.78,
    "f1_score": 0.72,
    "training_data": "500 alerts",
    "description": "Keyword-based baseline",
})

registry.register("alert_classifier", "v2", {
    "type": "fine-tuned-distilbert",
    "accuracy": 0.91,
    "f1_score": 0.89,
    "training_data": "2000 alerts",
    "description": "Fine-tuned DistilBERT on labeled alerts",
})

registry.register("alert_classifier", "v3", {
    "type": "fine-tuned-distilbert-lora",
    "accuracy": 0.94,
    "f1_score": 0.93,
    "training_data": "5000 alerts",
    "description": "LoRA fine-tuned with expanded dataset",
})

# Set v3 as active
registry.set_active("alert_classifier", "v3")

# Show registry
print("Model Registry:")
print("=" * 70)
print(f"{'Version':>8s}  {'Type':>25s}  {'Acc':>5s}  {'F1':>5s}  Active")
print("-" * 65)

for v in registry.list_versions("alert_classifier"):
    active = " <-- ACTIVE" if v["is_active"] else ""
    print(f"{v['version']:>8s}  {v['type']:>25s}  {v['accuracy']:>5.2f}  "
          f"{v['f1_score']:>5.2f}{active}")

# Simulate rollback
print(f"\nActive model: {registry.get_active()['version']}")
print("Simulating problem with v3... Rolling back!")
prev = registry.rollback("alert_classifier")
print(f"Rolled back to: {prev['version']} ({prev['description']})")
print(f"Active model: {registry.get_active()['version']}")
PYEOF
```

---

## Step 2. A/B testing models

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
import time
from collections import defaultdict

random.seed(42)

print("""
A/B Testing: Run two models simultaneously, send traffic to both.

Why?
  - New model might have better accuracy on test data
    but worse accuracy on real production data
  - A/B test catches this before you fully switch over

DBA analogy:
  - Like testing a new index before dropping the old one
  - Or running a query against primary AND replica to compare results
  - Production traffic is the real test, not synthetic benchmarks
""")

# Two "models" with different behavior
def model_v2(message):
    """Keyword-based with moderate accuracy."""
    msg = message.lower()
    if "cpu" in msg or "slow" in msg:
        return "performance", 0.85
    elif "disk" in msg:
        return "storage", 0.80
    elif "replication" in msg or "lag" in msg:
        return "replication", 0.82
    return "unknown", 0.3

def model_v3(message):
    """Improved model with better accuracy on most categories."""
    msg = message.lower()
    if any(w in msg for w in ["cpu", "slow", "query", "connection", "pool"]):
        return "performance", 0.95
    elif any(w in msg for w in ["disk", "space", "wal", "storage"]):
        return "storage", 0.92
    elif any(w in msg for w in ["replication", "lag", "standby", "failover"]):
        return "replication", 0.94
    elif any(w in msg for w in ["login", "ssl", "password"]):
        return "security", 0.90
    return "unknown", 0.4

class ABRouter:
    """Route requests between two model versions."""

    def __init__(self, model_a, model_b, traffic_split=0.8):
        self.model_a = model_a         # current production model
        self.model_b = model_b         # new candidate model
        self.traffic_split = traffic_split
        # traffic_split=0.8 means 80% goes to model_a, 20% to model_b

        self.results = {"a": [], "b": []}

    def route(self, message):
        """Route a request to model A or B based on traffic split."""
        if random.random() < self.traffic_split:
            # Send to model A (current)
            category, confidence = self.model_a(message)
            self.results["a"].append({"confidence": confidence, "category": category})
            return category, confidence, "v2"
        else:
            # Send to model B (candidate)
            category, confidence = self.model_b(message)
            self.results["b"].append({"confidence": confidence, "category": category})
            return category, confidence, "v3"

    def get_comparison(self):
        """Compare performance between models."""
        def stats(results):
            if not results:
                return {"count": 0, "avg_confidence": 0}
            confs = [r["confidence"] for r in results]
            cats = defaultdict(int)
            for r in results:
                cats[r["category"]] += 1
            return {
                "count": len(results),
                "avg_confidence": sum(confs) / len(confs),
                "categories": dict(cats),
            }
        return {
            "model_a (v2)": stats(self.results["a"]),
            "model_b (v3)": stats(self.results["b"]),
        }

# Run A/B test
router = ABRouter(model_v2, model_v3, traffic_split=0.8)

# Simulate 100 requests
test_messages = [
    "CPU at 95% on pg-primary",
    "Disk space at 92%",
    "Replication lag 60 seconds",
    "SSL certificate expiring",
    "Slow query on orders table",
    "Connection pool exhausted",
    "WAL directory growing",
    "Failed login from 10.0.0.99",
    "Standby server not responding",
    "Query latency above 500ms",
]

print("A/B Test: v2 (80% traffic) vs v3 (20% traffic)")
print("=" * 55)

for i in range(100):
    msg = test_messages[i % len(test_messages)]
    cat, conf, version = router.route(msg)

# Show comparison
comparison = router.get_comparison()

print(f"\n{'Metric':<25s}  {'v2 (current)':>15s}  {'v3 (candidate)':>15s}")
print("-" * 60)

a = comparison["model_a (v2)"]
b = comparison["model_b (v3)"]

print(f"{'Requests routed':<25s}  {a['count']:>15d}  {b['count']:>15d}")
print(f"{'Avg confidence':<25s}  {a['avg_confidence']:>15.3f}  {b['avg_confidence']:>15.3f}")

print(f"\nCategory distribution:")
all_cats = set(list(a.get("categories", {}).keys()) + list(b.get("categories", {}).keys()))
for cat in sorted(all_cats):
    a_count = a.get("categories", {}).get(cat, 0)
    b_count = b.get("categories", {}).get(cat, 0)
    print(f"  {cat:<20s}  {a_count:>15d}  {b_count:>15d}")

print("""
A/B testing workflow:
  1. Deploy new model alongside current (don't replace)
  2. Route 10-20% of traffic to the new model
  3. Compare metrics: accuracy, confidence, latency
  4. If new model is better, gradually increase traffic
  5. If new model is worse, route 100% back to current (instant rollback)

This is much safer than "deploy and pray."
""")
PYEOF
```

---

## Step 3. Shadow mode (safe testing)

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import json
from datetime import datetime

print("""
Shadow Mode: Run the new model on real traffic WITHOUT serving its results.

How it works:
  1. Every request goes to the production model (v2) - client gets v2's answer
  2. Secretly, the request ALSO goes to the candidate model (v3)
  3. Compare results offline - the client never sees v3's output
  4. If v3 is better, promote it to production

DBA analogy:
  - Like running EXPLAIN ANALYZE on a new index without actually using it
  - Or testing a new query plan with pg_hint_plan while keeping the old plan active
  - Zero risk to users - they always get the current model's predictions
""")

class ShadowRunner:
    """Run a shadow model alongside production."""

    def __init__(self, production_model, shadow_model):
        self.production = production_model
        self.shadow = shadow_model
        self.comparisons = []

    def predict(self, message):
        """Run both models, return only production result."""
        # Production model (served to client)
        start = time.time()
        prod_cat, prod_conf = self.production(message)
        prod_ms = (time.time() - start) * 1000

        # Shadow model (for comparison only)
        start = time.time()
        shadow_cat, shadow_conf = self.shadow(message)
        shadow_ms = (time.time() - start) * 1000

        # Log comparison (never shown to client)
        self.comparisons.append({
            "message": message[:50],
            "production": {"category": prod_cat, "confidence": prod_conf, "ms": prod_ms},
            "shadow": {"category": shadow_cat, "confidence": shadow_conf, "ms": shadow_ms},
            "agree": prod_cat == shadow_cat,
            "timestamp": datetime.now().isoformat(),
        })

        # Always return production result
        return prod_cat, prod_conf

    def report(self):
        """Show shadow comparison report."""
        total = len(self.comparisons)
        agree = sum(1 for c in self.comparisons if c["agree"])
        disagree = total - agree

        prod_conf = sum(c["production"]["confidence"] for c in self.comparisons) / total
        shadow_conf = sum(c["shadow"]["confidence"] for c in self.comparisons) / total

        return {
            "total_requests": total,
            "agreement_rate": round(agree / total * 100, 1),
            "disagreements": disagree,
            "avg_confidence_production": round(prod_conf, 3),
            "avg_confidence_shadow": round(shadow_conf, 3),
        }

# Models (same as Step 2)
def model_v2(msg):
    m = msg.lower()
    if "cpu" in m or "slow" in m: return "performance", 0.85
    elif "disk" in m: return "storage", 0.80
    elif "replication" in m: return "replication", 0.82
    return "unknown", 0.3

def model_v3(msg):
    m = msg.lower()
    if any(w in m for w in ["cpu", "slow", "query", "connection"]): return "performance", 0.95
    elif any(w in m for w in ["disk", "space", "wal"]): return "storage", 0.92
    elif any(w in m for w in ["replication", "lag", "standby"]): return "replication", 0.94
    elif any(w in m for w in ["login", "ssl", "password"]): return "security", 0.90
    return "unknown", 0.4

# Run shadow test
shadow = ShadowRunner(model_v2, model_v3)

test_messages = [
    "CPU at 95% on primary server",
    "Disk space critically low",
    "Replication lag increasing",
    "Slow query: sequential scan",
    "SSL certificate expiring soon",
    "Connection pool at 98%",
    "Failed login attempt detected",
    "WAL directory growing fast",
    "Query timeout on analytics",
    "Standby failover triggered",
]

print("Shadow Mode: v3 runs silently alongside v2")
print("=" * 65)
print(f"{'Production (v2)':>20s}  {'Shadow (v3)':>20s}  {'Agree':>6s}  Message")
print("-" * 75)

for msg in test_messages:
    # Client only sees production result
    prod_cat, prod_conf = shadow.predict(msg)

    # But we logged the comparison
    comp = shadow.comparisons[-1]
    s = comp["shadow"]
    agree = "yes" if comp["agree"] else "NO"
    print(f"{prod_cat:>13s} ({prod_conf:.0%})  {s['category']:>13s} ({s['confidence']:.0%})  {agree:>6s}  {msg[:30]}")

# Show report
print(f"\nShadow Report:")
report = shadow.report()
for k, v in report.items():
    print(f"  {k}: {v}")

# Show disagreements
disagreements = [c for c in shadow.comparisons if not c["agree"]]
if disagreements:
    print(f"\nDisagreements ({len(disagreements)}):")
    for d in disagreements:
        print(f"  {d['message'][:35]}")
        print(f"    v2: {d['production']['category']}, v3: {d['shadow']['category']}")

print("""
Shadow mode workflow:
  1. Deploy shadow model (no traffic impact)
  2. Run for 1-7 days on real traffic
  3. Analyze: agreement rate, confidence, disagreements
  4. If shadow is clearly better, promote to A/B test
  5. If shadow has issues, fix and re-deploy shadow
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Model registry | Track all model versions | pg_dump backup catalog |
| Active model | Know what's running in production | pg_stat_activity for models |
| Rollback | Switch back to previous version | Point-in-time recovery |
| A/B testing | Compare models on live traffic | Testing new index vs old |
| Shadow mode | Test new model with zero risk | EXPLAIN ANALYZE without using plan |
| Traffic splitting | Route % of requests to each model | Read replicas with load balancing |
