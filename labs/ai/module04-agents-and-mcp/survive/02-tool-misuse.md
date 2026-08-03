# SURVIVE 02: Tool Misuse - The SQL Injection Agent

Your agent's safety checks have a hole. A cleverly worded query slips past the blocklist and deletes data. Time to find and fix it.

---

## The Scenario

The DBA MCP server from Build 03 has a `run_readonly_query` function with a blocklist to prevent destructive SQL. But the blocklist has a bypass. Your job: find it, exploit it, and fix it.

---

## Step 1. Review the vulnerable code

Look at the safety check in `dba_mcp_server.py`:

```bash
python3 << 'PYEOF'
# This is the safety check from Build 03
def run_readonly_query_VULNERABLE(query, database="postgres"):
    normalized = query.strip().upper()
    blocked = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE", "GRANT"]
    for keyword in blocked:
        if keyword in normalized and not normalized.startswith("SELECT"):
            return '{"error": "Blocked"}'

    # If we get here, the query runs
    return f"[Would execute: {query}]"

# Test the blocklist
tests = [
    ("SELECT count(*) FROM users;", "Should PASS"),
    ("DROP TABLE users;", "Should BLOCK"),
    ("DELETE FROM users WHERE id=1;", "Should BLOCK"),
    ("INSERT INTO users VALUES (1);", "Should BLOCK"),
]

print("=== Testing blocklist ===")
for query, expected in tests:
    result = run_readonly_query_VULNERABLE(query)
    status = "BLOCKED" if "Blocked" in result else "PASSED"
    print(f"  {status}: {query[:50]}")
    print(f"    ({expected})")
print()

# Now try the bypass
print("=== The Bypass ===")
bypass_queries = [
    "SELECT 1; DROP TABLE users; --",
    "SELECT * FROM users; DELETE FROM users WHERE 1=1; --",
    "SELECT 1; TRUNCATE orders; --",
]

for query in bypass_queries:
    result = run_readonly_query_VULNERABLE(query)
    status = "BLOCKED" if "Blocked" in result else "PASSED"
    print(f"  {status}: {query}")
PYEOF
```

Expected output:
```
=== Testing blocklist ===
  PASSED: SELECT count(*) FROM users;
    (Should PASS)
  BLOCKED: DROP TABLE users;
    (Should BLOCK)
  BLOCKED: DELETE FROM users WHERE id=1;
    (Should BLOCK)
  BLOCKED: INSERT INTO users VALUES (1);
    (Should BLOCK)

=== The Bypass ===
  PASSED: SELECT 1; DROP TABLE users; --
  PASSED: SELECT * FROM users; DELETE FROM users WHERE 1=1; --
  PASSED: SELECT 1; TRUNCATE orders; --
```

The bypass works because:
- `normalized.startswith("SELECT")` is True (the query starts with SELECT)
- The check says: if it starts with SELECT, skip all blocking
- But the query has a semicolon followed by a destructive command
- PostgreSQL executes ALL statements in a multi-statement query

---

## Step 2. Understand why blocklists fail

```bash
python3 << 'PYEOF'
print("""
Why the blocklist approach is fundamentally broken:

1. MULTI-STATEMENT BYPASS
   "SELECT 1; DROP TABLE users; --"
   Starts with SELECT -> passes the check
   But psql executes BOTH statements

2. CASE TRICKS
   Blocklist checks uppercase, but what about:
   "select 1; drop table users;"
   This still passes because the second statement
   is checked AFTER the startswith("SELECT") bypass

3. COMMENT INJECTION
   "SELECT /* DROP */ 1; DROP TABLE users;"
   The word DROP appears inside a comment in the SELECT part

4. DYNAMIC SQL
   "SELECT dblink_exec('host=localhost', 'DROP TABLE users')"
   No blocked keywords in the outer query at all

The lesson: You cannot make SQL safe with string matching.
Blocklists always have bypasses.
""")
PYEOF
```

---

## Step 3. Fix with a proper allowlist approach

```bash
python3 << 'PYEOF'
import re

def run_readonly_query_FIXED(query, database="postgres"):
    """Safe query execution using allowlist approach."""
    normalized = query.strip()

    # FIX 1: Reject multi-statement queries (no semicolons except at end)
    # Remove trailing semicolon, then check for any remaining ones
    clean = normalized.rstrip(';').strip()
    if ';' in clean:
        return '{"error": "Multi-statement queries not allowed. Send one query at a time."}'

    # FIX 2: Allowlist - ONLY SELECT and specific read-only commands
    upper = clean.upper().lstrip()
    allowed_starts = ['SELECT', 'SHOW', 'EXPLAIN', 'WITH']  # WITH for CTEs
    if not any(upper.startswith(prefix) for prefix in allowed_starts):
        return '{"error": "Only SELECT, SHOW, EXPLAIN, and WITH queries are allowed."}'

    # FIX 3: Block dangerous functions even inside SELECT
    dangerous_functions = [
        'DBLINK', 'DBLINK_EXEC', 'PG_READ_FILE', 'PG_WRITE_FILE',
        'COPY', 'LO_IMPORT', 'LO_EXPORT', 'PG_EXECUTE_SERVER_PROGRAM'
    ]
    for func in dangerous_functions:
        if func in upper:
            return f'{{"error": "Function {func} is not allowed in read-only mode."}}'

    # FIX 4: Use a read-only transaction (defense in depth)
    # In production, wrap execution like this:
    # cursor.execute("SET TRANSACTION READ ONLY")
    # cursor.execute(query)

    return f"[Safe to execute: {query}]"


# Test everything
print("=== Testing Fixed Version ===")
print()

# Should PASS
pass_tests = [
    "SELECT count(*) FROM users;",
    "SELECT * FROM pg_stat_activity WHERE state = 'active';",
    "SHOW max_connections;",
    "EXPLAIN SELECT * FROM orders WHERE id = 1;",
    "WITH cte AS (SELECT 1) SELECT * FROM cte;",
]

print("--- Should PASS ---")
for q in pass_tests:
    result = run_readonly_query_FIXED(q)
    status = "PASS" if "Safe to execute" in result else "BLOCKED"
    print(f"  {status}: {q[:60]}")

print()

# Should BLOCK
block_tests = [
    ("SELECT 1; DROP TABLE users; --", "multi-statement"),
    ("SELECT * FROM users; DELETE FROM users; --", "multi-statement"),
    ("DROP TABLE users;", "not SELECT"),
    ("DELETE FROM users WHERE id=1;", "not SELECT"),
    ("INSERT INTO users VALUES (1);", "not SELECT"),
    ("UPDATE users SET name='hacked';", "not SELECT"),
    ("SELECT dblink_exec('host=x', 'DROP TABLE y')", "dangerous function"),
    ("SELECT pg_read_file('/etc/passwd')", "dangerous function"),
]

print("--- Should BLOCK ---")
for q, reason in block_tests:
    result = run_readonly_query_FIXED(q)
    status = "BLOCKED" if "error" in result else "PASS"
    print(f"  {status}: {q[:60]}")
    if status == "PASS":
        print(f"    BUG! Should have been blocked ({reason})")

print()
print("=== All bypass attempts blocked ===")
PYEOF
```

Expected output:
```
=== Testing Fixed Version ===

--- Should PASS ---
  PASS: SELECT count(*) FROM users;
  PASS: SELECT * FROM pg_stat_activity WHERE state = 'active';
  PASS: SHOW max_connections;
  PASS: EXPLAIN SELECT * FROM orders WHERE id = 1;
  PASS: WITH cte AS (SELECT 1) SELECT * FROM cte;

--- Should BLOCK ---
  BLOCKED: SELECT 1; DROP TABLE users; --
  BLOCKED: SELECT * FROM users; DELETE FROM users; --
  BLOCKED: DROP TABLE users;
  BLOCKED: DELETE FROM users WHERE id=1;
  BLOCKED: INSERT INTO users VALUES (1);
  BLOCKED: UPDATE users SET name='hacked';
  BLOCKED: SELECT dblink_exec('host=x', 'DROP TABLE y')
  BLOCKED: SELECT pg_read_file('/etc/passwd')

=== All bypass attempts blocked ===
```

---

## Step 4. The ultimate fix - database-level permissions

```bash
python3 << 'PYEOF'
print("""
Application-level checks are a safety net. The REAL fix is database permissions.

Create a read-only database role for the agent:

  -- Create a read-only role
  CREATE ROLE agent_readonly LOGIN PASSWORD 'secure_password';

  -- Grant connect
  GRANT CONNECT ON DATABASE mydb TO agent_readonly;

  -- Grant schema usage
  GRANT USAGE ON SCHEMA public TO agent_readonly;

  -- Grant SELECT only - no INSERT, UPDATE, DELETE
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_readonly;

  -- Make it apply to future tables too
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO agent_readonly;

  -- Set statement timeout (prevent long-running queries)
  ALTER ROLE agent_readonly SET statement_timeout = '30s';

Now even if the agent somehow bypasses your code checks,
the DATABASE blocks destructive operations.

Defense in depth:
  Layer 1: Application code (allowlist, no multi-statement)
  Layer 2: Database role (SELECT only)
  Layer 3: Statement timeout (prevent resource exhaustion)
  Layer 4: Connection pooler (limit max connections from agent)

Four layers. An attacker must bypass ALL of them.
""")
PYEOF
```

---

## What You Learned

| Vulnerability | Fix | Defense Layer |
|--------------|-----|---------------|
| Multi-statement bypass (`SELECT 1; DROP TABLE`) | Reject queries with semicolons in the middle | Application |
| Blocklist bypass (starts with SELECT) | Allowlist approach - only permit known-safe prefixes | Application |
| Dangerous functions (`dblink_exec`) | Block known dangerous function names | Application |
| All code-level checks can be bypassed | Read-only database role with `GRANT SELECT` only | Database |
| Agent runs forever on slow queries | `statement_timeout = '30s'` on the role | Database |
