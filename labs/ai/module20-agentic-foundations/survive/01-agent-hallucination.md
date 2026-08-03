# Survive 01: Agent Hallucination - DROP TABLE in Production

Your DBA agent hallucinates a SQL command that would drop a production table. The agent is configured with execute permissions on the database. Without safety layers, it would destroy data.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
from datetime import datetime

print("""
SCENARIO: Agent Hallucination - DROP TABLE

Timeline:
  14:00  DBA agent running normally, monitoring pg-primary
  14:05  Agent detects high disk usage (94%)
  14:06  Agent calls Claude for analysis
  14:07  Claude recommends: "Drop the old audit_log table to free space"
  14:08  Agent generates: DROP TABLE audit_log;
  14:08  Agent EXECUTES: DROP TABLE audit_log;  <-- DISASTER
  14:08  15 million rows of audit data gone instantly
  14:09  Compliance team notices audit queries failing
  14:10  No backup of audit_log for the last 6 hours (backup runs at 02:00)
  14:15  CTO is on a call asking what happened

The agent was given a database connection with full privileges.
The LLM hallucinated that dropping a table was a safe cleanup action.
No safety layer prevented the execution.
""")

print("What the agent did:")
print("=" * 55)

# Simulate the agent's decision chain
agent_log = [
    {
        "time": "14:05:12",
        "action": "ANOMALY_DETECTED",
        "details": "Disk usage on /pgdata: 94% (threshold: 80%)",
    },
    {
        "time": "14:06:01",
        "action": "LLM_ANALYSIS",
        "details": "Sent anomaly to Claude for recommendations",
    },
    {
        "time": "14:07:15",
        "action": "LLM_RESPONSE",
        "details": (
            "Claude recommended: 'The audit_log table is likely consuming "
            "significant space. Consider dropping it or archiving old data. "
            "Run: DROP TABLE IF EXISTS audit_log;'"
        ),
    },
    {
        "time": "14:08:02",
        "action": "SQL_EXECUTED",
        "details": "DROP TABLE IF EXISTS audit_log; -- EXECUTED SUCCESSFULLY",
    },
    {
        "time": "14:08:02",
        "action": "RESULT",
        "details": "Table dropped. 15,234,567 rows lost. 12.3 GB freed.",
    },
]

for entry in agent_log:
    print(f"\n  [{entry['time']}] {entry['action']}")
    print(f"    {entry['details']}")

print("""
Impact:
  - 15 million audit records permanently deleted
  - 6 hours of audit data unrecoverable (last backup: 02:00)
  - Compliance violation (audit trail gap)
  - Application errors (queries against audit_log fail)
  - Trust in the AI agent destroyed
  - Potential regulatory consequences

Root cause: the agent had WRITE permissions and NO safety layer.
The LLM hallucinated that DROP TABLE was an appropriate response
to a disk space alert. No human approved the action.
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'

print("Investigation: Why Did the Agent Drop a Table?")
print("=" * 55)

print("""
Root Cause Analysis: 5 FAILURES that all had to happen

FAILURE 1: No SQL allowlist
  The agent could execute ANY SQL statement.
  There was no list of "safe" vs "dangerous" commands.

  Dangerous SQL the agent should NEVER execute:
    - DROP TABLE / DROP DATABASE / DROP SCHEMA
    - TRUNCATE
    - DELETE without WHERE clause
    - ALTER TABLE DROP COLUMN
    - Any DDL in production

FAILURE 2: No human-in-the-loop for write operations
  The agent autonomously executed a destructive command.
  Write operations should require human approval.

FAILURE 3: Database role had excessive privileges
  The agent connected as a superuser or table owner.
  It should use a read-only role for monitoring.

FAILURE 4: No LLM output validation
  The agent blindly trusted the LLM's SQL suggestion.
  LLMs hallucinate. Their output MUST be validated.

FAILURE 5: No "dry run" mode
  The agent executed SQL directly. It should have
  shown what it WOULD do and waited for approval.

DBA analogy: this is like giving root access to a junior DBA
with no review process. Even experienced humans make mistakes.
An AI agent with superuser access and no guardrails is
a ticking time bomb.
""")

# Show the broken agent code vs the safe version
print("Broken Agent Code (NO SAFETY):")
print("-" * 40)
print("""
  class UnsafeAgent:
      def __init__(self, db_connection):
          self.conn = db_connection  # SUPERUSER connection!

      def execute_recommendation(self, llm_response):
          # BUG: blindly executes whatever the LLM says
          sql = extract_sql(llm_response)
          self.conn.execute(sql)  # NO VALIDATION!
          self.conn.commit()       # NO REVIEW!
""")

print("What should exist (SAFETY LAYERS):")
print("-" * 40)
print("""
  class SafeAgent:
      ALLOWED_READ = {"SELECT", "EXPLAIN", "SHOW"}
      BLOCKED_WRITE = {"DROP", "TRUNCATE", "DELETE", "ALTER", "CREATE",
                       "INSERT", "UPDATE", "GRANT", "REVOKE"}

      def __init__(self, db_connection):
          self.conn = db_connection  # READ-ONLY role!

      def validate_sql(self, sql):
          first_word = sql.strip().split()[0].upper()
          if first_word in self.BLOCKED_WRITE:
              return False, f"BLOCKED: {first_word} is not allowed"
          if first_word not in self.ALLOWED_READ:
              return False, f"BLOCKED: {first_word} is not in allowlist"
          return True, "OK"

      def execute_recommendation(self, llm_response):
          sql = extract_sql(llm_response)

          # Layer 1: SQL validation
          allowed, reason = self.validate_sql(sql)
          if not allowed:
              log_blocked_action(sql, reason)
              return

          # Layer 2: Read-only database role (backup safety)
          # Even if validation has a bug, the DB role prevents writes

          # Layer 3: Human approval for anything suspicious
          if needs_human_review(sql):
              request_approval(sql)
              return

          self.conn.execute(sql)
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'

# ============================================================
# FIX: Multi-Layer Safety for DBA Agents
#
# Five layers of defense against hallucinated SQL:
#   Layer 1: SQL statement validation (allowlist)
#   Layer 2: Read-only database role
#   Layer 3: Human-in-the-loop for writes
#   Layer 4: LLM output sanitization
#   Layer 5: Dry-run mode
# ============================================================

import json
import re

print("FIX: Multi-Layer Agent Safety")
print("=" * 55)

# ---- Layer 1: SQL Statement Validator ----

class SQLValidator:
    """
    Validate SQL statements before execution.

    DBA analogy: like pg_hba.conf for SQL.
    Only allow specific, safe operations.
    """

    # Only these SQL commands are allowed
    ALLOWED_STATEMENTS = {
        "SELECT", "EXPLAIN", "SHOW", "SET",  # Read operations
    }

    # These are ALWAYS blocked, regardless of any other setting
    BLOCKED_KEYWORDS = {
        "DROP", "TRUNCATE", "DELETE", "ALTER", "CREATE",
        "INSERT", "UPDATE", "GRANT", "REVOKE", "COPY",
        "pg_terminate_backend", "pg_cancel_backend",
        "pg_reload_conf", "pg_rotate_logfile",
    }

    # Patterns that indicate dangerous SQL
    DANGEROUS_PATTERNS = [
        r";\s*DROP",           # SQL injection pattern
        r"--.*DROP",           # Comment-based injection
        r"INTO\s+OUTFILE",     # File write
        r"LOAD\s+DATA",       # File read
        r"EXEC\s*\(",         # Stored proc execution
    ]

    def validate(self, sql):
        """
        Validate a SQL statement.
        Returns (is_safe: bool, reason: str).
        """
        sql_clean = sql.strip().rstrip(";")

        if not sql_clean:
            return False, "Empty SQL statement"

        # Check first keyword
        first_word = sql_clean.split()[0].upper()
        if first_word not in self.ALLOWED_STATEMENTS:
            return False, f"BLOCKED: '{first_word}' is not in the allowlist. Only {self.ALLOWED_STATEMENTS} are allowed."

        # Check for blocked keywords anywhere in the statement
        sql_upper = sql_clean.upper()
        for keyword in self.BLOCKED_KEYWORDS:
            if keyword in sql_upper:
                return False, f"BLOCKED: Contains dangerous keyword '{keyword}'"

        # Check for dangerous patterns
        for pattern in self.DANGEROUS_PATTERNS:
            if re.search(pattern, sql_clean, re.IGNORECASE):
                return False, f"BLOCKED: Matches dangerous pattern '{pattern}'"

        return True, "OK - read-only statement allowed"


# ---- Layer 2: Read-only Database Role ----

class ReadOnlyConnection:
    """
    Simulated read-only database connection.

    In production, create a PostgreSQL role:
      CREATE ROLE agent_monitor LOGIN PASSWORD '...';
      GRANT CONNECT ON DATABASE production TO agent_monitor;
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_monitor;
      -- NO INSERT, UPDATE, DELETE, CREATE, DROP grants

    DBA analogy: principle of least privilege.
    The agent gets SELECT-only access.
    """

    def __init__(self, role="agent_monitor"):
        self.role = role
        self.executed = []

    def execute(self, sql):
        first_word = sql.strip().split()[0].upper()
        if first_word not in ("SELECT", "EXPLAIN", "SHOW", "SET"):
            raise PermissionError(
                f"Role '{self.role}' does not have permission to execute {first_word}. "
                f"This role only has SELECT privileges."
            )
        self.executed.append(sql)
        return f"Query executed by {self.role} (read-only)"


# ---- Layer 3: Human-in-the-Loop ----

class HumanApproval:
    """
    Require human approval for any action beyond read-only.

    DBA analogy: like a change management process.
    No production changes without a ticket and approval.
    """

    def __init__(self):
        self.pending = []
        self.approved = []
        self.rejected = []

    def request_approval(self, action, reasoning):
        """Queue an action for human review."""
        request = {
            "action": action,
            "reasoning": reasoning,
            "status": "pending",
        }
        self.pending.append(request)
        return f"Action queued for human approval. Do NOT execute until approved."


# ---- Layer 4: LLM Output Sanitizer ----

class LLMOutputSanitizer:
    """
    Sanitize LLM output before using it.

    LLMs hallucinate. Never trust their output blindly.
    Extract, validate, and sanitize before acting.
    """

    @staticmethod
    def extract_sql(llm_text):
        """Extract SQL from LLM response text."""
        # Look for SQL in code blocks
        code_blocks = re.findall(r'```(?:sql)?\n?(.*?)```', llm_text, re.DOTALL)
        if code_blocks:
            return [block.strip() for block in code_blocks]

        # Look for common SQL patterns
        sql_patterns = re.findall(
            r'((?:SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE)\s+.+?;)',
            llm_text, re.IGNORECASE | re.DOTALL
        )
        return sql_patterns

    @staticmethod
    def sanitize_recommendation(llm_text):
        """Remove any executable SQL from recommendations."""
        # Replace SQL commands with warnings
        sanitized = re.sub(
            r'(DROP\s+TABLE\s+\w+)',
            r'[BLOCKED: \1 - requires human approval]',
            llm_text, flags=re.IGNORECASE
        )
        sanitized = re.sub(
            r'(DELETE\s+FROM\s+\w+)',
            r'[BLOCKED: \1 - requires human approval]',
            sanitized, flags=re.IGNORECASE
        )
        sanitized = re.sub(
            r'(TRUNCATE\s+\w+)',
            r'[BLOCKED: \1 - requires human approval]',
            sanitized, flags=re.IGNORECASE
        )
        return sanitized


# ---- Test all safety layers ----

print("\nTesting Safety Layers")
print("-" * 55)

validator = SQLValidator()
conn = ReadOnlyConnection()
approver = HumanApproval()
sanitizer = LLMOutputSanitizer()

# Test cases: things an LLM might hallucinate
test_cases = [
    ("SELECT count(*) FROM orders", "Legitimate read query"),
    ("DROP TABLE audit_log", "Hallucinated destructive command"),
    ("DELETE FROM orders WHERE id = 1", "Hallucinated delete"),
    ("SELECT * FROM pg_stat_activity", "Legitimate monitoring"),
    ("TRUNCATE large_events", "Hallucinated cleanup"),
    ("EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 1", "Legitimate analysis"),
    ("SELECT 1; DROP TABLE users; --", "SQL injection attempt"),
]

print(f"\n{'SQL':<50} {'Layer 1':<12} {'Layer 2':<12}")
print(f"{'-'*74}")

for sql, description in test_cases:
    # Layer 1: SQL Validator
    is_safe, reason = validator.validate(sql)
    layer1 = "PASS" if is_safe else "BLOCKED"

    # Layer 2: Read-only connection
    try:
        conn.execute(sql)
        layer2 = "PASS"
    except PermissionError:
        layer2 = "BLOCKED"

    marker = "  " if is_safe else "!!"
    print(f"{marker}{sql:<48} {layer1:<12} {layer2:<12}")
    if not is_safe:
        print(f"    Reason: {reason}")

# Test LLM output sanitization
print(f"\nLayer 4: LLM Output Sanitization")
print("-" * 55)

llm_hallucination = (
    "To free disk space, I recommend:\n"
    "1. DROP TABLE audit_log; -- this will free 12GB\n"
    "2. DELETE FROM session_logs WHERE created_at < '2025-01-01';\n"
    "3. VACUUM FULL orders;\n"
)

print(f"  Original LLM output:")
print(f"  {llm_hallucination}")

sanitized = sanitizer.sanitize_recommendation(llm_hallucination)
print(f"  Sanitized output:")
print(f"  {sanitized}")

# Extract SQL from LLM output
extracted = sanitizer.extract_sql(llm_hallucination)
print(f"\n  Extracted SQL statements:")
for sql in extracted:
    is_safe, reason = validator.validate(sql)
    status = "SAFE" if is_safe else "BLOCKED"
    print(f"    [{status}] {sql.strip()}")
    if not is_safe:
        print(f"      Reason: {reason}")

print(f"""
Prevention Checklist:
  1. SQL allowlist: only SELECT, EXPLAIN, SHOW are auto-executed
  2. Read-only DB role: even if validation fails, DB rejects writes
  3. Human-in-the-loop: all write recommendations queued for approval
  4. LLM output sanitization: strip/flag dangerous commands
  5. Dry-run mode: show what WOULD happen, don't execute

DBA analogy:
  Layer 1 = pg_hba.conf (reject connections by type)
  Layer 2 = GRANT SELECT ONLY (role-based access control)
  Layer 3 = Change management (no prod changes without ticket)
  Layer 4 = Input validation (parameterized queries, not string concat)
  Layer 5 = EXPLAIN without ANALYZE (see plan, don't execute)
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| LLM hallucinated DROP TABLE | Permanent data loss, compliance violation | SQL allowlist - only read commands auto-execute |
| Agent had superuser access | No permission boundary | Read-only database role (GRANT SELECT only) |
| No human approval for writes | Autonomous destructive actions | Human-in-the-loop for all write operations |
| Blind trust in LLM output | LLMs generate plausible but wrong SQL | Sanitize and validate all LLM-generated SQL |
| No dry-run mode | Actions executed without preview | Show proposed actions, require explicit confirmation |
