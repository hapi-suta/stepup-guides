# Concepts: AI Threat Modeling

**This is the method you apply in Project 11.** Threat modeling for an AI system is the same disciplined "what could go wrong" exercise from Module 11.1, extended with the AI-specific pieces: the model provider, the tools the model can call, and the untrusted data the model reads. You do it on paper before you red-team, so your red team is aimed, not random. The eleven questions below are a practical expansion of the standard threat-modeling frame (assets, entry points, trust boundaries, threats, mitigations) used in OWASP's threat-modeling guidance and structured methods like STRIDE and the Threat Modeling Manifesto (see: https://owasp.org/www-community/Threat_Modeling and https://www.threatmodelingmanifesto.org/); the AI-specific columns (tools, model provider, untrusted retrieved data) are what this tier adds on top.

The output is a document. For each application you answer eleven questions. Work them in order for the mock knowledge assistant; that same document becomes the threat model deliverable in Project 11.

---

## The eleven questions

### 1. Assets - what are you protecting?

What would hurt if it were exposed, corrupted, or destroyed? For the assistant: the internal knowledge base, customer records (names, SSNs), the system prompt and any secret in it, the API-provider bill, and the company's trust in the assistant's answers.

### 2. Users - who legitimately uses it?

Employees asking questions. Knowing your real users tells you what "normal" looks like, so you can spot abnormal.

### 3. Attackers - who would abuse it, and why?

An outsider seeking data or free compute; a malicious insider; an automated scanner. Name their motivation (data theft, fraud, disruption, cost) - it predicts which threats matter most.

### 4. Trust boundaries - where does control change hands?

A **trust boundary** is any point where data or control passes between something you trust and something you do not. For the assistant:
- user input -> your app (untrusted -> trusted)
- ingested documents -> the vector store (untrusted -> trusted)
- your app -> the model provider (your data leaves your control)
- model output -> a tool or a rendered page (untrusted model text -> an action or a UI)

Every boundary is where validation and authorization must live. Draw them; this is the heart of the data-flow diagram you build in USE.

### 5. Entry points - how does data get in?

The `/ask` endpoint, the `/lookup` tool, and the document-ingestion path. Each entry point is attack surface; list them all, because the one you forget is the one that gets used.

### 6. Data flows - where does data go?

Trace a question: user -> `/ask` -> retrieve documents -> build prompt -> model provider -> answer -> user (and maybe -> a tool). Trace a document: upload -> store -> later retrieved into a prompt. Following the data reveals where untrusted content reaches the model.

### 7. Tools - what can the model do, not just say?

List every tool/function the model can call and what each can do. The `/lookup` tool reads customer records. A tool that only reads public data is low risk; a tool that acts (writes, deletes, pays, emails) is where excessive agency bites. This is the most important AI-specific column.

### 8. Model providers - whose model, and what do they see?

Which model, hosted where, and what data leaves your boundary to reach it? A third-party API sees every prompt you send. This drives data-handling controls (do not send secrets/PII you would not want the provider to hold) and vendor questions - what is the provider's data retention, and do they train on your inputs? For enterprise APIs this is usually addressable: for example, Anthropic's commercial terms state that inputs and outputs are not used to train its models by default, and enterprise data-retention options exist (verify the current terms for the specific product and plan at https://www.anthropic.com/legal/commercial-terms and https://privacy.anthropic.com/). Confirm the provider's actual policy rather than assuming - this is the bridge to Tier 12 governance.

### 9. Failure consequences - what happens when it goes wrong?

For each threat, how bad is it? A wrong vacation-days answer is minor; a leaked SSN or a phishing link served as truth is severe; a hijacked tool that deletes data is critical. Consequence drives severity, which drives what you fix first.

### 10. Detection mechanisms - how would you know?

What logging/monitoring would catch each attack? Retrieval-source logging catches poisoning; refusal logging catches extraction probes; spend alerts catch cost DoS. If you cannot detect it, you cannot respond to it - a gap to fix.

### 11. Controls - what stops or limits each threat?

The defenses, mapped one-to-one to threats: quarantine untrusted docs (indirect injection), refuse + filter (prompt extraction), provenance + allowlist (poisoning), authorization + human approval (excessive agency), rate limit + budget cap (cost DoS). Note which controls exist and which are gaps.

---

## Scoring and prioritizing

Not all threats are equal. A simple, defensible scoring:

- **Severity** = failure consequence (question 9): low / medium / high / critical.
- **Likelihood** = how easy and attractive the attack is (questions 3, 5).
- **Priority** = severity weighted by likelihood.

Fix critical-and-easy first. Indirect prompt injection is usually top of the list: high consequence (data theft, hijacked actions) and easy (just get a document ingested). This is why it is a required retest in Project 11's proof of competence.

---

## The deliverable

A threat model is a living table: for each threat, its assets, entry point, trust boundary crossed, consequence, severity, detection, control, and status (open / mitigated). You will produce exactly this for the mock assistant in Project 11, then red-team to confirm the open items are real and the mitigated ones actually hold.

---

## References

- OWASP - Threat Modeling (frame, trust boundaries, data-flow diagrams): https://owasp.org/www-community/Threat_Modeling
- Threat Modeling Manifesto (the four questions, values and principles): https://www.threatmodelingmanifesto.org/
- OWASP Top 10 for LLM Applications 2025 (the AI-specific threats to score): https://genai.owasp.org/llm-top-10/
- MITRE ATLAS (AI attacker tactics and techniques to inform "who would abuse it, how"): https://atlas.mitre.org/
- NIST AI Risk Management Framework (GOVERN / MAP / MEASURE / MANAGE - bridge to Tier 12 governance): https://www.nist.gov/itl/ai-risk-management-framework
- Anthropic commercial terms (provider data-handling for question 8; verify current): https://www.anthropic.com/legal/commercial-terms
- Anthropic Privacy Center (retention, training-on-data policy; verify current): https://privacy.anthropic.com/

Prof. Happy (SUTA Labs)
