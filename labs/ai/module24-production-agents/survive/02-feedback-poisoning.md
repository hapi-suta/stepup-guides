# Survive 02: Feedback Poisoning

## The Scenario

A well-intentioned but mistaken team member provides wrong feedback on several alert
classifications. They mark replication lag alerts as "wrong - this is actually a disk
I/O issue" when the agent's original diagnosis was correct. The agent stores these
incorrect corrections and starts using them. Over the next two weeks, every replication
lag alert gets misclassified as a disk I/O problem. DBAs waste time investigating disk
when the real issue is always a long-running transaction or network problem. Two P1
replication failures go undiagnosed for over an hour each because the agent pointed
the team in the wrong direction.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'

# This script shows how incorrect feedback poisons the agent's learning,
# causing it to misclassify alerts based on bad corrections.

print("=" * 60)
print("SCENARIO: Feedback Poisoning - Agent Learns Wrong Patterns")
print("=" * 60)

print("""
Timeline:
  Week 1, Day 1:
    Agent correctly diagnoses replication lag as "long-running transaction"
    DBA Alice confirms: CORRECT
    Agent accuracy on replication alerts: 100%

  Week 1, Day 3:
    New team member Bob reviews past alerts
    Bob sees replication lag alert, thinks "must be disk I/O"
    Bob marks agent diagnosis as WRONG
    Bob writes: "This is a disk I/O bottleneck, not a transaction issue"
    Agent stores Bob's correction

  Week 1, Day 4:
    Similar replication lag alert arrives
    Agent finds Bob's correction in feedback database
    Agent now says: "Disk I/O bottleneck" (WRONG)
    DBA Charlie follows the agent's advice, investigates disk
    Disk is fine. Wastes 30 minutes.
    Charlie finally checks replication directly - finds blocking transaction

  Week 2:
    Bob provides 3 more wrong corrections on replication alerts
    Agent confidence in "disk I/O" diagnosis grows with each one
    Agent now says "disk I/O" for ALL replication alerts
    Accuracy on replication alerts drops to 0%

  Week 2, Day 5:
    Critical replication failure on production
    Agent says: "Disk I/O issue - check iostat and reduce checkpoint frequency"
    DBA follows agent advice. Spends 45 minutes on disk investigation.
    Real cause: WAL sender killed by OOM, standby is 2 hours behind
    By the time DBA finds the real issue, the standby is unusable for failover

Root cause: NO VALIDATION on feedback quality.
Anyone could provide feedback. Wrong feedback was accepted and used
without any quality checks or confidence thresholds.
""")

# -----------------------------------------------------------------------
# DEMONSTRATE THE POISONING
# -----------------------------------------------------------------------

# Feedback database (starts with some correct entries)
feedback_db = []

def store_feedback(alert_text, diagnosis, rating, correction="", reviewer=""):
    feedback_db.append({
        "alert_text": alert_text,
        "keywords": set(alert_text.lower().replace(",", " ").replace("=", " ").split()),
        "diagnosis": diagnosis,
        "rating": rating,
        "correction": correction,
        "reviewer": reviewer
    })

def find_corrections(alert_text):
    """Find past corrections matching this alert."""
    alert_kw = set(alert_text.lower().replace(",", " ").replace("=", " ").split())
    matches = []
    for fb in feedback_db:
        if fb["rating"] in ("wrong", "partial"):
            overlap = len(alert_kw & fb["keywords"])
            if overlap >= 2:
                matches.append(fb)
    return matches

def diagnose(alert_text):
    """Diagnose using feedback if available, otherwise use default rules."""
    corrections = find_corrections(alert_text)
    if corrections:
        # Uses the most recent correction
        c = corrections[-1]
        return f"[Feedback] {c['correction']}"
    if "replication" in alert_text.lower() or "lag" in alert_text.lower():
        return "Replication lag - check for long-running transactions"
    return "Unknown issue"


# Phase 1: Agent works correctly
print("Phase 1: Agent working correctly (before poisoning)")
print("-" * 50)

store_feedback(
    "replication_lag_seconds=300, replay_lsn stuck",
    "Replication lag - check for long-running transactions",
    "correct", "", "Alice"
)

alert1 = "replication_lag_seconds=250, replay_lsn not advancing"
d1 = diagnose(alert1)
print(f"  Alert: {alert1}")
print(f"  Agent: {d1}")
print(f"  Correct? YES - no poisoned feedback yet\n")

# Phase 2: Bob provides wrong feedback
print("Phase 2: Poisoning begins (Bob provides wrong corrections)")
print("-" * 50)

store_feedback(
    "replication_lag_seconds=300, replay_lsn stuck",
    "Replication lag - check for long-running transactions",
    "wrong",
    "This is a disk I/O bottleneck. Check iostat output and reduce checkpoint_completion_target.",
    "Bob"
)

store_feedback(
    "replication_lag_seconds=180, standby behind",
    "Replication lag - network or transaction issue",
    "wrong",
    "Not replication - this is disk I/O saturation on the standby. Add faster SSDs.",
    "Bob"
)

store_feedback(
    "replication_lag_seconds=500, replay delayed",
    "Replication lag - WAL sender backpressure",
    "wrong",
    "Disk I/O problem. The WAL writes are slow because of disk contention.",
    "Bob"
)

print(f"  Bob added 3 wrong corrections about 'disk I/O'")
print(f"  Total feedback records: {len(feedback_db)}")
print(f"  Wrong corrections: {sum(1 for f in feedback_db if f['rating'] == 'wrong')}\n")

# Phase 3: Agent now misdiagnoses
print("Phase 3: Agent poisoned (uses Bob's wrong corrections)")
print("-" * 50)

test_alerts = [
    "replication_lag_seconds=200, replay_lsn stuck",
    "replication_lag_seconds=400, standby not catching up",
    "replication_lag_seconds=120, replay delayed after maintenance",
]

for alert in test_alerts:
    d = diagnose(alert)
    print(f"  Alert: {alert[:50]}...")
    print(f"  Agent: {d[:70]}...")
    print(f"  Correct? NO - poisoned by Bob's feedback\n")

print("Result: Agent now misclassifies ALL replication alerts as disk I/O.")
print("DBAs waste time checking disk when the real issue is replication.")

PYEOF
```

### Expected output (yours will differ):

```
============================================================
SCENARIO: Feedback Poisoning - Agent Learns Wrong Patterns
============================================================

[scenario text printed here]

Phase 1: Agent working correctly (before poisoning)
--------------------------------------------------
  Alert: replication_lag_seconds=250, replay_lsn not advancing
  Agent: Replication lag - check for long-running transactions
  Correct? YES - no poisoned feedback yet

Phase 2: Poisoning begins (Bob provides wrong corrections)
--------------------------------------------------
  Bob added 3 wrong corrections about 'disk I/O'
  Total feedback records: 4
  Wrong corrections: 3

Phase 3: Agent poisoned (uses Bob's wrong corrections)
--------------------------------------------------
  Alert: replication_lag_seconds=200, replay_lsn stuck...
  Agent: [Feedback] Disk I/O problem. The WAL writes are slow bec...
  Correct? NO - poisoned by Bob's feedback

  Alert: replication_lag_seconds=400, standby not catching up...
  Agent: [Feedback] Disk I/O problem. The WAL writes are slow bec...
  Correct? NO - poisoned by Bob's feedback

  Alert: replication_lag_seconds=120, replay delayed after mainte...
  Agent: [Feedback] Disk I/O problem. The WAL writes are slow bec...
  Correct? NO - poisoned by Bob's feedback

Result: Agent now misclassifies ALL replication alerts as disk I/O.
DBAs waste time checking disk when the real issue is replication.
```

---

## Investigate

On your **Mac terminal**, find the root causes:

```bash
python3 << 'PYEOF'

print("Investigation: How Did Wrong Feedback Poison the Agent?")
print("=" * 55)

print("""
ROOT CAUSE 1: No reviewer qualification check
-----------------------------------------------
Anyone could provide feedback - no permission levels.
Bob was a new team member who did not understand replication.
His corrections were accepted with the same weight as Alice's
(a senior DBA with 10 years of PostgreSQL experience).

DBA analogy: like granting ALTER TABLE to every user.
A junior developer could change column types on production tables.
You need GRANT/REVOKE to control who can make schema changes.

ROOT CAUSE 2: No consensus requirement
-----------------------------------------------
A single person's feedback could override the agent's behavior.
One wrong correction from Bob was enough to change the diagnosis
for all future replication alerts.

DBA analogy: like Patroni failover without quorum.
If one node declares the primary dead (falsely), it promotes
itself. With quorum, you need 2-of-3 to agree before failover.

ROOT CAUSE 3: No feedback validation against ground truth
-----------------------------------------------
No one checked whether Bob's corrections were actually correct.
There was no mechanism to verify: "Did disk I/O actually cause
the lag?" The agent blindly trusted the human input.

DBA analogy: like accepting a pg_restore without verifying the
backup. If the backup was corrupted, you just restored garbage.
Always run pg_restore --list first to verify.

ROOT CAUSE 4: No accuracy monitoring that would catch the drift
-----------------------------------------------
Agent accuracy on replication alerts went from 100% to 0% over
two weeks, but no one noticed because there was no accuracy
dashboard broken down by alert category.

DBA analogy: like not monitoring cache_hit_ratio per table.
Overall cache ratio might be 99%, but one critical table could
drop to 50% and you would never know.
""")

PYEOF
```

### Expected output (yours will differ):

```
Investigation: How Did Wrong Feedback Poison the Agent?
=======================================================

ROOT CAUSE 1: No reviewer qualification check
...
ROOT CAUSE 2: No consensus requirement
...
ROOT CAUSE 3: No feedback validation against ground truth
...
ROOT CAUSE 4: No accuracy monitoring that would catch the drift
...
```

---

## The Fix

Four changes prevent feedback poisoning.

### Fix 1: Reviewer qualification and weighted feedback

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 1: Weight feedback by reviewer expertise level.
# Senior DBA corrections count more than junior ones.
# DBA analogy: like pg_hba.conf rules - different users get
# different access levels. A superuser's opinion carries more weight.

print("Fix 1: Weighted Feedback by Reviewer Expertise")
print("=" * 50)


class WeightedFeedback:
    """
    Weights feedback based on reviewer expertise level.
    Higher-weight reviewers' corrections take priority.
    """

    # Expertise levels and their weights
    WEIGHTS = {
        "senior_dba": 3.0,    # 10+ years, deep PG expertise
        "mid_dba": 2.0,       # 3-10 years
        "junior_dba": 1.0,    # < 3 years
        "developer": 0.5,     # not a DBA specialist
    }

    def __init__(self):
        self.feedback = []

    def store(self, alert_keywords, correction, reviewer, expertise):
        weight = self.WEIGHTS.get(expertise, 0.5)
        self.feedback.append({
            "keywords": set(alert_keywords),
            "correction": correction,
            "reviewer": reviewer,
            "expertise": expertise,
            "weight": weight
        })

    def get_best_correction(self, alert_keywords):
        """Return the correction with the highest weight."""
        alert_kw = set(alert_keywords)
        matches = []

        for fb in self.feedback:
            overlap = len(alert_kw & fb["keywords"])
            if overlap >= 2:
                # Score = keyword overlap * reviewer weight
                score = overlap * fb["weight"]
                matches.append({"correction": fb["correction"],
                                "reviewer": fb["reviewer"],
                                "expertise": fb["expertise"],
                                "score": score})

        if not matches:
            return None

        # Return the highest-scoring correction
        matches.sort(key=lambda x: x["score"], reverse=True)
        return matches[0]


# Demo
wf = WeightedFeedback()

# Bob (junior) says "disk I/O" - WRONG
wf.store(
    ["replication", "lag", "replay_lsn", "stuck"],
    "Disk I/O bottleneck - check iostat",
    "Bob", "junior_dba"
)

# Alice (senior) says "blocking transaction" - CORRECT
wf.store(
    ["replication", "lag", "replay_lsn", "stuck"],
    "Long-running transaction holding replication slot - find and terminate",
    "Alice", "senior_dba"
)

# When a replication alert comes in, Alice's feedback wins
result = wf.get_best_correction(["replication", "lag", "replay_lsn"])
print(f"\n  Alert keywords: replication, lag, replay_lsn")
print(f"  Best correction: {result['correction']}")
print(f"  From: {result['reviewer']} ({result['expertise']}, score={result['score']})")
print(f"\n  Alice's senior_dba weight (3.0) outweighs Bob's junior_dba weight (1.0)")

PYEOF
```

### Expected output (yours will differ):

```
Fix 1: Weighted Feedback by Reviewer Expertise
==================================================

  Alert keywords: replication, lag, replay_lsn
  Best correction: Long-running transaction holding replication slot - find and terminate
  From: Alice (senior_dba, score=9.0)

  Alice's senior_dba weight (3.0) outweighs Bob's junior_dba weight (1.0)
```

### Fix 2: Require consensus before accepting corrections

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 2: Require multiple reviewers to agree before a correction
# is accepted into the feedback database.
# DBA analogy: like Patroni requiring quorum (2-of-3) for failover.
# One node cannot unilaterally promote - it needs agreement.

print("Fix 2: Consensus Requirement for Corrections")
print("=" * 50)


class ConsensusCorrection:
    """
    Corrections need N reviewers to agree before they are stored.
    Pending corrections are held in a staging area until quorum is met.
    """

    def __init__(self, required_votes: int = 2):
        self.required_votes = required_votes
        self.pending = {}     # corrections waiting for consensus
        self.accepted = []    # corrections that passed consensus

    def propose_correction(self, alert_category: str, correction: str,
                           reviewer: str):
        """
        A reviewer proposes a correction. It goes to pending.
        If enough reviewers agree, it moves to accepted.
        """
        key = f"{alert_category}:{correction[:30]}"

        if key not in self.pending:
            self.pending[key] = {
                "category": alert_category,
                "correction": correction,
                "votes": [],
                "created_by": reviewer
            }

        # Add this reviewer's vote (each reviewer can only vote once)
        if reviewer not in self.pending[key]["votes"]:
            self.pending[key]["votes"].append(reviewer)

        vote_count = len(self.pending[key]["votes"])

        if vote_count >= self.required_votes:
            # Quorum met - move to accepted
            self.accepted.append(self.pending[key])
            del self.pending[key]
            return {"status": "ACCEPTED", "votes": vote_count}
        else:
            remaining = self.required_votes - vote_count
            return {"status": "PENDING", "votes": vote_count, "needs": remaining}


# Demo
cc = ConsensusCorrection(required_votes=2)

print()

# Bob proposes a wrong correction
r1 = cc.propose_correction(
    "replication_lag",
    "Disk I/O bottleneck",
    "Bob"
)
print(f"  Bob proposes 'Disk I/O': {r1['status']} ({r1['votes']} votes, needs {r1.get('needs', 0)} more)")

# No one else agrees, so it stays pending
print(f"  Pending corrections: {len(cc.pending)}")
print(f"  Accepted corrections: {len(cc.accepted)}")

# Alice proposes the correct correction
r2 = cc.propose_correction(
    "replication_lag",
    "Blocking transaction holding slot",
    "Alice"
)
print(f"\n  Alice proposes 'Blocking transaction': {r2['status']} ({r2['votes']} votes, needs {r2.get('needs', 0)} more)")

# Charlie agrees with Alice
r3 = cc.propose_correction(
    "replication_lag",
    "Blocking transaction holding slot",
    "Charlie"
)
print(f"  Charlie agrees with Alice: {r3['status']} ({r3['votes']} votes)")

print(f"\n  Pending corrections: {len(cc.pending)} (Bob's wrong one still waiting)")
print(f"  Accepted corrections: {len(cc.accepted)} (Alice's correct one passed)")

if cc.accepted:
    print(f"  Accepted: '{cc.accepted[0]['correction']}'")

PYEOF
```

### Expected output (yours will differ):

```
Fix 2: Consensus Requirement for Corrections
==================================================

  Bob proposes 'Disk I/O': PENDING (1 votes, needs 1 more)
  Pending corrections: 1
  Accepted corrections: 0

  Alice proposes 'Blocking transaction': PENDING (1 votes, needs 1 more)
  Charlie agrees with Alice: ACCEPTED (2 votes)

  Pending corrections: 1 (Bob's wrong one still waiting)
  Accepted corrections: 1 (Alice's correct one passed)
  Accepted: 'Blocking transaction holding slot'
```

### Fix 3: Accuracy monitoring per alert category

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 3: Monitor accuracy per alert category, not just overall.
# If accuracy drops in one category, alert the team immediately.
# DBA analogy: monitoring cache_hit_ratio PER TABLE, not just overall.

print("Fix 3: Per-Category Accuracy Monitoring")
print("=" * 50)


class CategoryAccuracyMonitor:
    """
    Tracks accuracy per alert category and fires alerts
    when any category drops below a threshold.
    """

    def __init__(self, alert_threshold: float = 0.7):
        self.threshold = alert_threshold
        self.categories = {}
        self.alerts = []

    def record(self, category: str, was_correct: bool):
        if category not in self.categories:
            self.categories[category] = {"correct": 0, "total": 0}

        self.categories[category]["total"] += 1
        if was_correct:
            self.categories[category]["correct"] += 1

        # Check if this category dropped below threshold
        data = self.categories[category]
        if data["total"] >= 3:  # need at least 3 samples
            accuracy = data["correct"] / data["total"]
            if accuracy < self.threshold:
                self.alerts.append({
                    "category": category,
                    "accuracy": round(accuracy * 100, 1),
                    "total": data["total"],
                    "message": f"Accuracy for '{category}' dropped to "
                               f"{round(accuracy*100,1)}% ({data['correct']}/{data['total']}). "
                               f"Check feedback quality for this category."
                })

    def report(self):
        print(f"\n  {'Category':<25} {'Correct':<10} {'Total':<8} {'Accuracy'}")
        print(f"  {'-' * 55}")
        for cat, data in sorted(self.categories.items()):
            acc = round(data["correct"] / data["total"] * 100, 1) if data["total"] > 0 else 0
            flag = " <-- BELOW THRESHOLD" if acc < self.threshold * 100 else ""
            print(f"  {cat:<25} {data['correct']:<10} {data['total']:<8} {acc}%{flag}")


# Demo: simulate accuracy tracking over time
monitor = CategoryAccuracyMonitor(alert_threshold=0.7)

# Connection alerts - agent does well
for _ in range(8):
    monitor.record("connections", True)
for _ in range(2):
    monitor.record("connections", False)

# Replication alerts - poisoned by bad feedback
monitor.record("replication_lag", True)   # before poisoning
monitor.record("replication_lag", False)  # after Bob's feedback
monitor.record("replication_lag", False)
monitor.record("replication_lag", False)
monitor.record("replication_lag", False)

# Disk alerts - agent does well
for _ in range(5):
    monitor.record("disk_usage", True)

print("\nAccuracy by category:")
monitor.report()

if monitor.alerts:
    print(f"\n  ACCURACY ALERTS:")
    for alert in monitor.alerts:
        print(f"  [{alert['category']}] {alert['message']}")

PYEOF
```

### Expected output (yours will differ):

```
Fix 3: Per-Category Accuracy Monitoring
==================================================

Accuracy by category:

  Category                  Correct    Total    Accuracy
  -------------------------------------------------------
  connections               8          10       80.0%
  disk_usage                5          5        100.0%
  replication_lag           1          5        20.0% <-- BELOW THRESHOLD

  ACCURACY ALERTS:
  [replication_lag] Accuracy for 'replication_lag' dropped to 20.0% (1/5). Check feedback quality for this category.
```

### Fix 4: Feedback expiration and rollback

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 4: Feedback has an expiration date. Old corrections can be
# reviewed and rolled back if accuracy drops.
# DBA analogy: like WAL retention and PITR. You can roll back to
# a known-good state if a bad change was applied.

print("Fix 4: Feedback Expiration and Rollback")
print("=" * 50)

import datetime


class FeedbackWithRollback:
    """
    Feedback entries have a creation date and can be rolled back.
    If a category's accuracy drops, you can remove all feedback
    from a specific reviewer or time period.
    """

    def __init__(self):
        self.feedback = []
        self.rollback_log = []

    def store(self, category, correction, reviewer, timestamp=None):
        entry = {
            "id": len(self.feedback) + 1,
            "category": category,
            "correction": correction,
            "reviewer": reviewer,
            "timestamp": timestamp or datetime.datetime.now().isoformat(),
            "active": True
        }
        self.feedback.append(entry)
        return entry["id"]

    def rollback_by_reviewer(self, reviewer):
        """
        Deactivate all feedback from a specific reviewer.
        DBA analogy: like revoking all GRANTs from a role.
        """
        count = 0
        for fb in self.feedback:
            if fb["reviewer"] == reviewer and fb["active"]:
                fb["active"] = False
                count += 1

        self.rollback_log.append({
            "action": "rollback_reviewer",
            "reviewer": reviewer,
            "entries_deactivated": count,
            "timestamp": datetime.datetime.now().isoformat()
        })
        return count

    def get_active_corrections(self, category):
        """Return only active (non-rolled-back) corrections."""
        return [
            fb for fb in self.feedback
            if fb["category"] == category and fb["active"]
        ]


# Demo
frb = FeedbackWithRollback()

print()

# Alice provides correct feedback
frb.store("replication_lag", "Check for blocking transactions", "Alice")

# Bob provides wrong feedback (3 entries)
frb.store("replication_lag", "Disk I/O issue", "Bob")
frb.store("replication_lag", "Check iostat output", "Bob")
frb.store("replication_lag", "SSD upgrade needed", "Bob")

active = frb.get_active_corrections("replication_lag")
print(f"  Before rollback: {len(active)} active corrections")
for fb in active:
    print(f"    [{fb['reviewer']}] {fb['correction']}")

# Accuracy dropped - roll back Bob's feedback
print(f"\n  Accuracy dropped! Rolling back Bob's feedback...")
rolled = frb.rollback_by_reviewer("Bob")
print(f"  Deactivated {rolled} entries from Bob")

active = frb.get_active_corrections("replication_lag")
print(f"\n  After rollback: {len(active)} active corrections")
for fb in active:
    print(f"    [{fb['reviewer']}] {fb['correction']}")

print(f"\n  Rollback log: {frb.rollback_log}")
print(f"\n  Agent is now back to using Alice's correct feedback only.")

PYEOF
```

### Expected output (yours will differ):

```
Fix 4: Feedback Expiration and Rollback
==================================================

  Before rollback: 4 active corrections
    [Alice] Check for blocking transactions
    [Bob] Disk I/O issue
    [Bob] Check iostat output
    [Bob] SSD upgrade needed

  Accuracy dropped! Rolling back Bob's feedback...
  Deactivated 3 entries from Bob

  After rollback: 1 active corrections
    [Alice] Check for blocking transactions

  Rollback log: [{'action': 'rollback_reviewer', 'reviewer': 'Bob', 'entries_deactivated': 3, ...}]

  Agent is now back to using Alice's correct feedback only.
```

---

## What You Learned

| Problem | Why It Caused the Incident | Fix |
|---------|---------------------------|-----|
| No reviewer qualification | Anyone could override agent behavior with wrong feedback | Weight feedback by reviewer expertise level |
| Single reviewer can override | One person's wrong feedback affected all future alerts | Require consensus (2+ reviewers) before accepting |
| No per-category accuracy tracking | Overall accuracy looked fine while one category was 0% | Monitor accuracy per alert category with thresholds |
| No feedback rollback capability | Wrong feedback was permanent once stored | Support rollback by reviewer or time period |
| No feedback expiration | Old corrections persisted indefinitely | Set expiration dates on feedback entries |
