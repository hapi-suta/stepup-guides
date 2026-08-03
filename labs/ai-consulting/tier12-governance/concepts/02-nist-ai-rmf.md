# Concepts 12.2: NIST AI Risk Management Framework

**Tier 12 - Responsible AI and governance.** Teaching reference. The NIST AI Risk Management Framework (AI RMF 1.0, document number NIST AI 100-1, released January 2023) is the most cited, vendor-neutral, and voluntary framework for managing AI risk (see: https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf). American federal agencies, many enterprises, and most serious AI consultants use it as the backbone. If you learn one framework cold, learn this one. This module is theory only.

**Who this is for:** consultants who need a shared language with clients and regulators. NIST AI RMF is that language in the United States and increasingly beyond.

**Why it matters:** clients rarely say "make us responsible." They say "align us to NIST AI RMF" or "our regulator expects an AI risk framework." When you can walk into that room and say "there are four functions - Govern, Map, Measure, Manage - here is where you have gaps," you are the consultant they hire.

---

## 1. What NIST AI RMF is and is not

- It **is** a voluntary, flexible, rights-preserving framework for identifying and managing AI risks across the lifecycle.
- It **is not** a certification (you cannot "get certified in NIST AI RMF" the way you can with ISO 42001) and it is not a law.
- It applies to any AI system: classical ML, generative AI, agents. NIST also publishes a **Generative AI Profile** (NIST AI 600-1, released July 2024) that adds GenAI-specific risks. NIST's official term for hallucination is **confabulation**; the profile's twelve risk categories also include data privacy, harmful bias and homogenization, dangerous/violent/hateful content, information integrity, information security, intellectual property, CBRN information, and more (see: https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf). Study that profile too - your assistant is generative.

The framework has two parts: the **core** (four functions) and **profiles** (how the core applies to a specific context or technology, like the Generative AI Profile).

---

## 2. The four core functions

Memorize these four. They are not sequential steps; they run continuously and overlap. Think of Govern as the ring around the other three.

### Govern
The culture, policies, roles, and accountability that make risk management happen at all. Govern is cross-cutting - it sits around Map, Measure, and Manage. It answers: who is accountable, what are our policies, what is our risk tolerance, how do we keep the AI inventory, how do we handle third parties, how do we train staff. Without Govern, the other three functions have no home.

### Map
Establish the context and identify risks. For each AI system: what is its purpose, who are the affected people, what are the intended benefits, what could go wrong, what are the categories of risk. Map is where you build the **AI system inventory** and run **impact assessments**. You cannot manage a risk you have not mapped.

### Measure
Analyze, assess, and track the risks you mapped, using quantitative and qualitative methods. This is metrics: accuracy, fairness metrics, groundedness, safety-violation rates, drift, red-team results. Measure produces the evidence. If Map says "this could be biased," Measure computes the disparate-impact ratio and tells you whether it is.

### Manage
Act on the measured risks: prioritize, respond, mitigate, and monitor. Allocate resources to the highest risks, implement controls, plan incident response, and decide when to accept, transfer, mitigate, or avoid a risk. Manage is where mitigation, monitoring, and decommissioning live.

A one-line mnemonic for a client: **Govern** sets the rules, **Map** finds the risks, **Measure** sizes them, **Manage** deals with them - continuously.

---

## 3. Key concepts you will be asked about

- **AI system inventory:** a living register of every AI system the organization runs, with owner, purpose, risk class, and status. You cannot govern what you have not inventoried. Shadow AI (staff using tools nobody approved) is why this matters.
- **Risk tolerance:** how much risk the organization is willing to accept, set by leadership. Governance decisions flow from it. A hospital's tolerance for a clinical model differs from a marketing team's tolerance for a copy generator.
- **Impact assessment:** a structured analysis of who could be affected and how, run during Map (detailed in Concepts 12.4).
- **Documentation:** the through-line of the whole framework. Every function produces artifacts. "If it is not written down, it did not happen" applies to auditors exactly as it does to DBAs.
- **Monitoring:** ongoing Measure + Manage after deployment. Drift, safety violations, cost, and user feedback are watched continuously.
- **Incident response:** a predefined process for when the AI causes harm, produces a biased output, or is attacked. You will build the template in the toolkit.

---

## 4. How the functions map to what you already built

You have been doing NIST AI RMF without the labels. Make the mapping explicit - clients love this:

| NIST function | What you already built in earlier tiers |
|---------------|-----------------------------------------|
| Govern | Policies, accountability, the toolkit in this tier |
| Map | Threat model (Tier 11), impact assessment, system inventory |
| Measure | Evaluation harness and metrics (Tier 7, 10), fairness metrics (this tier), red-team results (Tier 11) |
| Manage | Rollback and DR runbooks (Tier 10), incident response, monitoring dashboards (Tier 10) |

The point: governance is not a new pile of work bolted on at the end. It is the organizing frame for work you already know how to do. Your value is connecting the engineering evidence to the governance function that needs it.

---

## 5. Applying NIST AI RMF as a consultant

The engagement pattern:

1. **Govern:** confirm policies, roles, risk tolerance, and an AI inventory exist. If not, that is finding number one.
2. **Map:** inventory the AI systems, run an impact assessment on each, and classify risk.
3. **Measure:** pull or build the metrics that size each mapped risk (accuracy, fairness, groundedness, safety).
4. **Manage:** prioritize by risk, assign controls and owners, define incident response and monitoring.

A "governance gap audit" (one of this tier's SURVIVE scenarios) is exactly this pattern run against a system that skipped it: a deployed model with no inventory entry, no impact assessment, and no oversight plan. You find the gaps by walking the four functions.

---

## Key takeaways

- NIST AI RMF is voluntary, vendor-neutral, and the default risk language in the US. It is not a certification and not a law.
- Four functions: Govern (the ring), Map (find risks), Measure (size them), Manage (act). They run continuously, not once.
- Also study the NIST Generative AI Profile - your assistant is generative and has extra risks (confabulation, information integrity, data privacy).
- Core concepts: AI system inventory, risk tolerance, impact assessment, documentation, monitoring, incident response.
- You already produce most of the evidence in earlier tiers; governance is the frame that organizes it and assigns owners.

---

## References

- NIST AI Risk Management Framework (landing page) - https://www.nist.gov/itl/ai-risk-management-framework
- NIST AI RMF 1.0 (NIST AI 100-1) - four functions, cross-cutting Govern - https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf
- NIST AI 600-1, Generative AI Profile (July 2024) - GenAI risk categories incl. confabulation - https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf

Prof. Happy (SUTA Labs)
