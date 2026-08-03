# Build 02: Data Versioning

A model is only as good as its training data. If you can't tell what data a model was trained on, you can't reproduce it, debug it, or improve it. Data versioning tracks every dataset version so you always know exactly what went into every model.

---

## Step 1. Why version your data?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
The Problem Without Data Versioning:

  "Our model accuracy dropped from 94% to 82%. What changed?"
  "We retrained with newer data."
  "What was different about the newer data?"
  "... I'm not sure. We pulled fresh data from the database."
  "Can we retrain with the old data to verify?"
  "We didn't save it."

DBA analogy:
  This is like running UPDATE on a table without a WHERE clause
  and not having a backup. The old data is gone.

  In databases, you'd use:
  - pg_dump before schema changes
  - Logical replication for change data capture
  - PITR (point-in-time recovery) to go back in time

  Data versioning is PITR for your training data.

What to version:
  1. Raw data (the source of truth)
  2. Processed data (after cleaning, splitting)
  3. Train/test/val splits (exact rows in each split)
  4. Data transformations (what processing was applied)
  5. Metadata (when collected, how many rows, schema)
""")
PYEOF
```

---

## Step 2. Build a data version tracker

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import hashlib
import os
from datetime import datetime
from pathlib import Path

class DataVersionTracker:
    """Track versions of datasets used for training."""

    def __init__(self, base_dir="/tmp/data_versions"):
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self.registry_file = self.base_dir / "registry.json"
        self.registry = self._load()

    def _load(self):
        if self.registry_file.exists():
            with open(self.registry_file) as f:
                return json.load(f)
        return {"versions": []}

    def _save(self):
        with open(self.registry_file, "w") as f:
            json.dump(self.registry, f, indent=2)

    def _compute_hash(self, data):
        """Compute a hash of the data for integrity checking."""
        data_str = json.dumps(data, sort_keys=True)
        # sort_keys=True ensures consistent ordering
        return hashlib.sha256(data_str.encode()).hexdigest()[:12]
        # SHA256 hash, truncated to 12 chars for readability
        # Like a git commit hash - uniquely identifies the data

    def register_version(self, name, data, metadata=None):
        """Register a new dataset version."""
        data_hash = self._compute_hash(data)

        # Check if this exact data already exists
        for v in self.registry["versions"]:
            if v["hash"] == data_hash:
                print(f"  Data already registered as {v['version_id']}")
                return v["version_id"]

        version_id = f"{name}_v{len(self.registry['versions']) + 1}"

        # Save the data
        data_file = self.base_dir / f"{version_id}.json"
        with open(data_file, "w") as f:
            json.dump(data, f)

        # Register
        entry = {
            "version_id": version_id,
            "name": name,
            "hash": data_hash,
            "num_rows": len(data) if isinstance(data, list) else "N/A",
            "created_at": datetime.now().isoformat(),
            "data_file": str(data_file),
            "metadata": metadata or {},
        }

        self.registry["versions"].append(entry)
        self._save()
        return version_id

    def get_version(self, version_id):
        """Load a specific dataset version."""
        for v in self.registry["versions"]:
            if v["version_id"] == version_id:
                with open(v["data_file"]) as f:
                    return json.load(f), v
        raise ValueError(f"Version {version_id} not found")

    def list_versions(self, name=None):
        """List all registered versions."""
        versions = self.registry["versions"]
        if name:
            versions = [v for v in versions if v["name"] == name]
        return versions

    def diff(self, version_a, version_b):
        """Compare two dataset versions."""
        data_a, meta_a = self.get_version(version_a)
        data_b, meta_b = self.get_version(version_b)

        return {
            "version_a": version_a,
            "version_b": version_b,
            "rows_a": len(data_a),
            "rows_b": len(data_b),
            "rows_diff": len(data_b) - len(data_a),
            "same_data": meta_a["hash"] == meta_b["hash"],
        }

# Demo
tracker = DataVersionTracker()

print("Data Versioning Demo")
print("=" * 55)

# Version 1: initial dataset
dataset_v1 = [
    {"message": "CPU at 95%", "category": "performance"},
    {"message": "Disk full", "category": "storage"},
    {"message": "Replication lag 60s", "category": "replication"},
    {"message": "Failed login", "category": "security"},
    {"message": "Slow query 30s", "category": "performance"},
]

v1_id = tracker.register_version("alerts", dataset_v1, {
    "source": "manual_labels",
    "labeler": "happy",
    "description": "Initial labeled dataset",
})
print(f"  Registered: {v1_id} ({len(dataset_v1)} rows)")

# Version 2: added more data
dataset_v2 = dataset_v1 + [
    {"message": "WAL growing fast", "category": "storage"},
    {"message": "SSL cert expiring", "category": "security"},
    {"message": "Connection pool full", "category": "performance"},
    {"message": "Standby not streaming", "category": "replication"},
    {"message": "Checkpoint too frequent", "category": "performance"},
]

v2_id = tracker.register_version("alerts", dataset_v2, {
    "source": "manual_labels",
    "labeler": "happy",
    "description": "Expanded dataset with more examples",
})
print(f"  Registered: {v2_id} ({len(dataset_v2)} rows)")

# Version 3: fixed labels
dataset_v3 = dataset_v2.copy()
dataset_v3[3] = {"message": "Failed login", "category": "security"}
# Added a new alert type
dataset_v3.append({"message": "Backup failed", "category": "backup"})

v3_id = tracker.register_version("alerts", dataset_v3, {
    "source": "manual_labels + auto_labels",
    "labeler": "happy + model_v2",
    "description": "Added backup category, fixed labels",
})
print(f"  Registered: {v3_id} ({len(dataset_v3)} rows)")

# List versions
print(f"\nAll versions:")
print(f"{'ID':>15s}  {'Rows':>5s}  {'Hash':>14s}  Description")
print("-" * 65)
for v in tracker.list_versions("alerts"):
    desc = v["metadata"].get("description", "")[:30]
    print(f"{v['version_id']:>15s}  {v['num_rows']:>5}  {v['hash']:>14s}  {desc}")

# Compare versions
print(f"\nDiff between v1 and v3:")
diff = tracker.diff(v1_id, v3_id)
for k, v in diff.items():
    print(f"  {k}: {v}")
PYEOF
```

---

## Step 3. Track train/test splits

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import random
import hashlib
from datetime import datetime

random.seed(42)

print("""
Train/Test Split Versioning:
  The SAME dataset can produce DIFFERENT splits.
  If you don't save the exact split, you can't reproduce results.

DBA analogy:
  Like saving the exact WHERE clause used to create a subset.
  SELECT * FROM alerts WHERE id IN (1,3,5,7) -- train
  SELECT * FROM alerts WHERE id IN (2,4,6,8) -- test
  Save these IDs, not just "80/20 split."
""")

def create_versioned_split(data, train_ratio=0.8, seed=42):
    """Create a reproducible train/test split with full tracking."""

    # Set random seed for reproducibility
    random.seed(seed)
    # With the same seed + same data, you get the same split every time

    # Shuffle indices (not the data itself)
    indices = list(range(len(data)))
    random.shuffle(indices)

    # Split
    split_point = int(len(data) * train_ratio)
    train_indices = sorted(indices[:split_point])
    test_indices = sorted(indices[split_point:])
    # sorted() so the indices are in order (easier to read)

    train_data = [data[i] for i in train_indices]
    test_data = [data[i] for i in test_indices]

    # Create version metadata
    split_info = {
        "created_at": datetime.now().isoformat(),
        "total_rows": len(data),
        "train_rows": len(train_data),
        "test_rows": len(test_data),
        "train_ratio": train_ratio,
        "random_seed": seed,
        "train_indices": train_indices,
        "test_indices": test_indices,
        "data_hash": hashlib.sha256(
            json.dumps(data, sort_keys=True).encode()
        ).hexdigest()[:12],
    }

    return train_data, test_data, split_info

# Create a dataset
alerts = [
    {"id": i, "message": f"Alert {i}: database issue type {i % 5}",
     "category": ["performance", "storage", "replication", "security", "backup"][i % 5]}
    for i in range(20)
]

# Create versioned split
train, test, split_info = create_versioned_split(alerts, train_ratio=0.8, seed=42)

print("Versioned Train/Test Split:")
print("=" * 50)
print(f"  Total: {split_info['total_rows']}")
print(f"  Train: {split_info['train_rows']} ({split_info['train_ratio']:.0%})")
print(f"  Test:  {split_info['test_rows']} ({1-split_info['train_ratio']:.0%})")
print(f"  Seed:  {split_info['random_seed']}")
print(f"  Data hash: {split_info['data_hash']}")

# Category distribution in each split
from collections import Counter
train_cats = Counter(d["category"] for d in train)
test_cats = Counter(d["category"] for d in test)

print(f"\nCategory distribution:")
print(f"  {'Category':>15s}  {'Train':>6s}  {'Test':>5s}")
print(f"  {'-'*30}")
all_cats = sorted(set(list(train_cats.keys()) + list(test_cats.keys())))
for cat in all_cats:
    print(f"  {cat:>15s}  {train_cats.get(cat, 0):>6d}  {test_cats.get(cat, 0):>5d}")

# Verify reproducibility
train2, test2, split2 = create_versioned_split(alerts, train_ratio=0.8, seed=42)
assert [d["id"] for d in train] == [d["id"] for d in train2]
assert [d["id"] for d in test] == [d["id"] for d in test2]
print(f"\nReproducibility check: PASSED (same seed = same split)")

# Save split info
split_file = "/tmp/split_v1.json"
with open(split_file, "w") as f:
    json.dump(split_info, f, indent=2)
print(f"Split info saved to: {split_file}")

print("""
To reproduce this exact split later:
  1. Load the same dataset (verified by data_hash)
  2. Use the same seed (42)
  3. Use the same ratio (0.8)
  4. Or just use the saved train_indices/test_indices directly
""")
PYEOF
```

---

## Step 4. Data lineage

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

print("""
Data Lineage: Track where data came from and how it was transformed.

For every model, you should be able to answer:
  1. Where did the training data come from? (source)
  2. How was it processed? (transformations)
  3. What version of the processing code was used? (code version)
  4. What does the final dataset look like? (statistics)

DBA analogy:
  Like tracking the ETL pipeline that loads your data warehouse.
  "This table was loaded from these 3 source tables,
   with these joins, these filters, on this date,
   using this version of the ETL script."
""")

class DataLineage:
    """Track data transformations from source to model."""

    def __init__(self):
        self.steps = []

    def add_step(self, name, description, input_info, output_info, code_ref=None):
        """Record a transformation step."""
        self.steps.append({
            "step": len(self.steps) + 1,
            "name": name,
            "description": description,
            "input": input_info,
            "output": output_info,
            "code_ref": code_ref,
            "timestamp": datetime.now().isoformat(),
        })

    def show(self):
        """Display the lineage chain."""
        print("Data Lineage:")
        print("=" * 60)
        for step in self.steps:
            print(f"\n  Step {step['step']}: {step['name']}")
            print(f"  Description: {step['description']}")
            print(f"  Input:  {step['input']}")
            print(f"  Output: {step['output']}")
            if step.get("code_ref"):
                print(f"  Code:   {step['code_ref']}")
            if step["step"] < len(self.steps):
                print(f"     |")
                print(f"     v")

# Build lineage for alert classifier training data
lineage = DataLineage()

lineage.add_step(
    "extract",
    "Pull raw alerts from PostgreSQL monitoring tables",
    {"source": "postgres://monitoring/alerts", "query": "SELECT * FROM alerts WHERE created_at > '2024-01-01'"},
    {"rows": 15000, "columns": ["id", "message", "severity", "source", "created_at"]},
    code_ref="scripts/extract_alerts.py@v2.3"
)

lineage.add_step(
    "clean",
    "Remove duplicates, empty messages, normalize severity",
    {"rows": 15000, "from_step": "extract"},
    {"rows": 12847, "removed": 2153, "reason": "1200 duplicates, 953 empty messages"},
    code_ref="scripts/clean_alerts.py@v1.1"
)

lineage.add_step(
    "label",
    "Auto-label with keyword rules, manually verify 500 samples",
    {"rows": 12847, "from_step": "clean"},
    {"rows": 12847, "categories": {"performance": 4100, "storage": 3200, "replication": 2800, "security": 1747, "backup": 1000}},
    code_ref="scripts/label_alerts.py@v3.0"
)

lineage.add_step(
    "split",
    "80/10/10 train/val/test split with stratification",
    {"rows": 12847, "from_step": "label"},
    {"train": 10278, "val": 1284, "test": 1285, "seed": 42},
    code_ref="scripts/split_data.py@v1.0"
)

lineage.add_step(
    "tokenize",
    "Tokenize with DistilBERT tokenizer, max_length=128",
    {"rows": 10278, "from_step": "split (train)"},
    {"rows": 10278, "avg_tokens": 23, "max_tokens": 128, "truncated": 12},
    code_ref="scripts/tokenize.py@v2.0"
)

lineage.show()

# Save lineage
lineage_file = "/tmp/data_lineage.json"
with open(lineage_file, "w") as f:
    json.dump({"steps": lineage.steps}, f, indent=2)

print(f"\nLineage saved to: {lineage_file}")
print(f"\nWith this lineage, you can:")
print(f"  1. Reproduce the exact dataset from source")
print(f"  2. Debug: 'why did accuracy drop?' -> check each step")
print(f"  3. Audit: 'what data was the model trained on?'")
print(f"  4. Improve: 'where are we losing data?' -> step 2 removed 14%")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Data versioning | Track each dataset snapshot | pg_dump with timestamps |
| Content hashing | Detect if data changed | Checksum for backup integrity |
| Split versioning | Save exact train/test split | Save the WHERE clause |
| Reproducibility | Same seed + data = same split | Deterministic query results |
| Data lineage | Track source -> transformations -> output | ETL pipeline documentation |
| Diff | Compare two dataset versions | pg_diff between schemas |
