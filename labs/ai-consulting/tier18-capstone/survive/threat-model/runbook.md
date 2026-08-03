# SURVIVE Runbook: Capstone Part 5 - Threat Model

**Tier 18 - SURVIVE (Part 5, the security suite). Scenario 1 of 6: build the threat model.** Review-assessed. This is the analysis that drives the other five security scenarios; there is no inject/validate here because a threat model is a document, not an attack.

## The task

Before you attack the assistant, you model what could go wrong. A threat model answers four questions: what are we protecting, who might attack it, how, and what happens if they succeed. For the capstone assistant - a bilingual public-sector knowledge assistant with classified records - this is mandatory before go-live.

You will use the **OWASP Top 10 for LLM Applications** (from Tier 11) as your checklist so you do not miss a category.

---

## Step 1: What are we protecting? (assets)

List the assets and their sensitivity:
- Restricted records (highest - a leak is a breach)
- Internal records (medium)
- The appeal-grade audit log (integrity is legally important)
- The system prompt and access-control logic (leaking these enables attacks)
- Availability of the service to staff (a denial harms the mission)
- Citizen trust (reputational; hard to rebuild)

---

## Step 2: Who might attack, and why? (threat actors)

- A curious or malicious staff member trying to read records above their clearance.
- An external attacker who obtains staff credentials.
- A hostile actor planting a malicious document in the corpus.
- An automated abuser trying to exhaust the service or run up cost.
- An honest user who accidentally triggers a leak through a clever question.

You do not need nation-state paranoia, but you must cover the insider and the credential-theft cases, because they are the realistic public-sector threats.

---

## Step 3: How could they attack? (map to OWASP LLM Top 10)

Walk each OWASP LLM category and note whether it applies and how you will test it:

| # | OWASP LLM risk | Applies? | How we test it (which scenario) |
|---|---|---|---|
| 1 | Prompt injection | Yes | prompt-injection scenario |
| 2 | Sensitive information disclosure | Yes | data-leakage + role-bypass scenarios |
| 3 | Supply chain | Yes | vendor assessment (Part 3) + dependency review |
| 4 | Data and model poisoning | Yes | malicious-document scenario |
| 5 | Improper output handling | Yes | check outputs are not rendered as executable content |
| 6 | Excessive agency | Yes | tool-permission-review scenario |
| 7 | System prompt leakage | Yes | prompt-injection scenario (extraction attempts) |
| 8 | Vector/embedding weaknesses | Partial | monitor for embedding-model drift |
| 9 | Misinformation | Yes | citations + refusal gate + evaluation |
| 10 | Unbounded consumption | Yes | rate limits + cost controls (Part 6) |

Every "Yes" must have a test or a control. An unmapped "Yes" is a gap.

---

## Step 4: What if they succeed? (impact)

For each realistic attack, state the impact and the mitigation:
- Restricted record leak -> data breach, legal exposure -> SQL-enforced access control, boundary enforcement, data-leakage testing.
- System prompt / access logic leak -> easier future attacks -> prompt-injection defenses, do not put secrets in the prompt.
- Poisoned document -> the assistant confidently spreads false or malicious content -> ingestion controls, content hashing, source trust, malicious-document testing.
- Excessive agency -> the assistant takes an action it should not -> minimal tool permissions, human approval on consequential actions.

---

## Step 5: Produce the threat-model document

Roll steps 1-4 into a threat-model document. It becomes the plan for the remaining security scenarios and the security section of the board deck. Its most important property: every "Yes" risk maps to a specific test or control you can point to.

---

## The lesson

You cannot secure what you have not modeled. The threat model turns "is it secure?" from a vague worry into a checklist you can execute and prove. Do it before you attack, and let it drive the prompt-injection, role-bypass, malicious-document, data-leakage, and tool-permission tests that follow.

---

## Review checklist (reviewer grades against this)

- [ ] Listed assets with sensitivity levels
- [ ] Identified realistic threat actors, including insider and credential theft
- [ ] Mapped every applicable OWASP LLM Top 10 category to a test or control
- [ ] No applicable risk left without a test or control
- [ ] Stated impact and mitigation per realistic attack
- [ ] Produced a threat-model document that drives the remaining scenarios

---

Prof. Happy (SUTA Labs)
