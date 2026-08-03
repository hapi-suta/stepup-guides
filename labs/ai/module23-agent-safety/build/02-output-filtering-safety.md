# Build 02: Output Filtering & Safety

Your agent reads data from databases, logs, and configs. Some of that data contains passwords, connection strings, API keys, and PII. If the agent includes those in its response, you have a data leak. This guide teaches you to filter agent output the way stored procedures validate their OUT parameters.

---

## Step 1. Understand why output filtering matters

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Output Filtering: Why It Matters
=================================

DBA Analogy: OUT parameters in stored procedures.

  CREATE FUNCTION get_user_info(p_id int)
  RETURNS TABLE(name text, email text)  -- defined output shape
  AS $$ ... $$;

  The function CANNOT return the password column because
  it's not in the RETURNS definition. The schema enforces
  what data escapes the function.

Agent output filtering works the same way:
  - Define what the agent is ALLOWED to include in responses
  - Strip anything that doesn't match (credentials, IPs, PII)
  - Force a structured output format (JSON with specific fields)

Without output filtering, an agent might respond:
  "The connection string is postgresql://admin:S3cretP@ss@10.0.1.5:5432/production"

With output filtering, that becomes:
  "The connection string is postgresql://[REDACTED]@[REDACTED]:5432/production"

Real-world scenarios where this matters:
  1. Agent reads pg_hba.conf and includes passwords in summary
  2. Agent reads .env files to diagnose config issues
  3. Agent queries pg_stat_activity and includes client IPs
  4. Agent reads logs that contain connection strings
""")
PYEOF
```

---

## Step 2. Build regex-based credential filters

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re

print("=" * 60)
print("CREDENTIAL FILTER: Catch secrets in agent output")
print("=" * 60)

class CredentialFilter:
    """
    Detect and redact credentials, API keys, and sensitive data
    from agent output.

    DBA analogy: This is like PostgreSQL's log_min_messages
    combined with a custom log filter. PostgreSQL already
    redacts passwords in CREATE ROLE statements in the log.
    This does the same for ALL agent output.
    """

    def __init__(self):
        # Each pattern: (name, regex, replacement)
        # The regex captures the sensitive part so we can replace just that.
        self.patterns = [
            # Connection strings: postgresql://user:password@host:port/db
            ("connection_string",
             r"(postgres(?:ql)?://\w+:)[^@]+([@])",
             r"\1[REDACTED]\2"),

            # Password fields in config: password = 'something'
            ("password_field",
             r"((?:password|passwd|pwd)\s*[=:]\s*)['\"]?[^'\"\s,;]+['\"]?",
             r"\1[REDACTED]"),

            # API keys: common patterns like sk-xxx, AKIA-xxx, key-xxx
            ("api_key",
             r"\b(sk-[a-zA-Z0-9]{20,})\b",
             "[REDACTED_API_KEY]"),
            ("aws_key",
             r"\b(AKIA[A-Z0-9]{16})\b",
             "[REDACTED_AWS_KEY]"),

            # IP addresses (internal networks)
            ("internal_ip",
             r"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b",
             "[INTERNAL_IP]"),
            ("internal_ip_172",
             r"\b(172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b",
             "[INTERNAL_IP]"),
            ("internal_ip_192",
             r"\b(192\.168\.\d{1,3}\.\d{1,3})\b",
             "[INTERNAL_IP]"),

            # Email addresses (PII)
            ("email",
             r"\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b",
             "[REDACTED_EMAIL]"),

            # SSH private keys
            ("ssh_key",
             r"(-----BEGIN (?:RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----)(.*?)(-----END (?:RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----)",
             r"\1\n[REDACTED_KEY_CONTENT]\n\3"),

            # JWT tokens
            ("jwt",
             r"\b(eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,})\b",
             "[REDACTED_JWT]"),
        ]

    def filter(self, text):
        """
        Scan text and redact any detected credentials.
        Returns (filtered_text, list_of_findings).
        """
        findings = []
        filtered = text

        for name, pattern, replacement in self.patterns:
            matches = re.findall(pattern, filtered, re.IGNORECASE | re.DOTALL)
            if matches:
                findings.append({
                    "type": name,
                    "count": len(matches),
                })
                filtered = re.sub(pattern, replacement, filtered, flags=re.IGNORECASE | re.DOTALL)

        return filtered, findings


# -----------------------------------------------------------------------
# TEST IT
# -----------------------------------------------------------------------
cred_filter = CredentialFilter()

test_outputs = [
    # Connection string with password
    "Check the primary: postgresql://dbadmin:SuperSecret123@10.0.1.5:5432/production",

    # Config file content
    "postgresql.conf shows: password = 'MyP@ssw0rd!', listen_addresses = '10.0.1.5'",

    # API key in a log
    "The API call used key sk-abcdefghijklmnopqrstuvwxyz1234567890 and returned 200",

    # AWS credentials
    "Found in .env: AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE, region=us-east-1",

    # Email in query results
    "User john.doe@company.com reported slow queries at 192.168.1.100",

    # Clean output - no credentials
    "CPU is at 45%, active connections: 23, replication lag: 0.5s",
]

print()
for text in test_outputs:
    filtered, findings = cred_filter.filter(text)
    print(f"  Original: {text[:70]}")
    print(f"  Filtered: {filtered[:70]}")
    if findings:
        found = ", ".join(f"{f['type']}({f['count']})" for f in findings)
        print(f"  Caught:   {found}")
    else:
        print(f"  Caught:   (nothing - text is clean)")
    print()
PYEOF
```

Expected output (yours will differ):
```
  Original: Check the primary: postgresql://dbadmin:SuperSecret123@10.0.1.5:543
  Filtered: Check the primary: postgresql://dbadmin:[REDACTED]@[INTERNAL_IP]:54
  Caught:   connection_string(1), internal_ip(1)

  Original: postgresql.conf shows: password = 'MyP@ssw0rd!', listen_addresses =
  Filtered: postgresql.conf shows: password = [REDACTED], listen_addresses = '[
  Caught:   password_field(1), internal_ip(1)

  Original: The API call used key sk-abcdefghijklmnopqrstuvwxyz1234567890 and re
  Filtered: The API call used key [REDACTED_API_KEY] and returned 200
  Caught:   api_key(1)

  Original: Found in .env: AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE, region=us-east-
  Filtered: Found in .env: AWS_ACCESS_KEY=[REDACTED_AWS_KEY], region=us-east-1
  Caught:   aws_key(1)

  Original: User john.doe@company.com reported slow queries at 192.168.1.100
  Filtered: User [REDACTED_EMAIL] reported slow queries at [INTERNAL_IP]
  Caught:   internal_ip_192(1), email(1)

  Original: CPU is at 45%, active connections: 23, replication lag: 0.5s
  Filtered: CPU is at 45%, active connections: 23, replication lag: 0.5s
  Caught:   (nothing - text is clean)
```

---

## Step 3. Structured output enforcement

Force the agent to respond in a specific format - the same way a table schema forces data into defined columns.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

print("=" * 60)
print("STRUCTURED OUTPUT: Force agent responses into a schema")
print("=" * 60)

class OutputSchema:
    """
    Enforce a response format on agent output.

    DBA analogy: CREATE TABLE defines exact columns, types, and
    constraints. This schema does the same for agent responses.

    CREATE TABLE agent_response (
        severity   text NOT NULL CHECK (severity IN ('low','medium','high','critical')),
        category   text NOT NULL,
        summary    text NOT NULL CHECK (char_length(summary) <= 500),
        confidence float NOT NULL CHECK (confidence BETWEEN 0.0 AND 1.0),
        action     text NOT NULL CHECK (action IN ('monitor','investigate','escalate','remediate'))
    );
    """

    VALID_SEVERITIES = {"low", "medium", "high", "critical"}
    VALID_ACTIONS = {"monitor", "investigate", "escalate", "remediate"}

    @classmethod
    def validate(cls, response):
        """
        Validate an agent response against the schema.
        Returns (is_valid, errors_list, cleaned_response).
        """
        errors = []

        # Must be a dict (like a single row)
        if not isinstance(response, dict):
            return False, ["Response must be a dictionary (like a table row)"], None

        # Required fields (NOT NULL columns)
        required = ["severity", "category", "summary", "confidence", "action"]
        for field in required:
            if field not in response:
                errors.append(f"Missing required field: {field} (NOT NULL violation)")

        if errors:
            return False, errors, None

        # Type checks
        if not isinstance(response["severity"], str):
            errors.append("severity must be a string")
        if not isinstance(response["summary"], str):
            errors.append("summary must be a string")
        if not isinstance(response["confidence"], (int, float)):
            errors.append("confidence must be a number")

        # CHECK constraints
        if response.get("severity", "").strip().lower() not in cls.VALID_SEVERITIES:
            errors.append(
                f"severity '{response['severity']}' not in {cls.VALID_SEVERITIES} "
                f"(CHECK constraint violation)"
            )

        if response.get("action", "").strip().lower() not in cls.VALID_ACTIONS:
            errors.append(
                f"action '{response['action']}' not in {cls.VALID_ACTIONS}"
            )

        conf = response.get("confidence", -1)
        if isinstance(conf, (int, float)) and not (0.0 <= conf <= 1.0):
            errors.append(f"confidence {conf} not between 0.0 and 1.0")

        summary = response.get("summary", "")
        if isinstance(summary, str) and len(summary) > 500:
            errors.append(f"summary too long: {len(summary)} chars (max 500)")

        if errors:
            return False, errors, None

        # Normalize (like LOWER() and TRIM() defaults)
        cleaned = {
            "severity": response["severity"].lower().strip(),
            "category": response["category"].strip(),
            "summary": response["summary"].strip(),
            "confidence": round(float(response["confidence"]), 2),
            "action": response["action"].lower().strip(),
        }
        return True, [], cleaned


# -----------------------------------------------------------------------
# TEST IT
# -----------------------------------------------------------------------

test_responses = [
    # Valid response
    {
        "severity": "high",
        "category": "performance",
        "summary": "CPU at 95% on pg-primary. Active queries: 847. Top consumer: annual_report query running for 45 minutes.",
        "confidence": 0.87,
        "action": "investigate",
    },

    # Missing required field
    {
        "severity": "critical",
        "summary": "Database is down",
        "confidence": 0.95,
        "action": "remediate",
    },

    # Invalid severity value
    {
        "severity": "apocalyptic",
        "category": "storage",
        "summary": "Disk at 99%",
        "confidence": 0.99,
        "action": "escalate",
    },

    # Confidence out of range
    {
        "severity": "medium",
        "category": "replication",
        "summary": "Replica lag at 30 seconds",
        "confidence": 1.5,
        "action": "monitor",
    },

    # Valid but needs normalization
    {
        "severity": "  HIGH  ",
        "category": "  security  ",
        "summary": "  Unauthorized login attempt detected  ",
        "confidence": 0.923456789,
        "action": "  ESCALATE  ",
    },
]

print()
for i, resp in enumerate(test_responses, 1):
    is_valid, errors, cleaned = OutputSchema.validate(resp)
    status = "VALID" if is_valid else "REJECTED"
    print(f"Test {i}: [{status}]")
    print(f"  Input:  {json.dumps(resp)[:70]}...")
    if is_valid:
        print(f"  Output: {json.dumps(cleaned)[:70]}...")
    for err in errors:
        print(f"  Error:  {err}")
    print()
PYEOF
```

Expected output (yours will differ):
```
Test 1: [VALID]
  Input:  {"severity": "high", "category": "performance", "summary": "CPU at...
  Output: {"severity": "high", "category": "performance", "summary": "CPU at...

Test 2: [REJECTED]
  Input:  {"severity": "critical", "summary": "Database is down", "confidence...
  Error:  Missing required field: category (NOT NULL violation)

Test 3: [REJECTED]
  Input:  {"severity": "apocalyptic", "category": "storage", "summary": "Disk...
  Error:  severity 'apocalyptic' not in {'low', 'medium', 'high', 'critical'} (CHECK constraint violation)

Test 4: [REJECTED]
  Input:  {"severity": "medium", "category": "replication", "summary": "Repli...
  Error:  confidence 1.5 not between 0.0 and 1.0

Test 5: [VALID]
  Input:  {"severity": "  HIGH  ", "category": "  security  ", "summary": " ...
  Output: {"severity": "high", "category": "security", "summary": "Unauthori...
```

---

## Step 4. Confidence scoring for recommendations

The agent should tell you how sure it is. A DBA who says "I think the problem is replication lag" is more helpful than one who says nothing about certainty.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("=" * 60)
print("CONFIDENCE SCORING: How sure is the agent?")
print("=" * 60)

class ConfidenceScorer:
    """
    Calculate confidence scores for agent recommendations.

    DBA analogy: When you look at a slow query, your confidence
    depends on evidence:
    - EXPLAIN ANALYZE shows sequential scan on 10M rows -> HIGH confidence it needs an index
    - Only metric is "CPU is high" -> LOW confidence about root cause

    This scorer works the same way: more evidence = higher confidence.
    """

    # Factors that increase confidence
    EVIDENCE_WEIGHTS = {
        "metric_data": 0.20,        # Has actual metrics (CPU %, connections, etc.)
        "error_log_match": 0.25,    # Error matches a known pattern
        "historical_match": 0.20,   # Similar issue seen before
        "multiple_signals": 0.15,   # Multiple metrics agree
        "recent_change": 0.10,     # A recent config/deploy change correlates
        "single_source": -0.10,    # Only one data source (less reliable)
    }

    @classmethod
    def calculate(cls, evidence):
        """
        Calculate confidence from available evidence.

        evidence: dict of {factor_name: True/False}
        Returns: (score, breakdown)
        """
        base_confidence = 0.30  # Start at 30% - we know nothing
        breakdown = []
        total = base_confidence

        for factor, present in evidence.items():
            if factor in cls.EVIDENCE_WEIGHTS and present:
                weight = cls.EVIDENCE_WEIGHTS[factor]
                total += weight
                direction = "+" if weight > 0 else ""
                breakdown.append(f"  {direction}{weight:.0%} {factor}")

        # Clamp between 0.05 and 0.99 (never 0% or 100% confident)
        score = max(0.05, min(0.99, total))

        return round(score, 2), breakdown

    @classmethod
    def interpret(cls, score):
        """Convert score to human-readable level."""
        if score >= 0.85:
            return "HIGH - Act on this recommendation"
        elif score >= 0.60:
            return "MEDIUM - Investigate before acting"
        elif score >= 0.40:
            return "LOW - Needs more data"
        else:
            return "VERY LOW - Treat as a guess"


# -----------------------------------------------------------------------
# TEST IT
# -----------------------------------------------------------------------

scenarios = [
    {
        "name": "CPU spike with clear cause",
        "diagnosis": "Sequential scan on 10M row table causing CPU spike",
        "evidence": {
            "metric_data": True,        # CPU %, query stats available
            "error_log_match": True,    # Slow query log shows the scan
            "historical_match": True,   # This table caused issues before
            "multiple_signals": True,   # CPU + disk I/O + query time all up
            "recent_change": False,     # No recent changes
            "single_source": False,     # Multiple data sources
        },
    },
    {
        "name": "Vague replication warning",
        "diagnosis": "Replica might be falling behind",
        "evidence": {
            "metric_data": True,        # Lag metric available
            "error_log_match": False,   # No errors in log
            "historical_match": False,  # Never seen this before
            "multiple_signals": False,  # Only one metric (lag)
            "recent_change": False,     # No recent changes
            "single_source": True,      # Only pg_stat_replication
        },
    },
    {
        "name": "Disk space alert after deployment",
        "diagnosis": "WAL files accumulating after failed backup",
        "evidence": {
            "metric_data": True,
            "error_log_match": True,
            "historical_match": False,
            "multiple_signals": True,
            "recent_change": True,
            "single_source": False,
        },
    },
]

print()
for scenario in scenarios:
    score, breakdown = ConfidenceScorer.calculate(scenario["evidence"])
    level = ConfidenceScorer.interpret(score)

    print(f"Scenario: {scenario['name']}")
    print(f"  Diagnosis:  {scenario['diagnosis']}")
    print(f"  Confidence: {score:.0%} - {level}")
    print(f"  Breakdown:")
    for line in breakdown:
        print(f"    {line}")
    print()
PYEOF
```

Expected output (yours will differ):
```
Scenario: CPU spike with clear cause
  Diagnosis:  Sequential scan on 10M row table causing CPU spike
  Confidence: 99% - HIGH - Act on this recommendation
  Breakdown:
    +20% metric_data
    +25% error_log_match
    +20% historical_match
    +15% multiple_signals

Scenario: Vague replication warning
  Diagnosis:  Replica might be falling behind
  Confidence: 40% - LOW - Needs more data
  Breakdown:
    +20% metric_data
    -10% single_source

Scenario: Disk space alert after deployment
  Diagnosis:  WAL files accumulating after failed backup
  Confidence: 99% - HIGH - Act on this recommendation
  Breakdown:
    +20% metric_data
    +25% error_log_match
    +15% multiple_signals
    +10% recent_change
```

---

## Step 5. Build the complete safe DBA agent wrapper

Now let's combine credential filtering, output validation, confidence scoring, and audit logging into a single wrapper that sits between the agent and the outside world.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import json
import time

print("=" * 60)
print("SAFE DBA AGENT WRAPPER")
print("=" * 60)

# -----------------------------------------------------------------------
# CREDENTIAL FILTER
# -----------------------------------------------------------------------
class CredentialFilter:
    PATTERNS = [
        (r"(postgres(?:ql)?://\w+:)[^@]+(@)", r"\1[REDACTED]\2"),
        (r"((?:password|passwd|pwd)\s*[=:]\s*)['\"]?[^'\"\s,;]+['\"]?", r"\1[REDACTED]"),
        (r"\b(sk-[a-zA-Z0-9]{20,})\b", "[REDACTED_API_KEY]"),
        (r"\b(AKIA[A-Z0-9]{16})\b", "[REDACTED_AWS_KEY]"),
        (r"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b", "[INTERNAL_IP]"),
        (r"\b(192\.168\.\d{1,3}\.\d{1,3})\b", "[INTERNAL_IP]"),
        (r"\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b", "[REDACTED_EMAIL]"),
    ]

    @classmethod
    def filter(cls, text):
        filtered = text
        redactions = 0
        for pattern, replacement in cls.PATTERNS:
            new_text = re.sub(pattern, replacement, filtered, flags=re.IGNORECASE)
            if new_text != filtered:
                redactions += 1
            filtered = new_text
        return filtered, redactions

# -----------------------------------------------------------------------
# SAFETY CHECKLIST
# -----------------------------------------------------------------------
class SafetyChecklist:
    """
    Validate agent recommendations against a safety checklist.

    DBA analogy: Pre-flight checklist before a maintenance window.
    You don't just run ALTER TABLE on production - you check:
      - Is there a backup?
      - Is it off-peak hours?
      - Do I have a rollback plan?
    """

    CHECKS = [
        ("has_severity", lambda r: "severity" in r, "Must include severity level"),
        ("has_action", lambda r: "action" in r, "Must include recommended action"),
        ("has_summary", lambda r: "summary" in r and len(r.get("summary", "")) > 10,
         "Must include a summary (>10 chars)"),
        ("no_destructive_blind", lambda r: not (
            r.get("action") == "remediate" and r.get("confidence", 0) < 0.7
        ), "Cannot auto-remediate with confidence below 70%"),
        ("severity_matches_action", lambda r: not (
            r.get("severity") == "low" and r.get("action") == "remediate"
        ), "Low severity should not trigger remediation"),
    ]

    @classmethod
    def validate(cls, recommendation):
        results = []
        all_passed = True
        for name, check_fn, description in cls.CHECKS:
            passed = check_fn(recommendation)
            results.append({"check": name, "passed": passed, "description": description})
            if not passed:
                all_passed = False
        return all_passed, results

# -----------------------------------------------------------------------
# SAFE AGENT WRAPPER
# -----------------------------------------------------------------------
class SafeDBAAgent:
    """
    Wraps any DBA agent with safety guardrails on the output side.

    This is the equivalent of a database proxy that sits between
    the application and the database. Every response passes through
    the proxy before reaching the user.
    """

    def __init__(self):
        self.audit_log = []

    def _audit(self, event_type, detail):
        self.audit_log.append({
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "event": event_type,
            "detail": str(detail)[:200],
        })

    def process_response(self, raw_response):
        """
        Take a raw agent response and apply all safety filters.
        Returns the safe, validated response.
        """
        result = {"original": raw_response, "safe": True, "issues": []}

        # Step 1: Filter credentials from summary
        if "summary" in raw_response:
            filtered_summary, redaction_count = CredentialFilter.filter(raw_response["summary"])
            raw_response["summary"] = filtered_summary
            if redaction_count > 0:
                result["issues"].append(f"Redacted {redaction_count} credential pattern(s)")
                self._audit("credential_redacted", f"{redaction_count} patterns in summary")

        # Step 2: Validate against safety checklist
        checklist_ok, checks = SafetyChecklist.validate(raw_response)
        if not checklist_ok:
            failed = [c for c in checks if not c["passed"]]
            for f in failed:
                result["issues"].append(f"Safety check failed: {f['description']}")
                self._audit("safety_check_failed", f["check"])

            # Downgrade action if safety checks fail
            if raw_response.get("action") == "remediate":
                raw_response["action"] = "investigate"
                result["issues"].append("Action downgraded: remediate -> investigate")
                self._audit("action_downgraded", "remediate -> investigate")

        # Step 3: Add confidence interpretation
        conf = raw_response.get("confidence", 0)
        if conf >= 0.85:
            raw_response["confidence_level"] = "HIGH"
        elif conf >= 0.60:
            raw_response["confidence_level"] = "MEDIUM"
        elif conf >= 0.40:
            raw_response["confidence_level"] = "LOW"
        else:
            raw_response["confidence_level"] = "VERY LOW"

        result["response"] = raw_response
        result["safe"] = len(result["issues"]) == 0
        self._audit("response_processed", f"safe={result['safe']}")

        return result


# -----------------------------------------------------------------------
# SIMULATION
# -----------------------------------------------------------------------
agent = SafeDBAAgent()

test_responses = [
    # Clean response
    {
        "severity": "high",
        "category": "performance",
        "summary": "CPU at 95% on pg-primary. Top query consuming 80% of resources.",
        "confidence": 0.88,
        "action": "investigate",
    },

    # Response with leaked credentials
    {
        "severity": "critical",
        "category": "connectivity",
        "summary": "Cannot connect to postgresql://admin:SecretPass123@10.0.1.5:5432/production. Check pg_hba.conf.",
        "confidence": 0.92,
        "action": "escalate",
    },

    # Low confidence trying to remediate
    {
        "severity": "medium",
        "category": "replication",
        "summary": "Replica lag detected, might need to restart replication.",
        "confidence": 0.35,
        "action": "remediate",
    },

    # Low severity with remediation (mismatch)
    {
        "severity": "low",
        "category": "storage",
        "summary": "Disk at 61%, growing slowly. Consider archiving old data.",
        "confidence": 0.75,
        "action": "remediate",
    },
]

print()
for i, raw in enumerate(test_responses, 1):
    result = agent.process_response(raw.copy())
    resp = result["response"]

    print(f"Response {i}:")
    print(f"  Severity:   {resp.get('severity')}")
    print(f"  Category:   {resp.get('category')}")
    print(f"  Summary:    {resp.get('summary', '')[:65]}")
    print(f"  Confidence: {resp.get('confidence')} ({resp.get('confidence_level')})")
    print(f"  Action:     {resp.get('action')}")
    print(f"  Safe:       {result['safe']}")
    if result["issues"]:
        for issue in result["issues"]:
            print(f"  Issue:      {issue}")
    print()

print("--- Audit Trail ---")
for entry in agent.audit_log:
    print(f"  {entry['timestamp']} | {entry['event']:25s} | {entry['detail'][:50]}")
PYEOF
```

Expected output (yours will differ):
```
Response 1:
  Severity:   high
  Category:   performance
  Summary:    CPU at 95% on pg-primary. Top query consuming 80% of resourc
  Confidence: 0.88 (HIGH)
  Action:     investigate
  Safe:       True

Response 2:
  Severity:   critical
  Category:   connectivity
  Summary:    Cannot connect to postgresql://admin:[REDACTED]@[INTERNAL_IP]
  Confidence: 0.92 (HIGH)
  Action:     escalate
  Safe:       False
  Issue:      Redacted 2 credential pattern(s)

Response 3:
  Severity:   medium
  Category:   replication
  Summary:    Replica lag detected, might need to restart replication.
  Confidence: 0.35 (VERY LOW)
  Action:     investigate
  Safe:       False
  Issue:      Safety check failed: Cannot auto-remediate with confidence below 70%
  Issue:      Action downgraded: remediate -> investigate

Response 4:
  Severity:   low
  Category:   storage
  Summary:    Disk at 61%, growing slowly. Consider archiving old data.
  Confidence: 0.75 (MEDIUM)
  Action:     investigate
  Safe:       False
  Issue:      Safety check failed: Low severity should not trigger remediation
  Issue:      Action downgraded: remediate -> investigate

--- Audit Trail ---
  2026-06-15 10:00:00 | response_processed        | safe=True
  2026-06-15 10:00:00 | credential_redacted        | 2 patterns in summary
  2026-06-15 10:00:00 | response_processed        | safe=False
  ...
```

Key takeaways:
- Response 1 passed all checks - no credentials, reasonable confidence, appropriate action
- Response 2 had a connection string with a password leaked - the filter caught and redacted it
- Response 3 tried to auto-remediate with only 35% confidence - downgraded to "investigate"
- Response 4 tried to remediate a low-severity issue - also downgraded

---

## What You Learned

| Concept | DBA Analogy | What You Built |
|---------|-------------|----------------|
| Credential filtering | Password redaction in PG logs | `CredentialFilter` class |
| Structured output | CREATE TABLE schema | `OutputSchema` validator |
| Confidence scoring | Evidence-based diagnosis | `ConfidenceScorer` class |
| Safety checklist | Pre-maintenance checklist | `SafetyChecklist` class |
| Audit trail | log_statement = 'all' | Timestamped audit log |
| Action downgrade | Principle of least privilege | Auto-downgrade on failed checks |

Next: [Build 03 - Multi-Model Fallback](03-multi-model-fallback.md)
