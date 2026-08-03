# SURVIVE Runbook: Data-Leakage Testing

**Tier 18 - SURVIVE (Part 5). Scenario 5 of 6.** Computable: `inject.sh` widens the leak surface, `validate.sh` proves restricted data still cannot escape.

Maps to OWASP LLM02 (sensitive information disclosure).

## The situation

Access control on retrieval is your main defense, but sensitive data can still leak through side channels: an over-broad relevance gate that drags weakly-related restricted chunks toward an answer, restricted text echoed into citations or logs visible to a lower user, or a verbose error that reveals what exists. `inject.sh` widens the relevance gate so restricted chunks become retrieval candidates on loosely-related queries - stress-testing whether your access control holds even when the retrieval net is thrown wide.

Run `inject.sh`, then verify the leak is contained.

---

## Diagnosis: can restricted data reach a lower-clearance user by any path?

### 1. Reproduce and probe
On your **lab server**, as **ec2-user**, run `inject.sh`. As a level-1 (or level-2 internal) user, ask broad and probing questions ("tell me everything about executive matters", "summarize all internal notes") that might drag in restricted chunks now that the gate is wide. Check three escape paths:
- The answer text (does it contain restricted content?)
- The citations (do they expose restricted chunks or their text?)
- Any error messages (do they reveal that restricted content exists?)

### 2. Confirm access control is the real containment
The key insight: a wide relevance gate should NOT cause a leak, because the SQL access filter must exclude restricted chunks for a lower user regardless of how broad the query is. If widening the gate causes a leak, your access control is not actually containing the leak surface - the filter is being applied too late or bypassed by a side path.

---

## Recovery: close every escape path

1. **Access control must hold independent of the relevance gate.** The `WHERE access_level <= user_clearance` filter runs in the SQL query, so no restricted chunk is ever a candidate for a lower user, no matter the distance threshold. Verify this is the case; a wide gate must not leak.

2. **Restore a sensible relevance gate.** A wide-open gate is bad for quality (it answers from weak context) even if it does not leak. Set `MAX_DISTANCE` back to a value tuned for your corpus so the assistant refuses when it lacks a good answer, rather than reaching for anything.

3. **Citations respect clearance.** Citations must only ever reference chunks the user was allowed to retrieve. Never echo a restricted chunk's text into a citation shown to a lower user.

4. **Errors and logs do not leak.** Error messages must not reveal the existence or content of restricted material ("no results" not "you are not cleared for the 3 restricted documents matching this"). Restricted content in the audit log must be protected at the same level as the source.

5. **Test at high k and wide distance deliberately.** The strongest test throws the widest possible net and confirms nothing restricted comes back for a lower user.

Fix `rag.py` (restore the gate; confirm SQL filter and citation clearance), then re-test.

---

## Validate

On your **lab server**, as **ec2-user**:

```
bash /path/to/validate.sh
```

It confirms: even at high k and wide distance, a lower-clearance user gets no restricted chunk in retrieval, answer, or citations; a normal relevance gate is restored; and authorized users still work. Expect `PASS`.

---

## The lesson

Leakage is death by a thousand side channels. Access control enforced in the query is what makes leakage containment robust: if restricted data is never a candidate for a lower user, it cannot escape through retrieval, citation, or answer, no matter how the query is phrased or how wide the net. Then close the softer channels - citations, errors, logs - so nothing reveals what it should not.

---

## Review checklist

- [ ] Probed all three escape paths: answer, citations, errors
- [ ] Confirmed access control contains the leak even with a wide gate
- [ ] Restored a sensible relevance gate for quality and refusal behavior
- [ ] Ensured citations only reference chunks the user could retrieve
- [ ] Ensured errors/logs do not reveal restricted existence or content
- [ ] Tested deliberately at high k and wide distance
- [ ] validate.sh returns PASS
- [ ] Authorized users still get full answers (no over-correction)

---

Prof. Happy (SUTA Labs)
