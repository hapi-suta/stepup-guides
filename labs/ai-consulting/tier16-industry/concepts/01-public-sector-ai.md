# Concepts: Public-Sector AI

**Tier 16, Module 16.1** - what changes when your client is a government or public institution.

This is a teaching reference. Read it once now, then return to it whenever you scope a public-sector engagement. Public-sector AI is not commercial AI with a government logo. The constraints are different, the failure costs are different, and the definition of "success" is different.

Why this matters for a consultant: the same RAG assistant that is a nice productivity tool inside a startup becomes a legally accountable decision system inside a government agency. If you carry commercial assumptions into a public-sector room, you will lose the room. Learn the vocabulary and the constraints first.

---

## The core difference in one line

**Commercial AI optimizes for value; public-sector AI optimizes for legitimacy.**

A private company can accept an opaque model that makes more money. A public institution spends public money, serves people who cannot choose another provider, and must be able to justify every decision that affects a citizen. Legitimacy - the defensible, explainable, accountable use of authority - is the whole game.

---

## The public-sector AI use-cases you will actually be asked about

### Citizen-service assistants
Chat or voice assistants that answer questions about benefits, permits, taxes, or services. The trap: citizens cannot "shop elsewhere", so a wrong or hallucinated answer is not a lost sale, it is a citizen who missed a deadline or a benefit they were entitled to.

### Document processing
Extracting and classifying data from forms, applications, and records at scale. High volume, often legacy paper, frequently multilingual. This is usually the safest, highest-value first use case because it is administrative, not decisional.

### Fraud detection
Flagging benefit fraud, procurement fraud, or tax evasion. High impact and high risk: a false positive can cut off someone's benefits. These are decision-support systems, never auto-deciders, and they must be appealable.

### Regulatory support
Helping staff find and apply the correct regulation, policy, or precedent. Value is in speed and consistency; risk is in the model confidently citing a repealed or wrong rule.

### Government knowledge management
Turning scattered internal policy, memos, and procedures into a searchable, cited assistant for staff. Internal-facing, so lower external risk, but the source corpus is often messy and access-controlled.

### Public records
Search and disclosure over public records, including freedom-of-information requests. Must respect redaction, classification, and privacy law.

### Multilingual services
Serving citizens in every official and community language. In many jurisdictions this is a legal duty, not a feature. Quality must be equal across languages, which is hard.

### Procurement
Assisting with tenders, evaluation, and contract review. Sensitive because procurement decisions are legally challengeable and must be seen to be fair.

---

## The public-sector constraints you must design for

### Public accountability
Every consequential decision must be traceable to a rule, a human, and a reason. "The model said so" is never an acceptable justification. Design for an audit trail from day one: who asked, what the system returned, what sources it cited, and who made the final call.

### Accessibility
Public services must be usable by people with disabilities. In practice this means your assistant must meet a recognized accessibility standard. The core standard is the Web Content Accessibility Guidelines (WCAG), maintained by the W3C (see: https://www.w3.org/WAI/standards-guidelines/wcag/). In the US, Section 508 of the Rehabilitation Act requires federal information and communication technology to be accessible and incorporates WCAG 2.0 Level AA by reference (see: https://www.section508.gov/manage/laws-and-policies/). Accessibility is not optional polish - it is frequently a legal requirement and a procurement gate.

### Appeals
Citizens have a right to challenge decisions that affect them. Your system must be able to reconstruct, after the fact, exactly what information was used and why - and a human must be able to overturn the outcome. If your architecture cannot support an appeal, it cannot be used for consequential decisions.

### High-impact decisions
A "high-impact" decision is one that materially affects a person's rights, money, freedom, or access to services (benefits eligibility, immigration status, licensing, sanctions). The rule: **AI supports, humans decide.** High-impact use cases require documented human oversight, an impact assessment, and an appeal path before they go live. This tracks the risk-based, lifecycle approach in the NIST AI Risk Management Framework (AI RMF 1.0), whose "Map" function is designed to identify context, stakeholders, and potential harms before deployment (see: https://www.nist.gov/itl/ai-risk-management-framework).

---

## The public-sector operating rules (memorize these)

1. **AI supports, humans decide** on anything consequential. The human is accountable, not the model.
2. **Explainability is a requirement, not a nice-to-have.** If you cannot explain why the system produced an answer, you cannot defend it on appeal.
3. **Every consequential interaction is logged and reconstructable.** Retention and audit are part of the design, not an afterthought.
4. **Equal service across languages and abilities.** Accessibility and multilingual quality are gates, not enhancements.
5. **Start administrative, earn your way to decisional.** Prove value and safety on low-risk document work before touching eligibility or enforcement.
6. **Procurement and fairness must be visible.** It is not enough to be fair; the process must be seen to be fair.

---

## How this reframes your existing toolkit

Your Tier 7 assistant and Tier 12 governance toolkit already do most of the technical work. Public-sector specialization is mostly about adding constraints on top:

| Your existing capability | Public-sector addition |
|---|---|
| RAG with citations | Citations become the audit trail and the appeal evidence |
| Access control | Now maps to records classification and disclosure law |
| Logging | Now a legal retention and reconstruction requirement |
| Evaluation | Now must prove equal quality across languages and groups |
| Human review | Now a documented, mandatory oversight step for high-impact use |

You are not rebuilding. You are hardening and documenting for a higher standard of accountability.

---

## One-line glossary

| Term | One line |
|---|---|
| Legitimacy | The defensible, accountable use of public authority - the goal of public-sector AI. |
| High-impact decision | A decision that materially affects a person's rights, money, or access to services. |
| Human oversight | A documented, mandatory human decision point on consequential outputs. |
| Appeal path | The ability to reconstruct and overturn an AI-informed decision after the fact. |
| Accessibility (WCAG) | A recognized standard making services usable by people with disabilities; often legally required. |
| Public accountability | Every consequential decision is traceable to a rule, a human, and a reason. |

---

## References

- NIST AI Risk Management Framework (AI RMF 1.0), National Institute of Standards and Technology: https://www.nist.gov/itl/ai-risk-management-framework
- Web Content Accessibility Guidelines (WCAG), W3C Web Accessibility Initiative: https://www.w3.org/WAI/standards-guidelines/wcag/
- Section 508 of the Rehabilitation Act - IT Accessibility Laws and Policies, Section508.gov: https://www.section508.gov/manage/laws-and-policies/
- U.S. Access Board, Revised 508 Standards (incorporate WCAG 2.0 Level AA): https://www.access-board.gov/ict/

Notes:
- The specific accessibility, records-classification, disclosure, and language-access obligations vary by country and jurisdiction. Confirm the exact standard and legal duty that applies to [CLIENT] before treating any requirement here as binding.

---

Prof. Happy (SUTA Labs)
