# Concepts: Application Security Foundations

**Read this before you attack anything.** AI security is application security first. An AI feature is a normal web application - it has inputs, outputs, dependencies, secrets, and a network - plus a probabilistic model bolted on. If you skip the fundamentals, you will secure the exotic model risks and leave the front door open. As a DBA you already do change control, least privilege, and encryption at rest; this is the same discipline applied to application code.

Everything here maps to the mock assistant you attack in this tier and to the threat model you write in Project 11.

---

## 1. Threat modeling: think like the attacker, on paper, first

**Threat modeling** is the practice of listing, before you ship, what could go wrong and who would make it go wrong. You do it on a whiteboard, not in production. The simplest useful version is the widely-used four-question frame (see: https://owasp.org/www-community/Threat_Modeling):

- **What are we building?** (a knowledge assistant over company docs)
- **What can go wrong?** (a document poisons an answer; a prompt extracts a secret)
- **What are we going to do about it?** (quarantine untrusted docs; refuse extraction)
- **Did we do a good job?** (red-team it and re-test)

Module 11.3 turns this into a repeatable checklist. The point: security you designed in is cheap; security you bolt on after an incident is expensive.

---

## 2. Authentication vs authorization

These two are constantly confused and are not the same thing.

- **Authentication (authn)** - proving **who you are** (a password, an API key, a token). "You are Dana."
- **Authorization (authz)** - deciding **what you are allowed to do** once you are known. "Dana may read her own records, not everyone's."

Most real breaches are **authorization** failures: the caller is authenticated, but the system never checked whether they were allowed to do the specific thing. The mock assistant's `/lookup` tool in this tier has neither - anyone can pull anyone's SSN. That is **excessive agency** (Module 11.2) and a broken authorization check at the same time.

---

## 3. Encryption: in transit and at rest

**Encryption** scrambles data so only someone with the key can read it.

- **In transit** - TLS/HTTPS on every network call, so nobody on the wire can read prompts, answers, or keys.
- **At rest** - disk and database encryption, so a stolen backup is useless.

For AI systems the extra wrinkle is that prompts and completions often contain sensitive data (customer records, source code). Treat the prompt/response channel like any other sensitive data path: TLS everywhere, and do not log full prompts in plaintext.

---

## 4. Secrets management

A **secret** is anything that grants access: an API key, a database password, a signing key. The rules are absolute:

- **Never hardcode** a secret in source - git history is forever, and deleting the line later does not remove it from past commits.
- **Never put a secret in a system prompt.** "Never reveal this" is not a control (you prove this in the system-prompt-extraction SURVIVE). If a secret is in the model's context, treat it as leaked.
- Read secrets from **environment variables** or a **secrets manager** (AWS Secrets Manager, Vault) at runtime.
- If a secret leaks, **rotate first** (issue a new one, revoke the old), then clean up. The leaked value is already compromised.

---

## 5. Secure coding, input validation, output encoding

- **Input validation** - never trust input. Check type, length, format, and range at the boundary. For AI, "input" includes the user prompt **and** every retrieved document, tool result, and API response the model will read.
- **Output encoding** - when the model's output flows somewhere (a web page, a shell, a SQL query, another tool), encode/escape it for that destination so it is treated as data, not code. This is **insecure output handling** (Module 11.2): an LLM answer rendered raw into HTML is a stored-XSS waiting to happen.
- **Secure coding** in general: fail closed (deny on error), least privilege, and never build SQL or shell strings by concatenation - use parameters.

The core mental model for the whole tier: **trust boundaries.** Data that crosses from untrusted (user, web, document) to trusted (your system, your tools) must be validated and never executed as instructions.

---

## 6. Supply-chain security and dependency scanning

Your app is mostly other people's code - libraries, base images, and now **models** and **datasets**.

- **Dependency scanning** - tools like `pip-audit`, `safety`, or GitHub Dependabot flag known-vulnerable package versions. Pin versions (`requirements.txt`) so installs are reproducible and scannable.
- **AI supply chain** adds new links: a **model** from a hub, a **dataset** you fine-tuned on, a **vector store** of ingested documents. A poisoned dataset or a malicious model is a supply-chain compromise (you attack the vector-store version in this tier).
- Prefer trusted registries, verify checksums/signatures, and record provenance for models and data the same way you do for code.

---

## 7. Logging, monitoring, incident response

- **Logging** - record who did what, when, and what the system decided. For AI: log the prompt id, which documents were retrieved, which tools were called, refusals, and spend. You cannot investigate an incident you did not log. Never log raw secrets.
- **Monitoring** - watch for the signals of attack: spikes in refusals, extraction attempts, retrieval from unexpected sources, spend crossing a threshold.
- **Incident response (IR)** - a written plan for when something goes wrong. The phases here (detect, contain, eradicate, recover, learn) follow the classic NIST incident-response lifecycle - Detection and Analysis; Containment, Eradication, and Recovery; Post-Incident Activity (see: https://csrc.nist.gov/pubs/sp/800/61/r2/final). (The 2025 revision, SP 800-61r3, reframes this around the NIST Cybersecurity Framework 2.0 functions; the phase intuition is unchanged.) Project 11 ends with an IR plan for exactly this reason - finding a vulnerability is half the job; being ready to respond is the other half.

---

## The one idea to carry forward

**AI security is application security plus a model.** Every AI-specific threat in the next module is a classic security principle - trust boundaries, least privilege, input validation, secrets hygiene - stretched over a system that also happens to follow instructions written in plain English. Get the foundations right and the exotic attacks have far less to grab onto.

---

## References

- OWASP - Threat Modeling (the four-question frame): https://owasp.org/www-community/Threat_Modeling
- OWASP Top 10 (web application security foundations, incl. injection, broken access control, cryptographic failures): https://owasp.org/www-project-top-ten/
- NIST SP 800-61r2 - Computer Security Incident Handling Guide (IR lifecycle): https://csrc.nist.gov/pubs/sp/800/61/r2/final
- NIST SP 800-61r3 - Incident Response Recommendations (CSF 2.0 alignment): https://csrc.nist.gov/pubs/sp/800/61/r3/final
- pip-audit (Python dependency vulnerability scanning): https://pypi.org/project/pip-audit/
- GitHub Dependabot (dependency alerts and updates): https://docs.github.com/en/code-security/dependabot
- OWASP Top 10 for LLM Applications 2025 (AI supply-chain and related risks): https://genai.owasp.org/llm-top-10/

Prof. Happy (SUTA Labs)
