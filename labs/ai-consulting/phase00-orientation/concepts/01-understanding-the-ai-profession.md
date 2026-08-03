# Concepts: Understanding the AI Profession

**Phase 0, Module 0.1** - the vocabulary you need before touching a keyboard.

This is a teaching reference. Read it once now, then come back to it whenever a term is fuzzy. Every definition here is grounded in authoritative sources (NIST, OWASP, and industry practice), cited at the bottom - not invented.

Why this matters for a consultant: your clients will use these words loosely and often wrongly. Part of your value is knowing the difference between "we need AI" and "we need a rules engine," or between "deploy a model" and "operate a model." Precision of language is precision of thinking.

---

## The big picture: nested circles, not synonyms

The most common beginner mistake is treating these as interchangeable. They are nested and overlapping.

```
Artificial Intelligence  (the whole field: making machines act "smart")
   > Machine Learning     (systems that learn patterns from data)
       > Deep Learning    (ML using many-layered neural networks)
           > Generative AI / LLMs  (deep learning that generates content)
```

Data science overlaps all of these but is its own discipline. "AI agents" sit on top of LLMs. The *-Ops and governance/security/consulting terms are about how you build, run, and control the above - not different kinds of model.

---

## Core technical terms

### Artificial intelligence (AI)
The broad field of building systems that perform tasks normally requiring human intelligence: reasoning, perception, language, decision-making. AI is the umbrella. Everything below is a subset.

### Machine learning (ML)
A subset of AI where the system **learns patterns from data** instead of being explicitly programmed with rules. You do not write "if temperature > X then alert"; you show the system many labelled examples and it learns the rule. If a plain set of hand-written rules solves the problem reliably, you do not need ML.

### Deep learning
A subset of ML that uses **neural networks with many layers**. It powers image recognition, speech, and modern language models. It needs more data and more compute than classical ML, and it is harder to explain.

### Data science
The discipline of extracting insight from data: profiling, statistics, visualization, experimentation, and modelling. It overlaps ML but leans toward **answering questions and informing decisions**, not only shipping predictive models. A data scientist may never deploy a model to production.

### Generative AI
AI that **creates new content** - text, images, code, audio - rather than only classifying or predicting a number. It is a use of deep learning.

### Large language models (LLMs)
Generative AI models trained on huge amounts of text that predict the next token (word-piece) and can therefore write, summarize, translate, answer, and reason over language. Examples: Claude, GPT, Gemini. They start from a pretrained **foundation model** and are adapted (instruction-tuned, sometimes fine-tuned) for tasks.

### AI agents
Systems that use an LLM as a "brain" plus **tools, memory, and a loop** to take multi-step actions toward a goal, not just answer a single prompt. An agent can call APIs, read files, and decide its next step. More capability means more risk - which is why agent safety is its own topic later.

---

## The "who does what" terms (roles and disciplines)

### Data engineering
Building the **pipelines and storage** that move, clean, and serve data (ETL/ELT, warehouses, lakes, streaming). AI is only as good as the data feeding it; this is the plumbing.

### ML engineering
Turning models into **reliable software**: packaging, serving, scaling, and integrating models into applications.

### MLOps (Machine Learning Operations)
The practice of managing the **end-to-end ML lifecycle** - development, deployment, monitoring, and maintenance - reliably and repeatably. MLOps measures **performance** with hard metrics like accuracy or F1 score. [ZenML, Red Hat]

### LLMOps (Large Language Model Operations)
A specialization of MLOps for **LLM-based applications** in production: deployment, monitoring, governance, and optimization. Key differences from MLOps: [Red Hat, UbiOps]
- **You measure behaviour, not just performance** - is the output helpful, relevant, safe? - rather than only accuracy.
- **You start from a foundation model** and fine-tune or prompt it, instead of training from scratch.
- **The dominant cost is inference** (GPU compute and per-token API fees), not training.
- New concerns appear: prompts, tokens, context windows, hallucinations, and provider outages.

Think of it this way: **LLMOps extends MLOps**. Everything in MLOps still applies; LLMs just add new failure modes to operate.

---

## The "keep it safe and legal" terms

### AI governance
The policies, accountability, and processes that keep an organization's AI **trustworthy and controlled** across its lifecycle. The reference standard is the **NIST AI Risk Management Framework**, whose core is four interconnected functions: [NIST]
- **Govern** - risk culture, accountability, and policies; who approves high-risk uses, how third-party models enter, how safety testing is resourced. It cuts across the other three.
- **Map** - understand the AI system in its real context and identify technical, social, and ethical impacts.
- **Measure** - assess risk with both quantitative and qualitative methods (likelihood and consequences).
- **Manage** - prioritize and respond to the risks you found, with mitigations.

These are **iterative, not one-time steps**, run throughout the system's life.

### AI security
Protecting AI systems from attack and misuse. Generative-AI systems have their own threat list - the **OWASP Top 10 for LLM Applications (2025)**: [OWASP]
1. Prompt injection
2. Sensitive information disclosure
3. Supply chain
4. Data and model poisoning
5. Improper output handling
6. Excessive agency
7. System prompt leakage
8. Vector and embedding weaknesses
9. Misinformation
10. Unbounded consumption

You will study and defend against each of these in Tier 11. For now, just know AI security is not the same as normal application security - it has extra, AI-specific attack surfaces.

Governance versus security in one line: **governance decides what is allowed and who is accountable; security stops attackers from breaking what you allowed.**

---

## The "turn it into a business" terms

### AI product management
Deciding **what to build and why**: user research, problem definition, requirements, pilots, metrics, and change management. It connects technology to real user and business value.

### AI consulting
Helping an organization **identify, govern, secure, build, and operate** AI that creates measurable value. It combines all of the above with executive communication and commercial skill. This is the target identity of this whole curriculum.

---

## One-line glossary (memorize these)

| Term | One line |
|---|---|
| Artificial intelligence | The whole field of making machines act intelligently. |
| Machine learning | Systems that learn patterns from data instead of hard-coded rules. |
| Deep learning | ML using many-layered neural networks. |
| Data science | Extracting insight from data to inform decisions. |
| Generative AI | AI that creates new content. |
| Large language model | Generative model trained on text that predicts the next token. |
| AI agent | An LLM plus tools, memory, and a loop that takes multi-step actions. |
| Data engineering | Pipelines and storage that feed AI. |
| ML engineering | Turning models into reliable software. |
| MLOps | Operating the ML lifecycle; measures performance. |
| LLMOps | MLOps extended for LLMs; measures behaviour, cost is inference. |
| AI governance | Policies and accountability that keep AI trustworthy (NIST: Govern/Map/Measure/Manage). |
| AI security | Defending AI from attack (OWASP LLM Top 10). |
| AI product management | Deciding what to build and why. |
| AI consulting | Helping orgs identify, govern, secure, build, and operate valuable AI. |

---

## Check yourself (Exit gate for this concept)

You can explain, without notes, to a non-technical person:
1. Why AI, ML, deep learning, and generative AI are nested, not the same thing.
2. The difference between MLOps and LLMOps in one sentence.
3. The difference between AI governance and AI security in one sentence.

If you can do all three, move on. If not, re-read and try again.

---

## Sources

- [NIST AI RMF: Govern, Map, Measure, Manage explained](https://blog.balancedsec.com/p/original-inside-the-nist-ai-risk) and [NIST AI RMF Core](https://airc.nist.gov/airmf-resources/airmf/5-sec-core/)
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [What is LLMOps - Red Hat](https://www.redhat.com/en/topics/ai/llmops)
- [MLOps vs LLMOps - ZenML](https://www.zenml.io/blog/mlops-vs-llmops) and [UbiOps](https://ubiops.com/llmops-vs-mlops/)
