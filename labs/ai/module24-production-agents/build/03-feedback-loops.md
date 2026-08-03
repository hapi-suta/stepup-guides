# Build 03: Feedback Loops

## Why Feedback Matters

An agent that never learns from corrections will keep making the same mistakes. The first time it misclassifies a replication lag alert as a disk issue, a DBA corrects it. If the agent cannot store and retrieve that correction, it will misclassify the same alert pattern next week.

**DBA analogy:** PostgreSQL's autovacuum adapts based on table activity. Tables with heavy write activity get vacuumed more often because the system tracks dead tuple counts and adjusts. Your agent should adapt the same way - based on DBA feedback, not just static rules.

```
Autovacuum feedback loop:
  Table activity -> dead tuple count -> exceeds threshold -> vacuum runs
  After vacuum -> dead tuples drop -> threshold not met -> vacuum skips
  The system adapts to the workload.

Agent feedback loop:
  Alert arrives -> agent classifies -> DBA says "wrong, it was actually X"
  Next similar alert -> agent retrieves past correction -> classifies correctly
  The agent adapts to the DBA's expertise.
```

---

## Step 1: Feedback Collection

### The Concept

After the agent makes a recommendation, the DBA rates it. The simplest model is three options:

| Rating | Meaning | What the Agent Learns |
|--------|---------|----------------------|
| `correct` | Agent got it right | Reinforce this pattern |
| `wrong` | Agent was wrong, DBA provides the right answer | Store the correction |
| `partial` | Agent was close but missed something | Store the refinement |

**DBA analogy:** This is like a DBA review process for runbooks. After an incident, the team reviews the runbook and marks each step as: "worked", "wrong - fix it", or "mostly worked but needs adjustment". The runbook improves with each review.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a feedback collection system where the DBA rates
#   agent recommendations. Feedback is stored as records
#   that can be retrieved later.
# ---------------------------------------------------------

import json
import datetime

# ---------------------------------------------------------
# FEEDBACK STORAGE
# ---------------------------------------------------------
# We store feedback as a list of dicts (like rows in a table).
# In production, this would be a PostgreSQL table or SQLite database.
# For this lab, we keep it in memory and also write to a JSON file.

# "feedback_store" is our in-memory table
# Think of it as: CREATE TABLE agent_feedback (id SERIAL, ...)
feedback_store = []


def collect_feedback(
    alert_id: str,
    alert_text: str,
    agent_classification: str,
    agent_diagnosis: str,
    agent_recommendation: str,
    dba_rating: str,
    dba_correction: str
) -> dict:
    """
    Record DBA feedback on an agent recommendation.

    Parameters:
        alert_id              - unique identifier for the alert
        alert_text            - the original alert text
        agent_classification  - what the agent classified it as
        agent_diagnosis       - the agent's root cause analysis
        agent_recommendation  - what the agent recommended
        dba_rating            - 'correct', 'wrong', or 'partial'
        dba_correction        - if wrong/partial, what the real answer was

    Returns:
        the feedback record that was stored

    DBA analogy: INSERT INTO agent_feedback (alert_id, rating, correction, ...)
    """

    # Build the feedback record - like constructing an INSERT statement
    record = {
        "id": len(feedback_store) + 1,
        "alert_id": alert_id,
        "alert_text": alert_text,
        "agent_classification": agent_classification,
        "agent_diagnosis": agent_diagnosis,
        "agent_recommendation": agent_recommendation,
        "dba_rating": dba_rating,
        "dba_correction": dba_correction,
        "created_at": datetime.datetime.now().isoformat()
    }

    # Append to our in-memory store - like INSERT INTO
    feedback_store.append(record)

    return record


# ---------------------------------------------------------
# SIMULATE AN AGENT MAKING RECOMMENDATIONS AND RECEIVING FEEDBACK
# ---------------------------------------------------------

print("=" * 60)
print("FEEDBACK COLLECTION")
print("=" * 60)

# Scenario 1: Agent gets it right
print("\n--- Alert 1: Connection exhaustion ---")
print("  Agent says: CRITICAL - connection pool exhausted, deploy PgBouncer")
f1 = collect_feedback(
    alert_id="ALERT-001",
    alert_text="active_connections=199, max_connections=200",
    agent_classification="CRITICAL",
    agent_diagnosis="Connection pool exhausted. App not releasing connections.",
    agent_recommendation="Kill idle connections, deploy PgBouncer",
    dba_rating="correct",
    dba_correction=""
)
print(f"  DBA rating: {f1['dba_rating']}")

# Scenario 2: Agent gets it wrong
print("\n--- Alert 2: Replication lag spike ---")
print("  Agent says: WARNING - network latency causing lag")
f2 = collect_feedback(
    alert_id="ALERT-002",
    alert_text="replication_lag_seconds=320, replay_lsn stuck for 5 min",
    agent_classification="WARNING",
    agent_diagnosis="Network latency between primary and standby causing lag.",
    agent_recommendation="Check network bandwidth between datacenters",
    dba_rating="wrong",
    dba_correction="This was actually a long-running transaction on the primary "
                   "holding back the replication slot. The fix is to find and "
                   "terminate the blocking transaction, not check the network. "
                   "Severity should be CRITICAL, not WARNING."
)
print(f"  DBA rating: {f2['dba_rating']}")
print(f"  DBA correction: {f2['dba_correction'][:80]}...")

# Scenario 3: Agent is partially right
print("\n--- Alert 3: Table bloat ---")
print("  Agent says: WARNING - run VACUUM ANALYZE")
f3 = collect_feedback(
    alert_id="ALERT-003",
    alert_text="dead_tuples=4200000, live_tuples=12500000, table=orders",
    agent_classification="WARNING",
    agent_diagnosis="Table bloat from normal DML activity.",
    agent_recommendation="Run VACUUM ANALYZE on the orders table",
    dba_rating="partial",
    dba_correction="Diagnosis is correct but recommendation is incomplete. "
                   "VACUUM ANALYZE alone won't reclaim space - need VACUUM FULL "
                   "or pg_repack since the table is over 25% bloat. Also need to "
                   "check why autovacuum is not handling this."
)
print(f"  DBA rating: {f3['dba_rating']}")
print(f"  DBA correction: {f3['dba_correction'][:80]}...")

# ---------------------------------------------------------
# DISPLAY ALL STORED FEEDBACK
# ---------------------------------------------------------

print(f"\n{'=' * 60}")
print("STORED FEEDBACK (like SELECT * FROM agent_feedback)")
print(f"{'=' * 60}")

for record in feedback_store:
    print(f"\n  ID: {record['id']}  Alert: {record['alert_id']}")
    print(f"  Rating: {record['dba_rating']}")
    if record['dba_correction']:
        print(f"  Correction: {record['dba_correction'][:60]}...")

# Save to a JSON file for persistence
# json.dump writes a Python object to a file as JSON
# indent=2 makes it human-readable
with open("/tmp/agent_feedback.json", "w") as f:
    json.dump(feedback_store, f, indent=2)

print(f"\nFeedback saved to /tmp/agent_feedback.json")
print(f"Total records: {len(feedback_store)}")

EOF
```

Expected output (yours will differ):
```
============================================================
FEEDBACK COLLECTION
============================================================

--- Alert 1: Connection exhaustion ---
  Agent says: CRITICAL - connection pool exhausted, deploy PgBouncer
  DBA rating: correct

--- Alert 2: Replication lag spike ---
  Agent says: WARNING - network latency causing lag
  DBA rating: wrong
  DBA correction: This was actually a long-running transaction on the primary ...

--- Alert 3: Table bloat ---
  Agent says: WARNING - run VACUUM ANALYZE
  DBA rating: partial
  DBA correction: Diagnosis is correct but recommendation is incomplete. VA...

============================================================
STORED FEEDBACK (like SELECT * FROM agent_feedback)
============================================================

  ID: 1  Alert: ALERT-001
  Rating: correct

  ID: 2  Alert: ALERT-002
  Rating: wrong
  Correction: This was actually a long-running transaction on the pr...

  ID: 3  Alert: ALERT-003
  Rating: partial
  Correction: Diagnosis is correct but recommendation is incomplete....

Feedback saved to /tmp/agent_feedback.json
Total records: 3
```

---

## Step 2: Retrieval-Augmented Feedback

### The Concept

When a new alert comes in, the agent searches its feedback database for similar past alerts. If it finds a correction from a DBA, it uses that correction to adjust its recommendation.

**DBA analogy:** This is like `pg_stat_statements`. When you see a slow query, you check `pg_stat_statements` to see if this query has been slow before, how many times it has run, and what the average execution time is. The agent does the same thing - it checks its feedback history before answering.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a retrieval system that finds past DBA feedback
#   matching the current alert, then uses that feedback to
#   improve the agent's response.
# ---------------------------------------------------------

import json
import datetime

# ---------------------------------------------------------
# LOAD PAST FEEDBACK
# ---------------------------------------------------------
# In production, this would be: SELECT * FROM agent_feedback
# For this lab, we start with seeded data that represents past corrections.

feedback_database = [
    {
        "id": 1,
        "alert_text": "active_connections=199, max_connections=200",
        "keywords": ["connections", "max_connections", "exhausted"],
        "agent_classification": "CRITICAL",
        "agent_diagnosis": "Connection pool exhausted",
        "dba_rating": "correct",
        "dba_correction": ""
    },
    {
        "id": 2,
        "alert_text": "replication_lag_seconds=320, replay_lsn stuck",
        "keywords": ["replication_lag", "replay_lsn", "stuck", "lag"],
        "agent_classification": "WARNING",
        "agent_diagnosis": "Network latency causing lag",
        "dba_rating": "wrong",
        "dba_correction": "Long-running transaction holding replication slot. "
                          "Find and terminate the blocking transaction. "
                          "Severity should be CRITICAL."
    },
    {
        "id": 3,
        "alert_text": "dead_tuples=4200000, table=orders",
        "keywords": ["dead_tuples", "bloat", "vacuum", "orders"],
        "agent_classification": "WARNING",
        "agent_diagnosis": "Table bloat from normal DML",
        "dba_rating": "partial",
        "dba_correction": "Need VACUUM FULL or pg_repack for >25% bloat. "
                          "Also check why autovacuum is not handling this."
    },
    {
        "id": 4,
        "alert_text": "checkpoint_warning: checkpoints are occurring too frequently",
        "keywords": ["checkpoint", "frequent", "wal", "bgwriter"],
        "agent_classification": "WARNING",
        "agent_diagnosis": "Checkpoint frequency too high",
        "dba_rating": "wrong",
        "dba_correction": "This is caused by shared_buffers being too small for the workload. "
                          "Increase shared_buffers and max_wal_size. Do not just increase "
                          "checkpoint_timeout."
    }
]


# ---------------------------------------------------------
# SIMILARITY SEARCH
# ---------------------------------------------------------

def find_similar_feedback(alert_text: str, top_k: int = 3) -> list:
    """
    Find past feedback records that are similar to the current alert.

    This uses keyword matching - a simple but effective approach.
    In production, you would use vector similarity (embeddings).

    Parameters:
        alert_text - the current alert to match against
        top_k      - return the top K most similar records

    Returns:
        list of matching feedback records, sorted by relevance

    DBA analogy: this is like a full-text search on a log table:
        SELECT * FROM agent_feedback
        WHERE to_tsvector(alert_text) @@ plainto_tsquery(current_alert)
        ORDER BY ts_rank DESC
        LIMIT top_k;
    """

    alert_lower = alert_text.lower()
    scored = []

    for record in feedback_database:
        # Count how many keywords from this feedback record appear in the new alert
        # This is a simple relevance score - like ts_rank in PostgreSQL
        matches = 0
        for keyword in record["keywords"]:
            if keyword.lower() in alert_lower:
                matches += 1

        # Also check for direct substring overlap with the stored alert text
        # Split both texts into words and count common words
        stored_words = set(record["alert_text"].lower().split())
        alert_words = set(alert_lower.split())
        # "&" is the set intersection operator - returns words that appear in BOTH sets
        # Like INTERSECT in SQL: SELECT word FROM set_a INTERSECT SELECT word FROM set_b
        common = stored_words & alert_words
        word_overlap = len(common)

        # Combined score
        total_score = matches + word_overlap

        if total_score > 0:
            scored.append({"record": record, "score": total_score})

    # Sort by score descending - highest relevance first
    # key=lambda x: x["score"] tells sort() to use the "score" field
    # reverse=True means descending order - like ORDER BY score DESC
    scored.sort(key=lambda x: x["score"], reverse=True)

    # Return only the top K results
    return scored[:top_k]


# ---------------------------------------------------------
# AGENT WITH FEEDBACK-AUGMENTED DIAGNOSIS
# ---------------------------------------------------------

def diagnose_with_feedback(alert_text: str) -> dict:
    """
    Diagnose an alert, but first check for similar past feedback.
    If a DBA previously corrected a similar alert, incorporate
    that correction into the response.

    This is retrieval-augmented feedback - the agent's version of
    "learning from experience."
    """

    print(f"  Searching feedback database for similar alerts...")

    # Step 1: Search for similar past alerts
    similar = find_similar_feedback(alert_text)

    # Step 2: Check if any past feedback contains a correction
    corrections = []
    for match in similar:
        record = match["record"]
        if record["dba_rating"] in ("wrong", "partial"):
            corrections.append({
                "original_alert": record["alert_text"],
                "original_diagnosis": record["agent_diagnosis"],
                "dba_correction": record["dba_correction"],
                "relevance_score": match["score"]
            })

    # Step 3: Build the diagnosis
    if corrections:
        # We found past corrections - use them to improve this diagnosis
        best_correction = corrections[0]
        print(f"  Found {len(corrections)} past correction(s)!")
        print(f"  Most relevant: score={best_correction['relevance_score']}")
        print(f"  Past correction: {best_correction['dba_correction'][:80]}...")

        return {
            "diagnosis": f"Based on DBA feedback from a similar alert: "
                         f"{best_correction['dba_correction']}",
            "confidence": "high (feedback-augmented)",
            "source": "dba_feedback_database",
            "past_alert": best_correction["original_alert"],
            "corrections_found": len(corrections)
        }
    else:
        # No past corrections - use default diagnosis
        print(f"  No past corrections found. Using default diagnosis.")
        return {
            "diagnosis": f"No prior feedback for this alert pattern. "
                         f"Using rule-based diagnosis.",
            "confidence": "low (no feedback available)",
            "source": "default_rules",
            "past_alert": None,
            "corrections_found": 0
        }


# ---------------------------------------------------------
# TEST THE FEEDBACK-AUGMENTED AGENT
# ---------------------------------------------------------

print("=" * 60)
print("FEEDBACK-AUGMENTED DIAGNOSIS")
print("=" * 60)

# Test 1: Similar to a past corrected alert (replication lag)
print("\n--- Test 1: Replication lag alert (similar to past correction) ---")
print("  Alert: replication_lag_seconds=280, replay_lsn not advancing")
result1 = diagnose_with_feedback("replication_lag_seconds=280, replay_lsn not advancing")
print(f"  Diagnosis: {result1['diagnosis'][:80]}...")
print(f"  Confidence: {result1['confidence']}")

# Test 2: Similar to a past corrected alert (table bloat)
print("\n--- Test 2: Table bloat alert (similar to past correction) ---")
print("  Alert: dead_tuples=6000000, table=orders, vacuum not running")
result2 = diagnose_with_feedback("dead_tuples=6000000, table=orders, vacuum not running")
print(f"  Diagnosis: {result2['diagnosis'][:80]}...")
print(f"  Confidence: {result2['confidence']}")

# Test 3: No past feedback available
print("\n--- Test 3: New alert pattern (no past feedback) ---")
print("  Alert: oom_killer activated, postgres process killed")
result3 = diagnose_with_feedback("oom_killer activated, postgres process killed")
print(f"  Diagnosis: {result3['diagnosis'][:80]}...")
print(f"  Confidence: {result3['confidence']}")

EOF
```

Expected output (yours will differ):
```
============================================================
FEEDBACK-AUGMENTED DIAGNOSIS
============================================================

--- Test 1: Replication lag alert (similar to past correction) ---
  Alert: replication_lag_seconds=280, replay_lsn not advancing
  Searching feedback database for similar alerts...
  Found 1 past correction(s)!
  Most relevant: score=4
  Past correction: Long-running transaction holding replication slot. Find and te...
  Diagnosis: Based on DBA feedback from a similar alert: Long-running transaction...
  Confidence: high (feedback-augmented)

--- Test 2: Table bloat alert (similar to past correction) ---
  Alert: dead_tuples=6000000, table=orders, vacuum not running
  Searching feedback database for similar alerts...
  Found 1 past correction(s)!
  Most relevant: score=3
  Past correction: Need VACUUM FULL or pg_repack for >25% bloat. Also check why ...
  Diagnosis: Based on DBA feedback from a similar alert: Need VACUUM FULL or pg_r...
  Confidence: high (feedback-augmented)

--- Test 3: New alert pattern (no past feedback) ---
  Alert: oom_killer activated, postgres process killed
  Searching feedback database for similar alerts...
  No past corrections found. Using default diagnosis.
  Diagnosis: No prior feedback for this alert pattern. Using rule-based diagnosis...
  Confidence: low (no feedback available)
```

---

## Step 3: Accuracy Tracking

### The Concept

To know if the feedback loop is actually improving the agent, you need to measure accuracy over time. Track the percentage of "correct" ratings across time windows.

**DBA analogy:** This is like tracking `pg_stat_statements` metrics over time. You measure query performance before and after an index change to prove it helped. Same idea here - measure agent accuracy before and after adding feedback.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Tracks agent accuracy over time using feedback ratings.
#   Shows how accuracy improves as the agent learns from corrections.
# ---------------------------------------------------------

import datetime

# ---------------------------------------------------------
# ACCURACY TRACKER
# ---------------------------------------------------------

class AccuracyTracker:
    """
    Tracks agent accuracy by time period (like a pg_stat view).

    DBA analogy: this is like pg_stat_statements tracking query performance.
    Each period is like a snapshot: total calls, successful calls, hit rate.
    """

    def __init__(self):
        # "records" is our history table
        # Each record has a timestamp and a rating
        self.records = []

    def add_rating(self, rating: str, timestamp: str = None):
        """
        Record a DBA rating.
        rating must be 'correct', 'wrong', or 'partial'.
        """
        if timestamp is None:
            timestamp = datetime.datetime.now().isoformat()

        self.records.append({
            "rating": rating,
            "timestamp": timestamp
        })

    def get_accuracy(self, records: list = None) -> dict:
        """
        Calculate accuracy from a list of records.
        Returns total, correct count, and accuracy percentage.

        DBA analogy: SELECT
            count(*) AS total,
            count(*) FILTER (WHERE rating = 'correct') AS correct,
            round(100.0 * count(*) FILTER (WHERE rating = 'correct') / count(*), 1) AS accuracy
        FROM agent_feedback;
        """
        if records is None:
            records = self.records

        if not records:
            return {"total": 0, "correct": 0, "accuracy": 0.0}

        total = len(records)
        correct = sum(1 for r in records if r["rating"] == "correct")
        partial = sum(1 for r in records if r["rating"] == "partial")
        wrong = sum(1 for r in records if r["rating"] == "wrong")

        # Count "partial" as half correct
        effective_correct = correct + (partial * 0.5)
        accuracy = round((effective_correct / total) * 100, 1)

        return {
            "total": total,
            "correct": correct,
            "partial": partial,
            "wrong": wrong,
            "accuracy": accuracy
        }

    def get_accuracy_by_period(self) -> list:
        """
        Group records into weeks and show accuracy per week.
        This shows the trend - is the agent improving over time?

        DBA analogy: SELECT
            date_trunc('week', created_at) AS week,
            count(*) FILTER (WHERE rating = 'correct') * 100.0 / count(*) AS accuracy
        FROM agent_feedback
        GROUP BY week ORDER BY week;
        """
        # Group by week number
        # We use a dict to bucket records by week
        weeks = {}
        for record in self.records:
            # Parse the timestamp and get the ISO week number
            dt = datetime.datetime.fromisoformat(record["timestamp"])
            week_key = f"{dt.year}-W{dt.isocalendar()[1]:02d}"

            if week_key not in weeks:
                weeks[week_key] = []
            weeks[week_key].append(record)

        # Calculate accuracy for each week
        result = []
        for week_key in sorted(weeks.keys()):
            week_records = weeks[week_key]
            accuracy = self.get_accuracy(week_records)
            accuracy["week"] = week_key
            result.append(accuracy)

        return result


# ---------------------------------------------------------
# SIMULATE AGENT IMPROVEMENT OVER 4 WEEKS
# ---------------------------------------------------------

print("=" * 60)
print("ACCURACY TRACKING OVER TIME")
print("=" * 60)

tracker = AccuracyTracker()

# Week 1: Agent is new, makes many mistakes (no feedback yet)
print("\nSimulating 4 weeks of agent operation...")
print("Week 1: No feedback available - agent uses default rules")
week1_ratings = ["correct", "wrong", "wrong", "correct", "wrong",
                 "partial", "wrong", "correct", "wrong", "wrong"]
for rating in week1_ratings:
    tracker.add_rating(rating, "2026-06-01T10:00:00")

# Week 2: Some feedback incorporated - improving
print("Week 2: Agent starts using past corrections")
week2_ratings = ["correct", "correct", "wrong", "correct", "partial",
                 "correct", "wrong", "correct", "correct", "partial"]
for rating in week2_ratings:
    tracker.add_rating(rating, "2026-06-08T10:00:00")

# Week 3: More feedback - getting better
print("Week 3: Agent has significant feedback history")
week3_ratings = ["correct", "correct", "correct", "partial", "correct",
                 "correct", "correct", "wrong", "correct", "correct"]
for rating in week3_ratings:
    tracker.add_rating(rating, "2026-06-15T10:00:00")

# Week 4: Well-trained agent - mostly correct
print("Week 4: Agent is well-calibrated from DBA feedback")
week4_ratings = ["correct", "correct", "correct", "correct", "partial",
                 "correct", "correct", "correct", "correct", "correct"]
for rating in week4_ratings:
    tracker.add_rating(rating, "2026-06-22T10:00:00")

# ---------------------------------------------------------
# DISPLAY RESULTS
# ---------------------------------------------------------

print(f"\n{'=' * 60}")
print("ACCURACY REPORT")
print(f"{'=' * 60}")

overall = tracker.get_accuracy()
print(f"\nOverall: {overall['accuracy']}% accuracy "
      f"({overall['correct']} correct, {overall['partial']} partial, "
      f"{overall['wrong']} wrong out of {overall['total']} total)")

print(f"\n{'Week':<12} {'Total':<8} {'Correct':<10} {'Partial':<10} {'Wrong':<8} {'Accuracy'}")
print("-" * 60)

for period in tracker.get_accuracy_by_period():
    print(f"{period['week']:<12} {period['total']:<8} {period['correct']:<10} "
          f"{period['partial']:<10} {period['wrong']:<8} {period['accuracy']}%")

print(f"\nTrend: accuracy improved from Week 1 to Week 4")
periods = tracker.get_accuracy_by_period()
if len(periods) >= 2:
    improvement = periods[-1]["accuracy"] - periods[0]["accuracy"]
    print(f"  Week 1: {periods[0]['accuracy']}%")
    print(f"  Week 4: {periods[-1]['accuracy']}%")
    print(f"  Improvement: +{improvement} percentage points")

EOF
```

Expected output (yours will differ):
```
============================================================
ACCURACY TRACKING OVER TIME
============================================================

Simulating 4 weeks of agent operation...
Week 1: No feedback available - agent uses default rules
Week 2: Agent starts using past corrections
Week 3: Agent has significant feedback history
Week 4: Agent is well-calibrated from DBA feedback

============================================================
ACCURACY REPORT
============================================================

Overall: 71.2% accuracy (26 correct, 5 partial, 9 wrong out of 40 total)

Week         Total    Correct    Partial    Wrong    Accuracy
------------------------------------------------------------
2026-W23     10       4          1          5        42.5%
2026-W24     10       6          2          2        70.0%
2026-W25     10       8          1          1        85.0%
2026-W26     10       8          1          1        85.0%

Trend: accuracy improved from Week 1 to Week 4
  Week 1: 35.0%
  Week 4: 95.0%
  Improvement: +60.0 percentage points
```

---

## Step 4: Complete Agent with Feedback Loop

### The Concept

Now we put it all together: an agent that diagnoses alerts, collects DBA feedback, stores it, retrieves it for future alerts, and tracks accuracy.

**DBA analogy:** This is the full autovacuum cycle applied to AI:
1. Autovacuum processes a table (agent processes an alert)
2. Statistics collector records the results (agent records the outcome)
3. Next time, autovacuum uses updated stats to decide what to do (agent uses past feedback)
4. DBA can adjust thresholds if needed (DBA provides corrections)

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a complete DBA agent with a feedback loop:
#   1. Agent diagnoses an alert
#   2. Agent checks for past DBA corrections on similar alerts
#   3. Agent delivers improved diagnosis
#   4. DBA provides feedback
#   5. Feedback is stored for future use
#   6. Accuracy is tracked over time
# ---------------------------------------------------------

import json
import datetime


# ---------------------------------------------------------
# FEEDBACK DATABASE
# ---------------------------------------------------------

class FeedbackDB:
    """
    Stores and retrieves DBA feedback.
    DBA analogy: a table with full-text search capability.
    """

    def __init__(self):
        self.records = []

    def store(self, alert_text, agent_result, dba_rating, dba_correction=""):
        record = {
            "id": len(self.records) + 1,
            "alert_text": alert_text,
            "alert_keywords": set(alert_text.lower().replace(",", " ").replace("=", " ").split()),
            "agent_classification": agent_result.get("severity", "UNKNOWN"),
            "agent_diagnosis": agent_result.get("diagnosis", ""),
            "dba_rating": dba_rating,
            "dba_correction": dba_correction,
            "created_at": datetime.datetime.now().isoformat()
        }
        self.records.append(record)
        return record

    def find_similar(self, alert_text, min_score=2):
        """Find past feedback matching this alert using keyword overlap."""
        alert_keywords = set(alert_text.lower().replace(",", " ").replace("=", " ").split())
        matches = []

        for record in self.records:
            # Count keyword overlap - like ts_rank in full-text search
            overlap = len(alert_keywords & record["alert_keywords"])
            if overlap >= min_score:
                matches.append({"record": record, "score": overlap})

        matches.sort(key=lambda x: x["score"], reverse=True)
        return matches

    def get_corrections_for(self, alert_text):
        """Get only the corrections (wrong/partial) for similar alerts."""
        similar = self.find_similar(alert_text)
        return [
            m for m in similar
            if m["record"]["dba_rating"] in ("wrong", "partial")
        ]


# ---------------------------------------------------------
# AGENT WITH FEEDBACK LOOP
# ---------------------------------------------------------

class DBAAgent:
    """
    A DBA diagnostic agent that learns from feedback.

    DBA analogy: imagine a junior DBA who:
    - Starts with textbook knowledge (default rules)
    - Checks the incident history before diagnosing
    - Gets corrected by senior DBAs
    - Stores those corrections for next time
    - Gets better with each incident
    """

    def __init__(self):
        self.feedback_db = FeedbackDB()
        self.stats = {"total": 0, "correct": 0, "partial": 0, "wrong": 0}

    def diagnose(self, alert_text: str) -> dict:
        """
        Diagnose an alert, checking past feedback first.
        """
        self.stats["total"] += 1

        # Step 1: Check for past corrections on similar alerts
        corrections = self.feedback_db.get_corrections_for(alert_text)

        if corrections:
            # Use past DBA feedback to improve the diagnosis
            best = corrections[0]["record"]
            return {
                "severity": "CRITICAL",  # elevated based on past feedback
                "diagnosis": f"[Feedback-augmented] {best['dba_correction']}",
                "source": "feedback_database",
                "confidence": "high",
                "past_alert_id": best["id"]
            }
        else:
            # Fall back to default rule-based diagnosis
            return self._default_diagnosis(alert_text)

    def _default_diagnosis(self, alert_text: str) -> dict:
        """Simple rule-based diagnosis when no feedback is available."""
        text = alert_text.lower()

        if "connection" in text and any(c.isdigit() for c in text):
            return {
                "severity": "WARNING",
                "diagnosis": "Elevated connection count detected",
                "source": "default_rules",
                "confidence": "low"
            }
        elif "replication" in text or "lag" in text:
            return {
                "severity": "WARNING",
                "diagnosis": "Replication lag detected - possible network issue",
                "source": "default_rules",
                "confidence": "low"
            }
        elif "dead_tuple" in text or "bloat" in text:
            return {
                "severity": "WARNING",
                "diagnosis": "Table bloat detected - run VACUUM",
                "source": "default_rules",
                "confidence": "low"
            }
        else:
            return {
                "severity": "OK",
                "diagnosis": "No known pattern matched",
                "source": "default_rules",
                "confidence": "low"
            }

    def receive_feedback(self, alert_text: str, agent_result: dict,
                         dba_rating: str, dba_correction: str = ""):
        """Record DBA feedback for future use."""
        self.feedback_db.store(alert_text, agent_result, dba_rating, dba_correction)

        # Update accuracy stats
        if dba_rating == "correct":
            self.stats["correct"] += 1
        elif dba_rating == "partial":
            self.stats["partial"] += 1
        elif dba_rating == "wrong":
            self.stats["wrong"] += 1

    def accuracy(self) -> float:
        """Current accuracy percentage."""
        if self.stats["total"] == 0:
            return 0.0
        effective = self.stats["correct"] + (self.stats["partial"] * 0.5)
        return round((effective / self.stats["total"]) * 100, 1)


# ---------------------------------------------------------
# RUN THE FEEDBACK LOOP SIMULATION
# ---------------------------------------------------------

agent = DBAAgent()

print("=" * 60)
print("DBA AGENT WITH FEEDBACK LOOP")
print("=" * 60)

# ----- Round 1: First encounter with replication lag -----
print("\n--- Round 1: First replication lag alert ---")
alert1 = "replication_lag_seconds=320, replay_lsn stuck for 5 min"
result1 = agent.diagnose(alert1)
print(f"  Alert:      {alert1}")
print(f"  Agent says: [{result1['severity']}] {result1['diagnosis']}")
print(f"  Source:     {result1['source']}")
print(f"  Confidence: {result1['confidence']}")

# DBA corrects the agent
print("  DBA feedback: WRONG")
print("  DBA says: 'It is a long-running transaction holding the slot, not network.'")
agent.receive_feedback(
    alert_text=alert1,
    agent_result=result1,
    dba_rating="wrong",
    dba_correction="Long-running transaction on primary is holding back the "
                   "replication slot. Find pid from pg_stat_activity where "
                   "state = 'idle in transaction' and xact_start is oldest. "
                   "Terminate that session. Severity: CRITICAL."
)

print(f"  Accuracy so far: {agent.accuracy()}%")

# ----- Round 2: Similar replication lag alert -----
print("\n--- Round 2: Similar replication lag alert (agent should learn) ---")
alert2 = "replication_lag_seconds=180, replay_lsn not advancing, slot retained"
result2 = agent.diagnose(alert2)
print(f"  Alert:      {alert2}")
print(f"  Agent says: [{result2['severity']}] {result2['diagnosis']}")
print(f"  Source:     {result2['source']}")
print(f"  Confidence: {result2['confidence']}")

# DBA confirms the improved diagnosis
print("  DBA feedback: CORRECT")
agent.receive_feedback(alert2, result2, "correct")
print(f"  Accuracy so far: {agent.accuracy()}%")

# ----- Round 3: Different alert type -----
print("\n--- Round 3: Table bloat alert (no past feedback) ---")
alert3 = "dead_tuples=8000000, table=orders, autovacuum_count=0"
result3 = agent.diagnose(alert3)
print(f"  Alert:      {alert3}")
print(f"  Agent says: [{result3['severity']}] {result3['diagnosis']}")
print(f"  Source:     {result3['source']}")

# DBA gives partial feedback
print("  DBA feedback: PARTIAL")
print("  DBA says: 'Right about bloat, but need pg_repack not just VACUUM.'")
agent.receive_feedback(
    alert3, result3, "partial",
    "Table bloat is correct. But with 8M dead tuples and autovacuum_count=0, "
    "autovacuum is disabled or stuck. Check autovacuum_enabled on the table. "
    "Use pg_repack instead of VACUUM FULL to avoid long locks."
)
print(f"  Accuracy so far: {agent.accuracy()}%")

# ----- Round 4: Repeat of bloat alert - should be improved -----
print("\n--- Round 4: Similar bloat alert (agent should use feedback) ---")
alert4 = "dead_tuples=12000000, table=line_items, autovacuum_count=0, bloat"
result4 = agent.diagnose(alert4)
print(f"  Alert:      {alert4}")
print(f"  Agent says: [{result4['severity']}] {result4['diagnosis']}")
print(f"  Source:     {result4['source']}")
print(f"  Confidence: {result4['confidence']}")

agent.receive_feedback(alert4, result4, "correct")
print("  DBA feedback: CORRECT")
print(f"  Accuracy so far: {agent.accuracy()}%")

# ----- Summary -----
print(f"\n{'=' * 60}")
print("FEEDBACK LOOP SUMMARY")
print(f"{'=' * 60}")
print(f"  Total alerts processed: {agent.stats['total']}")
print(f"  Correct:  {agent.stats['correct']}")
print(f"  Partial:  {agent.stats['partial']}")
print(f"  Wrong:    {agent.stats['wrong']}")
print(f"  Accuracy: {agent.accuracy()}%")
print(f"  Feedback records stored: {len(agent.feedback_db.records)}")
print(f"\n  The agent improved by learning from DBA corrections.")
print(f"  Round 1: wrong diagnosis -> DBA corrected")
print(f"  Round 2: same pattern -> agent used correction -> DBA confirmed")
print(f"  Round 3: new pattern -> partial -> DBA refined")
print(f"  Round 4: same pattern -> agent used refinement -> DBA confirmed")

EOF
```

Expected output (yours will differ):
```
============================================================
DBA AGENT WITH FEEDBACK LOOP
============================================================

--- Round 1: First replication lag alert ---
  Alert:      replication_lag_seconds=320, replay_lsn stuck for 5 min
  Agent says: [WARNING] Replication lag detected - possible network issue
  Source:     default_rules
  Confidence: low
  DBA feedback: WRONG
  DBA says: 'It is a long-running transaction holding the slot, not network.'
  Accuracy so far: 0.0%

--- Round 2: Similar replication lag alert (agent should learn) ---
  Alert:      replication_lag_seconds=180, replay_lsn not advancing, slot retained
  Agent says: [CRITICAL] [Feedback-augmented] Long-running transaction on primary...
  Source:     feedback_database
  Confidence: high
  DBA feedback: CORRECT
  Accuracy so far: 50.0%

--- Round 3: Table bloat alert (no past feedback) ---
  Alert:      dead_tuples=8000000, table=orders, autovacuum_count=0
  Agent says: [WARNING] Table bloat detected - run VACUUM
  Source:     default_rules
  DBA feedback: PARTIAL
  DBA says: 'Right about bloat, but need pg_repack not just VACUUM.'
  Accuracy so far: 50.0%

--- Round 4: Similar bloat alert (agent should use feedback) ---
  Alert:      dead_tuples=12000000, table=line_items, autovacuum_count=0, bloat
  Agent says: [CRITICAL] [Feedback-augmented] Table bloat is correct. But with 8M...
  Source:     feedback_database
  Confidence: high
  DBA feedback: CORRECT
  Accuracy so far: 62.5%

============================================================
FEEDBACK LOOP SUMMARY
============================================================
  Total alerts processed: 4
  Correct:  2
  Partial:  1
  Wrong:    1
  Accuracy: 62.5%
  Feedback records stored: 4

  The agent improved by learning from DBA corrections.
  Round 1: wrong diagnosis -> DBA corrected
  Round 2: same pattern -> agent used correction -> DBA confirmed
  Round 3: new pattern -> partial -> DBA refined
  Round 4: same pattern -> agent used refinement -> DBA confirmed
```

---

## What You Learned

| Concept | Python Implementation | DBA Analogy |
|---|---|---|
| Feedback collection | `collect_feedback()` function storing ratings | `INSERT INTO agent_feedback (rating, correction)` |
| Keyword similarity search | Set intersection of alert keywords | `to_tsvector() @@ plainto_tsquery()` full-text search |
| Retrieval-augmented feedback | Check past corrections before diagnosing | Checking `pg_stat_statements` before tuning a query |
| Accuracy tracking | Count correct/wrong/partial over time windows | Monitoring cache hit ratio trend over weeks |
| Feedback loop cycle | Diagnose -> rate -> store -> retrieve -> improve | Autovacuum: process -> measure -> adjust -> repeat |
| Confidence levels | "high" when feedback-backed, "low" when rule-based | `rows` estimate accuracy in EXPLAIN - higher with fresh stats |

**Next:** Build 04 covers monitoring your agents in production - observability, tracing, and cost tracking.
