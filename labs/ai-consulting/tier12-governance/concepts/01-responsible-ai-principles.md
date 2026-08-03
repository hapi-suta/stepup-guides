# Concepts 12.1: Responsible-AI Principles

**Tier 12 - Responsible AI and governance.** Teaching reference. Every tier before this taught you to build and secure AI systems. This tier teaches you to answer a harder question a client and a regulator will both ask: "how do we know this system is trustworthy, and who is accountable when it is wrong?" Responsible AI is the set of principles that turns that question into a checklist you can actually run.

**Who this is for:** DBAs and engineers moving into AI consulting. You already think in terms of constraints, controls, and audits (backups, permissions, change control). Responsible AI is the same discipline applied to a model instead of a database. This module is vocabulary and theory only - no keyboard. Read it before you touch the toolkit in BUILD.

**Why it matters commercially:** "I can build a RAG assistant" is a junior skill. "I can build a RAG assistant and prove to your board, your lawyers, and your regulator that it is validated, fair, private, and accountable" is the consultant. The principles below are the language executives and auditors already speak. Learn them.

---

## 1. The twelve principles at a glance

These map onto the NIST AI RMF's characteristics of trustworthy AI and the themes in ISO/IEC 42001. One precision note so you get it right in front of an auditor: NIST's own list is **seven** characteristics, not twelve - "valid and reliable, safe, secure and resilient, accountable and transparent, explainable and interpretable, privacy-enhanced, and fair with harmful bias managed" (see: https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf, Section 3). The twelve below are a fuller teaching set (we split some of NIST's paired characteristics and add inclusion and accessibility); they *map onto* NIST's seven, they do not restate them one-for-one. You should be able to define each in one plain sentence and give one AI example.

| Principle | One-sentence definition |
|-----------|-------------------------|
| Validity | The system actually does the job it claims to do, measured on real data. |
| Reliability | It keeps doing that job consistently over time and across inputs. |
| Safety | It does not cause physical, financial, or psychological harm. |
| Security | It resists attackers, misuse, and leaks (Tier 11 territory). |
| Privacy | It protects personal and confidential data end to end. |
| Transparency | People know when AI is used and how it makes decisions at a high level. |
| Explainability | You can give a human-understandable reason for a specific decision. |
| Fairness | It does not systematically disadvantage a protected group. |
| Accountability | A named human or role owns the outcomes, good and bad. |
| Human oversight | A person can review, override, and stop the system. |
| Inclusion | It works for the full range of intended users, not just the majority. |
| Accessibility | People with disabilities can use it (screen readers, captions, plain language). |

Keep this table in your head. In a client meeting you will walk down it and ask "how does your system handle each of these?" The gaps you find are your engagement.

---

## 2. Validity and reliability

- **Validity** is "does it work?" measured objectively. A churn model that scores 0.9 AUC on a fair held-out set is valid for that task. A model tested only on the training data has no evidence of validity.
- **Reliability** is "does it keep working?" A valid model can become unreliable when the world changes (concept drift, Tier 10) or when a dependency breaks (a provider deprecates a model version).

The consultant's job is to demand evidence, not vibes. "Validated" means there is a written record of what was tested, on what data, with what result, by whom, and when. If there is no record, treat it as not validated.

---

## 3. Safety and security

- **Safety** is about harm to people and the business: a medical triage assistant that under-triages a real emergency is a safety failure even if it is secure.
- **Security** is about attackers and misuse: prompt injection, data poisoning, cost exhaustion (all Tier 11). Security is a precondition for safety - an insecure system cannot be safe.

For a consultant the practical test is: "list the ways this system could hurt someone or the organization, then show me the control for each." That list is your impact assessment (Concepts 12.4).

---

## 4. Privacy

Privacy in AI has some twists beyond normal application privacy:

- **Training and prompt data:** does the vendor train on your prompts? Does your RAG index contain personal data it should not?
- **Memorization:** a model can regurgitate training data. Sensitive-information disclosure is an OWASP GenAI risk.
- **Inference-time leakage:** logs, traces, and evaluation datasets quietly accumulate personal data.

The governance control is data classification plus a written statement of what data flows where. You will build the vendor questions for this in Concepts 12.6.

---

## 5. Transparency vs explainability

These get confused. They are different.

- **Transparency** is systemic and up front: users are told "you are talking to an AI assistant", documentation describes the model, its data, and its limits (that is what a model card and a data sheet are for).
- **Explainability** is per decision: "why was THIS loan application declined?" A human can be given a reason they understand.

An executive-friendly line: transparency is the label on the box; explainability is the receipt for one purchase. High-risk decisions (credit, hiring, benefits) usually need both, and often a legal right to an explanation.

---

## 6. Fairness

Fairness means the system does not systematically disadvantage a protected group (race, sex, age, disability, and others depending on jurisdiction). Two traps:

- **Fairness is not one number.** Different fairness definitions can conflict mathematically. You must pick the definition that fits the use case and defend it.
- **Removing the protected attribute does not remove bias.** A **proxy variable** (zip code standing in for race, first name standing in for sex) carries the bias back in. This is why "we don't use race, so we're fair" is wrong.

In BUILD's USE you will actually compute a fairness metric (selection rate by group, disparate-impact ratio) in Python. You cannot govern fairness you cannot measure. One concrete, defensible benchmark to know: the US **four-fifths (80%) rule** - if a protected group's selection rate is below 80% of the highest group's rate, that is treated as a flag for adverse impact. It comes from the 1978 Uniform Guidelines on Employee Selection Procedures (29 CFR 1607.4(D); see: https://www.law.cornell.edu/cfr/text/29/1607.4). Treat it as a widely-used **rule of thumb**, not a strict statistical test - it is a screening threshold, not proof of discrimination on its own.

---

## 7. Accountability and human oversight

- **Accountability** answers "who is responsible when it goes wrong?" The answer must be a named human or role, never "the AI" and never "the vendor" alone. Governance assigns an owner to every AI system in the inventory.
- **Human oversight** is the mechanism that makes accountability real: a person who can review outputs, override decisions, and pull the plug. There are three postures, and you must state which applies:
  - **Human in the loop:** a person approves each consequential action before it happens (highest control).
  - **Human on the loop:** the system acts, a person monitors and can intervene.
  - **Human in command:** a person sets the policy and can shut it down, but does not touch each action.

High-risk uses demand human in the loop. You designed exactly this in Tier 8 (the read-only agent with a human-approval gate). Governance is where you write it down as policy.

---

## 8. Inclusion and accessibility

- **Inclusion** is whether the system works across the real user base: languages (English AND French for your assistant), dialects, literacy levels, edge-case users. A model that only works well for the majority group has an inclusion gap.
- **Accessibility** is whether people with disabilities can use it: screen-reader compatibility, captions, keyboard navigation, plain-language output. In the public sector this is often a legal requirement, not a nice-to-have.

Consultants forget these two constantly. Naming them in a readiness assessment instantly signals you are senior.

---

## 9. How principles become governance

Principles are useless as a poster on a wall. Governance turns each principle into:

1. A **policy** statement (what we require).
2. A **control** (how we enforce it).
3. **Evidence** (proof the control ran).
4. An **owner** (who is accountable).

That four-part chain - principle, policy, control, evidence, owner - is the whole discipline. The rest of this tier gives you the frameworks (NIST AI RMF, ISO/IEC 42001) and the artifacts (policies, impact assessments, model cards, vendor questionnaires) that make the chain real.

---

## Key takeaways

- Twelve principles: validity, reliability, safety, security, privacy, transparency, explainability, fairness, accountability, human oversight, inclusion, accessibility. Be able to define each in one sentence.
- "Validated" means there is a written, dated record. No record means not validated.
- Transparency is the label on the box; explainability is the receipt for one decision.
- Fairness is not one number, and dropping the protected attribute does not fix bias because of proxy variables.
- Accountability must land on a named human; human oversight (in the loop / on the loop / in command) is the mechanism.
- Every principle must become policy, control, evidence, and owner. That chain is the job.

---

## References

- NIST AI RMF 1.0 (NIST AI 100-1) - characteristics of trustworthy AI, Section 3 - https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf
- ISO/IEC 42001:2023 (AI management system) - https://www.iso.org/standard/42001
- OWASP Top 10 for LLM Applications - LLM02 Sensitive Information Disclosure (memorization/leakage) - https://genai.owasp.org/llmrisk/llm02-2025-sensitive-information-disclosure/
- US Uniform Guidelines on Employee Selection Procedures - four-fifths rule (29 CFR 1607.4) - https://www.law.cornell.edu/cfr/text/29/1607.4

Prof. Happy (SUTA Labs)
