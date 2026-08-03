# Survive 01: Training Data Corruption

Someone accidentally included production test data in the training set. The model was retrained, deployed, and shows 99% accuracy. But it's memorizing test cases, not learning patterns. Real-world accuracy is 60%.

---

## The Disaster

On your **Mac terminal**, run the injection script:

```bash
python3 << 'PYEOF'
import json
import random
from collections import Counter

random.seed(42)

print("""
SCENARIO: Training Data Corruption

Your automated retraining pipeline ran last night.
The new model shows 99.2% accuracy on the test set.
The team celebrated. It was deployed to production.

But production users report: "The classifier is wrong half the time."

What happened:
  - A data engineer ran a script to export labeled data
  - The script accidentally included the TEST SET in the TRAINING SET
  - The model memorized the test answers instead of learning patterns
  - Test accuracy: 99.2% (it literally memorized the answers)
  - Real-world accuracy: ~60% (no actual learning happened)

This is called "data leakage" or "test set contamination."
""")

# Show the corrupted data pipeline
print("Data Pipeline (CORRUPTED):")
print("=" * 55)

# Original correct split
all_data = [{"id": i, "message": f"Alert {i}", "category": random.choice(["perf", "storage", "rep", "sec"])}
            for i in range(1000)]

train_correct = all_data[:800]  # 80%
test_correct = all_data[800:]   # 20%

print(f"  Original split:")
print(f"    Train: {len(train_correct)} rows (ids 0-799)")
print(f"    Test:  {len(test_correct)} rows (ids 800-999)")

# The corrupted version: test data leaked into training
train_corrupted = all_data[:800] + all_data[800:]  # train = ALL data
test_corrupted = all_data[800:]                      # test = subset of train

print(f"\n  Corrupted split:")
print(f"    Train: {len(train_corrupted)} rows (ids 0-999, includes test!)")
print(f"    Test:  {len(test_corrupted)} rows (ids 800-999, all in train)")

# Check overlap
train_ids = set(d["id"] for d in train_corrupted)
test_ids = set(d["id"] for d in test_corrupted)
overlap = train_ids & test_ids
# & is set intersection - items in BOTH sets

print(f"\n  Overlap: {len(overlap)} test items found in training set ({len(overlap)/len(test_ids)*100:.0f}%)")
print(f"  This means the model can just MEMORIZE the test answers")

print(f"""
Symptoms:
  1. Unusually high test accuracy (99%+ is suspicious)
  2. Big gap between test accuracy and real-world accuracy
  3. Model fails on NEW data it hasn't seen
  4. Model is confident but wrong on production data

DBA analogy:
  Like testing your backup by restoring the SAME database to itself.
  "Backup verified!" - but you never actually tested recovery.
  The test was meaningless because it wasn't independent.
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, check for contamination:

```bash
python3 << 'PYEOF'
import json
import random
import hashlib

random.seed(42)

print("Investigation: Detecting Data Leakage")
print("=" * 55)

# Simulate the data
all_data = [{"id": i, "message": f"Alert {i}: issue type {i % 5}"}
            for i in range(1000)]

train = all_data[:800] + all_data[800:]  # corrupted
test = all_data[800:]

# Detection method 1: Check for ID overlap
print("\nMethod 1: ID Overlap Check")
train_ids = set(d["id"] for d in train)
test_ids = set(d["id"] for d in test)
overlap = train_ids & test_ids
print(f"  Train IDs: {len(train_ids)}")
print(f"  Test IDs: {len(test_ids)}")
print(f"  Overlap: {len(overlap)}")
if overlap:
    print(f"  CONTAMINATION DETECTED: {len(overlap)} test items in training set")

# Detection method 2: Content hash overlap
print("\nMethod 2: Content Hash Check")
def hash_row(row):
    return hashlib.md5(json.dumps(row, sort_keys=True).encode()).hexdigest()

train_hashes = set(hash_row(d) for d in train)
test_hashes = set(hash_row(d) for d in test)
hash_overlap = train_hashes & test_hashes
print(f"  Unique train hashes: {len(train_hashes)}")
print(f"  Unique test hashes: {len(test_hashes)}")
print(f"  Hash overlap: {len(hash_overlap)}")
if hash_overlap:
    print(f"  CONTAMINATION DETECTED: {len(hash_overlap)} identical rows")

# Detection method 3: Suspiciously high accuracy
print("\nMethod 3: Accuracy Anomaly Check")
test_acc = 0.992
historical_accs = [0.88, 0.89, 0.91, 0.90, 0.92]
avg_historical = sum(historical_accs) / len(historical_accs)
improvement = test_acc - avg_historical

print(f"  Current accuracy: {test_acc:.3f}")
print(f"  Historical average: {avg_historical:.3f}")
print(f"  Improvement: {improvement:+.3f}")

if improvement > 0.05:
    print(f"  SUSPICIOUS: {improvement:.1%} improvement is unusually large")
    print(f"  Normal improvements are 1-3%, not {improvement:.1%}")

print("""
ROOT CAUSE: The data export script used:
  SELECT * FROM alerts  -- ALL rows
  instead of:
  SELECT * FROM alerts WHERE split = 'train'  -- only train rows

The test set was included in training data.
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import json
import hashlib
import random
from datetime import datetime

random.seed(42)

print("""
FIX: Three-layer defense against data contamination.

Layer 1: Automated overlap detection (run before every training)
Layer 2: Hold-out validation set (never used in any pipeline)
Layer 3: Real-world accuracy monitoring (catch it in production)
""")

# Layer 1: Automated contamination check
def check_contamination(train_data, test_data, id_field="id"):
    """Check for data leakage between train and test sets."""
    issues = []

    # Check 1: ID overlap
    train_ids = set(d[id_field] for d in train_data)
    test_ids = set(d[id_field] for d in test_data)
    id_overlap = train_ids & test_ids
    if id_overlap:
        issues.append(f"ID overlap: {len(id_overlap)} test IDs found in training")

    # Check 2: Content overlap (hash-based)
    def hash_content(d):
        content = {k: v for k, v in d.items() if k != id_field}
        return hashlib.md5(json.dumps(content, sort_keys=True).encode()).hexdigest()

    train_hashes = set(hash_content(d) for d in train_data)
    test_hashes = set(hash_content(d) for d in test_data)
    content_overlap = train_hashes & test_hashes
    if content_overlap:
        issues.append(f"Content overlap: {len(content_overlap)} identical rows")

    # Check 3: Size sanity
    total = len(train_data) + len(test_data)
    unique_ids = len(train_ids | test_ids)
    if unique_ids < total:
        issues.append(f"Duplicate IDs: {total} rows but only {unique_ids} unique IDs")

    return len(issues) == 0, issues

# Test with CLEAN data
all_data = [{"id": i, "message": f"Alert {i}", "category": "perf"} for i in range(1000)]
clean_train = all_data[:800]
clean_test = all_data[800:]

print("Layer 1: Automated Contamination Check")
print("=" * 55)

clean, issues = check_contamination(clean_train, clean_test)
print(f"\n  Clean split: {'PASSED' if clean else 'FAILED'}")
for issue in issues:
    print(f"    {issue}")

# Test with CONTAMINATED data
dirty_train = all_data[:800] + all_data[800:]  # includes test data
dirty_test = all_data[800:]

clean, issues = check_contamination(dirty_train, dirty_test)
print(f"\n  Contaminated split: {'PASSED' if clean else 'FAILED'}")
for issue in issues:
    print(f"    {issue}")

# Layer 2: Hold-out set
print(f"\nLayer 2: Hold-Out Validation Set")
print("=" * 55)
print("""
  Keep a SEPARATE hold-out set that is NEVER used in any pipeline.

  Split strategy:
    Train: 70% (used for training)
    Val:   15% (used for hyperparameter tuning)
    Test:  10% (used for final evaluation)
    Hold:   5% (NEVER touched until you suspect contamination)

  If test accuracy >> hold-out accuracy, contamination is likely.
""")

# Simulate
test_acc = 0.992
holdout_acc = 0.88
gap = test_acc - holdout_acc
print(f"  Test accuracy:    {test_acc:.3f}")
print(f"  Hold-out accuracy: {holdout_acc:.3f}")
print(f"  Gap:              {gap:.3f}")
if gap > 0.05:
    print(f"  ALERT: {gap:.1%} gap suggests data contamination")

# Layer 3: Production monitoring
print(f"\nLayer 3: Production Accuracy Monitoring")
print("=" * 55)
print("""
  Track accuracy on REAL predictions (not test set):
    1. Log every prediction
    2. Periodically get ground truth (human labels)
    3. Compare prediction vs ground truth
    4. If production accuracy << test accuracy, investigate

  This catches contamination even if Layers 1 and 2 miss it.
""")

print("""
Prevention checklist:
  1. AUTOMATE contamination checks (run before every training job)
  2. SPLIT data ONCE and save the split (don't re-split)
  3. KEEP a hold-out set that no pipeline touches
  4. MONITOR real-world accuracy (catches all forms of leakage)
  5. VERSION your data (can recreate any split)
  6. LOG the exact query used to export training data
  7. BE SUSPICIOUS of >95% accuracy (could be legit, but verify)

  DBA parallel:
    - Test backups by restoring to a DIFFERENT server
    - Test failover by actually failing over (not just checking connection)
    - Monitor replication lag, don't just check "is streaming?"
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Test set in training | Model memorizes answers, can't generalize | Automated overlap detection |
| No hold-out set | No independent verification | Keep 5% hold-out never used in pipelines |
| Trusting test accuracy | 99% accuracy can be fake | Compare test vs hold-out vs production |
| Manual data splits | Error-prone, not reproducible | Automate splits with versioning |
| No production monitoring | Can't catch contamination after deploy | Track real-world accuracy |
