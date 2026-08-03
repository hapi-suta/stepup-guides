# Build 01: Experiment Tracking

When you train a model, you make dozens of choices: learning rate, batch size, number of epochs, which data to use. Experiment tracking records every choice and its result so you can reproduce winners and learn from failures.

---

## Step 1. Why track experiments?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
The Problem Without Experiment Tracking:

  "Which model is in production?"
  "The one I trained... sometime last month? With the bigger dataset?"
  "What learning rate did I use?"
  "I think 0.001... or was it 0.01?"
  "Can you retrain it?"
  "Maybe? I don't remember all the settings."

This conversation has happened at every ML team ever.

DBA analogy:
  Imagine running ALTER TABLE without recording what you changed.
  - "What indexes exist on this table?"
  - "I added some last month... I think?"
  - "Can you reproduce the schema?"
  - "Maybe from pg_dump... if I made one?"

  You'd never operate a database this way.
  Don't operate ML models this way either.

What to track for every experiment:
  1. Parameters: learning_rate, epochs, batch_size, model_type
  2. Metrics: accuracy, f1_score, loss, training_time
  3. Data: dataset_version, train_size, test_size
  4. Code: git_commit, branch
  5. Artifacts: model file, training logs, plots
""")
PYEOF
```

---

## Step 2. Build an experiment tracker

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import os
import time
from datetime import datetime
from pathlib import Path

class ExperimentTracker:
    """Track ML experiments - parameters, metrics, artifacts."""

    def __init__(self, project_name, base_dir="/tmp/mlops_experiments"):
        self.project_name = project_name
        self.base_dir = Path(base_dir) / project_name
        self.base_dir.mkdir(parents=True, exist_ok=True)
        # Create project directory

        self.experiments = self._load_experiments()
        self.current = None

    def _load_experiments(self):
        """Load all experiments from disk."""
        index_file = self.base_dir / "index.json"
        if index_file.exists():
            with open(index_file) as f:
                return json.load(f)
        return []

    def _save_experiments(self):
        """Save experiment index to disk."""
        with open(self.base_dir / "index.json", "w") as f:
            json.dump(self.experiments, f, indent=2)

    def start_experiment(self, name, params):
        """Start a new experiment run."""
        exp_id = f"exp_{len(self.experiments) + 1:03d}"
        # f-string: exp_001, exp_002, etc.
        # :03d means pad with zeros to 3 digits

        self.current = {
            "id": exp_id,
            "name": name,
            "params": params,
            "metrics": {},
            "started_at": datetime.now().isoformat(),
            "finished_at": None,
            "status": "running",
        }
        return exp_id

    def log_metric(self, name, value):
        """Log a metric value."""
        if self.current is None:
            raise ValueError("No experiment running. Call start_experiment() first.")
        self.current["metrics"][name] = value

    def log_metrics(self, metrics_dict):
        """Log multiple metrics at once."""
        for name, value in metrics_dict.items():
            self.log_metric(name, value)

    def end_experiment(self, status="completed"):
        """End the current experiment and save it."""
        if self.current is None:
            return
        self.current["finished_at"] = datetime.now().isoformat()
        self.current["status"] = status

        # Calculate duration
        start = datetime.fromisoformat(self.current["started_at"])
        end = datetime.fromisoformat(self.current["finished_at"])
        self.current["duration_seconds"] = (end - start).total_seconds()

        self.experiments.append(self.current)
        self._save_experiments()

        exp_id = self.current["id"]
        self.current = None
        return exp_id

    def compare(self, metric="accuracy"):
        """Compare all experiments by a metric."""
        results = []
        for exp in self.experiments:
            if metric in exp.get("metrics", {}):
                results.append({
                    "id": exp["id"],
                    "name": exp["name"],
                    metric: exp["metrics"][metric],
                    "params": exp["params"],
                })
        # Sort by metric (descending = best first)
        # lambda x: x[metric] is a tiny function: given x (a dict), return x[metric]
        # This tells sort() to compare experiments by their metric value.
        # DBA analogy: ORDER BY metric_value DESC
        results.sort(key=lambda x: x[metric], reverse=True)
        return results

    def get_best(self, metric="accuracy"):
        """Get the experiment with the best metric value."""
        results = self.compare(metric)
        return results[0] if results else None

# Demo: track multiple experiments
tracker = ExperimentTracker("alert_classifier")

print("Experiment Tracking Demo")
print("=" * 70)

# Experiment 1: Keyword baseline
tracker.start_experiment("keyword_baseline", {
    "model_type": "keyword_rules",
    "num_keywords": 25,
    "categories": 5,
})
# Simulate training
time.sleep(0.01)
tracker.log_metrics({
    "accuracy": 0.78,
    "f1_score": 0.72,
    "precision": 0.80,
    "recall": 0.65,
    "training_time_seconds": 0.5,
})
tracker.end_experiment()

# Experiment 2: DistilBERT with low learning rate
tracker.start_experiment("distilbert_low_lr", {
    "model_type": "distilbert",
    "learning_rate": 1e-5,
    "epochs": 3,
    "batch_size": 16,
    "frozen_layers": "all_except_classifier",
})
time.sleep(0.01)
tracker.log_metrics({
    "accuracy": 0.89,
    "f1_score": 0.87,
    "precision": 0.90,
    "recall": 0.84,
    "training_time_seconds": 120,
})
tracker.end_experiment()

# Experiment 3: DistilBERT with higher learning rate
tracker.start_experiment("distilbert_high_lr", {
    "model_type": "distilbert",
    "learning_rate": 5e-5,
    "epochs": 5,
    "batch_size": 32,
    "frozen_layers": "first_4",
})
time.sleep(0.01)
tracker.log_metrics({
    "accuracy": 0.91,
    "f1_score": 0.89,
    "precision": 0.92,
    "recall": 0.87,
    "training_time_seconds": 180,
})
tracker.end_experiment()

# Experiment 4: LoRA fine-tuning
tracker.start_experiment("distilbert_lora", {
    "model_type": "distilbert+lora",
    "learning_rate": 2e-4,
    "epochs": 5,
    "batch_size": 32,
    "lora_rank": 8,
    "lora_alpha": 16,
})
time.sleep(0.01)
tracker.log_metrics({
    "accuracy": 0.94,
    "f1_score": 0.93,
    "precision": 0.95,
    "recall": 0.91,
    "training_time_seconds": 90,
})
tracker.end_experiment()

# Compare experiments
print("\nExperiment Comparison (sorted by accuracy):")
print(f"{'ID':>8s}  {'Name':>22s}  {'Acc':>5s}  {'F1':>5s}  {'Model':>20s}  {'LR':>8s}")
print("-" * 80)

for exp in tracker.compare("accuracy"):
    lr = exp["params"].get("learning_rate", "N/A")
    lr_str = f"{lr:.0e}" if isinstance(lr, float) else str(lr)
    print(f"{exp['id']:>8s}  {exp['name']:>22s}  {exp['accuracy']:>5.2f}  "
          f"{exp.get('f1_score', 0):>5.2f}  {exp['params']['model_type']:>20s}  {lr_str:>8s}")

best = tracker.get_best("accuracy")
print(f"\nBest experiment: {best['id']} ({best['name']}) - accuracy: {best['accuracy']}")
print(f"Parameters: {json.dumps(best['params'], indent=2)}")
PYEOF
```

---

## Step 3. MLflow-style tracking

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
import random
from datetime import datetime
from pathlib import Path

random.seed(42)

print("""
MLflow is the most popular experiment tracking tool.
This demo shows the MLflow pattern - even without installing it.

MLflow concepts:
  - Experiment: a project (e.g., "alert_classifier")
  - Run: one training attempt within an experiment
  - Parameters: inputs (learning_rate, epochs)
  - Metrics: outputs (accuracy, loss) - can be logged over time
  - Artifacts: files (model.pt, plots, configs)
  - Tags: metadata (author, description, git commit)

DBA analogy:
  - Experiment = database (alert_classifier_db)
  - Run = transaction (one complete operation)
  - Parameters = configuration (postgresql.conf settings)
  - Metrics = performance counters (pg_stat_statements)
  - Artifacts = backups and exports
  - Tags = comments and labels on objects
""")

class MLflowStyleTracker:
    """Simplified MLflow-style tracking."""

    def __init__(self, experiment_name, tracking_dir="/tmp/mlflow_demo"):
        self.experiment = experiment_name
        self.tracking_dir = Path(tracking_dir) / experiment_name
        self.tracking_dir.mkdir(parents=True, exist_ok=True)
        self.run = None

    def start_run(self, run_name=None, tags=None):
        """Start a new run."""
        run_id = f"run_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        # strftime formats datetime: 20240115_103000

        self.run = {
            "run_id": run_id,
            "run_name": run_name or run_id,
            "experiment": self.experiment,
            "tags": tags or {},
            "params": {},
            "metrics": {},
            "metric_history": {},
            # metric_history stores values over time (e.g., loss per epoch)
            "artifacts": [],
            "start_time": datetime.now().isoformat(),
        }
        print(f"  Started run: {self.run['run_name']}")
        return self

    def log_param(self, key, value):
        """Log a parameter (set once)."""
        self.run["params"][key] = value

    def log_params(self, params):
        """Log multiple parameters."""
        self.run["params"].update(params)

    def log_metric(self, key, value, step=None):
        """Log a metric (can be logged multiple times with step)."""
        self.run["metrics"][key] = value
        # Also track history
        if key not in self.run["metric_history"]:
            self.run["metric_history"][key] = []
        self.run["metric_history"][key].append({
            "value": value,
            "step": step,
            "timestamp": datetime.now().isoformat(),
        })

    def log_artifact(self, filepath):
        """Log a file artifact."""
        self.run["artifacts"].append(filepath)

    def end_run(self):
        """End the run and save."""
        self.run["end_time"] = datetime.now().isoformat()
        self.run["status"] = "FINISHED"

        # Save run to disk
        run_file = self.tracking_dir / f"{self.run['run_id']}.json"
        with open(run_file, "w") as f:
            json.dump(self.run, f, indent=2)

        print(f"  Ended run: {self.run['run_name']}")
        result = self.run
        self.run = None
        return result

# Simulate a training session with epoch-level logging
tracker = MLflowStyleTracker("alert_classifier_v2")

print("MLflow-Style Experiment Tracking:")
print("=" * 60)

# Run 1: Train a model
tracker.start_run(
    run_name="distilbert_lr2e5_ep10",
    tags={"author": "happy", "git_commit": "abc123", "description": "LoRA fine-tune"}
)

tracker.log_params({
    "model": "distilbert-base-uncased",
    "learning_rate": 2e-5,
    "epochs": 10,
    "batch_size": 32,
    "lora_rank": 8,
    "optimizer": "AdamW",
    "dataset_version": "v3",
    "train_size": 4000,
    "test_size": 1000,
})

# Simulate training loop - log metrics per epoch
print("\n  Training progress:")
for epoch in range(1, 11):
    # Simulate improving metrics
    train_loss = 1.5 * (0.7 ** epoch) + random.uniform(-0.05, 0.05)
    val_loss = 1.6 * (0.72 ** epoch) + random.uniform(-0.05, 0.05)
    accuracy = min(0.98, 0.5 + 0.05 * epoch + random.uniform(-0.02, 0.02))
    f1 = min(0.97, accuracy - 0.02 + random.uniform(-0.01, 0.01))

    tracker.log_metric("train_loss", round(train_loss, 4), step=epoch)
    tracker.log_metric("val_loss", round(val_loss, 4), step=epoch)
    tracker.log_metric("accuracy", round(accuracy, 4), step=epoch)
    tracker.log_metric("f1_score", round(f1, 4), step=epoch)

    if epoch % 3 == 0 or epoch == 10:
        print(f"    Epoch {epoch:>2d}: loss={train_loss:.4f}  val_loss={val_loss:.4f}  "
              f"acc={accuracy:.4f}  f1={f1:.4f}")

tracker.log_artifact("/tmp/models/alert_classifier_v2.pt")
run_result = tracker.end_run()

# Show final metrics
print(f"\nFinal Metrics:")
print(f"  Accuracy: {run_result['metrics']['accuracy']}")
print(f"  F1 Score: {run_result['metrics']['f1_score']}")
print(f"  Train Loss: {run_result['metrics']['train_loss']}")

# Show metric history (loss curve)
print(f"\nLoss Curve (train_loss per epoch):")
for entry in run_result["metric_history"]["train_loss"]:
    step = entry["step"]
    value = entry["value"]
    bar = "#" * int(value * 20)
    print(f"  Epoch {step:>2d}: {value:.4f} {bar}")

print(f"\nRun saved to: {tracker.tracking_dir}")
print(f"This run can be loaded and compared against future experiments")
PYEOF
```

---

## Step 4. Comparing experiments with a leaderboard

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from pathlib import Path

print("""
Experiment Leaderboard: Compare all runs at a glance.

Like pg_stat_statements showing your top queries,
a leaderboard shows your top models.
""")

# Create multiple experiment runs
experiments = [
    {
        "name": "keyword_baseline",
        "params": {"model": "rules", "keywords": 25},
        "metrics": {"accuracy": 0.78, "f1": 0.72, "latency_ms": 0.1, "size_mb": 0.01},
    },
    {
        "name": "tfidf_svm",
        "params": {"model": "svm", "features": "tfidf", "C": 1.0},
        "metrics": {"accuracy": 0.84, "f1": 0.81, "latency_ms": 2, "size_mb": 5},
    },
    {
        "name": "distilbert_frozen",
        "params": {"model": "distilbert", "frozen": True, "lr": 2e-5},
        "metrics": {"accuracy": 0.89, "f1": 0.87, "latency_ms": 45, "size_mb": 250},
    },
    {
        "name": "distilbert_unfrozen",
        "params": {"model": "distilbert", "frozen": False, "lr": 1e-5},
        "metrics": {"accuracy": 0.91, "f1": 0.89, "latency_ms": 45, "size_mb": 250},
    },
    {
        "name": "distilbert_lora_r4",
        "params": {"model": "distilbert+lora", "rank": 4, "lr": 2e-4},
        "metrics": {"accuracy": 0.92, "f1": 0.91, "latency_ms": 46, "size_mb": 252},
    },
    {
        "name": "distilbert_lora_r8",
        "params": {"model": "distilbert+lora", "rank": 8, "lr": 2e-4},
        "metrics": {"accuracy": 0.94, "f1": 0.93, "latency_ms": 47, "size_mb": 253},
    },
    {
        "name": "bert_full_finetune",
        "params": {"model": "bert-base", "frozen": False, "lr": 5e-6},
        "metrics": {"accuracy": 0.93, "f1": 0.92, "latency_ms": 85, "size_mb": 420},
    },
]

# Sort by accuracy (descending)
experiments.sort(key=lambda x: x["metrics"]["accuracy"], reverse=True)

print("Experiment Leaderboard (sorted by accuracy):")
print("=" * 85)
print(f"{'#':>3s}  {'Name':>25s}  {'Acc':>5s}  {'F1':>5s}  {'Latency':>8s}  {'Size':>8s}  {'Model':>18s}")
print("-" * 85)

for i, exp in enumerate(experiments):
    m = exp["metrics"]
    medal = " *" if i == 0 else ""
    print(f"{i+1:>3d}  {exp['name']:>25s}  {m['accuracy']:>5.2f}  {m['f1']:>5.2f}  "
          f"{m['latency_ms']:>6.1f}ms  {m['size_mb']:>6.1f}MB  {exp['params']['model']:>18s}{medal}")

print(f"\n* = best model")

# Show tradeoffs
print(f"\nTradeoff Analysis:")
best_acc = experiments[0]
fastest = min(experiments, key=lambda x: x["metrics"]["latency_ms"])
smallest = min(experiments, key=lambda x: x["metrics"]["size_mb"])

print(f"  Best accuracy:  {best_acc['name']} ({best_acc['metrics']['accuracy']:.2f})")
print(f"  Fastest:        {fastest['name']} ({fastest['metrics']['latency_ms']}ms)")
print(f"  Smallest:       {smallest['name']} ({smallest['metrics']['size_mb']}MB)")

print("""
Choosing a model isn't just about accuracy:
  - Real-time alerts need low latency -> keyword rules or TF-IDF
  - Batch processing can tolerate higher latency -> BERT
  - Edge deployment needs small size -> DistilBERT + LoRA
  - Maximum accuracy with no constraints -> full BERT fine-tune

Track ALL metrics so you can make informed tradeoffs.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Experiment tracking | Record params + metrics for every run | pg_stat_statements tracking query performance |
| Parameters | Inputs to training (lr, epochs) | postgresql.conf settings |
| Metrics | Outputs from training (accuracy, loss) | Query performance metrics (rows, time) |
| Metric history | Track metrics over time (per epoch) | Time-series monitoring |
| Artifacts | Save model files and logs | pg_dump files |
| Leaderboard | Compare all experiments | Top queries by total_time |
