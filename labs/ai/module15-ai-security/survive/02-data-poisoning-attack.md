# Survive 02: Data Poisoning Attack

Your automated retraining pipeline pulled new labeled data from a shared spreadsheet. An attacker added 200 carefully crafted entries that label "disk full" alerts as "low priority." After retraining, the model ignores disk alerts. Two databases run out of space before anyone notices.

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
SCENARIO: Data Poisoning Attack

Your training pipeline:
  1. Pull labeled alerts from a shared Google Sheet
  2. Combine with existing training data
  3. Retrain model weekly (automated)
  4. Deploy if accuracy > 85%

An attacker (disgruntled contractor) added 200 entries:
  - All are disk/storage alerts
  - All labeled as "low" priority or "performance" category
  - The entries look legitimate (realistic alert messages)

After retraining:
  - Test accuracy: 87% (passes the 85% threshold)
  - But the model now classifies disk alerts as "performance" or "low"
  - Real disk alerts go to the wrong team or get deprioritized

Timeline:
  Monday:    Poisoned data added to spreadsheet
  Wednesday: Automated retraining runs, new model deploys
  Thursday:  Disk at 95% alert classified as "low priority performance"
  Friday:    Two databases hit 100% disk, queries fail
  Saturday:  On-call engineer discovers the issue at 3 AM
""")

# Show the poisoned vs clean data
clean_data = [
    {"message": "Disk at 95% on /pgdata", "category": "storage", "severity": "critical"},
    {"message": "Disk usage growing fast", "category": "storage", "severity": "high"},
    {"message": "Tablespace full on pg-primary", "category": "storage", "severity": "critical"},
]

poisoned_data = [
    {"message": "Disk at 95% on /pgdata", "category": "performance", "severity": "low"},
    {"message": "Disk usage growing fast", "category": "performance", "severity": "low"},
    {"message": "Tablespace full on pg-primary", "category": "performance", "severity": "low"},
]

print("Clean training data (correct labels):")
for d in clean_data:
    print(f"  [{d['severity']:>8s}] [{d['category']:>13s}] {d['message']}")

print("\nPoisoned training data (wrong labels):")
for d in poisoned_data:
    print(f"  [{d['severity']:>8s}] [{d['category']:>13s}] {d['message']} <- WRONG")

print("""
The poisoned data is subtle:
  - Messages are realistic (copied from real alerts)
  - Only the LABELS are wrong
  - 200 entries out of 5000 (4%) - small enough to not tank overall accuracy
  - But enough to flip the model's decision on disk alerts
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the poisoning:

```bash
python3 << 'PYEOF'
import json
import random
from collections import Counter, defaultdict
from datetime import datetime, timedelta

random.seed(42)

print("Investigation: Finding the Poisoned Data")
print("=" * 55)

# Simulate the full training dataset
categories = ["performance", "storage", "replication", "security"]
data = []

# Clean data (4800 entries)
for i in range(4800):
    cat = random.choice(categories)
    keywords = {
        "performance": ["cpu", "slow", "query", "latency"],
        "storage": ["disk", "space", "wal", "tablespace"],
        "replication": ["replication", "lag", "standby"],
        "security": ["login", "password", "ssl"],
    }
    kw = random.choice(keywords[cat])
    data.append({
        "message": f"{kw} issue on server-{random.randint(1,10)}",
        "category": cat,
        "added_by": "training_pipeline",
        "added_at": (datetime.now() - timedelta(days=random.randint(30, 180))).isoformat(),
    })

# Poisoned data (200 entries) - disk alerts labeled as performance
for i in range(200):
    disk_messages = [
        f"Disk at {random.randint(90,99)}% on /pgdata",
        f"Disk usage growing fast on server-{random.randint(1,5)}",
        f"Tablespace full on pg-{random.choice(['primary', 'standby'])}",
        f"Storage warning: {random.choice(['/data', '/wal', '/log'])} nearly full",
    ]
    data.append({
        "message": random.choice(disk_messages),
        "category": "performance",  # POISONED: should be "storage"
        "added_by": "spreadsheet_import",
        "added_at": (datetime.now() - timedelta(days=3)).isoformat(),
    })

# Detection Method 1: Keyword-label mismatch
print("\nMethod 1: Keyword-Label Mismatch")
keyword_rules = {
    "performance": ["cpu", "slow", "query", "latency"],
    "storage": ["disk", "space", "wal", "tablespace", "storage", "full"],
    "replication": ["replication", "lag", "standby"],
    "security": ["login", "password", "ssl"],
}

mismatches = []
for item in data:
    msg = item["message"].lower()
    expected_cats = set()
    for cat, keywords in keyword_rules.items():
        if any(kw in msg for kw in keywords):
            expected_cats.add(cat)
    if expected_cats and item["category"] not in expected_cats:
        mismatches.append(item)

print(f"  Found {len(mismatches)} keyword-label mismatches")

# Check source of mismatches
sources = Counter(m["added_by"] for m in mismatches)
print(f"  By source:")
for source, count in sources.most_common():
    print(f"    {source}: {count}")

# Detection Method 2: Temporal anomaly
print(f"\nMethod 2: Temporal Anomaly")
dates = defaultdict(int)
for item in data:
    date = item["added_at"][:10]
    dates[date] += 1

recent = {d: c for d, c in dates.items() if d > (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")}
if recent:
    print(f"  Recent additions (last 7 days):")
    for date, count in sorted(recent.items()):
        flag = " <- SPIKE" if count > 50 else ""
        print(f"    {date}: {count} entries{flag}")

# Detection Method 3: Source verification
print(f"\nMethod 3: Source Verification")
sources_all = Counter(d["added_by"] for d in data)
for source, count in sources_all.most_common():
    mismatch_count = sum(1 for m in mismatches if m["added_by"] == source)
    mismatch_rate = mismatch_count / count * 100 if count > 0 else 0
    flag = " <- HIGH MISMATCH RATE" if mismatch_rate > 10 else ""
    print(f"  {source}: {count} entries, {mismatch_count} mismatches ({mismatch_rate:.1f}%){flag}")

print(f"""
ROOT CAUSE:
  200 entries from "spreadsheet_import" have disk-related messages
  but are labeled as "performance" instead of "storage".

  All added within the last 3 days (temporal anomaly).
  100% mismatch rate from that source (source anomaly).
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

print("""
FIX: Four-layer defense against data poisoning.

Layer 1: Source verification (who can contribute training data?)
Layer 2: Automated label checking (keyword-label consistency)
Layer 3: Distribution monitoring (before and after adding new data)
Layer 4: Staged deployment (test on holdout before deploying)
""")

# Layer 1: Source verification
print("Layer 1: Source Verification")
print("=" * 50)
print("""
  BEFORE: Anyone with spreadsheet access can add training data
  AFTER:  Training data changes require:
    1. Identified author (who added this?)
    2. Review by at least one other person
    3. Automated quality checks before merge

  Implementation:
    - Move from shared spreadsheet to git-tracked JSONL files
    - Every data change is a pull request
    - PR requires automated checks + human review
    - Full audit trail of who added what
""")

# Layer 2: Automated quality gate
print("Layer 2: Automated Quality Gate")
print("=" * 50)

def quality_gate(new_data, keyword_rules):
    """Check new data for quality issues before adding to training set."""
    issues = []

    # Check 1: keyword-label consistency
    for item in new_data:
        msg = item["message"].lower()
        expected = set()
        for cat, keywords in keyword_rules.items():
            if any(kw in msg for kw in keywords):
                expected.add(cat)
        if expected and item["category"] not in expected:
            issues.append({
                "type": "label_mismatch",
                "message": item["message"][:50],
                "label": item["category"],
                "expected": list(expected),
            })

    # Check 2: batch anomaly (too many similar labels)
    from collections import Counter
    cat_counts = Counter(d["category"] for d in new_data)
    total = len(new_data)
    for cat, count in cat_counts.items():
        if count / total > 0.5 and total > 10:
            issues.append({
                "type": "batch_skew",
                "detail": f"{cat} is {count}/{total} ({count/total:.0%}) of new data",
            })

    return len(issues) == 0, issues

# Test the quality gate
keyword_rules = {
    "performance": ["cpu", "slow", "query"],
    "storage": ["disk", "space", "wal", "tablespace", "full"],
    "replication": ["replication", "lag", "standby"],
    "security": ["login", "password", "ssl"],
}

# Test with poisoned data
poisoned_batch = [
    {"message": "Disk at 95%", "category": "performance"},
    {"message": "Disk space full", "category": "performance"},
    {"message": "Tablespace running out", "category": "performance"},
]

passed, issues = quality_gate(poisoned_batch, keyword_rules)
print(f"\n  Poisoned batch: {'PASSED' if passed else 'BLOCKED'}")
for issue in issues[:3]:
    print(f"    {issue['type']}: {issue.get('message', issue.get('detail', ''))[:50]}")

# Test with clean data
clean_batch = [
    {"message": "Disk at 95%", "category": "storage"},
    {"message": "CPU at 90%", "category": "performance"},
    {"message": "Replication lag 60s", "category": "replication"},
]

passed, issues = quality_gate(clean_batch, keyword_rules)
print(f"\n  Clean batch: {'PASSED' if passed else 'BLOCKED'}")

print("""
Layer 3: Distribution Monitoring
  Compare data distribution BEFORE and AFTER adding new data.
  If the distribution shifts significantly, flag for review.
  (Covered in Build 03)

Layer 4: Staged Deployment
  After retraining with new data:
  1. Test on holdout set (data the attacker can't access)
  2. Compare per-category accuracy (not just overall)
  3. Run behavioral tests for each category
  4. Deploy to shadow mode for 24 hours
  5. Only promote to production after all checks pass

  The per-category check is KEY:
    Overall accuracy: 87% (passes threshold)
    Performance accuracy: 92%
    Storage accuracy: 45%   <- THIS catches the poison
    Replication accuracy: 90%
    Security accuracy: 88%

Prevention checklist:
  1. AUTHENTICATE data sources (who added this?)
  2. AUTOMATE quality checks (keyword-label consistency)
  3. CHECK per-category accuracy (not just overall)
  4. MONITOR distribution shifts (before/after new data)
  5. USE holdout set (attacker can't poison what they can't access)
  6. STAGED deployment (shadow mode catches production issues)
  7. TRACK data lineage (which data version trained which model)
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Unverified data source | Anyone can poison training data | Require authenticated, reviewed data |
| Mislabeled data | Model learns wrong classifications | Automated keyword-label checking |
| Overall accuracy hides poison | 87% overall but 45% on storage | Check per-category accuracy |
| No temporal monitoring | Spike of bad data goes unnoticed | Monitor data additions over time |
| No holdout set | Attacker can poison train AND test | Keep holdout set separate and secure |
