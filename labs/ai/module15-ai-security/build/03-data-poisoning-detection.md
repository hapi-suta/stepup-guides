# Build 03: Data Poisoning Detection

Data poisoning is when an attacker corrupts your training data to make the model behave incorrectly. It's subtle - the model trains fine, metrics look okay, but it systematically fails on specific patterns the attacker designed.

---

## Step 1. Understand data poisoning

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Data Poisoning: Corrupting training data to manipulate the model.

Attack types:

1. LABEL FLIPPING
   Change labels on specific examples:
   "disk at 99%" labeled as "low priority" (should be critical)
   Model learns to ignore disk alerts.

2. BACKDOOR INJECTION
   Add special trigger patterns:
   Any alert containing "MAINTENANCE" is labeled "ignore"
   Attacker later sends: "CPU at 99% MAINTENANCE" -> model ignores it

3. DATA INJECTION
   Add many examples of one pattern:
   Add 1000 fake "security" alerts for normal login messages
   Model becomes over-sensitive, flags everything as security

DBA analogy:
  Like someone inserting bad rows into your reference data:
  INSERT INTO severity_mapping VALUES ('disk_full', 'low');
  -- disk_full should be 'critical', not 'low'
  -- Every query using this mapping now gets wrong answers

Why it's dangerous:
  - Model metrics might look fine (poisoned data is in train AND test)
  - The attack is targeted (only affects specific patterns)
  - Hard to detect by looking at aggregate accuracy
  - Can persist through retraining if data source isn't cleaned
""")
PYEOF
```

---

## Step 2. Detect label anomalies

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import random
from collections import Counter, defaultdict

random.seed(42)

print("""
Detection Method 1: Label Anomaly Detection

Look for labels that don't match expectations:
  - "disk full" labeled as anything other than "storage"
  - "CPU 99%" labeled as "low priority"
  - Labels that contradict keyword patterns

DBA analogy:
  Like finding rows where severity='low' but message contains 'CRITICAL'.
  SELECT * FROM alerts WHERE severity = 'low'
    AND message ILIKE '%critical%';
""")

# Create a dataset with some poisoned labels
categories = {
    "performance": ["cpu", "slow", "query", "latency", "timeout", "connection"],
    "storage": ["disk", "space", "full", "wal", "tablespace"],
    "replication": ["replication", "lag", "standby", "failover"],
    "security": ["login", "password", "ssl", "unauthorized"],
}

# Build keyword -> expected category mapping
keyword_to_category = {}
for cat, keywords in categories.items():
    for kw in keywords:
        keyword_to_category[kw] = cat

def detect_label_anomalies(data, keyword_to_category):
    """Find samples where the label contradicts keyword patterns."""
    anomalies = []

    for item in data:
        msg = item["message"].lower()
        label = item["category"]

        # Find which categories the keywords suggest
        expected_cats = set()
        for keyword, expected_cat in keyword_to_category.items():
            if keyword in msg:
                expected_cats.add(expected_cat)

        # If we found expected categories and the label isn't one of them
        if expected_cats and label not in expected_cats:
            anomalies.append({
                "message": item["message"],
                "labeled_as": label,
                "expected": list(expected_cats),
                "suspicious": True,
            })

    return anomalies

# Create dataset with poisoned labels
clean_data = [
    {"message": "CPU at 95% on primary", "category": "performance"},
    {"message": "Disk space at 90%", "category": "storage"},
    {"message": "Replication lag 60 seconds", "category": "replication"},
    {"message": "Failed login from 10.0.0.99", "category": "security"},
    {"message": "Slow query on orders table", "category": "performance"},
    {"message": "WAL directory growing fast", "category": "storage"},
    {"message": "Standby not streaming", "category": "replication"},
    {"message": "SSL certificate expiring", "category": "security"},
]

# Poison: flip some labels
poisoned_data = clean_data.copy()
poisoned_data.append({"message": "Disk full on /pgdata", "category": "performance"})  # should be storage
poisoned_data.append({"message": "CPU at 99% critical", "category": "security"})  # should be performance
poisoned_data.append({"message": "Replication lag 300s", "category": "storage"})  # should be replication

print("Label Anomaly Detection:")
print("=" * 65)

anomalies = detect_label_anomalies(poisoned_data, keyword_to_category)

print(f"\nFound {len(anomalies)} suspicious labels in {len(poisoned_data)} samples:")
for a in anomalies:
    print(f"  SUSPICIOUS: '{a['message'][:40]}'")
    print(f"    Labeled as: {a['labeled_as']}")
    print(f"    Expected:   {a['expected']}")
    print()

print(f"These {len(anomalies)} samples should be reviewed by a human")
print("They could be poisoned data or genuine edge cases")
PYEOF
```

---

## Step 3. Detect distribution anomalies

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
from collections import Counter

random.seed(42)

print("""
Detection Method 2: Distribution Anomaly Detection

If someone injects many examples, the data distribution shifts.
Compare current data distribution to a known-good baseline.

DBA analogy:
  Like checking if a table's row count distribution changed unexpectedly.
  SELECT category, count(*) FROM alerts GROUP BY category;
  If "security" suddenly has 10x more rows than usual, investigate.
""")

def check_distribution(data, baseline_distribution, max_shift=0.1):
    """Compare data distribution to baseline. Flag large shifts."""
    current_cats = Counter(d["category"] for d in data)
    total = sum(current_cats.values())
    current_dist = {cat: count / total for cat, count in current_cats.items()}

    anomalies = []
    for cat in set(list(baseline_distribution.keys()) + list(current_dist.keys())):
        baseline_pct = baseline_distribution.get(cat, 0)
        current_pct = current_dist.get(cat, 0)
        shift = abs(current_pct - baseline_pct)

        if shift > max_shift:
            anomalies.append({
                "category": cat,
                "baseline": round(baseline_pct, 3),
                "current": round(current_pct, 3),
                "shift": round(shift, 3),
            })

    return anomalies

# Known-good baseline distribution
baseline = {
    "performance": 0.30,
    "storage": 0.25,
    "replication": 0.20,
    "security": 0.15,
    "backup": 0.10,
}

# Generate normal data
normal_data = []
for i in range(1000):
    r = random.random()
    if r < 0.30:
        cat = "performance"
    elif r < 0.55:
        cat = "storage"
    elif r < 0.75:
        cat = "replication"
    elif r < 0.90:
        cat = "security"
    else:
        cat = "backup"
    normal_data.append({"category": cat, "message": f"Alert {i}"})

# Generate POISONED data (security category inflated)
poisoned_data = normal_data.copy()
for i in range(300):
    poisoned_data.append({"category": "security", "message": f"Injected security alert {i}"})

print("Distribution Anomaly Detection:")
print("=" * 60)

# Check normal data
print("\nNormal data (1000 samples):")
anomalies = check_distribution(normal_data, baseline, max_shift=0.05)
if anomalies:
    for a in anomalies:
        print(f"  SHIFT: {a['category']}: {a['baseline']:.1%} -> {a['current']:.1%} ({a['shift']:+.1%})")
else:
    print("  No significant distribution shifts detected")

# Check poisoned data
print(f"\nPoisoned data (1300 samples, 300 injected 'security'):")
anomalies = check_distribution(poisoned_data, baseline, max_shift=0.05)
if anomalies:
    for a in anomalies:
        print(f"  ANOMALY: {a['category']}: {a['baseline']:.1%} -> {a['current']:.1%} ({a['shift']:+.1%})")
else:
    print("  No shifts detected")

print(f"\n  The 'security' category shifted from 15% to ~35%")
print(f"  This is a strong signal of data injection")
PYEOF
```

---

## Step 4. Build a complete poisoning defense

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import random
import hashlib
from collections import Counter, defaultdict
from datetime import datetime

random.seed(42)

print("""
Complete Data Poisoning Defense:
  1. Label anomaly detection (individual samples)
  2. Distribution anomaly detection (aggregate shifts)
  3. Source verification (who added this data?)
  4. Temporal anomaly detection (sudden spikes)
  5. Content fingerprinting (detect duplicates/templates)
""")

class DataPoisoningDetector:
    """Detect potential data poisoning in training datasets."""

    def __init__(self, baseline_dist=None):
        self.baseline_dist = baseline_dist or {}
        self.keyword_rules = {
            "performance": ["cpu", "slow", "query", "latency", "timeout"],
            "storage": ["disk", "space", "full", "wal"],
            "replication": ["replication", "lag", "standby"],
            "security": ["login", "password", "ssl", "unauthorized"],
        }

    def check_all(self, data):
        """Run all poisoning checks."""
        results = {
            "total_samples": len(data),
            "checks": {},
        }

        # Check 1: label anomalies
        label_issues = self._check_labels(data)
        results["checks"]["label_anomalies"] = {
            "count": len(label_issues),
            "pct": round(len(label_issues) / len(data) * 100, 1),
            "samples": label_issues[:5],
        }

        # Check 2: distribution
        dist_issues = self._check_distribution(data)
        results["checks"]["distribution_shifts"] = {
            "count": len(dist_issues),
            "details": dist_issues,
        }

        # Check 3: duplicate detection
        dupe_issues = self._check_duplicates(data)
        results["checks"]["suspicious_duplicates"] = {
            "count": dupe_issues["duplicate_count"],
            "pct": round(dupe_issues["duplicate_count"] / len(data) * 100, 1),
            "top_duplicates": dupe_issues["top_duplicates"],
        }

        # Check 4: template detection
        template_issues = self._check_templates(data)
        results["checks"]["template_patterns"] = {
            "count": len(template_issues),
            "patterns": template_issues[:3],
        }

        # Overall risk
        risk_score = 0
        if results["checks"]["label_anomalies"]["pct"] > 5:
            risk_score += 2
        if results["checks"]["distribution_shifts"]["count"] > 0:
            risk_score += 2
        if results["checks"]["suspicious_duplicates"]["pct"] > 10:
            risk_score += 1
        if results["checks"]["template_patterns"]["count"] > 0:
            risk_score += 1

        results["risk_level"] = "high" if risk_score >= 3 else "medium" if risk_score >= 1 else "low"
        results["risk_score"] = risk_score

        return results

    def _check_labels(self, data):
        issues = []
        for item in data:
            msg = item.get("message", "").lower()
            label = item.get("category", "")
            expected = set()
            for cat, keywords in self.keyword_rules.items():
                if any(kw in msg for kw in keywords):
                    expected.add(cat)
            if expected and label not in expected:
                issues.append({"message": item["message"][:50], "label": label, "expected": list(expected)})
        return issues

    def _check_distribution(self, data):
        if not self.baseline_dist:
            return []
        cats = Counter(d["category"] for d in data)
        total = sum(cats.values())
        issues = []
        for cat in set(list(self.baseline_dist.keys()) + list(cats.keys())):
            baseline = self.baseline_dist.get(cat, 0)
            current = cats.get(cat, 0) / total
            if abs(current - baseline) > 0.10:
                issues.append({"category": cat, "baseline": round(baseline, 3), "current": round(current, 3)})
        return issues

    def _check_duplicates(self, data):
        msg_counts = Counter(d.get("message", "").lower().strip() for d in data)
        dupes = {msg: count for msg, count in msg_counts.items() if count > 2}
        return {
            "duplicate_count": sum(count - 1 for count in dupes.values()),
            "top_duplicates": sorted(
                [{"message": msg[:50], "count": count} for msg, count in dupes.items()],
                key=lambda x: x["count"], reverse=True
            )[:5],
        }

    def _check_templates(self, data):
        """Detect if many messages follow the same template (mass injection)."""
        # Simple: check for messages that are very similar
        prefixes = Counter()
        for d in data:
            msg = d.get("message", "")
            if len(msg) > 10:
                prefix = msg[:20]
                prefixes[prefix] += 1

        suspicious = [{"prefix": prefix, "count": count}
                      for prefix, count in prefixes.items() if count > 10]
        return sorted(suspicious, key=lambda x: x["count"], reverse=True)

# Test with poisoned dataset
detector = DataPoisoningDetector(baseline_dist={
    "performance": 0.30, "storage": 0.25,
    "replication": 0.20, "security": 0.15, "backup": 0.10,
})

# Normal data
data = []
for i in range(500):
    cats = ["performance", "storage", "replication", "security", "backup"]
    weights = [30, 25, 20, 15, 10]
    cat = random.choices(cats, weights=weights)[0]
    kw = random.choice(detector.keyword_rules.get(cat, ["alert"]))
    data.append({"message": f"{kw} issue on server-{random.randint(1,10)}", "category": cat})

# Inject poison: 50 mislabeled + 100 injected security alerts
for i in range(50):
    data.append({"message": f"disk space critical on server-{i}", "category": "performance"})
for i in range(100):
    data.append({"message": f"Injected security alert number {i}", "category": "security"})

print("Data Poisoning Detection Report:")
print("=" * 60)

results = detector.check_all(data)

print(f"\nDataset: {results['total_samples']} samples")
print(f"Risk Level: {results['risk_level'].upper()} (score: {results['risk_score']})")

for check_name, check_result in results["checks"].items():
    print(f"\n  {check_name}:")
    for k, v in check_result.items():
        if isinstance(v, list) and len(v) > 0:
            print(f"    {k}:")
            for item in v[:3]:
                print(f"      {item}")
        else:
            print(f"    {k}: {v}")

print("""
Response to poisoning detection:
  1. QUARANTINE flagged samples (don't train on them)
  2. INVESTIGATE the source (who added this data?)
  3. RETRAIN without poisoned data
  4. ADD detection rules for the attack pattern
  5. MONITOR model behavior after retraining
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Label flipping | Attacker changes category labels | Corrupting reference data |
| Distribution check | Detect shifts in category balance | Monitoring table row counts |
| Duplicate detection | Find mass-injected similar data | Finding duplicate rows |
| Template detection | Find auto-generated attack data | Detecting bot traffic patterns |
| Source verification | Track who added each data point | Audit logging (pgaudit) |
| Data quarantine | Isolate suspicious data | Quarantine tables for bad rows |
