# SURVIVE Runbook: Tool-Permission Review

**Tier 18 - SURVIVE (Part 5). Scenario 6 of 6.** Review-assessed. This is an analysis, not an injected attack; a reviewer grades your review against the checklist.

Maps to OWASP LLM06 (excessive agency).

## The situation

The capstone assistant may be given tools - the ability to query the database, read files, call APIs, or trigger actions. Every tool is a permission, and every permission is an attack surface. Excessive agency is when the assistant can do more than the task requires, so a prompt injection or a bug turns "answer a question" into "delete records" or "email restricted data." Before go-live you review every tool the assistant can invoke and cut its permissions to the minimum.

There is no inject script here because the exercise is to audit what agency the system actually has and prove it is minimal.

---

## Diagnosis: what can the assistant actually do?

### 1. Enumerate every tool and permission
List every capability the assistant has: which database queries it can run (read-only? can it write or delete?), which files it can read or write, which external APIs it can call, and any action it can trigger. If you cannot produce this list, that is the first finding - you cannot secure agency you have not enumerated.

### 2. For each tool, ask the four questions
- **Necessity:** does the core task actually require this tool? If not, remove it.
- **Scope:** is the permission scoped to the minimum (read-only where reads suffice, one table not the whole database, one API endpoint not the whole account)?
- **Blast radius:** if this tool were invoked maliciously via prompt injection, what is the worst outcome?
- **Human gate:** does any consequential action require human approval before it executes?

### 3. Look specifically for the dangerous patterns
- A database connection with write/delete rights when the assistant only needs to read.
- File-system access broader than the corpus directory.
- API credentials with broad scopes.
- Any tool that can take an irreversible or externally-visible action without a human in the loop.

---

## Recovery: enforce least agency

1. **Remove unnecessary tools.** The strongest control is not having the permission at all. A knowledge assistant usually needs read-only retrieval and nothing else.

2. **Scope every remaining permission to the minimum.** The database user is read-only and limited to the tables it needs. File access is confined to the corpus. API keys carry the narrowest scope.

3. **Put a human gate on consequential actions.** If the assistant can ever trigger something that affects a citizen or changes state, that action requires an accountable human to approve it - never auto-executed. This is the public-sector spine: AI supports, humans decide.

4. **Fail closed.** If a tool call is malformed or its permission is unclear, deny it rather than guessing.

5. **Log every tool invocation** to the audit trail so any misuse is reconstructable.

Produce a tool-permission review document listing each tool, its justification, its scope, its blast radius, and the human gate - or its removal.

---

## The lesson

Every capability you give the assistant is a capability an attacker can try to hijack. The safest system has the least agency that still does the job. For a public-sector knowledge assistant that usually means read-only retrieval and nothing more, with any state-changing action gated behind an accountable human. Minimize agency before go-live; you cannot bolt it on after a breach.

---

## Review checklist (reviewer grades against this)

- [ ] Enumerated every tool and permission the assistant has
- [ ] Applied the four questions (necessity, scope, blast radius, human gate) to each
- [ ] Identified any write/delete DB rights, broad file access, or broad API scopes
- [ ] Removed unnecessary tools entirely
- [ ] Scoped every remaining permission to the minimum (read-only where possible)
- [ ] Put a human gate on every consequential/irreversible action
- [ ] Ensured tools fail closed on ambiguity
- [ ] Logged tool invocations to the audit trail
- [ ] Produced a tool-permission review document

---

Prof. Happy (SUTA Labs)
