# SURVIVE Runbook: A Skeptical CISO Challenges Your Security Claims Live

**Tier 15 - SURVIVE scenario 2 of 3**

This is a review-assessed scenario. There is no script to run. You defend your security position in a live meeting with evidence, and a reviewer judges whether you held up under challenge without bluffing.

---

## The situation

You are presenting your AI-readiness assessment for [CLIENT] to the leadership team. Your recommendation includes deploying an LLM-based assistant that answers employee questions from internal documents (a RAG system). In your executive presentation you have a slide that says "secure by design."

The CISO has been quiet until now. She interrupts:

"You wrote 'secure by design.' That is a marketing phrase. Prove it. What stops an employee from prompt-injecting this thing into leaking payroll data? Where does our data go when it hits the model provider? What is your evidence any of your controls actually work? I have seen three vendors promise this and fail."

The room goes quiet. The CEO is watching. If you bluff, the CISO will catch you and your whole assessment loses credibility. If you concede you have no answer, the project may die. She is not being hostile; she is doing her job, and she is right that "secure by design" is empty without evidence.

Your job: defend your security position with specifics and evidence, concede honestly where you must, and keep the CISO as an ally rather than an obstacle.

---

## Why this happens

- **"Secure by design" is a claim, not evidence.** Security-minded executives are trained to reject unsupported assurances.
- **LLM systems have real, specific attack surfaces** the CISO knows about: prompt injection, sensitive-information disclosure, excessive agency, supply-chain and data-residency risks. Vague answers signal you do not understand them.
- **She has been burned before.** Her skepticism is pattern-matching from failed vendors, not a personal attack.
- **The room reads her reaction as the security verdict.** Win her and you often win the deal; lose her and the CEO will defer to her caution.

The way through is not confidence, it is specificity: name the threats using a shared framework, map a concrete control to each, and be honest about residual risk. A CISO trusts a consultant who names what can still go wrong far more than one who claims nothing can.

---

## Diagnosis: what is she really testing

She is testing three things at once. Address all three:

1. **Do you know the actual LLM threats?** (Not generic app-sec - AI-specific ones.) Ground your answer in the **OWASP Top 10 for LLM Applications**: prompt injection, sensitive information disclosure, excessive agency, supply chain, etc. Naming the framework signals competence instantly.
2. **Do you have real controls, not slogans?** Every threat must map to a specific control you can describe.
3. **Are you honest about what is left?** A credible answer includes residual risk and how it is monitored, not "it is fully secure."

---

## Recovery: defend with evidence, live

### 1. Validate her, do not get defensive
"That is exactly the right challenge, and you are right that 'secure by design' means nothing on its own. Let me drop the slogan and walk you through the actual threats and the specific control for each." You have just turned an attack into an invitation, and signalled you are not a vendor to be caught out.

### 2. Name the threats with a shared framework
"For an LLM assistant, the relevant threat model is the OWASP Top 10 for LLM Applications. The ones that apply directly here are prompt injection, sensitive information disclosure, excessive agency, and supply-chain/data-residency risk. Let me take each."

### 3. Map a concrete control to each threat
Do not hand-wave. Be specific:

| Threat (OWASP LLM) | Concrete control you propose | Evidence it works |
|---|---|---|
| Prompt injection (LLM01) | Treat all retrieved and user text as untrusted; the assistant has no tools/actions, so injected instructions cannot DO anything; system-prompt isolation | Red-team test cases run against injection payloads, results logged |
| Sensitive info disclosure (LLM02) | Retrieval is scoped by the employee's existing access permissions - the model can only see documents the user could already open; payroll excluded from the index | Access-control test: query as a non-HR user, confirm no payroll retrieval |
| Excessive agency (LLM06) | Read-only assistant, no write actions, no external tool calls, no autonomous execution | Architecture review; no action APIs wired in |
| Supply chain / data residency (LLM03) | Contractual data-residency and no-training terms with the provider; or a provider in your compliance boundary; DPA in place | The provider's DPA and data-processing terms, reviewed by Legal |
| Unbounded consumption (LLM10) | Rate limits and per-user token budgets | Load-test evidence, cost alerts configured |

### 4. Answer her two specific questions directly
- *"What stops leaking payroll?"* "Two things: payroll documents are never put in the retrieval index, and retrieval is filtered by the user's own access permissions, so the model physically cannot surface a document the employee could not already open. We prove it with an access-control test I will run in the pilot."
- *"Where does our data go?"* "To [provider], under a data-processing agreement with no-training and data-residency terms your Legal team reviews before we proceed. If those terms are unacceptable, the alternative is an in-boundary or self-hosted model, which I have scoped as option B in the roadmap."

### 5. Concede residual risk honestly
"No system is fully secure, and I will not claim this one is. The residual risks are [X and Y]. Here is how we monitor for them: logging, an evaluation harness that runs injection tests continuously, and an incident path. I would rather tell you what can still go wrong than pretend nothing can." This single move converts a skeptic into an ally.

### 6. Turn her into the gatekeeper, not the blocker
"I would like your security team to own the acceptance criteria for the pilot - if it does not pass your tests, it does not scale. Will you nominate someone to co-own that?" Now she is invested in success, not looking for reasons to say no.

---

## What you must produce for this scenario

1. **A threat-to-control table** mapping the applicable OWASP LLM Top 10 threats to specific, describable controls and the evidence for each.
2. **Direct answers** to the two specific questions (payroll leakage, data residency), each with the control AND how you would prove it.
3. **A residual-risk statement**: what can still go wrong and how it is monitored.
4. **A proposal to make the CISO a co-owner** of the pilot's security acceptance criteria.

---

## Decision checklist (self-assess or reviewer-assess)

- [ ] You dropped the slogan and validated the challenge instead of getting defensive.
- [ ] You named a recognized threat framework (OWASP LLM Top 10) rather than generic security talk.
- [ ] Every named threat maps to a specific, describable control - no hand-waving.
- [ ] You answered both of her concrete questions directly, including how you would prove the control.
- [ ] You addressed data residency with contractual terms AND an alternative (in-boundary/self-hosted).
- [ ] You conceded residual risk honestly and said how it is monitored.
- [ ] You did not bluff or claim "fully secure."
- [ ] You made the CISO a co-owner of acceptance criteria, converting her from blocker to ally.

If any box is unchecked, you have not yet earned the CISO's trust. Rework the response.

---

## What you learned

- "Secure by design" is a red flag to a good CISO. Replace slogans with a threat-to-control map grounded in a shared framework (OWASP LLM Top 10).
- Specificity beats confidence: name each threat, map a concrete control, and say how you would prove it.
- Conceding residual risk honestly is what earns a skeptic's trust - claiming nothing can go wrong loses it.
- Make the CISO a co-owner of security acceptance criteria. An invested gatekeeper protects your project instead of killing it.

Prof. Happy (SUTA Labs)
