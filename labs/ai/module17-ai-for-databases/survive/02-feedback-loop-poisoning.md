# Survive 02: Feedback Loop Poisoning

A junior DBA joins the team and starts "correcting" AI classifications. They consistently label connectivity issues as "performance" because they don't understand the difference. After 3 weeks, the AI retrains on this feedback and starts misclassifying connectivity alerts.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
import json
import random
from collections import Counter

random.seed(42)

print("""
SCENARIO: Feedback Loop Poisoning

Your feedback system:
  1. AI classifies an alert
  2. DBA reviews and confirms or corrects
  3. Corrections become training data
  4. Model retrains weekly on new data

The poisoning:
  Week 1: New junior DBA (Alex) starts reviewing alerts
  Week 2: Alex corrects 45 connectivity alerts to "performance"
          (Alex thinks connection timeouts are performance issues)
  Week 3: Model retrains. Connectivity accuracy drops from 92% to 61%
  Week 4: Senior DBA notices connection pool alerts going to wrong team

The junior DBA wasn't malicious - just inexperienced.
But the AI learned their mistakes as "truth."
""")

# Show the impact
print("Feedback Data Analysis:")
print("=" * 55)

# Simulate DBA feedback
feedback = []

# Senior DBA (Sarah) - 200 correct reviews
for _ in range(200):
    cats = ["performance", "storage", "replication", "connectivity", "security"]
    cat = random.choice(cats)
    feedback.append({
        "dba": "sarah",
        "ai_predicted": cat,
        "dba_label": cat,          # Sarah confirms (correct)
        "type": "confirm",
    })

# Junior DBA (Alex) - 50 reviews, 45 wrong corrections
for _ in range(45):
    feedback.append({
        "dba": "alex",
        "ai_predicted": "connectivity",
        "dba_label": "performance",  # Alex "corrects" to performance (WRONG)
        "type": "correct",
    })
for _ in range(5):
    feedback.append({
        "dba": "alex",
        "ai_predicted": "performance",
        "dba_label": "performance",
        "type": "confirm",
    })

# Analyze
print(f"\n  Total feedback: {len(feedback)}")
by_dba = Counter(f["dba"] for f in feedback)
for dba, count in by_dba.most_common():
    corrections = sum(1 for f in feedback if f["dba"] == dba and f["type"] == "correct")
    print(f"    {dba}: {count} reviews ({corrections} corrections)")

# Show the connectivity -> performance corruption
conn_corrections = [
    f for f in feedback
    if f["ai_predicted"] == "connectivity" and f["dba_label"] == "performance"
]
print(f"\n  Suspicious: {len(conn_corrections)} times connectivity was 'corrected' to performance")
print(f"    All by: {Counter(f['dba'] for f in conn_corrections).most_common()}")

# Impact on training data
train_labels = Counter(f["dba_label"] for f in feedback)
conn_as_perf = sum(1 for f in feedback if f["ai_predicted"] == "connectivity" and f["dba_label"] == "performance")
conn_correct = sum(1 for f in feedback if f["ai_predicted"] == "connectivity" and f["dba_label"] == "connectivity")

print(f"\n  In training data after feedback:")
print(f"    'connectivity' alerts labeled correctly: {conn_correct}")
print(f"    'connectivity' alerts mislabeled as performance: {conn_as_perf}")
print(f"    Corruption rate: {conn_as_perf / (conn_correct + conn_as_perf) * 100:.0f}%")

print("""
After retraining on this data:
  - Connectivity accuracy: 92% -> 61% (31% drop)
  - Performance precision: 90% -> 78% (false positives from connectivity)
  - Connection pool alerts now go to performance team (wrong team)
  - Mean time to resolve connectivity issues: 15 min -> 45 min
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'
from collections import Counter, defaultdict

print("Investigation: Detecting Feedback Poisoning")
print("=" * 55)

# Simulate feedback data
import random
random.seed(42)

feedback = []
for _ in range(200):
    cats = ["performance", "storage", "replication", "connectivity", "security"]
    cat = random.choice(cats)
    feedback.append({"dba": "sarah", "predicted": cat, "label": cat, "type": "confirm"})

for _ in range(45):
    feedback.append({"dba": "alex", "predicted": "connectivity", "label": "performance", "type": "correct"})
for _ in range(5):
    feedback.append({"dba": "alex", "predicted": "performance", "label": "performance", "type": "confirm"})

# Detection Method 1: Per-DBA correction rate
print("\nMethod 1: Per-DBA Correction Rate")
print("-" * 45)

dba_stats = defaultdict(lambda: {"total": 0, "corrections": 0})
for f in feedback:
    dba_stats[f["dba"]]["total"] += 1
    if f["type"] == "correct":
        dba_stats[f["dba"]]["corrections"] += 1

for dba, stats in dba_stats.items():
    rate = stats["corrections"] / stats["total"] * 100
    flag = " <- HIGH CORRECTION RATE" if rate > 30 else ""
    print(f"  {dba}: {stats['corrections']}/{stats['total']} corrections ({rate:.0f}%){flag}")

# Detection Method 2: Correction pattern analysis
print(f"\nMethod 2: Correction Pattern Analysis")
print("-" * 45)

correction_patterns = Counter()
for f in feedback:
    if f["type"] == "correct":
        pattern = f"{f['predicted']} -> {f['label']}"
        correction_patterns[pattern] += 1

for pattern, count in correction_patterns.most_common(5):
    flag = " <- SUSPICIOUS PATTERN" if count > 10 else ""
    print(f"  {pattern}: {count} times{flag}")

# Detection Method 3: Inter-annotator agreement
print(f"\nMethod 3: Cross-DBA Agreement Check")
print("-" * 45)

# Check if Alex's corrections agree with Sarah's labels for the same category
sarah_labels = Counter(f["label"] for f in feedback if f["dba"] == "sarah" and f["predicted"] == "connectivity")
alex_labels = Counter(f["label"] for f in feedback if f["dba"] == "alex" and f["predicted"] == "connectivity")

print(f"  When AI predicts 'connectivity':")
print(f"    Sarah labels it as: {dict(sarah_labels)}")
print(f"    Alex labels it as:  {dict(alex_labels)}")

if sarah_labels and alex_labels:
    sarah_top = sarah_labels.most_common(1)[0][0]
    alex_top = alex_labels.most_common(1)[0][0]
    if sarah_top != alex_top:
        print(f"    DISAGREEMENT: Sarah says '{sarah_top}', Alex says '{alex_top}'")

print("""
ROOT CAUSE:
  1. No review of junior DBA's corrections before training
  2. No inter-annotator agreement check
  3. No threshold on how much one DBA can change training data
  4. No "correction of corrections" workflow

The system trusted ALL DBA feedback equally.
A junior DBA with 3 weeks of experience had the same
influence as a senior DBA with 10 years.
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
from collections import Counter, defaultdict

print("""
FIX: Four layers of feedback quality control.

Layer 1: DBA trust levels (experience-based weighting)
Layer 2: Correction anomaly detection (flag unusual patterns)
Layer 3: Cross-review requirement (corrections need second opinion)
Layer 4: Feedback quarantine (new DBA's corrections held for review)
""")

print("Layer 1: DBA Trust Levels")
print("=" * 50)

class TrustedFeedbackSystem:
    """
    Weight DBA feedback by experience level.

    Trust levels:
      Senior (10+ years): feedback goes directly to training
      Mid-level (3-10 years): feedback accepted with spot checks
      Junior (< 3 years): feedback quarantined for review

    DBA analogy: like database role privileges.
    Superuser can ALTER SYSTEM. Regular user can only SELECT.
    Senior DBA feedback is trusted. Junior's needs review.
    """

    def __init__(self):
        self.dba_profiles = {}
        self.feedback_queue = []         # pending feedback
        self.approved_feedback = []      # reviewed and approved
        self.quarantined = []            # held for review

    def register_dba(self, name, experience_years):
        """Register a DBA with their experience level."""
        if experience_years >= 10:
            level = "senior"
        elif experience_years >= 3:
            level = "mid"
        else:
            level = "junior"

        self.dba_profiles[name] = {
            "experience_years": experience_years,
            "trust_level": level,
            "total_reviews": 0,
            "corrections": 0,
            "correction_rate": 0,
        }

    def submit_feedback(self, dba_name, predicted, label, feedback_type):
        """Submit DBA feedback with trust-based routing."""
        profile = self.dba_profiles.get(dba_name)
        if not profile:
            return {"status": "rejected", "reason": "Unknown DBA"}

        entry = {
            "dba": dba_name,
            "predicted": predicted,
            "label": label,
            "type": feedback_type,
            "trust_level": profile["trust_level"],
        }

        # Update stats
        profile["total_reviews"] += 1
        if feedback_type == "correct":
            profile["corrections"] += 1
        profile["correction_rate"] = profile["corrections"] / profile["total_reviews"]

        # Route based on trust level
        if profile["trust_level"] == "senior":
            self.approved_feedback.append(entry)
            return {"status": "approved", "reason": "Senior DBA - auto-approved"}

        elif profile["trust_level"] == "mid":
            if feedback_type == "confirm":
                self.approved_feedback.append(entry)
                return {"status": "approved", "reason": "Mid-level confirm - auto-approved"}
            else:
                # Corrections from mid-level need spot check
                self.feedback_queue.append(entry)
                return {"status": "queued", "reason": "Mid-level correction - queued for spot check"}

        else:  # junior
            self.quarantined.append(entry)
            return {"status": "quarantined", "reason": "Junior DBA - all feedback held for review"}

    def get_stats(self):
        """Get feedback routing stats."""
        return {
            "approved": len(self.approved_feedback),
            "queued": len(self.feedback_queue),
            "quarantined": len(self.quarantined),
        }


# Test the trust system
system = TrustedFeedbackSystem()
system.register_dba("sarah", experience_years=12)
system.register_dba("alex", experience_years=1)
system.register_dba("mike", experience_years=5)

# Submit feedback
test_feedback = [
    ("sarah", "performance", "performance", "confirm"),
    ("sarah", "storage", "storage", "confirm"),
    ("alex", "connectivity", "performance", "correct"),
    ("alex", "connectivity", "performance", "correct"),
    ("alex", "connectivity", "performance", "correct"),
    ("mike", "performance", "performance", "confirm"),
    ("mike", "connectivity", "storage", "correct"),
]

print(f"\nFeedback Routing:")
print("-" * 65)
for dba, pred, label, ftype in test_feedback:
    result = system.submit_feedback(dba, pred, label, ftype)
    print(f"  {dba:<8s} {pred}->{label} [{ftype:>7s}] -> {result['status']:>12s} ({result['reason'][:35]})")

stats = system.get_stats()
print(f"\n  Summary: {stats['approved']} approved, {stats['queued']} queued, {stats['quarantined']} quarantined")
print(f"  Alex's 3 corrections are ALL quarantined (not in training data)")


# Layer 2: Correction anomaly detection
print(f"\nLayer 2: Correction Anomaly Detection")
print("=" * 50)

def detect_anomalous_corrections(feedback_log, max_correction_rate=0.5):
    """
    Flag DBAs whose correction patterns are unusual.

    If a DBA corrects > 50% of what they review, something is wrong.
    Either the AI is very bad (check other DBAs) or the DBA is wrong.
    """
    dba_stats = defaultdict(lambda: {"total": 0, "corrections": 0})
    for f in feedback_log:
        dba_stats[f["dba"]]["total"] += 1
        if f["type"] == "correct":
            dba_stats[f["dba"]]["corrections"] += 1

    anomalies = []
    for dba, stats in dba_stats.items():
        rate = stats["corrections"] / stats["total"] if stats["total"] > 0 else 0
        if rate > max_correction_rate and stats["total"] >= 5:
            anomalies.append({
                "dba": dba,
                "correction_rate": round(rate * 100),
                "total_reviews": stats["total"],
            })

    return anomalies

# Check for anomalies
import random
random.seed(42)

sample_log = []
for _ in range(100):
    sample_log.append({"dba": "sarah", "type": "confirm"})
for _ in range(45):
    sample_log.append({"dba": "alex", "type": "correct"})
for _ in range(5):
    sample_log.append({"dba": "alex", "type": "confirm"})

anomalies = detect_anomalous_corrections(sample_log)
for a in anomalies:
    print(f"  ANOMALY: {a['dba']} corrects {a['correction_rate']}% of reviews ({a['total_reviews']} total)")

print("""
Layer 3: Cross-Review Requirement
  Any correction that changes a category must be reviewed
  by a second DBA before entering training data.

  "Alex says this connectivity alert is performance."
  -> Sarah reviews: "No, it's connectivity. Alex is wrong."
  -> Alex's correction is rejected.
  -> Alex gets coached on the difference.

Layer 4: Feedback Quarantine for New DBAs
  First 30 days: ALL feedback quarantined
  Days 31-90: corrections quarantined, confirms accepted
  After 90 days: full trust (if correction rate < 20%)

Prevention checklist:
  1. Trust levels based on experience (senior/mid/junior)
  2. Junior corrections quarantined by default
  3. Correction anomaly detection (flag high correction rates)
  4. Cross-review requirement for category changes
  5. Gradual trust elevation (30 -> 90 days)
  6. Weekly review of feedback quality metrics
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Equal trust for all DBAs | Junior mistakes become training data | Trust levels by experience |
| No review of corrections | Wrong corrections poison the model | Cross-review requirement |
| High correction rate undetected | One DBA can skew entire category | Anomaly detection on correction patterns |
| Immediate feedback inclusion | Bad data enters training before review | Quarantine period for new DBAs |
| No feedback quality metrics | Can't detect poisoning until accuracy drops | Track correction rates per DBA |
