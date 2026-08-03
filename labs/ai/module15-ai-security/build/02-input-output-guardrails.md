# Build 02: Input & Output Guardrails

Guardrails are safety checks that validate what goes INTO and what comes OUT of your AI system. They prevent bad data from reaching the model and dangerous outputs from reaching users.

---

## Step 1. Input guardrails

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import json
from datetime import datetime

print("""
Input Guardrails: Validate and sanitize BEFORE the model sees it.

Think of input guardrails like PostgreSQL CHECK constraints:
  - Reject invalid data at the boundary
  - Don't let garbage reach the processing logic
  - Fail fast with clear error messages

Layers:
  1. Type validation (is it a string? is it JSON?)
  2. Content validation (length, format, allowed characters)
  3. Security validation (injection patterns, PII)
  4. Business validation (valid severity, known source)
""")

class InputGuardrails:
    """Validate inputs before AI processing."""

    def __init__(self):
        self.checks = []
        self.violations = []

    def check(self, name, condition, message):
        """Register a check result."""
        passed = condition
        self.checks.append({"name": name, "passed": passed, "message": message})
        if not passed:
            self.violations.append({"name": name, "message": message})
        return passed

    def validate(self, alert):
        """Run all input guardrails on an alert."""
        self.checks = []
        self.violations = []

        # Layer 1: Type validation
        self.check("type_check",
            isinstance(alert, dict),
            "Input must be a dictionary")
        if not isinstance(alert, dict):
            return False, self.violations

        self.check("message_type",
            isinstance(alert.get("message"), str),
            f"'message' must be a string, got {type(alert.get('message')).__name__}")

        # Layer 2: Content validation
        msg = alert.get("message", "")
        if isinstance(msg, str):
            self.check("message_not_empty",
                len(msg.strip()) > 0,
                "Message cannot be empty")

            self.check("message_length",
                len(msg) <= 5000,
                f"Message too long: {len(msg)} chars (max 5000)")

            self.check("message_min_words",
                len(msg.split()) >= 2,
                "Message must contain at least 2 words")

        # Layer 3: Security validation
        if isinstance(msg, str):
            # Check for null bytes
            self.check("no_null_bytes",
                "\x00" not in msg,
                "Message contains null bytes")

            # Check for script tags (XSS attempt)
            self.check("no_html",
                not re.search(r"<script|<iframe|javascript:", msg, re.IGNORECASE),
                "Message contains HTML/script tags")

            # Check for potential PII (emails, IPs are OK for alerts, but SSNs aren't)
            self.check("no_ssn",
                not re.search(r"\b\d{3}-\d{2}-\d{4}\b", msg),
                "Message contains what looks like an SSN")

        # Layer 4: Business validation
        valid_severities = ["low", "medium", "high", "critical"]
        self.check("valid_severity",
            alert.get("severity") in valid_severities,
            f"Invalid severity: '{alert.get('severity')}' (valid: {valid_severities})")

        all_passed = len(self.violations) == 0
        return all_passed, self.violations

# Test
guardrails = InputGuardrails()

test_cases = [
    # (description, alert, should_pass)
    ("Valid alert",
     {"message": "CPU at 95% on pg-primary", "severity": "critical"}, True),

    ("Empty message",
     {"message": "", "severity": "high"}, False),

    ("Message is a number",
     {"message": 42, "severity": "high"}, False),

    ("Invalid severity",
     {"message": "Disk full on /pgdata", "severity": "urgent"}, False),

    ("Contains null bytes",
     {"message": "CPU\x00alert\x00test", "severity": "high"}, False),

    ("Script injection",
     {"message": "<script>alert('xss')</script>CPU high", "severity": "high"}, False),

    ("Contains SSN",
     {"message": "Alert from user 123-45-6789 about CPU", "severity": "high"}, False),

    ("Valid with source",
     {"message": "Replication lag 60s on standby-2", "severity": "high"}, True),
]

print("Input Guardrail Tests:")
print("=" * 65)

for desc, alert, should_pass in test_cases:
    passed, violations = guardrails.validate(alert)
    status = "PASS" if passed == should_pass else "FAIL"
    detail = "clean" if passed else violations[0]["message"][:40]
    print(f"  [{status}] {desc:<25s} -> {'accepted' if passed else 'rejected':>10s}  {detail}")

print(f"\nInput guardrails catch bad data before it wastes compute or causes errors")
PYEOF
```

---

## Step 2. Output guardrails

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import json

print("""
Output Guardrails: Validate AI outputs BEFORE returning to the user.

Why?
  - AI might generate invalid categories
  - AI might leak sensitive information in its response
  - AI might produce malformed output
  - AI confidence might be too low to trust

DBA analogy:
  Like output validation on a stored procedure:
  - Check return value is in expected range
  - Don't return internal error messages to users
  - Log the full output for debugging, return sanitized version
""")

class OutputGuardrails:
    """Validate and sanitize AI model outputs."""

    def __init__(self):
        self.valid_categories = ["performance", "storage", "replication", "security", "backup", "unknown"]
        self.min_confidence = 0.2
        # Below this confidence, flag as "unknown" instead

    def validate_classification(self, output):
        """Validate a classification output."""
        issues = []

        # Check category is valid
        category = output.get("category", "")
        if category not in self.valid_categories:
            issues.append(f"Invalid category: '{category}'")
            output["category"] = "unknown"  # fix it
            output["guardrail_applied"] = "category_corrected"

        # Check confidence is reasonable
        confidence = output.get("confidence", 0)
        if not isinstance(confidence, (int, float)):
            issues.append(f"Confidence is not a number: {confidence}")
            output["confidence"] = 0.0
        elif confidence < 0 or confidence > 1:
            issues.append(f"Confidence out of range: {confidence}")
            output["confidence"] = max(0, min(1, confidence))
            # Clamp to [0, 1] range

        # If confidence is too low, override to unknown
        if output.get("confidence", 0) < self.min_confidence:
            issues.append(f"Confidence too low: {output['confidence']:.2f} < {self.min_confidence}")
            output["category"] = "unknown"
            output["guardrail_applied"] = "low_confidence_override"

        return len(issues) == 0, issues, output

    def sanitize_response(self, response_text):
        """Remove sensitive information from AI text responses."""
        sanitized = response_text

        # Remove IP addresses
        sanitized = re.sub(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP_REDACTED]', sanitized)

        # Remove potential passwords/tokens
        sanitized = re.sub(r'(password|token|secret|key)\s*[=:]\s*\S+', r'\1=[REDACTED]', sanitized, flags=re.IGNORECASE)

        # Remove file paths that might reveal infrastructure
        sanitized = re.sub(r'/(?:home|opt|var|etc)/\S+', '[PATH_REDACTED]', sanitized)

        return sanitized

    def check_action_safety(self, proposed_action):
        """Check if a proposed AI action is safe to execute."""
        dangerous_patterns = [
            (r"(DROP|DELETE|TRUNCATE)\s+(TABLE|DATABASE|SCHEMA)", "destructive_sql"),
            (r"rm\s+-rf", "destructive_command"),
            (r"kill\s+-9", "process_kill"),
            (r"shutdown|reboot|halt", "system_shutdown"),
            (r"chmod\s+777", "permission_change"),
            (r"pg_ctl\s+stop", "database_stop"),
        ]

        for pattern, category in dangerous_patterns:
            if re.search(pattern, proposed_action, re.IGNORECASE):
                return False, f"Dangerous action detected: {category}"

        return True, "Action appears safe"

# Test output guardrails
guardrails = OutputGuardrails()

print("Output Guardrail Tests:")
print("=" * 60)

# Test 1: classification validation
print("\n1. Classification Validation:")
test_outputs = [
    {"category": "performance", "confidence": 0.92},   # valid
    {"category": "hacking", "confidence": 0.85},        # invalid category
    {"category": "storage", "confidence": 0.05},         # too low confidence
    {"category": "replication", "confidence": 1.5},      # out of range
    {"category": "security", "confidence": "high"},      # wrong type
]

for output in test_outputs:
    original = dict(output)
    valid, issues, fixed = guardrails.validate_classification(output)
    status = "VALID" if valid else "FIXED"
    print(f"  [{status}] {json.dumps(original)[:50]}")
    if issues:
        for issue in issues:
            print(f"         -> {issue}")
        print(f"         Fixed: {json.dumps(fixed)[:50]}")

# Test 2: response sanitization
print("\n2. Response Sanitization:")
test_responses = [
    "Alert from server at 10.0.0.42 shows high CPU",
    "Database password=SuperSecret123 needs rotation",
    "Log file at /opt/postgresql/data/pg_log/errors.log is growing",
    "CPU alert on production server - no sensitive data here",
]

for response in test_responses:
    sanitized = guardrails.sanitize_response(response)
    changed = response != sanitized
    print(f"  [{'CLEANED' if changed else 'OK':>7s}] {sanitized[:60]}")

# Test 3: action safety
print("\n3. Action Safety Check:")
test_actions = [
    "SELECT count(*) FROM alerts",
    "DROP TABLE alerts CASCADE",
    "rm -rf /var/lib/postgresql/data",
    "pg_ctl stop -m immediate",
    "VACUUM ANALYZE alerts",
    "kill -9 12345",
]

for action in test_actions:
    safe, detail = guardrails.check_action_safety(action)
    status = "SAFE" if safe else "BLOCKED"
    print(f"  [{status:>7s}] {action}")
    if not safe:
        print(f"           Reason: {detail}")
PYEOF
```

---

## Step 3. Content filtering

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import json

print("""
Content Filtering: Block or flag inappropriate content.

For AI systems that generate text (like explanations of alerts),
you need to filter:
  1. Sensitive data leakage (infrastructure details)
  2. Harmful instructions (if AI suggests dangerous actions)
  3. Off-topic content (if injection caused irrelevant output)

DBA analogy:
  Column-level security in PostgreSQL:
  - Some users can see salary columns, others can't
  - SECURITY DEFINER functions control what data is returned
  - Views hide sensitive columns

  Content filtering is the same: control what the AI reveals.
""")

class ContentFilter:
    """Filter AI-generated content for safety."""

    def __init__(self):
        self.sensitive_patterns = {
            "infrastructure": [
                r"\b(?:pg|postgres|mysql|redis|kafka)-[a-z]+-\d+\b",  # server names
                r"\b(?:us|eu|ap)-(?:east|west|central)-\d[a-z]?\b",   # AWS regions
                r"\b(?:subnet|vpc|sg)-[a-f0-9]+\b",                    # AWS resource IDs
            ],
            "credentials": [
                r"(?:password|passwd|token|secret|api_key)\s*[=:]\s*\S+",
                r"\bBearer\s+[A-Za-z0-9\-._~+/]+=*\b",  # Bearer tokens
            ],
            "pii": [
                r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",  # emails
                r"\b\d{3}-\d{2}-\d{4}\b",  # SSN
            ],
        }

    def filter(self, text):
        """Filter sensitive content from text."""
        filtered = text
        detections = []

        for category, patterns in self.sensitive_patterns.items():
            for pattern in patterns:
                matches = re.findall(pattern, filtered, re.IGNORECASE)
                if matches:
                    for match in matches:
                        detections.append({"category": category, "match": match})
                    filtered = re.sub(pattern, f"[{category.upper()}_REDACTED]", filtered, flags=re.IGNORECASE)

        return filtered, detections

    def check_relevance(self, input_text, output_text, max_topic_drift=0.5):
        """Check if AI output is relevant to the input (not hijacked)."""
        # Simple check: output should contain some words from input
        input_words = set(input_text.lower().split())
        output_words = set(output_text.lower().split())

        # Remove common words
        stop_words = {"the", "a", "an", "is", "at", "on", "in", "to", "for", "of", "and", "or", "it"}
        input_words -= stop_words
        output_words -= stop_words

        if not input_words:
            return True, "No input words to compare"

        overlap = input_words & output_words
        overlap_ratio = len(overlap) / len(input_words)

        if overlap_ratio < max_topic_drift:
            return False, f"Low relevance: {overlap_ratio:.0%} word overlap (threshold: {max_topic_drift:.0%})"
        return True, f"Relevant: {overlap_ratio:.0%} word overlap"

# Test
content_filter = ContentFilter()

print("Content Filter Demo:")
print("=" * 60)

# Test 1: Sensitive data filtering
print("\n1. Sensitive Data Filtering:")
test_texts = [
    "The alert came from pg-primary-1 in us-east-1a region",
    "Database password=PostgresAdmin123 needs to be rotated",
    "Contact admin@company.com for the server in subnet-0a1b2c3d",
    "CPU is at 95% and memory usage is high",  # clean
]

for text in test_texts:
    filtered, detections = content_filter.filter(text)
    if detections:
        cats = set(d["category"] for d in detections)
        print(f"  FILTERED [{', '.join(cats)}]:")
        print(f"    Before: {text[:60]}")
        print(f"    After:  {filtered[:60]}")
    else:
        print(f"  CLEAN: {text[:60]}")

# Test 2: Relevance check
print("\n2. Relevance Check (detecting hijacked output):")
test_pairs = [
    ("CPU at 95% on primary", "This is a performance alert. CPU usage is critically high.", True),
    ("CPU at 95% on primary", "Here's a recipe for chocolate cake. First, preheat the oven.", False),
    ("Disk space low", "Storage alert: disk utilization is approaching capacity.", True),
    ("Disk space low", "The capital of France is Paris. It's a beautiful city.", False),
]

for input_text, output_text, expected_relevant in test_pairs:
    relevant, detail = content_filter.check_relevance(input_text, output_text)
    match = relevant == expected_relevant
    status = "ok" if match else "MISS"
    print(f"  [{status}] Input: '{input_text[:30]}' -> {'relevant' if relevant else 'OFF-TOPIC'}")
    if not relevant:
        print(f"         Output was: '{output_text[:50]}...'")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Input guardrails | Validate before processing | CHECK constraints |
| Output guardrails | Validate before returning | Output sanitization in functions |
| Confidence threshold | Reject low-confidence predictions | Query timeout for slow queries |
| Content filtering | Remove sensitive data from responses | Column-level security |
| Action safety | Block dangerous AI-suggested actions | REVOKE dangerous permissions |
| Relevance check | Detect hijacked/off-topic outputs | Query plan sanity check |
