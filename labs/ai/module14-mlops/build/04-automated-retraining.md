# Build 04: Automated Retraining

Models degrade over time as data changes. Automated retraining detects when a model needs updating and triggers a new training cycle - without manual intervention.

---

## Step 1. Why models need retraining

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
import time

random.seed(42)

print("""
Models Degrade Over Time (Data Drift):

Month 1: Model trained on alerts from January. Accuracy: 94%
Month 3: New alert patterns appear (K8s, cloud-native). Accuracy: 88%
Month 6: Major infra change (AWS to GCP). Accuracy: 76%
Month 9: Half the alerts are patterns the model never saw. Accuracy: 62%

The model didn't break - the world changed and the model didn't.

DBA analogy:
  Like PostgreSQL statistics going stale.
  - ANALYZE updates statistics so the query planner makes good choices
  - Without ANALYZE, the planner uses outdated stats and picks bad plans
  - Queries slow down even though nothing "broke"

  autoanalyze runs ANALYZE automatically when data changes enough.
  Automated retraining is autoanalyze for your models.

When to retrain:
  1. SCHEDULED: every week/month (simple, predictable)
  2. DRIFT-TRIGGERED: when data distribution changes significantly
  3. PERFORMANCE-TRIGGERED: when accuracy drops below threshold
  4. DATA-TRIGGERED: when new labeled data accumulates
""")

# Simulate accuracy degradation over time
print("Simulating model degradation over 12 months:")
print("-" * 50)

accuracy = 0.94
for month in range(1, 13):
    # Simulate drift: accuracy drops ~2% per month
    drift = random.uniform(0.01, 0.04)
    accuracy = max(0.5, accuracy - drift)

    bar = "#" * int(accuracy * 40)
    status = "OK" if accuracy > 0.85 else ("WARN" if accuracy > 0.75 else "CRITICAL")
    print(f"  Month {month:>2d}: {accuracy:.2f} {bar} [{status}]")

    if accuracy < 0.75:
        print(f"           ^ Retrain trigger! Accuracy below 75%")

print(f"\nWithout retraining: accuracy dropped from 94% to {accuracy:.0%}")
print("With automated retraining: accuracy stays above 85% (retrain threshold)")
PYEOF
```

---

## Step 2. Build a retraining trigger

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import random
import time
from datetime import datetime, timedelta
from collections import defaultdict

random.seed(42)

print("""
Retraining Triggers: Automatically detect when to retrain.

Three types:
  1. Schedule-based: retrain every N days (simplest)
  2. Performance-based: retrain when accuracy drops (reactive)
  3. Drift-based: retrain when data distribution changes (proactive)
""")

class RetrainingTrigger:
    """Monitor model performance and trigger retraining."""

    def __init__(self, model_name):
        self.model_name = model_name
        self.predictions = []
        self.last_retrain = datetime.now()
        self.retrain_count = 0

    def log_prediction(self, predicted, actual, timestamp=None):
        """Log a prediction with ground truth."""
        self.predictions.append({
            "predicted": predicted,
            "actual": actual,
            "correct": predicted == actual,
            "timestamp": (timestamp or datetime.now()).isoformat(),
        })

    def check_schedule(self, retrain_every_days=7):
        """Check if it's time for scheduled retraining."""
        days_since = (datetime.now() - self.last_retrain).days
        if days_since >= retrain_every_days:
            return True, f"Last retrain was {days_since} days ago (threshold: {retrain_every_days})"
        return False, f"Last retrain was {days_since} days ago (next in {retrain_every_days - days_since} days)"

    def check_performance(self, window=100, threshold=0.85):
        """Check if recent accuracy is below threshold."""
        if len(self.predictions) < window:
            return False, f"Not enough data ({len(self.predictions)}/{window})"

        recent = self.predictions[-window:]
        accuracy = sum(1 for p in recent if p["correct"]) / len(recent)

        if accuracy < threshold:
            return True, f"Accuracy {accuracy:.2f} < {threshold:.2f} (last {window} predictions)"
        return False, f"Accuracy {accuracy:.2f} >= {threshold:.2f} (last {window} predictions)"

    def check_drift(self, window=100):
        """Check if prediction distribution has shifted."""
        if len(self.predictions) < window * 2:
            return False, "Not enough data for drift detection"

        # Compare recent predictions to older predictions
        older = self.predictions[-window*2:-window]
        recent = self.predictions[-window:]

        older_dist = defaultdict(int)
        recent_dist = defaultdict(int)

        for p in older:
            older_dist[p["predicted"]] += 1
        for p in recent:
            recent_dist[p["predicted"]] += 1

        # Simple drift check: category proportions changed significantly
        all_cats = set(list(older_dist.keys()) + list(recent_dist.keys()))
        max_shift = 0
        shifted_cat = None

        for cat in all_cats:
            older_pct = older_dist[cat] / len(older)
            recent_pct = recent_dist[cat] / len(recent)
            shift = abs(recent_pct - older_pct)
            if shift > max_shift:
                max_shift = shift
                shifted_cat = cat

        drift_threshold = 0.15  # 15% shift
        if max_shift > drift_threshold:
            return True, f"Category '{shifted_cat}' shifted by {max_shift:.0%} (threshold: {drift_threshold:.0%})"
        return False, f"Max shift: {max_shift:.0%} in '{shifted_cat}' (threshold: {drift_threshold:.0%})"

    def should_retrain(self):
        """Check all triggers and decide if retraining is needed."""
        schedule_trigger, schedule_detail = self.check_schedule(retrain_every_days=7)
        perf_trigger, perf_detail = self.check_performance(window=50, threshold=0.85)
        drift_trigger, drift_detail = self.check_drift(window=50)

        triggers = {
            "schedule": (schedule_trigger, schedule_detail),
            "performance": (perf_trigger, perf_detail),
            "drift": (drift_trigger, drift_detail),
        }

        should = any(t[0] for t in triggers.values())
        return should, triggers

# Demo: simulate predictions over time with degradation
trigger = RetrainingTrigger("alert_classifier")
trigger.last_retrain = datetime.now() - timedelta(days=10)  # last retrain 10 days ago

categories = ["performance", "storage", "replication", "security"]

# Simulate 200 predictions with gradually degrading accuracy
print("Simulating 200 predictions with model degradation:")
print("-" * 55)

for i in range(200):
    actual = random.choice(categories)

    # Model accuracy degrades over time
    if i < 50:
        correct_prob = 0.92  # good
    elif i < 100:
        correct_prob = 0.85  # degrading
    elif i < 150:
        correct_prob = 0.75  # bad
    else:
        correct_prob = 0.65  # terrible
        # Also shift the distribution (drift)
        if random.random() < 0.3:
            actual = "security"  # more security alerts than before

    if random.random() < correct_prob:
        predicted = actual  # correct
    else:
        predicted = random.choice([c for c in categories if c != actual])  # wrong

    trigger.log_prediction(predicted, actual)

# Check triggers
print(f"\nAfter 200 predictions:")
should, triggers = trigger.should_retrain()

print(f"\nRetrain Trigger Check:")
print("=" * 60)
for name, (fired, detail) in triggers.items():
    status = "TRIGGERED" if fired else "ok"
    print(f"  [{status:>10s}] {name:<15s} {detail}")

print(f"\nDecision: {'RETRAIN NOW' if should else 'No retraining needed'}")
PYEOF
```

---

## Step 3. Retraining pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
import random
from datetime import datetime

random.seed(42)

print("""
Automated Retraining Pipeline:
  1. Detect: trigger fires (schedule, drift, or performance)
  2. Collect: gather new training data
  3. Validate: check data quality
  4. Train: train new model
  5. Evaluate: test against current model
  6. Deploy: if better, deploy (shadow first)
  7. Monitor: watch new model in production

DBA analogy: like pg_cron + pg_repack running automatically:
  1. Detect: table bloat exceeds threshold
  2. Execute: REPACK TABLE
  3. Validate: table is smaller, queries are faster
  4. Monitor: check for issues after repack
""")

class RetrainingPipeline:
    """Automated model retraining pipeline."""

    def __init__(self, model_name):
        self.model_name = model_name
        self.log = []

    def _log(self, step, status, detail):
        entry = {
            "step": step,
            "status": status,
            "detail": detail,
            "timestamp": datetime.now().isoformat(),
        }
        self.log.append(entry)
        icon = "ok" if status == "success" else "!!"
        print(f"  [{icon}] {step}: {detail}")

    def collect_data(self):
        """Step 1: Collect new training data."""
        # In production: query database for new labeled alerts
        new_data = [
            {"message": f"Alert {i}: system issue", "category": random.choice(["perf", "storage", "rep", "sec"])}
            for i in range(500)
        ]
        self._log("collect", "success", f"Collected {len(new_data)} new labeled examples")
        return new_data

    def validate_data(self, data):
        """Step 2: Validate data quality."""
        issues = []

        # Check for empty messages
        empty = sum(1 for d in data if not d.get("message", "").strip())
        if empty > 0:
            issues.append(f"{empty} empty messages")

        # Check category distribution
        from collections import Counter
        cats = Counter(d["category"] for d in data)
        min_per_cat = len(data) * 0.05  # at least 5% per category
        underrep = [c for c, n in cats.items() if n < min_per_cat]
        if underrep:
            issues.append(f"Underrepresented categories: {underrep}")

        if issues:
            self._log("validate", "warning", f"Issues: {'; '.join(issues)}")
        else:
            self._log("validate", "success", f"Data quality OK ({len(data)} rows)")

        return len(issues) == 0, data

    def train_model(self, data):
        """Step 3: Train new model."""
        time.sleep(0.1)  # simulate training
        accuracy = 0.90 + random.uniform(0, 0.05)
        f1 = accuracy - 0.02 + random.uniform(-0.01, 0.01)

        model = {
            "version": f"v{random.randint(10,99)}",
            "accuracy": round(accuracy, 4),
            "f1_score": round(f1, 4),
            "trained_at": datetime.now().isoformat(),
            "train_size": len(data),
        }
        self._log("train", "success",
                  f"Model {model['version']}: accuracy={model['accuracy']}, f1={model['f1_score']}")
        return model

    def evaluate(self, new_model, current_model):
        """Step 4: Compare new model vs current."""
        acc_diff = new_model["accuracy"] - current_model["accuracy"]
        improved = acc_diff > -0.02  # allow up to 2% regression

        if improved:
            self._log("evaluate", "success",
                      f"New model is {'better' if acc_diff > 0 else 'comparable'}: "
                      f"{acc_diff:+.3f} accuracy")
        else:
            self._log("evaluate", "failed",
                      f"New model regressed: {acc_diff:+.3f} accuracy")

        return improved

    def deploy(self, model, mode="shadow"):
        """Step 5: Deploy the model."""
        self._log("deploy", "success",
                  f"Model {model['version']} deployed in {mode} mode")
        return True

    def run(self, current_model):
        """Run the full retraining pipeline."""
        print(f"\nRetraining Pipeline: {self.model_name}")
        print("=" * 55)

        # Collect
        data = self.collect_data()

        # Validate
        valid, data = self.validate_data(data)
        if not valid:
            print("\n  Pipeline paused: data quality issues detected")
            print("  Fix data issues and re-run")

        # Train
        new_model = self.train_model(data)

        # Evaluate
        improved = self.evaluate(new_model, current_model)

        if improved:
            # Deploy
            self.deploy(new_model, mode="shadow")
            print(f"\n  Pipeline complete: model {new_model['version']} deployed to shadow")
            print(f"  Next: monitor shadow mode for 24h, then promote to production")
        else:
            print(f"\n  Pipeline complete: new model did NOT improve")
            print(f"  Keeping current model in production")

        return new_model if improved else None

# Run the pipeline
pipeline = RetrainingPipeline("alert_classifier")

current = {"accuracy": 0.88, "f1_score": 0.86, "version": "v3"}
print(f"Current production model: {current['version']} (accuracy: {current['accuracy']})")

result = pipeline.run(current)

# Show pipeline log
print(f"\nPipeline Log:")
print(f"{'Step':>12s}  {'Status':>8s}  Detail")
print("-" * 60)
for entry in pipeline.log:
    print(f"{entry['step']:>12s}  {entry['status']:>8s}  {entry['detail'][:50]}")
PYEOF
```

---

## Step 4. Putting it all together

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Complete MLOps Lifecycle - How Everything Connects:

  Data Versioning (Build 02)
       |
       v
  Experiment Tracking (Build 01)
       |
       v
  CI/CD Testing (Build 03)
       |
       v
  Deployment (Module 13)
       |
       v
  Monitoring (Module 10)
       |
       v
  Retraining Trigger (this Build)
       |
       v
  (cycle repeats)

Production checklist:
  [ ] Training data is versioned (can reproduce any model)
  [ ] Experiments are tracked (know what works and why)
  [ ] Tests run automatically (CI/CD pipeline)
  [ ] Deployment is gated (must pass quality checks)
  [ ] Model is monitored (accuracy, latency, drift)
  [ ] Retraining is automated (triggered by drift or schedule)
  [ ] Rollback is instant (model registry with version switching)

Tools in the real world:
  Experiment tracking: MLflow, Weights & Biases
  Data versioning: DVC, LakeFS
  CI/CD: GitHub Actions, GitLab CI
  Serving: FastAPI, TensorFlow Serving, Triton
  Monitoring: Prometheus + Grafana, WhyLabs
  Orchestration: Airflow, Prefect, Dagster

For most DBA use cases, you can build all of this with:
  - Python scripts (training, testing, deployment)
  - GitHub Actions (CI/CD)
  - PostgreSQL (data storage, experiment tracking, monitoring)
  - cron / pg_cron (retraining schedule)
  - FastAPI (model serving)

Keep it simple. Add tools only when you outgrow the simple approach.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Scheduled retraining | Retrain on a timer | pg_cron VACUUM schedule |
| Performance trigger | Retrain when accuracy drops | Auto-ANALYZE on stale stats |
| Drift trigger | Retrain when data changes | Detecting schema/data drift |
| Retraining pipeline | Automated collect->train->evaluate->deploy | Automated backup->test->restore |
| Deployment gates | Block bad models from production | Pre-migration checks |
| MLOps lifecycle | Connect all stages into a continuous loop | Database operations lifecycle |
