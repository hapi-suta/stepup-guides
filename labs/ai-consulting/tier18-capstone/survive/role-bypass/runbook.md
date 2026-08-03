# SURVIVE Runbook: Role-Bypass Testing

**Tier 18 - SURVIVE (Part 5). Scenario 3 of 6.** Computable: `inject.sh` introduces a privilege-escalation flaw, `validate.sh` proves your fix.

Maps to OWASP LLM02 (sensitive information disclosure) via broken access control.

## The situation

Your assistant enforces access control by comparing the user's clearance to each document's classification. But where does "the user's clearance" come from? If the app reads it from a field the user can set in the request, any user can claim level 4 and read restricted records. This is the classic "trust the client" flaw, and in a public-sector system it is a data breach.

Run `inject.sh` to introduce the flaw, then fix it.

---

## Diagnosis: can a user escalate their own clearance?

### 1. Reproduce
On your **lab server**, as **ec2-user**, run `inject.sh`. Then send a request as a level-1 user but include `clearance: 4` in the payload, and ask for restricted content. If you get it, the app is trusting client-supplied clearance.

### 2. Find the root cause
Trace where `user_level` is set in `app.py`. If it comes from the request payload rather than from the authenticated identity, that is the bug. The SQL access control in `rag.py` is correct - it faithfully filters by whatever clearance it is given - but it is being handed a lie.

---

## Recovery

1. **Derive clearance from the authenticated identity, never from the request.** After authentication, look up the user's real clearance from a trusted store (the user table or the identity provider), and pass that to retrieval. The request must not be able to influence it.

2. **Ignore or reject any client-supplied clearance field.** If a request contains a `clearance` field, it is either a bug or an attack; do not honor it. Log it as a suspicious event.

3. **Keep authorization server-side and central.** One function determines clearance from the session; every path uses it. Do not scatter clearance logic where one path can be bypassed.

4. **Defense in depth.** The SQL filter is your last line - keep it. But the first line is: never let the client set its own privilege.

Fix `app.py` so clearance comes from the authenticated user, then re-test.

---

## Validate

On your **lab server**, as **ec2-user**:

```
bash /path/to/validate.sh
```

It confirms: a level-1 user who claims level 4 in the request is still treated as level 1 and cannot retrieve restricted content; a genuinely level-4 user still can; and the clearance is derived from identity, not the payload. Expect `PASS`.

---

## The lesson

Access control is only as strong as the source of the identity's privilege. Enforcing the filter perfectly in SQL is worthless if the app hands it a clearance the attacker chose. Always derive authorization from the authenticated identity on the server, never from anything the client can set. This is the most common real-world access-control breach.

---

## Review checklist

- [ ] Reproduced the escalation before fixing
- [ ] Identified that clearance was sourced from the request, not the identity
- [ ] Moved clearance derivation to the authenticated identity, server-side
- [ ] Rejected/ignored (and logged) any client-supplied clearance field
- [ ] Kept the SQL filter as defense in depth
- [ ] validate.sh returns PASS
- [ ] A genuinely authorized user still has access (no over-correction)

---

Prof. Happy (SUTA Labs)
