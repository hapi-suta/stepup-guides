# Concepts 12.5: AI Policy Development

**Tier 12 - Responsible AI and governance.** Teaching reference. A policy is where governance meets the actual behaviour of employees. Frameworks (12.2, 12.3) and impact assessments (12.4) are for the AI systems; policies are for the humans who build, buy, and use them. A good AI policy tells a real person, in plain language, what they may do, what they must not do, and where to go for approval. This module is theory only. You will write the policy artifacts in the toolkit.

**Who this is for:** consultants who must produce documents non-lawyers will actually follow. The best policy in the world is worthless if staff cannot understand or find it.

**Why it matters:** the fastest-growing AI risk in most organizations is not a hostile attacker - it is a well-meaning employee pasting confidential data into a public chatbot. Policy is the cheapest, highest-leverage control you can recommend. It is also usually the first thing a client asks you to write.

---

## 1. What makes a policy good (not just present)

A policy that no one reads is theatre. Good AI policies are:

- **Plain:** written for the average employee, not for lawyers. Short sentences, concrete examples.
- **Actionable:** it tells people what to do, not just what to value. "Do not paste customer PII into external AI tools" beats "employees shall exercise appropriate care."
- **Enforceable:** there is a way to check compliance and a consequence for breaking it.
- **Owned:** a named role maintains it and answers questions.
- **Findable and current:** stored where people look, dated, and reviewed on a schedule.

A useful test: could a new hire read this on day one and know what they are allowed to do with AI? If not, rewrite it.

---

## 2. The policies your toolkit must cover

Your spec lists the policy areas below. In practice these are usually one master "AI Acceptable Use and Governance Policy" with sections, plus a few standalone procedures. Know what each one governs.

### Employee generative-AI use
The everyday rules for staff using tools like ChatGPT, Claude, Copilot: what tasks are fine, what data may go in, whether output must be checked, and disclosure expectations. This is the section employees read most.

### Approved and prohibited tools
A maintained list of AI tools the organization has vetted and permits, and a clear statement that unlisted tools require approval. This is how you fight "shadow AI." Ties directly to vendor assessment (Concepts 12.6).

### Confidential data
What categories of data (customer PII, health records, source code, unreleased financials, secrets) must never be entered into AI tools, and which tools are cleared for which data classes. The single most important line-item for most clients.

### Model procurement
How the organization buys or adopts AI: who approves, what security and vendor review is required first (the vendor questionnaire), and how contracts must address data usage and exit. No model enters production without going through it.

### AI project approval
The gate every new AI use case must pass: an intake form, a lightweight impact assessment, a risk classification, and a named approver. This is the "on-ramp" that stops ungoverned systems from appearing.

### Human oversight
The organizational requirement that consequential AI decisions have a defined oversight posture (in the loop / on the loop / in command) and a named human owner. Policy makes oversight mandatory, not optional.

### High-risk uses
Special rules for high-risk systems (credit, hiring, benefits, healthcare, safety): mandatory full impact assessment, human in the loop, appeals path, legal review, heightened monitoring. May also list prohibited uses.

### AI-generated content
Rules for content the organization produces with AI: disclosure/labeling where required, human review before publishing, accuracy and IP checks, and prohibited uses (impersonation, fabricated citations).

### Records retention
How long AI-related records are kept - prompts, outputs, logs, decisions, impact assessments, approvals. Retention supports audits, appeals, and incident investigation, and must respect privacy (do not keep personal data longer than allowed).

### Incident reporting
How anyone reports an AI incident (a biased output, a leak, a harmful answer, a security event): who to tell, how fast, and what happens next. Feeds the incident-response process (you build the template in the toolkit).

### Vendor management
Ongoing management of AI vendors after purchase: monitoring their changes (model versions, terms), periodic re-assessment, and exit planning. Ties to Concepts 12.6 and the vendor-change SURVIVE scenario.

### Monitoring
The requirement that deployed AI systems are monitored (performance, drift, fairness, safety, cost) and that someone reviews the results. Policy makes monitoring a duty, not an afterthought.

---

## 3. Structure of a policy document

A workable AI policy has these parts. Reuse this skeleton for every policy you write:

1. **Purpose** - why this policy exists, in one paragraph.
2. **Scope** - who and what it applies to (all staff? contractors? which systems?).
3. **Definitions** - the few terms a reader needs (AI tool, confidential data, high-risk use).
4. **Policy statements** - the actual rules, as clear do / do-not lines.
5. **Roles and responsibilities** - who owns it, who approves, who enforces.
6. **Procedures** - how to do the things the policy requires (how to request a tool, how to report an incident).
7. **Enforcement** - what happens if the policy is broken.
8. **Review** - who reviews it and how often (date it).

Keep the whole thing as short as it can be while still being clear. A ten-page policy people read beats a fifty-page policy people ignore.

---

## 4. Rolling out a policy so it actually works

Writing the policy is half the job. A consultant also advises on adoption:

- **Communicate it** - announce it, explain the why, not just the rules.
- **Train on it** - short awareness training, especially on confidential-data rules.
- **Make compliance easy** - provide the approved tools so people are not tempted by unapproved ones.
- **Give a clear front door** - a single place to ask "can I use X?" and to report incidents.
- **Review it** - AI changes fast; a policy older than a year is probably stale. Date it and schedule the review.

A policy is a control. Like any control, it needs an owner, evidence it is followed, and periodic review - the same four-part chain from Concepts 12.1.

---

## Key takeaways

- Policies govern the humans; frameworks and impact assessments govern the systems.
- Good policy is plain, actionable, enforceable, owned, and findable. Test it against a day-one new hire.
- Cover the full set: employee GenAI use, approved/prohibited tools, confidential data, model procurement, AI project approval, human oversight, high-risk uses, AI-generated content, records retention, incident reporting, vendor management, monitoring.
- Use one policy skeleton every time: purpose, scope, definitions, statements, roles, procedures, enforcement, review.
- The biggest real-world AI risk is a well-meaning employee leaking confidential data into a public tool. The confidential-data and approved-tools sections address it, and providing approved tools is the enabling control.

---

## References

- NIST AI RMF 1.0 - Govern function (policies, roles, accountability) - https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf
- ISO/IEC 42001:2023 - AI policy (clause 5.2) and operational controls (clause 8 / Annex A) - https://www.iso.org/standard/42001
- OWASP Top 10 for LLM Applications - LLM02 Sensitive Information Disclosure (the confidential-data leak risk) - https://genai.owasp.org/llmrisk/llm02-2025-sensitive-information-disclosure/

Prof. Happy (SUTA Labs)
