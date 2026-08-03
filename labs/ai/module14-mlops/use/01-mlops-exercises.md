# Use 01: MLOps Exercises

Practice building the operational infrastructure around ML models.

---

## Exercise 1. Experiment comparison report

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

print("""
Exercise: Build an experiment comparison report.

Given multiple experiment results, generate a report that:
  1. Ranks experiments by primary metric
  2. Shows tradeoffs (accuracy vs latency vs size)
  3. Recommends the best model for a given use case
""")

experiments = [
    {"name": "keyword_rules", "accuracy": 0.78, "f1": 0.72, "latency_ms": 0.1, "size_mb": 0.01, "train_time_s": 0.5},
    {"name": "tfidf_logreg", "accuracy": 0.85, "f1": 0.82, "latency_ms": 1.5, "size_mb": 3, "train_time_s": 5},
    {"name": "distilbert_frozen", "accuracy": 0.91, "f1": 0.89, "latency_ms": 42, "size_mb": 250, "train_time_s": 300},
    {"name": "distilbert_lora", "accuracy": 0.94, "f1": 0.93, "latency_ms": 45, "size_mb": 253, "train_time_s": 180},
    {"name": "bert_full", "accuracy": 0.93, "f1": 0.92, "latency_ms": 85, "size_mb": 420, "train_time_s": 600},
]

# Rank by accuracy
by_accuracy = sorted(experiments, key=lambda x: x["accuracy"], reverse=True)

print("Experiment Ranking (by accuracy):")
print("=" * 80)
print(f"{'#':>3s}  {'Name':>20s}  {'Acc':>5s}  {'F1':>5s}  {'Latency':>8s}  {'Size':>8s}  {'Train':>8s}")
print("-" * 75)

for i, exp in enumerate(by_accuracy):
    print(f"{i+1:>3d}  {exp['name']:>20s}  {exp['accuracy']:>5.2f}  {exp['f1']:>5.2f}  "
          f"{exp['latency_ms']:>6.1f}ms  {exp['size_mb']:>6.1f}MB  {exp['train_time_s']:>6.0f}s")

# Recommend for different use cases
print(f"\nRecommendations:")
print("-" * 55)

# Use case 1: real-time alerts (latency < 10ms)
fast_models = [e for e in experiments if e["latency_ms"] < 10]
best_fast = max(fast_models, key=lambda x: x["accuracy"])
print(f"  Real-time (latency < 10ms): {best_fast['name']}")
print(f"    Accuracy: {best_fast['accuracy']:.2f}, Latency: {best_fast['latency_ms']}ms")

# Use case 2: maximum accuracy (no constraints)
best_acc = max(experiments, key=lambda x: x["accuracy"])
print(f"  Max accuracy (no constraints): {best_acc['name']}")
print(f"    Accuracy: {best_acc['accuracy']:.2f}, Latency: {best_acc['latency_ms']}ms")

# Use case 3: best accuracy per MB
efficiency = [(e, e["accuracy"] / max(e["size_mb"], 0.01)) for e in experiments]
best_eff = max(efficiency, key=lambda x: x[1])
print(f"  Most efficient (accuracy/size): {best_eff[0]['name']}")
print(f"    Accuracy: {best_eff[0]['accuracy']:.2f}, Size: {best_eff[0]['size_mb']}MB")

print("\nThe best model depends on your constraints, not just accuracy")
PYEOF
```

---

## Exercise 2. Data quality dashboard

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import random
from collections import Counter

random.seed(42)

print("""
Exercise: Build a data quality dashboard that checks:
  1. Missing values
  2. Category balance
  3. Duplicate detection
  4. Text length distribution
""")

# Generate a dataset with quality issues
data = []
categories = ["performance", "storage", "replication", "security", "backup"]

for i in range(500):
    cat = random.choices(categories, weights=[40, 25, 15, 15, 5])[0]
    # random.choices with weights: performance is 40x more likely than backup
    # This creates an IMBALANCED dataset (common in practice)

    msg = f"Alert {i}: {cat} issue on server-{random.randint(1,20)}"

    # Inject quality issues
    if random.random() < 0.03:
        msg = ""  # empty message (3%)
    if random.random() < 0.02:
        msg = None  # null message (2%)
    if random.random() < 0.05:
        msg = data[random.randint(0, max(0, len(data)-1))]["message"] if data else msg  # duplicate

    data.append({"message": msg, "category": cat, "id": i})

# Quality checks
print("Data Quality Dashboard")
print("=" * 55)

# Check 1: missing values
null_msgs = sum(1 for d in data if d["message"] is None)
empty_msgs = sum(1 for d in data if d["message"] is not None and not str(d["message"]).strip())
print(f"\n1. Missing Values:")
print(f"   Null messages: {null_msgs} ({null_msgs/len(data)*100:.1f}%)")
print(f"   Empty messages: {empty_msgs} ({empty_msgs/len(data)*100:.1f}%)")
status = "OK" if (null_msgs + empty_msgs) / len(data) < 0.05 else "WARNING"
print(f"   Status: {status}")

# Check 2: category balance
cats = Counter(d["category"] for d in data)
print(f"\n2. Category Balance:")
total = len(data)
for cat, count in cats.most_common():
    pct = count / total * 100
    bar = "#" * int(pct)
    status = "ok" if pct > 5 else "LOW"
    print(f"   {cat:>15s}: {count:>4d} ({pct:>5.1f}%) {bar} {status}")

# Check imbalance ratio
max_cat = cats.most_common(1)[0][1]
min_cat = cats.most_common()[-1][1]
ratio = max_cat / min_cat
print(f"   Imbalance ratio: {ratio:.1f}x (>{5}x is problematic)")

# Check 3: duplicates
valid_msgs = [str(d["message"]).lower().strip() for d in data if d["message"]]
unique = len(set(valid_msgs))
dupes = len(valid_msgs) - unique
print(f"\n3. Duplicates:")
print(f"   Total messages: {len(valid_msgs)}")
print(f"   Unique: {unique}")
print(f"   Duplicates: {dupes} ({dupes/len(valid_msgs)*100:.1f}%)")

# Check 4: text length
lengths = [len(str(d["message"])) for d in data if d["message"]]
print(f"\n4. Text Length Distribution:")
print(f"   Min: {min(lengths)} chars")
print(f"   Max: {max(lengths)} chars")
print(f"   Mean: {sum(lengths)/len(lengths):.0f} chars")
short = sum(1 for l in lengths if l < 10)
print(f"   Very short (<10 chars): {short} ({short/len(lengths)*100:.1f}%)")

# Overall score
issues = (null_msgs + empty_msgs > len(data) * 0.05) + (ratio > 5) + (dupes > len(data) * 0.1)
score = ["GOOD", "ACCEPTABLE", "NEEDS WORK", "POOR"][min(issues, 3)]
print(f"\nOverall Data Quality: {score} ({3-issues}/3 checks passed)")
PYEOF
```

---

## Exercise 3. Deployment rollback

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime, timedelta

print("""
Exercise: Implement automated rollback.

Scenario: You deployed model v4. Within 30 minutes, accuracy dropped.
The system should automatically roll back to v3.
""")

class ModelDeployment:
    """Track deployments with rollback capability."""

    def __init__(self):
        self.history = []
        self.active = None

    def deploy(self, version, metrics):
        entry = {
            "version": version,
            "deployed_at": datetime.now().isoformat(),
            "metrics_at_deploy": metrics,
            "status": "active",
        }
        # Deactivate current
        if self.active:
            self.active["status"] = "replaced"
        self.history.append(entry)
        self.active = entry
        return entry

    def check_health(self, current_metrics, thresholds):
        """Check if current metrics are within acceptable range."""
        issues = []
        for metric, threshold in thresholds.items():
            if metric in current_metrics:
                if current_metrics[metric] < threshold:
                    issues.append(f"{metric}: {current_metrics[metric]:.2f} < {threshold:.2f}")
        return len(issues) == 0, issues

    def rollback(self):
        """Roll back to the previous version."""
        if len(self.history) < 2:
            return None, "No previous version to roll back to"

        # Mark current as rolled back
        self.active["status"] = "rolled_back"
        self.active["rolled_back_at"] = datetime.now().isoformat()

        # Find the last good version
        for entry in reversed(self.history[:-1]):
            if entry["status"] != "rolled_back":
                entry["status"] = "active"
                self.active = entry
                return entry, f"Rolled back to {entry['version']}"

        return None, "No good version found"

# Simulate deployment and rollback
deployer = ModelDeployment()

# Deploy v3 (good model)
deployer.deploy("v3", {"accuracy": 0.91, "f1": 0.89, "latency_ms": 45})
print("Deployed v3: accuracy=0.91, f1=0.89")

# Deploy v4 (new model)
deployer.deploy("v4", {"accuracy": 0.94, "f1": 0.93, "latency_ms": 47})
print("Deployed v4: accuracy=0.94, f1=0.93")

# After 30 minutes, v4 accuracy drops on real traffic
print("\n30 minutes later...")
current = {"accuracy": 0.78, "f1": 0.74, "latency_ms": 120}
thresholds = {"accuracy": 0.85, "f1": 0.82}

healthy, issues = deployer.check_health(current, thresholds)
print(f"Health check: {'HEALTHY' if healthy else 'UNHEALTHY'}")
for issue in issues:
    print(f"  Issue: {issue}")

if not healthy:
    print("\nTriggering automatic rollback...")
    previous, message = deployer.rollback()
    print(f"  {message}")
    print(f"  Active model: {deployer.active['version']}")
    print(f"  Metrics at deploy: {deployer.active['metrics_at_deploy']}")

print(f"\nDeployment History:")
for entry in deployer.history:
    print(f"  {entry['version']}: {entry['status']}")
PYEOF
```

---

## Exercise 4. Model reproducibility check

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import hashlib
import random
from datetime import datetime

print("""
Exercise: Verify you can reproduce a model from its metadata.

A model is reproducible if you can recreate it exactly from:
  1. Training data version (hash)
  2. Random seed
  3. Hyperparameters
  4. Code version (git commit)
""")

def create_model_card(model_name, params, data_hash, git_commit, metrics):
    """Create a model card with full reproducibility info."""
    return {
        "model_name": model_name,
        "version": params.get("version", "unknown"),
        "created_at": datetime.now().isoformat(),

        "reproducibility": {
            "data_hash": data_hash,
            "random_seed": params.get("seed", None),
            "git_commit": git_commit,
            "python_version": "3.11",
            "dependencies": {
                "torch": "2.1.0",
                "transformers": "4.36.0",
                "scikit-learn": "1.3.2",
            },
        },

        "hyperparameters": {
            k: v for k, v in params.items()
            if k not in ["version", "seed"]
        },

        "metrics": metrics,

        "training": {
            "train_size": params.get("train_size", "unknown"),
            "epochs": params.get("epochs", "unknown"),
            "training_time_s": params.get("training_time_s", "unknown"),
        },
    }

# Create a model card
card = create_model_card(
    "alert_classifier",
    {
        "version": "v4",
        "seed": 42,
        "learning_rate": 2e-4,
        "epochs": 5,
        "batch_size": 32,
        "model_type": "distilbert+lora",
        "lora_rank": 8,
        "lora_alpha": 16,
        "train_size": 4000,
        "training_time_s": 180,
    },
    data_hash="abc123def456",
    git_commit="7f8a9b0c1d2e",
    metrics={
        "accuracy": 0.94,
        "f1_score": 0.93,
        "precision": 0.95,
        "recall": 0.91,
        "p95_latency_ms": 47,
    }
)

print("Model Card:")
print("=" * 55)
print(json.dumps(card, indent=2))

# Reproducibility checklist
print(f"\nReproducibility Checklist:")
checks = {
    "Data version tracked": card["reproducibility"]["data_hash"] is not None,
    "Random seed recorded": card["reproducibility"]["random_seed"] is not None,
    "Git commit recorded": card["reproducibility"]["git_commit"] is not None,
    "Dependencies pinned": len(card["reproducibility"]["dependencies"]) > 0,
    "Hyperparams recorded": len(card["hyperparameters"]) > 0,
    "Metrics recorded": len(card["metrics"]) > 0,
}

all_pass = True
for check, passed in checks.items():
    status = "PASS" if passed else "FAIL"
    if not passed:
        all_pass = False
    print(f"  [{status}] {check}")

print(f"\nReproducibility: {'FULL' if all_pass else 'INCOMPLETE'}")
PYEOF
```

---

## Exercise 5. MLOps maturity assessment

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Exercise: Assess your ML system's operational maturity.

Level 0: Manual (most teams start here)
  - Train models in notebooks
  - Deploy by copying files
  - No monitoring, no versioning
  - "It works on my machine"

Level 1: Tracked
  - Experiments are tracked (params + metrics)
  - Models are versioned
  - Basic monitoring (is the server up?)
  - Manual deployment

Level 2: Automated
  - CI/CD runs tests on every change
  - Automated deployment with gates
  - Performance monitoring (accuracy, latency)
  - Data versioning

Level 3: Full MLOps
  - Automated retraining (drift/performance triggered)
  - A/B testing for new models
  - Data lineage and governance
  - Feature store
  - Automated rollback
  - Full observability

Assessment checklist:
""")

checklist = {
    "Level 0 -> 1": [
        ("Experiments tracked (params + metrics)", True),
        ("Models saved with version numbers", True),
        ("Training data saved (not just code)", True),
        ("Health check endpoint on model server", True),
    ],
    "Level 1 -> 2": [
        ("CI/CD runs model tests automatically", True),
        ("Deployment requires passing quality gates", True),
        ("Accuracy monitored in production", True),
        ("Data versions tracked with hashes", True),
        ("Rollback can be done in < 5 minutes", True),
    ],
    "Level 2 -> 3": [
        ("Retraining triggers automatically", False),
        ("A/B testing infrastructure exists", False),
        ("Data lineage is tracked end-to-end", False),
        ("Feature store for shared features", False),
        ("Model governance and audit trail", False),
    ],
}

total_checks = 0
total_passed = 0

for level, checks in checklist.items():
    passed = sum(1 for _, p in checks if p)
    total = len(checks)
    total_checks += total
    total_passed += passed
    pct = passed / total * 100

    print(f"\n{level}: {passed}/{total} ({pct:.0f}%)")
    for desc, status in checks:
        icon = "x" if status else " "
        print(f"  [{icon}] {desc}")

current_level = 0
if total_passed >= 4:
    current_level = 1
if total_passed >= 9:
    current_level = 2
if total_passed >= 14:
    current_level = 3

print(f"\nCurrent MLOps Level: {current_level}")
print(f"Total: {total_passed}/{total_checks} practices implemented")
print(f"\nThis module gave you the tools for Level 2.")
print(f"Level 3 comes with scale and team size.")
PYEOF
```

---

## What You Practiced

| Exercise | Skill | Production Use |
|----------|-------|---------------|
| Experiment comparison | Choose best model for constraints | Informed deployment decisions |
| Data quality dashboard | Detect data issues early | Prevent training on bad data |
| Deployment rollback | Automated recovery from bad deploys | Production resilience |
| Model reproducibility | Recreate any model from metadata | Debugging and auditing |
| Maturity assessment | Know where you are and what's next | Prioritize improvements |
