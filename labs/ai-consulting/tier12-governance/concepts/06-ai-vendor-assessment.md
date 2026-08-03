# Concepts 12.6: AI Vendor Assessment

**Tier 12 - Responsible AI and governance.** Teaching reference. Most organizations will not train their own frontier models - they will buy AI from vendors (OpenAI, Anthropic, AWS Bedrock, Azure, Google, and countless SaaS wrappers). That means most of an organization's AI risk is actually vendor risk. Vendor assessment is how a consultant sizes and controls that risk before a contract is signed, and manages it after. This module is theory only. You will build the vendor questionnaire in the toolkit and score a real vendor in USE.

**Who this is for:** consultants who must protect a client from picking the wrong AI vendor - or from being unable to leave the right one.

**Why it matters:** the two questions clients underestimate most are "what does the vendor do with our data?" and "how do we get out if this goes wrong?" A consultant who asks these before signing, and who has an exit plan, is worth their fee many times over. Tie this back to Tier 6's Model and Vendor Selection Matrix - that chose a model on quality/cost/risk; this assessment goes deeper on the contractual and data-governance risk.

---

## 1. Why vendor risk is different

When you use a vendor's AI, you inherit their choices about your data, their availability, their security, and their roadmap - and you often have little control over any of it. Three properties make it dangerous:

- **Your data leaves your walls.** Prompts, documents, and personal data may flow to the vendor and possibly their subprocessors.
- **Their changes become your changes.** A model deprecation or a terms update can break or degrade your system overnight (this is a SURVIVE scenario in this tier).
- **Lock-in creeps up.** The more you build on one vendor's specific features, the harder and more expensive it is to leave.

Vendor assessment turns these from surprises into managed, contracted risks.

---

## 2. What to ask - the assessment areas

These are the fields from your spec. Each becomes a question (or a group) in the vendor questionnaire. For each, you want a documented answer and, ideally, contractual backing.

### Training-data statements
What data was the model trained on? Any known copyright, bias, or provenance concerns? A vendor who cannot say anything about training data is a risk.

### Customer-data usage
The critical one. Does the vendor use YOUR prompts and data to train or improve their models? Is there an opt-out or an enterprise tier that guarantees no training on your data? Get it in writing. The major enterprise AI platforms do make this commitment - for example, Microsoft states that Azure OpenAI prompts and completions are not used to train the underlying OpenAI or Microsoft models (see: https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy), and Anthropic's commercial API terms similarly commit not to train on your inputs and outputs by default. Verify the exact commitment for the specific tier and contract the client is on - defaults differ between consumer and enterprise products, and terms change.

### Retention
How long does the vendor keep your prompts, outputs, and logs? Can you require deletion? Long or vague retention is a privacy and breach-exposure risk.

### Data residency
Where (geographically) is your data processed and stored? Can you pin it to a region? Public-sector and regulated clients often must keep data in-country.

### Encryption
Is data encrypted in transit and at rest? Who holds the keys? Can you bring your own keys?

### Security certifications
Does the vendor hold recognized certifications? The common ones to ask for are **SOC 2 Type II** (AICPA's Trust Services Criteria audit), **ISO/IEC 27001** (information-security management), and - increasingly for AI vendors - **ISO/IEC 42001** (the AI management-system standard from Concepts 12.3; see: https://www.iso.org/standard/42001). Certifications are third-party evidence, not marketing claims - ask for the current report or certificate, and check the scope and date, not just that a badge exists.

### Availability
What uptime does the vendor commit to (SLA)? What is the incident history? What happens during an outage - and do you have a fallback (Tier 6's model-fallback path)?

### Subprocessors
Who else touches your data - the cloud the vendor runs on, downstream model providers, support tools? Each subprocessor is another trust boundary and another place data can leak.

### Intellectual property
Who owns the outputs? Does the vendor indemnify you if an output infringes someone's copyright? Can you use outputs commercially?

### Indemnification
Will the vendor stand behind you (financially) if their product causes you legal harm - an IP claim, a data breach? The scope and caps of indemnification matter a great deal for high-stakes use.

### Model updates
How does the vendor change or deprecate models? How much notice do you get? Can you pin a version? Silent model changes are a top cause of production surprises (drift, changed behaviour).

### Exit procedures
How do you leave? Can you export your data, embeddings, fine-tunes, and configurations? Is there a transition period? An assessment without an exit answer is incomplete.

### Export capability
Concretely, can you get YOUR data and artifacts out in a usable format? "You can export" means nothing if the format is unusable or the embeddings are locked to their model.

### Pricing risk
How is it priced (per token, per seat, per call), and how exposed are you to price increases or usage spikes? Model a worst-case cost. Pricing that can balloon is a business risk, not just a finance line.

---

## 3. Scoring and deciding

A questionnaire produces answers; a consultant produces a **recommendation**. A workable scoring approach:

- Score each area (for example 1-5, or red / amber / green) against the client's requirements and risk tolerance.
- Weight the areas by what matters for this client - a public-sector client weights data residency and no-training-on-our-data heavily; a startup may weight cost and speed.
- Flag any **dealbreakers** (for example "vendor trains on our data with no opt-out" for a client handling PII). A dealbreaker fails the vendor regardless of a high total score.
- Produce a short written recommendation: proceed, proceed with conditions, or reject - with reasons and required contract terms.

You will do exactly this in USE: score a real vendor and write the recommendation.

---

## 4. Vendor management does not end at signing

Assessment is the gate; **vendor management** is the ongoing discipline (a policy area from Concepts 12.5):

- **Monitor** the vendor for changes: model deprecations, terms updates, security incidents, pricing changes.
- **Re-assess** periodically and after any material change.
- **Keep the exit warm:** avoid single-vendor lock-in where you can (the multi-provider abstraction from Tier 6), and keep the export path tested, not theoretical.

The vendor-terms-change SURVIVE scenario in this tier exercises exactly this: a vendor changes its terms or deprecates a model version, and you must trigger the vendor-management and exit review. If you never assessed the exit path, that is the moment it hurts.

---

## Key takeaways

- Most of an organization's AI risk is vendor risk: your data leaves, their changes become yours, and lock-in creeps up.
- Assess every area: training-data statements, customer-data usage (do they train on your data?), retention, data residency, encryption, security certifications, availability, subprocessors, IP, indemnification, model updates, exit procedures, export capability, pricing risk.
- The two most-underestimated questions: "what do you do with our data?" and "how do we get out?"
- Turn the questionnaire into a weighted score plus a written recommendation, and honour dealbreakers regardless of total score.
- Assessment is the gate; vendor management (monitor, re-assess, keep the exit warm) is the ongoing job. A model change or terms change is when an untested exit path bites.

---

## References

- Microsoft - Azure OpenAI data privacy (prompts/completions not used to train base models) - https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy
- Anthropic - Commercial terms / privacy (no training on API inputs and outputs by default) - https://www.anthropic.com/legal/commercial-terms
- ISO/IEC 42001:2023 (AI management-system certification) - https://www.iso.org/standard/42001
- ISO/IEC 27001 (information-security certification) - https://www.iso.org/standard/27001
- AICPA SOC 2 (Trust Services Criteria) - https://www.aicpa-cima.com/topic/audit-assurance/audit-and-assurance-greater-than-soc-2

Prof. Happy (SUTA Labs)
