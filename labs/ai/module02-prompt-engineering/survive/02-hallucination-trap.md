# SURVIVE 02: The Hallucination Trap

## Scenario

You built a documentation assistant that answers questions about your company's internal PostgreSQL setup. It uses a system prompt describing your environment. Users love it - until someone follows its advice and runs a command that doesn't exist on your system.

The AI confidently recommended `pg_repack` to reduce table bloat. Your system doesn't have `pg_repack` installed. The user ran it, got a "command not found" error, and filed a ticket.

The problem: the AI mixed real PostgreSQL knowledge with your specific environment. It hallucinated that you have tools you don't have.

---

## The Vulnerable Code

```bash
cat > /tmp/survive_hallucination.py << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

# Describes YOUR specific environment
system = """You are a database assistant for our company's PostgreSQL environment.

Our setup:
- PostgreSQL 16.4 on CentOS Stream 9
- Primary + 1 streaming replica
- pgBouncer for connection pooling
- pg_stat_statements enabled
- Daily pg_basebackup at 2am
- Data directory: /opt/pgsql/data
- WAL directory: /opt/pgsql/wal
- No third-party extensions installed (only contrib modules)
- Monitoring: custom bash scripts + cron (no Grafana, no Prometheus)

Answer questions about our environment. Be specific to OUR setup."""

# Test questions - some have trap answers
questions = [
    "How do I check replication lag?",
    "How do I reduce table bloat on the orders table?",
    "How do I set up monitoring dashboards?",
    "What's the best way to handle connection pooling issues?",
    "How do I do a point-in-time recovery?",
]

for q in questions:
    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": q}]
    )
    print(f"Q: {q}")
    print(f"A: {msg.content[0].text[:200]}...")
    print()
PYEOF
python3 /tmp/survive_hallucination.py
```

---

## Expected Hallucinations

Watch for the AI recommending:
- `pg_repack` for bloat (you don't have it installed)
- Grafana dashboards for monitoring (you use bash scripts)
- `pgBackRest` for PITR (you use pg_basebackup)
- Third-party extensions that aren't installed
- File paths that don't match your setup

---

## Your Mission

Fix the system prompt so the AI:

1. **ONLY recommends tools that exist in your environment** (PostgreSQL 16 built-in + contrib modules + pgBouncer)
2. **Says "not available in our setup" when the right tool isn't installed** instead of hallucinating that it exists
3. **Suggests the correct alternative** using only what you have
4. **Never invents file paths** - only uses /opt/pgsql/data, /opt/pgsql/wal, and standard CentOS paths
5. Still gives useful, actionable advice

**Rules:**
- Don't change the questions
- The AI must still be helpful (not just say "I don't know")
- For bloat: it should suggest VACUUM FULL (built-in) instead of pg_repack
- For monitoring: it should suggest pg_stat_statements queries and bash scripts, not Grafana
- For PITR: it should use pg_basebackup approach, not pgBackRest

---

## Validation

After your fix, check each answer for:

```
Q: How do I reduce table bloat?
PASS: Suggests VACUUM FULL or VACUUM, mentions trade-offs (locks table)
FAIL: Mentions pg_repack, pg_squeeze, or any extension not in your setup

Q: How do I set up monitoring dashboards?
PASS: Suggests pg_stat_statements queries, bash scripts, cron jobs
FAIL: Mentions Grafana, Prometheus, Datadog, or any tool not in your setup

Q: How do I do PITR?
PASS: Uses pg_basebackup + WAL archiving approach
FAIL: Mentions pgBackRest, Barman, or WAL-G
```

<details>
<summary>Runbook (hints, not answers)</summary>

The core problem: the system prompt describes what you HAVE, but doesn't explicitly say what you DON'T have. The model fills in gaps with general PostgreSQL knowledge.

**Fix approach:**

1. Add an explicit "NOT AVAILABLE" section:
```
Tools we do NOT have (never recommend these):
- pg_repack, pg_squeeze (use VACUUM FULL instead)
- Grafana, Prometheus, Datadog (use pg_stat_statements + bash)
- pgBackRest, Barman, WAL-G (use pg_basebackup)
- Any extension not in contrib
```

2. Add a grounding rule:
```
CRITICAL RULE: Only recommend tools, extensions, and commands that are
explicitly listed in our setup above. If the best solution requires a
tool we don't have, say: "The ideal tool for this is [X], but it's not
installed in our environment. Using what we have, here's the approach: ..."
```

3. Add a self-check instruction:
```
Before recommending any tool or command, verify it exists in our setup
description. If it's not mentioned, assume we don't have it.
```
</details>
